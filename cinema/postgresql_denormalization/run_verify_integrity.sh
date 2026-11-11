#!/bin/sh
# v2.1.0 무결성 검증을 한 번에 실행한다. (사용자의 cinema DB 는 건드리지 않음)
#
#   1) 측정용 임시 DB 를 만들고 create_ddl.sql + insert_data.sql 을 적재
#   2) verify_integrity.sql 의 케이스 실행 (결과 열 PASS / FAIL)
#        C01~C14 이용 가능 좌석 수 규칙 / X01~X07 입력 위반 / P01~P02 정상 입력 / S01 총 좌석 수 변경
#        K01~K10 기존 제약 점검 / D01~D05 중복 예매 방지 / B01~B07 예매 규칙
#   3) 동시성 케이스 실행 (세션 2개씩): C15 상영 INSERT 와 좌석 변경의 직렬화, C16 데드락, C18 동시 중복 예매,
#        C19 동시 예매로 이용 가능 좌석 수 초과 시도, C20 좌석 상태 변경과 예매의 경쟁
#   4) STRESS=1 이면 C17 (pgbench 로 상영 수정·좌석 변경·예매·취소를 섞어 데드락 발생 여부) 실행
#   5) PASS / FAIL / ERROR 건수를 요약하고, 하나라도 FAIL 이거나 ERROR 면 종료 코드 1
#
# 사용법: sh cinema/postgresql_denormalization/run_verify_integrity.sh   (어느 디렉터리에서 실행해도 됨)
#   CONTAINER=db-optimization-postgres   PostgreSQL 컨테이너 이름
#   DB=cinema_verify_bench               임시 DB. 매 실행마다 만들고 끝나면 지우므로 이름은 _bench 로 끝나야 한다.
#   KEEP_DB=1                            끝나고 임시 DB 를 지우지 않음 (직접 psql 로 들어가서 확인할 때)
#   STRESS=1                             C17 부하 테스트까지 실행 (기본은 건너뜀)
#   STRESS_SECONDS=10                    부하 테스트 시간(초)
#   REVERT_FIX=1                         데드락 수정(좌석 트리거의 상영 행 선잠금)을 빼고 수정 전 잠금 순서로 적재.
#                                        C16/C17 이 실제로 데드락을 잡아내는지(FAIL 이 나오는지) 확인할 때 쓴다.

set -u

CONTAINER="${CONTAINER:-db-optimization-postgres}"
DB="${DB:-cinema_verify_bench}"
KEEP_DB="${KEEP_DB:-0}"
STRESS="${STRESS:-0}"
STRESS_SECONDS="${STRESS_SECONDS:-10}"
REVERT_FIX="${REVERT_FIX:-0}"
DIR=$(cd "$(dirname "$0")" && pwd)

case "$DB" in
    *_bench) ;;
    *) echo "DB 이름은 _bench 로 끝나야 합니다 (실수로 실제 DB 를 지우지 않기 위함): $DB" >&2; exit 2 ;;
esac

