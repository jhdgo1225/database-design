CREATE TABLE tbl_dept_m1 (
  dept_id CHAR(3)  NOT NULL PRIMARY KEY -- 학부 코드 번호(1자리) + 학부 소속 학과 번호(2자리)
, name    CHAR(32) NOT NULL  -- 학과 이름
);

CREATE TABLE tbl_stud_m1 (
  stud_id CHAR(10)     NOT NULL PRIMARY KEY                              -- 입학년도(4) + 소속학과(3) + 등록순서(3)
, passwd  CHAR(64)     NOT NULL                                          -- 대/소문자·숫자·특수문자 각 1자 이상, 12~20자리 SHA-256 해시
, name    VARCHAR(4)   NOT NULL                                          -- 한국 이름
, birth   DATE         NOT NULL                                          -- 생년월일
, grade   INT          NOT NULL                                          -- 1,2,3,4학년
, sex     CHAR(1)      NOT NULL                                          -- 'M': Male, 'F': Female
, dept_id CHAR(3)      NOT NULL REFERENCES tbl_dept_m1(dept_id)
                         ON UPDATE CASCADE ON DELETE RESTRICT            -- 소속학과 ID
, addr    VARCHAR(128) NOT NULL                                          -- 도로명주소
, zipcode CHAR(5)      NOT NULL                                          -- 우정사업본부 표준
, phone   CHAR(11)     NOT NULL                                          -- '01000000000' 형식
, email   VARCHAR(64)  NOT NULL                                          -- 학생 이메일
);

CREATE TABLE tbl_prof_m1 (
  prof_id CHAR(9)   NOT NULL PRIMARY KEY                           -- 입학년도(4) + 소속학과(3) + 등록순서(2)
, passwd  CHAR(64)  NOT NULL                                       -- 대/소문자·숫자·특수문자 각 1자 이상, 12~20자리 SHA-256 해시
, name    VARCHAR(4) NOT NULL                                      -- 교수 이름 (한국 이름)
, birth   DATE       NOT NULL                                      -- 교수 생년월일
, sex     CHAR(1)    NOT NULL                                      -- 'M': Male, 'F': Female
, dept_id CHAR(3)    NOT NULL REFERENCES tbl_dept_m1(dept_id)     -- 소속학과 ID
                     ON UPDATE CASCADE ON DELETE RESTRICT
, addr    VARCHAR(128) NOT NULL                                    -- 도로명주소
, zipcode CHAR(5)     NOT NULL                                     -- 우정사업본부 표준
, phone   CHAR(11)    NOT NULL                                     -- '01000000000' 형식
, email   VARCHAR(64) NOT NULL                                     -- 교수 이메일
, rank    CHAR(1)     NOT NULL                                     -- 'P': 정교수, 'S': 부교수, 'L': 조교수, 'T': 시간강사
);

CREATE TABLE tbl_subj_m1 (
  subj_id     CHAR(5)    NOT NULL PRIMARY KEY,  -- 학과ID(3자리) + 등록순서(2자리)
  name        VARCHAR(64) NOT NULL,             -- 과목명
  description VARCHAR(256) NOT NULL,             -- 과목 설명
  course      CHAR(2)    NOT NULL,              -- 이수구분 (MR/ME/GR/GE)
  score       REAL       NOT NULL               -- 과목 학점 (전공:3, 교양:2)
);

CREATE TABLE tbl_offe_d1 (
  offe_id CHAR(13) NOT NULL PRIMARY KEY                             -- 학기(6자리) + 과목코드(5자리) + 등록번호(2자리)
, semester    CHAR(6)  NOT NULL                                         -- 과목이 개설된 학기 (YYYY학기 ex: 202501)
, subj_id CHAR(5)  NOT NULL REFERENCES tbl_subj_m1(subj_id)        -- 과목코드
                      ON UPDATE CASCADE ON DELETE RESTRICT
, prof_id CHAR(9)  NOT NULL REFERENCES tbl_prof_m1(prof_id)        -- 교수 ID
                      ON UPDATE CASCADE ON DELETE RESTRICT
, dept_id CHAR(3)  NOT NULL REFERENCES tbl_dept_m1(dept_id)        -- 대상학과 ID
                      ON UPDATE CASCADE ON DELETE RESTRICT
, grade   INT      NOT NULL                                         -- 개설과목 대상 학년 (1~4)
);

CREATE TABLE tbl_room_l1 (
  room_id  VARCHAR(6)  NOT NULL PRIMARY KEY   -- 호관명(2자리) + 호실번호(최대4자리)
, building CHAR(2)     NOT NULL               -- 강의실 건물 호관 이름 (01~10, MB)
, roomno   VARCHAR(4)  NOT NULL               -- 강의실 호실 번호 (예: B106)
);

CREATE TABLE tbl_sche_d1 (
  sche_id CHAR(16) NOT NULL PRIMARY KEY                                 -- 개설ID(13) + 요일(1) + 교시(2)
, offe_id CHAR(13) NOT NULL                                             -- 개설과목 ID
    REFERENCES tbl_offe_d1(offe_id)
    ON UPDATE CASCADE ON DELETE RESTRICT
, weekday INT         NOT NULL                                          -- 강의 진행 요일 (0=일, 1=월, …, 6=토)
, period  INT         NOT NULL                                          -- 강의를 하는 교시 (1~10)
, room_id VARCHAR(6)     NOT NULL                                          -- 강의실 ID
    REFERENCES tbl_room_l1(room_id)
    ON UPDATE CASCADE ON DELETE RESTRICT
);


CREATE TABLE tbl_enrl_t1 (
  enrl_id CHAR(18) NOT NULL PRIMARY KEY
    -- 시간표ID(16자리) + 신청순서(2자리)
, stud_id CHAR(10) NOT NULL
    REFERENCES tbl_stud_m1(stud_id)
    ON UPDATE CASCADE ON DELETE RESTRICT
    -- 학생 ID
, sche_id CHAR(16) NOT NULL
    REFERENCES tbl_sche_d1(sche_id)
    ON UPDATE CASCADE ON DELETE RESTRICT
    -- 시간표 ID
, grade VARCHAR(2) NULL
);
