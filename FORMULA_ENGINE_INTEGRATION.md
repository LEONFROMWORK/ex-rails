# FormulaEngine Integration Guide

ExcelApp-Rails 시스템에 FormulaEngine Node.js 서비스와의 통신을 위한 HTTP 클라이언트가 구현되었습니다.

## 구현된 컴포넌트

### 1. 설정 파일
- **config/formula_engine.yml**: 환경별 FormulaEngine 서비스 설정
- **config/initializers/formula_engine.rb**: Rails 설정 초기화

### 2. 핵심 서비스
- **app/services/formula_engine_client.rb**: FormulaEngine API와 통신하는 HTTP 클라이언트
- **app/common/errors.rb**: FormulaEngine 관련 에러 클래스 추가

### 3. 헬퍼 모듈
- **app/helpers/formula_engine_helper.rb**: Rails 컨트롤러/모델에서 사용할 수 있는 편의 메소드

### 4. 테스트
- **spec/services/formula_engine_client_spec.rb**: RSpec 테스트 스위트

## 사용 방법

### 기본 사용법

#### 1. 헬스 체크
```ruby
# 컨트롤러에서
def check_formula_engine
  health = check_formula_engine_health
  
  if health[:success]
    render json: { status: 'healthy', data: health }
  else
    render json: { status: 'unhealthy', error: health[:message] }
  end
end
```

#### 2. 수식 검증
```ruby
# 컨트롤러에서
def validate_formula
  formula = params[:formula]
  result = validate_excel_formula(formula)
  
  render json: result
end

# 모델에서
class ExcelFile < ApplicationRecord
  def validate_all_formulas
    formulas = extract_formulas_from_file # 사용자 구현 필요
    validate_multiple_formulas(formulas)
  end
end
```

#### 3. Excel 파일 분석
```ruby
# 컨트롤러에서
def analyze_excel
  file_path = params[:file_path]
  analysis = analyze_excel_file_with_formula_engine(file_path)
  
  if analysis[:success]
    render json: { analysis: analysis[:data] }
  else
    render json: { error: analysis[:message] }
  end
end

# 모델에서
class ExcelFile < ApplicationRecord
  def perform_advanced_analysis
    return unless file_path.present?
    
    analysis = analyze_excel_file_with_formula_engine(file_path)
    
    if analysis[:success]
      update(
        analysis_data: analysis[:data],
        analysis_completed_at: Time.current
      )
    end
    
    analysis
  end
end
```

### 고급 사용법

#### 1. 직접 클라이언트 사용
```ruby
# 세션 관리가 필요한 경우
client = FormulaEngineClient.new

# 세션 생성
session_result = client.create_session
return unless session_result.success?

begin
  # Excel 데이터 로드
  excel_data = [['A1', 'B1'], ['=SUM(A1:A1)', '=B1*2']]
  load_result = client.load_excel_data(excel_data)
  
  # 분석 수행
  analysis_result = client.analyze_formulas
  
  # 결과 처리
  puts analysis_result.value[:analysis] if analysis_result.success?
ensure
  # 세션 정리
  client.destroy_session
end
```

#### 2. 클래스 메소드 사용 (자동 세션 관리)
```ruby
# 간단한 수식 검증
result = FormulaEngineClient.validate_formula('=SUM(A1:A10)')

# Excel 분석
excel_data = extract_excel_data_somehow
result = FormulaEngineClient.analyze_excel(excel_data)
```

### 실제 사용 사례

