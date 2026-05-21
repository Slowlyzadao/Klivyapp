# Limpeza de `contact_inboxes` órfãos
#
# Histórico:
# `contact_inboxes` está acoplada a `inboxes` e `contacts` via colunas sem
# foreign keys formais — o cleanup ao deletar uma Inbox/Contact é feito
# por `dependent: :destroy_async` (job em background). Quando o job falha
# (queue limpa, Redis reiniciado, deploy interrompeu), as rows ficam
# apontando para `inbox_id` ou `contact_id` que não existem mais.
#
# Os efeitos práticos desses órfãos:
# - `fetchContactableInbox(contact_id)` retorna 404 ao bater num órfão,
#   gerando ruído no console do dashboard (visto em [1.5.5.17] e [1.6.0.18]).
# - `Contact#contact_inboxes` retorna rows que falham ao acessar `.inbox`.
#
# Este script NÃO toca em:
# - Volume `/app/storage` (sessão Baileys/WhatsApp QR — vive em disco)
# - Tabela `inboxes` (canais ativos)
# - Tabela `contacts`
# - Tabela `conversations` / `messages`
# - Active Storage / R2 / blobs
#
# Uso (rodar em produção em ordem):
#
#   1) DRY-RUN — relatório sem alterar nada:
#      bundle exec rails contact_inboxes:list_orphans
#
#   2) Após revisar a saída do passo 1:
#      bundle exec rails contact_inboxes:remove_orphans
#
# A rake task `remove_orphans` é idempotente: se já não há órfãos, vira
# no-op com mensagem de confirmação.

namespace :contact_inboxes do
  desc 'DRY-RUN: lista contact_inboxes órfãos sem deletar nada'
  task list_orphans: :environment do
    inbox_orphans = ContactInbox.where('inbox_id IS NULL OR inbox_id NOT IN (SELECT id FROM inboxes)')
    contact_orphans = ContactInbox.where('contact_id IS NULL OR contact_id NOT IN (SELECT id FROM contacts)')

    inbox_count = inbox_orphans.count
    contact_count = contact_orphans.count
    total = ContactInbox.count

    puts ''
    puts '=== Contact Inboxes — Orphan Report (DRY-RUN) ==='
    puts ''
    puts "Total contact_inboxes na base: #{total}"
    puts "Órfãos apontando para INBOX deletada/nil:   #{inbox_count}"
    puts "Órfãos apontando para CONTACT deletado/nil: #{contact_count}"
    puts ''

    if inbox_count.zero? && contact_count.zero?
      puts '✓ Sem órfãos. Banco está limpo, nada a fazer.'
      next
    end

    if inbox_count.positive?
      puts '--- Top 10 inboxes deletadas por número de órfãos:'
      inbox_orphans.group(:inbox_id).count.sort_by { |_, c| -c }.first(10).each do |inbox_id, count|
        puts "  inbox_id=#{inbox_id || 'nil'}: #{count} órfãos"
      end
      puts ''
      puts '--- Amostra de até 20 rows (source_id mascarado por privacidade):'
      puts format('%-8s | %-12s | %-12s | %-25s | %s', 'id', 'contact_id', 'inbox_id', 'source_id (masked)', 'created_at')
      puts '-' * 100
      inbox_orphans.limit(20).find_each do |ci|
        source = ci.source_id.to_s
        masked = source.length > 16 ? "#{source[0, 6]}***#{source[-6, 6]}" : '***'
        puts format('%-8s | %-12s | %-12s | %-25s | %s', ci.id, ci.contact_id, ci.inbox_id, masked, ci.created_at)
      end
      puts ''
    end

    if contact_count.positive?
      puts '--- Amostra de até 20 rows com CONTACT deletado:'
      contact_orphans.limit(20).find_each do |ci|
        source = ci.source_id.to_s
        masked = source.length > 16 ? "#{source[0, 6]}***#{source[-6, 6]}" : '***'
        puts "  id=#{ci.id} contact_id=#{ci.contact_id || 'nil'} (deletado) inbox_id=#{ci.inbox_id} source=#{masked}"
      end
      puts ''
    end

    puts '=== Próximo passo ==='
    puts 'Se a lista acima estiver OK para deletar, rode:'
    puts '  bundle exec rails contact_inboxes:remove_orphans'
    puts ''
  end

  desc 'Remove contact_inboxes órfãos do banco. Rodar APENAS após `list_orphans` revisado.'
  task remove_orphans: :environment do
    inbox_orphans = ContactInbox.where('inbox_id IS NULL OR inbox_id NOT IN (SELECT id FROM inboxes)')
    contact_orphans = ContactInbox.where('contact_id IS NULL OR contact_id NOT IN (SELECT id FROM contacts)')

    inbox_count = inbox_orphans.count
    contact_count = contact_orphans.count

    if inbox_count.zero? && contact_count.zero?
      puts '✓ Sem órfãos. Nada a deletar.'
      next
    end

    puts "Removendo #{inbox_count} órfãos de inbox + #{contact_count} órfãos de contact..."
    puts '(rows podem se sobrepor — id apontando para inbox E contact deletados são contados nos dois)'

    # `delete_all` ignora callbacks e validations — apropriado aqui porque
    # o ContactInbox.belongs_to :contact / :inbox são validados com
    # `presence: true`, então um destroy via Rails falharia em órfãos.
    # Não há callbacks `before_destroy`/`after_destroy` em ContactInbox
    # (verificado em [app/models/contact_inbox.rb]), só `has_many :conversations,
    # dependent: :destroy_async` — e essas conversations já estão órfãs
    # pelo mesmo motivo do contact_inbox; tratar separadamente fora do escopo
    # desta task.
    ActiveRecord::Base.transaction do
      deleted_by_inbox = inbox_orphans.delete_all
      deleted_by_contact = contact_orphans.delete_all
      puts "Deletados: #{deleted_by_inbox} via inbox-órfão + #{deleted_by_contact} via contact-órfão"
    end

    # Re-checa zero pra confirmar
    remaining_inbox = ContactInbox.where('inbox_id IS NULL OR inbox_id NOT IN (SELECT id FROM inboxes)').count
    remaining_contact = ContactInbox.where('contact_id IS NULL OR contact_id NOT IN (SELECT id FROM contacts)').count

    if remaining_inbox.zero? && remaining_contact.zero?
      puts '✓ Cleanup concluído. Zero órfãos restantes.'
    else
      puts "⚠ Atenção: ainda restam #{remaining_inbox} + #{remaining_contact} órfãos. Re-rode a task."
    end
  end
end
