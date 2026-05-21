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

  # Aprovar = criar ClinicalNote com source='telemed_ai'. Transação garante
  # que ou os dois lados ficam atualizados ou nada muda. ClinicalNote nasce
  # como `draft` — assinatura digital fica como um segundo passo explícito.
  def approve!(actor:)
    raise 'Proposta já aprovada' if status == 'approved'
    raise 'Proposta rejeitada não pode ser aprovada' if status == 'rejected'

    transaction do
      note = build_clinical_note_for(actor)
      note.save!

      update!(
        status: 'approved',
        clinical_note: note,
        reviewed_by: actor,
        reviewed_at: Time.current
      )
      # Link bidirecional — `clinical_notes.proposed_evolution_id` aponta de
      # volta. Setamos depois do save pra evitar circularidade na construção.
      note.update_column(:proposed_evolution_id, id)
      note
    end
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

  private

  # Mapeia SOAP da proposta pras colunas existentes em ClinicalNote
  # (complaint_of_day, assessment, conduct, guidance_given). PRD §7.4 +
  # ClinicalNote schema:
  #
  #   S — Subjetivo   → complaint_of_day
  #   O — Objetivo    → assessment (parte inicial)  ─ tb concat em assessment
  #   A — Avaliação   → assessment (hipótese diagnóstica)
  #   P — Plano       → conduct
  #
  # Mantemos `raw_markdown` salvo no ProposedEvolution pra recuperar texto
  # completo sem perdas se o dentista precisar reconciliar depois.
  def build_clinical_note_for(actor)
    event   = telemed_recording.agenda_event
    patient = Patient.find_by(contact_id: event.contact_id, account_id: event.account_id)
    raise 'Paciente do agendamento não encontrado' unless patient

    soap = soap_structure.is_a?(Hash) ? soap_structure : {}
    subjetivo = soap['subjetivo'].to_s.strip
    objetivo  = soap['objetivo'].to_s.strip
    avaliacao = soap['avaliacao'].to_s.strip
    plano     = soap['plano'].to_s.strip

    assessment_parts = []
    assessment_parts << "[Objetivo]\n#{objetivo}"   if objetivo.present?
    assessment_parts << "[Avaliação]\n#{avaliacao}" if avaliacao.present?

    ClinicalNote.new(
      account_id:       event.account_id,
      patient_id:       patient.id,
      professional_id:  event.user_id || actor.id,
      appointment_id:   event.id,
      note_date:        (event.starts_at&.to_date || Time.current.to_date),
      complaint_of_day: subjetivo.presence,
      assessment:       assessment_parts.join("\n\n").presence,
      conduct:          plano.presence,
      status:           'draft',
      source:           'telemed_ai'
    )
  end
end