psql_admin() { docker exec -i "$CONTAINER" psql -U postgres -q "$@"; }
psql_db()    { docker exec -i "$CONTAINER" psql -U postgres -q -d "$DB" "$@"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

psql_admin -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB" || exit 2
if [ "$REVERT_FIX" = "1" ]; then
    echo "[REVERT_FIX=1] 좌석 트리거의 '상영 행 선잠금' 줄을 뺀 수정 전 잠금 순서로 적재합니다. C16/C17 은 FAIL 이 나와야 정상입니다."
    sed '/ORDER BY scrn_id FOR UPDATE/d' "$DIR/create_ddl.sql" | psql_db -v ON_ERROR_STOP=1 || { echo "create_ddl.sql 적재 실패" >&2; exit 2; }
else
    psql_db -v ON_ERROR_STOP=1 < "$DIR/create_ddl.sql" || { echo "create_ddl.sql 적재 실패" >&2; exit 2; }
fi
psql_db -v ON_ERROR_STOP=1 < "$DIR/insert_data.sql" || { echo "insert_data.sql 적재 실패" >&2; exit 2; }

# 동시성 케이스 사이에 상태를 되돌린다: 6번 상영관 좌석 전부 Y, 테스트용 상영(V..., S...) 삭제
reset_state() {
    psql_db -c "DELETE FROM tbl_bytk_d1 WHERE scrn_id LIKE 'V%' OR scrn_id LIKE 'S%'; DELETE FROM tbl_scrn_m1 WHERE scrn_id LIKE 'V%' OR scrn_id LIKE 'S%'; UPDATE tbl_seat_m1 SET status = 'Y' WHERE thtr_id = 6;" >/dev/null
}

# C01 ~ C14
OUT=$(psql_db < "$DIR/verify_integrity.sql" 2>&1)
echo "$OUT"
EXTRA=""

# C15 동시성: 세션 A 가 예정 상영을 INSERT 한 채 3초간 커밋을 미루는 동안 세션 B 가 좌석을 N 으로 바꾼다.
#             B 가 기다렸다가 A 의 상영을 보고 이용 가능 좌석 수를 149 로 계산해야 한다.
reset_state
echo
echo "== C15  동시성: 상영 INSERT 미커밋 중 좌석 변경 -> 좌석 변경이 대기, 최종 이용 가능 좌석 수 149"
( psql_db -c "BEGIN; INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime) VALUES ('V00000000099','2026092601',6,150,CURRENT_DATE+30,'10:00'); SELECT pg_sleep(3); COMMIT;" >/dev/null ) &
sleep 1
START=$(date +%s)
psql_db -c "UPDATE tbl_seat_m1 SET status='N' WHERE thtr_id=6 AND seatcode='A1'" >/dev/null
ELAPSED=$(( $(date +%s) - START ))
wait
CAP=$(psql_db -t -A -c "SELECT capacity FROM tbl_scrn_m1 WHERE scrn_id='V00000000099'")
if [ "$CAP" = "149" ] && [ "$ELAPSED" -ge 1 ]; then R=PASS; else R=FAIL; fi
L="좌석 변경 대기 시간 ${ELAPSED}초 (1초 이상이어야 함), 최종 이용 가능 좌석 수 ${CAP} (기대 149)  결과 ${R}"
echo "$L"; EXTRA="$EXTRA
$L"

# C16 데드락: 상영 UPDATE(세션 A)와 같은 상영관의 좌석 변경(세션 B)의 잠금 순서를 일부러 엇갈리게 만든다.
#   t=0  A: 상영 행을 FOR UPDATE 로 잡고 2초 대기
#   t=1  B: 좌석을 N 으로 변경 -> 트리거가 상영 행을 잠그려다 A 에게 막힘 (수정 전에는 상영관 행을 먼저 잡고 상영 행에서 막힘)
#   t=2  A: 같은 행의 계획 좌석 수 UPDATE -> 트리거가 상영관 행 FOR SHARE 를 요청
#   수정 전: 서로를 기다려 데드락, 한쪽이 중단됨 / 수정 후: 둘 다 성공
reset_state
echo
echo "== C16  데드락: 상영 UPDATE 와 같은 상영관 좌석 변경의 잠금 순서를 엇갈리게 -> 둘 다 성공해야 함"
psql_db -c "INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime) VALUES ('V00000000098','2026092601',6,150,CURRENT_DATE+30,'10:00')" >/dev/null
( psql_db -c "BEGIN; SELECT 1 FROM tbl_scrn_m1 WHERE scrn_id='V00000000098' FOR UPDATE; SELECT pg_sleep(2); UPDATE tbl_scrn_m1 SET planned_capacity=100 WHERE scrn_id='V00000000098'; COMMIT;" >"$TMP/A.out" 2>&1; echo $? >"$TMP/A.rc" ) &
sleep 1
( psql_db -c "BEGIN; UPDATE tbl_seat_m1 SET status='N' WHERE thtr_id=6 AND seatcode='A1'; COMMIT;" >"$TMP/B.out" 2>&1; echo $? >"$TMP/B.rc" ) &
wait
A_RC=$(cat "$TMP/A.rc"); B_RC=$(cat "$TMP/B.rc")
DL=$(cat "$TMP/A.out" "$TMP/B.out" | grep -c 'deadlock detected')
CAP=$(psql_db -t -A -c "SELECT capacity FROM tbl_scrn_m1 WHERE scrn_id='V00000000098'")
SEAT=$(psql_db -t -A -c "SELECT status FROM tbl_seat_m1 WHERE thtr_id=6 AND seatcode='A1'")
if [ "$DL" = "0" ] && [ "$A_RC" = "0" ] && [ "$B_RC" = "0" ] && [ "$CAP" = "100" ] && [ "$SEAT" = "N" ]; then R=PASS; else R=FAIL; fi
L="데드락 ${DL}건, 세션 A 종료코드 ${A_RC}, 세션 B 종료코드 ${B_RC}, 최종 이용 가능 좌석 수 ${CAP} (기대 100), 좌석 A1 상태 ${SEAT} (기대 N)  결과 ${R}"
echo "$L"; EXTRA="$EXTRA
$L"
[ "$DL" != "0" ] && cat "$TMP/A.out" "$TMP/B.out" | grep -E 'ERROR|DETAIL' | head -n 3 | sed 's/^/    /'

# C18 동시 중복 예매: 두 세션이 같은 상영의 같은 좌석(A5)을 거의 동시에 예매한다.
#   t=0  A: 예매 INSERT 후 커밋하지 않고 2초 대기
#   t=1  B: 같은 좌석 예매 INSERT -> A 가 끝날 때까지 기다렸다가 중복으로 거부되어야 한다 (UNIQUE 인덱스가 직렬화)
#   결과: 예매는 정확히 1건, 한쪽은 성공 / 한쪽은 duplicate key 로 실패
reset_state
echo
echo "== C18  동시 중복 예매: 두 세션이 같은 상영의 같은 좌석을 동시에 예매 -> 정확히 1건만 성공"
psql_db -c "INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime) VALUES ('V00000000097','2026092601',6,150,CURRENT_DATE+30,'10:00')" >/dev/null
INS="INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, seatcode, buy_method, savings, mileage) VALUES ((SELECT mebr_id FROM tbl_mebr_m1 ORDER BY mebr_id LIMIT 1), 'V00000000097', 6, 'A5', 'P', 0, 0)"
( psql_db -c "BEGIN; $INS; SELECT pg_sleep(2); COMMIT;" >"$TMP/A.out" 2>&1; echo $? >"$TMP/A.rc" ) &
sleep 1
( psql_db -c "$INS" >"$TMP/B.out" 2>&1; echo $? >"$TMP/B.rc" ) &
wait
A_RC=$(cat "$TMP/A.rc"); B_RC=$(cat "$TMP/B.rc")
DUP=$(cat "$TMP/A.out" "$TMP/B.out" | grep -c 'duplicate key')
CNT=$(psql_db -t -A -c "SELECT count(*) FROM tbl_bytk_d1 WHERE scrn_id='V00000000097' AND seatcode='A5'")
if [ "$CNT" = "1" ] && [ "$A_RC" = "0" ] && [ "$B_RC" != "0" ] && [ "$DUP" = "1" ]; then R=PASS; else R=FAIL; fi
L="A5 예매 ${CNT}건 (기대 1), 세션 A 종료코드 ${A_RC} (기대 0), 세션 B 종료코드 ${B_RC} (기대 0 아님), duplicate key ${DUP}건 (기대 1)  결과 ${R}"
echo "$L"; EXTRA="$EXTRA
$L"

# C19 동시 예매로 이용 가능 좌석 수 초과 시도: 이용 가능 좌석 수 1 인 상영에 두 세션이 동시에 예매한다.
#   t=0  A: 예매 INSERT 후 커밋하지 않고 2초 대기
#   t=1  B: 예매 INSERT -> 상영 행 잠금에서 기다렸다가 A 가 커밋하면 이용 가능 좌석 수 초과(23514)로 거부되어야 한다
#   잠금이 없으면 둘 다 이용 가능 좌석 수 검사를 통과해 예매가 2건 저장된다.
reset_state
echo
echo "== C19  동시 예매로 이용 가능 좌석 수 초과 시도: 이용 가능 좌석 수 1 상영에 두 세션이 동시에 예매 -> 정확히 1건만 성공"
psql_db -c "INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime) VALUES ('V00000000096','2026092601',6,1,CURRENT_DATE+30,'10:00')" >/dev/null
INS="INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, buy_method, savings, mileage) VALUES ((SELECT mebr_id FROM tbl_mebr_m1 ORDER BY mebr_id LIMIT 1), 'V00000000096', 6, 'P', 0, 0)"
( psql_db -c "BEGIN; $INS; SELECT pg_sleep(2); COMMIT;" >"$TMP/A.out" 2>&1; echo $? >"$TMP/A.rc" ) &
sleep 1
( psql_db -v VERBOSITY=verbose -c "$INS" >"$TMP/B.out" 2>&1; echo $? >"$TMP/B.rc" ) &
wait
A_RC=$(cat "$TMP/A.rc"); B_RC=$(cat "$TMP/B.rc")
CHK=$(grep -c '23514' "$TMP/B.out")
CNT=$(psql_db -t -A -c "SELECT count(*) FROM tbl_bytk_d1 WHERE scrn_id='V00000000096'")
if [ "$CNT" = "1" ] && [ "$A_RC" = "0" ] && [ "$B_RC" != "0" ] && [ "$CHK" = "1" ]; then R=PASS; else R=FAIL; fi
L="예매 ${CNT}건 (기대 1), 세션 A 종료코드 ${A_RC} (기대 0), 세션 B 종료코드 ${B_RC} (기대 0 아님), 이용 가능 좌석 수 초과(23514) ${CHK}건 (기대 1)  결과 ${R}"
echo "$L"; EXTRA="$EXTRA
$L"

# C20 좌석 상태 변경과 예매의 경쟁 (두 방향)
#   C20a: A 가 좌석 A7 을 예매한 채 커밋하지 않고, B 가 같은 좌석을 이용 불가(N)로 바꾼다 -> B 는 기다렸다가 거부되어야 한다
#   C20b: A 가 좌석 A8 을 이용 불가(N)로 바꾼 채 커밋하지 않고, B 가 같은 좌석을 예매한다 -> B 는 기다렸다가 거부되어야 한다
#   잠금이 없으면 이용 불가 좌석에 예매가 저장된다.
reset_state
echo
echo "== C20a 좌석 예매(미커밋) 중 같은 좌석을 이용 불가로 변경 -> 변경 거부, 좌석은 Y 로 유지, 예매 1건"
psql_db -c "INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime) VALUES ('V00000000095','2026092601',6,150,CURRENT_DATE+30,'10:00')" >/dev/null
INS="INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, seatcode, buy_method, savings, mileage) VALUES ((SELECT mebr_id FROM tbl_mebr_m1 ORDER BY mebr_id LIMIT 1), 'V00000000095', 6, 'A7', 'P', 0, 0)"
( psql_db -c "BEGIN; $INS; SELECT pg_sleep(2); COMMIT;" >"$TMP/A.out" 2>&1; echo $? >"$TMP/A.rc" ) &
sleep 1
( psql_db -v VERBOSITY=verbose -c "UPDATE tbl_seat_m1 SET status='N' WHERE thtr_id=6 AND seatcode='A7'" >"$TMP/B.out" 2>&1; echo $? >"$TMP/B.rc" ) &
wait
A_RC=$(cat "$TMP/A.rc"); B_RC=$(cat "$TMP/B.rc"); CHK=$(grep -c '23514' "$TMP/B.out")
CNT=$(psql_db -t -A -c "SELECT count(*) FROM tbl_bytk_d1 WHERE scrn_id='V00000000095' AND seatcode='A7'")
ST=$(psql_db -t -A -c "SELECT status FROM tbl_seat_m1 WHERE thtr_id=6 AND seatcode='A7'")
if [ "$CNT" = "1" ] && [ "$ST" = "Y" ] && [ "$A_RC" = "0" ] && [ "$B_RC" != "0" ] && [ "$CHK" = "1" ]; then R=PASS; else R=FAIL; fi
L="예매 ${CNT}건 (기대 1), 좌석 A7 상태 ${ST} (기대 Y), 세션 A 종료코드 ${A_RC}, 세션 B 종료코드 ${B_RC} (기대 0 아님), 거부(23514) ${CHK}건 (기대 1)  결과 ${R}"
echo "$L"; EXTRA="$EXTRA
$L"

reset_state
echo
echo "== C20b 좌석을 이용 불가로 변경(미커밋) 중 같은 좌석을 예매 -> 예매 거부, 좌석은 N, 예매 0건"
psql_db -c "INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime) VALUES ('V00000000094','2026092601',6,150,CURRENT_DATE+30,'10:00')" >/dev/null
INS="INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, seatcode, buy_method, savings, mileage) VALUES ((SELECT mebr_id FROM tbl_mebr_m1 ORDER BY mebr_id LIMIT 1), 'V00000000094', 6, 'A8', 'P', 0, 0)"
( psql_db -c "BEGIN; UPDATE tbl_seat_m1 SET status='N' WHERE thtr_id=6 AND seatcode='A8'; SELECT pg_sleep(2); COMMIT;" >"$TMP/A.out" 2>&1; echo $? >"$TMP/A.rc" ) &
sleep 1
( psql_db -v VERBOSITY=verbose -c "$INS" >"$TMP/B.out" 2>&1; echo $? >"$TMP/B.rc" ) &
wait
A_RC=$(cat "$TMP/A.rc"); B_RC=$(cat "$TMP/B.rc"); CHK=$(grep -c '23514' "$TMP/B.out")
CNT=$(psql_db -t -A -c "SELECT count(*) FROM tbl_bytk_d1 WHERE scrn_id='V00000000094' AND seatcode='A8'")
ST=$(psql_db -t -A -c "SELECT status FROM tbl_seat_m1 WHERE thtr_id=6 AND seatcode='A8'")
if [ "$CNT" = "0" ] && [ "$ST" = "N" ] && [ "$A_RC" = "0" ] && [ "$B_RC" != "0" ] && [ "$CHK" = "1" ]; then R=PASS; else R=FAIL; fi
L="예매 ${CNT}건 (기대 0), 좌석 A8 상태 ${ST} (기대 N), 세션 A 종료코드 ${A_RC}, 세션 B 종료코드 ${B_RC} (기대 0 아님), 거부(23514) ${CHK}건 (기대 1)  결과 ${R}"
echo "$L"; EXTRA="$EXTRA
$L"

# C17 부하 테스트 (선택): 상영 UPDATE 와 좌석 변경을 여러 세션이 섞어 실행하며 데드락 실패 건수를 센다.
if [ "$STRESS" = "1" ]; then
    reset_state
    echo
    echo "== C17  부하 테스트: 8세션이 ${STRESS_SECONDS}초간 상영 UPDATE·좌석 변경·예매·취소를 섞어 실행 -> 데드락 0건, 정합성 불일치 0건"
    psql_db -c "INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
                SELECT 'S0000000000' || g, '2026092601', 6, 150, CURRENT_DATE + 30, make_time(8 + g, 0, 0) FROM generate_series(1, 5) g" >/dev/null
    docker exec -i "$CONTAINER" sh -c 'cat > /tmp/verify_stress_scrn.sql' <<'EOF'
\set sid random(1,5)
\set cap random(100,150)
UPDATE tbl_scrn_m1 SET planned_capacity = :cap WHERE scrn_id = 'S0000000000' || :sid::text;
EOF
    # 예매·좌석 변경은 규칙 위반(check_violation, unique_violation)으로 거부되는 것이 정상이므로 함수로 감싸 무시한다.
    # 데드락(deadlock_detected)은 일부러 잡지 않아 pgbench 가 "데드락 실패" 로 센다.
    psql_db -c "
        CREATE FUNCTION verify_try_book(p_scrn text, p_seat text) RETURNS void AS \$\$
        BEGIN
            INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, seatcode, buy_method, savings, mileage)
            VALUES ((SELECT mebr_id FROM tbl_mebr_m1 ORDER BY mebr_id LIMIT 1), p_scrn, 6, p_seat, 'P', 0, 0);
        EXCEPTION WHEN check_violation OR unique_violation THEN NULL;
        END; \$\$ LANGUAGE plpgsql;
        CREATE FUNCTION verify_try_toggle(p_seat text) RETURNS void AS \$\$
        BEGIN
            UPDATE tbl_seat_m1 SET status = CASE status WHEN 'Y' THEN 'N' ELSE 'Y' END WHERE thtr_id = 6 AND seatcode = p_seat;
        EXCEPTION WHEN check_violation THEN NULL;
        END; \$\$ LANGUAGE plpgsql;" >/dev/null
    docker exec -i "$CONTAINER" sh -c 'cat > /tmp/verify_stress_seat.sql' <<'EOF'
