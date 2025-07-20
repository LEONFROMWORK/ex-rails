# Railway 배포 가이드

## 준비 사항

### 1. Railway 계정 및 프로젝트 설정
1. [Railway](https://railway.app) 계정 생성
2. 새 프로젝트 생성
3. GitHub 리포지토리 연결

### 2. 서비스 구성

Railway에서 다음 서비스들을 설정해야 합니다:

#### a) PostgreSQL 데이터베이스
- Railway에서 PostgreSQL 서비스 추가
- `DATABASE_URL` 자동 생성됨

#### b) Redis 인스턴스
- Railway에서 Redis 서비스 추가
- `REDIS_URL` 자동 생성됨

#### c) Rails 앱 (메인 서비스)
- GitHub 리포지토리 연결
- 루트 디렉토리 설정

#### d) Formula Engine (별도 서비스)
- 같은 프로젝트 내 새 서비스 추가
- 디렉토리: `/formula_service`
- 내부 네트워킹으로 연결

## 환경 변수 설정

Railway 대시보드에서 다음 환경 변수를 설정하세요:

### 필수 환경 변수

```env
# Rails 핵심 설정
RAILS_MASTER_KEY=<your_master_key>
SECRET_KEY_BASE=<generate_with_rails_secret>
RAILS_HOST=your-app.railway.app

# OAuth 인증 (Google)
GOOGLE_CLIENT_ID=<your_google_client_id>
GOOGLE_CLIENT_SECRET=<your_google_client_secret>

# OAuth 인증 (Kakao)
KAKAO_CLIENT_ID=<your_kakao_client_id>
KAKAO_CLIENT_SECRET=<your_kakao_client_secret>

# AI 서비스 (최소 하나 필수)
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_AI_API_KEY=AIza...
OPENROUTER_API_KEY=sk-or-...

# 관리자 이메일 (쉼표로 구분)
ADMIN_EMAILS=your-email@example.com

# Formula Engine URL (내부 네트워킹)
FORMULA_ENGINE_URL=http://formula-engine.railway.internal:3002

# 기능 플래그
PAYMENT_ENABLED=false
SUBSCRIPTION_REQUIRED=false
```

### 선택적 환경 변수

```env
# AWS S3 (파일 저장용)
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_REGION=
AWS_BUCKET=

# 이메일 설정
SMTP_ADDRESS=
SMTP_PORT=
SMTP_DOMAIN=
SMTP_USER_NAME=
SMTP_PASSWORD=
```

## 배포 단계

### 1. 로컬에서 준비

```bash
# 마스터 키 확인
cat config/master.key

# SECRET_KEY_BASE 생성
rails secret

# 자산 사전 컴파일 테스트
RAILS_ENV=production bundle exec rails assets:precompile
```

### 2. OAuth 리다이렉트 URL 설정

#### Google OAuth
1. [Google Cloud Console](https://console.cloud.google.com) 접속
2. OAuth 2.0 클라이언트 ID 설정
3. 승인된 리디렉션 URI 추가:
   - `https://your-app.railway.app/auth/google_oauth2/callback`

#### Kakao OAuth
1. [Kakao Developers](https://developers.kakao.com) 접속
2. 앱 설정 > 플랫폼 > Web 플랫폼 추가
3. 사이트 도메인: `https://your-app.railway.app`
4. Redirect URI: `https://your-app.railway.app/auth/kakao/callback`

### 3. Railway 배포

```bash
# Git push로 자동 배포
git add .
git commit -m "Production deployment ready"
git push origin main
```

### 4. 배포 후 확인

1. 데이터베이스 마이그레이션 확인
2. 헬스체크 엔드포인트: `https://your-app.railway.app/up`
3. OAuth 로그인 테스트
4. Formula Engine 연결 확인

## 트러블슈팅

### 자산 컴파일 오류
```bash
# Railway 로그 확인
railway logs

# 로컬에서 문제 재현
RAILS_ENV=production bundle exec rails assets:precompile
```

### 데이터베이스 연결 오류
- `DATABASE_URL` 환경 변수 확인
- PostgreSQL 서비스 상태 확인
- 네트워크 설정 확인

### Formula Engine 연결 오류
- 내부 네트워킹 URL 확인
- 서비스 간 통신 허용 확인
- 포트 설정 확인 (3002)

## 성능 최적화

### 1. 캐싱 설정
- Redis가 자동으로 Rails 캐시로 사용됨
- Solid Cache로 영구 캐싱 구현

### 2. 작업 큐
- Solid Queue가 백그라운드 작업 처리
- 별도 워커 프로세스 불필요

### 3. 자산 최적화
- Tailwind CSS 프로덕션 빌드
- JavaScript 번들 최적화
- 이미지 최적화

## 모니터링

### 1. 에러 추적
- 내장 에러 모니터링 시스템 활성화
- `/admin/stats`에서 에러 통계 확인

### 2. 성능 모니터링
- Railway 대시보드에서 메트릭 확인
- 응답 시간 및 메모리 사용량 모니터링

### 3. 로그 확인
```bash
# Railway CLI로 로그 확인
railway logs

# 특정 서비스 로그
railway logs -s formula-engine
```

## 백업 및 복구

### 데이터베이스 백업
```bash
# Railway CLI로 백업
railway run rails db:dump

# 복구
railway run rails db:restore
```

### 주기적 백업
- Railway는 자동 백업 제공
- 추가 백업은 S3에 저장 권장

## 보안 체크리스트

- [ ] 모든 환경 변수 설정 완료
- [ ] OAuth 리다이렉트 URL 설정
- [ ] HTTPS 강제 적용 확인
- [ ] CSP 헤더 작동 확인
- [ ] 관리자 이메일 설정
- [ ] 프로덕션 시드 데이터 확인

## 지원 및 문의

문제 발생 시:
1. Railway 상태 페이지 확인
2. 애플리케이션 로그 분석
3. GitHub Issues에 문제 보고