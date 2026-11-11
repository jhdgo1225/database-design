-- 측정용 대량 샘플 (반정규화 스키마, v2.1.0). insert_data.sql 적재 후에 실행한다.

-- =====================================================================================================
-- [공통 생성 로직] 정규화(postgresql)와 반정규화(postgresql_denormalization)의 insert_data_bulk.sql 에서 동일하다.
--   난수 대신 md5 해시로 값을 만들기 때문에 두 스키마에서, 그리고 같은 날 다시 실행해도 항상 같은 데이터가 생성된다.
--   기존 샘플을 먼저 적재한 뒤에 실행한다. 기존 샘플과 겹치지 않는 ID 범위를 사용한다.
--
--   영화 300편 (상영중 120 / 상영예정 30 / 상영종료 150, ID 'B000000001'~) / 인물 3,000명 / 출연 약 2,700건
--   상영관 30개 (ID 11~40, 150석·200석 교대) / 좌석 5,250석 (전부 이용 가능)
--   상영 약 13,700회: 상영관 30개 x 76일(오늘 기준 -45일 ~ +30일) x 하루 6회. 영화는 상영중 영화 중에서 해시로 고른다.
--   회원 20,000명 (ID 'bulk000001'~, 등급 1~5) / 충전 60,000건 / 찜 약 6만 건
--   예매 약 33만 건: 상영마다 좌석 수 x 3~57% (시간대·주말 가중치 적용, 상영관 좌석의 90% 이하). 지난 상영은 많이, 앞으로의 상영은
--     오늘에서 멀수록 적게 생성한다. 좌석은 지정하지 않는다 (기존 샘플과 같음). 결제수단·구매방법·금액은 CHECK 규칙을 지킨다.
--
--   날짜 기준은 CURRENT_DATE 이다. 정보시스템 쿼리 3~6번("이번 달")과 8·9번("앞으로의 상영")이 의미 있는 행을 읽도록 하기 위해서다.
--   예매 시각(buydate)은 오늘 0시를 넘지 않게 해서 하루 안에서는 항상 같은 데이터가 된다.
--   이용 가능 좌석 수는 모든 상영에서 상영관 총 좌석 수와 같다. (좌석이 전부 이용 가능하므로 정규화의 th.seat 와 반정규화의 sc.capacity 가 같은 값)
-- =====================================================================================================

-- 시드 문자열 -> 0 ~ 2^28-1 정수 (결정적 의사 난수)
CREATE FUNCTION pg_temp.bulk_hash(seed TEXT) RETURNS INT AS $$
    SELECT ('x' || substr(md5(seed), 1, 7))::bit(28)::INT
$$ LANGUAGE sql IMMUTABLE;

-- md5 문자열(32자리)의 pos 번째부터 7자리 -> 0 ~ 2^28-1 정수. 한 번 계산한 해시에서 서로 다른 구간을 꺼내 쓴다.
CREATE FUNCTION pg_temp.hx(h TEXT, pos INT) RETURNS INT AS $$
    SELECT ('x' || substr(h, pos, 7))::bit(28)::INT
$$ LANGUAGE sql IMMUTABLE;

-- 영화 300편
CREATE TEMP TABLE bulk_movie AS
SELECT s.*,
       CASE s.status WHEN 'I' THEN CURRENT_DATE - (10 + s.g % 80)
                     WHEN 'S' THEN CURRENT_DATE + (3 + s.g % 25)
                     ELSE          CURRENT_DATE - (200 + s.g % 150)
       END AS startdate
FROM (
    SELECT g,
           'B' || lpad(g::text, 9, '0') AS scmv_id,
           '샘플 영화 ' || lpad(g::text, 4, '0') AS title,
           '샘플 영화 ' || g || '의 줄거리입니다.' AS summary,
           80 + (g * 7) % 80 AS playtime,
           (ARRAY['A', 'T', 'F', 'N'])[g % 4 + 1] AS agerating,
           CASE WHEN g % 10 < 4 THEN 'I' WHEN g % 10 = 4 THEN 'S' ELSE 'D' END AS status
    FROM generate_series(1, 300) AS g
) s;
-- 상영종료 영화만 종료일이 있고, 상영예정 영화는 요금이 정해지지 않았다.
ALTER TABLE bulk_movie ADD COLUMN enddate DATE, ADD COLUMN fee INT;
UPDATE bulk_movie SET enddate = startdate + (30 + g % 60) WHERE status = 'D';
UPDATE bulk_movie SET fee = 7000 + (g % 6) * 1000 WHERE status <> 'S';

