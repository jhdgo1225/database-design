# 로그인방식 테이블 ✅
INSERT INTO tbl_lgmt_l1(lgmt_id, name)
VALUES
    ('GN', '일반'),
    ('NV', '네이버'),
    ('KA', '카카오'),
    ('GG', '구글');

# 계정 테이블 ✅
INSERT INTO tbl_acnt_m1(acnt_id, passwd, name, lgmt_id, phone, email, pc)
VALUES
    ('member0001','ef92b778bafe771e89245b89ecbcf3b27f3c6ab3502f6b7a588f1aef78b560f1','김민준', 'GN','01010000001','member0001@example.com', 'P'),
    ('member0002','6b3a55e0261b0304143f805a249bb4b51e915e941a8b2eafef72d3d4e1f3f7a9','박서연', 'NV','01010000002','member0002@example.com', 'P'),
    ('member0003','62b9d3c391d5f8e0483e456cb8c0f3b4d8e16f7a2c3d4e5f6a7b8c9d0e1f2a3b','이서준', 'KA','01010000003','member0003@example.com', 'P'),
    ('member0004','8523089c11ad42e93f5efcedf5f0a0f8b3c6a0eaf3d1b7f2a7c9e0d8f5b4a1c2','최하은', 'GG','01010000004','member0004@example.com', 'P'),
    ('member0005','2e7d2c03a9507ae265ecf5b5356885a53393a5d1a0dc5a1f6e1a0948c8b7e1f4','정도윤', 'GN','01010000005','member0005@example.com', 'P'),
    ('member0006','e7cf3ef4f17c3999a94f2c6f612e8a888e5e1e4b45e2c68f8b02f7e1b3b3bf4b','박경해', 'GN','01010000006','member0006@example.com', 'P'),
    ('member0007','8cb2237d0679ca88db6464eac60da96345513964e9b0c88a2df2d96a8f45f186','이시야', 'NV','01010000007','member0007@example.com', 'P'),
    ('member0008','3a7bd3e2360a3d80d5e22cfb9e5eda1a7e1a0c9b0f7b9a3e4d5f6b7c8d9e0f12','최하은', 'KA','01010000008','member0008@example.com', 'P'),
    ('member0009','45c48cce2e2d7fbdea1afc51c7c6ad26a67e0f7a5b4a3c2d1e0f9b8a7c6d5e4f','김규호', 'GG','01010000009','member0009@example.com', 'P'),
    ('member0010','d8578edf8458ce06fbc5bb76a58c5ca4a5e6c4d3f2b1a09876543210fedcba98','조수빈', 'GG','01010000010','member0010@example.com', 'P'),
    ('member0011','a1d0c6e83f027327d8461063f4ac58a6e6d0f8a4b3c2d1e0f9a8b7c6d5e4f3b2','진민준', 'KA','01010000011','member0011@example.com', 'P'),
    ('member0012','9c1185a5c5e9fc54612808977ee8f548b2258d31a72b2e9f0e5bbf7b1d4c3a2b','김아인', 'NV','01010000012','member0012@example.com', 'P'),
    ('member0013','3c363836cf4e16666669a25da280a1865c2d96e7a3b5f1a8d7e9c4b2a1f0e8d7','이서유', 'KA','01010000013','member0013@example.com', 'P'),
    ('member0014','8493a6f3b2e1d0c9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5','최시연', 'GN','01010000014','member0014@example.com', 'P'),
    ('member0015','f7846f55cf23e14eebeab5b4e1550cad5b509e3348d9fa7d1c2b3a4e5f6d7c8b','김도운', 'GN','01010000015','member0015@example.com', 'P'),
    ('member0016','1c4038d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8091a2b3c4d5e6f7a8b9c0d1e2f3a','유다연', 'GN','01010000016','member0016@example.com', 'P'),
    ('member0017','2d4149e5f7a8b9c0d1e2f3a4b5c6d7e8f9012a3b4c5d6e7f8a9b0c1d2e3f4a5b','이재환', 'GN','01010000017','member0017@example.com', 'P'),
    ('member0018','3e525af6a9b0c1d2e3f4a5b6c7d8e9f01234b5c6d7e8f9a0b1c2d3e4f5a6b7c8','박화원', 'NV','01010000018','member0018@example.com', 'P'),
    ('member0019','4f636bf7b0a1c2d3e4f5a6b7c8d9e0f12345c6d7e8f9a0b1c2d3e4f5a6b7c8d9','김구지', 'GG','01010000019','member0019@example.com', 'P'),
    ('member0020','50a74cf8c1b2d3e4f5a6b7c8d9e0f11234567d8e9f0a1b2c3d4e5f6a7b8c9d0e','김재연', 'NV','01010000020','member0020@example.com', 'P'),
    ('member0021','61b85df9d2c3e4f5a6b7c8d9e0f11235678aedf0b1c2d3e4f5a6b7c8d9e0f112','남경호', 'GN','01010000021','member0021@example.com', 'C'),
    ('member0022','72c96e0ae3d4f5a6b7c8d9e0f11234789bfed01c2d3e4f5a6b7c8d9e0f112345','염정연', 'GN','01010000022','member0022@example.com', 'C'),
    ('member0023','83da7f1bf4e5a6b7c8d9e0f1124589abcfe120d3e4f5a6b7c8d9e0f11234567a','조지훈', 'GN','01010000023','member0023@example.com', 'C'),
    ('member0024','94eb801c05f6b7c8d9e0f11234589abcdfe231e4f5a6b7c8d9e0f1123456789a','장덕수', 'GN','01010000024','member0024@example.com', 'C'),
    ('member0025','a5fc912d16e7c8d9e0f11234589abcdeff342f5a6b7c8d9e0f1123456789abcd','변기현', 'GN','01010000025','member0025@example.com', 'C'),
    ('member0026','b60d932e27f8d9e0f11234589abcdef123453f6a7b8c9d0e1f1123456789abce','정유정', 'GN','01010000026','member0026@example.com', 'C'),
    ('member0027','c71e943f38a9e0f11234589abcdef12356454a7b8c9d0e1f1123456789abcdf0','성시경', 'GN','01010000027','member0027@example.com', 'C'),
    ('member0028','d82fa50a49b0f123456789abcdef12367565b8c9d0e1f1123456789abcdeff1e','최시은', 'GN','01010000028','member0028@example.com', 'C'),
    ('member0029','e93fb61b5ac1f23456789abcdef12378676c9d0e1f1123456789abcdeff1234f','이동호', 'GN','01010000029','member0029@example.com', 'C'),
    ('member0030','fa40c72c6bd2f3456789abcdef12389787d0e1f1123456789abcdeff1234567c','서희지', 'GN','01010000030','member0030@example.com', 'C');

