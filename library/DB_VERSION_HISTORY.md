# library DB 버전 이력 (패치노트)

PostgreSQL `library` 스키마의 버전별 변경 이력입니다. 스키마가 바뀔 때마다 이 문서 맨 위에 새 버전을 추가합니다.

- 버전 규칙: `MAJOR.MINOR.PATCH`
  - MAJOR: 테이블 추가·삭제, 컬럼 이름·타입 변경 등 기존 쿼리·데이터가 그대로 동작하지 않는 변경
  - MINOR: 기존 쿼리를 깨지 않는 컬럼·제약·트리거 추가
  - PATCH: 주석·데이터 정정 등 구조가 바뀌지 않는 수정
- 기록 시점: 2026-11-10, git HEAD `70e5f58`
- 각 버전은 스키마 파일(DDL), 샘플 데이터, 정보시스템 쿼리 세 가지를 한 묶음으로 봅니다.
- 정규화(v1.x)와 반정규화(v2.x, v3.x)는 서로 다른 폴더에 나란히 있는 두 갈래입니다. v1.x는 비교 기준이고 반정규화는 v1.0.0에서 변환한 결과입니다. 반정규화는 v2.0.0 이후 보유도서의 기본키가 바뀌어 v3.0.0이 되었습니다.

| 버전 | 이름 | 상태 | 위치 | 마지막 변경 커밋 |
|---|---|---|---|---|
| v3.0.1 | 대량 샘플 생성기 (반정규화) | 적용됨 (현재) | `library/postgresql_denormalized/` | `c45a2be` (2026-11-03) |
| v3.0.0 | 반정규화: 복합키·사본 트리거·ISBN 검증 | 적용됨 | `library/postgresql_denormalized/` | `9d68c69` (2026-11-03) |
| v2.0.0 | 반정규화 (UUID 기본키) | 대체됨 | `library/postgresql_denormalized/` | `4a1431f` (2026-10-05) |
| v1.0.1 | 샘플 ISBN 정정 + 대량 샘플 생성기 | 적용됨 | `library/postgresql/` | `c45a2be` (2026-11-03) |
| v1.0.0 | 정규화 (기준) | 적용됨 | `library/postgresql/` | `4c2a5f3` (2026-10-05) |

> MySQL 버전(`library/mysql/`, 2025-12-22 최초 커밋 `9b7334e`~`7f4d09e`)은 별도 제품 계열이라 이 이력의 범위에 넣지 않았습니다. 샘플 ISBN 정정(`cb0e007`)은 MySQL 샘플에도 같이 적용되었습니다.
>
> `library/trigger_study/`(PostgreSQL·MySQL·Oracle 트리거 학습 정리 3개)는 v3.0.0의 트리거를 설명한 학습 문서이고 아직 git에 추가되지 않았습니다. 스키마가 아니므로 버전에 포함하지 않았습니다.

> **로그 파일 안내:** 이 문서가 말하는 측정 로그(`library_<before|after>_NN.log`, `library_*_meta.txt`)는 저장소에 없습니다. 로그를 열어 보려면 반드시 측정 스크립트(`library/estimation_response_time_and_resource.sh`)를 실행해서 생성해야 합니다. 이 문서의 수치를 확인하려고 새로 측정하면 값이 조금 다를 수 있습니다. 시간은 호스트 상태에 따라 달라지고, 캐시 상태에 따라 달라지는 값(버퍼 read 등)도 있습니다.

---

## v3.0.1: 대량 샘플 생성기 (반정규화)

- 위치: `library/postgresql_denormalized/insert_data_bulk.sql` (신규), 커밋 `c45a2be` (2026-11-03)
- 스키마 변경 없음. 정규화 쪽 `postgresql/insert_data_bulk.sql`(v1.0.1)과 같은 데이터를 만듭니다.
- 부속: `library/estimation_response_time_and_resource.sh`(측정, `795c584`), `library/summarize_estimation_result.sh`(요약, `9d723ae`), 원본 로그 `library/results/`·`library/results_parallel0/`(`9dbddd3`, 두 폴더 모두 이후 저장소에서 삭제), 비교 문서 [EXECUTION_TIME_COMPARISON_BULK.md](EXECUTION_TIME_COMPARISON_BULK.md)(`668131f`)
- `insert_data.sql` 적재 후에 실행합니다. 보유도서는 `book_no`를 트리거가 부여하므로 사본 번호 순서대로 INSERT합니다.
- 난수 대신 md5 해시로 값을 만들어 실행할 때마다, 두 스키마에서 항상 같은 데이터가 나옵니다.

