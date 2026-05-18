module AiAgent
  module InternalNotifier
    # Prepend module no BookAppointmentTool — captura o resultado do `execute`
    # e dispara `AppointmentBookingFailed` quando relevante. Não muda o
    # comportamento da tool (resultado é repassado intacto), só observa.
    #
    # Wired no engine.rb pra evitar que tocar o tool por aqui crie
    # acoplamento — o prepend roda em to_prepare, idempotente.
    module BookAppointmentToolPrepend
      def execute(*args, **kwargs)
        result = super
        notify_failure_if_needed(result)
        notify_debt_if_needed(result)
        result
      end

      private

      def notify_failure_if_needed(result)
        return unless respond_to?(:account, true) && respond_to?(:contact_id, true)

        AiAgent::InternalNotifier::AppointmentBookingFailed.call(
          account: account,
          contact_id: contact_id,
          result: result
        )
      rescue StandardError => e
        Rails.logger.warn(
          "[AiAgent::InternalNotifier::BookAppointmentToolPrepend] notify_failure falhou: #{e.class}: #{e.message}"
        )
      end

      def notify_debt_if_needed(result)
        return unless result.is_a?(Hash) && (result[:booked] || result['booked'])
        return unless respond_to?(:account, true) && respond_to?(:contact_id, true)
        return if contact_id.blank?

        debt = AiAgent::Detectors::PatientDebt.check(account: account, contact_id: contact_id)
        AiAgent::InternalNotifier::PatientDebtAlert.call(
          account: account,
          contact_id: contact_id,
          debt_result: debt
        )
      rescue StandardError => e
        Rails.logger.warn(
          "[AiAgent::InternalNotifier::BookAppointmentToolPrepend] notify_debt falhou: #{e.class}: #{e.message}"
        )
      end
    end
  end
end
