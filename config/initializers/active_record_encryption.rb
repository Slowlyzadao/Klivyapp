# Active Record Encryption configuration
#
# Permite usar `encrypts :col_name` em models — usado em
# `Financial::GatewaySetting` pra api_key/webhook_secret (CRIT-SEC-03).
#
# Chaves são lidas de env vars (dev/prod). Fallback p/ dev com chaves
# determinísticas a partir do `secret_key_base` — NÃO use em produção.
#
# Gerar chaves novas em prod:
#   bin/rails db:encryption:init
#   # copia o YAML resultante pra credentials.yml.enc OU pra ENV:
#   #   ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
#   #   ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
#   #   ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
#
# Rotacionar chaves:
#   bin/rails db:encryption:init → adiciona nova
#   Mantém antiga em config até todos os registros serem reencrypted

Rails.application.config.active_record.encryption.tap do |enc|
  primary       = ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY']
  deterministic = ENV['ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY']
  salt          = ENV['ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT']

  if primary.present? && deterministic.present? && salt.present?
    enc.primary_key            = primary
    enc.deterministic_key      = deterministic
    enc.key_derivation_salt    = salt
  else
    # Fallback de DEV / TEST — deriva do secret_key_base.
    # Em produção, sempre setar as ENV vars acima (kill switch: rejeita boot
    # se chaves não estiverem disponíveis fora de development/test).
    if Rails.env.production?
      raise <<~MSG
        Active Record Encryption keys ausentes em produção.
        Setar ENV vars:
          ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
          ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
          ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
        Gerar via: bin/rails db:encryption:init
      MSG
    end

    base = Rails.application.secret_key_base.to_s
    raise 'secret_key_base ausente — encryption não pode derivar chaves' if base.blank?

    enc.primary_key            = Digest::SHA256.hexdigest("ar_enc:primary:#{base}")[0, 32]
    enc.deterministic_key      = Digest::SHA256.hexdigest("ar_enc:deterministic:#{base}")[0, 32]
    enc.key_derivation_salt    = Digest::SHA256.hexdigest("ar_enc:salt:#{base}")[0, 32]
  end

  # Suporte a leitura de dados em texto puro (Base64) durante migração.
  # Quando lê uma coluna que NÃO está encriptada (legacy data), retorna o
  # valor cru. Após migration de re-encrypt rodar, pode-se desativar.
  enc.support_unencrypted_data = true

  # Logging: nunca logar valores encriptados (proteção contra leak em logs).
  enc.encrypt_fixtures = false

  # Propaga as chaves pro `ActiveRecord::Encryption.config` (objeto separado
  # do `Rails.application.config.active_record.encryption`). Sem essa chamada,
  # `encrypts :col, deterministic: true` explode com
  # "Missing Active Record encryption credential: deterministic_key" no
  # primeiro save — mesmo com as chaves "setadas" via Rails config, porque
  # `ActiveRecord::Encryption::EncryptedAttributeType` lê de
  # `ActiveRecord::Encryption.config` (que é populado pelo railtie do AR
  # ANTES desse initializer rodar — então config setado aqui não chega lá).
  ActiveRecord::Encryption.configure(
    primary_key: enc.primary_key,
    deterministic_key: enc.deterministic_key,
    key_derivation_salt: enc.key_derivation_salt,
    support_unencrypted_data: enc.support_unencrypted_data
  )
end
