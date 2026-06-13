# Orquestra request_otp / verify_otp / select_account.
# Mantém os controllers magros — toda a lógica de negócio fica aqui.
module PatientPortal
  class Authenticator
    class FloodError < StandardError; end
    class InvalidOtpError < StandardError; end
    class NoContactError < StandardError; end

    # ─── PASSO 1: paciente pediu OTP ────────────────────────────────────────
    def self.request_otp(identifier_raw:, channel:, ip:)
      kind, value = IdentifierNormalizer.call(identifier_raw)
      raise NoContactError, 'Identificador inválido.' if kind == :unknown

      # Anti-flood: máx MAX_OTPS_PER_DAY por identifier nas últimas 24h
      recent_count = PatientPortalOtp.where(identifier: value)
                                      .where('created_at > ?', 24.hours.ago)
                                      .count
      raise FloodError, 'Muitas tentativas. Tente novamente mais tarde.' if recent_count >= PatientPortalOtp::MAX_OTPS_PER_DAY

      # Verifica se identificador tem algum Contact/Patient ativo
      result = PatientFinder.new(identifier_kind: kind, normalized_value: value).call
      raise NoContactError, 'Não encontramos seu cadastro. Procure a clínica.' if result.empty?

      code = PatientPortalOtp.generate_code
      otp = PatientPortalOtp.create!(
        identifier: value,
        channel:    channel,
        ip:         ip,
        code:       code
      )
      # `code` é attr_accessor — não persiste; só o digest sobrevive.
      otp.code = code

      OtpDispatcher.new(otp: otp, identifier_kind: kind, channel: channel).call
      { sent: true, channel: channel }
    end

    # ─── PASSO 2: paciente digitou OTP ──────────────────────────────────────
    def self.verify_otp(identifier_raw:, code:, ip:)
      _kind, value = IdentifierNormalizer.call(identifier_raw)
      otp = PatientPortalOtp.where(identifier: value).order(created_at: :desc).first
      raise InvalidOtpError, 'OTP inválido ou expirado.' unless otp&.consumable?

      unless otp.matches?(code)
        otp.register_failed_attempt!
        raise InvalidOtpError, 'Código incorreto.'
      end

      otp.consume!

      kind = value.include?('@') ? :email : :phone
      result = PatientFinder.new(identifier_kind: kind, normalized_value: value).call
      raise NoContactError, 'Cadastro não encontrado.' if result.empty?

      # Emite token temporário (5 min) com a lista de accounts permitidas;
      # SPA chama select_account em seguida.
      temp_jti = SecureRandom.urlsafe_base64(16)
      token = JwtEncoder.encode(
        patient_id: result.patients.first.id, # sub é só placeholder no temp
        account_id: nil,
        jti: temp_jti,
        expires_at: 5.minutes.from_now
      )

      {
        temp_token: token,
        patients: result.patients.map { |p|
          { patient_id: p.id, account_id: p.account_id, account_name: p.account.name, patient_name: p.name }
        }
      }
    end

    # ─── PASSO 3: paciente escolheu clínica ────────────────────────────────
    def self.select_account(patient_id:, account_id:, ip:, user_agent:)
      patient = Patient.find_by(id: patient_id, account_id: account_id)
      raise NoContactError, 'Vínculo não encontrado.' unless patient&.portal_active?

      jti = SecureRandom.urlsafe_base64(16)
      expires_at = PatientPortalSession::DEFAULT_TTL_DAYS.days.from_now

      session = PatientPortalSession.create!(
        account_id:        account_id,
        patient_id:        patient.id,
        active_patient_id: patient.id, # Sprint I — default = self-access
        jwt_jti:           jti,
        expires_at:        expires_at,
        ip:                ip,
        user_agent:        user_agent
      )

      jwt = JwtEncoder.encode(
        patient_id: patient.id,
        account_id: account_id,
        jti:        jti,
        expires_at: expires_at
      )

      PatientPortalAccessLog.log!(
        account: patient.account, patient: patient,
        action: 'login_account_selected', ip: ip, user_agent: user_agent
      )

      { jwt: jwt, expires_at: expires_at, session_id: session.id, patient: patient }
    end
  end
end
