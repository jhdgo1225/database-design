-- v2.1.0 무결성 검증 케이스 (이용 가능 좌석 수 반영)
--
-- 전제: create_ddl.sql 과 insert_data.sql 이 적재된 DB 에서 실행한다. (한 번에 실행: run_verify_integrity.sh)
--   psql -d <DB> -f verify_integrity.sql
--
-- 모든 케이스는 BEGIN ... ROLLBACK 안에서 실행하므로 데이터가 남지 않는다.
-- 결과 열이 PASS 면 기대대로 동작한 것이고, FAIL 이면 규칙이 깨진 것이다.
--
-- 케이스에서 쓰는 데이터
--   * 6번 상영관: 총 150석, 좌석코드 A1, A2 ... (전부 'Y')
--   * 7번 상영관: 예정 상영 없음 (샘플 상영은 전부 2026-10 이라 지난 상영)
--   * '202610100601': 6번 상영관의 지난 상영 (이용 가능 좌석 수 150)
--   * 예정 상영은 CURRENT_DATE + 30 일로 직접 만들어 쓴다. scrn_id 는 'V' 로 시작하는 12자리.
--
-- 하나씩 직접 실행해 보고 싶으면 케이스 블록(BEGIN 부터 ROLLBACK 까지)을 복사하되,
-- 아래 도우미 함수 8개(pg_temp.show, reject, accept, val, sql_mebr, sql_bytk, sql_scmv, sql_mngr)를 먼저 같은 세션에서 만들어야 한다.
--
-- 케이스 번호
--   C01~C14  v2.1.0 이용 가능 좌석 수 규칙 (좌석 상태 -> 상영의 이용 가능 좌석 수, 지난·상영 중 상영, 예매 충돌, 기본 제약)
--   X01~X07  입력 위반 케이스: 반정규화 전 스키마에서는 통과하던 잘못된 입력 7건이 거부(또는 무력화)되는지
--              X01~X02 금액·결제수단 불일치 / X03~X04 다른 상영관 좌석 예매 / X05~X06 상영의 이용 가능 좌석 수 임의 값 / X07 출연 중복
--   P01~P02  정상 입력은 과도하게 막히지 않는지 (미결제·좌석 미지정 전화 예약, 결제수단별 정상 예매)
--   S01      상영관 총 좌석 수 변경이 상영의 이용 가능 좌석 수에 미치는 영향 (v2.0.0 의 전파 -> v2.1.0 의 차단으로 바뀐 동작)
--   K01~K10  기존 제약 점검: 회원·인물·예매·충전 CHECK, 필수값, 길이, FK 존재, PK 중복, ON DELETE RESTRICT, ON UPDATE CASCADE
--   D01~D05  중복 예매 방지: 같은 상영의 같은 좌석은 한 번만 예매할 수 있음 (UNIQUE (scrn_id, seatcode))
--   B01~B07  예매 규칙: 이용 불가 좌석 예매 거부(예정 상영), 이용 가능 좌석 수 초과 예매 거부(모든 상영), 예매 UPDATE, 계획 좌석 수 하향 제한
--   F01~F06  값 형식: 영화 코드값(status I/S/D, agerating A/T/F/N)·날짜·숫자, 충전 금액, 회원·관리자 전화번호·이메일
--   (동시성 C15~C20 은 run_verify_integrity.sh)

-- ---------------------------------------------------------------------
-- 도우미 함수 (이 세션에서만 존재)
-- ---------------------------------------------------------------------

-- 상영의 이용 가능 좌석 수가 기대값과 같은지 보여준다.
CREATE FUNCTION pg_temp.show(p_step text, p_scrn text, p_expected int)
RETURNS TABLE("단계" text, "계획좌석수" int, "이용가능좌석수" int, "기대" int, "결과" text) AS $$
BEGIN
    RETURN QUERY
    SELECT p_step, s.planned_capacity, s.capacity, p_expected,
           CASE WHEN s.capacity = p_expected THEN 'PASS' ELSE 'FAIL' END
    FROM tbl_scrn_m1 AS s
    WHERE s.scrn_id = p_scrn;
    IF NOT FOUND THEN
        RETURN QUERY SELECT p_step, NULL::int, NULL::int, p_expected, 'FAIL (상영 행 없음)'::text;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- SQL 문이 기대한 에러코드로 거부되는지 보여준다. (통과해 버리면 FAIL)
--   23514 = check_violation, 23503 = foreign_key_violation
CREATE FUNCTION pg_temp.reject(p_step text, p_sql text, p_state text)
RETURNS TABLE("단계" text, "기대 에러코드" text, "결과" text, "에러 메시지" text) AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY
        SELECT p_step, p_state,
               CASE WHEN SQLSTATE = p_state THEN 'PASS' ELSE 'FAIL' END,
               SQLERRM;
        RETURN;
    END;
    RETURN QUERY SELECT p_step, p_state, 'FAIL'::text, '거부되지 않고 통과함'::text;
END;
$$ LANGUAGE plpgsql;

-- SQL 문이 에러 없이 저장되는지 보여준다. (거부되면 FAIL) 정상 입력이 과도하게 막히지 않는지 확인하는 용도
CREATE FUNCTION pg_temp.accept(p_step text, p_sql text)
RETURNS TABLE("단계" text, "결과" text, "에러 메시지" text) AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT p_step, 'FAIL'::text, SQLERRM;
        RETURN;
    END;
    RETURN QUERY SELECT p_step, 'PASS'::text, '정상 저장됨'::text;
END;
$$ LANGUAGE plpgsql;

-- 값 비교
CREATE FUNCTION pg_temp.val(p_step text, p_actual bigint, p_expected bigint)
RETURNS TABLE("단계" text, "실제" bigint, "기대" bigint, "결과" text) AS $$
    SELECT p_step, p_actual, p_expected,
           CASE WHEN p_actual IS NOT DISTINCT FROM p_expected THEN 'PASS' ELSE 'FAIL' END;
$$ LANGUAGE sql;

-- 회원 INSERT 문을 만든다. 기본값은 모두 유효한 값이라서 검사하려는 항목만 바꿔 넘기면 된다.
--   예) pg_temp.sql_mebr(p_sex => 'X')   p_rating 에 'DEFAULT' 를 넘기면 rating 컬럼 기본값을 쓴다.
CREATE FUNCTION pg_temp.sql_mebr(
    p_id text DEFAULT 'kuser01', p_sex text DEFAULT 'M', p_savings int DEFAULT 0, p_mileage int DEFAULT 0,
    p_rating text DEFAULT '3', p_name text DEFAULT '홍길동', p_passwd text DEFAULT 'pw',
    p_phone text DEFAULT '01012345678', p_email text DEFAULT 'k@example.com')
RETURNS text AS $$
    SELECT format($f$INSERT INTO tbl_mebr_m1(mebr_id, passwd, name, birth, sex, phone, email, savings, mileage, rating)
                     VALUES (%L, %L, %L, DATE '2000-01-01', %L, %L, %L, %s, %s, %s)$f$,
                  p_id, p_passwd, p_name, p_sex, p_phone, p_email, p_savings, p_mileage, p_rating);
$$ LANGUAGE sql;

-- 영화 INSERT 문을 만든다. 기본값은 유효한 값(상영예정, 전체 관람가, 100분, 요금 8000, 종료일 미정)이다.
--   p_id 를 생략하면 호출마다 다른 ID 가 만들어진다. p_fee, p_end 에 NULL 을 넘기면 NULL 로 저장한다.
CREATE FUNCTION pg_temp.sql_scmv(
    p_id text DEFAULT substr(md5(random()::text), 1, 10), p_status text DEFAULT 'S', p_age text DEFAULT 'A',
    p_playtime int DEFAULT 100, p_fee text DEFAULT '8000', p_start text DEFAULT '2026-11-01', p_end text DEFAULT NULL,
    p_title text DEFAULT 'fmt test')
RETURNS text AS $$
    SELECT format($f$INSERT INTO tbl_scmv_m1(scmv_id, title, summary, playtime, agerating, startdate, enddate, fee, status)
                     VALUES (%L, %L, 's', %s, %L, DATE %L, %s, %s, %L)$f$,
                  p_id, p_title, p_playtime, p_age, p_start,
                  CASE WHEN p_end IS NULL THEN 'NULL' ELSE format('DATE %L', p_end) END,
                  COALESCE(p_fee, 'NULL'), p_status);
$$ LANGUAGE sql;

-- 관리자 INSERT 문을 만든다. 기본값은 유효한 값이다.
CREATE FUNCTION pg_temp.sql_mngr(
    p_id text DEFAULT 'mgr' || substr(md5(random()::text), 1, 8),
    p_phone text DEFAULT '01012345678', p_email text DEFAULT 'm@example.com')
RETURNS text AS $$
    SELECT format($f$INSERT INTO tbl_mngr_m1(mngr_id, passwd, name, phone, birth, email)
                     VALUES (%L, 'pw', '관리자', %L, DATE '1990-01-01', %L)$f$, p_id, p_phone, p_email);
$$ LANGUAGE sql;

-- 예매 INSERT 문을 만든다. 기본값은 "좌석 미지정 전화 예약(미결제)" 이고, 검사하려는 항목만 바꿔 넘긴다.
--   예) pg_temp.sql_bytk('V00000000051', p_buy => 'O')   p_buydate 에 'now' 를 넘기면 현재 시각, NULL 이면 NULL
--   p_mebr 를 생략하면 샘플 회원 한 명을 쓴다.
CREATE FUNCTION pg_temp.sql_bytk(
    p_scrn text, p_seat text DEFAULT NULL, p_buy text DEFAULT 'P', p_pay text DEFAULT NULL, p_buydate text DEFAULT NULL,
    p_savings int DEFAULT 0, p_mileage int DEFAULT 0, p_thtr int DEFAULT 6, p_mebr text DEFAULT NULL)
