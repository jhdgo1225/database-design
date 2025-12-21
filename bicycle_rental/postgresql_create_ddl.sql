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

drop table tblmebrm1;

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
            )
);

drop table tbltickd1;

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

drop table tblbyclm1;

CREATE TABLE tblrtplM1 (
    rtpl_id CHAR(5)    NOT NULL PRIMARY KEY
        CHECK (rtpl_id ~ '^(0[1-9]|1[0-9]|2[0-5])[0-9]{3}$'),
    space   VARCHAR(128) NOT NULL,
    addr    VARCHAR(256) NOT NULL,
    avail   SMALLINT     NOT NULL
        CHECK (avail >= 0)
);

drop table tblrtplm1;

CREATE TABLE tblrackD1 (
    rack_id   CHAR(7)  NOT NULL PRIMARY KEY,
    rtpl_id   CHAR(5)  NOT NULL REFERENCES tblrtplM1(rtpl_id),
    status    CHAR(3)  NOT NULL CHECK (status IN ('AVL', 'DMG')),
    bycl_id   CHAR(7)  NULL     REFERENCES tblbyclM1(bycl_id),
    gubun     CHAR(2)  NOT NULL CHECK (gubun  IN ('GN',  'SD'))
);

drop table tblrackd1;

CREATE TABLE tblrentT1 (
    rent_id      SERIAL         PRIMARY KEY,
    mebr_id      VARCHAR(16)    NOT NULL REFERENCES tblmebrM1(mebr_id),
    rtpl_id      CHAR(5)        NOT NULL REFERENCES tblrtplM1(rtpl_id),
    bycl_id      CHAR(7)        NOT NULL REFERENCES tblbyclM1(bycl_id),
    rentdate     TIMESTAMP      NOT NULL,
    time         INTERVAL       NOT NULL,
    dist         REAL           NOT NULL,
    kcal         REAL           NOT NULL,
    carbon       REAL           NOT NULL,
    retrtpl_id   CHAR(5)        REFERENCES tblrtplM1(rtpl_id),
    returndate   TIMESTAMP,
    fee          INT            NOT NULL
);

drop table tblrentt1;

CREATE TABLE tblspclD1 (
    spcl_id        BIGSERIAL    PRIMARY KEY,
    bycl_id        CHAR(7)      NOT NULL REFERENCES tblbyclM1(bycl_id),
    spclgubun      CHAR(2)      NOT NULL
                       CHECK (spclgubun IN ('SP', 'CL')),
    collectreason  CHAR(2)
                       CHECK (collectreason IN ('SP', 'DM', 'RP')),
    rtpl_id        CHAR(5)      NOT NULL REFERENCES tblrtplM1(rtpl_id),
    spcldate       TIMESTAMP    NOT NULL
);

drop table tblspcld1;

CREATE TABLE tbldmlsD1 (
    dmls_id     BIGSERIAL      PRIMARY KEY,
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

drop table tbldmlsd1;

CREATE TABLE tblfavoT1 (
    mebr_id VARCHAR(16) NOT NULL,
    rtpl_id CHAR(5)     NOT NULL,
    PRIMARY KEY (mebr_id, rtpl_id),
    FOREIGN KEY (mebr_id) REFERENCES tblmebrM1(mebr_id),
    FOREIGN KEY (rtpl_id) REFERENCES tblrtplM1(rtpl_id)
);

drop table tblfavot1;

