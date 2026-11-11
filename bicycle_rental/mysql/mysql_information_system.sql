-- 1번
SELECT
  rt.space       AS 대여소명,
  DATE_FORMAT(tr.rentdate, '%Y-%m') AS 년월,
  COUNT(*)       AS `대여 자전거 수`
FROM tblrentT1 tr
JOIN tblrtplM1 rt
  ON tr.rtpl_id = rt.rtpl_id
GROUP BY
  rt.space,
  DATE_FORMAT(tr.rentdate, '%Y-%m')
ORDER BY
  rt.space,
  년월;

-- 2번
SELECT
  r.bycl_id AS 자전거번호,
  DATE_FORMAT(r.rentdate, '%Y-%m') AS 년월,
  CONCAT(
    FLOOR(SUM(TIME_TO_SEC(r.time)) / 3600), '시간 ',
    FLOOR((SUM(TIME_TO_SEC(r.time)) % 3600) / 60), '분 ',
    SUM(TIME_TO_SEC(r.time)) % 60, '초'
  ) AS 대여시간
FROM tblrentT1 r
GROUP BY
  r.bycl_id,
  DATE_FORMAT(r.rentdate, '%Y-%m')
ORDER BY
  r.bycl_id,
  년월;

-- 3번
SELECT
  DATE_FORMAT(occurdate, '%Y-%m')              AS 년월,
  SUM(CASE WHEN dmlsflag = 'DM' THEN 1 ELSE 0 END) AS 파손건수,
  SUM(CASE WHEN dmlsflag = 'LS' THEN 1 ELSE 0 END) AS 분실건수
FROM tbldmlsD1
GROUP BY
  DATE_FORMAT(occurdate, '%Y-%m')
ORDER BY
  년월;

-- 4번
SELECT
  rt.space                         AS 대여소명,
  DATE_FORMAT(r.returndate, '%Y-%m') AS 년월,
  SUM(r.fee)                       AS 수입금액
FROM tblrentT1 r
JOIN tblrtplM1 rt
  ON r.retrtpl_id = rt.rtpl_id
GROUP BY
  rt.space,
  DATE_FORMAT(r.returndate, '%Y-%m')
ORDER BY
  rt.space,
  년월;

-- 5번
WITH stats AS (
  SELECT
    rt.space                                      AS 대여소명,
    DAYOFWEEK(r.rentdate) - 1                     AS dow_key,          -- 0=일,1=월…6=토
    CASE DAYOFWEEK(r.rentdate) - 1                -- 출력용 한글 요일
      WHEN 1 THEN '월' WHEN 2 THEN '화' WHEN 3 THEN '수'
      WHEN 4 THEN '목' WHEN 5 THEN '금' WHEN 6 THEN '토'
      WHEN 0 THEN '일'
    END                                            AS 요일,
    CASE                                          -- 시간대 정렬키
      WHEN HOUR(r.rentdate) BETWEEN 0  AND 4  THEN 1
      WHEN HOUR(r.rentdate) BETWEEN 5  AND 11 THEN 2
      WHEN HOUR(r.rentdate) BETWEEN 12 AND 17 THEN 3
      ELSE 4
    END                                            AS timeslot_key,
    CASE                                          -- 출력용 시간대
      WHEN HOUR(r.rentdate) BETWEEN 0  AND 4  THEN '심야'
      WHEN HOUR(r.rentdate) BETWEEN 5  AND 11 THEN '오전'
      WHEN HOUR(r.rentdate) BETWEEN 12 AND 17 THEN '오후'
      ELSE '야간'
    END                                            AS 시간대,
    COUNT(*)                                      AS 대여횟수,
    CONCAT(
      FLOOR(SUM(TIME_TO_SEC(r.time)) / 3600), '시간 ',
      FLOOR((SUM(TIME_TO_SEC(r.time)) % 3600) / 60), '분 ',
      SUM(TIME_TO_SEC(r.time)) % 60, '초'
    ) AS 이용시간
  FROM tblrentT1 r
  JOIN tblrtplM1 rt
    ON r.rtpl_id = rt.rtpl_id
  GROUP BY
    대여소명,
    dow_key,
    요일,
    timeslot_key,
    시간대
)
SELECT
  대여소명,
  요일,
  시간대,
  대여횟수,
  이용시간
