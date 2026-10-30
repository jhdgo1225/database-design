/*
업데이트01 (2026-10-30 금요일)
기준: 최근 commit(831cf18)의 정규화 버전 school/postgresql/postgresql_create_ddl.sql 대비 변경점
      (commit 당시 경로는 school/postgresql_create_ddl.sql, 내용 동일). 테이블 이름의 접미사 1 → 2 는 반정규화 버전을 뜻한다.
테이블 8개 → 5개, 신규 객체: 트리거 함수 1개(fn_subj_freeze), 트리거 1개(trg_subj_freeze)

- tbl_dept_m1 → tbl_dept_m2 : 학과 신설 일자(created_at), 종료 일자(suspended_at) 추가
- tbl_stud_m1 + tbl_prof_m1 → tbl_pers_m2 : 학생·교수를 구성원 테이블 하나로 통합
    · 구성원 유형(person_type), 입교 경로(entry_type) 추가, 재적 상태(status) 확장, 값 범위·유형별 CHECK 추가
- tbl_subj_m1 + tbl_offe_d1 → tbl_subj_d2 : 과목·개설과목을 하나로 통합
    · 기본키 offe_id, 과목 정보는 개설 행마다 복사(스냅샷), 수강신청이 있는 개설은 트리거로 과목 정보 수정 차단
- tbl_room_l1 제거 : 강의실 정보를 tbl_sche_d2.room_code 로 흡수
- tbl_sche_d1 → tbl_sche_d2 : room_id(FK) → room_code(FK 없음), 개설과목과 식별 관계 (sche_id 제거)
- tbl_enrl_t1 → tbl_enrl_t2 : 시간표(sche_id) 대신 개설과목(offe_id)을 참조, enrl_id 대신 (offe_id, enrlno) 복합 식별자, 학생 복합 FK
각 변경의 상세 내용은 해당 테이블 바로 위의 주석을 참고한다.
*/

/*
[업데이트01] tbl_dept_m1 → tbl_dept_m2
- 학과 신설 일자(created_at) 추가 (NOT NULL)
- 학과 종료 일자(suspended_at) 추가 (NOT NULL)
*/
CREATE TABLE tbl_dept_m2 (
  dept_id		CHAR(3)		NOT NULL,			 	-- 학부 코드 번호(1자리) + 학부 소속 학과 번호(2자리)
  name   		CHAR(32)	NOT NULL,  				-- 학과 이름
  created_at	DATE		NOT NULL,				-- 학과 신설 일자
  suspended_at	DATE		NOT NULL,				-- 학과 종료 일자
  PRIMARY KEY (dept_id)
);

