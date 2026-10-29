# 1번: 현재 등급별 회원 수를 구하라
-- SELECT	mb.회원등급ID AS 회원등급ID,
-- 		COUNT(mb.회원등급ID) AS 등급별회원수
-- FROM	회원테이블 AS mb
-- GROUP BY mb.회원등급ID;

SELECT	mb.mbrt_id AS 회원등급ID,
		COUNT(mb.mbrt_id) AS 등급별회원수
FROM	tbl_mebr_m1 AS mb
GROUP BY mb.mbrt_id;

# 2번: 현재 충전 금액의 잔액을 구하라
-- SELECT 회원이름, 적립금 from tbl_mebr_m1;

SELECT name, savings from tbl_mebr_m1;

# 3번: 이번 달 우리 영화관의 이용객 수 및 매출을 구하라(마일리지 고려)
-- SELECT	COUNT(DISTINCT(tk.회원ID)) AS 이용객수,
-- 		SUM(tk.적립금)				AS 매출
-- FROM	예매테이블	AS tk
-- WHERE	tk.예매일자 BETWEEN '2025-04-01' AND '2025-04-30';

SELECT	COUNT(DISTINCT(tk.mebr_id)) AS 이용객수,
		SUM(tk.savings)				AS 매출
FROM	tbl_bytk_d1	AS tk
WHERE	tk.buydata BETWEEN '2025-04-01' AND '2025-04-30';

# 4번: 이번 달 우리 영화관의 이용률을 계산하려고 한다.
#     * 상영관별 이용률은 ‘인원/좌석수 X 상영횟수 X 일수’
-- SELECT
--     th.상영관ID AS 상영관ID,
--     th.좌석수 AS 좌석수,
--     COUNT(DISTINCT sc.상영일자) AS 상영일수,
--     COUNT(sc.영화상영ID) AS 상영횟수,
--     COUNT(b.회원ID) AS 총관람인원,
--     ROUND(
--         (COUNT(b.회원ID) / (th.좌석수 * COUNT(sc.영화상영ID))) * 100,
--         2
--     ) AS 이용률_퍼센트
-- FROM 상영관테이블 AS th
-- JOIN 영화상영테이블 AS sc
--     ON th.상영관ID = sc.상영관ID
-- LEFT JOIN 예매테이블 AS b
--     ON sc.영화상영ID = b.영화상영ID
-- WHERE DATE_FORMAT(sc.상영일자, '%Y-%m') = DATE_FORMAT(CURRENT_DATE(), '%Y-%m')
-- GROUP BY th.상영관ID, th.좌석수
-- ORDER BY th.상영관ID;

SELECT
    th.thtr_id AS 상영관ID,
    th.seat AS 좌석수,
    COUNT(DISTINCT sc.scrndate) AS 상영일수,
    COUNT(sc.scrn_id) AS 상영횟수,
    COUNT(b.mebr_id) AS 총관람인원,
    ROUND(
        (COUNT(b.mebr_id) / (th.seat * COUNT(sc.scrn_id))) * 100,
        2
    ) AS 이용률_퍼센트
FROM tbl_thtr_m1 AS th
JOIN tbl_scrn_m1 AS sc
    ON th.thtr_id = sc.thtr_id
LEFT JOIN tbl_bytk_d1 AS b
    ON sc.scrn_id = b.scrn_id
WHERE DATE_FORMAT(sc.scrndate, '%Y-%m') = DATE_FORMAT(CURRENT_DATE(), '%Y-%m')
GROUP BY th.thtr_id, th.seat
ORDER BY th.thtr_id;


# 5번: 영화별 이용률을 구하라
-- SELECT
--     mv.영화제목 AS 영화제목,
--     COUNT(DISTINCT sc.상영일자) AS 상영일수,
--     COUNT(sc.영화상영ID) AS 상영횟수,
--     SUM(th.좌석수) AS 총좌석합계,
--     COUNT(b.회원ID) AS 총관람인원,
--     ROUND(
--         (COUNT(b.회원ID) / (SUM(th.좌석수))) * 100,
--         2
--     ) AS 이용률_퍼센트
-- FROM 영화테이블 AS mv
-- JOIN 영화상영테이블 AS sc
--     ON mv.영화ID = sc.영화ID
-- JOIN 상영관테이블 AS th
--     ON sc.상영관ID = th.상영관ID
-- LEFT JOIN 예매테이블 AS b
--     ON sc.영화상영ID = b.영화상영ID
-- WHERE DATE_FORMAT(sc.상영일자, '%Y-%m') = DATE_FORMAT(CURRENT_DATE(), '%Y-%m')
-- GROUP BY mv.영화제목
-- ORDER BY 이용률_퍼센트 DESC;

