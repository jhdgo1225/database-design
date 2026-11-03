-- 이전 데이터 구조인 경우, 삭제하는 단계

DROP TABLE IF EXISTS tbl_loan_1;
DROP TABLE IF EXISTS tbl_reservation_1;
DROP TABLE IF EXISTS tbl_restriction_1;
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

-- 트리거/CHECK 제약이 의존하는 객체이므로 테이블을 모두 지운 뒤에 삭제
DROP SEQUENCE IF EXISTS seq_book_id;
DROP FUNCTION IF EXISTS fn_assign_book_no();
DROP FUNCTION IF EXISTS fn_sync_book_info();
DROP FUNCTION IF EXISTS fn_protect_book_key();
DROP FUNCTION IF EXISTS fn_isbn13_valid(TEXT);

-- 보유도서 테이블 (도서, 보유도서위치, 보유도서상태를 반정규화하여 흡수)
CREATE SEQUENCE seq_book_id;

-- EXCLUDE 제약에서 정수/문자열의 '<>' 연산자를 GiST 인덱스로 쓰기 위한 확장
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- 국내 ISBN-13 표기 규칙 검증 (접두부-국가번호-발행자번호-서명식별번호-체크기호)
--   접두부-국가번호는 978-89 또는 979-11, 숫자 13자리, 하이픈 4개, 체크기호(가중치 1,3 교대) 일치
--   발행자번호 자릿수는 번호 범위에 따라 결정 (00~24:2, 250~549:3, 5500~8499:4, 85000~94999:5, 950000~999999:6)
CREATE FUNCTION fn_isbn13_valid(isbn TEXT) RETURNS BOOLEAN AS $$
DECLARE
    digits TEXT;
    total INT := 0;
    pub_len INT;
BEGIN
    IF isbn !~ '^(978-89|979-11)-[0-9]{2,6}-[0-9]{1,5}-[0-9]$' THEN
        RETURN FALSE;
    END IF;

    digits := replace(isbn, '-', '');
    IF length(digits) <> 13 THEN
        RETURN FALSE;
    END IF;

    -- 국가번호 뒤 7자리(발행자번호 + 서명식별번호)의 앞자리로 발행자번호 자릿수를 정하고 하이픈 위치와 비교
    pub_len := CASE
        WHEN substr(digits, 6, 2)::INT <= 24 THEN 2
        WHEN substr(digits, 6, 3)::INT BETWEEN 250 AND 549 THEN 3
        WHEN substr(digits, 6, 4)::INT BETWEEN 5500 AND 8499 THEN 4
        WHEN substr(digits, 6, 5)::INT BETWEEN 85000 AND 94999 THEN 5
        ELSE 6
    END;
    IF length(split_part(isbn, '-', 3)) <> pub_len THEN
        RETURN FALSE;
    END IF;

    FOR i IN 1..12 LOOP
        total := total + substr(digits, i, 1)::INT * CASE WHEN i % 2 = 1 THEN 1 ELSE 3 END;
    END LOOP;

    RETURN (10 - total % 10) % 10 = substr(digits, 13, 1)::INT;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE TABLE tbl_book_held_1 (
    book_id INT NOT NULL,
    book_no INT NOT NULL,
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

    PRIMARY KEY (book_id, book_no),

    CONSTRAINT chk_book_id CHECK (book_id >= 1),
    CONSTRAINT chk_book_no CHECK (book_no >= 1),
    CONSTRAINT chk_book_isbn CHECK (fn_isbn13_valid(book_isbn)),

    -- 한 ISBN은 하나의 book_id에만 속함 (같은 book_id의 사본끼리는 같은 ISBN 허용)
    --   UNIQUE로는 사본 간 중복을 막아버리고 CHECK는 다른 행을 볼 수 없으므로 EXCLUDE 사용
    CONSTRAINT excl_book_isbn
        EXCLUDE USING gist (book_isbn WITH =, book_id WITH <>),

    -- 보유도서위치 도메인 제약 (CHECK로 코드값 제한, FK 대체)
    CONSTRAINT chk_held_loc
        CHECK (book_held_loc_code IN ('G', 'C', 'S')),

    -- 보유도서상태 도메인 제약 (CHECK로 코드값 제한, FK 대체)
    CONSTRAINT chk_held_status
        CHECK (book_held_status_code IN ('A', 'L', 'O', 'R', 'N', 'M', 'F', 'D'))
);
COMMENT ON TABLE tbl_book_held_1 IS '도서관에 등록된 도서의 실물 정보 (도서/위치/상태 반정규화 통합)';
COMMENT ON COLUMN tbl_book_held_1.book_id IS '원본 도서 ID (반정규화, FK 아님, 같은 책의 여러 사본을 묶는 식별자)';
COMMENT ON COLUMN tbl_book_held_1.book_no IS '해당 도서 N번째 사본';
COMMENT ON COLUMN tbl_book_held_1.book_title IS '도서 제목 (반정규화)';
COMMENT ON COLUMN tbl_book_held_1.book_author IS '도서 지은이, 옮긴이, 감수자 (반정규화)';
COMMENT ON COLUMN tbl_book_held_1.book_category_code IS '도서 카테고리를 의미하는 코드 (반정규화)';
COMMENT ON COLUMN tbl_book_held_1.book_isbn IS '도서 ISBN-13 (반정규화, 국내 표기: 978-89 또는 979-11 + 발행자번호 + 서명식별번호 + 체크기호, 하이픈 포함)';
COMMENT ON COLUMN tbl_book_held_1.book_publisher IS '도서를 발행한 출판사 (반정규화)';
COMMENT ON COLUMN tbl_book_held_1.book_pub_year IS '도서 발행년도 (반정규화)';
COMMENT ON COLUMN tbl_book_held_1.book_pages IS '도서 총 페이지 수 (반정규화)';
COMMENT ON COLUMN tbl_book_held_1.book_call_no IS '청구기호';
COMMENT ON COLUMN tbl_book_held_1.book_held_loc_code IS '보유도서 위치 코드 (G:종합자료실(2층), C:어린이실(-1층), S:보존서고(2층))';
COMMENT ON COLUMN tbl_book_held_1.book_held_status_code IS '보유도서 상태 코드 (A:대출가능, L:대출중, O:연체중, R:예약됨, N:예약불가, M:보수중, F:분실, D:폐기)';

