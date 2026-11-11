-- 측정용 대량 샘플. 실행 순서는 아래와 같다.
--   1) postgresql_create_ddl.sql
--   2) postgresql_insert_data.sql
--   3) ../migration/shift_dates_to_current.sql  (기존 샘플의 날짜를 오늘 기준으로 옮김)
--   4) 이 파일
--   5) postgresql_verify_data.sql  (규칙 위반이 없는지 확인)

-- =====================================================================================================
-- 난수 대신 md5 해시로 값을 만들기 때문에 같은 날 다시 실행해도 항상 같은 데이터가 생성된다.
-- 기존 샘플과 겹치지 않는 ID 범위를 사용하므로 기존 샘플(30명, 30대, 20곳)은 그대로 남는다.
--
--   대여소 400곳  25개 구 x 16곳, ID '01101'~'25116', 이름 '샘플대여소 01101'
--   자전거 2,500대  GN00101~GN02100(일반 2,000대), SD02101~SD02600(새싹 500대)
--   회원 20,000명  ID 'bulk000001'~
--   대여 약 33만 건  최근 365일(오늘 0시 이전). 하루를 8시간 구간 3개로 나눠 자전거마다 구간당 최대 1건
--   이용권, 보충/수거, 파손/분실, 즐겨찾기, 거치대는 대여 이력에서 이어서 만든다.
--
-- 지키는 규칙 (postgresql_insert_data.sql을 다듬을 때 정한 규칙과 같다)
--   * 자전거 상태: ING는 거치대에 없고 미반납 대여가 있다. LST는 확정된 분실(liable Y, confirm Y)과 연결된
--     미반납 대여가 있고 거치대에 없다. COL/RP는 마지막 이벤트가 수거(CL)이고 거치대에 없다.
--     AVL/DMG는 마지막 위치의 거치대에 있다. PD는 설치 전이라 이력이 없다.
--   * 대여 연속성: 같은 자전거의 다음 대여 시작 대여소 = 이전 반납 대여소. 사이에 보충(SP)이 있으면 그 보충 대여소.
--     수거(CL) 대여소 = 직전 위치. 수거 뒤에는 보충(SP)을 거쳐야 다시 대여한다.
--   * 대여소 avail = 그 대여소 거치대에 있는 AVL 자전거 수.
--   * 요금: 대여는 선불이다. 1시간당 성인 1,000원, 성인이 아닌 회원 800원이고 만 19세 이상이 성인이다.
--     고정 시간을 넘으면 10분마다 성인 300원, 성인이 아닌 회원(만 12세 미만 포함) 200원이 붙는다.
--     * 이용권이 없는 일반 대여: 요금 = 고정 시간(1시간 또는 2시간) 요금 + 초과분. 고정 시간은 tblrentT1.fixhour에 있고,
--       이용 시간이 길수록 2시간을 고를 확률이 높게 정했다. (45분 이하 5%, 90분 이하 35%, 그보다 길면 60%)
--     * 일일권(PRE1A 1시간, PRE2A 2시간) 구매 후 첫 대여: 요금 = 일일권 금액 - 사용 마일리지 + 초과분.
--       나이는 이용권 구매일 기준이다. 일일권 금액은 나이에 따라 달라져서 tbltickD1에는 저장하지 않는다.
--       일일권 시간 안의 나머지 대여는 일반 대여다.
--     * 정기권 구매 후 첫 대여: 요금 = 이용권 금액 - 사용 마일리지 + 이용 시간 초과분.
--       정기권이 유효한 동안의 대여는 이용 시간 이내 0원, 초과분만 낸다.
--   * 속도: 15분 이하 대여는 시속 30km 이내, 그보다 길면 시속 19km 이내.
--   * 한 자전거와 한 회원은 같은 시간에 두 대여를 하지 않는다. 미반납 대여는 자전거마다, 회원마다 하나뿐이다.
--
-- 날짜 기준은 CURRENT_DATE다. 모든 시각은 오늘 0시를 넘지 않아서 하루 안에서는 항상 같은 데이터가 된다.
-- 이용권 종료일처럼 앞으로의 날짜는 오늘을 넘을 수 있다.
-- =====================================================================================================

BEGIN;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM tblmebrM1 WHERE mebr_id = 'bulk000001') THEN
        RAISE EXCEPTION '대량 샘플이 이미 적재되어 있습니다. 테이블을 비우거나 새로 만든 뒤 실행하세요.';
    END IF;
END
$$;

-- 시드 문자열의 md5(32자리)에서 7자리씩 꺼내 쓴다. pos가 7 이상 차이 나면 서로 겹치지 않는 값이다.
CREATE FUNCTION pg_temp.hx(h TEXT, pos INT) RETURNS INT AS $$
    SELECT ('x' || substr(h, pos, 7))::bit(28)::INT
$$ LANGUAGE sql IMMUTABLE;

-- 0 이상 1 미만 실수
CREATE FUNCTION pg_temp.hu(h TEXT, pos INT) RETURNS DOUBLE PRECISION AS $$
    SELECT (('x' || substr(h, pos, 7))::bit(28)::INT)::DOUBLE PRECISION / 268435456.0
$$ LANGUAGE sql IMMUTABLE;

-- 구 번호와 0~1 값으로 대여소 ID를 고른다. 번호가 작은 대여소일수록 자주 고른다.
CREATE FUNCTION pg_temp.st_id(gu INT, u DOUBLE PRECISION) RETURNS CHAR(5) AS $$
    SELECT (lpad(gu::text, 2, '0') || (101 + floor(16 * power(u, 1.5))::INT)::text)::CHAR(5)
$$ LANGUAGE sql IMMUTABLE;

-- 반납 대여소: 85%는 자전거의 소속 구, 나머지는 아무 구
CREATE FUNCTION pg_temp.dest_st(home INT, h TEXT) RETURNS CHAR(5) AS $$
    SELECT pg_temp.st_id(CASE WHEN pg_temp.hu(h, 1) < 0.85 THEN home ELSE 1 + pg_temp.hx(h, 8) % 25 END,
                         pg_temp.hu(h, 15))
$$ LANGUAGE sql IMMUTABLE;

CREATE TEMP TABLE bulk_cfg AS
SELECT CURRENT_DATE::TIMESTAMP AS snap, CURRENT_DATE - 365 AS d0;

