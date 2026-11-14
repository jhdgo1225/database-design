#!/bin/sh
# estimation_response_time_and_resource.sh 가 남긴 로그에서 쿼리별 실행시간, 계획시간, 버퍼, 메모리를 요약한다.
# (cinema/summarize_estimation_result.sh 를 참고했다.)
#
# 비교표: 쿼리 세트(phase)를 나란히 놓고 정규화(before) 대비 변화율을 괄호에 보여준다.
#   before 정규화 / a23 후보 2·3 / a1 후보 1 / a123 후보 1·2·3을 합친 것
#   실행시간, 계획시간, 실행 버퍼(hit + read), 그 중 read, 계획 버퍼 hit, 계획 메모리, 노드 메모리, 디스크
# 상세표: phase 마다 쿼리별 수치를 한 줄씩 보여준다.
#   시간표: Execution Time(ms)의 중앙값, 사분위 범위(IQR: 1사분위~3사분위), 변동계수(CV = 표준편차/평균), 최소~최대, 측정 횟수
#           bicycle_<phase>_NN_time.log (TIMING OFF) 에서 읽는다. CV 가 10% 를 넘으면 이상치가 섞여 변동이 크다는 표시(*)를 붙인다.
#           평균 대신 중앙값을 쓰는 이유: 컨테이너 일시 지연 같은 이상치 한 번에 평균이 크게 흔들리기 때문이다.
#   자원표: bicycle_<phase>_NN.log (BUFFERS, MEMORY 를 켠 자원 측정) 에서 읽고, 측정 횟수 사이의 중앙값을 쓴다.
#     shared hit / read   최상위 노드의 공유 버퍼 블록 수(1블록 = 8kB). hit 는 shared_buffers 에서 찾은 것, read 는 디스크(OS 캐시)에서 읽은 것
#     temp 읽기/쓰기      최상위 노드의 임시 파일 블록 수. work_mem 을 넘겨서 정렬·해시가 디스크를 썼다는 뜻이다.
#     계획 메모리         EXPLAIN (MEMORY) 의 Planning 메모리 used / allocated (kB)
#     노드 메모리         실행 노드의 Memory Usage(해시, 집계)와 Sort 의 Memory 를 모두 더한 값 (kB). 노드가 동시에 쓰는 양의 상한에 가깝다.
#     디스크              Sort 의 Disk, 집계의 Disk Usage 를 더한 값 (kB)
#     계획 버퍼 hit       계획을 세우는 동안 읽은 카탈로그·통계 블록 수 (Planning 의 Buffers)
#     JIT                 JIT 컴파일에 쓴 시간(ms). JIT 가 켜지지 않은 쿼리는 0
#     워커 / 반환 행 수   Gather 노드마다 실제로 띄운 병렬 워커 수의 합 / 최상위 노드가 돌려준 행 수
#     (읽기 전용이라 shared dirtied/written, WAL 은 나오지 않고, track_io_timing 이 꺼져 있어 I/O 시간도 없다.)
#
# 사용법: sh bicycle_rental/summarize_estimation_result.sh [결과 폴더]   (기본: 이 스크립트가 있는 폴더의 results_bulk_interleaved_parallel0)
#   SKIP=0   각 시간 로그에서 앞쪽 N회를 제외한다.
#   v1.2.1 의 results_parallel0, results_parallel2 처럼 bicycle_NN.log 하나뿐인 폴더도 읽는다. (상세표만)

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DIR="${1:-$SCRIPT_DIR/results_bulk_interleaved_parallel0}"
SKIP="${SKIP:-0}"

[ -d "$DIR" ] || { echo "ERROR: 결과 폴더가 없습니다: $DIR" >&2; exit 1; }
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

# 시간 로그 -> "중앙값 Q1 Q3 최소 최대 CV(%) 측정횟수 계획시간중앙값"
time_stat() {
  awk -v skip="$SKIP" '
    function sortarr(a, n,    i, j, t) {
      for (i = 2; i <= n; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t }
    }
    function pct(a, n, p,    pos, lo, fr) {
      pos = (n - 1) * p + 1; lo = int(pos); fr = pos - lo
      return (lo >= n) ? a[n] : a[lo] + (a[lo + 1] - a[lo]) * fr
    }
    /^===== RUN/ { run++; next }
    /Planning Time:/ { if (run > skip) { np++; p[np] = $3 } }
    /Execution Time:/ { if (run > skip) { nt++; t[nt] = $3 } }
    END {
      if (nt == 0) { print "0 0 0 0 0 0 0 0"; exit }
      for (i = 1; i <= nt; i++) { s += t[i]; ss += t[i] * t[i] }
      mean = s / nt
      var = (nt > 1) ? (ss - nt * mean * mean) / (nt - 1) : 0
      if (var < 0) var = 0
      cv = (mean > 0) ? sqrt(var) / mean * 100 : 0
      sortarr(t, nt); sortarr(p, np)
      printf "%.3f %.3f %.3f %.3f %.3f %.1f %d %.3f\n", pct(t, nt, 0.5), pct(t, nt, 0.25), pct(t, nt, 0.75), t[1], t[nt], cv, nt, (np > 0 ? pct(p, np, 0.5) : 0)
    }' "$1"
}

