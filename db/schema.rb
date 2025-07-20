# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_07_20_142450) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "ai_feedbacks", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "chat_message_id", null: false
    t.integer "rating"
    t.text "feedback_text"
    t.integer "ai_tier_used"
    t.string "provider"
    t.decimal "confidence_score"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_message_id"], name: "index_ai_feedbacks_on_chat_message_id"
    t.index ["user_id"], name: "index_ai_feedbacks_on_user_id"
  end

  create_table "ai_provider_metrics", force: :cascade do |t|
    t.string "provider"
    t.string "model"
    t.integer "tier"
    t.integer "total_requests"
    t.integer "total_rating"
    t.decimal "average_rating"
    t.integer "positive_feedback_count"
    t.integer "negative_feedback_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "ai_usage_records", force: :cascade do |t|
    t.bigint "user_id"
    t.string "model_id", null: false
    t.integer "provider", default: 0, null: false
    t.decimal "cost", precision: 10, scale: 6, default: "0.0", null: false
    t.integer "input_credits", default: 0, null: false
    t.integer "output_credits", default: 0, null: false
    t.integer "request_type", default: 0, null: false
    t.text "request_prompt"
    t.text "response_content"
    t.json "metadata"
    t.decimal "latency_ms", precision: 10, scale: 2
    t.string "request_id"
    t.string "session_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_ai_usage_records_on_created_at"
    t.index ["model_id", "created_at"], name: "index_ai_usage_records_on_model_id_and_created_at"
    t.index ["model_id", "provider"], name: "idx_usage_model_provider"
    t.index ["model_id"], name: "index_ai_usage_records_on_model_id"
    t.index ["provider", "created_at"], name: "idx_usage_provider_created"
    t.index ["provider", "created_at"], name: "index_ai_usage_records_on_provider_and_created_at"
    t.index ["provider"], name: "index_ai_usage_records_on_provider"
    t.index ["request_id"], name: "index_ai_usage_records_on_request_id"
    t.index ["request_type"], name: "index_ai_usage_records_on_request_type"
    t.index ["session_id"], name: "index_ai_usage_records_on_session_id"
    t.index ["user_id", "created_at"], name: "idx_usage_user_created"
    t.index ["user_id", "created_at"], name: "index_ai_usage_records_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_ai_usage_records_on_user_id"
  end

  create_table "analyses", force: :cascade do |t|
    t.bigint "excel_file_id", null: false
    t.bigint "user_id", null: false
    t.json "detected_errors"
    t.json "ai_analysis"
    t.json "corrections"
    t.integer "ai_tier_used", default: 0, null: false
    t.decimal "confidence_score", precision: 3, scale: 2
    t.integer "credits_used", default: 0, null: false
    t.decimal "cost", precision: 10, scale: 6
    t.integer "status", default: 0, null: false
    t.integer "error_count", default: 0
    t.integer "fixed_count", default: 0
    t.text "analysis_summary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "formula_analysis"
    t.decimal "formula_complexity_score", precision: 5, scale: 2
    t.integer "formula_count", default: 0
    t.json "formula_functions"
    t.json "formula_dependencies"
    t.json "circular_references"
    t.json "formula_errors"
    t.json "formula_optimization_suggestions"
    t.index ["ai_tier_used"], name: "index_analyses_on_ai_tier_used"
    t.index ["confidence_score"], name: "index_analyses_on_confidence_score"
    t.index ["created_at"], name: "index_analyses_on_created_at"
    t.index ["excel_file_id", "created_at"], name: "idx_analyses_file_created"
    t.index ["excel_file_id"], name: "index_analyses_on_excel_file_id"
    t.index ["formula_complexity_score"], name: "index_analyses_on_formula_complexity_score"
    t.index ["formula_count"], name: "index_analyses_on_formula_count"
    t.index ["status"], name: "index_analyses_on_status"
    t.index ["user_id", "ai_tier_used"], name: "idx_analyses_user_tier"
    t.index ["user_id", "created_at"], name: "idx_analyses_user_created"
    t.index ["user_id"], name: "index_analyses_on_user_id"
  end

  create_table "billing_keys", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "billing_key"
    t.string "customer_key"
    t.string "card_number"
    t.string "card_type"
    t.string "card_owner_type"
    t.string "issuer_code"
    t.string "acquirer_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["billing_key"], name: "index_billing_keys_on_billing_key", unique: true
    t.index ["customer_key"], name: "index_billing_keys_on_customer_key", unique: true
    t.index ["user_id"], name: "index_billing_keys_on_user_id"
  end

  create_table "chat_conversations", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "excel_file_id"
    t.string "title"
    t.integer "status", default: 0, null: false
    t.json "context"
    t.integer "message_count", default: 0
    t.integer "total_tokens_used", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_chat_conversations_on_created_at"
    t.index ["excel_file_id"], name: "index_chat_conversations_on_excel_file_id"
    t.index ["status"], name: "index_chat_conversations_on_status"
    t.index ["user_id", "created_at"], name: "idx_conversations_user_created"
    t.index ["user_id", "updated_at"], name: "idx_conversations_user_updated"
    t.index ["user_id"], name: "index_chat_conversations_on_user_id"
  end

  create_table "chat_messages", force: :cascade do |t|
    t.bigint "chat_conversation_id", null: false
    t.bigint "user_id", null: false
    t.text "content", null: false
    t.string "role", default: "user", null: false
    t.json "metadata"
    t.integer "tokens_used", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "ai_tier_used"
    t.decimal "confidence_score"
    t.string "provider"
    t.integer "user_rating"
    t.text "user_feedback"
    t.index ["chat_conversation_id", "created_at"], name: "idx_messages_conversation_created"
    t.index ["chat_conversation_id"], name: "index_chat_messages_on_chat_conversation_id"
    t.index ["created_at"], name: "index_chat_messages_on_created_at"
    t.index ["role"], name: "index_chat_messages_on_role"
    t.index ["user_id"], name: "index_chat_messages_on_user_id"
  end

  create_table "excel_files", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "original_name", null: false
    t.string "file_path", null: false
    t.bigint "file_size", null: false
    t.string "content_hash"
    t.integer "status", default: 0, null: false
    t.json "metadata"
    t.integer "sheet_count"
    t.integer "row_count"
    t.integer "column_count"
    t.string "file_format"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["content_hash"], name: "index_excel_files_on_content_hash"
    t.index ["created_at"], name: "index_excel_files_on_created_at"
    t.index ["status"], name: "index_excel_files_on_status"
    t.index ["user_id", "created_at"], name: "idx_excel_files_user_created"
    t.index ["user_id", "created_at"], name: "idx_excel_files_user_created_active", where: "(status = ANY (ARRAY[0, 1, 2]))"
    t.index ["user_id", "status"], name: "idx_excel_files_user_status"
    t.index ["user_id"], name: "index_excel_files_on_user_id"
  end

  create_table "knowledge_items", force: :cascade do |t|
    t.text "question", null: false
    t.text "answer", null: false
    t.json "excel_functions", default: []
    t.json "code_snippets", default: []
    t.integer "difficulty", default: 1
    t.decimal "quality_score", precision: 3, scale: 1, null: false
    t.string "source", null: false
    t.json "tags", default: []
    t.json "embedding"
    t.json "metadata", default: {}
    t.integer "search_count", default: 0
    t.integer "use_count", default: 0
    t.integer "helpful_votes", default: 0
    t.boolean "is_active", default: true
    t.datetime "last_used"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_knowledge_items_on_created_at"
    t.index ["difficulty"], name: "index_knowledge_items_on_difficulty"
    t.index ["is_active"], name: "index_knowledge_items_on_is_active"
    t.index ["quality_score"], name: "index_knowledge_items_on_quality_score"
    t.index ["source"], name: "index_knowledge_items_on_source"
  end

  create_table "knowledge_threads", force: :cascade do |t|
    t.string "external_id", null: false
    t.string "source", null: false
    t.string "title", null: false
    t.text "question_content"
    t.text "answer_content"
    t.string "category", default: "general"
    t.decimal "quality_score", precision: 3, scale: 1, default: "0.0"
    t.json "source_metadata"
    t.boolean "op_confirmed", default: false
    t.integer "votes", default: 0
    t.string "source_url"
    t.boolean "is_active", default: true
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_knowledge_threads_on_category"
    t.index ["external_id", "source"], name: "index_knowledge_threads_on_external_id_and_source", unique: true
    t.index ["external_id"], name: "index_knowledge_threads_on_external_id"
    t.index ["is_active"], name: "index_knowledge_threads_on_is_active"
    t.index ["op_confirmed"], name: "index_knowledge_threads_on_op_confirmed"
    t.index ["processed_at"], name: "index_knowledge_threads_on_processed_at"
    t.index ["quality_score"], name: "index_knowledge_threads_on_quality_score"
    t.index ["source"], name: "index_knowledge_threads_on_source"
  end

  create_table "payment_intents", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "order_id", null: false
    t.integer "amount", null: false
    t.string "payment_type", null: false
    t.string "status", default: "created", null: false
    t.string "toss_payment_key"
    t.string "toss_transaction_id"
    t.text "error_message"
    t.datetime "paid_at"
    t.json "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_payment_intents_on_order_id", unique: true
    t.index ["payment_type"], name: "index_payment_intents_on_payment_type"
    t.index ["status", "created_at"], name: "idx_payment_intents_status_created"
    t.index ["status"], name: "index_payment_intents_on_status"
    t.index ["toss_payment_key"], name: "index_payment_intents_on_toss_payment_key"
    t.index ["user_id", "status"], name: "idx_payment_intents_user_status"
    t.index ["user_id"], name: "index_payment_intents_on_user_id"
  end

  create_table "payment_methods", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "method_type"
    t.boolean "is_default", default: false
    t.string "card_number"
    t.string "card_type"
    t.bigint "billing_key_id"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["billing_key_id"], name: "index_payment_methods_on_billing_key_id"
    t.index ["method_type"], name: "index_payment_methods_on_method_type"
    t.index ["user_id"], name: "index_payment_methods_on_user_id"
  end

  create_table "payment_webhooks", force: :cascade do |t|
    t.string "event_type"
    t.string "payment_key"
    t.string "order_id"
    t.string "status"
    t.jsonb "payload", default: {}
    t.datetime "processed_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type"], name: "index_payment_webhooks_on_event_type"
    t.index ["order_id"], name: "index_payment_webhooks_on_order_id"
    t.index ["payment_key"], name: "index_payment_webhooks_on_payment_key"
    t.index ["status"], name: "index_payment_webhooks_on_status"
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "transaction_id"
    t.string "order_id"
    t.string "payment_method"
    t.integer "amount"
    t.string "currency"
    t.string "status"
    t.datetime "approved_at"
    t.datetime "canceled_at"
    t.datetime "failed_at"
    t.string "card_number"
    t.string "card_type"
    t.string "receipt_url"
    t.string "checkout_url"
    t.string "failure_code"
    t.string "failure_message"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_payments_on_order_id", unique: true
    t.index ["payment_method"], name: "index_payments_on_payment_method"
    t.index ["status"], name: "index_payments_on_status"
    t.index ["transaction_id"], name: "index_payments_on_transaction_id", unique: true
    t.index ["user_id"], name: "index_payments_on_user_id"
  end

  create_table "rag_documents", force: :cascade do |t|
    t.text "content", null: false
    t.jsonb "metadata", default: {}, null: false
    t.text "embedding_text", null: false
    t.integer "credits", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "to_tsvector('english'::regconfig, content)", name: "index_rag_documents_on_content_tsvector", using: :gin
    t.index ["created_at"], name: "index_rag_documents_on_created_at"
    t.index ["credits", "created_at"], name: "idx_rag_docs_credits_created"
    t.index ["credits"], name: "index_rag_documents_on_credits"
    t.index ["metadata"], name: "index_rag_documents_on_metadata", using: :gin
    t.check_constraint "char_length(content) <= 10000", name: "content_max_length"
    t.check_constraint "char_length(content) >= 10", name: "content_min_length"
    t.check_constraint "credits > 0", name: "tokens_positive"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.binary "payload", null: false
    t.datetime "created_at", null: false
    t.bigint "channel_hash", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.binary "key", null: false
    t.binary "value", null: false
    t.datetime "created_at", null: false
    t.bigint "key_hash", null: false
    t.integer "byte_size", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "plan_type", null: false
    t.integer "status", default: 0, null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at"
    t.datetime "canceled_at"
    t.string "payment_id"
    t.string "payment_method"
    t.decimal "amount", precision: 10, scale: 2
    t.string "currency", default: "KRW"
    t.json "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "tier"
    t.index ["ends_at"], name: "index_subscriptions_on_ends_at"
    t.index ["plan_type"], name: "index_subscriptions_on_plan_type"
    t.index ["status", "ends_at"], name: "idx_subscriptions_status_end_date"
    t.index ["status"], name: "index_subscriptions_on_status"
    t.index ["user_id", "ends_at"], name: "idx_subscriptions_user_active", where: "(status = 0)"
    t.index ["user_id", "status"], name: "index_subscriptions_on_user_id_and_status"
    t.index ["user_id", "tier"], name: "idx_subscriptions_user_tier"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest"
    t.string "name", null: false
    t.integer "role", default: 0, null: false
    t.integer "tier", default: 0, null: false
    t.integer "credits", default: 100, null: false
    t.string "referral_code"
    t.string "referred_by"
    t.boolean "email_verified", default: false, null: false
    t.datetime "last_seen_at"
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "provider"
    t.string "uid"
    t.string "avatar_url"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["referral_code"], name: "index_users_on_referral_code", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role", "created_at"], name: "idx_users_role_created"
    t.index ["role"], name: "index_users_on_role"
    t.index ["tier", "credits"], name: "idx_users_tier_credits"
    t.index ["tier"], name: "index_users_on_tier"
  end

  add_foreign_key "ai_feedbacks", "chat_messages"
  add_foreign_key "ai_feedbacks", "users"
  add_foreign_key "ai_usage_records", "users"
  add_foreign_key "analyses", "excel_files"
  add_foreign_key "analyses", "users"
  add_foreign_key "billing_keys", "users"
  add_foreign_key "chat_conversations", "excel_files"
  add_foreign_key "chat_conversations", "users"
  add_foreign_key "chat_messages", "chat_conversations"
  add_foreign_key "chat_messages", "users"
  add_foreign_key "excel_files", "users"
  add_foreign_key "payment_intents", "users"
  add_foreign_key "payment_methods", "billing_keys"
  add_foreign_key "payment_methods", "users"
  add_foreign_key "payments", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "subscriptions", "users"
end
