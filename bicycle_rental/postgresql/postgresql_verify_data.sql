-- 데이터 규칙 검증. 기존 샘플(postgresql_insert_data.sql)과 대량 샘플(postgresql_insert_data_bulk.sql)에 모두 쓴다.
-- 규칙마다 위반한 행 수를 한 줄씩 보여주고, 모두 0이어야 한다.
-- 날짜를 옮긴 뒤(migration/shift_dates_to_current.sql)에도 같은 결과여야 한다.

WITH
-- 자전거 이벤트: 대여(시작/반납 대여소), 보충(SP, 둔 대여소), 수거(CL, 수거한 대여소)
ev AS (
    SELECT bycl_id, rentdate AS ts, COALESCE(returndate, rentdate) AS end_ts, 'RENT' AS kind,
           rtpl_id AS st_in, retrtpl_id AS st_out, (returndate IS NULL) AS is_open
    FROM tblrentT1
    UNION ALL
    SELECT bycl_id, spcldate, spcldate, spclgubun,
           CASE WHEN spclgubun = 'CL' THEN rtpl_id END,
           CASE WHEN spclgubun = 'SP' THEN rtpl_id END,
           FALSE
    FROM tblspclD1
),
seq AS (
    SELECT ev.*,
           LAG(kind)    OVER w AS pkind,
           LAG(st_out)  OVER w AS pout,
           LAG(end_ts)  OVER w AS pend,
           LAG(is_open) OVER w AS popen
    FROM ev
    WINDOW w AS (PARTITION BY bycl_id ORDER BY ts, end_ts)
),
last_ev AS (
    SELECT DISTINCT ON (bycl_id) bycl_id, kind, st_out, is_open
    FROM ev ORDER BY bycl_id, ts DESC, end_ts DESC
),
-- 정기권(PRE 제외)과 일일권
tk AS (
    SELECT t.*, (ticket NOT LIKE 'PRE%') AS periodic FROM tbltickD1 t
),
-- 일일권으로 한 대여: 일일권 시간 안의 첫 대여. 1시간당 성인 1,000원, 성인이 아닌 회원 800원 (이용권 구매일 기준 만 19세 이상이 성인)
pre AS (
    SELECT DISTINCT ON (t.tick_id) t.tick_id, r.rent_id, t.points, t.usehour,
           EXTRACT(YEAR FROM AGE(t.startdate::DATE, m.birth)) >= 19 AS adult
    FROM tbltickD1 t
    JOIN tblmebrM1 m ON m.mebr_id = t.mebr_id
    JOIN tblrentT1 r ON r.mebr_id = t.mebr_id AND r.rentdate >= t.startdate AND r.rentdate < t.enddate
    WHERE t.ticket LIKE 'PRE%'
    ORDER BY t.tick_id, r.rentdate
),
-- 요금 계산 기준: 정기권이 유효한 시간(tick_id), 일일권으로 한 대여(pre_*)
rent_t AS (
    SELECT r.rent_id, r.mebr_id, r.fee, r.time, r.rentdate, r.fixhour AS rent_hour,
           EXTRACT(EPOCH FROM r.time) / 60 AS dur,
           t.tick_id, t.price, t.points, t.usehour,
           ROW_NUMBER() OVER (PARTITION BY t.tick_id ORDER BY r.rentdate) AS nth_in_ticket,
           EXTRACT(YEAR FROM AGE(r.rentdate::DATE, m.birth)) >= 19 AS adult,
           p.rent_id IS NOT NULL AS is_pre,
           p.points AS pre_points, p.usehour AS pre_hour, p.adult AS pre_adult
    FROM tblrentT1 r
    JOIN tblmebrM1 m ON m.mebr_id = r.mebr_id
    LEFT JOIN tk t ON t.periodic AND t.mebr_id = r.mebr_id AND r.rentdate >= t.startdate AND r.rentdate < t.enddate
    LEFT JOIN pre p ON p.rent_id = r.rent_id
)
SELECT check_name, violations FROM (

-- 회원
SELECT 1 AS no, 'totalrental = 회원의 대여 건수' AS check_name, COUNT(*) AS violations
FROM tblmebrM1 m WHERE m.totalrental <> (SELECT COUNT(*) FROM tblrentT1 r WHERE r.mebr_id = m.mebr_id)

-- 대여
UNION ALL SELECT 2, '반납 완료 대여는 반납 대여소와 반납일시가 있고, 미반납은 둘 다 없다', COUNT(*)
FROM tblrentT1 WHERE (returndate IS NULL) <> (retrtpl_id IS NULL)
UNION ALL SELECT 3, '반납 완료 대여의 time = 반납일시 - 대여일시', COUNT(*)
FROM tblrentT1 WHERE returndate IS NOT NULL AND returndate - rentdate <> time
UNION ALL SELECT 4, '속도: 15분 이하 시속 36km, 그보다 길면 시속 25km 이내', COUNT(*)
FROM tblrentT1
WHERE dist / (EXTRACT(EPOCH FROM time) / 3600.0) > CASE WHEN EXTRACT(EPOCH FROM time) <= 900 THEN 36 ELSE 25 END
UNION ALL SELECT 5, '같은 자전거의 대여가 시간상 겹침', COUNT(*)
FROM seq WHERE pend IS NOT NULL AND ts < pend
UNION ALL SELECT 6, '같은 회원의 대여가 시간상 겹침', COUNT(*)
FROM (SELECT rentdate, LAG(COALESCE(returndate, rentdate)) OVER (PARTITION BY mebr_id ORDER BY rentdate) AS pend FROM tblrentT1) x
WHERE pend IS NOT NULL AND rentdate < pend

-- 자전거 상태와 거치대
UNION ALL SELECT 7, '미반납 대여가 있는 자전거는 ING 또는 LST, 그 반대도 같다', COUNT(*)
FROM tblbyclM1 b
WHERE (b.status IN ('ING', 'LST')) <> EXISTS (SELECT 1 FROM tblrentT1 r WHERE r.bycl_id = b.bycl_id AND r.returndate IS NULL)
UNION ALL SELECT 8, 'AVL 자전거는 거치대에 있고, PD/ING/LST/COL/RP 자전거는 거치대에 없다', COUNT(*)
FROM tblbyclM1 b
WHERE (b.status = 'AVL' AND NOT EXISTS (SELECT 1 FROM tblrackD1 k WHERE k.bycl_id = b.bycl_id))
   OR (b.status IN ('PD', 'ING', 'LST', 'COL', 'RP') AND EXISTS (SELECT 1 FROM tblrackD1 k WHERE k.bycl_id = b.bycl_id))
UNION ALL SELECT 9, '거치대의 자전거와 거치대의 gubun이 같고, 고장 난 거치대에는 자전거가 없다', COUNT(*)
FROM tblrackD1 k LEFT JOIN tblbyclM1 b ON b.bycl_id = k.bycl_id
WHERE (k.bycl_id IS NOT NULL AND (k.gubun <> b.gubun OR k.status <> 'AVL'))
UNION ALL SELECT 10, '대여소 avail = 거치대에 있는 AVL 자전거 수', COUNT(*)
FROM tblrtplM1 p
WHERE p.avail <> (SELECT COUNT(*) FROM tblrackD1 k JOIN tblbyclM1 b ON b.bycl_id = k.bycl_id
                  WHERE k.rtpl_id = p.rtpl_id AND b.status = 'AVL')

-- 이벤트 흐름 (대여 연속성)
UNION ALL SELECT 11, '미반납 대여 뒤에 다른 이벤트가 있음', COUNT(*)
FROM seq WHERE popen
UNION ALL SELECT 12, '대여/수거 대여소가 직전 위치(이전 반납 대여소 또는 보충 대여소)와 다름', COUNT(*)
FROM seq WHERE st_in IS NOT NULL AND pkind IS NOT NULL AND pkind <> 'CL' AND pout IS DISTINCT FROM st_in
UNION ALL SELECT 13, '수거(CL) 뒤에 보충(SP) 없이 대여 또는 수거', COUNT(*)
FROM seq WHERE st_in IS NOT NULL AND pkind = 'CL'
UNION ALL SELECT 14, '상태 COL/RP인데 마지막 이벤트가 수거(CL)가 아님', COUNT(*)
FROM tblbyclM1 b LEFT JOIN last_ev l ON l.bycl_id = b.bycl_id
WHERE b.status IN ('COL', 'RP') AND l.kind IS DISTINCT FROM 'CL'
UNION ALL SELECT 15, '마지막 이벤트가 수거(CL)인데 거치대에 있음', COUNT(*)
FROM last_ev l JOIN tblrackD1 k ON k.bycl_id = l.bycl_id WHERE l.kind = 'CL'
UNION ALL SELECT 16, '거치된 자전거의 거치대 대여소가 마지막 위치와 다름', COUNT(*)
FROM last_ev l JOIN tblrackD1 k ON k.bycl_id = l.bycl_id WHERE l.kind IN ('RENT', 'SP') AND l.st_out IS DISTINCT FROM k.rtpl_id
UNION ALL SELECT 17, '설치일시 이전의 이벤트, 또는 PD 자전거의 이벤트', COUNT(*)
FROM ev e JOIN tblbyclM1 b ON b.bycl_id = e.bycl_id WHERE b.installdate IS NULL OR e.ts < b.installdate
UNION ALL SELECT 18, '설치일시 < 등록일시', COUNT(*)
FROM tblbyclM1 WHERE installdate < registerdate
UNION ALL SELECT 19, '현재보다 뒤의 대여/반납/보충/수거/파손/청구 일시', COUNT(*)
FROM (SELECT rentdate AS t FROM tblrentT1 UNION ALL SELECT returndate FROM tblrentT1
      UNION ALL SELECT spcldate FROM tblspclD1 UNION ALL SELECT occurdate FROM tbldmlsD1
      UNION ALL SELECT claimdate FROM tbldmlsD1) x WHERE t > CURRENT_TIMESTAMP

-- 파손/분실
UNION ALL SELECT 20, '파손/분실의 자전거, 회원이 대여와 다름', COUNT(*)
FROM tbldmlsD1 d JOIN tblrentT1 r ON r.rent_id = d.rent_id WHERE d.bycl_id <> r.bycl_id OR d.mebr_id <> r.mebr_id
UNION ALL SELECT 21, '파손/분실 발생일시가 대여 시간 밖', COUNT(*)
FROM tbldmlsD1 d JOIN tblrentT1 r ON r.rent_id = d.rent_id WHERE d.occurdate < r.rentdate OR d.occurdate > r.rentdate + r.time
UNION ALL SELECT 22, '책임(liable Y)이면 금액과 청구일시가 있고, 아니면 둘 다 없다', COUNT(*)
FROM tbldmlsD1 WHERE (liable = 'Y') <> (amount IS NOT NULL) OR (liable = 'Y') <> (claimdate IS NOT NULL)
UNION ALL SELECT 23, '청구일시가 발생일시보다 빠르거나 같음, 또는 확정(confirm Y)인데 책임(liable Y)이 아님', COUNT(*)
FROM tbldmlsD1 WHERE claimdate <= occurdate OR (confirm = 'Y' AND liable <> 'Y')
UNION ALL SELECT 24, '확정된 분실(LS, confirm Y)이 미반납 대여 + LST 자전거와 연결되지 않음', COUNT(*)
FROM tbldmlsD1 d JOIN tblrentT1 r ON r.rent_id = d.rent_id JOIN tblbyclM1 b ON b.bycl_id = d.bycl_id
WHERE d.dmlsflag = 'LS' AND d.confirm = 'Y' AND (r.returndate IS NOT NULL OR b.status <> 'LST')
UNION ALL SELECT 25, 'LST 자전거에 확정된 분실이 없음', COUNT(*)
FROM tblbyclM1 b WHERE b.status = 'LST'
  AND NOT EXISTS (SELECT 1 FROM tbldmlsD1 d WHERE d.bycl_id = b.bycl_id AND d.dmlsflag = 'LS' AND d.confirm = 'Y')

-- 보충/수거
UNION ALL SELECT 26, '수거 사유(collectreason)는 수거(CL)일 때만 있음', COUNT(*)
FROM tblspclD1 WHERE (spclgubun = 'CL') <> (collectreason IS NOT NULL)

-- 이용권과 요금
UNION ALL SELECT 27, '이용권 종료일 != 시작일 + 기간(정기권) 또는 이용 시간(일일권)', COUNT(*)
FROM tbltickD1
WHERE (ticket NOT LIKE 'PRE%' AND enddate <> startdate + make_interval(days => periodday))
   OR (ticket LIKE 'PRE%' AND enddate <> startdate + make_interval(hours => usehour))
UNION ALL SELECT 28, '같은 회원의 정기권 유효 기간이 겹침', COUNT(*)
FROM (SELECT startdate, LAG(enddate) OVER (PARTITION BY mebr_id ORDER BY startdate) AS pend
      FROM tbltickD1 WHERE ticket NOT LIKE 'PRE%') x WHERE pend IS NOT NULL AND startdate < pend
UNION ALL SELECT 29, '정기권도 일일권도 없는 대여의 요금이 고정 시간 선불(1시간당 성인 1,000원, 성인이 아닌 회원 800원) + 초과분(10분마다 성인 300원, 성인이 아닌 회원 200원)과 다름', COUNT(*)
FROM rent_t WHERE tick_id IS NULL AND NOT is_pre
  AND fee <> rent_hour * CASE WHEN adult THEN 1000 ELSE 800 END
             + CASE WHEN adult THEN 300 ELSE 200 END * GREATEST(0, CEIL((dur - 60 * rent_hour) / 10.0))::INT
UNION ALL SELECT 30, '정기권 구매 후 첫 대여의 요금이 이용권 금액 - 마일리지(+초과분)와 다름', COUNT(*)
FROM rent_t WHERE tick_id IS NOT NULL AND nth_in_ticket = 1
  AND fee <> price - points + CASE WHEN adult THEN 300 ELSE 200 END * GREATEST(0, CEIL((dur - 60 * usehour) / 10.0))::INT
UNION ALL SELECT 31, '정기권 유효 중 대여의 요금이 초과분(10분마다 성인 300원, 성인이 아닌 회원 200원)과 다름', COUNT(*)
FROM rent_t WHERE tick_id IS NOT NULL AND nth_in_ticket > 1
  AND fee <> CASE WHEN adult THEN 300 ELSE 200 END * GREATEST(0, CEIL((dur - 60 * usehour) / 10.0))::INT
UNION ALL SELECT 32, '일일권 대여의 요금이 이용권 금액 - 마일리지 + 초과분(10분마다 성인 300원, 성인이 아닌 회원 200원)과 다름', COUNT(*)
FROM rent_t WHERE tick_id IS NULL AND is_pre
  AND fee <> pre_hour * CASE WHEN pre_adult THEN 1000 ELSE 800 END - pre_points
             + CASE WHEN pre_adult THEN 300 ELSE 200 END * GREATEST(0, CEIL((dur - 60 * pre_hour) / 10.0))::INT
UNION ALL SELECT 34, '이용권이 있는 대여의 고정 대여 시간(tblrentT1.fixhour)이 이용권의 이용 시간(usehour)과 다름', COUNT(*)
FROM rent_t WHERE (tick_id IS NOT NULL AND rent_hour <> usehour) OR (tick_id IS NULL AND is_pre AND rent_hour <> pre_hour)
UNION ALL SELECT 33, '일일권의 사용 마일리지가 일일권 금액보다 큼', COUNT(*)
FROM tbltickD1 t JOIN tblmebrM1 m ON m.mebr_id = t.mebr_id
WHERE t.ticket LIKE 'PRE%'
  AND t.points > t.usehour * CASE WHEN EXTRACT(YEAR FROM AGE(t.startdate::DATE, m.birth)) >= 19 THEN 1000 ELSE 800 END
) q
ORDER BY no;