-- 날짜별 이용 계수 (d = 0이 365일 전, 364가 어제)
CREATE TEMP TABLE bulk_day AS
SELECT x.d, x.dt, x.dow, x.mon,
       CASE x.mon WHEN 1 THEN 0.45 WHEN 2 THEN 0.5 WHEN 3 THEN 0.85 WHEN 4 THEN 1.2 WHEN 5 THEN 1.35
                  WHEN 6 THEN 1.1 WHEN 7 THEN 0.85 WHEN 8 THEN 0.9 WHEN 9 THEN 1.3 WHEN 10 THEN 1.35
                  WHEN 11 THEN 0.8 ELSE 0.5 END AS sf
FROM (
    SELECT d, (c.d0 + d)::TIMESTAMP AS dt,
           EXTRACT(DOW FROM c.d0 + d)::INT AS dow, EXTRACT(MONTH FROM c.d0 + d)::INT AS mon
    FROM bulk_cfg c, generate_series(0, 364) AS d
) x;

-- 구간(j: 0=0~8시, 1=8~16시, 2=16~24시) 안에서 시작 시각의 가중치. 출퇴근 시간이 많다.
CREATE TEMP TABLE bulk_hourw AS
SELECT j, hr, tot, SUM(w) OVER (PARTITION BY j ORDER BY hr) - w AS lo, SUM(w) OVER (PARTITION BY j ORDER BY hr) AS hi
FROM (
    SELECT j, hr, w, SUM(w) OVER (PARTITION BY j) AS tot
    FROM (VALUES (0,0,1),(0,1,1),(0,2,1),(0,3,1),(0,4,2),(0,5,6),(0,6,12),(0,7,15),
                 (1,0,15),(1,1,10),(1,2,6),(1,3,6),(1,4,8),(1,5,8),(1,6,7),(1,7,7),
                 (2,0,8),(2,1,14),(2,2,16),(2,3,12),(2,4,8),(2,5,6),(2,6,4),(2,7,2)) AS v(j, hr, w)
) q;

CREATE FUNCTION pg_temp.pick_hr(jj INT, r INT) RETURNS INT AS $$
    SELECT hr FROM bulk_hourw WHERE j = jj AND (r % tot) >= lo AND (r % tot) < hi
$$ LANGUAGE sql STABLE;

-- =====================================================================================================
-- 대여소 400곳
-- =====================================================================================================
CREATE TEMP TABLE bulk_gu (gu_no INT, gu_name TEXT);
INSERT INTO bulk_gu VALUES
    (1,'강남구'),(2,'강동구'),(3,'강북구'),(4,'강서구'),(5,'관악구'),(6,'광진구'),(7,'구로구'),(8,'금천구'),
    (9,'노원구'),(10,'도봉구'),(11,'동대문구'),(12,'동작구'),(13,'마포구'),(14,'서대문구'),(15,'서초구'),
    (16,'성동구'),(17,'성북구'),(18,'송파구'),(19,'양천구'),(20,'영등포구'),(21,'용산구'),(22,'은평구'),
    (23,'종로구'),(24,'중구'),(25,'중랑구');

CREATE TEMP TABLE bulk_rtpl AS
SELECT lpad(g.gu_no::text, 2, '0') || (100 + n)::text AS rtpl_id,
       g.gu_no,
       '샘플대여소 ' || lpad(g.gu_no::text, 2, '0') || (100 + n)::text AS space,
       '서울특별시 ' || g.gu_name || ' '
           || (ARRAY['중앙로','시장로','공원로','강변로','학교로','역말로','언덕로','하늘로'])[1 + (n + g.gu_no) % 8]
           || ' ' || (10 + (('x' || substr(md5('rtpl' || g.gu_no || '/' || n), 1, 7))::bit(28)::INT) % 190)::text AS addr
FROM bulk_gu g, generate_series(1, 16) AS n;

-- =====================================================================================================
-- 자전거 2,500대
-- =====================================================================================================
CREATE TEMP TABLE bulk_bike AS
SELECT n,
       CASE WHEN n <= 2100 THEN 'GN' ELSE 'SD' END AS gubun,
       (CASE WHEN n <= 2100 THEN 'GN' ELSE 'SD' END) || lpad(n::text, 5, '0') AS bycl_id,
       h, h2,
       CASE WHEN pg_temp.hx(h, 1) % 1000 < 20 THEN 'PD'
            WHEN pg_temp.hx(h, 1) % 1000 < 40 THEN 'ING'
            WHEN pg_temp.hx(h, 1) % 1000 < 50 THEN 'LST'
            WHEN pg_temp.hx(h, 1) % 1000 < 65 THEN 'COL'
            WHEN pg_temp.hx(h, 1) % 1000 < 80 THEN 'RP'
            WHEN pg_temp.hx(h, 1) % 1000 < 100 THEN 'DMG'
            ELSE 'AVL' END AS fate,
       1 + n % 25 AS gu_no,
       0.5 + (pg_temp.hx(h, 8) % 1000) / 1000.0 AS act
FROM (SELECT n, md5('bike' || n) AS h, md5('bike2' || n) AS h2 FROM generate_series(101, 2600) AS n) b;

ALTER TABLE bulk_bike ADD COLUMN cutoff_day INT, ADD COLUMN late_day INT,
                      ADD COLUMN registerdate TIMESTAMP, ADD COLUMN installdate TIMESTAMP, ADD COLUMN s0 CHAR(5);

-- 수거되거나 분실되는 자전거는 이 날(d) 이전까지만 대여한다
UPDATE bulk_bike SET cutoff_day = 60 + pg_temp.hx(h2, 1) % 270 WHERE fate IN ('LST', 'COL', 'RP');
-- 일부 AVL/DMG 자전거는 기간 중간에 새로 설치한다
UPDATE bulk_bike SET late_day = pg_temp.hx(h2, 8) % 300
WHERE fate IN ('AVL', 'DMG') AND pg_temp.hx(h2, 15) % 100 < 15;

UPDATE bulk_bike b SET
    registerdate = c.snap - make_interval(days => 3 + pg_temp.hx(b.h2, 22) % 57, secs => pg_temp.hx(b.h, 15) % 86400)
FROM bulk_cfg c WHERE b.fate = 'PD';
UPDATE bulk_bike b SET
    installdate  = c.d0 + make_interval(days => b.late_day, secs => pg_temp.hx(b.h, 15) % 86400)
FROM bulk_cfg c WHERE b.late_day IS NOT NULL;
UPDATE bulk_bike SET
    registerdate = installdate - make_interval(days => 1 + pg_temp.hx(h2, 22) % 20, secs => pg_temp.hx(h, 22) % 86400)
