# FormulaEngine UI 구현 문서

## 개요

이 문서는 FormulaEngine을 통한 수식 분석 결과를 사용자에게 보여주는 UI 구현에 대해 설명합니다.

## 구현된 기능

### 1. 수식 분석 탭 추가

- **위치**: `app/views/excel_files/show.html.erb`
- **기능**: 기존 "Analysis Results", "VBA Analysis", "Image Analysis", "History" 탭에 "Formula Analysis" 탭 추가
- **아이콘**: `fas fa-calculator`

### 2. 수식 복잡도 표시

- **복잡도 점수**: 0-5.0 범위의 수치로 표시
- **복잡도 레벨**: Low, Medium, High, Very High로 분류
- **시각적 표현**: 그라데이션 배경의 카드 컴포넌트
- **애니메이션**: 숫자 카운팅 효과

### 3. 함수 사용 통계

#### 차트 시각화
- **타입**: Chart.js 도넛 차트
- **데이터**: 함수 카테고리별 사용량
- **카테고리**: Statistical, Logical, Lookup, Text, Date & Time, Math, Reference, Other

#### 함수 테이블
- **표시 내용**: 상위 10개 사용 함수
- **정보**: 함수명, 사용 횟수, 카테고리
- **정렬**: 사용 횟수 기준 내림차순
- **스크롤**: 테이블 최대 높이 400px, 스크롤 가능

### 4. 의존성 분석

- **차트**: 직접/간접 의존성 비율 파이 차트
- **통계**: 직접 의존성, 간접 의존성, 중첩 수식 개수
- **시각화**: Chart.js 파이 차트

### 5. 순환 참조 경고

- **표시 조건**: 순환 참조가 있을 때만 표시
- **심각도**: Low, Medium, High 분류
- **정보**: 영향받는 셀, 참조 체인, 설명
- **스타일**: 빨간색 경고 카드

### 6. 수식 오류 목록

- **오류 타입**: REF, NAME, VALUE, DIV, NUM 등
- **표시 정보**: 셀 위치, 수식, 오류 메시지, 수정 제안
- **심각도**: High, Medium, Low 분류
- **상호작용**: 각 오류 항목은 클릭 가능

### 7. 최적화 제안

- **제안 타입**: 
  - complexity_reduction: 복잡한 수식 단순화
  - function_upgrade: VLOOKUP → XLOOKUP 등
  - maintainability: 하드코딩 값 개선
- **우선순위**: High, Medium, Low
- **표시 정보**: 현재 수식, 문제점, 개선 제안

## JavaScript 컴포넌트

### FormulaAnalysisController (Stimulus)

**파일**: `app/javascript/controllers/formula_analysis_controller.js`

#### 주요 기능
- Chart.js 차트 관리
- 실시간 데이터 업데이트
- 애니메이션 효과
- 인터랙티브 기능 (정렬, 필터링)
- 키보드 단축키 지원

#### 주요 메소드
- `updateAllComponents()`: 모든 UI 컴포넌트 업데이트
- `updateFunctionChart()`: 함수 사용 차트 생성/업데이트
- `updateFunctionTable()`: 함수 테이블 생성/업데이트
- `animateNumber()`: 숫자 카운팅 애니메이션
- `exportAnalysisData()`: 분석 데이터 JSON 내보내기

## 백엔드 통합

### 컨트롤러 액션

**파일**: `app/controllers/excel_files_controller.rb`

#### 새로운 액션
- `analyze_formulas`: FormulaEngine 분석 수행 (5토큰 소모)
- `formula_results`: 수식 분석 결과 조회

#### 비동기 처리
- **잡**: `ExcelAnalysis::Jobs::AnalyzeFormulaJob`
- **큐**: ActiveJob 기본 큐
- **알림**: ActionCable을 통한 실시간 진행상황 알림

### 데이터베이스 필드

**테이블**: `analyses`

#### 추가된 필드
- `formula_analysis`: JSON 형태의 원본 분석 데이터
- `formula_complexity_score`: DECIMAL 복잡도 점수
- `formula_count`: INTEGER 수식 개수
- `formula_functions`: JSON 함수 사용 통계
- `formula_dependencies`: JSON 의존성 정보
- `circular_references`: JSON 순환 참조 정보
- `formula_errors`: JSON 수식 오류 목록
- `formula_optimization_suggestions`: JSON 최적화 제안

## 스타일링

### CSS 클래스

**파일**: `app/views/excel_files/show.html.erb` (인라인 스타일)

#### 주요 클래스
- `.formula-complexity-*`: 복잡도 레벨별 스타일
- `.formula-chart-container`: 차트 컨테이너
- `.formula-stats-card`: 통계 카드
- `.formula-error-card`: 오류 카드
- `.formula-suggestion-card`: 제안 카드
- `.circular-ref-warning`: 순환 참조 경고

