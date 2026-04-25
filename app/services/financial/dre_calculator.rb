class Financial::DreCalculator
  DRE_LINES = [
    { key: :receita_bruta,          label: 'Receita bruta',            tipo: 'total',    sign: 1  },
    { key: :deducoes,               label: '(-) Deduções',             tipo: 'reducao',  sign: -1 },
    { key: :receita_liquida,        label: '= Receita líquida',        tipo: 'subtotal', sign: 1  },
    { key: :custos_assistenciais,   label: '(-) Custos assistenciais', tipo: 'reducao',  sign: -1 },
    { key: :margem_bruta,           label: '= Margem bruta',           tipo: 'subtotal', sign: 1  },
    { key: :custos_fixos,           label: '(-) Custos fixos',         tipo: 'reducao',  sign: -1 },
    { key: :marketing,              label: '(-) Marketing',            tipo: 'reducao',  sign: -1 },
    { key: :despesas_financeiras,   label: '(-) Desp. financeiras',    tipo: 'reducao',  sign: -1 },
    { key: :impostos,               label: '(-) Impostos',             tipo: 'reducao',  sign: -1 },
    { key: :resultado_liquido,      label: '= Resultado líquido',      tipo: 'final',    sign: 1  }
  ].freeze

  def initialize(account:, period:, regime: 'caixa')
    @account = account
    @period  = period.is_a?(String) ? Date.parse("#{period}-01") : period
    @regime  = regime
  end

  def call
    totais = fetch_totals
    build_waterfall(totais)
  end

  private

  def date_field
    @regime == 'competencia' ? :competence_date : :received_at
  end

  def period_range
    @period.beginning_of_month..@period.end_of_month.end_of_day
  end

  def base_scope
    @account.account_transactions.kept
            .where(date_field => period_range)
  end

  def fetch_totals
    receita_bruta = base_scope.where(entry_type: 'entrada', status: 'recebido').sum(:amount).to_f

    # Group expenses by cost_type (fixo/variavel) since dre_line doesn't exist yet
    by_cost_type = base_scope.where(entry_type: 'saida', status: 'pago')
                             .joins('LEFT JOIN financial_categories ON financial_categories.id = account_transactions.financial_category_id')
                             .group('COALESCE(financial_categories.cost_type, \'fixo\')')
                             .sum(:amount)
                             .transform_values(&:to_f)

    custos_variaveis = by_cost_type.fetch('variavel', 0.0)
    custos_fixos     = by_cost_type.fetch('fixo', 0.0)

    {
      receita_bruta: receita_bruta,
      deducoes: 0.0,
      custos_assistenciais: custos_variaveis,
      custos_fixos: custos_fixos,
      marketing: 0.0,
      despesas_financeiras: 0.0,
      impostos: 0.0
    }
  end

  def build_waterfall(totais)
    valores = build_valores(totais)
    receita = totais[:receita_bruta]
    acumulado = 0.0

    DRE_LINES.map do |linha|
      valor = valores[linha[:key]].round(2)
      base, topo, acumulado = waterfall_position(linha[:tipo], valor, acumulado)
      build_row(linha, valor, receita, base, topo)
    end
  end

  def build_valores(totais)
    sl = subtotals(totais)
    {
      receita_bruta: totais[:receita_bruta],
      deducoes: -totais[:deducoes],
      receita_liquida: sl[:receita_liquida],
      custos_assistenciais: -totais[:custos_assistenciais],
      margem_bruta: sl[:margem_bruta],
      custos_fixos: -totais[:custos_fixos],
      marketing: -totais[:marketing],
      despesas_financeiras: -totais[:despesas_financeiras],
      impostos: -totais[:impostos],
      resultado_liquido: sl[:resultado]
    }
  end

  def subtotals(totais)
    receita_liquida = totais[:receita_bruta] - totais[:deducoes]
    margem_bruta    = receita_liquida - totais[:custos_assistenciais]
    resultado       = margem_bruta - totais[:custos_fixos] - totais[:marketing] -
                      totais[:despesas_financeiras] - totais[:impostos]
    { receita_liquida: receita_liquida, margem_bruta: margem_bruta, resultado: resultado }
  end

  def waterfall_position(tipo, valor, acumulado)
    base = tipo == 'total' ? 0.0 : acumulado
    topo = tipo.in?(%w[subtotal final]) ? valor : base + valor
    acumulado = topo if tipo.in?(%w[subtotal final total])
    [base.round(2), topo.round(2), acumulado]
  end

  def build_row(linha, valor, receita, base, topo)
    {
      linha: linha[:label],
      valor: valor,
      percentual: receita.positive? ? (valor / receita * 100).round(1) : 0.0,
      tipo: linha[:tipo],
      base: base,
      topo: topo
    }
  end
end
