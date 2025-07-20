# frozen_string_literal: true

module ExcelAnalysis
  module Services
    # Excel 버전별 호환성 분석 시스템
    # 다양한 Excel 버전 간의 기능 호환성을 분석하고 마이그레이션 가이드 제공
    class ExcelCompatibilityAnalyzer
      include ActiveModel::Model

      # 호환성 분석 오류
      class CompatibilityAnalysisError < StandardError; end
      class VersionDetectionError < StandardError; end
      class FeatureCompatibilityError < StandardError; end

      # Excel 버전 정보
      EXCEL_VERSIONS = {
        "97" => {
          year: 1997,
          max_rows: 65_536,
          max_columns: 256,
          max_formula_length: 1024,
          supported_functions: %w[SUM AVERAGE COUNT IF VLOOKUP HLOOKUP],
          unsupported_features: [ "pivot_charts", "conditional_formatting", "data_validation" ]
        },
        "2000" => {
          year: 2000,
          max_rows: 65_536,
          max_columns: 256,
          max_formula_length: 1024,
          supported_functions: %w[SUM AVERAGE COUNT IF VLOOKUP HLOOKUP SUMIF COUNTIF],
          unsupported_features: [ "pivot_charts", "advanced_conditional_formatting" ]
        },
        "2003" => {
          year: 2003,
          max_rows: 65_536,
          max_columns: 256,
          max_formula_length: 1024,
          supported_functions: %w[SUM AVERAGE COUNT IF VLOOKUP HLOOKUP SUMIF COUNTIF LOOKUP],
          unsupported_features: [ "tables", "slicers" ]
        },
        "2007" => {
          year: 2007,
          max_rows: 1_048_576,
          max_columns: 16_384,
          max_formula_length: 8192,
          supported_functions: %w[SUM AVERAGE COUNT IF VLOOKUP HLOOKUP SUMIF COUNTIF SUMIFS COUNTIFS AVERAGEIFS IFERROR],
          new_features: [ "tables", "conditional_formatting_v2", "larger_worksheets" ]
        },
        "2010" => {
          year: 2010,
          max_rows: 1_048_576,
          max_columns: 16_384,
          max_formula_length: 8192,
          supported_functions: %w[SUM AVERAGE COUNT IF VLOOKUP HLOOKUP SUMIF COUNTIF SUMIFS COUNTIFS AVERAGEIFS IFERROR AGGREGATE],
          new_features: [ "slicers", "sparklines", "improved_pivot_tables" ]
        },
        "2013" => {
          year: 2013,
          max_rows: 1_048_576,
          max_columns: 16_384,
          max_formula_length: 8192,
          supported_functions: %w[SUM AVERAGE COUNT IF VLOOKUP HLOOKUP SUMIF COUNTIF SUMIFS COUNTIFS AVERAGEIFS IFERROR AGGREGATE WEBSERVICE ENCODEURL],
          new_features: [ "power_query", "power_pivot", "recommended_charts" ]
        },
        "2016" => {
          year: 2016,
          max_rows: 1_048_576,
          max_columns: 16_384,
          max_formula_length: 8192,
          supported_functions: %w[SUM AVERAGE COUNT IF VLOOKUP HLOOKUP SUMIF COUNTIF SUMIFS COUNTIFS AVERAGEIFS IFERROR AGGREGATE WEBSERVICE ENCODEURL FORECAST],
          new_features: [ "power_bi_integration", "advanced_charts", "tell_me_feature" ]
        },
        "2019" => {
          year: 2019,
          max_rows: 1_048_576,
          max_columns: 16_384,
          max_formula_length: 8192,
          supported_functions: %w[SUM AVERAGE COUNT IF VLOOKUP HLOOKUP SUMIF COUNTIF SUMIFS COUNTIFS AVERAGEIFS IFERROR AGGREGATE WEBSERVICE ENCODEURL FORECAST IFS SWITCH MAXIFS MINIFS],
          new_features: [ "dynamic_arrays", "xlookup_preview", "improved_accessibility" ]
        },
        "365" => {
          year: 2021,
          max_rows: 1_048_576,
          max_columns: 16_384,
          max_formula_length: 8192,
          supported_functions: %w[SUM AVERAGE COUNT IF VLOOKUP HLOOKUP SUMIF COUNTIF SUMIFS COUNTIFS AVERAGEIFS IFERROR AGGREGATE WEBSERVICE ENCODEURL FORECAST IFS SWITCH MAXIFS MINIFS XLOOKUP XMATCH FILTER SORT UNIQUE LAMBDA LET],
          new_features: [ "dynamic_arrays_full", "xlookup", "lambda_functions", "let_function", "real_time_collaboration" ]
        }
      }.freeze

      # 기능별 호환성 매트릭스
      FEATURE_COMPATIBILITY = {
        dynamic_arrays: {
          minimum_version: "365",
          fallback_strategy: "convert_to_traditional_formulas",
          impact: "high"
        },
        xlookup: {
          minimum_version: "365",
          fallback_strategy: "convert_to_vlookup_index_match",
          impact: "medium"
        },
        lambda_functions: {
          minimum_version: "365",
          fallback_strategy: "expand_to_traditional_functions",
          impact: "high"
        },
        power_query: {
          minimum_version: "2013",
          fallback_strategy: "manual_data_transformation",
          impact: "high"
        },
        slicers: {
          minimum_version: "2010",
          fallback_strategy: "use_traditional_filters",
          impact: "low"
        }
      }.freeze

      attr_reader :formula_engine_client

      def initialize
        @formula_engine_client = FormulaEngineClient.instance
      end

      # Excel 파일 호환성 분석
      # @param excel_file [ExcelFile] 분석할 Excel 파일
      # @param target_versions [Array] 대상 버전 목록
      # @return [Common::Result] 호환성 분석 결과
      def analyze_compatibility(excel_file, target_versions = [ "97", "2003", "2007", "2010", "2016", "365" ])
        Rails.logger.info("Excel 호환성 분석 시작: #{excel_file.id}")

        compatibility_analysis = {
          file_info: {
            excel_file_id: excel_file.id,
            detected_version: nil,
            file_format: nil
          },
          target_versions: target_versions,
          compatibility_matrix: {},
          issues_by_version: {},
          migration_recommendations: {},
          summary: {
            fully_compatible_versions: [],
            partially_compatible_versions: [],
            incompatible_versions: [],
            critical_issues_count: 0,
            warning_issues_count: 0
          }
        }

        begin
          # 1. 현재 파일의 Excel 버전 감지
          version_detection = detect_excel_version(excel_file)
          return version_detection if version_detection.failure?

          compatibility_analysis[:file_info].merge!(version_detection.value)

          # 2. 파일 특성 분석
          file_analysis = analyze_file_characteristics(excel_file)
          return file_analysis if file_analysis.failure?

          file_characteristics = file_analysis.value

          # 3. 각 대상 버전별 호환성 검사
          target_versions.each do |target_version|
            version_compatibility = analyze_version_compatibility(
              file_characteristics,
              target_version,
              compatibility_analysis[:file_info][:detected_version]
            )

            if version_compatibility.success?
              compatibility_analysis[:compatibility_matrix][target_version] = version_compatibility.value
              compatibility_analysis[:issues_by_version][target_version] = version_compatibility.value[:issues]

              # 마이그레이션 권장사항 생성
              migration_recommendations = generate_migration_recommendations(
                version_compatibility.value,
                target_version
              )
              compatibility_analysis[:migration_recommendations][target_version] = migration_recommendations
            end
          end

          # 4. 전체 요약 생성
          generate_compatibility_summary(compatibility_analysis)

          Common::Result.success(compatibility_analysis)

        rescue StandardError => e
          Rails.logger.error("호환성 분석 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "호환성 분석 실패: #{e.message}",
              code: "COMPATIBILITY_ANALYSIS_ERROR",
              details: { excel_file_id: excel_file.id, target_versions: target_versions }
            )
          )
        end
      end

      # 특정 기능의 호환성 검사
      # @param feature [String] 검사할 기능
      # @param target_version [String] 대상 Excel 버전
      # @return [Common::Result] 기능 호환성 결과
      def check_feature_compatibility(feature, target_version)
        Rails.logger.info("기능 호환성 검사: #{feature} -> Excel #{target_version}")

        begin
          if FEATURE_COMPATIBILITY.key?(feature.to_sym)
            feature_info = FEATURE_COMPATIBILITY[feature.to_sym]
            minimum_version = feature_info[:minimum_version]

            is_compatible = version_supports_feature?(target_version, minimum_version)

            result = {
              feature: feature,
              target_version: target_version,
              is_compatible: is_compatible,
              minimum_required_version: minimum_version,
              fallback_strategy: feature_info[:fallback_strategy],
              impact_level: feature_info[:impact]
            }

            unless is_compatible
              result[:migration_suggestions] = generate_feature_migration_suggestions(
                feature,
                target_version,
                feature_info
              )
            end

            Common::Result.success(result)
          else
            Common::Result.failure(
              Common::Errors::ValidationError.new(
                message: "알 수 없는 기능: #{feature}",
                details: { available_features: FEATURE_COMPATIBILITY.keys }
              )
            )
          end

        rescue StandardError => e
          Rails.logger.error("기능 호환성 검사 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "기능 호환성 검사 실패: #{e.message}",
              code: "FEATURE_COMPATIBILITY_ERROR",
              details: { feature: feature, target_version: target_version }
            )
          )
        end
      end

      # 호환성 개선 제안
      # @param compatibility_analysis [Hash] 호환성 분석 결과
      # @param target_version [String] 대상 버전
      # @return [Common::Result] 개선 제안 결과
      def suggest_compatibility_improvements(compatibility_analysis, target_version)
        Rails.logger.info("호환성 개선 제안 생성: Excel #{target_version}")

        begin
          improvements = {
            target_version: target_version,
            priority_improvements: [],
            optional_improvements: [],
            automated_fixes: [],
            manual_changes_required: [],
            estimated_effort: {}
          }

          version_issues = compatibility_analysis[:issues_by_version][target_version] || []

          # 우선순위별 개선사항 분류
          version_issues.each do |issue|
            improvement = generate_improvement_suggestion(issue, target_version)

            case issue[:severity]
            when "critical", "error"
              improvements[:priority_improvements] << improvement
            when "warning"
              improvements[:optional_improvements] << improvement
            end

            if improvement[:can_automate]
              improvements[:automated_fixes] << improvement
            else
              improvements[:manual_changes_required] << improvement
            end
          end

          # 작업량 추정
          improvements[:estimated_effort] = estimate_migration_effort(improvements)

          Common::Result.success(improvements)

        rescue StandardError => e
          Rails.logger.error("호환성 개선 제안 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "호환성 개선 제안 실패: #{e.message}",
              code: "COMPATIBILITY_IMPROVEMENT_ERROR",
              details: { target_version: target_version }
            )
          )
        end
      end

      # 자동 호환성 변환
      # @param excel_file [ExcelFile] 변환할 Excel 파일
      # @param target_version [String] 대상 버전
      # @param options [Hash] 변환 옵션
      # @return [Common::Result] 변환 결과
      def auto_convert_for_compatibility(excel_file, target_version, options = {})
        Rails.logger.info("자동 호환성 변환 시작: #{excel_file.id} -> Excel #{target_version}")

        conversion_result = {
          original_file: excel_file.id,
          target_version: target_version,
          conversions_applied: [],
          conversion_summary: {},
          warnings: [],
          manual_steps_required: []
        }

        begin
          # 1. 호환성 분석 수행
          compatibility_result = analyze_compatibility(excel_file, [ target_version ])
          return compatibility_result if compatibility_result.failure?

          compatibility_data = compatibility_result.value
          version_issues = compatibility_data[:issues_by_version][target_version] || []

          # 2. 자동 변환 가능한 이슈들 처리
          version_issues.each do |issue|
            if can_auto_convert?(issue, target_version)
              conversion = apply_auto_conversion(issue, target_version, options)

              if conversion[:success]
                conversion_result[:conversions_applied] << conversion
              else
                conversion_result[:warnings] << {
                  issue: issue,
                  reason: conversion[:error_message]
                }
              end
            else
              conversion_result[:manual_steps_required] << {
                issue: issue,
                manual_steps: generate_manual_conversion_steps(issue, target_version)
              }
            end
          end

          # 3. 변환 요약 생성
          conversion_result[:conversion_summary] = {
            total_issues: version_issues.length,
            auto_converted: conversion_result[:conversions_applied].length,
            manual_required: conversion_result[:manual_steps_required].length,
            conversion_rate: calculate_conversion_rate(conversion_result)
          }

          Common::Result.success(conversion_result)

        rescue StandardError => e
          Rails.logger.error("자동 호환성 변환 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "자동 호환성 변환 실패: #{e.message}",
              code: "AUTO_CONVERSION_ERROR",
              details: { excel_file_id: excel_file.id, target_version: target_version }
            )
          )
        end
      end

      private

      # Excel 버전 감지
      def detect_excel_version(excel_file)
        begin
          # 파일 확장자 기반 초기 추정
          file_extension = File.extname(excel_file.filename).downcase
          estimated_version = estimate_version_from_extension(file_extension)

          # 파일 내용 분석을 통한 정확한 버전 감지
          analysis_service = FormulaAnalysisService.new(excel_file)
          analysis_result = analysis_service.analyze

          if analysis_result.success?
            formula_data = analysis_result.value[:formula_analysis]
            detected_version = detect_version_from_content(formula_data, estimated_version)
          else
            detected_version = estimated_version
          end

          Common::Result.success({
            detected_version: detected_version,
            file_format: file_extension,
            detection_confidence: calculate_detection_confidence(detected_version, file_extension)
          })

        rescue StandardError => e
          Rails.logger.error("Excel 버전 감지 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "Excel 버전 감지 실패: #{e.message}",
              code: "VERSION_DETECTION_ERROR"
            )
          )
        end
      end

      # 파일 특성 분석
      def analyze_file_characteristics(excel_file)
        begin
          # FormulaAnalysisService를 통한 상세 분석
          analysis_service = FormulaAnalysisService.new(excel_file)
          analysis_result = analysis_service.analyze
          return analysis_result if analysis_result.failure?

          formula_data = analysis_result.value[:formula_analysis]

          characteristics = {
            worksheet_count: extract_worksheet_count(formula_data),
            total_formulas: extract_total_formulas(formula_data),
            used_functions: extract_used_functions(formula_data),
            max_formula_length: calculate_max_formula_length(formula_data),
            has_large_ranges: detect_large_ranges(formula_data),
            features_used: detect_advanced_features(formula_data),
            data_complexity: assess_data_complexity(formula_data)
          }

          Common::Result.success(characteristics)

        rescue StandardError => e
          Rails.logger.error("파일 특성 분석 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "파일 특성 분석 실패: #{e.message}",
              code: "FILE_ANALYSIS_ERROR"
            )
          )
        end
      end

      # 버전별 호환성 분석
      def analyze_version_compatibility(file_characteristics, target_version, current_version)
        target_specs = EXCEL_VERSIONS[target_version]
        return Common::Result.failure(
          Common::Errors::ValidationError.new(message: "지원하지 않는 Excel 버전: #{target_version}")
        ) unless target_specs

        compatibility_result = {
          target_version: target_version,
          is_compatible: true,
          compatibility_score: 100.0,
          issues: [],
          limitations: [],
          recommendations: []
        }

        # 1. 워크시트 크기 제한 검사
        check_worksheet_size_limits(file_characteristics, target_specs, compatibility_result)

        # 2. 수식 길이 제한 검사
        check_formula_length_limits(file_characteristics, target_specs, compatibility_result)

        # 3. 함수 호환성 검사
        check_function_compatibility(file_characteristics, target_specs, compatibility_result)

        # 4. 고급 기능 호환성 검사
        check_advanced_features_compatibility(file_characteristics, target_specs, compatibility_result)

        # 5. 전체 호환성 점수 계산
        compatibility_result[:compatibility_score] = calculate_compatibility_score(compatibility_result)
        compatibility_result[:is_compatible] = compatibility_result[:compatibility_score] >= 80.0

        Common::Result.success(compatibility_result)
      end

      # 마이그레이션 권장사항 생성
      def generate_migration_recommendations(compatibility_result, target_version)
        recommendations = []

        compatibility_result[:issues].each do |issue|
          case issue[:type]
          when "unsupported_function"
            recommendations << {
              type: "function_replacement",
              priority: "high",
              description: "#{issue[:function]} 함수를 #{target_version}에서 지원하는 대안으로 교체",
              suggested_alternatives: get_function_alternatives(issue[:function], target_version),
              automation_possible: true
            }
          when "worksheet_size_limit"
            recommendations << {
              type: "data_reduction",
              priority: "critical",
              description: "워크시트 크기를 대상 버전의 제한 내로 축소",
              suggested_actions: [ "데이터 분할", "불필요한 행/열 제거", "여러 워크시트로 분리" ],
              automation_possible: false
            }
          when "advanced_feature"
            recommendations << {
              type: "feature_replacement",
              priority: "medium",
              description: "#{issue[:feature]} 기능을 대상 버전에서 지원하는 방법으로 변경",
              suggested_alternatives: get_feature_alternatives(issue[:feature], target_version),
              automation_possible: issue[:feature] != "pivot_tables"
            }
          end
        end

        recommendations
      end

      # 호환성 요약 생성
      def generate_compatibility_summary(compatibility_analysis)
        summary = compatibility_analysis[:summary]

        compatibility_analysis[:compatibility_matrix].each do |version, result|
          case result[:compatibility_score]
          when 90..100
            summary[:fully_compatible_versions] << version
          when 70..89
            summary[:partially_compatible_versions] << version
          else
            summary[:incompatible_versions] << version
          end

          result[:issues].each do |issue|
            case issue[:severity]
            when "critical", "error"
              summary[:critical_issues_count] += 1
            when "warning"
              summary[:warning_issues_count] += 1
            end
          end
        end
      end

      # 헬퍼 메소드들

      def estimate_version_from_extension(extension)
        case extension
        when ".xls" then "2003"
        when ".xlsx", ".xlsm" then "2007"
        when ".xlsb" then "2010"
        else "365"
        end
      end

      def detect_version_from_content(formula_data, estimated_version)
        used_functions = extract_used_functions(formula_data)

        # 최신 함수 사용 여부로 버전 추정
        if used_functions.any? { |f| %w[XLOOKUP XMATCH FILTER SORT UNIQUE LAMBDA LET].include?(f.upcase) }
          "365"
        elsif used_functions.any? { |f| %w[IFS SWITCH MAXIFS MINIFS].include?(f.upcase) }
          "2019"
        elsif used_functions.any? { |f| %w[FORECAST WEBSERVICE].include?(f.upcase) }
          "2016"
        elsif used_functions.any? { |f| %w[AGGREGATE].include?(f.upcase) }
          "2010"
        elsif used_functions.any? { |f| %w[SUMIFS COUNTIFS AVERAGEIFS IFERROR].include?(f.upcase) }
          "2007"
        else
          estimated_version
        end
      end

      def calculate_detection_confidence(detected_version, file_extension)
        base_confidence = 0.7

        # 파일 확장자와 감지된 버전의 일치성 확인
        expected_extension = case detected_version
        when "97", "2000", "2003" then ".xls"
        when "2007", "2010", "2013", "2016", "2019", "365" then ".xlsx"
        end

        if file_extension == expected_extension
          base_confidence += 0.2
        end

        [ base_confidence, 1.0 ].min
      end

      def extract_worksheet_count(formula_data)
        formula_data&.dig("summary", "totalSheets") || 1
      end

      def extract_total_formulas(formula_data)
        formula_data&.dig("summary", "totalFormulas") || 0
      end

      def extract_used_functions(formula_data)
        functions_data = formula_data&.dig("functions", "details") || []
        functions_data.map { |f| f["name"] }.uniq
      end

      def calculate_max_formula_length(formula_data)
        formulas = formula_data&.dig("formulas") || []
        formulas.map { |f| f["formula"]&.length || 0 }.max || 0
      end

      def detect_large_ranges(formula_data)
        # 큰 범위 참조 감지 로직
        false # 예시
      end

      def detect_advanced_features(formula_data)
        features = []

        # 고급 기능 감지 로직
        used_functions = extract_used_functions(formula_data)

        features << "dynamic_arrays" if used_functions.any? { |f| %w[FILTER SORT UNIQUE].include?(f.upcase) }
        features << "xlookup" if used_functions.include?("XLOOKUP")
        features << "lambda_functions" if used_functions.include?("LAMBDA")

        features
      end

      def assess_data_complexity(formula_data)
        total_formulas = extract_total_formulas(formula_data)

        case total_formulas
        when 0..10 then "simple"
        when 11..100 then "moderate"
        when 101..1000 then "complex"
        else "very_complex"
        end
      end

      def check_worksheet_size_limits(characteristics, target_specs, result)
        # 워크시트 크기 제한 검사 로직
        if characteristics[:worksheet_count] > 256 && target_specs[:max_columns] == 256
          result[:issues] << {
            type: "worksheet_size_limit",
            severity: "critical",
            message: "워크시트가 대상 버전의 열 제한을 초과합니다.",
            details: {
              current: characteristics[:worksheet_count],
              limit: target_specs[:max_columns]
            }
          }
          result[:is_compatible] = false
        end
      end

      def check_formula_length_limits(characteristics, target_specs, result)
        if characteristics[:max_formula_length] > target_specs[:max_formula_length]
          result[:issues] << {
            type: "formula_length_limit",
            severity: "error",
            message: "수식 길이가 대상 버전의 제한을 초과합니다.",
            details: {
              max_length: characteristics[:max_formula_length],
              limit: target_specs[:max_formula_length]
            }
          }
        end
      end

      def check_function_compatibility(characteristics, target_specs, result)
        unsupported_functions = characteristics[:used_functions] - target_specs[:supported_functions]

        unsupported_functions.each do |func|
          result[:issues] << {
            type: "unsupported_function",
            severity: "error",
            function: func,
            message: "#{func} 함수는 대상 버전에서 지원되지 않습니다."
          }
        end
      end

      def check_advanced_features_compatibility(characteristics, target_specs, result)
        characteristics[:features_used].each do |feature|
          if FEATURE_COMPATIBILITY.key?(feature.to_sym)
            feature_info = FEATURE_COMPATIBILITY[feature.to_sym]
            unless version_supports_feature?(target_specs[:year].to_s, feature_info[:minimum_version])
              result[:issues] << {
                type: "advanced_feature",
                severity: feature_info[:impact] == "high" ? "error" : "warning",
                feature: feature,
                message: "#{feature} 기능은 대상 버전에서 지원되지 않습니다."
              }
            end
          end
        end
      end

      def calculate_compatibility_score(compatibility_result)
        total_issues = compatibility_result[:issues].length
        return 100.0 if total_issues == 0

        critical_issues = compatibility_result[:issues].count { |i| i[:severity] == "critical" }
        error_issues = compatibility_result[:issues].count { |i| i[:severity] == "error" }
        warning_issues = compatibility_result[:issues].count { |i| i[:severity] == "warning" }

        score = 100.0
        score -= critical_issues * 30.0
        score -= error_issues * 15.0
        score -= warning_issues * 5.0

        [ score, 0.0 ].max
      end

      def version_supports_feature?(target_version, minimum_version)
        target_year = EXCEL_VERSIONS[target_version]&.dig(:year) || 0
        minimum_year = EXCEL_VERSIONS[minimum_version]&.dig(:year) || 0

        target_year >= minimum_year
      end

      def generate_feature_migration_suggestions(feature, target_version, feature_info)
        [
          {
            strategy: feature_info[:fallback_strategy],
            description: "#{feature}를 #{target_version}에서 지원하는 방법으로 변경",
            effort_level: feature_info[:impact],
            automated: feature_info[:impact] != "high"
          }
        ]
      end

      def generate_improvement_suggestion(issue, target_version)
        {
          issue_type: issue[:type],
          description: issue[:message],
          suggested_action: generate_action_for_issue(issue, target_version),
          can_automate: can_auto_convert?(issue, target_version),
          effort_estimate: estimate_issue_effort(issue)
        }
      end

      def generate_action_for_issue(issue, target_version)
        case issue[:type]
        when "unsupported_function"
          "#{issue[:function]} 함수를 #{get_function_alternatives(issue[:function], target_version).first}로 교체"
        when "formula_length_limit"
          "긴 수식을 여러 단계로 분할"
        when "advanced_feature"
          "#{issue[:feature]} 기능을 기본 기능으로 교체"
        else
          "수동 검토 및 수정 필요"
        end
      end

      def can_auto_convert?(issue, target_version)
        case issue[:type]
        when "unsupported_function"
          %w[XLOOKUP XMATCH IFS SWITCH].include?(issue[:function])
        when "advanced_feature"
          issue[:feature] == "dynamic_arrays"
        else
          false
        end
      end

      def apply_auto_conversion(issue, target_version, options)
        # 자동 변환 로직 구현
        {
          success: true,
          original: issue,
          converted: "변환된 내용",
          method: "자동 변환 방법"
        }
      end

      def generate_manual_conversion_steps(issue, target_version)
        case issue[:type]
        when "worksheet_size_limit"
          [
            "큰 데이터셋을 여러 워크시트로 분할",
            "불필요한 행과 열 삭제",
            "데이터를 외부 파일로 분리"
          ]
        when "formula_length_limit"
          [
            "복잡한 수식을 여러 단계로 분할",
            "중간 계산용 헬퍼 컬럼 생성",
            "수식 단순화 및 최적화"
          ]
        else
          [ "수동 검토 및 수정 필요" ]
        end
      end

      def calculate_conversion_rate(conversion_result)
        total = conversion_result[:conversions_applied].length + conversion_result[:manual_steps_required].length
        return 100.0 if total == 0

        (conversion_result[:conversions_applied].length.to_f / total * 100).round(2)
      end

      def estimate_migration_effort(improvements)
        {
          automated_fixes: improvements[:automated_fixes].length,
          manual_changes: improvements[:manual_changes_required].length,
          estimated_hours: calculate_estimated_hours(improvements),
          complexity_level: determine_complexity_level(improvements)
        }
      end

      def calculate_estimated_hours(improvements)
        hours = 0
        hours += improvements[:automated_fixes].length * 0.5
        hours += improvements[:manual_changes_required].length * 2.0
        hours
      end

      def determine_complexity_level(improvements)
        manual_count = improvements[:manual_changes_required].length

        case manual_count
        when 0..3 then "low"
        when 4..10 then "medium"
        else "high"
        end
      end

      def estimate_issue_effort(issue)
        case issue[:severity]
        when "critical" then "high"
        when "error" then "medium"
        when "warning" then "low"
        else "low"
        end
      end

      def get_function_alternatives(function, target_version)
        alternatives = {
          "XLOOKUP" => [ "VLOOKUP", "INDEX+MATCH" ],
          "XMATCH" => [ "MATCH" ],
          "FILTER" => [ "IF with array formula" ],
          "SORT" => [ "Manual sorting" ],
          "UNIQUE" => [ "Remove duplicates manually" ],
          "IFS" => [ "Nested IF" ],
          "SWITCH" => [ "Nested IF" ]
        }

        alternatives[function] || [ "Alternative function" ]
      end

      def get_feature_alternatives(feature, target_version)
        alternatives = {
          "dynamic_arrays" => [ "Traditional formulas" ],
          "slicers" => [ "Traditional filters" ],
          "power_query" => [ "Manual data transformation" ]
        }

        alternatives[feature] || [ "Manual alternative" ]
      end
    end
  end
end
