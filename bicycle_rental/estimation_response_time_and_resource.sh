#!/bin/sh
# bicycle_rental 정보시스템 쿼리 1~7번의 응답시간·메모리·버퍼 사용량을 정규화와 반정규화(v2.0.0)에서 측정한다.
# (cinema/estimation_response_time_and_resource.sh 와 같은 방식이다.)
#
# 독립된 DB 두 개를 미리 만들어 두고, 쿼리마다 쿼리 세트(phase) 네 개를 번갈아 측정한다. 사용자의 bicycle_rental DB 는 건드리지 않는다.
#   phase   DB          쿼리 파일
#   before  정규화 DB   postgresql/postgresql_information_system.sql                              (정규화)
#   a23     반정규화 DB postgresql_denormalization/postgresql_information_system_row.sql           (후보 2·3: 대여소 이름 복사, 시각 파생 열)
#   a1      반정규화 DB postgresql_denormalization/postgresql_information_system_summary.sql       (후보 1: 집계 테이블, 대여소는 조인)
#   a123    반정규화 DB postgresql_denormalization/postgresql_information_system.sql               (후보 1·2·3을 합침)
#
#   setup  : 정규화 DB(bicycle_rental_normalized_bench), 반정규화 DB(bicycle_rental_denormalized_bench)를 만들고
#            DDL -> 기존 샘플 -> 날짜 이동 -> 대량 샘플 순서로 적재한 뒤 VACUUM (ANALYZE).
#            반정규화 DB 는 대량 샘플 전에 집계 트리거를 끄고, 적재 뒤 집계 테이블을 다시 만들고 트리거를 켠다.
#            이미 같은 조건(BULK)으로 준비된 DB 는 건너뛴다. 스키마 파일을 고쳤다면 REBUILD=1 로 다시 만든다.
#   measure: 쿼리마다 자원 측정과 시간 측정을 차례로 하고, 두 측정 모두 한 회마다 phase 순서를 한 칸씩 돌려 가며 실행한다.
#            (1회: before a23 a1 a123, 2회: a23 a1 a123 before, ... 각 측정 앞에 WARMUP회 x 모든 phase 워밍업)
#              자원 측정: EXPLAIN (ANALYZE, BUFFERS, MEMORY, WAL, SETTINGS, SUMMARY) 를 RES_RUNS회  -> bicycle_<phase>_NN.log
#              시간 측정: EXPLAIN (ANALYZE, TIMING OFF, BUFFERS OFF, MEMORY OFF, SUMMARY ON) 을 RUNS회 -> bicycle_<phase>_NN_time.log
#   drop   : 두 측정용 DB 를 지운다.
#
# 시간과 자원을 따로 재는 이유: EXPLAIN ANALYZE 는 노드마다 시간을 재고 BUFFERS·MEMORY 를 모으는 비용이 실행 시간에 포함되고,
# 그 비용은 플랜의 노드 수에 따라 달라진다. 그래서 버퍼·메모리·플랜은 전체 옵션으로 몇 번만 보고, 시간은 계측 옵션을 끄고 여러 번 잰다.
# 쿼리는 위 SQL 파일에서 읽으므로 SQL 파일과 항상 일치한다.
#
# 사용법: sh bicycle_rental/estimation_response_time_and_resource.sh [setup|measure|all|drop]   (기본: all, 어느 디렉터리에서 실행해도 됨)
#   RUNS=30        쿼리당 시간 측정 횟수 (phase 마다 시간 로그에 남는 횟수)
#   RES_RUNS=3     쿼리당 자원 측정(전체 EXPLAIN 옵션) 횟수. 버퍼·메모리·플랜은 반복해도 같아서 적게 돌린다.
#   WARMUP=3       각 측정 전에 phase 마다 먼저 실행하고 버리는 횟수. 캐시 상태를 안정시키기 위함
#   PHASES="before a23 a1 a123"   측정할 phase. 일부만 고를 수 있다.
#   BULK=1         기본 샘플 뒤에 대량 샘플(postgresql_insert_data_bulk.sql)을 추가로 적재한다. 0 이면 기본 샘플(대여 50건)만 사용.
#   REBUILD=1      이미 준비된 DB 도 지우고 다시 적재한다.
#   PARALLEL=0     측정 쿼리의 max_parallel_workers_per_gather 를 지정한다. 0 이면 병렬 실행을 끄고 직렬로 측정한다.
#                  비워 두면 서버 기본값(이 컨테이너는 2)을 쓴다.
#   OUT_DIR        로그 저장 위치. 기본값: BULK=1 이면 bicycle_rental/results_bulk_interleaved, BULK=0 이면 results_interleaved 이고,
#                  PARALLEL 을 지정하면 뒤에 _parallel<값> 이 붙는다. 같은 이름의 기존 로그는 덮어쓴다.
#   DB_BEFORE, DB_AFTER   측정용 DB 이름. 실제 DB 를 지우지 않도록 이름이 _bench 로 끝나야 한다.
#   CONTAINER, WORKSPACE  컨테이너 이름 / 컨테이너 안에서 repo 가 마운트된 경로 (docker-compose.yml 의 ./:/workspace:ro)
#
# 두 DB 는 같은 PostgreSQL 인스턴스에 있으므로 shared_buffers 를 함께 쓴다.
# 스키마를 적재한 직후 VACUUM (ANALYZE) 를 실행하고, 통계는 default_statistics_target=2000 (표본 60만 행)으로 만들어서
# 가장 큰 테이블(대여 약 33만 행) 전체를 읽는다. 대량 샘플은 CURRENT_DATE 기준으로 만들어지지만 쿼리 1~7번은 CURRENT_DATE 를 쓰지 않는다.
# 반정규화 스키마는 트리거를 쓰고 대량 적재 중에 트리거를 껐다 켜므로 슈퍼유저(postgres)로 적재한다.
#
# 출력: ${OUT_DIR}/bicycle_<phase>_NN.log (자원 측정), bicycle_<phase>_NN_time.log (시간 측정) (NN = 쿼리 번호),
#       bicycle_before_meta.txt, bicycle_after_meta.txt (테이블별 행 수, 크기, 서버 설정)
# 요약은 sh bicycle_rental/summarize_estimation_result.sh [결과 폴더] 로 볼 수 있다.