# 개인회원 테이블 ✅
INSERT INTO tbl_pnmb_d1(pnmb_id, acnt_id, birth, sex, addr)
VALUES
    ('Pmember0001', 'member0001','19950202','M', '서울 용산구 한강대로 23'),
    ('Pmember0002', 'member0002','19960303','F', '서울 용산구 한강대로 26'),
    ('Pmember0003', 'member0003','19970404','M', '서울 용산구 한강대로 31'),
    ('Pmember0004', 'member0004','19970505','F', '서울 용산구 한강대로 32'),
    ('Pmember0005', 'member0005','19970606','M', '서울 용산구 한강대로 35'),
    ('Pmember0006', 'member0006','19970707','F', '서울 용산구 한강대로 37'),
    ('Pmember0007', 'member0007','19970808','M', '서울 용산구 한강대로 39'),
    ('Pmember0008', 'member0008','19970909','F', '서울 용산구 한강대로 42'),
    ('Pmember0009', 'member0009','19971010','M', '서울 용산구 한강대로 45'),
    ('Pmember0010', 'member0010','19981111','F', '서울 용산구 한강대로 49'),
    ('Pmember0011', 'member0011','19991212','M', '서울 용산구 한강대로 50'),
    ('Pmember0012', 'member0012','19980113','F', '서울 용산구 한강대로 50-1'),
    ('Pmember0013', 'member0013','19990214','M', '서울 용산구 한강대로 51'),
    ('Pmember0014', 'member0014','19990315','F', '서울 용산구 한강대로 52'),
    ('Pmember0015', 'member0015','20000416','M', '서울 용산구 한강대로 52-1'),
    ('Pmember0016', 'member0016','20000517','F', '서울 용산구 한강대로 53'),
    ('Pmember0017', 'member0017','20000618','M', '서울 용산구 한강대로 54'),
    ('Pmember0018', 'member0018','20000719','F', '서울 용산구 한강대로 54-1'),
    ('Pmember0019', 'member0019','20010820','M', '서울 용산구 한강대로 54-2'),
    ('Pmember0020', 'member0020','20010921','F', '서울 용산구 한강대로 55');

