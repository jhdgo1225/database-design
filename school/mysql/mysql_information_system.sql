-- 1번
SELECT
    p.prof_id      AS 교수번호,
    p.name        AS 교수명,
    CASE t.weekday
        WHEN 0 THEN '일요일'
        WHEN 1 THEN '월요일'
        WHEN 2 THEN '화요일'
        WHEN 3 THEN '수요일'
        WHEN 4 THEN '목요일'
        WHEN 5 THEN '금요일'
        WHEN 6 THEN '토요일'
    END          AS 강의요일,
    t.period        AS 교시
FROM tbl_prof_m1         AS p
JOIN tbl_offe_d1      AS o
  ON p.prof_id = o.prof_id
JOIN tbl_sche_d1     AS t
  ON o.offe_id = t.offe_id
WHERE p.prof_id = '200230503'
    AND o.semester = CONCAT(
        YEAR(CURDATE()),
        CASE
            WHEN MONTH(CURDATE()) BETWEEN 3 AND 8 THEN '01'
            ELSE '02'
        END
    )
ORDER BY
    t.weekday,
    t.period;

-- 2번
SELECT
    s.stud_id       AS 학번,
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
    t.period       AS 교시,
    c.name     AS 과목명,
    CONCAT(r.building, r.roomno) AS 강의실
FROM tbl_stud_m1      AS s
JOIN tbl_enrl_t1      AS k ON s.stud_id = k.stud_id
JOIN tbl_sche_d1 AS t ON k.sche_id   = t.sche_id
JOIN tbl_offe_d1   AS o ON t.offe_id = o.offe_id
JOIN tbl_subj_m1      AS c ON o.subj_id = c.subj_id
JOIN tbl_room_l1     AS r ON t.room_id = r.room_id
WHERE s.stud_id = '2021305050'
 AND o.semester = CONCAT(
        YEAR(CURDATE()),
        CASE
            WHEN MONTH(CURDATE()) BETWEEN 3 AND 8 THEN '01'
            ELSE '02'
        END
    )
ORDER BY
    t.weekday,
    t.period;

-- 3번
SELECT
    r.building               AS 호관,
    r.roomno             AS 강의실,
    CASE t.weekday
        WHEN 0 THEN '일요일'
        WHEN 1 THEN '월요일'
        WHEN 2 THEN '화요일'
        WHEN 3 THEN '수요일'
        WHEN 4 THEN '목요일'
        WHEN 5 THEN '금요일'
        WHEN 6 THEN '토요일'
    END                 AS 강의요일,
    t.period               AS 교시,
    c.name              AS 강의과목명,
    p.name               AS 강의교수명
FROM tbl_room_l1               AS r
JOIN tbl_sche_d1   AS t ON r.room_id   = t.room_id
JOIN tbl_offe_d1     AS o ON t.offe_id     = o.offe_id
JOIN tbl_subj_m1         AS c ON o.subj_id   = c.subj_id
JOIN tbl_prof_m1         AS p ON o.prof_id     = p.prof_id
WHERE o.semester = CONCAT(
        YEAR(CURDATE()),
        CASE
            WHEN MONTH(CURDATE()) BETWEEN 3 AND 8 THEN '01'
            ELSE '02'
        END
    )
ORDER BY
    r.building,
    r.roomno,
    t.weekday,
    t.period;

-- 4번
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

    COUNT(DISTINCT CONCAT(o.prof_id, '-', s.weekday)) AS lecture_count
FROM tbl_sche_d1 s
JOIN tbl_offe_d1 o ON s.offe_id = o.offe_id
JOIN tbl_prof_m1 p ON o.prof_id = p.prof_id
WHERE o.semester = CONCAT(
        YEAR(CURDATE()),
        CASE
            WHEN MONTH(CURDATE()) BETWEEN 3 AND 8 THEN '01'
            ELSE '02'
        END
    )
GROUP BY s.weekday, p.rank
ORDER BY
    s.weekday,
    CASE p.rank
        WHEN 'P' THEN 1
        WHEN 'S' THEN 2
        WHEN 'L' THEN 3
        WHEN 'T' THEN 4
    END;

-- 5번
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

    r.building AS building_code,

    COUNT(DISTINCT CONCAT(e.stud_id, '-', s.weekday, '-', r.building)) AS expected_students

FROM tbl_enrl_t1 e
JOIN tbl_sche_d1 s ON e.sche_id = s.sche_id
JOIN tbl_offe_d1 o ON s.offe_id = o.offe_id
JOIN tbl_room_l1 r ON s.room_id = r.room_id

WHERE o.semester = CONCAT(
        YEAR(CURDATE()),
        CASE
            WHEN MONTH(CURDATE()) BETWEEN 3 AND 8 THEN '01'
            ELSE '02'
        END
    )

GROUP BY s.weekday, r.building
ORDER BY s.weekday, r.building;

-- 6번
-- MySQL에서는 View 생성
CREATE OR REPLACE VIEW vw_stud_semester_scores AS
SELECT
    base.stud_id,
    base.stud_name,
    base.semester,
    base.applied_credits,
    base.earned_credits,
    base.total_grade_points,

    ROUND(
        base.total_grade_points / NULLIF(base.applied_credits, 0),
        2
    ) AS average_gpa

FROM (
    SELECT
        s.stud_id,
        s.name AS stud_name,
        o.semester,

        -- 신청학점
        SUM(sub.score) AS applied_credits,

        -- 취득학점
        SUM(CASE
            WHEN e.grade IS NOT NULL AND e.grade != 'F' THEN sub.score
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
            END * sub.score
        ) AS total_grade_points

    FROM tbl_enrl_t1 e
    JOIN tbl_stud_m1 s ON e.stud_id = s.stud_id
    JOIN tbl_sche_d1 sch ON e.sche_id = sch.sche_id
    JOIN tbl_offe_d1 o ON sch.offe_id = o.offe_id
    JOIN tbl_subj_m1 sub ON o.subj_id = sub.subj_id

    GROUP BY s.stud_id, s.name, o.semester
) AS base;

-- 6번 문제 SQL문
SELECT   s.stud_id     AS 학번,
         s.name        AS 이름,
         d.name        AS 학과,
         s.grade       AS 학년,
         SUM(v.applied_credits)     AS 총신청학점,
         SUM(v.earned_credits)      AS 총취득학점,
         SUM(v.total_grade_points)  AS 총평점,
         ROUND(SUM(v.total_grade_points) / NULLIF(SUM(v.applied_credits), 0), 2) AS 총평점평균
FROM vw_stud_semester_scores AS v
    JOIN tbl_stud_m1 AS s ON v.stud_id = s.stud_id
    JOIN tbl_dept_m1 AS d ON s.dept_id = d.dept_id
WHERE  s.dept_id='401' AND    s.grade=4
GROUP BY s.stud_id, s.name, d.name, s.grade
ORDER BY s.stud_id;
