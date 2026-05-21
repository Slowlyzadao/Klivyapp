# Sprint L — Gravação audio-only de uma teleconsulta LiveKit Egress.
#
# Estratégia de pipeline (PRD §5.1 — refinada 2026-05-20):
#   - 3 gravações paralelas: doctor-temp + patient-temp + composite (audio)
#   - Whisper × 2 nos temps → diarização perfeita → merge → DELETA temps
#   - Mantém apenas `composite_audio_key` no longo prazo (~28 MB/h)
#
# Estados:
#   pending      ─ recording iniciado, aguardando upload
#   recording    ─ LiveKit confirmou início dos 3 egress jobs
#   uploaded     ─ os 3 arquivos chegaram no R2
#   transcribing ─ Whisper rodando nos 2 temps
#   transcribed  ─ texto+segments persistidos, temps deletados
#   evolving     ─ GenerateEvolutionJob rodando
#   ready        ─ ProposedEvolution disponível
#   failed       ─ falha terminal
#
# Quota / Purge:
#   - `archive!` marca archived_at + deleta composite do R2.
#   - Registro NÃO é destruído — auditoria + bookmark de "houve consulta".
#   - ClinicalNote derivada NÃO é tocada (regra clínica: prontuário permanece
#     20 anos independente do destino do áudio).
class TelemedRecording < ApplicationRecord
  STATUSES = %w[pending recording uploaded transcribing transcribed evolving ready failed].freeze
  KINDS    = %w[audio video].freeze
  MAX_RETRIES = 3

  belongs_to :agenda_event
  belongs_to :account
  has_many   :proposed_evolutions, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :recording_kind, inclusion: { in: KINDS }
  validate  :at_least_one_egress_id_after_pending

  scope :ready,         -> { where(status: 'ready') }
  scope :failed,        -> { where(status: 'failed') }
  scope :active_storage, -> { where(archived_at: nil) } # nao confundir com ActiveStorage do Rails
  scope :archived,       -> { where.not(archived_at: nil) }
  scope :for_account,    ->(account_id) { where(account_id: account_id) }
  scope :recent,         -> { order(created_at: :desc) }

  # Webhook do LiveKit Egress reporta status por egress_id. Cada gravação
  # tem 3 ids potenciais (doctor isolated, patient isolated, composite).
  scope :by_egress_id, ->(id) {
    where('doctor_egress_id = :id OR patient_egress_id = :id OR composite_egress_id = :id', id: id)
  }

  # Última proposta de evolução (UI default).
  def latest_proposed_evolution
    proposed_evolutions.order(created_at: :desc).first
  end

  # Helpers de estado
  def ready?         = status == 'ready'
  def failed?        = status == 'failed'
  def transcribing?  = status == 'transcribing'
  def transcribed?   = status == 'transcribed'
  def archived?      = archived_at.present?
  def in_pipeline?   = STATUSES.include?(status) && !ready? && !failed?

  # Egress IDs presentes — usado pelo webhook pra saber se TODOS terminaram.
  def expected_egress_ids
    [doctor_egress_id, patient_egress_id, composite_egress_id].compact
  end

  # Identifica qual role um egress_id pertence — webhook usa pra preencher
  # a coluna correta de storage key (doctor_audio_key, patient_audio_key,
  # composite_audio_key).
  def role_for_egress_id(egress_id)
    return 'doctor'    if doctor_egress_id    == egress_id
    return 'patient'   if patient_egress_id   == egress_id
    return 'composite' if composite_egress_id == egress_id

    nil
  end

  # Todas as 3 keys finalizaram no R2? Trigger da TranscribeJob.
  def all_files_uploaded?
    doctor_audio_key.present? && patient_audio_key.present? && composite_audio_key.present?
  end

  # Apenas o composite — pos transcribe, doctor/patient são deletados.
  def composite_only?
    composite_audio_key.present? && doctor_audio_key.blank? && patient_audio_key.blank?
  end

  def fail!(reason)
    update_columns(
      status: 'failed',
      failure_reason: reason.to_s.first(2000),
      updated_at: Time.current
    )
  end

  def bump_retry!
    update_columns(retry_count: retry_count + 1, updated_at: Time.current)
  end

  def retries_exhausted?
    retry_count >= MAX_RETRIES
  end

  # Arquiva: deleta arquivo R2 + marca timestamp. Registro permanece pra
  # audit trail. ClinicalNote derivada **não** é tocada.
  # Caller (job de quota ou purge) tipicamente envolve em transaction.
  def archive!(reason: nil)
    return if archived?

    keys = [composite_audio_key, doctor_audio_key, patient_audio_key].compact
    keys.each do |key|
      begin
        Telemed::RecordingStorage.delete(key)
      rescue StandardError => e
        Rails.logger.warn("[TelemedRecording##{id}#archive!] R2 delete falhou key=#{key}: #{e.message}")
      end
    end

    update!(
      archived_at:         Time.current,
      composite_audio_key: nil,
      doctor_audio_key:    nil,
      patient_audio_key:   nil,
      failure_reason:      reason.presence
    )
  end

  def to_summary_hash
    {
      id: id,
      agenda_event_id: agenda_event_id,
      status: status,
      recording_kind: recording_kind,
      duration_seconds: duration_seconds,
      transcript_provider: transcript_provider,
      has_transcript: transcript_text.present?,
      has_evolution: latest_proposed_evolution&.id.present?,
      has_audio: composite_audio_key.present?,
      archived: archived?,
      archived_at: archived_at,
      evolution_status: latest_proposed_evolution&.status,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  # Em pending aceita zero ids (registro nasce vazio). Em qualquer outro
  # estado precisa ter ao menos 1 dos 3 egress_ids preenchidos.
  def at_least_one_egress_id_after_pending
    return if status == 'pending'
    return if [doctor_egress_id, patient_egress_id, composite_egress_id].any?(&:present?)

    errors.add(:base, 'Pelo menos um egress_id é obrigatório após status pending')
  end
end