# 학력 테이블 ✅
INSERT INTO tbl_educ_d1(educ_id, pnmb_id, sctype, scname, admissionym, graduationym, status)
VALUES
    ('Pmember00011','Pmember0001','HS', '용산고등학교','201103', '201402', 'GR'),
    ('Pmember00012','Pmember0001','UNIV4', '명지대학교','201403', '201902', 'GR'),
    ('Pmember00021','Pmember0002','HS', '보성여자고등학교','201203', '201502', 'GR'),
    ('Pmember00022','Pmember0002','UNIV4', '동국대학교','201503', '201902', 'GR'),
    ('Pmember00031','Pmember0003','HS', '배문고등학교','201303', '201602', 'GR'),
    ('Pmember00032','Pmember0003','UNIV4', '건국대학교','201603', '202002', 'GR'),
    ('Pmember00041','Pmember0004','HS', '보성여자고등학교','201303', '201602', 'GR'),
    ('Pmember00042','Pmember0004','COL23', '인하공업전문대학','201603', '201902', 'GR'),
    ('Pmember00043','Pmember0004','UNIV4', '인하공업전문대학','201903', '202002', 'GR'),
    ('Pmember00051','Pmember0005','HS', '중경고등학교','201303', '201602', 'GR'),
    ('Pmember00052','Pmember0005','UNIV4', '서강대학교','201603', '202002', 'GR'),
    ('Pmember00061','Pmember0006','HS', '신광여자고등학교','201303', '201602', 'GR'),
    ('Pmember00062','Pmember0006','COL23', '인하공업전문대학','201603', '201902', 'GR'),
    ('Pmember00071','Pmember0007','HS', '중경고등학교','201303', '201602', 'GR'),
    ('Pmember00072','Pmember0007','UNIV4', '서울대학교','201603', '202002', 'GR'),
    ('Pmember00073','Pmember0007','GRAD', '서울대학교','202003', '202202', 'GR'),
    ('Pmember00074','Pmember0007','GRAD', '서울대학교','202203', '202502', 'GR'),
    ('Pmember00081','Pmember0008','HS', '신광여자고등학교','201303', '201602', 'GR'),
    ('Pmember00082','Pmember0008','UNIV4', '중앙대학교','201603', '202002', 'GR'),
    ('Pmember00091','Pmember0009','HS', '배문고등학교','201303', '201602', 'GR'),
    ('Pmember00092','Pmember0009','COL23', '인하공업전문대학','201603', '202002', 'GR'),
    ('Pmember00101','Pmember0010','HS', '신광여자고등학교','201403', '201702', 'GR'),
    ('Pmember00102','Pmember0010','UNIV4', '고려대학교','201703', '202102', 'GR'),
    ('Pmember00103','Pmember0010','GRAD', '고려대학교','202103', '202402', 'GR'),
    ('Pmember00111','Pmember0011','HS', '배문고등학교','201503', '201802', 'GR'),
    ('Pmember00121','Pmember0012','HS', '성심여자고등학교','201403', '201702', 'GR'),
    ('Pmember00131','Pmember0013','HS', '용산고등학교','201503', '201802', 'GR'),
    ('Pmember00141','Pmember0014','HS', '성심여자고등학교','201503', '201802', 'GR'),
    ('Pmember00151','Pmember0015','HS', '휘문고등학교','201603', '201902', 'GR'),
    ('Pmember00161','Pmember0016','HS', NULL,NULL, '201902', 'GR'),
    ('Pmember00171','Pmember0017','HS', NULL,NULL, '201902', 'GR'),
    ('Pmember00181','Pmember0018','HS', NULL,NULL, '201902', 'GR'),
    ('Pmember00191','Pmember0019','HS', NULL,NULL, '202002', 'GR'),
    ('Pmember00201','Pmember0020','HS', NULL,NULL, '202002', 'GR');

