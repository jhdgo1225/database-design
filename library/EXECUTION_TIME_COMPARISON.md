# 도서관 정보시스템 쿼리 실행 시간 비교 (반정규화 전/후)

## 비교 조건

- before와 after의 차이는 **조인 1회 제거**와 **`book_held_id`의 기본키 데이터 타입 변경(VARCHAR(12) → UUID)** 두 가지입니다.
- 그 외 조건(`LIMIT` / `WITH TIES`, GROUP BY 키)은 통일했습니다.
- 도구: DBeaver `EXPLAIN ANALYZE`, 쿼리당 각 10회 측정, 값은 Execution Time(ms)입니다.
- 대상: 정보시스템 쿼리 1번(사본 단위), 3번, 5번, 6번

## 결과 요약

| 번호 | 변경 | 평균 | 중앙값 | 최소 |
|---|---|---|---|---|
| 1 (사본 단위) | 3개 중 1개 제거 | 0.142 → 0.128 | 0.089 → 0.121 | 0.071 → 0.063 |
| 3 | 조인 전부 제거 | 0.108 → 0.071 | 0.104 → 0.064 (약 39% 감소) | 0.061 → 0.041 |
| 5 | 3개 중 1개 제거 | 0.165 → 0.134 | 0.157 → 0.088 (약 44% 감소) | 0.077 → 0.064 |
| 6 | 3개 중 1개 제거 | 0.265 → 0.150 | 0.151 → 0.096 (약 36% 감소) | 0.093 → 0.065 |

- **3번, 5번, 6번**: 조인을 제거한 쪽이 일관되게 빨랐고, 분포 대부분이 before보다 낮습니다.
- **1번**: 평균과 최소값은 조금 낮고 중앙값은 높아서 방향이 엇갈립니다. 두 분포가 완전히 겹치므로 차이가 없다고 봅니다.
- 6번 before 평균에는 0.996 ms 이상치 한 번이 포함되어 있습니다. 이상치를 빼면 평균은 0.184입니다.
- 5번은 제거된 조인이 Nested Loop + Index Scan(`tbl_book_1_pkey`, 11회 반복)이며, 이 단계가 약 0.015 ms를 차지합니다. after에도 0.389, 0.228 이상치가 있어 평균 차이(약 19%)가 중앙값 차이(약 44%)보다 작습니다. 0.1 ms 아래로 끝난 횟수는 before 1/10, after 6/10입니다.

## 쿼리

### 1번: 대출 상위 5위의 도서 정보

```sql
-- before
SELECT b.book_id, b.book_title, b.book_author, b.book_publisher, COUNT(*) AS loan_count
FROM tbl_loan_1 l
JOIN tbl_book_held_1 bh ON l.book_held_id = bh.book_held_id
JOIN tbl_book_1 b ON bh.book_id = b.book_id
GROUP BY b.book_id
ORDER BY loan_count DESC
LIMIT 5;

-- after
SELECT bh.book_held_id, bh.book_title, bh.book_author, bh.book_publisher, COUNT(*) AS loan_count
FROM tbl_loan_1 l
JOIN tbl_book_held_1 bh ON l.book_held_id = bh.book_held_id
GROUP BY bh.book_held_id
ORDER BY loan_count DESC
LIMIT 5;
```

### 3번: 분류별 도서 수

```sql
-- before
SELECT b.book_category_code, COUNT(*) AS book_count
FROM tbl_book_held_1 bh
JOIN tbl_book_1 b ON bh.book_id = b.book_id
GROUP BY b.book_category_code;

-- after
SELECT book_category_code, COUNT(*) AS book_count
FROM tbl_book_held_1
GROUP BY book_category_code;
```

### 5번: 현재 대여 중인 도서의 분류별 통계

```sql
-- before
SELECT b.book_category_code, COUNT(*) AS loaned_book_count
FROM tbl_loan_1 l
JOIN tbl_book_held_1 bh ON l.book_held_id = bh.book_held_id
JOIN tbl_book_1 b ON bh.book_id = b.book_id
WHERE l.actual_return_date IS NULL
GROUP BY b.book_category_code;

-- after
SELECT bh.book_category_code, COUNT(*) AS loaned_book_count
FROM tbl_loan_1 l
JOIN tbl_book_held_1 bh ON l.book_held_id = bh.book_held_id
WHERE l.actual_return_date IS NULL
GROUP BY bh.book_category_code;
```

