#!/bin/sh
# cinema 정보시스템 쿼리 1~9번의 응답시간·리소스를 반정규화 전/후로 측정한다.
#
# 한 DB 안에서 다음 순서로 진행한다. (실제 컨테이너에서 실행, 사용자의 cinema DB 는 건드리지 않음)
#   1) before: public 스키마를 비우고 정규화 스키마 + 데이터 적재 -> 쿼리 9개 x RUNS 회 측정
#   2) after : public 스키마를 비우고 반정규화 스키마 + 데이터 적재 -> 쿼리 9개 x RUNS 회 측정
# 쿼리는 각 information_system.sql 에서 읽으므로 SQL 파일과 항상 일치한다.
# EXPLAIN (ANALYZE, BUFFERS, MEMORY, WAL, SETTINGS, SUMMARY) 로 실행해 로그에 저장한다.
#
# 사용법: sh estimation_response_time_and_resource.sh [before|after|both]   (기본: both)
#   RUNS=10               쿼리당 반복 횟수
#   OUT_DIR=results        로그 저장 위치. 기존 cinema_<before|after>_NN.log 는 덮어쓴다.
#   DB=cinema_bench        측정용 DB. 매 실행마다 만들고 끝나면 지우므로 이름은 _bench 로 끝나야 한다.
#   KEEP_DB=1              끝나고 측정용 DB 를 지우지 않음
#   CONTAINER, WORKSPACE   컨테이너 이름 / 컨테이너 안에서 repo 가 마운트된 경로 (docker-compose.yml 의 ./:/workspace:ro)
#
# 스키마를 적재한 직후 전체 ANALYZE 를 실행하므로 전/후 모두 모든 테이블에 통계가 있는 상태에서 측정한다.
#
# 출력: ${OUT_DIR}/cinema_<before|after>_NN.log (NN = 쿼리 번호), cinema_<before|after>_meta.txt (테이블별 통계 상태, 서버 설정)

set -u

CONTAINER="${CONTAINER:-db-optimization-postgres}"
DB="${DB:-cinema_bench}"
RUNS="${RUNS:-10}"
OUT_DIR="${OUT_DIR:-results}"
WORKSPACE="${WORKSPACE:-/workspace}"
KEEP_DB="${KEEP_DB:-0}"
MODE="${1:-both}"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

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

case "$MODE" in before|after|both) ;; *) die "사용법: sh $0 [before|after|both]" ;; esac
# 매번 DROP/CREATE 하는 DB 이므로 실제 DB(cinema, library 등)를 지우지 않도록 이름으로 막는다.
case "$DB" in *_bench) ;; *) die "DB 이름은 _bench 로 끝나야 합니다 (실제 DB 보호): $DB" ;; esac
docker exec "$CONTAINER" test -d "$WORKSPACE/cinema/postgresql_denormalization" \
  || die "컨테이너 '$CONTAINER' 에서 $WORKSPACE/cinema 를 찾을 수 없습니다. 컨테이너가 실행 중인지, repo 가 마운트되어 있는지 확인하세요."
mkdir -p "$OUT_DIR"

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

measure() {
  phase=$1
  case "$phase" in
    before)
      ddl=cinema/postgresql/postgresql_create_ddl.sql
      ins=cinema/postgresql/postgresql_insert_data.sql
      sqlfile=cinema/postgresql/postgresql_information_system.sql ;;
    after)
      ddl=cinema/postgresql_denormalization/create_ddl.sql
      ins=cinema/postgresql_denormalization/insert_data.sql
      sqlfile=cinema/postgresql_denormalization/information_system.sql ;;
  esac
  prefix="$OUT_DIR/cinema_$phase"
  qdir="$TMP_ROOT/$phase"
  mkdir -p "$qdir"

  # 전체 줄 주석을 뺀 뒤 ';' 단위로 쿼리를 나눠 q_01.sql ... 로 저장
  grep -v '^[[:space:]]*--' "$SCRIPT_DIR/$sqlfile" \
    | awk -v dir="$qdir" 'BEGIN { RS = ";" } NF { n++; f = sprintf("%s/q_%02d.sql", dir, n); print > f; close(f) }'
  [ "$(ls "$qdir"/q_*.sql | wc -l | tr -d ' ')" -eq 9 ] || die "$sqlfile 에서 쿼리 9개를 찾지 못했습니다."

  echo "==> [$phase] 스키마 구성 (같은 DB '$DB' 의 public 스키마를 비우고 다시 만듭니다)"
  psql_in -d postgres -At -c "SELECT 1 FROM pg_database WHERE datname = '$DB'" | grep -q 1 \
    || psql_in -d postgres -c "CREATE DATABASE \"$DB\"" || die "DB 생성 실패"
  psql_in -d "$DB" -c "SET client_min_messages = warning; DROP SCHEMA public CASCADE; CREATE SCHEMA public;" || die "스키마 초기화 실패"
  psql_in -d "$DB" -f "$WORKSPACE/$ddl" || die "$ddl 적용 실패"
  psql_in -d "$DB" -f "$WORKSPACE/$ins" || die "$ins 적용 실패"

  # 전/후가 같은 통계 상태에서 비교되도록 모든 테이블을 분석한다.
  psql_in -d "$DB" -c "ANALYZE" || die "ANALYZE 실패"

  {
    echo "date: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "phase: $phase"
    echo "stats: analyze  runs: $RUNS  db: $DB"
    psql_in -d "$DB" -At -c "SELECT version()"
    psql_in -d "$DB" -At -c "SELECT name || '=' || setting FROM pg_settings WHERE name IN ('shared_buffers','work_mem','jit','max_parallel_workers_per_gather','TimeZone') ORDER BY 1"
    psql_in -d "$DB" -At -F '=' -c "SELECT relname, CASE WHEN last_analyze IS NOT NULL OR last_autoanalyze IS NOT NULL THEN 'analyzed' ELSE 'NO-STATS' END FROM pg_stat_user_tables ORDER BY 1"
  } > "${prefix}_meta.txt"

  for q in "$qdir"/q_*.sql; do
    n=$(basename "$q" .sql | sed 's/^q_//')
    log="${prefix}_${n}.log"
    : > "$log"
    i=1
    while [ "$i" -le "$RUNS" ]; do
      echo "===== RUN $i =====" >> "$log"
      { printf '%s\n' "$EXPLAIN_OPTS"; cat "$q"; echo ';'; } | psql_in -d "$DB" >> "$log" \
        || die "[$phase] 쿼리 $n 실행 실패 (로그: $log)"
      i=$((i + 1))
    done
    echo "    쿼리 $n: ${RUNS}회 -> $log"
  done
}

echo "컨테이너: $CONTAINER / 측정용 DB: $DB / 반복: ${RUNS}회 / 로그: $OUT_DIR (같은 이름의 기존 로그는 덮어씁니다)"
case "$MODE" in
  before) measure before ;;
  after)  measure after ;;
  both)   measure before; measure after ;;
esac

[ "$KEEP_DB" = 1 ] || psql_in -d postgres -c "DROP DATABASE IF EXISTS \"$DB\"" || die "측정용 DB 삭제 실패"
echo "==> 완료"
