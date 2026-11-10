# school DB 버전 이력 (패치노트)

PostgreSQL `school` 스키마의 버전별 변경 이력입니다. 스키마가 바뀔 때마다 이 문서 맨 위에 새 버전을 추가합니다.

- 버전 규칙: `MAJOR.MINOR.PATCH`
  - MAJOR: 테이블 추가·삭제, 컬럼 이름·타입 변경 등 기존 쿼리·데이터가 그대로 동작하지 않는 변경
  - MINOR: 기존 쿼리를 깨지 않는 컬럼·제약·트리거·인덱스 추가
  - PATCH: 주석·데이터 정정 등 구조가 바뀌지 않는 수정
- 기록 시점: 2026-11-10, git HEAD `70e5f58`
- 각 버전은 스키마 파일(DDL), 샘플 데이터, 정보시스템 쿼리 세 가지를 한 묶음으로 봅니다.
- 정규화(v1.x)와 반정규화(v2.x)는 서로 다른 폴더에 나란히 있는 두 갈래라서 버전이 따로 올라갑니다. v1.x는 비교 기준이고 v2.x는 v1.0.0에서 변환한 결과입니다.

| 버전 | 이름 | 상태 | 위치 | 마지막 변경 커밋 |
|---|---|---|---|---|
| v2.1.0 | 강의실 이중 배정 방지 | 적용됨 | `school/postgresql_denormalization/` | `b0b4dd2` (2026-11-10) |
| v2.0.0 | 반정규화 | 적용됨 | `school/postgresql_denormalization/` | `10c90a4` (2026-10-30) |
| v1.1.0 | 정규화 + 강의실 이중 배정 방지 | 적용됨 | `school/postgresql/` | `b0b4dd2` (2026-11-10) |
| v1.0.0 | 정규화 (기준) | 적용됨 | `school/postgresql/` | `3e7b21a` (2026-10-30) |

> MySQL 버전(`school/mysql/`, 2025-12-22 최초 커밋 `7dc367c`~`abe6fa7`)은 별도 제품 계열이라 이 이력의 범위에 넣지 않았습니다.

---

## v2.1.0: 강의실 이중 배정 방지

