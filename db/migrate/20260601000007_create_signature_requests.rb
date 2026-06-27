# Cria a tabela central do plugin signatures.
#
# `signable` é polimórfico — pode apontar pra Document ou ConsentRecord (e
# futuros tipos). Mantemos `account_id` desnormalizado pra evitar JOIN em
# queries scoped por clínica (high-volume futuro).
#
# `provider` identifica o serviço externo usado ('clicksign', 'mock', etc.).
# `external_id` é o envelope_id (ou equivalente) retornado pelo provider —
# usado pra correlacionar webhook → SignatureRequest.
#
# Status segue máquina simples: pending → sent → viewed → signed → completed
# (caminho feliz) ou → cancelled / failed / expired (caminhos de erro).
class CreateSignatureRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :signature_requests do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :signable, polymorphic: true, null: false, index: true
      t.references :requested_by_user, foreign_key: { to_table: :users }, index: true

      # ─── Provider & rastreio externo ────────────────────────────────────
      # 'mock' (dev/test), 'clicksign' (produção). Lista validada no model.
      t.string :provider, null: false, default: 'mock'
      t.string :external_id, limit: 128 # envelope_id no provider
      t.string :signing_url, limit: 2048 # URL hosted pelo provider pro signer

      # ─── Estado da assinatura ───────────────────────────────────────────
      # pending  — criado mas não enviado pro provider ainda
      # sent     — provider confirmou criação do envelope; convite enviado
      # viewed   — signer abriu o link (event opcional, depende do provider)
      # signed   — signer completou; aguardando download do doc assinado
      # completed — doc assinado baixado e arquivado; processo finalizado
      # cancelled — clínica cancelou o envelope antes de assinar
      # failed   — erro irrecuperável (validação do provider, etc.)
      # expired  — envelope passou da validade sem assinatura
      t.string :status, null: false, default: 'pending'

      # ─── Signer ─────────────────────────────────────────────────────────
      t.string :signer_name, limit: 200
      t.string :signer_email, limit: 255
      t.string :signer_phone, limit: 32
      t.string :signer_cpf, limit: 14

      # ─── Mensagem opcional ao signer ────────────────────────────────────
      t.text :message

      # ─── Timeline ───────────────────────────────────────────────────────
      t.datetime :sent_at
      t.datetime :viewed_at
      t.datetime :signed_at
      t.datetime :completed_at
      t.datetime :cancelled_at
      t.datetime :expires_at

      # ─── Auditoria ──────────────────────────────────────────────────────
      # JSONB com eventos provenientes do provider (webhook events crus
      # + nossas transições internas). Cada entry: { at, kind, ip, ua, meta }.
      t.jsonb :audit_log, null: false, default: []

      # ─── Validação de integridade ───────────────────────────────────────
      # SHA-256 do PDF original enviado pra assinatura. Permite comparar
      # com o PDF assinado retornado pra detectar manipulação.
      t.string :original_pdf_hash, limit: 64
      # SHA-256 do PDF FINAL assinado retornado pelo provider.
      t.string :signed_pdf_hash, limit: 64

      t.timestamps
    end

    # Lookup principal: requests pendentes/em-progresso da clínica.
    add_index :signature_requests, [:account_id, :status],
              name: 'idx_signature_requests_account_status'

    # Webhook lookup: provider + external_id (Clicksign manda envelope_id
    # no payload). Index unique parcial pra detectar duplicate webhooks.
    add_index :signature_requests, [:provider, :external_id],
              unique: true,
              where: 'external_id IS NOT NULL',
              name: 'idx_signature_requests_external_id_unique'

    # Listagem dentro do Document/ConsentRecord — geralmente 1-3 rows por
    # signable, então é leve.
    # (já indexado via `polymorphic: true, index: true` acima)
  end
end
