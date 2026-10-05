-- 이전 데이터 구조인 경우, 삭제하는 단계

DROP TABLE IF EXISTS tbl_loan_1;
DROP TABLE IF EXISTS tbl_reservation_1;
DROP TABLE IF EXISTS tbl_reimbursement_1;
DROP TABLE IF EXISTS tbl_overdue_1;
DROP TABLE IF EXISTS tbl_reservation_status_1;
DROP TABLE IF EXISTS tbl_overdue_status_1;
DROP TABLE IF EXISTS tbl_loan_suspension_1;
DROP TABLE IF EXISTS tbl_loan_suspension_status_1;
DROP TABLE IF EXISTS tbl_reservation_suspension_1;
DROP TABLE IF EXISTS tbl_member_1;
DROP TABLE IF EXISTS tbl_member_grade_1;
DROP TABLE IF EXISTS tbl_book_held_1;
DROP TABLE IF EXISTS tbl_book_1;
DROP TABLE IF EXISTS tbl_book_held_loc_1;
DROP TABLE IF EXISTS tbl_book_held_status_1;

-- 보유도서 테이블 (도서, 보유도서위치, 보유도서상태를 반정규화하여 흡수)
CREATE TABLE tbl_book_held_1 (
    book_held_id UUID NOT NULL DEFAULT gen_random_uuid(),
    book_id INT NOT NULL,
    book_title VARCHAR(200) NOT NULL,
    book_author VARCHAR(100) NOT NULL,
    book_category_code VARCHAR(10) NOT NULL,
    book_isbn VARCHAR(23) NOT NULL,
    book_publisher VARCHAR(15) NOT NULL,
    book_pub_year INT NOT NULL,
    book_pages INT NOT NULL,
    book_call_no VARCHAR(30) NOT NULL,
    book_held_loc_code CHAR(1) NOT NULL,
    book_held_status_code CHAR(1) NOT NULL,

    PRIMARY KEY (book_held_id),

    -- 보유도서위치 도메인 제약 (CHECK로 코드값 제한, FK 대체)
    CONSTRAINT chk_held_loc
        CHECK (book_held_loc_code IN ('G', 'C', 'S')),

    -- 보유도서상태 도메인 제약 (CHECK로 코드값 제한, FK 대체)
    CONSTRAINT chk_held_status
        CHECK (book_held_status_code IN ('A', 'L', 'O', 'R', 'N', 'M', 'F', 'D'))
);
COMMENT ON TABLE tbl_book_held_1 IS '도서관에 등록된 도서의 실물 정보 (도서/위치/상태 반정규화 통합)';
COMMENT ON COLUMN tbl_book_held_1.book_held_id IS '보유도서 ID (UUID)';
COMMENT ON COLUMN tbl_book_held_1.book_id IS '원본 도서 ID (반정규화, FK 아님, 같은 책의 여러 사본을 묶는 식별자)';
COMMENT ON COLUMN tbl_book_held_1.book_title IS '도서 제목 (반정규화)';
COMMENT ON COLUMN tbl_book_held_1.book_author IS '도서 지은이, 옮긴이, 감수자 (반정규화)';
COMMENT ON COLUMN tbl_book_held_1.book_category_code IS '도서 카테고리를 의미하는 코드 (반정규화)';
COMMENT ON COLUMN tbl_book_held_1.book_isbn IS '도서 ISBN (반정규화)';
COMMENT ON COLUMN tbl_book_held_1.book_publisher IS '도서를 발행한 출판사 (반정규화)';
COMMENT ON COLUMN tbl_book_held_1.book_pub_year IS '도서 발행년도 (반정규화)';
COMMENT ON COLUMN tbl_book_held_1.book_pages IS '도서 총 페이지 수 (반정규화)';
COMMENT ON COLUMN tbl_book_held_1.book_call_no IS '청구기호';
COMMENT ON COLUMN tbl_book_held_1.book_held_loc_code IS '보유도서 위치 코드 (G:종합자료실(2층), C:어린이실(-1층), S:보존서고(2층))';
COMMENT ON COLUMN tbl_book_held_1.book_held_status_code IS '보유도서 상태 코드 (A:대출가능, L:대출중, O:연체중, R:예약됨, N:예약불가, M:보수중, F:분실, D:폐기)';

