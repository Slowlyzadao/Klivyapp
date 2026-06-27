# Backfill dos 10 AgendaServices canon pras contas existentes.
#
# 2026-05-23: criamos `Agenda::Bootstrap::SeedDefaultServices` que roda
# automaticamente em `Account.after_create_commit`. Contas que já existiam
# antes desse callback (as 7 atuais: Acme, BeClinic, Leandro, Gabriel,
# Mamedes, Benuv, Streit) NÃO ganharam o seed automático.
#
# Esta migration roda o service em todas as contas que ainda não têm
# AgendaServices, criando os 10 padrão. Idempotente — pula contas que já
# tenham qualquer AgendaService cadastrado (preserva edições manuais).
#
# Espelhamento intencional dos 10 procedimentos canon: o modal
# `ServicePricingFormModalV2` faz auto-sugestão por nome, então depois
# desta migration os 10 AgendaServices vão automaticamente ser linkados
# às suas DreCategories L3 quando o operador configurar o pricing.
class BackfillDefaultAgendaServices < ActiveRecord::Migration[7.1]
  def up
    Account.find_each do |account|
      existing = ::AgendaService.where(account_id: account.id, deleted_at: nil).count
      if existing.positive?
        say "Account ##{account.id} (#{account.name}): já tem #{existing} services — pulando"
        next
      end

      result = ::Agenda::Bootstrap::SeedDefaultServices.call(account: account)
      if result.success?
        say "Account ##{account.id} (#{account.name}): #{result.created} services criados, #{result.skipped} pulados"
      else
        say "⚠ Account ##{account.id}: #{result.errors.join('; ')}"
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Backfill de defaults — não desfaz pra preservar edições da clínica.'
  end
end
