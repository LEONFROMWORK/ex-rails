# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'PipeData Performance', type: :request do
  let(:valid_token) { 'test_pipedata_token' }

  before do
    allow(Rails.application.credentials).to receive(:pipedata_api_token).and_return(valid_token)
    allow(ENV).to receive(:[]).with('PIPEDATA_API_TOKEN').and_return(valid_token)
  end

  describe '성능 벤치마크' do
    context '소량 데이터 처리' do
      it '100건 데이터를 1초 이내에 처리한다' do
        headers = { 'X-PipeData-Token' => valid_token }

        # 100건 데이터 생성
        large_data = {
          data: Array.new(100) do |i|
            {
              question: "성능 테스트 질문 #{i + 1}번입니다. 이것은 100건 배치 처리 테스트용 질문으로 충분한 길이를 가져야 합니다.",
              answer: "성능 테스트 답변 #{i + 1}번입니다. 이것은 100건 배치 처리 테스트용 답변으로 충분한 길이를 가져야 하며, 실제 Excel 관련 내용을 포함해야 합니다. VLOOKUP, INDEX, MATCH 등의 함수에 대한 설명이 포함될 수 있습니다.",
              difficulty: [ "easy", "medium", "hard", "expert" ][i % 4],
              quality_score: 6.0 + (i % 5),
              source: "pipedata_performance_100",
              excel_functions: [ "SUM", "AVERAGE", "COUNT" ][i % 3],
              code_snippets: [ "=SUM(A1:A10)", "=AVERAGE(B1:B10)", "=COUNT(C1:C10)" ][i % 3],
              tags: [ "performance", "test", "100batch" ],
              metadata: {
                batch_id: "100_batch_test",
                index: i,
                timestamp: Time.current.iso8601
              }
            }
          end
        }

        # 성능 측정
        start_time = Time.current
        start_memory = GC.stat[:heap_allocated_pages]

        post '/api/v1/pipedata', params: large_data, headers: headers

        end_time = Time.current
        end_memory = GC.stat[:heap_allocated_pages]

        processing_time = end_time - start_time
        memory_increase = end_memory - start_memory

        # 검증
        expect(response).to have_http_status(:ok)
        expect(processing_time).to be < 1.second

        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be true
        expect(response_body['created']).to eq(100)
        expect(response_body['processed']).to eq(100)

        # 메모리 사용량도 확인 (10MB = 약 2500 페이지)
        expect(memory_increase).to be < 2500

        Rails.logger.info "100건 처리 시간: #{processing_time.round(3)}초, 메모리 증가: #{memory_increase}페이지"
      end
    end

    context '중량 데이터 처리' do
      it '1000건 데이터를 10초 이내에 처리한다' do
        headers = { 'X-PipeData-Token' => valid_token }

        # 1000건 데이터 생성
        massive_data = {
          data: Array.new(1000) do |i|
            {
              question: "대용량 성능 테스트 질문 #{i + 1}번입니다. 이것은 1000건 대용량 배치 처리 테스트용 질문으로 충분한 길이를 가져야 합니다. Excel의 다양한 함수들에 대한 질문이며, 실제 사용자가 자주 묻는 질문들을 시뮬레이션합니다.",
              answer: "대용량 성능 테스트 답변 #{i + 1}번입니다. 이것은 1000건 대용량 배치 처리 테스트용 답변으로 매우 긴 내용을 포함해야 합니다. Excel에서 #{[ 'VLOOKUP', 'INDEX', 'MATCH', 'SUMIF', 'COUNTIF' ][i % 5]} 함수를 사용하는 방법에 대한 상세한 설명이 포함되어 있습니다. 이 함수는 데이터 분석에서 매우 중요한 역할을 하며, 올바른 사용법을 익히는 것이 중요합니다. 다양한 예시와 주의사항도 함께 제공됩니다.",
              difficulty: [ "easy", "medium", "hard", "expert" ][i % 4],
              quality_score: 5.0 + (i % 6),
              source: "pipedata_performance_1000",
              excel_functions: [ "VLOOKUP", "INDEX", "MATCH", "SUMIF", "COUNTIF", "PIVOT_TABLE" ][i % 6],
              code_snippets: [
                "=VLOOKUP(A1,B:C,2,FALSE)",
                "=INDEX(C:C,MATCH(A1,B:B,0))",
                "=SUMIF(A:A,\">100\",B:B)",
                "=COUNTIF(A:A,\"완료\")"
              ][i % 4],
              tags: [ "performance", "test", "1000batch", "large-scale" ],
              metadata: {
                batch_id: "1000_batch_test",
                index: i,
                timestamp: Time.current.iso8601,
                category: [ "formula", "pivot", "chart", "macro" ][i % 4],
                priority: i % 3 == 0 ? "high" : "normal"
              }
            }
          end
        }

        # 성능 측정
        start_time = Time.current
        start_memory = GC.stat[:heap_allocated_pages]
        gc_start_time = GC.stat[:total_time]

        post '/api/v1/pipedata', params: massive_data, headers: headers

        end_time = Time.current
        end_memory = GC.stat[:heap_allocated_pages]
        gc_end_time = GC.stat[:total_time]

        processing_time = end_time - start_time
        memory_increase = end_memory - start_memory
        gc_time = gc_end_time - gc_start_time

        # 검증
        expect(response).to have_http_status(:ok)
        expect(processing_time).to be < 10.seconds

        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be true
        expect(response_body['created']).to eq(1000)
        expect(response_body['processed']).to eq(1000)

        # 메모리 사용량 확인 (100MB = 약 25000 페이지)
        expect(memory_increase).to be < 25000

        Rails.logger.info "1000건 처리 시간: #{processing_time.round(3)}초, 메모리 증가: #{memory_increase}페이지, GC 시간: #{gc_time}ms"
      end
    end

    context '메모리 효율성' do
      it '요청당 메모리 사용량이 100MB 이하이다' do
        headers = { 'X-PipeData-Token' => valid_token }

        # GC 강제 실행으로 메모리 정리
        3.times { GC.start }
        before_memory = GC.stat[:heap_allocated_pages]

        data = {
          data: Array.new(50) do |i|
            {
              question: "메모리 효율성 테스트 질문 #{i + 1}번입니다. " + "긴 텍스트를 추가하여 메모리 사용량을 늘립니다. " * 10,
              answer: "메모리 효율성 테스트 답변 #{i + 1}번입니다. " + "매우 긴 답변 내용을 포함하여 메모리 사용 패턴을 확인합니다. " * 20,
              difficulty: "medium",
              quality_score: 7.5,
              source: "pipedata_memory_test",
              excel_functions: [ "MEMORY_TEST" ],
              code_snippets: [ "=MEMORY_TEST()" ],
              tags: [ "memory", "efficiency", "test" ],
              metadata: {
                large_data: "X" * 1000, # 1KB 데이터
                array_data: Array.new(100) { |j| "item_#{j}" },
                nested_data: {
                  level1: { level2: { level3: "deep_value" * 100 } }
                }
              }
            }
          end
        }

        post '/api/v1/pipedata', params: data, headers: headers

        # 메모리 사용량 측정
        3.times { GC.start } # GC 실행하여 정확한 메모리 사용량 측정
        after_memory = GC.stat[:heap_allocated_pages]
        memory_increase = after_memory - before_memory

        expect(response).to have_http_status(:ok)

        # 100MB = 약 25000 페이지 (1페이지 ≈ 4KB)
        expect(memory_increase).to be < 25000

        Rails.logger.info "50건(메모리 집약적) 처리 후 메모리 증가: #{memory_increase}페이지 (약 #{(memory_increase * 4 / 1024.0).round(2)}MB)"
      end

      it '메모리 누수가 없다' do
        headers = { 'X-PipeData-Token' => valid_token }

        # 기준 메모리 사용량 측정
        3.times { GC.start }
        baseline_memory = GC.stat[:heap_allocated_pages]

        # 여러 번 요청 실행
        10.times do |iteration|
          data = {
            data: [
              {
                question: "메모리 누수 테스트 질문 #{iteration + 1}번입니다. 이것은 반복 실행 테스트용 질문입니다.",
                answer: "메모리 누수 테스트 답변 #{iteration + 1}번입니다. 이것은 반복 실행 테스트용 답변으로 충분한 길이를 가져야 합니다.",
                difficulty: "medium",
                quality_score: 7.0,
                source: "pipedata_memory_leak_test_#{iteration}",
                excel_functions: [ "TEST" ],
                code_snippets: [ "=TEST()" ],
                tags: [ "memory-leak", "test" ],
                metadata: { iteration: iteration }
              }
            ]
          }

          post '/api/v1/pipedata', params: data, headers: headers
          expect(response).to have_http_status(:ok)
        end

        # 최종 메모리 사용량 측정
        3.times { GC.start }
        final_memory = GC.stat[:heap_allocated_pages]
        total_memory_increase = final_memory - baseline_memory

        # 10번의 요청 후 메모리 증가량이 합리적인 범위 내에 있는지 확인
        # 각 요청당 평균 메모리 증가량이 500페이지(약 2MB) 이하여야 함
        average_memory_per_request = total_memory_increase / 10.0
        expect(average_memory_per_request).to be < 500

        Rails.logger.info "10회 반복 실행 후 총 메모리 증가: #{total_memory_increase}페이지, 평균: #{average_memory_per_request.round(2)}페이지/요청"
      end
    end

    context 'DB 연결 풀 효율성' do
      it 'DB 연결을 효율적으로 사용한다' do
        headers = { 'X-PipeData-Token' => valid_token }

        # 연결 풀 상태 확인
        pool = ActiveRecord::Base.connection_pool
        initial_connections = pool.connections.count

        data = {
          data: Array.new(20) do |i|
            {
              question: "DB 연결 테스트 질문 #{i + 1}번입니다. 이것은 DB 연결 효율성 테스트용 질문입니다.",
              answer: "DB 연결 테스트 답변 #{i + 1}번입니다. 이것은 DB 연결 효율성 테스트용 답변으로 충분한 길이를 가져야 합니다.",
              difficulty: "medium",
              quality_score: 7.0,
              source: "pipedata_db_connection_test",
              excel_functions: [ "DB_TEST" ],
              code_snippets: [ "=DB_TEST()" ],
              tags: [ "db", "connection", "test" ]
            }
          end
        }

        post '/api/v1/pipedata', params: data, headers: headers

        expect(response).to have_http_status(:ok)

        # 요청 후 연결 수가 크게 증가하지 않았는지 확인
        final_connections = pool.connections.count
        connection_increase = final_connections - initial_connections

        # 연결 증가량이 5개 이하여야 함 (합리적 범위)
        expect(connection_increase).to be <= 5

        # 사용 가능한 연결이 있는지 확인
        expect(pool.connections.count).to be < pool.size

        Rails.logger.info "DB 연결 상태 - 초기: #{initial_connections}, 최종: #{final_connections}, 증가: #{connection_increase}, 풀 크기: #{pool.size}"
      end
    end

    context '응답 시간 일관성' do
      it '여러 요청의 응답 시간이 일관되다' do
        headers = { 'X-PipeData-Token' => valid_token }
        response_times = []

        # 20번의 요청 실행하여 응답 시간 측정
        20.times do |i|
          data = {
            data: [
              {
                question: "응답 시간 일관성 테스트 질문 #{i + 1}번입니다. 이것은 응답 시간 측정용 질문입니다.",
                answer: "응답 시간 일관성 테스트 답변 #{i + 1}번입니다. 이것은 응답 시간 측정용 답변으로 충분한 길이를 가져야 합니다.",
                difficulty: "medium",
                quality_score: 7.0,
                source: "pipedata_response_time_test_#{i}",
                excel_functions: [ "TIMER" ],
                code_snippets: [ "=NOW()" ],
                tags: [ "response-time", "consistency", "test" ]
              }
            ]
          }

          start_time = Time.current
          post '/api/v1/pipedata', params: data, headers: headers
          response_time = Time.current - start_time

          expect(response).to have_http_status(:ok)
          response_times << response_time
        end

        # 통계 계산
        average_time = response_times.sum / response_times.length
        max_time = response_times.max
        min_time = response_times.min
        std_dev = Math.sqrt(response_times.map { |t| (t - average_time) ** 2 }.sum / response_times.length)

        # 검증
        expect(average_time).to be < 0.5.seconds
        expect(max_time).to be < 1.0.seconds
        expect(std_dev).to be < 0.2.seconds # 표준편차가 0.2초 이하 (일관성)

        Rails.logger.info "응답 시간 통계 - 평균: #{average_time.round(3)}초, 최대: #{max_time.round(3)}초, 최소: #{min_time.round(3)}초, 표준편차: #{std_dev.round(3)}초"
      end
    end

    context '에러 복구 성능' do
      it '에러 상황에서도 성능이 저하되지 않는다' do
        headers = { 'X-PipeData-Token' => valid_token }

        # 에러가 포함된 데이터와 정상 데이터 혼합
        mixed_data = {
          data: Array.new(50) do |i|
            if i % 5 == 0 # 20%는 에러 데이터
              {
                question: "", # 에러: 빈 질문
                answer: "에러 테스트 답변입니다.",
                difficulty: "medium",
                quality_score: 7.0,
                source: "pipedata_error_performance_test"
              }
            else # 80%는 정상 데이터
              {
                question: "에러 복구 성능 테스트 질문 #{i + 1}번입니다. 이것은 에러 복구 성능 테스트용 질문입니다.",
                answer: "에러 복구 성능 테스트 답변 #{i + 1}번입니다. 이것은 에러 복구 성능 테스트용 답변으로 충분한 길이를 가져야 합니다.",
                difficulty: "medium",
                quality_score: 7.0,
                source: "pipedata_error_performance_test",
                excel_functions: [ "ERROR_TEST" ],
                code_snippets: [ "=ERROR_TEST()" ],
                tags: [ "error", "recovery", "performance" ]
              }
            end
          end
        }

        start_time = Time.current
        post '/api/v1/pipedata', params: mixed_data, headers: headers
        processing_time = Time.current - start_time

        expect(response).to have_http_status(:ok)
        expect(processing_time).to be < 2.seconds # 에러 처리 포함해도 2초 이내

        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be true
        expect(response_body['processed']).to eq(50)
        expect(response_body['created']).to eq(40) # 정상 데이터 40개
        expect(response_body['errors']).to eq(10) # 에러 데이터 10개

        Rails.logger.info "에러 포함 50건 처리 시간: #{processing_time.round(3)}초 (에러율: 20%)"
      end
    end
  end

  describe '부하 테스트' do
    context '동시 사용자 시뮬레이션' do
      it '10명의 동시 사용자 요청을 처리한다' do
        headers = { 'X-PipeData-Token' => valid_token }
        threads = []
        results = []

        start_time = Time.current

        # 10개 스레드로 동시 요청
        10.times do |user_id|
          threads << Thread.new do
            user_data = {
              data: Array.new(5) do |i|
                {
                  question: "동시 사용자 #{user_id + 1} 질문 #{i + 1}번입니다. 이것은 동시성 테스트용 질문입니다.",
                  answer: "동시 사용자 #{user_id + 1} 답변 #{i + 1}번입니다. 이것은 동시성 테스트용 답변으로 충분한 길이를 가져야 합니다.",
                  difficulty: "medium",
                  quality_score: 7.0,
                  source: "pipedata_concurrent_user_test_#{user_id}",
                  excel_functions: [ "CONCURRENT" ],
                  code_snippets: [ "=CONCURRENT()" ],
                  tags: [ "concurrent", "user", user_id.to_s ]
                }
              end
            }

            thread_start_time = Time.current
            begin
              post '/api/v1/pipedata', params: user_data, headers: headers
              thread_end_time = Time.current

              results << {
                user_id: user_id,
                status: response.status,
                processing_time: thread_end_time - thread_start_time,
                response_body: JSON.parse(response.body),
                success: response.status == 200
              }
            rescue => e
              results << {
                user_id: user_id,
                error: e.message,
                success: false
              }
            end
          end
        end

        # 모든 스레드 완료 대기
        threads.each(&:join)
        total_time = Time.current - start_time

        # 결과 검증
        expect(results.length).to eq(10)

        success_count = results.count { |r| r[:success] }
        expect(success_count).to eq(10) # 모든 요청 성공

        # 전체 처리 시간이 합리적인지 확인 (병렬 처리로 단일 요청보다 크게 늘어나지 않아야 함)
        expect(total_time).to be < 5.seconds

        # 개별 요청 처리 시간 확인
        processing_times = results.map { |r| r[:processing_time] }.compact
        average_processing_time = processing_times.sum / processing_times.length
        expect(average_processing_time).to be < 2.seconds

        # 총 생성된 레코드 수 확인
        total_created = results.sum { |r| r[:response_body]['created'] if r[:response_body] }
        expect(total_created).to eq(50) # 10명 * 5개씩

        Rails.logger.info "10명 동시 사용자 테스트 - 총 시간: #{total_time.round(3)}초, 평균 응답: #{average_processing_time.round(3)}초, 성공률: #{success_count}/10"
      end
    end

    context '연속 요청 처리' do
      it '1분간 연속 요청을 안정적으로 처리한다' do
        headers = { 'X-PipeData-Token' => valid_token }

        start_time = Time.current
        end_time = start_time + 60.seconds # 1분간 실행
        request_count = 0
        success_count = 0
        total_processing_time = 0

        while Time.current < end_time
          data = {
            data: [
              {
                question: "연속 요청 테스트 질문 #{request_count + 1}번입니다. 이것은 1분간 연속 요청 테스트용 질문입니다.",
                answer: "연속 요청 테스트 답변 #{request_count + 1}번입니다. 이것은 1분간 연속 요청 테스트용 답변으로 충분한 길이를 가져야 합니다.",
                difficulty: "medium",
                quality_score: 7.0,
                source: "pipedata_continuous_test_#{request_count}",
                excel_functions: [ "CONTINUOUS" ],
                code_snippets: [ "=CONTINUOUS()" ],
                tags: [ "continuous", "endurance", "test" ],
                metadata: { request_number: request_count }
              }
            ]
          }

          request_start = Time.current
          post '/api/v1/pipedata', params: data, headers: headers
          request_end = Time.current

          request_processing_time = request_end - request_start
          total_processing_time += request_processing_time

          request_count += 1
          success_count += 1 if response.status == 200

          # 너무 빨리 요청하지 않도록 약간의 대기 (실제 사용 패턴 시뮬레이션)
          sleep(0.1) if Time.current < end_time
        end

        actual_duration = Time.current - start_time
        average_processing_time = total_processing_time / request_count
        requests_per_second = request_count / actual_duration

        # 검증
        expect(success_count).to eq(request_count) # 모든 요청 성공
        expect(request_count).to be >= 30 # 최소 30개 요청 처리
        expect(average_processing_time).to be < 1.second
        expect(requests_per_second).to be >= 0.5 # 초당 최소 0.5개 요청 처리

        Rails.logger.info "1분 연속 테스트 - 총 요청: #{request_count}개, 성공률: #{success_count}/#{request_count}, 평균 응답: #{average_processing_time.round(3)}초, RPS: #{requests_per_second.round(2)}"
      end
    end
  end
end