set -u

CONTAINER="${CONTAINER:-db-optimization-postgres}"
DB_BEFORE="${DB_BEFORE:-bicycle_rental_normalized_bench}"
DB_AFTER="${DB_AFTER:-bicycle_rental_denormalized_bench}"
RUNS="${RUNS:-30}"
RES_RUNS="${RES_RUNS:-3}"
WARMUP="${WARMUP:-3}"
WORKSPACE="${WORKSPACE:-/workspace}"
BULK="${BULK:-1}"
REBUILD="${REBUILD:-0}"
PHASES="${PHASES:-before a23 a1 a123}"
MODE="${1:-all}"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT=$(basename "$SCRIPT_DIR")   # bicycle_rental (컨테이너 안에서는 $WORKSPACE/$PROJECT)
PARALLEL="${PARALLEL:-}"
if [ "$BULK" = 1 ]; then RESULT_NAME=results_bulk_interleaved; else RESULT_NAME=results_interleaved; fi
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/$RESULT_NAME${PARALLEL:+_parallel$PARALLEL}}"
EXPECTED_QUERIES=7
READY_MARK="bench-ready bulk=$BULK stats=2000 vacuumed"
SHIFT=migration/shift_dates_to_current.sql

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
for p in $PHASES; do case "$p" in before|a23|a1|a123) ;; *) die "알 수 없는 phase: $p (before a23 a1 a123 중에서 고르세요)" ;; esac; done
# 지우고 다시 만들 수 있는 DB 이므로 실제 DB(bicycle_rental, cinema 등)를 지우지 않도록 이름으로 막는다.
for d in "$DB_BEFORE" "$DB_AFTER"; do
  case "$d" in *_bench) ;; *) die "DB 이름은 _bench 로 끝나야 합니다 (실제 DB 보호): $d" ;; esac
done
[ "$DB_BEFORE" != "$DB_AFTER" ] || die "DB_BEFORE 와 DB_AFTER 는 서로 달라야 합니다."
docker exec "$CONTAINER" test -d "$WORKSPACE/$PROJECT/postgresql_denormalization" \
  || die "컨테이너 '$CONTAINER' 에서 $WORKSPACE/$PROJECT 를 찾을 수 없습니다. 컨테이너가 실행 중인지, repo 가 마운트되어 있는지 확인하세요."

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