\set k random(1,15)
SELECT verify_try_toggle('A' || :k::text);
EOF
    docker exec -i "$CONTAINER" sh -c 'cat > /tmp/verify_stress_book.sql' <<'EOF'
\set sid random(1,5)
\set k random(1,15)
SELECT verify_try_book('S0000000000' || :sid::text, 'A' || :k::text);
EOF
    docker exec -i "$CONTAINER" sh -c 'cat > /tmp/verify_stress_cancel.sql' <<'EOF'
\set sid random(1,5)
\set k random(1,15)
DELETE FROM tbl_bytk_d1 WHERE scrn_id = 'S0000000000' || :sid::text AND seatcode = 'A' || :k::text;
EOF
    PGB=$(docker exec "$CONTAINER" pgbench -U postgres -n -c 8 -j 2 -T "$STRESS_SECONDS" --failures-detailed \
          -f /tmp/verify_stress_scrn.sql@1 -f /tmp/verify_stress_seat.sql@1 \
          -f /tmp/verify_stress_book.sql@2 -f /tmp/verify_stress_cancel.sql@1 "$DB" 2>&1)
    docker exec "$CONTAINER" rm -f /tmp/verify_stress_scrn.sql /tmp/verify_stress_seat.sql /tmp/verify_stress_book.sql /tmp/verify_stress_cancel.sql
    DONE=$(echo "$PGB" | awk '/^number of transactions actually processed/{print $6}')
    DLF=$(echo "$PGB"  | awk '/^number of deadlock failures/{print $5}')
    BAD=$(psql_db -t -A -c "SELECT count(*) FROM tbl_scrn_m1 s WHERE s.scrn_id LIKE 'S%'
          AND s.capacity <> LEAST(s.planned_capacity, (SELECT count(*) FROM tbl_seat_m1 WHERE thtr_id = 6 AND status = 'Y'))")
    # 부하 후 예매 규칙 위반: 이용 가능 좌석 수를 넘는 예매 수, 예정 상영에서 이용 불가 좌석에 걸린 예매
    BOOK_BAD=$(psql_db -t -A -c "SELECT
        (SELECT count(*) FROM tbl_scrn_m1 s WHERE s.scrn_id LIKE 'S%'
           AND (SELECT count(*) FROM tbl_bytk_d1 b WHERE b.scrn_id = s.scrn_id) > s.capacity)
      + (SELECT count(*) FROM tbl_bytk_d1 b JOIN tbl_seat_m1 st ON st.thtr_id = b.thtr_id AND st.seatcode = b.seatcode
          WHERE b.scrn_id LIKE 'S%' AND st.status = 'N')")
    if [ "${DLF:-x}" = "0" ] && [ "$BAD" = "0" ] && [ "$BOOK_BAD" = "0" ]; then R=PASS; else R=FAIL; fi
    L="처리 ${DONE:-?}건, 데드락 실패 ${DLF:-?}건, capacity 불일치 ${BAD}건, 예매 규칙 위반 ${BOOK_BAD}건  결과 ${R}"
    echo "$L"; EXTRA="$EXTRA
$L"
fi
reset_state

# 요약
PASS=$(printf '%s\n%s\n' "$OUT" "$EXTRA" | grep -c -w PASS)
FAIL=$(printf '%s\n%s\n' "$OUT" "$EXTRA" | grep -c -w FAIL)
ERR=$(printf '%s\n' "$OUT" | grep -c 'ERROR')
echo
echo "========== 요약: PASS ${PASS}건 / FAIL ${FAIL}건 / 예상 밖 ERROR ${ERR}건 =========="

if [ "$KEEP_DB" != "1" ]; then
    psql_admin -c "DROP DATABASE IF EXISTS $DB"
fi

[ "$FAIL" -eq 0 ] && [ "$ERR" -eq 0 ]
