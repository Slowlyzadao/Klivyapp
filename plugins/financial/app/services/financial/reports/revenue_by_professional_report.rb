module Financial
  module Reports
    # Receitas por Profissional — canon Hub Relatórios (2026-05-23).
    #
    # Agrega receita (Entries `direction='in'` + `affects_dre=true`) por
    # `professional_id` no período de competência. Inclui:
    #   - total recebido
    #   - quantidade de recebimentos
    #   - pacientes únicos
    #   - ticket médio
    #
    # Já existe `Charts.revenue_by_professional` mas retorna shape de chart
    # (label/value/color) — esse aqui é a versão TABULAR completa pra Hub
    # Relatórios. Reaproveita a mesma fonte (Entry) pra consistência.
    #
    # Retorno:
    #   {
    #     period:  { from:, to: },
    #     summary: { total_cents:, professionals_count: },
    #     items:   [{ professional: { id, name, avatar_url }, qty:, patients_count:,
    #                 total_cents:, ticket_avg_cents:, percent_of_total: }]
    #   }
    class RevenueByProfessionalReport
      RELEVANT_KINDS = %w[receita manual_entry].freeze

      def self.call(**kwargs) = new(**kwargs).call

      def initialize(account:, from:, to:)
        @account = account
        @from = from.to_date
        @to   = to.to_date
      end

      def call
        entries = base_scope.includes(:professional, :patient).to_a
        total_revenue = entries.sum(&:amount_cents)

        grouped = entries.group_by(&:professional_id)

        items = grouped.map do |prof_id, prof_entries|
          professional = prof_entries.first.professional
          patient_ids = prof_entries.map(&:patient_id).compact.uniq
          total = prof_entries.sum(&:amount_cents).to_i
          qty = prof_entries.size

          {
            professional: build_professional_payload(prof_id, professional),
            qty: qty,
            patients_count: patient_ids.size,
            total_cents: total,
            ticket_avg_cents: qty.positive? ? (total.to_f / qty).round.to_i : nil,
            percent_of_total: total_revenue.positive? ? ((total.to_f / total_revenue) * 100).round(2) : 0.0
          }
        end.sort_by { |i| -i[:total_cents] }

        {
          period: { from: @from.iso8601, to: @to.iso8601 },
          summary: {
            total_cents: total_revenue,
            professionals_count: items.count { |i| i[:professional][:id].present? }
          },
          items: items
        }
      end

      private

      def base_scope
        Financial::Entry
          .for_account(@account.id)
          .income
          .for_dre
          .where(kind: RELEVANT_KINDS)
          .on_competence_date(@from, @to)
      end

      def build_professional_payload(prof_id, user)
        return { id: nil, name: 'Sem profissional', avatar_url: nil } if prof_id.nil? || user.nil?

        {
          id: user.id,
          name: user.name,
          avatar_url: user.try(:avatar_url)
        }
      end
    end
  end
end
