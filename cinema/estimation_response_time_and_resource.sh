#!/bin/sh
# cinema 정보시스템 쿼리 1~9번의 응답시간·리소스를 정규화(before) / 반정규화(after) 스키마에서 측정한다.
#
# 독립된 DB 두 개를 미리 만들어 두고, 쿼리마다 두 DB 를 번갈아 측정한다. (실제 컨테이너에서 실행, 사용자의 cinema DB 는 건드리지 않음)
#   setup  : 정규화 DB(cinema_normalized_bench) / 반정규화 DB(cinema_denormalized_bench) 를 만들고 스키마 + 데이터 적재 + VACUUM (ANALYZE)
#            이미 같은 조건(BULK)으로 준비된 DB 는 건너뛴다. 적재는 한 번만 하고 측정은 여러 번 반복할 수 있다.
#   measure: 쿼리마다 자원 측정과 시간 측정을 차례로 하고, 두 측정 모두 한 회마다 정규화 -> 반정규화 순서를 번갈아 바꾼다.
#            (홀수 회: 정규화 먼저, 짝수 회: 반정규화 먼저. 각 측정 앞에 WARMUP회 x 두 DB 워밍업)
#              자원 측정: EXPLAIN (ANALYZE, BUFFERS, MEMORY, WAL, SETTINGS, SUMMARY) 를 RES_RUNS회  -> cinema_<before|after>_NN.log
#              시간 측정: EXPLAIN (ANALYZE, TIMING OFF, BUFFERS OFF, MEMORY OFF, SUMMARY ON) 을 RUNS회 -> cinema_<before|after>_NN_time.log
#   drop   : 두 측정용 DB 를 지운다.
#
# 처음에는 한 DB 에서 정규화를 모두 측정하고, 스키마를 지운 뒤 반정규화를 적재해 측정했다. 그 방식은 적재할 때마다 시간이 들었고,
# 7번 쿼리가 나중에 측정한 DB 에서만 다른 플랜(Heap Fetches 6121)을 타서 15~20% 느리게 나왔다. 적재 직후 가시성 맵이 비어 있었던 것으로 보인다.
# 그래서 DB 를 둘로 나눠 미리 VACUUM 해 두고, 두 DB 를 같은 시간대에 번갈아 측정하도록 바꿨다.
#
# 시간과 자원을 따로 측정하는 이유: EXPLAIN ANALYZE 는 노드마다 시간을 재고 BUFFERS·MEMORY 를 모으는 비용이 실행 시간에 포함된다.
# 이 비용은 계획의 노드 수에 따라 달라지므로 조인이 줄어든 반정규화 쪽이 계측 비용도 적어서 실제보다 빨라 보인다.
# 같은 DB 에서 옵션만 바꿔 비교했더니 4번 쿼리의 정규화 쪽 중앙값이 전체 옵션에서는 약 104 ms, TIMING OFF 에서는 약 64 ms 였고
# 전/후 변화율도 -9.2% 에서 -3.9% 로 달라졌다. (cinema/results_bulk_interleaved_parallel0 의 자원 로그와 시간 로그 기준) 그래서 버퍼·메모리·플랜은 전체 옵션으로 몇 번만 보고,
# 시간은 노드별 타이머와 버퍼·메모리 집계를 끄고 여러 번 잰다. 두 측정의 플랜 모양(노드 종류)이 같은지는 로그에서 확인한다.
# 쿼리는 각 information_system.sql 에서 읽으므로 SQL 파일과 항상 일치한다.
#
# 사용법: sh cinema/estimation_response_time_and_resource.sh [setup|measure|all|drop]   (기본: all, 어느 디렉터리에서 실행해도 됨)
#   RUNS=30                 쿼리당 시간 측정 횟수 (DB 마다 시간 로그에 남는 횟수)
#   RES_RUNS=3              쿼리당 자원 측정(전체 EXPLAIN 옵션) 횟수. 버퍼·메모리·플랜은 반복해도 같아서 적게 돌린다.
#   WARMUP=3                각 측정 전에 DB 마다 먼저 실행하고 버리는 횟수 (로그에 남기지 않음). 캐시 상태를 안정시키기 위함
#   BULK=1                  기본 샘플 뒤에 대량 샘플(insert_data_bulk.sql)을 추가로 적재한다. 0 이면 기본 샘플만 사용.
#                           대량 샘플: 영화 300편 / 상영관 30개 / 상영 약 13,700회 / 회원 20,000명 / 예매 약 31.5만 건 / 충전 6만 건 / 찜 약 6만 건
#                           (정규화·반정규화 모두 논리적으로 같은 데이터. 날짜는 CURRENT_DATE 기준으로 만들어지므로 "이번 달" 쿼리가 의미 있는 행을 읽는다)
#   REBUILD=1               이미 준비된 DB 도 지우고 다시 적재한다. (데이터 생성기나 스키마를 바꾼 뒤에 사용)
#   OUT_DIR=cinema/results_bulk_interleaved   로그 저장 위치. 기본값: BULK=1 이면 results_bulk_interleaved, BULK=0 이면 results_interleaved 이고,
#                           PARALLEL 을 지정하면 뒤에 _parallel<값> 이 붙는다. 같은 이름의 기존 cinema_<before|after>_NN.log 는 덮어쓴다.
#   PARALLEL=0              측정 쿼리의 max_parallel_workers_per_gather 를 지정한다. 0 이면 병렬 실행을 끄고 직렬로 측정한다.
#                           비워 두면 서버 기본값(이 컨테이너는 2)을 쓴다.
#   DB_BEFORE, DB_AFTER     측정용 DB 이름. 실제 DB 를 지우지 않도록 이름이 _bench 로 끝나야 한다.
#   CONTAINER, WORKSPACE    컨테이너 이름 / 컨테이너 안에서 repo 가 마운트된 경로 (docker-compose.yml 의 ./:/workspace:ro)
#
# 두 DB 는 같은 PostgreSQL 인스턴스에 있으므로 shared_buffers 를 함께 쓴다. shared_buffers 와 각 DB 의 크기(size_total)는 meta 파일에 남는다.
# 스키마를 적재한 직후 VACUUM (ANALYZE) 를 실행하므로 전/후 모두 모든 테이블에 통계와 가시성 맵이 있는 상태에서 측정한다.
# 반정규화 스키마는 트리거를 쓰고 대량 적재 중에 사용자 트리거를 껐다 켜므로 슈퍼유저(postgres)로 적재한다.
#
# 출력: ${OUT_DIR}/cinema_<before|after>_NN.log (자원 측정), cinema_<before|after>_NN_time.log (시간 측정) (NN = 쿼리 번호),
#       cinema_<before|after>_meta.txt (테이블별 행 수·통계 상태, 서버 설정)
# 쿼리별 중앙값/사분위 범위/변동계수 요약은 sh cinema/summarize_estimation_result.sh [결과 폴더] 로 볼 수 있다.

