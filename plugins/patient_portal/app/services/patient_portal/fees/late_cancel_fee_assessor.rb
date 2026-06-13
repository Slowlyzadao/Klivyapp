# Avalia fee de cancelamento tardio (Sprint H, PRD §9.3).
#
# Chamado pelo controller de cancelamento DO PORTAL após `soft_delete!` —
# nunca pelo cancelamento da recepção (esse é controlado pela clínica).
#
# Regras:
#   - Só cobra se setting `financial.late_cancel_auto_invoice` for true.
#   - Só cobra se a consulta foi cancelada DENTRO da janela protegida
#     (starts_at - now < cancel_window_hours).
#   - Valor: `late_cancel_fee_cents` (absoluto) ou `late_cancel_fee_percent`
#     sobre o preço do serviço — Calculator decide a prioridade.
#   - Idempotente: se já existe Budget pra este `agenda_event_id` + kind, reusa.
#   - Notifica o paciente in-app (kind=`financial_charge`) + push.
module PatientPortal
  module Fees
    class LateCancelFeeAssessor
      Result = Struct.new(:assessed, :installment, :fee_cents, :reason, keyword_init: true) do
        def assessed? = !!assessed
        def to_h
          { assessed: assessed?, installment_id: installment&.id, fee_cents: fee_cents, reason: reason }
        end
      end

      def initialize(appointment:, actor: nil, now: Time.current)
        @event   = appointment
        @account = appointment.account
        @actor   = actor
        @now     = now
        # Quando actor é o próprio paciente (fluxo controller), o controller
        # passa current_patient. Caso contrário, resolve via contact_id como
        # o NoShowFeeAssessor faz.
        @patient = actor.is_a?(Patient) ? actor :
                   Patient.find_by(account_id: @account&.id, contact_id: appointment.contact_id)
      end

      def call
        return skip('cancel_outside_window') unless within_window?

        cfg = fee_config
        return skip('not_enabled') unless cfg[:enabled]

        amount = Calculator.compute(
          fixed_cents: cfg[:fixed_cents],
          percent:     cfg[:percent],
          base_cents:  service_base_cents
        )
        return skip('amount_zero') if amount <= 0

        installment = FeeIssuer.new(
          account: @account, patient: @patient, agenda_event: @event,
          kind: 'late_cancel', amount_cents: amount
        ).call
        return skip('issuer_failed') unless installment

        notify!(installment, amount)
        Result.new(assessed: true, installment: installment, fee_cents: amount, reason: 'charged')
      rescue StandardError => e
        Rails.logger.error("[LateCancelFeeAssessor] #{e.class} #{e.message}")
        Result.new(assessed: false, fee_cents: 0, reason: "error: #{e.class}")
      end

      private

      def skip(reason)
        Result.new(assessed: false, fee_cents: 0, reason: reason)
      end

      def within_window?
        return false unless @event&.starts_at

        window_h = fee_config[:window_hours].to_i
        return true if window_h.zero? # 0 = sempre aplica

        (@event.starts_at - @now) < window_h.hours
      end

      def fee_config
        @fee_config ||= begin
          setting = @account.patient_portal_setting
          fin = setting&.financial || {}
          resched = setting&.rescheduling || {}
          {
            enabled:      fin['late_cancel_auto_invoice'] == true,
            fixed_cents:  fin['late_cancel_fee_cents'],
            percent:      fin['late_cancel_fee_percent'],
            window_hours: resched['cancel_window_hours'] || 24
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
          title: 'Taxa de cancelamento gerada',
          body:  "Foi gerada uma cobrança de #{format_currency(amount)} pelo cancelamento da consulta.",
          payload: { installment_id: installment.id, agenda_event_id: @event.id, fee_kind: 'late_cancel' }
        )
      end

      def format_currency(cents)
        "R$ #{format('%.2f', (cents || 0) / 100.0).tr('.', ',')}"
      end
    end
  end
end
