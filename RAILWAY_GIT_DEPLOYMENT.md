# Railway Git Push 자동 배포 설정

## 🔗 현재 연결 상태
- ✅ Railway 프로젝트: `엑셀 Rails` (23715624-2291-4a72-9689-cd8eeedb31d1)
- ✅ 로컬 저장소: 연결됨
- ❌ GitHub 자동 배포: 설정 필요

## 🚀 Git Push 자동 배포 설정

### 1단계: Railway 대시보드 접속
```bash
# 프로젝트 URL (자동으로 열림)
https://railway.app/project/23715624-2291-4a72-9689-cd8eeedb31d1
```

### 2단계: GitHub 저장소 연결
1. **"Add Service"** 클릭
2. **"GitHub Repo"** 선택  
3. **"LEONFROMWORK/ex-rails"** 검색 및 선택
4. **"Deploy"** 클릭

### 3단계: 자동 배포 확인
- ✅ **Branch**: `main` 
- ✅ **Auto-deploy**: 활성화
- ✅ **Build Command**: 자동 감지 (`nixpacks`)

## 📋 배포 트리거 방법

### Git Push로 자동 배포
```bash
# 코드 변경 후
git add .
git commit -m "배포 업데이트"
git push origin main  # 자동으로 Railway 배포 시작
```

### 수동 배포 (필요시)
```bash
railway redeploy
```

## 🔧 환경 변수 설정

Railway 대시보드 > Variables 탭에서 설정:

### 필수 환경 변수
```bash
SECRET_KEY_BASE=bd28abcc8ebb9b1f04c4e2d2b402462df272b3cd63164f472229bf0dd7979fa8443e34bb8ee0cb13da6fe26b9ae309fa41ef71d0e6af74b3ba3e7d1aee8127d7
ADMIN_EMAILS=your-email@example.com
PAYMENT_ENABLED=false
SUBSCRIPTION_REQUIRED=false
```

### 자동 설정되는 환경 변수
- `DATABASE_URL` (PostgreSQL 추가 시)
- `REDIS_URL` (Redis 추가 시)
- `RAILS_HOST` (도메인 생성 시)

## 📊 배포 모니터링

### 배포 상태 확인
```bash
railway logs
railway status
```

### 웹 대시보드에서 확인
- **Deployments** 탭: 배포 로그
- **Metrics** 탭: 성능 모니터링
- **Settings** 탭: 도메인 및 설정

## 🎯 성공 지표

### ✅ 배포 완료 확인
- [ ] GitHub 저장소 연결됨
- [ ] PostgreSQL 서비스 추가됨
- [ ] Redis 서비스 추가됨  
- [ ] 도메인 생성됨
- [ ] 헬스체크 통과 (`/up`)
- [ ] 애플리케이션 접근 가능

### 🔗 배포 후 링크들
- **애플리케이션**: https://your-domain.railway.app
- **헬스체크**: https://your-domain.railway.app/up
- **로그인**: https://your-domain.railway.app/auth/login
- **관리자**: https://your-domain.railway.app/admin

## 🚨 문제 해결

### 배포 실패 시
1. Railway 대시보드 > Deployments > 로그 확인
2. 환경 변수 설정 재확인
3. `railway redeploy` 수동 재배포

### Git Push가 배포를 트리거하지 않을 때
1. Railway 대시보드에서 GitHub 연결 상태 확인
2. Auto-deploy 설정 활성화 확인
3. Branch 설정이 `main`인지 확인