| 항목 | 값 |
|---|---|
| 도서 | `book_id` 1001~6000 (5,000종), ISBN은 국내 표기 규칙과 체크기호를 맞춤 |
| 보유도서 | 약 12,500권 |
| 회원 | 번호 1001~11000 (10,000명) |
| 대출 | 사본별 2~42건, 약 19만 건. 마지막 대출의 5%는 미반납(연체중) |
| 대출정지·예약·예약제한·변상 | 생성하지 않음 (정보시스템 쿼리 1~8번이 쓰지 않음) |

적재 후 규모는 정규화가 도서 5,015 / 보유도서 12,517 / 회원 10,015 / 대출 184,485 / 연체 38,102이고, 반정규화는 보유도서 12,517 / 회원 10,015 / 대출 184,485(연체 이력이 있는 대출 38,102)로 논리적으로 같습니다 (2026-11-10 임시 DB에서 확인).

---

## v3.0.0: 반정규화: 복합키·사본 트리거·ISBN 검증

> 기준(롤백 지점): v2.0.0 (`4a1431f`)
> 커밋: `9d68c69` (2026-11-03)
> 버전 번호 판단: 위 버전 규칙으로 `book_held_id` 삭제와 외래키 컬럼 교체는 MAJOR에 해당합니다. v2.0.0의 `book_held_id`를 쓰던 쿼리·INSERT가 그대로 동작하지 않습니다.

### 변경된 파일

| 파일 | 변경 |
|---|---|
| `postgresql_denormalized/create_ddl.sql` | 보유도서 기본키 변경, 시퀀스 1개, 확장 `btree_gist`, 함수 4개, 트리거 3개, CHECK 3개, EXCLUDE 1개, 대출·예약의 복합 FK, 맨 앞 `DROP` 블록에 `tbl_restriction_1`·함수·시퀀스 추가. 회원·제한이력 테이블은 변경 없음 |
| `postgresql_denormalized/insert_data.sql` | 보유도서 INSERT에서 UUID 값 대신 `book_id`만 명시하고 `book_no`는 트리거에 맡김, ISBN의 하이픈 위치를 국내 표기로 정정, `seq_book_id`를 `setval`로 맞춤, 대출·예약 INSERT를 `(book_id, book_no)`로 변경 |
| `postgresql_denormalized/information_system.sql` | 1·5·6번의 대출↔보유도서 조인을 `(book_id, book_no)` 두 컬럼으로 변경, 1번 `GROUP BY`에 제목·저자·출판사 추가 |

### 구조 변경 (호환되지 않음)

| 테이블 | 변경 |
|---|---|
| `tbl_book_held_1` | `book_held_id UUID`(기본키) **삭제**. 기본키를 `(book_id, book_no)` 복합 키로 변경 (`book_no` = 해당 도서의 N번째 사본) |
| `tbl_loan_1` | `book_held_id` 삭제, `book_id`·`book_no` 추가. FK는 `(book_id, book_no) → tbl_book_held_1` 복합 FK (`fk_loan_book_id`) |
| `tbl_reservation_1` | `book_held_id` 삭제, `book_id`·`book_no` 추가. FK는 `(book_id, book_no)` 복합 FK (`fk_reserv_book_id`) |
| `tbl_member_1`, `tbl_restriction_1` | 변경 없음 |

### 제약·트리거 추가