# 자원 로그 -> "hit read temp읽기 temp쓰기 계획메모리used 계획메모리allocated 노드메모리 디스크 최상위노드(공백은 _)" (측정 횟수 사이의 중앙값)
res_stat() {
  awk '
    function sortarr(a, n,    i, j, t) {
      for (i = 2; i <= n; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t }
    }
    function med(name,    i, n, a) {
      n = nr
      for (i = 1; i <= n; i++) a[i] = v[name, i]
      sortarr(a, n)
      return (n % 2) ? a[(n + 1) / 2] : (a[n / 2] + a[n / 2 + 1]) / 2
    }
    function flush() {
      if (!run) return
      nr++
      v["hit", nr] = hit; v["rd", nr] = rd; v["tr", nr] = tr; v["tw", nr] = tw
      v["mu", nr] = mu; v["ma", nr] = ma; v["nm", nr] = nm; v["dk", nr] = dk
      v["ph", nr] = ph; v["jit", nr] = jit; v["wk", nr] = wk; v["rw", nr] = rw
      if (nr == 1) top1 = top
    }
    /^===== RUN/ {
      flush(); run++
      hit = rd = tr = tw = mu = ma = nm = dk = ph = jit = wk = rw = 0; gotbuf = 0; inplan = 0; gotsep = 0; top = ""
      next
    }
    /^-----+/ && !gotsep {
      gotsep = 1; getline; top = $0
      # 최상위 노드가 돌려준 행 수 (actual time=a..b rows=N)
      if (match(top, /actual time=[0-9.]+\.\.[0-9.]+ rows=[0-9]+/)) { s = substr(top, RSTART, RLENGTH); sub(/.*rows=/, "", s); rw = s + 0 }
      sub(/^ +/, "", top); sub(/  \(cost.*/, "", top); sub(/ +$/, "", top); gsub(/ /, "_", top); next
    }
    /^ *Planning:/ { inplan = 1; next }
    /^ *Buffers: shared/ && inplan { if (match($0, /hit=[0-9]+/)) ph = substr($0, RSTART + 4, RLENGTH - 4) + 0; next }
    /Timing: Generation/ { if (match($0, /Total [0-9.]+ ms/)) jit = substr($0, RSTART + 6, RLENGTH - 9) + 0; next }
    /Workers Launched:/ { if (match($0, /Launched: [0-9]+/)) wk += substr($0, RSTART + 10, RLENGTH - 10); next }
    /^ *Buffers: shared/ && !inplan && !gotbuf {
      gotbuf = 1; seg = ""
      for (i = 1; i <= NF; i++) {
        f = $i; gsub(/,/, "", f)
        if (f == "shared" || f == "temp" || f == "local") { seg = f; continue }
        if (seg == "shared" && f ~ /^hit=/)  { split(f, kv, "="); hit = kv[2] }
        if (seg == "shared" && f ~ /^read=/) { split(f, kv, "="); rd  = kv[2] }
        if (seg == "temp"   && f ~ /^read=/)    { split(f, kv, "="); tr = kv[2] }
        if (seg == "temp"   && f ~ /^written=/) { split(f, kv, "="); tw = kv[2] }
      }
      next
    }
    /^ *Memory: used=/ { if (match($0, /used=[0-9]+/)) mu = substr($0, RSTART + 5, RLENGTH - 5) + 0; if (match($0, /allocated=[0-9]+/)) ma = substr($0, RSTART + 10, RLENGTH - 10) + 0; next }
    {
      line = $0
      while (match(line, /Memory Usage: [0-9]+kB/)) { s = substr(line, RSTART, RLENGTH); sub(/Memory Usage: /, "", s); sub(/kB/, "", s); nm += s; line = substr(line, RSTART + RLENGTH) }
      line = $0
      # Incremental Sort 는 "Average Memory: N  Peak Memory: M" 을 함께 찍는다. 이때는 Peak 를 쓴다.
      if (match(line, /Peak Memory: [0-9]+kB/)) { s = substr(line, RSTART, RLENGTH); sub(/Peak Memory: /, "", s); sub(/kB/, "", s); nm += s }
      else while (match(line, /Sort Method: [a-zA-Z -]+Memory: [0-9]+kB/)) { s = substr(line, RSTART, RLENGTH); sub(/.*Memory: /, "", s); sub(/kB/, "", s); nm += s; line = substr(line, RSTART + RLENGTH) }
      line = $0
      while (match(line, /(Disk|Disk Usage): [0-9]+kB/)) { s = substr(line, RSTART, RLENGTH); sub(/.*: /, "", s); sub(/kB/, "", s); dk += s; line = substr(line, RSTART + RLENGTH) }
    }
    END {
      flush()
      if (nr == 0) { print "0 0 0 0 0 0 0 0 0 0 0 0 -"; exit }
      printf "%.0f %.0f %.0f %.0f %.0f %.0f %.0f %.0f %.0f %.1f %.0f %.0f %s\n", med("hit"), med("rd"), med("tr"), med("tw"), med("mu"), med("ma"), med("nm"), med("dk"), med("ph"), med("jit"), med("wk"), med("rw"), top1
    }' "$1"
}

# phase 이름 -> 설명
phase_label() {
  case "$1" in
    before) echo "정규화" ;;
    a23)    echo "후보 2·3" ;;
    a1)     echo "후보 1" ;;
    a123)   echo "후보 1·2·3" ;;
    *)      echo "$1" ;;
  esac
}

