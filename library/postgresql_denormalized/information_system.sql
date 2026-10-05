-- # 1번: 대출 상위 5위의 도서 정보를 구하라
-- [반정규화 영향] tbl_book_1은 사라졌지만 book_id를 tbl_book_held_1에 그대로 반정규화해두었으므로
-- 같은 책의 여러 보유 사본(book_held_id)을 book_id 기준으로 묶어 집계합니다.

SELECT
    bh.book_id,
    bh.book_title,
    bh.book_author,
    bh.book_publisher,
    COUNT(*) AS loan_count
FROM tbl_loan_1 l
JOIN tbl_book_held_1 bh ON l.book_held_id = bh.book_held_id
GROUP BY
    bh.book_id
ORDER BY loan_count DESC
LIMIT 5;                      -- N개 만큼 행 출력
-- FETCH FIRST 5 ROW ONLY;       -- N개 만큼 행 출력
-- FETCH FIRST 5 ROW WITH TIES;  -- 동점자 포함 N위 출력

-- # 2번: 대출 상위 5위의 회원 정보를 구하라.
SELECT
    m.member_no,
    m.member_name,
    m.member_phone,
    m.member_addr,
    m.member_email,
    COUNT(*) AS loan_count
FROM tbl_loan_1 l
JOIN tbl_member_1 m ON l.member_no = m.member_no
GROUP BY
    m.member_no
ORDER BY loan_count DESC
-- LIMIT 5;                      -- N개 만큼 행 출력
-- FETCH FIRST 5 ROW ONLY;       -- N개 만큼 행 출력
FETCH FIRST 5 ROW WITH TIES;  -- 동점자 포함 N위 출력

-- # 3번: 우리 도서관의 도서에 대한 분류별 도서 수를 구하라
-- [반정규화 영향] 도서 분류 코드가 tbl_book_held_1에 직접 있으므로 JOIN 없이 바로 집계합니다.
SELECT
    book_category_code,
    COUNT(*) AS book_count
FROM tbl_book_held_1
GROUP BY book_category_code;

-- # 4번: 오늘 미납 도서가 있는 회원의 정보를 구하라
SELECT DISTINCT
    m.member_no,
    m.member_name,
    m.member_phone,
    m.member_addr,
    m.member_email,
    l.return_due_date
FROM tbl_loan_1 l
JOIN tbl_member_1 m ON l.member_no = m.member_no
WHERE l.actual_return_date IS NULL
  AND l.return_due_date < CURRENT_DATE;

-- # 5번: 현재 대여 중인 도서의 분류별 통계를 구하라
-- [반정규화 영향] tbl_book_1 JOIN 제거, book_category_code는 tbl_book_held_1에서 바로 사용
SELECT
    bh.book_category_code,
    COUNT(*) AS loaned_book_count
FROM tbl_loan_1 l
JOIN tbl_book_held_1 bh ON l.book_held_id = bh.book_held_id
WHERE l.actual_return_date IS NULL
GROUP BY bh.book_category_code;

-- # 6번: 분류별 대출 권수가 많은 상위 5위를 구하라.
-- [반정규화 영향] tbl_book_1 JOIN 제거, book_category_code는 tbl_book_held_1에서 바로 사용
SELECT
    bh.book_category_code,
    COUNT(*) AS loan_count
FROM tbl_loan_1 l
JOIN tbl_book_held_1 bh ON l.book_held_id = bh.book_held_id
GROUP BY bh.book_category_code
ORDER BY loan_count DESC
-- LIMIT 5;                      -- N개 만큼 행 출력
-- FETCH FIRST 5 ROW ONLY;       -- N개 만큼 행 출력
FETCH FIRST 5 ROW WITH TIES;  -- 동점자 포함 N위 출력

-- # 7번: 2022~2024년까지 월별 대여 권수를 구하라(대여일 기준)
SELECT
    TO_CHAR(loan_date, 'YYYY-MM') AS loan_month,
    COUNT(*) AS loan_count
FROM tbl_loan_1
WHERE loan_date BETWEEN '2022-01-01' AND '2024-12-31'
GROUP BY loan_month
ORDER BY loan_month;

-- # 8번: 계절별 대출 권수의 분포를 구하라
SELECT
    CASE
      WHEN EXTRACT(MONTH FROM loan_date) IN (12, 1, 2) THEN 'Winter'
      WHEN EXTRACT(MONTH FROM loan_date) IN (3, 4, 5) THEN 'Spring'
      WHEN EXTRACT(MONTH FROM loan_date) IN (6, 7, 8) THEN 'Summer'
      WHEN EXTRACT(MONTH FROM loan_date) IN (9, 10, 11) THEN 'Autumn'
    END AS season,
    COUNT(*) AS loan_count
FROM tbl_loan_1
GROUP BY season;
