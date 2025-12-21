CREATE TABLE tblmebrM1 (
    mebr_id VARCHAR(16) PRIMARY KEY,
    passwd CHAR(64) NOT NULL,
    name VARCHAR(128) NOT NULL,
    sex CHAR(1) NOT NULL CHECK (sex IN ('M', 'F')),
    birth DATE NOT NULL,
    phone CHAR(11) NOT NULL CHECK (phone REGEXP '^010[0-9]{8}$'),
    email VARCHAR(64) NOT NULL,
    totalrental INT NOT NULL,
    points INT NOT NULL,
    signupmethod CHAR(2) NOT NULL CHECK (signupmethod IN ('GN', 'NV', 'KA', 'GG')),
    flag CHAR(1) NOT NULL DEFAULT 'N' CHECK (flag IN ('Y', 'N')),
    CONSTRAINT chk_mebr_id_format CHECK (
        CHAR_LENGTH(mebr_id) BETWEEN 10 AND 16
        AND mebr_id REGEXP '^[a-z0-9]+$'
        AND mebr_id REGEXP '[a-z]'
        AND mebr_id REGEXP '[0-9]'
    )
);

CREATE TABLE tbltickD1 (
  tick_id   INT AUTO_INCREMENT PRIMARY KEY,
  mebr_id   VARCHAR(16) NOT NULL,
  ticket    VARCHAR(8) NOT NULL,
  startdate DATETIME   NOT NULL,
  enddate   DATETIME   NOT NULL,
  points    INT         NOT NULL,
  paymethod VARCHAR(4)  NOT NULL,
  FOREIGN KEY (mebr_id) REFERENCES tblmebrM1(mebr_id),
  CONSTRAINT chk_ticket_format CHECK (
    ticket REGEXP '^PRE[12][AN]$' OR
    ticket REGEXP '^(030|090|180|365)[12][0-9]{3}[AN]$'
  ),
  CONSTRAINT chk_paymethod_format CHECK (
    paymethod REGEXP '^(CP|BT)[A-Z]{2}$' OR
    paymethod REGEXP '^(NV|KA|TO|ML)$'
  )
);

CREATE TABLE tblbyclM1 (
    bycl_id     CHAR(7)     NOT NULL PRIMARY KEY,
    registerdate DATETIME  NOT NULL,
    installdate  DATETIME  NULL,
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
    rtpl_id CHAR(5)    NOT NULL PRIMARY KEY,
    space   VARCHAR(128) NOT NULL,
    addr    VARCHAR(256) NOT NULL,
    avail   SMALLINT     NOT NULL CHECK (avail >= 0),
    CONSTRAINT chk_rtpl_id_format CHECK (rtpl_id REGEXP '^(0[1-9]|1[0-9]|2[0-5])[0-9]{3}$')
);

CREATE TABLE tblrackD1 (
    rack_id   CHAR(7)  NOT NULL PRIMARY KEY,
    rtpl_id   CHAR(5)  NOT NULL,
    status    CHAR(3)  NOT NULL CHECK (status IN ('AVL', 'DMG')),
    bycl_id   CHAR(7)  NULL,
    gubun     CHAR(2)  NOT NULL CHECK (gubun  IN ('GN',  'SD')),
    FOREIGN KEY (rtpl_id) REFERENCES tblrtplM1(rtpl_id),
    FOREIGN KEY (bycl_id) REFERENCES tblbyclM1(bycl_id)
);

CREATE TABLE tblrentT1 (
    rent_id      INT AUTO_INCREMENT PRIMARY KEY,
    mebr_id      VARCHAR(16)    NOT NULL,
    rtpl_id      CHAR(5)        NOT NULL,
    bycl_id      CHAR(7)        NOT NULL,
    rentdate     DATETIME       NOT NULL,
    time         TIME           NOT NULL,
    dist         REAL           NOT NULL,
    kcal         REAL           NOT NULL,
    carbon       REAL           NOT NULL,
    retrtpl_id   CHAR(5),
    returndate   DATETIME,
    fee          INT            NOT NULL,
    FOREIGN KEY (mebr_id) REFERENCES tblmebrM1(mebr_id),
    FOREIGN KEY (rtpl_id) REFERENCES tblrtplM1(rtpl_id),
    FOREIGN KEY (bycl_id) REFERENCES tblbyclM1(bycl_id),
    FOREIGN KEY (retrtpl_id) REFERENCES tblrtplM1(rtpl_id)
);

CREATE TABLE tblspclD1 (
    spcl_id        BIGINT AUTO_INCREMENT PRIMARY KEY,
    bycl_id        CHAR(7)      NOT NULL,
    spclgubun      CHAR(2)      NOT NULL CHECK (spclgubun IN ('SP', 'CL')),
    collectreason  CHAR(2) CHECK (collectreason IN ('SP', 'DM', 'RP')),
    rtpl_id        CHAR(5)      NOT NULL,
    spcldate       DATETIME    NOT NULL,
    FOREIGN KEY (bycl_id) REFERENCES tblbyclM1(bycl_id),
    FOREIGN KEY (rtpl_id) REFERENCES tblrtplM1(rtpl_id)
);

CREATE TABLE tbldmlsD1 (
    dmls_id     BIGINT AUTO_INCREMENT PRIMARY KEY,
    bycl_id     CHAR(7)        NOT NULL,
    mebr_id     VARCHAR(16)    NOT NULL,
    dmlsflag    CHAR(2)        NOT NULL CHECK (dmlsflag IN ('DM', 'LS')),
    name        VARCHAR(128),
    phone       CHAR(11),
    addr        VARCHAR(128),
    reason      VARCHAR(600),
    occurdate   DATETIME      NOT NULL,
    liable      CHAR(1)        NOT NULL DEFAULT 'N' CHECK (liable IN ('Y', 'N')),
    confirm     CHAR(1)        NOT NULL DEFAULT 'N' CHECK (confirm IN ('Y', 'N')),
    amount      INT,
    claimdate   DATETIME,
    FOREIGN KEY (bycl_id) REFERENCES tblbyclM1(bycl_id),
    FOREIGN KEY (mebr_id) REFERENCES tblmebrM1(mebr_id)
);

CREATE TABLE tblfavoT1 (
    mebr_id VARCHAR(16) NOT NULL,
    rtpl_id CHAR(5)     NOT NULL,
    PRIMARY KEY (mebr_id, rtpl_id),
    FOREIGN KEY (mebr_id) REFERENCES tblmebrM1(mebr_id),
    FOREIGN KEY (rtpl_id) REFERENCES tblrtplM1(rtpl_id)
);
