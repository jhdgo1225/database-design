#!/bin/sh
# 반정규화 쿼리 세 벌이 정규화 쿼리와 같은 결과를 내는지 쿼리마다 비교한다.
# 반정규화 스키마는 정규화 스키마의 열을 그대로 가지고 있어서, 한 DB 에서 정규화 쿼리와 반정규화 쿼리를 모두 실행해 출력을 바이트 단위로 비교한다.
#   정규화:         postgresql/postgresql_information_system.sql
#   후보 2·3:       postgresql_denormalization/postgresql_information_system_row.sql
#   후보 1:         postgresql_denormalization/postgresql_information_system_summary.sql
#   후보 1·2·3:     postgresql_denormalization/postgresql_information_system.sql
#
# 사용법: sh bicycle_rental/postgresql_denormalization/verify_query_equivalence.sh   (어느 디렉터리에서 실행해도 됨)
#   DB_NAME     반정규화 스키마가 적재된 DB. 기본값 bicycle_rental_denormalized_bench
#   CONTAINER, WORKSPACE   컨테이너 이름 / 컨테이너 안에서 repo 가 마운트된 경로
# 결과가 다른 쿼리가 있으면 그 번호를 보여 주고 종료 코드 1 로 끝난다.

set -u

CONTAINER="${CONTAINER:-db-optimization-postgres}"
DB_NAME="${DB_NAME:-bicycle_rental_denormalized_bench}"
EXPECTED_QUERIES=7
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")

die() { echo "ERROR: $*" >&2; exit 1; }
psql_in() { docker exec -i -e PGOPTIONS="-c client_min_messages=warning" "$CONTAINER" psql -X -q -v ON_ERROR_STOP=1 -U postgres "$@"; }

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

# 전체 줄 주석과 줄 끝 주석을 뺀 뒤 ';' 단위로 쿼리를 나눠 $TMP_ROOT/$2/q_01.sql ... 로 저장한다. $1=SQL 파일 $2=이름
split_queries() {
  mkdir -p "$TMP_ROOT/$2"
  sed 's/--.*$//' "$1" \
    | awk -v dir="$TMP_ROOT/$2" 'BEGIN { RS = ";" } NF { n++; f = sprintf("%s/q_%02d.sql", dir, n); print > f; close(f) }'
  nq=$(ls "$TMP_ROOT/$2"/q_*.sql 2>/dev/null | wc -l | tr -d ' ')
  [ "$nq" -eq "$EXPECTED_QUERIES" ] || die "$1 에서 쿼리 ${EXPECTED_QUERIES}개를 찾지 못했습니다 (찾은 수: $nq)."
}

psql_in -d "$DB_NAME" -At -c "SELECT 1" > /dev/null || die "DB '$DB_NAME' 에 연결할 수 없습니다."

split_queries "$PROJECT_DIR/postgresql/postgresql_information_system.sql" base
split_queries "$SCRIPT_DIR/postgresql_information_system_row.sql" row
split_queries "$SCRIPT_DIR/postgresql_information_system_summary.sql" summary
split_queries "$SCRIPT_DIR/postgresql_information_system.sql" combined

fail=0
n=1
while [ "$n" -le "$EXPECTED_QUERIES" ]; do
  q=$(printf '%02d' "$n")
  for v in base row summary combined; do
    psql_in -d "$DB_NAME" -At -F '|' < "$TMP_ROOT/$v/q_$q.sql" > "$TMP_ROOT/$v.out" || die "$v 쿼리 $q 실행 실패"
  done
  lines=$(wc -l < "$TMP_ROOT/base.out" | tr -d ' ')
  res=""
  for v in row summary combined; do
    if cmp -s "$TMP_ROOT/base.out" "$TMP_ROOT/$v.out"; then res="$res $v=같음"; else res="$res $v=다름"; fail=1; cp "$TMP_ROOT/$v.out" "${TMPDIR:-/tmp}/bicycle_query_${q}_$v.out"; fi
  done
  echo "쿼리 $q (${lines}행):$res"
  n=$((n + 1))
done

[ "$fail" -eq 0 ] && echo "==> 모든 쿼리의 결과가 같습니다." || { echo "==> 결과가 다른 쿼리가 있습니다. (다른 쪽 출력은 ${TMPDIR:-/tmp}/bicycle_query_NN_*.out)"; exit 1; }