RETURNS text AS $$
    SELECT format($f$INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, seatcode, buy_method, pay_method, buydate, savings, mileage)
                     VALUES (COALESCE(%L, (SELECT mebr_id FROM tbl_mebr_m1 ORDER BY mebr_id LIMIT 1)), %L, %s, %L, %L, %L, %s, %s, %s)$f$,
                  p_mebr, p_scrn, p_thtr, p_seat, p_buy, p_pay,
                  CASE WHEN p_buydate IS NULL THEN 'NULL' ELSE quote_literal(p_buydate) || '::timestamptz' END,
                  p_savings, p_mileage);
$$ LANGUAGE sql;

-- ---------------------------------------------------------------------
-- C01  예정 상영: 이용 불가 좌석이 이용 가능 좌석 수에 반영되고, 복구되면 되돌아온다
--      기대: 150 -> (좌석 10개 N) 140 -> (전부 Y) 150
-- ---------------------------------------------------------------------
\echo
\echo '== C01  예정 상영 150 -> 좌석 10개 이용 불가 -> 140 -> 복구 -> 150'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000001', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.show('처음', 'V00000000001', 150);

UPDATE tbl_seat_m1 SET status = 'N'
 WHERE thtr_id = 6 AND seatcode IN (SELECT seatcode FROM tbl_seat_m1 WHERE thtr_id = 6 ORDER BY seatcode LIMIT 10);
SELECT * FROM pg_temp.show('좌석 10개 N', 'V00000000001', 140);

UPDATE tbl_seat_m1 SET status = 'Y' WHERE thtr_id = 6;
SELECT * FROM pg_temp.show('전부 Y 로 복구', 'V00000000001', 150);
ROLLBACK;

-- ---------------------------------------------------------------------
-- C02  관리자가 정한 계획 좌석 수(120)는 보존된다
--      기대: 이용 가능 140 -> 120 유지, 이용 가능 100 -> 100, 복구 -> 120 (150 으로 올라가지 않음)
-- ---------------------------------------------------------------------
\echo
\echo '== C02  계획 좌석 수 120 보존'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000002', '2026092601', 6, 120, CURRENT_DATE + 30, '10:00');

UPDATE tbl_seat_m1 SET status = 'N'
 WHERE thtr_id = 6 AND seatcode IN (SELECT seatcode FROM tbl_seat_m1 WHERE thtr_id = 6 ORDER BY seatcode LIMIT 10);
SELECT * FROM pg_temp.show('이용 가능 140', 'V00000000002', 120);

UPDATE tbl_seat_m1 SET status = 'N'
 WHERE thtr_id = 6 AND seatcode IN (SELECT seatcode FROM tbl_seat_m1 WHERE thtr_id = 6 AND status = 'Y' ORDER BY seatcode LIMIT 40);
SELECT * FROM pg_temp.show('이용 가능 100', 'V00000000002', 100);

UPDATE tbl_seat_m1 SET status = 'Y' WHERE thtr_id = 6;
SELECT * FROM pg_temp.show('전부 Y 로 복구', 'V00000000002', 120);
ROLLBACK;

-- ---------------------------------------------------------------------
-- C03  계획 좌석 수 수정이 예정 상영에 즉시 반영, 좌석이 N 인 상태에서 만든 상영도 제한됨
-- ---------------------------------------------------------------------
\echo
\echo '== C03  좌석 10개 N 상태에서 상영 INSERT -> 140, 계획 좌석 수 100 으로 수정 -> 100'
BEGIN;
UPDATE tbl_seat_m1 SET status = 'N'
 WHERE thtr_id = 6 AND seatcode IN (SELECT seatcode FROM tbl_seat_m1 WHERE thtr_id = 6 ORDER BY seatcode LIMIT 10);
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000003', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.show('INSERT (희망 150)', 'V00000000003', 140);

UPDATE tbl_scrn_m1 SET planned_capacity = 100 WHERE scrn_id = 'V00000000003';
SELECT * FROM pg_temp.show('계획 좌석 수 100 으로 수정', 'V00000000003', 100);
ROLLBACK;

-- ---------------------------------------------------------------------
-- C04  계획 좌석 수가 상영관 총 좌석 수(150)를 넘으면 거부 (INSERT / UPDATE)
-- ---------------------------------------------------------------------
\echo
\echo '== C04  계획 좌석 수 151 > 총 좌석 수 150 거부'
BEGIN;
SELECT * FROM pg_temp.reject('INSERT 151',
    $q$INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
       VALUES ('V00000000004', '2026092601', 6, 151, CURRENT_DATE + 30, '10:00')$q$, '23514');

INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000004', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.reject('UPDATE 151',
    $q$UPDATE tbl_scrn_m1 SET planned_capacity = 151 WHERE scrn_id = 'V00000000004'$q$, '23514');
ROLLBACK;

-- ---------------------------------------------------------------------
-- C05  capacity 는 직접 쓸 수 없다 (입력한 값은 무시되고 계산값이 유지됨)
-- ---------------------------------------------------------------------
\echo
\echo '== C05  capacity 직접 입력(9999) 무시: 예정 INSERT / 예정 UPDATE / 지난 상영 UPDATE'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, capacity, scrndate, scrntime)
VALUES ('V00000000005', '2026092601', 6, 150, 9999, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.show('예정 INSERT capacity=9999', 'V00000000005', 150);

UPDATE tbl_scrn_m1 SET capacity = 9999 WHERE scrn_id = 'V00000000005';
SELECT * FROM pg_temp.show('예정 UPDATE capacity=9999', 'V00000000005', 150);

UPDATE tbl_scrn_m1 SET capacity = 9999 WHERE scrn_id = '202610100601';
SELECT * FROM pg_temp.show('지난 상영 UPDATE capacity=9999', '202610100601', 150);
ROLLBACK;

-- ---------------------------------------------------------------------
-- C06  지난 상영은 좌석 상태가 바뀌어도 이용 가능 좌석 수가 변하지 않는다
-- ---------------------------------------------------------------------
\echo
\echo '== C06  지난 상영: 좌석 10개를 N 으로 바꿔도 이용 가능 좌석 수 150 유지'
BEGIN;
UPDATE tbl_seat_m1 SET status = 'N'
 WHERE thtr_id = 6 AND seatcode IN (SELECT seatcode FROM tbl_seat_m1 WHERE thtr_id = 6 ORDER BY seatcode LIMIT 10);
SELECT * FROM pg_temp.show('지난 상영 202610100601', '202610100601', 150);
SELECT * FROM pg_temp.val('6번 상영관 지난 상영 중 이용 가능 좌석 수가 150 이 아닌 행',
    (SELECT count(*) FROM tbl_scrn_m1 WHERE thtr_id = 6 AND capacity <> 150), 0);
ROLLBACK;

-- ---------------------------------------------------------------------
-- C07  지난 상영 INSERT 는 현재 좌석 상태와 무관하게 계획 좌석 수를 그대로 기록
--      지난 상영도 총 좌석 수 초과는 거부, 다른 컬럼 수정 시 이용 가능 좌석 수 유지
-- ---------------------------------------------------------------------
\echo
\echo '== C07  지난 상영 INSERT (좌석 10개 N 상태) -> 150, 151 거부, 시간 수정 후에도 150'
BEGIN;
UPDATE tbl_seat_m1 SET status = 'N'
 WHERE thtr_id = 6 AND seatcode IN (SELECT seatcode FROM tbl_seat_m1 WHERE thtr_id = 6 ORDER BY seatcode LIMIT 10);
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000007', '2026092601', 6, 150, DATE '2020-01-01', '10:00');
SELECT * FROM pg_temp.show('지난 상영 INSERT', 'V00000000007', 150);

SELECT * FROM pg_temp.reject('지난 상영 계획 좌석 수 151',
    $q$UPDATE tbl_scrn_m1 SET planned_capacity = 151 WHERE scrn_id = 'V00000000007'$q$, '23514');

UPDATE tbl_scrn_m1 SET scrntime = '11:00' WHERE scrn_id = 'V00000000007';
SELECT * FROM pg_temp.show('상영 시간 수정 후', 'V00000000007', 150);
ROLLBACK;

-- ---------------------------------------------------------------------
-- C08  상영 중(이미 시작한) 상영은 지난 상영과 같이 취급, 곧 시작할 상영은 예정 상영
-- ---------------------------------------------------------------------
\echo
\echo '== C08  1분 전 시작한(상영 중) 상영은 이용 가능 좌석 수 150 유지 / 1시간 뒤 시작할 상영은 140'
BEGIN;
UPDATE tbl_seat_m1 SET status = 'N'
 WHERE thtr_id = 6 AND seatcode IN (SELECT seatcode FROM tbl_seat_m1 WHERE thtr_id = 6 ORDER BY seatcode LIMIT 10);
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000008', '2026092601', 6, 150,
        (LOCALTIMESTAMP - INTERVAL '1 minute')::date, (LOCALTIMESTAMP - INTERVAL '1 minute')::time),
       ('V00000000018', '2026092601', 6, 150,
        (LOCALTIMESTAMP + INTERVAL '1 hour')::date,  (LOCALTIMESTAMP + INTERVAL '1 hour')::time);