/*
[업데이트01] tbl_stud_m1 + tbl_prof_m1 → tbl_pers_m2 (학생·교수 통합)
- stud_id CHAR(10) / prof_id CHAR(9) → person_id VARCHAR(10) (학생 10자리, 교수 9자리 유지. ck_pers_kind 가 유형별 길이를 검사)
- 구성원 유형(person_type) 추가: 'S' 학생, 'P' 교수
- 입교 경로(entry_type) 추가: 'N' 신입학/신규임용, 'T' 편입학/전입
- 재적 상태(status) 확장: 기존 학생 'E'(재학)/'G'(졸업) → 'A' 재학·재직, 'L' 휴학·휴직, 'D' 중퇴·사직, 'G' 졸업·퇴직
  (기존 데이터 이전 시 'E' 는 'A' 로 변환. NULL 허용 → NOT NULL DEFAULT 'A')
- 학생 전용 grade, 교수 전용 rank 를 NULL 허용으로 변경하고 유형에 따라 한쪽만 채우도록 CHECK 추가
- 개설과목·수강신청이 학생/교수를 정확히 구분해 참조하도록 UNIQUE (person_id, person_type) 추가
- sex, entry_type, status, rank 값 범위 CHECK 추가
*/
CREATE TABLE tbl_pers_m2 (
  person_id   VARCHAR(10)  NOT NULL PRIMARY KEY                    -- (학생) 입학년도(4) + 소속학과(3) + 등록순서(3) = 10자리, (교수) 임용년도(4) + 소속학과(3) + 등록순서(2) = 9자리
, person_type CHAR(1)      NOT NULL                                -- 상위 구분. 'S': 학생(Student), 'P': 교수(Professor)
, passwd      CHAR(64)     NOT NULL                                -- 대/소문자·숫자·특수문자 각 1자 이상, 12~20자리 SHA-256 해시
, name        VARCHAR(4)   NOT NULL                                -- 한국 이름
, birth       DATE         NOT NULL                                -- 생년월일
, sex         CHAR(1)      NOT NULL                                -- 'M': Male, 'F': Female
, dept_id     CHAR(3)      NOT NULL REFERENCES tbl_dept_m2(dept_id) -- 소속학과 ID
                           ON UPDATE CASCADE ON DELETE RESTRICT
, addr        VARCHAR(128) NOT NULL                                -- 도로명주소
, zipcode     CHAR(5)      NOT NULL                                -- 우정사업본부 표준
, phone       CHAR(11)     NOT NULL                                -- '01000000000' 형식
, email       VARCHAR(64)  NOT NULL                                -- 이메일
, entry_type  CHAR(1)      NOT NULL DEFAULT 'N'                    -- 입교 경로. 'N': 처음 들어옴 (학생=신입학, 교수=신규임용), 'T': 타 학교에서 옮겨옴 (학생=편입학, 교수=전입)
, status      CHAR(1)      NOT NULL DEFAULT 'A'                    -- 재적 상태. 'A': 재학/재직, 'L': 휴학/휴직, 'D': 중퇴/사직, 'G': 졸업/퇴직(정년·임기만료)
, grade       INT          NULL                                    -- (학생 전용) 1,2,3,4학년
, rank        CHAR(1)      NULL                                    -- (교수 전용) 'P': 정교수, 'S': 부교수, 'L': 조교수, 'T': 시간강사

  -- 다른 테이블이 (person_id, person_type) 쌍으로 참조할 수 있도록 하는 FK 대상
, CONSTRAINT uq_pers_id_type UNIQUE (person_id, person_type)
, CONSTRAINT ck_pers_type  CHECK (person_type IN ('S', 'P'))
, CONSTRAINT ck_pers_sex   CHECK (sex IN ('M', 'F'))
, CONSTRAINT ck_pers_entry CHECK (entry_type IN ('N', 'T'))
, CONSTRAINT ck_pers_stat  CHECK (status IN ('A', 'L', 'D', 'G'))
, CONSTRAINT ck_pers_rank  CHECK (rank IN ('P', 'S', 'L', 'T'))
  -- 학생은 grade만, 교수는 rank만 채우고 ID 길이도 유형에 맞아야 한다.
, CONSTRAINT ck_pers_kind  CHECK (
       (person_type = 'S' AND grade BETWEEN 1 AND 4 AND rank IS NULL     AND LENGTH(person_id) = 10)
    OR (person_type = 'P' AND grade IS NULL         AND rank IS NOT NULL AND LENGTH(person_id) = 9)
  )
);