| 대상 | 내용 |
|---|---|
| `chk_book_id`, `chk_book_no` | `book_id >= 1`, `book_no >= 1` |
| `chk_book_isbn` | `fn_isbn13_valid(book_isbn)`: 국내 ISBN-13 표기 검증 |
| `excl_book_isbn` | `EXCLUDE USING gist (book_isbn WITH =, book_id WITH <>)`: 한 ISBN은 하나의 `book_id`에만 속함. 같은 `book_id`의 사본끼리는 같은 ISBN 허용 (UNIQUE는 사본 중복까지 막고, CHECK는 다른 행을 볼 수 없어서 EXCLUDE 사용) |
| `seq_book_id` | `book_id` 발급용 시퀀스 |
| `fn_isbn13_valid` | 접두부 `978-89` 또는 `979-11`, 하이픈 4개, 숫자 13자리, 발행자번호 자릿수가 번호 범위(00~24:2 / 250~549:3 / 5500~8499:4 / 85000~94999:5 / 950000~999999:6)에 맞는지, 체크기호(가중치 1,3 교대) 일치 확인 |
| `fn_assign_book_no` / `trg_assign_book_no` | BEFORE INSERT. `book_id`가 NULL이면 시퀀스로 새 도서 발급. 같은 `book_id`의 기존 사본이 있으면 첫 사본의 서지 정보(제목·저자·분류·ISBN·출판사·발행년도·페이지)를 생략한 컬럼에 복사하고, 다른 값을 직접 지정하면 거부. `book_no` = 그 도서의 `MAX(book_no) + 1`. `pg_advisory_xact_lock(book_id)`로 같은 도서의 동시 INSERT·수정을 직렬화 |
| `fn_sync_book_info` / `trg_sync_book_info` | AFTER UPDATE OF 서지 컬럼. 한 사본의 서지 정보가 바뀌면 같은 `book_id`의 다른 사본에 전파. `pg_trigger_depth() > 1`로 재귀 차단 |
| `fn_protect_book_key` / `trg_protect_book_key` | BEFORE UPDATE OF `book_id`, `book_no`. 값이 바뀌는 UPDATE를 거부. `book_id`를 바꾸면 다른 도서의 사본이 되어 서지 정보가 어긋나고, `book_no`를 바꾸면 대출·예약 이력의 참조가 깨지기 때문 |

### 검증 (2026-11-10, 임시 DB, PostgreSQL 17.10)

별도 검증 스크립트는 없고, 임시 DB에 `create_ddl.sql`, `insert_data.sql` 순서로 적재해 직접 확인했습니다.

| 시나리오 | 결과 |
|---|---|
| 새 도서 INSERT (`book_id` 생략) | 시퀀스로 `book_id` 발급, `book_no = 1` |
| 기존 도서(12번)의 사본 추가, 서지 컬럼 생략 | `book_no = 4`, 제목·ISBN이 기존 사본에서 복사됨 |
| 같은 `book_id`에 다른 제목으로 사본 추가 | 거부 (`check_violation`, "서지 정보가 기존 사본과 다릅니다") |
| ISBN 체크기호가 틀린 INSERT | `chk_book_isbn` 위반으로 거부 |
| 다른 도서의 ISBN과 같은 ISBN | `excl_book_isbn` 위반으로 거부 |
| 한 사본의 제목 UPDATE | 같은 도서의 3개 사본 모두 변경 |
| `book_no` 또는 `book_id` UPDATE | 거부 (`integrity_constraint_violation`) |
| 상태 코드를 `'Z'`로 UPDATE | `chk_held_status`로 거부 |
| 샘플 적재 | 에러 없음. 보유도서 17, 회원 15, 대출 21, 예약 13, 제한이력 14 (테이블 5개) |
| `information_system.sql` 8개 쿼리 | 소규모 샘플과 대량 샘플 적재 후 모두 에러 없이 실행 |
| 정규화 샘플의 ISBN 15종 | 모두 `fn_isbn13_valid` 통과, 도서별 ISBN이 v3.0.0 샘플과 같음 (v1.0.1 참고) |

트리거 하나씩 빼고 다시 돌리는 방식의 검증(cinema 문서의 `verify_integrity.sql` 같은 것)은 하지 않았습니다. 동시성(같은 `book_id`의 동시 INSERT·수정, 데드락)도 따로 부하를 걸어 보지 않았습니다. 위 표는 단일 세션에서의 동작 확인입니다.

### 정보시스템 쿼리 변경

| 번호 | 변경 |
|---|---|
| 1 | 조인 조건이 `book_held_id` 하나 → `(book_id, book_no)` 두 컬럼. `GROUP BY`가 `book_id` 하나 → 제목·저자·출판사를 포함한 4개 컬럼 (기본키가 `(book_id, book_no)`라서 `book_id`만으로는 서지 컬럼이 함수적으로 결정되지 않음. 같은 `book_id` 사본의 서지 정보는 트리거가 동일하게 유지) |
| 5, 6 | 조인 조건이 `(book_id, book_no)` 두 컬럼으로 변경 |
| 2, 3, 4, 7, 8 | 없음 |

