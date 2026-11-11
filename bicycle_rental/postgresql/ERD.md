# bicycle_rental ERD (PostgreSQL)

`postgresql_create_ddl.sql` 기준으로 그린 ERD입니다. 실선은 FK가 PK의 일부인 관계, 점선은 일반 FK 관계입니다.

```mermaid
erDiagram
    tblmebrM1 {
        VARCHAR(16) mebr_id PK "소문자+숫자, 10~16자"
        CHAR(64) passwd
        VARCHAR(128) name
        CHAR(1) sex "M / F"
        DATE birth
        CHAR(11) phone "010으로 시작"
        VARCHAR(64) email
        INT totalrental
        INT points
        CHAR(2) signupmethod "GN / NV / KA / GG"
        CHAR(1) flag "Y / N, 기본 N"
    }

    tbltickD1 {
        INT tick_id PK "IDENTITY"
        VARCHAR(16) mebr_id FK
        VARCHAR(8) ticket "PRE 또는 030~365 이용권 코드"
        TIMESTAMP startdate
        TIMESTAMP enddate
        INT points
        VARCHAR(4) paymethod "CP/BT+2자, NV, KA, TO, ML"
        INT periodday "생성 컬럼, 코드의 기간(PRE는 NULL)"
        INT usehour "생성 컬럼, 코드의 이용 시간"
        INT price "생성 컬럼, 코드의 금액 x 100(PRE는 NULL)"
    }

    tblbyclM1 {
        CHAR(7) bycl_id PK
        TIMESTAMP registerdate
        TIMESTAMP installdate "NULL 허용"
        VARCHAR(3) status "PD/AVL/ING/DMG/LST/RP/COL"
        CHAR(2) gubun "GN 일반 / SD 새싹"
    }

    tblrtplM1 {
        CHAR(5) rtpl_id PK
        VARCHAR(128) space
        VARCHAR(256) addr
        SMALLINT avail "0 이상"
    }

    tblrackD1 {
        CHAR(7) rack_id PK
        CHAR(5) rtpl_id FK
        CHAR(3) status "AVL / DMG"
        CHAR(7) bycl_id FK "NULL 허용"
        CHAR(2) gubun "GN / SD"
    }

    tblrentT1 {
        INT rent_id PK "SERIAL"
        VARCHAR(16) mebr_id FK
        CHAR(5) rtpl_id FK "대여 대여소"
        CHAR(7) bycl_id FK
        TIMESTAMP rentdate
        INTERVAL time
        REAL dist
        REAL kcal
        REAL carbon
        CHAR(5) retrtpl_id FK "반납 대여소, NULL 허용"
        TIMESTAMP returndate "NULL 허용"
        INT fee
    }

    tblspclD1 {
        BIGINT spcl_id PK "BIGSERIAL"
        CHAR(7) bycl_id FK
        CHAR(2) spclgubun "SP / CL"
        CHAR(2) collectreason "DM / RP, 수거(CL)일 때만, 보충(SP)은 NULL"
        CHAR(5) rtpl_id FK
        TIMESTAMP spcldate
    }

    tbldmlsD1 {
        BIGINT dmls_id PK "BIGSERIAL"
        INT rent_id FK "파손/분실이 발생한 대여"
        CHAR(7) bycl_id FK
        VARCHAR(16) mebr_id FK
        CHAR(2) dmlsflag "DM 파손 / LS 분실"
        VARCHAR(128) name "NULL 허용"
        CHAR(11) phone "NULL 허용"
        VARCHAR(128) addr "NULL 허용"
        VARCHAR(600) reason "NULL 허용"
        TIMESTAMP occurdate
        CHAR(1) liable "Y / N, 기본 N"
        CHAR(1) confirm "Y / N, 기본 N"
        INT amount "NULL 허용"
        TIMESTAMP claimdate "NULL 허용"
    }

    tblfavoT1 {
        VARCHAR(16) mebr_id PK, FK
        CHAR(5) rtpl_id PK, FK
    }

    tblmebrM1 ||..o{ tbltickD1 : "구매"
    tblmebrM1 ||..o{ tblrentT1 : "대여"
    tblmebrM1 ||..o{ tbldmlsD1 : "파손/분실 책임"
    tblmebrM1 ||--o{ tblfavoT1 : "즐겨찾기"

    tblrtplM1 ||--o{ tblfavoT1 : "즐겨찾기 대상"
    tblrtplM1 ||..o{ tblrackD1 : "보유"
    tblrtplM1 ||..o{ tblrentT1 : "대여 대여소"
    tblrtplM1 |o..o{ tblrentT1 : "반납 대여소"
    tblrtplM1 ||..o{ tblspclD1 : "작업 대여소"

    tblbyclM1 |o..o{ tblrackD1 : "거치"
    tblbyclM1 ||..o{ tblrentT1 : "대여됨"
    tblbyclM1 ||..o{ tblspclD1 : "특별 처리"
    tblbyclM1 ||..o{ tbldmlsD1 : "파손/분실 대상"

    tblrentT1 ||..o{ tbldmlsD1 : "대여 중 발생"
```

## 관계 정리

| 부모 | 자식 | FK 컬럼 | 비고 |
|---|---|---|---|
| tblmebrM1 | tbltickD1 | mebr_id | 회원 1명이 이용권 여러 개 |
| tblmebrM1 | tblrentT1 | mebr_id | |
| tblmebrM1 | tbldmlsD1 | mebr_id | |
| tblmebrM1 | tblfavoT1 | mebr_id | PK의 일부 |
| tblrtplM1 | tblfavoT1 | rtpl_id | PK의 일부 |
| tblrtplM1 | tblrackD1 | rtpl_id | |
| tblrtplM1 | tblrentT1 | rtpl_id | 대여한 대여소 |
| tblrtplM1 | tblrentT1 | retrtpl_id | 반납한 대여소, 반납 전에는 NULL |
| tblrtplM1 | tblspclD1 | rtpl_id | |
| tblbyclM1 | tblrackD1 | bycl_id | 빈 거치대는 NULL |
| tblbyclM1 | tblrentT1 | bycl_id | |
| tblbyclM1 | tblspclD1 | bycl_id | |
| tblbyclM1 | tbldmlsD1 | bycl_id | |
| tblrentT1 | tbldmlsD1 | rent_id | 파손/분실이 발생한 대여. mebr_id, bycl_id는 이 대여와 같은 값을 반정규화로 함께 저장 |

## 참고

- tblfavoT1은 회원과 대여소의 다대다 관계를 풀어주는 연결 테이블입니다.
- tblrentT1이 tblrtplM1을 두 번 참조합니다(rtpl_id, retrtpl_id).
- tblrackD1.bycl_id에는 UNIQUE가 없어서, DDL만 보면 한 자전거가 여러 거치대에 들어갈 수 있습니다. ERD에서도 1:N으로 그렸습니다.
