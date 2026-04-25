class Financial::ProfessionalRevenueService
  def initialize(account:, period: nil)
    @account = account
    @today   = Time.zone.today
    @ref     = period.present? ? Date.parse("#{period}-01") : @today.beginning_of_month
  end

  def call
    rows = revenue_rows
    rows.map { |row| build_row(row) }.sort_by { |r| -r[:margem] }
  end

  private

  def period_range
    @ref.beginning_of_month..@ref.end_of_month.end_of_day
  end

  def revenue_rows
    @account.account_transactions.kept
            .where(entry_type: 'entrada')
            .where.not(professional_id: nil)
            .joins('INNER JOIN users ON users.id = account_transactions.professional_id')
            .where(received_at: period_range)
            .group('users.id', 'users.name')
            .select(
              'users.id AS professional_id',
              'users.name AS nome',
              'SUM(CASE WHEN account_transactions.status = \'recebido\' THEN account_transactions.amount ELSE 0 END) AS recebido',
              'SUM(account_transactions.amount) AS producao'
            )
  end

  def build_row(row)
    custo = commission_cost(row.professional_id)
    margem = row.recebido.to_f - custo
    margem_pct = row.recebido.to_f.positive? ? (margem / row.recebido.to_f * 100).round(1) : 0.0
    {
      professional_id: row.professional_id,
      nome: row.nome,
      producao: row.producao.to_f.round(2),
      recebido: row.recebido.to_f.round(2),
      custo_total: custo.round(2),
      margem: margem.round(2),
      margem_pct: margem_pct
    }
  end

  def commission_cost(professional_id)
    @account.account_transactions.kept
            .where(entry_type: 'saida', professional_id: professional_id)
            .where('description ILIKE ? OR description ILIKE ?', '%comissão%', '%comissao%')
            .where(paid_at: period_range)
            .sum(:amount).to_f
  end
end