-- 회원 테이블 (회원등급을 반정규화하여 흡수, 대출정지/예약제한 현재 상태 포함)
CREATE TABLE tbl_member_1 (
    member_no VARCHAR(14) NOT NULL,
    member_id VARCHAR(16) NOT NULL,
    member_passwd VARCHAR(64) NOT NULL,
    member_loan_passwd CHAR(4) NOT NULL,
    member_name VARCHAR(10) NOT NULL,
    member_age INT NOT NULL,
    member_birth TIMESTAMP NOT NULL,
    member_phone CHAR(13) NOT NULL,

    member_addr VARCHAR(255) NOT NULL,
    member_email VARCHAR(100) NOT NULL,

    -- [반정규화] 회원등급 (기본값 'N'=일반)
    member_grade_code CHAR(1) NOT NULL DEFAULT 'N',
    member_loan_day INT NOT NULL DEFAULT 14,

    -- [반정규화] 대출정지 현재 상태 (정지 이력 없으면 모두 NULL)
    member_loan_suspension_status_code CHAR(1) NULL,
    member_loan_suspension_start TIMESTAMP NULL,
    member_loan_suspension_end TIMESTAMP NULL,

    -- [반정규화] 예약제한 현재 상태 (제한 이력 없으면 모두 NULL)
    member_reservation_suspension_start TIMESTAMP NULL,
    member_reservation_suspension_end TIMESTAMP NULL,

    PRIMARY KEY (member_no),

    -- 1. 회원등급 도메인 제약 (등급 코드-대출일수 조합을 CHECK로 고정, FK 대체)
    CONSTRAINT chk_member_grade
        CHECK (
            (member_grade_code = 'N' AND member_loan_day = 14) OR
            (member_grade_code = 'V' AND member_loan_day = 21)
        ),

    -- 2. 대출정지상태 도메인 제약 (CHECK로 코드값 제한, FK 대체, 정지 없음 시 NULL 허용)
    CONSTRAINT chk_member_loan_suspension_status
        CHECK (member_loan_suspension_status_code IS NULL OR member_loan_suspension_status_code IN ('S', 'P', 'D'))
);
COMMENT ON TABLE tbl_member_1 IS '도서관에 가입한 회원 정보 (회원등급 반정규화, 대출정지/예약제한 현재 상태 포함)';
COMMENT ON COLUMN tbl_member_1.member_no IS '회원번호 (서울시+도서관+가입순서)';
COMMENT ON COLUMN tbl_member_1.member_id IS '회원 아이디 (소문자/숫자, 10~16자)';
COMMENT ON COLUMN tbl_member_1.member_passwd IS '회원 비밀번호 (해시값 저장)';
COMMENT ON COLUMN tbl_member_1.member_loan_passwd IS '대출 비밀번호 (숫자 4자리)';
COMMENT ON COLUMN tbl_member_1.member_name IS '회원 이름 (한국 이름)';
COMMENT ON COLUMN tbl_member_1.member_age IS '회원 나이';
COMMENT ON COLUMN tbl_member_1.member_birth IS '회원 생년월일';
COMMENT ON COLUMN tbl_member_1.member_phone IS '회원 전화번호 (010-0000-0000)';
COMMENT ON COLUMN tbl_member_1.member_addr IS '회원 주소 (도로명 주소)';
COMMENT ON COLUMN tbl_member_1.member_email IS '회원 이메일';
COMMENT ON COLUMN tbl_member_1.member_grade_code IS '회원등급 코드 (N:일반, V:VIP, 반정규화)';
COMMENT ON COLUMN tbl_member_1.member_loan_day IS '등급별 대출 가능 일수 (N=14일, V=21일, 반정규화)';
COMMENT ON COLUMN tbl_member_1.member_loan_suspension_status_code IS '대출정지 상태 코드 (S:대출정지, P:연체료지불, D:대출정지해제, 반정규화, 정지 없음 시 NULL)';
COMMENT ON COLUMN tbl_member_1.member_loan_suspension_start IS '대출정지 시작 날짜 (반정규화, 정지 없음 시 NULL)';
COMMENT ON COLUMN tbl_member_1.member_loan_suspension_end IS '대출정지 종료 날짜 (반정규화, 정지 없음 시 NULL)';
COMMENT ON COLUMN tbl_member_1.member_reservation_suspension_start IS '예약제한 시작 날짜 (반정규화, 제한 없음 시 NULL)';
COMMENT ON COLUMN tbl_member_1.member_reservation_suspension_end IS '예약제한 종료 날짜 (반정규화, 제한 없음 시 NULL)';