set -u

CONTAINER="${CONTAINER:-db-optimization-postgres}"
DB_BEFORE="${DB_BEFORE:-cinema_normalized_bench}"
DB_AFTER="${DB_AFTER:-cinema_denormalized_bench}"
RUNS="${RUNS:-30}"
RES_RUNS="${RES_RUNS:-3}"
WARMUP="${WARMUP:-3}"
WORKSPACE="${WORKSPACE:-/workspace}"
BULK="${BULK:-1}"
REBUILD="${REBUILD:-0}"
MODE="${1:-all}"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT=$(basename "$SCRIPT_DIR")   # cinema (컨테이너 안에서는 $WORKSPACE/$PROJECT)
PARALLEL="${PARALLEL:-}"
if [ "$BULK" = 1 ]; then RESULT_NAME=results_bulk_interleaved; else RESULT_NAME=results_interleaved; fi
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/$RESULT_NAME${PARALLEL:+_parallel$PARALLEL}}"
EXPECTED_QUERIES=9
READY_MARK="bench-ready bulk=$BULK stats=2000 vacuumed"

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
# 지우고 다시 만들 수 있는 DB 이므로 실제 DB(cinema, library 등)를 지우지 않도록 이름으로 막는다.
for d in "$DB_BEFORE" "$DB_AFTER"; do
  case "$d" in *_bench) ;; *) die "DB 이름은 _bench 로 끝나야 합니다 (실제 DB 보호): $d" ;; esac
