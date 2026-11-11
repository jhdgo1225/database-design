# cinema DB 버전 이력 (패치노트)

PostgreSQL `cinema` 스키마의 버전별 변경 이력입니다. 스키마가 바뀔 때마다 이 문서 맨 위에 새 버전을 추가합니다.

- 버전 규칙: `MAJOR.MINOR.PATCH`
  - MAJOR: 테이블 추가·삭제, 컬럼 이름·타입 변경 등 기존 쿼리·데이터가 그대로 동작하지 않는 변경
  - MINOR: 기존 쿼리를 깨지 않는 컬럼·제약·트리거 추가
  - PATCH: 주석·용어·데이터 정정, 샘플·측정 도구 추가 등 구조가 바뀌지 않는 수정
- 기록 시점: 2026-11-11, git HEAD `1fca8cd`
- 각 버전은 스키마 파일(DDL), 샘플 데이터, 정보시스템 쿼리 세 가지를 한 묶음으로 봅니다.

| 버전 | 이름 | 상태 | 위치 | 마지막 변경 커밋 |
|---|---|---|---|---|
| v2.1.1 | 용어 정리·대량 샘플·측정 도구 (현재) | 커밋 전 | `cinema/postgresql_denormalization/` | 아직 없음 |
| v2.1.0 | 이용 가능 좌석 수 반영 | 적용됨 | `cinema/postgresql_denormalization/` | `e87c8d8` (2026-11-10) |
| v2.0.0 | 반정규화 | 적용됨 | `cinema/postgresql_denormalization/` | `de58a35` (2026-10-30) |
| v1.0.0 | 정규화 (기준) | 적용됨 | `cinema/postgresql/` | `ee39242` (2026-10-30) |

> MySQL 버전(`cinema/mysql/`, 2025-12-22 최초 커밋 `aacab33`~`f47d280`)은 별도 제품 계열이라 이 이력의 범위에 넣지 않았습니다.

---

## v2.1.1: 용어 정리·대량 샘플·측정 도구 (현재)

> 커밋: 아직 없음 (커밋한 뒤 해시를 채웁니다)
> 기준(롤백 지점): v2.1.0 (`e87c8d8`)
> 구분: PATCH. 테이블·컬럼·제약·트리거의 구조는 v2.1.0과 같고, 용어·메시지·별칭, 샘플 데이터, 측정 도구가 바뀝니다.

### 변경 요약

- 좌석 용어를 통일했습니다. 컬럼 이름은 그대로 두고 문서·주석·메시지의 말만 바꿨습니다. 문장 속에서는 띄어 쓰고, SQL 별칭과 컬럼 이름은 따옴표 없이 쓰려고 붙여 씁니다.

| 컬럼 | v2.1.0 표현 | v2.1.1 표현 |
|---|---|---|
| `tbl_thtr_m1.seat` | 총 좌석수 | 총 좌석 수 |
| `tbl_scrn_m1.capacity` | 정원, 이용 가능 정원 | 이용 가능 좌석 수 |
| `tbl_scrn_m1.planned_capacity` | 희망 정원 | 계획 좌석 수 |
| `status = 'Y'`인 좌석의 개수 | 이용 가능 좌석수 | Y 상태 좌석 수 (이 이용 가능 좌석 수와 겹치지 않게 구분) |

- 정보시스템 4·5·8·9번의 출력 컬럼 이름이 바뀝니다: `정원` → `이용가능좌석수`, `정원합계` → `이용가능좌석수합계`. 결과 값과 실행 계획은 같습니다.
- 트리거 함수의 에러 메시지 문구가 바뀝니다 (예: `희망 정원(%)이 …` → `계획 좌석 수(%)가 …`). SQLSTATE와 검사 조건은 같습니다.
- `create_ddl.sql` 맨 앞에 기존 객체를 지우는 `DROP` 단계를 넣어 다시 실행할 수 있게 했습니다.
- 대량 샘플 생성기를 추가했습니다. 영화 300편, 상영관 30개, 상영 약 13,700회, 회원 20,000명, 예매 약 31.5만 건, 충전 6만 건, 찜 약 6만 건이고 값은 md5 해시로 정합니다. 정규화·반정규화에 논리적으로 같은 데이터를 넣습니다.
- 응답시간·리소스 측정 도구를 바꿨습니다. 독립된 DB 두 개(`cinema_normalized_bench`, `cinema_denormalized_bench`)를 미리 적재하고 `VACUUM (ANALYZE)` 한 뒤 번갈아 측정하며, 자원 측정(전체 `EXPLAIN` 옵션 3회)과 시간 측정(`TIMING OFF` 30회)을 나눴습니다.

### 변경된 파일

| 파일 | 변경 |
|---|---|
| `postgresql_denormalization/create_ddl.sql` | 용어·에러 메시지 문구, 맨 앞 `DROP` 단계 |
| `postgresql_denormalization/insert_data.sql` | 헤더 주석의 용어 |
| `postgresql_denormalization/information_system.sql` | 4·5·8·9번의 별칭과 주석 |
| `postgresql_denormalization/verify_integrity.sql`, `run_verify_integrity.sh` | 케이스 라벨·주석의 용어 |
| `postgresql_denormalization/insert_data_bulk.sql` | 대량 샘플 생성기 (신규). 적재 중 사용자 트리거를 끄고, 적재 뒤 규칙을 SQL로 확인한 다음 다시 켬 |
| `postgresql/postgresql_insert_data_bulk.sql` | 정규화 쪽 대량 샘플 생성기 (신규) |
| `estimation_response_time_and_resource.sh` | `setup`·`measure`·`all`·`drop`, 두 DB 번갈아 측정, 자원·시간 두 단계 측정 (다시 작성) |
| `summarize_estimation_result.sh` | 시간 로그와 자원 로그를 읽어 쿼리별 중앙값·사분위 범위·CV 요약 (신규) |
| `results_bulk_interleaved_parallel0/`, `results_bulk_interleaved_parallel2/` | 직렬·병렬 측정 로그 (신규) |
| `EXECUTION_TIME_COMPARISON_BULK.md` | 대량 샘플 비교 문서 (신규) |

