SELECT stud_id  as 학번,
       passwd   as 비밀번호,
       name     as 이름,
       birth    as 생년월일,
       grade    as 학년,
       sex      as 성별,
       dept_id  as 소속학과ID,
       addr     as 주소,
       zipcode  as 우편번호,
       phone    as 전화번호,
       email    as 이메일,
       status   as 졸업여부
FROM            tbl_stud_m1;

SELECT prof_id  as 학번,
       passwd   as 비밀번호,
       name     as 이름,
       birth    as 생년월일,
       sex      as 성별,
       dept_id  as 소속학과ID,
       addr     as 주소,
       zipcode  as 우편번호,
       phone    as 전화번호,
       email    as 이메일,
       rank     as 직급
FROM            tbl_prof_m1;

SELECT subj_id      as 과목코드,
       name         as 과목명,
       description  as 과목설명,
       course       as 이수구분,
       score        as 학점
FROM                tbl_subj_m1;

SELECT offe_id      as 개설과목ID,
       semester     as 학기,
       subj_id      as 과목코드,
       prof_id      as 교수ID,
       dept_id      as 대상학과ID,
       grade        as 대상학년
FROM                tbl_offe_d1;

SELECT sche_id      as 시간표ID,
       offe_id      as 개설ID,
       weekday      as 요일,
       period       as 교시,
       room_id      as 강의실ID
FROM                tbl_sche_d1;

SELECT room_id      as 강의실ID,
       building     as 호관,
       roomno       as 강의실
FROM                tbl_room_l1;


SELECT enrl_id      as 수강ID,
       stud_id      as 학번,
       sche_id      as 시간표ID,
       grade        as 성적등급,
       ygrade       as 신청학년
FROM                tbl_enrl_t1
ORDER BY stud_id;
