# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExcelAnalysis::Services::FormulaAnalysisService do
  let(:user) { create(:user) }
  let(:excel_file) { create(:excel_file, user: user) }
  let(:service) { described_class.new(excel_file) }

  describe '#analyze' do
    context 'when FormulaEngine is available' do
      let(:mock_formula_engine) { instance_double(FormulaEngineClient) }
      let(:mock_file_analyzer) { instance_double(ExcelAnalysis::Services::FileAnalyzer) }

      let(:file_analyzer_data) do
        {
          format: 'xlsx',
          worksheets: [
            {
              name: 'Sheet1',
              data: [
                [ { value: 10, formula: nil }, { value: 20, formula: nil } ],
                [ { value: 30, formula: '=A1+B1' }, { value: 40, formula: '=SUM(A1:B1)' } ]
              ],
              formulas: [
                { formula: '=A1+B1', address: 'A2', row: 1, col: 0 },
                { formula: '=SUM(A1:B1)', address: 'B2', row: 1, col: 1 }
              ],
              row_count: 2,
              column_count: 2,
              formula_count: 2
            }
          ],
          metadata: { worksheet_count: 1 }
        }
      end

      let(:formula_engine_response) do
        {
          analysis: {
            summary: { totalFormulas: 2 },
            functions: {
              summary: { totalFunctions: 2, uniqueFunctions: 2 },
              details: [
                { name: 'SUM', count: 1 },
                { name: 'ADD', count: 1 }
              ]
            },
            dependencies: {
              summary: { totalDependencies: 2 },
              direct: [ { from: 'A1', to: 'A2' } ],
              indirect: [],
              nested: [],
              chains: []
            },
            circularReferences: [],
            errors: [],
            formulas: [
              { cell: 'A2', formula: '=A1+B1', complexity_score: 1.0 },
              { cell: 'B2', formula: '=SUM(A1:B1)', complexity_score: 1.5 }
            ]
          }
        }
      end

      before do
        allow(ExcelAnalysis::Services::FileAnalyzer).to receive(:new)
          .with(excel_file.file_path).and_return(mock_file_analyzer)
        allow(mock_file_analyzer).to receive(:extract_data).and_return(file_analyzer_data)

        allow(FormulaEngineClient).to receive(:instance).and_return(mock_formula_engine)
        allow(mock_formula_engine).to receive(:analyze_excel_with_session)
          .and_return(Common::Result.success(formula_engine_response))
      end

      it 'successfully analyzes formulas' do
        result = service.analyze

        expect(result).to be_success

        analysis_data = result.value
        expect(analysis_data).to include(
          :formula_analysis,
          :formula_complexity_score,
          :formula_count,
          :formula_functions,
          :formula_dependencies,
          :circular_references,
          :formula_errors,
          :formula_optimization_suggestions
        )

        expect(analysis_data[:formula_count]).to eq(2)
        expect(analysis_data[:formula_complexity_score]).to be_a(Float)
        expect(analysis_data[:formula_functions][:total_functions]).to eq(2)
        expect(analysis_data[:formula_dependencies][:total_dependencies]).to eq(2)
        expect(analysis_data[:circular_references]).to eq([])
        expect(analysis_data[:formula_errors]).to eq([])
      end

      it 'calculates complexity score correctly' do
        result = service.analyze

        expect(result).to be_success
        complexity_score = result.value[:formula_complexity_score]

        # 기본 수식 2개 * 0.1 = 0.2
        # SUM 함수는 복잡하지 않으므로 추가 점수 없음
        expect(complexity_score).to eq(0.2)
      end

      it 'extracts function statistics correctly' do
        result = service.analyze

        expect(result).to be_success
        functions_data = result.value[:formula_functions]

        expect(functions_data).to include(
          total_functions: 2,
          unique_functions: 2,
          function_usage: [
            { name: 'SUM', count: 1 },
            { name: 'ADD', count: 1 }
          ]
        )

        expect(functions_data[:categories]).to include('Statistical', 'Math')
      end
    end

    context 'when file extraction fails' do
      let(:mock_file_analyzer) { instance_double(ExcelAnalysis::Services::FileAnalyzer) }

      before do
        allow(ExcelAnalysis::Services::FileAnalyzer).to receive(:new)
          .with(excel_file.file_path).and_return(mock_file_analyzer)
        allow(mock_file_analyzer).to receive(:extract_data)
          .and_return({ error: 'File corrupted' })
      end

      it 'returns failure result' do
        result = service.analyze

        expect(result).to be_failure
        expect(result.error.message).to include('Excel 데이터 추출 실패')
      end
    end

    context 'when FormulaEngine analysis fails' do
      let(:mock_formula_engine) { instance_double(FormulaEngineClient) }
      let(:mock_file_analyzer) { instance_double(ExcelAnalysis::Services::FileAnalyzer) }

      before do
        allow(ExcelAnalysis::Services::FileAnalyzer).to receive(:new)
          .with(excel_file.file_path).and_return(mock_file_analyzer)
        allow(mock_file_analyzer).to receive(:extract_data)
          .and_return({ format: 'xlsx', worksheets: [], metadata: {} })

        allow(FormulaEngineClient).to receive(:instance).and_return(mock_formula_engine)
        allow(mock_formula_engine).to receive(:analyze_excel_with_session)
          .and_return(Common::Result.failure(
            Common::Errors::BusinessError.new(message: 'FormulaEngine unavailable')
          ))
      end

      it 'returns failure result' do
        result = service.analyze

        expect(result).to be_failure
        expect(result.error.message).to include('FormulaEngine unavailable')
      end
    end

    context 'with complex formulas' do
      let(:mock_formula_engine) { instance_double(FormulaEngineClient) }
      let(:mock_file_analyzer) { instance_double(ExcelAnalysis::Services::FileAnalyzer) }

      let(:complex_formula_response) do
        {
          analysis: {
            summary: { totalFormulas: 5 },
            functions: {
              summary: { totalFunctions: 8, uniqueFunctions: 4 },
              details: [
                { name: 'VLOOKUP', count: 2 },
                { name: 'INDEX', count: 1 },
                { name: 'MATCH', count: 1 },
                { name: 'SUMIFS', count: 1 },
                { name: 'IF', count: 3 }
              ]
            },
            dependencies: {
              summary: { totalDependencies: 10 },
              nested: [
                { cell: 'A1', nesting_level: 3 },
                { cell: 'B1', nesting_level: 2 }
              ]
            },
            circularReferences: [
              {
                cells: [ 'A1', 'B1' ],
                chain: [ 'A1 -> B1', 'B1 -> A1' ]
              }
            ],
            errors: [
              {
                cell: 'C1',
                formula: '=A1/0',
                type: 'DIV',
                message: 'Division by zero'
              }
            ],
            formulas: [
              { cell: 'A1', formula: '=VLOOKUP(B1,Data!A:C,3,FALSE)', complexity_score: 4.0 }
            ]
          }
        }
      end

      before do
        allow(ExcelAnalysis::Services::FileAnalyzer).to receive(:new)
          .with(excel_file.file_path).and_return(mock_file_analyzer)
        allow(mock_file_analyzer).to receive(:extract_data)
          .and_return({ format: 'xlsx', worksheets: [], metadata: {} })

        allow(FormulaEngineClient).to receive(:instance).and_return(mock_formula_engine)
        allow(mock_formula_engine).to receive(:analyze_excel_with_session)
          .and_return(Common::Result.success(complex_formula_response))
      end

      it 'calculates high complexity score' do
        result = service.analyze

        expect(result).to be_success
        complexity_score = result.value[:formula_complexity_score]

        # 기본 점수 (5 formulas * 0.1) + 복잡한 함수들 + 중첩 수식 + 순환 참조
        expect(complexity_score).to be > 2.0
      end

      it 'detects circular references' do
        result = service.analyze

        expect(result).to be_success
        circular_refs = result.value[:circular_references]

        expect(circular_refs).to have(1).item
        expect(circular_refs.first).to include(
          cells: [ 'A1', 'B1' ],
          severity: 'Low',
          description: 'A1 → B1 간에 순환 참조가 발생했습니다.'
        )
      end

      it 'extracts formula errors' do
        result = service.analyze

        expect(result).to be_success
        formula_errors = result.value[:formula_errors]

        expect(formula_errors).to have(1).item
        expect(formula_errors.first).to include(
          cell: 'C1',
          error_type: 'DIV',
          message: 'Division by zero',
          suggestion: '0으로 나누기 오류입니다. 분모를 확인하세요.'
        )
      end

      it 'generates optimization suggestions' do
        result = service.analyze

        expect(result).to be_success
        suggestions = result.value[:formula_optimization_suggestions]

        # 복잡한 수식에 대한 제안이 생성되어야 함
        expect(suggestions).not_to be_empty

        complex_suggestion = suggestions.find { |s| s[:type] == 'complexity_reduction' }
        expect(complex_suggestion).to be_present
        expect(complex_suggestion[:priority]).to eq('Medium')

        vlookup_suggestion = suggestions.find { |s| s[:type] == 'function_upgrade' }
        expect(vlookup_suggestion).to be_present
        expect(vlookup_suggestion[:suggestion]).to include('XLOOKUP')
      end
    end
  end

  describe 'private methods' do
    let(:service) { described_class.new(excel_file) }

    describe '#is_complex_function?' do
      it 'identifies complex functions correctly' do
        expect(service.send(:is_complex_function?, 'VLOOKUP')).to be true
        expect(service.send(:is_complex_function?, 'INDEX')).to be true
        expect(service.send(:is_complex_function?, 'SUMIFS')).to be true
        expect(service.send(:is_complex_function?, 'SUM')).to be false
        expect(service.send(:is_complex_function?, 'COUNT')).to be false
      end
    end

    describe '#categorize_function' do
      it 'categorizes functions correctly' do
        expect(service.send(:categorize_function, 'SUM')).to eq('Statistical')
        expect(service.send(:categorize_function, 'VLOOKUP')).to eq('Lookup')
        expect(service.send(:categorize_function, 'IF')).to eq('Logical')
        expect(service.send(:categorize_function, 'LEFT')).to eq('Text')
        expect(service.send(:categorize_function, 'NOW')).to eq('Date & Time')
        expect(service.send(:categorize_function, 'ABS')).to eq('Math')
        expect(service.send(:categorize_function, 'OFFSET')).to eq('Reference')
        expect(service.send(:categorize_function, 'CUSTOM')).to eq('Other')
      end
    end

    describe '#has_hardcoded_values?' do
      it 'detects hardcoded values' do
        expect(service.send(:has_hardcoded_values?, '=A1+5')).to be true
        expect(service.send(:has_hardcoded_values?, '=SUM(A1:A10,100)')).to be true
        expect(service.send(:has_hardcoded_values?, '=IF(A1="text",B1,C1)')).to be true
        expect(service.send(:has_hardcoded_values?, '=SUM(A1:B10)')).to be false
        expect(service.send(:has_hardcoded_values?, '=A1+B1')).to be false
      end
    end
  end
end