SELECT * FROM pg_temp.show('상영 중 (좌석 10개 N 상태에서 INSERT)', 'V00000000008', 150);
SELECT * FROM pg_temp.show('1시간 뒤 시작 (예정 상영)',             'V00000000018', 140);

UPDATE tbl_seat_m1 SET status = 'N'
 WHERE thtr_id = 6 AND seatcode IN (SELECT seatcode FROM tbl_seat_m1 WHERE thtr_id = 6 AND status = 'Y' ORDER BY seatcode LIMIT 5);
SELECT * FROM pg_temp.show('좌석 5개 더 N -> 상영 중은 변화 없음', 'V00000000008', 150);
SELECT * FROM pg_temp.show('좌석 5개 더 N -> 예정 상영은 135',     'V00000000018', 135);
ROLLBACK;

-- ---------------------------------------------------------------------
-- C09  예정 상영에서 이미 예매된 좌석은 이용 불가로 바꿀 수 없다
-- ---------------------------------------------------------------------
\echo
\echo '== C09  예매된 좌석 A1 -> N 거부, 예매 안 된 좌석 A2 -> N 허용(이용 가능 좌석 수 149)'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000009', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, seatcode, buy_method, savings, mileage)
VALUES ((SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1), 'V00000000009', 6, 'A1', 'P', 0, 0);

SELECT * FROM pg_temp.reject('예매된 좌석 A1 -> N',
    $q$UPDATE tbl_seat_m1 SET status = 'N' WHERE thtr_id = 6 AND seatcode = 'A1'$q$, '23514');

UPDATE tbl_seat_m1 SET status = 'N' WHERE thtr_id = 6 AND seatcode = 'A2';
SELECT * FROM pg_temp.show('예매 안 된 좌석 A2 -> N', 'V00000000009', 149);
ROLLBACK;

-- ---------------------------------------------------------------------
-- C10  예매 수가 새 이용 가능 좌석 수를 넘게 되는 좌석 변경은 거부 (좌석 미지정 전화 예매 150건)
-- ---------------------------------------------------------------------
\echo
\echo '== C10  예매 150건 / 이용 가능 좌석 수 150 에서 좌석 1개 N 거부, 이용 가능 좌석 수 150 유지'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000010', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, seatcode, buy_method, savings, mileage)
SELECT (SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1), 'V00000000010', 6, NULL, 'P', 0, 0
FROM generate_series(1, 150);

SELECT * FROM pg_temp.reject('좌석 A1 -> N (예매 150 > 새 이용 가능 좌석 수 149)',
    $q$UPDATE tbl_seat_m1 SET status = 'N' WHERE thtr_id = 6 AND seatcode = 'A1'$q$, '23514');
SELECT * FROM pg_temp.show('거부 후 이용 가능 좌석 수', 'V00000000010', 150);
ROLLBACK;

-- ---------------------------------------------------------------------
-- C11  상영관 총 좌석 수 축소 보호
-- ---------------------------------------------------------------------
\echo
\echo '== C11  예정 상영의 계획 좌석 수(150)보다 작게 줄이면 거부, 예정 상영 없는 상영관은 축소 가능'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000011', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.reject('6번 상영관 150 -> 100',
    $q$UPDATE tbl_thtr_m1 SET seat = 100 WHERE thtr_id = 6$q$, '23514');

UPDATE tbl_thtr_m1 SET seat = 100 WHERE thtr_id = 7;
SELECT * FROM pg_temp.val('7번 상영관(예정 상영 없음) 150 -> 100',
    (SELECT seat FROM tbl_thtr_m1 WHERE thtr_id = 7), 100);
ROLLBACK;

-- ---------------------------------------------------------------------
-- C12  이용 가능 좌석을 삭제 / 추가하면 예정 상영의 이용 가능 좌석 수에 반영
-- ---------------------------------------------------------------------
\echo
\echo '== C12  이용 가능 좌석 삭제 -> 149, 좌석 추가 -> 150'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000012', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
DELETE FROM tbl_seat_m1 WHERE thtr_id = 6 AND seatcode = 'A1';
SELECT * FROM pg_temp.show('좌석 A1 삭제', 'V00000000012', 149);

INSERT INTO tbl_seat_m1(thtr_id, seatcode, status) VALUES (6, 'A1', 'Y');
SELECT * FROM pg_temp.show('좌석 A1 다시 추가', 'V00000000012', 150);
ROLLBACK;

-- ---------------------------------------------------------------------
-- C13  기본 제약: 없는 상영관, 잘못된 좌석 상태, 음수 계획 좌석 수
-- ---------------------------------------------------------------------
\echo
\echo '== C13  없는 상영관 / 좌석 status=X / 음수 계획 좌석 수 거부'
BEGIN;
SELECT * FROM pg_temp.reject('없는 상영관 99',
    $q$INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
       VALUES ('V00000000013', '2026092601', 99, 10, CURRENT_DATE + 30, '10:00')$q$, '23503');
SELECT * FROM pg_temp.reject('좌석 status = X',
    $q$UPDATE tbl_seat_m1 SET status = 'X' WHERE thtr_id = 6 AND seatcode = 'A1'$q$, '23514');
SELECT * FROM pg_temp.reject('계획 좌석 수 -1',
    $q$INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
       VALUES ('V00000000014', '2026092601', 6, -1, CURRENT_DATE + 30, '10:00')$q$, '23514');
ROLLBACK;

-- ---------------------------------------------------------------------
-- C14  적재된 전체 데이터 정합성: capacity <= planned_capacity <= 총 좌석 수
-- ---------------------------------------------------------------------
\echo
\echo '== C14  적재된 전체 상영의 규칙 위반 건수'
SELECT * FROM pg_temp.val('capacity > planned_capacity 또는 planned_capacity > 총 좌석 수인 상영',
    (SELECT count(*) FROM tbl_scrn_m1 AS s
      WHERE s.capacity > s.planned_capacity
         OR s.planned_capacity > (SELECT t.seat FROM tbl_thtr_m1 AS t WHERE t.thtr_id = s.thtr_id)), 0);

-- ---------------------------------------------------------------------
-- X01~X07  입력 위반 케이스
--   반정규화 전(원본) 스키마에서는 통과하던 잘못된 입력이 지금은 막히는지 확인한다.
--   예매(tbl_bytk_d1) 입력은 6번 상영관의 예정 상영 'V0000000002x' 를 만들어 쓴다.
--     pay_method: A 적립금 / B 마일리지 / C 복합, NULL 이면 미결제.  에러코드 23514=CHECK, 23503=FK, 23505=PK/UNIQUE
-- ---------------------------------------------------------------------

-- X01 금액·결제수단 불일치 ①: 적립금(A) 결제인데 적립금은 0 이고 마일리지 금액만 있음
\echo
\echo '== X01  금액·결제수단 불일치 ① 적립금(A) 결제인데 마일리지 금액만 입력 -> 거부'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000021', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.reject('pay_method=A, savings=0, mileage=5000',
    $q$INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, seatcode, buy_method, pay_method, buydate, savings, mileage)
       VALUES ((SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1), 'V00000000021', 6, 'A1', 'O', 'A', now(), 0, 5000)$q$, '23514');
ROLLBACK;

-- X02 금액·결제수단 불일치 ②: 미결제(결제수단 NULL)인데 결제 금액이 있음
\echo
\echo '== X02  금액·결제수단 불일치 ② 미결제(pay_method NULL)인데 적립금 5000 입력 -> 거부'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000022', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.reject('pay_method=NULL, savings=5000',
    $q$INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, seatcode, buy_method, pay_method, buydate, savings, mileage)
       VALUES ((SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1), 'V00000000022', 6, NULL, 'P', NULL, NULL, 5000, 0)$q$, '23514');
ROLLBACK;

-- X03 다른 상영관 좌석 예매 ①: 상영은 6번 상영관인데 예매에는 7번 상영관을 입력
\echo
\echo '== X03  다른 상영관 좌석 예매 ① 6번 상영관 상영을 7번 상영관 좌석(A1)으로 예매 -> 거부'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000023', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.reject('예매 thtr_id=7 (상영은 6번 상영관)',
    $q$INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, seatcode, buy_method, savings, mileage)
       VALUES ((SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1), 'V00000000023', 7, 'A1', 'P', 0, 0)$q$, '23503');
ROLLBACK;

-- X04 다른 상영관 좌석 예매 ②: 상영관 번호는 맞지만 그 상영관에 없는 좌석(다른 상영관에만 있는 좌석)을 입력
--     A20 은 200석 상영관(1~5번)에만 있고 150석 상영관(6~10번)에는 없다.
\echo
\echo '== X04  다른 상영관 좌석 예매 ② 150석 상영관(6번)에 없는 좌석 A20 으로 예매 -> 거부'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000024', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.val('전제: 1번 상영관에 A20 이 있다', (SELECT count(*) FROM tbl_seat_m1 WHERE thtr_id = 1 AND seatcode = 'A20'), 1);
SELECT * FROM pg_temp.val('전제: 6번 상영관에 A20 이 없다', (SELECT count(*) FROM tbl_seat_m1 WHERE thtr_id = 6 AND seatcode = 'A20'), 0);
SELECT * FROM pg_temp.reject('예매 좌석 (6번 상영관, A20)',
    $q$INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, seatcode, buy_method, savings, mileage)
       VALUES ((SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1), 'V00000000024', 6, 'A20', 'P', 0, 0)$q$, '23503');
