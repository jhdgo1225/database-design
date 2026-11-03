-- 측정용 대량 샘플 (반정규화 스키마). insert_data.sql 적재 후에 실행한다.

-- =====================================================================================================
-- [공통 생성 로직] 정규화(postgresql)와 반정규화(postgresql_denormalized)의 insert_data_bulk.sql 에서 동일하다.
--   난수 대신 md5 해시로 값을 만들기 때문에 실행할 때마다, 그리고 두 스키마에서 항상 같은 데이터가 생성된다.
--   기존 샘플(insert_data.sql)을 먼저 적재한 뒤에 실행한다. 기존 샘플과 겹치지 않는 ID 범위를 사용한다.
--     도서 book_id 1001~6000 (5,000종) / 사본 약 12,500권 / 회원 번호 1001~11000 (10,000명)
--     대출은 사본별로 2~42건, 총 약 19만 건 (최근 대출일 2025-03-05 ~ 2025-03-31, 가장 오래된 대출 2022년 초)
--   사본의 마지막 대출 중 5%는 미반납(연체중)이며, 이 사본의 상태는 '대출중'이다.
--   대출정지/예약/예약제한/변상 이력은 생성하지 않는다. (정보시스템 쿼리 1~8번이 사용하지 않음)
-- =====================================================================================================

-- 시드 문자열 -> 0 ~ 2^28-1 정수 (결정적 의사 난수)
CREATE FUNCTION pg_temp.bulk_hash(seed TEXT) RETURNS INT AS $$
    SELECT ('x' || substr(md5(seed), 1, 7))::bit(28)::INT
$$ LANGUAGE sql IMMUTABLE;

-- 도서 5,000종: ISBN 은 국내 표기 규칙(978-89 + 3자리 발행자번호, 979-11 + 4자리 발행자번호)과 체크기호를 맞춘다.
CREATE TEMP TABLE bulk_book AS
SELECT t.*,
       t.isbn_body || '-' || ((10 - (
           SELECT sum(substr(replace(t.isbn_body, '-', ''), i, 1)::INT * CASE WHEN i % 2 = 1 THEN 1 ELSE 3 END)
           FROM generate_series(1, 12) AS i
       ) % 10) % 10) AS book_isbn
FROM (
    SELECT
        1000 + g AS book_id,
        g,
        '샘플 도서 ' || lpad(g::text, 5, '0') AS book_title,
        '샘플 저자 ' || (g % 700 + 1) AS book_author,
        (ARRAY['005.1', '160', '239', '399', '412.85', '414.1', '454', '711.4', '808', '808.9', '813.6', '833.6'])[g % 12 + 1] AS book_category_code,
        CASE WHEN g % 10 < 5
             THEN '978-89-' || (400 + g % 10) || '-' || (1000 + g / 10)
             ELSE '979-11-' || (5700 + g % 10 - 5) || '-' || lpad((g / 10)::text, 3, '0')
        END AS isbn_body,
        '샘플출판사' || (g % 10 + 1) AS book_publisher,
        1990 + g % 36 AS book_pub_year,
        100 + (g * 37) % 700 AS book_pages,
        1 + g % 4 AS copy_cnt
    FROM generate_series(1, 5000) AS g
) t;

-- 보유도서(사본): 도서당 1~4권, 복본기호(=N)는 사본 번호
CREATE TEMP TABLE bulk_copy AS
SELECT s.*,
       2 + floor(power(pg_temp.bulk_hash('n' || s.copy_seq) / 268435456.0, 2) * 40)::INT AS loan_cnt,
       (s.copy_seq % 20 = 0) AS open_last,
       CASE WHEN s.book_category_code IN ('711.4', '808.9') THEN 'C'
            WHEN s.copy_seq % 25 = 0 THEN 'S'
            ELSE 'G'
       END AS loc_code,
       CASE WHEN s.copy_seq % 20 = 0 THEN 'L'
            WHEN s.copy_seq % 50 = 7 THEN 'M'
            ELSE 'A'
       END AS status_code
FROM (
    SELECT
        row_number() OVER (ORDER BY b.book_id, k) AS copy_seq,
        b.book_id,
        k AS copy_no,
        b.book_category_code,
        b.book_category_code || '-샘플' || b.g || CASE WHEN k > 1 THEN '=' || k ELSE '' END AS book_call_no
    FROM bulk_book b
    CROSS JOIN LATERAL generate_series(1, b.copy_cnt) AS k
) s;

