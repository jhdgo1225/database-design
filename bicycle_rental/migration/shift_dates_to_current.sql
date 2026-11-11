-- =============================================================================
-- bicycle_rental 데이터 마이그레이션: 시간 데이터를 오늘 기준으로 최신화
--
-- 전제조건: bicycle_rental/postgresql/postgresql_create_ddl.sql + postgresql_insert_data.sql 이
--           이미 적용된 PostgreSQL 데이터베이스 (기존 샘플은 2025-04 ~ 2025-05 기준).
-- 순서:     대량 샘플(postgresql_insert_data_bulk.sql)보다 먼저 실행한다.
--           대량 샘플을 먼저 적재하면 그 데이터가 가장 최근 이벤트가 되어서 기존 샘플은 옮겨지지 않는다.
-- 배경:     기존 샘플의 날짜가 과거에 머물러 있어서, 오늘 기준으로 만든 대량 샘플과 기간이 맞지 않는다.
--
-- 효과:     가장 최근 이벤트 시각(대여, 반납, 보충/수거, 파손/분실 발생, 청구) 이 오늘 0시 이전이면서
--           가장 가깝도록, 시간 데이터 전체를 같은 간격만큼 옮긴다.
--           이동량은 7일의 배수다. 요일이 그대로 유지되고, 시각 사이의 간격(대여 시간 등)도 변하지 않는다.
--           (예: 2026-11-12 실행 시 +525일(75주): 2025-05-30 17:40 -> 2026-11-06 17:40)
--
--   이동 대상 컬럼
--     tblbyclM1.registerdate / installdate   자전거 등록일시 / 설치일시
--     tbltickD1.startdate / enddate          이용권 시작일시 / 종료일시
--     tblrentT1.rentdate / returndate        대여일시 / 반납일시
--     tblspclD1.spcldate                     보충/수거 일시
--     tbldmlsD1.occurdate / claimdate        파손/분실 발생일시 / 청구일시
--     tblmebrM1.birth                        생년월일. 일일권 요금이 이용권 구매일의 만 나이(성인 여부)로 정해지므로
--                                            같은 일수만큼 옮겨서 구매 시점의 나이가 그대로 유지되게 한다.
--   이동하지 않는 컬럼: tblrentT1.time (이용 시간)
--
-- 멱등성:   이동량을 "가장 최근 이벤트와 오늘의 차이"로 계산하므로 같은 주에 다시 실행하면
--           이동량이 0이라 아무 것도 바꾸지 않는다. (일주일이 지나면 다시 7일 단위로 이동)
--
-- 주의:     * 이용권 종료일처럼 미래 날짜는 같은 간격으로 함께 이동하므로 오늘을 넘을 수 있다.
--           * 이동량이 0 이하(가장 최근 이벤트가 이미 오늘 직전 일주일 안이거나 오늘 이후)이면 건너뛴다.
--           * 키가 날짜를 포함하지 않아서 PK 갱신은 없다.
-- =============================================================================

BEGIN;

DO $$
DECLARE
    v_latest  TIMESTAMP;
    v_days    INT;   -- 이동할 일수 (7의 배수)
    v_future  INT;
BEGIN
    SELECT MAX(t) INTO v_latest
    FROM (SELECT MAX(rentdate)   AS t FROM tblrentT1
          UNION ALL SELECT MAX(returndate) FROM tblrentT1
          UNION ALL SELECT MAX(spcldate)   FROM tblspclD1
          UNION ALL SELECT MAX(occurdate)  FROM tbldmlsD1
          UNION ALL SELECT MAX(claimdate)  FROM tbldmlsD1) x;

    IF v_latest IS NULL THEN
        RAISE NOTICE '이벤트 데이터가 없어 이동할 기준이 없습니다. 건너뜁니다.';
        RETURN;
    END IF;

    -- 가장 최근 이벤트가 오늘 0시 이전에 놓이는 최대의 7일 배수
    v_days := (CURRENT_DATE - v_latest::DATE) / 7 * 7;
    IF v_latest::DATE + v_days >= CURRENT_DATE THEN
        v_days := v_days - 7;
    END IF;

    IF v_days <= 0 THEN
        RAISE NOTICE '가장 최근 이벤트(%)가 이미 오늘(%) 기준입니다. 변경 없음.', v_latest, CURRENT_DATE;
        RETURN;
    END IF;

    RAISE NOTICE '가장 최근 이벤트 % -> 오늘 %: % 일(% 주) 이동', v_latest, CURRENT_DATE, v_days, v_days / 7;

    UPDATE tblbyclM1 SET registerdate = registerdate + make_interval(days => v_days),
                         installdate  = installdate  + make_interval(days => v_days);
    UPDATE tbltickD1 SET startdate = startdate + make_interval(days => v_days),
                         enddate   = enddate   + make_interval(days => v_days);
    UPDATE tblrentT1 SET rentdate   = rentdate   + make_interval(days => v_days),
                         returndate = returndate + make_interval(days => v_days);
    UPDATE tblspclD1 SET spcldate = spcldate + make_interval(days => v_days);
    UPDATE tbldmlsD1 SET occurdate = occurdate + make_interval(days => v_days),
                         claimdate = claimdate + make_interval(days => v_days);
    UPDATE tblmebrM1 SET birth = birth + v_days;

    -- 사후 검증: 이벤트가 오늘 0시를 넘지 않아야 한다. (이용권 종료일 등 미래 날짜는 제외)
    SELECT COUNT(*) INTO v_future
    FROM (SELECT rentdate AS t FROM tblrentT1 UNION ALL SELECT returndate FROM tblrentT1
          UNION ALL SELECT spcldate FROM tblspclD1 UNION ALL SELECT occurdate FROM tbldmlsD1
          UNION ALL SELECT claimdate FROM tbldmlsD1) x
    WHERE t >= CURRENT_DATE;
    IF v_future > 0 THEN
        RAISE EXCEPTION '이동 후에도 오늘 이후의 이벤트가 % 건 있습니다.', v_future;
    END IF;
END
$$;

COMMIT;

-- 결과 확인용
SELECT 'tblbyclM1.registerdate' AS col, MIN(registerdate)::TEXT AS min_value, MAX(registerdate)::TEXT AS max_value FROM tblbyclM1
UNION ALL SELECT 'tblbyclM1.installdate', MIN(installdate)::TEXT, MAX(installdate)::TEXT FROM tblbyclM1
UNION ALL SELECT 'tbltickD1.startdate',   MIN(startdate)::TEXT,   MAX(startdate)::TEXT   FROM tbltickD1
UNION ALL SELECT 'tbltickD1.enddate',     MIN(enddate)::TEXT,     MAX(enddate)::TEXT     FROM tbltickD1
UNION ALL SELECT 'tblrentT1.rentdate',    MIN(rentdate)::TEXT,    MAX(rentdate)::TEXT    FROM tblrentT1
UNION ALL SELECT 'tblrentT1.returndate',  MIN(returndate)::TEXT,  MAX(returndate)::TEXT  FROM tblrentT1
UNION ALL SELECT 'tblspclD1.spcldate',    MIN(spcldate)::TEXT,    MAX(spcldate)::TEXT    FROM tblspclD1
UNION ALL SELECT 'tbldmlsD1.occurdate',   MIN(occurdate)::TEXT,   MAX(occurdate)::TEXT   FROM tbldmlsD1
UNION ALL SELECT 'tbldmlsD1.claimdate',   MIN(claimdate)::TEXT,   MAX(claimdate)::TEXT   FROM tbldmlsD1;
