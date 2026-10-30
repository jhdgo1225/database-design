-- 반정규화 구조(create_ddl.sql) 기준 정보시스템 쿼리.
-- 원본: school/postgresql/postgresql_information_system.sql 의 tbl_ 테이블 쿼리 1~6번
--       (한글 테이블명 초안, 자리표시자 쿼리, 확인용 select * 는 옮기지 않았습니다.)
-- 별칭(AS ...)은 원본과 동일하게 유지해 전/후 결과를 비교할 수 있게 했습니다.
-- [반정규화 영향] 표시가 있는 쿼리만 구조 때문에 달라진 부분이 있습니다.
--
-- [수정 2026-10-30] 학기 비교를 (...)::CHAR(6) 으로 맞춤(정규화 쿼리와 동일). semester 컬럼이 CHAR(6) 인데 text 와 비교하면
--                   컬럼이 (semester)::text 로 변환되어 통계를 쓰지 못한다. 학번 비교(person_id VARCHAR(10) = '…')는 그대로 둔다.
--
-- 테이블 대응: tbl_stud_m1 + tbl_prof_m1 -> tbl_pers_m2 (stud_id/prof_id -> person_id)
--              tbl_subj_m1 + tbl_offe_d1 -> tbl_subj_d2   (기본키 offe_id)
--              tbl_room_l1 제거           -> tbl_sche_d2.room_code (호관 = 앞 2자리, 호실 = 나머지)
--              tbl_sche_d1 -> tbl_sche_d2, tbl_enrl_t1 -> tbl_enrl_t2, tbl_dept_m1 -> tbl_dept_m2

-- 1번: 교수의 이번 학기 강의 요일·교시
-- [반정규화 영향] 교수가 tbl_pers_m2 로 합쳐졌을 뿐 조인 수는 같습니다. (조인 2개 -> 2개)
--                 tbl_subj_d2.prof_id 는 (prof_id, prof_type) 복합 FK 로 교수만 가리킵니다.
SELECT
    p.person_id AS 교수번호,
    p.name      AS 교수명,
    CASE t.weekday
        WHEN 0 THEN '일요일'
        WHEN 1 THEN '월요일'
        WHEN 2 THEN '화요일'
        WHEN 3 THEN '수요일'
        WHEN 4 THEN '목요일'
        WHEN 5 THEN '금요일'
        WHEN 6 THEN '토요일'
    END         AS 강의요일,
    t.period    AS 교시
FROM tbl_pers_m2 AS p
JOIN tbl_subj_d2 AS o
  ON p.person_id = o.prof_id
JOIN tbl_sche_d2 AS t
  ON o.offe_id = t.offe_id
WHERE p.person_id = '200230503'
    AND o.semester = (
    TO_CHAR(CURRENT_DATE, 'YYYY') ||
    CASE
        WHEN EXTRACT(MONTH FROM CURRENT_DATE) BETWEEN 3 AND 8 THEN '01'
        ELSE '02'
    END
)::CHAR(6)
ORDER BY
    t.weekday,
    t.period;

-- 2번: 학생의 이번 학기 시간표
-- [반정규화 영향] 과목명·학기가 tbl_subj_d2 에 있어 개설과목·과목 조인이 하나로 줄고,
--                 강의실 조인은 room_code 로 대체됩니다. (조인 5개 -> 3개)
--                 강의실 = CONCAT(호관, 호실) = room_code 이므로 값이 같습니다.
--                 수강신청이 시간표 한 칸이 아니라 개설과목을 가리키므로 개설과목의 모든 시간표 행이 나옵니다.
SELECT
    s.person_id  AS 학번,
    s.name       AS 학생이름,
    CASE t.weekday
        WHEN 0 THEN '일요일'
        WHEN 1 THEN '월요일'
        WHEN 2 THEN '화요일'
        WHEN 3 THEN '수요일'
        WHEN 4 THEN '목요일'
        WHEN 5 THEN '금요일'
        WHEN 6 THEN '토요일'
    END          AS 강의요일,
    t.period     AS 교시,
    o.name       AS 과목명,
    t.room_code  AS 강의실
