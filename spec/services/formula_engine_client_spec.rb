# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormulaEngineClient, type: :service do
  let(:client) { described_class.new }
  let(:base_url) { 'http://localhost:3002' }
  let(:session_id) { 'test-session-123' }

  before do
    # FormulaEngine 설정 모킹
    allow(client).to receive(:load_config).and_return({
      'base_url' => base_url,
      'timeout' => 30,
      'open_timeout' => 10,
      'max_retries' => 3,
      'retry_delay' => 1.0,
      'log_requests' => false,
      'log_responses' => false
    })
  end

  describe '#initialize' do
    it '설정을 올바르게 로드한다' do
      expect(client.base_url).to eq(base_url)
      expect(client.timeout).to eq(30)
    end

    context '잘못된 설정일 때' do
      before do
        allow(client).to receive(:load_config).and_return({
          'base_url' => '',
          'timeout' => 0
        })
      end

      it 'base_url이 없으면 예외를 발생시킨다' do
        expect { described_class.new }.to raise_error(/base_url이 설정되지 않았습니다/)
      end
    end
  end

  describe '#create_session' do
    context '성공적인 응답' do
      let(:success_response) do
        double('HTTParty::Response',
          success?: true,
          parsed_response: {
            'success' => true,
            'sessionId' => session_id,
            'message' => 'FormulaEngine 세션이 생성되었습니다.'
          }
        )
      end

      before do
        allow(HTTParty).to receive(:post).and_return(success_response)
      end

      it '세션을 성공적으로 생성한다' do
        result = client.create_session

        expect(result.success?).to be true
        expect(result.value[:session_id]).to eq(session_id)
        expect(client.session_id).to eq(session_id)
      end
    end

    context '실패 응답' do
      let(:error_response) do
        double('HTTParty::Response',
          success?: false,
          code: 500,
          parsed_response: {
            'success' => false,
            'error' => 'Internal Server Error'
          }
        )
      end

      before do
        allow(HTTParty).to receive(:post).and_return(error_response)
      end

      it '실패 결과를 반환한다' do
        result = client.create_session

        expect(result.failure?).to be true
        expect(result.error).to be_a(Common::Errors::BusinessError)
        expect(result.error.message).to include('Internal Server Error')
      end
    end

    context '네트워크 에러' do
      before do
        allow(HTTParty).to receive(:post).and_raise(Net::TimeoutError)
      end

      it '네트워크 에러를 처리한다' do
        result = client.create_session

        expect(result.failure?).to be true
        expect(result.error.message).to include('세션 생성 실패')
      end
    end
  end

  describe '#destroy_session' do
    let(:success_response) do
      double('HTTParty::Response',
        success?: true,
        parsed_response: {
          'success' => true,
          'message' => '세션이 삭제되었습니다.'
        }
      )
    end

    before do
      client.instance_variable_set(:@session_id, session_id)
      allow(HTTParty).to receive(:delete).and_return(success_response)
    end

    it '세션을 성공적으로 삭제한다' do
      result = client.destroy_session

      expect(result.success?).to be true
      expect(client.session_id).to be_nil
    end

    context '세션 ID가 없을 때' do
      it '성공 결과를 반환한다' do
        result = client.destroy_session(nil)

        expect(result.success?).to be true
      end
    end
  end

  describe '#load_excel_data' do
    let(:excel_data) { [ [ 'A1', 'B1' ], [ 'A2', 'B2' ] ] }
    let(:success_response) do
      double('HTTParty::Response',
        success?: true,
        parsed_response: {
          'success' => true,
          'message' => 'FormulaEngine 생성 완료'
        }
      )
    end

    before do
      client.instance_variable_set(:@session_id, session_id)
      allow(HTTParty).to receive(:post).and_return(success_response)
    end

    it 'Excel 데이터를 성공적으로 로드한다' do
      result = client.load_excel_data(excel_data)

      expect(result.success?).to be true
      expect(result.value[:session_id]).to eq(session_id)
    end

    context '세션이 없을 때' do
      before do
        client.instance_variable_set(:@session_id, nil)
      end

      it '세션 필수 에러를 반환한다' do
        result = client.load_excel_data(excel_data)

        expect(result.failure?).to be true
        expect(result.error.message).to include('세션이 필요합니다')
      end
    end
  end

  describe '#analyze_formulas' do
    let(:analysis_data) do
      {
        'sheets' => [
          {
            'name' => 'Sheet1',
            'formulaCount' => 5,
            'functions' => { 'SUM' => 2, 'AVERAGE' => 1 }
          }
        ],
        'totalFormulas' => 5,
        'functions' => { 'SUM' => 2, 'AVERAGE' => 1 }
      }
    end

    let(:success_response) do
      double('HTTParty::Response',
        success?: true,
        parsed_response: {
          'success' => true,
          'data' => analysis_data
        }
      )
    end

    before do
      client.instance_variable_set(:@session_id, session_id)
      allow(HTTParty).to receive(:get).and_return(success_response)
    end

    it '수식 분석을 성공적으로 수행한다' do
      result = client.analyze_formulas

      expect(result.success?).to be true
      expect(result.value[:analysis]).to eq(analysis_data)
      expect(result.value[:session_id]).to eq(session_id)
    end
  end

  describe '#validate_formula' do
    let(:formula) { '=SUM(A1:A10)' }
    let(:success_response) do
      double('HTTParty::Response',
        success?: true,
        parsed_response: {
          'success' => true,
          'valid' => true,
          'errors' => []
        }
      )
    end

    before do
      client.instance_variable_set(:@session_id, session_id)
      allow(HTTParty).to receive(:post).and_return(success_response)
    end

    it '수식을 성공적으로 검증한다' do
      result = client.validate_formula(formula)

      expect(result.success?).to be true
      expect(result.value[:valid]).to be true
      expect(result.value[:formula]).to eq(formula)
    end

    context '수식이 없을 때' do
      it '수식 필수 에러를 반환한다' do
        result = client.validate_formula('')

        expect(result.failure?).to be true
        expect(result.error.message).to include('수식이 필요합니다')
      end
    end
  end

  describe '#calculate_formula' do
    let(:formula) { '=SUM(1,2,3)' }
    let(:success_response) do
      double('HTTParty::Response',
        success?: true,
        parsed_response: {
          'success' => true,
          'result' => 6
        }
      )
    end

    before do
      client.instance_variable_set(:@session_id, session_id)
      allow(HTTParty).to receive(:post).and_return(success_response)
    end

    it '수식을 성공적으로 계산한다' do
      result = client.calculate_formula(formula)

      expect(result.success?).to be true
      expect(result.value[:result]).to eq(6)
      expect(result.value[:formula]).to eq(formula)
    end
  end

  describe '#get_supported_functions' do
    let(:functions_data) do
      {
        'total' => 100,
        'functions' => [ 'SUM', 'AVERAGE', 'MAX', 'MIN' ],
        'categories' => {
          'MATH' => [ 'SUM', 'AVERAGE', 'MAX', 'MIN' ]
        }
      }
    end

    let(:success_response) do
      double('HTTParty::Response',
        success?: true,
        parsed_response: {
          'success' => true,
          'total' => functions_data['total'],
          'functions' => functions_data['functions'],
          'categories' => functions_data['categories']
        }
      )
    end

    before do
      allow(HTTParty).to receive(:get).and_return(success_response)
    end

    it '지원 함수 목록을 성공적으로 조회한다' do
      result = client.get_supported_functions

      expect(result.success?).to be true
      expect(result.value[:total]).to eq(100)
      expect(result.value[:functions]).to include('SUM', 'AVERAGE')
    end
  end

  describe '#health_check' do
    let(:health_data) do
      {
        'status' => 'healthy',
        'service' => 'FormulaEngine',
        'version' => '1.0.0',
        'hyperformulaVersion' => '2.7.0',
        'supportedFunctions' => 350,
        'activeSessions' => 0,
        'uptime' => 3600,
        'memory' => { 'rss' => 12345678 }
      }
    end

    let(:success_response) do
      double('HTTParty::Response',
        success?: true,
        parsed_response: health_data
      )
    end

    before do
      allow(HTTParty).to receive(:get).and_return(success_response)
    end

    it '헬스 체크를 성공적으로 수행한다' do
      result = client.health_check

      expect(result.success?).to be true
      expect(result.value[:status]).to eq('healthy')
      expect(result.value[:service]).to eq('FormulaEngine')
      expect(result.value[:supported_functions]).to eq(350)
    end
  end

  describe '#analyze_excel_with_session' do
    let(:excel_data) { [ [ 'A1', 'B1' ], [ 'A2', 'B2' ] ] }
    let(:session_response) do
      double('HTTParty::Response',
        success?: true,
        parsed_response: {
          'success' => true,
          'sessionId' => session_id
        }
      )
    end

    let(:load_response) do
      double('HTTParty::Response',
        success?: true,
        parsed_response: { 'success' => true }
      )
    end

    let(:analyze_response) do
      double('HTTParty::Response',
        success?: true,
        parsed_response: {
          'success' => true,
          'data' => { 'totalFormulas' => 0 }
        }
      )
    end

    let(:delete_response) do
      double('HTTParty::Response',
        success?: true,
        parsed_response: { 'success' => true }
      )
    end

    before do
      allow(HTTParty).to receive(:post).with(
        "#{base_url}/sessions", anything
      ).and_return(session_response)

      allow(HTTParty).to receive(:post).with(
        "#{base_url}/sessions/#{session_id}/load", anything
      ).and_return(load_response)

      allow(HTTParty).to receive(:get).with(
        "#{base_url}/sessions/#{session_id}/analyze", anything
      ).and_return(analyze_response)

      allow(HTTParty).to receive(:delete).with(
        "#{base_url}/sessions/#{session_id}", anything
      ).and_return(delete_response)
    end

    it '자동 세션 관리로 Excel 분석을 수행한다' do
      result = client.analyze_excel_with_session(excel_data)

      expect(result.success?).to be true
      expect(client.session_id).to be_nil # 세션이 정리되었는지 확인
    end
  end

  describe 'class methods' do
    describe '.health_check' do
      it 'FormulaEngineClient.health_check를 호출한다' do
        expect_any_instance_of(described_class).to receive(:health_check)
        described_class.health_check
      end
    end

    describe '.analyze_excel' do
      let(:excel_data) { [ [ 'test' ] ] }

      it 'FormulaEngineClient.analyze_excel_with_session을 호출한다' do
        expect_any_instance_of(described_class).to receive(:analyze_excel_with_session).with(excel_data)
        described_class.analyze_excel(excel_data)
      end
    end

    describe '.validate_formula' do
      let(:formula) { '=SUM(1,2,3)' }

      it 'FormulaEngineClient.validate_formula_with_session을 호출한다' do
        expect_any_instance_of(described_class).to receive(:validate_formula_with_session).with(formula)
        described_class.validate_formula(formula)
      end
    end
  end
end
