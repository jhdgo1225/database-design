#!/bin/sh
# library 정보시스템 쿼리 1~8번의 응답시간·리소스를 반정규화 전/후로 측정한다.
#
# 한 DB 안에서 다음 순서로 진행한다. (실제 컨테이너에서 실행, 사용자의 library DB 는 건드리지 않음)
#   1) before: public 스키마를 비우고 정규화 스키마(library/postgresql) + 데이터 적재 -> 쿼리 8개 x RUNS 회 측정
#   2) after : public 스키마를 비우고 반정규화 스키마(library/postgresql_denormalized) + 데이터 적재 -> 쿼리 8개 x RUNS 회 측정
# 쿼리는 각 information_system.sql 에서 읽으므로 SQL 파일과 항상 일치한다.
# EXPLAIN (ANALYZE, BUFFERS, MEMORY, WAL, SETTINGS, SUMMARY) 로 실행해 로그에 저장한다.
#
# 사용법: sh library/estimation_response_time_and_resource.sh [before|after|both]   (기본: both, 어느 디렉터리에서 실행해도 됨)
#   RUNS=30                 쿼리당 측정 횟수 (로그에 남는 횟수)
#   WARMUP=3                쿼리당 측정 전에 먼저 실행하고 버리는 횟수 (로그에 남기지 않음). 캐시 상태를 안정시키기 위함
#   OUT_DIR=library/results 로그 저장 위치(기본: 이 스크립트가 있는 폴더의 results). 기존 library_<before|after>_NN.log 는 덮어쓴다.
#   PARALLEL=0              측정 쿼리의 max_parallel_workers_per_gather 를 지정한다. 0 이면 병렬 실행을 끄고 직렬로 측정한다.
#                           비워 두면 서버 기본값(이 컨테이너는 2)을 쓴다. 지정하면 기존 로그를 덮어쓰지 않도록 OUT_DIR 기본값이
#                           results_parallel<값> 으로 바뀐다. 전/후가 서로 다른(직렬 / 병렬) 플랜을 고를 때 같은 조건으로 비교하려는 용도.
#   DB=library_bench        측정용 DB. 매 실행마다 만들고 끝나면 지우므로 이름은 _bench 로 끝나야 한다.
#   KEEP_DB=1               끝나고 측정용 DB 를 지우지 않음
#   BULK=1                  기본 샘플(insert_data.sql) 뒤에 대량 샘플(insert_data_bulk.sql)을 추가로 적재한다. 0 이면 기본 샘플만 사용.
#                           대량 샘플: 도서 5,000종 / 사본 약 12,500권 / 회원 10,000명 / 대출 약 18만 건 (정규화·반정규화 모두 같은 데이터)
#   CONTAINER, WORKSPACE    컨테이너 이름 / 컨테이너 안에서 repo 가 마운트된 경로 (docker-compose.yml 의 ./:/workspace:ro)
#
# 스키마를 적재한 직후 전체 ANALYZE 를 실행하므로 전/후 모두 모든 테이블에 통계가 있는 상태에서 측정한다.
# 반정규화 스키마는 btree_gist 확장과 트리거를 사용하므로 슈퍼유저(postgres)로 적재한다.
#
# 출력: ${OUT_DIR}/library_<before|after>_NN.log (NN = 쿼리 번호), library_<before|after>_meta.txt (테이블별 통계 상태, 서버 설정)
# 쿼리별 중앙값/사분위 범위/변동계수 요약은 sh library/summarize_estimation_result.sh [결과 폴더] 로 볼 수 있다.

set -u

CONTAINER="${CONTAINER:-db-optimization-postgres}"
DB="${DB:-library_bench}"
RUNS="${RUNS:-30}"
WARMUP="${WARMUP:-3}"
WORKSPACE="${WORKSPACE:-/workspace}"
KEEP_DB="${KEEP_DB:-0}"
BULK="${BULK:-1}"
MODE="${1:-both}"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT=$(basename "$SCRIPT_DIR")   # library (컨테이너 안에서는 $WORKSPACE/$PROJECT)
PARALLEL="${PARALLEL:-}"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/results${PARALLEL:+_parallel$PARALLEL}}"
EXPECTED_QUERIES=8