-- 대출 테이블 (연체, 변상 이력을 반정규화하여 흡수)
CREATE TABLE tbl_loan_1 (
    loan_id INT NOT NULL GENERATED BY DEFAULT AS IDENTITY,
    book_held_id UUID NOT NULL,
    member_no VARCHAR(14) NOT NULL,
    loan_date TIMESTAMP NOT NULL,
    return_due_date TIMESTAMP NOT NULL,

    -- [설정] 반납이 아직 안 된 상태일 수 있으므로 NULL 허용
    actual_return_date TIMESTAMP NULL,

    extension_status CHAR(1) NOT NULL,

    -- [반정규화] 연체 이력 (해당 대출 건이 연체된 적이 없으면 모두 NULL)
    overdue_start TIMESTAMP NULL,
    overdue_end TIMESTAMP NULL,
    overdue_status_code CHAR(1) NULL,

    -- [반정규화] 변상 이력 (해당 대출 건에 변상 사유가 없으면 모두 NULL)
    reimbursement_date TIMESTAMP NULL,
    reimbursement_status CHAR(1) NULL,

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
        ON DELETE CASCADE,

    -- 3. 연체상태 도메인 제약 (CHECK로 코드값 제한, FK 대체, 연체 없음 시 NULL 허용)
    CONSTRAINT chk_loan_overdue_status
        CHECK (overdue_status_code IS NULL OR overdue_status_code IN ('O', 'R', 'D')),

    -- 4. 변상여부 도메인 제약 (CHECK로 코드값 제한, 변상 없음 시 NULL 허용)
    CONSTRAINT chk_loan_reimbursement_status
        CHECK (reimbursement_status IS NULL OR reimbursement_status IN ('Y', 'N'))
);
COMMENT ON TABLE tbl_loan_1 IS '회원의 도서 대출 이력 (연체/변상 이력 반정규화 통합)';
COMMENT ON COLUMN tbl_loan_1.loan_id IS '대출 기록 ID';
COMMENT ON COLUMN tbl_loan_1.book_held_id IS '보유도서 ID (FK)';
COMMENT ON COLUMN tbl_loan_1.member_no IS '회원번호 (FK)';
COMMENT ON COLUMN tbl_loan_1.loan_date IS '대출 날짜';
COMMENT ON COLUMN tbl_loan_1.return_due_date IS '반납 예정 날짜';
COMMENT ON COLUMN tbl_loan_1.actual_return_date IS '실제 반납일 (미반납 시 NULL)';
COMMENT ON COLUMN tbl_loan_1.extension_status IS '대출 연장 여부 (Y/N)';
COMMENT ON COLUMN tbl_loan_1.overdue_start IS '연체 시작 날짜 (반정규화, 연체 이력 없으면 NULL)';
COMMENT ON COLUMN tbl_loan_1.overdue_end IS '연체 종료 날짜 (반정규화, 미종료/연체 없음 시 NULL)';
COMMENT ON COLUMN tbl_loan_1.overdue_status_code IS '연체 상태 코드 (O:연체중, R:반납됨, D:분실/파손, 반정규화, 연체 없음 시 NULL)';
COMMENT ON COLUMN tbl_loan_1.reimbursement_date IS '변상 처리 날짜 (반정규화, 변상 이력 없으면 NULL)';
COMMENT ON COLUMN tbl_loan_1.reimbursement_status IS '변상 처리 여부 코드 (Y:변상완료, N:변상 처리 안 됨, 반정규화, 변상 없음 시 NULL)';

