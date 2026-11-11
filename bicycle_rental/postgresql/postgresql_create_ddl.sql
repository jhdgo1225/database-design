CREATE TABLE tblmebrM1 (
    mebr_id VARCHAR(16) PRIMARY KEY CHECK (
        LENGTH(mebr_id) BETWEEN 10 AND 16
        AND mebr_id ~ '^(?=.*[a-z])(?=.*[0-9])[a-z0-9]+$'
    ),
    passwd CHAR(64) NOT NULL,
    name VARCHAR(128) NOT NULL,
    sex CHAR(1) NOT NULL CHECK (sex IN ('M', 'F')),
    birth DATE NOT NULL,
    phone CHAR(11) NOT NULL CHECK (phone ~ '^010[0-9]{8}$'),
    email VARCHAR(64) NOT NULL,
    totalrental INT NOT NULL,
    points INT NOT NULL,
    signupmethod CHAR(2) NOT NULL CHECK (signupmethod IN ('GN', 'NV', 'KA', 'GG')),
    flag CHAR(1) NOT NULL DEFAULT 'N' CHECK (flag IN ('Y', 'N'))
);


CREATE TABLE tbltickD1 (
  tick_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  mebr_id   VARCHAR(16) NOT NULL
            REFERENCES tblmebrM1(mebr_id),
  ticket    VARCHAR(8) NOT NULL
            CHECK (
              ticket ~ ('^PRE[12][AN]$|^(?:030|090|180|365)[12][0-9]{3}[AN]$')
            ),
  startdate TIMESTAMP   NOT NULL,
  enddate   TIMESTAMP   NOT NULL,
  points    INT         NOT NULL,
  paymethod VARCHAR(4)  NOT NULL
            CHECK (
              paymethod ~ '^(CP|BT)[A-Z]{2}$|^(NV|KA|TO|ML)$'
            ),
  -- 이용권 코드(ticket)에서 뽑아낸 값. 코드가 바뀌면 같이 바뀌고, 직접 넣을 수 없다.
  -- 코드 구성: 기간(3자리) + 시간(1자리) + 금액(3자리) + A/N, PRE는 PRE + 시간(1자리) + A/N
  -- 마지막 A/N은 의미가 정해지지 않아 아직 분리하지 않았다.
  periodday INT GENERATED ALWAYS AS (
              CASE WHEN ticket LIKE 'PRE%' THEN NULL
                   ELSE SUBSTRING(ticket FROM 1 FOR 3)::INT END
            ) STORED,
  usehour   INT GENERATED ALWAYS AS (
              SUBSTRING(ticket FROM 4 FOR 1)::INT
            ) STORED,
  price     INT GENERATED ALWAYS AS (   -- 금액 3자리를 100원 단위로 읽음
              CASE WHEN ticket LIKE 'PRE%' THEN NULL
                   ELSE SUBSTRING(ticket FROM 5 FOR 3)::INT * 100 END
            ) STORED
);


CREATE TABLE tblbyclM1 (
    bycl_id     CHAR(7)     NOT NULL PRIMARY KEY,
    registerdate TIMESTAMP  NOT NULL,
    installdate  TIMESTAMP  NULL,
    status      VARCHAR(3)  NOT NULL CHECK (
        status IN (
            'PD',   -- Pending (준비중)
            'AVL',  -- Available (대여가능)
            'ING',  -- In-going (대여중)
            'DMG',  -- Damaged (파손)
            'LST',  -- Lost (분실)
            'RP',   -- Repair (수리)
            'COL'   -- Collect (수거)
        )
    ),
    gubun       CHAR(2)     NOT NULL CHECK (
        gubun IN (
            'GN',   -- General (일반)
            'SD'    -- Seed (새싹)
        )
    )
);


CREATE TABLE tblrtplM1 (
    rtpl_id CHAR(5)    NOT NULL PRIMARY KEY
        CHECK (rtpl_id ~ '^(0[1-9]|1[0-9]|2[0-5])[0-9]{3}$'),
    space   VARCHAR(128) NOT NULL,
    addr    VARCHAR(256) NOT NULL,
    avail   SMALLINT     NOT NULL
        CHECK (avail >= 0)
);


CREATE TABLE tblrackD1 (
    rack_id   CHAR(7)  NOT NULL PRIMARY KEY,
    rtpl_id   CHAR(5)  NOT NULL REFERENCES tblrtplM1(rtpl_id),
    status    CHAR(3)  NOT NULL CHECK (status IN ('AVL', 'DMG')),
    bycl_id   CHAR(7)  NULL     UNIQUE REFERENCES tblbyclM1(bycl_id),  -- 한 자전거는 거치대 하나에만 (NULL은 여러 개 가능)
    gubun     CHAR(2)  NOT NULL CHECK (gubun  IN ('GN',  'SD'))
);


