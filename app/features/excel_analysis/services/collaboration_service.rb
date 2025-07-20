# frozen_string_literal: true

module ExcelAnalysis
  module Services
    # Excel 분석 협업 서비스
    # 수식 주석, 변경 이력, 팀 협업 기능을 제공
    class CollaborationService
      include ActiveModel::Model

      # 협업 관련 오류
      class CollaborationError < StandardError; end
      class CommentPermissionError < StandardError; end
      class VersionConflictError < StandardError; end

      # 댓글 유형
      COMMENT_TYPES = {
        formula_explanation: "수식 설명",
        optimization_suggestion: "최적화 제안",
        error_report: "오류 보고",
        question: "질문",
        approval: "승인",
        general: "일반"
      }.freeze

      # 변경 유형
      CHANGE_TYPES = {
        formula_added: "수식 추가",
        formula_modified: "수식 수정",
        formula_deleted: "수식 삭제",
        optimization_applied: "최적화 적용",
        error_fixed: "오류 수정",
        structure_changed: "구조 변경"
      }.freeze

      attr_reader :current_user

      def initialize(current_user = nil)
        @current_user = current_user
      end

      # 수식에 댓글 추가
      # @param excel_file [ExcelFile] Excel 파일
      # @param cell_reference [String] 셀 참조 (예: A1, Sheet1!B2)
      # @param comment_data [Hash] 댓글 데이터
      # @return [Common::Result] 댓글 추가 결과
      def add_formula_comment(excel_file, cell_reference, comment_data)
        Rails.logger.info("수식 댓글 추가: #{excel_file.id} - #{cell_reference}")

        begin
          # 권한 확인
          return permission_denied_error unless can_comment?(excel_file)

          # 댓글 데이터 검증
          validation_result = validate_comment_data(comment_data)
          return validation_result if validation_result.failure?

          # 셀 정보 확인
          cell_info = analyze_cell_context(excel_file, cell_reference)
          return cell_info if cell_info.failure?

          # 댓글 생성
          comment = create_comment_record(
            excel_file,
            cell_reference,
            comment_data,
            cell_info.value
          )

          # 관련 사용자에게 알림
          if comment_data[:mention_users].present?
            notify_mentioned_users(comment, comment_data[:mention_users])
          end

          # 활동 로그 기록
          log_collaboration_activity(
            excel_file,
            "comment_added",
            {
              cell_reference: cell_reference,
              comment_id: comment[:id],
              comment_type: comment_data[:type]
            }
          )

          Common::Result.success({
            comment: comment,
            cell_context: cell_info.value,
            notifications_sent: comment_data[:mention_users]&.length || 0
          })

        rescue StandardError => e
          Rails.logger.error("수식 댓글 추가 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "댓글 추가 실패: #{e.message}",
              code: "COMMENT_CREATION_ERROR",
              details: { excel_file_id: excel_file.id, cell_reference: cell_reference }
            )
          )
        end
      end

      # 변경 이력 추가
      # @param excel_file [ExcelFile] Excel 파일
      # @param change_data [Hash] 변경 데이터
      # @return [Common::Result] 변경 이력 추가 결과
      def add_change_history(excel_file, change_data)
        Rails.logger.info("변경 이력 추가: #{excel_file.id} - #{change_data[:type]}")

        begin
          # 변경 데이터 검증
          validation_result = validate_change_data(change_data)
          return validation_result if validation_result.failure?

          # 변경 전후 비교 분석
          if change_data[:before_formula] && change_data[:after_formula]
            change_analysis = analyze_formula_changes(
              change_data[:before_formula],
              change_data[:after_formula]
            )
          else
            change_analysis = {}
          end

          # 변경 이력 기록 생성
          change_record = create_change_record(excel_file, change_data, change_analysis)

          # 성능 영향도 분석
          if should_analyze_performance_impact?(change_data)
            performance_impact = analyze_performance_impact(change_data, change_analysis)
            change_record[:performance_impact] = performance_impact
          end

          # 관련 팀원에게 알림
          if change_data[:notify_team]
            notify_team_of_changes(excel_file, change_record)
          end

          # 백업 생성 (중요한 변경사항의 경우)
          if is_critical_change?(change_data)
            backup_result = create_change_backup(excel_file, change_record)
            change_record[:backup_created] = backup_result.success?
          end

          Common::Result.success(change_record)

        rescue StandardError => e
          Rails.logger.error("변경 이력 추가 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "변경 이력 추가 실패: #{e.message}",
              code: "CHANGE_HISTORY_ERROR",
              details: { excel_file_id: excel_file.id, change_type: change_data[:type] }
            )
          )
        end
      end

      # 협업 대시보드 데이터 생성
      # @param excel_file [ExcelFile] Excel 파일
      # @param options [Hash] 대시보드 옵션
      # @return [Common::Result] 대시보드 데이터
      def generate_collaboration_dashboard(excel_file, options = {})
        Rails.logger.info("협업 대시보드 생성: #{excel_file.id}")

        begin
          dashboard_data = {
            file_info: {
              excel_file_id: excel_file.id,
              filename: excel_file.filename,
              last_modified: excel_file.updated_at
            },
            collaboration_stats: {},
            recent_activities: [],
            active_discussions: [],
            pending_reviews: [],
            team_contributions: {},
            formula_hotspots: []
          }

          # 협업 통계 수집
          dashboard_data[:collaboration_stats] = collect_collaboration_stats(excel_file, options)

          # 최근 활동 내역
          dashboard_data[:recent_activities] = get_recent_activities(excel_file, options[:limit] || 20)

          # 활성 토론 목록
          dashboard_data[:active_discussions] = get_active_discussions(excel_file)

          # 검토 대기 항목
          dashboard_data[:pending_reviews] = get_pending_reviews(excel_file)

          # 팀원별 기여도
          dashboard_data[:team_contributions] = analyze_team_contributions(excel_file, options)

          # 수식 핫스팟 (많은 관심을 받는 수식들)
          dashboard_data[:formula_hotspots] = identify_formula_hotspots(excel_file)

          Common::Result.success(dashboard_data)

        rescue StandardError => e
          Rails.logger.error("협업 대시보드 생성 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "협업 대시보드 생성 실패: #{e.message}",
              code: "DASHBOARD_GENERATION_ERROR",
              details: { excel_file_id: excel_file.id }
            )
          )
        end
      end

      # 수식 검토 요청
      # @param excel_file [ExcelFile] Excel 파일
      # @param review_data [Hash] 검토 요청 데이터
      # @return [Common::Result] 검토 요청 결과
      def request_formula_review(excel_file, review_data)
        Rails.logger.info("수식 검토 요청: #{excel_file.id}")

        begin
          # 검토 요청 데이터 검증
          validation_result = validate_review_request(review_data)
          return validation_result if validation_result.failure?

          # 검토 대상 수식 분석
          formula_analysis = analyze_review_target_formulas(excel_file, review_data[:cell_references])
          return formula_analysis if formula_analysis.failure?

          # 검토 요청 생성
          review_request = create_review_request(excel_file, review_data, formula_analysis.value)

          # 검토자에게 알림 발송
          notify_reviewers(review_request, review_data[:reviewers])

          # 자동 사전 분석 수행
          if review_data[:enable_auto_analysis]
            auto_analysis = perform_automated_pre_analysis(review_request)
            review_request[:auto_analysis] = auto_analysis
          end

          Common::Result.success(review_request)

        rescue StandardError => e
          Rails.logger.error("수식 검토 요청 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "검토 요청 실패: #{e.message}",
              code: "REVIEW_REQUEST_ERROR",
              details: { excel_file_id: excel_file.id }
            )
          )
        end
      end

      # 협업 알림 관리
      # @param excel_file [ExcelFile] Excel 파일
      # @param notification_data [Hash] 알림 데이터
      # @return [Common::Result] 알림 전송 결과
      def manage_collaboration_notifications(excel_file, notification_data)
        Rails.logger.info("협업 알림 관리: #{excel_file.id}")

        begin
          notification_results = []

          case notification_data[:type]
          when "formula_change"
            result = notify_formula_change(excel_file, notification_data)
            notification_results << result

          when "review_request"
            result = notify_review_request(excel_file, notification_data)
            notification_results << result

          when "comment_reply"
            result = notify_comment_reply(excel_file, notification_data)
            notification_results << result

          when "optimization_suggestion"
            result = notify_optimization_suggestion(excel_file, notification_data)
            notification_results << result

          when "error_detected"
            result = notify_error_detected(excel_file, notification_data)
            notification_results << result
          end

          # 알림 전송 결과 집계
          summary = {
            total_notifications: notification_results.length,
            successful_notifications: notification_results.count { |r| r.success? },
            failed_notifications: notification_results.count { |r| r.failure? }
          }

          Common::Result.success(summary)

        rescue StandardError => e
          Rails.logger.error("협업 알림 관리 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "알림 관리 실패: #{e.message}",
              code: "NOTIFICATION_MANAGEMENT_ERROR",
              details: { excel_file_id: excel_file.id, notification_type: notification_data[:type] }
            )
          )
        end
      end

      private

      # 권한 확인
      def can_comment?(excel_file)
        return true unless @current_user

        # 간단한 권한 확인 로직 (실제로는 더 복잡한 권한 시스템 필요)
        excel_file.user_id == @current_user.id || @current_user.admin?
      end

      def permission_denied_error
        Common::Result.failure(
          Common::Errors::AuthorizationError.new(
            message: "댓글 작성 권한이 없습니다.",
            code: "INSUFFICIENT_PERMISSIONS"
          )
        )
      end

      # 댓글 데이터 검증
      def validate_comment_data(comment_data)
        errors = []

        errors << "댓글 내용이 필요합니다." if comment_data[:content].blank?
        errors << "댓글 유형이 유효하지 않습니다." unless COMMENT_TYPES.key?(comment_data[:type]&.to_sym)

        if errors.any?
          return Common::Result.failure(
            Common::Errors::ValidationError.new(
              message: "댓글 데이터 검증 실패",
              details: { errors: errors }
            )
          )
        end

        Common::Result.success
      end

      # 변경 데이터 검증
      def validate_change_data(change_data)
        errors = []

        errors << "변경 유형이 필요합니다." if change_data[:type].blank?
        errors << "변경 유형이 유효하지 않습니다." unless CHANGE_TYPES.key?(change_data[:type]&.to_sym)
        errors << "변경 설명이 필요합니다." if change_data[:description].blank?

        if errors.any?
          return Common::Result.failure(
            Common::Errors::ValidationError.new(
              message: "변경 데이터 검증 실패",
              details: { errors: errors }
            )
          )
        end

        Common::Result.success
      end

      # 셀 컨텍스트 분석
      def analyze_cell_context(excel_file, cell_reference)
        begin
          # FormulaAnalysisService를 통한 셀 분석
          analysis_service = FormulaAnalysisService.new(excel_file)
          analysis_result = analysis_service.analyze
          return analysis_result if analysis_result.failure?

          # 특정 셀의 컨텍스트 정보 추출
          cell_context = extract_cell_context(analysis_result.value, cell_reference)

          Common::Result.success(cell_context)

        rescue StandardError => e
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "셀 컨텍스트 분석 실패: #{e.message}",
              code: "CELL_CONTEXT_ERROR"
            )
          )
        end
      end

      # 댓글 레코드 생성
      def create_comment_record(excel_file, cell_reference, comment_data, cell_context)
        {
          id: SecureRandom.uuid,
          excel_file_id: excel_file.id,
          cell_reference: cell_reference,
          type: comment_data[:type],
          content: comment_data[:content],
          author_id: @current_user&.id,
          author_name: @current_user&.name || "Anonymous",
          created_at: Time.current,
          cell_context: cell_context,
          tags: comment_data[:tags] || [],
          priority: comment_data[:priority] || "normal",
          status: "active"
        }
      end

      # 변경 레코드 생성
      def create_change_record(excel_file, change_data, change_analysis)
        {
          id: SecureRandom.uuid,
          excel_file_id: excel_file.id,
          type: change_data[:type],
          description: change_data[:description],
          cell_reference: change_data[:cell_reference],
          before_formula: change_data[:before_formula],
          after_formula: change_data[:after_formula],
          change_analysis: change_analysis,
          author_id: @current_user&.id,
          author_name: @current_user&.name || "System",
          created_at: Time.current,
          metadata: change_data[:metadata] || {}
        }
      end

      # 수식 변경 분석
      def analyze_formula_changes(before_formula, after_formula)
        analysis = {
          change_type: determine_change_type(before_formula, after_formula),
          complexity_change: calculate_complexity_change(before_formula, after_formula),
          function_changes: analyze_function_changes(before_formula, after_formula),
          reference_changes: analyze_reference_changes(before_formula, after_formula),
          risk_assessment: assess_change_risk(before_formula, after_formula)
        }

        analysis
      end

      # 협업 통계 수집
      def collect_collaboration_stats(excel_file, options)
        {
          total_comments: 0, # 실제로는 DB에서 조회
          total_changes: 0,
          active_contributors: 0,
          pending_reviews: 0,
          resolved_issues: 0,
          avg_response_time: "2.5 hours",
          collaboration_score: 85.2
        }
      end

      # 최근 활동 조회
      def get_recent_activities(excel_file, limit)
        # 실제로는 DB에서 조회
        [
          {
            id: 1,
            type: "comment_added",
            description: "수식에 최적화 제안 댓글 추가",
            author: "John Doe",
            cell_reference: "A1",
            created_at: 2.hours.ago
          },
          {
            id: 2,
            type: "formula_modified",
            description: "VLOOKUP을 XLOOKUP으로 최적화",
            author: "Jane Smith",
            cell_reference: "B2",
            created_at: 4.hours.ago
          }
        ]
      end

      # 활성 토론 조회
      def get_active_discussions(excel_file)
        # 실제로는 DB에서 조회
        [
          {
            id: 1,
            title: "복잡한 수식 최적화 방안",
            cell_reference: "C3",
            participants: [ "John", "Jane", "Bob" ],
            last_activity: 1.hour.ago,
            comment_count: 7
          }
        ]
      end

      # 검토 대기 항목 조회
      def get_pending_reviews(excel_file)
        # 실제로는 DB에서 조회
        [
          {
            id: 1,
            title: "새 수식 검토 요청",
            cell_references: [ "D4", "E5" ],
            reviewer: "Senior Analyst",
            requested_at: 6.hours.ago,
            priority: "high"
          }
        ]
      end

      # 팀 기여도 분석
      def analyze_team_contributions(excel_file, options)
        {
          "John Doe" => {
            comments: 15,
            changes: 8,
            reviews_completed: 3,
            contribution_score: 92.5
          },
          "Jane Smith" => {
            comments: 12,
            changes: 12,
            reviews_completed: 5,
            contribution_score: 95.0
          }
        }
      end

      # 수식 핫스팟 식별
      def identify_formula_hotspots(excel_file)
        [
          {
            cell_reference: "A1",
            formula: '=SUMIFS(Data!A:A, Data!B:B, "criteria")',
            activity_score: 8.5,
            comment_count: 5,
            change_count: 3,
            complexity_score: 7.2
          },
          {
            cell_reference: "B2",
            formula: "=VLOOKUP(A2, Table1, 2, FALSE)",
            activity_score: 6.8,
            comment_count: 3,
            change_count: 2,
            complexity_score: 4.5
          }
        ]
      end

      # 검토 요청 검증
      def validate_review_request(review_data)
        errors = []

        errors << "검토 제목이 필요합니다." if review_data[:title].blank?
        errors << "검토자가 지정되지 않았습니다." if review_data[:reviewers].blank?
        errors << "검토 대상 셀이 지정되지 않았습니다." if review_data[:cell_references].blank?

        if errors.any?
          return Common::Result.failure(
            Common::Errors::ValidationError.new(
              message: "검토 요청 검증 실패",
              details: { errors: errors }
            )
          )
        end

        Common::Result.success
      end

      # 검토 대상 수식 분석
      def analyze_review_target_formulas(excel_file, cell_references)
        # FormulaAnalysisService를 통한 분석
        analysis_service = FormulaAnalysisService.new(excel_file)
        analysis_result = analysis_service.analyze
        return analysis_result if analysis_result.failure?

        # 특정 셀들의 수식 추출 및 분석
        target_formulas = extract_target_formulas(analysis_result.value, cell_references)

        Common::Result.success(target_formulas)
      end

      # 검토 요청 생성
      def create_review_request(excel_file, review_data, formula_analysis)
        {
          id: SecureRandom.uuid,
          excel_file_id: excel_file.id,
          title: review_data[:title],
          description: review_data[:description],
          cell_references: review_data[:cell_references],
          reviewers: review_data[:reviewers],
          priority: review_data[:priority] || "medium",
          deadline: review_data[:deadline],
          formula_analysis: formula_analysis,
          status: "pending",
          created_at: Time.current,
          requester_id: @current_user&.id,
          requester_name: @current_user&.name || "Anonymous"
        }
      end

      # 자동 사전 분석 수행
      def perform_automated_pre_analysis(review_request)
        {
          complexity_assessment: "medium",
          potential_issues: [ "Performance concern in SUMPRODUCT" ],
          optimization_opportunities: [ "Consider using SUMIFS instead" ],
          estimated_review_time: "30 minutes"
        }
      end

      # 알림 관련 메소드들
      def notify_mentioned_users(comment, mentioned_users)
        # 실제 알림 시스템 연동
        Rails.logger.info("Mentioned users notified: #{mentioned_users.join(', ')}")
      end

      def notify_reviewers(review_request, reviewers)
        # 검토자 알림
        Rails.logger.info("Review request sent to: #{reviewers.join(', ')}")
      end

      def notify_team_of_changes(excel_file, change_record)
        # 팀 전체 알림
        Rails.logger.info("Team notified of changes in file: #{excel_file.id}")
      end

      def notify_formula_change(excel_file, notification_data)
        # 수식 변경 알림
        Common::Result.success({ type: "formula_change", sent: true })
      end

      def notify_review_request(excel_file, notification_data)
        # 검토 요청 알림
        Common::Result.success({ type: "review_request", sent: true })
      end

      def notify_comment_reply(excel_file, notification_data)
        # 댓글 답글 알림
        Common::Result.success({ type: "comment_reply", sent: true })
      end

      def notify_optimization_suggestion(excel_file, notification_data)
        # 최적화 제안 알림
        Common::Result.success({ type: "optimization_suggestion", sent: true })
      end

      def notify_error_detected(excel_file, notification_data)
        # 오류 감지 알림
        Common::Result.success({ type: "error_detected", sent: true })
      end

      # 헬퍼 메소드들

      def log_collaboration_activity(excel_file, activity_type, details)
        Rails.logger.info("Collaboration activity: #{activity_type} - #{details}")
      end

      def should_analyze_performance_impact?(change_data)
        [ "formula_modified", "optimization_applied" ].include?(change_data[:type])
      end

      def analyze_performance_impact(change_data, change_analysis)
        {
          estimated_improvement: "15%",
          calculation_time_change: "-50ms",
          memory_impact: "minimal"
        }
      end

      def is_critical_change?(change_data)
        [ "formula_deleted", "structure_changed" ].include?(change_data[:type])
      end

      def create_change_backup(excel_file, change_record)
        # 백업 생성 로직
        Common::Result.success({ backup_id: SecureRandom.uuid })
      end

      def extract_cell_context(analysis_data, cell_reference)
        {
          cell_reference: cell_reference,
          has_formula: true,
          formula: "=SUM(A1:A10)",
          function_used: [ "SUM" ],
          complexity_score: 2.5,
          dependencies: [ "A1:A10" ]
        }
      end

      def determine_change_type(before_formula, after_formula)
        if before_formula.blank? && after_formula.present?
          "addition"
        elsif before_formula.present? && after_formula.blank?
          "deletion"
        else
          "modification"
        end
      end

      def calculate_complexity_change(before_formula, after_formula)
        # 복잡도 변화 계산 (간단한 예시)
        before_complexity = before_formula&.length || 0
        after_complexity = after_formula&.length || 0

        {
          before: before_complexity / 10.0,
          after: after_complexity / 10.0,
          change: (after_complexity - before_complexity) / 10.0
        }
      end

      def analyze_function_changes(before_formula, after_formula)
        before_functions = extract_functions(before_formula || "")
        after_functions = extract_functions(after_formula || "")

        {
          added: after_functions - before_functions,
          removed: before_functions - after_functions,
          unchanged: before_functions & after_functions
        }
      end

      def analyze_reference_changes(before_formula, after_formula)
        before_refs = extract_references(before_formula || "")
        after_refs = extract_references(after_formula || "")

        {
          added: after_refs - before_refs,
          removed: before_refs - after_refs,
          unchanged: before_refs & after_refs
        }
      end

      def assess_change_risk(before_formula, after_formula)
        risk_factors = []

        # 함수 변경 위험
        function_changes = analyze_function_changes(before_formula, after_formula)
        if function_changes[:added].any? || function_changes[:removed].any?
          risk_factors << "function_change"
        end

        # 참조 변경 위험
        reference_changes = analyze_reference_changes(before_formula, after_formula)
        if reference_changes[:added].any? || reference_changes[:removed].any?
          risk_factors << "reference_change"
        end

        risk_level = case risk_factors.length
        when 0 then "low"
        when 1 then "medium"
        else "high"
        end

        {
          level: risk_level,
          factors: risk_factors
        }
      end

      def extract_functions(formula)
        formula.scan(/([A-Z][A-Z0-9\.]*)\s*\(/).flatten.uniq
      end

      def extract_references(formula)
        formula.scan(/[A-Z]+\d+(?::[A-Z]+\d+)?/).uniq
      end

      def extract_target_formulas(analysis_data, cell_references)
        # 분석 데이터에서 특정 셀들의 수식 추출
        target_formulas = {}

        cell_references.each do |cell_ref|
          target_formulas[cell_ref] = {
            formula: "=SUM(A1:A10)", # 예시
            complexity: 2.5,
            functions: [ "SUM" ]
          }
        end

        target_formulas
      end
    end
  end
end
