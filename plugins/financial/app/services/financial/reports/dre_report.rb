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

      # Retorna a lista de lançamentos numa categoria E TODOS SEUS DESCENDENTES
      # (drill-down hierárquico). Usa o materialized path da categoria:
      # `path LIKE '<cat.path>/%'` pega filhos em qualquer profundidade.
      # Canon `mapa-financeiro.json` step 2 — "Lançamentos sempre caem no
      # nível mais baixo. Níveis acima apenas somam e agrupam."
      def entries_in_category_subtree(category_id)
        cat = ::Financial::DreCategory.for_account(@account.id).alive.find_by(id: category_id)
        return entries_for(@from, @to).none unless cat

        descendant_ids = [cat.id] +
                         ::Financial::DreCategory
                           .for_account(@account.id)
                           .alive
                           .where('path LIKE ?', "#{cat.path}/%")
                           .pluck(:id)

        entries_for(@from, @to)
          .where(financial_dre_category_id: descendant_ids)
          .order(competence_date: :desc)
      end

      private

      def entries_for(from, to)
        # Auditoria 2026-05-22 (`MED-CALC-01`): defesa em profundidade.
        # `for_dre` filtra `affects_dre = true`, mas se algum lançamento de
        # transferência interna for criado com `affects_dre=true` por bug,
        # o filtro explícito de `kind` impede que ele apareça no DRE.
        # Canon: "Transferência interna NÃO afeta DRE — apenas movimentação
        # entre contas".
        Financial::Entry
          .for_account(@account.id)
          .for_dre
          .where.not(kind: %w[transferencia sangria suprimento])
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

        sections << build_section('receita', 'Receita Bruta', revenue(current), revenue(previous))
        # Deduções da Receita Bruta — estornos/cancelamentos de receita
        # (kind 'estorno_receita'). Saem da Receita Líquida; NÃO entram nas
        # seções de despesa (senão dobrariam o efeito no lucro líquido).
        # Só renderiza a seção quando há dedução no período atual OU anterior —
        # evita um card "Deduções R$ 0,00" vazio na maioria das contas/períodos.
        # (O resumo segue mostrando a linha "(–) Deduções", zerada via
        # `section_total`, que é o padrão de waterfall do DRE.)
        if deductions(current).exists? || deductions(previous).exists?
          sections << build_section('deducao', 'Deduções', deductions(current), deductions(previous))
        end
        # Seções de despesa: saídas (out) ABATIDAS pelos estornos de despesa
        # (estorno_despesa, direction in) — um pagamento revertido reduz a
        # despesa em vez de virar receita (ver expense_reversals_by_kind p/
        # roteamento, conservação e ressalvas de competência/modificadores).
        sections << build_section('custo_variavel', 'Custos Variáveis',
                                  outflow_by_kind(current, 'custo_variavel'),
                                  outflow_by_kind(previous, 'custo_variavel'),
                                  current_credits: expense_reversals_by_kind(current, 'custo_variavel'),
                                  previous_credits: expense_reversals_by_kind(previous, 'custo_variavel'))
        sections << build_section('despesa_fixa', 'Despesas Fixas',
                                  outflow_by_kind(current, 'despesa_fixa'),
                                  outflow_by_kind(previous, 'despesa_fixa'),
                                  current_credits: expense_reversals_by_kind(current, 'despesa_fixa'),
                                  previous_credits: expense_reversals_by_kind(previous, 'despesa_fixa'))
        sections << build_section('outra_despesa', 'Outras Despesas',
                                  outflow_by_kind(current, 'outra_despesa'),
                                  outflow_by_kind(previous, 'outra_despesa'),
                                  current_credits: expense_reversals_by_kind(current, 'outra_despesa'),
                                  previous_credits: expense_reversals_by_kind(previous, 'outra_despesa'))
        sections
      end

      # Filtra saídas por kind da DRE category, explicitando
      # `financial_dre_categories.account_id` no JOIN como defesa em
      # profundidade — entries já vêm scoped, mas o JOIN explícito impede
      # qualquer chance de cruzar com category de outra conta.
      def outflow_by_kind(scope, kind)
        scope.outflow
             .where.not(kind: 'estorno_receita')
             .joins(:financial_dre_category)
             .where(financial_dre_categories: { account_id: @account.id, kind: kind })
      end

      # Estornos de receita (devoluções/cancelamentos) = deduções da Receita
      # Bruta. São Entries `direction: 'out'`, `kind: 'estorno_receita'`, com a
      # categoria de receita herdada do recibo original. `amount_cents` é
      # positivo e somado direto — a subtração acontece em `compute_summary`
      # (receita_liquida = receita_bruta - deducoes). Ficam FORA das seções de
      # despesa (`outflow_by_kind` os exclui) pra não dobrar o efeito no lucro:
      # um estorno reduz a receita, não vira despesa nova.
      def deductions(scope)
        scope.where(kind: 'estorno_receita')
      end

      # Receita Bruta = entradas que são REALMENTE receita. Exclui
      # `estorno_despesa` (direction in): é dinheiro que VOLTA de uma despesa
      # revertida, não receita — ele abate a despesa (ver
      # `expense_reversals_by_kind`), não infla a receita.
      def revenue(scope)
        scope.income.where.not(kind: 'estorno_despesa')
      end

      # Estornos de despesa (kind 'estorno_despesa', direction 'in') ABATEM a
      # despesa que revertem — entram como CRÉDITO (negativo) na seção de
      # despesa correspondente, em vez de aparecer como receita.
      #
      # Roteamento — partição COMPLETA e DISJUNTA, garantindo CONSERVAÇÃO (todo
      # estorno_despesa excluído da Receita Bruta por `revenue` é re-incluído
      # como crédito em EXATAMENTE uma seção, nunca some do DRE):
      #   • custo_variavel / despesa_fixa → estornos cuja categoria é desse kind;
      #   • outra_despesa → bucket-padrão: tudo que NÃO é custo_variavel/
      #     despesa_fixa (cobre o caso latente de estorno com categoria de
      #     receita por reclassificação indevida e, defensivamente, categoria nula).
      #
      # Ressalva (documentada, não-bug): o crédito usa a competence_date do
      # ESTORNO (reversed_at) — igual ao estorno de receita; se o estorno cair em
      # período != da despesa original, a seção pode ficar NEGATIVA no mês do
      # estorno (a despesa cheia fica no mês original). No MESMO período o estorno
      # ZERA a despesa: ReverseExpense reverte o total efetivo que saiu do caixa
      # (principal + juros + multa − desconto), não só o principal (fix 1.8.0.57).
      def expense_reversals_by_kind(scope, kind)
        reversals = scope.where(kind: 'estorno_despesa')
        return reversals.joins(:financial_dre_category)
                        .where(financial_dre_categories: { account_id: @account.id, kind: kind }) unless kind == 'outra_despesa'

        specific_ids = ::Financial::DreCategory.for_account(@account.id)
                                               .where(kind: %w[custo_variavel despesa_fixa])
                                               .pluck(:id)
        return reversals if specific_ids.empty?

        reversals.where.not(financial_dre_category_id: specific_ids)
                 .or(reversals.where(financial_dre_category_id: nil))
      end

      def build_section(kind, label, current_scope, previous_scope, current_credits: nil, previous_credits: nil)
        # `credits` = lançamentos que ABATEM a seção (somados com sinal NEGATIVO).
        # Hoje: estornos de despesa (direction in) que zeram a despesa revertida.
        # nil = nenhum crédito (Receita Bruta, Deduções e seções sem reversão).
        cc = current_credits  || current_scope.none
        pc = previous_credits || previous_scope.none

        current_total  = current_scope.sum(:amount_cents)  - cc.sum(:amount_cents)
        previous_total = previous_scope.sum(:amount_cents) - pc.sum(:amount_cents)

        category_ids = (current_scope.distinct.pluck(:financial_dre_category_id) +
                       previous_scope.distinct.pluck(:financial_dre_category_id) +
                       cc.distinct.pluck(:financial_dre_category_id) +
                       pc.distinct.pluck(:financial_dre_category_id)).compact.uniq

        categories = Financial::DreCategory.where(id: category_ids).index_by(&:id)

        category_breakdown = category_ids.map do |cid|
          c_total  = current_scope.where(financial_dre_category_id: cid).sum(:amount_cents)  - cc.where(financial_dre_category_id: cid).sum(:amount_cents)
          p_total  = previous_scope.where(financial_dre_category_id: cid).sum(:amount_cents) - pc.where(financial_dre_category_id: cid).sum(:amount_cents)
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
        uncategorized_total_cur = current_scope.where(financial_dre_category_id: nil).sum(:amount_cents)  - cc.where(financial_dre_category_id: nil).sum(:amount_cents)
        uncategorized_total_prev = previous_scope.where(financial_dre_category_id: nil).sum(:amount_cents) - pc.where(financial_dre_category_id: nil).sum(:amount_cents)
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
        deducoes        = section_total(sections, 'deducao')
        custos          = section_total(sections, 'custo_variavel')
        despesas_fixas  = section_total(sections, 'despesa_fixa')
        outras_despesas = section_total(sections, 'outra_despesa')

        receita_liquida = receita_bruta - deducoes
        margem_bruta    = receita_liquida - custos
        ebitda          = margem_bruta - despesas_fixas
        lucro_liquido   = ebitda - outras_despesas

        {
          receita_bruta_cents: receita_bruta,
          deducoes_cents: deducoes,
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