EXPLAIN_OPTS='EXPLAIN (
    ANALYZE,                         -- 실제 쿼리 실행 및 실제 실행 시간
    BUFFERS,                         -- 공유/로컬 버퍼의 hit, read, dirtied, written
    MEMORY,                          -- 계획 단계 메모리 사용량 (used / allocated)
    WAL,                             -- 생성된 WAL 레코드, 바이트 (읽기 전용이면 출력 없음)
    SETTINGS,                        -- 실행 계획에 영향을 준 비기본 설정
    SUMMARY                          -- 전체 Planning Time, Execution Time
)'

die() { echo "ERROR: $*" >&2; exit 1; }
psql_in() { docker exec -i "$CONTAINER" psql -X -q -v ON_ERROR_STOP=1 -U postgres "$@"; }
# 측정용: PARALLEL 이 지정되면 이 연결에만 max_parallel_workers_per_gather 를 적용한다. (적재·ANALYZE 에는 영향 없음)
psql_meas() {
  if [ -n "$PARALLEL" ]; then
    docker exec -i -e PGOPTIONS="-c max_parallel_workers_per_gather=$PARALLEL" "$CONTAINER" psql -X -q -v ON_ERROR_STOP=1 -U postgres "$@"
  else
    psql_in "$@"
  fi
}

case "$PARALLEL" in ''|*[!0-9]*) [ -z "$PARALLEL" ] || die "PARALLEL 은 0 이상의 정수여야 합니다: $PARALLEL" ;; esac
case "$MODE" in before|after|both) ;; *) die "사용법: sh $0 [before|after|both]" ;; esac
# 매번 DROP/CREATE 하는 DB 이므로 실제 DB(library, cinema 등)를 지우지 않도록 이름으로 막는다.
case "$DB" in *_bench) ;; *) die "DB 이름은 _bench 로 끝나야 합니다 (실제 DB 보호): $DB" ;; esac
docker exec "$CONTAINER" test -d "$WORKSPACE/$PROJECT/postgresql_denormalized" \
  || die "컨테이너 '$CONTAINER' 에서 $WORKSPACE/$PROJECT 를 찾을 수 없습니다. 컨테이너가 실행 중인지, repo 가 마운트되어 있는지 확인하세요."
mkdir -p "$OUT_DIR"

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

