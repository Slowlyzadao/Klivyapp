# frozen_string_literal: true

# Token signed via Rails::MessageVerifier que carrega referência ao blob +
# account_id + expiração. Usado por `SecureBlobsController` para validar
# acesso cross-tenant a Active Storage blobs (Roadmap #17.1).
#
# Decisões:
# - `Rails.application.message_verifier(:secure_blob)` — namespace dedicado
#   permite rotacionar a chave deste verifier sem afetar outros tokens.
# - `JSON.generate({...}).then { |data| verify.generate(data) }` — payload
#   é JSON puro (sem objetos Ruby) para evitar Marshal/symbol → ruby (CVE
#   risk em deserialization).
# - `expires_at` codificado como Unix timestamp (Integer) — comparação
#   direta com `Time.current.to_i`, sem fuso horário.
# - `transformations` opcional — para variants de imagem (thumbnails). Hash
#   com apenas keys aceitas pelo ActiveStorage::Variant.
#
# Tokens são opacos: o caller (Document#signed_url, etc.) só chama
# `.encode(...)` e recebe a URL final. Validação acontece no controller.
module Patients
  class SecureBlobTokenService
    VERIFIER_NAMESPACE = :secure_blob
    DEFAULT_EXPIRES_IN = 15.minutes

    Expired   = Class.new(StandardError)
    Tampered  = Class.new(StandardError)
    Malformed = Class.new(StandardError)

    class << self
      # @param blob_id [Integer] ID do ActiveStorage::Blob
      # @param account_id [Integer] account que pode acessar o blob
      # @param expires_in [ActiveSupport::Duration] janela de validade do token
      # @param transformations [Hash, nil] params de variant (e.g., { resize_to_limit: [400, 400] })
      # @return [String] token assinado, seguro para query param
      def encode(blob_id:, account_id:, expires_in: DEFAULT_EXPIRES_IN, transformations: nil)
        payload = {
          'blob_id' => Integer(blob_id),
          'account_id' => Integer(account_id),
          'expires_at' => (Time.current + expires_in).to_i
        }
        payload['transformations'] = stringify_transformations(transformations) if transformations.present?

        verifier.generate(JSON.generate(payload))
      end

      # @param token [String]
      # @return [Hash{Symbol=>Object}] { blob_id:, account_id:, expires_at:, transformations: }
      # @raise [Tampered] assinatura inválida (chave secret diferente, payload alterado)
      # @raise [Expired] expires_at < now
      # @raise [Malformed] JSON inválido ou campos obrigatórios ausentes
      def decode!(token)
        raw = verifier.verify(token)
        data = JSON.parse(raw)

        validate_shape!(data)
        validate_freshness!(data)

        {
          blob_id: data['blob_id'],
          account_id: data['account_id'],
          expires_at: Time.zone.at(data['expires_at']),
          transformations: data['transformations']&.symbolize_keys
        }
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        raise Tampered
      rescue JSON::ParserError, ArgumentError, TypeError
        raise Malformed
      end

      private

      def verifier
        Rails.application.message_verifier(VERIFIER_NAMESPACE)
      end

      def validate_shape!(data)
        raise Malformed unless data.is_a?(Hash)
        raise Malformed unless data['blob_id'].is_a?(Integer)
        raise Malformed unless data['account_id'].is_a?(Integer)
        raise Malformed unless data['expires_at'].is_a?(Integer)
      end

      def validate_freshness!(data)
        raise Expired if Time.current.to_i >= data['expires_at']
      end

      # ActiveStorage variant transformations devem ser whitelist do Rails.
      # Stringificamos as keys porque JSON round-trip vira string mesmo —
      # padronizar evita surpresa no decode.
      def stringify_transformations(transformations)
        transformations.transform_keys(&:to_s)
      end
    end
  end
end
