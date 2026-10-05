-- =============================================================================
-- library 스키마 마이그레이션: library/postgresql/create_ddl.sql → library/postgresql_denormalized/create_ddl.sql
--
-- 전제조건: library/postgresql/create_ddl.sql + library/postgresql/insert_data.sql 이
--           이미 적용되어 기존 데이터가 들어있는 PostgreSQL 13+ 데이터베이스
-- 효과:     기존 9개 테이블(도서/보유도서위치/보유도서상태/회원등급/연체/연체상태/
--           예약상태/변상/대출정지/대출정지상태/예약제한)을 반정규화하여
--           tbl_book_held_1 / tbl_member_1 / tbl_loan_1 / tbl_reservation_1 /
--           tbl_restriction_1 5개 테이블로 재구성하고, 기존 데이터를 그대로 이전합니다.
--
-- 전략:     1) 신규 구조(_new 접미사)로 테이블을 새로 만들고 JOIN으로 데이터를 채운 뒤
--           2) 기존 테이블을 모두 삭제하고 3) _new 테이블을 최종 이름으로 교체합니다.
--           (ALTER TABLE로 컬럼을 하나씩 변환하기엔 PK 타입 변경(VARCHAR→UUID)과
--            여러 테이블의 흡수/통합이 섞여 있어 재생성 방식이 더 명확하고 검증하기 쉽습니다.)
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. 데이터 정합성 사전 점검: 새 설계는 변상/연체 이력이 반드시 기존 대출 건
--    (book_held_id, member_no 조합)에 붙어야 하는데, 현재 샘플 데이터 중
--    tbl_reimbursement_1 1건(book_held_id='EML000252100', member_no='11101001000007')은
--    tbl_loan_1에 매칭되는 대출 건이 없는 고아(orphan) 데이터입니다.
--    이런 행은 tbl_loan_1으로 옮겨질 수 없으므로 실패시키지 않고 경고만 남깁니다.
--    (운영 데이터라면 마이그레이션 전에 반드시 원인을 확인하세요.)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    orphan_reimbursement INT;
    orphan_overdue INT;
BEGIN
    SELECT COUNT(*) INTO orphan_reimbursement
    FROM tbl_reimbursement_1 r
    WHERE NOT EXISTS (
        SELECT 1 FROM tbl_loan_1 l
        WHERE l.book_held_id = r.book_held_id AND l.member_no = r.member_no
    );

    SELECT COUNT(*) INTO orphan_overdue
    FROM tbl_overdue_1 o
    WHERE NOT EXISTS (
        SELECT 1 FROM tbl_loan_1 l
        WHERE l.book_held_id = o.book_held_id AND l.member_no = o.member_no
    );

    IF orphan_reimbursement > 0 THEN
        RAISE WARNING '매칭되는 대출 건이 없는 변상(tbl_reimbursement_1) 기록 %건은 마이그레이션에서 제외됩니다.', orphan_reimbursement;
    END IF;

    IF orphan_overdue > 0 THEN
        RAISE WARNING '매칭되는 대출 건이 없는 연체(tbl_overdue_1) 기록 %건은 마이그레이션에서 제외됩니다.', orphan_overdue;
    END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 1. 보유도서 테이블 재구성
--    (도서 + 보유도서위치 + 보유도서상태 반정규화 흡수, PK를 VARCHAR(12) → UUID로 변경)
-- -----------------------------------------------------------------------------
CREATE TABLE tbl_book_held_1_new (
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

    -- 마이그레이션 전용 보조 컬럼: 기존 FK(book_held_id 문자열)를 새 UUID로 매핑하기 위함.
    -- 최종 구조에는 존재하지 않으며, 작업 마지막 단계에서 제거됩니다.
    old_book_held_id VARCHAR(12) NOT NULL,

    PRIMARY KEY (book_held_id),
    CONSTRAINT chk_held_loc_new
        CHECK (book_held_loc_code IN ('G', 'C', 'S')),
    CONSTRAINT chk_held_status_new
        CHECK (book_held_status_code IN ('A', 'L', 'O', 'R', 'N', 'M', 'F', 'D'))
);

