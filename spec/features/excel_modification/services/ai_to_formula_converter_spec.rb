# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExcelModification::Services::AiToFormulaConverter, type: :service do
  let(:converter) { described_class.new }

  before do
    # Mock the multimodal service
    multimodal_service = instance_double('AiIntegration::Services::MultimodalCoordinatorService')
    allow(AiIntegration::Services::MultimodalCoordinatorService).to receive(:new).and_return(multimodal_service)

    # Mock the Rails cache
    allow(Rails).to receive(:cache).and_return(
      instance_double(ActiveSupport::Cache::MemoryStore, read: nil, write: true)
    )

    # Mock FormulaEngineClient
    allow(FormulaEngineClient).to receive(:validate_formula) do |formula|
      if formula && formula.start_with?('=')
        Common::Result.success(valid: true, errors: [])
      else
        Common::Result.failure("Invalid formula")
      end
    end

    # Set up mock responses for different test cases
    allow(multimodal_service).to receive(:analyze_image) do |params|
      prompt = params[:prompt]
      if prompt.include?("합계") || prompt.include?("sum")
        Common::Result.success({
          formula: '=SUM(A1:A10)',
          explanation: 'A1부터 A10까지의 합계를 계산합니다',
          confidence: 0.95,
          cell_reference: 'A11'
        })
      elsif prompt.include?("평균") || prompt.include?("average")
        Common::Result.success({
          formula: '=AVERAGE(B:B)',
          explanation: 'B열의 평균값을 계산합니다',
          confidence: 0.92,
          cell_reference: 'C1'
        })
      elsif prompt.include?("100보다 큰")
        Common::Result.success({
          formula: '=SUMIF(C:C,">100")',
          explanation: 'C열에서 100보다 큰 값들의 합계를 계산합니다',
          confidence: 0.90,
          cell_reference: 'D1'
        })
      elsif prompt.include?("총합계")
        Common::Result.success({
          formula: '=SUM(A1:D100)',
          explanation: '전체 데이터 범위의 합계를 계산합니다',
          confidence: 0.88,
          cell_reference: 'D15'
        })
      else
        Common::Result.failure("Formula conversion failed")
      end
    end
  end

  describe '#convert' do
    context 'with valid text input' do
      it 'converts sum request to SUM formula' do
        result = converter.convert("A1부터 A10까지 합계를 구해줘")

        expect(result).to be_success
        expect(result.value[:formula]).to eq('=SUM(A1:A10)')
        expect(result.value[:explanation]).to be_present
      end

      it 'converts average request to AVERAGE formula' do
        result = converter.convert("B열의 평균값을 계산해줘")

        expect(result).to be_success
        expect(result.value[:formula]).to include('AVERAGE')
      end

      it 'converts conditional sum request to SUMIF formula' do
        # Update the mock to return SUMIF for this specific test
        multimodal_service = instance_double('AiIntegration::Services::MultimodalCoordinatorService')
        allow(AiIntegration::Services::MultimodalCoordinatorService).to receive(:new).and_return(multimodal_service)
        allow(multimodal_service).to receive(:analyze_image) do |params|
          Common::Result.success({
            formula: '=SUMIF(C:C,">100")',
            explanation: 'C열에서 100보다 큰 값들의 합계를 계산합니다',
            confidence: 0.90,
            cell_reference: 'D1'
          })
        end

        result = converter.convert("C열에서 100보다 큰 값들의 합계")

        expect(result).to be_success
        expect(result.value[:formula]).to include('SUMIF')
      end
    end

    context 'with context information' do
      let(:context) do
        {
          worksheet_name: 'Sales',
          selected_cell: 'D15',
          data_range: 'A1:D100'
        }
      end

      it 'considers context when generating formula' do
        # Update the mock to return D15 for this specific test
        multimodal_service = instance_double('AiIntegration::Services::MultimodalCoordinatorService')
        allow(AiIntegration::Services::MultimodalCoordinatorService).to receive(:new).and_return(multimodal_service)
        allow(multimodal_service).to receive(:analyze_image) do |params|
          Common::Result.success({
            formula: '=SUM(A1:D100)',
            explanation: '전체 데이터 범위의 합계를 계산합니다',
            confidence: 0.88,
            cell_reference: 'D15'
          })
        end

        result = converter.convert("이 시트의 총합계", context)

        expect(result).to be_success
        expect(result.value[:cell_reference]).to eq('D15')
      end
    end

    context 'with invalid input' do
      it 'returns failure for blank text' do
        result = converter.convert("")

        expect(result).to be_failure
        expect(result.error).to eq("Text cannot be blank")
      end
    end

    context 'caching' do
      it 'caches successful conversions' do
        cache = instance_double(ActiveSupport::Cache::MemoryStore)
        allow(Rails).to receive(:cache).and_return(cache)

        # First call - cache miss
        allow(cache).to receive(:read).and_return(nil).once
        allow(cache).to receive(:write).once

        result1 = converter.convert("합계 구하기")
        expect(result1).to be_success

        # Second call - cache hit
        allow(cache).to receive(:read).and_return(result1.value).once

        result2 = converter.convert("합계 구하기")
        expect(result2).to be_success
        expect(result2.value).to eq(result1.value)
      end
    end
  end

  describe '#convert_batch' do
    let(:requests) do
      [
        { text: "A1:A10 합계", context: {} },
        { text: "B열 평균", context: {} },
        { text: "", context: {} } # Invalid
      ]
    end

    it 'processes multiple requests' do
      result = converter.convert_batch(requests)

      expect(result).to be_success
      expect(result.value[:successful].size).to eq(2)
      expect(result.value[:failed].size).to eq(1)
      expect(result.value[:success_rate]).to be_within(0.01).of(0.67)
    end
  end
end
