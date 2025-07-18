# ExcelApp Rails - AI-Powered Excel Error Detection & Correction

AI 기반 엑셀 오류 자동 감지 및 수정 SaaS 플랫폼

## 🚀 주요 기능

### 1. Excel 파일 분석
- **파일 업로드**: .xlsx, .xls, .csv 등 다양한 형식 지원
- **자동 오류 감지**: 수식 오류, 데이터 검증, 순환 참조 등
- **실시간 분석**: WebSocket 기반 실시간 진행 상황 업데이트

### 2. 2단계 AI 분석 시스템
- **Tier 1**: 비용 효율적인 기본 분석 (Claude 3 Haiku, GPT-3.5)
- **Tier 2**: 고급 분석 (Claude 3 Opus, GPT-4)
- **멀티 프로바이더**: OpenAI, Anthropic, Google AI 자동 폴백

### 3. 결제 시스템
- **TossPayments 통합**: 한국 결제 시스템 완벽 지원
- **토큰 기반 과금**: 사용한 만큼 지불
- **구독 모델**: FREE, PRO, ENTERPRISE 티어

### 4. 실시간 채팅
- **AI 채팅**: 엑셀 관련 질문에 AI가 실시간 답변
- **컨텍스트 인식**: 업로드된 파일을 기반으로 한 맞춤형 답변

## 🛠️ 기술 스택

### Backend
- **Ruby on Rails 8.0**: 최신 Rails 프레임워크
- **PostgreSQL**: 메인 데이터베이스
- **Redis**: 캐싱 및 세션 관리
- **Solid Stack**: Rails 8의 통합 도구 모음
  - Solid Queue: 백그라운드 작업
  - Solid Cable: 실시간 WebSocket
  - Solid Cache: 캐싱 시스템

### Excel 처리
- **Roo**: Excel 파일 읽기
- **Caxlsx**: Excel 파일 생성
- **RubyXL**: Excel 파일 조작
- **Creek**: 대용량 파일 스트리밍

### AI & HTTP
- **HTTParty**: HTTP 요청 처리
- **Faraday**: 고급 HTTP 클라이언트
- **Multi-provider**: OpenAI, Anthropic, Google AI

### UI & Frontend
- **ViewComponent**: 컴포넌트 기반 UI
- **Tailwind CSS**: 유틸리티 우선 CSS
- **Stimulus**: 경량 JavaScript 프레임워크
- **Turbo**: SPA 경험 제공

## 🏗️ 아키텍처

### Vertical Slice Architecture
```
app/
├── features/                 # 기능별 수직 슬라이스
│   ├── excel_upload/        # 파일 업로드
│   ├── excel_analysis/      # 엑셀 분석
│   ├── ai_integration/      # AI 통합
│   ├── payment_processing/  # 결제 처리
│   └── user_management/     # 사용자 관리
├── common/                  # 공통 유틸리티
├── infrastructure/          # 외부 의존성
└── components/             # UI 컴포넌트
```

### 2단계 AI 시스템
```
사용자 요청 → Tier 1 분석 → 신뢰도 확인 → Tier 2 분석 (필요시)
```

## 📦 설치 및 실행

### 1. 의존성 설치
```bash
bundle install
```

### 2. 데이터베이스 설정
```bash
rails db:create
rails db:migrate
rails db:seed
```

### 3. 환경 변수 설정
```bash
# .env 파일 생성
OPENAI_API_KEY=your_openai_key
ANTHROPIC_API_KEY=your_anthropic_key
GOOGLE_API_KEY=your_google_key
TOSS_CLIENT_KEY=your_toss_client_key
TOSS_SECRET_KEY=your_toss_secret_key
AWS_ACCESS_KEY_ID=your_aws_access_key
AWS_SECRET_ACCESS_KEY=your_aws_secret_key
```

### 4. 개발 서버 실행
```bash
bin/dev
```

## 🧪 테스트

### 전체 테스트 실행
```bash
bundle exec rspec
```

### 특정 테스트 실행
```bash
bundle exec rspec spec/features/ai_integration/
```

### 코드 품질 검사
```bash
bundle exec rubocop
bundle exec brakeman
```

## 🚀 배포

### Kamal 배포 (권장)
```bash
# 초기 설정
kamal setup

# 배포
kamal deploy

# 로그 확인
kamal app logs
```

### 수동 배포
```bash
# 에셋 컴파일
rails assets:precompile

# 서버 실행
rails server -e production
```

## 📊 성능 목표

- **응답 시간**: 웹 UI < 200ms, API < 100ms
- **파일 처리**: 50MB 파일 < 30초
- **AI 분석**: Tier 1 < 15초, Tier 2 < 30초
- **동시 사용자**: 100명 이상 지원

## 🔒 보안

### 인증 & 권한
- Rails 8 내장 인증 시스템
- 역할 기반 접근 제어 (RBAC)
- JWT 토큰 기반 API 인증

### 데이터 보안
- AES-256 암호화 (민감 데이터)
- 암호화된 S3 파일 저장
- TLS 1.3 통신 보안

### 입력 검증
- 포괄적인 입력 유효성 검사
- 파일 타입 및 크기 제한
- SQL 인젝션 방지

## 📈 모니터링

### 성능 모니터링
- **Scout APM**: 애플리케이션 성능 모니터링
- **Sentry**: 에러 추적 및 성능 분석
- **Custom Metrics**: 비즈니스 로직 모니터링

### 로깅
- 구조화된 JSON 로깅
- 실시간 로그 분석
- 에러 및 성능 메트릭

## 🤝 기여하기

### 개발 가이드라인
1. Vertical Slice Architecture 준수
2. Result Pattern 사용 (비즈니스 로직 오류)
3. 얇은 컨트롤러 유지
4. 컴포넌트 기반 UI 개발

### 코드 스타일
- RuboCop 규칙 준수
- 테스트 커버리지 90% 이상
- 문서화된 API 엔드포인트

## 📞 지원

### 문제 해결
- GitHub Issues: 버그 리포트 및 기능 요청
- 문서: 상세한 API 문서 및 가이드
- 커뮤니티: 개발자 포럼

### 연락처
- 이메일: support@excelapp.com
- 슬랙: #excelapp-support

---

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다.

**ExcelApp Rails** - AI로 엑셀 작업을 더 스마트하게! 🚀