> 커밋: `b0b4dd2` (2026-11-10)
> 기준(롤백 지점): v2.0.0 (`10c90a4`)
> 같은 변경이 정규화 쪽에도 들어갔습니다 → [v1.1.0](#v110-정규화--강의실-이중-배정-방지).

### 변경된 파일

| 파일 | 변경 |
|---|---|
| `postgresql_denormalization/create_ddl.sql` | `tbl_sche_d2`에 CHECK 2개(`ck_sche_weekday`, `ck_sche_period`)와 유일 인덱스 `uq_sche_room_slot` 추가, 파일 맨 앞에 정규화 테이블 8개를 지우는 `DROP TABLE IF EXISTS` 추가, 컬럼 정의를 쉼표 뒤쪽 배치·탭 주석으로 재정렬(구조 변화 없음), 헤더 주석 |
| `postgresql_denormalization/insert_data.sql` | `tbl_sche_d2` INSERT 중 45행의 `room_code` 변경 |

### 변경 내용

| 대상 | 변경 | 분류 |
|---|---|---|
| `tbl_sche_d2` | `ck_sche_weekday CHECK (weekday BETWEEN 0 AND 6)` 추가 | 제약 추가 |
| `tbl_sche_d2` | `ck_sche_period CHECK (period BETWEEN 1 AND 10)` 추가 | 제약 추가 |
| `tbl_sche_d2` | `CREATE UNIQUE INDEX uq_sche_room_slot ON (SUBSTRING(offe_id FROM 1 FOR 6), room_code, weekday, period)` 추가 | 인덱스 추가 |

- **규칙:** 같은 학기 안에서 한 강의실의 같은 요일·교시에는 한 과목만 배정할 수 있습니다.
- **학기를 따로 두지 않은 이유:** 시간표에 학기 컬럼이 없어 `offe_id` 앞 6자리로 구합니다. 다른 학기에 같은 강의실·같은 칸을 쓰는 것은 정상이므로 `(room_code, weekday, period)`만 유일하게 하면 안 됩니다. 같은 개설과목(`offe_id`)의 중복은 기본키가 이미 막습니다.
- **스키마 파일 전체를 비교했을 때의 차이:** 수정 전 DDL과 `pg_dump -s`로 비교하면 위 CHECK 2개와 인덱스 1개만 다릅니다. 컬럼 재정렬은 구조에 영향이 없습니다.

### 샘플 데이터 정정

기존 샘플에는 같은 학기 안에서 같은 강의실·같은 칸에 여러 과목이 잡힌 곳이 있었습니다.

| 항목 | 값 |
|---|---|
| 충돌한 칸 | 10개 칸, 55행 |
| 옮긴 행 | 45행 (칸마다 1행은 그대로 두고 나머지를 같은 호관의 빈 강의실로 이동) |
| 규모 | 시간표 155행, 수강신청 220행 등 전/후 동일 |

이 정정 없이는 새 인덱스를 만들 수 없습니다. 수정 전(`HEAD`) 샘플을 새 DDL에 적재하면 `duplicate key value violates unique constraint "uq_sche_room_slot"`로 실패합니다.

### 검증 방법

별도 검증 스크립트는 없고, 임시 DB를 만들어 직접 확인했습니다 (2026-11-10, PostgreSQL 17.10). 같은 방법으로 다시 확인하려면 컨테이너에서 임시 DB에 `create_ddl.sql`, `insert_data.sql` 순서로 적재합니다.

| 점검 | 결과 |
|---|---|
| 새 DDL + 새 샘플 적재 | 에러 없음. 학과 11, 구성원 60, 개설과목 119, 시간표 155, 수강신청 220 |
| 새 DDL + 수정 전 샘플 적재 | `uq_sche_room_slot` 위반으로 실패 (`202602, MBB101, 1, 1`) |
| 같은 학기·같은 강의실·같은 칸에 다른 과목 INSERT | 거부 (`unique_violation`) |
| 요일 9, 교시 11 INSERT | 각각 `ck_sche_weekday`, `ck_sche_period`로 거부 |
| 다른 학기에는 쓰이지만 이 학기에는 비어 있는 칸에 INSERT | 허용 |
| 적재된 시간표의 요일·교시 범위 | 요일 1~5, 교시 1~10 (CHECK 통과) |
| 수정 전 샘플의 충돌 | 10개 칸 55행(추가분 45행) |

### 성능 영향

정보시스템 쿼리 6개를 `school/estimation_response_time_and_resource.sh`로 다시 돌려 기존 로그(`school/results/`)와 비교했습니다. 다시 돌린 결과는 임시 폴더에만 저장했고 저장소의 로그와 `EXECUTION_TIME_COMPARISON.md`는 **고치지 않았습니다**.

| 점검 | 결과 |
|---|---|
| 플랜 노드 구성 (전/후 6개 쿼리씩 12개) | 12개 모두 기존과 같음 |
| 새 인덱스 `uq_sche_room_slot`을 쓰는 플랜 | 없음 |
| 결과 행수 | 전/후 6개 쿼리 모두 기존과 같음 |
| 실행 시간 중앙값 합계, 전 | 1.754 → 1.893 ms |
| 실행 시간 중앙값 합계, 후 | 1.357 → 1.390 ms |

플랜이 바뀌지 않았고 새 인덱스를 읽는 곳도 없으므로 읽기 성능은 그대로라고 봅니다. 합계의 소폭 차이는 이전 측정 때도 나타나던 반복 측정 흔들림 수준으로 보이지만, 10회 측정 범위가 겹치는지까지는 따지지 않았습니다. 쓰기(INSERT) 비용은 측정하지 않았습니다. 시간표 행마다 인덱스 항목이 하나 늘어납니다.

### 동작 변경

- **`create_ddl.sql`을 실행하면 정규화 테이블 8개를 먼저 지웁니다** (`tbl_enrl_t1`, `tbl_sche_d1`, `tbl_offe_d1`, `tbl_room_l1`, `tbl_stud_m1`, `tbl_prof_m1`, `tbl_subj_m1`, `tbl_dept_m1`). 정규화 스키마가 들어 있는 DB에서 반정규화 DDL을 적용하는 용도이지만, 같은 DB에 정규화 데이터가 있으면 함께 사라지니 주의하세요. 반정규화 테이블(`*_m2`, `*_d2`, `*_t2`)은 지우지 않으므로 같은 DB에 두 번 실행하면 `already exists`로 실패합니다.
- 시간표를 INSERT하는 스크립트는 같은 학기에 한 강의실의 같은 칸을 겹쳐 쓰면 실패합니다. 기존 샘플(수정 전)이 그 경우입니다.

### 기록해 두는 가정과 범위 밖

- 학기는 `offe_id` 앞 6자리에서 구합니다. `tbl_subj_d2`의 `ck_subj_semester`가 `semester`와 앞 6자리가 같음을 강제하므로 둘은 어긋나지 않습니다.
- 강의실 이중 배정만 막습니다. 같은 교수가 같은 칸에 두 과목을 맡는 경우, 같은 학생이 시간이 겹치는 두 과목을 신청하는 경우는 검사하지 않습니다.
- 반정규화에서는 `room_code`가 외래키가 아니므로 존재하지 않는 강의실 코드도 들어갈 수 있습니다 (v2.0.0부터의 설계).
- 정규화(v1.1.0)에는 요일·교시 CHECK를 넣지 않았습니다. 전/후 비교에서 제약 개수가 다릅니다.

---

## v2.0.0: 반정규화

- 위치: `school/postgresql_denormalization/` (`create_ddl.sql`, `insert_data.sql`, `information_system.sql`)
- 커밋: `b677a49` 설계 → `1e603c3` 샘플 데이터 → `10c90a4` 정보시스템 쿼리 (모두 2026-10-30)
- 부속: `school/estimation_response_time_and_resource.sh` (`9881f61`) 응답시간·리소스 측정 스크립트, `school/EXECUTION_TIME_COMPARISON.md`와 `school/results/` (`b117a8a`) 측정 문서·원본 로그
- 기준: v1.0.0에서 변환
- 규모: 테이블 8개 → 5개, 트리거 함수 1개·트리거 1개 신규

### 요약

학생·교수를 구성원 테이블 하나로 합치고, 과목과 개설과목을 하나로 합치고, 강의실 룩업 테이블을 시간표에 흡수했습니다. 식별용 대리키(`sche_id`, `enrl_id`)는 부모 키와 순번의 복합 키로 바꿨습니다.

### 구조 변경 (호환되지 않음)

| 테이블 | 변경 |
|---|---|
| `tbl_dept_m1` → `tbl_dept_m2` | 학과 신설 일자(`created_at`), 종료 일자(`suspended_at`) 추가 (NOT NULL) |
| `tbl_stud_m1` + `tbl_prof_m1` → `tbl_pers_m2` | 학생·교수 통합. `person_id VARCHAR(10)`(학생 10자리, 교수 9자리), 구성원 유형 `person_type`('S'/'P'), 입교 경로 `entry_type`('N' 처음 / 'T' 옮겨옴) 추가 |
| `tbl_pers_m2.status` | 재적 상태 확장: 학생 'E'/'G' → 'A' 재학·재직 / 'L' 휴학·휴직 / 'D' 중퇴·사직 / 'G' 졸업·퇴직. 기존 'E'는 'A'로 변환, NOT NULL DEFAULT 'A' |
| `tbl_pers_m2.grade`, `rank` | 학생 전용·교수 전용으로 NULL 허용. `ck_pers_kind`가 유형별로 한쪽만 채우고 ID 길이(학생 10, 교수 9)도 맞추도록 강제 |
| `tbl_pers_m2` | `UNIQUE (person_id, person_type)` 추가 (복합 FK의 대상 키) |
| `tbl_subj_m1` + `tbl_offe_d1` → `tbl_subj_d2` | 과목·개설과목 통합. 기본키 `offe_id`, 과목 정보(`subj_id`, `semester`, `name`, `description`, `course`, `score`)는 개설 행마다 복사(스냅샷) |
| `tbl_subj_d2` | 교수 참조를 `prof_id CHAR(9)` 단일 FK에서 `(prof_id, prof_type)` 복합 FK로 변경 (`prof_type`은 'P' 고정). 교수만 지정 가능 |
| `tbl_room_l1` | **삭제**. 강의실 정보는 `tbl_sche_d2.room_code`로 흡수 |
| `tbl_sche_d1` → `tbl_sche_d2` | `room_id`(FK) → `room_code`(FK 없음). `sche_id` 삭제, 기본키를 `(offe_id, weekday, period)`로 변경해 개설과목과 식별 관계로 전환 |
| `tbl_enrl_t1` → `tbl_enrl_t2` | 시간표(`sche_id`) 대신 개설과목(`offe_id`) 참조. `enrl_id CHAR(18)` 삭제, 기본키 `(offe_id, enrlno)` (신청 순번 2자리 제한이 INT로 풀림). 학생은 `(stud_id, stud_type)` 복합 FK. `UNIQUE (offe_id, stud_id)`로 같은 개설 중복 신청 방지 |

### 제약·트리거 추가

| 대상 | 내용 |
|---|---|
| `tbl_pers_m2` | `sex` ('M','F'), `entry_type`, `status`, `rank`, `person_type` 값 범위 CHECK |
| `tbl_subj_d2` | `ck_subj_semester` (`offe_id` 앞 6자리 = `semester`), `ck_subj_code` (`offe_id` 7~11자리 = `subj_id`) |
| `tbl_enrl_t2` | `enrlno > 0`, `stud_type = 'S'` |
| `fn_subj_freeze` / `trg_subj_freeze` | BEFORE UPDATE OF 과목 정보 컬럼 ON `tbl_subj_d2`. 해당 개설에 수강신청이 하나라도 있으면 과목 정보 수정 거부. 과거 행 오타 정정은 `ALTER TABLE tbl_subj_d2 DISABLE TRIGGER trg_subj_freeze`로 잠시 끄고 처리 |

### 샘플 데이터

- 룩업·대리키 제거에 맞춘 INSERT로 재작성. 학생·교수는 구성원 60행, 과목+개설은 119행으로 통합
- 개설되지 않은 과목 4개와 쓰이지 않는 강의실 560개는 반정규화 구조에 담을 곳이 없어 제외
- 규모 (전/후): 학과 11, 개설과목 119, 시간표 155, 수강신청 220. 전은 학생 30, 교수 30, 과목 123, 강의실 660

### 정보시스템 쿼리 변경

| 번호 | 변경 |
|---|---|
| 1, 4 | 교수가 `tbl_pers_m2`로 바뀜. 조인 수 같음 |
| 2 | 개설과목·과목이 `tbl_subj_d2` 하나로, 강의실 조인은 `room_code`로 대체. SQL 조인 5개 → 3개 |
| 3 | 강의실·과목 조인 제거. SQL 조인 4개 → 2개 |
| 5 | 강의실 조인 제거, 호관은 `room_code` 앞 2자리. SQL 조인 3개 → 2개 |
| 6 | 시간표·과목 조인 제거. 뷰 안 SQL 조인 4개 → 2개 |

### 성능 측정 결과 (v1.0.0 → v2.0.0)

환경: PostgreSQL 17.10 (aarch64), 쿼리당 10회, `EXPLAIN (ANALYZE, BUFFERS, ...)`, 중앙값 기준. 상세는 [EXECUTION_TIME_COMPARISON.md](EXECUTION_TIME_COMPARISON.md), 원본 로그는 [results/](results)에 있습니다.

| 지표 (6개 쿼리 합, 전 → 후) | 결과 |
|---|---|
| 실행 시간 | 1.75 → 1.36 ms (-23%). 2·3·5·6번은 10회 측정 범위가 겹치지 않아 후가 빠름, 1·4번은 겹쳐서 차이 없음 |
| 실행 버퍼 hit | 122 → 96 (-21%) |
| 계획 시간 | 3.33 → 3.46 ms (+4%). 줄지 않음 |
| 플래너 메모리 used | 1016 → 838 kB (-18%) |
| 조인 수 | 22 → 15 (-32%) |

조인이 줄어든 2·3·5·6번이 빨라졌습니다. 데이터가 작아서(구성원 60, 개설과목 119, 시간표 155, 수강신청 220) 절대 시간은 모두 0.5 ms 미만입니다. 이 측정은 v2.1.0 이전 데이터·스키마 기준입니다.

### 알려진 한계

- 같은 학기에 한 강의실의 같은 칸에 여러 과목을 배정할 수 있습니다. 샘플 데이터에도 이런 행이 있었습니다. → v2.1.0에서 해결
- 시간표의 요일·교시 범위를 검사하지 않습니다. → v2.1.0에서 해결
- `room_code`에 외래키가 없어 없는 강의실 코드를 넣을 수 있습니다 (룩업 테이블 삭제의 대가).

---

## v1.1.0: 정규화 + 강의실 이중 배정 방지

> 커밋: `b0b4dd2` (2026-11-10)
> 기준(롤백 지점): v1.0.0 (`3e7b21a`)

| 파일 | 변경 |
|---|---|
| `postgresql/postgresql_create_ddl.sql` | `tbl_sche_d1`에 유일 인덱스 `uq_sche_room_slot ON (SUBSTRING(offe_id FROM 1 FOR 6), room_id, weekday, period)` 추가 |
| `postgresql/postgresql_insert_data.sql` | `tbl_sche_d1` INSERT 중 45행의 `room_id` 변경 (v2.1.0과 같은 정정) |

- 규칙과 학기를 구하는 방식은 [v2.1.0](#v210-강의실-이중-배정-방지)과 같습니다. 정규화·반정규화의 비교 기준을 맞추려고 같이 넣었습니다.
- 요일·교시 CHECK는 넣지 않았습니다 (v2.1.0에만 있음).
- 검증은 v2.1.0과 같은 방법으로 했습니다. 수정 전 샘플은 새 인덱스에서 같은 위치(`202602, MBB101, 1, 1`)로 실패하고, 새 DDL + 새 샘플은 에러 없이 적재됩니다 (학과 11, 학생 30, 교수 30, 과목 123, 개설과목 119, 강의실 660, 시간표 155, 수강신청 220).
- 성능: 플랜·결과 행수는 v2.1.0의 점검과 같습니다 (정규화 6개 쿼리 모두 기존과 같은 플랜, 새 인덱스를 쓰는 곳 없음).
- MINOR(v1.1.0)로 부여한 이유: 읽기 쿼리는 그대로 동작합니다. 시간표 INSERT는 같은 학기에 같은 칸을 겹쳐 쓰면 실패하지만 구조 자체는 깨지지 않습니다.

---

## v1.0.0: 정규화 (기준)

- 위치: `school/postgresql/` (`postgresql_create_ddl.sql`, `postgresql_insert_data.sql`, `postgresql_select_data.sql`, `postgresql_information_system.sql`)
- 커밋: `1ab0599` DDL → `a1229e0` 데이터 → `6ad6046` 조회 → `b932836` 정보시스템 쿼리 (2025-12-22), `6bebde1` 학생 `status`·수강신청 `ygrade` 컬럼 추가 (2026-10-05), `b24967d` 서브폴더로 이동 → `376551f` 샘플 학기를 2026으로 이동하고 신청 학년 채움 → `3e7b21a` 학기 비교를 `CHAR(6)`으로 맞춤 (2026-10-30)
- 규모: 테이블 8개

### 구조

| 분류 | 테이블 |
|---|---|
| 마스터 (`_m1`) | `tbl_dept_m1`(학과), `tbl_stud_m1`(학생), `tbl_prof_m1`(교수), `tbl_subj_m1`(과목) |
| 룩업 (`_l1`) | `tbl_room_l1`(강의실) |
| 이력·관계 (`_d1`, `_t1`) | `tbl_offe_d1`(개설과목), `tbl_sche_d1`(시간표), `tbl_enrl_t1`(수강신청) |

### 특징

- 대리키·파생 키 사용: `sche_id`(개설ID 13 + 요일 1 + 교시 2 = 16자리), `enrl_id`(시간표ID 16 + 신청순서 2 = 18자리, 신청 순서가 2자리라 개설당 99명 제한)
- 학생(`CHAR(10)`)과 교수(`CHAR(9)`)가 별도 테이블이고, 개설과목이 과목(`subj_id`)·교수(`prof_id`)를 외래키로 참조합니다.
- 수강신청은 시간표(`sche_id`)를 참조하므로 개설과목은 시간표를 거쳐 찾습니다.
- 모든 외래키는 `ON UPDATE CASCADE ON DELETE RESTRICT`입니다.
- CHECK 제약은 `tbl_stud_m1.status IN ('E','G')` 하나뿐입니다 (`E` 재학, `G` 졸업). 요일·교시·성별·직급 등의 값 범위 검사는 없습니다.
- 샘플 학기는 202601, 202602입니다. 정보시스템 쿼리 1~5번은 학기 조건을 `CURRENT_DATE`로 계산하므로 다른 해에 실행하면 결과가 0건입니다.
