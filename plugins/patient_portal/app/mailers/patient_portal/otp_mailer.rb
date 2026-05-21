# Mailer minimalista pro OTP. ActionMailer aproveita layout do projeto.
# Em dev, OtpDispatcher também loga o código no console.
module PatientPortal
  class OtpMailer < ApplicationMailer
    def send_code(email:, code:)
      @code = code
      mail(
        to: email,
        subject: 'Seu código de acesso ao Portal do Paciente',
        from: ENV.fetch('MAILER_SENDER_EMAIL', 'no-reply@klivy.app')
      )
    end
  end
end
