-- 반정규화 구조(create_ddl.sql) 기준 정보시스템 쿼리.
-- 원본: cinema/postgresql/postgresql_information_system.sql
-- 별칭(AS ...)은 원본과 동일하게 유지했으나, v2.1.0 에서 capacity 의미가 "이용 가능 정원"으로 바뀌어 4·5·8·9번의 좌석수 별칭만 "정원"/"정원합계"로 바꿨습니다.
-- [반정규화 영향] 표시가 있는 쿼리만 원본과 달라졌습니다.

-- 1번: 현재 등급별 회원 수를 구하라
-- [반정규화 영향] tbl_mbrt_l1(회원등급)은 tbl_mebr_m1.rating 으로 흡수되었습니다.
--                 원본도 tbl_mebr_m1.mbrt_id 만 집계했으므로 조인 수는 같고 컬럼명만 바뀝니다.
SELECT	mb.rating AS 회원등급ID,
		COUNT(mb.rating) AS 등급별회원수
FROM	tbl_mebr_m1 AS mb
GROUP BY mb.rating;

-- 2번: 현재 충전 금액의 잔액을 구하라
SELECT name, savings from tbl_mebr_m1;

-- 3번: 이번 달 우리 영화관의 이용객 수 및 매출을 구하라(마일리지 고려)
-- [반정규화 영향] buydate 는 이제 "결제 완료 시각"이며 미결제 전화 예약은 NULL 입니다.
--                 NULL 은 범위 조건을 만족하지 않으므로 미결제 예약은 이용객 수·매출에서 자동 제외됩니다.
SELECT	COUNT(DISTINCT(tk.mebr_id)) AS 이용객수,
		SUM(tk.savings)				AS 매출
