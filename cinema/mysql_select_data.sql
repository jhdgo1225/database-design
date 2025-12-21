SELECT  scmv_id      AS '영화ID',
        title        AS '영화명',
        summary      AS '영화개요',
        playtime     AS '상영시간',
        agerating    AS '영화등급',
        startdate    AS '상영시작일',
        enddate      AS '상영종료일',
        fee          AS '입장료',
        status       AS '상영현황'
FROM    tbl_scmv_m1;

SELECT  pers_id     AS '인물ID',
        name        AS '인물이름'
FROM    tbl_pers_m1;

SELECT  part_id     AS '참여ID',
        scmv_id     AS '영화ID',
        pers_id     AS '인물ID'
FROM    tbl_part_d1;

SELECT  thtr_id     AS '상영관ID',
        seat        AS '좌석수'
FROM    tbl_thtr_m1;

SELECT  seat_id     AS '좌석ID',
        thtr_id     AS '상영관ID',
        seatcode    AS '좌석코드',
        status      AS '좌석상태'
FROM    tbl_seat_m1
ORDER BY
  CAST(REGEXP_SUBSTR(seat_id, '^[0-9]+') AS UNSIGNED),   -- 앞의 숫자 부분
  REGEXP_SUBSTR(seat_id, '[A-Z]+'),                        -- 중간 문자 부분
  CAST(REGEXP_SUBSTR(seat_id, '[0-9]+$') AS UNSIGNED);     -- 뒤의 숫자 부분

SELECT  scrn_id     AS '영화상영ID',
        scmv_id     AS '영화ID',
        thtr_id     AS '상영관ID',
        scrndate    AS '상영일',
        scrntime    AS '상영시작시간'
FROM    tbl_scrn_m1;

SELECT  mebr_id     AS '회원ID',
        passwd      AS '비밀번호',
        name        AS '성명',
        birth       AS '생년월일',
        sex         AS '성별',
        phone       AS '전화번호',
        email       AS '이메일',
        savings     AS '적립금',
        mileage     AS '마일리지',
        mbrt_id     AS '회원등급ID'
FROM    tbl_mebr_m1;

SELECT  mbrt_id     AS '회원등급ID',
        ratio       AS '마일리지적립률'
FROM    tbl_mbrt_l1;

SELECT  bytk_id     AS '예매ID',
        mebr_id     AS '회원ID',
        scrn_id     AS '영화상영ID',
        seat_id     AS '좌석ID',
        btpy_id     AS '예매결제ID',
        buydate     AS '예매일시',
        savings     AS '적립금',
        mileage     AS '마일리지',
        method      AS '예매방법'
FROM    tbl_bytk_d1;

