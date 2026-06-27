# Backfill dos 10 templates default de notificação interna pra TODAS as
# Accounts que já existiam antes do plugin ai_agent ser instalado.
#
# Cenário: o callback `after_create_commit :seed_ai_agent_internal_notification_templates`
# em `Account.class_eval` (engine.rb) só dispara em conta nova. Accounts criadas
# antes da integração do plugin (release 1.6.1.30) ficaram sem os templates,
# fazendo a página "BEA → Notificações Internas" abrir vazia até alguém rodar
# o seeder via rails console.
#
# Esta migration garante o backfill no deploy. Seeder é idempotente — só cria
# template pro (account_id, event_key) que ainda não existir — então rodar em
# accounts já migradas (ex.: a Mamedes que recebeu seeder manual via console)
# é seguro: nada acontece.
#
# Roda dentro do `up` em vez de `change` porque é forward-only (down não tem
# como saber quais templates eram "default" para deletar — risco de deletar
# customizações da clínica). Em rollback, deixar os templates intactos é o
# comportamento mais seguro.
class BackfillAiAgentInternalNotificationTemplates < ActiveRecord::Migration[7.1]
  def up
    return unless defined?(::AiAgent::InternalNotifier::DefaultTemplatesSeeder)

    ::Account.find_each do |account|
      ::AiAgent::InternalNotifier::DefaultTemplatesSeeder.seed_for_account(account)
    rescue StandardError => e
      Rails.logger.warn(
        "[backfill] seed templates failed for account #{account.id}: #{e.class}: #{e.message}"
      )
    end
  end

  def down
    # Forward-only. Ver comentário do topo.
  end
end