# 상세표. $1=로그 이름 접두사 (예: bicycle_before_ 또는 bicycle_) $2=쿼리 번호 목록
report_detail() {
  pfx=$1; qs=$2
  echo "[실행시간] 단위 ms. 중앙값 [IQR] CV(변동계수) (측정 횟수)"
  printf '%-4s | %-44s | %-17s | %s\n' "쿼리" "실행시간 중앙값 [Q1 ~ Q3] CV (n)" "최소 ~ 최대" "계획시간 중앙값"
  printf '%s\n' "-----+----------------------------------------------+-------------------+----------------"
  for n in $qs; do
    l="$DIR/${pfx}${n}.log"
    tl="$DIR/${pfx}${n}_time.log"; [ -f "$tl" ] || tl=$l
    time_stat "$tl" | awk -v n="$n" '{
      star = ($6 > 10) ? "*" : " "
      printf "%-4s | %9.3f [%8.3f ~ %8.3f] %4.1f%%%s (%d) | %7.1f ~ %-7.1f | %.3f\n", n, $1, $2, $3, $6, star, $7, $4, $5, $8
    }'
  done
  echo
  echo "[버퍼와 메모리] 버퍼는 블록 수(1블록 = 8kB), 메모리는 kB. 측정 횟수 사이의 중앙값"
  printf '%-4s | %9s | %7s | %-13s | %-14s | %9s | %7s | %s\n' "쿼리" "shared hit" "read" "temp 읽기/쓰기" "계획 메모리 u/a" "노드 메모리" "디스크" "최상위 노드"
  printf '%s\n' "-----+------------+---------+---------------+----------------+-----------+---------+--------------"
  for n in $qs; do
    res_stat "$DIR/${pfx}${n}.log" | awk -v n="$n" '{
      printf "%-4s | %10d | %7d | %6d/%-6d | %6d/%-7d | %9d | %7d | %s\n", n, $1, $2, $3, $4, $5, $6, $7, $8, $13
    }'
  done
  echo
  echo "[그 밖의 항목] 계획 버퍼는 블록 수, JIT 는 컴파일 시간(ms), 워커는 Gather 노드마다 띄운 병렬 워커 수의 합"
  printf '%-4s | %10s | %9s | %6s | %s\n' "쿼리" "계획 버퍼 hit" "JIT (ms)" "워커" "반환 행 수"
  printf '%s\n' "-----+------------+-----------+--------+-----------"
  for n in $qs; do
    res_stat "$DIR/${pfx}${n}.log" | awk -v n="$n" '{
      printf "%-4s | %10d | %9.1f | %6d | %d\n", n, $9, $10, $11, $12
    }'
  done
}

