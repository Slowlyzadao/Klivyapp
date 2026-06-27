module Financial
  module Reports
    # Receitas por Forma de Pagamento — canon Hub Relatórios (2026-05-23).
    #
    # Agrega Entries de RECEITA (`direction='in'`, `affects_dre=true`, kind∈
    # ['receita','manual_entry']) por `payment_method` no período de
    # competência. Útil pra clínica avaliar mix de meios (PIX domina? cartão
    # crédito vale a pena pela MDR?) — decisão de baixa de taxa.
    #
    # Filtra `kind` pra ignorar transferências/sangrias/quebra-de-caixa que
    # não são "receita real". Categoria DRE não importa aqui — qualquer
    # entrada positiva conta.
    #
    # Retorno:
    #   {
    #     period:  { from:, to: },
    #     summary: { total_cents:, transactions_count: },
    #     items:   [{ payment_method:, label:, qty:, total_cents:,
    #                 ticket_avg_cents:, percent_of_total: }]
    #   }
    class RevenueByPaymentMethodReport
      # Mapa human-readable do canon (mesmo conjunto do `Installment::PAYMENT_METHODS`).
      LABELS = {
        'pix'              => 'PIX',
        'dinheiro'         => 'Dinheiro',
        'credito'          => 'Cartão de Crédito',
        'debito'           => 'Cartão de Débito',
        'boleto'           => 'Boleto',
        'transferencia'    => 'Transferência',
        'cheque'           => 'Cheque',
        'multiplas'        => 'Múltiplas formas',
        'credito_paciente' => 'Crédito do paciente',
        nil                => '(não informado)'
      }.freeze

      RELEVANT_KINDS = %w[receita manual_entry].freeze

      def self.call(**kwargs) = new(**kwargs).call

      def initialize(account:, from:, to:)
        @account = account
        @from = from.to_date
        @to   = to.to_date
      end

      def call
        scope = Financial::Entry
                  .for_account(@account.id)
                  .income
                  .for_dre
                  .where(kind: RELEVANT_KINDS)
                  .on_competence_date(@from, @to)

        # `nil` payment_method é tratado como bucket separado pro operador
        # detectar Entries sem forma definida (lacuna de dados).
        rows = scope.group(:payment_method).pluck(
          Arel.sql('payment_method'),
          Arel.sql('COUNT(*)::int             AS qty'),
          Arel.sql('SUM(amount_cents)::bigint AS total_cents')
        )

        total_revenue = rows.sum { |_pm, _q, t| t.to_i }

        items = rows.map do |pm, qty, total|
          qty_i = qty.to_i
          total_i = total.to_i
          {
            payment_method: pm,
            label: LABELS[pm] || pm.to_s.humanize,
            qty: qty_i,
            total_cents: total_i,
            ticket_avg_cents: qty_i.positive? ? (total_i.to_f / qty_i).round.to_i : nil,
            percent_of_total: total_revenue.positive? ? ((total_i.to_f / total_revenue) * 100).round(2) : 0.0
          }
        end.sort_by { |i| -i[:total_cents] }

        {
          period: { from: @from.iso8601, to: @to.iso8601 },
          summary: {
            total_cents: total_revenue,
            transactions_count: rows.sum { |_pm, q, _t| q.to_i }
          },
          items: items
        }
      end
    end
  end
end