-- 인물 3,000명, 영화마다 6~12명 출연
CREATE TEMP TABLE bulk_person AS
SELECT g,
       'P' || lpad(g::text, 6, '0') AS pers_id,
       '샘플인물 ' || g AS name,
       'Sample Person ' || g AS eng_name,
       (ARRAY['KOR', 'USA', 'GBR', 'CHN', 'JPN'])[g % 5 + 1] AS country_code
FROM generate_series(1, 3000) AS g;

CREATE TEMP TABLE bulk_part AS
SELECT m.scmv_id, p.pers_id
FROM bulk_movie m
CROSS JOIN LATERAL generate_series(1, 6 + pg_temp.bulk_hash('pc' || m.g) % 7) AS k
JOIN bulk_person p ON p.g = (m.g * 13 + k * 97) % 3000 + 1;

-- 상영관 30개 (ID 11~40) 와 좌석 (A~J 열, 150석은 1~15번, 200석은 1~20번)
CREATE TEMP TABLE bulk_theater AS
SELECT 10 + g AS thtr_id, CASE WHEN g % 2 = 0 THEN 150 ELSE 200 END AS seat
FROM generate_series(1, 30) AS g;

CREATE TEMP TABLE bulk_seat AS
SELECT t.thtr_id, chr(64 + r) || c AS seatcode
FROM bulk_theater t
CROSS JOIN generate_series(1, 10) AS r
CROSS JOIN LATERAL generate_series(1, t.seat / 10) AS c;

-- 상영: 상영관 x 일자(-45 ~ +30) x 하루 6회. scrn_id = 날짜(8) + 상영관(2) + 회차(2)
CREATE TEMP TABLE bulk_show_movie AS
SELECT row_number() OVER (ORDER BY g) AS n, scmv_id FROM bulk_movie WHERE status = 'I';

CREATE TEMP TABLE bulk_screening AS
SELECT to_char(d.dt, 'YYYYMMDD') || lpad(t.thtr_id::text, 2, '0') || lpad(s.slot::text, 2, '0') AS scrn_id,
       sm.scmv_id,
       t.thtr_id,
       t.seat,
       d.dt AS scrndate,
       (ARRAY['07:00', '10:00', '13:00', '16:00', '19:00', '22:00'])[s.slot]::time AS scrntime,
       s.slot,
       d.off
FROM bulk_theater t
CROSS JOIN (SELECT off, CURRENT_DATE + off AS dt FROM generate_series(-45, 30) AS off) d
CROSS JOIN generate_series(1, 6) AS s(slot)
JOIN bulk_show_movie sm
  ON sm.n = 1 + pg_temp.bulk_hash('sm' || t.thtr_id || '-' || d.off || '-' || s.slot) % (SELECT count(*) FROM bulk_show_movie);

-- 상영별 예매 수: 좌석 수 x (3% + 57% x u^2) x 회차 가중치 x 주말 가중치. 앞으로의 상영은 오늘에서 14일이 지나면 0 이 되도록 줄인다.
CREATE TEMP TABLE bulk_screening_cnt AS
SELECT sc.*,
       LEAST((sc.seat * 0.9)::INT,
             floor(sc.seat
                   * (0.03 + 0.57 * power(pg_temp.bulk_hash('fc' || sc.scrn_id) / 268435456.0, 2))
                   * (ARRAY[0.4, 0.7, 0.9, 1.0, 1.4, 0.6])[sc.slot]
                   * CASE WHEN extract(isodow FROM sc.scrndate) >= 6 THEN 1.4 ELSE 1.0 END
                   * CASE WHEN sc.off <= 0 THEN 1.0 ELSE greatest(0, 1 - sc.off / 14.0) * 0.5 END
             )::INT) AS cnt
FROM bulk_screening sc;