done
[ "$DB_BEFORE" != "$DB_AFTER" ] || die "DB_BEFORE 와 DB_AFTER 는 서로 달라야 합니다."
docker exec "$CONTAINER" test -d "$WORKSPACE/$PROJECT/postgresql_denormalization" \
  || die "컨테이너 '$CONTAINER' 에서 $WORKSPACE/$PROJECT 를 찾을 수 없습니다. 컨테이너가 실행 중인지, repo 가 마운트되어 있는지 확인하세요."

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

# phase(before|after) 에 해당하는 변수를 설정한다: db, sub, ddl, ins, bulk, sqlfile
select_phase() {
  case "$1" in
    before)
      db=$DB_BEFORE
      sub=postgresql
      ddl=$sub/postgresql_create_ddl.sql
      ins=$sub/postgresql_insert_data.sql
      bulk=$sub/postgresql_insert_data_bulk.sql
      sqlfile=$sub/postgresql_information_system.sql ;;
    after)
      db=$DB_AFTER
      sub=postgresql_denormalization
      ddl=$sub/create_ddl.sql
      ins=$sub/insert_data.sql
      bulk=$sub/insert_data_bulk.sql
      sqlfile=$sub/information_system.sql ;;
  esac
}

setup_db() {
  select_phase "$1"
  mark=$(psql_in -d postgres -At -c "SELECT shobj_description(oid, 'pg_database') FROM pg_database WHERE datname = '$db'")
  if [ "$REBUILD" != 1 ] && [ "$mark" = "$READY_MARK" ]; then
    echo "==> [$1] DB '$db' 는 이미 준비되어 있어 건너뜁니다 ($READY_MARK). 다시 만들려면 REBUILD=1"
    return 0
  fi
  echo "==> [$1] DB '$db' 를 새로 만들고 스키마·데이터를 적재합니다 ($sub)"
  psql_in -d postgres -c "DROP DATABASE IF EXISTS \"$db\"" || die "DB 삭제 실패: $db"
  psql_in -d postgres -c "CREATE DATABASE \"$db\"" || die "DB 생성 실패: $db"
  psql_in -d "$db" -f "$WORKSPACE/$PROJECT/$ddl" || die "$ddl 적용 실패"
  psql_in -d "$db" -f "$WORKSPACE/$PROJECT/$ins" || die "$ins 적용 실패"
  if [ "$BULK" = 1 ]; then
    psql_in -d "$db" -f "$WORKSPACE/$PROJECT/$bulk" || die "$bulk 적용 실패"
  fi
  # 전/후가 같은 통계 상태에서 비교되도록 모든 테이블을 분석한다.
  # ANALYZE 는 기본 설정(statistics_target=100)에서 행 3만 개를 무작위로 뽑아 통계를 만들므로 실험을 다시 돌릴 때마다
  # 통계가 달라지고, 경계에 있는 쿼리는 실행 계획이 바뀐다. 표본(300 x target)이 가장 큰 테이블(예매 약 31.5만 행)보다 크게 해서
  # 전체 행을 읽도록 고정하면 같은 데이터에서 항상 같은 통계가 나온다. (2000 -> 표본 60만 행)
  # VACUUM 도 함께 실행해 가시성 맵(relallvisible)을 채운다. 적재 직후에는 가시성 맵이 비어 있어 Index Only Scan 이 힙을 다시 읽고
  # (Heap Fetches > 0) 플래너가 그 비용을 반영해 플랜을 다르게 고를 수 있다. autovacuum 이 언제 도느냐에 따라 같은 쿼리가
  # 먼저 측정한 DB 와 나중에 측정한 DB 에서 다른 플랜을 타는 것이 7번 쿼리에서 실제로 관찰되었다.
  # (-c 를 둘로 나누는 이유: VACUUM 은 트랜잭션 블록 안에서 실행할 수 없고, 한 -c 에 여러 문장을 쓰면 하나의 트랜잭션이 된다.)
  psql_in -d "$db" -c "SET default_statistics_target = 2000" -c "VACUUM (ANALYZE)" || die "VACUUM ANALYZE 실패"
  psql_in -d "$db" -c "COMMENT ON DATABASE \"$db\" IS '$READY_MARK'" || die "준비 표시 실패"
}