# 비교표. $1=제목 $2=종류(t: 시간 통계, r: 자원 통계) $3=필드 번호 (1+2 처럼 쓰면 합) $4=소수 자릿수
pivot() {
  for n in $QUERIES; do
    for p in $FOUND; do
      v=$(awk -v f="$3" '{ k = split(f, a, "+"); t = 0; for (i = 1; i <= k; i++) t += $(a[i]); print t }' "$TMP_ROOT/${p}_${n}.$2")
      echo "$n $p $v"
    done
  done | awk -v title="$1" -v dec="$4" -v phases="$FOUND" -v labels="$LABELS" '
    BEGIN { np = split(phases, ph, " "); split(labels, lb, ",") }
    { if (!($1 in seen)) { seen[$1] = 1; qs[++nq] = $1 } val[$1, $2] = $3 }
    END {
      printf "[%s]\n", title
      printf "%-4s", "쿼리"
      for (j = 1; j <= np; j++) printf " | %-24s", lb[j]
      printf "\n----"
      for (j = 1; j <= np; j++) printf "-+-------------------------"
      printf "\n"
      for (i = 1; i <= nq + 1; i++) {
        if (i <= nq) { q = qs[i]; printf "%-4s", q } else { q = "합"; printf "%-4s", "합" }
        for (j = 1; j <= np; j++) {
          if (i <= nq) v = val[q, ph[j]]; else { v = 0; for (k = 1; k <= nq; k++) v += val[qs[k], ph[j]] }
          if (j == 1) { base = v; cell = sprintf("%.*f", dec, v) }
          else if (base > 0) cell = sprintf("%.*f (%+.1f%%)", dec, v, (v - base) / base * 100)
          else cell = sprintf("%.*f (-)", dec, v)
          printf " | %-24s", cell
        }
        printf "\n"
      }
      printf "\n"
    }'
}

echo "결과 폴더: $DIR"

if ls "$DIR"/bicycle_before_[0-9][0-9].log > /dev/null 2>&1; then
  FOUND=""; LABELS=""
  for p in before a23 a1 a123; do
    if ls "$DIR"/bicycle_${p}_[0-9][0-9].log > /dev/null 2>&1; then
      FOUND="$FOUND $p"; LABELS="$LABELS,$(phase_label "$p")"
    fi
  done
  FOUND=$(echo $FOUND); LABELS=${LABELS#,}
  QUERIES=$(ls "$DIR"/bicycle_before_[0-9][0-9].log | sed 's/.*_\([0-9][0-9]\)\.log/\1/')
  for f in before after; do
    [ -f "$DIR/bicycle_${f}_meta.txt" ] && { echo "[$f]"; grep -E '^(date|stats|PostgreSQL|shared_buffers|work_mem|jit|max_parallel|rows tblrentT1|rows tblrpmoS1|rows tblbcmoS1|rows tblrpwdS1|rows tblmbrgS1|rent_period|size_)' "$DIR/bicycle_${f}_meta.txt" | sed 's/^/  /'; }
  done
  echo
  for p in $FOUND; do
    for n in $QUERIES; do
      tl="$DIR/bicycle_${p}_${n}_time.log"; [ -f "$tl" ] || tl="$DIR/bicycle_${p}_${n}.log"
      time_stat "$tl" > "$TMP_ROOT/${p}_${n}.t"
      res_stat "$DIR/bicycle_${p}_${n}.log" > "$TMP_ROOT/${p}_${n}.r"
    done
  done
  pivot "실행시간 중앙값, ms" t 1 3
  pivot "계획시간 중앙값, ms" t 8 3
  pivot "실행 버퍼 shared hit + read, 블록" r 1+2 0
  pivot "그 중 shared read(shared_buffers 에 없어 OS 캐시에서 읽음), 블록" r 2 0
  pivot "계획 버퍼 shared hit, 블록" r 9 0
  pivot "계획 메모리 used, kB" r 5 0
  pivot "노드 메모리 합, kB" r 7 0
  pivot "디스크(정렬·집계가 work_mem 을 넘어 쓴 양), kB" r 8 0
  for p in $FOUND; do
    echo "=================== $p: $(phase_label "$p") ==================="
    report_detail "bicycle_${p}_" "$QUERIES"
    echo
  done
else
  ls "$DIR"/bicycle_[0-9][0-9].log > /dev/null 2>&1 \
    || { echo "ERROR: $DIR 에 bicycle_<phase>_NN.log 도 bicycle_NN.log 도 없습니다." >&2; exit 1; }
  [ -f "$DIR/bicycle_meta.txt" ] && grep -E '^(date|stats|PostgreSQL|shared_buffers|work_mem|jit|max_parallel|rows tblrentT1|rent_period|size_total)' "$DIR/bicycle_meta.txt" | sed 's/^/  /'
  echo
  report_detail "bicycle_" "$(ls "$DIR"/bicycle_[0-9][0-9].log | sed 's/.*bicycle_\([0-9][0-9]\)\.log/\1/')"
fi
echo
echo "* 시간은 노드별 타이머와 버퍼·메모리 집계를 끈 측정(_time.log), 버퍼·메모리는 전체 옵션을 켠 측정(NN.log)에서 읽는다."
echo "* 노드 메모리는 해시·집계의 Memory Usage 와 정렬의 Memory 를 모두 더한 값이라 노드가 동시에 쓴 양의 상한에 가깝다. 병렬 실행이면 워커 몫도 더해진다."
echo "* IQR/CV 는 한 번의 실험 안에서의 변동만 반영한다. 호스트 상태에 따른 실험 간 차이는 같은 조건으로 다시 측정해 확인한다."