-- 회원 10,000명: 10명 중 1명은 VIP
CREATE TEMP TABLE bulk_member AS
SELECT
    1000 + g AS n,
    '11101001' || lpad((1000 + g)::text, 6, '0') AS member_no,
    'user' || lpad((1000 + g)::text, 8, '0') AS member_id,
    md5((1000 + g)::text) || md5('pw' || (1000 + g)) AS member_passwd,
    lpad(((1000 + g) * 7919 % 10000)::text, 4, '0') AS member_loan_passwd,
    '샘플회원' || (1000 + g) AS member_name,
    10 + g % 60 AS member_age,
    DATE '2026-01-01' - ((10 + g % 60) * 365 + g % 365) AS member_birth,
    '010-' || lpad((g % 10000)::text, 4, '0') || '-' || lpad((g * 31 % 10000)::text, 4, '0') AS member_phone,
    '서울시 동작구 샘플로 ' || (1000 + g) AS member_addr,
    'user' || lpad((1000 + g)::text, 8, '0') || '@example.com' AS member_email,
    (g % 10 = 0) AS is_vip
FROM generate_series(1, 10000) AS g;

-- 대출: 사본별로 28일 간격, 최근 대출일이 2025-03-31 직전이 되도록 거꾸로 배치 (같은 사본의 대출 기간이 겹치지 않음)
--   대출 회원은 앞쪽 번호에 쏠리게(제곱 분포) 정하고, 10%는 연장(+7일), 반납일이 반납예정일을 넘으면 연체 이력 생성
CREATE TEMP TABLE bulk_loan AS
SELECT y.*,
       CASE WHEN y.actual_return_date IS NULL OR y.actual_return_date > y.return_due_date
            THEN y.return_due_date + 1 END AS overdue_start,
       CASE WHEN y.actual_return_date > y.return_due_date
            THEN y.actual_return_date END AS overdue_end,
       CASE WHEN y.actual_return_date IS NULL THEN 'O'
            WHEN y.actual_return_date > y.return_due_date THEN 'R' END AS overdue_status_code
FROM (
    SELECT x.*,
           x.loan_date + CASE WHEN m.is_vip THEN 21 ELSE 14 END + CASE WHEN x.is_ext THEN 7 ELSE 0 END AS return_due_date,
           CASE WHEN x.is_ext THEN 'Y' ELSE 'N' END AS extension_status,
           m.member_no,
           CASE WHEN x.is_open THEN NULL
                ELSE x.loan_date + 3 + pg_temp.bulk_hash('r' || x.copy_seq || '/' || x.j) % 16
           END AS actual_return_date
    FROM (
        SELECT
            row_number() OVER (ORDER BY c.copy_seq, j) AS loan_seq,
            c.copy_seq,
            c.book_id,
            c.copy_no,
            j,
            DATE '2025-03-31' - ((c.loan_cnt - j) * 28 + c.copy_seq % 27)::INT AS loan_date,
            (c.open_last AND j = c.loan_cnt) AS is_open,
            (pg_temp.bulk_hash('e' || c.copy_seq || '/' || j) % 10 = 0) AS is_ext,
            1001 + floor(power(pg_temp.bulk_hash('m' || c.copy_seq || '/' || j) / 268435456.0, 2) * 10000)::INT AS member_n
        FROM bulk_copy c
        CROSS JOIN LATERAL generate_series(1, c.loan_cnt) AS j
    ) x
    JOIN bulk_member m ON m.n = x.member_n
) y;

ANALYZE bulk_loan;

-- 보유도서 테이블: book_no 는 트리거가 book_id 별 반입 순서로 부여하므로 사본 번호 순서(copy_seq)대로 넣는다.
--   트리거가 같은 book_id 에 어드바이저리 락을 잡는데, 락은 트랜잭션이 끝나야 풀리고 공유 락 테이블 크기에 한도가 있으므로
--   한 문장에서 처리하는 도서 수를 1,000종으로 나눠 실행한다.
INSERT INTO tbl_book_held_1 (book_id, book_title, book_author, book_category_code, book_isbn, book_publisher, book_pub_year, book_pages, book_call_no, book_held_loc_code, book_held_status_code)
SELECT c.book_id, b.book_title, b.book_author, b.book_category_code, b.book_isbn, b.book_publisher, b.book_pub_year, b.book_pages, c.book_call_no, c.loc_code, c.status_code
FROM bulk_copy c JOIN bulk_book b USING (book_id)
WHERE c.book_id BETWEEN 1001 AND 2000
ORDER BY c.copy_seq;