WHERE late_day IS NOT NULL;
UPDATE bulk_bike b SET
    registerdate = c.d0 - make_interval(days => 20 + pg_temp.hx(b.h2, 22) % 280, secs => pg_temp.hx(b.h, 15) % 86400)
FROM bulk_cfg c WHERE b.fate <> 'PD' AND b.late_day IS NULL;
UPDATE bulk_bike SET
    installdate = registerdate + make_interval(days => 1 + pg_temp.hx(h, 22) % 14, secs => pg_temp.hx(h2, 15) % 86400)
WHERE fate <> 'PD' AND late_day IS NULL;

-- 처음 설치한 대여소는 소속 구 안에서 고른다
UPDATE bulk_bike SET s0 = pg_temp.st_id(gu_no, pg_temp.hu(h, 22)) WHERE fate <> 'PD';

-- =====================================================================================================
-- 회원 20,000명 (마지막 300명은 미반납 대여 전용)
-- =====================================================================================================
CREATE TEMP TABLE bulk_mebr AS
SELECT g, 'bulk' || lpad(g::text, 6, '0') AS mebr_id, h
FROM (SELECT g, md5('mebr' || g) AS h FROM generate_series(1, 20000) AS g) m;

ALTER TABLE bulk_mebr ADD COLUMN name TEXT, ADD COLUMN sex CHAR(1), ADD COLUMN birth DATE, ADD COLUMN phone CHAR(11),
                      ADD COLUMN points INT, ADD COLUMN signupmethod CHAR(2), ADD COLUMN grp CHAR(1);

UPDATE bulk_mebr SET
    name = (ARRAY['김','이','박','최','정','강','조','윤','장','임','한','오','서','신','권','황','안','송','류','홍'])[1 + pg_temp.hx(h, 1) % 20]
        || (ARRAY['민','서','지','도','하','예','주','시','현','수','준','유','채','건','우','은','재','태','나','승'])[1 + pg_temp.hx(h, 8) % 20]
        || (ARRAY['준','윤','우','아','진','연','현','원','영','서','민','빈','은','호','린','환','훈','희','안','솔'])[1 + pg_temp.hx(h, 15) % 20],
    sex = CASE WHEN pg_temp.hx(h, 22) % 2 = 0 THEN 'M' ELSE 'F' END,
    -- 회원의 3%는 만 6~11세 어린이, 나머지는 만 14~70세
    birth = CASE WHEN pg_temp.hu(h, 1) < 0.03
                 THEN CURRENT_DATE - (6 * 365 + floor(pg_temp.hu(h, 1) / 0.03 * 5 * 365))::INT
                 ELSE CURRENT_DATE - floor(365.25 * (14 + 56 * power(pg_temp.hu(h, 1), 1.6)))::INT END,
    phone = '010' || lpad((10000000 + (g::BIGINT * 7919) % 90000000)::text, 8, '0'),
    points = 100 * (pg_temp.hx(h, 8) % 101),
    signupmethod = CASE WHEN pg_temp.hx(h, 15) % 100 < 55 THEN 'GN' WHEN pg_temp.hx(h, 15) % 100 < 75 THEN 'NV'
                        WHEN pg_temp.hx(h, 15) % 100 < 90 THEN 'KA' ELSE 'GG' END,
    -- 정기권을 사는 회원(P)과 일일권을 사는 회원(R). 미반납 전용 회원은 이용권이 없다.
    grp = CASE WHEN g > 19700 THEN 'X'
               WHEN pg_temp.hx(h, 22) % 100 < 22 THEN 'P'
               WHEN pg_temp.hx(h, 22) % 100 < 34 THEN 'R' ELSE 'X' END;

-- =====================================================================================================
-- 대여 이력 만들기
--   자전거마다 (날짜 d, 구간 j) 칸을 돌면서 해시가 이용 확률보다 작은 칸에 대여를 한 건 넣는다.
--   대여는 구간 안에서 끝나므로 한 자전거의 대여는 겹치지 않는다.
-- =====================================================================================================
CREATE TEMP TABLE bulk_rent0 AS
WITH cell AS (
    SELECT b.n AS bn, b.bycl_id, b.gu_no, b.fate, b.s0, d.d, d.dt, j.j,
           md5('cell' || b.n || '/' || d.d || '/' || j.j) AS h,
           (CASE j.j WHEN 0 THEN CASE WHEN d.dow IN (0, 6) THEN 0.035 ELSE 0.105 END
                     WHEN 1 THEN CASE WHEN d.dow IN (0, 6) THEN 0.19  ELSE 0.115 END
                     ELSE        CASE WHEN d.dow IN (0, 6) THEN 0.25  ELSE 0.19  END END) * d.sf * b.act AS p
    FROM bulk_bike b
    JOIN bulk_day d ON (b.late_day IS NULL OR d.d > b.late_day)
                   AND (b.cutoff_day IS NULL OR d.d < b.cutoff_day)
    CROSS JOIN generate_series(0, 2) AS j(j)
    WHERE b.fate <> 'PD'
      -- 이용 중(ING)인 자전거는 어제 오후 4시 이후에 미반납 대여를 하나 가진다
      AND NOT (b.fate = 'ING' AND d.d = 364 AND j.j = 2)
), pick AS (
    SELECT c.*, md5(c.h || 'x') AS h2 FROM cell c WHERE pg_temp.hu(c.h, 1) < c.p
), timed AS (
    SELECT p.*,
           LEAST(pg_temp.pick_hr(p.j, pg_temp.hx(p.h, 8)) * 60 + pg_temp.hx(p.h, 15) % 60, 474) AS start_min,
           CASE WHEN pg_temp.hx(p.h2, 1) % 100 < 55 THEN 5 + pg_temp.hx(p.h2, 8) % 21
                WHEN pg_temp.hx(p.h2, 1) % 100 < 85 THEN 26 + pg_temp.hx(p.h2, 8) % 35
                WHEN pg_temp.hx(p.h2, 1) % 100 < 97 THEN 61 + pg_temp.hx(p.h2, 8) % 60
                ELSE 121 + pg_temp.hx(p.h2, 8) % 120 END AS dur0
    FROM pick p
)
SELECT t.bn, t.bycl_id, t.gu_no, t.fate, t.s0, t.d, t.j, t.h2,
       ROW_NUMBER() OVER (PARTITION BY t.bn ORDER BY t.d, t.j) AS k,
       t.dt + make_interval(hours => 8 * t.j, mins => t.start_min) AS rentdate,
       LEAST(t.dur0, 479 - t.start_min) AS dur
