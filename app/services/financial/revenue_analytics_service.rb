class Financial::RevenueAnalyticsService
  COMPOSITION_KEYS = %w[particular convenio plano outro].freeze

  PAYMENT_SOURCE_LABELS = {
    'particular' => 'Particular',
    'convenio'   => 'Convênio',
    'plano'      => 'Plano de Saúde',
    'outro'      => 'Outros'
  }.freeze

  def initialize(account:)
    @account = account
    @today   = Time.zone.today
  end

  # Gráfico 10 — ticket médio mensal (últimos N meses)
  def average_ticket(months: 12, professional_id: nil)
    months.downto(1).map do |n|
      ref   = @today - (n - 1).months
      mes   = ref.strftime('%Y-%m')
      scope = ticket_scope(ref, professional_id)
      receita_total = scope.sum(:amount).to_f
      atendimentos  = scope.where.not(patient_id: nil).distinct.count(:patient_id)
      ticket_medio  = atendimentos.positive? ? (receita_total / atendimentos).round(2) : 0.0
      { mes: mes, ticket_medio: ticket_medio, atendimentos: atendimentos, receita_total: receita_total.round(2) }
    end
  end

  # Gráfico 12 — composição de receita (donut atual + histórico empilhado)
  def revenue_composition(months: 6)
    atual     = composition_for_month(@today.beginning_of_month)
    historico = months.downto(1).map do |n|
      ref = @today - (n - 1).months
      composition_for_month(ref.beginning_of_month).merge(mes: ref.strftime('%Y-%m'))
    end
    { atual: atual, historico: historico }
  end

  private

  def ticket_scope(ref, professional_id)
    scope = @account.account_transactions.kept
                    .where(entry_type: 'entrada', status: 'recebido')
                    .where(received_at: ref.beginning_of_month..ref.end_of_month.end_of_day)
    scope = scope.where(professional_id: professional_id) if professional_id.present?
    scope
  end

  def composition_for_month(start_of)
    rows = @account.account_transactions.kept
                   .where(entry_type: 'entrada', status: 'recebido')
                   .where(received_at: start_of..start_of.end_of_month.end_of_day)
                   .group(:payment_source)
                   .sum(:amount)
                   .transform_values(&:to_f)

    COMPOSITION_KEYS.index_with { |k| rows.fetch(k, 0.0).round(2) }
  end
end