-- 사본 등록 시 book_id/book_no 부여 및 서지 정보 정합성 유지
--   서지 컬럼(제목/저자/분류/ISBN/출판사/발행년도/페이지)은 같은 book_id의 모든 사본이 동일해야 함
--   (반정규화로 중복 저장되므로 DB 제약으로 표현할 수 없어 트리거로 보장)
CREATE FUNCTION fn_assign_book_no() RETURNS trigger AS $$
DECLARE
    base tbl_book_held_1%ROWTYPE;
BEGIN
    -- 새 도서면 book_id를 NULL로 넣고, 기존 도서의 사본 추가면 그 book_id를 넣음
    IF NEW.book_id IS NULL THEN
        NEW.book_id := nextval('seq_book_id');
    END IF;

    -- 같은 book_id에 대한 동시 INSERT/서지 수정을 직렬화 (트랜잭션 종료 시 자동 해제)
    PERFORM pg_advisory_xact_lock(NEW.book_id);

    -- 기존 사본이 있으면 첫 사본의 서지 정보를 기준으로 삼음
    --   생략(NULL)한 서지 컬럼은 복사하고, 다른 값을 직접 지정하면 거부
    SELECT * INTO base
    FROM tbl_book_held_1
    WHERE book_id = NEW.book_id
    ORDER BY book_no
    LIMIT 1;

    IF FOUND THEN
        NEW.book_title := COALESCE(NEW.book_title, base.book_title);
        NEW.book_author := COALESCE(NEW.book_author, base.book_author);
        NEW.book_category_code := COALESCE(NEW.book_category_code, base.book_category_code);
        NEW.book_isbn := COALESCE(NEW.book_isbn, base.book_isbn);
        NEW.book_publisher := COALESCE(NEW.book_publisher, base.book_publisher);
        NEW.book_pub_year := COALESCE(NEW.book_pub_year, base.book_pub_year);
        NEW.book_pages := COALESCE(NEW.book_pages, base.book_pages);

        IF ROW(NEW.book_title, NEW.book_author, NEW.book_category_code, NEW.book_isbn,
               NEW.book_publisher, NEW.book_pub_year, NEW.book_pages)
           IS DISTINCT FROM
           ROW(base.book_title, base.book_author, base.book_category_code, base.book_isbn,
               base.book_publisher, base.book_pub_year, base.book_pages)
        THEN
            RAISE EXCEPTION 'book_id=%의 서지 정보가 기존 사본과 다릅니다. 서지 컬럼은 생략하거나 기존 값과 같아야 합니다.', NEW.book_id
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    SELECT COALESCE(MAX(book_no), 0) + 1 INTO NEW.book_no
    FROM tbl_book_held_1
    WHERE book_id = NEW.book_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_assign_book_no
    BEFORE INSERT ON tbl_book_held_1
    FOR EACH ROW EXECUTE FUNCTION fn_assign_book_no();