# 전체 줄 주석을 뺀 뒤 ';' 단위로 쿼리를 나눠 $TMP_ROOT/<phase>/q_01.sql ... 로 저장
split_queries() {
  select_phase "$1"
  qdir="$TMP_ROOT/$1"
  mkdir -p "$qdir"
  grep -v '^[[:space:]]*--' "$SCRIPT_DIR/$sqlfile" \
    | awk -v dir="$qdir" 'BEGIN { RS = ";" } NF { n++; f = sprintf("%s/q_%02d.sql", dir, n); print > f; close(f) }'
  nq=$(ls "$qdir"/q_*.sql 2>/dev/null | wc -l | tr -d ' ')
  [ "$nq" -eq "$EXPECTED_QUERIES" ] || die "$sqlfile 에서 쿼리 ${EXPECTED_QUERIES}개를 찾지 못했습니다 (찾은 수: $nq)."
}

write_meta() {
  select_phase "$1"
  psql_in -d "$db" -At -c "SELECT 1" > /dev/null || die "DB '$db' 에 연결할 수 없습니다. 먼저 setup 을 실행하세요."
  [ "$(psql_in -d postgres -At -c "SELECT shobj_description(oid, 'pg_database') FROM pg_database WHERE datname = '$db'")" = "$READY_MARK" ] \
    || die "DB '$db' 가 BULK=$BULK 조건으로 준비되어 있지 않습니다. 먼저 setup (또는 REBUILD=1) 을 실행하세요."
  {
    echo "date: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "phase: $1"
    echo "schema: $PROJECT/$sub"
    echo "stats: analyze  runs: $RUNS  res_runs: $RES_RUNS  warmup: $WARMUP  db: $db  bulk: $BULK  parallel: ${PARALLEL:-server-default}"
    echo "order: interleaved (odd run: before first, even run: after first), other db: $( [ "$1" = before ] && echo "$DB_AFTER" || echo "$DB_BEFORE" )"
    psql_in -d "$db" -At -c "SELECT version()"
    psql_meas -d "$db" -At -c "SELECT name || '=' || setting FROM pg_settings WHERE name IN ('shared_buffers','work_mem','jit','max_parallel_workers_per_gather','TimeZone') ORDER BY 1"
    psql_in -d "$db" -At -c "SELECT 'current_date=' || CURRENT_DATE"
    for t in tbl_scmv_m1 tbl_scrn_m1 tbl_seat_m1 tbl_mebr_m1 tbl_bytk_d1 tbl_chrg_d1 tbl_like_d1; do
      psql_in -d "$db" -At -c "SELECT 'rows $t=' || count(*) FROM $t"
    done
    psql_in -d "$db" -At -c "SELECT 'size_total=' || pg_size_pretty(sum(pg_total_relation_size(c.oid))) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relkind = 'r'"
    psql_in -d "$db" -At -c "SELECT 'size_bytk=' || pg_size_pretty(pg_total_relation_size('tbl_bytk_d1'))"
    psql_in -d "$db" -At -F '=' -c "SELECT relname, CASE WHEN last_analyze IS NOT NULL OR last_autoanalyze IS NOT NULL THEN 'analyzed' ELSE 'NO-STATS' END FROM pg_stat_user_tables ORDER BY 1"
  } > "$OUT_DIR/cinema_$1_meta.txt"
}