CREATE TABLE tblrentT1 (
    rent_id      SERIAL         PRIMARY KEY,
    mebr_id      VARCHAR(16)    NOT NULL REFERENCES tblmebrM1(mebr_id),
    rtpl_id      CHAR(5)        NOT NULL REFERENCES tblrtplM1(rtpl_id),
    bycl_id      CHAR(7)        NOT NULL REFERENCES tblbyclM1(bycl_id),
    rentdate     TIMESTAMP      NOT NULL,
    time         INTERVAL       NOT NULL,
    fixhour      SMALLINT       NOT NULL CHECK (fixhour IN (1, 2)),  -- 고정 대여 시간(선불로 정한 1시간 또는 2시간). 넘으면 10분마다 초과 요금
    dist         NUMERIC(6,2)   NOT NULL,
    kcal         NUMERIC(7,2)   NOT NULL,
    carbon       NUMERIC(6,3)   NOT NULL,
    retrtpl_id   CHAR(5)        REFERENCES tblrtplM1(rtpl_id),
    returndate   TIMESTAMP,
    fee          INT            NOT NULL
);


CREATE TABLE tblspclD1 (
    spcl_id        BIGSERIAL    PRIMARY KEY,
    bycl_id        CHAR(7)      NOT NULL REFERENCES tblbyclM1(bycl_id),
    spclgubun      CHAR(2)      NOT NULL
                       CHECK (spclgubun IN ('SP', 'CL')),
    collectreason  CHAR(2)
                       CHECK (collectreason IN ('DM', 'RP')),
    rtpl_id        CHAR(5)      NOT NULL REFERENCES tblrtplM1(rtpl_id),
    spcldate       TIMESTAMP    NOT NULL,
    -- 수거(CL)일 때만 수거 사유가 있고, 보충(SP)은 NULL
    CHECK ((spclgubun = 'CL' AND collectreason IS NOT NULL)
        OR (spclgubun = 'SP' AND collectreason IS NULL))
);


CREATE TABLE tbldmlsD1 (
    dmls_id     BIGSERIAL      PRIMARY KEY,
    rent_id     INT            NOT NULL REFERENCES tblrentT1(rent_id),
    bycl_id     CHAR(7)        NOT NULL REFERENCES tblbyclM1(bycl_id),
    mebr_id     VARCHAR(16)    NOT NULL REFERENCES tblmebrM1(mebr_id),
    dmlsflag    CHAR(2)        NOT NULL
                       CHECK (dmlsflag IN ('DM', 'LS')),
    name        VARCHAR(128),
    phone       CHAR(11),
    addr        VARCHAR(128),
    reason      VARCHAR(600),
    occurdate   TIMESTAMP      NOT NULL,
    liable      CHAR(1)        NOT NULL DEFAULT 'N'
                       CHECK (liable IN ('Y', 'N')),
    confirm     CHAR(1)        NOT NULL DEFAULT 'N'
                       CHECK (confirm IN ('Y', 'N')),
    amount      INT,
    claimdate   TIMESTAMP
);


CREATE TABLE tblfavoT1 (
    mebr_id VARCHAR(16) NOT NULL,
    rtpl_id CHAR(5)     NOT NULL,
    PRIMARY KEY (mebr_id, rtpl_id),
    FOREIGN KEY (mebr_id) REFERENCES tblmebrM1(mebr_id),
    FOREIGN KEY (rtpl_id) REFERENCES tblrtplM1(rtpl_id)
);


-- 인덱스
-- 미반납 대여(returndate IS NULL)는 자전거와 회원마다 하나뿐이다.
CREATE UNIQUE INDEX uq_rent_open_bycl ON tblrentT1 (bycl_id) WHERE returndate IS NULL;
CREATE UNIQUE INDEX uq_rent_open_mebr ON tblrentT1 (mebr_id) WHERE returndate IS NULL;

-- FK 컬럼 인덱스. PostgreSQL은 FK에 인덱스를 자동으로 만들지 않는다.
-- tblrackD1.bycl_id는 UNIQUE, tblfavoT1.mebr_id는 복합 PK가 이미 인덱스 역할을 한다.
CREATE INDEX idx_tick_mebr  ON tbltickD1 (mebr_id);
CREATE INDEX idx_rack_rtpl  ON tblrackD1 (rtpl_id);
CREATE INDEX idx_rent_mebr  ON tblrentT1 (mebr_id);
CREATE INDEX idx_rent_rtpl  ON tblrentT1 (rtpl_id);
CREATE INDEX idx_rent_bycl  ON tblrentT1 (bycl_id);
CREATE INDEX idx_rent_retrtpl ON tblrentT1 (retrtpl_id);
CREATE INDEX idx_spcl_bycl  ON tblspclD1 (bycl_id);
CREATE INDEX idx_spcl_rtpl  ON tblspclD1 (rtpl_id);
CREATE INDEX idx_dmls_rent  ON tbldmlsD1 (rent_id);
CREATE INDEX idx_dmls_bycl  ON tbldmlsD1 (bycl_id);
CREATE INDEX idx_dmls_mebr  ON tbldmlsD1 (mebr_id);
CREATE INDEX idx_favo_rtpl  ON tblfavoT1 (rtpl_id);