INSERT INTO tbl_book_held_1_new (
    book_id, book_title, book_author, book_category_code, book_isbn, book_publisher, book_pub_year, book_pages,
    book_call_no, book_held_loc_code, book_held_status_code, old_book_held_id
)
SELECT
    b.book_id, b.book_title, b.book_author, b.book_category_code, b.book_isbn, b.book_publisher, b.book_pub_year, b.book_pages,
    bh.book_call_no,
    CASE loc.book_held_loc_name
        WHEN '종합자료실' THEN 'G'
        WHEN '어린이실'   THEN 'C'
        WHEN '보존서고'   THEN 'S'
    END,
    CASE st.book_held_status_name
        WHEN '대출가능' THEN 'A'
        WHEN '대출중'   THEN 'L'
        WHEN '연체중'   THEN 'O'
        WHEN '예약됨'   THEN 'R'
        WHEN '예약불가' THEN 'N'
        WHEN '보수중'   THEN 'M'
        WHEN '분실'     THEN 'F'
        WHEN '폐기'     THEN 'D'
    END,
    bh.book_held_id
FROM tbl_book_held_1 bh
JOIN tbl_book_1 b ON b.book_id = bh.book_id
JOIN tbl_book_held_loc_1 loc ON loc.book_held_loc_id = bh.book_held_loc_id
JOIN tbl_book_held_status_1 st ON st.book_held_status_id = bh.book_held_status_id;

-- -----------------------------------------------------------------------------
-- 2. 회원 테이블 재구성
--    (회원등급 반정규화 흡수 + 대출정지/예약제한 "현재 상태" 반정규화 포함)
--    대출정지/예약제한 이력이 여러 건인 회원은 시작일이 가장 최근인 1건을 현재 상태로 채택합니다.
-- -----------------------------------------------------------------------------
CREATE TABLE tbl_member_1_new (
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
    member_grade_code CHAR(1) NOT NULL DEFAULT 'N',
    member_loan_day INT NOT NULL DEFAULT 14,
    member_loan_suspension_status_code CHAR(1) NULL,
    member_loan_suspension_start TIMESTAMP NULL,
    member_loan_suspension_end TIMESTAMP NULL,
    member_reservation_suspension_start TIMESTAMP NULL,
    member_reservation_suspension_end TIMESTAMP NULL,

    PRIMARY KEY (member_no),
    CONSTRAINT chk_member_grade_new
        CHECK (
            (member_grade_code = 'N' AND member_loan_day = 14) OR
            (member_grade_code = 'V' AND member_loan_day = 21)
        ),
    CONSTRAINT chk_member_loan_suspension_status_new
        CHECK (member_loan_suspension_status_code IS NULL OR member_loan_suspension_status_code IN ('S', 'P', 'D'))
);

WITH latest_loan_suspension AS (
    SELECT DISTINCT ON (ls.member_no)
        ls.member_no,
        lss.loan_suspension_status_name AS status_code,
        ls.loan_suspension_start,
        ls.loan_suspension_end
    FROM tbl_loan_suspension_1 ls
    JOIN tbl_loan_suspension_status_1 lss ON lss.loan_suspension_status_id = ls.loan_suspension_status_id
    ORDER BY ls.member_no, ls.loan_suspension_start DESC
),
latest_reservation_suspension AS (
    SELECT DISTINCT ON (rs.member_no)
        rs.member_no,
        rs.reservation_suspension_start,
        rs.reservation_suspension_end
    FROM tbl_reservation_suspension_1 rs
    ORDER BY rs.member_no, rs.reservation_suspension_start DESC
)
INSERT INTO tbl_member_1_new (
    member_no, member_id, member_passwd, member_loan_passwd, member_name, member_age, member_birth, member_phone,
    member_addr, member_email, member_grade_code, member_loan_day,
    member_loan_suspension_status_code, member_loan_suspension_start, member_loan_suspension_end,
    member_reservation_suspension_start, member_reservation_suspension_end
)
SELECT
    m.member_no, m.member_id, m.member_passwd, m.member_loan_passwd, m.member_name, m.member_age, m.member_birth, m.member_phone,
    m.member_addr, m.member_email,
    CASE g.member_grade_name WHEN '일반' THEN 'N' WHEN 'VIP' THEN 'V' END,
    g.member_loan_day,
    lls.status_code, lls.loan_suspension_start, lls.loan_suspension_end,
    lrs.reservation_suspension_start, lrs.reservation_suspension_end
FROM tbl_member_1 m
JOIN tbl_member_grade_1 g ON g.member_grade_id = m.member_grade_id
LEFT JOIN latest_loan_suspension lls ON lls.member_no = m.member_no
LEFT JOIN latest_reservation_suspension lrs ON lrs.member_no = m.member_no;

