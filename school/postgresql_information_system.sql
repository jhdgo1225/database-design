-- 1번
SELECT
    p.교수ID      AS 교수번호,
    p.성명        AS 교수명,
    CASE t.요일
        WHEN 0 THEN '일요일'
        WHEN 1 THEN '월요일'
        WHEN 2 THEN '화요일'
        WHEN 3 THEN '수요일'
        WHEN 4 THEN '목요일'
        WHEN 5 THEN '금요일'
        WHEN 6 THEN '토요일'
    END          AS 강의요일,
    t.교시        AS 교시
FROM 교수         AS p
JOIN 개설과목      AS o
  ON p.교수ID = o.교수ID
JOIN 강의시간표     AS t
  ON o.개설과목ID = t.개설ID
WHERE p.교수ID = :교수ID
    AND o.학기 = (
    TO_CHAR(CURRENT_DATE, 'YYYY') ||
    CASE
        WHEN EXTRACT(MONTH FROM CURRENT_DATE) BETWEEN 3 AND 8 THEN '01'
        ELSE '02'
    END
)
ORDER BY
    t.요일,
    t.교시;

SELECT
    p.prof_id   AS 교수번호,
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
FROM tbl_prof_m1 AS p
JOIN tbl_offe_d1 AS o
  ON p.prof_id = o.prof_id
JOIN tbl_sche_d1 AS t
  ON o.offe_id = t.offe_id
WHERE p.prof_id = '200230503'
    AND o.semester = (
    TO_CHAR(CURRENT_DATE, 'YYYY') ||
    CASE
        WHEN EXTRACT(MONTH FROM CURRENT_DATE) BETWEEN 3 AND 8 THEN '01'
        ELSE '02'
    END
)
ORDER BY
    t.weekday,
    t.period;

-- 2번
SELECT
    s.학번       AS 학번,
    s.성명       AS 학생이름,
    CASE t.요일
        WHEN 0 THEN '일요일'
        WHEN 1 THEN '월요일'
        WHEN 2 THEN '화요일'
        WHEN 3 THEN '수요일'
        WHEN 4 THEN '목요일'
        WHEN 5 THEN '금요일'
        WHEN 6 THEN '토요일'
    END          AS 강의요일,
    t.교시       AS 교시,
    c.과목명     AS 과목명,
    CONCAT(r.호관, r.강의실) AS 강의실
FROM 학생      AS s
JOIN 수강      AS k ON s.학번       = k.학번
JOIN 강의시간표 AS t ON k.시간표ID   = t.시간표ID
JOIN 개설과목   AS o ON t.개설ID     = o.개설과목ID
JOIN 과목      AS c ON o.과목코드   = c.과목코드
JOIN 강의실     AS r ON t.강의실ID   = r.강의실ID
WHERE s.학번 = :학번
    AND o.학기 = (
    TO_CHAR(CURRENT_DATE, 'YYYY') ||
    CASE
        WHEN EXTRACT(MONTH FROM CURRENT_DATE) BETWEEN 3 AND 8 THEN '01'
        ELSE '02'
    END
)
ORDER BY
    t.요일,
    t.교시;

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
 AND o.semester = (
    TO_CHAR(CURRENT_DATE, 'YYYY') ||
    CASE
        WHEN EXTRACT(MONTH FROM CURRENT_DATE) BETWEEN 3 AND 8 THEN '01'
        ELSE '02'
    END
)
ORDER BY
    t.weekday,
    t.period;

select * from tbl_stud_m1;

-- 3번
SELECT
    r.호관               AS 호관,
    r.강의실             AS 강의실,
    CASE t.요일
        WHEN 0 THEN '일요일'
        WHEN 1 THEN '월요일'
        WHEN 2 THEN '화요일'
        WHEN 3 THEN '수요일'
        WHEN 4 THEN '목요일'
        WHEN 5 THEN '금요일'
        WHEN 6 THEN '토요일'
    END                 AS 강의요일,
    t.교시               AS 교시,
    c.과목명              AS 강의과목명,
    p.성명               AS 강의교수명
