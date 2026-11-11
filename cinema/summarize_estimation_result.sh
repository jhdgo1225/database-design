#!/bin/sh
# estimation_response_time_and_resource.sh 가 남긴 로그에서 쿼리별 통계를 뽑아 반정규화 전/후를 비교한다.
#
# 쿼리마다 Execution Time(ms)의 중앙값, 사분위 범위(IQR: 1사분위~3사분위), 변동계수(CV = 표준편차/평균),
# 최상위 노드 기준 공유 버퍼 접근량(hit + read, 블록 수)의 중앙값을 구한다.
# 시간은 cinema_<before|after>_NN_time.log (TIMING OFF), 버퍼는 cinema_<before|after>_NN.log (BUFFERS 켠 자원 측정)에서 읽는다.
# _time.log 가 없는 이전 로그 폴더는 cinema_<before|after>_NN.log 한 파일에서 시간과 버퍼를 모두 읽는다.
# 평균 대신 중앙값을 쓰는 이유: 컨테이너 일시 지연 같은 이상치 한 번에 평균이 크게 흔들리기 때문이다.
#
# 판정은 전/후의 IQR 구간이 겹치는지로 하는 간단한 휴리스틱이다. (통계적 유의성 검정이 아님)
#   - 중앙값 변화가 3% 안쪽 : 차이 없음(3% 이내). 구간이 겹치지 않아도 차이로 보지 않는다.
#   - 구간이 겹치지 않음    : 개선 / 악화
#   - 구간이 겹침           : 차이 불분명 (측정 횟수를 늘리거나 전체 실험을 반복해 확인)
#   - CV 가 10% 를 넘음     : 이상치가 섞여 변동이 크다는 표시 (*). 중앙값은 이상치 영향이 작지만 IQR 과 함께 확인한다.
#
# 사용법: sh cinema/summarize_estimation_result.sh [결과 폴더]   (기본: 이 스크립트가 있는 폴더의 results_bulk_interleaved_parallel0)
#   SKIP=0   각 로그에서 앞쪽 N회를 제외한다. 워밍업 옵션이 없던 이전 로그를 분석할 때 쓴다.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DIR="${1:-$SCRIPT_DIR/results_bulk_interleaved_parallel0}"
SKIP="${SKIP:-0}"

[ -d "$DIR" ] || { echo "ERROR: 결과 폴더가 없습니다: $DIR" >&2; exit 1; }
ls "$DIR"/cinema_before_[0-9][0-9].log > /dev/null 2>&1 \
  || { echo "ERROR: $DIR 에 cinema_before_NN.log 가 없습니다." >&2; exit 1; }

# 시간 로그($1)와 자원 로그($2, 같은 파일이어도 됨) -> "중앙값 Q1 Q3 최소 최대 CV(%) 측정횟수 버퍼중앙값"
stat() {
  if [ "$1" = "$2" ]; then set -- "$1" "$2" one; else set -- "$1" "$2" two; fi
  awk -v skip="$SKIP" -v tf="$1" -v bf="$2" '
    function sortarr(a, n,    i, j, t) {
      for (i = 2; i <= n; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t }
    }
    function pct(a, n, p,    pos, lo, fr) {
      pos = (n - 1) * p + 1; lo = int(pos); fr = pos - lo
      return (lo >= n) ? a[n] : a[lo] + (a[lo + 1] - a[lo]) * fr
    }
    FNR == 1 { run = 0; got = 0 }
    /^===== RUN/ { run++; got = 0; next }
    /Execution Time:/ { if (FILENAME == tf && run > skip) { nt++; t[nt] = $3 } }
    /^ *Buffers: shared/ && !got {
      got = 1
      if (FILENAME == bf && (tf != bf || run > skip)) {
        b = 0
        # "shared hit=.. read=.., temp read=.. written=.." 에서 temp(임시 파일) 블록은 공유 버퍼가 아니므로 temp 앞까지만 더한다.
        for (i = 1; i <= NF; i++) {
          if ($i == "temp" || $i == "local") break
          if ($i ~ /^(hit|read)=/) { split($i, kv, "="); b += kv[2] }
        }
        nb++; buf[nb] = b
      }
    }
    END {
      if (nt == 0) { print "0 0 0 0 0 0 0 0"; exit }
      for (i = 1; i <= nt; i++) { s += t[i]; ss += t[i] * t[i] }
      mean = s / nt
      var = (nt > 1) ? (ss - nt * mean * mean) / (nt - 1) : 0
      if (var < 0) var = 0
      cv = (mean > 0) ? sqrt(var) / mean * 100 : 0
      sortarr(t, nt); sortarr(buf, nb)
      printf "%.3f %.3f %.3f %.3f %.3f %.1f %d %.0f\n", pct(t, nt, 0.5), pct(t, nt, 0.25), pct(t, nt, 0.75), t[1], t[nt], cv, nt, (nb > 0 ? pct(buf, nb, 0.5) : 0)
    }' $( [ "$3" = one ] && echo "$1" || echo "$1 $2" )
}

