class CreateKnowledgeItems < ActiveRecord::Migration[8.0]
  def change
    create_table :knowledge_items do |t|
      # 핵심 Q&A 데이터
      t.text :question, null: false
      t.text :answer, null: false
      t.json :excel_functions, default: []  # VLOOKUP, INDEX, MATCH 등
      t.json :code_snippets, default: []    # 예제 수식들

      # 분류 정보
      t.integer :difficulty, default: 1     # 0: EASY, 1: MEDIUM, 2: HARD, 3: EXPERT
      t.decimal :quality_score, precision: 3, scale: 1, null: false  # 0.0 - 10.0
      t.string :source, null: false         # pipedata_stackoverflow, pipedata_reddit 등
      t.json :tags, default: []            # excel, vlookup, error-handling 등

      # 벡터 검색을 위한 임베딩 (JSON 배열로 저장)
      t.json :embedding                    # OpenAI embeddings (1536 dimensions)

      # 메타데이터
      t.json :metadata, default: {}        # votes, accepted, author 등 소스별 정보

      # 사용 통계
      t.integer :search_count, default: 0  # 검색된 횟수
      t.integer :use_count, default: 0     # 실제 사용된 횟수
      t.integer :helpful_votes, default: 0 # 도움됨 투표

      # 관리 정보
      t.boolean :is_active, default: true
      t.datetime :last_used

      t.timestamps
    end

    # 인덱스 추가
    add_index :knowledge_items, :source
    add_index :knowledge_items, :difficulty
    add_index :knowledge_items, :quality_score
    add_index :knowledge_items, :is_active
    add_index :knowledge_items, :created_at
  end
end