### 검증 방법과 결과

- `sh cinema/postgresql_denormalization/run_verify_integrity.sh`: PASS 199 / FAIL 0 / ERROR 0 (`STRESS=1` 없음).
- 임시 `_bench` DB 두 개에 `setup`으로 DDL·기본 샘플·대량 샘플을 새로 적재했고, 대량 샘플 생성기의 검증 구문이 통과했습니다. 반정규화 쪽 정보시스템 쿼리 9개도 새 별칭으로 실행됩니다.
- 용어를 바꾸기 전에 만든 측정용 DB에서 정보시스템 쿼리 9개의 결과를 두 DB에서 실행해 행을 정렬해 비교했고 값이 모두 같았습니다.

### 성능 측정 결과 (v1.0.0 → v2.1.x, 대량 샘플)

환경: PostgreSQL 17.10 (aarch64), 예매 315,022건, 시간 측정 30회 중앙값. 상세는 [EXECUTION_TIME_COMPARISON_BULK.md](EXECUTION_TIME_COMPARISON_BULK.md), 원본 로그는 [results_bulk_interleaved_parallel0/](results_bulk_interleaved_parallel0)(직렬), [results_bulk_interleaved_parallel2/](results_bulk_interleaved_parallel2)(병렬)에 있습니다. 측정은 이 버전의 용어 변경 전 파일로 했고, 변경은 주석·메시지·별칭뿐이라 실행 계획은 같습니다.

| 지표 (9개 쿼리 합, 전 → 후) | 결과 |
|---|---|
| 실행 시간 (직렬) | 815.8 → 835.6 ms (+2.4%). 3번 +7.7%, 6번 +4.2%, 4번 -3.9% |
| 실행 시간 (병렬) | 660.2 → 663.5 ms (+0.5%) |
| 계획 시간 | 8.28 → 8.39 ms (+1.3%) |
| 계획 버퍼 hit / 플래너 메모리 | 2,150 → 2,092 (-3%) / 598 → 507 kB (-15%) |
| 실행 버퍼 hit | 23,452 → 27,234 (+16%). 예매 테이블이 커진 영향 |
| 조인 수 | 13 → 9 (-31%) |
| 저장 공간 | 53 → 61 MB (+16.7%) |

기본 샘플에서는 실행 시간 차이가 없었지만(아래 v2.0.0 항목) 예매 31.5만 건에서는 후가 약간 느리거나 비슷하고, 조인이 줄어든 이득은 계획 단계(버퍼·메모리)에서만 보입니다. 읽기 쿼리만 쟀고 트리거의 쓰기 비용은 측정하지 않았습니다.

### 알려진 한계

- 반정규화의 트리거 4개와 `UNIQUE (scrn_id, seatcode)` 인덱스가 쓰기에 주는 영향은 대량 샘플에서 측정하지 않았습니다(대량 적재도 사용자 트리거를 끄고 했습니다).
- 측정은 한 번의 실험이고 `shared_buffers`는 128MB 하나만 썼습니다.

---

## v2.1.0: 이용 가능 좌석 수 반영

> 커밋: `4a887dc` 이용 가능 좌석 수 계산 트리거 → `3b761f7` 예매 규칙 → `cbdebec` 값 형식 CHECK → `e87c8d8` 무결성 검증 스크립트 (모두 2026-11-10)
> 기준(롤백 지점): v2.0.0 (`de58a35`)

### 변경된 파일

| 파일 | 변경 |
|---|---|
| `postgresql_denormalization/create_ddl.sql` | 스키마 변경 + 함수 4개 + 트리거 4개 + 중복 예매 방지 `UNIQUE (scrn_id, seatcode)` |
| `postgresql_denormalization/insert_data.sql` | `tbl_scrn_m1` INSERT의 컬럼명 `capacity` → `planned_capacity`, 헤더 주석 |
| `postgresql_denormalization/information_system.sql` | 4·5·8·9번의 좌석수 별칭을 `이용가능좌석수`/`이용가능좌석수합계`로 변경, 주석 |
| `postgresql_denormalization/verify_integrity.sql` | 무결성 검증 케이스 C01~C14, X01~X07, P01~P02, S01, K01~K10, D01~D05, B01~B07, F01~F06 + 동시성·데드락 수동 재현 절차(주석) (신규) |
| `postgresql_denormalization/run_verify_integrity.sh` | 임시 DB 생성·적재·동시성 C15·C16·C18~C20 실행, `STRESS=1`이면 C17 부하 테스트, 요약 (신규) |

### 검증 방법

```
sh cinema/postgresql_denormalization/run_verify_integrity.sh
```

임시 DB(`cinema_verify_bench`)를 만들어 실행하고 끝나면 지웁니다. 케이스마다 결과 열에 `PASS`/`FAIL`이 찍히고 마지막에 건수를 요약합니다. 하나라도 `FAIL`이거나 예상 밖 `ERROR`가 있으면 종료 코드가 1입니다. C01~C14는 모두 `BEGIN ... ROLLBACK` 안에서 실행해 데이터가 남지 않고, 세션이 둘 필요한 C15~C20은 케이스 사이에 상태를 되돌립니다.

