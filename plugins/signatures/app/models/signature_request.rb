# Pedido de assinatura eletrônica de um documento (Document ou ConsentRecord).
# Cada row é um envelope no provider externo (Clicksign, etc.).
#
# Máquina de estados:
#   pending → sent → viewed → signed → completed
#              ↓
#              ↓→ cancelled
#              ↓→ failed
#              ↓→ expired
#
# Transições são chamadas via métodos `mark_sent!`, `mark_signed!` etc. —
# não usamos gem de state machine pra evitar dependência. Cada transição
# registra entrada em `audit_log` (JSONB).
class SignatureRequest < ApplicationRecord
  PROVIDERS = %w[mock clicksign].freeze
  STATUSES  = %w[pending sent viewed signed completed cancelled failed expired].freeze
  TERMINAL_STATUSES = %w[completed cancelled failed expired].freeze

  belongs_to :account
  belongs_to :signable, polymorphic: true
  belongs_to :requested_by_user, class_name: 'User', optional: true

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :status,   presence: true, inclusion: { in: STATUSES }
  validates :signer_email, presence: true,
                           format: { with: URI::MailTo::EMAIL_REGEXP },
                           if: :provider_needs_email?
  validates :signer_name, presence: true, length: { maximum: 200 }
  validates :external_id, uniqueness: { scope: :provider }, allow_nil: true

  scope :pending,   -> { where(status: 'pending') }
  scope :sent,      -> { where(status: 'sent') }
  scope :in_progress, -> { where(status: %w[pending sent viewed]) }
  scope :terminal,  -> { where(status: TERMINAL_STATUSES) }

  # ── Helpers de estado ─────────────────────────────────────────────────
  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  # ── Transições explícitas ─────────────────────────────────────────────
  # Cada transição valida origem permitida + persiste timestamp + log.
  # Caller deve passar `meta:` com infos relevantes (ip, ua, event_kind do
  # webhook, etc.) que vão pro audit_log.

  def mark_sent!(external_id:, signing_url: nil, meta: {})
    transition_to!('sent',
                   from: %w[pending],
                   updates: {
                     external_id: external_id,
                     signing_url: signing_url,
                     sent_at: Time.current
                   },
                   meta: meta)
  end

  def mark_viewed!(meta: {})
    transition_to!('viewed',
                   from: %w[sent],
                   updates: { viewed_at: Time.current },
                   meta: meta)
  end

  def mark_signed!(signed_pdf_hash: nil, meta: {})
    transition_to!('signed',
                   from: %w[sent viewed],
                   updates: {
                     signed_at: Time.current,
                     signed_pdf_hash: signed_pdf_hash
                   },
                   meta: meta)
  end

  # `complete!` é chamado depois que baixamos o PDF assinado do provider
  # e o anexamos ao Document/ConsentRecord (job assíncrono).
  def mark_completed!(meta: {})
    transition_to!('completed',
                   from: %w[signed],
                   updates: { completed_at: Time.current },
                   meta: meta)
  end

  def mark_cancelled!(reason: nil, meta: {})
    meta = meta.merge(reason: reason).compact
    transition_to!('cancelled',
                   from: %w[pending sent viewed],
                   updates: { cancelled_at: Time.current },
                   meta: meta)
  end

  def mark_failed!(reason:, meta: {})
    meta = meta.merge(reason: reason)
    transition_to!('failed',
                   from: STATUSES - TERMINAL_STATUSES,
                   updates: {},
                   meta: meta)
  end

  def mark_expired!(meta: {})
    transition_to!('expired',
                   from: %w[pending sent viewed],
                   updates: {},
                   meta: meta)
  end

  # Append-only log de eventos (não substitui histórico). Útil pra
  # auditoria LGPD e debug de webhooks.
  def append_audit!(kind:, meta: {})
    entry = {
      'at' => Time.current.iso8601,
      'kind' => kind.to_s,
      'meta' => meta.compact
    }
    self.audit_log = (audit_log || []) + [entry]
    save!
  end

  private

  def provider_needs_email?
    %w[clicksign].include?(provider)
  end

  def transition_to!(new_status, from:, updates:, meta:)
    unless from.include?(status)
      raise InvalidTransition, "Cannot transition from #{status} to #{new_status}"
    end

    entry = {
      'at' => Time.current.iso8601,
      'kind' => "transition.#{new_status}",
      'from' => status,
      'meta' => meta.compact
    }

    self.audit_log = (audit_log || []) + [entry]
    assign_attributes(updates.merge(status: new_status))
    save!
  end

  class InvalidTransition < StandardError; end
end