ROLLBACK;

-- X05 상영의 이용 가능 좌석 수 임의 값 ①: 터무니없이 큰 값(9999)
--     계획 좌석 수(planned_capacity)로 넣으면 거부, 이용 가능 좌석 수(capacity)에 직접 넣으면 무시되어 계산값 유지
\echo
\echo '== X05  상영의 이용 가능 좌석 수 임의 값 ① 9999 -> 계획 좌석 수는 거부, capacity 직접 입력은 무시'
BEGIN;
SELECT * FROM pg_temp.reject('planned_capacity = 9999',
    $q$INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
       VALUES ('V00000000025', '2026092601', 6, 9999, CURRENT_DATE + 30, '10:00')$q$, '23514');
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, capacity, scrndate, scrntime)
VALUES ('V00000000026', '2026092601', 6, 150, 9999, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.show('capacity = 9999 직접 입력', 'V00000000026', 150);
ROLLBACK;

-- X06 상영의 이용 가능 좌석 수 임의 값 ②: 상영관 좌석 수와 맞지 않는 작은 값(7)을 capacity 에 직접 입력
\echo
\echo '== X06  상영의 이용 가능 좌석 수 임의 값 ② capacity = 7 직접 입력 -> 무시되고 계산값 150 유지, UPDATE 도 마찬가지'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, capacity, scrndate, scrntime)
VALUES ('V00000000027', '2026092601', 6, 150, 7, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.show('INSERT capacity = 7', 'V00000000027', 150);
UPDATE tbl_scrn_m1 SET capacity = 7 WHERE scrn_id = 'V00000000027';
SELECT * FROM pg_temp.show('UPDATE capacity = 7', 'V00000000027', 150);
ROLLBACK;

-- X07 출연 중복: 같은 영화에 같은 인물을 두 번 등록
\echo
\echo '== X07  출연 중복 같은 (영화, 인물) 을 두 번 등록 -> 거부'
BEGIN;
SELECT * FROM pg_temp.reject('tbl_part_d1 기존 행 그대로 다시 INSERT',
    (SELECT format($f$INSERT INTO tbl_part_d1(scmv_id, pers_id) VALUES (%L, %L)$f$, scmv_id, pers_id) FROM tbl_part_d1 LIMIT 1),
    '23505');
ROLLBACK;

-- ---------------------------------------------------------------------
-- P01~P02  정상 입력은 과도하게 막히지 않는지
-- ---------------------------------------------------------------------

-- P01 미결제·좌석 미지정 전화 예약
\echo
\echo '== P01  미결제·좌석 미지정 전화 예약은 정상 저장되고 예매 가능 좌석 수에 반영'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000031', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.accept('전화 예약 (미결제, 좌석 NULL, 금액 0)',
    $q$INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, seatcode, buy_method, pay_method, buydate, savings, mileage)
       VALUES ((SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1), 'V00000000031', 6, NULL, 'P', NULL, NULL, 0, 0)$q$);
SELECT * FROM pg_temp.val('저장된 행 (전화, 미결제, 좌석 미지정, 금액 0)',
    (SELECT count(*) FROM tbl_bytk_d1
      WHERE scrn_id = 'V00000000031' AND buy_method = 'P' AND pay_method IS NULL AND buydate IS NULL
        AND seatcode IS NULL AND savings = 0 AND mileage = 0), 1);
SELECT * FROM pg_temp.val('예매 가능 좌석 수 = 이용 가능 좌석 수 150 - 예매 1',
    (SELECT s.capacity - count(b.bytk_id) FROM tbl_scrn_m1 AS s LEFT JOIN tbl_bytk_d1 AS b ON b.scrn_id = s.scrn_id
      WHERE s.scrn_id = 'V00000000031' GROUP BY s.capacity), 149);
ROLLBACK;

-- P02 결제수단별 정상 온라인 예매 (CHECK 가 정상 조합까지 막지 않는지)
\echo
\echo '== P02  결제수단별 정상 온라인 예매(적립금 A / 마일리지 B / 복합 C)는 정상 저장'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000032', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.accept('A 적립금 5000',
    $q$INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, seatcode, buy_method, pay_method, buydate, savings, mileage)
       VALUES ((SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1), 'V00000000032', 6, 'A2', 'O', 'A', now(), 5000, 0)$q$);
SELECT * FROM pg_temp.accept('B 마일리지 5000',
    $q$INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, seatcode, buy_method, pay_method, buydate, savings, mileage)
       VALUES ((SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1), 'V00000000032', 6, 'A3', 'O', 'B', now(), 0, 5000)$q$);
SELECT * FROM pg_temp.accept('C 복합 (적립금 3000 + 마일리지 2000)',
    $q$INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, seatcode, buy_method, pay_method, buydate, savings, mileage)
       VALUES ((SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1), 'V00000000032', 6, 'A4', 'O', 'C', now(), 3000, 2000)$q$);
SELECT * FROM pg_temp.val('저장된 결제 완료 예매 수',
    (SELECT count(*) FROM tbl_bytk_d1 WHERE scrn_id = 'V00000000032' AND pay_method IS NOT NULL), 3);
ROLLBACK;

-- ---------------------------------------------------------------------
-- S01  상영관 총 좌석 수(tbl_thtr_m1.seat) 변경이 상영의 이용 가능 좌석 수에 미치는 영향
--      v2.0.0 : 복합 FK (thtr_id, capacity) 의 ON UPDATE CASCADE 로 총 좌석 수 변경이 상영의 이용 가능 좌석 수로 "전파"되었다.
--      v2.1.0 : 이용 가능 좌석 수는 "계획 좌석 수"와 "Y 상태 좌석 수(좌석 상태)"로만 결정되므로 총 좌석 수 변경은 전파하지 않고,
--               예정 상영의 계획 좌석 수보다 작게 줄이는 변경만 막는다.
--               Y 상태 좌석 수 변경이 이용 가능 좌석 수로 전파되는 것은 C01, C02, C12 에서 확인한다.
-- ---------------------------------------------------------------------
\echo
\echo '== S01  상영관 총 좌석 수 변경: 증가는 허용(이용 가능 좌석 수 전파 없음), 예정 상영보다 작게 감소는 거부, 지난 상영 무영향'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000041', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.accept('6번 상영관 총 좌석 수 150 -> 160',
    $q$UPDATE tbl_thtr_m1 SET seat = 160 WHERE thtr_id = 6$q$);
SELECT * FROM pg_temp.show('증가 후 예정 상영의 이용 가능 좌석 수 (전파 없음)', 'V00000000041', 150);
SELECT * FROM pg_temp.show('증가 후 지난 상영의 이용 가능 좌석 수 (무영향)', '202610100601', 150);
SELECT * FROM pg_temp.reject('6번 상영관 160 -> 100 (예정 상영 계획 좌석 수 150 보다 작게)',
    $q$UPDATE tbl_thtr_m1 SET seat = 100 WHERE thtr_id = 6$q$, '23514');
UPDATE tbl_thtr_m1 SET seat = 100 WHERE thtr_id = 7;
SELECT * FROM pg_temp.show('예정 상영 없는 7번 상영관을 100 으로 줄여도 지난 상영의 이용 가능 좌석 수 유지',
    (SELECT min(scrn_id) FROM tbl_scrn_m1 WHERE thtr_id = 7), 150);
ROLLBACK;

-- ---------------------------------------------------------------------
-- K01~K10  기존 제약 점검 (v2.0.0 에서 추가된 CHECK / 필수값 / FK / PK / 삭제·수정 동작)
--   에러코드 23514=CHECK, 23502=NOT NULL, 23503=FK, 23505=PK/UNIQUE, 22001=길이 초과
-- ---------------------------------------------------------------------

-- K01 회원 tbl_mebr_m1
\echo
\echo '== K01  회원: sex / savings / mileage / rating / 필수값 / 중복 / 길이'
BEGIN;
SELECT * FROM pg_temp.reject('sex = X',                    pg_temp.sql_mebr(p_sex => 'X'),        '23514');
SELECT * FROM pg_temp.reject('savings = -1',               pg_temp.sql_mebr(p_savings => -1),     '23514');
SELECT * FROM pg_temp.reject('mileage = -1',               pg_temp.sql_mebr(p_mileage => -1),     '23514');
SELECT * FROM pg_temp.reject('rating = 0 (1~5 만 허용)',   pg_temp.sql_mebr(p_rating => '0'),     '23514');
SELECT * FROM pg_temp.reject('rating = 6 (1~5 만 허용)',   pg_temp.sql_mebr(p_rating => '6'),     '23514');
SELECT * FROM pg_temp.reject('passwd = NULL',              pg_temp.sql_mebr(p_passwd => NULL::text), '23502');
SELECT * FROM pg_temp.reject('mebr_id 중복',               pg_temp.sql_mebr(p_id => (SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1)), '23505');
SELECT * FROM pg_temp.reject('mebr_id 17자 (최대 16)',     pg_temp.sql_mebr(p_id => repeat('a', 17)), '22001');
SELECT * FROM pg_temp.reject('name 5자 (최대 4)',          pg_temp.sql_mebr(p_name => '가나다라마'),  '22001');
SELECT * FROM pg_temp.accept('정상 회원 (rating 생략)',    pg_temp.sql_mebr(p_rating => 'DEFAULT'));
SELECT * FROM pg_temp.val('rating 기본값 5', (SELECT rating FROM tbl_mebr_m1 WHERE mebr_id = 'kuser01'), 5);
ROLLBACK;