### 성능 영향 (v1.0.x → v3.0.x)

환경: PostgreSQL 17.10 (aarch64), 대량 샘플(대출 약 18만 건), 쿼리당 워밍업 3회 + 측정 30회, 직렬·병렬 구분, 중앙값 기준. 상세는 [EXECUTION_TIME_COMPARISON_BULK.md](EXECUTION_TIME_COMPARISON_BULK.md), 측정 스크립트를 실행했을 때 대략 이런 집계 결과가 나왔다는 기록입니다. 스크립트를 `PARALLEL=0`으로 실행하면 `results_parallel0/`(직렬), `PARALLEL` 없이 실행하면 `results/`(병렬)에 로그가 생기고, 그 로그로 확인합니다. 로그 파일은 저장소에 두지 않았습니다.

| 지표 (8개 쿼리 합, 전 → 후) | 직렬 실행 | 병렬 실행 |
|---|---|---|
| 실행 시간 | 399.1 → 379.2 ms (-5%). 3·6번만 후가 빠르고 나머지는 차이 없음 | 298.9 → 253.4 ms (-15%). 1·3·6번 후가 빠르고 5번은 후가 느림 |
| 실행 버퍼 hit | 16,069 → 18,227 (+13%) | 16,670 → 19,108 (+15%) |
| 계획 시간 | 5.74 → 9.65 ms (+68%) | 5.76 → 9.67 ms (+68%) |
| 조인 수 | 9 → 5 (-44%) | 9 → 5 (-44%) |
| 저장 공간 | 29.3 → 28.5 MB (-3%) | 같음 |

- 반정규화의 실행 시간 이득은 조인이 사라진 3·6번에 있습니다. 병렬 -15%는 1번이 전(직렬)에서 후(병렬)로 플랜이 바뀐 영향이 큽니다.
- 대출 테이블만 읽는 2·4·7·8번은 후가 같거나 약간 느립니다. 연체 이력 컬럼이 들어가 행이 넓어졌기 때문입니다 (`tbl_loan_1` 2,097 → 2,383 페이지, +14%).
- 계획 시간은 대출↔보유도서 조인이 두 컬럼 조건이 되면서 1·5·6번에서 0.9 → 2.3 ms로 늘었습니다.
- 대량 샘플(보유도서 12,517행, 트리거 포함) 적재 시간은 정규화 약 6.3초, 반정규화 약 6.4초로 거의 같았습니다 (임시 DB에서 `docker exec`로 1회씩 측정한 값이라 참고용).
- 이 문서의 수치와 [EXECUTION_TIME_COMPARISON.md](EXECUTION_TIME_COMPARISON.md)(v2.0.0 기준, DBeaver)의 수치는 조건이 달라 직접 비교하면 안 됩니다.

### 호환성에 미치는 영향

- `book_held_id`를 쓰던 쿼리·INSERT는 `(book_id, book_no)`로 고쳐야 합니다. 보유도서 INSERT는 `book_no`를 직접 넣지 않고 트리거가 부여하게 합니다.
- 서지 정보는 같은 도서의 모든 사본에 복제 저장되고, 한 사본의 서지 정보를 고치면 같은 도서의 모든 사본을 UPDATE합니다 (사본 수에 비례한 비용).
- `btree_gist` 확장이 필요합니다 (`CREATE EXTENSION IF NOT EXISTS`). 확장 생성 권한이 없거나 contrib 확장이 설치되지 않은 환경에서는 DDL이 실패합니다.
- ISBN은 국내 표기(`978-89`, `979-11`)만 허용합니다. 다른 접두부나 하이픈 없는 형태는 거부됩니다.
- 대출·예약 INSERT는 `(book_id, book_no)` 복합 FK를 만족해야 합니다.
- `create_ddl.sql`은 맨 앞에서 정규화(v1)와 v2.0.0이 쓰던 이름의 테이블 16개와 이 DDL이 만드는 시퀀스·함수를 먼저 지웁니다. 같은 DB에 정규화 데이터가 있으면 함께 사라집니다.

### 알려진 한계

