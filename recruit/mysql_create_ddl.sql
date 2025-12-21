-- 1) 로그인방식 ✅
CREATE TABLE tbl_lgmt_l1 (
  lgmt_id CHAR(2)        NOT NULL,
  name    VARCHAR(6)     NOT NULL,
  PRIMARY KEY (lgmt_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2) 계정
CREATE TABLE tbl_acnt_m1 (
  acnt_id VARCHAR(16)    NOT NULL,
  passwd  CHAR(64)       NOT NULL,
  name    VARCHAR(4)     NOT NULL,
  lgmt_id CHAR(2)        NOT NULL,
  phone   CHAR(11)       NOT NULL,
  email   VARCHAR(50)    NOT NULL,
  pc      CHAR(1)        NOT NULL,
  PRIMARY KEY (acnt_id),
  FOREIGN KEY (lgmt_id) REFERENCES tbl_lgmt_l1(lgmt_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3) 개인회원
CREATE TABLE tbl_pnmb_d1 (
  pnmb_id VARCHAR(17)    NOT NULL,
  acnt_id CHAR(10)       NOT NULL,
  birth   CHAR(8)        NOT NULL,
  sex     CHAR(1)        NOT NULL,
  addr    VARCHAR(100)   NOT NULL,
  PRIMARY KEY (pnmb_id),
  FOREIGN KEY (acnt_id) REFERENCES tbl_acnt_m1(acnt_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4) 학력 공통
CREATE TABLE tbl_educ_d1 (
  educ_id      VARCHAR(18)  NOT NULL,
  pnmb_id      VARCHAR(17)  NOT NULL,
  sctype       VARCHAR(5)   NOT NULL,
  scname       VARCHAR(50),
  admissionym  CHAR(6),
  graduationym CHAR(6),
  status       CHAR(2)      NOT NULL,
  PRIMARY KEY (educ_id),
  FOREIGN KEY (pnmb_id) REFERENCES tbl_pnmb_d1(pnmb_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 5) 고등학교
CREATE TABLE tbl_hgsc_d1 (
  educ_id VARCHAR(18)   NOT NULL,
  hsequal CHAR(1)       NOT NULL,
  PRIMARY KEY (educ_id),
  FOREIGN KEY (educ_id) REFERENCES tbl_educ_d1(educ_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 6) 대학교
CREATE TABLE tbl_univ_d1 (
  educ_id     VARCHAR(18)  NOT NULL,
  majorname   VARCHAR(50)  NOT NULL,
  credits     VARCHAR(4)   NOT NULL,
  total       VARCHAR(4)   NOT NULL,
  transfer    CHAR(1)      NOT NULL,
  secondmajor CHAR(1)      NOT NULL,
  secondtype  VARCHAR(5),
  secondname  VARCHAR(50),
  PRIMARY KEY (educ_id),
  FOREIGN KEY (educ_id) REFERENCES tbl_educ_d1(educ_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 7) 대학원
CREATE TABLE tbl_grad_d1 (
  educ_id   VARCHAR(18)   NOT NULL,
  majorname VARCHAR(50)   NOT NULL,
  degree    CHAR(1)       NOT NULL,
  credits   VARCHAR(4)    NOT NULL,
  total     VARCHAR(4)    NOT NULL,
  PRIMARY KEY (educ_id),
  FOREIGN KEY (educ_id) REFERENCES tbl_educ_d1(educ_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 8) 자격증 정보
CREATE TABLE tbl_cert_l1 (
  cert_id VARCHAR(20)   NOT NULL,
  name    VARCHAR(50)   NOT NULL,
  certym  CHAR(6)       NOT NULL,
  PRIMARY KEY (cert_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 9) 자격증 보유
CREATE TABLE tbl_cthd_t1 (
  cthd_id INT            NOT NULL AUTO_INCREMENT,
  pnmb_id VARCHAR(17)    NOT NULL,
  cert_id VARCHAR(20)    NOT NULL,
  PRIMARY KEY (cthd_id),
  FOREIGN KEY (pnmb_id) REFERENCES tbl_pnmb_d1(pnmb_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,
  FOREIGN KEY (cert_id) REFERENCES tbl_cert_l1(cert_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 10) 직무
CREATE TABLE tbl_posi_l1 (
  posi_id INT          NOT NULL AUTO_INCREMENT,
  name    VARCHAR(30)  NOT NULL,
  PRIMARY KEY (posi_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 11) 개인회원희망직무
CREATE TABLE tbl_pnps_t1 (
  pnps_id INT          NOT NULL AUTO_INCREMENT,
  pnmb_id VARCHAR(17)  NOT NULL,
  posi_id INT          NOT NULL,
  PRIMARY KEY (pnps_id),
  FOREIGN KEY (pnmb_id) REFERENCES tbl_pnmb_d1(pnmb_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,
  FOREIGN KEY (posi_id) REFERENCES tbl_posi_l1(posi_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 12) 경력사항
CREATE TABLE tbl_expr_t1 (
  expr_id  VARCHAR(19)  NOT NULL,
  phmb_id  VARCHAR(17)  NOT NULL,
  comp_id  VARCHAR(17)  NOT NULL,
  deptname VARCHAR(30)  NOT NULL,
  joinym   CHAR(6)      NOT NULL,
  leaveym  CHAR(6)      NOT NULL,
  grade    VARCHAR(10)  NOT NULL,
  role     VARCHAR(6),
  posi_id  INT          NOT NULL,
  PRIMARY KEY (expr_id),
  FOREIGN KEY (phmb_id) REFERENCES tbl_pnmb_d1(pnmb_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,
  FOREIGN KEY (comp_id) REFERENCES tbl_comp_d1(comp_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,
  FOREIGN KEY (posi_id) REFERENCES tbl_posi_l1(posi_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 13) 모회사
CREATE TABLE tbl_affi_l1 (
  affi_id CHAR(4)      NOT NULL,
  name    VARCHAR(50)  NOT NULL,
  PRIMARY KEY (affi_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 14) 기업
CREATE TABLE tbl_comp_d1 (
  comp_id       VARCHAR(17)  NOT NULL,
  acnt_id       VARCHAR(16)  NOT NULL,
  comptype      CHAR(2)      NOT NULL,
  brn           CHAR(12)     NOT NULL,
  compname      VARCHAR(50)  NOT NULL,
  ceo           VARCHAR(50)  NOT NULL,
  addr          VARCHAR(100) NOT NULL,
  affi_id       CHAR(4)      NOT NULL,
  industry      VARCHAR(50)  NOT NULL,
  capital       BIGINT       NOT NULL,
  homelink      VARCHAR(100) NOT NULL,
  empcount      INT          NOT NULL,
  empcountdate  DATE         NOT NULL,
  estdate       DATE         NOT NULL,
  revenue       BIGINT       NOT NULL,
  revenuedate   DATE         NOT NULL,
  fourinsurance CHAR(1)      NOT NULL,
  PRIMARY KEY (comp_id),
  FOREIGN KEY (acnt_id) REFERENCES tbl_acnt_m1(acnt_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,
  FOREIGN KEY (affi_id) REFERENCES tbl_affi_l1(affi_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 15) 주요사업
CREATE TABLE tbl_busi_d1 (
  busi_id INT          NOT NULL AUTO_INCREMENT,
  comp_id VARCHAR(17)  NOT NULL,
  name    VARCHAR(30)  NOT NULL,
  PRIMARY KEY (busi_id),
  FOREIGN KEY (comp_id) REFERENCES tbl_comp_d1(comp_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 16) 채용공고
CREATE TABLE tbl_post_m1 (
  post_id   VARCHAR(22)  NOT NULL,
  comp_id   VARCHAR(17)  NOT NULL,
  expr      VARCHAR(4)   NOT NULL,
  edu       VARCHAR(10),
  emptype   VARCHAR(10)  NOT NULL,
  salary    VARCHAR(30)  NOT NULL,
  loc       VARCHAR(50)  NOT NULL,
  startdate DATE         NOT NULL,
  enddate   DATE         NOT NULL,
  applymt   CHAR(1)      NOT NULL,
  PRIMARY KEY (post_id),
  FOREIGN KEY (comp_id) REFERENCES tbl_comp_d1(comp_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 17) 채용공고-직무 관계
CREATE TABLE tbl_ptps_d1 (
  ptps_id INT          NOT NULL AUTO_INCREMENT,
  post_id VARCHAR(22)  NOT NULL,
  posi_id INT          NOT NULL,
  PRIMARY KEY (ptps_id),
  FOREIGN KEY (post_id) REFERENCES tbl_post_m1(post_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,
  FOREIGN KEY (posi_id) REFERENCES tbl_posi_l1(posi_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 18) 지원
CREATE TABLE tbl_aply_t1 (
  aply_id VARCHAR(20)  NOT NULL,
  pnmb_id VARCHAR(17)  NOT NULL,
  post_id VARCHAR(22)  NOT NULL,
    applydate DATETIME NOT NULL,
  success CHAR(1)      NOT NULL,
  public  CHAR(1)      NOT NULL,
  PRIMARY KEY (aply_id),
  FOREIGN KEY (pnmb_id) REFERENCES tbl_pnmb_d1(pnmb_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,
  FOREIGN KEY (post_id) REFERENCES tbl_post_m1(post_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 19) 자기소개서
CREATE TABLE tbl_cvlt_d1 (
  cvlt_id  VARCHAR(21)      NOT NULL,
  aply_id  VARCHAR(20)      NOT NULL,
  question VARCHAR(200)     NOT NULL,
  answer   VARCHAR(2000)    NOT NULL,
  PRIMARY KEY (cvlt_id),
  FOREIGN KEY (aply_id) REFERENCES tbl_aply_t1(aply_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