-- K02 인물 tbl_pers_m1
\echo
\echo '== K02  인물: country_code 는 KOR/USA/GBR/CHN/JPN 만, birth 는 NULL 허용'
BEGIN;
SELECT * FROM pg_temp.reject('country_code = FRA',
    $q$INSERT INTO tbl_pers_m1(pers_id, name, eng_name, country_code, birth) VALUES ('kpers01', '가나', 'Ga', 'FRA', NULL)$q$, '23514');
SELECT * FROM pg_temp.accept('country_code = KOR, birth NULL',
    $q$INSERT INTO tbl_pers_m1(pers_id, name, eng_name, country_code, birth) VALUES ('kpers02', '가나', 'Ga', 'KOR', NULL)$q$);
ROLLBACK;

-- K03 예매 tbl_bytk_d1 의 결제 CHECK 3종 (X01, X02 에서 일부 확인한 것의 나머지 조합)
--     1) pay_method 별 savings/mileage 조합  2) 온라인(O) 예매는 결제수단 필수  3) 결제 시각(buydate)과 결제수단은 함께 존재
\echo
\echo '== K03  예매 CHECK: 코드값, 결제수단별 금액 조합, 온라인 결제수단 필수, 결제 시각과 결제수단 동시 존재'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000051', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
-- 다른 CHECK 에 걸리지 않도록 나머지 값은 정상 조합(적립금 결제)으로 두고 buy_method 만 틀리게 한다
SELECT * FROM pg_temp.reject('buy_method = X (나머지는 정상 결제)',
    pg_temp.sql_bytk('V00000000051', p_buy => 'X', p_pay => 'A', p_buydate => 'now', p_savings => 5000), '23514');
SELECT * FROM pg_temp.reject('pay_method = Z',
    pg_temp.sql_bytk('V00000000051', p_buy => 'O', p_pay => 'Z', p_buydate => 'now', p_savings => 5000), '23514');
SELECT * FROM pg_temp.reject('온라인(O) 예매인데 결제수단 NULL',
    pg_temp.sql_bytk('V00000000051', p_buy => 'O'), '23514');
SELECT * FROM pg_temp.reject('결제수단 A 인데 결제 시각(buydate) NULL',
    pg_temp.sql_bytk('V00000000051', p_buy => 'O', p_pay => 'A', p_savings => 5000), '23514');
SELECT * FROM pg_temp.reject('결제수단 NULL 인데 결제 시각 있음',
    pg_temp.sql_bytk('V00000000051', p_buydate => 'now'), '23514');
SELECT * FROM pg_temp.reject('B(마일리지) 인데 적립금 입력',
    pg_temp.sql_bytk('V00000000051', p_buy => 'O', p_pay => 'B', p_buydate => 'now', p_savings => 5000), '23514');
SELECT * FROM pg_temp.reject('C(복합) 인데 마일리지 0',
    pg_temp.sql_bytk('V00000000051', p_buy => 'O', p_pay => 'C', p_buydate => 'now', p_savings => 5000), '23514');
SELECT * FROM pg_temp.reject('A(적립금) 인데 마일리지도 입력',
    pg_temp.sql_bytk('V00000000051', p_buy => 'O', p_pay => 'A', p_buydate => 'now', p_savings => 3000, p_mileage => 2000), '23514');
SELECT * FROM pg_temp.reject('미결제인데 마일리지 있음',
    pg_temp.sql_bytk('V00000000051', p_mileage => 2000), '23514');
ROLLBACK;

-- K04 충전 tbl_chrg_d1
\echo
\echo '== K04  충전: charge_method 는 A~E 만'
BEGIN;
SELECT * FROM pg_temp.reject('charge_method = Z',
    $q$INSERT INTO tbl_chrg_d1(mebr_id, amount, charge_method) VALUES ((SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1), 10000, 'Z')$q$, '23514');
SELECT * FROM pg_temp.accept('charge_method = A',
    $q$INSERT INTO tbl_chrg_d1(mebr_id, amount, charge_method) VALUES ((SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1), 10000, 'A')$q$);
SELECT * FROM pg_temp.accept('charge_method = E',
    $q$INSERT INTO tbl_chrg_d1(mebr_id, amount, charge_method) VALUES ((SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1), 10000, 'E')$q$);
ROLLBACK;

-- K05 FK: 존재하지 않는 부모 행을 가리키는 입력
\echo
\echo '== K05  FK 존재 검사: 없는 회원 / 상영 / 영화 / 인물 / 상영관을 가리키는 입력'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000052', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.reject('예매: 없는 회원',    pg_temp.sql_bytk('V00000000052', p_mebr => 'nouser'), '23503');
SELECT * FROM pg_temp.reject('예매: 없는 상영',    pg_temp.sql_bytk('ZZZZZZZZZZZZ'), '23503');
SELECT * FROM pg_temp.reject('상영: 없는 영화',
    $q$INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
       VALUES ('V00000000053', '0000000000', 6, 150, CURRENT_DATE + 30, '10:00')$q$, '23503');
SELECT * FROM pg_temp.reject('출연: 없는 영화',    $q$INSERT INTO tbl_part_d1(scmv_id, pers_id) VALUES ('0000000000', (SELECT pers_id FROM tbl_pers_m1 LIMIT 1))$q$, '23503');
SELECT * FROM pg_temp.reject('출연: 없는 인물',    $q$INSERT INTO tbl_part_d1(scmv_id, pers_id) VALUES ('2026092601', 'nobody')$q$, '23503');
SELECT * FROM pg_temp.reject('찜: 없는 회원',      $q$INSERT INTO tbl_like_d1(scmv_id, mebr_id) VALUES ('2026092601', 'nouser')$q$, '23503');
SELECT * FROM pg_temp.reject('좌석: 없는 상영관',  $q$INSERT INTO tbl_seat_m1(thtr_id, seatcode, status) VALUES (99, 'A1', 'Y')$q$, '23503');
SELECT * FROM pg_temp.reject('충전: 없는 회원',    $q$INSERT INTO tbl_chrg_d1(mebr_id, amount, charge_method) VALUES ('nouser', 10000, 'A')$q$, '23503');
ROLLBACK;

-- K06 PK 중복
\echo
\echo '== K06  PK 중복: 좌석 / 상영 / 찜'
BEGIN;
SELECT * FROM pg_temp.reject('좌석 (6번 상영관, A1) 중복', $q$INSERT INTO tbl_seat_m1(thtr_id, seatcode, status) VALUES (6, 'A1', 'Y')$q$, '23505');
SELECT * FROM pg_temp.reject('상영 202610100601 중복',
    $q$INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
       VALUES ('202610100601', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00')$q$, '23505');
SELECT * FROM pg_temp.reject('찜 (영화, 회원) 중복',
    (SELECT format($f$INSERT INTO tbl_like_d1(scmv_id, mebr_id) VALUES (%L, %L)$f$, scmv_id, mebr_id) FROM tbl_like_d1 LIMIT 1), '23505');
ROLLBACK;

-- K07 필수값(NOT NULL)
\echo
\echo '== K07  필수값: 영화 제목 / 예매 회원 / 상영 계획 좌석 수가 NULL 이면 거부'
BEGIN;
SELECT * FROM pg_temp.reject('영화 title = NULL',
    $q$INSERT INTO tbl_scmv_m1(scmv_id, title, summary, playtime, agerating, startdate, status)
       VALUES ('K000000001', NULL, 's', 100, 'T', DATE '2026-11-01', 'S')$q$, '23502');
SELECT * FROM pg_temp.reject('예매 mebr_id = NULL',
    $q$INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, buy_method, savings, mileage)
       VALUES (NULL, '202610100601', 6, 'P', 0, 0)$q$, '23502');
-- LEAST 는 NULL 을 무시하므로 트리거가 capacity 를 계산해 버려도 planned_capacity 의 NOT NULL 에서 걸려야 한다
SELECT * FROM pg_temp.reject('상영 planned_capacity = NULL',
    $q$INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
       VALUES ('V00000000054', '2026092601', 6, NULL, CURRENT_DATE + 30, '10:00')$q$, '23502');
ROLLBACK;

-- K08 ON DELETE RESTRICT: 자식 행이 있는 부모 행은 지울 수 없다
\echo
\echo '== K08  삭제 제한(ON DELETE RESTRICT): 자식 행이 하나뿐인 새 부모 행을 만들어 그 FK 하나만 확인'
BEGIN;
-- 샘플 회원·영화는 여러 테이블이 참조해서 어느 FK 때문에 막혔는지 구분할 수 없다. 참조가 하나뿐인 새 행으로 격리한다.
INSERT INTO tbl_mebr_m1(mebr_id, passwd, name, birth, sex, phone, email, savings, mileage)
VALUES ('k08user', 'pw', '홍길동', DATE '2000-01-01', 'M', '01012345678', 'k@example.com', 0, 0);
INSERT INTO tbl_scmv_m1(scmv_id, title, summary, playtime, agerating, startdate, status)
VALUES ('K000000008', '테스트', 's', 100, 'T', DATE '2026-11-01', 'S');
INSERT INTO tbl_pers_m1(pers_id, name, eng_name, country_code) VALUES ('k08pers', '가나', 'Ga', 'KOR');
INSERT INTO tbl_thtr_m1(thtr_id, seat) VALUES (908, 10);
INSERT INTO tbl_seat_m1(thtr_id, seatcode, status) VALUES (908, 'A1', 'Y');

INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000055', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00'),
       ('V00000000058', 'K000000008', 6, 150, CURRENT_DATE + 30, '10:00');     -- 새 영화를 참조하는 상영 (영화 삭제 확인용)
INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, buy_method, savings, mileage)
VALUES ('k08user', 'V00000000055', 6, 'P', 0, 0);                              -- 새 회원의 예매 하나
INSERT INTO tbl_part_d1(scmv_id, pers_id) VALUES ('2026092601', 'k08pers');    -- 새 인물의 출연 하나

SELECT * FROM pg_temp.reject('상영 하나만 있는 영화 삭제',     $q$DELETE FROM tbl_scmv_m1 WHERE scmv_id = 'K000000008'$q$, '23503');
SELECT * FROM pg_temp.reject('좌석 하나만 있는 상영관 삭제',   $q$DELETE FROM tbl_thtr_m1 WHERE thtr_id = 908$q$, '23503');
SELECT * FROM pg_temp.reject('예매 하나만 있는 상영 삭제',     $q$DELETE FROM tbl_scrn_m1 WHERE scrn_id = 'V00000000055'$q$, '23503');
SELECT * FROM pg_temp.reject('예매 하나만 있는 회원 삭제',     $q$DELETE FROM tbl_mebr_m1 WHERE mebr_id = 'k08user'$q$, '23503');
SELECT * FROM pg_temp.reject('출연 하나만 있는 인물 삭제',     $q$DELETE FROM tbl_pers_m1 WHERE pers_id = 'k08pers'$q$, '23503');
ROLLBACK;

-- K09 ON UPDATE CASCADE: 부모 키를 바꾸면 자식 행이 따라간다
\echo
\echo '== K09  수정 전파(ON UPDATE CASCADE): 회원 ID, 상영 ID 를 바꾸면 예매 행이 따라감'
BEGIN;
CREATE TEMP TABLE _k09 ON COMMIT DROP AS
    SELECT mebr_id, count(*) AS n FROM tbl_bytk_d1 GROUP BY mebr_id ORDER BY mebr_id LIMIT 1;
UPDATE tbl_mebr_m1 SET mebr_id = 'cascade_test' WHERE mebr_id = (SELECT mebr_id FROM _k09);
SELECT * FROM pg_temp.val('회원 ID 변경 후 예매 행 수 (변경 전과 같아야 함)',
    (SELECT count(*) FROM tbl_bytk_d1 WHERE mebr_id = 'cascade_test'), (SELECT n FROM _k09));

INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000056', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, buy_method, savings, mileage)
VALUES ((SELECT mebr_id FROM tbl_mebr_m1 ORDER BY mebr_id LIMIT 1), 'V00000000056', 6, 'P', 0, 0);
UPDATE tbl_scrn_m1 SET scrn_id = 'V00000000057' WHERE scrn_id = 'V00000000056';
SELECT * FROM pg_temp.val('상영 ID 변경 후 새 ID 의 예매 행 수', (SELECT count(*) FROM tbl_bytk_d1 WHERE scrn_id = 'V00000000057'), 1);
SELECT * FROM pg_temp.val('상영 ID 변경 후 옛 ID 의 예매 행 수', (SELECT count(*) FROM tbl_bytk_d1 WHERE scrn_id = 'V00000000056'), 0);
ROLLBACK;

-- K10 데이터 길이/필수값 외에 적재된 데이터 전체가 제약을 만족하는지 (NOT VALID 로 추가된 제약이 없음을 확인)
\echo
\echo '== K10  검증되지 않은(NOT VALID) 제약이 없다'
SELECT * FROM pg_temp.val('convalidated = false 인 제약 수',
    (SELECT count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
      WHERE n.nspname = 'public' AND NOT c.convalidated), 0);

-- ---------------------------------------------------------------------
-- D01~D05  중복 예매 방지: UNIQUE (scrn_id, seatcode)
--   같은 상영의 같은 좌석은 한 번만 예매할 수 있다. 좌석 미지정(NULL) 전화 예약은 여러 건 가능하다.
--   동시에 같은 좌석을 예매하는 경우는 run_verify_integrity.sh 의 C18 에서 확인한다.
-- ---------------------------------------------------------------------

\echo
\echo '== D01  같은 상영의 같은 좌석 중복 예매 -> 거부 (회원·결제수단이 달라도 거부)'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000061', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.accept('좌석 A1 첫 예매', pg_temp.sql_bytk('V00000000061', 'A1'));
SELECT * FROM pg_temp.reject('좌석 A1 두 번째 예매 (같은 조건)', pg_temp.sql_bytk('V00000000061', 'A1'), '23505');
SELECT * FROM pg_temp.reject('좌석 A1 다른 회원·결제수단으로 예매',
    pg_temp.sql_bytk('V00000000061', 'A1', p_buy => 'O', p_pay => 'A', p_buydate => 'now', p_savings => 5000,
                     p_mebr => (SELECT mebr_id FROM tbl_mebr_m1 ORDER BY mebr_id DESC LIMIT 1)), '23505');
SELECT * FROM pg_temp.val('A1 예매 행 수', (SELECT count(*) FROM tbl_bytk_d1 WHERE scrn_id = 'V00000000061' AND seatcode = 'A1'), 1);
ROLLBACK;

\echo
\echo '== D02  좌석 미지정(NULL) 전화 예약은 한 상영에 여러 건 가능'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000062', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.accept('전화 예약 1 (좌석 NULL)', pg_temp.sql_bytk('V00000000062'));
SELECT * FROM pg_temp.accept('전화 예약 2 (좌석 NULL)', pg_temp.sql_bytk('V00000000062'));
SELECT * FROM pg_temp.accept('전화 예약 3 (좌석 NULL)', pg_temp.sql_bytk('V00000000062'));
SELECT * FROM pg_temp.val('좌석 미지정 예약 수', (SELECT count(*) FROM tbl_bytk_d1 WHERE scrn_id = 'V00000000062' AND seatcode IS NULL), 3);
ROLLBACK;

\echo
\echo '== D03  같은 좌석이라도 다른 상영이면 예매 가능, 한 상영의 다른 좌석도 가능'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000063', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00'),
       ('V00000000064', '2026092601', 6, 150, CURRENT_DATE + 30, '13:00');
SELECT * FROM pg_temp.accept('상영 1 좌석 A1', pg_temp.sql_bytk('V00000000063', 'A1'));
SELECT * FROM pg_temp.accept('상영 2 같은 좌석 A1', pg_temp.sql_bytk('V00000000064', 'A1'));
SELECT * FROM pg_temp.accept('상영 1 다른 좌석 A2', pg_temp.sql_bytk('V00000000063', 'A2'));
SELECT * FROM pg_temp.val('저장된 예매 행 수', (SELECT count(*) FROM tbl_bytk_d1 WHERE scrn_id IN ('V00000000063', 'V00000000064')), 3);
ROLLBACK;

\echo
\echo '== D04  예매를 취소(삭제)하면 같은 좌석을 다시 예매할 수 있다'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000065', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.accept('좌석 A1 예매', pg_temp.sql_bytk('V00000000065', 'A1'));
SELECT * FROM pg_temp.reject('취소 전 A1 재예매', pg_temp.sql_bytk('V00000000065', 'A1'), '23505');
DELETE FROM tbl_bytk_d1 WHERE scrn_id = 'V00000000065' AND seatcode = 'A1';
SELECT * FROM pg_temp.accept('취소 후 A1 재예매', pg_temp.sql_bytk('V00000000065', 'A1'));
ROLLBACK;

\echo
\echo '== D05  예매 좌석을 이미 예매된 다른 좌석으로 바꾸는 UPDATE 도 거부'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000066', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
INSERT INTO tbl_bytk_d1(mebr_id, scrn_id, thtr_id, seatcode, buy_method, savings, mileage)
VALUES ((SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1), 'V00000000066', 6, 'A1', 'P', 0, 0),
       ((SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1), 'V00000000066', 6, 'A2', 'P', 0, 0);
SELECT * FROM pg_temp.reject('A2 예매의 좌석을 A1 로 변경',
    $q$UPDATE tbl_bytk_d1 SET seatcode = 'A1' WHERE scrn_id = 'V00000000066' AND seatcode = 'A2'$q$, '23505');
SELECT * FROM pg_temp.accept('A2 예매의 좌석을 빈 좌석 A3 로 변경',
    $q$UPDATE tbl_bytk_d1 SET seatcode = 'A3' WHERE scrn_id = 'V00000000066' AND seatcode = 'A2'$q$);
ROLLBACK;

-- ---------------------------------------------------------------------
-- B01~B07  예매 규칙: 이용 불가 좌석 예매 거부(예정 상영), 이용 가능 좌석 수 초과 예매 거부(모든 상영), 계획 좌석 수 하향 제한
--   fn_check_bytk (예매 INSERT/UPDATE), fn_calc_scrn_capacity (계획 좌석 수 하향) 를 확인한다. 에러코드 23514=CHECK
--   동시에 일어나는 경우는 run_verify_integrity.sh 의 C19(이용 가능 좌석 수 마지막 1석), C20(좌석 상태 변경과 예매)에서 확인한다.
-- ---------------------------------------------------------------------

