# frozen_string_literal: true

module ExcelAnalysis
  module Commands
    # Command for analyzing Excel files
    # Follows Single Responsibility Principle (SRP) and Command Pattern
    class AnalyzeExcelFile < Shared::Contracts::Command
      include ActiveModel::Attributes

      attribute :file_id, :integer
      attribute :user_id, :integer
      attribute :analysis_type, :string, default: "comprehensive"
      attribute :options, default: {}

      validates :file_id, :user_id, presence: true
      validates :analysis_type, inclusion: { in: %w[comprehensive error_detection vba_analysis performance] }

      def initialize(dependencies = {})
        super()
        @file_repository = dependencies[:file_repository] || ExcelAnalysis::Repositories::FileRepository.new
        @analyzer_factory = dependencies[:analyzer_factory] || ExcelAnalysis::Factories::AnalyzerFactory.new
        @analysis_repository = dependencies[:analysis_repository] || ExcelAnalysis::Repositories::AnalysisRepository.new
      end

      private

      # Single responsibility: orchestrate Excel analysis workflow
      def execute
        file = @file_repository.find_by_id_and_user(file_id, user_id)
        return Result.failure(error: "File not found") unless file

        analyzer = @analyzer_factory.create(analysis_type)
        analysis_result = analyzer.analyze(file.file_path, options)

        return analysis_result if analysis_result.failure?

        analysis_record = @analysis_repository.create_from_result(
          file: file,
          user_id: user_id,
          result: analysis_result.value
        )

        Result.success(
          value: {
            analysis_id: analysis_record.id,
            summary: analysis_result.value[:summary],
            errors_found: analysis_result.value[:errors]&.count || 0
          }
        )
      end
    end
  end
end