FROM stats
ORDER BY
  대여소명,
  dow_key,       -- 월→…→일 순
  timeslot_key;  -- 심야→오전→오후→야간 순

-- 6번
WITH events AS (
  SELECT
    r.mebr_id,
    SUBSTRING(r.rtpl_id, 1, 2)       AS region_code,
    r.time,
    r.dist,
    r.carbon
  FROM tblrentT1 r

  UNION ALL

  SELECT
    r.mebr_id,
    SUBSTRING(r.retrtpl_id, 1, 2)    AS region_code,
    r.time,
    r.dist,
    r.carbon
  FROM tblrentT1 r
  WHERE r.retrtpl_id IS NOT NULL
)
SELECT
  e.mebr_id                                                AS 회원아이디,
  e.region_code                                            AS 구번호,
  COUNT(*)                                                 AS 이용횟수,

  CONCAT(
    FLOOR(SUM(TIME_TO_SEC(e.time)) / 3600), '시간 ',
    FLOOR((SUM(TIME_TO_SEC(e.time)) % 3600) / 60), '분 ',
    SUM(TIME_TO_SEC(e.time)) % 60, '초'
  ) AS 총이용시간,

  ROUND(SUM(e.dist), 2)                         AS 총이동거리,
  ROUND(SUM(e.carbon), 2)                       AS 총탄소저감량

FROM events e
GROUP BY
  e.mebr_id,
  e.region_code
ORDER BY
  e.mebr_id,
  e.region_code;

-- 7번
WITH RECURSIVE base AS (
    SELECT
        rt.space                                          AS station,
        DAYOFWEEK(r.rentdate) - 1                         AS dow,         -- 0=일,1=월…6=토
        CASE DAYOFWEEK(r.rentdate) - 1                    -- 한글 요일
            WHEN 1 THEN '월' WHEN 2 THEN '화' WHEN 3 THEN '수'
            WHEN 4 THEN '목' WHEN 5 THEN '금' WHEN 6 THEN '토'
            WHEN 0 THEN '일'
            END                                               AS day,
        CASE                                                -- 시간대
            WHEN HOUR(r.rentdate) BETWEEN 0  AND 4  THEN '심야'
            WHEN HOUR(r.rentdate) BETWEEN 5  AND 11 THEN '오전'
            WHEN HOUR(r.rentdate) BETWEEN 12 AND 17 THEN '오후'
            ELSE '야간'
            END                                               AS timeslot,
        COUNT(*)                                          AS rental_count,
        SUM(TIME_TO_SEC(r.time))                          AS total_time_sec
    FROM tblrentT1 r
    JOIN tblrtplM1 rt
      ON r.rtpl_id = rt.rtpl_id
    GROUP BY
        station,
        dow,
        day,
        timeslot
),
-- 데이터 기간 안에서 요일마다 날짜가 며칠이었는지. 같은 요일의 이용 시간을 합쳤기 때문에 하루 평균으로 나누려고 쓴다.
cal AS (
    SELECT DATE(MIN(rentdate)) AS d, DATE(MAX(rentdate)) AS last_d
    FROM tblrentT1
    UNION ALL
    SELECT d + INTERVAL 1 DAY, last_d
    FROM cal
    WHERE d < last_d
),
days AS (
    SELECT
        DAYOFWEEK(d) - 1 AS dow,
        COUNT(*)         AS day_cnt
    FROM cal
    GROUP BY dow
)
SELECT
    b.station       AS 대여소명,
    b.day           AS 요일,
    b.timeslot      AS 시간대,
    CEIL(
            (b.total_time_sec/3600.0) / d.day_cnt
                / CASE b.timeslot
                      WHEN '심야' THEN 5
                      WHEN '오전' THEN 7
                      WHEN '오후' THEN 6
                      ELSE 6
                END
    )                AS `적정 자전거 댓수`
FROM base b
JOIN days d
  ON d.dow = b.dow
ORDER BY
    b.station,
    CASE b.dow WHEN 1 THEN 1 WHEN 2 THEN 2 WHEN 3 THEN 3 WHEN 4 THEN 4 WHEN 5 THEN 5 WHEN 6 THEN 6 WHEN 0 THEN 7 END,
    CASE b.timeslot WHEN '심야' THEN 1 WHEN '오전' THEN 2 WHEN '오후' THEN 3 ELSE 4 END;