-- 회원 20,000명: 등급 1(최상) 5%, 2 15%, 3 30%, 4 25%, 5 25%
CREATE TEMP TABLE bulk_member AS
SELECT n,
       'bulk' || lpad(n::text, 6, '0') AS mebr_id,
       md5('bulk' || n) || md5('pw' || n) AS passwd,
       (ARRAY['김', '이', '박', '최', '정', '강', '조', '윤', '장', '임'])[pg_temp.bulk_hash('n1' || n) % 10 + 1]
         || (ARRAY['민', '서', '지', '하', '도', '예', '준', '윤', '수', '현'])[pg_temp.bulk_hash('n2' || n) % 10 + 1]
         || (ARRAY['준', '연', '우', '은', '윤', '아', '영', '진', '빈', '호'])[pg_temp.bulk_hash('n3' || n) % 10 + 1] AS name,
       DATE '1960-01-01' + pg_temp.bulk_hash('bd' || n) % 16000 AS birth,
       CASE WHEN pg_temp.bulk_hash('sx' || n) % 2 = 0 THEN 'M' ELSE 'F' END AS sex,
       '010' || lpad((20000000 + n)::text, 8, '0') AS phone,
       'bulk' || lpad(n::text, 6, '0') || '@example.com' AS email,
       (pg_temp.bulk_hash('sv' || n) % 200) * 1000 AS savings,
       (pg_temp.bulk_hash('ml' || n) % 50) * 100 AS mileage,
       CASE WHEN pg_temp.bulk_hash('rt' || n) % 100 < 5  THEN 1
            WHEN pg_temp.bulk_hash('rt' || n) % 100 < 20 THEN 2
            WHEN pg_temp.bulk_hash('rt' || n) % 100 < 50 THEN 3
            WHEN pg_temp.bulk_hash('rt' || n) % 100 < 75 THEN 4
            ELSE 5 END AS rating
FROM generate_series(1, 20000) AS n;

-- 예매: 결제수단 A(적립금) 40% / B(마일리지) 25% / C(복합) 35%, 구매방법 O(온라인) 70% / P(전화) 30%
--   금액 7,000~15,000원. 복합 결제는 마일리지 1,000~3,000원 + 나머지 적립금. 예매 시각은 상영 30분 ~ 7일 전이고 오늘 0시를 넘지 않는다.
CREATE TEMP TABLE bulk_booking AS
SELECT x.scrn_id, x.thtr_id, x.k, x.mebr_id, x.pay_method, x.buy_method, x.buydate,
       CASE x.pay_method WHEN 'A' THEN x.amt WHEN 'B' THEN 0 ELSE x.amt - x.ml END AS savings,
       CASE x.pay_method WHEN 'A' THEN 0 WHEN 'B' THEN x.amt ELSE x.ml END AS mileage
FROM (
    SELECT b.scrn_id, b.thtr_id, b.k,
           'bulk' || lpad((1 + pg_temp.hx(b.h1, 1) % 20000)::text, 6, '0') AS mebr_id,
           CASE WHEN pg_temp.hx(b.h1, 8) % 100 < 40 THEN 'A'
                WHEN pg_temp.hx(b.h1, 8) % 100 < 65 THEN 'B'
                ELSE 'C' END AS pay_method,
           CASE WHEN pg_temp.hx(b.h1, 15) % 100 < 70 THEN 'O' ELSE 'P' END AS buy_method,
           7000 + 1000 * (pg_temp.hx(b.h1, 22) % 9) AS amt,
           1000 * (1 + pg_temp.hx(b.h2, 1) % 3) AS ml,
           CASE WHEN (b.scrndate + b.scrntime) - ((30 + pg_temp.hx(b.h2, 8) % 10080) * interval '1 minute') >= CURRENT_DATE::timestamp
                THEN CURRENT_DATE::timestamp - ((1 + pg_temp.hx(b.h2, 15) % 259200) * interval '1 second')
                ELSE (b.scrndate + b.scrntime) - ((30 + pg_temp.hx(b.h2, 8) % 10080) * interval '1 minute')
           END AS buydate
    FROM (
        SELECT sc.scrn_id, sc.thtr_id, sc.scrndate, sc.scrntime, k,
               md5(sc.scrn_id || '-' || k) AS h1,
               md5(k || '-' || sc.scrn_id) AS h2
        FROM bulk_screening_cnt sc
        CROSS JOIN LATERAL generate_series(1, sc.cnt) AS k
    ) b
) x;

