# Sprint L — Gera proposta de evolução clínica via LLM.
#
# Enfileirado pelo TranscribeRecordingJob quando a transcrição fica pronta.
# Monta contexto do paciente (alergias, medicações, histórico recente),
# chama o EvolutionProvider configurado (PRD §5.3 — default Claude Sonnet 4.6),
# persiste em ProposedEvolution e move o recording pra `ready`.
#
# Falhas: 3 retries com backoff. Esgotado, marca `failed` no recording mas
# NÃO falha o transcript (transcript fica disponível pra UI mesmo sem
# evolução — dentista pode escrever manualmente).
module Telemed
  class GenerateEvolutionJob < ApplicationJob
    queue_as :default

    # Mesmo padrão do TranscribeRecordingJob: `retry_on` único, sem duplicar
    # exhaustion check no rescue. `bump_retry!` só registra contador.
    retry_on StandardError, wait: :exponentially_longer, attempts: 3 do |job, exception|
      recording = TelemedRecording.find_by(id: job.arguments.first)
      next if recording.nil? || recording.failed?

      recording.fail!("Geração de evolução falhou após retries (#{exception.class}): #{exception.message}")
    end
    discard_on ActiveJob::DeserializationError

    def perform(recording_id)
      recording = TelemedRecording.find_by(id: recording_id)
      return unless recording
      return if recording.ready? || recording.failed?
      return if recording.transcript_text.blank?

      recording.update!(status: 'evolving')

      provider_name   = resolve_provider_name(recording.account)
      provider        = EvolutionProvider.for(provider_name)
      patient_context = build_patient_context(recording.agenda_event)

      result = provider.call(
        transcript:      recording.transcript_text,
        patient_context: patient_context
      )

      ProposedEvolution.create!(
        telemed_recording: recording,
        provider:          result.provider,
        soap_structure:    result.soap_structure || {},
        raw_markdown:      result.raw_markdown,
        attention_points:  result.attention_points || [],
        input_tokens:      result.input_tokens,
        output_tokens:     result.output_tokens,
        status:            'pending_review'
      )

      recording.update!(status: 'ready')
      # Notificação ao dentista — push/email/in-app. MVP: registro em
      # PatientPortalNotification do dentista (já existe na Sprint E).
      notify_dentist(recording)

      # Sprint L — enforça quota da clínica (default 15 gravações ativas).
      # Arquiva as mais antigas se exceder. ClinicalNote permanece intacta.
      EnforceRecordingQuotaJob.perform_later(recording.account_id)
    rescue StandardError
      recording&.bump_retry!
      raise
    end

    private

    def resolve_provider_name(account)
      setting = account&.patient_portal_setting
      cfg     = setting&.telemedicine_recording.is_a?(Hash) ? setting.telemedicine_recording : {}
      cfg['ai_provider'].presence || EvolutionProvider::DEFAULT_PROVIDER
    end

    # Monta hash usado no prompt. Mantemos campos opcionais — provider
    # tolera ausência ("nenhuma registrada"). Anamneses e ClinicalNotes
    # já existentes alimentam histórico relevante.
    def build_patient_context(event)
      patient = Patient.find_by(contact_id: event.contact_id, account_id: event.account_id)
      return {} unless patient

      last_notes = ClinicalNote
                     .active.where(patient_id: patient.id)
                     .order(note_date: :desc).limit(3)
                     .map { |n| "#{n.note_date}: #{n.assessment.to_s.first(200)}" }

      {
        name:        patient.contact&.name || patient.full_name,
        age:         patient_age(patient),
        allergies:   safe_attr(patient, :allergies),
        medications: safe_attr(patient, :current_medications),
        history:     last_notes.join(' | ').presence
      }
    end

    def patient_age(patient)
      dob = safe_attr(patient, :birth_date) || safe_attr(patient, :date_of_birth)
      return nil unless dob

      now = Time.current.to_date
      age = now.year - dob.year
      age -= 1 if (now.month < dob.month) || (now.month == dob.month && now.day < dob.day)
      age
    end

    # Patient pode ter colunas diferentes entre clínicas (custom_attributes
    # JSONB ou colunas formais). Tenta column → custom_attributes → nil.
    def safe_attr(patient, attr)
      return patient.public_send(attr) if patient.respond_to?(attr) && patient.has_attribute?(attr)

      patient.try(:custom_attributes).is_a?(Hash) ? patient.custom_attributes[attr.to_s] : nil
    end

    # Notificação simples — usa o canal in-app do portal (Sprint E). Falha
    # silenciosa se o modelo não estiver disponível (CE pode não ter).
    def notify_dentist(recording)
      return unless defined?(PatientPortalNotification)

      user = recording.agenda_event.user
      return unless user

      PatientPortalNotification.create!(
        account_id:  recording.account_id,
        user_id:     user.id,
        kind:        'telemed_evolution_ready',
        title:       'Evolução de teleconsulta pronta para revisão',
        body:        "Consulta de #{recording.agenda_event.title} aguardando aprovação",
        metadata:    { telemed_recording_id: recording.id, agenda_event_id: recording.agenda_event_id }
      )
    rescue StandardError => e
      Rails.logger.warn("[GenerateEvolutionJob] notify_dentist falhou: #{e.message}")
    end
  end
end
