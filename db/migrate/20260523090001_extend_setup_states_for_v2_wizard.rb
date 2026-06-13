# Estende `financial_setup_states` com 3 passos novos pro wizard expandido
# (canon Setup #1..#8 — 2026-05-23):
#   - `step_payment_methods_done` → ≥1 forma de pagamento ativa (OBRIGATÓRIO)
#   - `step_agent_profiles_done`  → ≥1 perfil financeiro (RECOMENDADO)
#   - `step_services_done`        → ≥1 ServicePricing configurado (RECOMENDADO)
#
# Backfill: marca como `true` se a conta JÁ tem registros nas tabelas
# correspondentes. Sem isso contas em produção precisariam reabrir o wizard.
class ExtendSetupStatesForV2Wizard < ActiveRecord::Migration[7.1]
  def up
    add_column :financial_setup_states, :step_payment_methods_done, :boolean, default: false, null: false
    add_column :financial_setup_states, :step_agent_profiles_done,  :boolean, default: false, null: false
    add_column :financial_setup_states, :step_services_done,        :boolean, default: false, null: false

    # Backfill: se já tem registros nas tabelas alvo, considera o passo feito.
    execute <<~SQL
      UPDATE financial_setup_states ss
      SET step_payment_methods_done = TRUE
      WHERE EXISTS (
        SELECT 1 FROM financial_payment_methods pm
        WHERE pm.account_id = ss.account_id
          AND pm.deleted_at IS NULL
          AND pm.status = 'active'
      );
    SQL

    execute <<~SQL
      UPDATE financial_setup_states ss
      SET step_agent_profiles_done = TRUE
      WHERE EXISTS (
        SELECT 1 FROM financial_agent_profiles ap
        WHERE ap.account_id = ss.account_id
          AND ap.deleted_at IS NULL
          AND ap.status = 'active'
      );
    SQL

    execute <<~SQL
      UPDATE financial_setup_states ss
      SET step_services_done = TRUE
      WHERE EXISTS (
        SELECT 1 FROM financial_service_pricings sp
        WHERE sp.account_id = ss.account_id
          AND sp.deleted_at IS NULL
          AND sp.status = 'active'
      );
    SQL
  end

  def down
    remove_column :financial_setup_states, :step_payment_methods_done
    remove_column :financial_setup_states, :step_agent_profiles_done
    remove_column :financial_setup_states, :step_services_done
  end
end