# 고등학교 테이블 ✅
INSERT INTO tbl_hgsc_d1 (educ_id, hsequal) VALUES
  ('Pmember00011','N'),
  ('Pmember00021','N'),
  ('Pmember00031','N'),
  ('Pmember00041','N'),
  ('Pmember00051','N'),
  ('Pmember00061','N'),
  ('Pmember00071','N'),
  ('Pmember00081','N'),
  ('Pmember00091','N'),
  ('Pmember00101','N'),
  ('Pmember00111','N'),
  ('Pmember00121','N'),
  ('Pmember00131','N'),
  ('Pmember00141','N'),
  ('Pmember00151','N'),
  ('Pmember00161','Y'),
  ('Pmember00171','Y'),
  ('Pmember00181','Y'),
  ('Pmember00191','Y'),
  ('Pmember00201','Y');

# 대학교 테이블 ✅
INSERT INTO tbl_univ_d1
  (educ_id, majorname, credits, total, transfer, secondmajor, secondtype, secondname)
VALUES
  ('Pmember00012','경영학과', '3.84','4.5','N','Y', 'multi', '컴퓨터공학과'),
  ('Pmember00022','심리학과', '3.90','4.5','N','Y', 'minor', '경영학과'),
  ('Pmember00032','화학교육과', '4.2','4.5','N','Y', 'multi', '컴퓨터공학과'),
  ('Pmember00042','경영비서학과', '4.1','4.5','N', 'N', NULL, NULL),
  ('Pmember00043','경영비서학과', '4.23','4.5','N','N', NULL, NULL),
  ('Pmember00052','기계공학과', '3.2','4.5','N','Y', 'minor', '물리학과'),
  ('Pmember00062','컴퓨터정보과', '3.90','4.5','N','N', NULL, NULL),
  ('Pmember00072','천체물리학과', '2.56','4.5','N','N', NULL, NULL),
  ('Pmember00082','경영학과', '4.23','4.5','N','N', NULL, NULL),
  ('Pmember00092','컴퓨터시스템과', '4.06','4.5','N','N', NULL, NULL),
  ('Pmember00102','철학과', '4.41','4.5','N','N', NULL, NULL);

# 대학원 테이블 ✅
INSERT INTO tbl_grad_d1
  (educ_id, majorname, degree, credits, total)
VALUES
  ('Pmember00073','천체물리학과','M','3.57','4.5'),
  ('Pmember00074','천체물리학과','D','3.76','4.5'),
  ('Pmember00103','경영학과','I','4.12','4.5');

# 자격증 테이블 ✅
INSERT INTO tbl_cert_l1(cert_id, name)
VALUES
    ('HRDS01020101', '사회조사분석사1급'),
    ('HRDS01020103', '소비자전문상담사1급'),
    ('HRDS01160103', '기계기술사'),
    ('HRDS01160106', '일반기계기사'),
    ('HRDS01180105', '화공기사'),
    ('HRDS01180107', '화학류제조기사'),
    ('HRDS01180110', '화학분석기사'),
    ('HRDS01210107', '정보처리기사'),
    ('HRDS01210108', '정보처리산업기사');

# 자격증보유 테이블 ✅
INSERT INTO tbl_cthd_t1 (pnmb_id, cert_id, certym) VALUES
  ('Pmember0001', 'HRDS01210107', '201806'),  /* 명지대학교 → 정보처리기사 */
  ('Pmember0005', 'HRDS01210108', '201903'),  /* 서강대학교 → 정보처리산업기사 */
  ('Pmember0002', 'HRDS01020101', '201807'),  /* 동국대학교 → 사회조사분석사1급 */
  ('Pmember0003', 'HRDS01020103', '201812'),  /* 건국대학교 → 소비자전문상담사1급 */
  ('Pmember0004', 'HRDS01160106', '201906'),  /* 인하공업전문대학 → 일반기계기사 */
  ('Pmember0006', 'HRDS01160103', '201911'),  /* 인하공업전문대학 → 기계기술사 */
  ('Pmember0007', 'HRDS01180105', '202006'),  /* 서울대학교 → 화공기사 */
  ('Pmember0008', 'HRDS01180107', '201908'),  /* 중앙대학교 → 화학류제조기사 */
  ('Pmember0009', 'HRDS01210108', '201909');  /* 인하공업전문대학 → 화학분석기사 */