| 환경변수 | 효과 |
|---|---|
| `STRESS=1` | C17 부하 테스트(`pgbench` 8세션)까지 실행 (`STRESS_SECONDS`로 시간 조절, 기본 10초) |
| `REVERT_FIX=1` | 데드락 수정을 뺀 수정 전 잠금 순서로 적재. C16·C17이 `FAIL`로 나와야 정상이며, 검증이 실제로 데드락을 잡는지 확인하는 용도 |
| `KEEP_DB=1` | 끝나고 임시 DB를 지우지 않음. 터미널 2~3개로 데드락을 직접 따라 해 볼 때 사용 (절차는 `verify_integrity.sql` 끝의 주석) |

### 검증 결과 (임시 DB, PostgreSQL 17)

`STRESS=1`로 케이스 59개(점검 200건)를 모두 통과했습니다 (PASS 200 / FAIL 0 / ERROR 0).

| 케이스 | 내용 |
|---|---|
| C01~C14 | 좌석 상태 → 이용 가능 좌석 수 규칙, 지난·상영 중 상영, 예매 충돌, 기본 제약, 적재 데이터 정합성 |
| C15~C20 | 동시성: 직렬화(C15), 데드락 재현(C16), 부하 테스트(C17, `STRESS=1`, 상영 수정·좌석 변경·예매·취소 혼합), 동시 중복 예매(C18), 이용 가능 좌석 수 마지막 1석 경쟁(C19), 좌석 상태 변경과 예매의 경쟁 두 방향(C20a·C20b) |
| B01~B07 | 예매 규칙: 예정 상영에서 이용 불가 좌석 예매 거부, 이용 가능 좌석 수 초과 예매 거부(전화 예약·좌석 지정 모두), 이용 불가 좌석이 이용 가능 좌석 수를 줄이면 예매 가능 수도 감소, 취소 후 재예매, 지난 상영(이용 불가 좌석은 허용·이용 가능 좌석 수 초과는 거부), 예매 UPDATE(좌석 변경·상영 이동), 계획 좌석 수를 예매 수보다 낮추는 변경 거부 |
| F01~F06 | 값 형식: 영화 `status`(I/S/D)·`agerating`(A/T/F/N) 코드값, 종료일·상영시간·요금(미정은 NULL), 충전 금액 양수, 회원·관리자 전화번호(숫자 11자리)·이메일 형식. 거부 입력과 함께 정상 입력(`D` 상태, 종료일 = 시작일, 요금 0·NULL 등)이 저장되는지도 확인 |
| K01~K10 | 기존 제약 점검: 회원·인물·예매·충전 CHECK(코드값, 범위, 결제수단별 금액 조합, 온라인 결제수단 필수, 결제 시각과 결제수단 동시 존재), 필수값, 길이 초과, FK 존재, PK 중복, 삭제 제한(ON DELETE RESTRICT), 수정 전파(ON UPDATE CASCADE), NOT VALID 제약 없음 |
| D01~D05 | 중복 예매 방지: 같은 상영·같은 좌석 중복 거부, 좌석 미지정 전화 예약은 여러 건 가능, 다른 상영의 같은 좌석은 가능, 취소 후 재예매 가능, UPDATE로 이미 예매된 좌석으로 바꾸는 것도 거부 |
| X01~X02 | 금액·결제수단 불일치 입력 거부 (적립금 결제인데 마일리지 금액 / 미결제인데 금액 있음) |
| X03~X04 | 다른 상영관 좌석 예매 거부 (예매의 상영관이 상영과 다름 / 그 상영관에 없는 좌석 A20) |
| X05~X06 | 상영의 이용 가능 좌석 수 임의 값 차단 (계획 좌석 수 9999 거부, `capacity` 9999·7 직접 입력은 무시) |
| X07 | 출연 중복 거부 (`tbl_part_d1` PK) |
| P01~P02 | 미결제·좌석 미지정 전화 예약과 결제수단별(A/B/C) 정상 예매는 정상 저장 |
| S01 | 상영관 총 좌석 수 변경: 증가는 허용·이용 가능 좌석 수 전파 없음, 예정 상영보다 작게 감소는 거부, 지난 상영 무영향 |

X·P 케이스는 관련 제약을 하나씩 제거하면 각각 해당 케이스가 FAIL로 바뀌고(`tbl_bytk_d1` 결제 CHECK는 X01·X02, 복합 FK 두 개는 X03·X04, `tbl_part_d1` PK는 X07, 이용 가능 좌석 수 계산 트리거는 X05·X06, 총 좌석 수 보호 트리거는 S01), 정상 입력을 막는 제약을 추가하면 P02가 FAIL로 바뀌는 것을 확인했습니다.

K·D 케이스는 같은 방식으로 제약을 하나씩 빼거나 바꿔서 확인했고(중복 예매 UNIQUE 제거 → D01·D04·D05, CHECK 제거 → K01~K04, 예매 회원 FK 제거 → K05·K09, 삭제 제한 FK 5종을 `CASCADE`로 변경 → 각각 K08, `NOT VALID` 제약 추가 → K10), 이 과정에서 약한 케이스 두 개를 고쳤습니다. `buy_method = 'X'` 입력이 다른 CHECK에도 걸려서 이 제약이 있는지 구분하지 못했고, 회원 삭제 케이스는 충전·찜 FK에도 걸려서 예매 FK를 `CASCADE`로 바꿔도 통과했습니다. 지금은 대상 제약 하나만 위반하도록(K03) 또는 참조가 하나뿐인 새 행을 만들어(K08) 격리합니다.

