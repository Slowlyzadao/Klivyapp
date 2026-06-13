# Liga a feature flag `financial_timeline_v2` (PR 3 do refactor financeiro
# 2026-05-06) para todas as accounts existentes na base.
#
# Antes desta migration, a flag era ativada manualmente por clínica via
# Super Admin / console (ver `Patients::BetaFeatureChecker`). Após PR 3
# estabilizar (timeline = default permanente, visão clássica deletada),
# accounts sem a flag veem mensagem "em manutenção" e não conseguem usar
# o financeiro do prontuário — comportamento indesejado.
#
# Esta migration percorre TODAS as accounts (não só as ativas) e
# garante que `custom_attributes['beta_features']` contém a flag.
# Idempotente: se a flag já existir na account, pula sem alteração.
#
# Forward-only por convenção do projeto (down no-op).
class EnableFinancialTimelineV2ForAllAccounts < ActiveRecord::Migration[7.1]
  FEATURE = 'financial_timeline_v2'
  KEY = 'beta_features'

  def up
    Account.find_in_batches(batch_size: 100) do |batch|
      batch.each do |account|
        existing = Array(account.custom_attributes&.dig(KEY)).map(&:to_s)
        next if existing.include?(FEATURE)

        account.update!(
          custom_attributes: (account.custom_attributes || {}).merge(
            KEY => existing | [FEATURE]
          )
        )
      end
    end
  end

  def down
    # No-op: feature flag enables são forward-only no projeto.
  end
end