-- 충전 60,000건 (최근 180일), 찜 약 6만 건 (영화 300편 x 회원 20,000명 중 해시로 선택, 중복 제거)
CREATE TEMP TABLE bulk_charge AS
SELECT g,
       'bulk' || lpad((1 + pg_temp.bulk_hash('cm' || g) % 20000)::text, 6, '0') AS mebr_id,
       10000 * (1 + pg_temp.bulk_hash('ca' || g) % 10) AS amount,
       CURRENT_DATE::timestamp - ((pg_temp.bulk_hash('ct' || g) % 15552000) * interval '1 second') AS charged_at,
       (ARRAY['A', 'B', 'C', 'D', 'E'])[1 + pg_temp.bulk_hash('cp' || g) % 5] AS method
FROM generate_series(1, 60000) AS g;

CREATE TEMP TABLE bulk_like AS
SELECT DISTINCT m.scmv_id,
       'bulk' || lpad((1 + pg_temp.bulk_hash('lu' || s.i) % 20000)::text, 6, '0') AS mebr_id
FROM generate_series(1, 60000) AS s(i)
JOIN bulk_movie m ON m.g = 1 + pg_temp.bulk_hash('lm' || s.i) % 300;

-- =====================================================================================================
-- [반정규화 스키마 전용] 위에서 만든 임시 테이블을 반정규화 스키마(create_ddl.sql, v2.1.0)에 적재한다.
--   회원 등급은 tbl_mebr_m1.rating, 예매 결제수단은 tbl_bytk_d1.pay_method 에 흡수되어 있다.
--   예매에는 상영관(thtr_id), 상영에는 계획 좌석 수·이용 가능 좌석 수(planned_capacity, capacity)가 있다.
--
--   적재 중에는 사용자 트리거를 끈다. 예매 약 33만 건을 행마다 검사(좌석·이용 가능 좌석 수 확인, 잠금)하면 느리기 때문이다.
--   외래키·CHECK·UNIQUE 는 그대로 검사된다. 적재가 끝나면 트리거가 지키는 규칙을 아래에서 SQL 로 직접 검증하고 트리거를 다시 켠다.
-- =====================================================================================================

ALTER TABLE tbl_thtr_m1 DISABLE TRIGGER USER;
ALTER TABLE tbl_seat_m1 DISABLE TRIGGER USER;
ALTER TABLE tbl_scrn_m1 DISABLE TRIGGER USER;
ALTER TABLE tbl_bytk_d1 DISABLE TRIGGER USER;

INSERT INTO tbl_scmv_m1 (scmv_id, title, summary, playtime, agerating, startdate, enddate, fee, status)
SELECT scmv_id, title, summary, playtime, agerating, startdate, enddate, fee, status
FROM bulk_movie ORDER BY g;

INSERT INTO tbl_pers_m1 (pers_id, name, eng_name, country_code)
SELECT pers_id, name, eng_name, country_code FROM bulk_person ORDER BY g;

INSERT INTO tbl_part_d1 (scmv_id, pers_id)
SELECT scmv_id, pers_id FROM bulk_part ORDER BY scmv_id, pers_id;

INSERT INTO tbl_thtr_m1 (thtr_id, seat)
SELECT thtr_id, seat FROM bulk_theater ORDER BY thtr_id;
DO $$ BEGIN
    PERFORM setval(pg_get_serial_sequence('tbl_thtr_m1', 'thtr_id'), (SELECT max(thtr_id) FROM tbl_thtr_m1));
END $$;

INSERT INTO tbl_seat_m1 (thtr_id, seatcode, status)
SELECT thtr_id, seatcode, 'Y' FROM bulk_seat ORDER BY thtr_id, seatcode;

