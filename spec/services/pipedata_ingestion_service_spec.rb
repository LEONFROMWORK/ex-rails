# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PipedataIngestionService, type: :service do
  let(:valid_item) do
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
  end

  let(:invalid_item_missing_question) do
    {
      answer: "답변만 있는 아이템입니다. 질문이 없어서 처리되지 않아야 합니다.",
      difficulty: "medium",
      quality_score: 7.0,
      source: "pipedata_test"
    }
  end

  let(:invalid_item_missing_answer) do
    {
      question: "답변이 없는 질문입니다. 이것은 처리되지 않아야 합니다.",
      difficulty: "medium",
      quality_score: 7.0,
      source: "pipedata_test"
    }
  end

  describe '.call' do
    context '정상 데이터 처리' do
      it '유효한 단일 아이템을 성공적으로 처리한다' do
        expect {
          result = described_class.call([ valid_item ])

          expect(result).to be_success
          expect(result.data[:processed]).to eq(1)
          expect(result.data[:created]).to eq(1)
          expect(result.data[:duplicates]).to eq(0)
          expect(result.data[:errors]).to eq(0)
          expect(result.data[:message]).to include("Successfully processed")
        }.to change(KnowledgeItem, :count).by(1)
      end

      it '여러 유효한 아이템을 배치로 처리한다' do
        items = [
          valid_item,
          valid_item.merge(
            question: "두 번째 질문입니다. INDEX와 MATCH 함수를 어떻게 사용하나요?",
            answer: "INDEX와 MATCH 함수의 조합은 VLOOKUP보다 유연한 검색을 제공합니다. INDEX는 값을 반환하고 MATCH는 위치를 찾습니다.",
            excel_functions: [ "INDEX", "MATCH" ]
          ),
          valid_item.merge(
            question: "세 번째 질문입니다. SUMIF 함수의 사용법은 무엇인가요?",
            answer: "SUMIF 함수는 조건에 맞는 셀들의 합을 계산합니다. 기본 문법: =SUMIF(범위, 조건, 합계범위)",
            excel_functions: [ "SUMIF" ]
          )
        ]

        expect {
          result = described_class.call(items)

          expect(result).to be_success
          expect(result.data[:processed]).to eq(3)
          expect(result.data[:created]).to eq(3)
          expect(result.data[:duplicates]).to eq(0)
          expect(result.data[:errors]).to eq(0)
        }.to change(KnowledgeItem, :count).by(3)
      end

      it '배열 필드를 올바르게 정규화한다' do
        item_with_various_formats = valid_item.merge(
          excel_functions: "VLOOKUP", # 문자열
          code_snippets: [ "=VLOOKUP(A1,B:C,2,FALSE)" ], # 배열
          tags: nil, # nil
          metadata: '{"custom": "value"}' # JSON 문자열
        )

        result = described_class.call([ item_with_various_formats ])
        expect(result).to be_success

        created_item = KnowledgeItem.last
        expect(created_item.excel_functions).to eq([ "VLOOKUP" ])
        expect(created_item.code_snippets).to eq([ "=VLOOKUP(A1,B:C,2,FALSE)" ])
        expect(created_item.tags).to eq([])
        expect(created_item.metadata).to eq({ "custom" => "value" })
      end

      it '난이도 매핑을 올바르게 수행한다' do
        difficulties = [
          { input: "easy", expected: 0 },
          { input: "medium", expected: 1 },
          { input: "hard", expected: 2 },
          { input: "expert", expected: 3 },
          { input: "invalid", expected: 1 }, # 기본값 medium
          { input: nil, expected: 1 }
        ]

        difficulties.each_with_index do |difficulty_test, index|
          item = valid_item.merge(
            question: "난이도 테스트 질문 #{index + 1}번입니다. 이것은 테스트용 질문입니다.",
            difficulty: difficulty_test[:input]
          )

          described_class.call([ item ])
          created_item = KnowledgeItem.last
          expect(created_item.difficulty).to eq(difficulty_test[:expected])
        end
      end
    end

    context '중복 데이터 처리' do
      before do
        # 기존 아이템 생성
        KnowledgeItem.create!(
          question: valid_item[:question],
          answer: valid_item[:answer],
          difficulty: 1,
          quality_score: valid_item[:quality_score],
          source: valid_item[:source],
          embedding: Array.new(1536) { rand(-1.0..1.0) }
        )
      end

      it '중복 아이템을 올바르게 감지하고 처리한다' do
        expect {
          result = described_class.call([ valid_item ])

          expect(result).to be_success
          expect(result.data[:processed]).to eq(1)
          expect(result.data[:created]).to eq(0)
          expect(result.data[:duplicates]).to eq(1)
          expect(result.data[:errors]).to eq(0)
        }.not_to change(KnowledgeItem, :count)
      end

      it '중복과 신규 아이템이 섞인 경우를 처리한다' do
        new_item = valid_item.merge(
          question: "새로운 질문입니다. 이 질문은 중복되지 않은 질문입니다."
        )

        expect {
          result = described_class.call([ valid_item, new_item ])

          expect(result).to be_success
          expect(result.data[:processed]).to eq(2)
          expect(result.data[:created]).to eq(1)
          expect(result.data[:duplicates]).to eq(1)
          expect(result.data[:errors]).to eq(0)
        }.to change(KnowledgeItem, :count).by(1)
      end
    end

    context '에러 데이터 처리' do
      it '필수 필드가 누락된 아이템을 에러로 처리한다' do
        expect {
          result = described_class.call([ invalid_item_missing_question ])

          expect(result).to be_success
          expect(result.data[:processed]).to eq(1)
          expect(result.data[:created]).to eq(0)
          expect(result.data[:duplicates]).to eq(0)
          expect(result.data[:errors]).to eq(1)
          expect(result.data[:error_details]).to have(1).item
          expect(result.data[:error_details].first[:message]).to include("Missing required fields")
        }.not_to change(KnowledgeItem, :count)
      end

      it '여러 에러 아이템을 올바르게 처리한다' do
        error_items = [
          invalid_item_missing_question,
          invalid_item_missing_answer,
          valid_item.merge(question: "", answer: "빈 질문 테스트")
        ]

        expect {
          result = described_class.call(error_items)

          expect(result).to be_success
          expect(result.data[:processed]).to eq(3)
          expect(result.data[:created]).to eq(0)
          expect(result.data[:duplicates]).to eq(0)
          expect(result.data[:errors]).to eq(3)
          expect(result.data[:error_details]).to have(3).items
        }.not_to change(KnowledgeItem, :count)
      end

      it '정상 아이템과 에러 아이템이 섞인 경우를 처리한다' do
        mixed_items = [
          valid_item,
          invalid_item_missing_question,
          valid_item.merge(question: "정상적인 두 번째 질문입니다. 이것은 테스트용 질문입니다."),
          invalid_item_missing_answer
        ]

        expect {
          result = described_class.call(mixed_items)

          expect(result).to be_success
          expect(result.data[:processed]).to eq(4)
          expect(result.data[:created]).to eq(2)
          expect(result.data[:duplicates]).to eq(0)
          expect(result.data[:errors]).to eq(2)
        }.to change(KnowledgeItem, :count).by(2)
      end
    end

    context '대량 데이터 성능 테스트' do
      it '1000건 데이터를 10초 이내에 처리한다' do
        large_dataset = Array.new(1000) do |i|
          valid_item.merge(
            question: "대량 테스트 질문 #{i + 1}번입니다. 이것은 성능 테스트용 질문입니다.",
            answer: "대량 테스트 답변 #{i + 1}번입니다. 이것은 성능 테스트용 답변으로 충분한 길이를 가져야 합니다.",
            source: "pipedata_performance_test"
          )
        end

        start_time = Time.current

        expect {
          result = described_class.call(large_dataset)

          processing_time = Time.current - start_time
          expect(processing_time).to be < 10.seconds

          expect(result).to be_success
          expect(result.data[:created]).to eq(1000)
          expect(result.data[:processed]).to eq(1000)
        }.to change(KnowledgeItem, :count).by(1000)
      end

      it '메모리 사용량이 합리적 범위 내에 있다' do
        # 메모리 사용량 측정 (간단한 방법)
        before_memory = GC.stat[:heap_allocated_pages]

        large_dataset = Array.new(100) do |i|
          valid_item.merge(
            question: "메모리 테스트 질문 #{i + 1}번입니다. 이것은 메모리 테스트용 질문입니다.",
            answer: "메모리 테스트 답변 #{i + 1}번입니다. 이것은 메모리 테스트용 답변으로 충분한 길이를 가져야 합니다."
          )
        end

        described_class.call(large_dataset)

        after_memory = GC.stat[:heap_allocated_pages]
        memory_increase = after_memory - before_memory

        # 메모리 증가량이 100MB(대략 25000 페이지) 이내여야 함
        expect(memory_increase).to be < 25000
      end
    end

    context '입력 검증' do
      it '빈 배열로 호출 시 에러를 반환한다' do
        result = described_class.call([])

        expect(result).to be_failure
        expect(result.error).to include("Data items must be a non-empty array")
      end

      it 'nil로 호출 시 에러를 반환한다' do
        result = described_class.call(nil)

        expect(result).to be_failure
        expect(result.error).to include("Data items must be a non-empty array")
      end

      it '배열이 아닌 객체로 호출 시 에러를 반환한다' do
        result = described_class.call(valid_item) # 배열이 아닌 단일 객체

        expect(result).to be_failure
        expect(result.error).to include("Data items must be a non-empty array")
      end
    end

    context 'ActiveRecord 에러 처리' do
      it 'DB 저장 실패 시 에러로 처리한다' do
        # KnowledgeItem.create!이 실패하도록 모킹
        allow(KnowledgeItem).to receive(:create!).and_raise(
          ActiveRecord::RecordInvalid.new(KnowledgeItem.new)
        )

        result = described_class.call([ valid_item ])

        expect(result).to be_success
        expect(result.data[:errors]).to eq(1)
        expect(result.data[:created]).to eq(0)
        expect(result.data[:error_details].first[:message]).to include("Validation failed")
      end

      it '예상치 못한 에러를 처리한다' do
        # 예상치 못한 에러 발생
        allow(KnowledgeItem).to receive(:create!).and_raise(StandardError.new("Unexpected error"))

        result = described_class.call([ valid_item ])

        expect(result).to be_success
        expect(result.data[:errors]).to eq(1)
        expect(result.data[:created]).to eq(0)
        expect(result.data[:error_details].first[:message]).to include("Creation failed")
      end
    end

    context '임베딩 생성' do
      it '더미 임베딩을 생성한다' do
        result = described_class.call([ valid_item ])
        expect(result).to be_success

        created_item = KnowledgeItem.last
        expect(created_item.embedding).to be_an(Array)
        expect(created_item.embedding.length).to eq(1536)

        # 모든 값이 -1.0과 1.0 사이에 있는지 확인
        created_item.embedding.each do |value|
          expect(value).to be_between(-1.0, 1.0)
        end
      end
    end

    context '전체 시스템 에러' do
      it '서비스 전체 실패 시 failure result를 반환한다' do
        # 서비스 내부에서 예상치 못한 에러 발생
        allow_any_instance_of(described_class).to receive(:validate_input!).and_raise(
          StandardError.new("Service failure")
        )

        result = described_class.call([ valid_item ])

        expect(result).to be_failure
        expect(result.error).to include("Failed to process PipeData: Service failure")
      end
    end
  end

  describe '개별 메서드 테스트' do
    let(:service) { described_class.new([ valid_item ]) }

    describe '#normalize_array_field' do
      it '다양한 입력 형태를 배열로 정규화한다' do
        expect(service.send(:normalize_array_field, [ "a", "b" ])).to eq([ "a", "b" ])
        expect(service.send(:normalize_array_field, "single")).to eq([ "single" ])
        expect(service.send(:normalize_array_field, "")).to eq([])
        expect(service.send(:normalize_array_field, nil)).to eq([])
        expect(service.send(:normalize_array_field, 123)).to eq([])
      end
    end

    describe '#normalize_metadata' do
      it '다양한 메타데이터 형태를 해시로 정규화한다' do
        expect(service.send(:normalize_metadata, { key: "value" })).to eq({ key: "value" })
        expect(service.send(:normalize_metadata, '{"json": "value"}')).to eq({ "json" => "value" })
        expect(service.send(:normalize_metadata, 'invalid json')).to eq({ original: "invalid json" })
        expect(service.send(:normalize_metadata, nil)).to eq({})
        expect(service.send(:normalize_metadata, 123)).to eq({ original: "123" })
      end
    end

    describe '#map_difficulty' do
      it '난이도 문자열을 숫자로 매핑한다' do
        expect(service.send(:map_difficulty, "easy")).to eq(0)
        expect(service.send(:map_difficulty, "MEDIUM")).to eq(1)
        expect(service.send(:map_difficulty, "Hard")).to eq(2)
        expect(service.send(:map_difficulty, "expert")).to eq(3)
        expect(service.send(:map_difficulty, "invalid")).to eq(1) # 기본값
        expect(service.send(:map_difficulty, nil)).to eq(1) # 기본값
      end
    end
  end
end
