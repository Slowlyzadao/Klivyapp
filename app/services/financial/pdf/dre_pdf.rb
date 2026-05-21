# frozen_string_literal: true

# PDF: DRE — Demonstração do Resultado do Exercício (Income Statement).
class Financial::Pdf::DrePdf < Financial::Pdf::BasePdf
  def initialize(account:, period: nil, regime: 'competencia')
    super(account: account)
    @period_param = period || Time.zone.today.strftime('%Y-%m')
    @regime       = regime
  end

  private

  def build
    period_range = resolve_period
    prior_range  = resolve_prior(period_range)

    current = build_dre_data(period_range)
    prior   = build_dre_data(prior_range)

    draw_header(
      title: 'DRE — Demonstração do Resultado do Exercício',
      subtitle: "Regime de #{@regime == 'competencia' ? 'competência' : 'caixa'}.",
      period_label: "#{fmt_date(period_range.first)} a #{fmt_date(period_range.last)}"
    )

    margin_pct = current[:receita_bruta] > 0 ? (current[:lucro_liq] / current[:receita_bruta] * 100).round(1) : 0.0

    draw_kpi_cards([
      { label: 'Receita Bruta',   value: fmt(current[:receita_bruta]),  color: BRAND_GREEN, bg: 'f0fdf4' },
      { label: 'Total Despesas',  value: fmt(current[:total_expenses]), color: BRAND_RED,   bg: 'fef2f2' },
      { label: 'Lucro Líquido',   value: fmt(current[:lucro_liq]),      color: current[:lucro_liq] >= 0 ? BRAND_GREEN : BRAND_RED, bg: current[:lucro_liq] >= 0 ? 'f0fdf4' : 'fef2f2' },
      { label: 'Margem Líquida',  value: "#{margin_pct}%",              color: BRAND_BLUE,   bg: 'eff6ff' }
    ])

    draw_section_title('Demonstrativo Detalhado')
    draw_dre_table(current, prior)

    ensure_space(100)
    draw_section_title('Receitas por Categoria')
    draw_category_breakdown(current[:income_rows], 'receita')

    ensure_space(100)
    draw_section_title('Despesas por Categoria')
    draw_category_breakdown(current[:expense_rows], 'despesa')

    ensure_space(100)
    draw_section_title("Comparativo com Período Anterior")
    pdf.font_size(8) { pdf.text "Período anterior: #{fmt_date(prior_range.first)} a #{fmt_date(prior_range.last)}", color: BRAND_GRAY }
    pdf.move_down 8
    draw_comparison_table(current, prior)
  end

  def resolve_period
    ref = Date.parse("#{@period_param}-01")
    ref.beginning_of_month..ref.end_of_month
  rescue ArgumentError
    Date.today.all_month
  end

  def resolve_prior(range)
    length = (range.last - range.first).to_i + 1
    prior_end   = range.first - 1
    prior_start = prior_end - length + 1
    prior_start..prior_end
  end

  def build_dre_data(range)
    scope = account.account_transactions.kept
                   .where(competence_date: range)

    income_scope  = scope.entradas.where(status: %w[recebido pendente parcial])
    expense_scope = scope.saidas.where(status: %w[pago pendente parcial])

    income_rows  = category_rows(income_scope)
    expense_rows = category_rows(expense_scope)

    receita_bruta = income_rows.sum { |r| r[:amount] }
    deducoes      = income_rows.select { |r| r[:category_type] == 'deducao' }.sum { |r| r[:amount] }
    receita_liq   = receita_bruta - deducoes

    custos_var    = expense_rows.select { |r| r[:cost_type] == 'variavel' }.sum { |r| r[:amount] }
    margem_bruta  = receita_liq - custos_var

    desp_fixas    = expense_rows.select { |r| r[:cost_type] == 'fixo' }.sum { |r| r[:amount] }
    ebitda        = margem_bruta - desp_fixas

    outras_desp   = expense_rows.reject { |r| %w[fixo variavel].include?(r[:cost_type]) }.sum { |r| r[:amount] }
    lucro_liq     = ebitda - outras_desp

    total_expenses = custos_var + desp_fixas + outras_desp

    {
      receita_bruta: receita_bruta, deducoes: deducoes, receita_liq: receita_liq,
      custos_var: custos_var, margem_bruta: margem_bruta, desp_fixas: desp_fixas,
      ebitda: ebitda, outras_desp: outras_desp, lucro_liq: lucro_liq,
      total_expenses: total_expenses,
      income_rows: income_rows, expense_rows: expense_rows
    }
  end

  def category_rows(scope)
    scope
      .joins('LEFT JOIN financial_categories ON financial_categories.id = account_transactions.financial_category_id')
      .group('financial_categories.id', 'financial_categories.name', 'financial_categories.cost_type', 'financial_categories.category_type')
      .select(
        'financial_categories.id AS fc_id',
        'financial_categories.name AS fc_name',
        'financial_categories.cost_type AS fc_cost_type',
        'financial_categories.category_type AS fc_category_type',
        'SUM(account_transactions.amount) AS total_amount'
      )
      .map do |row|
        {
          category_id: row.fc_id,
          category_name: row.fc_name || 'Sem categoria',
          cost_type: row.fc_cost_type,
          category_type: row.fc_category_type,
          amount: row.total_amount.to_f
        }
      end
  end

  def draw_dre_table(current, _prior)
    dre_lines = [
      { label: 'Receita Bruta',          value: current[:receita_bruta], style: :section },
      { label: '(-) Deduções',           value: -current[:deducoes],     style: :deduction },
      { label: '= Receita Líquida',      value: current[:receita_liq],   style: :subtotal },
      { label: '(-) Custos Variáveis',   value: -current[:custos_var],   style: :deduction },
      { label: '= Margem Bruta',         value: current[:margem_bruta],  style: :subtotal },
      { label: '(-) Despesas Fixas',     value: -current[:desp_fixas],   style: :deduction },
      { label: '= EBITDA',               value: current[:ebitda],        style: :subtotal },
      { label: '(-) Outras Despesas',    value: -current[:outras_desp],  style: :deduction },
      { label: '= LUCRO LÍQUIDO',        value: current[:lucro_liq],     style: :total }
    ]

    pct_base = current[:receita_bruta]

    table_data = [['Descrição', 'Valor', '% da Receita']]
    dre_lines.each do |line|
      pct = pct_base > 0 ? (line[:value].abs / pct_base * 100).round(1) : 0.0
      table_data << [line[:label], fmt(line[:value]), "#{pct}%"]
    end

    pdf.table(table_data, header: true, width: pdf.bounds.width) do |t|
      t.row(0).font_style = :bold
      t.row(0).background_color = HEADER_BG
      t.row(0).text_color = BRAND_DARK
      t.row(0).size = 8

      t.cells.padding = [7, 10, 7, 10]
      t.cells.size = 9
      t.cells.border_width = 0.5
      t.cells.border_color = BORDER_COLOR

      t.column(1).align = :right
      t.column(2).align = :right

      # Style specific rows
      dre_lines.each_with_index do |line, i|
        row_idx = i + 1
        case line[:style]
        when :subtotal
          t.row(row_idx).font_style = :bold
          t.row(row_idx).background_color = 'f0f9ff'
        when :total
          t.row(row_idx).font_style = :bold
          t.row(row_idx).background_color = line[:value] >= 0 ? 'f0fdf4' : 'fef2f2'
          t.row(row_idx).text_color = line[:value] >= 0 ? BRAND_GREEN : BRAND_RED
        when :deduction
          t.row(row_idx).text_color = BRAND_RED
        end
      end
    end
  end

  def draw_category_breakdown(rows, type)
    return draw_empty_state("Nenhuma #{type} registrada no período.") if rows.empty?

    total = rows.sum { |r| r[:amount] }
    table_rows = rows.sort_by { |r| -r[:amount] }.map do |r|
      pct = total > 0 ? (r[:amount] / total * 100).round(1) : 0.0
      [r[:category_name], fmt(r[:amount]), "#{pct}%"]
    end

    draw_styled_table(
      ['Categoria', 'Valor', '% do Total'],
      table_rows,
      number_columns: [1, 2]
    )
  end

  def draw_comparison_table(current, prior)
    lines = [
      ['Receita Bruta',     current[:receita_bruta],  prior[:receita_bruta]],
      ['Receita Líquida',   current[:receita_liq],    prior[:receita_liq]],
      ['Margem Bruta',      current[:margem_bruta],   prior[:margem_bruta]],
      ['EBITDA',            current[:ebitda],          prior[:ebitda]],
      ['Lucro Líquido',     current[:lucro_liq],       prior[:lucro_liq]]
    ]

    table_data = [['Indicador', 'Período Atual', 'Período Anterior', 'Variação']]
    lines.each do |label, cur_val, prev_val|
      var = prev_val != 0 ? ((cur_val - prev_val) / prev_val.abs * 100).round(1) : nil
      var_str = var ? "#{var >= 0 ? '+' : ''}#{var}%" : '—'
      table_data << [label, fmt(cur_val), fmt(prev_val), var_str]
    end

    draw_styled_table(table_data[0], table_data[1..], number_columns: [1, 2, 3])
  end
end
