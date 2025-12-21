# 도서 테이블
CREATE TABLE tbl_book_1 (
    book_id INT NOT NULL AUTO_INCREMENT COMMENT '도서 ID',
    book_title VARCHAR(200) NOT NULL COMMENT '도서 제목',
    book_author VARCHAR(100) NOT NULL COMMENT '도서 지은이, 옮긴이, 감수자',
    book_category_code VARCHAR(10) NOT NULL COMMENT '도서 카테고리를 의미하는 코드',
    book_isbn VARCHAR(23) NOT NULL COMMENT '도서 ISBN',
    book_publisher VARCHAR(15) NOT NULL COMMENT '도서를 발행한 출판사',
    book_pub_year INT NOT NULL COMMENT '도서 발행년도',
    book_pages INT NOT NULL COMMENT '도서 총 페이지 수',
    PRIMARY KEY (book_id)
) COMMENT = '도서 테이블' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

# 보유도서위치 테이블
CREATE TABLE tbl_book_held_loc_1 (
    book_held_loc_id INT NOT NULL AUTO_INCREMENT COMMENT '보유도서 위치 코드 (1, 2, 3...)',
    book_held_loc_name VARCHAR(15) NOT NULL COMMENT '보유도서 위치 이름 (종합자료실, 어린이실 등)',
    book_held_loc_floor INT NOT NULL COMMENT '보유도서 위치의 층 (2, -1 등)',
    PRIMARY KEY (book_held_loc_id)
) COMMENT = '보유 도서의 위치 정보' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

# 보유도서상태 테이블
CREATE TABLE tbl_book_held_status_1 (
    book_held_status_id INT NOT NULL AUTO_INCREMENT COMMENT '보유도서 상태코드 (1~9)',
    book_held_status_name VARCHAR(10) NOT NULL COMMENT '보유도서 상태 이름 (대출가능, 대출중 등)',
    PRIMARY KEY (book_held_status_id)
) COMMENT = '보유도서상태 테이블' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

