# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExcelAnalysis::Services::ErrorDetector do
  let(:sample_file_data) do
    {
      worksheets: [
        {
          name: 'Sheet1',
          data: [
            [
              { value: 'Name', row: 0, col: 0 },
              { value: 'Amount', row: 0, col: 1 },
              { value: 'Formula', row: 0, col: 2 }
            ],
            [
              { value: 'John', row: 1, col: 0 },
              { value: 100, row: 1, col: 1 },
              { value: nil, row: 1, col: 2 }
            ],
            [
              { value: 'Jane', row: 2, col: 0 },
              { value: 'invalid', row: 2, col: 1 },
              { value: nil, row: 2, col: 2 }
            ]
          ],
          formulas: [
            {
              formula: '=B1+B2',
              address: 'C1',
              row: 0,
              col: 2
            },
            {
              formula: '=B2/0',
              address: 'C2',
              row: 1,
              col: 2
            },
            {
              formula: '=#REF!+B3',
              address: 'C3',
              row: 2,
              col: 2
            }
          ],
          formula_count: 3,
          row_count: 3
        }
      ]
    }
  end

  let(:detector) { described_class.new(sample_file_data) }

  describe '#detect_all_errors' do
    it 'detects all types of errors' do
      errors = detector.detect_all_errors

      expect(errors).not_to be_empty
      error_types = errors.map { |e| e[:type] }.uniq
      expect(error_types).to include(:formula_error, :missing_reference, :data_validation)
    end

    it 'returns empty array when file data has error' do
      error_data = { error: 'File could not be processed' }
      detector = described_class.new(error_data)

      errors = detector.detect_all_errors
      expect(errors).to be_empty
    end
  end

  describe '#detect_formula_errors' do
    it 'detects division by zero errors' do
      errors = detector.detect_all_errors
      div_zero_errors = errors.select { |e| e[:message].include?('division by zero') }

      expect(div_zero_errors).not_to be_empty
      expect(div_zero_errors.first[:severity]).to eq('medium')
      expect(div_zero_errors.first[:address]).to eq('C2')
    end

    it 'detects #REF! errors' do
      errors = detector.detect_all_errors
      ref_errors = errors.select { |e| e[:message].include?('#REF!') }

      expect(ref_errors).not_to be_empty
      expect(ref_errors.first[:severity]).to eq('high')
      expect(ref_errors.first[:type]).to eq(:missing_reference)
    end

    it 'detects #VALUE! errors' do
      file_data_with_value_error = sample_file_data.dup
      file_data_with_value_error[:worksheets][0][:formulas] << {
        formula: '=#VALUE!',
        address: 'D1',
        row: 0,
        col: 3
      }

      detector = described_class.new(file_data_with_value_error)
      errors = detector.detect_all_errors
      value_errors = errors.select { |e| e[:message].include?('#VALUE!') }

      expect(value_errors).not_to be_empty
      expect(value_errors.first[:type]).to eq(:formula_error)
    end

    it 'detects long formulas as performance issues' do
      long_formula = '=' + 'A1+' * 200 + 'A1' # Very long formula
      file_data_with_long_formula = sample_file_data.dup
      file_data_with_long_formula[:worksheets][0][:formulas] << {
        formula: long_formula,
        address: 'D1',
        row: 0,
        col: 3
      }

      detector = described_class.new(file_data_with_long_formula)
      errors = detector.detect_all_errors
      performance_errors = errors.select { |e| e[:type] == :performance_issue && e[:message].include?('very long') }

      expect(performance_errors).not_to be_empty
    end

    it 'detects volatile functions' do
      file_data_with_volatile = sample_file_data.dup
      file_data_with_volatile[:worksheets][0][:formulas] << {
        formula: '=NOW()+RAND()',
        address: 'D1',
        row: 0,
        col: 3
      }

      detector = described_class.new(file_data_with_volatile)
      errors = detector.detect_all_errors
      volatile_errors = errors.select { |e| e[:message].include?('volatile function') }

      expect(volatile_errors.size).to be >= 2 # NOW() and RAND()
    end
  end

  describe '#detect_circular_references' do
    it 'detects simple circular references' do
      circular_data = {
        worksheets: [
          {
            name: 'Sheet1',
            data: [],
            formulas: [
              { formula: '=B1', address: 'A1', row: 0, col: 0 },
              { formula: '=A1', address: 'B1', row: 0, col: 1 }
            ]
          }
        ]
      }

      detector = described_class.new(circular_data)
      errors = detector.detect_all_errors
      circular_errors = errors.select { |e| e[:type] == :circular_reference }

      expect(circular_errors).not_to be_empty
      expect(circular_errors.first[:severity]).to eq('high')
    end

    it 'detects complex circular references' do
      complex_circular_data = {
        worksheets: [
          {
            name: 'Sheet1',
            data: [],
            formulas: [
              { formula: '=B1', address: 'A1', row: 0, col: 0 },
              { formula: '=C1', address: 'B1', row: 0, col: 1 },
              { formula: '=A1', address: 'C1', row: 0, col: 2 }
            ]
          }
        ]
      }

      detector = described_class.new(complex_circular_data)
      errors = detector.detect_all_errors
      circular_errors = errors.select { |e| e[:type] == :circular_reference }

      expect(circular_errors).not_to be_empty
    end
  end

  describe '#detect_data_validation_errors' do
    it 'detects mixed data types in columns' do
      errors = detector.detect_all_errors
      validation_errors = errors.select { |e| e[:type] == :data_validation }

      expect(validation_errors).not_to be_empty
      mixed_type_error = validation_errors.find { |e| e[:message].include?('mixed data types') }
      expect(mixed_type_error).to be_present
    end

    it 'handles columns with consistent data types' do
      consistent_data = {
        worksheets: [
          {
            name: 'Sheet1',
            data: [
              [
                { value: 100, row: 0, col: 0 },
                { value: 200, row: 0, col: 1 }
              ],
              [
                { value: 300, row: 1, col: 0 },
                { value: 400, row: 1, col: 1 }
              ]
            ],
            formulas: []
          }
        ]
      }

      detector = described_class.new(consistent_data)
      errors = detector.detect_all_errors
      validation_errors = errors.select { |e| e[:type] == :data_validation }

      expect(validation_errors).to be_empty
    end
  end

  describe '#detect_performance_issues' do
    it 'detects worksheets with too many formulas' do
      performance_data = sample_file_data.dup
      performance_data[:worksheets][0][:formula_count] = 1500

      detector = described_class.new(performance_data)
      errors = detector.detect_all_errors
      performance_errors = errors.select { |e| e[:type] == :performance_issue && e[:message].include?('formulas') }

      expect(performance_errors).not_to be_empty
      expect(performance_errors.first[:severity]).to eq('low')
    end

    it 'detects very large worksheets' do
      large_data = sample_file_data.dup
      large_data[:worksheets][0][:row_count] = 60000

      detector = described_class.new(large_data)
      errors = detector.detect_all_errors
      size_errors = errors.select { |e| e[:message].include?('rows') }

      expect(size_errors).not_to be_empty
      expect(size_errors.first[:severity]).to eq('medium')
    end
  end

  describe 'error structure' do
    it 'includes all required fields in error objects' do
      errors = detector.detect_all_errors

      expect(errors).not_to be_empty
      error = errors.first

      expect(error).to include(:type, :type_name, :worksheet, :address, :message, :severity, :detected_at)
      expect(error[:detected_at]).to be_present
    end

    it 'includes formula in formula-related errors' do
      errors = detector.detect_all_errors
      formula_errors = errors.select { |e| e[:formula].present? }

      expect(formula_errors).not_to be_empty
      expect(formula_errors.first[:formula]).to be_a(String)
    end
  end

  describe 'edge cases' do
    it 'handles empty worksheets' do
      empty_data = {
        worksheets: [
          {
            name: 'Empty',
            data: [],
            formulas: [],
            formula_count: 0,
            row_count: 0
          }
        ]
      }

      detector = described_class.new(empty_data)
      errors = detector.detect_all_errors

      expect(errors).to be_empty
    end

    it 'handles worksheets with no formulas' do
      no_formula_data = {
        worksheets: [
          {
            name: 'NoFormulas',
            data: [
              [ { value: 'Static', row: 0, col: 0 } ]
            ],
            formulas: [],
            formula_count: 0,
            row_count: 1
          }
        ]
      }

      detector = described_class.new(no_formula_data)
      errors = detector.detect_all_errors

      # Should not have formula-related errors
      formula_errors = errors.select { |e| [ :formula_error, :circular_reference ].include?(e[:type]) }
      expect(formula_errors).to be_empty
    end
  end
end
