# frozen_string_literal: true

# PDF: Comissões do Profissional.
class Financial::Pdf::CommissionsPdf < Financial::Pdf::BasePdf
  def initialize(account:, professional:, period:)
    super(account: account)
    @professional = professional
    @period       = period
  end

  private

  def build
    result = Financial::CommissionCalculator.new(
      account: account,
      professional: @professional,
      period: @period
    ).call

    transactions = result[:transactions] || []
    total        = result[:total_commission] || 0

    draw_header(
      title: 'Relatório de Comissões',
      subtitle: "Profissional: #{@professional.name}",
      period_label: "#{fmt_date(@period.first)} a #{fmt_date(@period.last)}"
    )

    draw_kpi_cards([
      { label: 'Profissional',     value: @professional.name,      color: BRAND_BLUE,  bg: 'eff6ff' },
      { label: 'Transações',       value: transactions.size.to_s,  color: BRAND_GRAY,  bg: 'f8fafc' },
      { label: 'Total Faturado',   value: fmt(transactions.sum { |t| t[:amount] }), color: BRAND_BLUE, bg: 'eff6ff' },
      { label: 'Total Comissão',   value: fmt(total),              color: BRAND_GREEN, bg: 'f0fdf4' }
    ])

    draw_section_title('Detalhamento das Comissões')
    draw_commissions_table(transactions)

    ensure_space(100)
    draw_section_title('Resumo por Tipo de Regra')
    draw_rule_summary(transactions)

    ensure_space(100)
    draw_section_title('Resumo por Categoria')
    draw_category_commission_summary(transactions)

    draw_total_row('TOTAL DE COMISSÕES', fmt(total), color: BRAND_GREEN)
  end

  def draw_commissions_table(transactions)
    headers = ['Descrição', 'Categoria', 'Data', 'Valor Transação', 'Regra', 'Comissão']

    rows = transactions.map do |tx|
      [
        truncate_text(tx[:description] || '—', 30),
        tx[:category_name] || '—',
        fmt_date(tx[:received_at]),
        fmt(tx[:amount]),
        rule_label(tx[:rule_type], tx[:rule_value]),
        fmt(tx[:commission_amount])
      ]
    end

    draw_styled_table(headers, rows,
                      number_columns: [3, 5],
                      col_widths: { 0 => 110, 1 => 80, 2 => 62, 3 => 75, 4 => 80, 5 => 75 },
                      empty_message: 'Nenhuma comissão encontrada no período.')
  end

  def draw_rule_summary(transactions)
    groups = transactions.group_by { |t| t[:rule_type] }
    rows = groups.map do |type, txs|
      total_comm = txs.sum { |t| t[:commission_amount] }
      total_base = txs.sum { |t| t[:amount] }
      avg_pct = total_base > 0 ? (total_comm / total_base * 100).round(1) : 0.0
      [rule_type_label(type), txs.size.to_s, fmt(total_base), fmt(total_comm), "#{avg_pct}%"]
    end

    draw_styled_table(
      ['Tipo de Regra', 'Qtd', 'Base', 'Comissão', '% Médio'],
      rows,
      number_columns: [1, 2, 3, 4]
    )
  end

  def draw_category_commission_summary(transactions)
    groups = transactions.group_by { |t| t[:category_name] || 'Sem categoria' }
    rows = groups.map do |name, txs|
      [name, txs.size.to_s, fmt(txs.sum { |t| t[:amount] }), fmt(txs.sum { |t| t[:commission_amount] })]
    end.sort_by { |r| -r[3].gsub(/[^\d,]/, '').tr(',', '.').to_f }

    draw_styled_table(
      ['Categoria', 'Qtd', 'Total Faturado', 'Total Comissão'],
      rows,
      number_columns: [1, 2, 3]
    )
  end

  def rule_label(type, value)
    case type
    when 'percentage_production' then "#{value}% Produção"
    when 'percentage_received'   then "#{value}% Recebido"
    when 'fixed_value'           then fmt(value)
    else type
    end
  end

  def rule_type_label(type)
    { 'percentage_production' => '% sobre Produção',
      'percentage_received' => '% sobre Recebido',
      'fixed_value' => 'Valor Fixo' }[type] || type
  end

  def truncate_text(text, max)
    text.length > max ? "#{text[0..max - 1]}..." : text
  end
end
