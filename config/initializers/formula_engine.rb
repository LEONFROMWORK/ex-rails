# frozen_string_literal: true

# FormulaEngine 서비스 설정 초기화
Rails.application.configure do
  # FormulaEngine 설정 로드
  formula_engine_config_path = Rails.root.join("config", "formula_engine.yml")

  if File.exist?(formula_engine_config_path)
    begin
      formula_engine_config = YAML.load_file(formula_engine_config_path, aliases: true)
      config.formula_engine = formula_engine_config[Rails.env] || formula_engine_config["default"]

      Rails.logger.info "FormulaEngine 설정 로드 완료: #{config.formula_engine['base_url']}"
    rescue StandardError => e
      Rails.logger.error "FormulaEngine 설정 로드 실패: #{e.message}"
      # 기본 설정으로 대체
      config.formula_engine = {
        "base_url" => ENV["FORMULA_ENGINE_URL"] || "http://localhost:3002",
        "timeout" => 30,
        "open_timeout" => 10,
        "max_retries" => 3,
        "retry_delay" => 1.0,
        "log_requests" => true,
        "log_responses" => false
      }
    end
  else
    Rails.logger.warn "FormulaEngine 설정 파일을 찾을 수 없습니다: #{formula_engine_config_path}"
    # 기본 설정 사용
    config.formula_engine = {
      "base_url" => ENV["FORMULA_ENGINE_URL"] || "http://localhost:3002",
      "timeout" => 30,
      "open_timeout" => 10,
      "max_retries" => 3,
      "retry_delay" => 1.0,
      "log_requests" => true,
      "log_responses" => false
    }
  end
end

# FormulaEngine 헬스 체크 (개발 환경에서만)
if Rails.env.development?
  Rails.application.config.after_initialize do
    begin
      # 서버 시작 후 FormulaEngine 연결 확인
      Rails.logger.info "FormulaEngine 연결 확인 중..."

      # 간단한 헬스 체크 수행 (비동기)
      Thread.new do
        sleep 2 # Rails 서버 완전 시작 대기

        begin
          result = FormulaEngineClient.health_check
          if result.success?
            health_data = result.value
            Rails.logger.info "✅ FormulaEngine 연결 성공"
            Rails.logger.info "   - 서비스: #{health_data[:service]} v#{health_data[:version]}"
            Rails.logger.info "   - HyperFormula: v#{health_data[:hyperformula_version]}"
            Rails.logger.info "   - 지원 함수: #{health_data[:supported_functions]}개"
            Rails.logger.info "   - 활성 세션: #{health_data[:active_sessions]}개"
          else
            Rails.logger.warn "⚠️  FormulaEngine 연결 실패: #{result.error.message}"
          end
        rescue StandardError => e
          Rails.logger.warn "⚠️  FormulaEngine 연결 확인 중 오류: #{e.message}"
        end
      end
    rescue StandardError => e
      Rails.logger.error "FormulaEngine 초기화 중 오류: #{e.message}"
    end
  end
end
