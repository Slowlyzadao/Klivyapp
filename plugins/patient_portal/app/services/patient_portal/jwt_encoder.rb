# Codifica/decodifica JWT do paciente.
#
# Claims:
#   - sub        : Patient#id
#   - account_id : account selecionada
#   - jti        : identificador único da sessão (pareado com PatientPortalSession)
#   - exp        : expiração
#
# Chave: SECRET_KEY_BASE da aplicação (mesma do Rails). Não vamos criar um secret
# separado no MVP — único par de chaves é suficiente, e o `jti` permite revogar
# uma sessão específica sem invalidar todas (mais cirúrgico que rotacionar segredo).
module PatientPortal
  class JwtEncoder
    ALGO = 'HS256'.freeze

    class InvalidTokenError < StandardError; end

    class << self
      def encode(patient_id:, account_id:, jti:, expires_at:)
        payload = {
          sub: patient_id,
          account_id: account_id,
          jti: jti,
          exp: expires_at.to_i,
          iat: Time.current.to_i
        }
        JWT.encode(payload, secret, ALGO)
      end

      def decode(token)
        decoded, _header = JWT.decode(token, secret, true, algorithm: ALGO)
        decoded.with_indifferent_access
      rescue JWT::DecodeError => e
        raise InvalidTokenError, e.message
      end

      private

      def secret
        Rails.application.secret_key_base
      end
    end
  end
end
