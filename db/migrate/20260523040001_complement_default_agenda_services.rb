# Complementa AgendaServices canon nas contas que tinham legacy.
#
# A migration anterior (`20260523030001_backfill_default_agenda_services`)
# PULOU contas que já tinham QUALQUER AgendaService (early return overly
# conservador). Resultado: 3 contas ficaram sem o canon completo:
#   - Account 1 (Acme): 7 services legacy (Avaliação, Profilaxia, etc do
#                       db/seeds/treatments.rb antigo)
#   - Account 14 (BeClinic Standard): 1 service legacy
#   - Account 31 (Mamedes): 2 services legacy
#
# Decisão arquitetural: canon DRE × AgendaServices deve estar SIMÉTRICO.
# Toda conta DEVE ter pelo menos os 10 procedimentos canon. Legacy convive.
#
# Esta migration roda `Agenda::Bootstrap::SeedDefaultServices` em TODAS as
# contas — o service é idempotente por (external_id canon, name) então:
#   - Contas já completas: skipa todos os 10 (criação=0, skipped=10)
#   - Contas legacy: cria APENAS os canon faltantes (preserva legacy)
#   - Contas vazias: cria os 10
class ComplementDefaultAgendaServices < ActiveRecord::Migration[7.1]
  def up
    Account.find_each do |account|
      result = ::Agenda::Bootstrap::SeedDefaultServices.call(account: account)
      if result.success?
        if result.created.positive?
          say "Account ##{account.id} (#{account.name}): +#{result.created} canon adicionados (#{result.skipped} já existiam)"
        else
          say "Account ##{account.id} (#{account.name}): completa (#{result.skipped} canon já existiam)"
        end
      else
        say "⚠ Account ##{account.id}: #{result.errors.join('; ')}"
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Complement de canon — não desfaz pra preservar serviços criados.'
  end
end
