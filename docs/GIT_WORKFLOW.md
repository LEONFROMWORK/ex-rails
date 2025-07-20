# Git Workflow Guide - ExcelApp-Rails

## 브랜치 전략

### GitHub Flow 기반 워크플로우

우리는 단순하고 효과적인 **GitHub Flow**를 사용합니다:

```
main (production-ready)
├── feature/excel-analysis-v2
├── feature/user-authentication
├── hotfix/security-patch
└── docs/api-documentation
```

### 브랜치 유형

#### 1. Main Branch (`main`)
- **목적**: 프로덕션 배포 가능한 코드
- **보호**: 직접 푸시 금지, PR을 통해서만 병합
- **자동화**: CI/CD 파이프라인 자동 실행

#### 2. Feature Branches (`feature/`)
- **명명 규칙**: `feature/description-of-feature`
- **예시**: 
  - `feature/excel-formula-engine`
  - `feature/user-dashboard-redesign`
  - `feature/ai-integration-openai`
- **생명주기**: 기능 완성 후 삭제

#### 3. Hotfix Branches (`hotfix/`)
- **명명 규칙**: `hotfix/critical-issue-description`
- **예시**: 
  - `hotfix/security-vulnerability-fix`
  - `hotfix/excel-upload-crash`
- **우선순위**: 최고 (즉시 리뷰 및 배포)

#### 4. Documentation Branches (`docs/`)
- **명명 규칙**: `docs/documentation-topic`
- **예시**: 
  - `docs/api-reference-update`
  - `docs/deployment-guide`

## 워크플로우 단계

### 1. 새 기능 개발

```bash
# 1. main 브랜치에서 최신 코드 가져오기
git checkout main
git pull origin main

# 2. 새 기능 브랜치 생성
git checkout -b feature/excel-ai-analysis

# 3. 개발 작업 수행
# ... 코딩 ...

# 4. 변경사항 커밋 (conventional commits 규칙 준수)
git add .
git commit -m "feat(ai): add Excel AI analysis service"

# 5. 원격 브랜치에 푸시
git push -u origin feature/excel-ai-analysis

# 6. Pull Request 생성
# GitHub에서 PR 생성 및 리뷰 요청
```

### 2. 코드 리뷰 프로세스

#### 리뷰어 요구사항
- **모든 PR**: 최소 1명의 승인 필요
- **중요한 변경**: 2명 이상의 승인 권장
- **아키텍처 변경**: 시니어 개발자 승인 필수

#### 리뷰 체크리스트
- [ ] 코드 품질 및 가독성
- [ ] 테스트 커버리지
- [ ] 보안 고려사항
- [ ] 성능 영향도
- [ ] 문서화 적절성

### 3. 병합 및 배포

```bash
# PR 승인 후 main으로 병합
# - Squash merge 사용 (기본)
# - Merge commit 제목은 conventional format 준수
```

## 커밋 메시지 규칙

### Conventional Commits 형식

```
type(scope): description

[optional body]

[optional footer]
```

### 타입 정의

- **feat**: 새로운 기능
- **fix**: 버그 수정
- **docs**: 문서 변경
- **style**: 코드 포맷팅, 세미콜론 누락 등
- **refactor**: 코드 리팩토링
- **test**: 테스트 추가/수정
- **chore**: 빌드 프로세스나 도구 변경
- **perf**: 성능 향상
- **ci**: CI 설정 변경
- **build**: 빌드 시스템 또는 의존성 변경

### 예시

```bash
# 좋은 예시
feat(excel): add formula validation engine
fix(auth): resolve session timeout issue
docs(api): update Excel processing endpoints
test(upload): add file size validation tests

# 나쁜 예시
added new feature
bug fix
updated docs
```

## 브랜치 명명 규칙

### 형식
```
type/short-description
```

