module Financial
  module Reports
    # Despesas por Categoria — canon F-30 §sub-aba 1.
    #
    # Para o gestor enxergar onde gasta. Pizza/barras com % de cada categoria
    # sobre total de despesa do período. Drill-down em uma categoria mostra
    # lista de despesas. Comparativo de 6 meses (linha de tendência).
    #
    # Estrutura do retorno:
    # {
    #   period: { from:, to: },
    #   summary: { total_cents:, expenses_count:, categories_count: },
    #   categories: [
    #     { id:, name:, kind:, total_cents:, percent_of_total:, expenses_count: }
    #   ],
    #   trend: [
    #     { month: '2026-01', label: 'Jan/26', total_cents: },
    #     ...
    #   ],
    #   uncategorized: { count:, total_cents: }
    # }
    class ExpensesByCategoryReport
      attr_reader :account, :from, :to

      def self.call(**kwargs) = new(**kwargs).call

      def initialize(account:, from:, to:)
        @account = account
        @from = from.to_date
        @to = to.to_date
      end

      def call
        scope = base_scope
        total_cents = scope.sum(:amount_cents).to_i
        categories = build_categories(scope, total_cents)
        groups = build_groups(scope, total_cents)
        trend = build_trend
        uncategorized = build_uncategorized(scope)

        {
          period: { from: @from, to: @to },
          summary: {
            total_cents: total_cents,
            expenses_count: scope.count,
            categories_count: categories.size
          },
          categories: categories, # legacy flat (mantém compat com drill-down)
          groups: groups,         # hierárquico GRUPO → ITEM (wireframe Hub Relatórios)
          trend: trend,
          uncategorized: uncategorized
        }
      end

      # Drill-down: lista de despesas de uma categoria no período.
      # category_id pode ser nil → "Sem categoria".
      def expenses_in_category(category_id)
        scope = base_scope
        scope = if category_id.present?
                  scope.where(financial_dre_category_id: category_id)
                else
                  scope.where(financial_dre_category_id: nil)
                end
        scope.includes(:financial_dre_category, :financial_bank_account)
             .order(due_date: :desc)
      end

      private

      # Despesas LANÇADAS no período (pendente + vencido + pago).
      # Decisão 2026-05-23: incluir status em aberto pro operador enxergar
      # categorias com compromisso financeiro, não só caixa realizado.
      # Excluí `cancelado` e `estornado` (não compõem despesa válida).
      #
      # Alinhamento com wireframe: subtítulo "combina despesas fixas +
      # saídas manuais" implica visão por COMPETÊNCIA (regime competência
      # do DRE), não regime caixa.
      def base_scope
        ::Financial::Expense
          .where(account_id: @account.id)
          .where(status: %w[pendente pago vencido])
          .where(competence_date: @from..@to)
      end

      def build_categories(scope, grand_total)
        breakdown = scope
                      .where.not(financial_dre_category_id: nil)
                      .group(:financial_dre_category_id)
                      .pluck(
                        :financial_dre_category_id,
                        Arel.sql('SUM(amount_cents)'),
                        Arel.sql('COUNT(*)')
                      )

        cat_ids = breakdown.map(&:first)
        cats = ::Financial::DreCategory.where(id: cat_ids).index_by(&:id)

        breakdown.map do |cat_id, total, count|
          cat = cats[cat_id]
          {
            id: cat_id,
            name: cat&.name || 'Sem nome',
            kind: cat&.kind,
            total_cents: total.to_i,
            percent_of_total: percent_of(total.to_i, grand_total),
            expenses_count: count.to_i
          }
        end.sort_by { |c| -c[:total_cents] }
      end

      # Estrutura hierárquica GRUPO → ITEM seguindo o plano de contas canônico
      # (level 1 = Grupo; level 2+ = Item). Wireframe Hub Relatórios (2026-05-23):
      #
      #   1. Pessoal              (TOTAL GRUPO)  R$ X    %
      #   1. Pessoal     | Salários e Ordenados  R$ Y    %
      #   1. Pessoal     | Encargos Sociais      R$ Z    %
      #   2. Ocupação             (TOTAL GRUPO)  ...
      #
      # Estratégia: pra cada Expense, sobe o `path` da DreCategory até o
      # ancestral level=1 (o "Grupo"). Agrega na raiz; lista a categoria
      # original como item.
      def build_groups(scope, grand_total)
        # Carrega TODAS as categorias da conta (incluindo ancestors) numa
        # query só pra resolver path. Vale a pena vs queries por expense.
        all_cats = ::Financial::DreCategory.where(account_id: @account.id).index_by(&:id)

        # Resolve root (level=1) pra cada categoria via parent walk.
        root_of = {}
        all_cats.each_value do |cat|
          root_of[cat.id] = resolve_root(cat, all_cats)
        end

        # Pluck (cat_id, sum, count) das despesas
        breakdown = scope
                      .where.not(financial_dre_category_id: nil)
                      .group(:financial_dre_category_id)
                      .pluck(
                        :financial_dre_category_id,
                        Arel.sql('SUM(amount_cents)'),
                        Arel.sql('COUNT(*)')
                      )

        # Agrupa por root (level=1). `nil` root = categoria órfã (path
        # corrompido); manda pra um bucket "Outros".
        groups_map = {}
        breakdown.each do |cat_id, total, count|
          cat  = all_cats[cat_id]
          next if cat.nil?

          root = root_of[cat_id] || cat
          gid  = root.id

          groups_map[gid] ||= {
            id: gid,
            name: root.name,
            position: root.position.to_i,
            kind: root.kind,
            total_cents: 0,
            items: []
          }
          groups_map[gid][:total_cents] += total.to_i

          # Se a categoria do expense é o próprio root, mostra como item
          # "(direto no grupo)" pra deixar claro que não foi categorizado
          # num subitem específico.
          item_name = (cat.id == root.id) ? "#{root.name} (direto)" : cat.name
          groups_map[gid][:items] << {
            id: cat.id,
            name: item_name,
            total_cents: total.to_i,
            percent_of_total: percent_of(total.to_i, grand_total),
            expenses_count: count.to_i
          }
        end

        # Ordena items dentro de cada grupo (maior → menor) e grupos
        # entre si (maior → menor).
        groups_map.each_value do |g|
          g[:items].sort_by! { |i| -i[:total_cents] }
          g[:percent_of_total] = percent_of(g[:total_cents], grand_total)
        end

        groups_map.values.sort_by { |g| -g[:total_cents] }
      end

      # Sobe a árvore via parent_id até achar nó level=1. Hash `all_cats`
      # evita N+1 (já carregou tudo).
      def resolve_root(cat, all_cats)
        current = cat
        depth_guard = 0
        while current.parent_id && depth_guard < ::Financial::DreCategory::MAX_LEVEL
          parent = all_cats[current.parent_id]
          break if parent.nil?

          current = parent
          depth_guard += 1
        end
        current
      end

      # 6 meses retroativos a partir do FIM do período. Cada bucket é um mês
      # cheio (1º ao último dia). Permite ver tendência mensal mesmo quando
      # o filtro principal cobre só o mês corrente. Mesmo filtro de status
      # do `base_scope` (pendente + vencido + pago).
      def build_trend
        end_month = @to.beginning_of_month
        months = (0..5).map { |i| end_month - i.months }.reverse

        months.map do |month_start|
          month_end = month_start.end_of_month
          total = ::Financial::Expense
                    .where(account_id: @account.id)
                    .where(status: %w[pendente pago vencido])
                    .where(competence_date: month_start..month_end)
                    .sum(:amount_cents).to_i
          {
            month: month_start.strftime('%Y-%m'),
            label: brazilian_month_label(month_start),
            total_cents: total
          }
        end
      end

      def build_uncategorized(scope)
        without_cat = scope.where(financial_dre_category_id: nil)
        {
          count: without_cat.count,
          total_cents: without_cat.sum(:amount_cents).to_i
        }
      end

      def percent_of(part, total)
        return 0.0 if total.zero?
        ((part.to_f / total) * 100).round(1)
      end

      MONTHS_BR = %w[Jan Fev Mar Abr Mai Jun Jul Ago Set Out Nov Dez].freeze
      def brazilian_month_label(date)
        "#{MONTHS_BR[date.month - 1]}/#{date.strftime('%y')}"
      end
    end
  end
end