예매 규칙(B·C19·C20)도 같은 방식으로 확인했습니다. 예매 트리거를 빼면 B01~B06, C19, C20b가, 좌석 행 `FOR SHARE`를 빼면 C20b가, 예매 쪽 상영 행 `FOR NO KEY UPDATE`를 빼면 C19가, 계획 좌석 수 하향 시 예매 수 검사를 빼면 B07이 FAIL로 바뀝니다. 잠금을 빼면 동시성 케이스가 실제로 실패한다는 뜻입니다. C20a는 좌석 변경 트리거가 상영 행을 `FOR UPDATE`로 잠그면서 예매 INSERT의 외래키 잠금과 이미 충돌해 예매 트리거 없이도 통과합니다. 부하 테스트(C17)에 예매·취소를 섞은 뒤에도 데드락 0건, 규칙 위반 0건이었습니다 (79,445건 처리).

값 형식 제약(F)도 CHECK를 하나씩 빼서 확인했고, 빼면 각각 해당 케이스(F01 영화 코드값, F02 날짜·숫자, F03 충전 금액, F04 회원 전화, F05 회원 이메일, F06 관리자)가 FAIL로 바뀝니다. `status`에서 `D`를 빼는 변경도 F01이 잡고, 정상 값(요금 0)을 막는 변경은 F02가 잡습니다.

> **동작 변경 (v2.0.0 → v2.1.0):** v2.0.0에서는 복합 FK `(thtr_id, capacity)`의 `ON UPDATE CASCADE`로 상영관 총 좌석 수 변경이 상영의 이용 가능 좌석 수로 전파되었습니다. v2.1.0은 이용 가능 좌석 수를 계획 좌석 수와 Y 상태 좌석 수로만 결정하므로 총 좌석 수 변경을 전파하지 않고 예정 상영의 계획 좌석 수보다 작게 줄이는 변경만 막습니다(S01). Y 상태 좌석 수 변경이 이용 가능 좌석 수로 전파되는 것은 C01·C02·C12에서 확인합니다.

트리거를 하나씩 빼고 다시 돌렸을 때 `trg_calc_scrn_capacity`는 C04·C05·C13에서 FAIL이 나오고 나머지 케이스에서 ERROR가 나왔고, `trg_apply_seat_change`는 C01·C02·C08·C09·C10·C12에서, `trg_protect_thtr_seat`는 C11에서 FAIL이 나와서 각 트리거가 빠지면 검증이 실패하는 것을 확인했습니다. 상영 중인 상영(C08)과 총 좌석 수 축소 보호(C11), 케이스 단위 롤백까지 모두 이 스크립트에 들어 있습니다.

| 시나리오 | 결과 |
|---|---|
| 예정 상영 150 → 좌석 10개 `'N'` → 복구 | 150 → 140 → 150 |
| `planned_capacity = 120`인 예정 상영 | 이용 가능 140에서 120 유지, 100으로 내려가면 100, 복구하면 120까지만 복구 |
| `planned_capacity` > 총 좌석 수 (INSERT·UPDATE, 지난 상영 포함) | 거부 (`check_violation`) |
| `capacity` 직접 입력 (예정·지난 상영) | 무시되고 계산값 유지 |
| 지난 상영 | 좌석 변경에 영향 없음, 좌석 `'N'` 상태에서 INSERT해도 `planned_capacity` 그대로 기록 |
| 예정 상영에서 예매된 좌석을 `'N'`으로 변경 | 거부 |
| 예매 수가 새 이용 가능 좌석 수를 넘게 되는 좌석 변경 (예매 150건) | 거부, 거부 후 `capacity` 150 유지 |
| 총 좌석 수를 예정 상영의 `planned_capacity`보다 작게 변경 | 거부 (예정 상영이 없는 상영관은 가능) |
| 이용 가능 좌석 삭제·추가 | 149 / 150으로 반영 |
| 없는 상영관 INSERT, 좌석 `status = 'X'` | 각각 `foreign_key_violation`, `check_violation` |
| 적재된 948개 상영 | 전부 `capacity <= planned_capacity <= 총 좌석 수` |
| 동시성 (상영 INSERT 미커밋 중 좌석 변경) | 좌석 변경이 약 2초 대기한 뒤 `capacity = 149`로 정확히 계산 |
| `information_system.sql` 9개 쿼리 | 에러 없이 실행 |

### 데드락 발견과 수정

구현 직후 동시성 점검에서 데드락이 발견되어 같은 v2.1.0 안에서 수정했습니다.

- **원인:** 상영 UPDATE 트리거(`fn_calc_scrn_capacity`)는 "상영 행 → 상영관 행(`FOR SHARE`)", 좌석 변경 트리거(`fn_apply_seat_change`)는 "상영관 행(`FOR NO KEY UPDATE`) → 상영 행" 순서로 잠가서 같은 상영관을 동시에 건드리면 서로를 기다렸습니다.
- **수정:** 좌석 변경 트리거가 그 상영관의 예정 상영 행을 `ORDER BY scrn_id FOR UPDATE`로 먼저 잠근 뒤 상영관 행을 잠급니다. 두 트리거의 순서가 "상영 행 → 상영관 행"으로 같아졌습니다.

| 점검 | 수정 전 | 수정 후 |
|---|---|---|
| C16 두 세션으로 잠금 순서를 엇갈리게 재현 | `deadlock detected`, 좌석 변경이 중단되고 롤백됨 | 둘 다 성공, 이용 가능 좌석 수 100, 좌석 A1은 `'N'` |
| C17 부하 테스트 (8세션, 10~15초, 상영 UPDATE와 좌석 변경 혼합) | 데드락 실패 20~28건, 약 11% (처리 54~222건) | 데드락 0건 (처리 37,440건) |
| 부하 후 `capacity` 정합성 불일치 | 0건 | 0건 |

