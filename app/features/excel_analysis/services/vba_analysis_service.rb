# frozen_string_literal: true

module ExcelAnalysis
  module Services
    # VBACop + Rubberduck 기반 VBA 분석 서비스 (오픈소스)
    class VbaAnalysisService
      include Memoist

      # VBA 분석 메트릭
      VBA_METRICS = {
        complexity_thresholds: {
          low: 10,
          medium: 25,
          high: 50,
          critical: 100
        },
        security_patterns: {
          dangerous_functions: %w[Shell Environ CreateObject GetObject],
          file_operations: %w[Open Save SaveAs Close Kill],
          external_calls: %w[DLL Declare CallByName],
          registry_access: %w[SaveSetting GetSetting DeleteSetting]
        },
        performance_patterns: {
          inefficient_loops: %w[For While Do],
          unoptimized_calls: %w[Select Activate],
          memory_leaks: %w[Set Nothing]
        }
      }.freeze

      def initialize(file_path, options = {})
        @file_path = file_path
        @options = options.with_defaults({
          deep_analysis: true,
          security_scan: true,
          performance_analysis: true,
          extract_code: true
        })
        @cache = Rails.cache
      end

      # 종합 VBA 분석 (Rubberduck + 커스텀 분석)
      def analyze_vba_comprehensive
        start_time = Time.current

        Rails.logger.info("Starting comprehensive VBA analysis for #{@file_path}")

        begin
          # 1단계: VBA 코드 추출
          vba_modules = extract_vba_modules
          return no_vba_result if vba_modules.empty?

          # 2단계: 정적 분석 (VBACop 스타일)
          static_analysis = perform_static_analysis(vba_modules)

          # 3단계: 보안 분석
          security_analysis = perform_security_analysis(vba_modules)

          # 4단계: 성능 분석
          performance_analysis = perform_performance_analysis(vba_modules)

          # 5단계: 복잡도 분석
          complexity_analysis = calculate_complexity_metrics(vba_modules)

          # 6단계: 종합 점수 계산
          overall_score = calculate_overall_score(static_analysis, security_analysis, performance_analysis)

          processing_time = Time.current - start_time

          {
            success: true,
            modules_found: vba_modules.size,
            static_analysis: static_analysis,
            security_analysis: security_analysis,
            performance_analysis: performance_analysis,
            complexity_analysis: complexity_analysis,
            overall_score: overall_score,
            recommendations: generate_recommendations(static_analysis, security_analysis, performance_analysis),
            processing_time: processing_time,
            analysis_timestamp: Time.current
          }

        rescue StandardError => e
          Rails.logger.error("VBA analysis failed: #{e.message}")
          error_result(e.message)
        end
      end

      # VBA 보안 스캔 (특화 분석)
      def scan_vba_security
        vba_modules = extract_vba_modules
        return no_vba_result if vba_modules.empty?

        security_issues = []
        risk_level = "low"

        vba_modules.each do |module_data|
          module_issues = scan_module_security(module_data)
          security_issues.concat(module_issues)
        end

        # 위험도 평가
        risk_level = assess_security_risk(security_issues)

        {
          security_issues: security_issues,
          risk_level: risk_level,
          total_issues: security_issues.size,
          critical_issues: security_issues.count { |issue| issue[:severity] == "critical" },
          recommendations: generate_security_recommendations(security_issues)
        }
      end

      # VBA 성능 최적화 분석
      def analyze_vba_performance
        vba_modules = extract_vba_modules
        return no_vba_result if vba_modules.empty?

        performance_issues = []
        optimization_opportunities = []

        vba_modules.each do |module_data|
          module_performance = analyze_module_performance(module_data)
          performance_issues.concat(module_performance[:issues])
          optimization_opportunities.concat(module_performance[:optimizations])
        end

        {
          performance_issues: performance_issues,
          optimization_opportunities: optimization_opportunities,
          estimated_improvement: calculate_performance_improvement(optimization_opportunities),
          priority_fixes: prioritize_performance_fixes(performance_issues)
        }
      end

      private

      # VBA 모듈 추출 (RubyXL + 커스텀 파서)
      def extract_vba_modules
        cache_key = "vba_extraction:#{File.mtime(@file_path).to_i}:#{@file_path.hash}"
        cached_result = @cache.read(cache_key)
        return cached_result if cached_result

        modules = []

        begin
          # Excel 파일에서 VBA 프로젝트 추출
          workbook = RubyXL::Parser.parse(@file_path)

          # VBA 프로젝트 확인
          if workbook.vba_project
            Rails.logger.info("VBA project detected, extracting modules")
            modules = extract_modules_from_vba_project(workbook.vba_project)
          else
            # 파일 시그니처로 매크로 존재 확인
            modules = detect_vba_by_signature
          end

          @cache.write(cache_key, modules, expires_in: 1.hour)
          modules

        rescue StandardError => e
          Rails.logger.warn("VBA extraction failed: #{e.message}")
          # 폴백: 파일 내용 직접 스캔
          scan_file_for_vba_signatures
        end
      end

      def extract_modules_from_vba_project(vba_project)
        modules = []

        vba_project.modules.each_with_index do |module_obj, index|
          module_data = {
            name: module_obj.name || "Module#{index + 1}",
            type: determine_module_type(module_obj),
            code: extract_module_code(module_obj),
            line_count: 0,
            function_count: 0,
            sub_count: 0
          }

          # 코드 메트릭 계산
          if module_data[:code]
            module_data[:line_count] = module_data[:code].lines.count
            module_data[:function_count] = count_functions(module_data[:code])
            module_data[:sub_count] = count_subroutines(module_data[:code])
          end

          modules << module_data
        end

        modules
      end

      def detect_vba_by_signature
        # 파일 바이너리에서 VBA 시그니처 검색
        File.open(@file_path, "rb") do |file|
          content = file.read(1024 * 1024) # 첫 1MB만 스캔

          vba_signatures = [
            "Microsoft Office Macro",
            "VBA7",
            "ThisWorkbook",
            "Module1",
            "Sheet1",
            "UserForm"
          ]

          detected_modules = []

          vba_signatures.each do |signature|
            if content.include?(signature)
              detected_modules << {
                name: signature,
                type: "detected_signature",
                code: nil,
                detected_by: "signature_scan"
              }
            end
          end

          detected_modules
        end
      end

      def scan_file_for_vba_signatures
        # 최후 수단: 텍스트 패턴으로 VBA 존재 추정
        return [] unless File.exist?(@file_path)

        vba_patterns = [
          /Sub\s+\w+\(/i,
          /Function\s+\w+\(/i,
          /Private\s+Sub/i,
          /Public\s+Function/i,
          /Dim\s+\w+\s+As/i
        ]

        # 파일 내용 샘플링
        sample_content = ""
        File.open(@file_path, "rb") do |file|
          # 파일 여러 지점에서 샘플링
          [ 0, file.size / 4, file.size / 2, file.size * 3 / 4 ].each do |offset|
            file.seek(offset)
            sample_content += file.read(4096) || ""
          end
        end

        detected_patterns = []
        vba_patterns.each_with_index do |pattern, index|
          matches = sample_content.scan(pattern)
          if matches.any?
            detected_patterns << {
              name: "VBA_Pattern_#{index + 1}",
              type: "pattern_detection",
              pattern: pattern.source,
              matches: matches.size,
              code: nil
            }
          end
        end

        detected_patterns
      end

      # 정적 분석 (VBACop 스타일)
      def perform_static_analysis(modules)
        issues = []
        code_quality_score = 100

        modules.each do |module_data|
          next unless module_data[:code]

          # 코딩 스타일 검사
          style_issues = check_coding_style(module_data)
          issues.concat(style_issues)

          # 잠재적 버그 검사
          bug_issues = detect_potential_bugs(module_data)
          issues.concat(bug_issues)

          # 코드 복잡도 검사
          complexity_issues = check_code_complexity(module_data)
          issues.concat(complexity_issues)
        end

        # 품질 점수 계산
        code_quality_score -= issues.size * 2
        code_quality_score = [ code_quality_score, 0 ].max

        {
          total_issues: issues.size,
          code_quality_score: code_quality_score,
          issues_by_severity: group_issues_by_severity(issues),
          detailed_issues: issues
        }
      end

      def check_coding_style(module_data)
        issues = []
        code = module_data[:code]

        # Option Explicit 검사
        unless code.match?(/Option\s+Explicit/i)
          issues << {
            type: "style",
            severity: "warning",
            message: "Option Explicit not declared",
            module: module_data[:name],
            recommendation: 'Add "Option Explicit" at the top of the module'
          }
        end

        # 변수 명명 규칙 검사
        code.scan(/Dim\s+(\w+)/i) do |var_name|
          if var_name[0].length < 3
            issues << {
              type: "style",
              severity: "info",
              message: "Variable name too short: #{var_name[0]}",
              module: module_data[:name],
              recommendation: "Use descriptive variable names with at least 3 characters"
            }
          end
        end

        # 매직 넘버 검사
        magic_numbers = code.scan(/\b\d{2,}\b/).uniq
        if magic_numbers.any?
          issues << {
            type: "style",
            severity: "info",
            message: "Magic numbers found: #{magic_numbers.join(', ')}",
            module: module_data[:name],
            recommendation: "Consider using named constants instead of magic numbers"
          }
        end

        issues
      end

      def detect_potential_bugs(module_data)
        issues = []
        code = module_data[:code]

        # 초기화되지 않은 변수 사용 가능성
        variables = code.scan(/Dim\s+(\w+)/i).flatten
        variables.each do |var|
          # 선언 후 사용 전 초기화 확인 (간소화)
          var_usage = code.scan(/#{Regexp.escape(var)}\s*[=<>]/i)
          if var_usage.empty?
            issues << {
              type: "bug",
              severity: "warning",
              message: "Variable '#{var}' may be used without initialization",
              module: module_data[:name],
              recommendation: "Initialize variables before use"
            }
          end
        end

        # Division by zero 가능성
        if code.match?(/\/\s*[a-zA-Z_]\w*/i)
          issues << {
            type: "bug",
            severity: "warning",
            message: "Potential division by zero",
            module: module_data[:name],
            recommendation: "Add zero-check before division operations"
          }
        end

        # 무한 루프 가능성
        loop_patterns = [ /Do\s+While/i, /While\s+.+\s+Wend/i, /For\s+.+\s+Next/i ]
        loop_patterns.each do |pattern|
          if code.match?(pattern)
            # 루프 종료 조건 간단 검사
            unless code.match?(/Exit\s+(Do|While|For)/i)
              issues << {
                type: "bug",
                severity: "info",
                message: "Loop without explicit exit condition",
                module: module_data[:name],
                recommendation: "Add exit conditions to prevent infinite loops"
              }
            end
          end
        end

        issues
      end

      def check_code_complexity(module_data)
        issues = []
        code = module_data[:code]

        # 함수/서브루틴 길이 검사
        functions = extract_functions_and_subs(code)
        functions.each do |func|
          line_count = func[:code].lines.count
          if line_count > 50
            issues << {
              type: "complexity",
              severity: "warning",
              message: "Function '#{func[:name]}' is too long (#{line_count} lines)",
              module: module_data[:name],
              recommendation: "Break down large functions into smaller, focused functions"
            }
          end
        end

        # 중첩 수준 검사
        nesting_level = calculate_max_nesting_level(code)
        if nesting_level > 4
          issues << {
            type: "complexity",
            severity: "warning",
            message: "High nesting level detected (#{nesting_level})",
            module: module_data[:name],
            recommendation: "Reduce nesting levels by extracting methods or using early returns"
          }
        end

        issues
      end

      # 보안 분석
      def perform_security_analysis(modules)
        security_issues = []
        risk_score = 0

        modules.each do |module_data|
          next unless module_data[:code]

          module_issues = scan_module_security(module_data)
          security_issues.concat(module_issues)
          risk_score += calculate_module_risk_score(module_issues)
        end

        {
          total_security_issues: security_issues.size,
          risk_score: risk_score,
          risk_level: determine_risk_level(risk_score),
          issues_by_category: group_security_issues(security_issues),
          detailed_issues: security_issues
        }
      end

      def scan_module_security(module_data)
        issues = []
        code = module_data[:code]

        # 위험한 함수 호출 검사
        VBA_METRICS[:security_patterns][:dangerous_functions].each do |func|
          if code.match?(/#{Regexp.escape(func)}\s*\(/i)
            issues << {
              type: "security",
              category: "dangerous_function",
              severity: "critical",
              message: "Dangerous function call: #{func}",
              module: module_data[:name],
              recommendation: "Review the necessity of this function and implement proper security measures"
            }
          end
        end

        # 파일 시스템 접근 검사
        VBA_METRICS[:security_patterns][:file_operations].each do |op|
          if code.match?(/#{Regexp.escape(op)}\s*\(/i)
            issues << {
              type: "security",
              category: "file_operation",
              severity: "warning",
              message: "File operation detected: #{op}",
              module: module_data[:name],
              recommendation: "Ensure file operations are necessary and implement proper error handling"
            }
          end
        end

        # 외부 DLL 호출 검사
        VBA_METRICS[:security_patterns][:external_calls].each do |call|
          if code.match?(/#{Regexp.escape(call)}/i)
            issues << {
              type: "security",
              category: "external_call",
              severity: "high",
              message: "External call detected: #{call}",
              module: module_data[:name],
              recommendation: "Review external calls for security implications"
            }
          end
        end

        issues
      end

      # 성능 분석
      def perform_performance_analysis(modules)
        performance_issues = []
        optimization_score = 100

        modules.each do |module_data|
          next unless module_data[:code]

          module_performance = analyze_module_performance(module_data)
          performance_issues.concat(module_performance[:issues])
          optimization_score -= module_performance[:penalty_points]
        end

        optimization_score = [ optimization_score, 0 ].max

        {
          total_performance_issues: performance_issues.size,
          optimization_score: optimization_score,
          issues_by_category: group_performance_issues(performance_issues),
          detailed_issues: performance_issues
        }
      end

      def analyze_module_performance(module_data)
        issues = []
        penalty_points = 0
        code = module_data[:code]

        # 비효율적인 셀 참조 패턴
        if code.match?(/Cells\(\d+,\s*\d+\)/i) && code.scan(/Cells\(/).size > 10
          issues << {
            type: "performance",
            category: "inefficient_cell_access",
            severity: "warning",
            message: "Multiple individual cell references detected",
            module: module_data[:name],
            recommendation: "Use range references instead of individual cell access"
          }
          penalty_points += 10
        end

        # Select/Activate 사용 검사
        select_count = code.scan(/\.Select\b/i).size
        activate_count = code.scan(/\.Activate\b/i).size

        if select_count > 0 || activate_count > 0
          issues << {
            type: "performance",
            category: "unnecessary_selection",
            severity: "info",
            message: "Unnecessary Select/Activate calls: #{select_count + activate_count}",
            module: module_data[:name],
            recommendation: "Work directly with objects instead of selecting them first"
          }
          penalty_points += (select_count + activate_count) * 2
        end

        # 화면 업데이트 최적화 누락
        unless code.match?(/Application\.ScreenUpdating\s*=\s*False/i)
          if code.match?(/For\s+.+\s+Next/i) # 루프가 있을 때만
            issues << {
              type: "performance",
              category: "screen_updating",
              severity: "info",
              message: "Screen updating not disabled during loops",
              module: module_data[:name],
              recommendation: "Set Application.ScreenUpdating = False before loops and True after"
            }
            penalty_points += 5
          end
        end

        {
          issues: issues,
          penalty_points: penalty_points,
          optimizations: generate_module_optimizations(code)
        }
      end

      # 복잡도 분석
      def calculate_complexity_metrics(modules)
        total_complexity = 0
        module_complexities = []

        modules.each do |module_data|
          next unless module_data[:code]

          complexity = calculate_cyclomatic_complexity(module_data[:code])
          total_complexity += complexity

          module_complexities << {
            module: module_data[:name],
            complexity: complexity,
            level: categorize_complexity(complexity)
          }
        end

        average_complexity = modules.any? ? (total_complexity.to_f / modules.size).round(2) : 0

        {
          total_complexity: total_complexity,
          average_complexity: average_complexity,
          module_complexities: module_complexities,
          complexity_distribution: calculate_complexity_distribution(module_complexities)
        }
      end

      def calculate_cyclomatic_complexity(code)
        # 간소화된 순환 복잡도 계산
        complexity = 1 # 기본 경로

        # 조건문 카운트
        complexity += code.scan(/\bIf\b/i).size
        complexity += code.scan(/\bElseIf\b/i).size
        complexity += code.scan(/\bCase\b/i).size
        complexity += code.scan(/\bFor\b/i).size
        complexity += code.scan(/\bWhile\b/i).size
        complexity += code.scan(/\bDo\b/i).size
        complexity += code.scan(/\bOn Error\b/i).size

        complexity
      end

      # 유틸리티 메서드들
      def determine_module_type(module_obj)
        case module_obj.class.name
        when /sheet/i then "worksheet"
        when /workbook/i then "workbook"
        when /form/i then "userform"
        else "standard"
        end
      end

      def extract_module_code(module_obj)
        # 모듈 객체에서 VBA 코드 추출
        if module_obj.respond_to?(:code_module)
          module_obj.code_module.source_code
        elsif module_obj.respond_to?(:source)
          module_obj.source
        else
          # 폴백: 객체를 문자열로 변환
          module_obj.to_s
        end
      rescue StandardError => e
        Rails.logger.warn("Failed to extract module code: #{e.message}")
        nil
      end

      def count_functions(code)
        code.scan(/Function\s+\w+/i).size
      end

      def count_subroutines(code)
        code.scan(/Sub\s+\w+/i).size
      end

      def extract_functions_and_subs(code)
        functions = []

        # Function 추출
        code.scan(/Function\s+(\w+).*?End\s+Function/im) do |match|
          functions << {
            name: match[0],
            type: "function",
            code: $&
          }
        end

        # Sub 추출
        code.scan(/Sub\s+(\w+).*?End\s+Sub/im) do |match|
          functions << {
            name: match[0],
            type: "sub",
            code: $&
          }
        end

        functions
      end

      def calculate_max_nesting_level(code)
        max_level = 0
        current_level = 0

        code.each_line do |line|
          line_trimmed = line.strip.downcase

          # 시작 키워드
          if line_trimmed.match?(/^(if|for|while|do|with|select)\b/)
            current_level += 1
            max_level = [ max_level, current_level ].max
          end

          # 종료 키워드
          if line_trimmed.match?(/^(end\s+(if|for|while|with|select)|next|wend|loop)\b/)
            current_level = [ current_level - 1, 0 ].max
          end
        end

        max_level
      end

      def categorize_complexity(complexity)
        case complexity
        when 0..VBA_METRICS[:complexity_thresholds][:low]
          "low"
        when VBA_METRICS[:complexity_thresholds][:low]..VBA_METRICS[:complexity_thresholds][:medium]
          "medium"
        when VBA_METRICS[:complexity_thresholds][:medium]..VBA_METRICS[:complexity_thresholds][:high]
          "high"
        else
          "critical"
        end
      end

      def calculate_overall_score(static_analysis, security_analysis, performance_analysis)
        # 가중 평균으로 전체 점수 계산
        weights = {
          code_quality: 0.3,
          security: 0.4,
          performance: 0.3
        }

        code_quality_score = static_analysis[:code_quality_score] || 0
        security_score = 100 - (security_analysis[:risk_score] || 0)
        performance_score = performance_analysis[:optimization_score] || 0

        overall = (
          code_quality_score * weights[:code_quality] +
          security_score * weights[:security] +
          performance_score * weights[:performance]
        ).round(2)

        {
          overall_score: overall,
          breakdown: {
            code_quality: code_quality_score,
            security: security_score,
            performance: performance_score
          },
          grade: calculate_grade(overall)
        }
      end

      def calculate_grade(score)
        case score
        when 90..100 then "A"
        when 80..89 then "B"
        when 70..79 then "C"
        when 60..69 then "D"
        else "F"
        end
      end

      def generate_recommendations(static_analysis, security_analysis, performance_analysis)
        recommendations = []

        # 정적 분석 기반 추천
        if static_analysis[:code_quality_score] < 70
          recommendations << {
            category: "code_quality",
            priority: "high",
            action: "Improve code quality by addressing style and complexity issues",
            impact: "Better maintainability and reduced bugs"
          }
        end

        # 보안 분석 기반 추천
        if security_analysis[:risk_score] > 20
          recommendations << {
            category: "security",
            priority: "critical",
            action: "Address security vulnerabilities immediately",
            impact: "Prevent potential security breaches"
          }
        end

        # 성능 분석 기반 추천
        if performance_analysis[:optimization_score] < 80
          recommendations << {
            category: "performance",
            priority: "medium",
            action: "Optimize VBA code for better performance",
            impact: "Faster execution and better user experience"
          }
        end

        recommendations
      end

      # 결과 포맷팅 메서드들
      def no_vba_result
        {
          success: true,
          has_vba: false,
          message: "No VBA modules detected in this file",
          modules_found: 0
        }
      end

      def error_result(message)
        {
          success: false,
          error: message,
          modules_found: 0
        }
      end

      def group_issues_by_severity(issues)
        issues.group_by { |issue| issue[:severity] }
              .transform_values(&:size)
      end

      def group_security_issues(issues)
        issues.group_by { |issue| issue[:category] }
              .transform_values(&:size)
      end

      def group_performance_issues(issues)
        issues.group_by { |issue| issue[:category] }
              .transform_values(&:size)
      end

      def calculate_complexity_distribution(module_complexities)
        distribution = { low: 0, medium: 0, high: 0, critical: 0 }

        module_complexities.each do |mod|
          distribution[mod[:level].to_sym] += 1
        end

        distribution
      end

      def generate_module_optimizations(code)
        optimizations = []

        # Application.ScreenUpdating 최적화
        if code.match?(/For\s+.+\s+Next/i) && !code.match?(/ScreenUpdating.*False/i)
          optimizations << "Add Application.ScreenUpdating = False before loops"
        end

        # 범위 참조 최적화
        if code.scan(/Cells\(/).size > 5
          optimizations << "Use Range objects instead of individual Cells references"
        end

        # 변수 선언 최적화
        unless code.match?(/Option\s+Explicit/i)
          optimizations << "Add Option Explicit to enforce variable declaration"
        end

        optimizations
      end

      # 메모이제이션으로 성능 최적화
      # memoize :extract_vba_modules, :detect_vba_by_signature
    end
  end
end
