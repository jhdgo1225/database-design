#!/bin/sh
# estimation_response_time_and_resource.sh 가 남긴 로그에서 쿼리별 실행시간, 버퍼, 메모리를 요약한다.
# (cinema/summarize_estimation_result.sh 를 참고했다. 전/후 비교가 없어서 쿼리마다 한 줄씩 수치를 보여준다.)
#
# 시간표: Execution Time(ms)의 중앙값, 사분위 범위(IQR: 1사분위~3사분위), 변동계수(CV = 표준편차/평균), 최소~최대, 측정 횟수
#         bicycle_NN_time.log (TIMING OFF) 에서 읽는다. CV 가 10% 를 넘으면 이상치가 섞여 변동이 크다는 표시(*)를 붙인다.
#         평균 대신 중앙값을 쓰는 이유: 컨테이너 일시 지연 같은 이상치 한 번에 평균이 크게 흔들리기 때문이다.
# 자원표: bicycle_NN.log (BUFFERS, MEMORY 를 켠 자원 측정) 에서 읽고, 측정 횟수 사이의 중앙값을 쓴다.
#   shared hit / read   최상위 노드의 공유 버퍼 블록 수(1블록 = 8kB). hit 는 shared_buffers 에서 찾은 것, read 는 디스크(OS 캐시)에서 읽은 것
#   temp 읽기/쓰기      최상위 노드의 임시 파일 블록 수. work_mem 을 넘겨서 정렬·해시가 디스크를 썼다는 뜻이다.
#   계획 메모리         EXPLAIN (MEMORY) 의 Planning 메모리 used / allocated (kB)
#   노드 메모리         실행 노드의 Memory Usage(해시, 집계)와 Sort 의 Memory 를 모두 더한 값 (kB). 노드가 동시에 쓰는 양의 상한에 가깝다.
#   디스크              Sort 의 Disk, 집계의 Disk Usage 를 더한 값 (kB)
#
# 사용법: sh bicycle_rental/summarize_estimation_result.sh [결과 폴더]   (기본: 이 스크립트가 있는 폴더의 results)
#   SKIP=0   각 시간 로그에서 앞쪽 N회를 제외한다.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DIR="${1:-$SCRIPT_DIR/results}"
SKIP="${SKIP:-0}"

[ -d "$DIR" ] || { echo "ERROR: 결과 폴더가 없습니다: $DIR" >&2; exit 1; }
ls "$DIR"/bicycle_[0-9][0-9].log > /dev/null 2>&1 \
  || { echo "ERROR: $DIR 에 bicycle_NN.log 가 없습니다." >&2; exit 1; }

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
      if (nr == 1) top1 = top
    }
    /^===== RUN/ {
      flush(); run++
      hit = rd = tr = tw = mu = ma = nm = dk = 0; gotbuf = 0; inplan = 0; gotsep = 0; top = ""
      next
    }
    /^-----+/ && !gotsep { gotsep = 1; getline; top = $0; sub(/^ +/, "", top); sub(/  \(cost.*/, "", top); sub(/ +$/, "", top); gsub(/ /, "_", top); next }
    /^ *Planning:/ { inplan = 1; next }
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
    /^ *Memory: used=/ { if (match($0, /used=[0-9]+/)) mu = substr($0, RSTART + 5, RLENGTH - 5); if (match($0, /allocated=[0-9]+/)) ma = substr($0, RSTART + 10, RLENGTH - 10); next }
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
      if (nr == 0) { print "0 0 0 0 0 0 0 0 -"; exit }
      printf "%.0f %.0f %.0f %.0f %.0f %.0f %.0f %.0f %s\n", med("hit"), med("rd"), med("tr"), med("tw"), med("mu"), med("ma"), med("nm"), med("dk"), top1
    }' "$1"
}

echo "결과 폴더: $DIR"
[ -f "$DIR/bicycle_meta.txt" ] && grep -E '^(date|stats|PostgreSQL|shared_buffers|work_mem|jit|max_parallel|rows tblrentT1|rent_period|size_total)' "$DIR/bicycle_meta.txt" | sed 's/^/  /'
echo
echo "[실행시간] 단위 ms. 중앙값 [IQR] CV(변동계수) (측정 횟수)"
printf '%-4s | %-44s | %-17s | %s\n' "쿼리" "실행시간 중앙값 [Q1 ~ Q3] CV (n)" "최소 ~ 최대" "계획시간 중앙값"
printf '%s\n' "-----+----------------------------------------------+-------------------+----------------"
for l in "$DIR"/bicycle_[0-9][0-9].log; do
  n=$(basename "$l" .log | sed 's/^bicycle_//')
  tl="$DIR/bicycle_${n}_time.log"; [ -f "$tl" ] || tl=$l
  time_stat "$tl" | awk -v n="$n" '{
    star = ($6 > 10) ? "*" : " "
    printf "%-4s | %9.3f [%8.3f ~ %8.3f] %4.1f%%%s (%d) | %7.1f ~ %-7.1f | %.3f\n", n, $1, $2, $3, $6, star, $7, $4, $5, $8
  }'
done
echo
echo "[버퍼와 메모리] 버퍼는 블록 수(1블록 = 8kB), 메모리는 kB. 측정 횟수 사이의 중앙값"
printf '%-4s | %9s | %7s | %-13s | %-14s | %9s | %7s | %s\n' "쿼리" "shared hit" "read" "temp 읽기/쓰기" "계획 메모리 u/a" "노드 메모리" "디스크" "최상위 노드"
printf '%s\n' "-----+------------+---------+---------------+----------------+-----------+---------+--------------"
for l in "$DIR"/bicycle_[0-9][0-9].log; do
  n=$(basename "$l" .log | sed 's/^bicycle_//')
  res_stat "$l" | awk -v n="$n" '{
    printf "%-4s | %10d | %7d | %6d/%-6d | %6d/%-7d | %9d | %7d | %s\n", n, $1, $2, $3, $4, $5, $6, $7, $8, $9
  }'
done
echo
echo "* 시간은 노드별 타이머와 버퍼·메모리 집계를 끈 측정(_time.log), 버퍼·메모리는 전체 옵션을 켠 측정(NN.log)에서 읽는다."
echo "* 노드 메모리는 해시·집계의 Memory Usage 와 정렬의 Memory 를 모두 더한 값이라 노드가 동시에 쓴 양의 상한에 가깝다. 병렬 실행이면 워커 몫도 더해진다."
echo "* IQR/CV 는 한 번의 실험 안에서의 변동만 반영한다. 호스트 상태에 따른 실험 간 차이는 같은 조건으로 다시 측정해 확인한다."
