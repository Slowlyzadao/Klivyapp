# Fase 6: candidatos do trigger `service_recall` (reativação por serviço).
# Dado uma regra com `agenda_service_id` + intervalo (`recall_interval_value`
# em days/weeks/months), acha pacientes cuja ÚLTIMA sessão assinada daquele
# serviço completou o intervalo agora — e que ainda não reagendaram.
#
# Isolado do CandidateFinder porque lê models de OUTROS plugins (patients:
# SessionLog/TreatmentItem/Patient; agenda: AgendaEvent) — acesso defensivo
# via `defined?`, na convenção da governança da Bea (§1.4). Tudo escopado
# por `account_id`.
#
# `target_at = performed_at + intervalo` é determinístico por sessão, então
# a janela de captura (RECALL_WINDOW) pode ser ampla sem duplicar: o índice
# único de FollowUpExecution dedupa. A janela tolera gaps do cron e evita
# disparar recalls muito antigos (anti-blast no cold start).
class AiAgent::FollowUps::ServiceRecallFinder
  RECALL_WINDOW = 2.days

  def initialize(rule, step, now: Time.current)
    @rule = rule
    @step = step
    @now = now
  end

  def call
    return [] unless ready?

    interval = @rule.recall_interval
    # performed_at tal que (performed_at + interval) caiu nas últimas RECALL_WINDOW.
    window = (@now - interval - RECALL_WINDOW)..(@now - interval)
    candidate_sessions(window).filter_map { |session| candidate_for(session, interval) }
  end

  private

  def ready?
    @rule.service_recall? &&
      @rule.agenda_service_id.present? &&
      @rule.recall_interval_value.to_i.positive? &&
      defined?(::SessionLog) && defined?(::Patient)
  end

  # Sessões ASSINADAS do serviço-alvo, com performed_at na janela.
  def candidate_sessions(window)
    ::SessionLog
      .signed
      .joins(:treatment_item)
      .where(account_id: @rule.account_id, performed_at: window)
      .where(treatment_items: { agenda_service_id: @rule.agenda_service_id })
      .to_a
  end

  def candidate_for(session, interval)
    return nil unless latest_for_patient?(session)

    # Patient escopado por account_id (defesa multi-tenant), embora a
    # sessão já seja da conta.
    patient = ::Patient.find_by(id: session.patient_id, account_id: @rule.account_id)
    contact_id = patient&.contact_id
    return nil if contact_id.blank?
    return nil if rebooked_service?(contact_id, session.patient_id)

    {
      contact_id: contact_id,
      conversation_id: nil,
      agenda_event_id: nil,
      step_id: @step.id,
      anchor_at: session.performed_at + interval,
      target_at: session.performed_at + interval
    }
  end

  # É a última sessão assinada desse paciente pra esse serviço? Se houver
  # uma mais recente, o paciente já voltou — não reativa agora.
  def latest_for_patient?(session)
    latest = ::SessionLog
             .signed
             .joins(:treatment_item)
             .where(account_id: @rule.account_id, patient_id: session.patient_id)
             .where(treatment_items: { agenda_service_id: @rule.agenda_service_id })
             .maximum(:performed_at)
    latest.nil? || latest <= session.performed_at
  end

  # Já tem consulta futura DESSE serviço marcada (scheduled/confirmed)?
  # Ignora eventos soft-deletados (deleted_at) e cobre os dois vínculos:
  # por contact_id E por custom_attributes.patient_id (eventos criados
  # pela UI da agenda costumam ter contact_id nil, com o paciente no
  # custom_attributes).
  def rebooked_service?(contact_id, patient_id)
    return false unless defined?(::AgendaEvent)

    base = ::AgendaEvent
           .where(account_id: @rule.account_id, agenda_service_id: @rule.agenda_service_id,
                  status: %w[scheduled confirmed], deleted_at: nil)
           .where('starts_at > ?', @now)

    return true if base.exists?(contact_id: contact_id)

    base.exists?(["agenda_events.custom_attributes ->> 'patient_id' = ?", patient_id.to_s])
  rescue StandardError
    # custom_attributes pode não existir em schemas antigos — degrada pro
    # check por contact_id (já avaliado acima).
    false
  end
end
