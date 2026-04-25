class Financial::ReceivablesForecastService
  WEEKS = [
    { label_key: 'S1', days: 1..7 },
    { label_key: 'S2', days: 8..14 },
    { label_key: 'S3', days: 15..21 },
    { label_key: 'S4', days: 22..31 }
  ].freeze

  METHODS = %w[pix dinheiro cartao_debito cartao_credito boleto convenio outro].freeze

  def initialize(account:, month: nil)
    @account = account
    ref = month.present? ? Date.parse("#{month}-01") : Time.zone.today.next_month.beginning_of_month
    @start_date = ref.beginning_of_month
    @end_date   = ref.end_of_month
  end

  def call
    raw = pending_receivables
    build_weeks(raw)
  end

  private

  def pending_receivables
    @account.account_transactions.kept
            .where(entry_type: 'entrada', status: 'pendente')
            .where(due_date: @start_date..@end_date)
            .select(:due_date, :amount, :payment_method)
  end

  def build_weeks(records)
    WEEKS.map do |wk|
      range  = wk[:days]
      subset = records.select { |r| range.include?(r.due_date.day) }
      totals = week_totals(subset)
      totals.merge(semana: week_label(wk, range), total: totals.values.sum)
    end
  end

  def week_totals(subset)
    totals = METHODS.index_with { |_m| 0.0 }
    subset.each { |r| totals[normalize_method(r.payment_method)] += r.amount.to_f }
    totals
  end

  def week_label(week_def, range)
    day_end = [range.last, @end_date.day].min
    "#{week_def[:label_key]} (#{format('%02d', range.first)}-#{format('%02d', day_end)})"
  end

  METHOD_MAP = {
    'pix' => 'pix',
    'dinheiro' => 'dinheiro',
    'cash' => 'dinheiro',
    'debito' => 'cartao_debito',
    'credito' => 'cartao_credito',
    'credit' => 'cartao_credito',
    'boleto' => 'boleto',
    'convenio' => 'convenio',
    'plano' => 'convenio'
  }.freeze

  def normalize_method(method)
    return 'outro' if method.blank?

    m = method.to_s.downcase
    METHOD_MAP.find { |k, _v| m.include?(k) }&.last || 'outro'
  end
end
