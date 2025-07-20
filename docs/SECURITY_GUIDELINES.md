# 보안 및 민감정보 관리 가이드라인 - ExcelApp-Rails

## 🔒 보안 정책

### 민감정보 정의
다음과 같은 정보들은 절대 Git 리포지토리에 커밋되어서는 안됩니다:

#### 인증 정보
- API 키 (OpenAI, Google, AWS 등)
- 데이터베이스 비밀번호
- 암호화 키 및 시크릿
- JWT 서명 키
- OAuth 클라이언트 시크릿

#### 개인정보
- 사용자 이메일 주소
- 전화번호
- 개인 식별 정보
- 결제 정보

#### 시스템 정보
- 서버 IP 주소
- 내부 URL 및 엔드포인트
- 시스템 구성 정보

## 🛡️ 보안 도구 설정

### 1. git-secrets 설정

```bash
# git-secrets 설치 (macOS)
brew install git-secrets

# 글로벌 설정
git secrets --install
git secrets --register-aws

# 프로젝트별 설정
git secrets --install .git/hooks
git secrets --register-aws

# 커스텀 패턴 추가
git secrets --add 'password\s*=\s*["\'][^"\']+["\']'
git secrets --add 'api[_-]?key\s*=\s*["\'][^"\']+["\']'
git secrets --add 'secret\s*=\s*["\'][^"\']+["\']'
git secrets --add 'token\s*=\s*["\'][^"\']+["\']'
```

### 2. Brakeman 보안 스캔

```bash
# Gemfile에 추가
gem 'brakeman', group: [:development, :test]

# 스캔 실행
bundle exec brakeman

# 자동화된 스캔 설정 (CI/CD)
bundle exec brakeman --exit-on-warn --no-pager
```

### 3. Bundler Audit

```bash
# 취약한 의존성 검사
gem install bundler-audit
bundle audit

# CI/CD에서 자동 실행
bundle audit --update
```

## 🔐 환경변수 관리

### .env 파일 구조

```bash
# 개발 환경 (.env.development)
DATABASE_URL=postgresql://localhost/excelapp_development
REDIS_URL=redis://localhost:6379/0
OPENAI_API_KEY=your_openai_key_here
SECRET_KEY_BASE=your_secret_key_base

# 테스트 환경 (.env.test)
DATABASE_URL=postgresql://localhost/excelapp_test
REDIS_URL=redis://localhost:6379/1

# 프로덕션 환경 (서버에서만 설정)
DATABASE_URL=postgresql://production_server/excelapp_production
REDIS_URL=redis://production_server:6379/0
SECRET_KEY_BASE=production_secret_key
```

### Rails Credentials 사용

```bash
# 개발 환경에서 크리덴셜 편집
EDITOR=vim rails credentials:edit

# 프로덕션 크리덴셜 편집
EDITOR=vim rails credentials:edit --environment production

# 크리덴셜 구조 예시
# config/credentials.yml.enc
openai:
  api_key: your_openai_api_key
  
aws:
  access_key_id: your_aws_access_key
  secret_access_key: your_aws_secret_key
  
database:
  password: your_db_password
```

### 환경변수 로딩

```ruby
# config/application.rb
config.before_configuration do
  env_file = Rails.root.join("config", "local_env.yml")
  YAML.load(File.open(env_file)).each do |key, value|
    ENV[key.to_s] = value
  end if File.exists?(env_file)
end

# 안전한 환경변수 접근
class Settings
  def self.openai_api_key
    ENV.fetch('OPENAI_API_KEY') do
      Rails.application.credentials.dig(:openai, :api_key)
    end
  end
  
  def self.database_url
    ENV.fetch('DATABASE_URL') do
      raise 'DATABASE_URL must be set'
    end
  end
end
```

## 🚨 커밋 히스토리 스캔

### 기존 히스토리에서 시크릿 검출

```bash
# git-secrets로 전체 히스토리 스캔
git secrets --scan-history

# truffleHog를 사용한 고급 스캔
pip install truffleHog
truffleHog --regex --entropy=False .

# GitLeaks를 사용한 스캔
# https://github.com/zricethezav/gitleaks
gitleaks detect --source .
```

### 이미 커밋된 시크릿 제거

```bash
# BFG Repo-Cleaner 사용
java -jar bfg.jar --replace-text passwords.txt
git reflog expire --expire=now --all && git gc --prune=now --aggressive

# git filter-branch 사용 (소규모 수정)
git filter-branch --force --index-filter \
  'git rm --cached --ignore-unmatch config/secrets.yml' \
  --prune-empty --tag-name-filter cat -- --all
```

## 🔍 코드 리뷰 보안 체크리스트

### 인증 및 권한
- [ ] 적절한 인증 검사
- [ ] 권한 부여 로직 확인
- [ ] 세션 관리 보안
- [ ] CSRF 보호 확인

