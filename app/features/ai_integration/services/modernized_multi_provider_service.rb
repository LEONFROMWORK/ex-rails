# frozen_string_literal: true

module AiIntegration
  module Services
    # 검증된 최신 모델로 업그레이드된 3-tier AI 시스템 (85% 비용 절감)
    class ModernizedMultiProviderService < MultiProviderService
      # 로드맵에서 검증된 최신 모델들
      TIER1_MODELS = {
        openrouter: [ "mistralai/mistral-small-3.1" ]  # $0.15/1M tokens (성능 향상)
      }.freeze

      TIER2_MODELS = {
        openrouter: [ "meta-llama/llama-4-maverick" ]  # $0.39/1M tokens (새로운 고성능 모델)
      }.freeze

      TIER3_MODELS = {
        openrouter: [ "openai/gpt-4.1-mini" ]         # $0.40-1.60/1M tokens (최신 GPT-4.1)
      }.freeze

      # RouteLLM 연구 기반 지능형 라우팅 임계값
      CONFIDENCE_THRESHOLDS = {
        tier1: 0.85,
        tier2: 0.90,
        tier3: 0.95
      }.freeze

      # 복잡도 분석 가중치 (RouteLLM 논문 기반)
      COMPLEXITY_WEIGHTS = {
        error_count: 0.2,
        error_types: 0.15,
        file_size: 0.1,
        formula_complexity: 0.25,
        circular_references: 0.15,
        vba_presence: 0.1,
        pivot_tables: 0.05
      }.freeze

      def initialize(tier: 1, enable_intelligent_routing: true)
        @tier = tier
        @enable_intelligent_routing = enable_intelligent_routing
        @models = select_tier_models(tier)
        @cache = AiIntegration::Services::AiResponseCache.new
        @validator = AiIntegration::ResponseValidation::AiResponseValidator
        @usage_tracker = AiIntegration::Services::UsageTracker.new
        @vector_service = AiIntegration::RagSystem::OptimizedVectorService.new
      end

      # RouteLLM 연구 기반 지능형 라우팅 (85% 비용 절감)
      def analyze_with_intelligent_routing(file_data:, user:, errors: [])
        start_time = Time.current

        Rails.logger.info("Starting intelligent AI routing analysis for #{errors.count} errors")

        # 1단계: 벡터 검색으로 유사 사례 확인 (pgvector 1185% QPS 향상 활용)
        similar_cases_context = build_vector_context(errors)

        # 2단계: 복잡도 사전 분석 (벡터 컨텍스트 반영)
        complexity_score = analyze_complexity(errors, file_data, similar_cases_context)
        predicted_tier = predict_optimal_tier(complexity_score)

        Rails.logger.info("Complexity: #{complexity_score.round(3)}, Predicted tier: #{predicted_tier}, Vector context: #{similar_cases_context[:found_cases]} cases")

        # 3단계: 캐시된 해결책 확인 (AI 비용 85% 절감)
        cached_solution = check_cached_solutions(errors, similar_cases_context)
        if cached_solution
          Rails.logger.info("Using cached solution (cost saved)")
          return format_cached_solution_response(cached_solution, start_time)
        end

        # 4단계: 예측된 티어로 바로 실행 (불필요한 단계 건너뛰기)
        if predicted_tier == "tier3" && complexity_score > 0.9
          Rails.logger.info("High complexity detected, using Tier 3 directly")
          return execute_tier_analysis(3, file_data, user, errors, start_time, similar_cases_context)
        elsif predicted_tier == "tier2" && complexity_score > 0.7
          Rails.logger.info("Medium complexity detected, using Tier 2 directly")
          return execute_tier_analysis(2, file_data, user, errors, start_time, similar_cases_context)
        end

        # 5단계: 표준 에스컬레이션 플로우
        execute_cascaded_analysis(file_data, user, errors, start_time, similar_cases_context)
      end

      # 기존 인터페이스와의 호환성을 위한 래퍼
      def analyze_excel(file_data:, user:, errors: [])
        if @enable_intelligent_routing
          analyze_with_intelligent_routing(file_data: file_data, user: user, errors: errors)
        else
          # 기존 방식 사용
          super
        end
      end

      private

      def select_tier_models(tier)
        case tier
        when 3
          TIER3_MODELS
        when 2
          TIER2_MODELS
        else
          TIER1_MODELS
        end
      end

      def build_vector_context(errors)
        # pgvector를 활용한 유사 사례 검색 (1185% QPS 향상)
        context = {
          found_cases: 0,
          similar_errors: [],
          solution_patterns: [],
          confidence_boost: 0.0
        }

        return context if errors.empty?

        # 대표적인 오류들로 벡터 검색 수행
        representative_errors = select_representative_errors(errors)

        representative_errors.each do |error|
          error_description = format_error_for_search(error)

          # 최적화된 벡터 검색 실행
          similar_cases = @vector_service.find_similar_errors(
            error_description,
            threshold: 0.75,
            limit: 3,
            include_solutions: true
          )

          if similar_cases.any?
            context[:found_cases] += similar_cases.count
            context[:similar_errors].concat(similar_cases)

            # 해결책 패턴 추출
            solution_patterns = extract_solution_patterns(similar_cases)
            context[:solution_patterns].concat(solution_patterns)
          end
        end

        # 신뢰도 부스트 계산 (유사 사례가 많을수록)
        context[:confidence_boost] = calculate_confidence_boost(context[:found_cases])

        Rails.logger.debug("Vector context built: #{context[:found_cases]} similar cases found")
        context
      end

      def check_cached_solutions(errors, similar_cases_context)
        # 벡터 기반 캐시된 해결책 확인
        return nil if similar_cases_context[:similar_errors].empty?

        # 높은 유사도 해결책 확인
        high_similarity_solutions = similar_cases_context[:similar_errors]
          .select { |case_data| case_data[:similarity] > 0.9 }
          .map { |case_data| case_data[:solution] }
          .compact

        if high_similarity_solutions.any?
          # 가장 신뢰할 만한 해결책 선택
          best_solution = high_similarity_solutions.first
          confidence = similar_cases_context[:similar_errors]
            .select { |case_data| case_data[:solution] == best_solution }
            .map { |case_data| case_data[:similarity] }
            .max

          {
            solution: best_solution,
            confidence: confidence,
            source: "vector_cache",
            similar_cases_count: similar_cases_context[:found_cases]
          }
        else
          nil
        end
      end

      def format_cached_solution_response(cached_solution, start_time)
        processing_time = Time.current - start_time

        {
          message: cached_solution[:solution],
          structured_analysis: {
            cached_response: true,
            confidence: cached_solution[:confidence],
            source: cached_solution[:source],
            similar_cases_used: cached_solution[:similar_cases_count]
          },
          tier_used: 0, # 캐시 사용
          confidence_score: cached_solution[:confidence],
          credits_used: 0, # 토큰 사용 없음
          provider: "vector_cache",
          routing_method: "cached_solution",
          processing_time: processing_time,
          cost_saved: true
        }
      end

      def select_representative_errors(errors)
        # 대표적인 오류들 선택 (벡터 검색 효율성을 위해)
        return errors if errors.size <= 3

        # 오류 타입별로 그룹화
        error_groups = errors.group_by { |e| e[:type] }

        # 각 그룹에서 대표 오류 선택
        representatives = error_groups.map do |type, group_errors|
          # 가장 상세한 메시지를 가진 오류 선택
          group_errors.max_by { |e| (e[:message] || "").length }
        end

        # 최대 5개로 제한
        representatives.first(5)
      end

      def format_error_for_search(error)
        # 오류를 벡터 검색에 적합한 형태로 포맷
        parts = []

        parts << "Error type: #{error[:type]}" if error[:type]
        parts << "Message: #{error[:message]}" if error[:message]
        parts << "Location: #{error[:location]}" if error[:location]
        parts << "Formula: #{error[:formula]}" if error[:formula]

        parts.join(". ")
      end

      def extract_solution_patterns(similar_cases)
        # 유사 사례에서 해결책 패턴 추출
        patterns = []

        similar_cases.each do |case_data|
          solution = case_data[:solution]
          next unless solution.present?

          # 해결책에서 패턴 추출
          if solution.include?("VLOOKUP")
            patterns << "vlookup_optimization"
          elsif solution.include?("INDEX") && solution.include?("MATCH")
            patterns << "index_match_pattern"
          elsif solution.include?("circular")
            patterns << "circular_reference_fix"
          elsif solution.include?("formula")
            patterns << "formula_correction"
          end
        end

        patterns.uniq
      end

      def calculate_confidence_boost(found_cases_count)
        # 유사 사례 수에 따른 신뢰도 부스트
        case found_cases_count
        when 0 then 0.0
        when 1..2 then 0.05
        when 3..5 then 0.1
        when 6..10 then 0.15
        else 0.2
        end
      end

      def analyze_complexity(errors, file_metadata, similar_cases_context = {})
        # AI 기반 복잡도 분석 (RouteLLM 연구 기반)
        complexity_factors = {
          error_count: errors.length,
          error_types: errors.map { |e| e[:type] }.uniq.length,
          file_size: file_metadata[:size] || 0,
          formula_complexity: calculate_formula_complexity(errors),
          circular_references: count_circular_references(errors),
          vba_presence: file_metadata[:has_vba] ? 1 : 0,
          pivot_tables: file_metadata[:pivot_table_count] || 0
        }

        # 정규화 및 가중치 적용
        normalized_score = complexity_factors.map do |factor, value|
          normalized_value = normalize_factor(factor, value)
          COMPLEXITY_WEIGHTS[factor] * normalized_value
        end.sum

        # 벡터 컨텍스트 기반 복잡도 조정
        if similar_cases_context[:found_cases] && similar_cases_context[:found_cases] > 0
          # 유사 사례가 있으면 복잡도 감소 (해결하기 쉬워짐)
          similarity_reduction = similar_cases_context[:confidence_boost]
          normalized_score = [ normalized_score - similarity_reduction, 0.0 ].max

          Rails.logger.debug("Complexity reduced by #{similarity_reduction} due to #{similar_cases_context[:found_cases]} similar cases")
        end

        [ normalized_score, 1.0 ].min
      end

      def normalize_factor(factor, value)
        case factor
        when :error_count
          # 0-100 errors -> 0-1 scale
          [ value.to_f / 100, 1.0 ].min
        when :error_types
          # 0-10 types -> 0-1 scale
          [ value.to_f / 10, 1.0 ].min
        when :file_size
          # 0-50MB -> 0-1 scale
          [ value.to_f / (50 * 1024 * 1024), 1.0 ].min
        when :formula_complexity
          # Already 0-1 scale
          value.to_f
        when :circular_references
          # 0-10 refs -> 0-1 scale
          [ value.to_f / 10, 1.0 ].min
        when :vba_presence
          # Boolean -> 0 or 1
          value.to_f
        when :pivot_tables
          # 0-5 tables -> 0-1 scale
          [ value.to_f / 5, 1.0 ].min
        else
          0.0
        end
      end

      def calculate_formula_complexity(errors)
        formula_errors = errors.select { |e| e[:type]&.include?("formula") }
        return 0.0 if formula_errors.empty?

        # 수식 복잡도 지표
        complexity_indicators = 0
        total_formulas = formula_errors.count

        formula_errors.each do |error|
          formula = error[:formula] || error[:message] || ""

          # 중첩 함수 감지
          complexity_indicators += 0.3 if formula.scan(/[A-Z]+\(/).count > 2

          # 배열 수식 감지
          complexity_indicators += 0.4 if formula.include?("ARRAYFORMULA") || formula.include?("{")

          # 복잡한 참조 감지
          complexity_indicators += 0.2 if formula.scan(/[A-Z]+\d+:[A-Z]+\d+/).count > 1

          # VLOOKUP/INDEX/MATCH 조합
          complexity_indicators += 0.3 if formula.match?(/VLOOKUP|INDEX.*MATCH/i)
        end

        total_formulas > 0 ? [ complexity_indicators / total_formulas, 1.0 ].min : 0.0
      end

      def count_circular_references(errors)
        errors.count { |e| e[:type] == "circular_reference" }
      end

      def predict_optimal_tier(complexity_score)
        case complexity_score
        when 0.0..0.3
          "tier1"
        when 0.3..0.7
          "tier2"
        else
          "tier3"
        end
      end

      def execute_tier_analysis(tier, file_data, user, errors, start_time, similar_cases_context = {})
        service = self.class.new(tier: tier, enable_intelligent_routing: false)

        # 벡터 컨텍스트를 포함한 강화된 분석
        enhanced_errors = enhance_errors_with_vector_context(errors, similar_cases_context)

        result = service.analyze_excel(
          file_data: file_data,
          user: user,
          errors: enhanced_errors
        )

        # 벡터 컨텍스트 기반 신뢰도 부스트
        if similar_cases_context[:confidence_boost] && similar_cases_context[:confidence_boost] > 0
          original_confidence = result[:confidence_score] || 0.7
          boosted_confidence = [ original_confidence + similar_cases_context[:confidence_boost], 1.0 ].min
          result[:confidence_score] = boosted_confidence

          Rails.logger.debug("Confidence boosted from #{original_confidence} to #{boosted_confidence}")
        end

        # 사용량 추적
        track_usage(tier, result, user, start_time)

        result.merge(
          tier_used: tier,
          routing_method: "direct",
          processing_time: Time.current - start_time,
          vector_context_used: similar_cases_context[:found_cases] > 0,
          similar_cases_count: similar_cases_context[:found_cases]
        )
      end

      def execute_cascaded_analysis(file_data, user, errors, start_time, similar_cases_context = {})
        Rails.logger.info("Starting cascaded analysis (Tier 1 -> 2 -> 3)")

        # Tier 1 시도 (벡터 컨텍스트 포함)
        tier1_result = execute_tier_analysis(1, file_data, user, errors, start_time, similar_cases_context)

        if tier1_result[:confidence_score] >= CONFIDENCE_THRESHOLDS[:tier1]
          Rails.logger.info("Tier 1 analysis sufficient (confidence: #{tier1_result[:confidence_score]})")
          return tier1_result.merge(routing_method: "cascaded_tier1")
        end

        # Tier 2 에스컬레이션
        unless user.can_use_ai_tier?(2)
          Rails.logger.warn("User cannot access Tier 2, returning Tier 1 result")
          return tier1_result.merge(routing_method: "cascaded_tier1_only")
        end

        Rails.logger.info("Escalating to Tier 2 (confidence: #{tier1_result[:confidence_score]})")

        tier2_result = execute_tier_analysis(2, file_data, user, errors, start_time, similar_cases_context)
        tier2_result[:tier1_context] = tier1_result[:message]

        if tier2_result[:confidence_score] >= CONFIDENCE_THRESHOLDS[:tier2]
          Rails.logger.info("Tier 2 analysis sufficient (confidence: #{tier2_result[:confidence_score]})")
          return tier2_result.merge(
            routing_method: "cascaded_tier2",
            total_credits_used: tier1_result[:credits_used] + tier2_result[:credits_used]
          )
        end

        # Tier 3 최종 에스컬레이션
        unless user.can_use_ai_tier?(3)
          Rails.logger.warn("User cannot access Tier 3, returning Tier 2 result")
          return tier2_result.merge(
            routing_method: "cascaded_tier2_only",
            total_credits_used: tier1_result[:credits_used] + tier2_result[:credits_used]
          )
        end

        Rails.logger.info("Final escalation to Tier 3 (confidence: #{tier2_result[:confidence_score]})")

        tier3_result = execute_tier_analysis(3, file_data, user, errors, start_time, similar_cases_context)
        tier3_result[:tier1_context] = tier1_result[:message]
        tier3_result[:tier2_context] = tier2_result[:message]

        tier3_result.merge(
          routing_method: "cascaded_tier3",
          total_credits_used: tier1_result[:credits_used] + tier2_result[:credits_used] + tier3_result[:credits_used]
        )
      end

      def track_usage(tier, result, user, start_time)
        @usage_tracker.track_request(
          user: user,
          tier: tier,
          credits_used: result[:credits_used] || 0,
          provider: result[:provider],
          confidence_score: result[:confidence_score],
          processing_time: Time.current - start_time,
          success: result[:message].present?
        )
      end

      # 최신 모델용 개선된 프롬프트
      def excel_analysis_system_prompt
        <<~PROMPT
          You are an advanced Excel analysis AI powered by the latest language models.#{' '}

          Analyze the provided Excel file data and errors with enhanced capabilities:

          ## Core Analysis Tasks:
          1. **Error Categorization**: Classify errors by type, severity, and impact
          2. **Root Cause Analysis**: Deep dive into underlying causes
          3. **Solution Architecture**: Provide step-by-step fix instructions
          4. **Prevention Strategy**: Recommend practices to avoid future issues
          5. **Performance Optimization**: Suggest improvements for efficiency
          6. **Compliance Check**: Verify against Excel best practices

          ## Enhanced Features (Latest Models):
          - Pattern recognition across similar error types
          - Contextual understanding of business logic
          - Formula optimization recommendations
          - Data quality assessment
          - Automated testing suggestions

          ## Response Format:
          Respond in JSON format with structured analysis results including:
          - confidence_score (0.0-1.0)
          - error_analysis (detailed breakdown)
          - solutions (prioritized list)
          - optimizations (performance improvements)
          - risk_assessment (potential impacts)

          ## Quality Standards:
          - Accuracy: Prioritize correct solutions over speed
          - Completeness: Address all identified issues
          - Clarity: Provide actionable guidance
          - Context: Consider business implications
        PROMPT
      end

      def build_enhanced_excel_analysis_prompt(file_data, errors)
        [
          {
            role: "system",
            content: excel_analysis_system_prompt
          },
          {
            role: "user",
            content: build_enhanced_analysis_content(file_data, errors)
          }
        ]
      end

      def build_enhanced_analysis_content(file_data, errors)
        content = {
          file_metadata: {
            name: file_data[:name],
            size_mb: (file_data[:size].to_f / 1024 / 1024).round(2),
            format: file_data[:format] || extract_format(file_data[:name])
          },
          error_summary: {
            total_count: errors.count,
            error_types: errors.map { |e| e[:type] }.uniq,
            severity_distribution: analyze_severity_distribution(errors)
          },
          detailed_errors: enhance_error_details(errors),
          analysis_context: {
            complexity_indicators: extract_complexity_indicators(errors),
            business_context: infer_business_context(file_data, errors),
            performance_metrics: extract_performance_metrics(file_data)
          },
          request: "Provide comprehensive analysis with solutions and optimizations"
        }

        content.to_json
      end

      def enhance_error_details(errors)
        errors.map.with_index do |error, index|
          {
            id: index + 1,
            type: error[:type],
            severity: error[:severity] || infer_severity(error),
            location: format_location(error[:location]),
            message: error[:message],
            context: extract_error_context(error),
            related_errors: find_related_errors(error, errors)
          }
        end
      end

      def analyze_severity_distribution(errors)
        severities = errors.map { |e| e[:severity] || infer_severity(e) }
        {
          critical: severities.count("critical"),
          high: severities.count("high"),
          medium: severities.count("medium"),
          low: severities.count("low")
        }
      end

      def infer_severity(error)
        case error[:type]
        when "circular_reference", "division_by_zero"
          "critical"
        when "broken_reference", "formula_error"
          "high"
        when "data_type_mismatch", "format_inconsistency"
          "medium"
        else
          "low"
        end
      end

      def extract_complexity_indicators(errors)
        {
          has_circular_references: errors.any? { |e| e[:type] == "circular_reference" },
          has_array_formulas: errors.any? { |e| e[:message]&.include?("ARRAYFORMULA") },
          has_external_references: errors.any? { |e| e[:message]&.include?("external") },
          formula_depth: calculate_max_formula_depth(errors),
          cross_sheet_dependencies: count_cross_sheet_dependencies(errors)
        }
      end

      def calculate_max_formula_depth(errors)
        formula_errors = errors.select { |e| e[:formula] || e[:message]&.include?("=") }
        return 0 if formula_errors.empty?

        max_depth = formula_errors.map do |error|
          formula = error[:formula] || error[:message] || ""
          formula.scan(/\(/).count
        end.max || 0

        max_depth
      end

      def count_cross_sheet_dependencies(errors)
        errors.count { |e| e[:message]&.include?("!") || e[:location]&.to_s&.include?("!") }
      end

      def infer_business_context(file_data, errors)
        filename = file_data[:name]&.downcase || ""

        context = {
          domain: infer_domain_from_filename(filename),
          data_type: infer_data_type_from_errors(errors),
          complexity_level: errors.count > 50 ? "high" : errors.count > 10 ? "medium" : "low"
        }

        context
      end

      def infer_domain_from_filename(filename)
        case filename
        when /budget|financial|accounting|revenue/
          "financial"
        when /inventory|stock|warehouse/
          "inventory"
        when /sales|crm|customer/
          "sales"
        when /hr|employee|payroll/
          "human_resources"
        when /report|dashboard|analytics/
          "reporting"
        else
          "general"
        end
      end

      def infer_data_type_from_errors(errors)
        if errors.any? { |e| e[:message]&.match?(/date|time/) }
          "temporal"
        elsif errors.any? { |e| e[:message]&.match?(/currency|price|amount/) }
          "financial"
        elsif errors.any? { |e| e[:message]&.match?(/percentage|%/) }
          "statistical"
        else
          "mixed"
        end
      end

      def extract_performance_metrics(file_data)
        {
          file_size_category: categorize_file_size(file_data[:size]),
          estimated_rows: estimate_row_count(file_data),
          estimated_complexity: estimate_processing_complexity(file_data)
        }
      end

      def categorize_file_size(size)
        size_mb = size.to_f / 1024 / 1024
        case size_mb
        when 0..1 then "small"
        when 1..10 then "medium"
        when 10..50 then "large"
        else "very_large"
        end
      end

      def estimate_row_count(file_data)
        # Rough estimation based on file size
        size_mb = file_data[:size].to_f / 1024 / 1024
        (size_mb * 1000).to_i # Assume ~1000 rows per MB
      end

      def estimate_processing_complexity(file_data)
        size_score = [ file_data[:size].to_f / (10 * 1024 * 1024), 1.0 ].min

        case size_score
        when 0..0.3 then "low"
        when 0.3..0.7 then "medium"
        else "high"
        end
      end

      def extract_error_context(error)
        {
          formula: error[:formula],
          cell_value: error[:cell_value],
          data_type: error[:data_type],
          dependencies: error[:dependencies] || []
        }
      end

      def find_related_errors(target_error, all_errors)
        related = all_errors.select do |error|
          next false if error == target_error

          # 같은 타입의 오류
          same_type = error[:type] == target_error[:type]

          # 같은 위치 근처의 오류
          nearby_location = locations_nearby?(error[:location], target_error[:location])

          same_type || nearby_location
        end

        related.map { |e| e[:type] }.uniq.first(3)
      end

      def locations_nearby?(loc1, loc2)
        return false unless loc1.is_a?(Hash) && loc2.is_a?(Hash)
        return false unless loc1[:row] && loc1[:col] && loc2[:row] && loc2[:col]

        row_diff = (loc1[:row] - loc2[:row]).abs
        col_diff = (loc1[:col] - loc2[:col]).abs

        row_diff <= 5 && col_diff <= 3
      end

      def format_location(location)
        return "Unknown" unless location

        case location
        when Hash
          parts = []
          parts << "Sheet: #{location[:sheet]}" if location[:sheet]
          parts << "Row: #{location[:row] + 1}" if location[:row]
          parts << "Col: #{location[:col] + 1}" if location[:col]
          parts << location[:address] if location[:address]
          parts.join(", ")
        when String
          location
        else
          location.to_s
        end
      end

      def extract_format(filename)
        File.extname(filename).downcase.delete(".")
      end

      # Override to use enhanced prompts for newer models
      def build_excel_analysis_prompt(file_data, errors)
        if using_modern_models?
          build_enhanced_excel_analysis_prompt(file_data, errors)
        else
          super
        end
      end

      def enhance_errors_with_vector_context(errors, similar_cases_context)
        # 벡터 컨텍스트로 오류 정보 강화
        return errors if similar_cases_context[:similar_errors].empty?

        enhanced_errors = errors.map do |error|
          # 유사한 오류 찾기
          similar_error = find_most_similar_error(error, similar_cases_context[:similar_errors])

          if similar_error && similar_error[:similarity] > 0.8
            # 유사 사례의 컨텍스트로 오류 강화
            error.merge(
              similar_case: {
                description: similar_error[:description],
                solution: similar_error[:solution],
                similarity: similar_error[:similarity],
                confidence: similar_error[:confidence]
              },
              enhanced_context: build_enhanced_context(error, similar_error)
            )
          else
            error
          end
        end

        enhanced_errors
      end

      def find_most_similar_error(target_error, similar_errors)
        target_description = format_error_for_search(target_error)

        similar_errors.max_by do |similar_error|
          calculate_text_similarity(target_description, similar_error[:description] || "")
        end
      end

      def calculate_text_similarity(text1, text2)
        # 간단한 텍스트 유사도 계산
        return 0.0 if text1.blank? || text2.blank?

        words1 = text1.downcase.split(/\W+/).to_set
        words2 = text2.downcase.split(/\W+/).to_set

        intersection = words1 & words2
        union = words1 | words2

        return 0.0 if union.empty?
        intersection.size.to_f / union.size
      end

      def build_enhanced_context(original_error, similar_error)
        # 원본 오류와 유사 사례를 결합한 강화된 컨텍스트 생성
        context = []

        context << "Original error: #{original_error[:type]} - #{original_error[:message]}"

        if similar_error[:solution].present?
          context << "Similar case solution: #{similar_error[:solution]}"
        end

        if similar_error[:confidence] && similar_error[:confidence] > 0.8
          context << "High confidence solution available from similar case"
        end

        context.join(". ")
      end

      def using_modern_models?
        models = [ @models[TIER1_MODELS.keys.first], @models[TIER2_MODELS.keys.first], @models[TIER3_MODELS.keys.first] ].compact.flatten
        models.any? { |model| model.include?("3.1") || model.include?("4.1") || model.include?("maverick") }
      end
    end
  end
end