- **`migration/to_denormalized_structure.sql`이 v3.0.0을 만들지 않습니다.** 이 스크립트는 `4a1431f`~`2056c44`(2026-10-05) 시점의 v2.0.0 구조(`book_held_id UUID` 기본키, 트리거 없음)로 옮기는 용도이고 이후 수정되지 않았습니다. v1.0.0 샘플 위에서 실행해 보면 `tbl_book_held_1`의 컬럼이 `book_held_id, book_id, ...`이고 기본키가 `(book_held_id)`, 트리거가 0개로 나옵니다. v3.0.0 DDL은 `book_id, book_no ...`, 기본키 `(book_id, book_no)`, 트리거 3개입니다. 기존 데이터를 v3.0.0으로 옮기려면 마이그레이션 스크립트를 새로 고쳐야 합니다.
- `book_no`는 `MAX(book_no) + 1`로 부여합니다. 마지막 사본을 삭제하면 그 번호가 다시 쓰입니다 (12번 도서 4번 사본을 지우고 새 사본을 넣으면 다시 4번이 됨, 임시 DB에서 확인). 대출·예약이 참조하는 사본은 외래키(`ON DELETE RESTRICT`)로 삭제되지 않으므로 이력이 엉키지는 않지만, 이력이 없는 사본 번호는 재사용됩니다.
- 동시성 점검은 하지 않았습니다. `pg_advisory_xact_lock(book_id)`는 정수 하나로 락을 걸므로 같은 데이터베이스에서 다른 용도로 쓰는 advisory lock과 키가 겹치면 서로 기다릴 수 있습니다.
- 정규화(v1.x)에는 위 트리거·ISBN 제약이 없습니다. 전/후 비교에서 쓰기 경로의 제약 수가 다릅니다.

---

## v2.0.0: 반정규화 (UUID 기본키)

> v3.0.0에 의해 대체됨. 구조 이력으로 남깁니다.

- 위치: `library/postgresql_denormalized/` (`create_ddl.sql`, `insert_data.sql`, `information_system.sql`)
- 커밋: `4a1431f` 설계 → `05b9c59` 샘플 데이터 → `c1e05b3` 정보시스템 쿼리 (모두 2026-10-05)
- 부속: `migration/to_denormalized_structure.sql` (`2056c44`, 2026-10-05) v1.0.0 → v2.0.0 데이터 이전 스크립트, [EXECUTION_TIME_COMPARISON.md](EXECUTION_TIME_COMPARISON.md) (DBeaver 측정, `c3c1dba`로 library 폴더에 이동)
- 기준: v1.0.0에서 변환
- 규모: 테이블 15개 → 5개

### 구조 변경 (호환되지 않음)

| 테이블 | 변경 |
|---|---|
| `tbl_book_1` | **삭제**. 서지 정보(제목·저자·분류·ISBN·출판사·발행년도·페이지)가 `tbl_book_held_1`로 흡수됨. `book_id`는 같은 책의 사본을 묶는 식별자로 남김 (FK 아님) |
| `tbl_book_held_loc_1` | **삭제**. `book_held_loc_code CHAR(1)` (G 종합자료실 / C 어린이실 / S 보존서고) CHECK로 흡수 |
| `tbl_book_held_status_1` | **삭제**. `book_held_status_code CHAR(1)` (A 대출가능 / L 대출중 / O 연체중 / R 예약됨 / N 예약불가 / M 보수중 / F 분실 / D 폐기) CHECK로 흡수 |
| `tbl_book_held_1` | 기본키 `book_held_id`를 `VARCHAR(12)`에서 `UUID`(`gen_random_uuid()`)로 변경 |
| `tbl_member_grade_1` | **삭제**. `tbl_member_1.member_grade_code`('N' 일반 / 'V' VIP)와 `member_loan_day`(14 / 21)로 흡수, 조합을 `chk_member_grade`로 고정 |
| `tbl_loan_suspension_1`, `tbl_reservation_suspension_1`, `tbl_loan_suspension_status_1` | **삭제**. 회원의 현재 상태 컬럼(`member_loan_suspension_*`, `member_reservation_suspension_*`)과 통합 이력 테이블 `tbl_restriction_1`(`restriction_type_code` L 대출정지 / R 예약제한)로 대체 |
| `tbl_overdue_1`, `tbl_overdue_status_1` | **삭제**. 대출의 `overdue_start`, `overdue_end`, `overdue_status_code`(O 연체중 / R 반납됨 / D 분실·파손)로 흡수 |
| `tbl_reimbursement_1` | **삭제**. 대출의 `reimbursement_date`, `reimbursement_status`(Y / N)로 흡수 |
| `tbl_reservation_status_1` | **삭제**. `tbl_reservation_1.reservation_status_code`(W 대기 / A 가능 / E 만료 / C 취소) CHECK로 흡수 |
| `tbl_loan_1`, `tbl_reservation_1` | `book_held_id`를 UUID로 교체 |

