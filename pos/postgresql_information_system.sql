--- 1번
SELECT
    b.name AS 업체이름,
    m.mebrid AS 고객아이디,
    COALESCE(p.post_count, 0)   AS "게시판 작성 횟수",
    COALESCE(r.repl_count, 0)   AS "댓글 작성 횟수"
FROM
    tblbusim b
    JOIN tblmebrm m
      ON b.mgr = m.mebrid
    -- 해당 업체의 “관리자(고객)”가 tblpostm 에 올린 게시글 수 집계
    LEFT JOIN (
        SELECT
            mebrid,
            COUNT(*) AS post_count
        FROM
            tblpostm
        GROUP BY
            mebrid
    ) p
      ON p.mebrid = m.mebrid
    -- 해당 업체의 “관리자(고객)”가 tblrepld 에 올린 댓글 수 집계
    LEFT JOIN (
        SELECT
            mebrid,
            COUNT(*) AS repl_count
        FROM
            tblrepld
        GROUP BY
            mebrid
    ) r
      ON r.mebrid = m.mebrid
ORDER BY
    b.busino,
    m.mebrid;


--- 2번
WITH ranked AS (
  SELECT
    b.serv                    AS cateno,
    b.name                    AS 업체이름,
    b.tablecnt                AS 테이블수,
    RANK() OVER (
      PARTITION BY b.serv
      ORDER BY b.tablecnt DESC
    )                         AS rnk_desc,
    RANK() OVER (
      PARTITION BY b.serv
      ORDER BY b.tablecnt ASC
    )                         AS rnk_asc
  FROM
    tblbusim b
),
avg_tbl AS (
  SELECT
    serv                      AS cateno,
    AVG(tablecnt)             AS avg_cnt
  FROM
    tblbusim
  GROUP BY
    serv
)
SELECT
  c.name                     AS 업종이름,
  rd.업체이름                AS 최대_업체이름,
  rd.테이블수                AS 최대_테이블_수,
  ra.업체이름                AS 최소_업체이름,
  ra.테이블수                AS 최소_테이블_수,
  ROUND(at.avg_cnt, 2)       AS 평균_테이블_수
FROM
  tblbsctl c
  JOIN avg_tbl at
    ON c.cateno = at.cateno
  LEFT JOIN ranked rd
    ON rd.cateno   = c.cateno
   AND rd.rnk_desc = 1
  LEFT JOIN ranked ra
    ON ra.cateno   = c.cateno
   AND ra.rnk_asc  = 1
ORDER BY
  c.name;


--- 3번
SELECT
    b.name AS 업체명,
    COALESCE(SUM(CASE WHEN a.gubun = 'I' THEN 1 ELSE 0 END), 0) AS 입고수,
    COALESCE(SUM(CASE WHEN a.gubun = 'O' THEN 1 ELSE 0 END), 0) AS 출고수,
    COALESCE(SUM(CASE WHEN a.gubun = 'L' THEN 1 ELSE 0 END), 0) AS 분실수,
    COALESCE(SUM(CASE WHEN a.gubun = 'D' THEN 1 ELSE 0 END), 0) AS 파기수
FROM
    tblbusim AS b
    LEFT JOIN tblstokm AS s
      ON s.busino = b.busino
    LEFT JOIN tblarext AS a
      ON a.stokno = s.stokno
     AND a.arexdate BETWEEN '2025-05-01' AND '2025-06-30'
GROUP BY
    b.name
ORDER BY
    b.name;

--- 4번
SELECT
  CASE
    WHEN GROUPING(b.name) = 0 THEN b.name
    ELSE c.name
  END AS "업체/업종",

  CASE
    WHEN GROUPING(s.position) = 0 THEN s.position
    ELSE NULL
  END AS 직책,

  COUNT(*) AS 인원수
FROM
  tblstafm AS s
  JOIN tblbusim AS b
    ON s.busino = b.busino
  JOIN tblbsctl AS c
    ON b.serv = c.cateno
GROUP BY
  GROUPING SETS (
    (b.name, s.position),
    (c.name)
  )
ORDER BY
  GROUPING(b.name) ASC,
  CASE
    WHEN GROUPING(b.name) = 0 THEN b.name
    ELSE NULL
  END ASC,
  CASE
    WHEN GROUPING(b.name) = 1
    THEN array_position(ARRAY['한식','중식','일식','양식'], c.name)
    ELSE NULL
  END ASC,
  직책;


--- 5번
SELECT
  b.name                AS 업체명,
  m.name                AS 메뉴이름,
  DATE(s.saledate)      AS 판매일자,
  SUM(d.count)          AS 총수량,
  SUM(d.price)          AS 총금액
FROM
  tblsalet  AS s
  JOIN tblsadtd  AS d ON s.saleno = d.saleno
  JOIN tblmenum  AS m ON d.menuno = m.menuno
  JOIN tblbusim  AS b ON s.busino = b.busino
WHERE
  s.saledate BETWEEN '2025-05-25' AND '2025-05-31'
GROUP BY
  b.name,
  m.name,
  DATE(s.saledate)
ORDER BY
  b.name,
  m.name,
  DATE(s.saledate);

--- 6번
SELECT
  b.name      AS 업체명,
  m.name      AS 메뉴이름,
  COUNT(*)    AS 총주문수
FROM
  tblsadtd AS d
  JOIN tblsalet AS s
    ON d.saleno = s.saleno
  JOIN tblmenum AS m
    ON d.menuno = m.menuno
  JOIN tblbusim AS b
    ON m.busino = b.busino
WHERE
  s.saledate BETWEEN '2025-05-25' AND '2025-06-15'
GROUP BY
  b.name,
  m.name
ORDER BY
  총주문수 DESC;

--- 7번
SELECT
  b.name                                  AS 업체명,
  s.name                                  AS 재고이름,
  CONCAT(s.appamount::TEXT, ' ', u.name)       AS "적정수량(단위)"
FROM
  tblbusim AS b
  JOIN tblstokm AS s
    ON s.busino = b.busino
  JOIN tblunitl AS u
    ON s.unit = u.cateno
ORDER BY
  b.name,
  s.name;

