-- =============================================================================
-- cinema 데이터 마이그레이션: 시간 데이터를 현재 월 기준으로 최신화
--
-- 전제조건: cinema/postgresql/postgresql_create_ddl.sql + postgresql_insert_data.sql 이
--           이미 적용된 PostgreSQL 데이터베이스 (샘플 데이터는 2025-04 기준)
-- 배경:     information_system 쿼리 4·5·6·8·9번은 CURRENT_DATE 로 "이번 달"을 계산하므로,
--           샘플 데이터가 과거(2025-04)에 머물러 있으면 결과가 0행이 되어 측정이 무의미해집니다.
-- 효과:     가장 최근 상영일(MAX(tbl_scrn_m1.scrndate))이 속한 달 → CURRENT_DATE 가 속한 달
--           까지의 개월 수 차이만큼, 시간 데이터 전체를 같은 간격으로 이동합니다.
--           (예: 2026-10-29 실행 시 +18개월: 2025-04-10 → 2026-10-10)
--
--   이동 대상 컬럼
--     tbl_scmv_m1.startdate / enddate    개봉일 / 종영일
--     tbl_scmv_m1.scmv_id                'YYYYMMDD' + 일련번호 (개봉일이 PK 앞 8자리에 포함)
--     tbl_scrn_m1.scrndate               상영일자
--     tbl_scrn_m1.scrn_id                'YYYYMMDD' + 상영관/회차 (상영일이 PK 앞 8자리에 포함)
--     tbl_bytk_d1.buydate                예매일시
--     tbl_chrg_d1.chargedate             충전일시
--   이동하지 않는 컬럼: tbl_mebr_m1.birth, tbl_mngr_m1.birth (생년월일은 시점과 무관)
--
-- 전략:     PK(scmv_id, scrn_id)가 날짜를 포함하므로 날짜만 바꾸면 PK 와 날짜가 어긋납니다.
--           두 PK 를 참조하는 FK 는 모두 ON UPDATE CASCADE 이므로
--           (tbl_scrn_m1.scmv_id, tbl_part_d1.scmv_id, tbl_like_d1.scmv_id, tbl_bytk_d1.scrn_id)
--           부모 테이블의 PK 만 갱신하면 자식 행은 자동으로 따라옵니다.
--
-- 멱등성:   이동량을 "현재 데이터와 현재 날짜의 차이"로 계산하므로 같은 달에 다시 실행하면
--           이동량이 0 이라 아무 것도 바꾸지 않습니다. (다음 달에 실행하면 다시 1개월 이동)
--
-- 주의:     * 이동량이 데이터 기간(약 5주)보다 작으면 새 PK 가 아직 이동되지 않은 기존 PK 와
--             충돌할 수 있습니다. 이 경우 unique 위반으로 트랜잭션 전체가 롤백됩니다.
--           * 월말(29~31일) 데이터를 일수가 적은 달로 옮기면 서로 다른 날짜가 같은 날로 합쳐져
--             PK 가 충돌할 수 있습니다. 이때도 동일하게 롤백되며 데이터는 변하지 않습니다.
-- =============================================================================

BEGIN;

DO $$
DECLARE
    v_latest    DATE;
    v_shift     INT;   -- 이동할 개월 수 (음수면 과거로 이동)
    v_bad_scrn  INT;
    v_bad_scmv  INT;
BEGIN
    SELECT MAX(scrndate) INTO v_latest FROM tbl_scrn_m1;

    IF v_latest IS NULL THEN
        RAISE NOTICE 'tbl_scrn_m1 이 비어 있어 이동할 기준이 없습니다. 건너뜁니다.';
        RETURN;
    END IF;

    v_shift := (EXTRACT(YEAR  FROM CURRENT_DATE)::INT * 12 + EXTRACT(MONTH FROM CURRENT_DATE)::INT)
             - (EXTRACT(YEAR  FROM v_latest)::INT      * 12 + EXTRACT(MONTH FROM v_latest)::INT);

    IF v_shift = 0 THEN
        RAISE NOTICE '이미 현재 월(%) 기준 데이터입니다. 변경 없음.', TO_CHAR(CURRENT_DATE, 'YYYY-MM');
        RETURN;
    END IF;

    RAISE NOTICE '최신 상영일 % → 현재 월 %: % 개월 이동', v_latest, TO_CHAR(CURRENT_DATE, 'YYYY-MM'), v_shift;

    -- 1) 영화: 개봉일/종영일 + PK 의 날짜 부분. scmv_id 변경은 scrn/part/like 로 CASCADE.
    UPDATE tbl_scmv_m1
    SET startdate = (startdate + MAKE_INTERVAL(months => v_shift))::DATE,
        enddate   = (enddate   + MAKE_INTERVAL(months => v_shift))::DATE,
        scmv_id   = TO_CHAR(startdate + MAKE_INTERVAL(months => v_shift), 'YYYYMMDD') || SUBSTR(scmv_id, 9);

    -- 2) 상영: 상영일자 + PK 의 날짜 부분. scrn_id 변경은 bytk 로 CASCADE.
    UPDATE tbl_scrn_m1
    SET scrndate = (scrndate + MAKE_INTERVAL(months => v_shift))::DATE,
        scrn_id  = TO_CHAR(scrndate + MAKE_INTERVAL(months => v_shift), 'YYYYMMDD') || SUBSTR(scrn_id, 9);

    -- 3) 예매 / 충전 이력
    UPDATE tbl_bytk_d1 SET buydate    = buydate    + MAKE_INTERVAL(months => v_shift);
    UPDATE tbl_chrg_d1 SET chargedate = chargedate + MAKE_INTERVAL(months => v_shift);

    -- 4) 사후 검증: PK 앞 8자리가 날짜 컬럼과 일치해야 하고, 최신 상영일이 현재 월이어야 합니다.
    SELECT COUNT(*) INTO v_bad_scrn FROM tbl_scrn_m1 WHERE LEFT(scrn_id, 8) <> TO_CHAR(scrndate,  'YYYYMMDD');
    SELECT COUNT(*) INTO v_bad_scmv FROM tbl_scmv_m1 WHERE LEFT(scmv_id, 8) <> TO_CHAR(startdate, 'YYYYMMDD');

    IF v_bad_scrn > 0 OR v_bad_scmv > 0 THEN
        RAISE EXCEPTION 'PK 날짜 불일치: scrn % 건, scmv % 건', v_bad_scrn, v_bad_scmv;
    END IF;

    IF (SELECT DATE_TRUNC('month', MAX(scrndate)) FROM tbl_scrn_m1) <> DATE_TRUNC('month', CURRENT_DATE) THEN
        RAISE EXCEPTION '이동 후에도 최신 상영일이 현재 월이 아닙니다.';
    END IF;
END
$$;

COMMIT;

-- 결과 확인용
SELECT 'tbl_scmv_m1.startdate' AS col, MIN(startdate)::TEXT AS min_value, MAX(startdate)::TEXT AS max_value FROM tbl_scmv_m1
UNION ALL SELECT 'tbl_scrn_m1.scrndate',  MIN(scrndate)::TEXT,  MAX(scrndate)::TEXT  FROM tbl_scrn_m1
UNION ALL SELECT 'tbl_bytk_d1.buydate',   MIN(buydate)::TEXT,   MAX(buydate)::TEXT   FROM tbl_bytk_d1
UNION ALL SELECT 'tbl_chrg_d1.chargedate', MIN(chargedate)::TEXT, MAX(chargedate)::TEXT FROM tbl_chrg_d1;
