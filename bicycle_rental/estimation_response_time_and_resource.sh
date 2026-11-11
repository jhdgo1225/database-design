#!/bin/sh
# bicycle_rental 정보시스템 쿼리 1~7번의 실행시간·메모리·버퍼 사용량을 측정한다.
# (cinema/estimation_response_time_and_resource.sh 를 참고했다. cinema 는 정규화/반정규화 DB 두 개를 번갈아 재지만,
#  bicycle_rental 은 아직 스키마가 하나라서 측정용 DB 하나만 쓴다.)
#
# 측정용 DB 를 따로 만들어 쓰므로 사용자의 bicycle_rental DB 는 건드리지 않는다. (실제 컨테이너에서 실행)
#   setup  : 측정용 DB(bicycle_rental_bench)를 만들고 DDL -> 기존 샘플 -> 날짜 이동 -> 대량 샘플 순서로 적재한 뒤 VACUUM (ANALYZE)
#            이미 같은 조건(BULK)으로 준비된 DB 는 건너뛴다. 적재는 한 번만 하고 측정은 여러 번 반복할 수 있다.
#   measure: 쿼리마다 자원 측정과 시간 측정을 차례로 한다. 각 측정 앞에 WARMUP회 워밍업(로그에 남기지 않음)
#              자원 측정: EXPLAIN (ANALYZE, BUFFERS, MEMORY, WAL, SETTINGS, SUMMARY) 를 RES_RUNS회  -> bicycle_NN.log
#              시간 측정: EXPLAIN (ANALYZE, TIMING OFF, BUFFERS OFF, MEMORY OFF, SUMMARY ON) 을 RUNS회 -> bicycle_NN_time.log
#   drop   : 측정용 DB 를 지운다.
#
# 시간과 자원을 따로 측정하는 이유: EXPLAIN ANALYZE 는 노드마다 시간을 재고 BUFFERS·MEMORY 를 모으는 비용이 실행 시간에 포함된다.
# 그래서 버퍼·메모리·플랜은 전체 옵션으로 몇 번만 보고, 시간은 노드별 타이머와 버퍼·메모리 집계를 끄고 여러 번 잰다.
# 쿼리는 postgresql/postgresql_information_system.sql 에서 읽으므로 SQL 파일과 항상 일치한다.
#
# 사용법: sh bicycle_rental/estimation_response_time_and_resource.sh [setup|measure|all|drop]   (기본: all, 어느 디렉터리에서 실행해도 됨)
#   RUNS=30        쿼리당 시간 측정 횟수
#   RES_RUNS=3     쿼리당 자원 측정(전체 EXPLAIN 옵션) 횟수. 버퍼·메모리·플랜은 반복해도 같아서 적게 돌린다.
#   WARMUP=3       각 측정 전에 먼저 실행하고 버리는 횟수. 캐시 상태를 안정시키기 위함
#   BULK=1         기본 샘플 뒤에 대량 샘플(postgresql_insert_data_bulk.sql)을 추가로 적재한다. 0 이면 기본 샘플(대여 50건)만 사용.
#   REBUILD=1      이미 준비된 DB 도 지우고 다시 적재한다. (데이터 생성기나 스키마를 바꾼 뒤에 사용)
#   PARALLEL=0     측정 쿼리의 max_parallel_workers_per_gather 를 지정한다. 0 이면 병렬 실행을 끄고 직렬로 측정한다.
#                  비워 두면 서버 기본값(이 컨테이너는 2)을 쓴다.
#   OUT_DIR        로그 저장 위치. 기본값: BULK=1 이면 bicycle_rental/results, BULK=0 이면 results_sample 이고,
#                  PARALLEL 을 지정하면 뒤에 _parallel<값> 이 붙는다. 같은 이름의 기존 로그는 덮어쓴다.
#   DB_NAME        측정용 DB 이름. 실제 DB 를 지우지 않도록 이름이 _bench 로 끝나야 한다.
#   CONTAINER, WORKSPACE   컨테이너 이름 / 컨테이너 안에서 repo 가 마운트된 경로 (docker-compose.yml 의 ./:/workspace:ro)
#
# 스키마를 적재한 직후 VACUUM (ANALYZE) 를 실행하므로 모든 테이블에 통계와 가시성 맵이 있는 상태에서 측정한다.
# 통계는 default_statistics_target=2000 (표본 60만 행)으로 만들어서 가장 큰 테이블(대여 약 33만 행) 전체를 읽는다.
# 대량 샘플은 CURRENT_DATE 기준으로 만들어지지만, 정보시스템 쿼리 1~7번은 CURRENT_DATE 를 쓰지 않아서 적재한 날짜와 상관없이 같은 행을 읽는다.
#
# 출력: ${OUT_DIR}/bicycle_NN.log (자원 측정), bicycle_NN_time.log (시간 측정) (NN = 쿼리 번호), bicycle_meta.txt (테이블별 행 수, 서버 설정)
# 쿼리별 요약은 sh bicycle_rental/summarize_estimation_result.sh [결과 폴더] 로 볼 수 있다.

