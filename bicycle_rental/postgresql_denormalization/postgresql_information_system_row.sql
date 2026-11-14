-- 후보 2·3만 쓰는 쿼리: 대여 테이블의 대여소 이름 복사와 시각 파생 열 (정규화 쿼리와 결과가 같아야 한다). 3, 6번은 정규화 쿼리와 같다.

--- 1번
SELECT
  tr.rtpl_space                   AS 대여소명,
  TO_CHAR(tr.rent_ym, 'YYYY-MM')  AS 년월,
  COUNT(*)                        AS "대여 자전거 수"
FROM tblrentT1 tr
GROUP BY
  tr.rtpl_space,
  tr.rent_ym
ORDER BY
  tr.rtpl_space,
  년월;

--- 2번
SELECT
  r.bycl_id AS 자전거번호,
  TO_CHAR(r.rent_ym, 'YYYY-MM') AS 년월,
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
  r.rent_ym
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
  r.retrtpl_space                  AS 대여소명,
  TO_CHAR(r.return_ym, 'YYYY-MM')  AS 년월,
  SUM(r.fee)                       AS 수입금액
FROM tblrentT1 r
WHERE r.retrtpl_id IS NOT NULL
GROUP BY
  r.retrtpl_space,
  r.return_ym
ORDER BY
  r.retrtpl_space,
  년월;

--- 5번
WITH stats AS (
  SELECT
    r.rtpl_space                                  AS 대여소명,
    r.rent_dow                                    AS dow_key,
    r.rent_slot                                   AS timeslot_key,
    COUNT(*)                                      AS 대여횟수,
    (
      (EXTRACT(DAY    FROM SUM(r.time)) * 24)
      + EXTRACT(HOUR   FROM SUM(r.time))
    )::INT   || '시간 ' ||
    EXTRACT(MINUTE FROM SUM(r.time))::INT || '분 ' ||
    EXTRACT(SECOND FROM SUM(r.time))::INT || '초' AS 이용시간
  FROM tblrentT1 r
  GROUP BY
    r.rtpl_space,
    r.rent_dow,
    r.rent_slot
)
SELECT
  대여소명,
  CASE dow_key                                    -- 출력용 한글 요일
    WHEN 1 THEN '월' WHEN 2 THEN '화' WHEN 3 THEN '수'
    WHEN 4 THEN '목' WHEN 5 THEN '금' WHEN 6 THEN '토'
    WHEN 0 THEN '일'
  END                                             AS 요일,
  CASE timeslot_key                               -- 출력용 시간대
    WHEN 1 THEN '심야' WHEN 2 THEN '오전' WHEN 3 THEN '오후'
    ELSE '야간'
  END                                             AS 시간대,
  대여횟수,
  이용시간
FROM stats
ORDER BY
  대여소명,
  dow_key,       -- 0=일이라 일요일이 먼저 나온다
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

  ROUND(SUM(e.dist), 2)                                  AS 총이동거리,
  ROUND(SUM(e.carbon), 2)                                AS 총탄소저감량

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
        r.rtpl_space                                      AS station,
        r.rent_dow                                        AS dow,
        r.rent_slot                                       AS slot,
        COUNT(*)                                          AS rental_count,
        SUM(EXTRACT(EPOCH FROM r.time))                   AS total_time_sec
    FROM tblrentT1 r
    GROUP BY
        r.rtpl_space,
        r.rent_dow,
        r.rent_slot
),
-- 데이터 기간 안에서 요일마다 날짜가 며칠이었는지. 같은 요일의 이용 시간을 합쳤기 때문에 하루 평균으로 나누려고 쓴다.
days AS (
    SELECT
        EXTRACT(DOW FROM g.d)::INT AS dow,
        COUNT(*)                   AS day_cnt
    FROM generate_series(
             (SELECT DATE_TRUNC('day', MIN(rentdate)) FROM tblrentT1),
             (SELECT DATE_TRUNC('day', MAX(rentdate)) FROM tblrentT1),
             INTERVAL '1 day'
         ) AS g(d)
    GROUP BY EXTRACT(DOW FROM g.d)::INT
)
SELECT
    b.station       AS 대여소명,
    CASE b.dow                                              -- 한글 요일
        WHEN 1 THEN '월' WHEN 2 THEN '화' WHEN 3 THEN '수'
        WHEN 4 THEN '목' WHEN 5 THEN '금' WHEN 6 THEN '토'
        WHEN 0 THEN '일'
    END             AS 요일,
    CASE b.slot                                             -- 시간대
        WHEN 1 THEN '심야' WHEN 2 THEN '오전' WHEN 3 THEN '오후'
        ELSE '야간'
    END             AS 시간대,
    CEIL(
            (b.total_time_sec/3600.0) / d.day_cnt
                / CASE b.slot
                      WHEN 1 THEN 5
                      WHEN 2 THEN 7
                      WHEN 3 THEN 6
                      ELSE 6
                END
    )                AS "적정 자전거 댓수"
FROM base b
JOIN days d
  ON d.dow = b.dow
ORDER BY
    b.station,
    CASE b.dow WHEN 1 THEN 1 WHEN 2 THEN 2 WHEN 3 THEN 3 WHEN 4 THEN 4 WHEN 5 THEN 5 WHEN 6 THEN 6 WHEN 0 THEN 7 END,
    b.slot;