수정 전 처리량이 낮은 것은 데드락 감지(`deadlock_timeout` 1초)를 기다리느라 멈춘 영향이 커서 수정 후와 그대로 비교할 수 없습니다. 부하 조건은 5개 상영과 1개 상영관을 8세션이 계속 두드리는 극단적인 경우라 실제 운영의 발생 빈도는 이보다 낮을 것입니다.

비용: 좌석 상태를 바꿀 때마다 그 상영관의 예정 상영 행을 모두 잠급니다 (상영관당 예정 상영은 현재 규모에서 약 100건).

### 성능 영향 (적재 시간)

`insert_data.sql` 전체 적재(좌석 1,750행, 상영 948행) 소요 시간, 3회 모두 같은 경향:

| 버전 | 소요 시간 |
|---|---|
| v2.0.0 | 약 0.13초 |
| v2.1.0 | 약 0.19초 (약 +45%) |

좌석 행마다 상영관 잠금·집계가 한 번, 상영 행마다 상영관 조회·집계가 한 번, 예매 행마다 상영·이용 가능 좌석 수 확인이 한 번(그리고 `UNIQUE (scrn_id, seatcode)` 인덱스 유지) 추가된 비용입니다 (예매 트리거와 유일 인덱스를 넣은 뒤 다시 측정). 정보시스템 쿼리의 실행 계획은 바뀌지 않았으므로(조회 컬럼은 그대로 `capacity`) v2.0.0 대비 읽기 성능 측정은 하지 않았습니다. v1.0.0 대비 v2.1.0의 읽기 성능은 대량 샘플로 따로 쟀습니다([EXECUTION_TIME_COMPARISON_BULK.md](EXECUTION_TIME_COMPARISON_BULK.md)).

### 배경

상영관의 일부 좌석이 이용 불가가 되어도 상영의 이용 가능 좌석 수(`capacity`)에 반영할 방법이 없었습니다. 예를 들어 150석 상영관에서 10석이 이용 불가여도 상영의 이용 가능 좌석 수는 150으로 남았습니다. 또한 v2.0.0의 복합 FK `(thtr_id, capacity)`는 이용 가능 좌석 수가 총 좌석 수와 "같아야 한다"만 강제할 수 있어서 140석 같은 값을 넣을 수 없습니다.

### 확정된 설계

| 항목 | 내용 |
|---|---|
| 좌석 `status` | `'Y'` 이용 가능, `'N'` 이용 불가. `CHECK`로 강제 |
| 이용 가능 좌석 수 모델 | `planned_capacity`(관리자 계획 좌석 수)를 새로 두고, `capacity`는 트리거가 계산하는 값으로 바꿈 |
| 예정 상영 (시작 시각 > `LOCALTIMESTAMP`) | `capacity = LEAST(planned_capacity, 현재 Y 상태 좌석 수)`. 좌석이 복구되면 `planned_capacity`까지 다시 올라감 |
| 지난·상영 중 상영 | `capacity = planned_capacity`를 그대로 기록. `planned_capacity ≤ 총 좌석 수`만 검사. 좌석 변경으로 자동 조정하지 않음 |
| 좌석 `'N'` 변경 | 예정 상영에 그 좌석 예매가 있거나, 예매 수가 새 이용 가능 좌석 수를 넘으면 거부 |
| 예매 INSERT/UPDATE | 예정 상영에서는 이용 불가(`'N'`) 좌석 예매 거부. 모든 상영(지난 상영 포함)에서 예매 수가 이용 가능 좌석 수를 넘으면 거부 |
| 계획 좌석 수 하향 | 계획 좌석 수를 이미 예매된 수보다 낮추는 UPDATE 거부 |
| 복합 FK | 쓰지 않음 |

### 스키마 변경 (예정)

| 대상 | 변경 | 분류 |
|---|---|---|
| `tbl_thtr_m1` | `UNIQUE (thtr_id, seat)` 삭제 | 제약 삭제 |
| `tbl_seat_m1` | `CHECK (status IN ('Y','N'))` 추가 | 제약 추가 |
| `tbl_scrn_m1` | `planned_capacity INT NOT NULL CHECK (>= 0)` 추가 | 컬럼 추가 |
| `tbl_scrn_m1` | `capacity`에 `CHECK (>= 0)` 추가, 값은 트리거가 계산 | 의미 변경 |
| `tbl_scrn_m1` | 복합 FK `(thtr_id, capacity)` 삭제, 단일 FK `thtr_id → tbl_thtr_m1(thtr_id)` 추가 | 제약 변경 |
| `tbl_scrn_m1` | `UNIQUE (scrn_id, thtr_id)` 유지 (`tbl_bytk_d1` FK 대상) | 변경 없음 |
| `tbl_bytk_d1` | `UNIQUE (scrn_id, seatcode)` 추가: 같은 상영의 같은 좌석 중복 예매 방지. `seatcode`가 NULL인 전화 예약(좌석 미지정)은 여러 건 가능 | 제약 추가 |
| `tbl_scmv_m1` | `status IN ('I','S','D')` (I 상영중 / S 상영예정 / D 상영종료, `D` 신규), `agerating IN ('A','T','F','N')` (A 전체 관람가 / T 12세 이상 / F 15세 이상 / N 청소년 관람불가), `playtime > 0`, `fee >= 0`(NULL 허용), `enddate IS NULL OR enddate >= startdate` | 제약 추가 |
| `tbl_chrg_d1` | `amount > 0` | 제약 추가 |
| `tbl_mebr_m1`, `tbl_mngr_m1` | `phone ~ '^[0-9]{11}$'` (하이픈 없는 숫자 11자리), `email ~ '^[^@[:space:]]+@[^@[:space:]]+$'` (공백 없는 "아이디@도메인" 형태, 완전한 이메일 검증은 아님) | 제약 추가 |

