# frozen_string_literal: true

class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # === 사용자 관련 성능 인덱스 ===

    # 사용자 대시보드 쿼리 최적화 (excel_files with status)
    add_index :excel_files, [ :user_id, :status ], name: 'idx_excel_files_user_status'
    add_index :excel_files, [ :user_id, :created_at ], name: 'idx_excel_files_user_created'

    # === 분석 관련 성능 인덱스 ===

    # 최신 분석 조회 최적화
    add_index :analyses, [ :excel_file_id, :created_at ], name: 'idx_analyses_file_created'
    add_index :analyses, [ :user_id, :ai_tier_used ], name: 'idx_analyses_user_tier'
    add_index :analyses, [ :user_id, :created_at ], name: 'idx_analyses_user_created'

    # === 채팅 관련 성능 인덱스 ===

    # 채팅 메시지 순서 조회 최적화
    add_index :chat_messages, [ :chat_conversation_id, :created_at ],
              name: 'idx_messages_conversation_created'

    # 채팅 대화 조회 최적화
    add_index :chat_conversations, [ :user_id, :created_at ],
              name: 'idx_conversations_user_created'
    add_index :chat_conversations, [ :user_id, :updated_at ],
              name: 'idx_conversations_user_updated'

    # === AI 사용량 추적 인덱스 ===

    # AI 사용량 분석 쿼리 최적화
    add_index :ai_usage_records, [ :user_id, :created_at ], name: 'idx_usage_user_created'
    add_index :ai_usage_records, [ :provider, :created_at ], name: 'idx_usage_provider_created'
    add_index :ai_usage_records, [ :model_id, :provider ], name: 'idx_usage_model_provider'

    # === 결제 관련 성능 인덱스 ===

    # 결제 이력 조회 최적화
    add_index :payments, [ :user_id, :processed_at ], name: 'idx_payments_user_processed'
    add_index :payment_intents, [ :user_id, :status ], name: 'idx_payment_intents_user_status'
    add_index :payment_intents, [ :status, :created_at ], name: 'idx_payment_intents_status_created'

    # === 관리자 대시보드 인덱스 ===

    # 시스템 통계 쿼리 최적화
    add_index :users, [ :role, :created_at ], name: 'idx_users_role_created'
    add_index :users, [ :tier, :credits ], name: 'idx_users_tier_credits'

    # === RAG 시스템 인덱스 ===

    # RAG 문서 검색 최적화 (실제 컬럼 기반)
    add_index :rag_documents, [ :credits, :created_at ],
              name: 'idx_rag_docs_credits_created'

    # === 구독 관리 인덱스 ===

    # 구독 만료 관리 최적화 (실제 컬럼 기반)
    add_index :subscriptions, [ :status, :ends_at ],
              name: 'idx_subscriptions_status_end_date'
    add_index :subscriptions, [ :user_id, :tier ],
              name: 'idx_subscriptions_user_tier'

    # === 외래키 제약조건 추가 (데이터 무결성) ===

    # ai_usage_records 외래키 제약조건 (NULL 허용)
    add_foreign_key :ai_usage_records, :users, on_delete: :nullify,
                    validate: false unless foreign_key_exists?(:ai_usage_records, :users)

    # 기존 외래키 제약조건 검증 및 추가
    add_foreign_key :analyses, :excel_files, on_delete: :cascade unless foreign_key_exists?(:analyses, :excel_files)
    add_foreign_key :analyses, :users, on_delete: :cascade unless foreign_key_exists?(:analyses, :users)
    add_foreign_key :chat_messages, :chat_conversations, on_delete: :cascade unless foreign_key_exists?(:chat_messages, :chat_conversations)
    add_foreign_key :chat_conversations, :users, on_delete: :cascade unless foreign_key_exists?(:chat_conversations, :users)
    add_foreign_key :payments, :payment_intents, on_delete: :cascade unless foreign_key_exists?(:payments, :payment_intents)

    # === 부분 인덱스 (조건부 인덱스) ===

    # 활성 상태의 데이터만 인덱싱 (enum 값 사용)
    add_index :excel_files, [ :user_id, :created_at ],
              where: "status IN (0, 1, 2)", # uploaded=0, processing=1, analyzed=2
              name: 'idx_excel_files_user_created_active'

    # 완료된 결제만 인덱싱
    add_index :payments, [ :user_id, :processed_at ],
              where: "status = 'completed'",
              name: 'idx_payments_user_processed_completed'

    # 활성 구독만 인덱싱
    add_index :subscriptions, [ :user_id, :ends_at ],
              where: "status = 0",
              name: 'idx_subscriptions_user_active'
  end

  def down
    # 인덱스 제거 (역순)
    remove_index :subscriptions, name: 'idx_subscriptions_user_active' if index_exists?(:subscriptions, [ :user_id, :ends_at ], name: 'idx_subscriptions_user_active')
    remove_index :payments, name: 'idx_payments_user_processed_completed' if index_exists?(:payments, [ :user_id, :processed_at ], name: 'idx_payments_user_processed_completed')
    remove_index :excel_files, name: 'idx_excel_files_user_created_active' if index_exists?(:excel_files, [ :user_id, :created_at ], name: 'idx_excel_files_user_created_active')

    # 외래키 제약조건 제거
    remove_foreign_key :payments, :payment_intents if foreign_key_exists?(:payments, :payment_intents)
    remove_foreign_key :chat_conversations, :users if foreign_key_exists?(:chat_conversations, :users)
    remove_foreign_key :chat_messages, :chat_conversations if foreign_key_exists?(:chat_messages, :chat_conversations)
    remove_foreign_key :analyses, :users if foreign_key_exists?(:analyses, :users)
    remove_foreign_key :analyses, :excel_files if foreign_key_exists?(:analyses, :excel_files)
    remove_foreign_key :ai_usage_records, :users if foreign_key_exists?(:ai_usage_records, :users)

    # 모든 추가된 인덱스 제거
    remove_index :subscriptions, name: 'idx_subscriptions_user_tier' if index_exists?(:subscriptions, [ :user_id, :tier ], name: 'idx_subscriptions_user_tier')
    remove_index :subscriptions, name: 'idx_subscriptions_status_end_date' if index_exists?(:subscriptions, [ :status, :ends_at ], name: 'idx_subscriptions_status_end_date')
    remove_index :rag_documents, name: 'idx_rag_docs_credits_created' if index_exists?(:rag_documents, [ :credits, :created_at ], name: 'idx_rag_docs_credits_created')
    remove_index :users, name: 'idx_users_tier_credits' if index_exists?(:users, [ :tier, :credits ], name: 'idx_users_tier_credits')
    remove_index :users, name: 'idx_users_role_created' if index_exists?(:users, [ :role, :created_at ], name: 'idx_users_role_created')
    remove_index :payment_intents, name: 'idx_payment_intents_status_created' if index_exists?(:payment_intents, [ :status, :created_at ], name: 'idx_payment_intents_status_created')
    remove_index :payment_intents, name: 'idx_payment_intents_user_status' if index_exists?(:payment_intents, [ :user_id, :status ], name: 'idx_payment_intents_user_status')
    remove_index :payments, name: 'idx_payments_user_processed' if index_exists?(:payments, [ :user_id, :processed_at ], name: 'idx_payments_user_processed')
    remove_index :ai_usage_records, name: 'idx_usage_model_provider' if index_exists?(:ai_usage_records, [ :model_id, :provider ], name: 'idx_usage_model_provider')
    remove_index :ai_usage_records, name: 'idx_usage_provider_created' if index_exists?(:ai_usage_records, [ :provider, :created_at ], name: 'idx_usage_provider_created')
    remove_index :ai_usage_records, name: 'idx_usage_user_created' if index_exists?(:ai_usage_records, [ :user_id, :created_at ], name: 'idx_usage_user_created')
    remove_index :chat_conversations, name: 'idx_conversations_user_updated' if index_exists?(:chat_conversations, [ :user_id, :updated_at ], name: 'idx_conversations_user_updated')
    remove_index :chat_conversations, name: 'idx_conversations_user_created' if index_exists?(:chat_conversations, [ :user_id, :created_at ], name: 'idx_conversations_user_created')
    remove_index :chat_messages, name: 'idx_messages_conversation_created' if index_exists?(:chat_messages, [ :chat_conversation_id, :created_at ], name: 'idx_messages_conversation_created')
    remove_index :analyses, name: 'idx_analyses_user_created' if index_exists?(:analyses, [ :user_id, :created_at ], name: 'idx_analyses_user_created')
    remove_index :analyses, name: 'idx_analyses_user_tier' if index_exists?(:analyses, [ :user_id, :ai_tier_used ], name: 'idx_analyses_user_tier')
    remove_index :analyses, name: 'idx_analyses_file_created' if index_exists?(:analyses, [ :excel_file_id, :created_at ], name: 'idx_analyses_file_created')
    remove_index :excel_files, name: 'idx_excel_files_user_created' if index_exists?(:excel_files, [ :user_id, :created_at ], name: 'idx_excel_files_user_created')
    remove_index :excel_files, name: 'idx_excel_files_user_status' if index_exists?(:excel_files, [ :user_id, :status ], name: 'idx_excel_files_user_status')
  end
end