/*
[업데이트01] tbl_subj_m1 + tbl_offe_d1 → tbl_subj_d2 (과목·개설과목 통합)
- 과목 정보(name, description, course, score)가 개설 행마다 복사된다. 기본키는 offe_id 단독
- offe_id = 학기(6) + 과목코드(5) + 등록번호(2). semester, subj_id 는 offe_id 에서 파생되는 값이므로
  ck_subj_semester, ck_subj_code 로 offe_id 와 일치하는지 검사
- 개설 행의 과목 정보는 '그 학기 시점의 값'(스냅샷)으로 정의한다. 개설할 때 직전 학기 값을 복사해 시작하고,
  수강신청이 하나라도 생기면 trg_subj_freeze 트리거(파일 맨 아래)가 과목 정보 수정을 막는다.
- 기존 tbl_subj_m1 의 기본키였던 subj_id 는 학기마다 반복되므로 더 이상 유일하지 않은 일반 컬럼이 된다.
- 개설과목의 subj_id → tbl_subj_m1 FK 는 테이블이 합쳐져 제거
- 교수 참조는 prof_id CHAR(9) 단일 FK 대신 (prof_id VARCHAR(10), prof_type) 복합 FK 로 변경하여 교수만 지정 가능
*/
CREATE TABLE tbl_subj_d2 (
  subj_id     CHAR(5)    NOT NULL,  								-- 과목코드. 학과ID(3자리) + 등록순서(2자리)
  offe_id 	CHAR(13) NOT NULL,                            			-- 학기(6자리) + 과목코드(5자리) + 등록번호(2자리)
  semester    CHAR(6)  NOT NULL,                                    -- 과목이 개설된 학기 (YYYY학기 ex: 202501)
  name        VARCHAR(64) NOT NULL,             					-- 과목명
  description VARCHAR(256) NOT NULL,            					-- 과목 설명
  course      CHAR(2)    NOT NULL,              					-- 이수구분 (MR/ME/GR/GE)
  score       REAL       NOT NULL               					-- 과목 학점 (전공:3, 교양:2)
, prof_id VARCHAR(10) NOT NULL                                      -- 교수 ID
, prof_type CHAR(1) NOT NULL DEFAULT 'P' CHECK (prof_type = 'P')    -- 구성원 유형 (교수 'P'로 고정, 복합 FK용)
, dept_id CHAR(3)  NOT NULL REFERENCES tbl_dept_m2(dept_id)         -- 대상학과 ID
                      ON UPDATE CASCADE ON DELETE RESTRICT
, grade   INT      NOT NULL                                         -- 개설과목 대상 학년 (1~4)
, FOREIGN KEY (prof_id, prof_type) REFERENCES tbl_pers_m2(person_id, person_type)
                      ON UPDATE CASCADE ON DELETE RESTRICT,
  PRIMARY KEY (offe_id),
  CONSTRAINT ck_subj_semester CHECK (SUBSTRING(offe_id FROM 1 FOR 6) = semester),
  CONSTRAINT ck_subj_code     CHECK (SUBSTRING(offe_id FROM 7 FOR 5) = subj_id)
);

/*
[업데이트01] tbl_sche_d1 → tbl_sche_d2, tbl_room_l1 제거
- 강의실 테이블(tbl_room_l1)을 없애고 강의실 코드를 시간표에 직접 저장
- room_id(FK) → room_code(FK 없음). 호관(building)·호실(roomno)은 room_code 에서 파생
- 개설과목과의 관계를 비식별 → 식별 관계로 변경: 부모 키 offe_id 가 기본키에 포함된다.
  기본키가 (offe_id, weekday, period)가 되므로 파생 코드였던 sche_id 는 제거
- offe_id 단독으로 개설과목이 정해지므로(subj_id 는 offe_id 에 포함) FK 는 offe_id 하나만 참조
*/
CREATE TABLE tbl_sche_d2 (
  offe_id CHAR(13) NOT NULL                                             -- 개설과목 ID
, weekday INT         NOT NULL                                          -- 강의 진행 요일 (0=일, 1=월, …, 6=토)
, period  INT         NOT NULL                                          -- 강의를 하는 교시 (1~10)
, room_code VARCHAR(6)     NOT NULL                                          -- 강의실 ID
, PRIMARY KEY (offe_id, weekday, period)
, FOREIGN KEY (offe_id) REFERENCES tbl_subj_d2(offe_id)
    ON UPDATE CASCADE ON DELETE RESTRICT
);


