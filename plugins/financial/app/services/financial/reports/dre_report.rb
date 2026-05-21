module Financial
  module Reports
    # Demonstração do Resultado do Exercício (DRE) — regime competência.
    # Canon §9.1 (estrutura) + BUG-03 (Var %) + BUG-04 (Sem categoria).
    #
    # Estrutura do retorno:
    # {
    #   period: { from:, to: },
    #   previous_period: { from:, to: },
    #   uncategorized_count: 12,
    #   uncategorized_amount_cents: 362600,
    #   sections: [
    #     { kind: 'receita', label: 'Receita Bruta', total_cents:, previous_total_cents:, var_label:,
    #       categories: [ { id:, name:, total_cents:, previous_total_cents:, var_label: } ] },
    #     { kind: 'deducao', ... },
    #     { kind: 'custo_variavel', label: 'Custos Variáveis', total_cents:, ... },
    #     ...
    #   ],
    #   summary: { receita_bruta:, deducoes:, receita_liquida:, custos:, margem_bruta:,
    #              despesas_fixas:, ebitda:, outras_despesas:, lucro_liquido: }
    # }
    class DreReport
      MIN_RATIO_FOR_PERCENT = 0.05  # < 5% do atual → "Novo" (BUG-03)

      attr_reader :account, :from, :to

      def self.call(**kwargs) = new(**kwargs).call

      def initialize(account:, from:, to:)
        @account = account
        @from = from.to_date
        @to = to.to_date
      end

      def call
        previous = previous_period_for(@from, @to)

        current_entries  = entries_for(@from, @to)
        previous_entries = entries_for(previous[:from], previous[:to])

        sections = build_sections(current_entries, previous_entries)
        uncategorized = uncategorized_summary(current_entries)
        summary = compute_summary(sections)

        {
          period: { from: @from, to: @to },
          previous_period: previous,
          uncategorized: uncategorized,
          sections: sections,
          summary: summary
        }
      end

      # Retorna a lista de lançamentos por categoria (drill-down — CT-DRE-02/03).
      def entries_in_category(category_id)
        entries_for(@from, @to).where(financial_dre_category_id: category_id).order(competence_date: :desc)
      end

      private

      def entries_for(from, to)
        Financial::Entry
          .for_account(@account.id)
          .for_dre
          .on_competence_date(from, to)
      end

      def previous_period_for(from, to)
        days = (to - from).to_i
        prev_to = from - 1
        prev_from = prev_to - days
        { from: prev_from, to: prev_to }
      end

      def build_sections(current, previous)
        sections = []

        sections << build_section('receita', 'Receita Bruta', current.income, previous.income)
        sections << build_section('custo_variavel', 'Custos Variáveis',
                                  outflow_by_kind(current, 'custo_variavel'),
                                  outflow_by_kind(previous, 'custo_variavel'))
        sections << build_section('despesa_fixa', 'Despesas Fixas',
                                  outflow_by_kind(current, 'despesa_fixa'),
                                  outflow_by_kind(previous, 'despesa_fixa'))
        sections << build_section('outra_despesa', 'Outras Despesas',
                                  outflow_by_kind(current, 'outra_despesa'),
                                  outflow_by_kind(previous, 'outra_despesa'))
        sections
      end

      # Filtra saídas por kind da DRE category, explicitando
      # `financial_dre_categories.account_id` no JOIN como defesa em
      # profundidade — entries já vêm scoped, mas o JOIN explícito impede
      # qualquer chance de cruzar com category de outra conta.
      def outflow_by_kind(scope, kind)
        scope.outflow
             .joins(:financial_dre_category)
             .where(financial_dre_categories: { account_id: @account.id, kind: kind })
      end

      def build_section(kind, label, current_scope, previous_scope)
        current_total = current_scope.sum(:amount_cents)
        previous_total = previous_scope.sum(:amount_cents)

        category_ids = (current_scope.distinct.pluck(:financial_dre_category_id) +
                       previous_scope.distinct.pluck(:financial_dre_category_id)).compact.uniq

        categories = Financial::DreCategory.where(id: category_ids).index_by(&:id)

        category_breakdown = category_ids.map do |cid|
          c_total  = current_scope.where(financial_dre_category_id: cid).sum(:amount_cents)
          p_total  = previous_scope.where(financial_dre_category_id: cid).sum(:amount_cents)
          {
            id: cid,
            name: categories[cid]&.name || 'Sem nome',
            total_cents: c_total,
            previous_total_cents: p_total,
            var_label: var_label_for(c_total, p_total)
          }
        end

        # Lançamentos sem categoria (financial_dre_category_id NULL) também aparecem
        # como "Sem categoria" para usuário ver e classificar.
        uncategorized_total_cur = current_scope.where(financial_dre_category_id: nil).sum(:amount_cents)
        uncategorized_total_prev = previous_scope.where(financial_dre_category_id: nil).sum(:amount_cents)
        if uncategorized_total_cur != 0 || uncategorized_total_prev != 0
          category_breakdown << {
            id: nil,
            name: 'Sem categoria',
            total_cents: uncategorized_total_cur,
            previous_total_cents: uncategorized_total_prev,
            var_label: var_label_for(uncategorized_total_cur, uncategorized_total_prev),
            warning: true
          }
        end

        {
          kind: kind,
          label: label,
          total_cents: current_total,
          previous_total_cents: previous_total,
          var_label: var_label_for(current_total, previous_total),
          categories: category_breakdown.sort_by { |c| -c[:total_cents] }
        }
      end

      # BUG-03: Var % robusta.
      # - previous = 0 e current = 0 → "—"
      # - previous = 0 e current > 0 → "Novo"
      # - previous < 5% do current   → "Novo"
      # - else → percentual com 1 casa
      def var_label_for(current, previous)
        return '—' if current.zero? && previous.zero?
        return 'Novo' if previous.zero?
        return 'Novo' if previous.abs < (current.abs * MIN_RATIO_FOR_PERCENT)

        pct = ((current - previous).to_f / previous.abs) * 100
        sign = pct >= 0 ? '+' : ''
        "#{sign}#{pct.round(1)}%"
      end

      def uncategorized_summary(scope)
        without_cat = scope.where(financial_dre_category_id: nil)
        {
          count: without_cat.count,
          amount_cents: without_cat.sum(:amount_cents)
        }
      end

      def compute_summary(sections)
        receita_bruta   = section_total(sections, 'receita')
        custos          = section_total(sections, 'custo_variavel')
        despesas_fixas  = section_total(sections, 'despesa_fixa')
        outras_despesas = section_total(sections, 'outra_despesa')

        receita_liquida = receita_bruta # deduções não modeladas explicitamente ainda
        margem_bruta    = receita_liquida - custos
        ebitda          = margem_bruta - despesas_fixas
        lucro_liquido   = ebitda - outras_despesas

        {
          receita_bruta_cents: receita_bruta,
          deducoes_cents: 0,
          receita_liquida_cents: receita_liquida,
          custos_variaveis_cents: custos,
          margem_bruta_cents: margem_bruta,
          despesas_fixas_cents: despesas_fixas,
          ebitda_cents: ebitda,
          outras_despesas_cents: outras_despesas,
          lucro_liquido_cents: lucro_liquido
        }
      end

      def section_total(sections, kind)
        sections.find { |s| s[:kind] == kind }&.dig(:total_cents).to_i
      end
    end
  end
end
