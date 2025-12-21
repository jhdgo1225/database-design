--- 1번
SELECT
  rt.space       AS 대여소명,
  TO_CHAR(tr.rentdate, 'YYYY-MM') AS 년월,
  COUNT(*)       AS "대여 자전거 수"
FROM tblrentT1 tr
JOIN tblrtplM1 rt
  ON tr.rtpl_id = rt.rtpl_id
GROUP BY
  rt.space,
  TO_CHAR(tr.rentdate, 'YYYY-MM')
ORDER BY
  rt.space,
  년월;

--- 2번
SELECT
  r.bycl_id AS 자전거번호,
  TO_CHAR(r.rentdate, 'YYYY-MM') AS 년월,
  (
    (EXTRACT(DAY   FROM SUM(r.time)) * 24) +
    EXTRACT(HOUR  FROM SUM(r.time))
  )::INT || '시간 ' ||
  EXTRACT(MINUTE FROM SUM(r.time))::INT || '분 ' ||
  EXTRACT(SECOND FROM SUM(r.time))::INT || '초'
    AS 대여시간
FROM tblrentT1 r
GROUP BY
  r.bycl_id,
  TO_CHAR(r.rentdate, 'YYYY-MM')
ORDER BY
  r.bycl_id,
  년월;

--- 3번
SELECT
  TO_CHAR(occurdate, 'YYYY-MM')              AS 년월,
  SUM(CASE WHEN dmlsflag = 'DM' THEN 1 ELSE 0 END) AS 파손건수,
  SUM(CASE WHEN dmlsflag = 'LS' THEN 1 ELSE 0 END) AS 분실건수
FROM tbldmlsD1
GROUP BY
  TO_CHAR(occurdate, 'YYYY-MM')
ORDER BY
  년월;

--- 4번
SELECT
  rt.space                         AS 대여소명,
  TO_CHAR(r.returndate, 'YYYY-MM') AS 년월,
  SUM(r.fee)                       AS 수입금액
FROM tblrentT1 r
JOIN tblrtplM1 rt
  ON r.retrtpl_id = rt.rtpl_id
GROUP BY
  rt.space,
  TO_CHAR(r.returndate, 'YYYY-MM')
ORDER BY
  rt.space,
  년월;

--- 5번
WITH stats AS (
  SELECT
    rt.space                                      AS 대여소명,
    EXTRACT(DOW FROM r.rentdate)::INT             AS dow_key,          -- 0=일,1=월…6=토
    CASE EXTRACT(DOW FROM r.rentdate)::INT        -- 출력용 한글 요일
      WHEN 1 THEN '월' WHEN 2 THEN '화' WHEN 3 THEN '수'
      WHEN 4 THEN '목' WHEN 5 THEN '금' WHEN 6 THEN '토'
      WHEN 0 THEN '일'
    END                                            AS 요일,
    CASE                                          -- 시간대 정렬키
      WHEN EXTRACT(HOUR FROM r.rentdate) BETWEEN 0  AND 4  THEN 1
      WHEN EXTRACT(HOUR FROM r.rentdate) BETWEEN 5  AND 11 THEN 2
      WHEN EXTRACT(HOUR FROM r.rentdate) BETWEEN 12 AND 17 THEN 3
      ELSE 4
    END                                            AS timeslot_key,
    CASE                                          -- 출력용 시간대
      WHEN EXTRACT(HOUR FROM r.rentdate) BETWEEN 0  AND 4  THEN '심야'
      WHEN EXTRACT(HOUR FROM r.rentdate) BETWEEN 5  AND 11 THEN '오전'
      WHEN EXTRACT(HOUR FROM r.rentdate) BETWEEN 12 AND 17 THEN '오후'
      ELSE '야간'
    END                                            AS 시간대,
    COUNT(*)                                      AS 대여횟수,
    (
      (EXTRACT(DAY    FROM SUM(r.time)) * 24)
      + EXTRACT(HOUR   FROM SUM(r.time))
    )::INT   || '시간 ' ||
    EXTRACT(MINUTE FROM SUM(r.time))::INT || '분 ' ||
    EXTRACT(SECOND FROM SUM(r.time))::INT || '초' AS 이용시간
  FROM tblrentT1 r
  JOIN tblrtplM1 rt
    ON r.rtpl_id = rt.rtpl_id
  GROUP BY
    rt.space,
    r.rentdate,
    r.time
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

--- 6번
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

  (
    (EXTRACT(DAY    FROM SUM(e.time)) * 24) +
     EXTRACT(HOUR   FROM SUM(e.time))
  )::INT                                                || '시간 '
  || EXTRACT(MINUTE FROM SUM(e.time))::INT              || '분 '
  || EXTRACT(SECOND FROM SUM(e.time))::INT              || '초'
    AS 총이용시간,

  ROUND(SUM(e.dist)::numeric, 2)                         AS 총이동거리,
  ROUND(SUM(e.carbon)::numeric, 2)                       AS 총탄소저감량

FROM events e
GROUP BY
  e.mebr_id,
  e.region_code
ORDER BY
  e.mebr_id,
  e.region_code;

--- 7번
WITH base AS (
    SELECT
        rt.space                                          AS station,
        EXTRACT(DOW FROM r.rentdate)::INT                 AS dow,         -- 0=일,1=월…6=토
        CASE EXTRACT(DOW FROM r.rentdate)::INT            -- 한글 요일
            WHEN 1 THEN '월' WHEN 2 THEN '화' WHEN 3 THEN '수'
            WHEN 4 THEN '목' WHEN 5 THEN '금' WHEN 6 THEN '토'
            WHEN 0 THEN '일'
            END                                               AS day,
        CASE                                                -- 시간대
            WHEN EXTRACT(HOUR FROM r.rentdate) BETWEEN 0  AND 4  THEN '심야'
            WHEN EXTRACT(HOUR FROM r.rentdate) BETWEEN 5  AND 11 THEN '오전'
            WHEN EXTRACT(HOUR FROM r.rentdate) BETWEEN 12 AND 17 THEN '오후'
            ELSE '야간'
            END                                               AS timeslot,
        COUNT(*)                                          AS rental_count,
        SUM(EXTRACT(EPOCH FROM r.time))                   AS total_time_sec
    FROM tblrentT1 r
             JOIN tblrtplM1 rt
                  ON r.rtpl_id = rt.rtpl_id
    GROUP BY
        rt.space,
        r.rentdate
)
SELECT
    station         AS 대여소명,
    day             AS 요일,
    timeslot        AS 시간대,
    CEIL(
            (total_time_sec/3600.0)
                / CASE timeslot
                      WHEN '심야' THEN 5
                      WHEN '오전' THEN 7
                      WHEN '오후' THEN 6
                      ELSE 6
                END
    )                AS "적정 자전거 댓수"
FROM base
ORDER BY
    station,
    CASE dow WHEN 1 THEN 1 WHEN 2 THEN 2 WHEN 3 THEN 3 WHEN 4 THEN 4 WHEN 5 THEN 5 WHEN 6 THEN 6 WHEN 0 THEN 7 END,
    CASE timeslot WHEN '심야' THEN 1 WHEN '오전' THEN 2 WHEN '오후' THEN 3 ELSE 4 END;