SELECT
    mv.title AS 영화제목,
    COUNT(DISTINCT sc.scrndate) AS 상영일수,
    COUNT(sc.scrn_id) AS 상영횟수,
    SUM(th.seat) AS 총좌석합계,
    COUNT(b.mebr_id) AS 총관람인원,
    ROUND(
        (COUNT(b.mebr_id) / (SUM(th.seat))) * 100,
        2
    ) AS 이용률_퍼센트
FROM tbl_scmv_m1 AS mv
JOIN tbl_scrn_m1 AS sc
    ON mv.scmv_id = sc.scmv_id
JOIN tbl_thtr_m1 AS th
    ON sc.thtr_id = th.thtr_id
LEFT JOIN tbl_bytk_d1 AS b
    ON sc.scrn_id = b.scrn_id
WHERE DATE_FORMAT(sc.scrndate, '%Y-%m') = DATE_FORMAT(CURRENT_DATE(), '%Y-%m')
GROUP BY mv.title
ORDER BY 이용률_퍼센트 DESC;

# 6번: 이번 달 예매자 수(비율)를 요일별 시간대별로 구하라
-- WITH 예매정보 AS (
--     SELECT tk.회원ID AS 회원ID,
--            tk.예매일시 AS 예매일시,
--            DAYNAME(tk.예매일시) AS 요일,
--            CASE
--                WHEN HOUR(tk.예매일시) BETWEEN 5 AND 11 THEN '오전'
--                WHEN HOUR(tk.예매일시) BETWEEN 12 AND 17 THEN '오후'
--                WHEN HOUR(tk.예매일시) BETWEEN 18 AND 23 THEN '저녁'
--                ELSE '심야'
--            END AS 시간대
--     FROM 예매테이블 AS tk
--     WHERE tk.예매일시 BETWEEN '2025-04-01' AND '2025-04-30'
-- ),
-- 집계 AS (
--     SELECT 요일,
--            시간대,
--            COUNT(DISTINCT 회원ID) AS 예매자수
--     FROM 예매정보
--     GROUP BY 요일, 시간대
-- ),
-- 총합 AS (
--     SELECT COUNT(DISTINCT 회원ID) AS 전체예매자수
--     FROM 예매정보
-- )
-- SELECT
--     c.요일,
--     c.시간대,
--     c.예매자수,
--     ROUND((c.예매자수 * 100.0) / t.전체예매자수, 2) AS 비율_퍼센트
-- FROM 집계 AS c, 총합 AS t
-- ORDER BY FIELD(c.요일, 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'), c.시간대;

WITH 예매정보 AS (
    SELECT tk.mebr_id AS 회원ID,
           tk.buydate AS 예매일시,
           DAYNAME(tk.buydate) AS 요일,
           CASE
               WHEN HOUR(tk.buydate) BETWEEN 5 AND 11 THEN '오전'
               WHEN HOUR(tk.buydate) BETWEEN 12 AND 17 THEN '오후'
               WHEN HOUR(tk.buydate) BETWEEN 18 AND 23 THEN '저녁'
               ELSE '심야'
           END AS 시간대
    FROM tbl_bytk_d1 AS tk
    WHERE tk.buydate BETWEEN '2025-04-01' AND '2025-04-30'
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
    ROUND((c.예매자수 * 100.0) / t.전체예매자수, 2) AS 비율_퍼센트
FROM 집계 AS c, 총합 AS t
ORDER BY FIELD(c.요일, 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'), c.시간대;

# 7번: 고객들에게 상영 예정인 영화 정보를 본 영화를 좋아하는 회원에게 이메일로 발송하고자 한다.
#     * 개봉 예정 영화를 좋아하는 회원을 정하는 규칙은 각자 정한다.
-- SELECT	mb.회원ID	AS 회원ID,
-- 		mb.이메일	AS 이메일,
-- 		mb.영화제목	AS 영화명
-- FROM	좋아요테이블	AS lk
-- 	JOIN	영화테이블 AS mv ON lk.영화ID=mv.영화ID
-- 	JOIN	회원테이블 AS mb ON lk.회원ID=mb.회원ID
-- WHERE	mv.상영현황='S';

SELECT	mb.mebr_id	AS 회원ID,
		mb.email	AS 이메일,
		mb.title	AS 영화명
FROM	tbl_like_d1	AS lk
	JOIN	tbl_scmv_m1 AS mv ON lk.scmv_id=mv.scmv_id
	JOIN	tbl_mebr_m1 AS mb ON lk.mebr_id=mb.mebr_id
WHERE	mv.status='S';

# 8번: 현재 상영관별 예매 가능한 좌석 수를 상영관, 상영횟수별로 구하라(전화 예매 고려)
# 8번
-- SELECT
--     th.상영관ID AS 상영관ID,
--     sc.상영일자 AS 상영일자,
--     sc.상영시간 AS 상영시간,
--     th.총좌석수 AS 총좌석수,
--     COUNT(b.좌석ID) AS 예매좌석수,
--     (th.seat - COUNT(b.좌석ID)) AS 예매가능좌석수
-- FROM 영화상영테이블 AS sc
-- JOIN 상영관테이블 AS th
--     ON sc.상영관ID= th.상영관ID
-- LEFT JOIN tbl_bytk_d1 AS b
--     ON sc.영화상영ID = b.영화상영ID
-- GROUP BY th.상영관ID, sc.상영일자, sc.상영시간, th.좌석수
-- ORDER BY th.상영관ID, sc.상영일자, sc.상영시간;

SELECT
    th.thtr_id AS 상영관ID,
    sc.scrndate AS 상영일자,
    sc.scrntime AS 상영시간,
    th.seat AS 총좌석수,
    COUNT(b.seat_id) AS 예매좌석수,
    (th.seat - COUNT(b.seat_id)) AS 예매가능좌석수
FROM tbl_scrn_m1 AS sc
JOIN tbl_thtr_m1 AS th
    ON sc.thtr_id = th.thtr_id
LEFT JOIN tbl_bytk_d1 AS b
    ON sc.scrn_id = b.scrn_id
GROUP BY th.thtr_id, sc.scrndate, sc.scrntime, th.seat
ORDER BY th.thtr_id, sc.scrndate, sc.scrntime;

# 9번
-- SELECT
--     mv.영화제목 AS 영화제목,
--     th.상영관ID AS 상영관ID,
--     sc.상영일자 AS 상영일자,
--     sc.상영시간 AS 상영시간,
--     th.좌석수 AS 총좌석수,
--     COUNT(b.좌석ID) AS 예매좌석수,
--     (th.좌석수 - COUNT(b.좌석ID)) AS 예매가능좌석수
-- FROM 영화상영테이블 AS sc
-- JOIN 상영관테이블 AS th
--     ON sc.상영관ID = th.상영관ID
-- JOIN tbl_scmv_m1 AS mv
--     ON sc.영화ID = mv.영화ID
-- LEFT JOIN tbl_bytk_d1 AS b
--     ON sc.영화상영ID = b.영화상영ID
-- GROUP BY mv.영화제목, th.상영관ID, sc.상영일자, sc.상영시간, th.좌석수
-- ORDER BY th.상영관ID, sc.상영일자, sc.상영시간;

SELECT
    mv.title AS 영화제목,
    th.thtr_id AS 상영관ID,
    sc.scrndate AS 상영일자,
    sc.scrntime AS 상영시간,
    th.seat AS 총좌석수,
    COUNT(b.seat_id) AS 예매좌석수,
    (th.seat - COUNT(b.seat_id)) AS 예매가능좌석수
FROM tbl_scrn_m1 AS sc
JOIN tbl_thtr_m1 AS th
    ON sc.thtr_id = th.thtr_id
JOIN tbl_scmv_m1 AS mv
    ON sc.scmv_id = mv.scmv_id
LEFT JOIN tbl_bytk_d1 AS b
    ON sc.scrn_id = b.scrn_id
GROUP BY mv.title, th.thtr_id, sc.scrndate, sc.scrntime, th.seat
ORDER BY th.thtr_id, sc.scrndate, sc.scrntime;
