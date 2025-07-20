# frozen_string_literal: true

module ExcelAnalysis
  module Services
    class ErrorDetector
    ERROR_TYPES = {
      formula_error: "Formula Error",
      circular_reference: "Circular Reference",
      missing_reference: "Missing Reference",
      data_validation: "Data Validation Error",
      formatting_issue: "Formatting Issue",
      performance_issue: "Performance Issue"
    }.freeze

    def initialize(file_data)
      @file_data = file_data
      @errors = []
    end

    def detect_all_errors
      return @errors if @file_data[:error]

      @file_data[:worksheets].each do |worksheet|
        detect_formula_errors(worksheet)
        detect_circular_references(worksheet)
        detect_missing_references(worksheet)
        detect_data_validation_errors(worksheet)
        detect_formatting_issues(worksheet)
        detect_performance_issues(worksheet)
      end

      @errors
    end

    private

    def detect_formula_errors(worksheet)
      worksheet[:formulas]&.each do |formula_info|
        formula = formula_info[:formula]
        next unless formula

        # Check for common formula errors
        if formula.include?("#REF!")
          add_error(
            type: :missing_reference,
            worksheet: worksheet[:name],
            address: formula_info[:address],
            message: "Formula contains #REF! error",
            formula: formula,
            severity: "high"
          )
        end

        if formula.include?("#VALUE!")
          add_error(
            type: :formula_error,
            worksheet: worksheet[:name],
            address: formula_info[:address],
            message: "Formula contains #VALUE! error",
            formula: formula,
            severity: "high"
          )
        end

        if formula.include?("#DIV/0!")
          add_error(
            type: :formula_error,
            worksheet: worksheet[:name],
            address: formula_info[:address],
            message: "Formula contains division by zero error",
            formula: formula,
            severity: "medium"
          )
        end

        if formula.include?("#NAME?")
          add_error(
            type: :formula_error,
            worksheet: worksheet[:name],
            address: formula_info[:address],
            message: "Formula contains unrecognized function or name",
            formula: formula,
            severity: "medium"
          )
        end

        # Check for inefficient formulas
        if formula.length > 500
          add_error(
            type: :performance_issue,
            worksheet: worksheet[:name],
            address: formula_info[:address],
            message: "Formula is very long and may impact performance",
            formula: formula.truncate(100),
            severity: "low"
          )
        end

        # Check for volatile functions
        volatile_functions = [ "NOW()", "TODAY()", "RAND()", "RANDBETWEEN(", "INDIRECT(" ]
        volatile_functions.each do |func|
          if formula.upcase.include?(func)
            add_error(
              type: :performance_issue,
              worksheet: worksheet[:name],
              address: formula_info[:address],
              message: "Formula uses volatile function #{func} which may slow down calculation",
              formula: formula,
              severity: "low"
            )
          end
        end
      end
    end

    def detect_circular_references(worksheet)
      formula_refs = {}

      worksheet[:formulas]&.each do |formula_info|
        formula = formula_info[:formula]
        address = formula_info[:address]

        # Extract cell references from formula
        references = extract_cell_references(formula)
        formula_refs[address] = references
      end

      # Check for circular dependencies
      formula_refs.each do |address, references|
        if has_circular_reference?(address, references, formula_refs, [])
          add_error(
            type: :circular_reference,
            worksheet: worksheet[:name],
            address: address,
            message: "Circular reference detected",
            severity: "high"
          )
        end
      end
    end

    def detect_missing_references(worksheet)
      all_addresses = Set.new

      # Collect all cell addresses that contain data
      worksheet[:data]&.each_with_index do |row, row_index|
        row.each_with_index do |cell, col_index|
          if cell[:value] || cell[:formula]
            address = "#{('A'.ord + col_index).chr}#{row_index + 1}"
            all_addresses.add(address)
          end
        end
      end

      # Check if formula references point to empty cells
      worksheet[:formulas]&.each do |formula_info|
        references = extract_cell_references(formula_info[:formula])

        references.each do |ref|
          unless all_addresses.include?(ref)
            add_error(
              type: :missing_reference,
              worksheet: worksheet[:name],
              address: formula_info[:address],
              message: "Formula references empty cell #{ref}",
              formula: formula_info[:formula],
              severity: "medium"
            )
          end
        end
      end
    end

    def detect_data_validation_errors(worksheet)
      # Check for inconsistent data types in columns
      columns = {}

      worksheet[:data]&.each do |row|
        row.each_with_index do |cell, col_index|
          next unless cell[:value]

          columns[col_index] ||= []
          columns[col_index] << {
            value: cell[:value],
            type: determine_data_type(cell[:value]),
            row: cell[:row]
          }
        end
      end

      columns.each do |col_index, cells|
        next if cells.count < 2

        types = cells.map { |c| c[:type] }.uniq
        if types.count > 1 && !types.include?(:mixed)
          col_letter = ("A".ord + col_index).chr
          add_error(
            type: :data_validation,
            worksheet: worksheet[:name],
            address: "Column #{col_letter}",
            message: "Column contains mixed data types: #{types.join(', ')}",
            severity: "medium"
          )
        end
      end
    end

    def detect_formatting_issues(worksheet)
      # Check for worksheets with too many formulas (performance issue)
      if worksheet[:formula_count] > 1000
        add_error(
          type: :performance_issue,
          worksheet: worksheet[:name],
          address: "Worksheet",
          message: "Worksheet has #{worksheet[:formula_count]} formulas, consider optimization",
          severity: "low"
        )
      end

      # Check for very large worksheets
      if worksheet[:row_count] > 50000
        add_error(
          type: :performance_issue,
          worksheet: worksheet[:name],
          address: "Worksheet",
          message: "Worksheet has #{worksheet[:row_count]} rows, may impact performance",
          severity: "medium"
        )
      end
    end

    def detect_performance_issues(worksheet)
      # Already covered in other methods
    end

    def add_error(type:, worksheet:, address:, message:, formula: nil, severity: "medium")
      @errors << {
        type: type,
        type_name: ERROR_TYPES[type],
        worksheet: worksheet,
        address: address,
        message: message,
        formula: formula,
        severity: severity,
        detected_at: Time.current.iso8601
      }
    end

    def extract_cell_references(formula)
      # Simple regex to extract cell references like A1, B2, etc.
      references = formula.scan(/([A-Z]+\d+)/).flatten
      references.uniq
    end

    def has_circular_reference?(current_address, references, all_refs, visited)
      return true if visited.include?(current_address)

      visited_copy = visited + [ current_address ]

      references.each do |ref|
        ref_references = all_refs[ref]
        next unless ref_references

        if ref_references.include?(current_address)
          return true
        end

        if has_circular_reference?(ref, ref_references, all_refs, visited_copy)
          return true
        end
      end

      false
    end

    def determine_data_type(value)
      case value
      when Numeric
        :number
      when Date, Time
        :date
      when TrueClass, FalseClass
        :boolean
      when String
        if value.match?(/^\d+$/)
          :number
        elsif value.match?(/^\d{4}-\d{2}-\d{2}/)
          :date
        else
          :text
        end
      else
        :mixed
      end
    end
    end
  end
end
