# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'PipeData Integration', type: :request do
  let(:valid_token) { 'test_pipedata_token' }
  let(:invalid_token) { 'invalid_token' }

  let(:realistic_pipedata) do
    {
      data: [
        {
          question: "Excel에서 VLOOKUP 함수를 사용할 때 #N/A 오류가 계속 발생합니다. 어떻게 해결할 수 있나요?",
          answer: "VLOOKUP #N/A 오류의 주요 원인과 해결방법:\n\n1. **검색값 불일치**: 찾는 값이 정확히 일치하지 않음\n   - 공백, 대소문자, 숨겨진 문자 확인\n   - TRIM 함수로 공백 제거\n\n2. **완전일치 설정**: 네 번째 인수를 FALSE로 설정\n   ```excel\n   =VLOOKUP(A1, B:D, 2, FALSE)\n   ```\n\n3. **테이블 범위 확인**: 검색값이 테이블의 첫 번째 열에 있는지 확인\n\n4. **IFERROR 함수 활용**: 오류 발생 시 대체값 표시\n   ```excel\n   =IFERROR(VLOOKUP(A1, B:D, 2, FALSE), \"찾을 수 없음\")\n   ```",
          difficulty: "medium",
          quality_score: 9.2,
          source: "pipedata_stackoverflow",
          excel_functions: [ "VLOOKUP", "IFERROR", "TRIM" ],
          code_snippets: [
            "=VLOOKUP(A1, B:D, 2, FALSE)",
            "=IFERROR(VLOOKUP(A1, B:D, 2, FALSE), \"찾을 수 없음\")",
            "=VLOOKUP(TRIM(A1), B:D, 2, FALSE)"
          ],
          tags: [ "excel", "vlookup", "error-handling", "na-error" ],
          metadata: {
            stackoverflow_id: "12345678",
            votes: 156,
            views: 45231,
            accepted: true,
            author: "excel_expert_2023",
            created_date: "2023-08-15",
            updated_date: "2023-08-20"
          }
        },
        {
          question: "피벗 테이블에서 날짜별로 데이터를 그룹화하고 싶은데, 월별로만 표시됩니다. 일별로 보려면 어떻게 해야 하나요?",
          answer: "피벗 테이블에서 날짜 그룹화를 변경하는 방법:\n\n1. **날짜 필드 클릭**: 피벗 테이블의 날짜 필드를 우클릭\n\n2. **그룹 해제**: '그룹 해제' 선택하여 기존 그룹화 제거\n\n3. **새로운 그룹화 설정**: \n   - 날짜 필드 다시 우클릭\n   - '그룹' 선택\n   - '일' 옵션 선택\n\n4. **자동 그룹화 비활성화**: \n   - 파일 > 옵션 > 데이터\n   - '피벗 테이블에서 자동으로 날짜/시간 열 감지' 체크 해제\n\n이렇게 하면 일별 데이터를 볼 수 있습니다.",
          difficulty: "easy",
          quality_score: 8.7,
          source: "pipedata_reddit",
          excel_functions: [ "PIVOT_TABLE" ],
          code_snippets: [],
          tags: [ "excel", "pivot-table", "date-grouping", "daily-data" ],
          metadata: {
            reddit_post_id: "abc123def",
            subreddit: "excel",
            upvotes: 89,
            comments: 23,
            op_confirmed: true,
            flair: "solved",
            created_date: "2023-09-10"
          }
        },
        {
          question: "INDEX와 MATCH 함수를 조합해서 사용하는 이유가 무엇인가요? VLOOKUP와 어떤 차이가 있나요?",
          answer: "INDEX + MATCH 조합의 장점과 VLOOKUP와의 차이:\n\n## INDEX + MATCH의 장점:\n\n1. **양방향 검색 가능**: 왼쪽 열에서도 검색 가능\n2. **열 삽입/삭제에 안전**: 열 번호 대신 실제 열 참조 사용\n3. **성능 우수**: 대용량 데이터에서 더 빠름\n4. **유연성**: 복잡한 조건 검색 가능\n\n## 사용 예시:\n```excel\n// 기본 INDEX + MATCH\n=INDEX(C:C, MATCH(A1, B:B, 0))\n\n// 두 조건 검색\n=INDEX(D:D, MATCH(1, (A:A=A1)*(B:B=B1), 0))\n```\n\n## VLOOKUP 대비 장점:\n- 검색 열이 반환 열 왼쪽에 있어도 됨\n- 열 구조 변경에 영향 받지 않음\n- 배열 수식과 조합하여 다중 조건 검색 가능",
          difficulty: "hard",
          quality_score: 9.5,
          source: "pipedata_stackoverflow",
          excel_functions: [ "INDEX", "MATCH", "VLOOKUP" ],
          code_snippets: [
            "=INDEX(C:C, MATCH(A1, B:B, 0))",
            "=INDEX(D:D, MATCH(1, (A:A=A1)*(B:B=B1), 0))",
            "=VLOOKUP(A1, B:D, 2, FALSE)"
          ],
          tags: [ "excel", "index", "match", "vlookup", "advanced" ],
          metadata: {
            stackoverflow_id: "87654321",
            votes: 234,
            views: 78543,
            accepted: true,
            author: "excel_master_pro",
            created_date: "2023-07-22",
            updated_date: "2023-07-25",
            bounty: 50
          }
        }
      ]
    }
  end

  before do
    # 환경 변수 설정
    allow(Rails.application.credentials).to receive(:pipedata_api_token).and_return(valid_token)
    allow(ENV).to receive(:[]).with('PIPEDATA_API_TOKEN').and_return(valid_token)
  end

  describe 'POST /api/v1/pipedata' do
    context 'End-to-End 통합 테스트' do
      it 'PipeData → Rails → DB 전체 플로우가 정상 작동한다' do
        headers = { 'X-PipeData-Token' => valid_token }

        # 요청 전 상태 확인
        expect(KnowledgeItem.count).to eq(0)

        # API 요청
        post '/api/v1/pipedata', params: realistic_pipedata, headers: headers

        # 응답 검증
        expect(response).to have_http_status(:ok)
        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be true
        expect(response_body['created']).to eq(3)
        expect(response_body['processed']).to eq(3)
        expect(response_body['duplicates']).to eq(0)
        expect(response_body['errors']).to eq(0)

        # 데이터베이스 검증
        expect(KnowledgeItem.count).to eq(3)

        # 첫 번째 아이템 상세 검증
        vlookup_item = KnowledgeItem.find_by(source: 'pipedata_stackoverflow', difficulty: 1)
        expect(vlookup_item).to be_present
        expect(vlookup_item.question).to include('VLOOKUP')
        expect(vlookup_item.answer).to include('#N/A 오류의 주요 원인')
        expect(vlookup_item.excel_functions).to include('VLOOKUP', 'IFERROR', 'TRIM')
        expect(vlookup_item.code_snippets).to have(3).items
        expect(vlookup_item.quality_score).to eq(9.2)
        expect(vlookup_item.metadata['stackoverflow_id']).to eq('12345678')
        expect(vlookup_item.metadata['votes']).to eq(156)
        expect(vlookup_item.embedding).to be_an(Array)
        expect(vlookup_item.embedding.length).to eq(1536)

        # 두 번째 아이템 검증 (Reddit)
        pivot_item = KnowledgeItem.find_by(source: 'pipedata_reddit')
        expect(pivot_item).to be_present
        expect(pivot_item.question).to include('피벗 테이블')
        expect(pivot_item.difficulty).to eq(0) # easy
        expect(pivot_item.metadata['reddit_post_id']).to eq('abc123def')
        expect(pivot_item.metadata['op_confirmed']).to be true

        # 세 번째 아이템 검증 (고급 함수)
        index_match_item = KnowledgeItem.find_by(difficulty: 2) # hard
        expect(index_match_item).to be_present
        expect(index_match_item.question).to include('INDEX와 MATCH')
        expect(index_match_item.excel_functions).to include('INDEX', 'MATCH', 'VLOOKUP')
        expect(index_match_item.quality_score).to eq(9.5)
      end

      it '실제 PipeData 형식 데이터로 성능을 테스트한다' do
        headers = { 'X-PipeData-Token' => valid_token }

        start_time = Time.current

        post '/api/v1/pipedata', params: realistic_pipedata, headers: headers

        response_time = Time.current - start_time

        expect(response).to have_http_status(:ok)
        expect(response_time).to be < 2.seconds # 3건 처리는 2초 이내

        # 메모리 사용량 확인 (간접적)
        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be true
      end

      it 'API 응답 시간이 합리적이다' do
        headers = { 'X-PipeData-Token' => valid_token }

        # 여러 번 요청하여 평균 응답 시간 측정
        response_times = []

        5.times do |i|
          data_with_unique_questions = {
            data: realistic_pipedata[:data].map.with_index do |item, index|
              item.merge(
                question: "#{item[:question]} - 테스트 #{i}-#{index}",
                source: "pipedata_performance_test_#{i}"
              )
            end
          }

          start_time = Time.current
          post '/api/v1/pipedata', params: data_with_unique_questions, headers: headers
          response_times << Time.current - start_time

          expect(response).to have_http_status(:ok)
        end

        average_response_time = response_times.sum / response_times.length
        expect(average_response_time).to be < 1.second
      end

      it '메모리 사용량을 모니터링한다' do
        headers = { 'X-PipeData-Token' => valid_token }

        # GC 강제 실행하여 메모리 정리
        GC.start
        before_memory = GC.stat[:heap_allocated_pages]

        # 요청 실행
        post '/api/v1/pipedata', params: realistic_pipedata, headers: headers

        after_memory = GC.stat[:heap_allocated_pages]
        memory_increase = after_memory - before_memory

        expect(response).to have_http_status(:ok)
        # 메모리 증가량이 5000 페이지(약 20MB) 이내여야 함
        expect(memory_increase).to be < 5000
      end
    end

    context '동시성 테스트' do
      it '동시 요청을 안전하게 처리한다' do
        headers = { 'X-PipeData-Token' => valid_token }

        # 10개의 스레드에서 동시 요청
        threads = []
        results = []

        10.times do |i|
          threads << Thread.new do
            unique_data = {
              data: [
                {
                  question: "동시성 테스트 질문 #{i}번입니다. 이것은 스레드 #{Thread.current.object_id}에서 생성된 질문입니다.",
                  answer: "동시성 테스트 답변 #{i}번입니다. 이것은 스레드 안전성을 확인하기 위한 답변으로 충분한 길이를 가져야 합니다.",
                  difficulty: "medium",
                  quality_score: 7.0 + (i % 3),
                  source: "pipedata_concurrency_test_#{i}",
                  excel_functions: [ "SUM", "AVERAGE" ],
                  code_snippets: [ "=SUM(A1:A10)" ],
                  tags: [ "concurrency", "test" ],
                  metadata: { thread_id: Thread.current.object_id, index: i }
                }
              ]
            }

            begin
              post '/api/v1/pipedata', params: unique_data, headers: headers
              results << {
                status: response.status,
                body: JSON.parse(response.body),
                thread_id: Thread.current.object_id
              }
            rescue => e
              results << {
                error: e.message,
                thread_id: Thread.current.object_id
              }
            end
          end
        end

        # 모든 스레드 완료 대기
        threads.each(&:join)

        # 결과 검증
        expect(results.length).to eq(10)

        # 모든 요청이 성공했는지 확인
        success_count = results.count { |r| r[:status] == 200 }
        expect(success_count).to eq(10)

        # 모든 아이템이 생성되었는지 확인
        created_count = results.sum { |r| r[:body]['created'] if r[:body] }
        expect(created_count).to eq(10)

        # 데이터베이스에 10개 아이템이 생성되었는지 확인
        expect(KnowledgeItem.where(source: /pipedata_concurrency_test_/).count).to eq(10)
      end

      it 'Race condition 없이 중복 검사를 수행한다' do
        headers = { 'X-PipeData-Token' => valid_token }

        # 동일한 질문으로 동시 요청 (첫 번째만 생성되고 나머지는 중복으로 처리되어야 함)
        same_question_data = {
          data: [
            {
              question: "Race condition 테스트용 질문입니다. 이 질문은 여러 스레드에서 동시에 처리됩니다.",
              answer: "Race condition 테스트용 답변입니다. 이것은 중복 검사 테스트를 위한 답변으로 충분한 길이를 가져야 합니다.",
              difficulty: "medium",
              quality_score: 8.0,
              source: "pipedata_race_condition_test",
              excel_functions: [ "TEST" ],
              code_snippets: [ "=TEST()" ],
              tags: [ "race-condition", "test" ]
            }
          ]
        }

        threads = []
        results = []

        5.times do
          threads << Thread.new do
            post '/api/v1/pipedata', params: same_question_data, headers: headers
            results << JSON.parse(response.body)
          end
        end

        threads.each(&:join)

        # 결과 검증
        total_created = results.sum { |r| r['created'] }
        total_duplicates = results.sum { |r| r['duplicates'] }

        # 하나만 생성되고 나머지는 중복으로 처리되어야 함
        expect(total_created).to eq(1)
        expect(total_duplicates).to eq(4)

        # 데이터베이스에 1개만 존재하는지 확인
        matching_items = KnowledgeItem.where(source: 'pipedata_race_condition_test')
        expect(matching_items.count).to eq(1)
      end
    end

    context '데이터 일관성 검증' do
      it '복잡한 메타데이터가 올바르게 저장된다' do
        headers = { 'X-PipeData-Token' => valid_token }

        complex_metadata_data = {
          data: [
            {
              question: "복잡한 메타데이터 테스트 질문입니다. 이것은 중첩된 JSON 구조를 테스트합니다.",
              answer: "복잡한 메타데이터 테스트 답변입니다. 이것은 JSON 직렬화/역직렬화를 확인하기 위한 답변입니다.",
              difficulty: "expert",
              quality_score: 9.8,
              source: "pipedata_complex_metadata_test",
              excel_functions: [ "COMPLEX_FUNCTION" ],
              code_snippets: [ "=COMPLEX_FUNCTION(A1:A10)" ],
              tags: [ "complex", "metadata", "test" ],
              metadata: {
                nested_object: {
                  level1: {
                    level2: {
                      value: "deep_nested_value",
                      array: [ 1, 2, 3, "string" ],
                      boolean: true,
                      null_value: nil
                    }
                  }
                },
                unicode_text: "한글 텍스트 🚀 emoji",
                special_chars: "!@#$%^&*()_+-=[]{}|;':\",./<>?",
                large_number: 999999999999999,
                floating_point: 3.14159265359,
                date_string: "2023-12-25T10:30:00Z"
              }
            }
          ]
        }

        post '/api/v1/pipedata', params: complex_metadata_data, headers: headers

        expect(response).to have_http_status(:ok)

        created_item = KnowledgeItem.last
        expect(created_item.metadata['nested_object']['level1']['level2']['value']).to eq('deep_nested_value')
        expect(created_item.metadata['nested_object']['level1']['level2']['array']).to eq([ 1, 2, 3, 'string' ])
        expect(created_item.metadata['unicode_text']).to eq('한글 텍스트 🚀 emoji')
        expect(created_item.metadata['special_chars']).to eq("!@#$%^&*()_+-=[]{}|;':\",./<>?")
        expect(created_item.metadata['large_number']).to eq(999999999999999)
        expect(created_item.metadata['floating_point']).to eq(3.14159265359)
      end

      it '벡터 임베딩이 일관되게 생성된다' do
        headers = { 'X-PipeData-Token' => valid_token }

        post '/api/v1/pipedata', params: realistic_pipedata, headers: headers

        expect(response).to have_http_status(:ok)

        # 모든 생성된 아이템의 임베딩 확인
        created_items = KnowledgeItem.last(3)

        created_items.each do |item|
          expect(item.embedding).to be_present
          expect(item.embedding).to be_an(Array)
          expect(item.embedding.length).to eq(1536)

          # 모든 임베딩 값이 -1.0과 1.0 사이에 있는지 확인
          item.embedding.each do |value|
            expect(value).to be_between(-1.0, 1.0)
            expect(value).to be_a(Numeric)
          end
        end
      end
    end

    context '에러 처리 테스트' do
      it '부분적 실패 상황을 올바르게 처리한다' do
        headers = { 'X-PipeData-Token' => valid_token }

        mixed_data = {
          data: [
            realistic_pipedata[:data][0], # 정상 데이터
            {
              question: "", # 에러 데이터 (빈 질문)
              answer: "에러 테스트 답변입니다.",
              difficulty: "medium",
              quality_score: 7.0,
              source: "pipedata_error_test"
            },
            realistic_pipedata[:data][1].merge( # 정상 데이터 (수정된)
              question: "수정된 피벗 테이블 질문입니다. 원본과 다른 질문으로 중복이 아닙니다.",
              source: "pipedata_mixed_test"
            ),
            {
              # 에러 데이터 (답변 없음)
              question: "답변이 없는 질문입니다. 이것은 에러를 유발해야 합니다.",
              difficulty: "medium",
              quality_score: 7.0,
              source: "pipedata_error_test"
            }
          ]
        }

        post '/api/v1/pipedata', params: mixed_data, headers: headers

        expect(response).to have_http_status(:ok)

        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be true
        expect(response_body['processed']).to eq(4)
        expect(response_body['created']).to eq(2) # 정상 데이터 2개만 생성
        expect(response_body['duplicates']).to eq(0)
        expect(response_body['errors']).to eq(2) # 에러 데이터 2개
        expect(response_body['error_details']).to have(2).items

        # 정상 데이터만 DB에 저장되었는지 확인
        expect(KnowledgeItem.count).to eq(2)
      end
    end
  end

  describe 'GET /api/v1/pipedata' do
    before do
      # 테스트 데이터 생성
      3.times do |i|
        KnowledgeItem.create!(
          question: "통계 테스트 질문 #{i + 1}번입니다. 이것은 통계 계산용 질문입니다.",
          answer: "통계 테스트 답변 #{i + 1}번입니다. 이것은 통계 계산용 답변으로 충분한 길이를 가져야 합니다.",
          difficulty: i % 4,
          quality_score: 7.0 + i,
          source: "pipedata_stats_test_#{i}",
          search_count: i * 10,
          use_count: i * 5,
          helpful_votes: i * 2,
          embedding: Array.new(1536) { rand(-1.0..1.0) }
        )
      end
    end

    it '정확한 통계 정보를 반환한다' do
      headers = { 'X-PipeData-Token' => valid_token }

      get '/api/v1/pipedata', headers: headers

      expect(response).to have_http_status(:ok)

      response_body = JSON.parse(response.body)
      expect(response_body['total_records']).to eq(3)
      expect(response_body['average_quality']).to eq(8.0) # (7.0 + 8.0 + 9.0) / 3
      expect(response_body['status']).to eq('active')
      expect(response_body['rails_version']).to eq(Rails.version)
      expect(response_body['app_version']).to eq('1.0.0')
      expect(response_body['sources']).to be_a(Hash)
      expect(response_body['sources'].keys).to include('pipedata_stats_test_0', 'pipedata_stats_test_1', 'pipedata_stats_test_2')
    end
  end
end