FROM timed t;

CREATE INDEX ON bulk_rent0 (bn, k);

-- 반납 대여소, 파손/분실 신고
CREATE TEMP TABLE bulk_rent1 AS
SELECT r.*,
       r.rentdate + make_interval(mins => r.dur) AS returndate,
       pg_temp.dest_st(r.gu_no, md5('ret' || r.bn || '/' || r.k)) AS ret_st,
       MAX(r.k) OVER (PARTITION BY r.bn) AS max_k,
       CASE WHEN pg_temp.hu(r.h2, 15) < 0.010 THEN 'DM'
            WHEN pg_temp.hu(r.h2, 15) < 0.0125 THEN 'LS' END AS flag0
FROM bulk_rent0 r;

-- 파손(DMG) 자전거와 수거(COL) 자전거는 마지막 대여에 파손 신고가 있다
CREATE TEMP TABLE bulk_rent2 AS
SELECT r.*,
       CASE WHEN r.fate IN ('DMG', 'COL') AND r.k = r.max_k THEN 'DM' ELSE r.flag0 END AS flag,
       LAG(r.returndate) OVER w AS prev_ret_ts,
       LAG(r.ret_st) OVER w AS prev_ret_st,
       LAG(CASE WHEN r.fate IN ('DMG', 'COL') AND r.k = r.max_k THEN 'DM' ELSE r.flag0 END) OVER w AS prev_flag
FROM bulk_rent1 r
WINDOW w AS (PARTITION BY r.bn ORDER BY r.k);

-- 대여 사이(gap)에 생기는 보충/수거: 수거(CL)는 직전 대여소에서, 보충(SP)은 소속 구의 대여소로
CREATE TEMP TABLE bulk_gap AS
SELECT g.*,
       prev_ret_ts + (rentdate - prev_ret_ts) * (CASE WHEN ev = 'SP' THEN 0.5 ELSE 0.6 END) AS sp_ts_raw,
       prev_ret_ts + (rentdate - prev_ret_ts) * 0.15 AS cl_ts_raw
FROM (
    SELECT r.bn, r.k, r.prev_ret_ts, r.prev_ret_st, r.rentdate, r.gu_no,
           CASE WHEN gm >= 720 AND r.prev_flag = 'DM' AND pg_temp.hu(hh, 1) < 0.6 THEN 'CLDM'
                WHEN gm >= 720 AND pg_temp.hu(hh, 8) < 0.004 THEN 'CLRP'
                WHEN gm >= 360 AND pg_temp.hu(hh, 15) < 0.03 THEN 'SP' END AS ev,
           pg_temp.st_id(r.gu_no, pg_temp.hu(hh, 22)) AS sp_st
    FROM (
        SELECT r.*, md5('gap' || r.bn || '/' || r.k) AS hh,
               EXTRACT(EPOCH FROM (r.rentdate - r.prev_ret_ts)) / 60 AS gm
        FROM bulk_rent2 r WHERE r.k >= 2
    ) r
) g
WHERE g.ev IS NOT NULL;

-- 각 대여의 시작 대여소: 사이에 보충이 있으면 보충 대여소, 없으면 이전 반납 대여소, 첫 대여는 처음 설치한 대여소
CREATE TEMP TABLE bulk_rent3 AS
SELECT r.*,
       COALESCE(g.sp_st, r.prev_ret_st, r.s0) AS start_st
FROM bulk_rent2 r
LEFT JOIN bulk_gap g ON g.bn = r.bn AND g.k = r.k;

-- 마지막 대여 이후의 위치
CREATE TEMP TABLE bulk_last AS
SELECT DISTINCT ON (r.bn) r.bn, r.ret_st, r.returndate
FROM bulk_rent3 r ORDER BY r.bn, r.k DESC;

-- 마지막 대여 이후의 보충/수거
--   AVL 자전거의 일부는 마지막 대여 뒤에 보충된다. COL/RP 자전거는 cutoff_day에 수거된다.
CREATE TEMP TABLE bulk_tail AS
SELECT b.n AS bn, 'SP'::CHAR(2) AS spclgubun, NULL::CHAR(2) AS collectreason,
       pg_temp.st_id(b.gu_no, pg_temp.hu(b.h2, 22)) AS rtpl_id,
       date_trunc('minute', l.returndate + (c.snap - l.returndate) * 0.5) AS spcldate
FROM bulk_bike b
JOIN bulk_last l ON l.bn = b.n
CROSS JOIN bulk_cfg c
WHERE b.fate = 'AVL' AND pg_temp.hu(b.h2, 15) < 0.10 AND c.snap - l.returndate >= INTERVAL '12 hours'
UNION ALL
SELECT b.n AS bn, 'CL', CASE b.fate WHEN 'COL' THEN 'DM' ELSE 'RP' END,
       COALESCE(l.ret_st, b.s0),
       c.d0::TIMESTAMP + make_interval(days => b.cutoff_day, hours => 8 + pg_temp.hx(b.h2, 15) % 12,
                                       mins => pg_temp.hx(b.h2, 22) % 60)
FROM bulk_bike b
LEFT JOIN bulk_last l ON l.bn = b.n
CROSS JOIN bulk_cfg c
WHERE b.fate IN ('COL', 'RP');

-- 자전거별 마지막 위치 (거치대에 있는 AVL/DMG 자전거가 들어갈 대여소)
CREATE TEMP TABLE bulk_loc AS
SELECT b.n AS bn, b.bycl_id, b.gubun, b.fate,
       COALESCE(t.rtpl_id, l.ret_st, b.s0) AS rtpl_id
FROM bulk_bike b
LEFT JOIN bulk_last l ON l.bn = b.n
LEFT JOIN bulk_tail t ON t.bn = b.n AND t.spclgubun = 'SP'
WHERE b.fate IN ('AVL', 'DMG');

