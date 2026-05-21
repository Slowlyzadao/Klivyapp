# Sprint L — Teleconsulta: proposta de evolução SOAP gerada por LLM.
#
# Estados:
#   pending_review ─ acabou de ser gerada, aguardando dentista revisar
#   edited         ─ dentista editou mas ainda não aprovou
#   approved       ─ aprovada → cria ClinicalNote(source='telemed_ai')
#   rejected       ─ descartada (reviewer_notes deve explicar)
#
# `approve!` é o ponto crítico que cruza a fronteira "IA → prontuário". Cria
# a ClinicalNote em transação atômica, link bidirecional, e marca a si
# própria como aprovada — qualquer falha aborta tudo.
class ProposedEvolution < ApplicationRecord
  STATUSES = %w[pending_review edited approved rejected].freeze

  # Audit Fase 3 — LGPD (#35). `raw_markdown` é o SOAP rendered em texto;
  # `reviewer_notes` armazena justificativa de rejeição (pode citar
  # condição do paciente). Ambos são PII clínica.
  # Mesma config global do TelemedRecording (config/application.rb) —
  # `support_unencrypted_data = true` permite migração suave.
  encrypts :raw_markdown
  encrypts :reviewer_notes

  belongs_to :telemed_recording
  belongs_to :clinical_note, optional: true
  belongs_to :reviewed_by,   class_name: 'User', optional: true

  has_one :agenda_event, through: :telemed_recording
  has_one :account,      through: :telemed_recording

  validates :provider, presence: true
  validates :status,   inclusion: { in: STATUSES }

  scope :pending,  -> { where(status: 'pending_review') }
  scope :approved, -> { where(status: 'approved') }
  scope :recent,   -> { order(created_at: :desc) }

  # Aprovar = criar ClinicalNote com source='telemed_ai'. Delegado pra
  # ProposedEvolutionApprovalService (audit Fase 3 — extraído pra
  # isolar a costura IA→prontuário do model de domínio puro). Retorna
  # a ClinicalNote criada (mantém contrato anterior pro controller).
  def approve!(actor:)
    Telemed::ProposedEvolutionApprovalService.call(evolution: self, actor: actor).clinical_note
  end

  # Rejeitar não cria nota. Reviewer_notes obrigatório pra trilha CFM.
  def reject!(actor:, reason:)
    raise 'Justificativa obrigatória ao rejeitar' if reason.to_s.strip.blank?
    raise 'Proposta já aprovada não pode ser rejeitada' if status == 'approved'

    update!(
      status: 'rejected',
      reviewer_notes: reason.to_s.strip,
      reviewed_by: actor,
      reviewed_at: Time.current
    )
  end

  # Update parcial do SOAP/markdown sem mudar status — usado quando dentista
  # edita antes de aprovar. Marca como `edited` na primeira modificação.
  def apply_edit!(soap_structure: nil, raw_markdown: nil, actor:)
    raise 'Proposta já aprovada' if status == 'approved'

    attrs = {}
    attrs[:soap_structure] = soap_structure if soap_structure.present?
    attrs[:raw_markdown]   = raw_markdown   if raw_markdown.present?
    attrs[:status]         = 'edited' if status == 'pending_review'
    attrs[:reviewed_by]    = actor
    attrs[:reviewed_at]    = Time.current

    update!(attrs)
  end

end
