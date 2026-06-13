# Substitui Base64-fake-encryption por Rails Active Record Encryption real.
#
# Auditoria 2026-05-22 (`CRIT-SEC-03`): `Financial::GatewaySetting#encode_secret`
# usava `Base64.strict_encode64` — encoding, NÃO criptografia. Vazamento de
# DB → credenciais Asaas em texto claro (Base64 reversível em 1 linha).
#
# Esta migration:
# 1. Limpa dados legacy (Base64 não tem valor; sem cliente real em produção)
# 2. Renomeia `api_key_ciphertext` → `api_key`, `webhook_secret_ciphertext` → `webhook_secret`
# 3. Active Record Encryption armazena na própria coluna (sem sufixo)
#
# Após esta migration, o model usa `encrypts :api_key, :webhook_secret` direto.
# Initializer `config/initializers/active_record_encryption.rb` provê as chaves.
#
# IMPORTANTE: existing data Base64 é PERDIDA. Acceptable porque:
#   (a) Sem cliente real em produção ainda (Fase 1A premissa)
#   (b) Base64 era "encryption" inútil — clínica reconfigurando do zero é
#       melhor que falsa sensação de segurança
class ConvertGatewaySettingToActiveRecordEncryption < ActiveRecord::Migration[7.1]
  def up
    # Limpa Base64 legacy — vai ser recadastrado encrypted real
    execute <<~SQL
      UPDATE financial_gateway_settings
      SET api_key_ciphertext = NULL,
          webhook_secret_ciphertext = NULL;
    SQL

    if column_exists?(:financial_gateway_settings, :api_key_ciphertext)
      rename_column :financial_gateway_settings, :api_key_ciphertext, :api_key
    end

    if column_exists?(:financial_gateway_settings, :webhook_secret_ciphertext)
      rename_column :financial_gateway_settings, :webhook_secret_ciphertext, :webhook_secret
    end

    # Expandir o tipo se for VARCHAR pra acomodar payloads criptografados
    # (que podem ser bem maiores que o texto original por causa do envelope JSON).
    change_column :financial_gateway_settings, :api_key, :text
    change_column :financial_gateway_settings, :webhook_secret, :text
  end

  def down
    # Forward-only — Base64 era inseguro, reverter perderia chaves novas
    # e exporia chaves antigas em texto claro novamente.
    raise ActiveRecord::IrreversibleMigration,
          'Encryption real é forward-only. Restaurar credenciais via cadastro manual se necessário.'
  end
end
