#!/bin/sh
# school 정보시스템 쿼리 1~6번의 응답시간·리소스를 반정규화 전/후로 측정한다.
#
# 한 DB 안에서 다음 순서로 진행한다. (실제 컨테이너에서 실행, 사용자의 school DB 는 건드리지 않음)
#   1) before: public 스키마를 비우고 정규화 스키마(school/postgresql) + 데이터 적재 -> 쿼리 6개 x RUNS 회 측정
#   2) after : public 스키마를 비우고 반정규화 스키마(school/postgresql_denormalization) + 데이터 적재 -> 쿼리 6개 x RUNS 회 측정
# 쿼리는 각 information_system.sql 에서 읽으므로 SQL 파일과 항상 일치한다.
# EXPLAIN (ANALYZE, BUFFERS, MEMORY, WAL, SETTINGS, SUMMARY) 로 실행해 로그에 저장한다.
#
# before 의 postgresql_information_system.sql 에는 설계 초안(한글 테이블명, :교수ID / <학과ID> 자리표시자)과
# 확인용 쿼리가 함께 있어 파일 전체를 그대로 실행할 수 없다. 그래서 두 파일 모두 전체 줄 주석을 뺀 뒤 ';' 단위로 나눠
#   - CREATE [OR REPLACE] VIEW 문           -> 측정 전에 적용 (같은 이름이 두 번 나오면 뒤의 정의가 남는다)
#   - tbl_ 테이블을 JOIN 하는 SELECT 문      -> 측정 대상 (1~6번, 파일에 나온 순서)
# 만 사용한다. 나머지(한글 테이블명 초안, select * from ...)는 실행하지 않는다.
#
# 사용법: sh school/estimation_response_time_and_resource.sh [before|after|both]   (기본: both, 어느 디렉터리에서 실행해도 됨)
#   RUNS=10                 쿼리당 반복 횟수
#   OUT_DIR=school/results  로그 저장 위치(기본: 이 스크립트가 있는 폴더의 results). 기존 school_<before|after>_NN.log 는 덮어쓴다.
#   DB=school_bench         측정용 DB. 매 실행마다 만들고 끝나면 지우므로 이름은 _bench 로 끝나야 한다.
#   KEEP_DB=1               끝나고 측정용 DB 를 지우지 않음
#   CONTAINER, WORKSPACE    컨테이너 이름 / 컨테이너 안에서 repo 가 마운트된 경로 (docker-compose.yml 의 ./:/workspace:ro)
#
# 스키마를 적재한 직후 전체 ANALYZE 를 실행하므로 전/후 모두 모든 테이블에 통계가 있는 상태에서 측정한다.
# 쿼리의 학기 조건은 실행 날짜(CURRENT_DATE)로 계산된다. 샘플 데이터의 학기는 202601, 202602 이므로 다른 해에 실행하면 결과 행이 0건이다.
#
# 출력: ${OUT_DIR}/school_<before|after>_NN.log (NN = 쿼리 번호), school_<before|after>_meta.txt (테이블별 통계 상태, 서버 설정)

set -u

CONTAINER="${CONTAINER:-db-optimization-postgres}"
DB="${DB:-school_bench}"
RUNS="${RUNS:-10}"
WORKSPACE="${WORKSPACE:-/workspace}"
KEEP_DB="${KEEP_DB:-0}"
MODE="${1:-both}"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT=$(basename "$SCRIPT_DIR")   # school (컨테이너 안에서는 $WORKSPACE/$PROJECT)
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/results}"
EXPECTED_QUERIES=6

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
# 매번 DROP/CREATE 하는 DB 이므로 실제 DB(school, library 등)를 지우지 않도록 이름으로 막는다.
case "$DB" in *_bench) ;; *) die "DB 이름은 _bench 로 끝나야 합니다 (실제 DB 보호): $DB" ;; esac
docker exec "$CONTAINER" test -d "$WORKSPACE/$PROJECT/postgresql_denormalization" \
  || die "컨테이너 '$CONTAINER' 에서 $WORKSPACE/$PROJECT 를 찾을 수 없습니다. 컨테이너가 실행 중인지, repo 가 마운트되어 있는지 확인하세요."
mkdir -p "$OUT_DIR"

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

