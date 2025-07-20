# frozen_string_literal: true

module ExcelModification
  module Services
    # Service to modify Excel files based on AI suggestions and user requests
    # Follows Single Responsibility Principle - handles Excel file modifications only
    class ExcelModificationService
      include ActiveModel::Model

      attr_reader :formula_converter, :formula_engine

      def initialize
        @formula_converter = AiToFormulaConverter.new
        @formula_engine = FormulaEngineClient.instance
      end

      # Modify Excel file based on AI suggestions and screenshot context
      def modify_with_ai_suggestions(excel_file:, screenshot:, user_request:, user:, tier: :balanced)
        # Validate inputs
        return Common::Result.failure("Excel file not found") unless excel_file
        return Common::Result.failure("User request cannot be blank") if user_request.blank?

        begin
          # 1. Analyze screenshot with user request
          analysis_result = analyze_modification_request(
            excel_file: excel_file,
            screenshot: screenshot,
            user_request: user_request,
            tier: tier
          )
          return analysis_result if analysis_result.failure?

          # 2. Convert AI suggestions to Excel modifications
          modifications = analysis_result.value[:modifications]

          # 3. Apply modifications to Excel file
          modified_file_result = apply_modifications(
            excel_file: excel_file,
            modifications: modifications,
            user: user
          )

          return modified_file_result if modified_file_result.failure?

          # 4. Create new version of the file
          new_file = create_modified_version(
            original_file: excel_file,
            modified_data: modified_file_result.value,
            user: user,
            description: user_request
          )

          Common::Result.success({
            modified_file: new_file,
            modifications_applied: modifications,
            download_url: download_url(new_file),
            preview: generate_preview(new_file)
          })

        rescue StandardError => e
          Rails.logger.error("Excel modification failed: #{e.message}")
          Common::Result.failure("Failed to modify Excel file: #{e.message}")
        end
      end

      private

      def analyze_modification_request(excel_file:, screenshot:, user_request:, tier: :balanced)
        # Use MultimodalCoordinatorService for comprehensive analysis
        coordinator = AiIntegration::Services::MultimodalCoordinatorService.new(
          user: User.system_user,
          default_tier: tier
        )

        # Get file metadata for context
        file_context = {
          filename: excel_file.original_name,
          file_size: excel_file.file_size,
          sheet_count: excel_file.metadata&.dig("sheet_count"),
          has_formulas: excel_file.metadata&.dig("has_formulas"),
          analysis_data: excel_file.latest_analysis&.structured_analysis
        }

        prompt = build_modification_prompt(user_request, file_context)

        result = coordinator.analyze_excel_screenshot(
          image_data: screenshot,
          context: {
            specific_question: user_request,
            excel_file_metadata: file_context
          }
        )

        return Common::Result.failure(result[:error]) unless result[:success]

        # Extract modifications from AI response
        modifications = extract_modifications(result[:analysis])

        Common::Result.success({
          modifications: modifications,
          confidence: result[:confidence_score],
          explanation: result[:analysis]
        })
      end

      def build_modification_prompt(user_request, file_context)
        <<~PROMPT
          사용자가 Excel 파일을 수정하고 싶어합니다.

          사용자 요청: "#{user_request}"

          파일 정보:
          - 파일명: #{file_context[:filename]}
          - 시트 수: #{file_context[:sheet_count] || '알 수 없음'}
          - 수식 포함: #{file_context[:has_formulas] ? '예' : '아니오'}

          스크린샷을 분석하고 다음 형식으로 수정 사항을 제안해주세요:

          ```json
          {
            "modifications": [
              {
                "type": "formula|value|format|structure",
                "sheet": "시트명",
                "cell": "셀 주소",
                "current_value": "현재 값",
                "new_value": "새로운 값",
                "formula": "=수식 (해당하는 경우)",
                "explanation": "변경 이유"
              }
            ],
            "summary": "전체 수정 사항 요약"
          }
          ```

          중요:#{' '}
          1. 정확한 셀 주소를 지정하세요
          2. 수식은 영어 함수명을 사용하세요
          3. 사용자 요청을 정확히 반영하세요
        PROMPT
      end

      def extract_modifications(ai_response)
        # Parse JSON from AI response
        json_match = ai_response.match(/```json\s*(\{.*?\})\s*```/m)

        if json_match
          begin
            data = JSON.parse(json_match[1])
            return data["modifications"] || []
          rescue JSON::ParserError
            Rails.logger.warn("Failed to parse modifications from AI response")
          end
        end

        # Fallback: Try to extract basic modifications
        []
      end

      def apply_modifications(excel_file:, modifications:, user:)
        # Read the Excel file
        file_path = excel_file.file.path
        workbook = Roo::Spreadsheet.open(file_path)

        # Create a new workbook for modifications
        package = Axlsx::Package.new

        # Copy sheets and apply modifications
        workbook.sheets.each do |sheet_name|
          workbook.default_sheet = sheet_name
          worksheet = package.workbook.add_worksheet(name: sheet_name)

          # Copy existing data
          (workbook.first_row..workbook.last_row).each do |row_idx|
            row_data = []
            (workbook.first_column..workbook.last_column).each do |col_idx|
              cell_value = workbook.cell(row_idx, col_idx)
              row_data << cell_value
            end
            worksheet.add_row row_data
          end

          # Apply modifications for this sheet
          sheet_modifications = modifications.select { |m| m["sheet"] == sheet_name }
          apply_sheet_modifications(worksheet, sheet_modifications)
        end

        # Generate modified file
        stream = StringIO.new
        package.serialize(stream)

        Common::Result.success({
          file_data: stream.string,
          content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
          modifications_count: modifications.size
        })

      rescue StandardError => e
        Rails.logger.error("Failed to apply modifications: #{e.message}")
        Common::Result.failure("Failed to apply modifications: #{e.message}")
      end

      def apply_sheet_modifications(worksheet, modifications)
        modifications.each do |mod|
          cell_ref = mod["cell"]
          next unless cell_ref

          # Convert cell reference to row/col indices
          col_letter, row_num = cell_ref.match(/([A-Z]+)(\d+)/).captures
          col_idx = col_letter.chars.inject(0) { |sum, char| sum * 26 + (char.ord - "A".ord + 1) } - 1
          row_idx = row_num.to_i - 1

          # Apply modification based on type
          case mod["type"]
          when "formula"
            # Validate formula first
            if mod["formula"] && @formula_engine.validate_formula(mod["formula"]).success?
              worksheet.rows[row_idx].cells[col_idx].value = mod["formula"]
            end
          when "value"
            worksheet.rows[row_idx].cells[col_idx].value = mod["new_value"]
          when "format"
            # Apply formatting if specified
            apply_cell_formatting(worksheet.rows[row_idx].cells[col_idx], mod["format_options"])
          end
        end
      rescue StandardError => e
        Rails.logger.error("Failed to apply modification: #{e.message}")
      end

      def apply_cell_formatting(cell, format_options)
        return unless format_options

        # Apply number format
        if format_options["number_format"]
          cell.style.num_fmt = format_options["number_format"]
        end

        # Apply font styling
        if format_options["bold"]
          cell.style.font.b = true
        end

        # Apply background color
        if format_options["bg_color"]
          cell.style.fill = Axlsx::PatternFill.new(
            patternType: "solid",
            fgColor: format_options["bg_color"]
          )
        end
      end

      def create_modified_version(original_file:, modified_data:, user:, description:)
        # Generate filename
        timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
        original_name = File.basename(original_file.original_name, ".*")
        extension = File.extname(original_file.original_name)
        new_filename = "#{original_name}_modified_#{timestamp}#{extension}"

        # Create new Excel file record
        new_file = user.excel_files.build(
          original_name: new_filename,
          file_size: modified_data[:file_data].bytesize,
          content_type: modified_data[:content_type],
          status: "completed",
          metadata: {
            parent_file_id: original_file.id,
            modification_description: description,
            modifications_count: modified_data[:modifications_count],
            modified_at: Time.current
          }
        )

        # Attach the file
        new_file.file.attach(
          io: StringIO.new(modified_data[:file_data]),
          filename: new_filename,
          content_type: modified_data[:content_type]
        )

        new_file.save!
        new_file
      end

      def download_url(file)
        Rails.application.routes.url_helpers.rails_blob_path(
          file.file,
          disposition: "attachment",
          only_path: true
        )
      end

      def generate_preview(file)
        # Generate a simple preview of the modified file
        {
          filename: file.original_name,
          size: ActiveSupport::NumberHelper.number_to_human_size(file.file_size),
          modified_at: file.created_at.strftime("%Y-%m-%d %H:%M"),
          modifications: file.metadata["modifications_count"]
        }
      end
    end
  end
end