# 한 번 실행해 결과를 $4 (없으면 버림) 에 덧붙인다. $1=phase $2=쿼리 번호 $3=옵션(EXPLAIN 문 앞부분)
run_once() {
  select_phase "$1"
  { printf '%s\n' "$3"; cat "$TMP_ROOT/$1/q_$2.sql"; echo ';'; } | psql_meas -d "$db" >> "${4:-/dev/null}" \
    || die "[$1] 쿼리 $2 실행 실패"
}

# 한 쿼리를 한 가지 옵션($1)으로 측정한다. 워밍업 $WARMUP회 뒤에 $2회를 정규화/반정규화 순서를 번갈아 가며 실행한다.
# $2=측정 횟수 $3=쿼리 번호 $4=before 로그 $5=after 로그
measure_pass() {
  opts=$1; cnt=$2; q=$3; logb=$4; loga=$5
  : > "$logb"; : > "$loga"
  w=1
  while [ "$w" -le "$WARMUP" ]; do
    run_once before "$q" "$opts"; run_once after "$q" "$opts"
    w=$((w + 1))
  done
  i=1
  while [ "$i" -le "$cnt" ]; do
    echo "===== RUN $i =====" >> "$logb"
    echo "===== RUN $i =====" >> "$loga"
    if [ $((i % 2)) -eq 1 ]; then
      run_once before "$q" "$opts" "$logb"; run_once after "$q" "$opts" "$loga"
    else
      run_once after "$q" "$opts" "$loga"; run_once before "$q" "$opts" "$logb"
    fi
    i=$((i + 1))
  done
}

measure_all() {
  mkdir -p "$OUT_DIR"
  split_queries before
  split_queries after
  write_meta before
  write_meta after
  n=1
  while [ "$n" -le "$EXPECTED_QUERIES" ]; do
    q=$(printf '%02d' "$n")
    measure_pass "$EXPLAIN_OPTS" "$RES_RUNS" "$q" "$OUT_DIR/cinema_before_$q.log" "$OUT_DIR/cinema_after_$q.log"
    measure_pass "$TIME_OPTS" "$RUNS" "$q" "$OUT_DIR/cinema_before_${q}_time.log" "$OUT_DIR/cinema_after_${q}_time.log"
    echo "    쿼리 $q: 자원 ${RES_RUNS}회 + 시간 ${RUNS}회 (각각 워밍업 ${WARMUP}회, 번갈아)"
    n=$((n + 1))
  done
}

echo "컨테이너: $CONTAINER / 정규화 DB: $DB_BEFORE / 반정규화 DB: $DB_AFTER / 워밍업: ${WARMUP}회 / 자원 측정: ${RES_RUNS}회 / 시간 측정: ${RUNS}회 / 대량 샘플: $BULK / 병렬 워커 상한: ${PARALLEL:-서버 기본값}"
case "$MODE" in
  setup)   setup_db before; setup_db after ;;
  measure) echo "로그: $OUT_DIR (같은 이름의 기존 로그는 덮어씁니다)"; measure_all ;;
  all)     setup_db before; setup_db after; echo "로그: $OUT_DIR (같은 이름의 기존 로그는 덮어씁니다)"; measure_all ;;
  drop)
    for d in "$DB_BEFORE" "$DB_AFTER"; do
      psql_in -d postgres -c "DROP DATABASE IF EXISTS \"$d\"" || die "DB 삭제 실패: $d"
    done ;;
esac
echo "==> 완료"