-- 미반납 대여 (이용 중 ING는 어제 저녁에 시작해 아직 타는 중, 분실 LST는 cutoff_day에 빌려 가서 돌아오지 않음)
CREATE TEMP TABLE bulk_open AS
WITH o AS (
    SELECT b.n AS bn, b.bycl_id, b.gu_no, b.fate, b.h2,
           COALESCE(l.ret_st, b.s0) AS start_st,
           CASE b.fate
               WHEN 'ING' THEN c.snap - make_interval(mins => 20 + pg_temp.hx(b.h2, 1) % 380)
               ELSE c.d0::TIMESTAMP + make_interval(days => b.cutoff_day)
                    + make_interval(hours => 8 * (pg_temp.hx(b.h2, 1) % 3))
                    + make_interval(mins => LEAST(pg_temp.pick_hr(pg_temp.hx(b.h2, 1) % 3, pg_temp.hx(b.h2, 8)) * 60
                                                  + pg_temp.hx(b.h2, 15) % 60, 474))
           END AS rentdate
    FROM bulk_bike b
    LEFT JOIN bulk_last l ON l.bn = b.n
    CROSS JOIN bulk_cfg c
    WHERE b.fate IN ('ING', 'LST')
)
SELECT o.*,
       CASE o.fate WHEN 'ING' THEN (EXTRACT(EPOCH FROM (c.snap - o.rentdate)) / 60)::INT
                   ELSE 10 + pg_temp.hx(o.h2, 22) % 170 END AS dur
FROM o CROSS JOIN bulk_cfg c;

-- 모든 대여를 한 테이블로. 회원은 칸(d, j)마다 서로 다른 회원이 되도록 정한다.
--   칸 안에서 번호(rank)에 7919를 곱해 더하면 같은 칸의 대여는 모두 다른 회원이 된다. (7919와 19700은 서로소)
--   칸이 다르면 시간이 겹치지 않으므로 한 회원의 대여도 겹치지 않는다.
CREATE TEMP TABLE bulk_rent AS
SELECT ROW_NUMBER() OVER (ORDER BY q.rentdate, q.bycl_id) AS rid, q.*
FROM (
    SELECT r.bycl_id, r.rentdate, r.dur, r.start_st AS rtpl_id, r.ret_st AS retrtpl_id, r.returndate,
           FALSE AS is_open, r.flag,
           ((pg_temp.hx(md5('mb' || r.d || '/' || r.j), 1) % 19700)
               + ROW_NUMBER() OVER (PARTITION BY r.d, r.j ORDER BY r.bn)::BIGINT * 7919) % 19700 + 1 AS mebr_idx,
           md5('met' || r.bn || '/' || r.k) AS hm
    FROM bulk_rent3 r
    UNION ALL
    SELECT o.bycl_id, o.rentdate, o.dur, o.start_st, NULL, NULL,
           TRUE, CASE o.fate WHEN 'LST' THEN 'LS' END,
           19700 + ROW_NUMBER() OVER (ORDER BY o.bn),
           md5('met' || o.bn || '/open')
    FROM bulk_open o
) q;

ALTER TABLE bulk_rent ADD COLUMN dist NUMERIC(6,2), ADD COLUMN kcal NUMERIC(7,2), ADD COLUMN carbon NUMERIC(6,3),
                      ADD COLUMN fee INT, ADD COLUMN fixhour SMALLINT;
CREATE UNIQUE INDEX ON bulk_rent (rid);
CREATE INDEX ON bulk_rent (mebr_idx, rentdate);

-- 이동거리/칼로리/탄소: 15분 이하는 시속 8~30km, 그보다 길면 시속 4~19km
UPDATE bulk_rent SET
    dist = round(((CASE WHEN dur <= 15 THEN 8 + 22 * pg_temp.hu(hm, 1) ELSE 4 + 15 * pg_temp.hu(hm, 1) END) * dur / 60.0)::NUMERIC, 2);
UPDATE bulk_rent SET
    kcal   = round(dist * (20 + 21 * pg_temp.hu(hm, 8))::NUMERIC, 2),
    carbon = round(dist * (0.10 + 0.20 * pg_temp.hu(hm, 15))::NUMERIC, 3);

-- =====================================================================================================
-- 이용권
-- =====================================================================================================
CREATE TEMP TABLE bulk_mr AS
SELECT r.rid, r.mebr_idx, r.rentdate,
       ROW_NUMBER() OVER (PARTITION BY r.mebr_idx ORDER BY r.rentdate) AS mrn,
       COUNT(*) OVER (PARTITION BY r.mebr_idx) AS mcnt
FROM bulk_rent r;
CREATE INDEX ON bulk_mr (mebr_idx, rentdate);

CREATE TEMP TABLE bulk_tick (
    mebr_idx INT, prid BIGINT, kind CHAR(1), ticket VARCHAR(8), startdate TIMESTAMP, enddate TIMESTAMP,
    points INT, paymethod VARCHAR(4), period INT, usehour INT, price INT
);

-- 이용권 종류(기간/이용 시간/금액)와 결제수단을 해시에서 고른다.
-- 금액은 이용권 코드의 금액 3자리 x 100원이다. (30일 6,000/9,000원 ... 365일 45,000/55,000원)
CREATE FUNCTION pg_temp.tspec(hh TEXT) RETURNS TABLE (period INT, usehour INT, price INT) AS $$
    SELECT pe.period, hr.usehour,
           CASE pe.period WHEN 30  THEN CASE hr.usehour WHEN 1 THEN 6000  ELSE 9000  END
                          WHEN 90  THEN CASE hr.usehour WHEN 1 THEN 15000 ELSE 21000 END
                          WHEN 180 THEN CASE hr.usehour WHEN 1 THEN 27000 ELSE 35000 END
                          ELSE          CASE hr.usehour WHEN 1 THEN 45000 ELSE 55000 END END
    FROM (SELECT CASE WHEN pg_temp.hx(hh, 1) % 100 < 35 THEN 30 WHEN pg_temp.hx(hh, 1) % 100 < 65 THEN 90
                      WHEN pg_temp.hx(hh, 1) % 100 < 85 THEN 180 ELSE 365 END AS period) pe,
         (SELECT CASE WHEN pg_temp.hx(hh, 8) % 100 < 60 THEN 1 ELSE 2 END AS usehour) hr
$$ LANGUAGE sql IMMUTABLE;

CREATE FUNCTION pg_temp.paym(hh TEXT) RETURNS VARCHAR(4) AS $$
    SELECT CASE WHEN pg_temp.hx(hh, 22) % 100 < 30 THEN 'CP' || (ARRAY['SH','KB','IB','WB','NH'])[1 + pg_temp.hx(hh, 15) % 5]
                WHEN pg_temp.hx(hh, 22) % 100 < 45 THEN 'BT' || (ARRAY['SH','KB','IB','WB','NH'])[1 + pg_temp.hx(hh, 15) % 5]
                WHEN pg_temp.hx(hh, 22) % 100 < 60 THEN 'NV'
                WHEN pg_temp.hx(hh, 22) % 100 < 75 THEN 'KA'
                WHEN pg_temp.hx(hh, 22) % 100 < 90 THEN 'TO' ELSE 'ML' END