# 직무 테이블 ✅
INSERT INTO tbl_posi_l1(name)
VALUES
    ('기획•전략'),
    ('인사•HR'),
    ('마케팅•광고•MD'),
    ('디자인'),
    ('운전•운송•배송'),
    ('고객상담•TM'),
    ('식•음료'),
    ('엔지니어링•설계'),
    ('교육'),
    ('의료•바이오'),
    ('공공•복지'),
    ('법무•사무•총무'),
    ('회계•세무'),
    ('AI•개발•데이터'),
    ('물류•무역'),
    ('영업'),
    ('금융•보험'),
    ('고객서비스•리테일'),
    ('제조•생산'),
    ('건축•시설'),
    ('미디어•문화•스포츠');

# 개인회원희망직무 테이블 ✅
INSERT INTO tbl_pnps_t1(pnmb_id, posi_id)
VALUES
    ('Pmember0001', 1),
    ('Pmember0002', 2),
    ('Pmember0003', 7),
    ('Pmember0004', 3),
    ('Pmember0005', 5),
    ('Pmember0006', 14),
    ('Pmember0007', 9),
    ('Pmember0008', 2),
    ('Pmember0009', 14),
    ('Pmember0010', 3);

# 모회사 테이블 ✅
INSERT INTO tbl_affi_l1(affi_id, name)
VALUES
    ('VIVA', '비바리퍼블리카그룹'),
    ('KAKO', '카카오그룹'),
    ('SOIL', '에쓰-오일그룹'),
    ('DOOS', '두산그룹'),
    ('SUNT', '썬텍인더스트리그룹'),
    ('NVHK', '엔브이에이치코리아그룹'),
    ('NEXN', '넥슨그룹');

# 기업 테이블 ✅
INSERT INTO tbl_comp_d1(comp_id, acnt_id, comptype, brn, compname, ceo, addr, affi_id, industry, capital, homelink, empcount, empcountdate, estdate, revenue, revenuedate, fourinsurance)
VALUES
    ('Cmember0021', 'member0021', 'VC', '000-00-00001', '(주)비바리퍼블리카', '이승건', '서울 강남구 테헤란로 142 (역삼동, 캐피탈타워) B존 12층 Toss', 'VIVA', '모바일•APP', 35506000000, 'https://career.toss.im/', 1405, '2024-12-31', '2013-04-23', 587050000000, '2024-12-31', 'Y'),
    ('Cmember0022', 'member0022', 'LE', '000-00-00002', '(주)카카오', '정신아', '경기 성남시 분당구 삼평동 681번지 에이치스퀘어 N동', 'KAKO', '포털 및 기타 인터넷 정보매개 서비스업', 44410000000, 'http://www.kakaocorp.com', 4028, '2024-12-31', '1995-02-16', 2595100000000, '2024-12-31', 'Y'),
    ('Cmember0023', 'member0023', 'SE', '000-00-00003', '토스모바일(주)', '이승훈', '서울 금천구 가산디지털1로 145 (가산동, 에이스하이엔드타워3차) 19층 1904호', 'VIVA', '네트워크•통신서비스', 1000000000, 'https://tossmobile.co.kr/', 50, '2024-12-31', '2009-10-21', 20000000000, '2024-12-31', 'Y'),
    ('Cmember0024', 'member0024', 'SE', '000-00-00004', '토스인슈어런스(주)', '조병익', '서울 구로구 경인로 662, 37층 (신도림동,디큐브시티)', 'VIVA', '증권•보험•카드', 500000000, 'https://tossinsu.com/', 61, '2024-12-31', '2018-10-30', 45380000000, '2023-12-31', 'Y'),
    ('Cmember0025', 'member0025', 'SE', '000-00-00005', '토스페이먼츠(주)', '임한욱', '서울 강남구 테헤란로 131, 15층 (역삼동,한국지식재산센터)', 'VIVA', '증권•보험•카드', 6860000000, 'http://www.tosspayments.com/', 371, '2025-02-28', '2020-03-30', 819670000000, '2024-12-31', 'Y'),
    ('Cmember0026', 'member0026', 'SE', '000-00-00006', '토스증권(주)', '김규빈', '서울 강남구 테헤란로 133, 1층 1층, 2층, 3층, 4층, 5층, 6층 (역삼동,한국타이어빌딩)', 'VIVA', '은행•금융', 138840000000, 'https://corp.tossinvest.com', 292, '2024-12-31', '2018-11-29', 426580000000, '2024-12-31', 'Y'),
    ('Cmember0027', 'member0027', 'LE', '000-00-00007', 'S-OIL(주)', '안와르에이알히즈아지', '서울 마포구 공덕동 471번지 S-Oil(주) 사옥 18층', 'SOIL', '원유 정제처리업', 291510000000, 'http://www.s-oil.com', 3488, '2024-12-31', '1976-01-06', 36100000000000, '2024-12-31', 'Y'),
    ('Cmember0028', 'member0028', 'LE', '000-00-00008', '두산로보틱스(주)', '박인원/조길성/김민표', '서울 서초구 서초대로77길 55 (서초동, 에이프로 스퀘 9층)', 'DOOS', '컴퓨터•하드웨어•장비', 32409000000, 'http://www.doosanrobotics.com', 231, '2024-12-31', '2015-07-31', 51570000000, '2024-12-31', 'Y'),
    ('Cmember0029', 'member0029', 'ME', '000-00-00009', '태양연마(주)', '신석호/신원식', '경기 안산시 단원구 성곡동 628-4', 'SUNT', '연마재 제조업', 4110000000, 'http://www.sunabrasives.co.kr', 189, '2024-12-31', '1988-01-01', 132240000000, '2024-12-31', 'Y'),
    ('Cmember0030', 'member0030', 'ME', '000-00-00010', '케이엔솔(주)', '구자겸/정우현', '서울 강남구 수서동 717-4 원방빌딩7층', 'NVHK', '공기 조화장치 제조업', 6490000000, 'http://k-ensol.com', 120, '2024-12-31', '1989-09-04', 241540000000, '2024-12-31', 'Y');

