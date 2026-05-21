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
        trend = build_trend
        uncategorized = build_uncategorized(scope)

        {
          period: { from: @from, to: @to },
          summary: {
            total_cents: total_cents,
            expenses_count: scope.count,
            categories_count: categories.size
          },
          categories: categories,
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

      # Despesas EFETIVADAS (status pago) — não inclui pendente porque
      # essas ainda não viraram saída de caixa real. O canon DRE conta
      # por competência, mas pra "onde está sendo gasto" o gestor quer
      # ver o que SAIU.
      # Campo `competence_date` pra alinhar com DRE.
      def base_scope
        ::Financial::Expense
          .where(account_id: @account.id)
          .where(status: 'pago')
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

      # 6 meses retroativos a partir do FIM do período. Cada bucket é um mês
      # cheio (1º ao último dia). Permite ver tendência mensal mesmo quando
      # o filtro principal cobre só o mês corrente.
      def build_trend
        end_month = @to.beginning_of_month
        months = (0..5).map { |i| end_month - i.months }.reverse

        months.map do |month_start|
          month_end = month_start.end_of_month
          total = ::Financial::Expense
                    .where(account_id: @account.id)
                    .where(status: 'pago')
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
