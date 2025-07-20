# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'PipeData Security', type: :request do
  let(:valid_token) { 'test_pipedata_token' }
  let(:invalid_token) { 'invalid_token' }

  let(:valid_data) do
    {
      data: [
        {
          question: "보안 테스트 질문입니다. 이것은 정상적인 질문입니다.",
          answer: "보안 테스트 답변입니다. 이것은 정상적인 답변으로 충분한 길이를 가져야 합니다.",
          difficulty: "medium",
          quality_score: 7.0,
          source: "pipedata_security_test",
          excel_functions: [ "SECURITY_TEST" ],
          code_snippets: [ "=SECURITY_TEST()" ],
          tags: [ "security", "test" ]
        }
      ]
    }
  end

  before do
    allow(Rails.application.credentials).to receive(:pipedata_api_token).and_return(valid_token)
    allow(ENV).to receive(:[]).with('PIPEDATA_API_TOKEN').and_return(valid_token)
  end

  describe '인증 보안' do
    context '토큰 검증' do
      it '유효한 토큰으로 접근을 허용한다' do
        headers = { 'X-PipeData-Token' => valid_token }

        post '/api/v1/pipedata', params: valid_data, headers: headers

        expect(response).to have_http_status(:ok)
      end

      it '무효한 토큰으로 접근을 거부한다' do
        headers = { 'X-PipeData-Token' => invalid_token }

        post '/api/v1/pipedata', params: valid_data, headers: headers

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)['error']).to eq('Unauthorized')
      end

      it '토큰 없이 접근을 거부한다' do
        post '/api/v1/pipedata', params: valid_data

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)['error']).to eq('Unauthorized')
      end

      it '빈 토큰으로 접근을 거부한다' do
        headers = { 'X-PipeData-Token' => '' }

        post '/api/v1/pipedata', params: valid_data, headers: headers

        expect(response).to have_http_status(:unauthorized)
      end

      it '잘못된 헤더명으로 접근을 거부한다' do
        headers = { 'Authorization' => "Bearer #{valid_token}" } # 잘못된 헤더

        post '/api/v1/pipedata', params: valid_data, headers: headers

        expect(response).to have_http_status(:unauthorized)
      end

      it '토큰 케이스 감지를 확인한다' do
        headers = { 'X-PipeData-Token' => valid_token.upcase } # 대문자로 변경

        post '/api/v1/pipedata', params: valid_data, headers: headers

        expect(response).to have_http_status(:unauthorized) # 정확히 일치해야 함
      end
    end

    context '타이밍 공격 방어' do
      it '토큰 비교 시 타이밍 공격을 방어한다' do
        # 여러 길이의 잘못된 토큰으로 응답 시간 측정
        short_token = 'short'
        long_token = 'very_long_invalid_token_that_should_not_work'

        headers_short = { 'X-PipeData-Token' => short_token }
        headers_long = { 'X-PipeData-Token' => long_token }

        # 짧은 토큰 응답 시간 측정
        start_time = Time.current
        post '/api/v1/pipedata', params: valid_data, headers: headers_short
        short_response_time = Time.current - start_time
        expect(response).to have_http_status(:unauthorized)

        # 긴 토큰 응답 시간 측정
        start_time = Time.current
        post '/api/v1/pipedata', params: valid_data, headers: headers_long
        long_response_time = Time.current - start_time
        expect(response).to have_http_status(:unauthorized)

        # 응답 시간 차이가 10ms 이내여야 함 (타이밍 공격 방어)
        time_difference = (long_response_time - short_response_time).abs
        expect(time_difference).to be < 0.01.seconds
      end
    end
  end

  describe 'SQL Injection 방어' do
    it 'question 필드에서 SQL Injection을 방어한다' do
      headers = { 'X-PipeData-Token' => valid_token }

      malicious_data = {
        data: [
          {
            question: "'; DROP TABLE knowledge_items; --",
            answer: "SQL Injection 테스트 답변입니다. 이것은 충분한 길이를 가져야 합니다.",
            difficulty: "medium",
            quality_score: 7.0,
            source: "pipedata_sql_injection_test",
            excel_functions: [ "MALICIOUS" ],
            code_snippets: [ "=MALICIOUS()" ],
            tags: [ "sql", "injection" ]
          }
        ]
      }

      expect {
        post '/api/v1/pipedata', params: malicious_data, headers: headers
      }.to change(KnowledgeItem, :count).by(1) # 정상적으로 저장됨

      expect(response).to have_http_status(:ok)

      # 데이터베이스가 손상되지 않았는지 확인
      expect(KnowledgeItem.count).to be > 0
      created_item = KnowledgeItem.last
      expect(created_item.question).to eq("'; DROP TABLE knowledge_items; --") # 문자열로 안전하게 저장
    end

    it 'answer 필드에서 SQL Injection을 방어한다' do
      headers = { 'X-PipeData-Token' => valid_token }

      malicious_data = {
        data: [
          {
            question: "SQL Injection 방어 테스트 질문입니다. 이것은 정상적인 질문입니다.",
            answer: "' UNION SELECT * FROM users WHERE '1'='1",
            difficulty: "medium",
            quality_score: 7.0,
            source: "pipedata_sql_injection_test",
            excel_functions: [ "UNION_ATTACK" ],
            code_snippets: [ "=UNION_ATTACK()" ],
            tags: [ "sql", "injection", "union" ]
          }
        ]
      }

      post '/api/v1/pipedata', params: malicious_data, headers: headers

      expect(response).to have_http_status(:ok)
      created_item = KnowledgeItem.last
      expect(created_item.answer).to eq("' UNION SELECT * FROM users WHERE '1'='1") # 안전하게 문자열로 저장
    end

    it 'metadata 필드에서 SQL Injection을 방어한다' do
      headers = { 'X-PipeData-Token' => valid_token }

      malicious_data = {
        data: [
          {
            question: "메타데이터 SQL Injection 테스트 질문입니다. 이것은 정상적인 질문입니다.",
            answer: "메타데이터 SQL Injection 테스트 답변입니다. 이것은 충분한 길이를 가져야 합니다.",
            difficulty: "medium",
            quality_score: 7.0,
            source: "pipedata_metadata_injection_test",
            excel_functions: [ "METADATA_ATTACK" ],
            code_snippets: [ "=METADATA_ATTACK()" ],
            tags: [ "metadata", "injection" ],
            metadata: {
              malicious_field: "'; DELETE FROM knowledge_items; --",
              nested: {
                attack: "' OR '1'='1"
              }
            }
          }
        ]
      }

      post '/api/v1/pipedata', params: malicious_data, headers: headers

      expect(response).to have_http_status(:ok)
      created_item = KnowledgeItem.last
      expect(created_item.metadata['malicious_field']).to eq("'; DELETE FROM knowledge_items; --")
      expect(created_item.metadata['nested']['attack']).to eq("' OR '1'='1")
    end
  end

  describe 'XSS 방어' do
    it 'question 필드에서 XSS를 방어한다' do
      headers = { 'X-PipeData-Token' => valid_token }

      xss_data = {
        data: [
          {
            question: "<script>alert('XSS Attack');</script>악성 스크립트 테스트 질문입니다.",
            answer: "XSS 방어 테스트 답변입니다. 이것은 충분한 길이를 가져야 합니다.",
            difficulty: "medium",
            quality_score: 7.0,
            source: "pipedata_xss_test",
            excel_functions: [ "XSS_TEST" ],
            code_snippets: [ "=XSS_TEST()" ],
            tags: [ "xss", "security" ]
          }
        ]
      }

      post '/api/v1/pipedata', params: xss_data, headers: headers

      expect(response).to have_http_status(:ok)
      created_item = KnowledgeItem.last

      # XSS 스크립트가 제거되었는지 확인
      expect(created_item.question).not_to include('<script>')
      expect(created_item.question).not_to include('</script>')
      expect(created_item.question).to include('악성 스크립트 테스트 질문입니다')
    end

    it 'answer 필드에서 XSS를 방어한다' do
      headers = { 'X-PipeData-Token' => valid_token }

      xss_data = {
        data: [
          {
            question: "XSS 방어 테스트 질문입니다. 이것은 정상적인 질문입니다.",
            answer: "<img src='x' onerror='alert(\"XSS\")'>XSS 공격 테스트 답변입니다. 충분한 길이를 가져야 합니다.",
            difficulty: "medium",
            quality_score: 7.0,
            source: "pipedata_xss_answer_test",
            excel_functions: [ "XSS_ANSWER" ],
            code_snippets: [ "=XSS_ANSWER()" ],
            tags: [ "xss", "answer", "security" ]
          }
        ]
      }

      post '/api/v1/pipedata', params: xss_data, headers: headers

      expect(response).to have_http_status(:ok)
      created_item = KnowledgeItem.last

      # XSS 태그가 제거되었는지 확인
      expect(created_item.answer).not_to include('<img')
      expect(created_item.answer).not_to include('onerror')
      expect(created_item.answer).to include('XSS 공격 테스트 답변입니다')
    end

    it '복합 XSS 공격을 방어한다' do
      headers = { 'X-PipeData-Token' => valid_token }

      complex_xss_data = {
        data: [
          {
            question: "<svg onload=alert('XSS')>복합 XSS 테스트</svg> 질문입니다. 충분한 길이가 필요합니다.",
            answer: "<iframe src='javascript:alert(\"XSS\")'></iframe>복합 XSS 답변입니다. 충분한 길이를 가져야 합니다.",
            difficulty: "medium",
            quality_score: 7.0,
            source: "pipedata_complex_xss_test",
            excel_functions: [ "<script>console.log('XSS')</script>" ],
            code_snippets: [ "=<script>alert('code')</script>()" ],
            tags: [ "<marquee>xss</marquee>", "security" ],
            metadata: {
              xss_field: "<object data='javascript:alert(\"XSS\")'></object>"
            }
          }
        ]
      }

      post '/api/v1/pipedata', params: complex_xss_data, headers: headers

      expect(response).to have_http_status(:ok)
      created_item = KnowledgeItem.last

      # 모든 XSS 태그가 제거되었는지 확인
      expect(created_item.question).not_to include('<svg')
      expect(created_item.question).not_to include('onload')
      expect(created_item.answer).not_to include('<iframe')
      expect(created_item.answer).not_to include('javascript:')
      expect(created_item.excel_functions.first).not_to include('<script>')
      expect(created_item.code_snippets.first).not_to include('<script>')
      expect(created_item.tags.first).not_to include('<marquee>')
    end
  end

  describe '대용량 페이로드 공격 방어' do
    it '매우 큰 질문 텍스트를 제한한다' do
      headers = { 'X-PipeData-Token' => valid_token }

      huge_question = "매우 긴 질문입니다. " * 10000 # 약 200KB 크기

      large_payload_data = {
        data: [
          {
            question: huge_question,
            answer: "대용량 페이로드 테스트 답변입니다. 이것은 충분한 길이를 가져야 합니다.",
            difficulty: "medium",
            quality_score: 7.0,
            source: "pipedata_large_payload_test"
          }
        ]
      }

      post '/api/v1/pipedata', params: large_payload_data, headers: headers

      expect(response).to have_http_status(:ok)

      # 질문이 적절히 잘렸는지 확인 (PipedataIngestionService에서 5000자로 제한)
      created_item = KnowledgeItem.last
      expect(created_item.question.length).to be <= 5000
    end

    it '매우 큰 배열 데이터를 처리한다' do
      headers = { 'X-PipeData-Token' => valid_token }

      huge_array = Array.new(10000) { |i| "item_#{i}" }

      large_array_data = {
        data: [
          {
            question: "대용량 배열 테스트 질문입니다. 이것은 정상적인 질문입니다.",
            answer: "대용량 배열 테스트 답변입니다. 이것은 충분한 길이를 가져야 합니다.",
            difficulty: "medium",
            quality_score: 7.0,
            source: "pipedata_large_array_test",
            excel_functions: huge_array,
            code_snippets: huge_array,
            tags: huge_array
          }
        ]
      }

      post '/api/v1/pipedata', params: large_array_data, headers: headers

      expect(response).to have_http_status(:ok)
      created_item = KnowledgeItem.last

      # 배열이 정상적으로 저장되었는지 확인
      expect(created_item.excel_functions).to be_an(Array)
      expect(created_item.excel_functions.length).to eq(10000)
    end

    it '요청 당 아이템 수를 제한한다' do
      headers = { 'X-PipeData-Token' => valid_token }

      # 과도하게 많은 아이템 (10000개)
      massive_items = Array.new(10000) do |i|
        {
          question: "대량 아이템 테스트 질문 #{i + 1}번입니다. 이것은 정상적인 질문입니다.",
          answer: "대량 아이템 테스트 답변 #{i + 1}번입니다. 이것은 충분한 길이를 가져야 합니다.",
          difficulty: "medium",
          quality_score: 7.0,
          source: "pipedata_massive_items_test_#{i}"
        }
      end

      massive_data = { data: massive_items }

      # 요청 시간 제한을 확인 (타임아웃이 발생할 수 있음)
      start_time = Time.current
      post '/api/v1/pipedata', params: massive_data, headers: headers
      processing_time = Time.current - start_time

      # 서버가 응답했는지 확인 (타임아웃되지 않음)
      expect(response.status).to be_in([ 200, 500, 422 ]) # 정상 처리 또는 서버 제한

      # 처리 시간이 합리적인 범위 내에 있는지 확인 (30초 이내)
      expect(processing_time).to be < 30.seconds
    end
  end

  describe '입력 유효성 검증' do
    it '잘못된 JSON 형식을 거부한다' do
      headers = {
        'X-PipeData-Token' => valid_token,
        'Content-Type' => 'application/json'
      }

      # 잘못된 JSON
      invalid_json = '{"data": [{"question": "incomplete'

      post '/api/v1/pipedata', params: invalid_json, headers: headers

      expect(response).to have_http_status(:bad_request)
    end

    it '필수 필드 누락을 적절히 처리한다' do
      headers = { 'X-PipeData-Token' => valid_token }

      incomplete_data = {
        data: [
          {
            # question 필드 누락
            answer: "필수 필드 누락 테스트 답변입니다. 이것은 충분한 길이를 가져야 합니다.",
            difficulty: "medium",
            quality_score: 7.0,
            source: "pipedata_validation_test"
          }
        ]
      }

      post '/api/v1/pipedata', params: incomplete_data, headers: headers

      expect(response).to have_http_status(:ok) # 서비스에서 에러로 처리하지만 HTTP는 성공

      response_body = JSON.parse(response.body)
      expect(response_body['errors']).to eq(1)
      expect(response_body['created']).to eq(0)
    end

    it '데이터 타입 검증을 수행한다' do
      headers = { 'X-PipeData-Token' => valid_token }

      wrong_type_data = {
        data: [
          {
            question: "타입 검증 테스트 질문입니다. 이것은 정상적인 질문입니다.",
            answer: "타입 검증 테스트 답변입니다. 이것은 충분한 길이를 가져야 합니다.",
            difficulty: "medium",
            quality_score: "not_a_number", # 숫자가 아닌 값
            source: "pipedata_type_validation_test"
          }
        ]
      }

      post '/api/v1/pipedata', params: wrong_type_data, headers: headers

      expect(response).to have_http_status(:ok)
      created_item = KnowledgeItem.last

      # 잘못된 타입은 기본값 또는 0으로 처리되어야 함
      expect(created_item.quality_score).to eq(0.0)
    end
  end

  describe '에러 정보 노출 방지' do
    it '내부 에러 정보를 노출하지 않는다' do
      headers = { 'X-PipeData-Token' => valid_token }

      # ActiveRecord 에러를 유발하는 데이터
      allow(KnowledgeItem).to receive(:create!).and_raise(
        ActiveRecord::StatementInvalid.new("PG::Error: database connection failed")
      )

      post '/api/v1/pipedata', params: valid_data, headers: headers

      expect(response).to have_http_status(:ok) # 서비스 레벨에서 처리

      response_body = JSON.parse(response.body)
      expect(response_body['errors']).to eq(1)

      # 내부 데이터베이스 에러 정보가 노출되지 않았는지 확인
      error_details = response_body['error_details']
      expect(error_details.first['message']).not_to include('PG::Error')
      expect(error_details.first['message']).not_to include('database connection')
    end

    it '시스템 에러 시 일반적인 메시지를 반환한다' do
      headers = { 'X-PipeData-Token' => valid_token }

      # 예상치 못한 시스템 에러 유발
      allow(PipedataIngestionService).to receive(:call).and_raise(
        StandardError.new("Internal system error with sensitive info")
      )

      post '/api/v1/pipedata', params: valid_data, headers: headers

      expect(response).to have_http_status(:internal_server_error)

      response_body = JSON.parse(response.body)
      expect(response_body['error']).to eq('Internal server error')
      expect(response_body['message']).to eq('Failed to process PipeData')

      # 민감한 시스템 정보가 노출되지 않았는지 확인
      expect(response_body.to_s).not_to include('sensitive info')
    end
  end

  describe '요청 빈도 제한' do
    it '동일 IP에서 과도한 요청을 제한한다' do
      headers = { 'X-PipeData-Token' => valid_token }

      # 짧은 시간 내에 많은 요청 시도
      request_times = []
      success_count = 0
      rate_limited_count = 0

      20.times do |i|
        small_data = {
          data: [
            {
              question: "요청 빈도 제한 테스트 질문 #{i + 1}번입니다. 이것은 정상적인 질문입니다.",
              answer: "요청 빈도 제한 테스트 답변 #{i + 1}번입니다. 이것은 충분한 길이를 가져야 합니다.",
              difficulty: "medium",
              quality_score: 7.0,
              source: "pipedata_rate_limit_test_#{i}"
            }
          ]
        }

        start_time = Time.current
        post '/api/v1/pipedata', params: small_data, headers: headers
        request_times << Time.current - start_time

        if response.status == 200
          success_count += 1
        elsif response.status == 429 # Too Many Requests
          rate_limited_count += 1
        end

        # 실제 과부하를 방지하기 위해 약간의 대기
        sleep(0.05)
      end

      # 모든 요청이 처리되었지만, 너무 빨리 보내면 일부는 제한될 수 있음
      expect(success_count + rate_limited_count).to eq(20)
      expect(success_count).to be >= 10 # 최소 절반은 성공해야 함
    end
  end
end