\echo
\echo '== B01  예정 상영에서 이용 불가(N) 좌석은 예매할 수 없다'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000071', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
UPDATE tbl_seat_m1 SET status = 'N' WHERE thtr_id = 6 AND seatcode = 'A1';
SELECT * FROM pg_temp.reject('이용 불가(N) 좌석 A1 예매', pg_temp.sql_bytk('V00000000071', 'A1'), '23514');
SELECT * FROM pg_temp.accept('이용 가능(Y) 좌석 A2 예매',   pg_temp.sql_bytk('V00000000071', 'A2'));
UPDATE tbl_seat_m1 SET status = 'Y' WHERE thtr_id = 6 AND seatcode = 'A1';
SELECT * FROM pg_temp.accept('복구(Y) 후 A1 예매',          pg_temp.sql_bytk('V00000000071', 'A1'));
ROLLBACK;

\echo
\echo '== B02  이용 가능 좌석 수를 넘는 예매는 거부 (이용 가능 좌석 수 3: 3건 저장, 4번째 거부)'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000072', '2026092601', 6, 3, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.accept('예매 1 (전화, 좌석 미지정)', pg_temp.sql_bytk('V00000000072'));
SELECT * FROM pg_temp.accept('예매 2 (좌석 A1)',           pg_temp.sql_bytk('V00000000072', 'A1'));
SELECT * FROM pg_temp.accept('예매 3 (좌석 A2)',           pg_temp.sql_bytk('V00000000072', 'A2'));
SELECT * FROM pg_temp.reject('예매 4 (이용 가능 좌석 수 3 초과, 좌석 미지정)', pg_temp.sql_bytk('V00000000072'), '23514');
SELECT * FROM pg_temp.reject('예매 4 (이용 가능 좌석 수 3 초과, 좌석 A3)',     pg_temp.sql_bytk('V00000000072', 'A3'), '23514');
SELECT * FROM pg_temp.val('저장된 예매 수', (SELECT count(*) FROM tbl_bytk_d1 WHERE scrn_id = 'V00000000072'), 3);
ROLLBACK;

\echo
\echo '== B03  이용 불가 좌석이 이용 가능 좌석 수를 줄이면 예매 가능 수도 따라 줄어든다 (150석 중 148석 이용 불가 -> 이용 가능 좌석 수 2)'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000073', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
UPDATE tbl_seat_m1 SET status = 'N' WHERE thtr_id = 6 AND seatcode NOT IN ('A1', 'A2');
SELECT * FROM pg_temp.show('이용 가능 2석 -> 이용 가능 좌석 수 2', 'V00000000073', 2);
SELECT * FROM pg_temp.accept('예매 1 (좌석 A1)', pg_temp.sql_bytk('V00000000073', 'A1'));
SELECT * FROM pg_temp.accept('예매 2 (좌석 A2)', pg_temp.sql_bytk('V00000000073', 'A2'));
SELECT * FROM pg_temp.reject('예매 3 (이용 가능 좌석 수 2 초과)', pg_temp.sql_bytk('V00000000073'), '23514');
ROLLBACK;

\echo
\echo '== B04  예매를 취소(삭제)하면 이용 가능 좌석 수에 여유가 생겨 다시 예매할 수 있다'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000074', '2026092601', 6, 2, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.accept('예매 1', pg_temp.sql_bytk('V00000000074', 'A1'));
SELECT * FROM pg_temp.accept('예매 2', pg_temp.sql_bytk('V00000000074', 'A2'));
SELECT * FROM pg_temp.reject('예매 3 (이용 가능 좌석 수 2 초과)', pg_temp.sql_bytk('V00000000074', 'A3'), '23514');
DELETE FROM tbl_bytk_d1 WHERE scrn_id = 'V00000000074' AND seatcode = 'A1';
SELECT * FROM pg_temp.accept('취소 후 예매 3', pg_temp.sql_bytk('V00000000074', 'A3'));
ROLLBACK;

\echo
\echo '== B05  지난 상영: 이용 불가 좌석 예매는 허용(과거 기록), 이용 가능 좌석 수 초과는 거부'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000075', '2026092601', 6, 2, DATE '2020-01-01', '10:00');
UPDATE tbl_seat_m1 SET status = 'N' WHERE thtr_id = 6 AND seatcode = 'A1';
SELECT * FROM pg_temp.accept('지난 상영의 현재 이용 불가 좌석 A1 예매', pg_temp.sql_bytk('V00000000075', 'A1'));
SELECT * FROM pg_temp.accept('지난 상영 예매 2',                        pg_temp.sql_bytk('V00000000075', 'A2'));
SELECT * FROM pg_temp.reject('지난 상영도 이용 가능 좌석 수 2 초과는 거부',          pg_temp.sql_bytk('V00000000075', 'A3'), '23514');
ROLLBACK;

\echo
\echo '== B06  예매 UPDATE 도 같은 규칙: 이용 불가 좌석으로 변경 거부, 이용 가능 좌석 수가 찬 다른 상영으로 이동 거부'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000076', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00'),
       ('V00000000077', '2026092601', 6, 1,   CURRENT_DATE + 30, '13:00');
UPDATE tbl_seat_m1 SET status = 'N' WHERE thtr_id = 6 AND seatcode = 'A9';
SELECT * FROM pg_temp.accept('예매 (좌석 A1)',           pg_temp.sql_bytk('V00000000076', 'A1'));
SELECT * FROM pg_temp.accept('다른 상영(이용 가능 좌석 수 1)에 예매',  pg_temp.sql_bytk('V00000000077', 'A1'));
SELECT * FROM pg_temp.reject('A1 예매를 이용 불가 좌석 A9 로 변경',
    $q$UPDATE tbl_bytk_d1 SET seatcode = 'A9' WHERE scrn_id = 'V00000000076' AND seatcode = 'A1'$q$, '23514');
SELECT * FROM pg_temp.reject('A1 예매를 이용 가능 좌석 수가 찬 상영으로 이동',
    $q$UPDATE tbl_bytk_d1 SET scrn_id = 'V00000000077', seatcode = 'A2' WHERE scrn_id = 'V00000000076' AND seatcode = 'A1'$q$, '23514');
SELECT * FROM pg_temp.accept('A1 예매를 이용 가능 좌석 A2 로 변경',
    $q$UPDATE tbl_bytk_d1 SET seatcode = 'A2' WHERE scrn_id = 'V00000000076' AND seatcode = 'A1'$q$);
ROLLBACK;

\echo
\echo '== B07  계획 좌석 수를 이미 예매된 수보다 낮출 수 없다 (예매 2건: 1 로 하향 거부, 2 유지·3 상향 허용)'
BEGIN;
INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
VALUES ('V00000000078', '2026092601', 6, 2, CURRENT_DATE + 30, '10:00');
SELECT * FROM pg_temp.accept('예매 1', pg_temp.sql_bytk('V00000000078', 'A1'));
SELECT * FROM pg_temp.accept('예매 2', pg_temp.sql_bytk('V00000000078', 'A2'));
SELECT * FROM pg_temp.reject('계획 좌석 수 2 -> 1 (예매 2건)',
    $q$UPDATE tbl_scrn_m1 SET planned_capacity = 1 WHERE scrn_id = 'V00000000078'$q$, '23514');
SELECT * FROM pg_temp.show('거부 후 이용 가능 좌석 수', 'V00000000078', 2);
SELECT * FROM pg_temp.accept('계획 좌석 수 2 -> 3',
    $q$UPDATE tbl_scrn_m1 SET planned_capacity = 3 WHERE scrn_id = 'V00000000078'$q$);
SELECT * FROM pg_temp.accept('상향 후 예매 3', pg_temp.sql_bytk('V00000000078', 'A3'));
ROLLBACK;

-- ---------------------------------------------------------------------
-- F01~F06  값 형식 제약
--   영화: status  I 상영중 / S 상영예정 / D 상영종료,  agerating  A 전체 관람가 / T 12세 이상 / F 15세 이상 / N 청소년 관람불가
--   에러코드 23514=CHECK, 22001=길이 초과
-- ---------------------------------------------------------------------

\echo
\echo '== F01  영화 코드값: status 는 I/S/D, agerating 은 A/T/F/N 만 허용'
BEGIN;
SELECT * FROM pg_temp.reject('status = ?',            pg_temp.sql_scmv(p_status => '?'), '23514');
SELECT * FROM pg_temp.reject('status = X',            pg_temp.sql_scmv(p_status => 'X'), '23514');
SELECT * FROM pg_temp.reject('agerating = Z',         pg_temp.sql_scmv(p_age => 'Z'),    '23514');
SELECT * FROM pg_temp.reject('agerating = 소문자 a',  pg_temp.sql_scmv(p_age => 'a'),    '23514');
SELECT * FROM pg_temp.accept('status = I (상영중)',   pg_temp.sql_scmv(p_status => 'I'));
SELECT * FROM pg_temp.accept('status = S (상영예정)', pg_temp.sql_scmv(p_status => 'S'));
SELECT * FROM pg_temp.accept('status = D (상영종료)', pg_temp.sql_scmv(p_status => 'D'));
SELECT * FROM pg_temp.accept('agerating = A (전체 관람가)',     pg_temp.sql_scmv(p_age => 'A'));
SELECT * FROM pg_temp.accept('agerating = T (12세 이상)',       pg_temp.sql_scmv(p_age => 'T'));
SELECT * FROM pg_temp.accept('agerating = F (15세 이상)',       pg_temp.sql_scmv(p_age => 'F'));
SELECT * FROM pg_temp.accept('agerating = N (청소년 관람불가)', pg_temp.sql_scmv(p_age => 'N'));
SELECT * FROM pg_temp.val('저장된 영화 수 (정상 7건)', (SELECT count(*) FROM tbl_scmv_m1 WHERE title = 'fmt test'), 7);
ROLLBACK;

