# Railway 배포 단계별 가이드

## 1단계: 프로젝트 생성
1. https://railway.app/new 접속
2. "Deploy from GitHub repo" 선택
3. `LEONFROMWORK/ex-rails` 저장소 검색 및 선택
4. "Deploy Now" 클릭

## 2단계: 환경 변수 설정
프로젝트 생성 후 Variables 탭에서 다음 변수들 설정:

### 필수 변수
```
SECRET_KEY_BASE=bd28abcc8ebb9b1f04c4e2d2b402462df272b3cd63164f472229bf0dd7979fa8443e34bb8ee0cb13da6fe26b9ae309fa41ef71d0e6af74b3ba3e7d1aee8127d7
ADMIN_EMAILS=your-email@example.com
PAYMENT_ENABLED=false
SUBSCRIPTION_REQUIRED=false
```

### 도메인 설정 (배포 후)
```
RAILS_HOST=your-generated-domain.railway.app
```

## 3단계: 데이터베이스 서비스 추가
1. 프로젝트 대시보드에서 "Add Service" 클릭
2. "PostgreSQL" 선택하여 추가
3. "Redis" 선택하여 추가
4. DATABASE_URL과 REDIS_URL이 자동으로 설정됨

## 4단계: Formula Engine 서비스 추가 (선택사항)
1. "Add Service" → "GitHub Repo" 선택
2. 동일한 `LEONFROMWORK/ex-rails` 저장소 선택
3. Root Directory를 `formula_service`로 설정
4. 환경 변수 설정:
   ```
   NODE_ENV=production
   PORT=3002
   ```

## 5단계: 도메인 설정
1. 메인 Rails 서비스에서 "Settings" → "Networking" 이동
2. "Generate Domain" 클릭하여 Railway 도메인 생성
3. 생성된 도메인을 RAILS_HOST 환경 변수에 설정

## 6단계: OAuth 설정 (선택사항)
배포 완료 후 OAuth 제공업체에서 리다이렉트 URI 설정:

### Google Cloud Console
- 프로젝트 선택 → APIs & Services → Credentials
- OAuth 2.0 Client IDs 편집
- 승인된 리디렉션 URI에 추가: `https://your-domain.railway.app/auth/google_oauth2/callback`

### Kakao Developers
- 앱 설정 → 카카오 로그인 → Redirect URI
- 추가: `https://your-domain.railway.app/auth/kakao/callback`

## 7단계: 배포 확인
다음 명령어로 배포 상태 확인:
```bash
./check_deployment.sh your-domain.railway.app
```

## 8단계: 로그 모니터링
Railway 대시보드에서 "Deployments" 탭에서 배포 로그 확인

## 문제 해결

### 배포 실패 시
1. Railway 대시보드에서 배포 로그 확인
2. 환경 변수 설정 재확인
3. 필요 시 수동 재배포: "Deploy" 버튼 클릭

### 데이터베이스 연결 실패 시
1. PostgreSQL 서비스가 추가되었는지 확인
2. DATABASE_URL 환경 변수가 자동 설정되었는지 확인
3. 마이그레이션 실행 확인 (배포 로그에서)

### 정적 파일 로드 실패 시
1. `RAILS_SERVE_STATIC_FILES=true` 환경 변수 확인
2. 에셋 프리컴파일이 성공했는지 배포 로그 확인

## 성공 지표
- ✅ 헬스체크 엔드포인트 `/up`이 200 응답
- ✅ 홈페이지 접근 가능
- ✅ 로그인 페이지 접근 가능
- ✅ 관리자 페이지 접근 가능 (설정된 ADMIN_EMAILS로)

## 유용한 링크
- Railway 대시보드: https://railway.app/dashboard
- 프로젝트 설정: Variables, Settings 탭
- 로그 확인: Deployments 탭