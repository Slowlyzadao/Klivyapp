module Financial
  module Reports
    # Ticket Médio — canon F-30 §sub-aba 3.
    #
    # Fórmula: receita ÷ pacientes únicos atendidos no período.
    # Comparativo entre profissionais (ranking).
    #
    # "Pacientes únicos" = pacientes distintos que receberam pagamento no
    # período (sem duplo-conte). Pra evitar inflar com retornos.
    # Receita = soma de PaymentReceipt.net_amount_cents (líquido após
    # deduções/MDR/etc).
    #
    # Especialidade não é coberta nesse MVP — não há campo de especialidade
    # direto na receita. Adicionar requer model work (canon F-30 nota técnica).
    #
    # Estrutura do retorno:
    # {
    #   period: { from:, to: },
    #   overall: {
    #     receita_cents:, patients_count:, ticket_medio_cents:
    #   },
    #   by_professional: [
    #     { id:, name:, avatar_url:, receita_cents:, patients_count:,
    #       ticket_medio_cents:, receipts_count: }
    #   ]
    # }
    class TicketMedioReport
      attr_reader :account, :from, :to

      def self.call(**kwargs) = new(**kwargs).call

      def initialize(account:, from:, to:)
        @account = account
        @from = from.to_date
        @to = to.to_date
      end

      def call
        # PaymentReceipt liga a Installment via `has_many :items` (não direto):
        # PaymentReceipt → PaymentReceiptItem → Installment → Budget.
        # Patient está direto na receipt (patient_id).
        receipts = base_scope

        {
          period: { from: @from, to: @to },
          overall: build_overall(receipts),
          by_professional: build_by_professional(receipts)
        }
      end

      private

      # Pagamentos efetivados no período (received_at é DATE, não datetime).
      # Usa net_amount_cents porque é o que efetivamente ENTROU pra clínica
      # (após dedução de MDR, juros, etc).
      def base_scope
        ::Financial::PaymentReceipt
          .where(account_id: @account.id)
          .where(received_at: @from..@to)
      end

      def build_overall(receipts)
        total_cents = receipts.sum(:net_amount_cents).to_i
        # PaymentReceipt já tem `patient_id` direto — sem JOIN.
        patients_count = receipts.distinct.count(:patient_id)

        {
          receita_cents: total_cents,
          patients_count: patients_count,
          ticket_medio_cents: ticket_medio(total_cents, patients_count)
        }
      end

      def build_by_professional(receipts)
        # PaymentReceipt liga a Installment via items (PaymentReceiptItem).
        # Cada receipt PODE pagar parcelas de múltiplas budgets (raro), mas
        # pra ranking de comissão simplificamos: receipt → professional da
        # PRIMEIRA budget tocada. Em produção real, splittar por item seria
        # mais preciso (TODO se necessário).
        receipt_prof_map = receipts
                             .joins(items: { installment: :budget })
                             .pluck(:id, 'financial_budgets.professional_id')
                             .uniq { |id, _| id } # 1ª (id, prof) por receipt
                             .to_h

        return [] if receipt_prof_map.empty?

        # Pega net + patient direto na receipt (sem JOIN — patient_id mora
        # em PaymentReceipt). Agrupa pelo prof do mapa acima.
        data_by_prof = receipts
                         .where(id: receipt_prof_map.keys)
                         .pluck(:id, :net_amount_cents, :patient_id)
                         .group_by { |id, _, _| receipt_prof_map[id] }

        prof_ids = data_by_prof.keys.compact
        professionals = ::User.where(id: prof_ids).index_by(&:id)

        rows = data_by_prof.map do |prof_id, triples|
          prof = professionals[prof_id]
          receita = triples.sum { |_, net, _| net.to_i }
          patients = triples.map { |_, _, pid| pid }.compact.uniq.size
          {
            id: prof_id,
            name: prof&.name || 'Sem profissional',
            avatar_url: prof.try(:resolved_avatar_url),
            receita_cents: receita,
            patients_count: patients,
            ticket_medio_cents: ticket_medio(receita, patients),
            receipts_count: triples.size
          }
        end

        rows.sort_by { |r| -r[:receita_cents] }
      end

      def ticket_medio(receita, patients)
        return 0 if patients.zero?
        (receita.to_f / patients).round
      end
    end
  end
end
