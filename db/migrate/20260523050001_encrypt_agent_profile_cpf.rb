# Criptografa `cpf` em `financial_agent_profiles` via Active Record Encryption.
#
# CPF é dado pessoal sensível (LGPD art. 5º II). Antes desta migration o campo
# era `string(20)` em texto plano — vazamento de DB → CPFs expostos.
#
# Decisão: `deterministic: true` (mesmo plaintext → mesmo ciphertext) pra
# permitir queries WHERE cpf = '...' e (futuramente) índice único por
# `(account_id, cpf)`. Tradeoff: análise estatística pode revelar padrões,
# mas pra CPF (alta cardinalidade, 11 dígitos = 10^11 combinações) é aceitável.
#
# Limpeza de dados legacy: contas em produção atualmente têm `cpf IS NULL`
# (Fase 2A recém deployada, modal de cadastro nem existia). Forward-only.
class EncryptAgentProfileCpf < ActiveRecord::Migration[7.1]
  def up
    # Safety net: limpa qualquer texto plano legacy. Esperado 0 rows.
    execute <<~SQL
      UPDATE financial_agent_profiles
      SET cpf = NULL
      WHERE cpf IS NOT NULL;
    SQL

    # Active Record Encryption deterministic gera ciphertext maior que 20 chars.
    # Texto é safe — sem perda de performance perceptível em volumes esperados
    # (poucas centenas de profissionais por conta).
    change_column :financial_agent_profiles, :cpf, :text
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Criptografia de CPF é forward-only (LGPD). Reverter exporia dados sensíveis.'
  end
end
