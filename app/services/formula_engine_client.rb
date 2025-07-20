# frozen_string_literal: true

# FormulaEngine Node.js 서비스와 통신하는 HTTP 클라이언트
# HyperFormula 기반 수식 분석, 검증, 계산 기능 제공
class FormulaEngineClient
  include ActiveModel::Model

  # FormulaEngine 연결 에러
  class ConnectionError < StandardError; end
  class SessionError < StandardError; end
  class ValidationError < StandardError; end
  class CalculationError < StandardError; end

  MAX_RETRIES = 3
  RETRY_DELAY = 1.0

  attr_reader :config, :base_url, :timeout, :session_id

  def initialize
    @config = load_config
    @base_url = @config["base_url"]
    @timeout = @config["timeout"]
    @open_timeout = @config["open_timeout"]
    @max_retries = @config["max_retries"]
    @retry_delay = @config["retry_delay"]
    @session_id = nil

    validate_configuration
  end

  # === 세션 관리 ===

  # 새 세션 생성
  def create_session
    response = make_request(
      method: :post,
      endpoint: "/sessions",
      timeout: @open_timeout
    )

    if response.success?
      result = response.parsed_response
      @session_id = result["sessionId"]

      Rails.logger.info("FormulaEngine 세션 생성: #{@session_id}")

      Common::Result.success({
        session_id: @session_id,
        message: result["message"]
      })
    else
      handle_api_error(response, "create_session")
    end

  rescue StandardError => e
    Rails.logger.error("FormulaEngine 세션 생성 실패: #{e.message}")
    Common::Result.failure(
      Common::Errors::BusinessError.new(
        message: "세션 생성 실패: #{e.message}",
        code: "FORMULA_ENGINE_SESSION_ERROR"
      )
    )
  end

  # 세션 삭제
  def destroy_session(session_id = @session_id)
    return Common::Result.success unless session_id

    response = make_request(
      method: :delete,
      endpoint: "/sessions/#{session_id}"
    )

    @session_id = nil if session_id == @session_id

    if response.success?
      Rails.logger.info("FormulaEngine 세션 삭제: #{session_id}")
      Common::Result.success(response.parsed_response)
    else
      # 세션 삭제 실패는 warning 레벨로 로깅
      Rails.logger.warn("FormulaEngine 세션 삭제 실패: #{session_id}")
      Common::Result.success # 실패해도 성공으로 처리
    end

  rescue StandardError => e
    Rails.logger.warn("FormulaEngine 세션 삭제 중 오류: #{e.message}")
    Common::Result.success # 실패해도 성공으로 처리
  end

  # === 데이터 로드 ===

  # Excel 데이터 로드
  def load_excel_data(excel_data, session_id = @session_id)
    return session_required_error unless session_id

    response = make_request(
      method: :post,
      endpoint: "/sessions/#{session_id}/load",
      data: { excelData: excel_data }
    )

    if response.success?
      result = response.parsed_response
      Rails.logger.info("FormulaEngine Excel 데이터 로드 완료: #{session_id}")

      Common::Result.success({
        message: result["message"],
        session_id: session_id
      })
    else
      handle_api_error(response, "load_excel_data")
    end

  rescue StandardError => e
    Rails.logger.error("FormulaEngine Excel 데이터 로드 실패: #{e.message}")
    Common::Result.failure(
      Common::Errors::FileProcessingError.new(
        message: "Excel 데이터 로드 실패: #{e.message}",
        details: { session_id: session_id }
      )
    )
  end

  # === 수식 분석 ===

  # 수식 분석 수행
  def analyze_formulas(session_id = @session_id)
    return session_required_error unless session_id

    response = make_request(
      method: :get,
      endpoint: "/sessions/#{session_id}/analyze"
    )

    if response.success?
      result = response.parsed_response

      if result["success"]
        Rails.logger.info("FormulaEngine 수식 분석 완료: #{session_id}")

        Common::Result.success({
          analysis: result["data"],
          session_id: session_id
        })
      else
        Common::Result.failure(
          Common::Errors::BusinessError.new(
            message: result["error"] || "수식 분석 실패",
            code: "FORMULA_ANALYSIS_ERROR"
          )
        )
      end
    else
      handle_api_error(response, "analyze_formulas")
    end

  rescue StandardError => e
    Rails.logger.error("FormulaEngine 수식 분석 실패: #{e.message}")
    Common::Result.failure(
      Common::Errors::BusinessError.new(
        message: "수식 분석 실패: #{e.message}",
        code: "FORMULA_ANALYSIS_ERROR",
        details: { session_id: session_id }
      )
    )
  end

  # === 수식 검증 ===

  # 수식 검증
  def validate_formula(formula, session_id = @session_id)
    return session_required_error unless session_id
    return formula_required_error unless formula.present?

    response = make_request(
      method: :post,
      endpoint: "/sessions/#{session_id}/validate",
      data: { formula: formula }
    )

    if response.success?
      result = response.parsed_response

      if result["success"]
        Common::Result.success({
          valid: result["valid"],
          errors: result["errors"] || [],
          formula: formula,
          session_id: session_id
        })
      else
        Common::Result.failure(
          Common::Errors::ValidationError.new(
            message: result["error"] || "수식 검증 실패",
            details: { formula: formula }
          )
        )
      end
    else
      handle_api_error(response, "validate_formula")
    end

  rescue StandardError => e
    Rails.logger.error("FormulaEngine 수식 검증 실패: #{e.message}")
    Common::Result.failure(
      Common::Errors::ValidationError.new(
        message: "수식 검증 실패: #{e.message}",
        details: { formula: formula, session_id: session_id }
      )
    )
  end

  # === 수식 계산 ===

  # 수식 계산
  def calculate_formula(formula, session_id = @session_id)
    return session_required_error unless session_id
    return formula_required_error unless formula.present?

    response = make_request(
      method: :post,
      endpoint: "/sessions/#{session_id}/calculate",
      data: { formula: formula }
    )

    if response.success?
      result = response.parsed_response

      if result["success"]
        Common::Result.success({
          result: result["result"],
          formula: formula,
          session_id: session_id
        })
      else
        Common::Result.failure(
          Common::Errors::BusinessError.new(
            message: result["error"] || "수식 계산 실패",
            code: "FORMULA_CALCULATION_ERROR",
            details: { formula: formula }
          )
        )
      end
    else
      handle_api_error(response, "calculate_formula")
    end

  rescue StandardError => e
    Rails.logger.error("FormulaEngine 수식 계산 실패: #{e.message}")
    Common::Result.failure(
      Common::Errors::BusinessError.new(
        message: "수식 계산 실패: #{e.message}",
        code: "FORMULA_CALCULATION_ERROR",
        details: { formula: formula, session_id: session_id }
      )
    )
  end

  # === 유틸리티 메소드 ===

  # 지원 함수 목록 조회
  def get_supported_functions
    response = make_request(
      method: :get,
      endpoint: "/functions"
    )

    if response.success?
      result = response.parsed_response

      if result["success"]
        Common::Result.success({
          total: result["total"],
          functions: result["functions"],
          categories: result["categories"]
        })
      else
        Common::Result.failure(
          Common::Errors::BusinessError.new(
            message: result["error"] || "함수 목록 조회 실패",
            code: "FORMULA_FUNCTIONS_ERROR"
          )
        )
      end
    else
      handle_api_error(response, "get_supported_functions")
    end

  rescue StandardError => e
    Rails.logger.error("FormulaEngine 함수 목록 조회 실패: #{e.message}")
    Common::Result.failure(
      Common::Errors::BusinessError.new(
        message: "함수 목록 조회 실패: #{e.message}",
        code: "FORMULA_FUNCTIONS_ERROR"
      )
    )
  end

  # 헬스 체크
  def health_check
    response = make_request(
      method: :get,
      endpoint: "/health",
      timeout: 5 # 헬스 체크는 짧은 타임아웃
    )

    if response.success?
      result = response.parsed_response
      Common::Result.success({
        status: result["status"],
        service: result["service"],
        version: result["version"],
        hyperformula_version: result["hyperformulaVersion"],
        supported_functions: result["supportedFunctions"],
        active_sessions: result["activeSessions"],
        uptime: result["uptime"],
        memory: result["memory"]
      })
    else
      Common::Result.failure(
        Common::Errors::BusinessError.new(
          message: "FormulaEngine 서비스 응답 없음",
          code: "FORMULA_ENGINE_UNHEALTHY"
        )
      )
    end

  rescue StandardError => e
    Rails.logger.error("FormulaEngine 헬스 체크 실패: #{e.message}")
    Common::Result.failure(
      Common::Errors::BusinessError.new(
        message: "FormulaEngine 헬스 체크 실패: #{e.message}",
        code: "FORMULA_ENGINE_UNHEALTHY"
      )
    )
  end

  # === 편의 메소드 ===

  # 자동 세션 관리를 포함한 Excel 분석
  def analyze_excel_with_session(excel_data)
    session_result = create_session
    return session_result if session_result.failure?

    begin
      # Excel 데이터 로드
      load_result = load_excel_data(excel_data)
      return load_result if load_result.failure?

      # 수식 분석 수행
      analyze_result = analyze_formulas
      return analyze_result if analyze_result.failure?

      analyze_result
    ensure
      # 세션 정리
      destroy_session
    end
  end

  # 파일 해시 기반 캐싱을 포함한 Excel 분석
  def analyze_excel_with_cache(file_path, file_hash = nil)
    # 파일 해시 계산 (제공되지 않은 경우)
    file_hash ||= calculate_file_hash(file_path)
    cache_key = "formula_analysis:#{file_hash}"

    # 캐시에서 확인
    cached_result = Rails.cache.read(cache_key)
    if cached_result
      Rails.logger.info("FormulaEngine 캐시 히트: #{cache_key}")
      return Common::Result.success(cached_result.merge(from_cache: true))
    end

    # 캐시 미스 - 실제 분석 수행
    Rails.logger.info("FormulaEngine 캐시 미스: #{cache_key}")

    # Excel 데이터 읽기
    excel_data = read_excel_data(file_path)
    return excel_data if excel_data.failure?

    # 분석 수행
    analysis_result = analyze_excel_with_session(excel_data.value)
    return analysis_result if analysis_result.failure?

    # 결과를 캐시에 저장
    result_data = analysis_result.value
    Rails.cache.write(cache_key, result_data, expires_in: 24.hours)

    Common::Result.success(result_data.merge(from_cache: false))
  rescue StandardError => e
    Rails.logger.error("FormulaEngine 캐시된 분석 실패: #{e.message}")
    Common::Result.failure(
      Common::Errors::BusinessError.new(
        message: "Excel 분석 실패: #{e.message}",
        code: "FORMULA_ANALYSIS_ERROR"
      )
    )
  end

  # 자동 세션 관리를 포함한 수식 검증
  def validate_formula_with_session(formula)
    session_result = create_session
    return session_result if session_result.failure?

    begin
      validate_formula(formula)
    ensure
      destroy_session
    end
  end

  # 자동 세션 관리를 포함한 수식 계산
  def calculate_formula_with_session(formula)
    session_result = create_session
    return session_result if session_result.failure?

    begin
      calculate_formula(formula)
    ensure
      destroy_session
    end
  end

  private

  # 설정 파일 로드
  def load_config
    config_path = Rails.root.join("config", "formula_engine.yml")

    unless File.exist?(config_path)
      raise "FormulaEngine 설정 파일을 찾을 수 없습니다: #{config_path}"
    end

    config_data = YAML.load_file(config_path, aliases: true)
    config_data[Rails.env] || config_data["default"]
  end

  # 설정 검증
  def validate_configuration
    unless @base_url.present?
      raise "FormulaEngine base_url이 설정되지 않았습니다"
    end

    unless @timeout.present? && @timeout.positive?
      raise "FormulaEngine timeout이 올바르지 않습니다"
    end
  end

  # HTTP 요청 수행
  def make_request(method:, endpoint:, data: nil, timeout: @timeout)
    url = "#{@base_url}#{endpoint}"

    headers = {
      "Content-Type" => "application/json",
      "Accept" => "application/json",
      "User-Agent" => "ExcelApp-Rails/1.0"
    }

    options = {
      headers: headers,
      timeout: timeout,
      open_timeout: @open_timeout
    }

    log_request(method, url, data) if log_requests?

    case method
    when :post
      options[:body] = data.to_json if data
      HTTParty.post(url, options)
    when :get
      HTTParty.get(url, options)
    when :delete
      HTTParty.delete(url, options)
    else
      raise ArgumentError, "지원하지 않는 HTTP 메소드: #{method}"
    end
  end

  # API 에러 처리
  def handle_api_error(response, operation)
    error_data = response.parsed_response

    error_message = if error_data.is_a?(Hash)
                      error_data["error"] || error_data["message"] || "FormulaEngine API 오류"
    else
                      "FormulaEngine API 오류"
    end

    Rails.logger.error("FormulaEngine #{operation} 실패: #{error_message} (HTTP #{response.code})")

    Common::Result.failure(
      Common::Errors::BusinessError.new(
        message: error_message,
        code: "FORMULA_ENGINE_API_ERROR",
        details: {
          operation: operation,
          status_code: response.code,
          response_body: error_data
        }
      )
    )
  end

  # 세션 필수 에러
  def session_required_error
    Common::Result.failure(
      Common::Errors::ValidationError.new(
        message: "세션이 필요합니다. create_session을 먼저 호출하세요.",
        details: { required: "session_id" }
      )
    )
  end

  # 수식 필수 에러
  def formula_required_error
    Common::Result.failure(
      Common::Errors::ValidationError.new(
        message: "수식이 필요합니다.",
        details: { required: "formula" }
      )
    )
  end

  # 로깅 설정 확인
  def log_requests?
    @config["log_requests"] == true
  end

  def log_responses?
    @config["log_responses"] == true
  end

  # 요청 로깅
  def log_request(method, url, data)
    Rails.logger.info("FormulaEngine #{method.upcase} #{url}")

    if data && log_responses?
      Rails.logger.debug("FormulaEngine 요청 데이터: #{data.inspect}")
    end
  end

  # 파일 해시 계산
  def calculate_file_hash(file_path)
    Digest::SHA256.file(file_path).hexdigest
  rescue StandardError => e
    Rails.logger.error("파일 해시 계산 실패: #{e.message}")
    # 실패 시 타임스탬프 기반 해시 사용
    Digest::SHA256.hexdigest("#{file_path}:#{Time.current.to_i}")
  end

  # Excel 데이터 읽기 (Roo 사용)
  def read_excel_data(file_path)
    excel = Roo::Spreadsheet.open(file_path)

    # 모든 시트 데이터를 HyperFormula 형식으로 변환
    sheets_data = {}
    excel.sheets.each do |sheet_name|
      excel.default_sheet = sheet_name

      # 2D 배열로 변환
      data = []
      (excel.first_row..excel.last_row).each do |row|
        row_data = []
        (excel.first_column..excel.last_column).each do |col|
          cell_value = excel.cell(row, col)
          row_data << cell_value
        end
        data << row_data
      end

      sheets_data[sheet_name] = data
    end

    Common::Result.success({ sheets: sheets_data })
  rescue StandardError => e
    Rails.logger.error("Excel 파일 읽기 실패: #{e.message}")
    Common::Result.failure(
      Common::Errors::FileProcessingError.new(
        message: "Excel 파일 읽기 실패: #{e.message}",
        details: { file_path: file_path }
      )
    )
  end

  # === 클래스 메소드 ===

  # 싱글톤 인스턴스
  def self.instance
    @instance ||= new
  end

  # 헬스 체크 (클래스 메소드)
  def self.health_check
    instance.health_check
  end

  # 지원 함수 목록 (클래스 메소드)
  def self.supported_functions
    instance.get_supported_functions
  end

  # Excel 분석 (클래스 메소드)
  def self.analyze_excel(excel_data)
    instance.analyze_excel_with_session(excel_data)
  end

  # 캐시된 Excel 분석 (클래스 메소드)
  def self.analyze_excel_file(file_path, file_hash = nil)
    instance.analyze_excel_with_cache(file_path, file_hash)
  end

  # 수식 검증 (클래스 메소드)
  def self.validate_formula(formula)
    instance.validate_formula_with_session(formula)
  end

  # 수식 계산 (클래스 메소드)
  def self.calculate_formula(formula)
    instance.calculate_formula_with_session(formula)
  end
end
