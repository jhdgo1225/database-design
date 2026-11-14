-- v2.0.0 반정규화 스키마. 정규화 스키마에 더한 부분(tblrtplM1, tblrentT1, 집계 테이블, 트리거)과 적재 순서는 DB_VERSION_HISTORY.md 에 있다.


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
        CHECK (avail >= 0),
    UNIQUE (rtpl_id, space)   -- tblrentT1 이 (rtpl_id, space) 로 참조하기 위한 대상 키
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
    rtpl_id      CHAR(5)        NOT NULL,
    bycl_id      CHAR(7)        NOT NULL REFERENCES tblbyclM1(bycl_id),
    rentdate     TIMESTAMP      NOT NULL,
    time         INTERVAL       NOT NULL,
    fixhour      SMALLINT       NOT NULL CHECK (fixhour IN (1, 2)),  -- 고정 대여 시간(선불로 정한 1시간 또는 2시간). 넘으면 10분마다 초과 요금
    dist         NUMERIC(6,2)   NOT NULL,
    kcal         NUMERIC(7,2)   NOT NULL,
    carbon       NUMERIC(6,3)   NOT NULL,
    retrtpl_id   CHAR(5),
    returndate   TIMESTAMP,
    fee          INT            NOT NULL,

    -- 반정규화 열
    rtpl_space    VARCHAR(128)  NOT NULL,   -- 대여소 이름 복사. trg_rent_fill 이 채운다
    retrtpl_space VARCHAR(128),
    rent_ym   DATE     GENERATED ALWAYS AS (DATE_TRUNC('month', rentdate)::DATE) STORED,     -- 대여한 달의 1일
    rent_dow  SMALLINT GENERATED ALWAYS AS (EXTRACT(DOW FROM rentdate)::SMALLINT) STORED,    -- 0=일, 1=월 ... 6=토
    rent_slot SMALLINT GENERATED ALWAYS AS (                                                -- 1=심야(0~4시), 2=오전(5~11시), 3=오후(12~17시), 4=야간
                CASE WHEN EXTRACT(HOUR FROM rentdate) BETWEEN 0  AND 4  THEN 1
                     WHEN EXTRACT(HOUR FROM rentdate) BETWEEN 5  AND 11 THEN 2
                     WHEN EXTRACT(HOUR FROM rentdate) BETWEEN 12 AND 17 THEN 3
                     ELSE 4 END
            ) STORED,
    return_ym DATE     GENERATED ALWAYS AS (DATE_TRUNC('month', returndate)::DATE) STORED,   -- 반납한 달의 1일, 미반납이면 NULL

    CHECK ((retrtpl_id IS NULL) = (retrtpl_space IS NULL)),
    FOREIGN KEY (rtpl_id, rtpl_space)       REFERENCES tblrtplM1(rtpl_id, space) ON UPDATE CASCADE,
    FOREIGN KEY (retrtpl_id, retrtpl_space) REFERENCES tblrtplM1(rtpl_id, space) ON UPDATE CASCADE
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


-- 집계 테이블. trg_rent_summary 가 대여에 맞춰 고치고, 개수가 0이 되면 행을 지운다.

-- 대여소×월 (쿼리 1, 4). rent_cnt는 대여 대여소·대여한 달 기준, ret_cnt와 ret_fee는 반납 대여소·반납한 달 기준
CREATE TABLE tblrpmoS1 (
    rtpl_id  CHAR(5) NOT NULL,
    space    VARCHAR(128) NOT NULL,   -- 대여소 이름 복사. 대여 행의 rtpl_space, retrtpl_space 에서 가져온다
    ym       DATE    NOT NULL,
    rent_cnt INT     NOT NULL DEFAULT 0 CHECK (rent_cnt >= 0),
    ret_cnt  INT     NOT NULL DEFAULT 0 CHECK (ret_cnt >= 0),
    ret_fee  BIGINT  NOT NULL DEFAULT 0,
    PRIMARY KEY (rtpl_id, ym),
    FOREIGN KEY (rtpl_id, space) REFERENCES tblrtplM1(rtpl_id, space) ON UPDATE CASCADE
);

-- 자전거×월 (쿼리 2)
CREATE TABLE tblbcmoS1 (
    bycl_id  CHAR(7)  NOT NULL,
    ym       DATE     NOT NULL,
    rent_cnt INT      NOT NULL CHECK (rent_cnt >= 0),
    time_sum INTERVAL NOT NULL,
    PRIMARY KEY (bycl_id, ym)
);