$$ LANGUAGE sql IMMUTABLE;

-- 정기권 첫 번째: 정기권을 사는 회원(P)의 대여 중 하나를 구매 직후 첫 대여로 삼는다.
INSERT INTO bulk_tick (mebr_idx, prid, kind, ticket, startdate, enddate, points, paymethod, period, usehour, price)
SELECT c.g, c.rid, 'P',
       lpad(s.period::text, 3, '0') || s.usehour || lpad((s.price / 100)::text, 3, '0') || 'A',
       c.rentdate - make_interval(mins => 1 + pg_temp.hx(c.hh, 15) % 15),
       c.rentdate - make_interval(mins => 1 + pg_temp.hx(c.hh, 15) % 15) + make_interval(days => s.period),
       LEAST(s.price, 500 * (pg_temp.hx(c.hh, 22) % 11)),
       pg_temp.paym(c.hh), s.period, s.usehour, s.price
FROM (
    SELECT m.g, r.rid, r.rentdate, md5('tk1' || m.g) AS hh
    FROM bulk_mebr m
    JOIN bulk_mr r ON r.mebr_idx = m.g AND r.mrn = 1 + pg_temp.hx(m.h, 15) % r.mcnt
    WHERE m.grp = 'P'
) c
CROSS JOIN LATERAL pg_temp.tspec(c.hh) s;

-- 정기권 두 번째: 첫 번째가 끝난 뒤 다시 대여한 회원의 절반이 새로 산다. 유효 기간이 겹치지 않는다.
INSERT INTO bulk_tick (mebr_idx, prid, kind, ticket, startdate, enddate, points, paymethod, period, usehour, price)
SELECT c.mebr_idx, c.rid, 'P',
       lpad(s.period::text, 3, '0') || s.usehour || lpad((s.price / 100)::text, 3, '0') || 'A',
       c.rentdate - make_interval(mins => 1 + pg_temp.hx(c.hh, 15) % 15),
       c.rentdate - make_interval(mins => 1 + pg_temp.hx(c.hh, 15) % 15) + make_interval(days => s.period),
       LEAST(s.price, 500 * (pg_temp.hx(c.hh, 22) % 11)),
       pg_temp.paym(c.hh), s.period, s.usehour, s.price
FROM (
    SELECT DISTINCT ON (t.mebr_idx) t.mebr_idx, r.rid, r.rentdate, md5('tk2' || t.mebr_idx) AS hh
    FROM bulk_tick t
    JOIN bulk_mr r ON r.mebr_idx = t.mebr_idx
                  AND r.rentdate >= t.enddate + make_interval(days => pg_temp.hx(md5('tk2gap' || t.mebr_idx), 1) % 10, mins => 15)
    WHERE t.kind = 'P' AND pg_temp.hx(md5('tk2' || t.mebr_idx), 8) % 100 < 50
    ORDER BY t.mebr_idx, r.rentdate
) c
CROSS JOIN LATERAL pg_temp.tspec(c.hh) s;

-- 일일권: 일일권을 사는 회원(R)의 대여 중 하나 직전에 산다. 1시간권(PRE1A) 또는 2시간권(PRE2A)
--   price에는 일일권 금액을 둔다. 1시간당 성인 1,000원, 성인이 아닌 회원 800원 (이용권 구매일 기준 만 19세 이상이 성인)
INSERT INTO bulk_tick (mebr_idx, prid, kind, ticket, startdate, enddate, points, paymethod, period, usehour, price)
SELECT c.g, c.rid, 'R',
       'PRE' || c.usehour || 'A',
       c.st, c.st + make_interval(hours => c.usehour),
       LEAST(c.price, (ARRAY[0, 0, 0, 500, 1000])[1 + pg_temp.hx(c.hh, 22) % 5]),
       pg_temp.paym(c.hh), NULL, c.usehour,
       c.price
FROM (
    SELECT q.*, q.usehour * CASE WHEN EXTRACT(YEAR FROM AGE(q.st::DATE, q.birth)) >= 19 THEN 1000 ELSE 800 END AS price
    FROM (
        SELECT m.g, m.birth, r.rid, md5('pre' || m.g) AS hh,
               CASE WHEN pg_temp.hx(md5('pre' || m.g), 8) % 100 < 60 THEN 1 ELSE 2 END AS usehour,
               r.rentdate - make_interval(mins => 1 + pg_temp.hx(md5('pre' || m.g), 15) % 10) AS st
        FROM bulk_mebr m
        JOIN bulk_mr r ON r.mebr_idx = m.g AND r.mrn = 1 + pg_temp.hx(m.h, 15) % r.mcnt
        WHERE m.grp = 'R'
    ) q
) c;