### 규칙
- **소문자 사용**: `feature/user-auth` ✅ `Feature/User-Auth` ❌
- **하이픈 구분**: `feature/excel-ai-analysis` ✅ `feature/excel_ai_analysis` ❌
- **간결하게**: 3-5 단어 이내
- **명확하게**: 기능이나 목적을 쉽게 파악 가능

### 예시

```bash
# Feature branches
feature/excel-formula-engine
feature/user-authentication
feature/ai-cost-optimization
feature/admin-dashboard

# Hotfix branches
hotfix/memory-leak-fix
hotfix/security-patch-cors
hotfix/excel-upload-timeout

# Documentation branches
docs/api-reference
docs/deployment-guide
docs/contributing-guidelines
```

## Git 명령어 모음

### 일상적인 작업

```bash
# 브랜치 생성 및 전환
git checkout -b feature/new-feature

# 변경사항 스테이징
git add .                    # 모든 변경사항
git add -p                   # 선택적 스테이징

# 커밋
git commit -m "feat(scope): description"
git commit --amend          # 최근 커밋 수정

# 푸시
git push -u origin branch-name   # 첫 푸시
git push                         # 이후 푸시

# 브랜치 정리
git branch -d feature/completed-feature  # 로컬 브랜치 삭제
git push origin --delete feature/completed-feature  # 원격 브랜치 삭제
```

### 고급 작업

```bash
# 리베이스로 깔끔한 히스토리 유지
git rebase main
git rebase -i HEAD~3        # 인터랙티브 리베이스

# 체리픽으로 특정 커밋 적용
git cherry-pick <commit-hash>

# 스태시를 사용한 임시 저장
git stash                   # 변경사항 임시 저장
git stash pop               # 저장된 변경사항 복원
git stash list              # 스태시 목록 확인
```

## 협업 규칙

### 1. 브랜치 관리
- **짧은 생명주기**: feature 브랜치는 1-2주 이내 완료
- **정기적 동기화**: 최소 주 2회 main 브랜치와 동기화
- **완료 후 정리**: PR 병합 후 즉시 브랜치 삭제

### 2. 커밋 관리
- **원자적 커밋**: 하나의 커밋은 하나의 변경사항
- **의미있는 메시지**: 나중에 봐도 이해할 수 있는 커밋 메시지
- **정기적 커밋**: 작은 단위로 자주 커밋

### 3. 충돌 해결
- **빠른 해결**: 충돌 발생 시 24시간 이내 해결
- **소통**: 충돌 시 관련 개발자와 즉시 소통
- **테스트**: 충돌 해결 후 반드시 테스트 실행

## 트러블슈팅

### 자주 발생하는 문제들

#### 1. 커밋 메시지 수정
```bash
# 마지막 커밋 메시지 수정
git commit --amend -m "올바른 커밋 메시지"

# 이미 푸시한 경우 (주의: 다른 사람과 공유 중이면 사용 금지)
git push --force-with-lease
```

#### 2. 잘못된 브랜치에서 작업한 경우
```bash
# 현재 작업을 스태시에 저장
git stash

# 올바른 브랜치로 이동
git checkout correct-branch

# 작업 복원
git stash pop
```

#### 3. main 브랜치와 동기화
```bash
# feature 브랜치에서 실행
git fetch origin
git rebase origin/main
```

## 자동화 도구

### Git Hooks
프로젝트에는 다음 훅이 설정되어 있습니다:

- **pre-commit**: 코드 스타일, 보안 검사
- **commit-msg**: 커밋 메시지 형식 검증
- **pre-push**: 전체 테스트 스위트 실행

### 설정 방법
```bash
# Git hooks 설정
./script/setup-git-hooks
```

## 리소스

- [Conventional Commits](https://www.conventionalcommits.org/)
- [GitHub Flow](https://guides.github.com/introduction/flow/)
- [Git 공식 문서](https://git-scm.com/doc)
- [Pro Git 책](https://git-scm.com/book)