-- 예약 테이블 (예약상태 테이블을 반정규화하여 흡수)
CREATE TABLE tbl_reservation_1 (
    reservation_id INT NOT NULL GENERATED BY DEFAULT AS IDENTITY,
    book_held_id UUID NOT NULL,
    member_no VARCHAR(14) NOT NULL,
    reservation_start TIMESTAMP NOT NULL,

    -- [설정] 예약 만료일이 아직 정해지지 않았거나 유효한 상태일 수 있으므로 NULL 허용
    reservation_end TIMESTAMP NULL,

    reservation_status_code CHAR(1) NOT NULL,

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

    -- 3. 예약상태 도메인 제약 (CHECK로 코드값 제한, FK 대체)
    CONSTRAINT chk_reserv_status
        CHECK (reservation_status_code IN ('W', 'A', 'E', 'C'))
);
COMMENT ON TABLE tbl_reservation_1 IS '회원의 도서 예약 이력 (예약상태 반정규화 통합)';
COMMENT ON COLUMN tbl_reservation_1.reservation_id IS '예약 기록 ID';
COMMENT ON COLUMN tbl_reservation_1.book_held_id IS '보유도서 ID (FK)';
COMMENT ON COLUMN tbl_reservation_1.member_no IS '회원번호 (FK)';
COMMENT ON COLUMN tbl_reservation_1.reservation_start IS '도서 예약 신청 날짜';
COMMENT ON COLUMN tbl_reservation_1.reservation_end IS '도서 예약 신청 만기 날짜 (NULL 허용)';
COMMENT ON COLUMN tbl_reservation_1.reservation_status_code IS '예약 상태 코드 (W:대기, A:가능, E:만료, C:취소, 반정규화)';

-- 제한이력 테이블 (대출정지 테이블 + 예약제한 테이블 통합, 대출정지상태 테이블 반정규화 흡수)
CREATE TABLE tbl_restriction_1 (
    restriction_id INT NOT NULL GENERATED BY DEFAULT AS IDENTITY,
    member_no VARCHAR(14) NOT NULL,
    restriction_type_code CHAR(1) NOT NULL,
    restriction_start TIMESTAMP NOT NULL,
    restriction_end TIMESTAMP NOT NULL,

    -- [설정] 예약제한 유형 이력에는 적용되지 않으므로 NULL 허용
    loan_suspension_status_code CHAR(1) NULL,

    PRIMARY KEY (restriction_id),

    -- 1. 회원 외래키 (회원 탈퇴 시 제한 기록 삭제: CASCADE)
    CONSTRAINT fk_restriction_member_no
        FOREIGN KEY (member_no) REFERENCES tbl_member_1 (member_no)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    -- 2. 제한유형 도메인 제약 (CHECK로 코드값 제한)
    CONSTRAINT chk_restriction_type
        CHECK (restriction_type_code IN ('L', 'R')),

    -- 3. 대출정지상태 도메인 제약 (CHECK로 코드값 제한, FK 대체, 제한유형이 대출정지(L)일 때만 값 존재)
    CONSTRAINT chk_restriction_loan_status
        CHECK (
            (restriction_type_code = 'L' AND loan_suspension_status_code IN ('S', 'P', 'D')) OR
            (restriction_type_code = 'R' AND loan_suspension_status_code IS NULL)
        )
);
COMMENT ON TABLE tbl_restriction_1 IS '회원의 대출정지/예약제한 통합 제한 이력 (대출정지, 예약제한, 대출정지상태 반정규화 통합)';
COMMENT ON COLUMN tbl_restriction_1.restriction_id IS '제한 이력 ID';
COMMENT ON COLUMN tbl_restriction_1.member_no IS '회원번호 (FK)';
COMMENT ON COLUMN tbl_restriction_1.restriction_type_code IS '제한 유형 코드 (L:대출정지, R:예약제한)';
COMMENT ON COLUMN tbl_restriction_1.restriction_start IS '제한 시작 날짜';
COMMENT ON COLUMN tbl_restriction_1.restriction_end IS '제한 종료 날짜';
COMMENT ON COLUMN tbl_restriction_1.loan_suspension_status_code IS '대출정지 상태 코드 (S:대출정지, P:연체료지불, D:대출정지해제, 반정규화, 예약제한 이력이면 NULL)';