-- 요금
--   초과분은 10분마다 성인 300원, 성인이 아닌 회원 200원 (나이는 대여일 기준, 일일권은 이용권 구매일 기준)
--   일반: 고정 시간 요금(1시간당 성인 1,000원, 성인이 아닌 회원 800원) + 초과분
--   정기권 구매 후 첫 대여: 이용권 금액 - 사용 마일리지 + 이용 시간 초과분
--   정기권 유효 중: 이용 시간 이내 0원, 초과분만
--   일일권(PRE) 구매 후 첫 대여: 일일권 금액 - 사용 마일리지 + 고정 시간 초과분
--   고정 대여 시간(fixhour): 이용권이 있는 대여는 이용권의 시간, 일반 대여는 이용 시간이 길수록 2시간을 고를 확률이 높다.
--   (45분 이하 5%, 90분 이하 35%, 그보다 길면 60%)
UPDATE bulk_rent r SET fee = f.fee, fixhour = f.hh
FROM (
    SELECT s.rid, s.hh,
           CASE WHEN s.t_prid IS NOT NULL AND s.t_prid = s.rid
                     THEN s.t_price - s.t_points
                          + CASE WHEN s.adult THEN 300 ELSE 200 END * GREATEST(0, CEIL((s.dur - 60 * s.hh) / 10.0))::INT
                WHEN s.t_prid IS NOT NULL
                     THEN CASE WHEN s.adult THEN 300 ELSE 200 END * GREATEST(0, CEIL((s.dur - 60 * s.hh) / 10.0))::INT
                WHEN s.p_prid IS NOT NULL
                     THEN s.p_price - s.p_points
                          + CASE WHEN s.p_price / s.hh = 1000 THEN 300 ELSE 200 END
                            * GREATEST(0, CEIL((s.dur - 60 * s.hh) / 10.0))::INT
                ELSE s.hh * CASE WHEN s.adult THEN 1000 ELSE 800 END
                     + CASE WHEN s.adult THEN 300 ELSE 200 END * GREATEST(0, CEIL((s.dur - 60 * s.hh) / 10.0))::INT END AS fee
    FROM (
        SELECT x.rid, x.dur, a.adult,
               t.prid AS t_prid, t.price AS t_price, t.points AS t_points,
               p.prid AS p_prid, p.price AS p_price, p.points AS p_points,
               CASE WHEN t.prid IS NOT NULL THEN t.usehour
                    WHEN p.prid IS NOT NULL THEN p.usehour
                    WHEN pg_temp.hu(x.hm, 22) < CASE WHEN x.dur <= 45 THEN 0.05 WHEN x.dur <= 90 THEN 0.35 ELSE 0.60 END
                         THEN 2 ELSE 1 END AS hh
        FROM bulk_rent x
        JOIN bulk_mebr m ON m.g = x.mebr_idx
        CROSS JOIN LATERAL (SELECT EXTRACT(YEAR FROM AGE(x.rentdate::DATE, m.birth)) >= 19 AS adult) a
        LEFT JOIN bulk_tick t ON t.kind = 'P' AND t.mebr_idx = x.mebr_idx
                             AND x.rentdate >= t.startdate AND x.rentdate < t.enddate
        LEFT JOIN bulk_tick p ON p.kind = 'R' AND p.prid = x.rid
    ) s
) f
WHERE f.rid = r.rid;

-- =====================================================================================================
-- 보충/수거
--   수거(CL) 뒤에는 보충(SP)이 이어진다. 마지막 대여 이후의 보충(AVL)과 수거(COL/RP)는 bulk_tail에 있다.
-- =====================================================================================================
CREATE TEMP TABLE bulk_spcl AS
SELECT bycl_id, 'SP'::CHAR(2) AS spclgubun, NULL::CHAR(2) AS collectreason, sp_st AS rtpl_id,
       date_trunc('minute', sp_ts_raw) AS spcldate
FROM (SELECT g.*, b.bycl_id FROM bulk_gap g JOIN bulk_bike b ON b.n = g.bn) g
UNION ALL
SELECT bycl_id, 'CL', CASE ev WHEN 'CLDM' THEN 'DM' ELSE 'RP' END, prev_ret_st, date_trunc('minute', cl_ts_raw)
FROM (SELECT g.*, b.bycl_id FROM bulk_gap g JOIN bulk_bike b ON b.n = g.bn) g
WHERE ev IN ('CLDM', 'CLRP')
UNION ALL
SELECT b.bycl_id, t.spclgubun, t.collectreason, t.rtpl_id, t.spcldate
FROM bulk_tail t JOIN bulk_bike b ON b.n = t.bn;

-- =====================================================================================================
-- 거치대: 마지막 위치에 거치된 자전거마다 한 칸씩, 대여소마다 빈 거치대 1~5칸 (일부는 고장)
-- =====================================================================================================
CREATE TEMP TABLE bulk_rack AS
SELECT d.rtpl_id || lpad(d.rn::text, 2, '0') AS rack_id, d.rtpl_id,
       'AVL'::CHAR(3) AS status, d.bycl_id, d.gubun
FROM (SELECT l.*, ROW_NUMBER() OVER (PARTITION BY l.rtpl_id ORDER BY l.bn) AS rn FROM bulk_loc l) d
UNION ALL
SELECT r.rtpl_id || lpad((COALESCE(dc.cnt, 0) + e.i)::text, 2, '0'), r.rtpl_id,
       CASE WHEN pg_temp.hx(md5('rk' || r.rtpl_id || '/' || e.i), 8) % 100 < 25 THEN 'DMG' ELSE 'AVL' END,
       NULL,
       CASE WHEN pg_temp.hx(md5('rk' || r.rtpl_id || '/' || e.i), 15) % 100 < 80 THEN 'GN' ELSE 'SD' END
FROM bulk_rtpl r
LEFT JOIN (SELECT rtpl_id, COUNT(*) AS cnt FROM bulk_loc GROUP BY rtpl_id) dc ON dc.rtpl_id = r.rtpl_id
CROSS JOIN LATERAL generate_series(1, 1 + pg_temp.hx(md5('rkn' || r.rtpl_id), 1) % 5) AS e(i);

-- =====================================================================================================
-- 파손/분실 신고
-- =====================================================================================================
CREATE TEMP TABLE bulk_dmls AS
SELECT q.*,
       CASE WHEN q.liable0 AND NOT q.is_open AND q.dmlsflag = 'DM' THEN pg_temp.hu(q.hd, 8) < 0.5
            ELSE q.is_open END AS confirm_b
FROM (
    SELECT r.rid, r.mebr_idx, r.bycl_id, r.is_open, r.flag AS dmlsflag, md5('dm' || r.rid) AS hd,
           date_trunc('minute', r.rentdate + (r.dur * (0.2 + 0.7 * pg_temp.hu(md5('dm' || r.rid), 1))) * INTERVAL '1 minute') AS occurdate,
           (r.is_open
            OR (c.snap - date_trunc('minute', r.rentdate + (r.dur * (0.2 + 0.7 * pg_temp.hu(md5('dm' || r.rid), 1))) * INTERVAL '1 minute') >= INTERVAL '1 day'
                AND pg_temp.hu(md5('dm' || r.rid), 15) < CASE r.flag WHEN 'DM' THEN 0.35 ELSE 0.15 END)) AS liable0
    FROM bulk_rent r CROSS JOIN bulk_cfg c
    WHERE r.flag IS NOT NULL
) q;

-- =====================================================================================================
-- 적재
-- =====================================================================================================
INSERT INTO tblmebrM1 (mebr_id, passwd, name, sex, birth, phone, email, totalrental, points, signupmethod, flag)
SELECT m.mebr_id, encode(sha256(convert_to(m.mebr_id, 'UTF8')), 'hex'), m.name, m.sex, m.birth, m.phone,
       m.mebr_id || '@example.com', COALESCE(rc.cnt, 0), m.points, m.signupmethod,
       CASE WHEN EXISTS (SELECT 1 FROM bulk_tick t, bulk_cfg c
                         WHERE t.mebr_idx = m.g AND t.kind = 'P' AND t.startdate <= c.snap AND t.enddate > c.snap)
            THEN 'Y' ELSE 'N' END
