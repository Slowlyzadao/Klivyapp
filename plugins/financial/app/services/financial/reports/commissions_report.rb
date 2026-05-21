module Financial
  module Reports
    # Relatório de Comissões — canon F-29.
    #
    # Agrupa CommissionEntries por profissional dentro do período (filtro
    # competence_date), com totais por status (devida / paga / estornada).
    # Estornadas entram com sinal NEGATIVO no total geral pra refletir
    # ajustes (canon F-29 §critérios: "Estornos como linha negativa").
    #
    # Estrutura do retorno:
    # {
    #   period: { from:, to: },
    #   filter: { professional_id: },
    #   summary: {
    #     total_due_cents:, total_paid_cents:, total_reversed_cents:,
    #     total_net_cents:, professionals_count:, entries_count:
    #   },
    #   professionals: [
    #     { id:, name:, avatar_url:,
    #       totals: { due_cents:, paid_cents:, reversed_cents:, net_cents: },
    #       entries: [ { id, status, status_label, competence_date, paid_at,
    #                    base_amount_cents, calc_base_cents, percent_basis_points,
    #                    commission_amount_cents, signed_amount_cents,
    #                    patient: {...}, payment_receipt: {...},
    #                    installment: {...}, deductions: {...}, expense_id } ]
    #     }
    #   ]
    # }
    class CommissionsReport
      STATUS_LABELS = {
        'provisionada' => 'Provisionada',
        'devida'       => 'Devida',
        'paga'         => 'Paga',
        'estornada'    => 'Estornada'
      }.freeze

      attr_reader :account, :from, :to, :professional_id

      def self.call(**kwargs) = new(**kwargs).call

      def initialize(account:, from:, to:, professional_id: nil)
        @account = account
        @from = from.to_date
        @to = to.to_date
        @professional_id = professional_id.presence
      end

      def call
        scope = base_scope
        all_entries = scope
                        .includes(:professional, :payment_receipt,
                                  :commission_rule, :expense,
                                  installment: [:patient, budget: :items])
                        .order(competence_date: :desc, id: :desc)
                        .to_a

        professionals = group_by_professional(all_entries)

        {
          period: { from: @from, to: @to },
          filter: { professional_id: @professional_id&.to_i },
          summary: build_summary(all_entries, professionals),
          professionals: professionals
        }
      end

      private

      # Provisionadas NÃO entram no relatório (ainda nem foram recebidas —
      # canon: provisionada vira devida quando o pagamento entra).
      # O relatório foca em devida/paga/estornada (operação de pagamento).
      def base_scope
        scope = ::Financial::CommissionEntry
                  .for_account(@account.id)
                  .where(status: %w[devida paga estornada])
                  .on_competence(@from, @to)
        scope = scope.for_professional(@professional_id) if @professional_id
        scope
      end

      def group_by_professional(entries)
        grouped = entries.group_by(&:professional_id)
        grouped.map do |prof_id, prof_entries|
          professional = prof_entries.first.professional
          {
            id: prof_id,
            name: professional&.name || "Profissional ##{prof_id}",
            avatar_url: professional.try(:resolved_avatar_url),
            totals: totals_for(prof_entries),
            entries_count: prof_entries.size,
            entries: prof_entries.map { |e| serialize_entry(e) }
          }
        end.sort_by { |p| -p[:totals][:net_cents] }
      end

      def totals_for(entries)
        due       = entries.select { |e| e.status == 'devida' }.sum(&:commission_amount_cents).to_i
        paid      = entries.select { |e| e.status == 'paga'   }.sum(&:commission_amount_cents).to_i
        reversed  = entries.select { |e| e.status == 'estornada' }.sum(&:commission_amount_cents).to_i
        # Estornadas entram com sinal negativo (canon F-29 §critérios).
        net       = due + paid - reversed
        { due_cents: due, paid_cents: paid, reversed_cents: reversed, net_cents: net }
      end

      def build_summary(all_entries, professionals)
        totals_aggregate = professionals.each_with_object(
          due_cents: 0, paid_cents: 0, reversed_cents: 0, net_cents: 0
        ) do |p, acc|
          acc[:due_cents]      += p[:totals][:due_cents]
          acc[:paid_cents]     += p[:totals][:paid_cents]
          acc[:reversed_cents] += p[:totals][:reversed_cents]
          acc[:net_cents]      += p[:totals][:net_cents]
        end

        {
          total_due_cents:      totals_aggregate[:due_cents],
          total_paid_cents:     totals_aggregate[:paid_cents],
          total_reversed_cents: totals_aggregate[:reversed_cents],
          total_net_cents:      totals_aggregate[:net_cents],
          professionals_count:  professionals.size,
          entries_count:        all_entries.size
        }
      end

      def serialize_entry(e)
        receipt = e.payment_receipt
        installment = e.installment
        patient = installment&.patient
        budget = installment&.budget
        # Estornos exibidos como negativos pra usuário visualizar imediatamente.
        signed = e.status == 'estornada' ? -e.commission_amount_cents.to_i : e.commission_amount_cents.to_i

        {
          id: e.id,
          status: e.status,
          status_label: STATUS_LABELS[e.status] || e.status,
          competence_date: e.competence_date,
          paid_at: e.paid_at,
          base_amount_cents: e.base_amount_cents.to_i,
          calc_base_cents: e.calc_base_cents.to_i,
          percent_basis_points: e.percent_basis_points,
          commission_amount_cents: e.commission_amount_cents.to_i,
          signed_amount_cents: signed,
          deductions: {
            mdr_cents: e.mdr_deduction_cents.to_i,
            lab_cents: e.lab_deduction_cents.to_i
          },
          patient: patient ? {
            id: patient.id,
            name: patient.name,
            avatar_url: patient.try(:resolved_avatar_url)
          } : nil,
          procedure_name: extract_procedure_name(budget),
          installment: installment ? {
            id: installment.id,
            number: installment.number,
            total_in_series: installment.total_in_series
          } : nil,
          payment_receipt: receipt ? {
            id: receipt.id,
            receipt_number: receipt.receipt_number,
            received_at: receipt.received_at,
            payment_method: receipt.payment_method,
            net_amount_cents: receipt.net_amount_cents.to_i
          } : nil,
          expense_id: e.financial_expense_id
        }
      end

      # Tenta inferir o procedimento a partir do primeiro item do orçamento.
      # Mesma estratégia usada no relatório de comissão tradicional —
      # canon F-29 §tabela-colunas pede "procedimento".
      def extract_procedure_name(budget)
        return nil unless budget
        first_item = budget.items.first
        first_item&.description.presence || first_item&.procedure&.try(:name) || budget.notes.presence
      end
    end
  end
end
