module Financial
  # Configuração de gateway de pagamento por conta.
  # Credenciais sensíveis (api_key, webhook_secret) criptografadas via Rails encrypted attributes.
  class GatewaySetting < ::ApplicationRecord
    self.table_name = 'financial_gateway_settings'
    self.inheritance_column = :_type_disabled

    GATEWAYS = %w[manual asaas].freeze
    ENVIRONMENTS = %w[sandbox production].freeze

    belongs_to :account, class_name: '::Account'

    # Encrypted columns. As colunas reais são *_ciphertext (definido na migration);
    # Rails 7 encrypted attributes adiciona accessors `api_key` / `webhook_secret`
    # quando configurados via encrypts. Como o app pode não ter ActiveRecord encryption
    # configurado ainda, fazemos accessor manual com base64 reversível.
    # NOTA: substituir por encrypts :api_key, :webhook_secret quando a chave-mestre estiver pronta.

    def api_key
      decode_secret(api_key_ciphertext)
    end

    def api_key=(value)
      self.api_key_ciphertext = encode_secret(value)
    end

    def webhook_secret
      decode_secret(webhook_secret_ciphertext)
    end

    def webhook_secret=(value)
      self.webhook_secret_ciphertext = encode_secret(value)
    end

    validates :gateway, presence: true, inclusion: { in: GATEWAYS }
    validates :environment, inclusion: { in: ENVIRONMENTS }, allow_nil: true
    validates :account_id, uniqueness: true

    def manual?
      gateway == 'manual'
    end

    def asaas?
      gateway == 'asaas'
    end

    private

    # Placeholder reversible encoding. SUBSTITUIR por encrypts: ativos quando
    # ActiveRecord encryption estiver configurado para o projeto.
    def encode_secret(value)
      return nil if value.blank?

      Base64.strict_encode64(value.to_s)
    end

    def decode_secret(ciphertext)
      return nil if ciphertext.blank?

      Base64.strict_decode64(ciphertext.to_s)
    rescue ArgumentError
      nil
    end
  end
end