룩업 테이블 대신 CHECK로 코드값을 제한합니다. 변경 후 테이블: `tbl_book_held_1`, `tbl_member_1`, `tbl_loan_1`, `tbl_reservation_1`, `tbl_restriction_1`.

### 정보시스템 쿼리 변경

| 번호 | 변경 |
|---|---|
| 1 | 도서 조인 제거, `book_id` 기준으로 사본을 묶어 집계. SQL 조인 2개 → 1개 |
| 3 | 분류 코드가 보유도서에 있어 조인 제거. 조인 1개 → 0개 |
| 5, 6 | 도서 조인 제거. SQL 조인 2개 → 1개 |
| 2, 4, 7, 8 | 없음 |

### 마이그레이션 (`migration/to_denormalized_structure.sql`)

- v1.0.0 스키마와 샘플이 적재된 PostgreSQL 13+ DB를 v2.0.0 구조로 옮깁니다. `_new` 접미사 테이블을 새로 만들어 JOIN으로 채우고, 기존 테이블을 지운 뒤 이름을 바꿉니다 (`ALTER`로 컬럼을 하나씩 바꾸기엔 기본키 타입 변경(VARCHAR → UUID)과 여러 테이블 통합이 섞여 있어서).
- 사전 점검: 일치하는 대출 건이 없는 변상·연체 기록은 옮길 곳이 없어서 경고만 남기고 제외합니다 (샘플에는 변상 1건이 해당: `book_held_id = EML000252100`, `member_no = 11101001000007`).
- **v3.0.0 구조로는 옮기지 못합니다** (v3.0.0의 알려진 한계 참고).

### 성능 측정 결과 (v1.0.0 → v2.0.0)

환경: DBeaver `EXPLAIN ANALYZE`, 기본 샘플, 쿼리당 10회 (정보시스템 1·3·5·6번). 비교 조건은 조인 제거와 `book_held_id` 기본키 타입 변경(`VARCHAR(12)` → `UUID`) 두 가지입니다.

| 번호 | 변경 | 중앙값 (ms, 전 → 후) |
|---|---|---|
| 1 (사본 단위) | 도서 조인 제거 | 0.089 → 0.121 (분포가 겹쳐 차이 없음) |
| 3 | 도서 조인 제거 (조인 없어짐) | 0.104 → 0.064 (-39%) |
| 5 | 도서 조인 제거 | 0.157 → 0.088 (-44%) |
| 6 | 도서 조인 제거 | 0.151 → 0.096 (-36%) |

기본 샘플이 작아(수십 행) 절대 시간은 0.2 ms 미만입니다. 이 측정은 v3.0.0 이전 구조 기준이라 v3.0.0 수치와 직접 비교하지 않습니다.

### 알려진 한계

- 같은 책의 사본끼리 서지 정보가 같아야 한다는 규칙을 DB가 강제하지 않았습니다 (`book_id`가 FK가 아니고, 중복 저장된 서지 컬럼의 일치를 검사하는 제약이 없음). → v3.0.0에서 트리거로 해결
- ISBN 형식·중복 검사가 없었습니다. 샘플에도 하이픈 위치가 틀린 ISBN이 들어 있었습니다 (예: `978-89-364345-9-5`). → v3.0.0에서 해결
- 보유도서 식별자가 의미 없는 UUID여서 사람이 읽을 수 없고 같은 도서의 몇 번째 사본인지 알 수 없었습니다. → v3.0.0에서 `(book_id, book_no)`로 해결

---

## v1.0.1: 샘플 ISBN 정정 + 대량 샘플 생성기

- 위치: `library/postgresql/insert_data.sql`(정정), `library/postgresql/insert_data_bulk.sql`(신규)
- 커밋: `cb0e007` ISBN 정정 (2026-11-03, `mysql/insert_data.sql`도 같이), `c45a2be` 대량 샘플 생성기 (2026-11-03)
- 스키마 변경 없음 (PATCH)

### 샘플 ISBN 정정

`postgresql/insert_data.sql`의 도서 15종 ISBN을 모두 고쳤습니다 (15행을 교체, 파일 변경은 30줄).