-- 서지 컬럼이 수정되면 같은 book_id의 다른 사본에 전파
CREATE FUNCTION fn_sync_book_info() RETURNS trigger AS $$
BEGIN
    -- 전파 UPDATE가 다시 이 트리거를 호출하는 재귀를 차단
    IF pg_trigger_depth() > 1 THEN
        RETURN NULL;
    END IF;

    PERFORM pg_advisory_xact_lock(NEW.book_id);

    UPDATE tbl_book_held_1
    SET book_title = NEW.book_title,
        book_author = NEW.book_author,
        book_category_code = NEW.book_category_code,
        book_isbn = NEW.book_isbn,
        book_publisher = NEW.book_publisher,
        book_pub_year = NEW.book_pub_year,
        book_pages = NEW.book_pages
    WHERE book_id = NEW.book_id
      AND book_no <> NEW.book_no
      AND ROW(book_title, book_author, book_category_code, book_isbn,
              book_publisher, book_pub_year, book_pages)
          IS DISTINCT FROM
          ROW(NEW.book_title, NEW.book_author, NEW.book_category_code, NEW.book_isbn,
              NEW.book_publisher, NEW.book_pub_year, NEW.book_pages);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_book_info
    AFTER UPDATE OF book_title, book_author, book_category_code, book_isbn,
                    book_publisher, book_pub_year, book_pages
    ON tbl_book_held_1
    FOR EACH ROW
    WHEN (ROW(OLD.book_title, OLD.book_author, OLD.book_category_code, OLD.book_isbn,
              OLD.book_publisher, OLD.book_pub_year, OLD.book_pages)
          IS DISTINCT FROM
          ROW(NEW.book_title, NEW.book_author, NEW.book_category_code, NEW.book_isbn,
              NEW.book_publisher, NEW.book_pub_year, NEW.book_pages))
    EXECUTE FUNCTION fn_sync_book_info();

-- 사본 식별자(book_id, book_no) 수정 금지
--   book_id를 바꾸면 다른 도서의 사본이 되어 서지 정보가 어긋나고,
--   book_no를 바꾸면 "반입 순서"라는 의미와 기존 대출/예약 이력의 참조가 깨짐
CREATE FUNCTION fn_protect_book_key() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION '보유도서의 book_id, book_no는 수정할 수 없습니다. (book_id=%, book_no=%)', OLD.book_id, OLD.book_no
        USING ERRCODE = 'integrity_constraint_violation';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_protect_book_key
    BEFORE UPDATE OF book_id, book_no
    ON tbl_book_held_1
    FOR EACH ROW
    WHEN (OLD.book_id IS DISTINCT FROM NEW.book_id OR OLD.book_no IS DISTINCT FROM NEW.book_no)
    EXECUTE FUNCTION fn_protect_book_key();

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
    book_id INT NOT NULL,
    book_no INT NOT NULL,
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
    CONSTRAINT fk_loan_book_id
        FOREIGN KEY (book_id, book_no) REFERENCES tbl_book_held_1 (book_id, book_no)
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
COMMENT ON COLUMN tbl_loan_1.book_id IS '보유도서 ID (FK)';
COMMENT ON COLUMN tbl_loan_1.book_no IS '보유도서 N번째 사본 (FK)';
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
    book_id INT NOT NULL,
    book_no INT NOT NULL,
    member_no VARCHAR(14) NOT NULL,
    reservation_start TIMESTAMP NOT NULL,

    -- [설정] 예약 만료일이 아직 정해지지 않았거나 유효한 상태일 수 있으므로 NULL 허용
    reservation_end TIMESTAMP NULL,

    reservation_status_code CHAR(1) NOT NULL,

    PRIMARY KEY (reservation_id),

    -- 1. 보유도서 외래키 (책 정보 보호: RESTRICT)
    CONSTRAINT fk_reserv_book_id
        FOREIGN KEY (book_id, book_no) REFERENCES tbl_book_held_1 (book_id, book_no)
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
COMMENT ON COLUMN tbl_reservation_1.book_id IS '보유도서 ID (FK)';
COMMENT ON COLUMN tbl_reservation_1.book_no IS '보유도서의 N번째 사본 (FK)';
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