set -u

CONTAINER="${CONTAINER:-db-optimization-postgres}"
DB_NAME="${DB_NAME:-bicycle_rental_bench}"
RUNS="${RUNS:-30}"
RES_RUNS="${RES_RUNS:-3}"
WARMUP="${WARMUP:-3}"
WORKSPACE="${WORKSPACE:-/workspace}"
BULK="${BULK:-1}"
REBUILD="${REBUILD:-0}"
MODE="${1:-all}"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT=$(basename "$SCRIPT_DIR")   # bicycle_rental (컨테이너 안에서는 $WORKSPACE/$PROJECT)
PARALLEL="${PARALLEL:-}"
if [ "$BULK" = 1 ]; then RESULT_NAME=results; else RESULT_NAME=results_sample; fi
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/$RESULT_NAME${PARALLEL:+_parallel$PARALLEL}}"
EXPECTED_QUERIES=7
READY_MARK="bench-ready bulk=$BULK stats=2000 vacuumed"

DDL=postgresql/postgresql_create_ddl.sql
INS=postgresql/postgresql_insert_data.sql
SHIFT=migration/shift_dates_to_current.sql
BULK_SQL=postgresql/postgresql_insert_data_bulk.sql
SQLFILE=postgresql/postgresql_information_system.sql

EXPLAIN_OPTS='EXPLAIN (
    ANALYZE,                         -- 실제 쿼리 실행 및 실제 실행 시간
    BUFFERS,                         -- 공유/로컬 버퍼의 hit, read, dirtied, written
    MEMORY,                          -- 계획 단계 메모리 사용량 (used / allocated)
    WAL,                             -- 생성된 WAL 레코드, 바이트 (읽기 전용이면 출력 없음)
    SETTINGS,                        -- 실행 계획에 영향을 준 비기본 설정
    SUMMARY                          -- 전체 Planning Time, Execution Time
)'

# 시간 측정용: 노드별 타이머(TIMING)와 BUFFERS·MEMORY 집계를 끄고 전체 Execution Time 만 얻는다.
TIME_OPTS='EXPLAIN (ANALYZE, TIMING OFF, BUFFERS OFF, MEMORY OFF, SUMMARY ON)'

die() { echo "ERROR: $*" >&2; exit 1; }
# 적재 SQL 의 "IF EXISTS" 삭제 구문이 내는 NOTICE 로 출력이 어지러워지지 않도록 경고 이상만 표시한다.
psql_in() { docker exec -i -e PGOPTIONS="-c client_min_messages=warning" "$CONTAINER" psql -X -q -v ON_ERROR_STOP=1 -U postgres "$@"; }
# 측정용: PARALLEL 이 지정되면 이 연결에만 max_parallel_workers_per_gather 를 적용한다. (적재·ANALYZE 에는 영향 없음)
psql_meas() {
  if [ -n "$PARALLEL" ]; then
    docker exec -i -e PGOPTIONS="-c max_parallel_workers_per_gather=$PARALLEL" "$CONTAINER" psql -X -q -v ON_ERROR_STOP=1 -U postgres "$@"
  else
    psql_in "$@"
  fi
}

case "$PARALLEL" in ''|*[!0-9]*) [ -z "$PARALLEL" ] || die "PARALLEL 은 0 이상의 정수여야 합니다: $PARALLEL" ;; esac
case "$MODE" in setup|measure|all|drop) ;; *) die "사용법: sh $0 [setup|measure|all|drop]" ;; esac
# 지우고 다시 만들 수 있는 DB 이므로 실제 DB(bicycle_rental, cinema 등)를 지우지 않도록 이름으로 막는다.
case "$DB_NAME" in *_bench) ;; *) die "DB 이름은 _bench 로 끝나야 합니다 (실제 DB 보호): $DB_NAME" ;; esac
docker exec "$CONTAINER" test -d "$WORKSPACE/$PROJECT/postgresql" \
  || die "컨테이너 '$CONTAINER' 에서 $WORKSPACE/$PROJECT 를 찾을 수 없습니다. 컨테이너가 실행 중인지, repo 가 마운트되어 있는지 확인하세요."

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