| 점검 | 정정 전 | 정정 후 |
|---|---|---|
| v3.0.0의 `fn_isbn13_valid` 통과 | 0 / 15 | 15 / 15 |
| 서로 다른 ISBN 수 | 12 / 15 (3건 중복) | 15 / 15 |

- 하이픈 위치가 틀렸습니다. 예: `979-11-711764-5-8` → `979-11-7117-645-8`.
- 서로 다른 도서가 같은 ISBN을 쓰던 곳을 고쳤습니다. 예: 미분적분학 바이블 I·II(`book_id` 2·3), 알고리즘 문제 해결 전략 1·2(4·5), 동물농장·데미안(8·9)이 각각 같은 ISBN이었습니다.
- 정정 이유: v3.0.0의 ISBN 검증과 `excl_book_isbn`이 들어오면서 정규화·MySQL 샘플도 같은 데이터가 되어야 전/후 비교의 조건이 같기 때문입니다. 정정 후 정규화의 `book_id`별 ISBN은 v3.0.0 샘플과 완전히 같습니다 (임시 DB에서 두 샘플을 적재해 비교).

### 대량 샘플 생성기

`insert_data_bulk.sql`은 정규화 기준 대량 데이터(도서 5,000종, 보유도서 약 12,500권, 회원 10,000명, 대출 약 19만 건)를 만듭니다. 규칙과 규모는 [v3.0.1](#v301-대량-샘플-생성기-반정규화)과 같습니다. 정규화 적재 후 규모는 도서 5,015 / 보유도서 12,517 / 회원 10,015 / 대출 184,485 / 연체 38,102입니다.

---

## v1.0.0: 정규화 (기준)

- 위치: `library/postgresql/` (`create_ddl.sql`, `insert_data.sql`, `information_system.sql`)
- 커밋: `f95b58e` DDL·샘플 데이터, `d2b3027` 정보시스템 쿼리 (2026-10-05), `4c2a5f3` 서브폴더로 이동 (2026-10-05)
- 규모: 테이블 15개. 샘플은 도서 15종, 보유도서 17, 회원 15, 대출 21, 연체 14, 예약 13

### 구조

| 분류 | 테이블 |
|---|---|
| 도서 | `tbl_book_1`(도서), `tbl_book_held_1`(보유도서), `tbl_book_held_loc_1`(보유도서 위치), `tbl_book_held_status_1`(보유도서 상태) |
| 회원 | `tbl_member_1`(회원), `tbl_member_grade_1`(회원 등급) |
| 대출·연체·변상 | `tbl_loan_1`(대출), `tbl_overdue_1`(연체), `tbl_overdue_status_1`(연체 상태), `tbl_reimbursement_1`(변상) |
| 예약 | `tbl_reservation_1`(예약), `tbl_reservation_status_1`(예약 상태) |
| 제한 | `tbl_loan_suspension_1`(대출정지), `tbl_loan_suspension_status_1`(대출정지 상태), `tbl_reservation_suspension_1`(예약제한) |

### 특징

- 상태·등급·위치는 모두 룩업 테이블(`*_status_1`, `*_grade_1`, `*_loc_1`)을 외래키로 참조합니다.
- 보유도서 기본키는 `book_held_id VARCHAR(12)` (`EML`/`JUL` + 숫자 9자리)이고, 대출·연체·예약·변상이 이 값을 참조합니다.
- 서지 정보는 `tbl_book_1`에만 있고, 정보시스템 쿼리가 필요할 때마다 `tbl_book_held_1`과 조인해서 읽습니다.
- 회원이 삭제되면 대출·연체·예약·변상·대출정지·예약제한 기록이 함께 삭제됩니다 (`ON DELETE CASCADE`). 보유도서와 상태 코드는 삭제할 수 없습니다 (`ON DELETE RESTRICT`).
- 연체 종료일, 실제 반납일, 예약 만기일, 변상 일자는 아직 정해지지 않을 수 있어 NULL을 허용합니다.
- CHECK 제약, ISBN 형식 검사, 중복 방지가 없습니다.
- `tbl_overdue_1`, `tbl_reimbursement_1`에는 대출 기록 ID가 없어 (`book_held_id`, `member_no`) 조합으로 대출과 연결합니다. 샘플에는 일치하는 대출이 없는 변상 1건이 있습니다.