### 트리거 (예정)

| 함수 | 트리거 시점 | 역할 |
|---|---|---|
| `fn_calc_scrn_capacity` | BEFORE INSERT / UPDATE OF `planned_capacity`, `thtr_id`, `scrndate`, `scrntime`, `capacity` ON `tbl_scrn_m1` | `planned_capacity ≤ 총 좌석 수` 검사, `capacity` 계산. 직접 입력한 `capacity`는 계산값으로 덮어씀. 계획 좌석 수를 낮추는 UPDATE는 이미 예매된 수보다 작아질 수 없음 |
| `fn_apply_seat_change` | AFTER INSERT / UPDATE OF `status` / DELETE ON `tbl_seat_m1` | 예약된 좌석·이용 가능 좌석 수 초과 시 거부, 예정 상영의 `capacity` 재계산 |
| `fn_protect_thtr_seat` | BEFORE UPDATE OF `seat` ON `tbl_thtr_m1` | 예정 상영의 `planned_capacity`보다 작게 줄이는 변경 거부. 복합 FK의 `ON UPDATE CASCADE`를 대체 |
| `fn_check_bytk` | BEFORE INSERT / UPDATE OF `scrn_id`, `thtr_id`, `seatcode` ON `tbl_bytk_d1` | 예정 상영에서 이용 불가(`'N'`) 좌석 예매 거부, 모든 상영에서 예매 수가 이용 가능 좌석 수를 넘으면 거부. 없는 상영·좌석은 외래키가 거부하도록 통과시킴 |

동시성은 `tbl_thtr_m1`의 해당 행을 잠가서 상영관 단위로 직렬화합니다. 상영 쪽은 `FOR SHARE`, 좌석 쪽은 `FOR NO KEY UPDATE`입니다. 데드락을 피하기 위해 두 트리거 모두 "상영 행 → 상영관 행" 순서로 잠급니다 (좌석 쪽은 예정 상영 행을 `scrn_id` 순으로 먼저 `FOR UPDATE`). 예매 트리거는 좌석 행(`FOR SHARE`) → 상영 행(`FOR NO KEY UPDATE`) 순서로 잠가, 좌석 변경(좌석 행 → 상영 행 → 상영관 행)과 같은 방향이라 순환 대기가 없습니다. 자세한 내용은 아래 "데드락 발견과 수정"을 참고하세요.

### 호환성에 미치는 영향

- `tbl_scrn_m1`에 INSERT하는 쿼리는 `capacity` 대신 `planned_capacity`를 넣어야 합니다 (`insert_data.sql` 수정 필요). 기존 `capacity` 읽기 쿼리는 그대로 동작합니다.
- `information_system.sql`의 `총좌석수`/`좌석수` 별칭은 이제 "이용 가능 좌석 수"를 뜻하므로 라벨·주석을 수정합니다.
- 복합 FK가 하던 "총 좌석 수 변경 시 이용 가능 좌석 수 자동 전파"가 사라지고 "차단"으로 바뀝니다.
- 대량 적재 시 상영 행마다 상영관 조회·좌석 집계가 추가되어 적재 시간이 늘었습니다 (아래 성능 영향 참고).
- 영화·충전·회원·관리자 입력에 값 형식 검사가 새로 걸립니다(위 스키마 변경 참고). 영화 `status`에 `D`(상영종료)가 추가되었고, 기존 샘플 데이터(`status` I/S, `agerating` A/T/F/N, 전화번호·이메일, 충전 금액 10000~50000)는 모두 통과합니다. `agerating`의 코드 의미는 샘플 영화의 실제 등급(예: 백설공주와 일곱난쟁이 = A, 야당 = N)으로 대응시켰습니다.
- 영화 `status`와 날짜의 관계(예: `D` 상영종료는 종료일이 있어야 한다)는 검사하지 않습니다. 코드값과 `enddate >= startdate`만 확인합니다.
- 예매 INSERT/UPDATE가 새로 검사를 받습니다: 이용 가능 좌석 수를 넘거나(모든 상영), 예정 상영에서 이용 불가 좌석을 지정하면 거부됩니다. 기존 샘플 예매 80건은 모두 통과합니다. 지난 상영에 이용 가능 좌석 수보다 많은 예매를 적재하는 스크립트는 거부되므로 계획 좌석 수(`planned_capacity`)를 먼저 맞춰야 합니다.
- 버전 번호 판단: 위 버전 규칙으로는 `tbl_scrn_m1`의 INSERT 쿼리가 깨지므로 MAJOR에 해당하지만, 읽기 쿼리는 그대로 동작해서 MINOR(v2.1.0)로 부여했습니다. 기준을 바꾸고 싶으면 v3.0.0으로 고칩니다.

### 기록해 두는 가정과 범위 밖