update tbl_bytk_d1 set seat_id='1A1' where bytk_id=1;
update tbl_bytk_d1 set seat_id='1A9' where bytk_id=2;
update tbl_bytk_d1 set seat_id='1A13' where bytk_id=3;
update tbl_bytk_d1 set seat_id='1A19' where bytk_id=4;
update tbl_bytk_d1 set seat_id='1C20' where bytk_id=5;
update tbl_bytk_d1 set seat_id='1D11' where bytk_id=6;
update tbl_bytk_d1 set seat_id='2E2' where bytk_id=7;
update tbl_bytk_d1 set seat_id='2E8' where bytk_id=8;
update tbl_bytk_d1 set seat_id='2F18' where bytk_id=9;
update tbl_bytk_d1 set seat_id='2G18' where bytk_id=10;
update tbl_bytk_d1 set seat_id='2H18' where bytk_id=11;
update tbl_bytk_d1 set seat_id='2H19' where bytk_id=12;
update tbl_bytk_d1 set seat_id='3I20' where bytk_id=13;
update tbl_bytk_d1 set seat_id='3A4' where bytk_id=14;
update tbl_bytk_d1 set seat_id='3B1' where bytk_id=15;
update tbl_bytk_d1 set seat_id='3C1' where bytk_id=16;
update tbl_bytk_d1 set seat_id='3D1' where bytk_id=17;
update tbl_bytk_d1 set seat_id='3F4' where bytk_id=18;
update tbl_bytk_d1 set seat_id='4B10' where bytk_id=19;
update tbl_bytk_d1 set seat_id='4C19' where bytk_id=20;
update tbl_bytk_d1 set seat_id='4D14' where bytk_id=21;
update tbl_bytk_d1 set seat_id='4E7' where bytk_id=22;
update tbl_bytk_d1 set seat_id='4F2' where bytk_id=23;
update tbl_bytk_d1 set seat_id='4E10' where bytk_id=24;
update tbl_bytk_d1 set seat_id='5A1' where bytk_id=25;
update tbl_bytk_d1 set seat_id='5A10' where bytk_id=26;
update tbl_bytk_d1 set seat_id='5A20' where bytk_id=27;
update tbl_bytk_d1 set seat_id='5B10' where bytk_id=28;
update tbl_bytk_d1 set seat_id='5C6' where bytk_id=29;
update tbl_bytk_d1 set seat_id='5C13' where bytk_id=30;
update tbl_bytk_d1 set seat_id='1D14' where bytk_id=31;
update tbl_bytk_d1 set seat_id='1D15' where bytk_id=32;
update tbl_bytk_d1 set seat_id='1A1' where bytk_id=33;
update tbl_bytk_d1 set seat_id='1B1' where bytk_id=34;
update tbl_bytk_d1 set seat_id='1C1' where bytk_id=35;
update tbl_bytk_d1 set seat_id='1D1' where bytk_id=36;
update tbl_bytk_d1 set seat_id='2A1' where bytk_id=37;
update tbl_bytk_d1 set seat_id='2A2' where bytk_id=38;
update tbl_bytk_d1 set seat_id='2A3' where bytk_id=39;
update tbl_bytk_d1 set seat_id='2A4' where bytk_id=40;
update tbl_bytk_d1 set seat_id='2A5' where bytk_id=41;
update tbl_bytk_d1 set seat_id='2A6' where bytk_id=42;
update tbl_bytk_d1 set seat_id='3A1' where bytk_id=43;
update tbl_bytk_d1 set seat_id='3A2' where bytk_id=44;
update tbl_bytk_d1 set seat_id='3A3' where bytk_id=45;
update tbl_bytk_d1 set seat_id='3A4' where bytk_id=46;
update tbl_bytk_d1 set seat_id='3A5' where bytk_id=47;
update tbl_bytk_d1 set seat_id='3A6' where bytk_id=48;
update tbl_bytk_d1 set seat_id='4A1' where bytk_id=49;
update tbl_bytk_d1 set seat_id='4A3' where bytk_id=50;
update tbl_bytk_d1 set seat_id='4A6' where bytk_id=51;
update tbl_bytk_d1 set seat_id='4A12' where bytk_id=52;
update tbl_bytk_d1 set seat_id='4B14' where bytk_id=53;
update tbl_bytk_d1 set seat_id='4E19' where bytk_id=54;
update tbl_bytk_d1 set seat_id='6G1' where bytk_id=55;
update tbl_bytk_d1 set seat_id='6G2' where bytk_id=56;
update tbl_bytk_d1 set seat_id='6A1' where bytk_id=57;
update tbl_bytk_d1 set seat_id='6G3' where bytk_id=58;
update tbl_bytk_d1 set seat_id='6G5' where bytk_id=59;
update tbl_bytk_d1 set seat_id='6G12' where bytk_id=60;
update tbl_bytk_d1 set seat_id='1A1' where bytk_id=61;
update tbl_bytk_d1 set seat_id='1B2' where bytk_id=62;
update tbl_bytk_d1 set seat_id='1C3' where bytk_id=63;
update tbl_bytk_d1 set seat_id='1E4' where bytk_id=64;
update tbl_bytk_d1 set seat_id='1F5' where bytk_id=65;
update tbl_bytk_d1 set seat_id='2J12' where bytk_id=66;
update tbl_bytk_d1 set seat_id='2B16' where bytk_id=67;
update tbl_bytk_d1 set seat_id='2B19' where bytk_id=68;
update tbl_bytk_d1 set seat_id='2C1' where bytk_id=69;
update tbl_bytk_d1 set seat_id='2D9' where bytk_id=70;
update tbl_bytk_d1 set seat_id='3A1' where bytk_id=71;
update tbl_bytk_d1 set seat_id='3B5' where bytk_id=72;
update tbl_bytk_d1 set seat_id='3C1' where bytk_id=73;
update tbl_bytk_d1 set seat_id='3D15' where bytk_id=74;
update tbl_bytk_d1 set seat_id='4A3' where bytk_id=75;
update tbl_bytk_d1 set seat_id='4E1' where bytk_id=76;
update tbl_bytk_d1 set seat_id='4A7' where bytk_id=77;
update tbl_bytk_d1 set seat_id='6C3' where bytk_id=78;
update tbl_bytk_d1 set seat_id='6G5' where bytk_id=79;
update tbl_bytk_d1 set seat_id='6G10' where bytk_id=80;


SELECT  btpy_id     AS '예매결제ID',
        method      AS '예매결제방식'
FROM    tbl_btpy_l1;

SELECT  chrg_id     AS '충전ID',
        mebr_id     AS '회원ID',
        amount      AS '충전금액',
        chargedate  AS '충전일시',
        crpy_id     AS '충전결제ID'
FROM    tbl_chrg_d1;

SELECT  crpy_id     AS '충전결제ID',
        method      AS '충전결제방식'
FROM    tbl_crpy_l1;

SELECT  scmv_id     AS '영화ID',
        mebr_id     AS '회원ID'
FROM    tbl_like_d1;

SELECT  mngr_id     AS '관리자ID',
        passwd      AS '관리자비밀번호',
        name        AS '관리자성명',
        phone       AS '관리자전화번호',
        birth       AS '관리자생년월일',
        email       AS '관리자이메일'
FROM    tbl_mngr_m1;

