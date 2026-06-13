class CreateFinancialV2IdempotencyAndGateway < ActiveRecord::Migration[7.0]
  # Suporte a idempotência server-side (canon Parte 6 §"Idempotência")
  # e configuração de gateway de pagamento por conta (preparação Asaas).
  #
  # Idempotency keys são guardadas em tabela ao invés de Redis para:
  #   - persistência durante deploys (Redis pode não estar configurado)
  #   - auditoria (rastrear chave → resposta)
  #   - simplicidade operacional (uma dependência a menos)
  # TTL aplicado via job de cleanup ou via filtro na query (created_at > 24h).
  def change
    # ---------------------------------------------------------------
    # Idempotency keys.
    # ---------------------------------------------------------------
    create_table :financial_idempotency_keys do |t|
      t.bigint  :account_id,           null: false
      t.string  :key,                  null: false, limit: 80  # UUID v4
      t.string  :request_path,         null: false, limit: 200
      t.string  :request_method,       null: false, limit: 10
      t.string  :request_fingerprint,  null: false, limit: 64  # SHA-256 do body
      t.integer :response_status,      null: false
      t.jsonb   :response_body,        default: {}
      t.bigint  :user_id
      t.datetime :created_at,          null: false
    end
    add_index :financial_idempotency_keys, :account_id
    add_index :financial_idempotency_keys, [:account_id, :key], unique: true,
              name: 'idx_uniq_idempotency_key_per_account'
    add_index :financial_idempotency_keys, :created_at  # cleanup TTL

    # ---------------------------------------------------------------
    # Wizard de configuração inicial (canon F-04).
    # Estado do wizard por conta — bloqueia uso do módulo até concluído.
    # ---------------------------------------------------------------
    create_table :financial_setup_states do |t|
      t.bigint  :account_id,           null: false
      t.string  :status,               null: false, default: 'pending', limit: 20
      # status: pending | in_progress | completed | skipped
      t.boolean :step_categories_done,        default: false, null: false
      t.boolean :step_bank_accounts_done,     default: false, null: false
      t.boolean :step_commission_rules_done,  default: false, null: false
      t.boolean :step_recurring_expenses_done, default: false, null: false
      t.boolean :step_revenue_goal_done,      default: false, null: false
      t.datetime :completed_at
      t.bigint  :completed_by_id
      t.timestamps
    end
    add_index :financial_setup_states, :account_id, unique: true,
              name: 'idx_uniq_setup_state_per_account'

    # ---------------------------------------------------------------
    # Gateway settings por conta — credenciais e configuração do Asaas.
    # Credenciais sensíveis são criptografadas via Rails encrypted attributes
    # (configurado no model Financial::GatewaySetting).
    # ---------------------------------------------------------------
    create_table :financial_gateway_settings do |t|
      t.bigint  :account_id,           null: false
      t.string  :gateway,              null: false, default: 'manual', limit: 30
      # gateway: manual | asaas
      t.string  :environment,          limit: 20, default: 'sandbox'  # sandbox | production
      t.text    :api_key_ciphertext     # encrypted
      t.string  :webhook_secret_ciphertext  # encrypted
      t.string  :default_pix_key
      t.string  :default_customer_external_ref_strategy, default: 'patient_id', limit: 30
      t.boolean :auto_sync_enabled,    default: false, null: false
      t.boolean :webhook_verified,     default: false, null: false
      t.datetime :webhook_last_received_at
      t.jsonb   :metadata,             default: {}
      t.bigint  :created_by_id
      t.bigint  :updated_by_id
      t.timestamps
    end
    add_index :financial_gateway_settings, :account_id, unique: true,
              name: 'idx_uniq_gateway_settings_per_account'

    # ---------------------------------------------------------------
    # Webhook events — registra todo evento recebido para reprocessamento e auditoria.
    # ---------------------------------------------------------------
    create_table :financial_gateway_webhook_events do |t|
      t.bigint  :account_id,           null: false
      t.string  :gateway,              null: false, limit: 30
      t.string  :event_id,             null: false, limit: 100  # ID externo do gateway
      t.string  :event_type,           null: false, limit: 80
      t.string  :status,               null: false, default: 'received', limit: 20
      # status: received | processed | failed | ignored
      t.jsonb   :payload,              default: {}, null: false
      t.text    :processing_error
      t.datetime :received_at,         null: false
      t.datetime :processed_at
      t.integer :processing_attempts,  default: 0, null: false
      t.timestamps
    end
    add_index :financial_gateway_webhook_events, :account_id
    add_index :financial_gateway_webhook_events, [:gateway, :event_id], unique: true,
              name: 'idx_uniq_gateway_event_id'
    add_index :financial_gateway_webhook_events, [:account_id, :status]
    add_index :financial_gateway_webhook_events, :received_at
  end
end
