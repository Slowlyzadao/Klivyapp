require_relative '../custom_roles/preset_seeder'

namespace :custom_roles do
  desc 'Garante que cada conta tem os 4 presets KlivyRole (Recepcionista/Especialista/Gerente/SDR). ' \
       'Idempotente: cria se faltar, restaura se estiver corrompido (perms vazias/all false), ' \
       'pula se admin customizou. Use FORCE=true pra sobrescrever customizações (cuidado em prod).'
  task seed_presets: :environment do
    force = ENV['FORCE'].to_s.casecmp('true').zero?
    only_account_id = ENV['ACCOUNT_ID']&.to_i

    scope = only_account_id ? Account.where(id: only_account_id) : Account.all
    total = scope.count
    puts "Aplicando presets em #{total} conta(s)#{' (FORCE=true)' if force}..."

    summary = { created: 0, restored: 0, skipped: 0, force_updated: 0 }
    scope.find_each do |account|
      result = CustomRoles::PresetSeeder.call(account, force: force)
      summary[:created] += result.created.size
      summary[:restored] += result.restored.size
      summary[:skipped] += result.skipped.size
      summary[:force_updated] += result.force_updated.size
    end

    puts '---'
    puts "TOTAL: created=#{summary[:created]} restored=#{summary[:restored]} " \
         "skipped=#{summary[:skipped]} force_updated=#{summary[:force_updated]}"
  end
end