echo "결과 폴더: $DIR  (각 로그의 앞 ${SKIP}회 제외)"
echo
printf '%-4s | %-34s | %-34s | %-9s | %-12s | %s\n' "쿼리" "before 중앙값 [IQR] CV (n)" "after 중앙값 [IQR] CV (n)" "변화(%)" "버퍼 b→a" "판정"
printf '%s\n' "-----+------------------------------------+------------------------------------+-----------+--------------+---------------"

for b in "$DIR"/cinema_before_[0-9][0-9].log; do
  n=$(basename "$b" .log | sed 's/^cinema_before_//')
  a="$DIR/cinema_after_$n.log"
  [ -f "$a" ] || continue
  tb="$DIR/cinema_before_${n}_time.log"; ta="$DIR/cinema_after_${n}_time.log"
  [ -f "$tb" ] || tb=$b
  [ -f "$ta" ] || ta=$a
  sb=$(stat "$tb" "$b"); sa=$(stat "$ta" "$a")
  echo "$n $sb $sa" | awk '{
    n = $1
    bm = $2; bq1 = $3; bq3 = $4; bcv = $7; bn = $8; bbuf = $9
    am = $10; aq1 = $11; aq3 = $12; acv = $15; an = $16; abuf = $17
    chg = (bm > 0) ? (am - bm) / bm * 100 : 0
    if (chg > -3 && chg < 3) v = "차이 없음(3% 이내)"
    else if (aq3 < bq1) v = "개선"; else if (bq3 < aq1) v = "악화"; else v = "차이 불분명(구간 겹침)"
    if (bcv > 10 || acv > 10) v = v " *변동 큼"
    printf "%-4s | %8.3f [%7.3f~%7.3f] %4.1f%% (%d) | %8.3f [%7.3f~%7.3f] %4.1f%% (%d) | %+8.1f%% | %5d→%-6d | %s\n", n, bm, bq1, bq3, bcv, bn, am, aq1, aq3, acv, an, chg, bbuf, abuf, v
  }'
done

echo
echo "* 시간 단위는 ms, 변화(%)는 중앙값 기준 (음수가 빨라진 것). 버퍼는 최상위 노드의 shared hit+read 블록 수 중앙값."
echo "* IQR/CV 는 한 번의 실험 안에서의 변동만 반영한다. before 와 after 는 한 회마다 순서를 바꿔 같은 시간대에 측정하지만,"
echo "  한 번의 실험이라 호스트 상태에 따른 실험 간 차이는 반영되지 않는다. 변화가 3% 안팎인 쿼리는 방향이 같은지 실험을 반복해 확인하고,"
echo "  버퍼 접근량(실행 계획이 같으면 반복해도 동일)을 함께 보고 판단한다."
