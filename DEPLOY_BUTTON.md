# 🚀 Railway 원클릭 배포

## 즉시 배포하기

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/template/github/LEONFROMWORK/ex-rails)

### 또는 수동 배포:

1. **Railway 접속**: https://railway.com/new
2. **"Deploy from GitHub repo" 선택**
3. **저장소 입력**: `LEONFROMWORK/ex-rails`
4. **"Deploy" 클릭**

---

## 🔧 배포 후 필수 설정

### 1단계: 환경 변수 설정
Railway 프로젝트 > Variables 탭에서 다음 설정:

```bash
# 필수 설정
SECRET_KEY_BASE=bd28abcc8ebb9b1f04c4e2d2b402462df272b3cd63164f472229bf0dd7979fa8443e34bb8ee0cb13da6fe26b9ae309fa41ef71d0e6af74b3ba3e7d1aee8127d7
ADMIN_EMAILS=your-email@example.com
PAYMENT_ENABLED=false
SUBSCRIPTION_REQUIRED=false

# 도메인 설정 (생성된 도메인으로 교체)
RAILS_HOST=your-project.railway.app
```

### 2단계: 데이터베이스 추가
- **Add Service** > **PostgreSQL** 선택
- **Add Service** > **Redis** 선택

### 3단계: 도메인 생성
- **Networking** > **Generate Domain** 클릭
- 생성된 도메인을 `RAILS_HOST` 환경변수에 설정

### 4단계: 배포 확인
- 헬스체크: `https://your-domain.railway.app/up`
- 로그인: `https://your-domain.railway.app/auth/login`

---

## 🎯 배포 상태 확인

```bash
# 배포 확인 스크립트 실행
./check_deployment.sh your-domain.railway.app
```

---

## 📊 성공 지표

- ✅ 헬스체크 200 응답
- ✅ 홈페이지 접근 가능  
- ✅ 로그인 페이지 접근 가능
- ✅ 관리자 페이지 접근 가능

---

## 🔧 문제 해결

### 배포 실패 시
1. Railway 대시보드 > Deployments > 로그 확인
2. 환경 변수 재확인
3. 수동 재배포: Deploy 버튼 클릭

### 데이터베이스 연결 실패 시
1. PostgreSQL 서비스 추가 확인
2. DATABASE_URL 자동 설정 확인
3. 마이그레이션 로그 확인

---

## 📞 지원

문제 발생 시:
1. **Railway 대시보드**: 로그 및 설정 확인
2. **GitHub Issues**: 코드 관련 문제
3. **Railway Discord**: 플랫폼 관련 문제