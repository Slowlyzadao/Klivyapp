# Envia OTP pro paciente. PRD §5.2:
#   - Email: ActionMailer (já funcional)
#   - WhatsApp: bloqueado no MVP (D-5 pendente) — flag `whatsapp_otp_enabled` ativa quando resolver
#
# Em dev, OTP também loga no Rails logger para testar sem checar inbox.
module PatientPortal
  class OtpDispatcher
    class WhatsappNotEnabledError < StandardError; end

    def initialize(otp:, identifier_kind:, channel:)
      @otp = otp
      @identifier_kind = identifier_kind
      @channel = channel
    end

    def call
      log_for_dev
      case @channel
      when 'email'    then send_email
      when 'whatsapp' then send_whatsapp
      else raise ArgumentError, "Canal desconhecido: #{@channel}"
      end
    end

    private

    def send_email
      return unless @identifier_kind == :email

      mail = PatientPortal::OtpMailer.send_code(email: @otp.identifier, code: @otp.code)
      # Em dev usamos deliver_now para abrir letter_opener (ou ver erro no log)
      # imediatamente, sem passar pelo Sidekiq. Prod usa _later.
      Rails.env.development? || Rails.env.test? ? mail.deliver_now : mail.deliver_later
    end

    def send_whatsapp
      # D-5 do PRD §19.4 — decisão executiva pendente sobre WhatsApp Business
      # próprio Klivy vs inbox da clínica. Por enquanto, recusa.
      raise WhatsappNotEnabledError, 'Envio de OTP por WhatsApp ainda não está ativo. Use email.'
    end

    def log_for_dev
      return unless Rails.env.development? || Rails.env.test?

      Rails.logger.warn("\n=== [PatientPortal OTP] ===\n  identifier: #{@otp.identifier}\n  channel:    #{@channel}\n  code:       #{@otp.code}\n  expires_at: #{@otp.expires_at}\n===========================\n")
    end
  end
end
