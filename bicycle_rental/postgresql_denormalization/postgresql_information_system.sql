-- 후보 1·2·3을 합친 쿼리: 집계 테이블에 복사해 둔 대여소 이름을 읽어서 조인도 없다 (정규화 쿼리와 결과가 같아야 한다). 2, 3, 6번은 후보 1만 쓰는 쿼리와 같다.

--- 1번
SELECT
  s.space                         AS 대여소명,
  TO_CHAR(s.ym, 'YYYY-MM')        AS 년월,
  SUM(s.rent_cnt)                 AS "대여 자전거 수"
FROM tblrpmoS1 s
WHERE s.rent_cnt > 0              -- 반납만 있는 행은 뺀다
GROUP BY
  s.space,
  s.ym
ORDER BY
  s.space,
  년월;

--- 2번
SELECT
  s.bycl_id AS 자전거번호,
  TO_CHAR(s.ym, 'YYYY-MM') AS 년월,
  (
    (EXTRACT(DAY   FROM s.time_sum) * 24) +
    EXTRACT(HOUR  FROM s.time_sum)
  )::INT || '시간 ' ||
  EXTRACT(MINUTE FROM s.time_sum)::INT || '분 ' ||
  EXTRACT(SECOND FROM s.time_sum)::INT || '초'
    AS 대여시간
FROM tblbcmoS1 s
ORDER BY
  s.bycl_id,
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
  s.space                          AS 대여소명,
  TO_CHAR(s.ym, 'YYYY-MM')         AS 년월,
  SUM(s.ret_fee)::BIGINT           AS 수입금액
FROM tblrpmoS1 s
WHERE s.ret_cnt > 0               -- 대여만 있는 행은 뺀다
GROUP BY
  s.space,
  s.ym
ORDER BY
  s.space,
  년월;

--- 5번
WITH stats AS (
  SELECT
    s.space                                       AS 대여소명,
    s.dow                                         AS dow_key,
    s.slot                                        AS timeslot_key,
    SUM(s.rent_cnt)                               AS 대여횟수,
    SUM(s.time_sum)                               AS time_sum
  FROM tblrpwdS1 s
  GROUP BY
    s.space,
    s.dow,
    s.slot
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
  (
    (EXTRACT(DAY    FROM time_sum) * 24)
    + EXTRACT(HOUR   FROM time_sum)
  )::INT   || '시간 ' ||
  EXTRACT(MINUTE FROM time_sum)::INT || '분 ' ||
  EXTRACT(SECOND FROM time_sum)::INT || '초'      AS 이용시간
FROM stats
ORDER BY
  대여소명,
  dow_key,       -- 0=일이라 일요일이 먼저 나온다
  timeslot_key;  -- 심야→오전→오후→야간 순

--- 6번
SELECT
  s.mebr_id                                                AS 회원아이디,
  s.region                                                 AS 구번호,
  s.use_cnt                                                AS 이용횟수,

  (
    (EXTRACT(DAY    FROM s.time_sum) * 24) +
     EXTRACT(HOUR   FROM s.time_sum)
  )::INT                                                || '시간 '
  || EXTRACT(MINUTE FROM s.time_sum)::INT               || '분 '
  || EXTRACT(SECOND FROM s.time_sum)::INT               || '초'
    AS 총이용시간,

  ROUND(s.dist_sum, 2)                                   AS 총이동거리,
  ROUND(s.carbon_sum, 2)                                 AS 총탄소저감량

FROM tblmbrgS1 s
ORDER BY
  s.mebr_id,
  s.region;

--- 7번
WITH base AS (
    SELECT
        s.space                                           AS station,
        s.dow                                             AS dow,
        s.slot                                            AS slot,
        SUM(s.rent_cnt)                                   AS rental_count,
        SUM(EXTRACT(EPOCH FROM s.time_sum))               AS total_time_sec
    FROM tblrpwdS1 s
    GROUP BY
        s.space,
        s.dow,
        s.slot
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