# phase 에 해당하는 변수를 설정한다: db, sqlfile
select_phase() {
  case "$1" in
    before) db=$DB_BEFORE; sqlfile=postgresql/postgresql_information_system.sql ;;
    a23)    db=$DB_AFTER;  sqlfile=postgresql_denormalization/postgresql_information_system_row.sql ;;
    a1)     db=$DB_AFTER;  sqlfile=postgresql_denormalization/postgresql_information_system_summary.sql ;;
    a123)   db=$DB_AFTER;  sqlfile=postgresql_denormalization/postgresql_information_system.sql ;;
  esac
}

# kind(before|after) 에 해당하는 DB 를 만든다. 샘플 INSERT 와 날짜 이동은 정규화 파일을 그대로 쓴다.
setup_db() {
  if [ "$1" = before ]; then
    db=$DB_BEFORE; ddl=postgresql/postgresql_create_ddl.sql
  else
    db=$DB_AFTER; ddl=postgresql_denormalization/postgresql_create_ddl.sql
  fi
  ins=postgresql/postgresql_insert_data.sql
  bulk=postgresql/postgresql_insert_data_bulk.sql
  mark=$(psql_in -d postgres -At -c "SELECT shobj_description(oid, 'pg_database') FROM pg_database WHERE datname = '$db'")
  if [ "$REBUILD" != 1 ] && [ "$mark" = "$READY_MARK" ]; then
    echo "==> [$1] DB '$db' 는 이미 준비되어 있어 건너뜁니다 ($READY_MARK). 다시 만들려면 REBUILD=1"
    return 0
  fi
  echo "==> [$1] DB '$db' 를 새로 만들고 스키마·데이터를 적재합니다 ($ddl)"
  psql_in -d postgres -c "DROP DATABASE IF EXISTS \"$db\"" || die "DB 삭제 실패: $db"
  psql_in -d postgres -c "CREATE DATABASE \"$db\"" || die "DB 생성 실패: $db"
  psql_in -d "$db" -f "$WORKSPACE/$PROJECT/$ddl" || die "$ddl 적용 실패"
  psql_in -d "$db" -f "$WORKSPACE/$PROJECT/$ins" || die "$ins 적용 실패"
  # 기존 샘플의 날짜를 오늘 기준으로 옮긴 뒤 대량 샘플을 적재한다. (순서가 바뀌면 기존 샘플이 옮겨지지 않는다)
  psql_in -d "$db" -f "$WORKSPACE/$PROJECT/$SHIFT" > /dev/null || die "$SHIFT 적용 실패"
  if [ "$BULK" = 1 ]; then
    if [ "$1" = after ]; then
      psql_in -d "$db" -c "ALTER TABLE tblrentT1 DISABLE TRIGGER trg_rent_summary" || die "집계 트리거 끄기 실패"
    fi
    psql_in -d "$db" -f "$WORKSPACE/$PROJECT/$bulk" > /dev/null || die "$bulk 적용 실패"
    if [ "$1" = after ]; then
      psql_in -d "$db" -c "SELECT fn_rebuild_rent_summary()" -c "ALTER TABLE tblrentT1 ENABLE TRIGGER trg_rent_summary" > /dev/null || die "집계 테이블 재생성 실패"
      # 집계 테이블이 대여 테이블과 맞는지 확인한다. 위반이 있으면 측정하지 않는다.
      bad=$(psql_in -d "$db" -At -F '|' -f "$WORKSPACE/$PROJECT/postgresql_denormalization/postgresql_verify_denormalization.sql" | awk -F'|' '$NF + 0 > 0' | wc -l | tr -d ' ')
      [ "$bad" = 0 ] || die "postgresql_verify_denormalization.sql 에서 위반이 있는 규칙 ${bad}개"
    fi
  fi
  # ANALYZE 는 기본 설정(statistics_target=100)에서 행 3만 개를 무작위로 뽑아 통계를 만들므로 다시 돌릴 때마다 통계가 달라지고,
  # 경계에 있는 쿼리는 실행 계획이 바뀐다. 표본(300 x target)이 가장 큰 테이블(대여 약 33만 행)보다 크게 해서 전체 행을 읽도록 고정한다.
  # VACUUM 도 함께 실행해 가시성 맵을 채운다. 적재 직후에는 가시성 맵이 비어 있어 Index Only Scan 이 힙을 다시 읽을 수 있다.
  # (-c 를 둘로 나누는 이유: VACUUM 은 트랜잭션 블록 안에서 실행할 수 없고, 한 -c 에 여러 문장을 쓰면 하나의 트랜잭션이 된다.)
  psql_in -d "$db" -c "SET default_statistics_target = 2000" -c "VACUUM (ANALYZE)" || die "VACUUM ANALYZE 실패"
  psql_in -d "$db" -c "COMMENT ON DATABASE \"$db\" IS '$READY_MARK'" || die "준비 표시 실패"
}

