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

ActiveRecord::Schema[7.1].define(version: 2026_05_21_000002) do
  # These extensions should be enabled to support this database
  enable_extension "pg_stat_statements"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"
  enable_extension "plpgsql"
  enable_extension "vector"

  create_table "access_tokens", force: :cascade do |t|
    t.string "owner_type"
    t.bigint "owner_id"
    t.string "token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id"], name: "index_access_tokens_on_owner_type_and_owner_id"
    t.index ["token"], name: "index_access_tokens_on_token", unique: true
  end

  create_table "account_saml_settings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "sso_url"
    t.text "certificate"
    t.string "sp_entity_id"
    t.string "idp_entity_id"
    t.json "role_mappings", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_account_saml_settings_on_account_id"
  end

  create_table "account_transactions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id"
    t.bigint "financial_category_id"
    t.bigint "bank_account_id"
    t.bigint "registered_by_id"
    t.bigint "professional_id"
    t.bigint "source_transaction_id"
    t.bigint "recurring_expense_id"
    t.bigint "estorno_de_id"
    t.string "entry_type", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.decimal "original_amount", precision: 12, scale: 2
    t.decimal "discount_amount", precision: 12, scale: 2, default: "0.0"
    t.string "payment_method"
    t.string "status", default: "pendente", null: false
    t.date "competence_date"
    t.date "due_date"
    t.date "received_at"
    t.date "paid_at"
    t.text "description"
    t.text "notes"
    t.string "origin"
    t.jsonb "metadata", default: {}
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "payment_source"
    t.index ["account_id", "competence_date"], name: "idx_acct_txns_account_competence"
    t.index ["account_id", "entry_type", "status"], name: "idx_acct_txns_account_type_status"
    t.index ["account_id"], name: "index_account_transactions_on_account_id"
    t.index ["bank_account_id"], name: "index_account_transactions_on_bank_account_id"
    t.index ["competence_date"], name: "index_account_transactions_on_competence_date"
    t.index ["deleted_at"], name: "index_account_transactions_on_deleted_at"
    t.index ["due_date"], name: "index_account_transactions_on_due_date"
    t.index ["entry_type"], name: "index_account_transactions_on_entry_type"
    t.index ["financial_category_id"], name: "index_account_transactions_on_financial_category_id"
    t.index ["patient_id"], name: "index_account_transactions_on_patient_id"
    t.index ["payment_source"], name: "index_account_transactions_on_payment_source"
    t.index ["recurring_expense_id"], name: "index_account_transactions_on_recurring_expense_id"
    t.index ["source_transaction_id"], name: "index_account_transactions_on_source_transaction_id", unique: true
    t.index ["status"], name: "index_account_transactions_on_status"
    t.check_constraint "payment_source IS NULL OR (payment_source::text = ANY (ARRAY['particular'::character varying::text, 'convenio'::character varying::text, 'plano'::character varying::text, 'outro'::character varying::text]))", name: "chk_account_transactions_payment_source"
  end

  create_table "account_users", force: :cascade do |t|
    t.bigint "account_id"
    t.bigint "user_id"
    t.integer "role", default: 0
    t.bigint "inviter_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "active_at", precision: nil
    t.integer "availability", default: 0, null: false
    t.boolean "auto_offline", default: true, null: false
    t.bigint "custom_role_id"
    t.bigint "agent_capacity_policy_id"
    t.bigint "klivy_role_id"
    t.boolean "is_agenda_provider"
    t.index ["account_id", "user_id"], name: "uniq_user_id_per_account_id", unique: true
    t.index ["account_id"], name: "index_account_users_on_account_id"
    t.index ["agent_capacity_policy_id"], name: "index_account_users_on_agent_capacity_policy_id"
    t.index ["custom_role_id"], name: "index_account_users_on_custom_role_id"
    t.index ["klivy_role_id"], name: "index_account_users_on_klivy_role_id"
    t.index ["user_id"], name: "index_account_users_on_user_id"
  end

  create_table "accounts", id: :serial, force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "locale", default: 0
    t.string "domain", limit: 100
    t.string "support_email", limit: 100
    t.bigint "feature_flags", default: 0, null: false
    t.integer "auto_resolve_duration"
    t.jsonb "limits", default: {}
    t.jsonb "custom_attributes", default: {}
    t.integer "status", default: 0
    t.jsonb "internal_attributes", default: {}, null: false
    t.jsonb "settings", default: {}
    t.index ["status"], name: "index_accounts_on_status"
  end

  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.string "message_id", null: false
    t.string "message_checksum", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", precision: nil, null: false
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agenda_audit_logs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id"
    t.string "entity_type", limit: 80, null: false
    t.bigint "entity_id", null: false
    t.string "action", limit: 30, null: false
    t.string "ip_address", limit: 45
    t.string "user_agent"
    t.jsonb "before", default: {}
    t.jsonb "after", default: {}
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.index ["account_id", "action"], name: "index_agenda_audit_logs_on_account_id_and_action"
    t.index ["account_id", "created_at"], name: "index_agenda_audit_logs_on_account_id_and_created"
    t.index ["account_id", "entity_type", "entity_id"], name: "idx_agenda_audit_logs_on_entity"
    t.index ["account_id", "user_id", "created_at"], name: "idx_agenda_audit_logs_chronological"
    t.index ["account_id"], name: "index_agenda_audit_logs_on_account_id"
  end

  create_table "agenda_categories", force: :cascade do |t|
    t.string "name", null: false
    t.string "color", default: "#3b82f6", null: false
    t.integer "position", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_agenda_categories_on_account_id_and_name", unique: true
    t.index ["account_id", "position"], name: "index_agenda_categories_on_account_id_and_position"
    t.index ["account_id"], name: "index_agenda_categories_on_account_id"
  end

  create_table "agenda_custom_attributes", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "field_type", default: "text", null: false
    t.boolean "required", default: false, null: false
    t.boolean "validate_cpf", default: true, null: false
    t.text "options"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "position"], name: "idx_agenda_custom_attrs_account_position"
    t.index ["account_id"], name: "index_agenda_custom_attributes_on_account_id"
  end

  create_table "agenda_events", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id"
    t.bigint "contact_id"
    t.string "title", null: false
    t.text "description"
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.jsonb "custom_attributes", default: {}
    t.string "status", default: "scheduled", null: false
    t.string "event_type", default: "appointment", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "category_id"
    t.string "source", default: "manual", null: false
    t.datetime "deleted_at"
    t.bigint "deleted_by_id"
    t.string "deletion_reason"
    t.text "deletion_note"
    t.bigint "agenda_service_id"
    t.index "((custom_attributes ->> 'patient_id'::text))", name: "index_agenda_events_on_patient_id_in_custom_attrs", where: "(((custom_attributes ->> 'patient_id'::text) IS NOT NULL) AND ((custom_attributes ->> 'patient_id'::text) <> ''::text))"
    t.index ["account_id", "source"], name: "index_agenda_events_on_account_and_source"
    t.index ["account_id", "starts_at"], name: "index_agenda_events_on_account_and_starts_at"
    t.index ["account_id", "user_id", "starts_at"], name: "index_agenda_events_kept_on_account_user_starts_at", where: "(deleted_at IS NULL)"
    t.index ["account_id", "user_id", "starts_at"], name: "index_agenda_events_on_account_user_starts_at"
    t.index ["account_id"], name: "index_agenda_events_on_account_id"
    t.index ["agenda_service_id"], name: "index_agenda_events_on_agenda_service_id"
    t.index ["category_id"], name: "index_agenda_events_on_category_id"
    t.index ["contact_id"], name: "index_agenda_events_on_contact_id"
    t.index ["deleted_at"], name: "index_agenda_events_on_deleted_at"
    t.index ["deleted_by_id"], name: "index_agenda_events_on_deleted_by_id"
    t.index ["user_id"], name: "index_agenda_events_on_user_id"
  end

  create_table "agenda_notification_logs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "agenda_event_id", null: false
    t.bigint "agenda_notification_rule_id", null: false
    t.datetime "sent_at", null: false
    t.string "status", default: "sent", null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_agenda_notification_logs_on_account_id_and_status"
    t.index ["account_id"], name: "index_agenda_notification_logs_on_account_id"
    t.index ["agenda_event_id", "agenda_notification_rule_id"], name: "idx_notif_log_unique_event_rule", unique: true
    t.index ["agenda_event_id"], name: "index_agenda_notification_logs_on_agenda_event_id"
    t.index ["agenda_notification_rule_id"], name: "index_agenda_notification_logs_on_agenda_notification_rule_id"
    t.index ["sent_at"], name: "index_agenda_notification_logs_on_sent_at"
  end

  create_table "agenda_notification_rules", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "title", null: false
    t.string "rule_type", default: "reminder", null: false
    t.string "icon", default: "i-lucide-bell", null: false
    t.string "icon_color", default: "blue", null: false
    t.decimal "trigger_offset_hours", precision: 8, scale: 2
    t.text "message_template", null: false
    t.jsonb "inboxes", default: [], null: false
    t.boolean "enabled", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "enabled"], name: "index_agenda_notification_rules_on_account_id_and_enabled"
    t.index ["account_id", "rule_type"], name: "index_agenda_notification_rules_on_account_id_and_rule_type"
    t.index ["account_id"], name: "index_agenda_notification_rules_on_account_id"
  end

  create_table "agenda_online_configs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.boolean "enabled", default: true
    t.boolean "allow_new_patients", default: true
    t.boolean "require_whatsapp_verification", default: false
    t.boolean "require_email_verification", default: false
    t.integer "min_lead_time_minutes", default: 180
    t.integer "future_limit_days", default: 60
    t.jsonb "form_fields", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_agenda_online_configs_on_account_id"
  end

  create_table "agenda_service_users", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "agenda_service_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_agenda_service_users_on_account_id"
    t.index ["agenda_service_id", "user_id"], name: "idx_agenda_service_users_unique", unique: true
    t.index ["agenda_service_id"], name: "index_agenda_service_users_on_agenda_service_id"
    t.index ["user_id"], name: "index_agenda_service_users_on_user_id"
  end

  create_table "agenda_services", force: :cascade do |t|
    t.string "name", null: false
    t.integer "duration_minutes", default: 60, null: false
    t.decimal "price", precision: 10, scale: 2, default: "0.0"
    t.boolean "requires_room", default: false, null: false
    t.string "color", default: "#3b82f6"
    t.integer "position", default: 0
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "default_category_id"
    t.datetime "deleted_at"
    t.uuid "uuid", default: -> { "gen_random_uuid()" }
    t.string "external_id", limit: 100
    t.index "account_id, lower(btrim((name)::text))", name: "uniq_agenda_services_account_lower_btrim_name", unique: true, where: "(deleted_at IS NULL)"
    t.index ["account_id", "deleted_at"], name: "index_agenda_services_on_account_id_and_deleted_at"
    t.index ["account_id", "external_id"], name: "uniq_agenda_services_account_external_id", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["account_id", "position"], name: "index_agenda_services_on_account_id_and_position"
    t.index ["account_id"], name: "index_agenda_services_on_account_id"
    t.index ["default_category_id"], name: "index_agenda_services_on_default_category_id"
    t.index ["uuid"], name: "uniq_agenda_services_uuid", unique: true
  end

  create_table "agenda_settings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.boolean "block_outside_working_hours", default: false, null: false
    t.boolean "block_lunch_break", default: false, null: false
    t.jsonb "week_days", default: [], null: false
    t.jsonb "exceptions", default: [], null: false
    t.jsonb "holidays", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "slot_interval_minutes", default: 60, null: false
    t.boolean "block_past_dates", default: false, null: false
    t.boolean "show_only_working_hours", default: false, null: false
    t.integer "visible_hours_buffer", default: 2, null: false
    t.index ["account_id"], name: "index_agenda_settings_on_account_id", unique: true
  end

  create_table "agent_bot_inboxes", force: :cascade do |t|
    t.integer "inbox_id"
    t.integer "agent_bot_id"
    t.integer "status", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "account_id"
  end

  create_table "agent_bots", force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.string "outgoing_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id"
    t.integer "bot_type", default: 0
    t.jsonb "bot_config", default: {}
    t.index ["account_id"], name: "index_agent_bots_on_account_id"
  end

  create_table "agent_capacity_policies", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", limit: 255, null: false
    t.text "description"
    t.jsonb "exclusion_rules", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_agent_capacity_policies_on_account_id"
  end

  create_table "ai_agent_account_settings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.boolean "enabled", default: false, null: false
    t.string "chat_model"
    t.integer "monthly_token_budget"
    t.integer "max_tokens_per_conversation"
    t.bigint "persona_id"
    t.jsonb "enabled_tools", default: [], null: false
    t.text "system_prompt_prefix"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "responsible_physician_id"
    t.string "responsible_physician_crm"
    t.string "responsible_physician_council"
    t.index ["account_id"], name: "index_ai_agent_account_settings_on_account_id", unique: true
    t.index ["persona_id"], name: "index_ai_agent_account_settings_on_persona_id"
    t.index ["responsible_physician_id"], name: "index_ai_agent_account_settings_on_responsible_physician_id"
  end

  create_table "ai_agent_audit_logs", force: :cascade do |t|
    t.bigint "super_admin_id"
    t.bigint "user_id"
    t.bigint "account_id"
    t.string "scope", null: false
    t.string "action", null: false
    t.jsonb "changes_summary", default: {}, null: false
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.index ["account_id"], name: "index_ai_agent_audit_logs_on_account_id"
    t.index ["created_at"], name: "index_ai_agent_audit_logs_on_created_at"
    t.index ["scope"], name: "index_ai_agent_audit_logs_on_scope"
  end

  create_table "ai_agent_child_chunks", force: :cascade do |t|
    t.bigint "parent_chunk_id", null: false
    t.bigint "document_id", null: false
    t.bigint "account_id", null: false
    t.integer "position", null: false
    t.text "content", null: false
    t.vector "embedding", limit: 1536
    t.integer "char_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_ai_agent_child_chunks_on_account_id"
    t.index ["document_id"], name: "index_ai_agent_child_chunks_on_document_id"
    t.index ["embedding"], name: "ai_agent_child_chunks_embedding_idx", opclass: :vector_cosine_ops, using: :ivfflat
    t.index ["parent_chunk_id", "position"], name: "index_ai_agent_child_chunks_on_parent_chunk_id_and_position", unique: true
    t.index ["parent_chunk_id"], name: "index_ai_agent_child_chunks_on_parent_chunk_id"
  end

  create_table "ai_agent_conversation_states", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "conversation_id", null: false
    t.string "status", default: "active", null: false
    t.string "last_intent"
    t.text "summary"
    t.jsonb "working_memory", default: {}, null: false
    t.datetime "last_message_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "last_sentiment_score", precision: 4, scale: 3
    t.string "last_sentiment_label"
    t.integer "consecutive_negative_count", default: 0, null: false
    t.integer "consecutive_tool_failures", default: 0, null: false
    t.index ["account_id", "conversation_id"], name: "idx_ai_agent_state_on_account_conv", unique: true
    t.index ["account_id"], name: "index_ai_agent_conversation_states_on_account_id"
    t.index ["status"], name: "index_ai_agent_conversation_states_on_status"
  end

  create_table "ai_agent_documents", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "source_type", default: "pdf", null: false
    t.string "external_link"
    t.integer "status", default: 0, null: false
    t.text "error_message"
    t.string "checksum"
    t.integer "char_count", default: 0
    t.integer "parent_chunk_count", default: 0
    t.integer "child_chunk_count", default: 0
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "checksum"], name: "index_ai_agent_documents_on_account_id_and_checksum"
    t.index ["account_id"], name: "index_ai_agent_documents_on_account_id"
    t.index ["status"], name: "index_ai_agent_documents_on_status"
  end

  create_table "ai_agent_feedbacks", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "trace_id"
    t.bigint "conversation_id"
    t.bigint "message_id"
    t.bigint "contact_id"
    t.integer "rating", null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "index_ai_agent_feedbacks_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_ai_agent_feedbacks_on_account_id"
    t.index ["rating"], name: "index_ai_agent_feedbacks_on_rating"
    t.index ["trace_id"], name: "index_ai_agent_feedbacks_on_trace_id"
  end

  create_table "ai_agent_follow_up_executions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "rule_id", null: false
    t.bigint "contact_id"
    t.bigint "conversation_id"
    t.bigint "agenda_event_id"
    t.datetime "target_at", null: false
    t.datetime "sent_at"
    t.string "status", default: "pending", null: false
    t.string "skip_reason"
    t.bigint "message_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status", "target_at"], name: "idx_ai_agent_follow_up_executions_status"
    t.index ["account_id"], name: "index_ai_agent_follow_up_executions_on_account_id"
    t.index ["rule_id", "contact_id", "agenda_event_id", "target_at"], name: "idx_ai_agent_follow_up_executions_unique_target", unique: true
    t.index ["rule_id"], name: "index_ai_agent_follow_up_executions_on_rule_id"
  end

  create_table "ai_agent_follow_up_rules", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", limit: 120, null: false
    t.boolean "enabled", default: true, null: false
    t.integer "position", default: 0, null: false
    t.string "trigger_type", null: false
    t.integer "offset_hours", default: 24, null: false
    t.jsonb "status_filter", default: {}, null: false
    t.text "context_brief", null: false
    t.integer "max_per_target", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "offset_unit", default: "hours", null: false
    t.string "applies_to", default: "both", null: false
    t.index ["account_id", "enabled", "trigger_type"], name: "idx_ai_agent_follow_up_rules_dispatch"
    t.index ["account_id"], name: "index_ai_agent_follow_up_rules_on_account_id"
  end

  create_table "ai_agent_global_settings", force: :cascade do |t|
    t.string "chat_provider", default: "openai", null: false
    t.string "chat_model"
    t.integer "max_tokens_per_conversation", default: 4096, null: false
    t.integer "max_monthly_cost_per_account_cents", default: 0, null: false
    t.bigint "default_persona_id"
    t.boolean "enabled_by_default_for_new_accounts", default: false, null: false
    t.jsonb "guardrails", default: {}, null: false
    t.jsonb "telemetry_config", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["default_persona_id"], name: "index_ai_agent_global_settings_on_default_persona_id"
  end

  create_table "ai_agent_internal_notification_templates", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "event_key", null: false
    t.string "name", null: false
    t.text "body", null: false
    t.string "target_type", default: "room", null: false
    t.bigint "target_id"
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "event_key"], name: "idx_ai_internal_notif_tpl_account_event", unique: true
    t.index ["account_id"], name: "index_ai_agent_internal_notification_templates_on_account_id"
  end

  create_table "ai_agent_parent_chunks", force: :cascade do |t|
    t.bigint "document_id", null: false
    t.integer "position", null: false
    t.text "content", null: false
    t.integer "char_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["document_id", "position"], name: "index_ai_agent_parent_chunks_on_document_id_and_position", unique: true
    t.index ["document_id"], name: "index_ai_agent_parent_chunks_on_document_id"
  end

  create_table "ai_agent_patient_memories", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "contact_id", null: false
    t.jsonb "preferences", default: {}, null: false
    t.jsonb "history", default: [], null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_consolidated_at"
    t.index ["account_id", "contact_id"], name: "idx_ai_agent_memory_on_account_contact", unique: true
    t.index ["account_id"], name: "index_ai_agent_patient_memories_on_account_id"
    t.index ["last_consolidated_at"], name: "index_ai_agent_patient_memories_on_last_consolidated_at"
  end

  create_table "ai_agent_persona_templates", force: :cascade do |t|
    t.string "name", null: false
    t.string "vertical", default: "general", null: false
    t.text "system_prompt", null: false
    t.jsonb "tone_settings", default: {}, null: false
    t.jsonb "few_shot_examples", default: [], null: false
    t.boolean "builtin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_ai_agent_persona_templates_on_name", unique: true
    t.index ["vertical"], name: "index_ai_agent_persona_templates_on_vertical"
  end

  create_table "ai_agent_tool_definitions", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.text "description"
    t.boolean "enabled_globally", default: true, null: false
    t.boolean "requires_oauth", default: false, null: false
    t.boolean "builtin", default: false, null: false
    t.jsonb "config_schema", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled_globally"], name: "index_ai_agent_tool_definitions_on_enabled_globally"
    t.index ["key"], name: "index_ai_agent_tool_definitions_on_key", unique: true
  end

  create_table "ai_agent_traces", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "conversation_id"
    t.bigint "message_id"
    t.bigint "contact_id"
    t.string "model"
    t.string "provider"
    t.integer "latency_ms"
    t.bigint "input_tokens", default: 0
    t.bigint "output_tokens", default: 0
    t.integer "cost_cents", default: 0
    t.jsonb "tool_calls", default: [], null: false
    t.string "sentiment_label"
    t.decimal "sentiment_score", precision: 4, scale: 3
    t.boolean "escalated", default: false, null: false
    t.string "escalation_reason"
    t.jsonb "guardrail_violations", default: [], null: false
    t.boolean "short_circuited", default: false, null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.index ["account_id", "created_at"], name: "index_ai_agent_traces_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_ai_agent_traces_on_account_id"
    t.index ["conversation_id"], name: "index_ai_agent_traces_on_conversation_id"
    t.index ["escalated"], name: "index_ai_agent_traces_on_escalated"
    t.index ["message_id"], name: "idx_ai_agent_traces_unique_message_success", unique: true, where: "((message_id IS NOT NULL) AND (error_message IS NULL))"
    t.index ["message_id"], name: "index_ai_agent_traces_on_message_id"
  end

  create_table "ai_agent_usage_counters", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.date "date", null: false
    t.bigint "input_tokens", default: 0, null: false
    t.bigint "output_tokens", default: 0, null: false
    t.integer "cost_cents", default: 0, null: false
    t.integer "conversations_count", default: 0, null: false
    t.integer "tool_calls_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "date"], name: "index_ai_agent_usage_counters_on_account_id_and_date", unique: true
    t.index ["account_id"], name: "index_ai_agent_usage_counters_on_account_id"
    t.index ["date"], name: "index_ai_agent_usage_counters_on_date"
  end

  create_table "anamneses", force: :cascade do |t|
    t.bigint "patient_id", null: false
    t.bigint "account_id", null: false
    t.bigint "professional_id"
    t.bigint "form_template_id"
    t.integer "version_number", default: 1, null: false
    t.string "specialty"
    t.text "chief_complaint"
    t.jsonb "medical_history", default: {}
    t.jsonb "allergies", default: []
    t.jsonb "current_medications", default: []
    t.text "surgical_history"
    t.text "family_history"
    t.jsonb "pregnancy", default: {}
    t.jsonb "relevant_habits", default: {}
    t.jsonb "contraindications", default: []
    t.text "additional_notes"
    t.string "status", default: "draft", null: false
    t.datetime "finalized_at"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_anamneses_on_account_id"
    t.index ["deleted_at"], name: "index_anamneses_on_deleted_at"
    t.index ["patient_id", "status", "deleted_at"], name: "index_anamneses_on_patient_status_deleted"
    t.index ["patient_id", "version_number"], name: "index_anamneses_on_patient_id_and_version_number"
    t.index ["patient_id"], name: "index_anamneses_on_patient_id"
    t.index ["professional_id"], name: "index_anamneses_on_professional_id"
    t.index ["status"], name: "index_anamneses_on_status"
  end

  create_table "applied_slas", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "sla_policy_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "sla_status", default: 0
    t.index ["account_id", "sla_policy_id", "conversation_id"], name: "index_applied_slas_on_account_sla_policy_conversation", unique: true
    t.index ["account_id"], name: "index_applied_slas_on_account_id"
    t.index ["conversation_id"], name: "index_applied_slas_on_conversation_id"
    t.index ["sla_policy_id"], name: "index_applied_slas_on_sla_policy_id"
  end

  create_table "article_embeddings", force: :cascade do |t|
    t.bigint "article_id", null: false
    t.text "term", null: false
    t.vector "embedding", limit: 1536
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["embedding"], name: "index_article_embeddings_on_embedding", using: :ivfflat
  end

  create_table "articles", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "portal_id", null: false
    t.integer "category_id"
    t.integer "folder_id"
    t.string "title"
    t.text "description"
    t.text "content"
    t.integer "status"
    t.integer "views"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "author_id"
    t.bigint "associated_article_id"
    t.jsonb "meta", default: {}
    t.string "slug", null: false
    t.integer "position"
    t.string "locale", default: "en", null: false
    t.index ["account_id"], name: "index_articles_on_account_id"
    t.index ["associated_article_id"], name: "index_articles_on_associated_article_id"
    t.index ["author_id"], name: "index_articles_on_author_id"
    t.index ["portal_id"], name: "index_articles_on_portal_id"
    t.index ["slug"], name: "index_articles_on_slug", unique: true
    t.index ["status"], name: "index_articles_on_status"
    t.index ["views"], name: "index_articles_on_views"
  end

  create_table "assignment_policies", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", limit: 255, null: false
    t.text "description"
    t.integer "assignment_order", default: 0, null: false
    t.integer "conversation_priority", default: 0, null: false
    t.integer "fair_distribution_limit", default: 100, null: false
    t.integer "fair_distribution_window", default: 3600, null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_assignment_policies_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_assignment_policies_on_account_id"
    t.index ["enabled"], name: "index_assignment_policies_on_enabled"
  end

  create_table "attachments", id: :serial, force: :cascade do |t|
    t.integer "file_type", default: 0
    t.string "external_url"
    t.float "coordinates_lat", default: 0.0
    t.float "coordinates_long", default: 0.0
    t.integer "message_id", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "fallback_title"
    t.string "extension"
    t.jsonb "meta", default: {}
    t.index ["account_id"], name: "index_attachments_on_account_id"
    t.index ["message_id"], name: "index_attachments_on_message_id"
  end

  create_table "audits", force: :cascade do |t|
    t.bigint "auditable_id"
    t.string "auditable_type"
    t.bigint "associated_id"
    t.string "associated_type"
    t.bigint "user_id"
    t.string "user_type"
    t.string "username"
    t.string "action"
    t.jsonb "audited_changes"
    t.integer "version", default: 0
    t.string "comment"
    t.string "remote_address"
    t.string "request_uuid"
    t.datetime "created_at", precision: nil
    t.index ["associated_type", "associated_id"], name: "associated_index"
    t.index ["auditable_type", "auditable_id", "version"], name: "auditable_index"
    t.index ["created_at"], name: "index_audits_on_created_at"
    t.index ["request_uuid"], name: "index_audits_on_request_uuid"
    t.index ["user_id", "user_type"], name: "user_index"
  end

  create_table "automation_rules", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "event_name", null: false
    t.jsonb "conditions", default: "{}", null: false
    t.jsonb "actions", default: "{}", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "active", default: true, null: false
    t.index ["account_id"], name: "index_automation_rules_on_account_id"
  end

  create_table "bank_accounts", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "bank_name"
    t.string "bank_code"
    t.string "account_type", default: "checking"
    t.decimal "initial_balance", precision: 12, scale: 2, default: "0.0"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "active"], name: "index_bank_accounts_on_account_id_and_active"
    t.index ["account_id"], name: "index_bank_accounts_on_account_id"
  end

  create_table "beclinic_account_profiles", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.decimal "monthly_goal", precision: 15, scale: 2
    t.decimal "quarterly_goal", precision: 15, scale: 2
    t.decimal "annual_goal", precision: 15, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_beclinic_account_profiles_on_account_id"
  end

  create_table "beclinic_user_profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "agenda_public_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id", null: false
    t.index ["account_id"], name: "index_beclinic_user_profiles_on_account_id"
    t.index ["user_id", "account_id"], name: "index_beclinic_user_profiles_on_user_and_account", unique: true
    t.index ["user_id"], name: "index_beclinic_user_profiles_on_user_id"
  end

  create_table "billing_customers", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "cpf_cnpj"
    t.string "phone"
    t.string "asaas_customer_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "billing_payments", force: :cascade do |t|
    t.bigint "subscription_id", null: false
    t.integer "status", default: 0, null: false
    t.decimal "amount", precision: 10, scale: 2
    t.datetime "due_date"
    t.datetime "paid_at"
    t.string "asaas_payment_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subscription_id"], name: "index_billing_payments_on_subscription_id"
  end

  create_table "billing_subscriptions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "status", default: 0, null: false
    t.string "plan"
    t.decimal "price", precision: 10, scale: 2
    t.string "asaas_customer_id"
    t.string "asaas_subscription_id"
    t.datetime "next_due_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "coupon_code"
    t.datetime "coupon_expires_at"
    t.string "asaas_credit_card_token"
    t.index ["account_id"], name: "index_billing_subscriptions_on_account_id"
    t.index ["coupon_expires_at"], name: "index_billing_subscriptions_on_coupon_expires_at", where: "(coupon_expires_at IS NOT NULL)"
  end

  create_table "campaigns", force: :cascade do |t|
    t.integer "display_id", null: false
    t.string "title", null: false
    t.text "description"
    t.text "message", null: false
    t.integer "sender_id"
    t.boolean "enabled", default: true
    t.bigint "account_id", null: false
    t.bigint "inbox_id", null: false
    t.jsonb "trigger_rules", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "campaign_type", default: 0, null: false
    t.integer "campaign_status", default: 0, null: false
    t.jsonb "audience", default: []
    t.datetime "scheduled_at", precision: nil
    t.boolean "trigger_only_during_business_hours", default: false
    t.jsonb "template_params"
    t.index ["account_id"], name: "index_campaigns_on_account_id"
    t.index ["campaign_status"], name: "index_campaigns_on_campaign_status"
    t.index ["campaign_type"], name: "index_campaigns_on_campaign_type"
    t.index ["inbox_id"], name: "index_campaigns_on_inbox_id"
    t.index ["scheduled_at"], name: "index_campaigns_on_scheduled_at"
  end

  create_table "canned_responses", id: :serial, force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "short_code"
    t.text "content"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "captain_assistant_responses", force: :cascade do |t|
    t.string "question", null: false
    t.text "answer", null: false
    t.vector "embedding", limit: 1536
    t.bigint "assistant_id", null: false
    t.bigint "documentable_id"
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "status", default: 1, null: false
    t.string "documentable_type"
    t.index ["account_id"], name: "index_captain_assistant_responses_on_account_id"
    t.index ["assistant_id"], name: "index_captain_assistant_responses_on_assistant_id"
    t.index ["documentable_id", "documentable_type"], name: "idx_cap_asst_resp_on_documentable"
    t.index ["embedding"], name: "vector_idx_knowledge_entries_embedding", using: :ivfflat
    t.index ["status"], name: "index_captain_assistant_responses_on_status"
  end

  create_table "captain_assistants", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "account_id", null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "config", default: {}, null: false
    t.jsonb "response_guidelines", default: []
    t.jsonb "guardrails", default: []
    t.index ["account_id"], name: "index_captain_assistants_on_account_id"
  end

  create_table "captain_custom_tools", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.text "description"
    t.string "http_method", default: "GET", null: false
    t.text "endpoint_url", null: false
    t.text "request_template"
    t.text "response_template"
    t.string "auth_type", default: "none"
    t.jsonb "auth_config", default: {}
    t.jsonb "param_schema", default: []
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "slug"], name: "index_captain_custom_tools_on_account_id_and_slug", unique: true
    t.index ["account_id"], name: "index_captain_custom_tools_on_account_id"
  end

  create_table "captain_documents", force: :cascade do |t|
    t.string "name"
    t.string "external_link", null: false
    t.text "content"
    t.bigint "assistant_id", null: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "metadata", default: {}
    t.index ["account_id"], name: "index_captain_documents_on_account_id"
    t.index ["assistant_id", "external_link"], name: "index_captain_documents_on_assistant_id_and_external_link", unique: true
    t.index ["assistant_id"], name: "index_captain_documents_on_assistant_id"
    t.index ["status"], name: "index_captain_documents_on_status"
  end

  create_table "captain_inboxes", force: :cascade do |t|
    t.bigint "captain_assistant_id", null: false
    t.bigint "inbox_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["captain_assistant_id", "inbox_id"], name: "index_captain_inboxes_on_captain_assistant_id_and_inbox_id", unique: true
    t.index ["captain_assistant_id"], name: "index_captain_inboxes_on_captain_assistant_id"
    t.index ["inbox_id"], name: "index_captain_inboxes_on_inbox_id"
  end

  create_table "captain_scenarios", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.text "instruction"
    t.jsonb "tools", default: []
    t.boolean "enabled", default: true, null: false
    t.bigint "assistant_id", null: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_captain_scenarios_on_account_id"
    t.index ["assistant_id", "enabled"], name: "index_captain_scenarios_on_assistant_id_and_enabled"
    t.index ["assistant_id"], name: "index_captain_scenarios_on_assistant_id"
    t.index ["enabled"], name: "index_captain_scenarios_on_enabled"
  end

  create_table "cash_entries", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "entry_type", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "description"
    t.string "source_type"
    t.bigint "source_id"
    t.string "payment_method"
    t.date "entry_date", null: false
    t.bigint "patient_id"
    t.bigint "registered_by_id"
    t.jsonb "metadata", default: {}
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "entry_date"], name: "index_cash_entries_on_account_id_and_entry_date"
    t.index ["account_id"], name: "index_cash_entries_on_account_id"
    t.index ["deleted_at"], name: "index_cash_entries_on_deleted_at"
    t.index ["entry_date"], name: "index_cash_entries_on_entry_date"
    t.index ["entry_type"], name: "index_cash_entries_on_entry_type"
    t.index ["patient_id"], name: "index_cash_entries_on_patient_id"
    t.index ["payment_method"], name: "index_cash_entries_on_payment_method"
    t.index ["source_type", "source_id"], name: "index_cash_entries_on_source_type_and_source_id"
  end

  create_table "cash_register_entries", force: :cascade do |t|
    t.bigint "cash_register_id", null: false
    t.bigint "account_id", null: false
    t.string "entry_type", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "payment_method"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_cash_register_entries_on_account_id"
    t.index ["cash_register_id", "entry_type"], name: "idx_cash_reg_entries_register_type"
    t.index ["cash_register_id"], name: "index_cash_register_entries_on_cash_register_id"
  end

  create_table "cash_registers", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "operator_id", null: false
    t.date "register_date", null: false
    t.string "status", default: "open", null: false
    t.decimal "opening_balance", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "cash_in", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "cash_out", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "withdrawals", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "supplements", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "closing_balance", precision: 10, scale: 2
    t.decimal "declared_balance", precision: 10, scale: 2
    t.decimal "difference", precision: 10, scale: 2
    t.text "closing_notes"
    t.datetime "opened_at"
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "operator_id", "register_date"], name: "idx_cash_registers_account_operator_date"
    t.index ["account_id", "register_date"], name: "idx_cash_registers_account_date"
    t.index ["account_id", "status"], name: "idx_cash_registers_account_status"
    t.index ["account_id"], name: "index_cash_registers_on_account_id"
    t.index ["operator_id"], name: "index_cash_registers_on_operator_id"
  end

  create_table "categories", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "portal_id", null: false
    t.string "name"
    t.text "description"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "locale", default: "en"
    t.string "slug", null: false
    t.bigint "parent_category_id"
    t.bigint "associated_category_id"
    t.string "icon", default: ""
    t.index ["associated_category_id"], name: "index_categories_on_associated_category_id"
    t.index ["locale", "account_id"], name: "index_categories_on_locale_and_account_id"
    t.index ["locale"], name: "index_categories_on_locale"
    t.index ["parent_category_id"], name: "index_categories_on_parent_category_id"
    t.index ["slug", "locale", "portal_id"], name: "index_categories_on_slug_and_locale_and_portal_id", unique: true
  end

  create_table "channel_api", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "webhook_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "identifier"
    t.string "hmac_token"
    t.boolean "hmac_mandatory", default: false
    t.jsonb "additional_attributes", default: {}
    t.index ["hmac_token"], name: "index_channel_api_on_hmac_token", unique: true
    t.index ["identifier"], name: "index_channel_api_on_identifier", unique: true
  end

  create_table "channel_email", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "email", null: false
    t.string "forward_to_email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "imap_enabled", default: false
    t.string "imap_address", default: ""
    t.integer "imap_port", default: 0
    t.string "imap_login", default: ""
    t.string "imap_password", default: ""
    t.boolean "imap_enable_ssl", default: true
    t.boolean "smtp_enabled", default: false
    t.string "smtp_address", default: ""
    t.integer "smtp_port", default: 0
    t.string "smtp_login", default: ""
    t.string "smtp_password", default: ""
    t.string "smtp_domain", default: ""
    t.boolean "smtp_enable_starttls_auto", default: true
    t.string "smtp_authentication", default: "login"
    t.string "smtp_openssl_verify_mode", default: "none"
    t.boolean "smtp_enable_ssl_tls", default: false
    t.jsonb "provider_config", default: {}
    t.string "provider"
    t.boolean "verified_for_sending", default: false, null: false
    t.index ["email"], name: "index_channel_email_on_email", unique: true
    t.index ["forward_to_email"], name: "index_channel_email_on_forward_to_email", unique: true
  end

  create_table "channel_facebook_pages", id: :serial, force: :cascade do |t|
    t.string "page_id", null: false
    t.string "user_access_token", null: false
    t.string "page_access_token", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "instagram_id"
    t.index ["page_id", "account_id"], name: "index_channel_facebook_pages_on_page_id_and_account_id", unique: true
    t.index ["page_id"], name: "index_channel_facebook_pages_on_page_id"
  end

  create_table "channel_instagram", force: :cascade do |t|
    t.string "access_token", null: false
    t.datetime "expires_at", null: false
    t.integer "account_id", null: false
    t.string "instagram_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["instagram_id"], name: "index_channel_instagram_on_instagram_id", unique: true
  end

  create_table "channel_line", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "line_channel_id", null: false
    t.string "line_channel_secret", null: false
    t.string "line_channel_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["line_channel_id"], name: "index_channel_line_on_line_channel_id", unique: true
  end

  create_table "channel_sms", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "phone_number", null: false
    t.string "provider", default: "default"
    t.jsonb "provider_config", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["phone_number"], name: "index_channel_sms_on_phone_number", unique: true
  end

  create_table "channel_telegram", force: :cascade do |t|
    t.string "bot_name"
    t.integer "account_id", null: false
    t.string "bot_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bot_token"], name: "index_channel_telegram_on_bot_token", unique: true
  end

  create_table "channel_tiktok", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "business_id", null: false
    t.string "access_token", null: false
    t.datetime "expires_at", null: false
    t.string "refresh_token", null: false
    t.datetime "refresh_token_expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_channel_tiktok_on_business_id", unique: true
  end

  create_table "channel_twilio_sms", force: :cascade do |t|
    t.string "phone_number"
    t.string "auth_token", null: false
    t.string "account_sid", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "medium", default: 0
    t.string "messaging_service_sid"
    t.string "api_key_sid"
    t.jsonb "content_templates", default: {}
    t.datetime "content_templates_last_updated"
    t.index ["account_sid", "phone_number"], name: "index_channel_twilio_sms_on_account_sid_and_phone_number", unique: true
    t.index ["messaging_service_sid"], name: "index_channel_twilio_sms_on_messaging_service_sid", unique: true
    t.index ["phone_number"], name: "index_channel_twilio_sms_on_phone_number", unique: true
  end

  create_table "channel_twitter_profiles", force: :cascade do |t|
    t.string "profile_id", null: false
    t.string "twitter_access_token", null: false
    t.string "twitter_access_token_secret", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "tweets_enabled", default: true
    t.index ["account_id", "profile_id"], name: "index_channel_twitter_profiles_on_account_id_and_profile_id", unique: true
  end

  create_table "channel_voice", force: :cascade do |t|
    t.string "phone_number", null: false
    t.string "provider", default: "twilio", null: false
    t.jsonb "provider_config", null: false
    t.integer "account_id", null: false
    t.jsonb "additional_attributes", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_channel_voice_on_account_id"
    t.index ["phone_number"], name: "index_channel_voice_on_phone_number", unique: true
  end

  create_table "channel_web_widgets", id: :serial, force: :cascade do |t|
    t.string "website_url"
    t.integer "account_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "website_token"
    t.string "widget_color", default: "#1f93ff"
    t.string "welcome_title"
    t.string "welcome_tagline"
    t.integer "feature_flags", default: 7, null: false
    t.integer "reply_time", default: 0
    t.string "hmac_token"
    t.boolean "pre_chat_form_enabled", default: false
    t.jsonb "pre_chat_form_options", default: {}
    t.boolean "hmac_mandatory", default: false
    t.boolean "continuity_via_email", default: true, null: false
    t.text "allowed_domains", default: ""
    t.index ["hmac_token"], name: "index_channel_web_widgets_on_hmac_token", unique: true
    t.index ["website_token"], name: "index_channel_web_widgets_on_website_token", unique: true
  end

  create_table "channel_whatsapp", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "phone_number", null: false
    t.string "provider", default: "default"
    t.jsonb "provider_config", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "message_templates", default: {}
    t.datetime "message_templates_last_updated", precision: nil
    t.index ["phone_number"], name: "index_channel_whatsapp_on_phone_number", unique: true
  end

  create_table "clinical_notes", force: :cascade do |t|
    t.bigint "patient_id", null: false
    t.bigint "account_id", null: false
    t.bigint "professional_id"
    t.bigint "appointment_id"
    t.bigint "form_template_id"
    t.date "note_date", null: false
    t.text "complaint_of_day"
    t.text "assessment"
    t.text "conduct"
    t.text "complications"
    t.text "guidance_given"
    t.date "return_recommended"
    t.string "status", default: "draft", null: false
    t.datetime "signed_at"
    t.bigint "signed_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "erratum_at"
    t.bigint "erratum_by_id"
    t.text "erratum_reason"
    t.integer "lock_version", default: 0, null: false
    t.bigint "proposed_evolution_id"
    t.string "source", default: "manual", null: false
    t.index ["account_id"], name: "index_clinical_notes_on_account_id"
    t.index ["appointment_id"], name: "index_clinical_notes_on_appointment_id"
    t.index ["deleted_at"], name: "index_clinical_notes_on_deleted_at"
    t.index ["erratum_at"], name: "index_clinical_notes_on_erratum_at"
    t.index ["erratum_by_id"], name: "index_clinical_notes_on_erratum_by_id"
    t.index ["note_date"], name: "index_clinical_notes_on_note_date"
    t.index ["patient_id", "note_date"], name: "index_clinical_notes_on_patient_id_and_note_date"
    t.index ["patient_id", "status", "deleted_at"], name: "index_clinical_notes_on_patient_status_deleted"
    t.index ["patient_id"], name: "index_clinical_notes_on_patient_id"
    t.index ["professional_id"], name: "index_clinical_notes_on_professional_id"
    t.index ["proposed_evolution_id"], name: "index_clinical_notes_on_proposed_evolution_id"
    t.index ["signed_by_id"], name: "index_clinical_notes_on_signed_by_id"
    t.index ["source"], name: "index_clinical_notes_on_source"
    t.index ["status"], name: "index_clinical_notes_on_status"
  end

  create_table "commission_rules", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "professional_id", null: false
    t.string "commission_type", null: false
    t.decimal "value", precision: 10, scale: 2, null: false
    t.bigint "financial_category_id"
    t.string "procedure_name"
    t.string "specialty"
    t.date "valid_from"
    t.date "valid_until"
    t.boolean "active", default: true
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "professional_id"], name: "index_commission_rules_on_account_id_and_professional_id"
    t.index ["account_id"], name: "index_commission_rules_on_account_id"
    t.index ["active"], name: "index_commission_rules_on_active"
    t.index ["professional_id"], name: "index_commission_rules_on_professional_id"
  end

  create_table "companies", force: :cascade do |t|
    t.string "name", null: false
    t.string "domain"
    t.text "description"
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "contacts_count"
    t.index ["account_id", "domain"], name: "index_companies_on_account_and_domain", unique: true, where: "(domain IS NOT NULL)"
    t.index ["account_id"], name: "index_companies_on_account_id"
    t.index ["name", "account_id"], name: "index_companies_on_name_and_account_id"
  end

  create_table "consent_records", force: :cascade do |t|
    t.bigint "patient_id", null: false
    t.bigint "account_id", null: false
    t.bigint "form_template_id"
    t.bigint "created_by_id"
    t.string "title", null: false
    t.string "status", default: "pendente"
    t.string "mode"
    t.text "signature_blob"
    t.string "integrity_hash"
    t.string "ip_address"
    t.string "device_info"
    t.datetime "signed_at"
    t.integer "expires_after_days"
    t.datetime "expires_at"
    t.string "remote_token"
    t.datetime "remote_link_sent_at"
    t.datetime "remote_link_expires_at"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "body"
    t.string "document_type"
    t.text "observations"
    t.index ["account_id"], name: "index_consent_records_on_account_id"
    t.index ["deleted_at"], name: "index_consent_records_on_deleted_at"
    t.index ["expires_at"], name: "index_consent_records_on_expires_at"
    t.index ["form_template_id"], name: "index_consent_records_on_form_template_id"
    t.index ["patient_id", "status"], name: "index_consent_records_on_patient_id_and_status"
    t.index ["patient_id"], name: "index_consent_records_on_patient_id"
    t.index ["remote_token"], name: "index_consent_records_on_remote_token", unique: true, where: "(remote_token IS NOT NULL)"
    t.index ["status"], name: "index_consent_records_on_status"
  end

  create_table "contact_inboxes", force: :cascade do |t|
    t.bigint "contact_id"
    t.bigint "inbox_id"
    t.text "source_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "hmac_verified", default: false
    t.string "pubsub_token"
    t.index ["contact_id"], name: "index_contact_inboxes_on_contact_id"
    t.index ["inbox_id", "source_id"], name: "index_contact_inboxes_on_inbox_id_and_source_id", unique: true
    t.index ["inbox_id"], name: "index_contact_inboxes_on_inbox_id"
    t.index ["pubsub_token"], name: "index_contact_inboxes_on_pubsub_token", unique: true
    t.index ["source_id"], name: "index_contact_inboxes_on_source_id"
  end

  create_table "contacts", id: :serial, force: :cascade do |t|
    t.string "name", default: ""
    t.string "email"
    t.string "phone_number"
    t.integer "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.jsonb "additional_attributes", default: {}
    t.string "identifier"
    t.jsonb "custom_attributes", default: {}
    t.datetime "last_activity_at", precision: nil
    t.integer "contact_type", default: 0
    t.string "middle_name", default: ""
    t.string "last_name", default: ""
    t.string "location", default: ""
    t.string "country_code", default: ""
    t.boolean "blocked", default: false, null: false
    t.bigint "company_id"
    t.index "((custom_attributes ->> 'cpf'::text))", name: "index_contacts_on_custom_attrs_cpf", where: "(custom_attributes ? 'cpf'::text)"
    t.index "lower((email)::text), account_id", name: "index_contacts_on_lower_email_account_id"
    t.index ["account_id", "contact_type"], name: "index_contacts_on_account_id_and_contact_type"
    t.index ["account_id", "email", "phone_number", "identifier"], name: "index_contacts_on_nonempty_fields", where: "(((email)::text <> ''::text) OR ((phone_number)::text <> ''::text) OR ((identifier)::text <> ''::text))"
    t.index ["account_id", "last_activity_at"], name: "index_contacts_on_account_id_and_last_activity_at", order: { last_activity_at: "DESC NULLS LAST" }
    t.index ["account_id"], name: "index_contacts_on_account_id"
    t.index ["account_id"], name: "index_resolved_contact_account_id", where: "(((email)::text <> ''::text) OR ((phone_number)::text <> ''::text) OR ((identifier)::text <> ''::text))"
    t.index ["blocked"], name: "index_contacts_on_blocked"
    t.index ["company_id"], name: "index_contacts_on_company_id"
    t.index ["email", "account_id"], name: "uniq_email_per_account_contact", unique: true
    t.index ["identifier", "account_id"], name: "uniq_identifier_per_account_contact", unique: true
    t.index ["name", "email", "phone_number", "identifier"], name: "index_contacts_on_name_email_phone_number_identifier", opclass: :gin_trgm_ops, using: :gin
    t.index ["phone_number", "account_id"], name: "index_contacts_on_phone_number_and_account_id"
  end

  create_table "conversation_participants", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_conversation_participants_on_account_id"
    t.index ["conversation_id"], name: "index_conversation_participants_on_conversation_id"
    t.index ["user_id", "conversation_id"], name: "index_conversation_participants_on_user_id_and_conversation_id", unique: true
    t.index ["user_id"], name: "index_conversation_participants_on_user_id"
  end

  create_table "conversations", id: :serial, force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "inbox_id", null: false
    t.integer "status", default: 0, null: false
    t.integer "assignee_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "contact_id"
    t.integer "display_id", null: false
    t.datetime "contact_last_seen_at", precision: nil
    t.datetime "agent_last_seen_at", precision: nil
    t.jsonb "additional_attributes", default: {}
    t.bigint "contact_inbox_id"
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.string "identifier"
    t.datetime "last_activity_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.bigint "team_id"
    t.bigint "campaign_id"
    t.datetime "snoozed_until", precision: nil
    t.jsonb "custom_attributes", default: {}
    t.datetime "assignee_last_seen_at", precision: nil
    t.datetime "first_reply_created_at", precision: nil
    t.integer "priority"
    t.bigint "sla_policy_id"
    t.datetime "waiting_since"
    t.text "cached_label_list"
    t.bigint "assignee_agent_bot_id"
    t.index ["account_id", "display_id"], name: "index_conversations_on_account_id_and_display_id", unique: true
    t.index ["account_id", "id"], name: "index_conversations_on_id_and_account_id"
    t.index ["account_id", "inbox_id", "status", "assignee_id"], name: "conv_acid_inbid_stat_asgnid_idx"
    t.index ["account_id"], name: "index_conversations_on_account_id"
    t.index ["assignee_id", "account_id"], name: "index_conversations_on_assignee_id_and_account_id"
    t.index ["campaign_id"], name: "index_conversations_on_campaign_id"
    t.index ["contact_id"], name: "index_conversations_on_contact_id"
    t.index ["contact_inbox_id"], name: "index_conversations_on_contact_inbox_id"
    t.index ["first_reply_created_at"], name: "index_conversations_on_first_reply_created_at"
    t.index ["identifier", "account_id"], name: "index_conversations_on_identifier_and_account_id"
    t.index ["inbox_id"], name: "index_conversations_on_inbox_id"
    t.index ["priority"], name: "index_conversations_on_priority"
    t.index ["status", "account_id"], name: "index_conversations_on_status_and_account_id"
    t.index ["status", "priority"], name: "index_conversations_on_status_and_priority"
    t.index ["team_id"], name: "index_conversations_on_team_id"
    t.index ["uuid"], name: "index_conversations_on_uuid", unique: true
    t.index ["waiting_since"], name: "index_conversations_on_waiting_since"
  end

  create_table "copilot_messages", force: :cascade do |t|
    t.bigint "copilot_thread_id", null: false
    t.bigint "account_id", null: false
    t.jsonb "message", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "message_type", default: 0
    t.index ["account_id"], name: "index_copilot_messages_on_account_id"
    t.index ["copilot_thread_id"], name: "index_copilot_messages_on_copilot_thread_id"
  end

  create_table "copilot_threads", force: :cascade do |t|
    t.string "title", null: false
    t.bigint "user_id", null: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "assistant_id"
    t.index ["account_id"], name: "index_copilot_threads_on_account_id"
    t.index ["assistant_id"], name: "index_copilot_threads_on_assistant_id"
    t.index ["user_id"], name: "index_copilot_threads_on_user_id"
  end

  create_table "critical_alerts", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.string "alert_type", null: false
    t.string "severity", default: "high", null: false
    t.string "title", null: false
    t.text "description"
    t.boolean "active", default: true
    t.bigint "created_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_critical_alerts_on_account_id"
    t.index ["deleted_at"], name: "index_critical_alerts_on_deleted_at"
    t.index ["patient_id", "active"], name: "index_critical_alerts_on_patient_id_and_active"
    t.index ["patient_id"], name: "index_critical_alerts_on_patient_id"
  end

  create_table "csat_survey_responses", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "message_id", null: false
    t.integer "rating", null: false
    t.text "feedback_message"
    t.bigint "contact_id", null: false
    t.bigint "assigned_agent_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "csat_review_notes"
    t.datetime "review_notes_updated_at"
    t.bigint "review_notes_updated_by_id"
    t.index ["account_id"], name: "index_csat_survey_responses_on_account_id"
    t.index ["assigned_agent_id"], name: "index_csat_survey_responses_on_assigned_agent_id"
    t.index ["contact_id"], name: "index_csat_survey_responses_on_contact_id"
    t.index ["conversation_id"], name: "index_csat_survey_responses_on_conversation_id"
    t.index ["message_id"], name: "index_csat_survey_responses_on_message_id", unique: true
    t.index ["review_notes_updated_by_id"], name: "index_csat_survey_responses_on_review_notes_updated_by_id"
  end

  create_table "custom_attribute_definitions", force: :cascade do |t|
    t.string "attribute_display_name"
    t.string "attribute_key"
    t.integer "attribute_display_type", default: 0
    t.integer "default_value"
    t.integer "attribute_model", default: 0
    t.bigint "account_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "attribute_description"
    t.jsonb "attribute_values", default: []
    t.string "regex_pattern"
    t.string "regex_cue"
    t.index ["account_id"], name: "index_custom_attribute_definitions_on_account_id"
    t.index ["attribute_key", "attribute_model", "account_id"], name: "attribute_key_model_index", unique: true
  end

  create_table "custom_filters", force: :cascade do |t|
    t.string "name", null: false
    t.integer "filter_type", default: 0, null: false
    t.jsonb "query", default: "{}", null: false
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_custom_filters_on_account_id"
    t.index ["user_id"], name: "index_custom_filters_on_user_id"
  end

  create_table "custom_roles", force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.bigint "account_id", null: false
    t.text "permissions", default: [], array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_custom_roles_on_account_id"
  end

  create_table "dashboard_apps", force: :cascade do |t|
    t.string "title", null: false
    t.jsonb "content", default: []
    t.bigint "account_id", null: false
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_dashboard_apps_on_account_id"
    t.index ["user_id"], name: "index_dashboard_apps_on_user_id"
  end

  create_table "data_imports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "data_type", null: false
    t.integer "status", default: 0, null: false
    t.text "processing_errors"
    t.integer "total_records"
    t.integer "processed_records"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_data_imports_on_account_id"
  end

  create_table "discount_coupons", force: :cascade do |t|
    t.string "code", null: false
    t.string "description", null: false
    t.string "kind", null: false
    t.integer "discount_percent"
    t.integer "trial_days"
    t.integer "months_duration"
    t.boolean "active", default: true, null: false
    t.integer "max_uses"
    t.integer "current_uses", default: 0, null: false
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "discount_amount", precision: 10, scale: 2
    t.index ["active"], name: "index_discount_coupons_on_active"
    t.index ["code"], name: "index_discount_coupons_on_code", unique: true
    t.index ["kind"], name: "index_discount_coupons_on_kind"
  end

  create_table "documents", force: :cascade do |t|
    t.bigint "patient_id", null: false
    t.bigint "account_id", null: false
    t.bigint "generated_by_id"
    t.bigint "form_template_id"
    t.string "document_type", null: false
    t.string "status", default: "gerado"
    t.string "title", null: false
    t.integer "version", default: 1
    t.boolean "is_generated", default: false
    t.jsonb "variables", default: {}
    t.string "file_name"
    t.string "mime_type"
    t.bigint "file_size"
    t.datetime "sent_at"
    t.datetime "signed_at"
    t.bigint "signed_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_documents_on_account_id"
    t.index ["deleted_at"], name: "index_documents_on_deleted_at"
    t.index ["document_type"], name: "index_documents_on_document_type"
    t.index ["form_template_id"], name: "index_documents_on_form_template_id"
    t.index ["patient_id", "document_type"], name: "index_documents_on_patient_id_and_document_type"
    t.index ["patient_id"], name: "index_documents_on_patient_id"
    t.index ["status"], name: "index_documents_on_status"
  end

  create_table "email_templates", force: :cascade do |t|
    t.string "name", null: false
    t.text "body", null: false
    t.integer "account_id"
    t.integer "template_type", default: 1
    t.integer "locale", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name", "account_id"], name: "index_email_templates_on_name_and_account_id", unique: true
  end

  create_table "exam_folders", force: :cascade do |t|
    t.bigint "patient_id", null: false
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "color", default: "#60a5fa"
    t.bigint "parent_id"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_exam_folders_on_account_id"
    t.index ["parent_id"], name: "index_exam_folders_on_parent_id"
    t.index ["patient_id", "position"], name: "idx_exam_folders_patient_position"
  end

  create_table "exam_medias", force: :cascade do |t|
    t.bigint "patient_id", null: false
    t.bigint "account_id", null: false
    t.bigint "uploaded_by_id"
    t.bigint "session_log_id"
    t.bigint "appointment_id"
    t.string "category", null: false
    t.string "file_name"
    t.string "mime_type"
    t.bigint "file_size"
    t.text "description"
    t.string "tags", default: [], array: true
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "exam_folder_id"
    t.boolean "locked", default: false, null: false
    t.index ["account_id"], name: "index_exam_medias_on_account_id"
    t.index ["appointment_id"], name: "index_exam_medias_on_appointment_id"
    t.index ["category"], name: "index_exam_medias_on_category"
    t.index ["deleted_at"], name: "index_exam_medias_on_deleted_at"
    t.index ["exam_folder_id"], name: "index_exam_medias_on_exam_folder_id"
    t.index ["patient_id", "category"], name: "index_exam_medias_on_patient_id_and_category"
    t.index ["patient_id"], name: "index_exam_medias_on_patient_id"
    t.index ["session_log_id"], name: "index_exam_medias_on_session_log_id"
  end

  create_table "financial_audit_logs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id"
    t.string "entity_type", limit: 80, null: false
    t.bigint "entity_id", null: false
    t.string "action", limit: 30, null: false
    t.string "ip_address", limit: 45
    t.string "user_agent"
    t.jsonb "before", default: {}
    t.jsonb "after", default: {}
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.index ["account_id", "action"], name: "index_financial_audit_logs_on_account_id_and_action"
    t.index ["account_id", "created_at"], name: "index_financial_audit_logs_on_account_id_and_created_at"
    t.index ["account_id", "entity_type", "entity_id"], name: "idx_audit_logs_on_entity"
    t.index ["account_id", "user_id", "created_at"], name: "idx_audit_logs_account_user_chronological"
    t.index ["account_id"], name: "index_financial_audit_logs_on_account_id"
  end

  create_table "financial_bank_accounts", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", limit: 120, null: false
    t.string "kind", limit: 30, default: "checking", null: false
    t.string "bank_name", limit: 120
    t.string "bank_code", limit: 10
    t.string "agency", limit: 20
    t.string "account_number", limit: 30
    t.bigint "initial_balance_cents", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.integer "card_settlement_days"
    t.string "gateway_account_id"
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.bigint "deleted_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "kind"], name: "index_financial_bank_accounts_on_account_id_and_kind"
    t.index ["account_id", "name"], name: "idx_uniq_bank_account_name_per_account", unique: true, where: "(deleted_at IS NULL)"
    t.index ["account_id"], name: "index_financial_bank_accounts_on_account_id"
    t.index ["deleted_at"], name: "index_financial_bank_accounts_on_deleted_at"
  end

  create_table "financial_budget_items", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "financial_budget_id", null: false
    t.bigint "treatment_item_id"
    t.string "description", limit: 240, null: false
    t.string "procedure_code", limit: 40
    t.integer "quantity", default: 1, null: false
    t.bigint "unit_price_cents", default: 0, null: false
    t.bigint "discount_cents", default: 0, null: false
    t.bigint "total_cents", default: 0, null: false
    t.bigint "professional_id"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_financial_budget_items_on_account_id"
    t.index ["financial_budget_id"], name: "idx_budget_items_on_budget"
    t.index ["treatment_item_id"], name: "index_financial_budget_items_on_treatment_item_id"
  end

  create_table "financial_budgets", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.bigint "professional_id"
    t.bigint "treatment_plan_id"
    t.string "external_id", limit: 60
    t.string "origin", limit: 30, default: "orcamento", null: false
    t.string "status", limit: 20, default: "rascunho", null: false
    t.bigint "subtotal_cents", default: 0, null: false
    t.bigint "discount_cents", default: 0, null: false
    t.string "discount_kind", limit: 16
    t.integer "discount_basis_points"
    t.bigint "total_cents", default: 0, null: false
    t.integer "installments_count", default: 1, null: false
    t.string "payment_method", limit: 30
    t.text "notes"
    t.date "valid_until"
    t.datetime "sent_at"
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.datetime "canceled_at"
    t.bigint "canceled_by_id"
    t.text "cancel_reason"
    t.jsonb "metadata", default: {}
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.bigint "deleted_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "external_id"], name: "idx_uniq_budget_external_id", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["account_id", "patient_id"], name: "index_financial_budgets_on_account_id_and_patient_id"
    t.index ["account_id", "status"], name: "index_financial_budgets_on_account_id_and_status"
    t.index ["account_id"], name: "index_financial_budgets_on_account_id"
    t.index ["deleted_at"], name: "index_financial_budgets_on_deleted_at"
    t.index ["professional_id"], name: "index_financial_budgets_on_professional_id"
    t.index ["treatment_plan_id"], name: "index_financial_budgets_on_treatment_plan_id"
  end

  create_table "financial_cash_movements", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "financial_cash_register_id", null: false
    t.bigint "financial_bank_account_id"
    t.string "kind", limit: 20, null: false
    t.bigint "amount_cents", null: false
    t.bigint "financial_entry_in_id"
    t.bigint "financial_entry_out_id"
    t.text "notes"
    t.datetime "occurred_at", null: false
    t.bigint "registered_by_id"
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.bigint "deleted_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "kind"], name: "index_financial_cash_movements_on_account_id_and_kind"
    t.index ["account_id"], name: "index_financial_cash_movements_on_account_id"
    t.index ["deleted_at"], name: "index_financial_cash_movements_on_deleted_at"
    t.index ["financial_cash_register_id"], name: "idx_cash_movements_on_register"
  end

  create_table "financial_cash_registers", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "financial_bank_account_id", null: false
    t.bigint "operator_id", null: false
    t.date "session_date", null: false
    t.string "status", limit: 16, default: "open", null: false
    t.bigint "opening_balance_cents", default: 0, null: false
    t.bigint "expected_balance_cents"
    t.bigint "counted_balance_cents"
    t.bigint "difference_cents", default: 0
    t.text "opening_note"
    t.text "closing_note"
    t.text "reopen_reason"
    t.datetime "opened_at", null: false
    t.datetime "closed_at"
    t.bigint "closed_by_id"
    t.datetime "reopened_at"
    t.bigint "reopened_by_id"
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.bigint "deleted_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "financial_bank_account_id", "session_date"], name: "idx_uniq_open_cash_register_per_day", unique: true, where: "(((status)::text = 'open'::text) AND (deleted_at IS NULL))"
    t.index ["account_id", "status", "session_date"], name: "idx_cash_registers_account_status_date"
    t.index ["account_id"], name: "index_financial_cash_registers_on_account_id"
    t.index ["deleted_at"], name: "index_financial_cash_registers_on_deleted_at"
    t.index ["operator_id"], name: "index_financial_cash_registers_on_operator_id"
  end

  create_table "financial_categories", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "category_type", null: false
    t.string "cost_type"
    t.bigint "parent_id"
    t.string "color", default: "#64748b"
    t.string "icon", default: "i-lucide-tag"
    t.boolean "is_default", default: false
    t.integer "position", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "category_type"], name: "index_financial_categories_on_account_id_and_category_type"
    t.index ["account_id"], name: "index_financial_categories_on_account_id"
    t.index ["category_type"], name: "index_financial_categories_on_category_type"
    t.index ["parent_id"], name: "index_financial_categories_on_parent_id"
  end

  create_table "financial_commission_entries", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "professional_id", null: false
    t.bigint "financial_installment_id"
    t.bigint "financial_commission_rule_id"
    t.bigint "financial_payment_receipt_id"
    t.string "status", limit: 20, default: "provisionada", null: false
    t.bigint "base_amount_cents", null: false
    t.bigint "mdr_deduction_cents", default: 0, null: false
    t.bigint "lab_deduction_cents", default: 0, null: false
    t.bigint "calc_base_cents", null: false
    t.integer "percent_basis_points"
    t.bigint "commission_amount_cents", null: false
    t.date "competence_date", null: false
    t.date "paid_at"
    t.bigint "paid_by_id"
    t.bigint "financial_expense_id"
    t.bigint "reverses_entry_id"
    t.text "notes"
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.bigint "deleted_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "professional_id"], name: "idx_commission_entries_on_professional"
    t.index ["account_id", "status"], name: "index_financial_commission_entries_on_account_id_and_status"
    t.index ["account_id"], name: "index_financial_commission_entries_on_account_id"
    t.index ["deleted_at"], name: "index_financial_commission_entries_on_deleted_at"
    t.index ["financial_installment_id"], name: "idx_commission_entries_on_installment"
    t.index ["financial_payment_receipt_id"], name: "idx_commission_entries_on_receipt"
  end

  create_table "financial_commission_rules", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "professional_id", null: false
    t.bigint "financial_dre_category_id"
    t.string "kind", limit: 40, null: false
    t.string "base", limit: 30, default: "recebido", null: false
    t.integer "percent_basis_points"
    t.bigint "fixed_amount_cents"
    t.string "procedure_name", limit: 200
    t.string "specialty", limit: 80
    t.boolean "deduct_mdr", default: false, null: false
    t.boolean "deduct_lab", default: false, null: false
    t.date "valid_from", null: false
    t.date "valid_until"
    t.boolean "active", default: true, null: false
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.bigint "deleted_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "professional_id"], name: "idx_commission_rules_account_professional"
    t.index ["account_id"], name: "index_financial_commission_rules_on_account_id"
    t.index ["deleted_at"], name: "index_financial_commission_rules_on_deleted_at"
    t.index ["professional_id", "valid_from", "valid_until"], name: "idx_commission_rules_validity"
  end

  create_table "financial_dre_categories", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", limit: 120, null: false
    t.string "kind", limit: 30, null: false
    t.bigint "parent_id"
    t.string "color", limit: 16, default: "#64748b"
    t.string "icon", limit: 60, default: "i-lucide-tag"
    t.boolean "is_default", default: false, null: false
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.bigint "deleted_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "kind"], name: "index_financial_dre_categories_on_account_id_and_kind"
    t.index ["account_id", "name", "kind"], name: "idx_uniq_dre_category_per_account", unique: true, where: "(deleted_at IS NULL)"
    t.index ["account_id"], name: "index_financial_dre_categories_on_account_id"
    t.index ["deleted_at"], name: "index_financial_dre_categories_on_deleted_at"
    t.index ["parent_id"], name: "index_financial_dre_categories_on_parent_id"
  end

  create_table "financial_entries", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "financial_bank_account_id", null: false
    t.bigint "financial_dre_category_id"
    t.bigint "patient_id"
    t.bigint "professional_id"
    t.string "direction", limit: 10, null: false
    t.string "kind", limit: 30, null: false
    t.bigint "amount_cents", null: false
    t.string "payment_method", limit: 30
    t.date "competence_date", null: false
    t.date "cash_date", null: false
    t.string "description", limit: 240, null: false
    t.string "source_type", limit: 60
    t.bigint "source_id"
    t.bigint "transfer_pair_id"
    t.bigint "reverses_entry_id"
    t.boolean "affects_dre", default: true, null: false
    t.boolean "affects_cashflow", default: true, null: false
    t.bigint "cash_register_id"
    t.jsonb "metadata", default: {}
    t.bigint "registered_by_id"
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.bigint "deleted_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "cash_date"], name: "idx_entries_account_cash_date"
    t.index ["account_id", "competence_date", "affects_dre"], name: "idx_entries_account_competence_dre"
    t.index ["account_id", "direction"], name: "index_financial_entries_on_account_id_and_direction"
    t.index ["account_id"], name: "index_financial_entries_on_account_id"
    t.index ["cash_register_id"], name: "index_financial_entries_on_cash_register_id", where: "(cash_register_id IS NOT NULL)"
    t.index ["deleted_at"], name: "index_financial_entries_on_deleted_at"
    t.index ["financial_bank_account_id"], name: "idx_entries_on_bank_account"
    t.index ["financial_dre_category_id"], name: "idx_entries_on_category"
    t.index ["patient_id"], name: "index_financial_entries_on_patient_id"
    t.index ["professional_id"], name: "index_financial_entries_on_professional_id"
    t.index ["reverses_entry_id"], name: "index_financial_entries_on_reverses_entry_id", where: "(reverses_entry_id IS NOT NULL)"
    t.index ["source_type", "source_id"], name: "index_financial_entries_on_source_type_and_source_id"
    t.index ["transfer_pair_id"], name: "index_financial_entries_on_transfer_pair_id", where: "(transfer_pair_id IS NOT NULL)"
  end

  create_table "financial_estimates", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.bigint "treatment_plan_id"
    t.bigint "generated_by_id"
    t.string "status", default: "rascunho", null: false
    t.decimal "subtotal", precision: 10, scale: 2, default: "0.0"
    t.decimal "discount_amount", precision: 10, scale: 2, default: "0.0"
    t.decimal "total", precision: 10, scale: 2, default: "0.0"
    t.string "discount_type"
    t.decimal "discount_value", precision: 10, scale: 2, default: "0.0"
    t.integer "installments_count", default: 1
    t.string "payment_method"
    t.text "notes"
    t.date "valid_until"
    t.datetime "approved_at"
    t.datetime "sent_at"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "recurrence_type", default: 0, null: false
    t.index ["account_id", "recurrence_type"], name: "index_financial_estimates_on_account_id_and_recurrence_type"
    t.index ["account_id"], name: "index_financial_estimates_on_account_id"
    t.index ["deleted_at"], name: "index_financial_estimates_on_deleted_at"
    t.index ["patient_id"], name: "index_financial_estimates_on_patient_id"
    t.index ["status"], name: "index_financial_estimates_on_status"
    t.index ["treatment_plan_id"], name: "index_financial_estimates_on_treatment_plan_id"
  end

  create_table "financial_expenses", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "financial_dre_category_id", null: false
    t.bigint "financial_bank_account_id"
    t.bigint "financial_recurring_expense_id"
    t.bigint "financial_commission_entry_id"
    t.bigint "supplier_id"
    t.string "supplier_name", limit: 200
    t.string "description", limit: 240, null: false
    t.string "status", limit: 20, default: "pendente", null: false
    t.bigint "amount_cents", null: false
    t.bigint "paid_amount_cents", default: 0, null: false
    t.string "payment_method", limit: 30
    t.date "competence_date", null: false
    t.date "due_date", null: false
    t.date "paid_at"
    t.bigint "installments_count", default: 1
    t.bigint "installment_number", default: 1
    t.bigint "parent_expense_id"
    t.string "external_id", limit: 60
    t.text "notes"
    t.jsonb "metadata", default: {}
    t.string "gateway", limit: 30, default: "manual"
    t.string "gateway_id", limit: 100
    t.string "gateway_status", limit: 40
    t.jsonb "gateway_metadata", default: {}
    t.datetime "gateway_synced_at"
    t.bigint "registered_by_id"
    t.bigint "paid_by_id"
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.bigint "deleted_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "competence_date"], name: "idx_expenses_account_competence"
    t.index ["account_id", "external_id"], name: "idx_uniq_expense_external_id", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["account_id", "status", "due_date"], name: "idx_expenses_account_status_due"
    t.index ["account_id", "status"], name: "index_financial_expenses_on_account_id_and_status"
    t.index ["account_id"], name: "index_financial_expenses_on_account_id"
    t.index ["deleted_at"], name: "index_financial_expenses_on_deleted_at"
    t.index ["financial_commission_entry_id"], name: "idx_expenses_on_commission_entry"
    t.index ["financial_dre_category_id"], name: "idx_expenses_on_category"
    t.index ["financial_recurring_expense_id"], name: "idx_expenses_on_recurring"
    t.index ["parent_expense_id"], name: "index_financial_expenses_on_parent_expense_id"
  end

  create_table "financial_gateway_settings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "gateway", limit: 30, default: "manual", null: false
    t.string "environment", limit: 20, default: "sandbox"
    t.text "api_key_ciphertext"
    t.string "webhook_secret_ciphertext"
    t.string "default_pix_key"
    t.string "default_customer_external_ref_strategy", limit: 30, default: "patient_id"
    t.boolean "auto_sync_enabled", default: false, null: false
    t.boolean "webhook_verified", default: false, null: false
    t.datetime "webhook_last_received_at"
    t.jsonb "metadata", default: {}
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "idx_uniq_gateway_settings_per_account", unique: true
  end

  create_table "financial_gateway_webhook_events", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "gateway", limit: 30, null: false
    t.string "event_id", limit: 100, null: false
    t.string "event_type", limit: 80, null: false
    t.string "status", limit: 20, default: "received", null: false
    t.jsonb "payload", default: {}, null: false
    t.text "processing_error"
    t.datetime "received_at", null: false
    t.datetime "processed_at"
    t.integer "processing_attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_financial_gateway_webhook_events_on_account_id_and_status"
    t.index ["account_id"], name: "index_financial_gateway_webhook_events_on_account_id"
    t.index ["gateway", "event_id"], name: "idx_uniq_gateway_event_id", unique: true
    t.index ["received_at"], name: "index_financial_gateway_webhook_events_on_received_at"
  end

  create_table "financial_idempotency_keys", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "key", limit: 80, null: false
    t.string "request_path", limit: 200, null: false
    t.string "request_method", limit: 10, null: false
    t.string "request_fingerprint", limit: 64, null: false
    t.integer "response_status", null: false
    t.jsonb "response_body", default: {}
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.index ["account_id", "key"], name: "idx_uniq_idempotency_key_per_account", unique: true
    t.index ["account_id"], name: "index_financial_idempotency_keys_on_account_id"
    t.index ["created_at"], name: "index_financial_idempotency_keys_on_created_at"
  end

  create_table "financial_installments", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "financial_budget_id", null: false
    t.bigint "patient_id", null: false
    t.bigint "professional_id"
    t.bigint "financial_dre_category_id"
    t.integer "number", null: false
    t.integer "total_in_series", null: false
    t.bigint "amount_cents", null: false
    t.bigint "received_amount_cents", default: 0, null: false
    t.string "status", limit: 20, default: "pendente", null: false
    t.string "payment_method", limit: 30
    t.date "due_date", null: false
    t.date "competence_date", null: false
    t.date "received_at"
    t.bigint "renegotiated_to_id"
    t.bigint "replaces_installment_id"
    t.text "notes"
    t.string "gateway", limit: 30, default: "manual"
    t.string "gateway_id", limit: 100
    t.string "gateway_status", limit: 40
    t.string "payment_link"
    t.string "barcode_line"
    t.text "pix_qr_code"
    t.string "pix_qr_code_image_url"
    t.jsonb "gateway_metadata", default: {}
    t.datetime "gateway_synced_at"
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.bigint "deleted_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "external_id", limit: 60
    t.index ["account_id", "due_date"], name: "index_financial_installments_on_account_id_and_due_date"
    t.index ["account_id", "external_id"], name: "idx_uniq_installment_external_id", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["account_id", "status", "due_date"], name: "idx_installments_account_status_due"
    t.index ["account_id", "status"], name: "index_financial_installments_on_account_id_and_status"
    t.index ["account_id"], name: "index_financial_installments_on_account_id"
    t.index ["deleted_at"], name: "index_financial_installments_on_deleted_at"
    t.index ["financial_budget_id", "number"], name: "idx_uniq_installment_number_per_budget", unique: true, where: "(deleted_at IS NULL)"
    t.index ["financial_budget_id"], name: "index_financial_installments_on_financial_budget_id"
    t.index ["gateway_id"], name: "index_financial_installments_on_gateway_id", where: "(gateway_id IS NOT NULL)"
    t.index ["patient_id"], name: "index_financial_installments_on_patient_id"
    t.index ["professional_id"], name: "index_financial_installments_on_professional_id"
  end

  create_table "financial_lgpd_requests", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.string "status", limit: 20, default: "pending", null: false
    t.text "reason"
    t.datetime "requested_at", null: false
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.datetime "executed_at"
    t.bigint "executed_by_id"
    t.datetime "rejected_at"
    t.bigint "rejected_by_id"
    t.text "rejection_reason"
    t.jsonb "anonymized_fields", default: {}
    t.text "notes"
    t.datetime "deleted_at"
    t.bigint "deleted_by_id"
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_financial_lgpd_requests_on_account_id"
    t.index ["deleted_at"], name: "index_financial_lgpd_requests_on_deleted_at"
    t.index ["patient_id"], name: "index_financial_lgpd_requests_on_patient_id"
    t.index ["status"], name: "index_financial_lgpd_requests_on_status"
  end

  create_table "financial_patient_credits", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.bigint "amount_cents", null: false
    t.string "origin", limit: 40, null: false
    t.bigint "origin_id"
    t.string "origin_type"
    t.text "description"
    t.bigint "registered_by_id"
    t.datetime "occurred_at", null: false
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.bigint "deleted_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "patient_id", "occurred_at"], name: "idx_patient_credits_chronological"
    t.index ["account_id", "patient_id"], name: "index_financial_patient_credits_on_account_id_and_patient_id"
    t.index ["account_id"], name: "index_financial_patient_credits_on_account_id"
    t.index ["deleted_at"], name: "index_financial_patient_credits_on_deleted_at"
    t.index ["origin_type", "origin_id"], name: "index_financial_patient_credits_on_origin_type_and_origin_id"
  end

  create_table "financial_payment_receipt_items", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "financial_payment_receipt_id", null: false
    t.bigint "financial_installment_id", null: false
    t.bigint "amount_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_financial_payment_receipt_items_on_account_id"
    t.index ["financial_installment_id"], name: "idx_receipt_items_on_installment"
    t.index ["financial_payment_receipt_id", "financial_installment_id"], name: "idx_uniq_receipt_installment_pair", unique: true
    t.index ["financial_payment_receipt_id"], name: "idx_receipt_items_on_receipt"
  end

  create_table "financial_payment_receipts", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.bigint "financial_bank_account_id", null: false
    t.bigint "financial_entry_id"
    t.bigint "received_by_id"
    t.string "receipt_number", limit: 30, null: false
    t.string "payment_method", limit: 30, null: false
    t.bigint "gross_amount_cents", null: false
    t.bigint "interest_amount_cents", default: 0, null: false
    t.bigint "fine_amount_cents", default: 0, null: false
    t.bigint "discount_amount_cents", default: 0, null: false
    t.bigint "credit_applied_cents", default: 0, null: false
    t.bigint "net_amount_cents", null: false
    t.date "received_at", null: false
    t.text "notes"
    t.string "pdf_status", limit: 20, default: "pending"
    t.string "pdf_url"
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.bigint "deleted_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "external_id", limit: 60
    t.jsonb "metadata", default: {}, null: false
    t.index ["account_id", "external_id"], name: "idx_uniq_receipt_external_id", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["account_id", "patient_id"], name: "index_financial_payment_receipts_on_account_id_and_patient_id"
    t.index ["account_id", "receipt_number"], name: "idx_uniq_receipt_number_per_account", unique: true, where: "(deleted_at IS NULL)"
    t.index ["account_id"], name: "index_financial_payment_receipts_on_account_id"
    t.index ["deleted_at"], name: "index_financial_payment_receipts_on_deleted_at"
    t.index ["financial_entry_id"], name: "index_financial_payment_receipts_on_financial_entry_id"
  end

  create_table "financial_recurring_expenses", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", limit: 200, null: false
    t.bigint "financial_dre_category_id", null: false
    t.bigint "financial_bank_account_id"
    t.bigint "amount_cents", null: false
    t.boolean "variable_amount", default: false, null: false
    t.string "frequency", limit: 20, default: "monthly", null: false
    t.integer "due_day", null: false
    t.string "competence_rule", limit: 20, default: "same_month", null: false
    t.date "start_date", null: false
    t.date "end_date"
    t.boolean "auto_pay", default: false, null: false
    t.boolean "active", default: true, null: false
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.bigint "deleted_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "active"], name: "index_financial_recurring_expenses_on_account_id_and_active"
    t.index ["account_id"], name: "index_financial_recurring_expenses_on_account_id"
    t.index ["deleted_at"], name: "index_financial_recurring_expenses_on_deleted_at"
  end

  create_table "financial_revenue_goals", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "period", limit: 20, null: false
    t.integer "year", null: false
    t.integer "month"
    t.integer "quarter"
    t.bigint "amount_cents", null: false
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "period", "year", "month", "quarter"], name: "idx_uniq_revenue_goal_per_period", unique: true
    t.index ["account_id"], name: "index_financial_revenue_goals_on_account_id"
  end

  create_table "financial_setup_states", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "status", limit: 20, default: "pending", null: false
    t.boolean "step_categories_done", default: false, null: false
    t.boolean "step_bank_accounts_done", default: false, null: false
    t.boolean "step_commission_rules_done", default: false, null: false
    t.boolean "step_recurring_expenses_done", default: false, null: false
    t.boolean "step_revenue_goal_done", default: false, null: false
    t.datetime "completed_at"
    t.bigint "completed_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "idx_uniq_setup_state_per_account", unique: true
  end

  create_table "folders", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "category_id", null: false
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "form_templates", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "template_type", null: false
    t.string "specialty"
    t.jsonb "fields", default: []
    t.boolean "is_global", default: false
    t.boolean "active", default: true
    t.bigint "created_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "template_type", "active"], name: "index_form_templates_on_account_id_and_template_type_and_active"
    t.index ["account_id"], name: "index_form_templates_on_account_id"
    t.index ["active"], name: "index_form_templates_on_active"
    t.index ["deleted_at"], name: "index_form_templates_on_deleted_at"
    t.index ["is_global"], name: "index_form_templates_on_is_global"
    t.index ["specialty"], name: "index_form_templates_on_specialty"
    t.index ["template_type"], name: "index_form_templates_on_template_type"
  end

  create_table "help_articles", force: :cascade do |t|
    t.string "title", null: false
    t.text "body"
    t.string "category", default: "outro", null: false
    t.string "status", default: "published", null: false
    t.string "video_url"
    t.integer "position", default: 0, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "next_steps"
    t.index ["category"], name: "index_help_articles_on_category"
    t.index ["deleted_at"], name: "index_help_articles_on_deleted_at"
    t.index ["status", "category"], name: "index_help_articles_on_status_and_category"
    t.index ["status"], name: "index_help_articles_on_status"
  end

  create_table "help_categories", force: :cascade do |t|
    t.string "name", null: false
    t.string "description"
    t.string "slug", null: false
    t.text "icon_svg"
    t.string "icon_class"
    t.integer "position", default: 0, null: false
    t.boolean "hidden", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_help_categories_on_slug", unique: true
  end

  create_table "help_faqs", force: :cascade do |t|
    t.string "question", default: "", null: false
    t.text "answer", default: "", null: false
    t.string "category", default: "outro", null: false
    t.integer "position", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active", "position"], name: "index_help_faqs_on_active_and_position"
    t.index ["category"], name: "index_help_faqs_on_category"
  end

  create_table "inbox_assignment_policies", force: :cascade do |t|
    t.bigint "inbox_id", null: false
    t.bigint "assignment_policy_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assignment_policy_id"], name: "index_inbox_assignment_policies_on_assignment_policy_id"
    t.index ["inbox_id"], name: "index_inbox_assignment_policies_on_inbox_id", unique: true
  end

  create_table "inbox_capacity_limits", force: :cascade do |t|
    t.bigint "agent_capacity_policy_id", null: false
    t.bigint "inbox_id", null: false
    t.integer "conversation_limit", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_capacity_policy_id", "inbox_id"], name: "idx_on_agent_capacity_policy_id_inbox_id_71c7ec4caf", unique: true
    t.index ["agent_capacity_policy_id"], name: "index_inbox_capacity_limits_on_agent_capacity_policy_id"
    t.index ["inbox_id"], name: "index_inbox_capacity_limits_on_inbox_id"
  end

  create_table "inbox_members", id: :serial, force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "inbox_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["inbox_id", "user_id"], name: "index_inbox_members_on_inbox_id_and_user_id", unique: true
    t.index ["inbox_id"], name: "index_inbox_members_on_inbox_id"
  end

  create_table "inboxes", id: :serial, force: :cascade do |t|
    t.integer "channel_id", null: false
    t.integer "account_id", null: false
    t.string "name", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "channel_type"
    t.boolean "enable_auto_assignment", default: true
    t.boolean "greeting_enabled", default: false
    t.string "greeting_message"
    t.string "email_address"
    t.boolean "working_hours_enabled", default: false
    t.string "out_of_office_message"
    t.string "timezone", default: "UTC"
    t.boolean "enable_email_collect", default: true
    t.boolean "csat_survey_enabled", default: false
    t.boolean "allow_messages_after_resolved", default: true
    t.jsonb "auto_assignment_config", default: {}
    t.boolean "lock_to_single_conversation", default: false, null: false
    t.bigint "portal_id"
    t.integer "sender_name_type", default: 0, null: false
    t.string "business_name"
    t.jsonb "csat_config", default: {}, null: false
    t.index ["account_id"], name: "index_inboxes_on_account_id"
    t.index ["channel_id", "channel_type"], name: "index_inboxes_on_channel_id_and_channel_type"
    t.index ["portal_id"], name: "index_inboxes_on_portal_id"
  end

  create_table "installation_configs", force: :cascade do |t|
    t.string "name", null: false
    t.jsonb "serialized_value", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "locked", default: true, null: false
    t.index ["name", "created_at"], name: "index_installation_configs_on_name_and_created_at", unique: true
    t.index ["name"], name: "index_installation_configs_on_name", unique: true
  end

  create_table "installments", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.bigint "transaction_id", null: false
    t.integer "number", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "status", default: "pendente", null: false
    t.date "due_date", null: false
    t.date "paid_at"
    t.string "payment_method"
    t.bigint "cash_entry_id"
    t.bigint "registered_by_id"
    t.text "notes"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_installments_on_account_id"
    t.index ["cash_entry_id"], name: "index_installments_on_cash_entry_id"
    t.index ["due_date"], name: "index_installments_on_due_date"
    t.index ["patient_id"], name: "index_installments_on_patient_id"
    t.index ["status"], name: "index_installments_on_status"
    t.index ["transaction_id"], name: "index_installments_on_transaction_id"
  end

  create_table "integrations_hooks", force: :cascade do |t|
    t.integer "status", default: 1
    t.integer "inbox_id"
    t.integer "account_id"
    t.string "app_id"
    t.integer "hook_type", default: 0
    t.string "reference_id"
    t.string "access_token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "settings", default: {}
  end

  create_table "internal_chat_attachments", force: :cascade do |t|
    t.bigint "message_id", null: false
    t.string "file_type", default: "file", null: false
    t.string "file_name"
    t.string "content_type"
    t.bigint "file_size"
    t.jsonb "meta", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_internal_chat_attachments_on_message_id"
  end

  create_table "internal_chat_memberships", force: :cascade do |t|
    t.bigint "room_id", null: false
    t.bigint "user_id"
    t.bigint "ai_agent_id"
    t.string "role", default: "member", null: false
    t.bigint "last_read_message_id"
    t.datetime "muted_until"
    t.datetime "joined_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "left_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_agent_id"], name: "index_internal_chat_memberships_on_ai_agent_id"
    t.index ["room_id", "ai_agent_id"], name: "idx_unique_membership_ai_agent", unique: true, where: "(ai_agent_id IS NOT NULL)"
    t.index ["room_id", "user_id"], name: "idx_unique_membership_user", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["room_id"], name: "index_internal_chat_memberships_on_room_id"
    t.index ["user_id"], name: "index_internal_chat_memberships_on_user_id"
    t.check_constraint "user_id IS NOT NULL AND ai_agent_id IS NULL OR user_id IS NULL AND ai_agent_id IS NOT NULL", name: "internal_chat_memberships_member_check"
  end

  create_table "internal_chat_mentions", force: :cascade do |t|
    t.bigint "message_id", null: false
    t.bigint "user_id"
    t.bigint "account_id", null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "ai_agent_id"
    t.index ["account_id", "ai_agent_id", "read_at"], name: "idx_on_account_id_ai_agent_id_read_at_d6ecd67437"
    t.index ["account_id", "user_id", "read_at"], name: "idx_on_account_id_user_id_read_at_7db12fe148"
    t.index ["message_id", "user_id"], name: "index_internal_chat_mentions_on_message_id_and_user_id", unique: true
    t.index ["message_id"], name: "index_internal_chat_mentions_on_message_id"
    t.check_constraint "user_id IS NOT NULL AND ai_agent_id IS NULL OR user_id IS NULL AND ai_agent_id IS NOT NULL", name: "internal_chat_mentions_target_check"
  end

  create_table "internal_chat_message_favorites", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "message_id", null: false
    t.bigint "account_id", null: false
    t.bigint "room_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_internal_chat_message_favorites_on_account_id"
    t.index ["message_id"], name: "index_internal_chat_message_favorites_on_message_id"
    t.index ["user_id", "account_id", "created_at"], name: "idx_msg_fav_user_account_created"
    t.index ["user_id", "message_id"], name: "idx_msg_fav_uniq", unique: true
    t.index ["user_id", "room_id", "created_at"], name: "idx_msg_fav_user_room_created"
    t.index ["user_id"], name: "index_internal_chat_message_favorites_on_user_id"
  end

  create_table "internal_chat_message_reactions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "message_id", null: false
    t.bigint "account_id", null: false
    t.bigint "room_id", null: false
    t.string "emoji", limit: 16, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_internal_chat_message_reactions_on_account_id"
    t.index ["message_id"], name: "index_internal_chat_message_reactions_on_message_id"
    t.index ["user_id", "message_id"], name: "idx_msg_reaction_uniq", unique: true
    t.index ["user_id"], name: "index_internal_chat_message_reactions_on_user_id"
  end

  create_table "internal_chat_messages", force: :cascade do |t|
    t.bigint "room_id", null: false
    t.bigint "sender_user_id"
    t.bigint "sender_ai_agent_id"
    t.text "content"
    t.string "content_type", default: "text", null: false
    t.jsonb "content_attributes", default: {}, null: false
    t.datetime "edited_at"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "sticker_id"
    t.index ["content_attributes"], name: "index_internal_chat_messages_on_content_attributes", using: :gin
    t.index ["room_id", "created_at"], name: "index_internal_chat_messages_on_room_id_and_created_at", order: { created_at: :desc }
    t.index ["room_id"], name: "index_internal_chat_messages_on_room_id"
    t.index ["sender_ai_agent_id"], name: "index_internal_chat_messages_on_sender_ai_agent_id"
    t.index ["sender_user_id"], name: "index_internal_chat_messages_on_sender_user_id"
    t.index ["sticker_id"], name: "index_internal_chat_messages_on_sticker_id"
  end

  create_table "internal_chat_read_receipts", force: :cascade do |t|
    t.bigint "message_id", null: false
    t.bigint "user_id", null: false
    t.datetime "read_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "user_id"], name: "index_internal_chat_read_receipts_on_message_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_internal_chat_read_receipts_on_user_id"
  end

  create_table "internal_chat_rooms", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "kind", default: "direct", null: false
    t.string "name"
    t.text "description"
    t.string "avatar_url"
    t.bigint "created_by_user_id"
    t.datetime "last_message_at"
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "system_role"
    t.index ["account_id", "kind"], name: "index_internal_chat_rooms_on_account_id_and_kind"
    t.index ["account_id", "last_message_at"], name: "index_internal_chat_rooms_on_account_id_and_last_message_at", order: { last_message_at: :desc }
    t.index ["account_id", "system_role"], name: "idx_internal_chat_rooms_system_role", unique: true, where: "(system_role IS NOT NULL)"
    t.index ["account_id"], name: "index_internal_chat_rooms_on_account_id"
    t.index ["created_by_user_id"], name: "index_internal_chat_rooms_on_created_by_user_id"
  end

  create_table "internal_chat_sticker_favorites", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "sticker_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sticker_id"], name: "index_internal_chat_sticker_favorites_on_sticker_id"
    t.index ["user_id", "sticker_id"], name: "idx_sticker_fav_uniq", unique: true
    t.index ["user_id"], name: "index_internal_chat_sticker_favorites_on_user_id"
  end

  create_table "internal_chat_stickers", force: :cascade do |t|
    t.bigint "account_id"
    t.bigint "created_by_user_id"
    t.string "name", limit: 120
    t.string "kind", default: "account", null: false
    t.integer "width"
    t.integer "height"
    t.integer "file_size"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "category", limit: 40
    t.index ["account_id", "kind"], name: "index_internal_chat_stickers_on_account_id_and_kind"
    t.index ["account_id"], name: "index_internal_chat_stickers_on_account_id"
    t.index ["created_by_user_id"], name: "index_internal_chat_stickers_on_created_by_user_id"
    t.index ["kind", "category"], name: "index_internal_chat_stickers_on_kind_and_category"
  end

  create_table "klivy_roles", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", limit: 80, null: false
    t.string "description", limit: 240
    t.string "preset_key", limit: 40
    t.jsonb "permissions", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_klivy_roles_on_account_and_name", unique: true
    t.index ["account_id"], name: "index_klivy_roles_on_account_id"
  end

  create_table "labels", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.string "color", default: "#1f93ff", null: false
    t.boolean "show_on_sidebar"
    t.bigint "account_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_labels_on_account_id"
    t.index ["title", "account_id"], name: "index_labels_on_title_and_account_id", unique: true
  end

  create_table "leaves", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.integer "leave_type", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.text "reason"
    t.bigint "approved_by_id"
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_leaves_on_account_id_and_status"
    t.index ["account_id"], name: "index_leaves_on_account_id"
    t.index ["approved_by_id"], name: "index_leaves_on_approved_by_id"
    t.index ["user_id"], name: "index_leaves_on_user_id"
  end

  create_table "macros", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.integer "visibility", default: 0
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.jsonb "actions", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_macros_on_account_id"
  end

  create_table "mentions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "account_id", null: false
    t.datetime "mentioned_at", precision: nil, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_mentions_on_account_id"
    t.index ["conversation_id"], name: "index_mentions_on_conversation_id"
    t.index ["user_id", "conversation_id"], name: "index_mentions_on_user_id_and_conversation_id", unique: true
    t.index ["user_id"], name: "index_mentions_on_user_id"
  end

  create_table "messages", id: :serial, force: :cascade do |t|
    t.text "content"
    t.integer "account_id", null: false
    t.integer "inbox_id", null: false
    t.integer "conversation_id", null: false
    t.integer "message_type", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "private", default: false, null: false
    t.integer "status", default: 0
    t.text "source_id"
    t.integer "content_type", default: 0, null: false
    t.json "content_attributes", default: {}
    t.string "sender_type"
    t.bigint "sender_id"
    t.jsonb "external_source_ids", default: {}
    t.jsonb "additional_attributes", default: {}
    t.text "processed_message_content"
    t.jsonb "sentiment", default: {}
    t.index "((additional_attributes -> 'campaign_id'::text))", name: "index_messages_on_additional_attributes_campaign_id", using: :gin
    t.index ["account_id", "content_type", "created_at"], name: "idx_messages_account_content_created"
    t.index ["account_id", "created_at", "message_type"], name: "index_messages_on_account_created_type"
    t.index ["account_id", "inbox_id"], name: "index_messages_on_account_id_and_inbox_id"
    t.index ["account_id"], name: "index_messages_on_account_id"
    t.index ["content"], name: "index_messages_on_content", opclass: :gin_trgm_ops, using: :gin
    t.index ["conversation_id", "account_id", "message_type", "created_at"], name: "index_messages_on_conversation_account_type_created"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["created_at"], name: "index_messages_on_created_at"
    t.index ["inbox_id"], name: "index_messages_on_inbox_id"
    t.index ["sender_type", "sender_id"], name: "index_messages_on_sender_type_and_sender_id"
    t.index ["source_id"], name: "index_messages_on_source_id"
  end

  create_table "migration_runs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "kind", null: false
    t.string "status", default: "pending", null: false
    t.string "source", default: "clinicorp", null: false
    t.string "csv_filename"
    t.integer "total_rows", default: 0
    t.integer "processed_rows", default: 0
    t.integer "created_count", default: 0
    t.integer "updated_count", default: 0
    t.integer "skipped_count", default: 0
    t.integer "error_count", default: 0
    t.jsonb "errors_log", default: []
    t.text "error_message"
    t.bigint "triggered_by_super_admin_id"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "kind"], name: "index_migration_runs_on_account_id_and_kind"
    t.index ["account_id"], name: "index_migration_runs_on_account_id"
    t.index ["status"], name: "index_migration_runs_on_status"
  end

  create_table "notes", force: :cascade do |t|
    t.text "content", null: false
    t.bigint "account_id", null: false
    t.bigint "contact_id", null: false
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_notes_on_account_id"
    t.index ["contact_id"], name: "index_notes_on_contact_id"
    t.index ["user_id"], name: "index_notes_on_user_id"
  end

  create_table "notification_settings", force: :cascade do |t|
    t.integer "account_id"
    t.integer "user_id"
    t.integer "email_flags", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "push_flags", default: 0, null: false
    t.index ["account_id", "user_id"], name: "by_account_user", unique: true
  end

  create_table "notification_subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "subscription_type", null: false
    t.jsonb "subscription_attributes", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "identifier"
    t.index ["identifier"], name: "index_notification_subscriptions_on_identifier", unique: true
    t.index ["user_id"], name: "index_notification_subscriptions_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.integer "notification_type", null: false
    t.string "primary_actor_type", null: false
    t.bigint "primary_actor_id", null: false
    t.string "secondary_actor_type"
    t.bigint "secondary_actor_id"
    t.datetime "read_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "snoozed_until"
    t.datetime "last_activity_at", default: -> { "CURRENT_TIMESTAMP" }
    t.jsonb "meta", default: {}
    t.index ["account_id"], name: "index_notifications_on_account_id"
    t.index ["last_activity_at"], name: "index_notifications_on_last_activity_at"
    t.index ["primary_actor_type", "primary_actor_id"], name: "uniq_primary_actor_per_account_notifications"
    t.index ["secondary_actor_type", "secondary_actor_id"], name: "uniq_secondary_actor_per_account_notifications"
    t.index ["user_id", "account_id", "last_activity_at"], name: "idx_notifications_unread_by_activity", order: { last_activity_at: :desc }, where: "((read_at IS NULL) AND (snoozed_until IS NULL))"
    t.index ["user_id", "account_id", "snoozed_until", "read_at"], name: "idx_notifications_performance"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "patient_appointments", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.bigint "professional_id"
    t.bigint "agenda_event_id"
    t.string "appointment_type", default: "avaliacao", null: false
    t.string "status", default: "scheduled", null: false
    t.datetime "scheduled_at", null: false
    t.datetime "ends_at"
    t.integer "duration_minutes", default: 60
    t.string "cancellation_reason"
    t.string "reschedule_reason"
    t.text "notes"
    t.boolean "recall_sent", default: false, null: false
    t.datetime "recall_sent_at"
    t.integer "return_in_days"
    t.bigint "session_log_id"
    t.bigint "treatment_plan_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_patient_appointments_on_account_id"
    t.index ["agenda_event_id"], name: "index_patient_appointments_on_agenda_event_id"
    t.index ["appointment_type"], name: "index_patient_appointments_on_appointment_type"
    t.index ["deleted_at"], name: "index_patient_appointments_on_deleted_at"
    t.index ["patient_id", "scheduled_at"], name: "index_patient_appointments_on_patient_id_and_scheduled_at"
    t.index ["patient_id", "status"], name: "index_patient_appointments_on_patient_id_and_status"
    t.index ["patient_id"], name: "index_patient_appointments_on_patient_id"
    t.index ["professional_id"], name: "index_patient_appointments_on_professional_id"
    t.index ["scheduled_at"], name: "index_patient_appointments_on_scheduled_at"
    t.index ["status"], name: "index_patient_appointments_on_status"
  end

  create_table "patient_audit_logs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.bigint "actor_id"
    t.string "actor_name"
    t.string "actor_role"
    t.string "action", null: false
    t.string "resource_type"
    t.bigint "resource_id"
    t.jsonb "changed_fields"
    t.jsonb "old_value"
    t.jsonb "new_value"
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.index ["account_id", "occurred_at"], name: "index_patient_audit_logs_on_account_id_and_occurred_at"
    t.index ["account_id"], name: "index_patient_audit_logs_on_account_id"
    t.index ["action"], name: "index_patient_audit_logs_on_action"
    t.index ["actor_id"], name: "index_patient_audit_logs_on_actor_id"
    t.index ["occurred_at"], name: "index_patient_audit_logs_on_occurred_at"
    t.index ["patient_id", "occurred_at"], name: "index_patient_audit_logs_on_patient_id_and_occurred_at"
    t.index ["patient_id"], name: "index_patient_audit_logs_on_patient_id"
    t.index ["resource_type", "resource_id"], name: "index_patient_audit_logs_on_resource_type_and_resource_id"
  end

  create_table "patient_portal_access_logs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.string "action", null: false
    t.string "resource_type"
    t.bigint "resource_id"
    t.string "ip"
    t.string "user_agent"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["account_id", "action", "created_at"], name: "idx_pp_access_logs_account_action_at"
    t.index ["account_id"], name: "index_patient_portal_access_logs_on_account_id"
    t.index ["patient_id", "created_at"], name: "index_patient_portal_access_logs_on_patient_id_and_created_at"
    t.index ["patient_id"], name: "index_patient_portal_access_logs_on_patient_id"
  end

  create_table "patient_portal_consents", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.string "term_type", null: false
    t.string "term_version", null: false
    t.datetime "accepted_at", null: false
    t.datetime "revoked_at"
    t.text "revocation_reason"
    t.string "ip"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_patient_portal_consents_on_account_id"
    t.index ["patient_id", "term_type", "term_version"], name: "idx_pp_consents_patient_term_version", unique: true
    t.index ["patient_id"], name: "index_patient_portal_consents_on_patient_id"
  end

  create_table "patient_portal_notifications", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.string "kind", null: false
    t.string "title", null: false
    t.text "body"
    t.jsonb "payload", default: {}
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "patient_id", "created_at"], name: "idx_pp_notifications_recent"
    t.index ["account_id"], name: "index_patient_portal_notifications_on_account_id"
    t.index ["patient_id", "read_at"], name: "index_patient_portal_notifications_on_patient_id_and_read_at"
    t.index ["patient_id"], name: "index_patient_portal_notifications_on_patient_id"
  end

  create_table "patient_portal_otps", force: :cascade do |t|
    t.string "identifier", null: false
    t.string "code_digest", null: false
    t.string "channel", null: false
    t.datetime "expires_at", null: false
    t.datetime "used_at"
    t.integer "attempts", default: 0, null: false
    t.string "ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_patient_portal_otps_on_expires_at"
    t.index ["identifier"], name: "index_patient_portal_otps_on_identifier"
  end

  create_table "patient_portal_push_subscriptions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.string "endpoint", limit: 1024, null: false
    t.string "p256dh_key", null: false
    t.string "auth_key", null: false
    t.string "user_agent", limit: 500
    t.datetime "last_used_at"
    t.integer "failure_count", default: 0, null: false
    t.datetime "disabled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_patient_portal_push_subscriptions_on_account_id"
    t.index ["endpoint"], name: "idx_pp_push_subs_endpoint_unique", unique: true
    t.index ["patient_id"], name: "index_patient_portal_push_subscriptions_on_patient_id"
  end

  create_table "patient_portal_sessions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.string "jwt_jti", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_seen_at"
    t.datetime "revoked_at"
    t.string "ip"
    t.string "user_agent"
    t.string "device_fingerprint"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "active_patient_id", null: false
    t.index ["account_id"], name: "index_patient_portal_sessions_on_account_id"
    t.index ["active_patient_id"], name: "index_patient_portal_sessions_on_active_patient_id"
    t.index ["jwt_jti"], name: "index_patient_portal_sessions_on_jwt_jti", unique: true
    t.index ["patient_id", "expires_at"], name: "index_patient_portal_sessions_on_patient_id_and_expires_at"
    t.index ["patient_id"], name: "index_patient_portal_sessions_on_patient_id"
  end

  create_table "patient_portal_settings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "active_preset", default: "autonomy_guided", null: false
    t.jsonb "scheduling", default: {}, null: false
    t.jsonb "rescheduling", default: {}, null: false
    t.jsonb "financial", default: {}, null: false
    t.jsonb "documents", default: {}, null: false
    t.jsonb "clinical", default: {}, null: false
    t.jsonb "messaging", default: {}, null: false
    t.jsonb "engagement", default: {}, null: false
    t.jsonb "invite", default: {}, null: false
    t.jsonb "business_hours", default: {}, null: false
    t.jsonb "notification_events_enabled", default: {}, null: false
    t.bigint "default_inbox_id"
    t.bigint "appointment_request_inbox_id"
    t.bigint "document_request_inbox_id"
    t.bigint "compliance_inbox_id"
    t.bigint "urgent_inbox_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "telemedicine_recording", default: {}, null: false
    t.index ["account_id"], name: "index_patient_portal_settings_on_account_id", unique: true
  end

  create_table "patient_responsible_links", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "responsible_patient_id", null: false
    t.bigint "dependent_patient_id", null: false
    t.string "role", default: "guardian", null: false
    t.boolean "is_primary", default: false, null: false
    t.datetime "active_from", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "active_until"
    t.datetime "revoked_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_patient_responsible_links_on_account_id"
    t.index ["dependent_patient_id"], name: "idx_resp_links_dependent"
    t.index ["responsible_patient_id", "dependent_patient_id"], name: "idx_resp_links_unique_pair", unique: true
    t.index ["responsible_patient_id"], name: "idx_resp_links_responsible"
  end

  create_table "patient_timeline_events", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.bigint "actor_id"
    t.string "event_type", null: false
    t.text "label", null: false
    t.string "actor_name"
    t.string "reference_type"
    t.bigint "reference_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_patient_timeline_events_on_account_id"
    t.index ["actor_id"], name: "index_patient_timeline_events_on_actor_id"
    t.index ["event_type"], name: "index_patient_timeline_events_on_event_type"
    t.index ["occurred_at"], name: "index_patient_timeline_events_on_occurred_at"
    t.index ["patient_id", "occurred_at"], name: "index_patient_timeline_events_on_patient_id_and_occurred_at"
    t.index ["patient_id"], name: "index_patient_timeline_events_on_patient_id"
    t.index ["reference_type", "reference_id"], name: "idx_on_reference_type_reference_id_6ad35aefb9"
  end

  create_table "patients", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "phone"
    t.string "email"
    t.string "cpf"
    t.string "rg"
    t.date "birthdate"
    t.string "sex"
    t.string "patient_status", default: "novo"
    t.integer "no_show_count", default: 0
    t.boolean "needs_recall", default: false
    t.string "avatar_url"
    t.jsonb "address", default: {}
    t.jsonb "contacts", default: []
    t.jsonb "emergency_contact", default: {}
    t.jsonb "insurance", default: {}
    t.jsonb "billing_info", default: {}
    t.jsonb "contact_preferences", default: {}
    t.jsonb "communication_opt_ins", default: {}
    t.jsonb "lgpd_consent", default: {}
    t.text "pinned_note"
    t.string "origin"
    t.string "unit"
    t.bigint "responsible_professional_id"
    t.bigint "contact_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "marital_status"
    t.datetime "recall_dismissed_at"
    t.bigint "recall_dismissed_by_id"
    t.text "notes"
    t.boolean "has_guardian", default: false, null: false
    t.jsonb "guardian", default: {}, null: false
    t.string "social_name"
    t.jsonb "external_ids", default: {}, null: false
    t.datetime "anonymized_at"
    t.string "portal_status", default: "active", null: false
    t.datetime "portal_suspended_until"
    t.text "portal_suspension_reason"
    t.datetime "last_recall_at"
    t.index ["account_id", "deleted_at"], name: "index_patients_on_account_id_and_deleted_at"
    t.index ["account_id", "name"], name: "index_patients_on_account_id_and_name"
    t.index ["account_id"], name: "index_patients_on_account_id"
    t.index ["anonymized_at"], name: "index_patients_on_anonymized_at"
    t.index ["contact_id"], name: "index_patients_on_contact_id"
    t.index ["cpf"], name: "index_patients_on_cpf"
    t.index ["deleted_at"], name: "index_patients_on_deleted_at"
    t.index ["email"], name: "index_patients_on_email"
    t.index ["external_ids"], name: "index_patients_on_external_ids", using: :gin
    t.index ["needs_recall"], name: "idx_patients_needs_recall_partial", where: "(needs_recall = true)"
    t.index ["patient_status"], name: "index_patients_on_patient_status"
    t.index ["phone"], name: "index_patients_on_phone"
    t.index ["portal_status"], name: "index_patients_on_portal_status"
    t.index ["recall_dismissed_at"], name: "idx_patients_recall_dismissed", where: "(recall_dismissed_at IS NOT NULL)"
  end

  create_table "platform_app_permissibles", force: :cascade do |t|
    t.bigint "platform_app_id", null: false
    t.string "permissible_type", null: false
    t.bigint "permissible_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["permissible_type", "permissible_id"], name: "index_platform_app_permissibles_on_permissibles"
    t.index ["platform_app_id", "permissible_id", "permissible_type"], name: "unique_permissibles_index", unique: true
    t.index ["platform_app_id"], name: "index_platform_app_permissibles_on_platform_app_id"
  end

  create_table "platform_apps", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "portal_appointment_requests", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.bigint "preferred_professional_id"
    t.bigint "preferred_service_id"
    t.jsonb "preferred_dates", default: []
    t.string "preferred_period"
    t.text "notes"
    t.string "status", default: "pending", null: false
    t.bigint "processed_by_id"
    t.datetime "processed_at"
    t.text "processed_notes"
    t.bigint "agenda_event_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_portal_appointment_requests_on_account_id"
    t.index ["patient_id", "status"], name: "index_portal_appointment_requests_on_patient_id_and_status"
    t.index ["patient_id"], name: "index_portal_appointment_requests_on_patient_id"
    t.index ["status"], name: "index_portal_appointment_requests_on_status"
  end

  create_table "portal_document_requests", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.bigint "source_document_id"
    t.string "document_type"
    t.text "reason", null: false
    t.string "status", default: "pending", null: false
    t.bigint "processed_by_id"
    t.datetime "processed_at"
    t.text "processed_notes"
    t.bigint "fulfilled_document_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_portal_document_requests_on_account_id"
    t.index ["patient_id", "status"], name: "index_portal_document_requests_on_patient_id_and_status"
    t.index ["patient_id"], name: "index_portal_document_requests_on_patient_id"
    t.index ["status"], name: "index_portal_document_requests_on_status"
  end

  create_table "portal_invites", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.bigint "invited_by_user_id"
    t.string "channel", default: "whatsapp", null: false
    t.string "token", null: false
    t.datetime "sent_at"
    t.datetime "accepted_at"
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "patient_id"], name: "index_portal_invites_on_account_id_and_patient_id"
    t.index ["account_id"], name: "index_portal_invites_on_account_id"
    t.index ["patient_id"], name: "index_portal_invites_on_patient_id"
    t.index ["token"], name: "index_portal_invites_on_token", unique: true
  end

  create_table "portal_payments", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.bigint "financial_installment_id", null: false
    t.string "method", null: false
    t.string "status", default: "pending", null: false
    t.string "gateway", default: "mock", null: false
    t.string "gateway_payment_id"
    t.text "pix_qr_code"
    t.text "pix_copy_paste"
    t.string "boleto_url"
    t.string "boleto_barcode"
    t.integer "amount_cents", null: false
    t.datetime "expires_at"
    t.datetime "paid_at"
    t.jsonb "gateway_payload", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_portal_payments_on_account_id"
    t.index ["financial_installment_id", "status"], name: "idx_portal_payments_installment_status"
    t.index ["financial_installment_id"], name: "index_portal_payments_on_financial_installment_id"
    t.index ["gateway_payment_id"], name: "index_portal_payments_on_gateway_payment_id", unique: true, where: "(gateway_payment_id IS NOT NULL)"
    t.index ["patient_id", "status"], name: "index_portal_payments_on_patient_id_and_status"
    t.index ["patient_id"], name: "index_portal_payments_on_patient_id"
  end

  create_table "portals", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "custom_domain"
    t.string "color"
    t.string "homepage_link"
    t.string "page_title"
    t.text "header_text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "config", default: {"allowed_locales" => ["en"]}
    t.boolean "archived", default: false
    t.bigint "channel_web_widget_id"
    t.jsonb "ssl_settings", default: {}, null: false
    t.index ["channel_web_widget_id"], name: "index_portals_on_channel_web_widget_id"
    t.index ["custom_domain"], name: "index_portals_on_custom_domain", unique: true
    t.index ["slug"], name: "index_portals_on_slug", unique: true
  end

  create_table "portals_members", id: false, force: :cascade do |t|
    t.bigint "portal_id", null: false
    t.bigint "user_id", null: false
    t.index ["portal_id", "user_id"], name: "index_portals_members_on_portal_id_and_user_id", unique: true
    t.index ["portal_id"], name: "index_portals_members_on_portal_id"
    t.index ["user_id"], name: "index_portals_members_on_user_id"
  end

  create_table "professional_portal_settings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.jsonb "overrides", default: {}, null: false
    t.boolean "accepts_direct_messages", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id"], name: "idx_prof_portal_settings_account_user", unique: true
    t.index ["account_id"], name: "index_professional_portal_settings_on_account_id"
    t.index ["user_id"], name: "index_professional_portal_settings_on_user_id"
  end

  create_table "proposed_evolutions", force: :cascade do |t|
    t.bigint "telemed_recording_id", null: false
    t.bigint "clinical_note_id"
    t.string "provider", null: false
    t.jsonb "soap_structure", default: {}, null: false
    t.text "raw_markdown"
    t.jsonb "attention_points", default: [], null: false
    t.string "status", default: "pending_review", null: false
    t.bigint "reviewed_by_id"
    t.datetime "reviewed_at"
    t.text "reviewer_notes"
    t.integer "input_tokens"
    t.integer "output_tokens"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["clinical_note_id"], name: "index_proposed_evolutions_on_clinical_note_id"
    t.index ["reviewed_by_id"], name: "index_proposed_evolutions_on_reviewed_by_id"
    t.index ["status"], name: "index_proposed_evolutions_on_status"
    t.index ["telemed_recording_id", "created_at"], name: "index_proposed_evolutions_on_recording_and_created"
    t.index ["telemed_recording_id"], name: "index_proposed_evolutions_on_telemed_recording_id"
  end

  create_table "recurring_expenses", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "financial_category_id"
    t.bigint "bank_account_id"
    t.bigint "registered_by_id"
    t.string "description", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.string "payment_method"
    t.string "frequency", null: false
    t.integer "due_day", default: 1
    t.integer "competence_offset_days", default: 0
    t.string "competence_rule", default: "same_month"
    t.date "start_date", null: false
    t.date "end_date"
    t.date "last_generated_at"
    t.boolean "active", default: true
    t.boolean "auto_confirm", default: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_recurring_expenses_on_account_id"
    t.index ["active"], name: "index_recurring_expenses_on_active"
    t.index ["financial_category_id"], name: "index_recurring_expenses_on_financial_category_id"
    t.index ["frequency"], name: "index_recurring_expenses_on_frequency"
  end

  create_table "related_categories", force: :cascade do |t|
    t.bigint "category_id"
    t.bigint "related_category_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id", "related_category_id"], name: "index_related_categories_on_category_id_and_related_category_id", unique: true
    t.index ["related_category_id", "category_id"], name: "index_related_categories_on_related_category_id_and_category_id", unique: true
  end

  create_table "reporting_events", force: :cascade do |t|
    t.string "name"
    t.float "value"
    t.integer "account_id"
    t.integer "inbox_id"
    t.integer "user_id"
    t.integer "conversation_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "value_in_business_hours"
    t.datetime "event_start_time", precision: nil
    t.datetime "event_end_time", precision: nil
    t.index ["account_id", "name", "created_at"], name: "reporting_events__account_id__name__created_at"
    t.index ["account_id", "name", "inbox_id", "created_at"], name: "index_reporting_events_for_response_distribution"
    t.index ["account_id"], name: "index_reporting_events_on_account_id"
    t.index ["conversation_id"], name: "index_reporting_events_on_conversation_id"
    t.index ["created_at"], name: "index_reporting_events_on_created_at"
    t.index ["inbox_id"], name: "index_reporting_events_on_inbox_id"
    t.index ["name"], name: "index_reporting_events_on_name"
    t.index ["user_id"], name: "index_reporting_events_on_user_id"
  end

  create_table "session_logs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.bigint "professional_id"
    t.bigint "treatment_plan_id"
    t.bigint "treatment_item_id"
    t.bigint "appointment_id"
    t.datetime "performed_at", null: false
    t.integer "duration_minutes"
    t.jsonb "areas_treated", default: [], null: false
    t.jsonb "products_used", default: [], null: false
    t.text "complications"
    t.text "result_observed"
    t.text "post_procedure_guidance"
    t.boolean "return_needed", default: false, null: false
    t.integer "return_in_days"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "procedure_name"
    t.text "complaint_of_day"
    t.text "assessment"
    t.text "next_consultation_details"
    t.text "observation"
    t.string "status", default: "draft", null: false
    t.datetime "signed_at"
    t.bigint "signed_by_id"
    t.datetime "erratum_at"
    t.bigint "erratum_by_id"
    t.text "erratum_reason"
    t.integer "lock_version", default: 0, null: false
    t.bigint "form_template_id"
    t.bigint "migrated_from_clinical_note_id"
    t.text "patient_signature_blob"
    t.string "patient_signature_mode"
    t.datetime "patient_signed_at"
    t.string "patient_signature_integrity_hash"
    t.string "patient_signature_remote_token"
    t.datetime "patient_signature_remote_link_sent_at"
    t.datetime "patient_signature_remote_link_expires_at"
    t.string "patient_signature_ip"
    t.text "patient_signature_device_info"
    t.index ["account_id"], name: "index_session_logs_on_account_id"
    t.index ["appointment_id"], name: "index_session_logs_on_appointment_id"
    t.index ["deleted_at"], name: "index_session_logs_on_deleted_at"
    t.index ["erratum_at"], name: "index_session_logs_on_erratum_at"
    t.index ["erratum_by_id"], name: "index_session_logs_on_erratum_by_id"
    t.index ["form_template_id"], name: "index_session_logs_on_form_template_id"
    t.index ["migrated_from_clinical_note_id"], name: "idx_session_logs_migrated_from_clinical_note", unique: true, where: "(migrated_from_clinical_note_id IS NOT NULL)"
    t.index ["patient_id", "status", "deleted_at"], name: "idx_session_logs_patient_status"
    t.index ["patient_id"], name: "index_session_logs_on_patient_id"
    t.index ["patient_signature_remote_token"], name: "idx_session_logs_patient_signature_token", unique: true, where: "(patient_signature_remote_token IS NOT NULL)"
    t.index ["performed_at"], name: "index_session_logs_on_performed_at"
    t.index ["professional_id"], name: "index_session_logs_on_professional_id"
    t.index ["signed_by_id"], name: "index_session_logs_on_signed_by_id"
    t.index ["treatment_item_id"], name: "index_session_logs_on_treatment_item_id"
    t.index ["treatment_plan_id"], name: "index_session_logs_on_treatment_plan_id"
  end

  create_table "sla_events", force: :cascade do |t|
    t.bigint "applied_sla_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "account_id", null: false
    t.bigint "sla_policy_id", null: false
    t.bigint "inbox_id", null: false
    t.integer "event_type"
    t.jsonb "meta", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_sla_events_on_account_id"
    t.index ["applied_sla_id"], name: "index_sla_events_on_applied_sla_id"
    t.index ["conversation_id"], name: "index_sla_events_on_conversation_id"
    t.index ["inbox_id"], name: "index_sla_events_on_inbox_id"
    t.index ["sla_policy_id"], name: "index_sla_events_on_sla_policy_id"
  end

  create_table "sla_policies", force: :cascade do |t|
    t.string "name", null: false
    t.float "first_response_time_threshold"
    t.float "next_response_time_threshold"
    t.boolean "only_during_business_hours", default: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "description"
    t.float "resolution_time_threshold"
    t.index ["account_id"], name: "index_sla_policies_on_account_id"
  end

  create_table "subscription_plans", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.decimal "price_monthly", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "price_yearly", precision: 10, scale: 2
    t.string "color", default: "#5B5BD6"
    t.jsonb "features", default: [], null: false
    t.jsonb "limits", default: {}, null: false
    t.string "slug"
    t.boolean "active", default: true, null: false
    t.integer "display_order", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_subscription_plans_on_active"
    t.index ["display_order"], name: "index_subscription_plans_on_display_order"
    t.index ["slug"], name: "index_subscription_plans_on_slug", unique: true
  end

  create_table "taggings", id: :serial, force: :cascade do |t|
    t.integer "tag_id"
    t.string "taggable_type"
    t.integer "taggable_id"
    t.string "tagger_type"
    t.integer "tagger_id"
    t.string "context", limit: 128
    t.datetime "created_at", precision: nil
    t.index ["context"], name: "index_taggings_on_context"
    t.index ["tag_id", "taggable_id", "taggable_type", "context", "tagger_id", "tagger_type"], name: "taggings_idx", unique: true
    t.index ["tag_id", "taggable_type"], name: "idx_taggings_tag_type_for_label_filter", where: "((context)::text = 'labels'::text)"
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_id", "taggable_type", "context"], name: "index_taggings_on_taggable_id_and_taggable_type_and_context"
    t.index ["taggable_id", "taggable_type", "tagger_id", "context"], name: "taggings_idy"
    t.index ["taggable_id"], name: "index_taggings_on_taggable_id"
    t.index ["taggable_type"], name: "index_taggings_on_taggable_type"
    t.index ["tagger_id", "tagger_type"], name: "index_taggings_on_tagger_id_and_tagger_type"
    t.index ["tagger_id"], name: "index_taggings_on_tagger_id"
  end

  create_table "tags", id: :serial, force: :cascade do |t|
    t.string "name"
    t.integer "taggings_count", default: 0
    t.index "lower((name)::text) gin_trgm_ops", name: "tags_name_trgm_idx", using: :gin
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "team_members", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id", "user_id"], name: "index_team_members_on_team_id_and_user_id", unique: true
    t.index ["team_id"], name: "index_team_members_on_team_id"
    t.index ["user_id"], name: "index_team_members_on_user_id"
  end

  create_table "teams", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.boolean "allow_auto_assign", default: true
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_teams_on_account_id"
    t.index ["name", "account_id"], name: "index_teams_on_name_and_account_id", unique: true
  end

  create_table "telemed_consents", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.string "term_version", default: "1.0", null: false
    t.datetime "accepted_at", null: false
    t.string "ip", limit: 64
    t.string "user_agent", limit: 255
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "patient_id", "term_version"], name: "idx_telemed_consents_unique_per_version", unique: true
    t.index ["account_id"], name: "index_telemed_consents_on_account_id"
    t.index ["patient_id"], name: "index_telemed_consents_on_patient_id"
  end

  create_table "telemed_recordings", force: :cascade do |t|
    t.bigint "agenda_event_id", null: false
    t.bigint "account_id", null: false
    t.string "doctor_egress_id"
    t.string "patient_egress_id"
    t.string "status", default: "pending", null: false
    t.string "doctor_audio_key"
    t.string "patient_audio_key"
    t.string "doctor_video_key"
    t.string "patient_video_key"
    t.string "composite_video_key"
    t.integer "duration_seconds"
    t.bigint "total_size_bytes"
    t.text "transcript_text"
    t.jsonb "transcript_segments"
    t.string "transcript_provider"
    t.text "failure_reason"
    t.integer "retry_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "composite_egress_id"
    t.string "composite_audio_key"
    t.datetime "archived_at"
    t.string "recording_kind", default: "audio", null: false
    t.index ["account_id", "created_at"], name: "index_telemed_recordings_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_telemed_recordings_on_account_id"
    t.index ["agenda_event_id"], name: "index_telemed_recordings_on_agenda_event_id"
    t.index ["archived_at"], name: "index_telemed_recordings_on_archived_at"
    t.index ["composite_egress_id"], name: "index_telemed_recordings_on_composite_egress_id", unique: true, where: "(composite_egress_id IS NOT NULL)"
    t.index ["doctor_egress_id"], name: "index_telemed_recordings_on_doctor_egress_id", unique: true, where: "(doctor_egress_id IS NOT NULL)"
    t.index ["patient_egress_id"], name: "index_telemed_recordings_on_patient_egress_id", unique: true, where: "(patient_egress_id IS NOT NULL)"
    t.index ["status"], name: "index_telemed_recordings_on_status"
  end

  create_table "transactions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.bigint "financial_estimate_id"
    t.bigint "registered_by_id"
    t.bigint "cash_entry_id"
    t.string "transaction_type", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "payment_method"
    t.string "status", default: "pendente", null: false
    t.date "due_date"
    t.date "paid_at"
    t.text "description"
    t.text "notes"
    t.integer "installment_number"
    t.integer "total_installments"
    t.jsonb "metadata", default: {}
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["cash_entry_id"], name: "index_transactions_on_cash_entry_id"
    t.index ["deleted_at"], name: "index_transactions_on_deleted_at"
    t.index ["due_date"], name: "index_transactions_on_due_date"
    t.index ["financial_estimate_id"], name: "index_transactions_on_financial_estimate_id"
    t.index ["patient_id"], name: "index_transactions_on_patient_id"
    t.index ["status"], name: "index_transactions_on_status"
  end

  create_table "treatment_items", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "treatment_plan_id", null: false
    t.string "procedure_code"
    t.string "procedure_name", null: false
    t.string "region"
    t.string "tooth_number"
    t.integer "sessions_planned", default: 1, null: false
    t.integer "sessions_done", default: 0, null: false
    t.decimal "unit_price", precision: 10, scale: 2
    t.decimal "total_price", precision: 10, scale: 2
    t.string "priority"
    t.string "status", default: "proposto", null: false
    t.text "clinical_justification"
    t.text "notes"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "discount_type"
    t.decimal "discount_value", precision: 10, scale: 2, default: "0.0", null: false
    t.bigint "agenda_service_id"
    t.index ["account_id"], name: "index_treatment_items_on_account_id"
    t.index ["agenda_service_id"], name: "index_treatment_items_on_agenda_service_id"
    t.index ["deleted_at"], name: "index_treatment_items_on_deleted_at"
    t.index ["status"], name: "index_treatment_items_on_status"
    t.index ["treatment_plan_id"], name: "index_treatment_items_on_treatment_plan_id"
  end

  create_table "treatment_plans", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "patient_id", null: false
    t.bigint "professional_id"
    t.string "title"
    t.text "description"
    t.string "status", default: "proposto", null: false
    t.boolean "partially_approved", default: false, null: false
    t.date "approved_at"
    t.bigint "approved_by_id"
    t.text "cancellation_reason"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "estimated_duration"
    t.integer "lock_version", default: 0, null: false
    t.index ["account_id"], name: "index_treatment_plans_on_account_id"
    t.index ["deleted_at"], name: "index_treatment_plans_on_deleted_at"
    t.index ["patient_id"], name: "index_treatment_plans_on_patient_id"
    t.index ["professional_id"], name: "index_treatment_plans_on_professional_id"
    t.index ["status"], name: "index_treatment_plans_on_status"
  end

  create_table "users", id: :serial, force: :cascade do |t|
    t.string "provider", default: "email", null: false
    t.string "uid", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at", precision: nil
    t.datetime "remember_created_at", precision: nil
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at", precision: nil
    t.datetime "last_sign_in_at", precision: nil
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "confirmation_token"
    t.datetime "confirmed_at", precision: nil
    t.datetime "confirmation_sent_at", precision: nil
    t.string "unconfirmed_email"
    t.string "name", null: false
    t.string "display_name"
    t.string "email"
    t.json "tokens"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "pubsub_token"
    t.integer "availability", default: 0
    t.jsonb "ui_settings", default: {}
    t.jsonb "custom_attributes", default: {}
    t.string "type"
    t.text "message_signature"
    t.string "otp_secret"
    t.integer "consumed_timestep"
    t.boolean "otp_required_for_login", default: false
    t.text "otp_backup_codes"
    t.index ["email"], name: "index_users_on_email"
    t.index ["otp_required_for_login"], name: "index_users_on_otp_required_for_login"
    t.index ["otp_secret"], name: "index_users_on_otp_secret", unique: true
    t.index ["pubsub_token"], name: "index_users_on_pubsub_token", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["uid", "provider"], name: "index_users_on_uid_and_provider", unique: true
  end

  create_table "waiting_list_entries", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "contact_id", null: false
    t.string "period", null: false
    t.string "specific_time"
    t.jsonb "preferred_days", default: []
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "contact_id"], name: "index_waiting_list_entries_on_account_id_and_contact_id", unique: true
    t.index ["account_id"], name: "index_waiting_list_entries_on_account_id"
    t.index ["contact_id"], name: "index_waiting_list_entries_on_contact_id"
  end

  create_table "webhooks", force: :cascade do |t|
    t.integer "account_id"
    t.integer "inbox_id"
    t.text "url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "webhook_type", default: 0
    t.jsonb "subscriptions", default: ["conversation_status_changed", "conversation_updated", "conversation_created", "contact_created", "contact_updated", "message_created", "message_updated", "webwidget_triggered"]
    t.string "name"
    t.index ["account_id", "url"], name: "index_webhooks_on_account_id_and_url", unique: true
  end

  create_table "working_hours", force: :cascade do |t|
    t.bigint "inbox_id"
    t.bigint "account_id"
    t.integer "day_of_week", null: false
    t.boolean "closed_all_day", default: false
    t.integer "open_hour"
    t.integer "open_minutes"
    t.integer "close_hour"
    t.integer "close_minutes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "open_all_day", default: false
    t.index ["account_id"], name: "index_working_hours_on_account_id"
    t.index ["inbox_id"], name: "index_working_hours_on_inbox_id"
  end

  add_foreign_key "account_users", "klivy_roles"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agenda_audit_logs", "accounts"
  add_foreign_key "agenda_categories", "accounts"
  add_foreign_key "agenda_events", "accounts"
  add_foreign_key "agenda_events", "agenda_categories", column: "category_id"
  add_foreign_key "agenda_events", "agenda_services", on_delete: :nullify
  add_foreign_key "agenda_events", "contacts", on_delete: :nullify
  add_foreign_key "agenda_events", "users"
  add_foreign_key "agenda_notification_logs", "accounts"
  add_foreign_key "agenda_notification_logs", "agenda_events"
  add_foreign_key "agenda_notification_logs", "agenda_notification_rules"
  add_foreign_key "agenda_notification_rules", "accounts"
  add_foreign_key "agenda_online_configs", "accounts"
  add_foreign_key "agenda_service_users", "accounts"
  add_foreign_key "agenda_service_users", "agenda_services"
  add_foreign_key "agenda_service_users", "users"
  add_foreign_key "agenda_services", "accounts"
  add_foreign_key "agenda_services", "agenda_categories", column: "default_category_id", on_delete: :nullify
  add_foreign_key "ai_agent_account_settings", "accounts"
  add_foreign_key "ai_agent_account_settings", "users", column: "responsible_physician_id"
  add_foreign_key "ai_agent_child_chunks", "accounts"
  add_foreign_key "ai_agent_child_chunks", "ai_agent_documents", column: "document_id"
  add_foreign_key "ai_agent_child_chunks", "ai_agent_parent_chunks", column: "parent_chunk_id"
  add_foreign_key "ai_agent_conversation_states", "accounts"
  add_foreign_key "ai_agent_documents", "accounts"
  add_foreign_key "ai_agent_feedbacks", "accounts"
  add_foreign_key "ai_agent_feedbacks", "ai_agent_traces", column: "trace_id"
  add_foreign_key "ai_agent_follow_up_executions", "accounts"
  add_foreign_key "ai_agent_follow_up_executions", "ai_agent_follow_up_rules", column: "rule_id", on_delete: :cascade
  add_foreign_key "ai_agent_follow_up_rules", "accounts"
  add_foreign_key "ai_agent_internal_notification_templates", "accounts"
  add_foreign_key "ai_agent_parent_chunks", "ai_agent_documents", column: "document_id"
  add_foreign_key "ai_agent_patient_memories", "accounts"
  add_foreign_key "ai_agent_traces", "accounts"
  add_foreign_key "ai_agent_usage_counters", "accounts"
  add_foreign_key "anamneses", "accounts"
  add_foreign_key "anamneses", "patients"
  add_foreign_key "beclinic_account_profiles", "accounts"
  add_foreign_key "beclinic_user_profiles", "accounts"
  add_foreign_key "beclinic_user_profiles", "users"
  add_foreign_key "billing_payments", "billing_subscriptions", column: "subscription_id"
  add_foreign_key "billing_subscriptions", "accounts"
  add_foreign_key "cash_entries", "accounts"
  add_foreign_key "cash_register_entries", "accounts"
  add_foreign_key "cash_register_entries", "cash_registers"
  add_foreign_key "cash_registers", "accounts"
  add_foreign_key "cash_registers", "users", column: "operator_id"
  add_foreign_key "clinical_notes", "accounts"
  add_foreign_key "clinical_notes", "patients"
  add_foreign_key "clinical_notes", "proposed_evolutions", on_delete: :nullify
  add_foreign_key "critical_alerts", "accounts"
  add_foreign_key "critical_alerts", "patients"
  add_foreign_key "form_templates", "accounts"
  add_foreign_key "inboxes", "portals"
  add_foreign_key "internal_chat_attachments", "internal_chat_messages", column: "message_id", on_delete: :cascade
  add_foreign_key "internal_chat_memberships", "internal_chat_rooms", column: "room_id", on_delete: :cascade
  add_foreign_key "internal_chat_mentions", "internal_chat_messages", column: "message_id", on_delete: :cascade
  add_foreign_key "internal_chat_message_favorites", "accounts", on_delete: :cascade
  add_foreign_key "internal_chat_message_favorites", "internal_chat_messages", column: "message_id", on_delete: :cascade
  add_foreign_key "internal_chat_message_favorites", "users", on_delete: :cascade
  add_foreign_key "internal_chat_message_reactions", "accounts", on_delete: :cascade
  add_foreign_key "internal_chat_message_reactions", "internal_chat_messages", column: "message_id", on_delete: :cascade
  add_foreign_key "internal_chat_message_reactions", "users", on_delete: :cascade
  add_foreign_key "internal_chat_messages", "internal_chat_rooms", column: "room_id", on_delete: :cascade
  add_foreign_key "internal_chat_messages", "internal_chat_stickers", column: "sticker_id", on_delete: :nullify
  add_foreign_key "internal_chat_read_receipts", "internal_chat_messages", column: "message_id", on_delete: :cascade
  add_foreign_key "internal_chat_rooms", "accounts", on_delete: :cascade
  add_foreign_key "internal_chat_sticker_favorites", "internal_chat_stickers", column: "sticker_id", on_delete: :cascade
  add_foreign_key "internal_chat_sticker_favorites", "users", on_delete: :cascade
  add_foreign_key "internal_chat_stickers", "accounts", on_delete: :cascade
  add_foreign_key "klivy_roles", "accounts"
  add_foreign_key "patient_appointments", "accounts"
  add_foreign_key "patient_appointments", "agenda_events"
  add_foreign_key "patient_appointments", "patients"
  add_foreign_key "patient_appointments", "users", column: "professional_id"
  add_foreign_key "patient_audit_logs", "accounts"
  add_foreign_key "patient_audit_logs", "patients"
  add_foreign_key "patient_portal_access_logs", "accounts"
  add_foreign_key "patient_portal_access_logs", "patients"
  add_foreign_key "patient_portal_consents", "accounts"
  add_foreign_key "patient_portal_consents", "patients"
  add_foreign_key "patient_portal_notifications", "accounts"
  add_foreign_key "patient_portal_notifications", "patients"
  add_foreign_key "patient_portal_push_subscriptions", "accounts"
  add_foreign_key "patient_portal_push_subscriptions", "patients"
  add_foreign_key "patient_portal_sessions", "accounts"
  add_foreign_key "patient_portal_sessions", "patients"
  add_foreign_key "patient_portal_settings", "accounts"
  add_foreign_key "patient_responsible_links", "accounts"
  add_foreign_key "patient_responsible_links", "patients", column: "dependent_patient_id"
  add_foreign_key "patient_responsible_links", "patients", column: "responsible_patient_id"
  add_foreign_key "patient_timeline_events", "accounts"
  add_foreign_key "patient_timeline_events", "patients"
  add_foreign_key "patient_timeline_events", "users", column: "actor_id"
  add_foreign_key "patients", "accounts"
  add_foreign_key "portal_appointment_requests", "accounts"
  add_foreign_key "portal_appointment_requests", "patients"
  add_foreign_key "portal_document_requests", "accounts"
  add_foreign_key "portal_document_requests", "patients"
  add_foreign_key "portal_invites", "accounts"
  add_foreign_key "portal_invites", "patients"
  add_foreign_key "portal_payments", "accounts"
  add_foreign_key "portal_payments", "financial_installments"
  add_foreign_key "portal_payments", "patients"
  add_foreign_key "professional_portal_settings", "accounts"
  add_foreign_key "professional_portal_settings", "users"
  add_foreign_key "proposed_evolutions", "clinical_notes"
  add_foreign_key "proposed_evolutions", "telemed_recordings"
  add_foreign_key "proposed_evolutions", "users", column: "reviewed_by_id"
  add_foreign_key "telemed_consents", "accounts"
  add_foreign_key "telemed_consents", "patients"
  add_foreign_key "telemed_recordings", "accounts"
  add_foreign_key "telemed_recordings", "agenda_events"
  add_foreign_key "treatment_items", "agenda_services", on_delete: :nullify
  add_foreign_key "waiting_list_entries", "accounts"
  add_foreign_key "waiting_list_entries", "contacts"
  create_trigger("accounts_after_insert_row_tr", :generated => true, :compatibility => 1).
      on("accounts").
      after(:insert).
      for_each(:row) do
    "execute format('create sequence IF NOT EXISTS conv_dpid_seq_%s', NEW.id);"
  end

  create_trigger("conversations_before_insert_row_tr", :generated => true, :compatibility => 1).
      on("conversations").
      before(:insert).
      for_each(:row) do
    "NEW.display_id := nextval('conv_dpid_seq_' || NEW.account_id);"
  end

  create_trigger("camp_dpid_before_insert", :generated => true, :compatibility => 1).
      on("accounts").
      name("camp_dpid_before_insert").
      after(:insert).
      for_each(:row) do
    "execute format('create sequence IF NOT EXISTS camp_dpid_seq_%s', NEW.id);"
  end

  create_trigger("campaigns_before_insert_row_tr", :generated => true, :compatibility => 1).
      on("campaigns").
      before(:insert).
      for_each(:row) do
    "NEW.display_id := nextval('camp_dpid_seq_' || NEW.account_id);"
  end

end