- 시간대: `scrndate`와 `scrntime`에 시간대가 없어서 `LOCALTIMESTAMP`로 비교합니다. DB 서버 시간대 = 극장 현지 시간으로 가정합니다.
- "예매 수"는 결제 여부와 상관없이 `tbl_bytk_d1`의 모든 행으로 셉니다 (기존 `COUNT(b.bytk_id)`와 같은 기준).
- 지난 상영의 `planned_capacity` 수정은 막지 않습니다 (데이터 정정용). 총 좌석 수 이하인지만 검사합니다.
- 예매 규칙(`fn_check_bytk`): 이용 가능 좌석 수 초과 예매와 이용 불가 좌석 예매를 막기 전에는 이용 가능 좌석 수 1인 상영에 예매 6건이 저장되고 `'N'` 좌석 예매도 저장되는 것을 확인했습니다 (예매 쪽에 검사가 없었음). 이용 불가 좌석 검사는 현재 좌석 상태를 보므로 예정 상영에만, 이용 가능 좌석 수 검사는 그 상영 자체의 값이라 지난 상영에도 적용합니다.
- 이용 불가 좌석 예매 거부는 예매의 `seatcode`를 새로 지정하거나 바꿀 때만 검사합니다. 이미 예매된 좌석이 나중에 `'N'`이 되는 경우는 좌석 변경 트리거가 막습니다.
- 중복 예매 방지(`UNIQUE (scrn_id, seatcode)`)는 인덱스를 하나 더 만들므로 예매 INSERT·UPDATE 비용이 조금 늘고, `scrn_id`로 예매를 찾는 쿼리(정보시스템 4·5·8·9번의 조인, 좌석 변경 트리거의 예매 수 확인)에는 인덱스가 생깁니다. v1.0.0 대 v2.0.0 성능 비교(`EXECUTION_TIME_COMPARISON.md`)는 이 인덱스가 없던 시점의 측정이고, 인덱스가 있는 v2.1.0은 `EXECUTION_TIME_COMPARISON_BULK.md`에서 측정했습니다.
- 데드락 검증 범위: 상영 UPDATE와 좌석 변경의 조합만 부하 테스트(C17)로 확인했습니다. 상영 INSERT와 좌석 변경이 섞이는 경우, 상영관 총 좌석 수 UPDATE가 섞이는 경우는 부하로 돌려보지 않았습니다.
- 인덱스: 좌석 변경 시 예매 조회(`tbl_bytk_d1`의 `thtr_id`·`seatcode`·`scrn_id`)와 상영 조회(`tbl_scrn_m1`의 `thtr_id`)에는 전용 인덱스가 없어 순차 스캔합니다. 지금 데이터 규모(예매 80, 상영 948)에서는 문제없으나 커지면 인덱스 추가를 검토합니다.

---

## v2.0.0: 반정규화

- 위치: `cinema/postgresql_denormalization/` (`create_ddl.sql`, `insert_data.sql`, `information_system.sql`)
- 커밋: `89e8775` 설계 → `d8bb2f6` 샘플 데이터 → `d05595b` 정보시스템 쿼리 → `de58a35` 샘플 데이터 정리 (모두 2026-10-30)
- 기준: v1.0.0에서 변환
- 규모: 테이블 14개 → 11개

### 요약

룩업 테이블 3개를 본 테이블 컬럼으로 흡수하고, 식별용 대리키를 자연키로 교체하고, 조인을 줄이기 위해 상영에 이용 가능 좌석 수 컬럼을 추가했습니다. 그와 함께 CHECK 제약을 대폭 늘렸습니다.

### 구조 변경 (호환되지 않음)

| 테이블 | 변경 |
|---|---|
| `tbl_mbrt_l1` | **삭제**. 회원 등급 코드가 `tbl_mebr_m1.rating`으로 흡수됨 |
| `tbl_btpy_l1` | **삭제**. 예매 결제수단 코드가 `tbl_bytk_d1.pay_method`로 흡수됨 |
| `tbl_crpy_l1` | **삭제**. 충전 결제수단 코드가 `tbl_chrg_d1.charge_method`로 흡수됨 |
| `tbl_part_d1` | `part_id` 삭제, PK를 `(scmv_id, pers_id)`로 변경 |
| `tbl_seat_m1` | `seat_id` 삭제, PK를 `(thtr_id, seatcode)`로 변경 |
| `tbl_scrn_m1` | `capacity` 추가 (`tbl_thtr_m1.seat`를 반정규화한 값, 조인 제거용) |
| `tbl_scrn_m1` | `thtr_id` 단일 FK 삭제, 복합 FK `(thtr_id, capacity) → tbl_thtr_m1(thtr_id, seat)` 추가 |
| `tbl_thtr_m1` | `UNIQUE (thtr_id, seat)` 추가 (위 복합 FK의 대상 키) |
| `tbl_scrn_m1` | `UNIQUE (scrn_id, thtr_id)` 추가 (아래 `tbl_bytk_d1` FK의 대상 키) |
| `tbl_pers_m1` | `name` 30 → 255자, `eng_name`·`country_code`·`birth` 추가 |
| `tbl_mebr_m1` | `mbrt_id` → `rating`, `email` 50 → 320자 |
| `tbl_bytk_d1` | `thtr_id`·`seatcode` 추가, `seat_id`·`btpy_id`·`method` 삭제 |
| `tbl_bytk_d1` | 컬럼 이름·의미 변경: 구 `buydate` → `reserved_at`(예약 시도 시각), 구 `btpy_id` → `pay_method`(NULL이면 미결제), 구 `method` → `buy_method`, `buydate`는 결제 완료 시각(NULL 허용)으로 의미 변경 |
| `tbl_bytk_d1` | FK 변경: `scrn_id` 단일 FK → `(scrn_id, thtr_id)` 복합 FK, `seat_id` FK → `(thtr_id, seatcode)` 복합 FK |
| `tbl_chrg_d1` | `chargedate` → `charged_at`, `crpy_id` → `charge_method` |
| 시간 타입 | `TIMESTAMP` → `TIMESTAMPTZ` (`reserved_at`, `buydate`, `charged_at`) |

### 제약 추가