# 주요사업 테이블 ✅
INSERT INTO tbl_busi_d1(comp_id, name)
VALUES
    ('Cmember0021', '금융플랫폼'),
    ('Cmember0022', '인터넷 서비스(인터넷 광고)/데이타베이스'),
    ('Cmember0022', '인터넷관련소프트웨어'),
    ('Cmember0022', '시스템통합'),
    ('Cmember0022', '인터넷광고사업'),
    ('Cmember0022', '무료이메일서비스'),
    ('Cmember0022', '전자상거래'),
    ('Cmember0023', 'MVNO 이동통신 판매'),
    ('Cmember0024', '보험 대리,중개'),
    ('Cmember0025', '금융지원(전자결제)'),
    ('Cmember0026', '투자중개'),
    ('Cmember0027', '석유제품'),
    ('Cmember0027', '가스'),
    ('Cmember0027', '윤활기유'),
    ('Cmember0027', '윤활유'),
    ('Cmember0027', '그리스'),
    ('Cmember0027', '석유화학제품 제조'),
    ('Cmember0027', '도매'),
    ('Cmember0028', '협동로봇 제조/기계장비중개'),
    ('Cmember0028', '산업용기계'),
    ('Cmember0028', '장비 도소매/소프트웨어 개발, 공급'),
    ('Cmember0028', '기술,직업훈련학원'),
    ('Cmember0029', '연마포'),
    ('Cmember0029', '연마지 제조'),
    ('Cmember0029', '도소매'),
    ('Cmember0029', '수출'),
    ('Cmember0030', '클린룸 설비 제조');

