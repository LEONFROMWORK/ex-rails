# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::PipedataController, type: :controller do
  let(:valid_token) { 'test_pipedata_token' }
  let(:invalid_token) { 'invalid_token' }

  let(:valid_data) do
    [
      {
        question: "VLOOKUP 함수에서 #N/A 에러가 발생하는 이유는 무엇인가요?",
        answer: "VLOOKUP 함수에서 #N/A 에러는 검색값이 테이블에 없거나 정확히 일치하지 않을 때 발생합니다. 해결방법은 1) 검색값 정확성 확인, 2) IFERROR 함수 사용, 3) 완전일치(FALSE) 설정입니다.",
        difficulty: "medium",
        quality_score: 8.5,
        source: "pipedata_stackoverflow",
        excel_functions: [ "VLOOKUP", "IFERROR" ],
        code_snippets: [ "=VLOOKUP(A1,B:C,2,FALSE)", "=IFERROR(VLOOKUP(A1,B:C,2,FALSE),\"Not Found\")" ],
        tags: [ "excel", "vlookup", "error-handling" ],
        metadata: {
          votes: 15,
          views: 1024,
          accepted: true
        }
      }
    ]
  end

  let(:invalid_data_missing_fields) do
    [
      {
        question: "", # 빈 질문
        answer: "답변만 있음",
        difficulty: "medium"
      }
    ]
  end

  let(:invalid_data_wrong_format) do
    [
      {
        question: "유효한 질문",
        answer: "유효한 답변",
        difficulty: "invalid_difficulty", # 잘못된 난이도
        quality_score: 15.0, # 범위 초과 점수
        source: nil
      }
    ]
  end

  before do
    # 환경 변수 설정
    allow(Rails.application.credentials).to receive(:pipedata_api_token).and_return(valid_token)
    allow(ENV).to receive(:[]).with('PIPEDATA_API_TOKEN').and_return(valid_token)
  end

  describe 'POST #create' do
    context '인증 테스트' do
      it '유효한 토큰으로 요청 시 성공한다' do
        request.headers['X-PipeData-Token'] = valid_token

        post :create, params: { data: valid_data }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['success']).to be true
      end

      it '무효한 토큰으로 요청 시 401 에러를 반환한다' do
        request.headers['X-PipeData-Token'] = invalid_token

        post :create, params: { data: valid_data }

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)['error']).to eq('Unauthorized')
      end

      it '토큰 없이 요청 시 401 에러를 반환한다' do
        post :create, params: { data: valid_data }

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)['error']).to eq('Unauthorized')
      end
    end

    context '데이터 검증 테스트' do
      before do
        request.headers['X-PipeData-Token'] = valid_token
      end

      it '유효한 Q&A 데이터를 성공적으로 처리한다' do
        expect {
          post :create, params: { data: valid_data }
        }.to change(KnowledgeItem, :count).by(1)

        expect(response).to have_http_status(:ok)

        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be true
        expect(response_body['created']).to eq(1)
        expect(response_body['processed']).to eq(1)
        expect(response_body['duplicates']).to eq(0)
        expect(response_body['errors']).to eq(0)
      end

      it '필수 필드 누락 데이터는 에러로 처리한다' do
        expect {
          post :create, params: { data: invalid_data_missing_fields }
        }.not_to change(KnowledgeItem, :count)

        expect(response).to have_http_status(:ok)

        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be true
        expect(response_body['created']).to eq(0)
        expect(response_body['processed']).to eq(1)
        expect(response_body['errors']).to eq(1)
      end

      it '중복 데이터는 중복으로 처리한다' do
        # 첫 번째 데이터 저장
        KnowledgeItem.create!(
          question: valid_data[0][:question],
          answer: valid_data[0][:answer],
          difficulty: 1,
          quality_score: valid_data[0][:quality_score],
          source: valid_data[0][:source],
          embedding: Array.new(1536) { rand(-1.0..1.0) }
        )

        expect {
          post :create, params: { data: valid_data }
        }.not_to change(KnowledgeItem, :count)

        response_body = JSON.parse(response.body)
        expect(response_body['duplicates']).to eq(1)
        expect(response_body['created']).to eq(0)
      end

      it '대량 데이터를 처리한다' do
        large_data = Array.new(100) do |i|
          {
            question: "Excel 질문 #{i + 1}번입니다. 이 질문은 테스트용 질문입니다.",
            answer: "Excel 답변 #{i + 1}번입니다. 이 답변은 테스트용 답변으로 충분한 길이를 가져야 합니다.",
            difficulty: "medium",
            quality_score: 7.0 + (i % 3),
            source: "pipedata_test",
            excel_functions: [ "SUM", "AVERAGE" ],
            code_snippets: [ "=SUM(A1:A10)" ],
            tags: [ "test", "excel" ]
          }
        end

        start_time = Time.current

        expect {
          post :create, params: { data: large_data }
        }.to change(KnowledgeItem, :count).by(100)

        processing_time = Time.current - start_time
        expect(processing_time).to be < 10.seconds # 100건 처리는 10초 이내

        response_body = JSON.parse(response.body)
        expect(response_body['created']).to eq(100)
        expect(response_body['processed']).to eq(100)
      end

      it '빈 배열 데이터는 적절히 처리한다' do
        post :create, params: { data: [] }

        expect(response).to have_http_status(:ok)
        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be true
        expect(response_body['processed']).to eq(0)
        expect(response_body['created']).to eq(0)
        expect(response_body['duplicates']).to eq(0)
        expect(response_body['errors']).to eq(0)
      end
    end

    context '서비스 에러 처리' do
      before do
        request.headers['X-PipeData-Token'] = valid_token
      end

      it 'PipedataIngestionService 에러 시 적절히 처리한다' do
        allow(PipedataIngestionService).to receive(:call).and_raise(StandardError.new('Service error'))

        post :create, params: { data: valid_data }

        expect(response).to have_http_status(:internal_server_error)
        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be false
        expect(response_body['error']).to eq('Internal server error')
      end
    end
  end

  describe 'GET #show' do
    before do
      request.headers['X-PipeData-Token'] = valid_token

      # 테스트 데이터 생성
      3.times do |i|
        KnowledgeItem.create!(
          question: "테스트 질문 #{i + 1}번입니다. 충분한 길이의 질문입니다.",
          answer: "테스트 답변 #{i + 1}번입니다. 충분한 길이의 답변으로 작성되었습니다.",
          difficulty: i % 4,
          quality_score: 7.0 + i,
          source: "pipedata_test_#{i}",
          search_count: i * 5,
          use_count: i * 3,
          helpful_votes: i * 2,
          embedding: Array.new(1536) { rand(-1.0..1.0) }
        )
      end
    end

    it '동기화 상태 및 통계를 반환한다' do
      get :show

      expect(response).to have_http_status(:ok)

      response_body = JSON.parse(response.body)
      expect(response_body['total_records']).to eq(3)
      expect(response_body['average_quality'].to_f).to be_a(Numeric)
      expect(response_body['status']).to eq('active')
      expect(response_body['rails_version']).to eq(Rails.version)
      expect(response_body['app_version']).to eq('1.0.0')
      expect(response_body['sources']).to be_a(Hash)
    end

    it '인증 없이 요청 시 401 에러를 반환한다' do
      request.headers['X-PipeData-Token'] = nil

      get :show

      expect(response).to have_http_status(:unauthorized)
    end

    it 'KnowledgeItemStatsService 에러 시 적절히 처리한다' do
      allow(KnowledgeItemStatsService).to receive(:call).and_raise(StandardError.new('Stats error'))

      get :show

      expect(response).to have_http_status(:internal_server_error)
      response_body = JSON.parse(response.body)
      expect(response_body['error']).to eq('Internal server error')
    end
  end
end
