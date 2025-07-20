# ExcelApp-Rails Git 모범사례 설정 가이드

## 🎯 완료된 Git 모범사례 적용 사항

ExcelApp-Rails 프로젝트에 다음과 같은 Git 모범사례가 성공적으로 적용되었습니다:

### ✅ 완료된 작업

#### 1. Git 구성 최적화
- **`.gitignore`**: Rails, Node.js, 개발 도구, 보안 등을 포함한 포괄적인 파일 무시 규칙
- **`.gitattributes`**: 라인 엔딩 정규화, 바이너리 파일 처리, 언어별 diff 설정
- **Git hooks**: pre-commit, pre-push, commit-msg 훅 자동 설치

#### 2. 브랜치 전략 및 워크플로우
- **GitHub Flow** 기반 워크플로우 문서화
- **브랜치 명명 규칙** 정의 (`feature/`, `fix/`, `hotfix/`, `docs/`)
- **커밋 메시지 컨벤션** (Conventional Commits 형식)

#### 3. 코드 품질 자동화
- **Pre-commit hooks**: RuboCop, Brakeman, ESLint 자동 실행
- **Pre-push hooks**: 전체 테스트 스위트 실행
- **Commit message linting**: 커밋 메시지 형식 자동 검증
- **Pre-commit framework**: `.pre-commit-config.yaml` 설정

#### 4. 보안 및 민감정보 관리
- **보안 가이드라인** 문서 작성
- **민감정보 검출** 패턴 설정
- **환경변수 관리** 방법 정의
- **보안 도구** 권장사항 제공

#### 5. 문서화
- **`CONTRIBUTING.md`**: 종합적인 기여 가이드
- **`docs/GIT_WORKFLOW.md`**: Git 워크플로우 상세 가이드
- **`docs/SECURITY_GUIDELINES.md`**: 보안 정책 및 가이드라인
- **Pull Request 템플릿**: 체계적인 PR 검토 프로세스

## 🚀 빠른 시작 가이드

### 1. 개발 환경 설정

```bash
# 1. 프로젝트 클론
git clone <repository-url>
cd excelapp-rails

# 2. 의존성 설치
bundle install
npm install

# 3. Git hooks 설정 (자동화)
./script/setup-git-hooks

# 4. Pre-commit framework 설정 (선택사항)
pip install pre-commit
pre-commit install
```

### 2. 개발 워크플로우

```bash
# 1. 새 기능 브랜치 생성
git checkout main
git pull origin main
git checkout -b feature/your-feature-name

# 2. 개발 및 커밋 (자동 검증)
git add .
git commit -m "feat(scope): add new feature"

# 3. 푸시 및 PR 생성 (자동 테스트)
git push -u origin feature/your-feature-name
# GitHub에서 PR 생성
```

### 3. 코드 품질 검사

```bash
# 수동 검사 실행
bundle exec rubocop                # Ruby 코드 스타일
bundle exec brakeman              # 보안 스캔
bundle exec rspec                 # 테스트 실행
npx eslint .                      # JavaScript 린팅
```

## 📁 생성된 파일 목록

### Git 설정 파일
- **`.gitignore`**: 포괄적인 파일 무시 규칙
- **`.gitattributes`**: 파일 속성 및 라인 엔딩 설정
- **`.pre-commit-config.yaml`**: Pre-commit framework 설정

### Git Hooks
- **`script/setup-git-hooks`**: Git hooks 자동 설치 스크립트
- **`script/hooks/pre-commit`**: 커밋 전 코드 품질 검사
- **`script/hooks/pre-push`**: 푸시 전 전체 테스트 실행
- **`script/hooks/commit-msg`**: 커밋 메시지 형식 검증
- **`script/hooks/check-schema`**: 데이터베이스 스키마 검사
- **`script/hooks/check-rspec-focus`**: RSpec 포커스 테스트 검출
- **`script/hooks/update-readme-toc`**: README 목차 자동 업데이트

### GitHub 템플릿
- **`.github/pull_request_template.md`**: PR 템플릿

### 문서
- **`CONTRIBUTING.md`**: 종합 기여 가이드
- **`docs/GIT_WORKFLOW.md`**: Git 워크플로우 가이드
- **`docs/SECURITY_GUIDELINES.md`**: 보안 가이드라인
- **`docs/SETUP_GUIDE.md`**: 이 파일

## ⚙️ 설정 커스터마이징

### Git Hooks 수정

```bash
# hooks 수정 후 재설치
./script/setup-git-hooks
```

### Pre-commit 설정 수정

```yaml
# .pre-commit-config.yaml 편집 후
pre-commit install
pre-commit run --all-files  # 전체 파일 검사
```

### RuboCop 설정

```yaml
# .rubocop.yml 파일 생성/수정
AllCops:
  TargetRubyVersion: 3.2
  NewCops: enable
  Exclude:
    - 'vendor/**/*'
    - 'node_modules/**/*'
```

## 🔧 문제 해결

### Git Hooks 실행 안됨

```bash
# 권한 확인 및 부여
ls -la .git/hooks/
chmod +x .git/hooks/*
```

### Pre-commit 설치 문제

```bash
# Python 가상환경에서 설치
python -m venv venv
source venv/bin/activate  # Linux/Mac
pip install pre-commit
```

### 커밋 메시지 형식 오류

```bash
# 올바른 형식 예시
git commit -m "feat(excel): add formula validation"
git commit -m "fix(auth): resolve session timeout"
git commit -m "docs: update API documentation"
```

## 📊 Git 모범사례 효과

### 코드 품질 향상
- ✅ 자동 코드 스타일 검사
- ✅ 보안 취약점 조기 발견
- ✅ 테스트 커버리지 보장

### 협업 효율성 증대
- ✅ 일관된 커밋 메시지
- ✅ 체계적인 브랜치 관리
- ✅ 명확한 PR 프로세스

### 보안 강화
- ✅ 민감정보 커밋 방지
- ✅ 의존성 취약점 검사
- ✅ 보안 가이드라인 준수

## 🎉 다음 단계

이제 Git 모범사례가 적용된 ExcelApp-Rails 프로젝트에서 안전하고 효율적인 개발을 시작할 수 있습니다!

1. **팀원 교육**: `CONTRIBUTING.md` 문서 공유
2. **CI/CD 통합**: GitHub Actions 등과 연동
3. **정기 점검**: 월간 보안 스캔 및 의존성 업데이트
4. **프로세스 개선**: 팀 피드백을 통한 지속적 개선

---

문의사항이나 개선 제안이 있으시면 언제든지 이슈를 생성해주세요!