-- 대여소×요일×시간대 (쿼리 5, 7). dow, slot 은 tblrentT1.rent_dow, rent_slot 과 같다
CREATE TABLE tblrpwdS1 (
    rtpl_id  CHAR(5)   NOT NULL,
    space    VARCHAR(128) NOT NULL,   -- 대여소 이름 복사. 대여 행의 rtpl_space 에서 가져온다
    dow      SMALLINT  NOT NULL,
    slot     SMALLINT  NOT NULL,
    rent_cnt INT       NOT NULL CHECK (rent_cnt >= 0),
    time_sum INTERVAL  NOT NULL,
    PRIMARY KEY (rtpl_id, dow, slot),
    FOREIGN KEY (rtpl_id, space) REFERENCES tblrtplM1(rtpl_id, space) ON UPDATE CASCADE
);

-- 회원×구 (쿼리 6). 구 번호는 대여소 ID 앞 2자리이고, 대여한 구와 반납한 구에서 한 번씩 센다
CREATE TABLE tblmbrgS1 (
    mebr_id    VARCHAR(16)   NOT NULL,
    region     CHAR(2)       NOT NULL,
    use_cnt    INT           NOT NULL CHECK (use_cnt >= 0),
    time_sum   INTERVAL      NOT NULL,
    dist_sum   NUMERIC(14,2) NOT NULL,
    carbon_sum NUMERIC(14,3) NOT NULL,
    PRIMARY KEY (mebr_id, region)
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


-- 대여소 이름 채우기
CREATE FUNCTION fn_rent_fill() RETURNS trigger AS $$
BEGIN
    SELECT space INTO NEW.rtpl_space FROM tblrtplM1 WHERE rtpl_id = NEW.rtpl_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION '대여소 %가 존재하지 않습니다.', NEW.rtpl_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    IF NEW.retrtpl_id IS NULL THEN
        NEW.retrtpl_space := NULL;
    ELSE
        SELECT space INTO NEW.retrtpl_space FROM tblrtplM1 WHERE rtpl_id = NEW.retrtpl_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION '반납 대여소 %가 존재하지 않습니다.', NEW.retrtpl_id
                USING ERRCODE = 'foreign_key_violation';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 대여소 이름 변경이 ON UPDATE CASCADE 로 전파될 때도 돌지만, 새 이름을 다시 읽을 뿐이라 같은 값이 된다
CREATE TRIGGER trg_rent_fill
    BEFORE INSERT OR UPDATE OF rtpl_id, retrtpl_id
    ON tblrentT1
    FOR EACH ROW
    EXECUTE FUNCTION fn_rent_fill();


-- 대여 한 건 r 을 집계 테이블 4개에 더하거나(p_sign = 1) 뺀다(-1). 뺄 때 개수가 0이 되면 행을 지운다
CREATE FUNCTION fn_rent_summary_apply(r tblrentT1, p_sign INT) RETURNS void AS $$
DECLARE
    v_returned BOOLEAN := r.retrtpl_id IS NOT NULL AND r.returndate IS NOT NULL;   -- 쿼리 4는 반납 대여소가 있고 반납일시도 있는 대여만 센다
BEGIN
    -- 대여소×월: 대여 쪽
    IF p_sign > 0 THEN
        INSERT INTO tblrpmoS1 (rtpl_id, space, ym, rent_cnt) VALUES (r.rtpl_id, r.rtpl_space, r.rent_ym, 1)
        ON CONFLICT (rtpl_id, ym) DO UPDATE SET rent_cnt = tblrpmoS1.rent_cnt + 1;
    ELSE
        UPDATE tblrpmoS1 SET rent_cnt = rent_cnt - 1 WHERE rtpl_id = r.rtpl_id AND ym = r.rent_ym;
        DELETE FROM tblrpmoS1 WHERE rtpl_id = r.rtpl_id AND ym = r.rent_ym AND rent_cnt = 0 AND ret_cnt = 0;
    END IF;

    -- 대여소×월: 반납 쪽
    IF v_returned THEN
        IF p_sign > 0 THEN
            INSERT INTO tblrpmoS1 (rtpl_id, space, ym, ret_cnt, ret_fee) VALUES (r.retrtpl_id, r.retrtpl_space, r.return_ym, 1, r.fee)
            ON CONFLICT (rtpl_id, ym) DO UPDATE
                SET ret_cnt = tblrpmoS1.ret_cnt + 1, ret_fee = tblrpmoS1.ret_fee + EXCLUDED.ret_fee;
        ELSE
            UPDATE tblrpmoS1 SET ret_cnt = ret_cnt - 1, ret_fee = ret_fee - r.fee
            WHERE rtpl_id = r.retrtpl_id AND ym = r.return_ym;
            DELETE FROM tblrpmoS1 WHERE rtpl_id = r.retrtpl_id AND ym = r.return_ym AND rent_cnt = 0 AND ret_cnt = 0;
        END IF;
    END IF;

    -- 자전거×월
    IF p_sign > 0 THEN
        INSERT INTO tblbcmoS1 (bycl_id, ym, rent_cnt, time_sum) VALUES (r.bycl_id, r.rent_ym, 1, r.time)
        ON CONFLICT (bycl_id, ym) DO UPDATE
            SET rent_cnt = tblbcmoS1.rent_cnt + 1, time_sum = tblbcmoS1.time_sum + EXCLUDED.time_sum;
    ELSE
        UPDATE tblbcmoS1 SET rent_cnt = rent_cnt - 1, time_sum = time_sum - r.time
        WHERE bycl_id = r.bycl_id AND ym = r.rent_ym;
        DELETE FROM tblbcmoS1 WHERE bycl_id = r.bycl_id AND ym = r.rent_ym AND rent_cnt = 0;
    END IF;

    -- 대여소×요일×시간대
    IF p_sign > 0 THEN
        INSERT INTO tblrpwdS1 (rtpl_id, space, dow, slot, rent_cnt, time_sum) VALUES (r.rtpl_id, r.rtpl_space, r.rent_dow, r.rent_slot, 1, r.time)
        ON CONFLICT (rtpl_id, dow, slot) DO UPDATE
            SET rent_cnt = tblrpwdS1.rent_cnt + 1, time_sum = tblrpwdS1.time_sum + EXCLUDED.time_sum;
    ELSE
        UPDATE tblrpwdS1 SET rent_cnt = rent_cnt - 1, time_sum = time_sum - r.time
        WHERE rtpl_id = r.rtpl_id AND dow = r.rent_dow AND slot = r.rent_slot;
        DELETE FROM tblrpwdS1 WHERE rtpl_id = r.rtpl_id AND dow = r.rent_dow AND slot = r.rent_slot AND rent_cnt = 0;
    END IF;

    -- 회원×구: 대여한 대여소의 구
    IF p_sign > 0 THEN
        INSERT INTO tblmbrgS1 (mebr_id, region, use_cnt, time_sum, dist_sum, carbon_sum)
        VALUES (r.mebr_id, SUBSTRING(r.rtpl_id, 1, 2), 1, r.time, r.dist, r.carbon)
        ON CONFLICT (mebr_id, region) DO UPDATE
            SET use_cnt = tblmbrgS1.use_cnt + 1, time_sum = tblmbrgS1.time_sum + EXCLUDED.time_sum,
                dist_sum = tblmbrgS1.dist_sum + EXCLUDED.dist_sum, carbon_sum = tblmbrgS1.carbon_sum + EXCLUDED.carbon_sum;
    ELSE
        UPDATE tblmbrgS1 SET use_cnt = use_cnt - 1, time_sum = time_sum - r.time,
                             dist_sum = dist_sum - r.dist, carbon_sum = carbon_sum - r.carbon
        WHERE mebr_id = r.mebr_id AND region = SUBSTRING(r.rtpl_id, 1, 2);
        DELETE FROM tblmbrgS1 WHERE mebr_id = r.mebr_id AND region = SUBSTRING(r.rtpl_id, 1, 2) AND use_cnt = 0;
    END IF;

    -- 회원×구: 반납한 대여소의 구
    IF r.retrtpl_id IS NOT NULL THEN
        IF p_sign > 0 THEN
            INSERT INTO tblmbrgS1 (mebr_id, region, use_cnt, time_sum, dist_sum, carbon_sum)
            VALUES (r.mebr_id, SUBSTRING(r.retrtpl_id, 1, 2), 1, r.time, r.dist, r.carbon)
            ON CONFLICT (mebr_id, region) DO UPDATE
                SET use_cnt = tblmbrgS1.use_cnt + 1, time_sum = tblmbrgS1.time_sum + EXCLUDED.time_sum,
                    dist_sum = tblmbrgS1.dist_sum + EXCLUDED.dist_sum, carbon_sum = tblmbrgS1.carbon_sum + EXCLUDED.carbon_sum;
        ELSE
            UPDATE tblmbrgS1 SET use_cnt = use_cnt - 1, time_sum = time_sum - r.time,
                                 dist_sum = dist_sum - r.dist, carbon_sum = carbon_sum - r.carbon
            WHERE mebr_id = r.mebr_id AND region = SUBSTRING(r.retrtpl_id, 1, 2);
            DELETE FROM tblmbrgS1 WHERE mebr_id = r.mebr_id AND region = SUBSTRING(r.retrtpl_id, 1, 2) AND use_cnt = 0;
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION fn_rent_summary() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM fn_rent_summary_apply(NEW, 1);
    ELSIF TG_OP = 'DELETE' THEN
        PERFORM fn_rent_summary_apply(OLD, -1);
    ELSE
        -- 집계에 쓰는 값이 그대로면 건너뛴다 (대여소 이름 전파 UPDATE)
        IF (OLD.rtpl_id, OLD.retrtpl_id, OLD.bycl_id, OLD.mebr_id, OLD.rentdate, OLD.returndate, OLD.time, OLD.fee, OLD.dist, OLD.carbon)
           IS NOT DISTINCT FROM
           (NEW.rtpl_id, NEW.retrtpl_id, NEW.bycl_id, NEW.mebr_id, NEW.rentdate, NEW.returndate, NEW.time, NEW.fee, NEW.dist, NEW.carbon) THEN
            RETURN NULL;
        END IF;
        PERFORM fn_rent_summary_apply(OLD, -1);
        PERFORM fn_rent_summary_apply(NEW, 1);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_rent_summary
    AFTER INSERT OR DELETE OR UPDATE OF rtpl_id, retrtpl_id, bycl_id, mebr_id, rentdate, returndate, time, fee, dist, carbon
    ON tblrentT1
    FOR EACH ROW
    EXECUTE FUNCTION fn_rent_summary();


-- 집계 테이블을 대여 테이블에서 처음부터 다시 만든다 (대량 적재 뒤, 검증할 때)
CREATE FUNCTION fn_rebuild_rent_summary() RETURNS void AS $$
BEGIN
    TRUNCATE tblrpmoS1, tblbcmoS1, tblrpwdS1, tblmbrgS1;

    INSERT INTO tblrpmoS1 (rtpl_id, space, ym, rent_cnt, ret_cnt, ret_fee)
    SELECT rtpl_id, space, ym, SUM(rc)::INT, SUM(tc)::INT, SUM(fee)
    FROM (
        SELECT rtpl_id, rtpl_space AS space, rent_ym AS ym, 1 AS rc, 0 AS tc, 0 AS fee FROM tblrentT1
        UNION ALL
        SELECT retrtpl_id, retrtpl_space, return_ym, 0, 1, fee FROM tblrentT1 WHERE retrtpl_id IS NOT NULL AND returndate IS NOT NULL
    ) x
    GROUP BY rtpl_id, space, ym;

    INSERT INTO tblbcmoS1 (bycl_id, ym, rent_cnt, time_sum)
    SELECT bycl_id, rent_ym, COUNT(*), SUM(time) FROM tblrentT1 GROUP BY bycl_id, rent_ym;

    INSERT INTO tblrpwdS1 (rtpl_id, space, dow, slot, rent_cnt, time_sum)
    SELECT rtpl_id, rtpl_space, rent_dow, rent_slot, COUNT(*), SUM(time) FROM tblrentT1 GROUP BY rtpl_id, rtpl_space, rent_dow, rent_slot;

    INSERT INTO tblmbrgS1 (mebr_id, region, use_cnt, time_sum, dist_sum, carbon_sum)
    SELECT mebr_id, region, COUNT(*), SUM(time), SUM(dist), SUM(carbon)
    FROM (
        SELECT mebr_id, SUBSTRING(rtpl_id, 1, 2) AS region, time, dist, carbon FROM tblrentT1
        UNION ALL
        SELECT mebr_id, SUBSTRING(retrtpl_id, 1, 2), time, dist, carbon FROM tblrentT1 WHERE retrtpl_id IS NOT NULL
    ) x
    GROUP BY mebr_id, region;
END;
$$ LANGUAGE plpgsql;
