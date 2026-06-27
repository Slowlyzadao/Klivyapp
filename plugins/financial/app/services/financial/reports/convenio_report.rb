module Financial
  module Reports
    # Faturamento por Convênio — canon F-30 §sub-aba 2.
    #
    # Por operadora (faturado, recebido, ticket médio). Filtro
    # convênio/particular/todos. Identifica gap entre faturado e recebido.
    #
    # Convênio = `Patient.insurance['name']` (jsonb). Se name vazio →
    # "Particular". Glosa e inadimplência simplificadas (canon F-30 nota
    # técnica permite; modelo dedicado seria expansão futura).
    #
    # "Faturado" = soma de Budget.total_cents APROVADOS no período.
    # "Recebido" = soma de PaymentReceipt.net_amount_cents recebidos no período.
    # "Em aberto" = soma de Installment pendentes/vencidas dos budgets aprovados
    # no período (gap faturado vs recebido).
    #
    # Estrutura do retorno:
    # {
    #   period: { from:, to: },
    #   filter: { mode: 'all' | 'convenio' | 'particular' },
    #   summary: {
    #     faturado_cents:, recebido_cents:, em_aberto_cents:,
    #     patients_count:, ticket_medio_cents:
    #   },
    #   operadoras: [
    #     { name:, faturado_cents:, recebido_cents:, em_aberto_cents:,
    #       patients_count:, ticket_medio_cents:, gap_cents: }
    #   ]
    # }
    class ConvenioReport
      attr_reader :account, :from, :to, :mode

      def self.call(**kwargs) = new(**kwargs).call

      def initialize(account:, from:, to:, mode: 'all')
        @account = account
        @from = from.to_date
        @to = to.to_date
        @mode = %w[all convenio particular].include?(mode.to_s) ? mode.to_s : 'all'
      end

      def call
        budgets = budgets_in_period
        receipts = receipts_in_period
        operadoras = build_operadoras(budgets, receipts)

        {
          period: { from: @from, to: @to },
          filter: { mode: @mode },
          summary: build_summary(operadoras),
          operadoras: operadoras
        }
      end

      private

      def budgets_in_period
        # Statuses canon do Budget: rascunho|enviado|aprovado|cancelado|concluido.
        # Pegamos `aprovado` e `concluido` (orçamentos efetivamente faturados).
        ::Financial::Budget
          .where(account_id: @account.id)
          .where(status: %w[aprovado concluido])
          .where(approved_at: @from.beginning_of_day..@to.end_of_day)
          .includes(:patient, :installments)
      end

      def receipts_in_period
        # PaymentReceipt tem `patient_id` direto — sem precisar atravessar
        # items → installment → budget pra achar o paciente.
        ::Financial::PaymentReceipt
          .where(account_id: @account.id)
          .where(received_at: @from..@to)
          .includes(:patient)
      end

      def build_operadoras(budgets, receipts)
        # Agrupa budgets por (insurance.name || 'Particular'), respeitando
        # o filtro mode.
        grouped_budgets = budgets.group_by { |b| operadora_for(b.patient) }
        # Receipts: paciente acessível direto (belongs_to :patient).
        grouped_receipts = receipts.group_by { |r| operadora_for(r.patient) }

        names = (grouped_budgets.keys + grouped_receipts.keys).uniq
                  .reject { |n| skip_by_mode?(n) }

        names.map do |name|
          bs = grouped_budgets[name] || []
          rs = grouped_receipts[name] || []
          faturado = bs.sum(&:total_cents).to_i
          recebido = rs.sum(&:net_amount_cents).to_i
          patient_ids = (bs.map(&:patient_id) + rs.map(&:patient_id)).compact.uniq
          patients_count = patient_ids.size

          # Em aberto — somatório de saldos restantes nas parcelas ligadas
          # aos budgets dessa operadora. Schema usa `amount_cents` e
          # `received_amount_cents` (não total_cents/paid_amount_cents).
          em_aberto = bs.flat_map(&:installments)
                        .select { |i| %w[pendente vencido parcial].include?(i.status) }
                        .sum do |i|
                          gross = i.amount_cents.to_i
                          received = i.received_amount_cents.to_i
                          (gross - received).clamp(0, gross)
                        end
                        .to_i

          {
            name: name,
            faturado_cents: faturado,
            recebido_cents: recebido,
            em_aberto_cents: em_aberto,
            gap_cents: (faturado - recebido).clamp(0, faturado),
            patients_count: patients_count,
            ticket_medio_cents: ticket_medio(recebido, patients_count)
          }
        end.sort_by { |op| -op[:faturado_cents] }
      end

      def build_summary(operadoras)
        faturado = operadoras.sum { |o| o[:faturado_cents] }
        recebido = operadoras.sum { |o| o[:recebido_cents] }
        em_aberto = operadoras.sum { |o| o[:em_aberto_cents] }
        patients = operadoras.sum { |o| o[:patients_count] }

        {
          faturado_cents: faturado,
          recebido_cents: recebido,
          em_aberto_cents: em_aberto,
          patients_count: patients,
          ticket_medio_cents: ticket_medio(recebido, patients)
        }
      end

      # Pega `insurance.name` do Patient (jsonb). Vazio → "Particular".
      def operadora_for(patient)
        return 'Particular' if patient.nil?
        ins = patient.insurance.is_a?(Hash) ? patient.insurance : {}
        name = ins['name'].to_s.strip.presence || ins[:name].to_s.strip.presence
        name || 'Particular'
      end

      def skip_by_mode?(name)
        case @mode
        when 'convenio'   then name == 'Particular'
        when 'particular' then name != 'Particular'
        else                   false
        end
      end

      def ticket_medio(receita, patients)
        return 0 if patients.zero?
        (receita.to_f / patients).round
      end
    end
  end
end
