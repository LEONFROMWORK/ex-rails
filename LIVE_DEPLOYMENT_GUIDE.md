# 🚀 실시간 Railway 배포 가이드

## 현재 진행 상황: STEP 1 - 프로젝트 생성

### ✅ 1단계: Railway 프로젝트 생성
**URL**: https://railway.app/new

1. **"Deploy from GitHub repo" 클릭**
2. **저장소 검색**: `LEONFROMWORK/ex-rails` 입력
3. **저장소 선택** 후 **"Deploy" 클릭**

---

## STEP 2 - 환경 변수 설정 (프로젝트 생성 후)

### 필수 환경 변수 설정
프로젝트 생성 후 **Variables** 탭에서 설정:

```bash
# 1. 기본 설정
SECRET_KEY_BASE=bd28abcc8ebb9b1f04c4e2d2b402462df272b3cd63164f472229bf0dd7979fa8443e34bb8ee0cb13da6fe26b9ae309fa41ef71d0e6af74b3ba3e7d1aee8127d7

# 2. 관리자 설정
ADMIN_EMAILS=your-email@example.com

# 3. 기능 플래그
PAYMENT_ENABLED=false
SUBSCRIPTION_REQUIRED=false

# 4. Rails 설정
RAILS_ENV=production
RAILS_SERVE_STATIC_FILES=true
RAILS_LOG_TO_STDOUT=true
```

---

## STEP 3 - 데이터베이스 서비스 추가

### PostgreSQL 추가
1. **프로젝트 대시보드** > **"+ New"** 클릭
2. **"Database"** > **"Add PostgreSQL"** 선택
3. 자동으로 `DATABASE_URL` 환경변수 생성됨

### Redis 추가  
1. **"+ New"** > **"Database"** > **"Add Redis"** 선택
2. 자동으로 `REDIS_URL` 환경변수 생성됨

---

## STEP 4 - 도메인 생성 및 설정

### 도메인 생성
1. **메인 서비스** > **"Settings"** > **"Networking"**
2. **"Generate Domain"** 클릭
3. 생성된 도메인 복사 (예: `your-app-name.railway.app`)

### RAILS_HOST 설정
1. **Variables** 탭으로 이동
2. **새 변수 추가**: `RAILS_HOST=your-app-name.railway.app`

---

## STEP 5 - 배포 확인 및 모니터링

### 배포 로그 확인
1. **"Deployments"** 탭 클릭
2. 최신 배포 로그 확인
3. 빌드 및 시작 과정 모니터링

### 배포 단계별 확인
- ✅ **Build**: Bundle install, npm install, assets precompile
- ✅ **Deploy**: DB migration, server start
- ✅ **Health Check**: `/up` 엔드포인트 응답

---

## STEP 6 - 기능 테스트

### 기본 기능 확인
배포 완료 후 다음 URL들 테스트:

```bash
# 1. 헬스체크
https://your-domain.railway.app/up

# 2. 홈페이지
https://your-domain.railway.app/

# 3. 로그인 페이지
https://your-domain.railway.app/auth/login

# 4. 관리자 페이지 (설정된 ADMIN_EMAILS로 로그인 후)
https://your-domain.railway.app/admin
```

---

## 🔧 문제 해결

### 배포 실패 시
1. **Deployments** > 로그에서 오류 확인
2. 환경 변수 재확인
3. **"Redeploy"** 버튼 클릭

### 데이터베이스 연결 오류 시
1. PostgreSQL 서비스 추가 확인
2. `DATABASE_URL` 자동 설정 확인
3. 마이그레이션 로그 확인

### 정적 파일 로드 실패 시
1. `RAILS_SERVE_STATIC_FILES=true` 확인
2. 에셋 빌드 로그 확인

---

## 📊 성공 지표

### ✅ 배포 성공 확인
- [ ] 헬스체크 200 응답
- [ ] 홈페이지 로딩 성공
- [ ] 로그인 페이지 접근 가능
- [ ] 관리자 페이지 접근 가능 (권한 있는 이메일로)

### 🎉 배포 완료!
모든 체크박스가 완료되면 배포 성공입니다!