# 줄 끝 주석까지 뺀 뒤 ';' 단위로 쿼리를 나눠 $TMP_ROOT/<phase>/q_01.sql ... 로 저장
# (줄 끝 주석이 있으면 마지막 ';' 뒤의 주석이 쿼리 하나로 잘못 세어지므로 'sed' 로 먼저 지운다. 쿼리 문자열에는 '--' 가 없다.)
split_queries() {
  select_phase "$1"
  qdir="$TMP_ROOT/$1"
  mkdir -p "$qdir"
  sed 's/--.*$//' "$SCRIPT_DIR/$sqlfile" \
    | awk -v dir="$qdir" 'BEGIN { RS = ";" } NF { n++; f = sprintf("%s/q_%02d.sql", dir, n); print > f; close(f) }'
  nq=$(ls "$qdir"/q_*.sql 2>/dev/null | wc -l | tr -d ' ')
  [ "$nq" -eq "$EXPECTED_QUERIES" ] || die "$sqlfile 에서 쿼리 ${EXPECTED_QUERIES}개를 찾지 못했습니다 (찾은 수: $nq)."
}

# kind(before|after) 의 DB 정보를 $OUT_DIR/bicycle_<kind>_meta.txt 에 남긴다.
write_meta() {
  if [ "$1" = before ]; then db=$DB_BEFORE; tables="tblmebrM1 tbltickD1 tblbyclM1 tblrtplM1 tblrackD1 tblrentT1 tblspclD1 tbldmlsD1 tblfavoT1"
  else db=$DB_AFTER; tables="tblmebrM1 tbltickD1 tblbyclM1 tblrtplM1 tblrackD1 tblrentT1 tblspclD1 tbldmlsD1 tblfavoT1 tblrpmoS1 tblbcmoS1 tblrpwdS1 tblmbrgS1"; fi
  psql_in -d "$db" -At -c "SELECT 1" > /dev/null || die "DB '$db' 에 연결할 수 없습니다. 먼저 setup 을 실행하세요."
  [ "$(psql_in -d postgres -At -c "SELECT shobj_description(oid, 'pg_database') FROM pg_database WHERE datname = '$db'")" = "$READY_MARK" ] \
    || die "DB '$db' 가 BULK=$BULK 조건으로 준비되어 있지 않습니다. 먼저 setup (또는 REBUILD=1) 을 실행하세요."
  {
    echo "date: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "kind: $1"
    echo "stats: analyze  runs: $RUNS  res_runs: $RES_RUNS  warmup: $WARMUP  db: $db  bulk: $BULK  parallel: ${PARALLEL:-server-default}  phases: $PHASES"
    echo "order: interleaved (phase order rotates by one every run)"
    psql_in -d "$db" -At -c "SELECT version()"
    psql_meas -d "$db" -At -c "SELECT name || '=' || setting FROM pg_settings WHERE name IN ('shared_buffers','work_mem','jit','max_parallel_workers_per_gather','TimeZone') ORDER BY 1"
    psql_in -d "$db" -At -c "SELECT 'current_date=' || CURRENT_DATE"
    for t in $tables; do
      psql_in -d "$db" -At -c "SELECT 'rows $t=' || count(*) FROM $t"
    done
    psql_in -d "$db" -At -c "SELECT 'rent_period=' || min(rentdate)::date || ' ~ ' || max(rentdate)::date FROM tblrentT1"
    psql_in -d "$db" -At -c "SELECT 'size_total=' || pg_size_pretty(sum(pg_total_relation_size(c.oid))) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relkind = 'r'"
    psql_in -d "$db" -At -c "SELECT 'size_rent=' || pg_size_pretty(pg_total_relation_size('tblrentT1')) || ' (table ' || pg_size_pretty(pg_table_size('tblrentT1')) || ', index ' || pg_size_pretty(pg_indexes_size('tblrentT1')) || ')'"
    if [ "$1" = after ]; then
      psql_in -d "$db" -At -c "SELECT 'size_summary=' || pg_size_pretty(sum(pg_total_relation_size(c.oid))) FROM pg_class c WHERE c.relname IN ('tblrpmos1', 'tblbcmos1', 'tblrpwds1', 'tblmbrgs1')"
    fi
    psql_in -d "$db" -At -F '=' -c "SELECT relname, CASE WHEN last_analyze IS NOT NULL OR last_autoanalyze IS NOT NULL THEN 'analyzed' ELSE 'NO-STATS' END FROM pg_stat_user_tables ORDER BY 1"
  } > "$OUT_DIR/bicycle_${1}_meta.txt"
}