# 보유도서 테이블
CREATE TABLE tbl_book_held_1 (
    book_held_id VARCHAR(12) NOT NULL COMMENT '보유도서 ID (EML/JUL + 숫자 9자리)',
    book_id INT NOT NULL COMMENT '도서 ID (FK)',
    book_call_no VARCHAR(30) NOT NULL COMMENT '청구기호',
    book_held_loc_id INT NOT NULL COMMENT '보유도서 위치코드 (FK)',
    book_held_status_id INT NOT NULL COMMENT '보유도서 상태코드 (FK)',

    PRIMARY KEY (book_held_id),

    -- 1. 도서 정보 외래키 (tbl_book_1)
    CONSTRAINT fk_held_book_id
        FOREIGN KEY (book_id) REFERENCES tbl_book_1 (book_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    -- 2. 위치 정보 외래키 (tbl_book_held_loc_1)
    CONSTRAINT fk_held_loc_id
        FOREIGN KEY (book_held_loc_id) REFERENCES tbl_book_held_loc_1 (book_held_loc_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    -- 3. 상태 정보 외래키 (tbl_book_held_status_1)
    CONSTRAINT fk_held_status_id
        FOREIGN KEY (book_held_status_id) REFERENCES tbl_book_held_status_1 (book_held_status_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) COMMENT = '도서관에 등록된 도서의 실물 정보' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

# 회원등급 테이블
CREATE TABLE tbl_member_grade_1 (
    member_grade_id INT NOT NULL AUTO_INCREMENT COMMENT '회원 등급 코드',
    member_grade_name VARCHAR(10) NOT NULL COMMENT '등급 이름 (일반, VIP)',
    member_loan_day INT NOT NULL COMMENT '등급별 대출 가능 일수 (14일, 21일)',
    PRIMARY KEY (member_grade_id)
) COMMENT = '회원 등급 정보' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

# 회원 테이블
CREATE TABLE tbl_member_1 (
    member_no VARCHAR(14) NOT NULL COMMENT '회원번호 (서울시+도서관+가입순서)',
    member_id VARCHAR(16) NOT NULL COMMENT '회원 아이디 (소문자/숫자, 10~16자)',
    member_passwd VARCHAR(64) NOT NULL COMMENT '회원 비밀번호 (해시값 저장)',
    member_loan_passwd CHAR(4) NOT NULL COMMENT '대출 비밀번호 (숫자 4자리)',
    member_name VARCHAR(10) NOT NULL COMMENT '회원 이름 (한국 이름)',
    member_age INT NOT NULL COMMENT '회원 나이',
    member_birth DATETIME NOT NULL COMMENT '회원 생년월일',
    member_phone CHAR(13) NOT NULL COMMENT '회원 전화번호 (010-0000-0000)',

    member_addr VARCHAR(255) NOT NULL COMMENT '회원 주소 (도로명 주소)',
    member_email VARCHAR(100) NOT NULL COMMENT '회원 이메일',

    -- 기본값 1(일반) 설정 및 FK 연결
    member_grade_id INT NOT NULL DEFAULT 1 COMMENT '회원등급코드 (FK)',

    PRIMARY KEY (member_no),

    -- 회원 등급 외래키 설정
    CONSTRAINT fk_member_grade
        FOREIGN KEY (member_grade_id) REFERENCES tbl_member_grade_1 (member_grade_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT

) COMMENT = '도서관에 가입한 회원 정보' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

# 대출 테이블
CREATE TABLE tbl_loan_1 (
    loan_id INT NOT NULL AUTO_INCREMENT COMMENT '대출 기록 ID',
    book_held_id VARCHAR(12) NOT NULL COMMENT '보유도서 ID (FK)',
    member_no VARCHAR(14) NOT NULL COMMENT '회원번호 (FK)',
    loan_date DATETIME NOT NULL COMMENT '대출 날짜',
    return_due_date DATETIME NOT NULL COMMENT '반납 예정 날짜',

    -- [설정] 반납이 아직 안 된 상태일 수 있으므로 NULL 허용
    actual_return_date DATETIME NULL COMMENT '실제 반납일 (미반납 시 NULL)',

    extension_status CHAR(1) NOT NULL COMMENT '대출 연장 여부 (Y/N)',

    PRIMARY KEY (loan_id),

    -- 1. 보유도서 외래키 (도서가 삭제되는 것을 방지: RESTRICT)
    CONSTRAINT fk_loan_book_held_id
        FOREIGN KEY (book_held_id) REFERENCES tbl_book_held_1 (book_held_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    -- 2. 회원 외래키 (회원이 삭제되면 대출 기록도 삭제: CASCADE)
    CONSTRAINT fk_loan_member_no
        FOREIGN KEY (member_no) REFERENCES tbl_member_1 (member_no)
        ON UPDATE CASCADE
        ON DELETE CASCADE

) COMMENT = '회원의 도서 대출 이력' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

# 연체상태 테이블
CREATE TABLE tbl_overdue_status_1 (
    overdue_status_id INT NOT NULL AUTO_INCREMENT COMMENT '도서 연체 상태 코드',
    overdue_status_name CHAR(1) NOT NULL COMMENT '도서 연체 상태 이름 (O:연체중, R:반납됨, D:분실/파손)',
    PRIMARY KEY (overdue_status_id)
) COMMENT = '연체 처리 상태' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

# 연체 테이블
CREATE TABLE tbl_overdue_1 (
    overdue_id INT NOT NULL AUTO_INCREMENT COMMENT '연체 기록 ID',
    book_held_id VARCHAR(12) NOT NULL COMMENT '보유도서 ID (FK)',
    member_no VARCHAR(14) NOT NULL COMMENT '회원번호 (FK)',
    overdue_start DATETIME NOT NULL COMMENT '도서의 연체 시작 날짜',

    -- [설정] 아직 연체 중(미반납)일 수 있으므로 NULL 허용
    overdue_end DATETIME NULL COMMENT '도서의 연체 종료 날짜 (미종료 시 NULL)',

    overdue_status_id INT NOT NULL COMMENT '도서 연체 상태 코드 (FK)',

    PRIMARY KEY (overdue_id),

    -- 1. 보유도서 외래키 (책 정보 보호: RESTRICT)
    CONSTRAINT fk_overdue_book_held_id
        FOREIGN KEY (book_held_id) REFERENCES tbl_book_held_1 (book_held_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    -- 2. 회원 외래키 (회원 삭제 시 연체기록 삭제: CASCADE)
    CONSTRAINT fk_overdue_member_no
        FOREIGN KEY (member_no) REFERENCES tbl_member_1 (member_no)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    -- 3. 연체상태 외래키 (상태코드 보호: RESTRICT)
    CONSTRAINT fk_overdue_status_id
        FOREIGN KEY (overdue_status_id) REFERENCES tbl_overdue_status_1 (overdue_status_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT

) COMMENT = '회원의 도서 연체 이력' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

# 예약상태 테이블
CREATE TABLE tbl_reservation_status_1 (
    reservation_status_id INT NOT NULL AUTO_INCREMENT COMMENT '예약 상태 코드',
    reservation_status_name CHAR(1) NOT NULL COMMENT '예약 상태 이름 (W:대기, A:가능, E:만료, C:취소)',
    PRIMARY KEY (reservation_status_id)
) COMMENT = '예약 처리 상태' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

# 예약 테이블
CREATE TABLE tbl_reservation_1 (
    reservation_id INT NOT NULL AUTO_INCREMENT COMMENT '예약 기록 ID',
    book_held_id VARCHAR(12) NOT NULL COMMENT '보유도서 ID (FK)',
    member_no VARCHAR(14) NOT NULL COMMENT '회원번호 (FK)',
    reservation_start DATETIME NOT NULL COMMENT '도서 예약 신청 날짜',

    -- [설정] 예약 만료일이 아직 정해지지 않았거나 유효한 상태일 수 있으므로 NULL 허용
    reservation_end DATETIME NULL COMMENT '도서 예약 신청 만기 날짜 (NULL 허용)',

    reservation_status_id INT NOT NULL COMMENT '도서 예약 상태 코드 (FK)',

    PRIMARY KEY (reservation_id),

    -- 1. 보유도서 외래키 (책 정보 보호: RESTRICT)
    CONSTRAINT fk_reserv_book_held_id
        FOREIGN KEY (book_held_id) REFERENCES tbl_book_held_1 (book_held_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    -- 2. 회원 외래키 (회원 탈퇴 시 예약기록 삭제: CASCADE)
    CONSTRAINT fk_reserv_member_no
        FOREIGN KEY (member_no) REFERENCES tbl_member_1 (member_no)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    -- 3. 예약상태 외래키 (상태코드 보호: RESTRICT)
    CONSTRAINT fk_reserv_status_id
        FOREIGN KEY (reservation_status_id) REFERENCES tbl_reservation_status_1 (reservation_status_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT

) COMMENT = '회원의 도서 예약 이력' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

# 변상 테이블
CREATE TABLE tbl_reimbursement_1 (
    reimbursement_id INT NOT NULL AUTO_INCREMENT COMMENT '변상 ID',
    book_held_id VARCHAR(12) NOT NULL COMMENT '보유도서 ID (FK)',
    member_no VARCHAR(14) NOT NULL COMMENT '회원번호 (FK)',

    -- [설정] 변상 처리가 완료되지 않은 상태(신청 단계 등)일 수 있으므로 NULL 허용
    reimbursement_date DATETIME NULL COMMENT '변상 처리한 날짜',

    reimbursement_status CHAR(1) NOT NULL COMMENT '변상 처리 여부 (Y: 변상완료, N: 변상 처리 안 됨)',

    PRIMARY KEY (reimbursement_id),

    -- 1. 보유도서 외래키 (변상 기록이 있는 책 정보 삭제 방지: RESTRICT)
    CONSTRAINT fk_reimbursement_book_held
        FOREIGN KEY (book_held_id) REFERENCES tbl_book_held_1 (book_held_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    -- 2. 회원 외래키 (회원 탈퇴 시 변상 기록 삭제: CASCADE)
    CONSTRAINT fk_reimbursement_member
        FOREIGN KEY (member_no) REFERENCES tbl_member_1 (member_no)
        ON UPDATE CASCADE
        ON DELETE CASCADE

) COMMENT = '파손/분실된 보유도서에 대한 변상 기록' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

# 대출정지상태 테이블
CREATE TABLE tbl_loan_suspension_status_1 (
    loan_suspension_status_id INT NOT NULL AUTO_INCREMENT COMMENT '대출 정지 상태 코드',
    loan_suspension_status_name CHAR(1) NOT NULL COMMENT '상태 이름 (S:대출정지, P:연체료지불, D:대출정지해제)',
    PRIMARY KEY (loan_suspension_status_id)
) COMMENT = '대출 정지 상태' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

# 대출정지 테이블
CREATE TABLE tbl_loan_suspension_1 (
    loan_suspension_id INT NOT NULL AUTO_INCREMENT COMMENT '대출 정지 ID',
    member_no VARCHAR(14) NOT NULL COMMENT '회원번호 (FK)',
    loan_suspension_start DATETIME NOT NULL COMMENT '대출 정지 시작 날짜',
    loan_suspension_end DATETIME NOT NULL COMMENT '대출 정지 종료 날짜',
    loan_suspension_status_id INT NOT NULL COMMENT '대출 정지 상태 코드 (FK)',

    PRIMARY KEY (loan_suspension_id),

    -- 1. 회원 외래키 (회원 탈퇴 시 정지 기록 삭제: CASCADE)
    CONSTRAINT fk_suspension_member_no
        FOREIGN KEY (member_no) REFERENCES tbl_member_1 (member_no)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    -- 2. 상태 외래키 (상태 코드 보호: RESTRICT)
    CONSTRAINT fk_suspension_status_id
        FOREIGN KEY (loan_suspension_status_id) REFERENCES tbl_loan_suspension_status_1 (loan_suspension_status_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT

) COMMENT = '회원의 대출 정지 기록' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

# 예약제한 테이블
CREATE TABLE tbl_reservation_suspension_1 (
    reservation_suspension_id INT NOT NULL AUTO_INCREMENT COMMENT '예약 제한 기록 ID',
    member_no VARCHAR(14) NOT NULL COMMENT '회원번호 (FK)',
    reservation_suspension_start DATETIME NOT NULL COMMENT '예약 제한 시작 날짜',
    reservation_suspension_end DATETIME NOT NULL COMMENT '예약 제한 종료 날짜',

    PRIMARY KEY (reservation_suspension_id),

    -- 회원 외래키 (회원 탈퇴 시 제한 기록 삭제: CASCADE)
    CONSTRAINT fk_res_suspension_member
        FOREIGN KEY (member_no) REFERENCES tbl_member_1 (member_no)
        ON UPDATE CASCADE
        ON DELETE CASCADE

) COMMENT = '예약 제한 기록' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
