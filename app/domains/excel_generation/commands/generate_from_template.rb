# frozen_string_literal: true

module ExcelGeneration
  module Commands
    # Command for generating Excel from template
    # Follows Single Responsibility Principle (SRP)
    class GenerateFromTemplate < Shared::Contracts::Command
      include ActiveModel::Attributes

      attribute :template_name, :string
      attribute :template_data, default: {}
      attribute :user_id, :integer
      attribute :customizations, default: {}
      attribute :output_filename, :string

      validates :template_name, :user_id, presence: true
      validates :template_data, presence: true

      def initialize(dependencies = {})
        super()
        @template_repository = dependencies[:template_repository] || ExcelGeneration::Repositories::TemplateRepository.new
        @generator_factory = dependencies[:generator_factory] || ExcelGeneration::Factories::GeneratorFactory.new
        @file_repository = dependencies[:file_repository] || ExcelGeneration::Repositories::GeneratedFileRepository.new
      end

      private

      def execute
        # Validate template exists
        template = @template_repository.find_by_name(template_name)
        return Shared::Types::Result.failure(error: "Template not found") unless template

        # Validate template data structure
        validation_result = validate_template_data(template, template_data)
        return validation_result if validation_result.failure?

        # Generate Excel file
        generator = @generator_factory.create(:template_based)
        generation_result = generator.generate(
          template: template,
          data: template_data,
          customizations: customizations,
          filename: output_filename
        )

        return generation_result if generation_result.failure?

        # Save file metadata
        file_record = @file_repository.create_from_generation(
          user_id: user_id,
          generation_result: generation_result.value,
          template_name: template_name
        )

        Shared::Types::Result.success(
          value: {
            file_id: file_record.id,
            file_path: generation_result.value[:file_path],
            file_size: generation_result.value[:file_size],
            generation_time: generation_result.value[:generation_time]
          }
        )
      rescue => error
        Shared::Types::Result.failure(error: "Generation failed: #{error.message}")
      end

      def validate_template_data(template, data)
        validator = ExcelGeneration::Validators::TemplateDataValidator.new(template, data)

        if validator.valid?
          Shared::Types::Result.success
        else
          Shared::Types::Result.failure(error: validator.errors.full_messages.join(", "))
        end
      end
    end
  end
end