#### 반응형 디자인
- **모바일**: 1열 그리드
- **태블릿**: 2열 그리드
- **데스크톱**: 4열 그리드
- **차트 높이**: 디바이스별 최적화

#### 애니메이션
- `countUp`: 숫자 카운팅 효과
- `fadeIn`: 페이드인 효과
- 호버 효과 및 트랜지션

## 라우팅

**파일**: `config/routes.rb`

```ruby
resources :excel_files do
  member do
    post :analyze_formulas
    get :formula_results
  end
end
```

## 의존성

### JavaScript 라이브러리
- **Chart.js 4.4.0**: 차트 라이브러리
- **Stimulus**: 프론트엔드 프레임워크

### CSS 프레임워크
- **Tailwind CSS**: 유틸리티 CSS
- **커스텀 스타일**: 수식 분석 전용 스타일

## 사용 방법

### 1. 수식 분석 실행
1. Excel 파일 상세 페이지로 이동
2. "Formula Analysis" 탭 클릭
3. "Analyze Formulas (5 tokens)" 버튼 클릭
4. 토큰 소모 확인 후 분석 실행

### 2. 결과 확인
- **개요**: 복잡도, 수식 개수, 함수 종류, 순환 참조 요약
- **함수 분석**: 카테고리별 차트, 상위 함수 테이블
- **의존성**: 의존성 차트 및 통계
- **문제점**: 순환 참조, 오류, 최적화 제안

### 3. 상호작용
- **차트 호버**: 상세 정보 툴팁 표시
- **테이블 스크롤**: 많은 함수 목록 스크롤
- **오류 클릭**: 상세 오류 정보 확인
- **데이터 내보내기**: Ctrl+E로 JSON 다운로드

## 성능 최적화

### 프론트엔드
- **지연 로딩**: 차트는 탭 활성화 시에만 생성
- **메모리 관리**: 차트 인스턴스 정리
- **애니메이션**: CSS Transform 활용
- **이미지 최적화**: SVG 아이콘 사용

### 백엔드
- **비동기 처리**: 백그라운드 잡으로 분석 수행
- **캐싱**: 분석 결과 DB 저장
- **토큰 관리**: 사용자별 토큰 확인 및 차감

## 에러 처리

### JavaScript
- **차트 생성 실패**: 기본 메시지 표시
- **데이터 로드 실패**: 재시도 버튼 제공
- **네트워크 오류**: 사용자 친화적 에러 메시지

### Ruby
- **FormulaEngine 연결 실패**: 대체 분석 로직
- **토큰 부족**: 명확한 에러 메시지
- **파일 처리 오류**: 로깅 및 사용자 알림

## 접근성

- **키보드 탐색**: Tab 키로 모든 요소 접근 가능
- **스크린 리더**: ARIA 레이블 및 롤 적용
- **색상 대비**: WCAG 2.1 AA 기준 준수
- **포커스 표시**: 명확한 포커스 링

## 브라우저 호환성

- **Chrome**: 88+
- **Firefox**: 85+
- **Safari**: 14+
- **Edge**: 88+

## 향후 개선 사항

1. **실시간 분석**: 파일 업로드와 동시에 수식 분석
2. **분석 비교**: 여러 버전 간 수식 변화 비교
3. **수식 편집기**: 웹에서 직접 수식 수정
4. **AI 추천**: 머신러닝 기반 최적화 제안
5. **협업 기능**: 팀원 간 분석 결과 공유
6. **API 확장**: 외부 시스템 연동을 위한 REST API

## 트러블슈팅

### 일반적인 문제

1. **차트가 표시되지 않음**
   - Chart.js 로드 확인
   - 브라우저 콘솔 에러 확인
   - 데이터 형식 검증

2. **분석 결과가 없음**
   - FormulaEngine 서비스 상태 확인
   - 토큰 잔액 확인
   - 파일 형식 호환성 확인

3. **성능 저하**
   - 대용량 파일의 경우 청크 처리
   - 차트 데이터 제한
   - 브라우저 메모리 확인

### 개발자 도구

1. **JavaScript 디버깅**
   ```javascript
   // 분석 데이터 확인
   console.log(controller.analysisDataValue)
   
   // 차트 인스턴스 확인
   console.log(controller.functionChart)
   ```

2. **Rails 로그 확인**
   ```bash
   tail -f log/development.log | grep "FormulaEngine"
   ```

3. **백그라운드 잡 모니터링**
   ```bash
   # Sidekiq Web UI 접근
   bundle exec sidekiq
   ```