# 채용공고 테이블 ✅
INSERT INTO tbl_post_m1(post_id, comp_id, title, expr, edu, emptype, salary, loc, startdate, enddate, applymt)
VALUES
    ('Cmember002100010', 'Cmember0021', '[토스페이먼츠] IT Planning Manager', 'E', '무관', 'P', '회사내규에 따름 - 면접 후 결정', '서울시 강남구', '2025-03-24', '2025-04-30', 'H'),
    ('Cmember002100011', 'Cmember0021', '[토스페이먼츠] Sales Systems Manager', '', '무관', 'P', '회사내규에 따름', '서울시 강남구', '2025-04-02', '2025-05-02', 'H'),
    ('Cmember002100012', 'Cmember0021', '[토스플레이스] Security Engineer(네트워크/엔드포인트 보안)', '', '무관', 'P', '회사내규에 따름', '서울시 강남구', NULL, NULL, 'H'),
    ('Cmember002200013', 'Cmember0021', '[토스] Finance Assistant', '', '무관', 'C', '월급 250만원', '서울시 강남구', '2025-03-28', '2025-04-27', 'H'),
    ('Cmember002200015', 'Cmember0022', '[카카오] 커머스 식품 CM(경력)', 'E5', '무관', 'P', '회사내규에 따름 - 면접 후 결정', '경기도 성남시 분당구', '2025-04-14', '2025-04-28', 'H'),
    ('Cmember002300017', 'Cmember0023', '[토스모바일] 백엔드 개발 경력자 채용', 'E5', '초대졸이상', 'P', '회사내규에 따름 - 면접 후 결정', '서울시 금천구', NULL, NULL, 'D'),
    ('Cmember002400020', 'Cmember0024', '토스인슈어런스 신입/경력 설계영업 모집', 'NE1', '무관', 'P', '월급 500만원 이상', '서울시 구로구', '2025-04-11', '2025-05-11', 'D'),
    ('Cmember002700030', 'Cmember0027', 'S-OIL 경력사원 채용 (생산직)', 'E6', '무관', 'C', '회사내규에 따름', '울산 울주군', '2025-04-22', '2025-05-06', 'H'),
    ('Cmember002800010', 'Cmember0028', '2025 두산로보틱스 상반기 경력직 공개채용', 'E', '대졸이상', 'P', '회사내규에 따름 - 면접 후 결정', '경기도 성남시 분당구, 수원시 권선구', '2025-04-23', '2025-05-06', 'H'),
    ('Cmember002900020', 'Cmember0029', '2025년 태양연마 신입/경력사원 수시 채용', 'NE2', '초대졸이상', 'P', '연봉 4600만원', '경기도 안산시 단원구', '2025-04-21', '2025-05-18', 'D'),
    ('Cmember003000030', 'Cmember0030', '2025년 상반기 분야별 경력직 채용', 'E2', '초대졸이상', 'P', '회사내규에 따름 [연봉 + 인센티브 + 복지포인트]', '서울시 강남구, 강동구', '2025-04-09', '2025-04-30', 'D');

# 채용공고-직무 테이블 ✅
INSERT INTO tbl_ptps_d1(post_id, posi_id)
VALUES
    ('Cmember002100010', 14),
    ('Cmember002100011', 1),
    ('Cmember002100012', 14),
    ('Cmember002200013', 1),
    ('Cmember002200015', 3),
    ('Cmember002300017', 14),
    ('Cmember002400020', 8),
    ('Cmember002700030', 19),
    ('Cmember002800010', 19),
    ('Cmember002900020', 19),
    ('Cmember003000030', 19);

# 경력사항 테이블 ✅
INSERT INTO tbl_expr_t1
  (expr_id, phmb_id, comp_id, deptname, joinym, leaveym, grade, role, posi_id)
VALUES
  ('Pmember000101', 'Pmember0001', 'Cmember0021', '기획팀',       '201901', '202012', '사원',   '팀원', 14),
  ('Pmember000201', 'Pmember0002', 'Cmember0022', '서비스개발팀', '201902', '202103', '대리',   '팀장', 3),
  ('Pmember000301', 'Pmember0003', 'Cmember0023', '네트워크팀',   '201910', '202112', '과장',   '부장', 14),
  ('Pmember000401', 'Pmember0004', 'Cmember0024', '영업부', '201911', '202211', '사원',   '팀원', 14),
  ('Pmember000501', 'Pmember0005', 'Cmember0025', '결제플랫폼팀','202003', '202312', '대리',   '팀장', 14),
  ('Pmember000601', 'Pmember0006', 'Cmember0026', '트레이딩팀',   '201911', '202311', '과장',   '부장', 2),
  ('Pmember000701', 'Pmember0007', 'Cmember0027', '정제공정부',   '202001', '202306', '사원',   '팀원', 19),
  ('Pmember000801', 'Pmember0008', 'Cmember0028', '로봇SW팀',     '202207', '202407', '대리',   '팀장', 19),
  ('Pmember000901', 'Pmember0009', 'Cmember0029', '생산관리팀',   '202201', '202312', '과장',   '부장', 19),
  ('Pmember001001', 'Pmember0010', 'Cmember0030', '설비엔지니어링','202101', '202312', '사원', '팀원', 19);

