select mebr_id as 아이디,
       passwd as 비밀번호,
       name as 이름,
       sex as 성별,
       birth as 생년월일,
       phone as 연락처,
       email as 이메일,
       totalrental as `자전거 대여 누적 횟수`,
       points as 마일리지,
       signupmethod as 가입수단,
       flag as `선불/등록권사용여부`
FROM tblmebrm1;

select tick_id as 구매번호,
       mebr_id as 아이디,
       ticket as 정기권,
       startdate as 구매일자,
       enddate as 종료일자,
       points as 마일리지사용,
       paymethod as 결제수단
from tbltickd1;

select bycl_id as 자전거번호,
       registerdate as 자전거등록일자,
       installdate as 자전거설치일자,
       status as 자전거상태,
       gubun as 자전거구분
from tblbyclm1;

select rtpl_id as 대여소번호,
       space as `대여소 지점명`,
       addr as `대여소 주소`,
       avail as `대여 가능한 자전거 수량`
from tblrtplm1;

select rack_id as 거치대번호,
       rtpl_id as 대여소번호,
       status as 거치대상태,
       bycl_id as `거치된 자전거 번호`,
       gubun as `거치대 구분`
from tblrackd1;

select rent_id as 대여ID,
       mebr_id as 대여회원,
       rtpl_id as 대여지점,
       bycl_id as 대여자전거,
       rentdate as 대여일자,
       CONCAT(
           FLOOR(TIME_TO_SEC(time) / 3600), '시간 ',
           FLOOR((TIME_TO_SEC(time) % 3600) / 60), '분 ',
           ROUND(TIME_TO_SEC(time) % 60), '초'
       ) as 이용시간,
       dist as 거리,
       kcal as 칼로리소모량,
       carbon as 탄소저감,
       retrtpl_id as 반납지점,
       fee as 대여료
from tblrentt1;

select spcl_id as `보충/수거ID`,
       bycl_id as 자전거번호,
       spclgubun as `보충/수거구분`,
       collectreason as 수거사유,
       rtpl_id as `보충/수거지점`,
       spcldate as `보충/수거일자`
from tblspcld1;

select dmls_id as `파손/분실ID`,
       bycl_id as `파손/분실 자전거`,
       mebr_id as 회원아이디,
       dmlsflag as `파손/분실 여부`,
       name as `파손/분실자 이름`,
       phone as `파손/분실자 전화번호`,
       addr as `파손/분실자 주소`,
       reason as `파손/분실 사유`,
       occurdate as `파손/분실 발생일자`,
       liable as 비용청구의무여부,
       confirm as 비용청구확인,
       amount as 청구비용,
       claimdate as 청구일자
from tbldmlsd1;

select mebr_id as 회원아이디,
       rtpl_id as 대여소번호
from tblfavot1;