# 전체 줄 주석을 뺀 뒤 ';' 단위로 문장을 나눠 뷰 정의는 v_NN.sql, 측정 대상 SELECT 는 q_NN.sql 로 저장
split_statements() {
  grep -v '^[[:space:]]*--' "$1" \
    | awk -v dir="$2" '
        BEGIN { RS = ";" }
        {
          stmt = $0
          up = toupper(stmt)
          if (up ~ /^[[:space:]]*CREATE[[:space:]]+(OR[[:space:]]+REPLACE[[:space:]]+)?VIEW[[:space:]]/) {
            sub(/^[[:space:]]*CREATE[[:space:]]+VIEW/, "CREATE OR REPLACE VIEW", stmt)
            v++; f = sprintf("%s/v_%02d.sql", dir, v)
          } else if (up ~ /^[[:space:]]*SELECT[[:space:]]/ && stmt ~ /tbl_/ && up ~ /[[:space:]]JOIN[[:space:]]/) {
            q++; f = sprintf("%s/q_%02d.sql", dir, q)
          } else next
          print stmt > f; close(f)
        }'
}

measure() {
  phase=$1
  case "$phase" in
    before)
      sub=postgresql
      ddl=$sub/postgresql_create_ddl.sql
      ins=$sub/postgresql_insert_data.sql
      sqlfile=$sub/postgresql_information_system.sql
      semtable=tbl_offe_d1 ;;
    after)
      sub=postgresql_denormalization
      ddl=$sub/create_ddl.sql
      ins=$sub/insert_data.sql
      sqlfile=$sub/information_system.sql
      semtable=tbl_subj_d2 ;;
  esac
  prefix="$OUT_DIR/school_$phase"
  qdir="$TMP_ROOT/$phase"
  mkdir -p "$qdir"

  split_statements "$SCRIPT_DIR/$sqlfile" "$qdir"
  nq=$(ls "$qdir"/q_*.sql 2>/dev/null | wc -l | tr -d ' ')
  [ "$nq" -eq "$EXPECTED_QUERIES" ] || die "$sqlfile 에서 측정 대상 쿼리 ${EXPECTED_QUERIES}개를 찾지 못했습니다 (찾은 수: $nq)."

  echo "==> [$phase] 스키마 구성 (같은 DB '$DB' 의 public 스키마를 비우고 다시 만듭니다)"
  psql_in -d postgres -At -c "SELECT 1 FROM pg_database WHERE datname = '$DB'" | grep -q 1 \
    || psql_in -d postgres -c "CREATE DATABASE \"$DB\"" || die "DB 생성 실패"
  psql_in -d "$DB" -c "SET client_min_messages = warning; DROP SCHEMA public CASCADE; CREATE SCHEMA public;" || die "스키마 초기화 실패"
  psql_in -d "$DB" -f "$WORKSPACE/$PROJECT/$ddl" || die "$ddl 적용 실패"
  psql_in -d "$DB" -f "$WORKSPACE/$PROJECT/$ins" || die "$ins 적용 실패"
  for v in "$qdir"/v_*.sql; do
    [ -e "$v" ] || continue
    psql_in -d "$DB" < "$v" || die "[$phase] 뷰 정의 적용 실패 ($(basename "$v"))"
  done

  # 전/후가 같은 통계 상태에서 비교되도록 모든 테이블을 분석한다.
  psql_in -d "$DB" -c "ANALYZE" || die "ANALYZE 실패"

  {
    echo "date: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "phase: $phase"
    echo "schema: $PROJECT/$sub"
    echo "stats: analyze  runs: $RUNS  db: $DB"
    psql_in -d "$DB" -At -c "SELECT version()"
    psql_in -d "$DB" -At -c "SELECT name || '=' || setting FROM pg_settings WHERE name IN ('shared_buffers','work_mem','jit','max_parallel_workers_per_gather','TimeZone') ORDER BY 1"
    psql_in -d "$DB" -At -F '=' -c "SELECT relname, CASE WHEN last_analyze IS NOT NULL OR last_autoanalyze IS NOT NULL THEN 'analyzed' ELSE 'NO-STATS' END FROM pg_stat_user_tables ORDER BY 1"
    psql_in -d "$DB" -At -F '=' -c "SELECT 'semester ' || semester, count(*) FROM $semtable GROUP BY semester ORDER BY 1"
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