| 대상 | 제약 |
|---|---|
| `tbl_pers_m1.country_code` | `IN ('KOR','USA','GBR','CHN','JPN')` |
| `tbl_mebr_m1.sex` | `IN ('M','F')` |
| `tbl_mebr_m1.savings`, `mileage` | `>= 0` |
| `tbl_mebr_m1.rating` | `1 ~ 5`, 기본값 5 |
| `tbl_bytk_d1.buy_method` | `IN ('O','P')` (온라인/전화) |
| `tbl_bytk_d1.pay_method` | `IN ('A','B','C')` (적립금/마일리지/복합), NULL이면 미결제 |
| `tbl_bytk_d1` | 결제수단별 `savings`·`mileage` 조합 검사, 온라인 예매는 결제수단 필수, `buydate`와 `pay_method`는 함께 존재 |
| `tbl_chrg_d1.charge_method` | `IN ('A','B','C','D','E')` |

### 샘플 데이터

- 룩업 3개 테이블의 INSERT 제거, `tbl_seat_m1`의 `seat_id` 제거, `tbl_bytk_d1`의 `thtr_id` 추가
- `tbl_part_d1`의 `(scmv_id, pers_id)` 중복 1건 제거
- `tbl_scrn_m1.capacity` 추가 (해당 상영관의 `tbl_thtr_m1.seat` 값)
- 규모 (전/후 동일): 회원 30, 영화 10, 상영관 10, 좌석 1,750, 상영 948, 예매 80, 충전 40

### 정보시스템 쿼리 변경

| 번호 | 변경 |
|---|---|
| 1 | `mbrt_id` → `rating` (컬럼명만) |
| 4, 5, 8, 9 | `tbl_thtr_m1` 조인 제거, 좌석 수를 `tbl_scrn_m1.capacity`에서 읽음 |
| 6 | 비교 기준 `buydate` → `reserved_at` |
| 2, 3, 7 | 없음 |

### 성능 측정 결과 (v1.0.0 → v2.0.0)

환경: PostgreSQL 17.10 (aarch64), 쿼리당 10회, `EXPLAIN (ANALYZE, BUFFERS, ...)`, 중앙값 기준. 상세는 [EXECUTION_TIME_COMPARISON.md](EXECUTION_TIME_COMPARISON.md), 원본 로그는 [results/](results)에 있습니다.

| 지표 (9개 쿼리 합, 전 → 후) | 결과 |
|---|---|
| 실행 시간 | 7.29 → 7.13 ms (-2%). 분포가 겹쳐서 유의한 차이 없음 |
| 계획 시간 | 3.02 → 2.82 ms (-7%) |
| 계획 버퍼 hit | 1850 → 1591 (-14%) |
| 플래너 메모리 | 592 → 470 kB (-21%) |
| 실행 버퍼 hit | 98 → 104 (+6%), 컬럼 추가로 테이블이 커진 영향 |
| 조인 수 | 13 → 9 (-31%) |

데이터가 작아서 실행 시간 차이는 측정되지 않았고, 조인이 줄어든 만큼 계획 단계 비용이 줄어든 점이 가장 믿을 만한 이득입니다. 다만 대량 샘플로 v2.1.0을 쟀을 때는 계획 시간이 줄지 않았고(9개 쿼리 합 8.28 → 8.39 ms) 계획 버퍼(-3%)와 플래너 메모리(-15%)만 줄었습니다. 자세한 내용은 [EXECUTION_TIME_COMPARISON_BULK.md](EXECUTION_TIME_COMPARISON_BULK.md)에 있습니다.

### 알려진 한계

- `tbl_seat_m1.status`에 값 정의와 `CHECK`가 없습니다 (현재 데이터는 전부 `'Y'`). 이용 불가 좌석을 상영의 이용 가능 좌석 수에 반영하는 방법이 없습니다. → v2.1.0에서 해결 예정
- 총 좌석 수(`tbl_thtr_m1.seat`)와 이용 가능 좌석 수(`capacity`)가 "항상 같다"는 복합 FK로만 강제되어 이용 가능 좌석 수를 더 작게 둘 수 없습니다. → v2.1.0에서 해결 예정

---

## v1.0.0: 정규화 (기준)

- 위치: `cinema/postgresql/` (`postgresql_create_ddl.sql`, `postgresql_insert_data.sql`, `postgresql_information_system.sql`)
- 커밋: `0473625` DDL → `8d1154a` 데이터 (2026-10-05), `1796cea` 서브폴더로 이동하며 2026-10 데이터로 갱신 → `ee39242` 정보시스템 쿼리 (2026-10-30)
- 부속: `migration/shift_dates_to_current_month.sql` (`8720b4d`), 샘플 데이터의 날짜를 현재 월로 옮기는 스크립트
- 규모: 테이블 14개

### 구조

| 분류 | 테이블 |
|---|---|
| 마스터 (`_m1`) | `tbl_scmv_m1`(영화), `tbl_pers_m1`(인물), `tbl_thtr_m1`(상영관), `tbl_seat_m1`(좌석), `tbl_scrn_m1`(상영), `tbl_mebr_m1`(회원), `tbl_mngr_m1`(관리자) |
| 룩업 (`_l1`) | `tbl_mbrt_l1`(회원 등급), `tbl_btpy_l1`(예매 결제수단), `tbl_crpy_l1`(충전 결제수단) |
| 이력·관계 (`_d1`) | `tbl_part_d1`(영화-인물), `tbl_bytk_d1`(예매), `tbl_chrg_d1`(충전), `tbl_like_d1`(찜) |

### 특징

- 대리키 사용: `part_id`(`tbl_part_d1`), `seat_id`(`tbl_seat_m1`)
- 상영관 좌석 수는 `tbl_thtr_m1.seat`에만 있고, 정보시스템 쿼리가 필요할 때마다 `tbl_thtr_m1`을 조인해서 읽습니다.
- `tbl_bytk_d1.seat_id`는 원본 데이터가 값을 채우지 않아 NULL 허용으로 둡니다.
- CHECK 제약은 거의 없고(코드값 검증 없음), 시간 타입은 `TIMESTAMP`입니다.