FROM tbl_pers_m2 AS s
JOIN tbl_enrl_t2 AS k ON s.person_id = k.stud_id
JOIN tbl_subj_d2 AS o ON k.offe_id   = o.offe_id
JOIN tbl_sche_d2 AS t ON o.offe_id   = t.offe_id
WHERE s.person_id = '2021305050'
 AND o.semester = (
    TO_CHAR(CURRENT_DATE, 'YYYY') ||
    CASE
        WHEN EXTRACT(MONTH FROM CURRENT_DATE) BETWEEN 3 AND 8 THEN '01'
        ELSE '02'
    END
)::CHAR(6)
ORDER BY
    t.weekday,
    t.period;

-- 3번: 이번 학기 강의실별 강의 요일·교시·과목·교수
-- [반정규화 영향] tbl_room_l1 과 과목 조인이 사라지고 호관·호실은 room_code 에서 잘라 냅니다. (조인 4개 -> 2개)
SELECT
    SUBSTRING(t.room_code FROM 1 FOR 2) AS 호관,
    SUBSTRING(t.room_code FROM 3)       AS 강의실,
    CASE t.weekday
        WHEN 0 THEN '일요일'
        WHEN 1 THEN '월요일'
        WHEN 2 THEN '화요일'
        WHEN 3 THEN '수요일'
        WHEN 4 THEN '목요일'
        WHEN 5 THEN '금요일'
        WHEN 6 THEN '토요일'
    END                                 AS 강의요일,
    t.period                            AS 교시,
    o.name                              AS 강의과목명,
    p.name                              AS 강의교수명
FROM tbl_sche_d2 AS t
JOIN tbl_subj_d2 AS o ON t.offe_id = o.offe_id
JOIN tbl_pers_m2 AS p ON o.prof_id = p.person_id
WHERE o.semester = (
    TO_CHAR(CURRENT_DATE, 'YYYY') ||
    CASE
        WHEN EXTRACT(MONTH FROM CURRENT_DATE) BETWEEN 3 AND 8 THEN '01'
        ELSE '02'
    END
)::CHAR(6)
ORDER BY
    t.room_code,
    t.weekday,
    t.period;

-- 4번: 이번 학기 요일별·교수 직급별 출강 인원 수
-- [반정규화 영향] 교수가 tbl_pers_m2 로 합쳐졌을 뿐 조인 수는 같습니다. (조인 2개 -> 2개)
SELECT
    CASE s.weekday
        WHEN 0 THEN '일요일'
        WHEN 1 THEN '월요일'
        WHEN 2 THEN '화요일'
        WHEN 3 THEN '수요일'
        WHEN 4 THEN '목요일'
        WHEN 5 THEN '금요일'
        WHEN 6 THEN '토요일'
    END AS weekday_name,

    CASE p.rank
        WHEN 'P' THEN '정교수'
        WHEN 'S' THEN '부교수'
        WHEN 'L' THEN '조교수'
        WHEN 'T' THEN '시간강사'
    END AS rank_name,

    COUNT(DISTINCT o.prof_id || '-' || s.weekday) AS lecture_count
FROM tbl_sche_d2 s
JOIN tbl_subj_d2 o ON s.offe_id = o.offe_id
JOIN tbl_pers_m2 p ON o.prof_id = p.person_id
WHERE o.semester = (
    TO_CHAR(CURRENT_DATE, 'YYYY') ||
    CASE
        WHEN EXTRACT(MONTH FROM CURRENT_DATE) BETWEEN 3 AND 8 THEN '01'
        ELSE '02'
    END
)::CHAR(6)
GROUP BY s.weekday, p.rank
ORDER BY
    s.weekday,
    CASE p.rank
        WHEN 'P' THEN 1
        WHEN 'S' THEN 2
        WHEN 'L' THEN 3
        WHEN 'T' THEN 4
    END;