-- -----------------------------------------------------------------------------
-- 3. 대출 테이블 재구성
--    (연체/변상 이력을 반정규화하여 흡수, book_held_id를 새 UUID로 교체)
--    연체·변상 테이블에는 loan_id가 없어 (book_held_id, member_no) 조합으로 매칭합니다.
--    현재 데이터에서는 이 조합이 대출 건마다 유일하여 안전하지만, 동일 회원이 같은
--    보유도서를 재대출하는 케이스가 생기면 loan_id 기반 매칭으로 바꿔야 합니다.
-- -----------------------------------------------------------------------------
CREATE TABLE tbl_loan_1_new (
    loan_id INT NOT NULL GENERATED BY DEFAULT AS IDENTITY,
    book_held_id UUID NOT NULL,
    member_no VARCHAR(14) NOT NULL,
    loan_date TIMESTAMP NOT NULL,
    return_due_date TIMESTAMP NOT NULL,
    actual_return_date TIMESTAMP NULL,
    extension_status CHAR(1) NOT NULL,
    overdue_start TIMESTAMP NULL,
    overdue_end TIMESTAMP NULL,
    overdue_status_code CHAR(1) NULL,
    reimbursement_date TIMESTAMP NULL,
    reimbursement_status CHAR(1) NULL,

    PRIMARY KEY (loan_id),
    CONSTRAINT fk_loan_book_held_id_new
        FOREIGN KEY (book_held_id) REFERENCES tbl_book_held_1_new (book_held_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    CONSTRAINT fk_loan_member_no_new
        FOREIGN KEY (member_no) REFERENCES tbl_member_1_new (member_no)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    CONSTRAINT chk_loan_overdue_status_new
        CHECK (overdue_status_code IS NULL OR overdue_status_code IN ('O', 'R', 'D')),
    CONSTRAINT chk_loan_reimbursement_status_new
        CHECK (reimbursement_status IS NULL OR reimbursement_status IN ('Y', 'N'))
);

INSERT INTO tbl_loan_1_new (
    loan_id, book_held_id, member_no, loan_date, return_due_date, actual_return_date, extension_status,
    overdue_start, overdue_end, overdue_status_code, reimbursement_date, reimbursement_status
)
SELECT
    l.loan_id, bh.book_held_id, l.member_no, l.loan_date, l.return_due_date, l.actual_return_date, l.extension_status,
    ov.overdue_start, ov.overdue_end, os.overdue_status_name,
    rb.reimbursement_date, rb.reimbursement_status
FROM tbl_loan_1 l
JOIN tbl_book_held_1_new bh ON bh.old_book_held_id = l.book_held_id
LEFT JOIN tbl_overdue_1 ov ON ov.book_held_id = l.book_held_id AND ov.member_no = l.member_no
LEFT JOIN tbl_overdue_status_1 os ON os.overdue_status_id = ov.overdue_status_id
LEFT JOIN tbl_reimbursement_1 rb ON rb.book_held_id = l.book_held_id AND rb.member_no = l.member_no;

-- identity 시퀀스를 명시적으로 넣은 loan_id 최댓값 이후로 맞춤 (다음 INSERT부터 자동 채번되도록)
SELECT setval(
    pg_get_serial_sequence('tbl_loan_1_new', 'loan_id'),
    (SELECT COALESCE(MAX(loan_id), 0) FROM tbl_loan_1_new) + 1,
    false
);

-- -----------------------------------------------------------------------------
-- 4. 예약 테이블 재구성 (예약상태 반정규화 흡수, book_held_id를 새 UUID로 교체)
-- -----------------------------------------------------------------------------
CREATE TABLE tbl_reservation_1_new (
    reservation_id INT NOT NULL GENERATED BY DEFAULT AS IDENTITY,
    book_held_id UUID NOT NULL,
    member_no VARCHAR(14) NOT NULL,
    reservation_start TIMESTAMP NOT NULL,
    reservation_end TIMESTAMP NULL,
    reservation_status_code CHAR(1) NOT NULL,

    PRIMARY KEY (reservation_id),
    CONSTRAINT fk_reserv_book_held_id_new
        FOREIGN KEY (book_held_id) REFERENCES tbl_book_held_1_new (book_held_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    CONSTRAINT fk_reserv_member_no_new
        FOREIGN KEY (member_no) REFERENCES tbl_member_1_new (member_no)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    CONSTRAINT chk_reserv_status_new
        CHECK (reservation_status_code IN ('W', 'A', 'E', 'C'))
);

INSERT INTO tbl_reservation_1_new (
    reservation_id, book_held_id, member_no, reservation_start, reservation_end, reservation_status_code
)
SELECT
    r.reservation_id, bh.book_held_id, r.member_no, r.reservation_start, r.reservation_end, rs.reservation_status_name
FROM tbl_reservation_1 r
JOIN tbl_book_held_1_new bh ON bh.old_book_held_id = r.book_held_id
JOIN tbl_reservation_status_1 rs ON rs.reservation_status_id = r.reservation_status_id;

SELECT setval(
    pg_get_serial_sequence('tbl_reservation_1_new', 'reservation_id'),
    (SELECT COALESCE(MAX(reservation_id), 0) FROM tbl_reservation_1_new) + 1,
    false
);

-- -----------------------------------------------------------------------------
-- 5. 제한이력 테이블 신설 (대출정지 테이블 + 예약제한 테이블 통합, 대출정지상태 반정규화 흡수)
-- -----------------------------------------------------------------------------
CREATE TABLE tbl_restriction_1 (
    restriction_id INT NOT NULL GENERATED BY DEFAULT AS IDENTITY,
    member_no VARCHAR(14) NOT NULL,
    restriction_type_code CHAR(1) NOT NULL,
    restriction_start TIMESTAMP NOT NULL,
    restriction_end TIMESTAMP NOT NULL,
    loan_suspension_status_code CHAR(1) NULL,

    PRIMARY KEY (restriction_id),
    CONSTRAINT fk_restriction_member_no
        FOREIGN KEY (member_no) REFERENCES tbl_member_1_new (member_no)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    CONSTRAINT chk_restriction_type
        CHECK (restriction_type_code IN ('L', 'R')),
    CONSTRAINT chk_restriction_loan_status
        CHECK (
            (restriction_type_code = 'L' AND loan_suspension_status_code IN ('S', 'P', 'D')) OR
            (restriction_type_code = 'R' AND loan_suspension_status_code IS NULL)
        )
);

INSERT INTO tbl_restriction_1 (member_no, restriction_type_code, restriction_start, restriction_end, loan_suspension_status_code)
SELECT ls.member_no, 'L', ls.loan_suspension_start, ls.loan_suspension_end, lss.loan_suspension_status_name
FROM tbl_loan_suspension_1 ls
JOIN tbl_loan_suspension_status_1 lss ON lss.loan_suspension_status_id = ls.loan_suspension_status_id
UNION ALL
SELECT rs.member_no, 'R', rs.reservation_suspension_start, rs.reservation_suspension_end, NULL
FROM tbl_reservation_suspension_1 rs;

-- -----------------------------------------------------------------------------
-- 6. 기존 테이블 삭제 (FK 의존관계 역순)
-- -----------------------------------------------------------------------------
DROP TABLE tbl_reimbursement_1;
DROP TABLE tbl_overdue_1;
DROP TABLE tbl_overdue_status_1;
DROP TABLE tbl_reservation_1;
DROP TABLE tbl_reservation_status_1;
DROP TABLE tbl_loan_1;
DROP TABLE tbl_loan_suspension_1;
DROP TABLE tbl_loan_suspension_status_1;
DROP TABLE tbl_reservation_suspension_1;
DROP TABLE tbl_book_held_1;
DROP TABLE tbl_book_1;
DROP TABLE tbl_book_held_loc_1;
DROP TABLE tbl_book_held_status_1;
DROP TABLE tbl_member_1;
DROP TABLE tbl_member_grade_1;

-- -----------------------------------------------------------------------------
-- 7. 신규 테이블을 최종 이름/제약조건 이름으로 정리
-- -----------------------------------------------------------------------------
ALTER TABLE tbl_book_held_1_new DROP COLUMN old_book_held_id;
ALTER TABLE tbl_book_held_1_new RENAME TO tbl_book_held_1;
ALTER TABLE tbl_member_1_new RENAME TO tbl_member_1;
ALTER TABLE tbl_loan_1_new RENAME TO tbl_loan_1;
ALTER TABLE tbl_reservation_1_new RENAME TO tbl_reservation_1;

ALTER TABLE tbl_book_held_1 RENAME CONSTRAINT tbl_book_held_1_new_pkey TO tbl_book_held_1_pkey;
ALTER TABLE tbl_book_held_1 RENAME CONSTRAINT chk_held_loc_new TO chk_held_loc;
ALTER TABLE tbl_book_held_1 RENAME CONSTRAINT chk_held_status_new TO chk_held_status;

ALTER TABLE tbl_member_1 RENAME CONSTRAINT tbl_member_1_new_pkey TO tbl_member_1_pkey;
ALTER TABLE tbl_member_1 RENAME CONSTRAINT chk_member_grade_new TO chk_member_grade;
ALTER TABLE tbl_member_1 RENAME CONSTRAINT chk_member_loan_suspension_status_new TO chk_member_loan_suspension_status;

ALTER TABLE tbl_loan_1 RENAME CONSTRAINT tbl_loan_1_new_pkey TO tbl_loan_1_pkey;
ALTER TABLE tbl_loan_1 RENAME CONSTRAINT fk_loan_book_held_id_new TO fk_loan_book_held_id;
ALTER TABLE tbl_loan_1 RENAME CONSTRAINT fk_loan_member_no_new TO fk_loan_member_no;
ALTER TABLE tbl_loan_1 RENAME CONSTRAINT chk_loan_overdue_status_new TO chk_loan_overdue_status;
ALTER TABLE tbl_loan_1 RENAME CONSTRAINT chk_loan_reimbursement_status_new TO chk_loan_reimbursement_status;

ALTER TABLE tbl_reservation_1 RENAME CONSTRAINT tbl_reservation_1_new_pkey TO tbl_reservation_1_pkey;
ALTER TABLE tbl_reservation_1 RENAME CONSTRAINT fk_reserv_book_held_id_new TO fk_reserv_book_held_id;
ALTER TABLE tbl_reservation_1 RENAME CONSTRAINT fk_reserv_member_no_new TO fk_reserv_member_no;
ALTER TABLE tbl_reservation_1 RENAME CONSTRAINT chk_reserv_status_new TO chk_reserv_status;

-- -----------------------------------------------------------------------------
-- 8. 테이블/컬럼 COMMENT 재적용 (library/postgresql_denormalized/create_ddl.sql과 동일)
-- -----------------------------------------------------------------------------
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

COMMENT ON TABLE tbl_reservation_1 IS '회원의 도서 예약 이력 (예약상태 반정규화 통합)';
COMMENT ON COLUMN tbl_reservation_1.reservation_id IS '예약 기록 ID';
COMMENT ON COLUMN tbl_reservation_1.book_held_id IS '보유도서 ID (FK)';
COMMENT ON COLUMN tbl_reservation_1.member_no IS '회원번호 (FK)';
COMMENT ON COLUMN tbl_reservation_1.reservation_start IS '도서 예약 신청 날짜';
COMMENT ON COLUMN tbl_reservation_1.reservation_end IS '도서 예약 신청 만기 날짜 (NULL 허용)';
COMMENT ON COLUMN tbl_reservation_1.reservation_status_code IS '예약 상태 코드 (W:대기, A:가능, E:만료, C:취소, 반정규화)';

COMMENT ON TABLE tbl_restriction_1 IS '회원의 대출정지/예약제한 통합 제한 이력 (대출정지, 예약제한, 대출정지상태 반정규화 통합)';
COMMENT ON COLUMN tbl_restriction_1.restriction_id IS '제한 이력 ID';
COMMENT ON COLUMN tbl_restriction_1.member_no IS '회원번호 (FK)';
COMMENT ON COLUMN tbl_restriction_1.restriction_type_code IS '제한 유형 코드 (L:대출정지, R:예약제한)';
COMMENT ON COLUMN tbl_restriction_1.restriction_start IS '제한 시작 날짜';
COMMENT ON COLUMN tbl_restriction_1.restriction_end IS '제한 종료 날짜';
COMMENT ON COLUMN tbl_restriction_1.loan_suspension_status_code IS '대출정지 상태 코드 (S:대출정지, P:연체료지불, D:대출정지해제, 반정규화, 예약제한 이력이면 NULL)';

COMMIT;

-- =============================================================================
-- 9. 검증 쿼리 (COMMIT 이후 수동 실행 권장)
-- =============================================================================
-- SELECT COUNT(*) FROM tbl_book_held_1;   -- 기존 tbl_book_held_1 행수(17)와 일치해야 함
-- SELECT COUNT(*) FROM tbl_member_1;      -- 기존 15와 일치해야 함
-- SELECT COUNT(*) FROM tbl_loan_1;        -- 기존 21과 일치해야 함
-- SELECT COUNT(*) FROM tbl_reservation_1; -- 기존 13과 일치해야 함
-- SELECT COUNT(*) FROM tbl_restriction_1; -- 기존 loan_suspension(10) + reservation_suspension(4) = 14와 일치해야 함
-- SELECT COUNT(*) FROM tbl_loan_1 WHERE overdue_status_code IS NOT NULL;     -- 14 (orphan 없음, 전수 매칭)
-- SELECT COUNT(*) FROM tbl_loan_1 WHERE reimbursement_status IS NOT NULL;   -- 2 (orphan 1건 제외)
