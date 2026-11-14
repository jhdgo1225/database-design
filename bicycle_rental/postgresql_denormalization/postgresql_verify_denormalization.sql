-- 반정규화로 더한 열과 집계 테이블이 대여 테이블과 맞는지 검증한다. 규칙마다 어긋난 행 수를 보여주고, 모두 0이어야 한다.

SELECT no, check_name, violations FROM (

          SELECT 1 AS no, '대여 대여소 이름(rtpl_space)이 대여소 테이블의 이름과 다름' AS check_name, COUNT(*) AS violations
FROM tblrentT1 r JOIN tblrtplM1 p ON p.rtpl_id = r.rtpl_id WHERE r.rtpl_space <> p.space
UNION ALL SELECT 2, '반납 대여소 이름(retrtpl_space)이 대여소 테이블의 이름과 다름', COUNT(*)
FROM tblrentT1 r JOIN tblrtplM1 p ON p.rtpl_id = r.retrtpl_id WHERE r.retrtpl_space <> p.space
UNION ALL SELECT 3, '반납 대여소(retrtpl_id)와 반납일시(returndate) 중 한쪽만 NULL (쿼리 4의 전제)', COUNT(*)
FROM tblrentT1 WHERE (retrtpl_id IS NULL) <> (returndate IS NULL)

UNION ALL SELECT 4, '대여 년월·요일·시간대(rent_ym, rent_dow, rent_slot)가 대여일시에서 계산한 값과 다름', COUNT(*)
FROM tblrentT1
WHERE rent_ym <> TO_DATE(TO_CHAR(rentdate, 'YYYY-MM') || '-01', 'YYYY-MM-DD')
   OR rent_dow <> EXTRACT(DOW FROM rentdate)
   OR rent_slot <> CASE WHEN EXTRACT(HOUR FROM rentdate) < 5 THEN 1
                        WHEN EXTRACT(HOUR FROM rentdate) < 12 THEN 2
                        WHEN EXTRACT(HOUR FROM rentdate) < 18 THEN 3 ELSE 4 END
UNION ALL SELECT 5, '반납 년월(return_ym)이 반납일시에서 계산한 값과 다르거나, 반납일시가 없는데 값이 있음', COUNT(*)
FROM tblrentT1
WHERE (returndate IS NULL) <> (return_ym IS NULL)
   OR return_ym <> TO_DATE(TO_CHAR(returndate, 'YYYY-MM') || '-01', 'YYYY-MM-DD')

-- 집계 테이블은 대여 테이블에서 다시 계산한 값과 행 단위로 비교한다
UNION ALL SELECT 6, '대여소×월(tblrpmoS1)이 대여 테이블에서 다시 계산한 값과 다름', COUNT(*)
FROM (
    SELECT rtpl_id, space, ym, SUM(rc)::INT AS rent_cnt, SUM(tc)::INT AS ret_cnt, SUM(fee) AS ret_fee
    FROM (
        SELECT rtpl_id, rtpl_space AS space, rent_ym AS ym, 1 AS rc, 0 AS tc, 0 AS fee FROM tblrentT1
        UNION ALL
        SELECT retrtpl_id, retrtpl_space, return_ym, 0, 1, fee FROM tblrentT1 WHERE retrtpl_id IS NOT NULL AND returndate IS NOT NULL
    ) x GROUP BY rtpl_id, space, ym
) a FULL JOIN tblrpmoS1 s ON s.rtpl_id = a.rtpl_id AND s.ym = a.ym
WHERE a.rtpl_id IS NULL OR s.rtpl_id IS NULL
   OR (a.space, a.rent_cnt, a.ret_cnt, a.ret_fee) IS DISTINCT FROM (s.space, s.rent_cnt, s.ret_cnt, s.ret_fee)
UNION ALL SELECT 7, '자전거×월(tblbcmoS1)이 대여 테이블에서 다시 계산한 값과 다름', COUNT(*)
FROM (SELECT bycl_id, rent_ym AS ym, COUNT(*)::INT AS rent_cnt, SUM(time) AS time_sum FROM tblrentT1 GROUP BY bycl_id, rent_ym) a
FULL JOIN tblbcmoS1 s ON s.bycl_id = a.bycl_id AND s.ym = a.ym
WHERE a.bycl_id IS NULL OR s.bycl_id IS NULL
   OR (a.rent_cnt, a.time_sum) IS DISTINCT FROM (s.rent_cnt, s.time_sum)
UNION ALL SELECT 8, '대여소×요일×시간대(tblrpwdS1)가 대여 테이블에서 다시 계산한 값과 다름', COUNT(*)
FROM (SELECT rtpl_id, rtpl_space AS space, rent_dow AS dow, rent_slot AS slot, COUNT(*)::INT AS rent_cnt, SUM(time) AS time_sum
      FROM tblrentT1 GROUP BY rtpl_id, rtpl_space, rent_dow, rent_slot) a
FULL JOIN tblrpwdS1 s ON s.rtpl_id = a.rtpl_id AND s.dow = a.dow AND s.slot = a.slot
WHERE a.rtpl_id IS NULL OR s.rtpl_id IS NULL
   OR (a.space, a.rent_cnt, a.time_sum) IS DISTINCT FROM (s.space, s.rent_cnt, s.time_sum)
UNION ALL SELECT 9, '회원×구(tblmbrgS1)가 대여 테이블에서 다시 계산한 값과 다름', COUNT(*)
FROM (
    SELECT mebr_id, region, COUNT(*)::INT AS use_cnt, SUM(time) AS time_sum, SUM(dist) AS dist_sum, SUM(carbon) AS carbon_sum
    FROM (
        SELECT mebr_id, SUBSTRING(rtpl_id, 1, 2) AS region, time, dist, carbon FROM tblrentT1
        UNION ALL
        SELECT mebr_id, SUBSTRING(retrtpl_id, 1, 2), time, dist, carbon FROM tblrentT1 WHERE retrtpl_id IS NOT NULL
    ) x GROUP BY mebr_id, region
) a FULL JOIN tblmbrgS1 s ON s.mebr_id = a.mebr_id AND s.region = a.region
WHERE a.mebr_id IS NULL OR s.mebr_id IS NULL
   OR (a.use_cnt, a.time_sum, a.dist_sum, a.carbon_sum) IS DISTINCT FROM (s.use_cnt, s.time_sum, s.dist_sum, s.carbon_sum)

UNION ALL SELECT 10, '집계 테이블에 개수가 0인 행이 남아 있음', COUNT(*) FROM (
    SELECT 1 FROM tblrpmoS1 WHERE rent_cnt = 0 AND ret_cnt = 0
    UNION ALL SELECT 1 FROM tblbcmoS1 WHERE rent_cnt = 0
    UNION ALL SELECT 1 FROM tblrpwdS1 WHERE rent_cnt = 0
    UNION ALL SELECT 1 FROM tblmbrgS1 WHERE use_cnt = 0
) z
) q
ORDER BY no;
