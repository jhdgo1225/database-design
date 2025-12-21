select mebrid 아이디,
       passwd 비밀번호,
       name 이름,
       addr 주소,
       email 이메일,
       phone 전화번호,
       manager 관리자여부
from tblmebrm;

select postno 게시판번호,
       mebrid 작성회원,
       title 제목,
       content 내용,
       write 작성일자,
       edit 수정일자
from tblpostm;

select replno 댓글번호,
       postno 게시판번호,
       mebrid 댓글작성자,
       content 내용,
       write 작성일자,
       edit 수정일자
from tblrepld;

select busino 업체번호,
       serv 업종,
       name 업체이름,
       mgr 업체관리자,
       tablecnt `테이블 총 수`,
       addr 주소
from tblbusim;

select cateno `업종 카테고리 번호`,
       name 이름
from tblbsctl;

select cateno `단위 카테고리 번호`,
       name 이름
from tblunitl;

select stafno 직원번호,
       busino 근무업체,
       name 이름,
       position 직책,
       salary 급여,
       status 상태,
       addr 주소,
       phone 전화번호
from tblstafm;

select stokno 재고번호,
       busino 관리업체,
       unit 단위,
       name 이름,
       amount 수량,
       appamount 적정수량
from tblstokm;

select arexno 입출고번호,
       stokno 재고,
       gubun 구분,
       amount 수량,
       arexdate 날짜,
       reason 사유
from tblarext;

select ordrno 주문번호,
       busino 업체,
       orderdate 날짜,
       total 총금액
from tblordrt;

select stodno 주문상세번호,
       ordrno 주문번호,
       stokno 재고번호,
       amount 수량,
       price 가격
from tblstodd;

select menuno 메뉴번호,
       busino 업체,
       name 이름,
       price 가격,
       size 양
from tblmenum;

select mestno `메뉴-재고번호`,
       menuno 메뉴,
       stokno 재고,
       amount `재고 소모량`
from tblmestt;

select saleno 판매번호,
       busino 판매업체,
       tableno `판매 테이블번호`,
       saledate 판매날짜,
       total 총금액
from tblsalet;

select sadtno 판매상세번호,
       saleno 판매번호,
       menuno 메뉴,
       count  수량,
       price  금액
from tblsadtd;