# 지원 테이블 ✅
INSERT INTO tbl_aply_t1
  (aply_id, pnmb_id, post_id, applydate, success, public)
VALUES
  -- 1차 지원: Pmember0001 → 첫 번째 공고
  ('Pmember0001001', 'Pmember0001', 'Cmember002100010', '2025-03-25 09:15:00', 'P', 'N'),
  ('Pmember0002001', 'Pmember0002', 'Cmember002100011', '2025-04-03 10:30:00', 'P', 'N'),
  ('Pmember0003001', 'Pmember0003', 'Cmember002100012', '2025-04-02 11:45:00', 'P', 'N'),
  ('Pmember0004001', 'Pmember0004', 'Cmember002200013', '2025-03-29 14:20:00', 'P', 'N'),
  ('Pmember0005001', 'Pmember0005', 'Cmember002200015', '2025-04-16 16:10:00', 'P', 'N'),
  ('Pmember0006001', 'Pmember0006', 'Cmember002300017', '2025-04-20 09:50:00', 'P', 'N'),
  ('Pmember0007001', 'Pmember0007', 'Cmember002400020', '2025-04-12 13:15:00', 'P', 'N'),
  ('Pmember0008001', 'Pmember0008', 'Cmember002700030', '2025-04-23 08:00:00', 'P', 'N'),
  ('Pmember0009001', 'Pmember0009', 'Cmember002800010', '2025-04-24 15:30:00', 'P', 'N'),
  ('Pmember0010001', 'Pmember0010', 'Cmember002900020', '2025-04-22 10:05:00', 'P', 'N'),
  ('Pmember0011001', 'Pmember0011', 'Cmember003000030', '2025-04-12 14:45:00', 'P', 'N');

# 자기소개서 테이블 ✅
INSERT INTO tbl_cvlt_d1
  (cvlt_id, aply_id, question, answer)
VALUES
  ('Pmember00010011','Pmember0001001','자신의 강점과 약점을 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00010012','Pmember0001001','지원 동기를 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00010013','Pmember0001001','입사 후 포부를 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00020011','Pmember0002001','자신의 강점과 약점을 기술해 주세요.','[여기에 답변을 입력해 주세요]'),
  ('Pmember00020012','Pmember0002001','지원 동기를 기술해 주세요.','[여기에 답변을 입력해 주세요]'),
  ('Pmember00020013','Pmember0002001','입사 후 포부를 기술해 주세요.','[여기에 답변을 입력해 주세요]'),
  ('Pmember00030011','Pmember0003001','자신의 강점과 약점을 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00030012','Pmember0003001','지원 동기를 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00030013','Pmember0003001','입사 후 포부를 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00040011','Pmember0004001','자신의 강점과 약점을 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00040012','Pmember0004001','지원 동기를 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00040013','Pmember0004001','입사 후 포부를 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00050011','Pmember0005001','자신의 강점과 약점을 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00050012','Pmember0005001','지원 동기를 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00050013','Pmember0005001','입사 후 포부를 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00060011','Pmember0006001','자신의 강점과 약점을 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00060012','Pmember0006001','지원 동기를 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00060013','Pmember0006001','입사 후 포부를 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00070011','Pmember0007001','자신의 강점과 약점을 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00070012','Pmember0007001','지원 동기를 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00070013','Pmember0007001','입사 후 포부를 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00080011','Pmember0008001','자신의 강점과 약점을 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00080012','Pmember0008001','지원 동기를 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00080013','Pmember0008001','입사 후 포부를 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00090011','Pmember0009001','자신의 강점과 약점을 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00090012','Pmember0009001','지원 동기를 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00090013','Pmember0009001','입사 후 포부를 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00100011','Pmember0010001','자신의 강점과 약점을 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00100012','Pmember0010001','지원 동기를 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00100013','Pmember0010001','입사 후 포부를 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00110011','Pmember0011001','자신의 강점과 약점을 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00110012','Pmember0011001','지원 동기를 기술해 주세요.','[여기에 답변을 입력하세요]'),
  ('Pmember00110013','Pmember0011001','입사 후 포부를 기술해 주세요.','[여기에 답변을 입력하세요]');


select * from tbl_aply_t1;
delete from tbl_aply_t1 where aply_id='Pmember0020001';