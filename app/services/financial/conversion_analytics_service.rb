class Financial::ConversionAnalyticsService
  ETAPAS = %i[leads agendados comparecidos orcados fechados].freeze

  # Mapeamento dos status do AgendaEvent para cada etapa do funil
  COMPARECIDOS_STATUS = %w[arrived in_progress completed].freeze
  ORCADOS_STATUS      = %w[completed].freeze  # completed = consulta realizada/orçada
  FECHADOS_STATUS     = %w[completed].freeze  # sobrepõe com completed — dado que não há status separado ainda

  def initialize(account:, months: 3)
    @account = account
    @months  = months.to_i
    @range   = @months.months.ago.beginning_of_month..Time.zone.now
  end

  def call
    values = fetch_values
    etapas = build_etapas(values)
    pior   = pior_queda(etapas)
    { etapas: etapas, pior_queda: pior, periodo_meses: @months }
  end

  def fetch_values
    [
      count_leads,
      count_agendados,
      count_comparecidos,
      count_orcados,
      count_fechados
    ]
  end

  def build_etapas(values)
    labels = %w[Leads Agendados Comparecidos Orçados Fechados]
    labels.each_with_index.map do |label, i|
      valor    = values[i]
      anterior = i.zero? ? nil : values[i - 1]
      taxa     = anterior&.positive? ? (valor.to_f / anterior * 100).round(1) : nil
      { etapa: label, valor: valor, taxa_conversao: taxa }
    end
  end

  def pior_queda(etapas)
    etapas[1..].select { |e| e[:taxa_conversao] }.min_by { |e| e[:taxa_conversao] }&.dig(:etapa)
  end

  private

  def count_leads
    @account.contacts.where(created_at: @range).count
  end

  def agenda_scope
    AgendaEvent.where(account_id: @account.id, starts_at: @range)
  end

  def consultation_scope
    agenda_scope.where(event_type: 'consultation')
  end

  # Agendados = todos os eventos de consulta no período
  def count_agendados
    consultation_scope.count
  end

  # Comparecidos = chegou, em atendimento ou completado (somente consultas)
  def count_comparecidos
    consultation_scope.where(status: COMPARECIDOS_STATUS).count
  end

  # Orçados = consulta concluída (potencial geração de orçamento)
  def count_orcados
    consultation_scope.where(status: ORCADOS_STATUS).count
  end

  # Fechados = consultas concluídas que geraram receita efetiva
  def count_fechados
    completed_contact_ids = consultation_scope
      .where(status: 'completed')
      .where.not(contact_id: nil)
      .pluck(:contact_id)

    return 0 if completed_contact_ids.empty?

    patient_ids = Patient.where(account_id: @account.id, contact_id: completed_contact_ids).pluck(:id)
    return 0 if patient_ids.empty?

    @account.account_transactions.kept
      .where(entry_type: 'entrada', status: 'recebido')
      .where(patient_id: patient_ids)
      .where(received_at: @range)
      .distinct
      .count(:patient_id)
  end
end