measure() {
  phase=$1
  case "$phase" in
    before) sub=postgresql ;;
    after)  sub=postgresql_denormalized ;;
  esac
  ddl=$sub/create_ddl.sql
  ins=$sub/insert_data.sql
  sqlfile=$sub/information_system.sql
  prefix="$OUT_DIR/library_$phase"
  qdir="$TMP_ROOT/$phase"
  mkdir -p "$qdir"

  # 전체 줄 주석을 뺀 뒤 ';' 단위로 쿼리를 나눠 q_01.sql ... 로 저장
  grep -v '^[[:space:]]*--' "$SCRIPT_DIR/$sqlfile" \
    | awk -v dir="$qdir" 'BEGIN { RS = ";" } NF { n++; f = sprintf("%s/q_%02d.sql", dir, n); print > f; close(f) }'
  nq=$(ls "$qdir"/q_*.sql 2>/dev/null | wc -l | tr -d ' ')
  [ "$nq" -eq "$EXPECTED_QUERIES" ] || die "$sqlfile 에서 쿼리 ${EXPECTED_QUERIES}개를 찾지 못했습니다 (찾은 수: $nq)."

  echo "==> [$phase] 스키마 구성 (같은 DB '$DB' 의 public 스키마를 비우고 다시 만듭니다)"
  psql_in -d postgres -At -c "SELECT 1 FROM pg_database WHERE datname = '$DB'" | grep -q 1 \
    || psql_in -d postgres -c "CREATE DATABASE \"$DB\"" || die "DB 생성 실패"
  psql_in -d "$DB" -c "SET client_min_messages = warning; DROP SCHEMA public CASCADE; CREATE SCHEMA public;" || die "스키마 초기화 실패"
  psql_in -d "$DB" -f "$WORKSPACE/$PROJECT/$ddl" || die "$ddl 적용 실패"
  psql_in -d "$DB" -f "$WORKSPACE/$PROJECT/$ins" || die "$ins 적용 실패"
  if [ "$BULK" = 1 ]; then
    psql_in -d "$DB" -f "$WORKSPACE/$PROJECT/$sub/insert_data_bulk.sql" || die "$sub/insert_data_bulk.sql 적용 실패"
  fi

  # 전/후가 같은 통계 상태에서 비교되도록 모든 테이블을 분석한다.
  # ANALYZE 는 기본 설정(statistics_target=100)에서 행 3만 개를 무작위로 뽑아 통계를 만들므로 실험을 다시 돌릴 때마다
  # 통계가 달라지고, 경계에 있는 쿼리는 실행 계획이 바뀐다. 표본(300 x target)이 가장 큰 테이블(약 18만 행)보다 크게 해서
  # 전체 행을 읽도록 고정하면 같은 데이터에서 항상 같은 통계가 나온다.
  psql_in -d "$DB" -c "SET default_statistics_target = 1000; ANALYZE" || die "ANALYZE 실패"

  {
    echo "date: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "phase: $phase"
    echo "schema: $PROJECT/$sub"
    echo "stats: analyze  runs: $RUNS  warmup: $WARMUP  db: $DB  bulk: $BULK  parallel: ${PARALLEL:-server-default}"
    psql_in -d "$DB" -At -c "SELECT version()"
    psql_meas -d "$DB" -At -c "SELECT name || '=' || setting FROM pg_settings WHERE name IN ('shared_buffers','work_mem','jit','max_parallel_workers_per_gather','TimeZone') ORDER BY 1"
    psql_in -d "$DB" -At -c "SELECT 'rows tbl_book_held_1=' || count(*) FROM tbl_book_held_1"
    psql_in -d "$DB" -At -c "SELECT 'rows tbl_loan_1=' || count(*) FROM tbl_loan_1"
    psql_in -d "$DB" -At -F '=' -c "SELECT relname, CASE WHEN last_analyze IS NOT NULL OR last_autoanalyze IS NOT NULL THEN 'analyzed' ELSE 'NO-STATS' END FROM pg_stat_user_tables ORDER BY 1"
  } > "${prefix}_meta.txt"

  for q in "$qdir"/q_*.sql; do
    n=$(basename "$q" .sql | sed 's/^q_//')
    log="${prefix}_${n}.log"
    : > "$log"
    # 워밍업: 같은 쿼리를 먼저 실행해 캐시를 안정시키고 결과는 버린다.
    w=1
    while [ "$w" -le "$WARMUP" ]; do
      { printf '%s\n' "$EXPLAIN_OPTS"; cat "$q"; echo ';'; } | psql_meas -d "$DB" > /dev/null \
        || die "[$phase] 쿼리 $n 워밍업 실패"
      w=$((w + 1))
    done
    i=1
    while [ "$i" -le "$RUNS" ]; do
      echo "===== RUN $i =====" >> "$log"
      { printf '%s\n' "$EXPLAIN_OPTS"; cat "$q"; echo ';'; } | psql_meas -d "$DB" >> "$log" \
        || die "[$phase] 쿼리 $n 실행 실패 (로그: $log)"
      i=$((i + 1))
    done
    echo "    쿼리 $n: 워밍업 ${WARMUP}회 + 측정 ${RUNS}회 -> $log"
  done
}

echo "컨테이너: $CONTAINER / 측정용 DB: $DB / 워밍업: ${WARMUP}회 + 측정: ${RUNS}회 / 병렬 워커 상한: ${PARALLEL:-서버 기본값} / 로그: $OUT_DIR (같은 이름의 기존 로그는 덮어씁니다)"
case "$MODE" in
  before) measure before ;;
  after)  measure after ;;
  both)   measure before; measure after ;;
esac

[ "$KEEP_DB" = 1 ] || psql_in -d postgres -c "DROP DATABASE IF EXISTS \"$DB\"" || die "측정용 DB 삭제 실패"
echo "==> 완료"
