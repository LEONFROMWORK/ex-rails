class CreateKnowledgeThreads < ActiveRecord::Migration[8.0]
  def change
    create_table :knowledge_threads do |t|
      t.string :external_id, null: false           # Reddit/StackOverflow ID
      t.string :source, null: false                # 'reddit', 'stackoverflow', 'manual'
      t.string :title, null: false
      t.text :question_content
      t.text :answer_content
      t.string :category, default: 'general'       # 'formula_errors', 'pivot_tables', etc.
      t.decimal :quality_score, precision: 3, scale: 1, default: 0.0
      t.json :source_metadata                      # Platform-specific data
      t.boolean :op_confirmed, default: false     # Reddit OP confirmation
      t.integer :votes, default: 0                # Upvotes/score
      t.string :source_url                         # Original URL
      t.boolean :is_active, default: true         # For soft deletion
      t.datetime :processed_at

      t.timestamps
    end

    add_index :knowledge_threads, :external_id
    add_index :knowledge_threads, :source
    add_index :knowledge_threads, [ :external_id, :source ], unique: true
    add_index :knowledge_threads, :category
    add_index :knowledge_threads, :quality_score
    add_index :knowledge_threads, :op_confirmed
    add_index :knowledge_threads, :is_active
    add_index :knowledge_threads, :processed_at
  end
end
