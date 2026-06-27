# Cria Financial::Budget + Installment representando uma fee gerada pelo
# portal do paciente (Sprint H).
#
# Reusado por LateCancelFeeAssessor e NoShowFeeAssessor. A fee aparece no
# financeiro do paciente como uma parcela `pendente` normal — pagamento online
# (Sprint F/G) ou marcação manual pela recepção fecha o ciclo.
#
# Idempotência: se já existe um Budget do mesmo `origin_kind` apontando para
# o mesmo `agenda_event_id`, reusa o existente (evita duplicar fee em caso de
# reentry de callback ou retry de job).
module PatientPortal
  module Fees
    class FeeIssuer
      DUE_IN_DAYS = 3

      def initialize(account:, patient:, agenda_event:, kind:, amount_cents:, due_date: nil)
        @account = account
        @patient = patient
        @event   = agenda_event
        @kind    = kind.to_s # 'late_cancel' | 'no_show'
        @amount  = amount_cents.to_i
        @due_date = due_date || (Date.current + DUE_IN_DAYS.days)
      end

      # @return [Financial::Installment, nil] sempre retorna a Installment
      #   (entidade que o paciente vê na lista de cobranças). Quando idempotente
      #   (Budget já existia), busca a Installment do Budget existente.
      def call
        return nil if @amount <= 0

        existing_budget = find_existing
        return existing_budget.installments.first if existing_budget

        ActiveRecord::Base.transaction do
          budget = Financial::Budget.create!(
            account_id:        @account.id,
            patient_id:        @patient.id,
            professional_id:   @event&.user_id,
            origin:            'orcamento',
            status:            'aprovado',
            subtotal_cents:    @amount,
            total_cents:       @amount,
            installments_count: 1,
            approved_at:       Time.current,
            valid_until:       Date.current + 6.months,
            notes:             notes_text
          )

          Financial::Installment.create!(
            account_id:          @account.id,
            financial_budget_id: budget.id,
            patient_id:          @patient.id,
            professional_id:     @event&.user_id,
            number:              1,
            total_in_series:     1,
            amount_cents:        @amount,
            received_amount_cents: 0,
            due_date:            @due_date,
            competence_date:     Date.current,
            status:              'pendente',
            payment_method:      'pix'
          )
        end
      end

      private

      def find_existing
        return nil unless @event

        Financial::Budget.where(account_id: @account.id, patient_id: @patient.id)
                        .where("notes LIKE ?", "%#{tag}%")
                        .first
      end

      def tag
        "[PortalFee:#{@kind}:event=#{@event&.id}]"
      end

      def notes_text
        kind_label = @kind == 'late_cancel' ? 'cancelamento fora da janela' : 'falta (no-show)'
        "Taxa de #{kind_label} — consulta ##{@event&.id} #{tag}"
      end
    end
  end
end