FROM 강의실               AS r
JOIN 강의시간표   AS t ON r.강의실ID   = t.강의실ID
JOIN 개설과목     AS o ON t.개설ID     = o.개설과목ID
JOIN 과목         AS c ON o.과목코드   = c.과목코드
JOIN 교수         AS p ON o.교수ID     = p.교수ID
WHERE r.강의실ID = :강의실ID
ORDER BY
    r.호관,
    r.강의실,
    t.요일,
    t.교시;

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
WHERE o.semester = (
    TO_CHAR(CURRENT_DATE, 'YYYY') ||
    CASE
        WHEN EXTRACT(MONTH FROM CURRENT_DATE) BETWEEN 3 AND 8 THEN '01'
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

    COUNT(DISTINCT o.prof_id || '-' || s.weekday) AS lecture_count
FROM tbl_sche_d1 s
JOIN tbl_offe_d1 o ON s.offe_id = o.offe_id
JOIN tbl_prof_m1 p ON o.prof_id = p.prof_id
WHERE o.semester = (
    TO_CHAR(CURRENT_DATE, 'YYYY') ||
    CASE
        WHEN EXTRACT(MONTH FROM CURRENT_DATE) BETWEEN 3 AND 8 THEN '01'
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

SELECT
    CASE s.요일
        WHEN 0 THEN '일요일'
        WHEN 1 THEN '월요일'
        WHEN 2 THEN '화요일'
        WHEN 3 THEN '수요일'
        WHEN 4 THEN '목요일'
        WHEN 5 THEN '금요일'
        WHEN 6 THEN '토요일'
    END AS 요일,

    CASE p.교수직급
        WHEN 'P' THEN '정교수'
        WHEN 'S' THEN '부교수'
        WHEN 'L' THEN '조교수'
        WHEN 'T' THEN '시간강사'
    END AS 교수직급,

    COUNT(DISTINCT o.교수ID || '-' || s.요일) AS 출강인원수
FROM 강의시간표   AS s
JOIN 개설과목    AS o ON s.개설과목ID = o.개설과목ID
JOIN 교수       AS p ON o.교수ID = p.교수ID
WHERE o.학기 = (
    TO_CHAR(CURRENT_DATE, 'YYYY') ||
    CASE
        WHEN EXTRACT(MONTH FROM CURRENT_DATE) BETWEEN 3 AND 8 THEN '01'
        ELSE '02'
    END
)
GROUP BY s.요일, p.교수직급
ORDER BY
    s.요일,
    CASE p.교수직급
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

    COUNT(DISTINCT e.stud_id || '-' || s.weekday || '-' || r.building) AS expected_students

FROM tbl_enrl_t1 e
JOIN tbl_sche_d1 s ON e.sche_id = s.sche_id
JOIN tbl_offe_d1 o ON s.offe_id = o.offe_id
JOIN tbl_room_l1 r ON s.room_id = r.room_id

WHERE o.semester = (
    TO_CHAR(CURRENT_DATE, 'YYYY') ||
    CASE
        WHEN EXTRACT(MONTH FROM CURRENT_DATE) BETWEEN 3 AND 8 THEN '01'
        ELSE '02'
    END
)

GROUP BY s.weekday, r.building
ORDER BY s.weekday, r.building;




-- 6번

CREATE OR REPLACE VIEW vw_stud_semester_scores AS
SELECT
    s.stud_id,
    s.name AS stud_name,
    o.semester,

    -- 신청학점 (성적 NULL이면 제외)
    SUM(sub.score) AS applied_credits,

    -- 취득학점 (F 제외)
    SUM(CASE WHEN e.grade != 'F' THEN sub.score ELSE 0 END) AS earned_credits,

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
    ) AS total_grade_points,

    -- 평점평균
    ROUND(
        CAST(SUM(
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
        ) / NULLIF(SUM(sub.score), 0) AS numeric),
        2
    ) AS average_gpa

FROM tbl_enrl_t1 e
JOIN tbl_stud_m1 s ON e.stud_id = s.stud_id
JOIN tbl_sche_d1 sch ON e.sche_id = sch.sche_id
JOIN tbl_offe_d1 o ON sch.offe_id = o.offe_id
JOIN tbl_subj_m1 sub ON o.subj_id = sub.subj_id

-- ✅ 성적 없는 수강은 제외
WHERE e.grade IS NOT NULL

GROUP BY s.stud_id, s.name, o.semester;

---- 이수학기성적 View 생성
CREATE VIEW vw_stud_semester_scores AS
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

---- 6번 문제 SQL문
SELECT   s.stud_id     AS 학번,
         s.name        AS 이름,
         d.name        AS 학과,
         s.grade       AS 학년,
         SUM(v.applied_credits)     AS 총신청학점,
         SUM(v.earned_credits)      AS 총취득학점,
         SUM(v.total_grade_points)  AS 총평점,
         ROUND(CAST(SUM(v.total_grade_points) / NULLIF(SUM(v.applied_credits), 0) AS numeric), 2) AS 총평점평균
FROM vw_stud_semester_scores AS v
    JOIN tbl_stud_m1 AS s ON v.stud_id = s.stud_id
    JOIN tbl_dept_m1 AS d ON s.dept_id = d.dept_id
WHERE  s.dept_id='401' AND    s.grade=4
GROUP BY s.stud_id, s.name, d.name, s.grade
ORDER BY s.stud_id;


SELECT
    s.학번           AS 학번,
    s.학생이름        AS 이름,
    d.학과명         AS 학과,
    s.학년           AS 학년,
    SUM(v.신청학점)   AS 총신청학점,
    SUM(v.취득학점)   AS 총취득학점,
    SUM(v.총평점)     AS 총평점,
    ROUND(
        CAST(SUM(v.총평점) / NULLIF(SUM(v.평점평균), 0) AS numeric),
        2
    )                AS 총평점평균
FROM 이수학점누적성적    AS v
JOIN 학생             AS s ON v.학번 = s.학번
JOIN 학과             AS d ON s.학과ID = d.학과ID
WHERE s.학과ID = <학과ID>
  AND s.학년 = <학년>
GROUP BY s.학번, s.학생이름, d.학과명, s.학년
ORDER BY s.학번;