FROM bulk_mebr m
LEFT JOIN (SELECT mebr_idx, COUNT(*) AS cnt FROM bulk_rent GROUP BY mebr_idx) rc ON rc.mebr_idx = m.g
ORDER BY m.g;

INSERT INTO tbltickD1 (mebr_id, ticket, startdate, enddate, points, paymethod)
SELECT m.mebr_id, t.ticket, t.startdate, t.enddate, t.points, t.paymethod
FROM bulk_tick t JOIN bulk_mebr m ON m.g = t.mebr_idx
ORDER BY t.startdate, m.mebr_id;

INSERT INTO tblbyclM1 (bycl_id, registerdate, installdate, status, gubun)
SELECT bycl_id, registerdate, installdate, fate, gubun FROM bulk_bike ORDER BY n;

INSERT INTO tblrtplM1 (rtpl_id, space, addr, avail)
SELECT r.rtpl_id, r.space, r.addr,
       (SELECT COUNT(*) FROM bulk_loc l WHERE l.rtpl_id = r.rtpl_id AND l.fate = 'AVL')
FROM bulk_rtpl r ORDER BY r.rtpl_id;

INSERT INTO tblrackD1 (rack_id, rtpl_id, status, bycl_id, gubun)
SELECT rack_id, rtpl_id, status, bycl_id, gubun FROM bulk_rack ORDER BY rack_id;

INSERT INTO tblrentT1 (mebr_id, rtpl_id, bycl_id, rentdate, time, fixhour, dist, kcal, carbon, retrtpl_id, returndate, fee)
SELECT m.mebr_id, r.rtpl_id, r.bycl_id, r.rentdate, make_interval(mins => r.dur), r.fixhour, r.dist, r.kcal, r.carbon,
       r.retrtpl_id, r.returndate, r.fee
FROM bulk_rent r JOIN bulk_mebr m ON m.g = r.mebr_idx
ORDER BY r.rid;

INSERT INTO tblspclD1 (bycl_id, spclgubun, collectreason, rtpl_id, spcldate)
SELECT bycl_id, spclgubun, collectreason, rtpl_id, spcldate FROM bulk_spcl ORDER BY spcldate, bycl_id;

INSERT INTO tbldmlsD1 (rent_id, bycl_id, mebr_id, dmlsflag, name, phone, addr, reason, occurdate, liable, confirm, amount, claimdate)
SELECT t.rent_id, d.bycl_id, m.mebr_id, d.dmlsflag, m.name, m.phone,
       '서울특별시 ' || gu.gu_name || ' ' || (1 + pg_temp.hx(d.hd, 8) % 50) || '길 ' || (1 + pg_temp.hx(d.hd, 15) % 200),
       CASE d.dmlsflag
           WHEN 'DM' THEN (ARRAY['파손 사고','파손 사고','브레이크 파손','바퀴 펑크','체인 이탈'])[1 + pg_temp.hx(d.hd, 22) % 5]
           ELSE (ARRAY['분실 신고','분실 신고','거치대 반납 실패 후 분실'])[1 + pg_temp.hx(d.hd, 22) % 3] END,
       d.occurdate,
       CASE WHEN d.liable0 THEN 'Y' ELSE 'N' END,
       CASE WHEN d.confirm_b THEN 'Y' ELSE 'N' END,
       CASE WHEN d.liable0 THEN (ARRAY[13000, 24000, 35000, 45000])[1 + pg_temp.hx(d.hd, 8) % 4] END,
       CASE WHEN d.liable0 THEN d.occurdate + make_interval(days => 1 + pg_temp.hx(d.hd, 22) %
                 LEAST(10, GREATEST(1, FLOOR(EXTRACT(EPOCH FROM (c.snap - d.occurdate)) / 86400)::INT))) END
FROM bulk_dmls d
JOIN bulk_rent r ON r.rid = d.rid
JOIN tblrentT1 t ON t.bycl_id = d.bycl_id AND t.rentdate = r.rentdate
JOIN bulk_mebr m ON m.g = d.mebr_idx
JOIN bulk_gu gu ON gu.gu_no = 1 + pg_temp.hx(d.hd, 1) % 25
CROSS JOIN bulk_cfg c
ORDER BY d.occurdate, d.bycl_id;

-- 즐겨찾기: 회원이 자주 빌린 대여소 중에서 0~5곳
INSERT INTO tblfavoT1 (mebr_id, rtpl_id)
SELECT m.mebr_id, f.rtpl_id
FROM (
    SELECT x.mebr_idx, x.rtpl_id,
           ROW_NUMBER() OVER (PARTITION BY x.mebr_idx ORDER BY x.cnt DESC, md5(x.mebr_idx || x.rtpl_id)) AS rn
    FROM (SELECT mebr_idx, rtpl_id, COUNT(*) AS cnt FROM bulk_rent WHERE mebr_idx <= 19700 GROUP BY mebr_idx, rtpl_id) x
) f
JOIN bulk_mebr m ON m.g = f.mebr_idx
WHERE f.rn <= pg_temp.hx(m.h, 22) % 6
ORDER BY m.mebr_id, f.rtpl_id;

COMMIT;

ANALYZE tblmebrM1;
ANALYZE tbltickD1;
ANALYZE tblbyclM1;
ANALYZE tblrtplM1;
ANALYZE tblrackD1;
ANALYZE tblrentT1;
ANALYZE tblspclD1;
ANALYZE tbldmlsD1;
ANALYZE tblfavoT1;

-- 적재 결과 확인용
SELECT 'tblmebrM1' AS tbl, COUNT(*) AS cnt FROM tblmebrM1
UNION ALL SELECT 'tbltickD1', COUNT(*) FROM tbltickD1
UNION ALL SELECT 'tblbyclM1', COUNT(*) FROM tblbyclM1
UNION ALL SELECT 'tblrtplM1', COUNT(*) FROM tblrtplM1
UNION ALL SELECT 'tblrackD1', COUNT(*) FROM tblrackD1
UNION ALL SELECT 'tblrentT1', COUNT(*) FROM tblrentT1
UNION ALL SELECT 'tblspclD1', COUNT(*) FROM tblspclD1
UNION ALL SELECT 'tbldmlsD1', COUNT(*) FROM tbldmlsD1
UNION ALL SELECT 'tblfavoT1', COUNT(*) FROM tblfavoT1;