#### Excel 업로드 컨트롤러에서 활용
```ruby
class ExcelFilesController < ApplicationController
  def create
    @excel_file = ExcelFile.new(excel_file_params)
    
    if @excel_file.save
      # 기본 분석
      basic_analysis = perform_basic_analysis(@excel_file.file_path)
      
      # FormulaEngine 고급 분석
      advanced_analysis = analyze_excel_file_with_formula_engine(@excel_file.file_path)
      
      if advanced_analysis[:success]
        @excel_file.update(
          formula_count: advanced_analysis[:data][:advanced_analysis]['totalFormulas'],
          complexity_score: calculate_complexity_score(advanced_analysis[:data]),
          analysis_data: advanced_analysis[:data]
        )
        
        render json: { 
          success: true, 
          file: @excel_file,
          analysis: advanced_analysis[:data]
        }
      else
        render json: { 
          success: false, 
          error: advanced_analysis[:message] 
        }
      end
    else
      render json: { 
        success: false, 
        errors: @excel_file.errors 
      }
    end
  end
  
  private
  
  def calculate_complexity_score(analysis_data)
    advanced = analysis_data[:advanced_analysis]
    total_formulas = advanced['totalFormulas'] || 0
    function_diversity = advanced['functions']&.keys&.size || 0
    
    # 간단한 복잡도 점수 계산
    (total_formulas * 0.1 + function_diversity * 2).round(2)
  end
end
```

#### 분석 작업(Job)에서 활용
```ruby
class AdvancedExcelAnalysisJob < ApplicationJob
  queue_as :default
  
  def perform(excel_file_id)
    excel_file = ExcelFile.find(excel_file_id)
    
    # FormulaEngine으로 고급 분석 수행
    analysis = analyze_excel_file_with_formula_engine(excel_file.file_path)
    
    if analysis[:success]
      # 분석 결과 저장
      excel_file.update!(
        advanced_analysis_data: analysis[:data],
        advanced_analysis_completed_at: Time.current
      )
      
      # 복잡도 분석
      complexity = analyze_formula_complexity(excel_file.file_path)
      if complexity[:success]
        excel_file.update!(complexity_analysis: complexity)
      end
      
      # 함수 사용 분석
      function_usage = analyze_function_usage(excel_file.file_path)
      if function_usage[:success]
        excel_file.update!(function_usage_analysis: function_usage)
      end
      
      Rails.logger.info "Excel 고급 분석 완료: #{excel_file.id}"
    else
      Rails.logger.error "Excel 고급 분석 실패: #{analysis[:message]}"
    end
  end
end
```

## 환경 설정

### 환경 변수
```bash
# FormulaEngine 서비스 URL (기본값: http://localhost:3002)
FORMULA_ENGINE_URL=http://localhost:3002
```

### 개발 환경에서 FormulaEngine 시작
```bash
# FormulaEngine 서비스 디렉토리로 이동
cd formula_service

# 의존성 설치 (최초 한 번)
npm install

# 서비스 시작
npm start
# 또는
node index.js
```

### Rails 서버 시작
```bash
# Rails 애플리케이션 루트에서
bundle exec rails server

# 로그에서 FormulaEngine 연결 상태 확인
# ✅ FormulaEngine 연결 성공
# ⚠️  FormulaEngine 연결 실패: ... (연결 실패 시)
```

## 에러 처리

구현된 에러 클래스들:
- `Common::Errors::FormulaEngineError`: 일반적인 FormulaEngine 에러
- `Common::Errors::FormulaValidationError`: 수식 검증 에러
- `Common::Errors::FormulaCalculationError`: 수식 계산 에러

모든 헬퍼 메소드는 일관된 형식으로 결과를 반환합니다:
```ruby
{
  success: true/false,
  data: {...},      # 성공 시 데이터
  message: "...",   # 상태 메시지
  error_code: "..." # 실패 시 에러 코드 (선택적)
}
```

## 성능 고려사항

1. **세션 관리**: 자동 세션 관리 메소드(`*_with_session`)는 편리하지만 매번 새 세션을 생성합니다.
2. **대용량 파일**: 큰 Excel 파일의 경우 백그라운드 작업으로 처리를 권장합니다.
3. **타임아웃**: 복잡한 분석의 경우 설정에서 타임아웃을 조정할 수 있습니다.

## 모니터링

FormulaEngine 서비스 상태는 다음 방법으로 모니터링할 수 있습니다:

```ruby
# 헬스 체크
health = check_formula_engine_health
puts health[:message]

# 지원 함수 확인
functions = get_formula_engine_functions
puts "지원 함수: #{functions[:total]}개"
```

이 통합을 통해 Rails 애플리케이션에서 고급 Excel 수식 분석, 검증, 계산 기능을 활용할 수 있습니다.