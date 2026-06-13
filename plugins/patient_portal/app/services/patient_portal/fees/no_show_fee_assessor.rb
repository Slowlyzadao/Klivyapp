# Avalia fee de no-show — disparado quando AgendaEvent transita pra `no_show`
# (Sprint H, PRD §9.3).
#
# Acionado por callback registrado no Engine (`after_update_commit` em
# AgendaEvent). Não importa quem mudou o status — recepção, profissional, job
# automático — qualquer caminho dispara este assessor.
#
# Regras (paralelo ao LateCancelFeeAssessor):
#   - Só cobra se setting `financial.no_show_auto_invoice` for true.
#   - Idempotente: FeeIssuer cuida (mesmo event_id + kind = 1 só Budget).
#   - Valor: `no_show_fee_cents` ou `no_show_fee_percent`.
module PatientPortal
  module Fees
    class NoShowFeeAssessor
      Result = Struct.new(:assessed, :installment, :fee_cents, :reason, keyword_init: true) do
        def assessed? = !!assessed
        def to_h
          { assessed: assessed?, installment_id: installment&.id, fee_cents: fee_cents, reason: reason }
        end
      end

      def initialize(event:)
        @event   = event
        @account = event.account
        # AgendaEvent.contact_id aponta pro Chatwoot Contact; Patient é
        # linkado via Patient.contact_id. Navegamos por essa coluna.
        @patient = resolve_patient
      end

      private

      def resolve_patient
        return nil unless @event && @account

        Patient.find_by(account_id: @account.id, contact_id: @event.contact_id)
      end

      public

      def call
        return skip('event_not_no_show')   unless @event&.status == 'no_show'
        return skip('patient_not_found')   unless @patient

        cfg = fee_config
        return skip('not_enabled')  unless cfg[:enabled]

        amount = Calculator.compute(
          fixed_cents: cfg[:fixed_cents],
          percent:     cfg[:percent],
          base_cents:  service_base_cents
        )
        return skip('amount_zero') if amount <= 0

        installment = FeeIssuer.new(
          account: @account, patient: @patient, agenda_event: @event,
          kind: 'no_show', amount_cents: amount
        ).call
        return skip('issuer_failed') unless installment

        notify!(installment, amount)
        Result.new(assessed: true, installment: installment, fee_cents: amount, reason: 'charged')
      rescue StandardError => e
        Rails.logger.error("[NoShowFeeAssessor] #{e.class} #{e.message}")
        Result.new(assessed: false, fee_cents: 0, reason: "error: #{e.class}")
      end

      private

      def skip(reason)
        Result.new(assessed: false, fee_cents: 0, reason: reason)
      end

      def fee_config
        @fee_config ||= begin
          fin = @account.patient_portal_setting&.financial || {}
          {
            enabled:     fin['no_show_auto_invoice'] == true,
            fixed_cents: fin['no_show_fee_cents'],
            percent:     fin['no_show_fee_percent']
          }
        end
      end

      def service_base_cents
        return 0 unless @event&.agenda_service

        if @event.agenda_service.respond_to?(:price_cents)
          @event.agenda_service.price_cents.to_i
        else
          (@event.agenda_service.try(:price).to_f * 100).round
        end
      end

      def notify!(installment, amount)
        PatientPortal::NotificationDispatcher.dispatch(
          account: @account, patient: @patient,
          kind: 'financial_charge',
          title: 'Cobrança por falta',
          body:  "Foi gerada uma cobrança de #{format_currency(amount)} pela falta na consulta.",
          payload: { installment_id: installment.id, agenda_event_id: @event.id, fee_kind: 'no_show' }
        )
      end

      def format_currency(cents)
        "R$ #{format('%.2f', (cents || 0) / 100.0).tr('.', ',')}"
      end
    end
  end
end