setup_db() {
  mark=$(psql_in -d postgres -At -c "SELECT shobj_description(oid, 'pg_database') FROM pg_database WHERE datname = '$DB_NAME'")
  if [ "$REBUILD" != 1 ] && [ "$mark" = "$READY_MARK" ]; then
    echo "==> DB '$DB_NAME' 는 이미 준비되어 있어 건너뜁니다 ($READY_MARK). 다시 만들려면 REBUILD=1"
    return 0
  fi
  echo "==> DB '$DB_NAME' 를 새로 만들고 스키마·데이터를 적재합니다 (BULK=$BULK)"
  psql_in -d postgres -c "DROP DATABASE IF EXISTS \"$DB_NAME\"" || die "DB 삭제 실패: $DB_NAME"
  psql_in -d postgres -c "CREATE DATABASE \"$DB_NAME\"" || die "DB 생성 실패: $DB_NAME"
  psql_in -d "$DB_NAME" -f "$WORKSPACE/$PROJECT/$DDL" || die "$DDL 적용 실패"
  psql_in -d "$DB_NAME" -f "$WORKSPACE/$PROJECT/$INS" || die "$INS 적용 실패"
  # 기존 샘플의 날짜를 오늘 기준으로 옮긴 뒤 대량 샘플을 적재한다. (순서가 바뀌면 기존 샘플이 옮겨지지 않는다)
  psql_in -d "$DB_NAME" -f "$WORKSPACE/$PROJECT/$SHIFT" > /dev/null || die "$SHIFT 적용 실패"
  if [ "$BULK" = 1 ]; then
    psql_in -d "$DB_NAME" -f "$WORKSPACE/$PROJECT/$BULK_SQL" || die "$BULK_SQL 적용 실패"
  fi
  # ANALYZE 는 기본 설정(statistics_target=100)에서 행 3만 개를 무작위로 뽑아 통계를 만들므로 다시 돌릴 때마다 통계가 달라지고,
  # 경계에 있는 쿼리는 실행 계획이 바뀐다. 표본(300 x target)이 가장 큰 테이블(대여 약 33만 행)보다 크게 해서 전체 행을 읽도록 고정한다.
  # VACUUM 도 함께 실행해 가시성 맵을 채운다. 적재 직후에는 가시성 맵이 비어 있어 Index Only Scan 이 힙을 다시 읽을 수 있다.
  # (-c 를 둘로 나누는 이유: VACUUM 은 트랜잭션 블록 안에서 실행할 수 없고, 한 -c 에 여러 문장을 쓰면 하나의 트랜잭션이 된다.)
  psql_in -d "$DB_NAME" -c "SET default_statistics_target = 2000" -c "VACUUM (ANALYZE)" || die "VACUUM ANALYZE 실패"
  psql_in -d "$DB_NAME" -c "COMMENT ON DATABASE \"$DB_NAME\" IS '$READY_MARK'" || die "준비 표시 실패"
}

# 전체 줄 주석과 줄 끝 주석을 뺀 뒤 ';' 단위로 쿼리를 나눠 $TMP_ROOT/q_01.sql ... 로 저장
# (줄 끝 주석이 있으면 마지막 ';' 뒤의 주석이 쿼리 하나로 잘못 세어지므로 'sed' 로 먼저 지운다. 쿼리 문자열에는 '--' 가 없다.)
split_queries() {
  sed 's/--.*$//' "$SCRIPT_DIR/$SQLFILE" \
    | awk -v dir="$TMP_ROOT" 'BEGIN { RS = ";" } NF { n++; f = sprintf("%s/q_%02d.sql", dir, n); print > f; close(f) }'
  nq=$(ls "$TMP_ROOT"/q_*.sql 2>/dev/null | wc -l | tr -d ' ')
  [ "$nq" -eq "$EXPECTED_QUERIES" ] || die "$SQLFILE 에서 쿼리 ${EXPECTED_QUERIES}개를 찾지 못했습니다 (찾은 수: $nq)."
}