### 6번: 분류별 대출 권수 상위 5위

```sql
-- before
SELECT b.book_category_code, COUNT(*) AS loan_count
FROM tbl_loan_1 l
JOIN tbl_book_held_1 bh ON l.book_held_id = bh.book_held_id
JOIN tbl_book_1 b ON bh.book_id = b.book_id
GROUP BY b.book_category_code
ORDER BY loan_count DESC
FETCH FIRST 5 ROW WITH TIES;

-- after
SELECT bh.book_category_code, COUNT(*) AS loan_count
FROM tbl_loan_1 l
JOIN tbl_book_held_1 bh ON l.book_held_id = bh.book_held_id
GROUP BY bh.book_category_code
ORDER BY loan_count DESC
FETCH FIRST 5 ROW WITH TIES;
```

## 측정 원본 (Execution Time, ms)

| 회차 | 1번 before | 1번 after | 3번 before | 3번 after | 5번 before | 5번 after | 6번 before | 6번 after |
|---|---|---|---|---|---|---|---|---|
| 1 | 0.150 | 0.234 | 0.113 | 0.053 | 0.158 | 0.075 | 0.330 | 0.140 |
| 2 | 0.102 | 0.196 | 0.119 | 0.093 | 0.156 | 0.145 | 0.174 | 0.447 |
| 3 | 0.084 | 0.128 | 0.106 | 0.073 | 0.160 | 0.228 | 0.322 | 0.069 |
| 4 | 0.090 | 0.113 | 0.089 | 0.075 | 0.166 | 0.389 | 0.154 | 0.071 |
| 5 | 0.396 | 0.079 | 0.067 | 0.074 | 0.077 | 0.097 | 0.146 | 0.075 |
| 6 | 0.088 | 0.089 | 0.113 | 0.042 | 0.245 | 0.076 | 0.996 | 0.170 |
| 7 | 0.071 | 0.063 | 0.087 | 0.041 | 0.150 | 0.073 | 0.148 | 0.117 |
| 8 | 0.086 | 0.065 | 0.218 | 0.054 | 0.320 | 0.078 | 0.144 | 0.065 |
| 9 | 0.273 | 0.173 | 0.102 | 0.045 | 0.110 | 0.064 | 0.144 | 0.273 |
| 10 | 0.081 | 0.143 | 0.061 | 0.163 | 0.103 | 0.116 | 0.093 | 0.068 |

## 해석 시 주의할 점

1. **조인 제거와 UUID 타입 변경은 분리되지 않습니다.** 위 수치는 두 변경이 합쳐진 효과입니다.
   - 3번의 조인 키는 `book_id`(정수)여서 UUID 변경의 영향이 가장 적습니다.
   - 1번, 5번, 6번은 `loan.book_held_id ⋈ held.book_held_id` 조인이 남아 있어 키 타입의 영향이 섞일 수 있습니다. before 계획에는 `(l.book_held_id)::text = (bh.book_held_id)::text` 형태의 캐스팅이 있고, after에는 없습니다.
2. **1번은 쿼리의 의미가 before와 다릅니다.** before는 `book_id`(책 단위), after는 `book_held_id`(사본 단위)로 묶습니다. 현재 데이터에서는 결과가 같지만 일반적으로 동등한 쿼리가 아닙니다.
3. **절대 차이가 작고 세션 간 변동과 비슷한 크기입니다.** 값이 0.04~0.1 ms 수준입니다. 같은 구조를 다른 세션에서 재측정하면 중앙값이 0.01~0.04 ms 흔들렸습니다.
4. **데이터가 매우 작습니다.** `tbl_loan_1` 21행, `tbl_book_held_1` 17행이라 데이터 규모에 따른 효과는 확인하지 못했습니다.
5. before는 16~17시대, after는 20시대에 측정해서 측정 시점이 다릅니다.
