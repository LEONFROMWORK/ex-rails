# Railway 서비스 설정 가이드

## 🔗 1단계: GitHub 저장소 연결
✅ **완료**: https://railway.app/project/23715624-2291-4a72-9689-cd8eeedb31d1

### GitHub 연결 확인사항
- [ ] **Repository**: LEONFROMWORK/ex-rails
- [ ] **Branch**: main 
- [ ] **Auto-deploy**: 활성화됨
- [ ] **Build Command**: nixpacks 자동 감지

## 📊 2단계: PostgreSQL 데이터베이스 추가

### 추가 방법
1. Railway 대시보드에서 **"+ New"** 클릭
2. **"Database"** → **"PostgreSQL"** 선택
3. **"Add PostgreSQL"** 클릭

### 자동 설정되는 환경 변수
```bash
DATABASE_URL=postgresql://postgres:password@hostname:port/database
```

### pgvector 확장 활성화
```sql
-- 배포 후 Railway 콘솔에서 실행
CREATE EXTENSION IF NOT EXISTS vector;
```

## 🔴 3단계: Redis 캐시 추가

### 추가 방법
1. Railway 대시보드에서 **"+ New"** 클릭  
2. **"Database"** → **"Redis"** 선택
3. **"Add Redis"** 클릭

### 자동 설정되는 환경 변수
```bash
REDIS_URL=redis://default:password@hostname:port
```

## ⚙️ 4단계: 필수 환경 변수 설정

Railway 대시보드 > **Variables** 탭에서 설정:

### 🔑 보안 키
```bash
SECRET_KEY_BASE=bd28abcc8ebb9b1f04c4e2d2b402462df272b3cd63164f472229bf0dd7979fa8443e34bb8ee0cb13da6fe26b9ae309fa41ef71d0e6af74b3ba3e7d1aee8127d7
RAILS_MASTER_KEY=<config/master.key 내용>
```

### 👨‍💼 관리자 설정
```bash
ADMIN_EMAILS=your-email@example.com
PAYMENT_ENABLED=false
SUBSCRIPTION_REQUIRED=false
```

### 🤖 AI 서비스 (선택사항)
```bash
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_AI_API_KEY=...
OPENROUTER_API_KEY=sk-or-...
```

### 🔐 OAuth (선택사항)  
```bash
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
KAKAO_CLIENT_ID=...
KAKAO_CLIENT_SECRET=...
```

## 🌐 5단계: 도메인 설정

### Custom Domain (선택사항)
1. **Settings** 탭 → **Domains** 섹션
2. **"Generate Domain"** 또는 **"Custom Domain"** 설정
3. **HTTPS** 자동 활성화 확인

### 기본 Railway 도메인
```
https://your-app-name.railway.app
```

## ✅ 6단계: 배포 테스트

### Git Push 배포 테스트
```bash
# 배포 트리거
git add .
git commit -m "Railway 자동 배포 테스트"
git push origin main
```

### 헬스체크 확인
```bash
# 배포 완료 후
curl https://your-domain.railway.app/up
```

## 📊 성공 체크리스트

### ✅ 서비스 연결 상태
- [ ] GitHub Repository 연결됨
- [ ] PostgreSQL 추가됨  
- [ ] Redis 추가됨
- [ ] 환경 변수 설정됨
- [ ] 도메인 생성됨

### ✅ 배포 상태
- [ ] Git Push 자동 배포 작동
- [ ] 애플리케이션 접근 가능
- [ ] 헬스체크 통과 (`/up`)
- [ ] 로그인 페이지 접근 가능

### 🔗 접근 링크들
- **애플리케이션**: `https://your-domain.railway.app`
- **헬스체크**: `https://your-domain.railway.app/up`  
- **로그인**: `https://your-domain.railway.app/auth/login`
- **관리자**: `https://your-domain.railway.app/admin`

## 🚨 문제 해결

### 배포 실패 시
1. Railway 대시보드 → **Deployments** → 로그 확인
2. **Variables** 탭에서 환경 변수 재확인
3. `railway redeploy` 수동 재배포

### Bundle install 오류 지속 시
Bundle install exit code 18 오류가 지속되면:
1. **nixpacks** 빌더 사용 중인지 확인
2. 임시로 비활성화된 gem들 확인
3. Railway 콘솔에서 `bundle install --verbose` 실행

### pgvector 오류 시
```bash
# Railway PostgreSQL 콘솔에서
CREATE EXTENSION IF NOT EXISTS vector;
```