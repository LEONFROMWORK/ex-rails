# Contributing to ExcelApp-Rails

ExcelApp-Rails 프로젝트에 기여해주셔서 감사합니다! 이 문서는 프로젝트에 효과적으로 기여하는 방법을 안내합니다.

## 📋 목차

- [시작하기](#시작하기)
- [개발 환경 설정](#개발-환경-설정)
- [Git 워크플로우](#git-워크플로우)
- [코딩 스타일](#코딩-스타일)
- [테스트](#테스트)
- [Pull Request 가이드라인](#pull-request-가이드라인)
- [이슈 보고](#이슈-보고)
- [보안](#보안)
- [커뮤니티 가이드라인](#커뮤니티-가이드라인)

## 🚀 시작하기

### 프로젝트 클론 및 설정

```bash
# 1. 프로젝트 포크 및 클론
git clone https://github.com/your-username/excelapp-rails.git
cd excelapp-rails

# 2. 업스트림 리모트 추가
git remote add upstream https://github.com/original/excelapp-rails.git

# 3. 의존성 설치
bundle install
npm install

# 4. 데이터베이스 설정
rails db:create
rails db:migrate
rails db:seed

# 5. Git hooks 설정
./script/setup-git-hooks

# 6. Pre-commit hooks 설정 (선택사항)
pip install pre-commit
pre-commit install
```

### 환경 변수 설정

```bash
# .env.development 파일 생성
cp .env.example .env.development

# 필요한 API 키 설정
# OPENAI_API_KEY=your_key_here
# DATABASE_URL=postgresql://localhost/excelapp_development
```

## 🛠️ 개발 환경 설정

### 필요한 도구

- **Ruby**: 3.2.0 이상
- **Rails**: 7.1.0 이상
- **Node.js**: 18.0 이상
- **PostgreSQL**: 14.0 이상
- **Redis**: 6.0 이상

### 권장 도구

```bash
# 코드 품질
gem install rubocop
gem install brakeman
gem install bundler-audit

# JavaScript 도구
npm install -g eslint
npm install -g prettier

# Git 보안
brew install git-secrets
```

### 개발 서버 실행

```bash
# Rails 서버 시작
bin/dev

# 또는 개별 서비스 시작
rails server
./bin/webpack-dev-server
redis-server
```

## 📝 Git 워크플로우

### 브랜치 전략

우리는 **GitHub Flow**를 사용합니다:

1. `main` 브랜치에서 새 브랜치 생성
2. 기능 개발 및 테스트
3. Pull Request 생성
4. 코드 리뷰 및 승인
5. `main`으로 병합

### 브랜치 명명 규칙

```bash
# 새로운 기능
feature/excel-ai-analysis
feature/user-authentication

# 버그 수정
fix/upload-timeout-issue
fix/formula-parsing-error

# 핫픽스
hotfix/security-patch
hotfix/critical-bug-fix

# 문서
docs/api-reference
docs/contributing-guide
```

### 커밋 메시지 규칙

[Conventional Commits](https://www.conventionalcommits.org/) 형식을 따릅니다:

```
type(scope): description

[optional body]

[optional footer]
```

#### 타입

- `feat`: 새로운 기능
- `fix`: 버그 수정
- `docs`: 문서 변경
- `style`: 코드 포맷팅
- `refactor`: 코드 리팩토링
- `test`: 테스트 추가/수정
- `chore`: 빌드, 설정 변경
- `perf`: 성능 향상
- `ci`: CI/CD 설정 변경

#### 예시

```bash
feat(excel): add formula validation engine
fix(auth): resolve session timeout issue
docs(api): update Excel processing endpoints
test(upload): add file size validation tests
```

## 🎨 코딩 스타일

### Ruby/Rails

- **RuboCop** 설정을 따릅니다
- **Rails 모범사례**를 준수합니다
- **SOLID 원칙**을 적용합니다

```ruby
# 좋은 예시
class ExcelAnalysisService
  def initialize(file)
    @file = file
  end

  def analyze
    validate_file
    extract_data
    process_formulas
  end

  private

  attr_reader :file

  def validate_file
    # 파일 검증 로직
  end
end

# 나쁜 예시
class ExcelService
  def do_everything(file)
    # 너무 많은 책임
  end
end
```

### JavaScript/TypeScript

- **ESLint** 및 **Prettier** 설정을 따릅니다
- **모던 ES6+** 문법을 사용합니다

```javascript
// 좋은 예시
const analyzeExcel = async (file) => {
  try {
    const result = await processFile(file);
    return { success: true, data: result };
  } catch (error) {
    return { success: false, error: error.message };
  }
};

// 나쁜 예시
function analyzeExcel(file, callback) {
  // 콜백 지옥
}
```

### CSS/SCSS

- **Tailwind CSS** 유틸리티 클래스 우선 사용
- **컴포넌트 기반** 스타일링
- **반응형 디자인** 고려

## 🧪 테스트

### 테스트 커버리지

- **단위 테스트**: 모든 서비스 및 모델
- **통합 테스트**: API 엔드포인트
- **시스템 테스트**: 주요 사용자 플로우

### RSpec 테스트 작성

```ruby
# spec/services/excel_analysis_service_spec.rb
RSpec.describe ExcelAnalysisService do
  describe '#analyze' do
    context 'when file is valid' do
      let(:file) { fixture_file_upload('sample.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') }
      
      it 'returns analysis results' do
        service = described_class.new(file)
        result = service.analyze
        
        expect(result).to be_successful
        expect(result.data).to include(:formulas, :errors)
      end
    end

    context 'when file is invalid' do
      let(:file) { fixture_file_upload('invalid.txt', 'text/plain') }
      
      it 'raises validation error' do
        service = described_class.new(file)
        
        expect { service.analyze }.to raise_error(ExcelAnalysisService::InvalidFileError)
      end
    end
  end
end
```

### 테스트 실행

```bash
# 전체 테스트 스위트
bundle exec rspec

# 특정 파일
bundle exec rspec spec/services/excel_analysis_service_spec.rb

# 태그별 실행
bundle exec rspec --tag focus

# 커버리지 확인
COVERAGE=true bundle exec rspec
```

## 📝 Pull Request 가이드라인

### PR 생성 전 체크리스트

- [ ] 최신 `main` 브랜치와 동기화
- [ ] 모든 테스트 통과
- [ ] 코드 스타일 검사 통과
- [ ] 보안 스캔 통과
- [ ] 관련 문서 업데이트

### PR 템플릿

Pull Request를 생성할 때 제공되는 템플릿을 모두 작성해주세요:

- **요약**: 변경사항 간단 설명
- **변경 유형**: feat, fix, docs 등
- **테스트**: 수행한 테스트 설명
- **체크리스트**: 모든 항목 확인

### 코드 리뷰 과정

1. **자동 검사**: CI/CD 파이프라인 통과
2. **피어 리뷰**: 최소 1명의 승인 필요
3. **시니어 리뷰**: 아키텍처 변경 시 필수
4. **최종 승인**: 모든 피드백 반영 후 병합

### 리뷰어 가이드라인

#### 리뷰 시 확인사항

- **기능성**: 요구사항 충족도
- **코드 품질**: 가독성, 유지보수성
- **성능**: 쿼리 최적화, 메모리 사용
- **보안**: 취약점, 민감정보 노출
- **테스트**: 커버리지, 케이스 완성도

#### 피드백 작성 방법

```markdown
# 좋은 피드백
💡 **제안**: 이 쿼리는 N+1 문제가 발생할 수 있습니다. `includes`를 사용해보세요.

🐛 **문제**: 이 메서드는 nil을 반환할 수 있어 다음 줄에서 오류가 발생할 수 있습니다.

✅ **칭찬**: 에러 핸들링이 잘 되어 있네요!

# 나쁜 피드백
이거 틀렸음
다시 해
```

## 🐛 이슈 보고

### 버그 리포트

버그를 발견했다면 다음 정보를 포함해서 이슈를 생성해주세요:

```markdown
## 버그 설명
Excel 파일 업로드 시 타임아웃 발생

## 재현 단계
1. 5MB 이상의 Excel 파일 준비
2. 파일 업로드 페이지 접속
3. 파일 선택 후 업로드 시도
4. 30초 후 타임아웃 오류 발생

## 예상 동작
파일이 정상적으로 업로드되어야 함

## 실제 동작
타임아웃 오류 발생

## 환경
- OS: macOS 13.0
- 브라우저: Chrome 108.0
- 파일 크기: 5.2MB
```

### 기능 요청

새로운 기능을 제안할 때는:

```markdown
## 기능 설명
Excel 파일에서 차트 정보 추출 기능

## 사용 사례
데이터 분석 시 차트 정보도 함께 분석하고 싶음

## 제안 해결책
1. Chart 모델 추가
2. ChartExtractor 서비스 구현
3. 분석 결과에 차트 정보 포함

## 추가 컨텍스트
현재는 셀 데이터만 추출되고 있음
```

## 🔒 보안

### 보안 정책

- **민감정보**: 절대 커밋하지 않기
- **의존성**: 정기적으로 취약점 스캔
- **API 키**: 환경변수 또는 Rails credentials 사용
- **사용자 입력**: 항상 검증 및 sanitize

### 보안 도구 사용

```bash
# Brakeman 보안 스캔
bundle exec brakeman

# 의존성 취약점 검사
bundle audit

# Git secrets 스캔
git secrets --scan
```

### 보안 이슈 보고

보안 취약점을 발견했다면:

1. **공개 이슈로 보고하지 마세요**
2. **security@excelapp.com**으로 이메일 발송
3. **상세한 설명과 재현 방법 포함**
4. **24시간 내 회신 예상**

## 👥 커뮤니티 가이드라인

### 행동 규범

- **존중**: 모든 기여자를 존중합니다
- **포용**: 다양성을 환영합니다
- **건설적**: 건설적인 피드백을 제공합니다
- **협력**: 함께 문제를 해결합니다

### 소통 채널

- **GitHub Issues**: 버그 리포트, 기능 요청
- **GitHub Discussions**: 일반적인 질문, 토론
- **Slack**: 실시간 소통 (팀 내부)
- **Email**: 보안 이슈, 긴급 문의

### 멘토링

새로운 기여자를 위한 지원:

- **Good First Issue** 라벨로 초보자 친화적 이슈 표시
- **멘토 배정** 프로그램 운영
- **문서화** 개선을 통한 진입 장벽 낮추기

## 📚 추가 리소스

### 문서

- [Git Workflow Guide](docs/GIT_WORKFLOW.md)
- [Security Guidelines](docs/SECURITY_GUIDELINES.md)
- [API Documentation](docs/API.md)
- [Architecture Overview](docs/ARCHITECTURE.md)

### 개발 도구

- [RuboCop 설정](.rubocop.yml)
- [ESLint 설정](.eslintrc.js)
- [Pre-commit 설정](.pre-commit-config.yaml)

### 학습 자료

- [Ruby on Rails Guides](https://guides.rubyonrails.org/)
- [RSpec Documentation](https://rspec.info/)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [Git Best Practices](https://git-scm.com/doc)

## 🙏 감사합니다

ExcelApp-Rails 프로젝트에 기여해주시는 모든 분들께 감사드립니다. 여러분의 기여가 프로젝트를 더욱 발전시킵니다!

### 주요 기여자

<!-- 기여자 목록은 자동으로 업데이트됩니다 -->

---

질문이나 도움이 필요하시면 언제든지 이슈를 생성하거나 팀에 문의해주세요!