write_meta() {
  psql_in -d "$DB_NAME" -At -c "SELECT 1" > /dev/null || die "DB '$DB_NAME' 에 연결할 수 없습니다. 먼저 setup 을 실행하세요."
  [ "$(psql_in -d postgres -At -c "SELECT shobj_description(oid, 'pg_database') FROM pg_database WHERE datname = '$DB_NAME'")" = "$READY_MARK" ] \
    || die "DB '$DB_NAME' 가 BULK=$BULK 조건으로 준비되어 있지 않습니다. 먼저 setup (또는 REBUILD=1) 을 실행하세요."
  {
    echo "date: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "schema: $PROJECT/postgresql"
    echo "stats: analyze  runs: $RUNS  res_runs: $RES_RUNS  warmup: $WARMUP  db: $DB_NAME  bulk: $BULK  parallel: ${PARALLEL:-server-default}"
    psql_in -d "$DB_NAME" -At -c "SELECT version()"
    psql_meas -d "$DB_NAME" -At -c "SELECT name || '=' || setting FROM pg_settings WHERE name IN ('shared_buffers','work_mem','jit','max_parallel_workers_per_gather','TimeZone') ORDER BY 1"
    psql_in -d "$DB_NAME" -At -c "SELECT 'current_date=' || CURRENT_DATE"
    for t in tblmebrM1 tbltickD1 tblbyclM1 tblrtplM1 tblrackD1 tblrentT1 tblspclD1 tbldmlsD1 tblfavoT1; do
      psql_in -d "$DB_NAME" -At -c "SELECT 'rows $t=' || count(*) FROM $t"
    done
    psql_in -d "$DB_NAME" -At -c "SELECT 'rent_period=' || min(rentdate)::date || ' ~ ' || max(rentdate)::date FROM tblrentT1"
    psql_in -d "$DB_NAME" -At -c "SELECT 'size_total=' || pg_size_pretty(sum(pg_total_relation_size(c.oid))) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relkind = 'r'"
    psql_in -d "$DB_NAME" -At -c "SELECT 'size_rent=' || pg_size_pretty(pg_total_relation_size('tblrentT1'))"
    psql_in -d "$DB_NAME" -At -F '=' -c "SELECT relname, CASE WHEN last_analyze IS NOT NULL OR last_autoanalyze IS NOT NULL THEN 'analyzed' ELSE 'NO-STATS' END FROM pg_stat_user_tables ORDER BY 1"
  } > "$OUT_DIR/bicycle_meta.txt"
}

# 한 번 실행해 결과를 $3 (없으면 버림) 에 덧붙인다. $1=쿼리 번호 $2=옵션(EXPLAIN 문 앞부분)
run_once() {
  { printf '%s\n' "$2"; cat "$TMP_ROOT/q_$1.sql"; echo ';'; } | psql_meas -d "$DB_NAME" >> "${3:-/dev/null}" \
    || die "쿼리 $1 실행 실패"
}

# 한 쿼리를 한 가지 옵션($1)으로 측정한다. 워밍업 $WARMUP회 뒤에 $2회를 실행해 $4 에 남긴다. $3=쿼리 번호
measure_pass() {
  opts=$1; cnt=$2; q=$3; log=$4
  : > "$log"
  w=1
  while [ "$w" -le "$WARMUP" ]; do
    run_once "$q" "$opts"
    w=$((w + 1))
  done
  i=1
  while [ "$i" -le "$cnt" ]; do
    echo "===== RUN $i =====" >> "$log"
    run_once "$q" "$opts" "$log"
    i=$((i + 1))
  done
}

measure_all() {
  mkdir -p "$OUT_DIR"
  split_queries
  write_meta
  n=1
  while [ "$n" -le "$EXPECTED_QUERIES" ]; do
    q=$(printf '%02d' "$n")
    measure_pass "$EXPLAIN_OPTS" "$RES_RUNS" "$q" "$OUT_DIR/bicycle_$q.log"
    measure_pass "$TIME_OPTS" "$RUNS" "$q" "$OUT_DIR/bicycle_${q}_time.log"
    echo "    쿼리 $q: 자원 ${RES_RUNS}회 + 시간 ${RUNS}회 (각각 워밍업 ${WARMUP}회)"
    n=$((n + 1))
  done
}

echo "컨테이너: $CONTAINER / DB: $DB_NAME / 워밍업: ${WARMUP}회 / 자원 측정: ${RES_RUNS}회 / 시간 측정: ${RUNS}회 / 대량 샘플: $BULK / 병렬 워커 상한: ${PARALLEL:-서버 기본값}"
case "$MODE" in
  setup)   setup_db ;;
  measure) echo "로그: $OUT_DIR (같은 이름의 기존 로그는 덮어씁니다)"; measure_all ;;
  all)     setup_db; echo "로그: $OUT_DIR (같은 이름의 기존 로그는 덮어씁니다)"; measure_all ;;
  drop)    psql_in -d postgres -c "DROP DATABASE IF EXISTS \"$DB_NAME\"" || die "DB 삭제 실패: $DB_NAME" ;;
esac
echo "==> 완료"