# 한 번 실행해 결과를 $4 (없으면 버림) 에 덧붙인다. $1=phase $2=쿼리 번호 $3=옵션(EXPLAIN 문 앞부분)
run_once() {
  select_phase "$1"
  { printf '%s\n' "$3"; cat "$TMP_ROOT/$1/q_$2.sql"; echo ';'; } | psql_meas -d "$db" >> "${4:-/dev/null}" \
    || die "[$1] 쿼리 $2 실행 실패"
}

# 한 쿼리를 한 가지 옵션($1)으로 측정한다. 워밍업 $WARMUP회 뒤에 $2회를 실행하고, 회마다 phase 순서를 한 칸씩 돌린다.
# $2=측정 횟수 $3=쿼리 번호 $4=로그 이름에 붙일 접미사(빈 값 또는 _time)
measure_pass() {
  opts=$1; cnt=$2; q=$3; suffix=$4
  np=$(echo $PHASES | wc -w | tr -d ' ')
  for p in $PHASES; do : > "$OUT_DIR/bicycle_${p}_${q}${suffix}.log"; done
  w=1
  while [ "$w" -le "$WARMUP" ]; do
    for p in $PHASES; do run_once "$p" "$q" "$opts"; done
    w=$((w + 1))
  done
  i=1
  while [ "$i" -le "$cnt" ]; do
    for p in $PHASES; do echo "===== RUN $i =====" >> "$OUT_DIR/bicycle_${p}_${q}${suffix}.log"; done
    shift_n=$(( (i - 1) % np ))
    # PHASES 를 shift_n 칸 돌린 순서로 실행한다.
    order=$(echo $PHASES | awk -v k="$shift_n" '{ for (j = 1; j <= NF; j++) printf "%s ", $(((j - 1 + k) % NF) + 1) }')
    for p in $order; do run_once "$p" "$q" "$opts" "$OUT_DIR/bicycle_${p}_${q}${suffix}.log"; done
    i=$((i + 1))
  done
}

measure_all() {
  mkdir -p "$OUT_DIR"
  for p in $PHASES; do split_queries "$p"; done
  write_meta before
  write_meta after
  n=1
  while [ "$n" -le "$EXPECTED_QUERIES" ]; do
    q=$(printf '%02d' "$n")
    measure_pass "$EXPLAIN_OPTS" "$RES_RUNS" "$q" ""
    measure_pass "$TIME_OPTS" "$RUNS" "$q" "_time"
    echo "    쿼리 $q: 자원 ${RES_RUNS}회 + 시간 ${RUNS}회 (각각 워밍업 ${WARMUP}회, phase 순서를 돌려 가며)"
    n=$((n + 1))
  done
}

echo "컨테이너: $CONTAINER / 정규화 DB: $DB_BEFORE / 반정규화 DB: $DB_AFTER / phase: $PHASES / 워밍업: ${WARMUP}회 / 자원 측정: ${RES_RUNS}회 / 시간 측정: ${RUNS}회 / 대량 샘플: $BULK / 병렬 워커 상한: ${PARALLEL:-서버 기본값}"
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
