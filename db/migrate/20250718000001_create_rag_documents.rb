# frozen_string_literal: true

class CreateRagDocuments < ActiveRecord::Migration[8.0]
  def change
    # Note: pgvector extension will be enabled manually for now
    # enable_extension 'vector'

    create_table :rag_documents do |t|
      t.text :content, null: false
      t.jsonb :metadata, null: false, default: {}
      t.text :embedding_text, null: false  # Store as text for now
      t.integer :credits, null: false, default: 0

      t.timestamps
    end

    # Add indexes
    add_index :rag_documents, :metadata, using: :gin
    add_index :rag_documents, :credits
    add_index :rag_documents, :created_at

    # Add full-text search index
    add_index :rag_documents, "to_tsvector('english', content)", using: :gin, name: 'index_rag_documents_on_content_tsvector'

    # Add constraints
    add_check_constraint :rag_documents, 'char_length(content) >= 10', name: 'content_min_length'
    add_check_constraint :rag_documents, 'char_length(content) <= 10000', name: 'content_max_length'
    add_check_constraint :rag_documents, 'tokens > 0', name: 'tokens_positive'
  end
end