### 입력 검증
- [ ] SQL Injection 방지
- [ ] XSS 방지
- [ ] 파일 업로드 검증
- [ ] 매개변수 화이트리스트

### 데이터 보호
- [ ] 민감한 데이터 암호화
- [ ] 로그에 민감정보 노출 방지
- [ ] 에러 메시지에 정보 노출 방지
- [ ] HTTPS 강제 사용

### API 보안
- [ ] Rate limiting 적용
- [ ] API 키 검증
- [ ] 적절한 HTTP 상태 코드
- [ ] CORS 설정 확인

## 🛠️ 보안 설정

### Rails 보안 설정

```ruby
# config/application.rb
config.force_ssl = true # 프로덕션
config.ssl_options = { redirect: { exclude: ->(request) { request.path =~ /health/ } } }

# config/initializers/security.rb
Rails.application.config.session_store :cookie_store,
  key: '_excelapp_session',
  secure: Rails.env.production?,
  httponly: true,
  same_site: :lax

# Content Security Policy
Rails.application.config.content_security_policy do |policy|
  policy.default_src :self, :https
  policy.font_src    :self, :https, :data
  policy.img_src     :self, :https, :data
  policy.object_src  :none
  policy.script_src  :self, :https
  policy.style_src   :self, :https, :unsafe_inline
end
```

### 데이터베이스 보안

```ruby
# config/database.yml - 프로덕션
production:
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  url: <%= ENV['DATABASE_URL'] %>
  sslmode: require
  # 추가 보안 설정
  prepared_statements: false
  advisory_locks: false
```

### HTTP 보안 헤더

```ruby
# config/initializers/security_headers.rb
Rails.application.config.force_ssl = true

Rails.application.config.ssl_options = {
  hsts: {
    expires: 1.year,
    subdomains: true,
    preload: true
  }
}

# 추가 보안 헤더
class SecurityHeadersMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, response = @app.call(env)
    
    headers['X-Frame-Options'] = 'DENY'
    headers['X-Content-Type-Options'] = 'nosniff'
    headers['X-XSS-Protection'] = '1; mode=block'
    headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    
    [status, headers, response]
  end
end

Rails.application.config.middleware.use SecurityHeadersMiddleware
```

## 📋 보안 체크리스트

### 개발 환경
- [ ] .env 파일이 .gitignore에 포함되어 있음
- [ ] git-secrets가 설정되어 있음
- [ ] pre-commit 훅이 활성화되어 있음
- [ ] Brakeman 스캔이 통과함
- [ ] Bundle audit가 깨끗함

### 코드 리뷰
- [ ] 하드코딩된 시크릿이 없음
- [ ] 민감한 정보가 로그에 출력되지 않음
- [ ] 적절한 권한 검사
- [ ] 입력 검증이 올바름
- [ ] SQL 쿼리가 안전함

### 배포 전
- [ ] 환경변수가 올바르게 설정됨
- [ ] SSL/TLS 인증서가 유효함
- [ ] 보안 헤더가 설정됨
- [ ] 데이터베이스 연결이 암호화됨
- [ ] 로그 레벨이 적절함

### 정기 점검
- [ ] 의존성 취약점 스캔 (월 1회)
- [ ] 접근 로그 검토 (주 1회)
- [ ] 실패한 로그인 시도 모니터링
- [ ] API 사용량 모니터링
- [ ] 보안 패치 적용

## 🚨 보안 사고 대응

### 시크릿 노출 시 대응 절차

1. **즉시 조치**
   - 노출된 키/토큰 무효화
   - 새로운 키 생성 및 교체
   - 관련 시스템 로그 확인

2. **Git 히스토리 정리**
   - BFG 또는 git filter-branch로 히스토리에서 제거
   - 팀원들에게 git pull --rebase 안내

3. **모니터링 강화**
   - 비정상적인 API 사용량 확인
   - 로그인 시도 모니터링
   - 시스템 액세스 로그 검토

4. **문서화**
   - 사고 보고서 작성
   - 재발 방지 조치 수립
   - 팀 교육 실시

## 📚 추가 리소스

### 도구
- [git-secrets](https://github.com/awslabs/git-secrets)
- [Brakeman](https://brakemanscanner.org/)
- [bundler-audit](https://github.com/rubysec/bundler-audit)
- [GitLeaks](https://github.com/zricethezav/gitleaks)
- [TruffleHog](https://github.com/trufflesecurity/truffleHog)

### 가이드라인
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Rails Security Guide](https://guides.rubyonrails.org/security.html)
- [GitHub Security Best Practices](https://docs.github.com/en/code-security)

### 모니터링
- [Scout APM](https://scoutapm.com/) - 성능 및 보안 모니터링
- [Honeybadger](https://www.honeybadger.io/) - 에러 추적 및 보안 알림