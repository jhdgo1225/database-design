SELECT acnt_id  as '계정ID',
       passwd   as '비밀번호',
       name     as '가입자명',
       lgmt_id  as '로그인방식ID',
       phone    as '전화번호',
       email    as '이메일',
       pc       as '개인기업구분'
FROM                tbl_acnt_m1;

SELECT lgmt_id  as '로그인방식ID',
       name     as '로그인방식이름'
FROM                tbl_lgmt_l1;

SELECT pnmb_id  as '개인회원ID',
       acnt_id  as '계정ID',
       birth    as '생년월일',
       sex      as '성별',
       addr     as '주소'
FROM                tbl_pnmb_d1;

SELECT educ_id      as '학력ID',
       pnmb_id      as '개인회원ID',
       sctype       as '학교구분',
       scname       as '학교명',
       admissionym  as '입학년월',
       graduationym as '졸업년월',
       status       as '졸업상태'
FROM                    tbl_educ_d1;

SELECT educ_id  as '학력ID',
       hsequal  as '검정고시여부'
FROM                tbl_hgsc_d1;

SELECT educ_id      as '학력ID',
       majorname    as '전공명',
       credits      as '학점',
       total        as '총점',
       transfer     as '편입여부',
       secondmajor  as '타전공여부',
       secondtype   as '타전공구분',
       secondname   as '타전공명'
FROM                    tbl_univ_d1;

SELECT educ_id      as '학력ID',
       majorname    as '전공명',
       degree       as '학위',
       credits      as '학점',
       total        as '총점'
FROM                    tbl_grad_d1;

SELECT cert_id  as '자격증ID',
       name     as '자격증이름'
FROM                tbl_cert_l1;

SELECT cthd_id  as '자격증보유ID',
       pnmb_id  as '개인회원ID',
       cert_id  as '자격증ID',
       certym   as '취득년월'
FROM                tbl_cthd_t1;

SELECT posi_id  as '직무ID',
       name     as '직무명'
FROM                tbl_posi_l1;

SELECT pnps_id  as '개인회원희망직무ID',
       pnmb_id  as '개인회원ID',
       posi_id  as '직무ID'
FROM                tbl_pnps_t1;

SELECT expr_id  as '경력사항ID',
       phmb_id  as '개인회원ID',
       comp_id  as '기업ID',
       deptname as '부서명',
       joinym   as '입사년월',
       leaveym  as '퇴사년월',
       grade    as '직급',
       role     as '직책',
       posi_id  as '직무ID'
FROM                tbl_expr_t1;

SELECT comp_id          as '기업ID',
       acnt_id          as '계정ID',
       comptype         as '기업형태',
       brn              as '사업자등록번호',
       compname         as '회사명',
       ceo              as '대표자명',
       addr             as '회사주소',
       affi_id          as '모회사ID',
       industry         as '산업',
       capital          as '자본금',
       homelink         as '홈페이지링크',
       empcount         as '사원수',
       empcountdate     as '사원수기준일자',
       estdate          as '설립일',
       revenue          as '매출액',
       revenuedate      as '매출액기준일자',
       fourinsurance    as '4대보험여부'
FROM                        tbl_comp_d1;

SELECT busi_id  as '주요사업ID',
       comp_id  as '기업ID',
       name     as '주요사업이름'
FROM                tbl_busi_d1;

SELECT affi_id  as '모회사ID',
       name     as '모회사명'
FROM                tbl_affi_l1;

SELECT post_id  as '채용공고ID',
       comp_id  as '기업ID',
       title    as '채용공고제목',
       expr     as '경력',
       edu      as '학력',
       emptype as '고용형태',
       salary   as '급여',
       loc      as '지역',
       startdate    as '채용시작일',
       enddate      as '채용마감일',
       applymt      as '지원방식'
FROM                    tbl_post_m1;

SELECT ptps_id  as '채용공고-직무ID',
       post_id  as '채용공고ID',
       posi_id  as '직무ID'
FROM                tbl_ptps_d1;

SELECT aply_id      as '지원ID',
       pnmb_id      as '개인회원ID',
       post_id      as '채용공고ID',
       applydate    as '지원일자',
       success      as '합격여부',
       public       as '자소서공개여부'
FROM                    tbl_aply_t1;

SELECT cvlt_id  as '자기소개서ID',
       aply_id  as '지원ID',
       question as '질문',
       answer   as '답변'
FROM                tbl_cvlt_d1;