# Liga a feature flag `payment_plan_wizard_v2` (F3 do PaymentPlanWizardV2,
# CHANGELOG 1.8.0.24) para todas as accounts existentes na base.
#
# Decisão (2026-05-27): só há 1 cliente em produção usando financeiro
# zerado, então não há risco de mudança de UX surpresa pra usuários
# legados. Ativar como default elimina o passo manual de "rodar runner
# por account". Novas accounts ganham a flag via callback no
# `plugins/patients/lib/patients/engine.rb` (espelha o pattern do
# `financial_timeline_v2`).
#
# A flag continua existindo (não foi descontinuada) — preservar permite
# kill-switch rápido em conta específica via runner reverso se algum
# bug aparecer em produção, sem precisar de revert + deploy.
#
# Idempotente: pula accounts que já têm a flag (rollback parcial seguro).
# Forward-only por convenção do projeto (down no-op).
class EnablePaymentPlanWizardV2ForAllAccounts < ActiveRecord::Migration[7.1]
  FEATURE = 'payment_plan_wizard_v2'
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
    # Para desativar em conta específica, usar runner ad-hoc removendo
    # FEATURE do array `beta_features`.
  end
end
