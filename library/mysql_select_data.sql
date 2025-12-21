# 도서 테이블
SELECT
    book_id AS '도서ID',
    book_title AS '제목',
    book_author AS '저자',
    book_category_code AS '분류코드',
    book_isbn AS 'ISBN',
    book_publisher AS '발행처',
    book_pub_year AS '발행년도',
    book_pages AS '페이지수'
FROM tbl_book_1
ORDER BY book_id ASC;

# 보유도서위치 테이블
SELECT
    book_held_loc_id AS '보유도서위치코드',
    book_held_loc_name AS '위치명',
    CASE
        WHEN book_held_loc_floor < 0 THEN CONCAT('B', ABS(book_held_loc_floor)) -- 음수일 경우 B+숫자
        ELSE CONCAT(book_held_loc_floor, 'F') -- 양수일 경우 숫자+F
    END AS '도서관층'
FROM tbl_book_held_loc_1;

# 보유도서상태 테이블
SELECT
    book_held_status_id AS '보유도서상태코드',
    book_held_status_name AS '상태명'
FROM tbl_book_held_status_1;

# 보유도서 테이블
SELECT
    book_held_id AS '보유도서ID',
    book_id AS '도서ID',
    book_call_no AS '청구기호',
    book_held_loc_id AS '보유도서위치코드',
    book_held_status_id AS '보유도서상태코드'
FROM tbl_book_held_1;

# 회원 테이블
SELECT
    member_no AS '회원번호',
    member_id AS '아이디',
    member_passwd AS '비밀번호',
    member_loan_passwd AS '대출비밀번호',
    member_name AS '이름',
    member_age AS '나이',
    DATE_FORMAT(member_birth, '%Y.%c.%e') AS '생년월일', -- 2014.4.28 형식으로 변환
    member_phone AS '전화번호',
    member_addr AS '주소',
    member_email AS '이메일',
    member_grade_id AS '회원등급코드'
FROM tbl_member_1;

# 회원등급 테이블
SELECT
    member_grade_id AS '회원등급코드',
    member_grade_name AS '등급명',
    member_loan_day AS '대출일수'
FROM tbl_member_grade_1;

# 대출 테이블
SELECT
    loan_id AS '대출ID',
    book_held_id AS '보유도서ID',
    member_no AS '회원번호',
    DATE_FORMAT(loan_date, '%Y.%c.%e') AS '대출일',
    DATE_FORMAT(return_due_date, '%Y.%c.%e') AS '반납예정일',
    DATE_FORMAT(actual_return_date, '%Y.%c.%e') AS '실제반납일',
    extension_status AS '연장여부'
FROM tbl_loan_1;

# 연체 테이블
SELECT
    overdue_id AS '연체ID',
    book_held_id AS '보유도서ID',
    member_no AS '회원번호',
    DATE_FORMAT(overdue_start, '%Y.%c.%e') AS '연체시작일',
    DATE_FORMAT(overdue_end, '%Y.%c.%e') AS '연체종료일',
    overdue_status_id AS '연체상태코드'
FROM tbl_overdue_1;

# 연체상태 테이블
SELECT
    overdue_status_id AS '연체상태코드',
    overdue_status_name AS '상태명'
FROM tbl_overdue_status_1;

# 예약 테이블
SELECT
    reservation_id AS '예약ID',
    book_held_id AS '보유도서ID',
    member_no AS '회원번호',
    DATE_FORMAT(reservation_start, '%Y.%c.%e') AS '예약일',
    DATE_FORMAT(reservation_end, '%Y.%c.%e') AS '예약만기일',
    reservation_status_id AS '예약상태코드'
FROM tbl_reservation_1;

# 예약상태 테이블
SELECT
    reservation_status_id AS '예약상태코드',
    reservation_status_name AS '상태명'
FROM tbl_reservation_status_1;

# 변상 테이블
SELECT
    reimbursement_id AS '변상ID',
    book_held_id AS '보유도서ID',
    member_no AS '회원번호',
    DATE_FORMAT(reimbursement_date, '%Y.%c.%e') AS '변상일자',
    reimbursement_status AS '변상처리여부'
FROM tbl_reimbursement_1;

# 대출정지상태 테이블
SELECT
    loan_suspension_status_id AS '대출정지상태코드',
    loan_suspension_status_name AS '상태명'
FROM tbl_loan_suspension_status_1;

# 대출정지 테이블
SELECT
    loan_suspension_id AS '대출정지ID',
    member_no AS '회원번호',
    DATE_FORMAT(loan_suspension_start, '%Y.%c.%e') AS '대출정지시작일',
    DATE_FORMAT(loan_suspension_end, '%Y.%c.%e') AS '대출정지종료일',
    loan_suspension_status_id AS '대출정지상태코드'
FROM tbl_loan_suspension_1;

# 예약제한 테이블
SELECT
    reservation_suspension_id AS '예약제한기록ID',
    member_no AS '회원번호',
    DATE_FORMAT(reservation_suspension_start, '%Y.%c.%e') AS '제한시작일',
    DATE_FORMAT(reservation_suspension_end, '%Y.%c.%e') AS '제한종료일'
FROM tbl_reservation_suspension_1;