-- 5번: 이번 학기 요일별·호관별 예상 수강 학생 수
-- [반정규화 영향] tbl_room_l1 조인이 사라지고 호관은 room_code 앞 2자리로 대체됩니다. (조인 3개 -> 2개)
--                 수강신청이 개설과목을 가리키므로 개설과목의 모든 시간표 행에 학생이 잡힙니다.
SELECT
    CASE s.weekday
        WHEN 0 THEN '일요일'
        WHEN 1 THEN '월요일'
        WHEN 2 THEN '화요일'
        WHEN 3 THEN '수요일'
        WHEN 4 THEN '목요일'
        WHEN 5 THEN '금요일'
        WHEN 6 THEN '토요일'
    END AS weekday_name,

    SUBSTRING(s.room_code FROM 1 FOR 2) AS building_code,

    COUNT(DISTINCT e.stud_id || '-' || s.weekday || '-' || SUBSTRING(s.room_code FROM 1 FOR 2)) AS expected_students

FROM tbl_enrl_t2 e
JOIN tbl_subj_d2 o ON e.offe_id = o.offe_id
JOIN tbl_sche_d2 s ON o.offe_id = s.offe_id

WHERE o.semester = (
    TO_CHAR(CURRENT_DATE, 'YYYY') ||
    CASE
        WHEN EXTRACT(MONTH FROM CURRENT_DATE) BETWEEN 3 AND 8 THEN '01'
        ELSE '02'
    END
)::CHAR(6)

GROUP BY s.weekday, building_code
ORDER BY s.weekday, building_code;

-- 6번: 학과·학년별 학생의 학기 성적 누적 (뷰 + 조회)
-- 이수학기성적 뷰
-- [반정규화 영향] 학생·개설과목·과목 정보가 각각 tbl_pers_m2, tbl_subj_d2 에 있어 시간표·과목 조인이 사라집니다. (조인 4개 -> 2개)
CREATE OR REPLACE VIEW vw_stud_semester_scores AS
SELECT
    base.stud_id,
    base.stud_name,
    base.semester,
    base.applied_credits,
    base.earned_credits,
    base.total_grade_points,

    ROUND(
        CAST(base.total_grade_points / NULLIF(base.applied_credits, 0) AS numeric),
        2
    ) AS average_gpa

FROM (
    SELECT
        s.person_id AS stud_id,
        s.name AS stud_name,
        o.semester,

        -- 신청학점
        SUM(o.score) AS applied_credits,

        -- 취득학점
        SUM(CASE
            WHEN e.grade IS NOT NULL AND e.grade != 'F' THEN o.score
            ELSE 0
        END) AS earned_credits,

        -- 총평점
        SUM(
            CASE e.grade
                WHEN 'A+' THEN 4.5
                WHEN 'A0' THEN 4.0
                WHEN 'B+' THEN 3.5
                WHEN 'B0' THEN 3.0
                WHEN 'C+' THEN 2.5
                WHEN 'C0' THEN 2.0
                WHEN 'D+' THEN 1.5
                WHEN 'D0' THEN 1.0
                WHEN 'F'  THEN 0.0
                ELSE NULL
            END * o.score
        ) AS total_grade_points

    FROM tbl_enrl_t2 e
    JOIN tbl_pers_m2 s ON e.stud_id = s.person_id
    JOIN tbl_subj_d2 o ON e.offe_id = o.offe_id

    GROUP BY s.person_id, s.name, o.semester
) AS base;

---- 6번 문제 SQL문
SELECT   s.person_id   AS 학번,
         s.name        AS 이름,
         d.name        AS 학과,
         s.grade       AS 학년,
         SUM(v.applied_credits)     AS 총신청학점,
         SUM(v.earned_credits)      AS 총취득학점,
         SUM(v.total_grade_points)  AS 총평점,
         ROUND(CAST(SUM(v.total_grade_points) / NULLIF(SUM(v.applied_credits), 0) AS numeric), 2) AS 총평점평균
FROM vw_stud_semester_scores AS v
    JOIN tbl_pers_m2 AS s ON v.stud_id = s.person_id
    JOIN tbl_dept_m2 AS d ON s.dept_id = d.dept_id
WHERE  s.dept_id='401' AND    s.grade=4
GROUP BY s.person_id, s.name, d.name, s.grade
ORDER BY s.person_id;