FROM	tbl_bytk_d1	AS tk
WHERE tk.buydate >= DATE_TRUNC('month', CURRENT_DATE)::date
    AND tk.buydate < (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month')::date;

-- 4번: 이번 달 우리 영화관의 이용률을 계산하려고 한다.
--     * 상영관별 이용률은 ‘인원/좌석수 X 상영횟수 X 일수’
-- [반정규화 영향] 정원(이용 가능 좌석 수)을 tbl_scrn_m1.capacity 에서 바로 읽으므로 tbl_thtr_m1 조인이 사라집니다. (조인 2개 -> 1개)
SELECT
    sc.thtr_id AS 상영관ID,
    sc.capacity AS 정원,
    COUNT(DISTINCT sc.scrndate) AS 상영일수,
    COUNT(sc.scrn_id) AS 상영횟수,
    COUNT(b.mebr_id) AS 총관람인원,
    ROUND(
        (COUNT(b.mebr_id)::numeric / NULLIF(sc.capacity * COUNT(sc.scrn_id), 0)) * 100,
        2
    ) AS 이용률_퍼센트
FROM tbl_scrn_m1 AS sc
LEFT JOIN tbl_bytk_d1 AS b
    ON sc.scrn_id = b.scrn_id
WHERE sc.scrndate >= DATE_TRUNC('month', CURRENT_DATE)::date
  AND sc.scrndate < (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month')::date
GROUP BY sc.thtr_id, sc.capacity
ORDER BY sc.thtr_id;

-- 5번: 영화별 이용률을 구하라
-- [반정규화 영향] 정원(이용 가능 좌석 수)을 tbl_scrn_m1.capacity 에서 바로 읽으므로 tbl_thtr_m1 조인이 사라집니다. (조인 3개 -> 2개)
SELECT
    mv.title AS 영화제목,
    COUNT(DISTINCT sc.scrndate) AS 상영일수,
    COUNT(sc.scrn_id) AS 상영횟수,
    SUM(sc.capacity) AS 정원합계,
    COUNT(b.mebr_id) AS 총관람인원,
    ROUND(
        (COUNT(b.mebr_id)::numeric / NULLIF(SUM(sc.capacity), 0)) * 100,
        2
    ) AS 이용률_퍼센트
FROM tbl_scmv_m1 AS mv
JOIN tbl_scrn_m1 AS sc
    ON mv.scmv_id = sc.scmv_id
LEFT JOIN tbl_bytk_d1 AS b
    ON sc.scrn_id = b.scrn_id
WHERE sc.scrndate >= DATE_TRUNC('month', CURRENT_DATE)::date
  AND sc.scrndate < (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month')::date
GROUP BY mv.title
ORDER BY 이용률_퍼센트 DESC;

-- 6번: 이번 달 예매자 수(비율)를 요일별 시간대별로 구하라
-- [반정규화 영향] "예약을 시도한 시간대"가 기준이므로 buydate(결제 완료 시각, NULL 가능) 대신
--                 reserved_at(NOT NULL)을 사용합니다. 결제까지 마치지 못한 전화 예약도 포함됩니다.
WITH 예매정보 AS (
    SELECT tk.mebr_id AS 회원ID,
           tk.reserved_at AS 예매일시,
           TO_CHAR(tk.reserved_at, 'FMDay') AS 요일,
           CASE
               WHEN EXTRACT(HOUR FROM tk.reserved_at) BETWEEN 5 AND 11 THEN '오전'
               WHEN EXTRACT(HOUR FROM tk.reserved_at) BETWEEN 12 AND 17 THEN '오후'
               WHEN EXTRACT(HOUR FROM tk.reserved_at) BETWEEN 18 AND 23 THEN '저녁'
               ELSE '심야'
           END AS 시간대
    FROM tbl_bytk_d1 AS tk
    WHERE tk.reserved_at >= DATE_TRUNC('month', CURRENT_DATE)::date
      AND tk.reserved_at < (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month')::date
),
집계 AS (
    SELECT 요일,
           시간대,
           COUNT(DISTINCT 회원ID) AS 예매자수
    FROM 예매정보
    GROUP BY 요일, 시간대
),
총합 AS (
    SELECT COUNT(DISTINCT 회원ID) AS 전체예매자수
    FROM 예매정보
)
SELECT
    c.요일,
    c.시간대,
    c.예매자수,
    ROUND((c.예매자수 * 100.0) / NULLIF(t.전체예매자수, 0), 2) AS 비율_퍼센트
FROM 집계 AS c, 총합 AS t
ORDER BY CASE c.요일
             WHEN 'Monday' THEN 1
             WHEN 'Tuesday' THEN 2
             WHEN 'Wednesday' THEN 3
             WHEN 'Thursday' THEN 4
             WHEN 'Friday' THEN 5
             WHEN 'Saturday' THEN 6
             WHEN 'Sunday' THEN 7
         END,
         c.시간대;

-- 7번: 고객들에게 상영 예정인 영화 정보를 본 영화를 좋아하는 회원에게 이메일로 발송하고자 한다.
--     * 개봉 예정 영화를 좋아하는 회원을 정하는 규칙은 각자 정한다.
SELECT	mb.mebr_id	AS 회원ID,
		mb.email	AS 이메일,
		mv.title	AS 영화명
FROM	tbl_like_d1	AS lk
	JOIN	tbl_scmv_m1 AS mv ON lk.scmv_id=mv.scmv_id
	JOIN	tbl_mebr_m1 AS mb ON lk.mebr_id=mb.mebr_id
WHERE	mv.status='S';

-- 8번: 현재 상영관별 예매 가능한 좌석 수를 상영관, 상영횟수별로 구하라(전화 예매 고려)
-- [참고] 전화 예약은 결제 전이라도 좌석을 점유하므로 결제 여부와 무관하게 tbl_bytk_d1 의 모든 행을 센다.
-- [반정규화 영향] 정원(이용 가능 좌석 수)을 tbl_scrn_m1.capacity 에서 바로 읽으므로 tbl_thtr_m1 조인이 사라집니다. (조인 2개 -> 1개)
SELECT
    sc.thtr_id AS 상영관ID,
    sc.scrndate AS 상영일자,
    sc.scrntime AS 상영시간,
    sc.capacity AS 정원,
    COUNT(b.bytk_id) AS 예매좌석수,
    (sc.capacity - COUNT(b.bytk_id)) AS 예매가능좌석수
FROM tbl_scrn_m1 AS sc
LEFT JOIN tbl_bytk_d1 AS b
    ON sc.scrn_id = b.scrn_id
WHERE (sc.scrndate + sc.scrntime) > LOCALTIMESTAMP
GROUP BY sc.thtr_id, sc.scrndate, sc.scrntime, sc.capacity
ORDER BY sc.thtr_id, sc.scrndate, sc.scrntime;

-- 9번: 영화 제목을 포함한 상영관별 예매 가능 좌석 수
-- [반정규화 영향] 정원(이용 가능 좌석 수)을 tbl_scrn_m1.capacity 에서 바로 읽으므로 tbl_thtr_m1 조인이 사라집니다. (조인 3개 -> 2개)
SELECT
    mv.title AS 영화제목,
    sc.thtr_id AS 상영관ID,
    sc.scrndate AS 상영일자,
    sc.scrntime AS 상영시간,
    sc.capacity AS 정원,
    COUNT(b.bytk_id) AS 예매좌석수,
    (sc.capacity - COUNT(b.bytk_id)) AS 예매가능좌석수
FROM tbl_scrn_m1 AS sc
JOIN tbl_scmv_m1 AS mv
    ON sc.scmv_id = mv.scmv_id
LEFT JOIN tbl_bytk_d1 AS b
    ON sc.scrn_id = b.scrn_id
WHERE (sc.scrndate + sc.scrntime) > LOCALTIMESTAMP
GROUP BY mv.title, sc.thtr_id, sc.scrndate, sc.scrntime, sc.capacity
ORDER BY sc.thtr_id, sc.scrndate, sc.scrntime;