INSERT INTO tbl_book_held_1 (book_id, book_title, book_author, book_category_code, book_isbn, book_publisher, book_pub_year, book_pages, book_call_no, book_held_loc_code, book_held_status_code)
SELECT c.book_id, b.book_title, b.book_author, b.book_category_code, b.book_isbn, b.book_publisher, b.book_pub_year, b.book_pages, c.book_call_no, c.loc_code, c.status_code
FROM bulk_copy c JOIN bulk_book b USING (book_id)
WHERE c.book_id BETWEEN 2001 AND 3000
ORDER BY c.copy_seq;

INSERT INTO tbl_book_held_1 (book_id, book_title, book_author, book_category_code, book_isbn, book_publisher, book_pub_year, book_pages, book_call_no, book_held_loc_code, book_held_status_code)
SELECT c.book_id, b.book_title, b.book_author, b.book_category_code, b.book_isbn, b.book_publisher, b.book_pub_year, b.book_pages, c.book_call_no, c.loc_code, c.status_code
FROM bulk_copy c JOIN bulk_book b USING (book_id)
WHERE c.book_id BETWEEN 3001 AND 4000
ORDER BY c.copy_seq;

INSERT INTO tbl_book_held_1 (book_id, book_title, book_author, book_category_code, book_isbn, book_publisher, book_pub_year, book_pages, book_call_no, book_held_loc_code, book_held_status_code)
SELECT c.book_id, b.book_title, b.book_author, b.book_category_code, b.book_isbn, b.book_publisher, b.book_pub_year, b.book_pages, c.book_call_no, c.loc_code, c.status_code
FROM bulk_copy c JOIN bulk_book b USING (book_id)
WHERE c.book_id BETWEEN 4001 AND 5000
ORDER BY c.copy_seq;

INSERT INTO tbl_book_held_1 (book_id, book_title, book_author, book_category_code, book_isbn, book_publisher, book_pub_year, book_pages, book_call_no, book_held_loc_code, book_held_status_code)
SELECT c.book_id, b.book_title, b.book_author, b.book_category_code, b.book_isbn, b.book_publisher, b.book_pub_year, b.book_pages, c.book_call_no, c.loc_code, c.status_code
FROM bulk_copy c JOIN bulk_book b USING (book_id)
WHERE c.book_id BETWEEN 5001 AND 6000
ORDER BY c.copy_seq;

-- 회원 테이블 (회원등급 반정규화: 일반 N=14일, VIP V=21일)
INSERT INTO tbl_member_1 (member_no, member_id, member_passwd, member_loan_passwd, member_name, member_age, member_birth, member_phone, member_addr, member_email, member_grade_code, member_loan_day)
SELECT member_no, member_id, member_passwd, member_loan_passwd, member_name, member_age, member_birth, member_phone, member_addr, member_email,
       CASE WHEN is_vip THEN 'V' ELSE 'N' END,
       CASE WHEN is_vip THEN 21 ELSE 14 END
FROM bulk_member
ORDER BY n;

-- 대출 테이블 (연체 이력 반정규화 통합)
INSERT INTO tbl_loan_1 (loan_id, book_id, book_no, member_no, loan_date, return_due_date, actual_return_date, extension_status, overdue_start, overdue_end, overdue_status_code)
SELECT 1000 + l.loan_seq, l.book_id, l.copy_no,
       l.member_no, l.loan_date, l.return_due_date, l.actual_return_date, l.extension_status,
       l.overdue_start, l.overdue_end, l.overdue_status_code
FROM bulk_loan l
ORDER BY l.loan_seq;

-- 명시적으로 ID 를 입력했으므로 시퀀스를 다음 값으로 맞춤
SELECT setval('seq_book_id', (SELECT MAX(book_id) FROM tbl_book_held_1) + 1, false);
SELECT setval(pg_get_serial_sequence('tbl_loan_1', 'loan_id'), (SELECT MAX(loan_id) FROM tbl_loan_1) + 1, false);

ANALYZE;

DROP TABLE bulk_loan, bulk_member, bulk_copy, bulk_book;
DROP FUNCTION pg_temp.bulk_hash(TEXT);