\echo
\echo '== F02  영화 날짜·숫자: 종료일 >= 시작일, 상영시간 > 0, 요금 >= 0 (미정은 NULL)'
BEGIN;
SELECT * FROM pg_temp.reject('종료일(2026-01-01) < 시작일(2026-12-01)', pg_temp.sql_scmv(p_start => '2026-12-01', p_end => '2026-01-01'), '23514');
SELECT * FROM pg_temp.reject('상영시간 0',   pg_temp.sql_scmv(p_playtime => 0),  '23514');
SELECT * FROM pg_temp.reject('상영시간 -5',  pg_temp.sql_scmv(p_playtime => -5), '23514');
SELECT * FROM pg_temp.reject('요금 -1',      pg_temp.sql_scmv(p_fee => '-1'),    '23514');
SELECT * FROM pg_temp.accept('종료일 = 시작일',   pg_temp.sql_scmv(p_start => '2026-12-01', p_end => '2026-12-01'));
SELECT * FROM pg_temp.accept('종료일 > 시작일',   pg_temp.sql_scmv(p_start => '2026-12-01', p_end => '2026-12-31'));
SELECT * FROM pg_temp.accept('종료일 NULL (미정)', pg_temp.sql_scmv(p_end => NULL::text));
SELECT * FROM pg_temp.accept('요금 0 (무료)',      pg_temp.sql_scmv(p_fee => '0'));
SELECT * FROM pg_temp.accept('요금 NULL (미정)',   pg_temp.sql_scmv(p_fee => NULL::text));
SELECT * FROM pg_temp.val('저장된 영화 수 (정상 5건)', (SELECT count(*) FROM tbl_scmv_m1 WHERE title = 'fmt test'), 5);
ROLLBACK;

\echo
\echo '== F03  충전 금액은 양수'
BEGIN;
SELECT * FROM pg_temp.reject('amount = 0',
    $q$INSERT INTO tbl_chrg_d1(mebr_id, amount, charge_method) VALUES ((SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1), 0, 'A')$q$, '23514');
SELECT * FROM pg_temp.reject('amount = -50000',
    $q$INSERT INTO tbl_chrg_d1(mebr_id, amount, charge_method) VALUES ((SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1), -50000, 'A')$q$, '23514');
SELECT * FROM pg_temp.accept('amount = 1',
    $q$INSERT INTO tbl_chrg_d1(mebr_id, amount, charge_method) VALUES ((SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1), 1, 'A')$q$);
SELECT * FROM pg_temp.accept('amount = 10000',
    $q$INSERT INTO tbl_chrg_d1(mebr_id, amount, charge_method) VALUES ((SELECT mebr_id FROM tbl_mebr_m1 LIMIT 1), 10000, 'A')$q$);
ROLLBACK;

\echo
\echo '== F04  회원 전화번호: 하이픈 없는 숫자 11자리'
BEGIN;
SELECT * FROM pg_temp.reject('문자 abcdefghijk',          pg_temp.sql_mebr(p_phone => 'abcdefghijk'),  '23514');
SELECT * FROM pg_temp.reject('하이픈 포함 010-1234-56',   pg_temp.sql_mebr(p_phone => '010-1234-56'),  '23514');
SELECT * FROM pg_temp.reject('숫자 10자리 (공백으로 채워짐)', pg_temp.sql_mebr(p_phone => '0101234567'), '23514');
SELECT * FROM pg_temp.reject('숫자 12자리 (길이 초과)',   pg_temp.sql_mebr(p_phone => '010123456789'), '22001');
SELECT * FROM pg_temp.accept('숫자 11자리 01012345678',   pg_temp.sql_mebr(p_id => 'f04ok'));
ROLLBACK;

\echo
\echo '== F05  회원 이메일: 공백 없는 "아이디@도메인" 형태'
BEGIN;
SELECT * FROM pg_temp.reject('@ 없음 (이메일아님)', pg_temp.sql_mebr(p_email => '이메일아님'),  '23514');
SELECT * FROM pg_temp.reject('아이디 없음 (@b.com)', pg_temp.sql_mebr(p_email => '@b.com'),     '23514');
SELECT * FROM pg_temp.reject('도메인 없음 (a@)',     pg_temp.sql_mebr(p_email => 'a@'),         '23514');
SELECT * FROM pg_temp.reject('@ 두 개 (a@@b.com)',   pg_temp.sql_mebr(p_email => 'a@@b.com'),   '23514');
SELECT * FROM pg_temp.reject('공백 포함 (a b@c.com)', pg_temp.sql_mebr(p_email => 'a b@c.com'),  '23514');
SELECT * FROM pg_temp.accept('a@b.com',              pg_temp.sql_mebr(p_id => 'f05ok', p_email => 'a@b.com'));
ROLLBACK;

\echo
\echo '== F06  관리자 전화번호·이메일도 같은 형식'
BEGIN;
SELECT * FROM pg_temp.reject('관리자 전화 abcdefghijk', pg_temp.sql_mngr(p_phone => 'abcdefghijk'), '23514');
SELECT * FROM pg_temp.reject('관리자 이메일 @ 없음',     pg_temp.sql_mngr(p_email => '이메일아님'),  '23514');
SELECT * FROM pg_temp.accept('정상 관리자',              pg_temp.sql_mngr());
ROLLBACK;

-- ---------------------------------------------------------------------
-- 동시성 케이스는 세션이 2개 필요해서 이 파일에서는 실행하지 않는다.
-- 자동 실행은 run_verify_integrity.sh (C15 직렬화, C16 데드락, STRESS=1 이면 C17 부하 테스트).
-- 아래는 같은 케이스를 터미널 2개로 직접 따라 해 보는 방법이다.
--
-- 준비:  KEEP_DB=1 sh cinema/postgresql_denormalization/run_verify_integrity.sh      (임시 DB cinema_verify_bench 가 남는다)
--        터미널마다  docker exec -it db-optimization-postgres psql -U postgres -d cinema_verify_bench
--        (수정 전 동작을 보려면 REVERT_FIX=1 KEEP_DB=1 sh ... 로 만든 DB 에서 같은 절차를 따라 한다)
--        한 번만, 아무 터미널에서:
--          INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
--          VALUES ('V00000000098', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
--          UPDATE tbl_seat_m1 SET status = 'Y' WHERE thtr_id = 6;
--
-- [C16 데드락]  각 단계는 앞 단계의 터미널이 멈춘 것을 확인한 뒤에 실행한다.
--   1) 터미널 A:  BEGIN;
--                 SELECT 1 FROM tbl_scrn_m1 WHERE scrn_id = 'V00000000098' FOR UPDATE;     -- 상영 행을 잡는다
--   2) 터미널 B:  BEGIN;
--                 UPDATE tbl_seat_m1 SET status = 'N' WHERE thtr_id = 6 AND seatcode = 'A1';
--                 -- A 가 상영 행을 잡고 있어서 B 가 멈춘다 (프롬프트가 돌아오지 않음)
--   3) 터미널 C(선택):  SELECT pid, wait_event_type, wait_event, left(query, 50) AS query
--                       FROM pg_stat_activity WHERE datname = 'cinema_verify_bench' AND state <> 'idle' AND pid <> pg_backend_pid();
--                       -- B 가 Lock / transactionid 로 기다리는 중임을 볼 수 있다
--   4) 터미널 A:  UPDATE tbl_scrn_m1 SET planned_capacity = 100 WHERE scrn_id = 'V00000000098';
--        수정 후: 바로 성공한다.  ->  COMMIT;  을 치면 B 가 풀려서 끝난다.  ->  터미널 B 에서 COMMIT;
--        수정 전: A 도 멈추고 약 1초 뒤 한쪽에 "ERROR: deadlock detected" 가 뜬다.  ->  양쪽에서 ROLLBACK;
--   5) 확인:  SELECT scrn_id, planned_capacity, capacity FROM tbl_scrn_m1 WHERE scrn_id = 'V00000000098';
--             SELECT status FROM tbl_seat_m1 WHERE thtr_id = 6 AND seatcode = 'A1';
--        수정 후: capacity 100, A1 은 N.  수정 전: 중단된 쪽의 변경은 사라져 있다(롤백됨).
--
-- [C15 직렬화]
--   터미널 A:  BEGIN;
--              INSERT INTO tbl_scrn_m1(scrn_id, scmv_id, thtr_id, planned_capacity, scrndate, scrntime)
--              VALUES ('V00000000099', '2026092601', 6, 150, CURRENT_DATE + 30, '10:00');
--              -- 여기서 COMMIT 하지 않고 기다린다
--   터미널 B:  UPDATE tbl_seat_m1 SET status = 'N' WHERE thtr_id = 6 AND seatcode = 'A1';
--              -- A 가 끝날 때까지 멈춰 있어야 한다 (상영관 행 잠금)
--   터미널 A:  COMMIT;     -- B 가 풀리고 끝난다
--   확인:      SELECT capacity FROM tbl_scrn_m1 WHERE scrn_id = 'V00000000099';   -- 149 여야 한다 (150 이면 규칙 위반)
--   정리:      DELETE FROM tbl_scrn_m1 WHERE scrn_id = 'V00000000099';
--              UPDATE tbl_seat_m1 SET status = 'Y' WHERE thtr_id = 6;
-- ---------------------------------------------------------------------
