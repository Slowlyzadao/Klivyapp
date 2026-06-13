module Financial
  module Reports
    # Receitas por Procedimento — canon Hub Relatórios (2026-05-23).
    #
    # Agrega `BudgetItem.description` (procedimento) dentro dos orçamentos
    # aprovados/concluídos num período. Mesmo critério do `Charts.top_procedures`
    # do dashboard, mas SEM limit (lista completa) e com `percent_of_total`.
    #
    # Diferença em relação ao top_procedures:
    #   - Sem limit: retorna TODOS os procedimentos do período (paginação no front)
    #   - Adiciona `percent_of_total` (Σ procedimento ÷ Σ geral × 100)
    #   - Total agregado disponível em `summary.total_cents`
    #
    # Retorno:
    #   {
    #     period:   { from:, to: },
    #     summary:  { total_cents:, total_quantity:, procedures_count: },
    #     items:    [{ rank:, name:, qty:, total_cents:, ticket_avg_cents:, percent_of_total: }]
    #   }
    class RevenueByProcedureReport
      def self.call(**kwargs) = new(**kwargs).call

      def initialize(account:, from:, to:)
        @account = account
        @from = from.to_date
        @to   = to.to_date
      end

      def call
        rows = aggregate_rows
        total_revenue = rows.sum { |r| r[:total_cents] }
        total_qty     = rows.sum { |r| r[:qty] }

        ranked = rows
                   .sort_by { |r| -r[:total_cents] }
                   .each_with_index
                   .map do |r, idx|
          r.merge(
            rank: idx + 1,
            percent_of_total: total_revenue.positive? ? ((r[:total_cents].to_f / total_revenue) * 100).round(2) : 0.0
          )
        end

        {
          period: { from: @from.iso8601, to: @to.iso8601 },
          summary: {
            total_cents: total_revenue,
            total_quantity: total_qty,
            procedures_count: ranked.size
          },
          items: ranked
        }
      end

      private

      def aggregate_rows
        Financial::BudgetItem
          .where(account_id: @account.id)
          .joins(:budget)
          .where(financial_budgets: { status: %w[aprovado concluido] })
          .where(financial_budgets: { approved_at: @from.beginning_of_day..@to.end_of_day })
          .group(:description)
          .pluck(
            :description,
            Arel.sql('SUM(financial_budget_items.quantity)::int        AS qty'),
            Arel.sql('SUM(financial_budget_items.total_cents)::bigint  AS total_cents')
          )
          .map do |name, qty, total|
            qty_i = qty.to_i
            total_i = total.to_i
            {
              name: name.presence || '(sem descrição)',
              qty: qty_i,
              total_cents: total_i,
              ticket_avg_cents: qty_i.positive? ? (total_i.to_f / qty_i).round.to_i : nil
            }
          end
      end
    end
  end
end
