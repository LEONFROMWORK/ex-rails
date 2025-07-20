# frozen_string_literal: true

module ExcelGeneration
  module Commands
    # Command for generating Excel from conversation
    # Follows Single Responsibility Principle (SRP)
    class GenerateFromConversation < Shared::Contracts::Command
      include ActiveModel::Attributes

      attribute :conversation_data, default: {}
      attribute :user_id, :integer
      attribute :output_filename, :string

      validates :conversation_data, :user_id, presence: true
      validate :validate_conversation_structure

      def initialize(dependencies = {})
        super()
        @conversation_analyzer = dependencies[:conversation_analyzer] || ExcelGeneration::Services::ConversationAnalyzer.new
        @template_designer = dependencies[:template_designer] || ExcelGeneration::Services::TemplateDesigner.new
        @generator_factory = dependencies[:generator_factory] || ExcelGeneration::Factories::GeneratorFactory.new
        @file_repository = dependencies[:file_repository] || ExcelGeneration::Repositories::GeneratedFileRepository.new
      end

      private

      def execute
        # Analyze conversation to extract requirements
        analysis_result = @conversation_analyzer.analyze(conversation_data)
        return analysis_result if analysis_result.failure?

        requirements = analysis_result.value

        # Design template structure based on requirements
        design_result = @template_designer.design_from_requirements(requirements)
        return design_result if design_result.failure?

        template_structure = design_result.value

        # Generate Excel file
        generator = @generator_factory.create(:conversation_based)
        generation_result = generator.generate(
          template_structure: template_structure,
          requirements: requirements,
          filename: output_filename
        )

        return generation_result if generation_result.failure?

        # Save file metadata
        file_record = @file_repository.create_from_generation(
          user_id: user_id,
          generation_result: generation_result.value,
          conversation_data: conversation_data
        )

        Shared::Types::Result.success(
          value: {
            file_id: file_record.id,
            file_path: generation_result.value[:file_path],
            file_size: generation_result.value[:file_size],
            generation_time: generation_result.value[:generation_time],
            template_structure: template_structure,
            requirements_analyzed: requirements
          }
        )
      rescue => error
        Shared::Types::Result.failure(error: "Generation failed: #{error.message}")
      end

      def validate_conversation_structure
        return if conversation_data.blank?

        unless conversation_data.is_a?(Hash) && conversation_data[:messages].is_a?(Array)
          errors.add(:conversation_data, "must contain messages array")
        end

        if conversation_data[:messages].empty?
          errors.add(:conversation_data, "must contain at least one message")
        end
      end
    end
  end
end
