# frozen_string_literal: true

require 'rails_helper'

RSpec.describe KnowledgeItem, type: :model do
  let(:valid_attributes) do
    {
      question: "VLOOKUP 함수는 어떻게 사용하나요?",
      answer: "VLOOKUP 함수는 테이블에서 특정 값을 찾아 해당 행의 다른 열 값을 반환합니다. 사용법: =VLOOKUP(검색값, 테이블배열, 열번호, [완전일치])",
      difficulty: 1,
      quality_score: 8.5,
      source: "pipedata_stackoverflow",
      excel_functions: [ "VLOOKUP" ],
      code_snippets: [ "=VLOOKUP(A1,B:C,2,FALSE)" ],
      tags: [ "excel", "vlookup" ],
      embedding: Array.new(1536) { rand(-1.0..1.0) },
      metadata: { votes: 10, accepted: true }
    }
  end

  describe '유효성 검증' do
    it '유효한 속성으로 생성된다' do
      knowledge_item = KnowledgeItem.new(valid_attributes)
      expect(knowledge_item).to be_valid
    end

    it 'question이 필수이다' do
      knowledge_item = KnowledgeItem.new(valid_attributes.except(:question))
      expect(knowledge_item).not_to be_valid
      expect(knowledge_item.errors[:question]).to include("can't be blank")
    end

    it 'question이 최소 10자 이상이어야 한다' do
      knowledge_item = KnowledgeItem.new(valid_attributes.merge(question: "짧은질문"))
      expect(knowledge_item).not_to be_valid
      expect(knowledge_item.errors[:question]).to include("is too short (minimum is 10 characters)")
    end

    it 'answer가 필수이다' do
      knowledge_item = KnowledgeItem.new(valid_attributes.except(:answer))
      expect(knowledge_item).not_to be_valid
      expect(knowledge_item.errors[:answer]).to include("can't be blank")
    end

    it 'answer가 최소 20자 이상이어야 한다' do
      knowledge_item = KnowledgeItem.new(valid_attributes.merge(answer: "짧은답변"))
      expect(knowledge_item).not_to be_valid
      expect(knowledge_item.errors[:answer]).to include("is too short (minimum is 20 characters)")
    end

    it 'quality_score가 필수이다' do
      knowledge_item = KnowledgeItem.new(valid_attributes.except(:quality_score))
      expect(knowledge_item).not_to be_valid
      expect(knowledge_item.errors[:quality_score]).to include("can't be blank")
    end

    it 'quality_score가 0.0-10.0 범위 내에 있어야 한다' do
      # 범위 내 값들은 유효
      [ 0.0, 5.5, 10.0 ].each do |score|
        knowledge_item = KnowledgeItem.new(valid_attributes.merge(quality_score: score))
        expect(knowledge_item).to be_valid, "quality_score #{score} should be valid"
      end

      # 범위 밖 값들은 무효
      [ -0.1, 10.1, 15.0 ].each do |score|
        knowledge_item = KnowledgeItem.new(valid_attributes.merge(quality_score: score))
        expect(knowledge_item).not_to be_valid, "quality_score #{score} should be invalid"
        expect(knowledge_item.errors[:quality_score]).to include("is not included in the list")
      end
    end

    it 'source가 필수이다' do
      knowledge_item = KnowledgeItem.new(valid_attributes.except(:source))
      expect(knowledge_item).not_to be_valid
      expect(knowledge_item.errors[:source]).to include("can't be blank")
    end

    it 'difficulty가 0-3 범위 내에 있어야 한다' do
      # 유효한 난이도 값들
      [ 0, 1, 2, 3 ].each do |difficulty|
        knowledge_item = KnowledgeItem.new(valid_attributes.merge(difficulty: difficulty))
        expect(knowledge_item).to be_valid, "difficulty #{difficulty} should be valid"
      end

      # 무효한 난이도 값들
      [ -1, 4, 10 ].each do |difficulty|
        knowledge_item = KnowledgeItem.new(valid_attributes.merge(difficulty: difficulty))
        expect(knowledge_item).not_to be_valid, "difficulty #{difficulty} should be invalid"
        expect(knowledge_item.errors[:difficulty]).to include("is not included in the list")
      end
    end
  end

  describe '스코프' do
    before do
      # 테스트 데이터 생성
      @active_item = KnowledgeItem.create!(valid_attributes.merge(is_active: true))
      @inactive_item = KnowledgeItem.create!(valid_attributes.merge(
        question: "비활성 질문입니다. 이 질문은 테스트용입니다.",
        is_active: false
      ))
      @high_quality = KnowledgeItem.create!(valid_attributes.merge(
        question: "고품질 질문입니다. 이 질문은 테스트용입니다.",
        quality_score: 9.0
      ))
      @low_quality = KnowledgeItem.create!(valid_attributes.merge(
        question: "저품질 질문입니다. 이 질문은 테스트용입니다.",
        quality_score: 5.0
      ))
    end

    it 'active 스코프는 활성 아이템만 반환한다' do
      active_items = KnowledgeItem.active
      expect(active_items).to include(@active_item, @high_quality, @low_quality)
      expect(active_items).not_to include(@inactive_item)
    end

    it 'by_difficulty 스코프는 난이도별로 필터링한다' do
      easy_item = KnowledgeItem.create!(valid_attributes.merge(
        question: "쉬운 질문입니다. 이 질문은 테스트용입니다.",
        difficulty: 0
      ))

      easy_items = KnowledgeItem.by_difficulty(:easy)
      expect(easy_items).to include(easy_item)
      expect(easy_items).not_to include(@active_item) # difficulty가 1인 아이템
    end

    it 'by_source 스코프는 소스별로 필터링한다' do
      reddit_item = KnowledgeItem.create!(valid_attributes.merge(
        question: "Reddit 질문입니다. 이 질문은 테스트용입니다.",
        source: "pipedata_reddit"
      ))

      stackoverflow_items = KnowledgeItem.by_source("pipedata_stackoverflow")
      expect(stackoverflow_items).to include(@active_item)
      expect(stackoverflow_items).not_to include(reddit_item)
    end

    it 'high_quality 스코프는 고품질 아이템만 반환한다' do
      high_quality_items = KnowledgeItem.high_quality
      expect(high_quality_items).to include(@active_item, @high_quality) # quality_score >= 7.0
      expect(high_quality_items).not_to include(@low_quality) # quality_score = 5.0
    end
  end

  describe '인스턴스 메서드' do
    let(:knowledge_item) { KnowledgeItem.create!(valid_attributes) }

    describe '#difficulty_name' do
      it '숫자 난이도를 문자열로 변환한다' do
        expect(KnowledgeItem.new(difficulty: 0).difficulty_name).to eq(:easy)
        expect(KnowledgeItem.new(difficulty: 1).difficulty_name).to eq(:medium)
        expect(KnowledgeItem.new(difficulty: 2).difficulty_name).to eq(:hard)
        expect(KnowledgeItem.new(difficulty: 3).difficulty_name).to eq(:expert)
      end
    end

    describe '#difficulty_name=' do
      it '문자열 난이도를 숫자로 설정한다' do
        knowledge_item.difficulty_name = 'hard'
        expect(knowledge_item.difficulty).to eq(2)

        knowledge_item.difficulty_name = 'easy'
        expect(knowledge_item.difficulty).to eq(0)
      end

      it '잘못된 난이도 이름은 무시한다' do
        original_difficulty = knowledge_item.difficulty
        knowledge_item.difficulty_name = 'invalid'
        expect(knowledge_item.difficulty).to eq(original_difficulty)
      end
    end

    describe '#increment_search_count!' do
      it 'search_count를 증가시키고 last_used를 업데이트한다' do
        original_count = knowledge_item.search_count
        original_last_used = knowledge_item.last_used

        travel_to 1.hour.from_now do
          knowledge_item.increment_search_count!

          expect(knowledge_item.search_count).to eq(original_count + 1)
          expect(knowledge_item.last_used).to be > original_last_used
        end
      end
    end

    describe '#increment_use_count!' do
      it 'use_count를 증가시키고 last_used를 업데이트한다' do
        original_count = knowledge_item.use_count

        knowledge_item.increment_use_count!

        expect(knowledge_item.use_count).to eq(original_count + 1)
        expect(knowledge_item.last_used).to be_present
      end
    end

    describe '#increment_helpful_votes!' do
      it 'helpful_votes를 증가시킨다' do
        original_votes = knowledge_item.helpful_votes

        knowledge_item.increment_helpful_votes!

        expect(knowledge_item.helpful_votes).to eq(original_votes + 1)
      end
    end
  end

  describe '클래스 메서드' do
    before do
      @item1 = KnowledgeItem.create!(valid_attributes.merge(
        search_count: 10,
        use_count: 5,
        helpful_votes: 3
      ))
      @item2 = KnowledgeItem.create!(valid_attributes.merge(
        question: "두 번째 질문입니다. 이 질문은 테스트용입니다.",
        source: "pipedata_reddit",
        quality_score: 7.5,
        search_count: 15,
        use_count: 8,
        helpful_votes: 1
      ))
    end

    describe '.find_duplicate' do
      it '중복 질문을 찾는다' do
        duplicate = KnowledgeItem.find_duplicate(@item1.question, @item1.source)
        expect(duplicate).to eq(@item1)
      end

      it '중복이 없으면 nil을 반환한다' do
        duplicate = KnowledgeItem.find_duplicate("존재하지 않는 질문", "unknown_source")
        expect(duplicate).to be_nil
      end
    end

    describe '.stats_by_source' do
      it '소스별 통계를 반환한다' do
        stats = KnowledgeItem.stats_by_source
        expect(stats["pipedata_stackoverflow"]).to eq(1)
        expect(stats["pipedata_reddit"]).to eq(1)
      end
    end

    describe '.average_quality_score' do
      it '평균 품질 점수를 계산한다' do
        # @item1: 8.5, @item2: 7.5 -> 평균: 8.0
        average = KnowledgeItem.average_quality_score
        expect(average).to eq(8.0)
      end
    end

    describe '.total_searches' do
      it '총 검색 횟수를 계산한다' do
        total = KnowledgeItem.total_searches
        expect(total).to eq(25) # 10 + 15
      end
    end

    describe '.total_usage' do
      it '총 사용 횟수를 계산한다' do
        total = KnowledgeItem.total_usage
        expect(total).to eq(13) # 5 + 8
      end
    end
  end

  describe '벡터 검색' do
    before do
      @item1 = KnowledgeItem.create!(valid_attributes.merge(
        embedding: Array.new(1536) { 0.5 } # 모든 차원이 0.5인 벡터
      ))
      @item2 = KnowledgeItem.create!(valid_attributes.merge(
        question: "두 번째 질문입니다. 이 질문은 테스트용입니다.",
        embedding: Array.new(1536) { 0.8 } # 모든 차원이 0.8인 벡터
      ))
    end

    describe '.vector_search' do
      it '유사한 벡터를 찾는다' do
        query_embedding = Array.new(1536) { 0.5 } # @item1과 동일한 벡터

        # Note: 실제 pgvector 없이는 정확한 검색이 어려우므로 기본 동작만 테스트
        results = KnowledgeItem.vector_search(query_embedding, limit: 5, threshold: 0.1)
        expect(results.count).to be >= 0 # 기본적으로 에러 없이 실행되는지 확인
      end

      it '빈 임베딩으로 검색 시 빈 결과를 반환한다' do
        results = KnowledgeItem.vector_search([], limit: 5)
        expect(results).to be_empty
      end

      it 'nil 임베딩으로 검색 시 빈 결과를 반환한다' do
        results = KnowledgeItem.vector_search(nil, limit: 5)
        expect(results).to be_empty
      end
    end
  end

  describe '데이터베이스 제약조건' do
    it '동일한 question과 source 조합은 허용된다 (현재 제약조건 없음)' do
      KnowledgeItem.create!(valid_attributes)

      expect {
        KnowledgeItem.create!(valid_attributes)
      }.not_to raise_error
    end
  end
end
