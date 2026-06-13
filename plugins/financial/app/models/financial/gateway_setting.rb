module Financial
  # Configuração de gateway de pagamento por conta.
  #
  # Auditoria 2026-05-22 (`CRIT-SEC-03`): Antes usava `Base64.strict_encode64`
  # (encoding, não encryption). Agora usa Rails Active Record Encryption real
  # — chaves derivadas em `config/initializers/active_record_encryption.rb`.
  # Vazamento de DB → ciphertext encriptado, sem valor sem a master key.
  class GatewaySetting < ::ApplicationRecord
    self.table_name = 'financial_gateway_settings'
    self.inheritance_column = :_type_disabled

    GATEWAYS = %w[manual asaas].freeze
    ENVIRONMENTS = %w[sandbox production].freeze

    belongs_to :account, class_name: '::Account'

    # Active Record Encryption — chaves derivadas no initializer.
    # `deterministic: false` significa que cada save gera ciphertext novo
    # (default, mais seguro). Tradeoff: não permite query por valor encriptado.
    # Aqui não buscamos por api_key, então fine.
    encrypts :api_key,        deterministic: false
    encrypts :webhook_secret, deterministic: false

    validates :gateway, presence: true, inclusion: { in: GATEWAYS }
    validates :environment, inclusion: { in: ENVIRONMENTS }, allow_nil: true
    validates :account_id, uniqueness: true

    def manual?
      gateway == 'manual'
    end

    def asaas?
      gateway == 'asaas'
    end

    # Indica se este setting tem credenciais cadastradas (sem vazar valor real).
    # UI mostra "Configurado ✓" sem expor api_key.
    def configured?
      api_key.present? && webhook_secret.present?
    end
  end
end