-- 이용 가능 좌석 수: 계획 좌석 수 = 상영관 총 좌석 수, 좌석이 전부 이용 가능하므로 capacity 도 같은 값 (트리거가 꺼져 있어 직접 넣는다)
INSERT INTO tbl_scrn_m1 (scrn_id, scmv_id, thtr_id, planned_capacity, capacity, scrndate, scrntime)
SELECT scrn_id, scmv_id, thtr_id, seat, seat, scrndate, scrntime FROM bulk_screening ORDER BY scrndate, scrntime, thtr_id;

INSERT INTO tbl_mebr_m1 (mebr_id, passwd, name, birth, sex, phone, email, savings, mileage, rating)
SELECT mebr_id, passwd, name, birth, sex, phone, email, savings, mileage, rating FROM bulk_member ORDER BY n;

-- 예매는 실제 서비스처럼 예매 시각 순서로 넣는다. 예약 시각(reserved_at)과 결제 시각(buydate)은 같게 둔다. (전부 결제 완료)
INSERT INTO tbl_bytk_d1 (mebr_id, scrn_id, thtr_id, buy_method, reserved_at, pay_method, buydate, savings, mileage)
SELECT mebr_id, scrn_id, thtr_id, buy_method, buydate, pay_method, buydate, savings, mileage
FROM bulk_booking ORDER BY buydate, scrn_id, k;

INSERT INTO tbl_chrg_d1 (mebr_id, amount, charged_at, charge_method)
SELECT mebr_id, amount, charged_at, method FROM bulk_charge ORDER BY g;

INSERT INTO tbl_like_d1 (scmv_id, mebr_id)
SELECT scmv_id, mebr_id FROM bulk_like ORDER BY scmv_id, mebr_id;

-- 트리거가 지키는 규칙을 직접 검증한다. 하나라도 어기면 적재를 실패시킨다.
DO $$
DECLARE
    bad BIGINT;
BEGIN
    -- 상영관 총 좌석 수 = 좌석 행 수 (좌석은 전부 이용 가능)
    SELECT count(*) INTO bad FROM tbl_thtr_m1 t
     WHERE t.seat <> (SELECT count(*) FROM tbl_seat_m1 s WHERE s.thtr_id = t.thtr_id AND s.status = 'Y');
    IF bad > 0 THEN RAISE EXCEPTION '대량 샘플 검증 실패: 총 좌석 수와 Y 상태 좌석 수가 다른 상영관 %개', bad; END IF;

    -- capacity = planned_capacity <= 총 좌석 수
    SELECT count(*) INTO bad FROM tbl_scrn_m1 s JOIN tbl_thtr_m1 t ON t.thtr_id = s.thtr_id
     WHERE s.capacity <> s.planned_capacity OR s.planned_capacity > t.seat;
    IF bad > 0 THEN RAISE EXCEPTION '대량 샘플 검증 실패: 계획 좌석 수·이용 가능 좌석 수 규칙을 어긴 상영 %개', bad; END IF;

    -- 예매 수 <= 이용 가능 좌석 수
    SELECT count(*) INTO bad FROM tbl_scrn_m1 s
     WHERE (SELECT count(*) FROM tbl_bytk_d1 b WHERE b.scrn_id = s.scrn_id) > s.capacity;
    IF bad > 0 THEN RAISE EXCEPTION '대량 샘플 검증 실패: 예매 수가 이용 가능 좌석 수를 넘는 상영 %개', bad; END IF;

    -- 예매에 이용 불가 좌석이 지정되지 않음 (이 샘플은 좌석을 지정하지 않는다)
    SELECT count(*) INTO bad FROM tbl_bytk_d1 b JOIN tbl_seat_m1 s ON s.thtr_id = b.thtr_id AND s.seatcode = b.seatcode
     WHERE s.status <> 'Y';
    IF bad > 0 THEN RAISE EXCEPTION '대량 샘플 검증 실패: 이용 불가 좌석이 지정된 예매 %건', bad; END IF;
END $$;

ALTER TABLE tbl_thtr_m1 ENABLE TRIGGER USER;
ALTER TABLE tbl_seat_m1 ENABLE TRIGGER USER;
ALTER TABLE tbl_scrn_m1 ENABLE TRIGGER USER;
ALTER TABLE tbl_bytk_d1 ENABLE TRIGGER USER;