/*
[업데이트01] tbl_enrl_t1 → tbl_enrl_t2
- 수강신청이 시간표(sche_id) 대신 개설과목(offe_id)을 직접 참조
- stud_id → (stud_id, stud_type) 복합 FK 로 변경하여 학생만 지정 가능
- tbl_sche_d2 는 더 이상 수강신청이 참조하지 않는다. 시간 충돌 검사는 offe_id 로 tbl_sche_d2 와 조인한다.
- enrl_id CHAR(18) (시간표ID(16) + 신청순서(2)) 제거: sche_id 가 없어져 정의가 성립하지 않는다.
  대신 개설과목과 식별 관계로, 부모 키 offe_id 와 신청 순번 enrlno 를 묶은 복합 기본키 (offe_id, enrlno)를 쓴다.
  신청 순번이 2자리(최대 99명)로 제한되던 것도 INT 로 풀린다.
- 한 학생이 같은 개설을 순번만 바꿔 중복 신청하지 못하도록 UNIQUE (offe_id, stud_id) 추가
- 기본키와 uq_enrl_stud 의 인덱스는 모두 선두 컬럼이 offe_id 이므로 offe_id 검색(조인, FK 검사, trg_subj_freeze 의 수강신청 존재 검사)에
  별도 인덱스가 필요 없다. (PostgreSQL 은 FK 만으로는 자식 쪽 인덱스를 만들지 않으므로 이 점이 중요하다.)
*/
CREATE TABLE tbl_enrl_t2 (
  offe_id CHAR(13) NOT NULL
    -- 개설과목 ID. 학기(6자리) + 과목코드(5자리) + 등록번호(2자리)
, enrlno INT NOT NULL CHECK (enrlno > 0)
    -- 신청 순번. 개설과목 안에서 1부터 매기는 신청 순서
, stud_id VARCHAR(10) NOT NULL
    -- 학생 ID
, stud_type CHAR(1) NOT NULL DEFAULT 'S' CHECK (stud_type = 'S')
    -- 구성원 유형 (학생 'S'로 고정, 복합 FK용)
, grade VARCHAR(2) NULL
, ygrade INT NULL
    -- 신청 학년
, FOREIGN KEY (stud_id, stud_type) REFERENCES tbl_pers_m2(person_id, person_type)
    ON UPDATE CASCADE ON DELETE RESTRICT
, PRIMARY KEY (offe_id, enrlno)
, FOREIGN KEY (offe_id) REFERENCES tbl_subj_d2(offe_id)
    ON UPDATE CASCADE ON DELETE RESTRICT
, CONSTRAINT uq_enrl_stud UNIQUE (offe_id, stud_id)
);

/*
[업데이트01] tbl_subj_d2 스냅샷 잠금 트리거
- 개설 행의 과목 정보(subj_id, semester, name, description, course, score)는 그 학기 시점의 값이다.
- 해당 개설에 수강신청이 하나라도 있으면 위 컬럼의 수정을 막는다. (INSERT 와 그 밖의 컬럼 수정은 영향 없음)
- 수강신청이 없는 개설(개설 직후)은 자유롭게 수정할 수 있다.
- 과거 행의 오타를 고쳐야 한다면 ALTER TABLE tbl_subj_d2 DISABLE TRIGGER trg_subj_freeze; 로 잠시 끈 뒤 되살린다.
- 수강신청 존재 검사는 tbl_enrl_t2 의 offe_id 선두 인덱스(기본키 또는 uq_enrl_stud)를 사용한다.
*/
CREATE FUNCTION fn_subj_freeze() RETURNS trigger AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM tbl_enrl_t2 WHERE offe_id = OLD.offe_id) THEN
    RAISE EXCEPTION '수강신청이 있는 개설과목(%)의 과목 정보는 수정할 수 없습니다.', OLD.offe_id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_subj_freeze
  BEFORE UPDATE OF subj_id, semester, name, description, course, score ON tbl_subj_d2
  FOR EACH ROW
  WHEN ((OLD.subj_id, OLD.semester, OLD.name, OLD.description, OLD.course, OLD.score)
        IS DISTINCT FROM
        (NEW.subj_id, NEW.semester, NEW.name, NEW.description, NEW.course, NEW.score))
  EXECUTE FUNCTION fn_subj_freeze();
