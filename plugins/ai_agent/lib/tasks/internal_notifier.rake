# Rake tasks pra testar o pipeline de notificações internas da Bea
# end-to-end SEM precisar de UI/detector real. Útil pra:
#   - Validar que um template recém-configurado vai realmente cair na
#     sala/DM certa
#   - Debugar por que um aviso não chega (`disabled?`, sala removida,
#     dedupe, falta de membro humano, etc)
#   - Smoke test pós-deploy
#
# Comportamento: chama o `AiAgent::InternalNotifier::Dispatcher` real
# — passa pelo Router, TemplateRenderer, MessageDispatcher e
# BroadcastMessageJob. A mensagem REAL aparece no Chat Interno como
# se um detector tivesse disparado.
#
# Exemplos:
#   # Lista todos os templates da conta com status + destino + detector
#   bundle exec rails 'ai_agent:internal_notifier:list[31]'
#
#   # Dispara um evento específico com vars fake (Maria Silva etc)
#   bundle exec rails 'ai_agent:internal_notifier:test[31,appointment_booking_failed]'
#
#   # Dispara TODOS os eventos ativos de uma vez (smoke test completo)
#   bundle exec rails 'ai_agent:internal_notifier:test_all[31]'
#
# Tabela de variáveis fake compartilhada entre as tasks. Mesma palette do
# FAKE_VARS no preview do modal de templates — mantém testes coerentes
# com o que a clínica vê na UI. Encapsulado em module pra não vazar
# constante no top-level (que warning ao re-carregar via `rake -T`).
module AiAgent
  module InternalNotifierRakeFixtures
    FAKE_VARS = {
      patient_name: 'Maria Silva',
      patient_phone: '(11) 92365-2248',
      patient_status: '(acabei de criar a ficha)',
      service_name: 'Avaliação ortodôntica',
      dentist_name: 'Dr. João',
      appointment_starts_at: 'segunda, 14:30',
      last_visit_line: '📌 Última visita: 15/02/2026',
      reason: '[TESTE rake] Slot ocupou entre confirmação e save',
      conversation_link: 'https://app.klivy.com/conversations/123',
      summary: '[TESTE rake] Pediu reembolso da consulta de 03/05',
      debt_amount: 'R$ 450,00',
      debt_summary: 'Sessão 02 e 03 de canal vencidas há 30 dias',
      trigger_terms: 'sangrando muito, não para',
      failure_count: '4',
      topics: 'preço de canal, plano Amil, horário sábado'
    }.freeze
  end
end

namespace :ai_agent do
  namespace :internal_notifier do

    desc 'Lista todos os templates de uma conta com status atual'
    task :list, [:account_id] => :environment do |_, args|
      account_id = Integer(args[:account_id])
      account = Account.find(account_id)

      puts "\n📋 Templates de notificação interna — Account ##{account.id} (#{account.name})\n"
      puts '─' * 100

      AiAgent::InternalNotifier::EventCatalog::EVENTS.each do |event_key, meta|
        tpl = AiAgent::InternalNotificationTemplate.find_by(account_id: account.id, event_key: event_key)

        if tpl.nil?
          puts "  ⚪ #{event_key.ljust(45)} | NÃO SEEDADO"
          next
        end

        status_icon = if tpl.disabled?
                        '⚫'
                      else
                        (meta[:detector_status] == :active ? '🟢' : '🟡')
                      end
        target = case tpl.target_type
                 when 'room'     then "sala ##{tpl.target_id}"
                 when 'user'     then "DM user ##{tpl.target_id}"
                 when 'disabled' then '—'
                 end
        detector = (meta[:detector_status] == :active ? '[detector ativo]' : '[detector pendente]')

        puts "  #{status_icon} #{event_key.ljust(45)} | #{target.ljust(15)} | enabled=#{tpl.enabled} | #{detector}"
      end

      puts '─' * 100
      puts '  🟢 = ativo, vai disparar  |  🟡 = configurado mas detector ainda não foi implementado'
      puts '  ⚫ = desativado (target=disabled OU enabled=false)  |  ⚪ = template ainda não seedado'
      puts
    end

    desc 'Dispara um evento específico (usa vars fake) — vê a msg real no Chat Interno'
    task :test, %i[account_id event_key] => :environment do |_, args|
      account = Account.find(Integer(args[:account_id]))
      event_key = args[:event_key].to_s

      unless AiAgent::InternalNotifier::EventCatalog.keys.include?(event_key)
        warn "❌ event_key '#{event_key}' não existe. Valores válidos:"
        AiAgent::InternalNotifier::EventCatalog.keys.each { |k| warn "   - #{k}" }
        exit 1
      end

      fire_one(account, event_key)
    end

    desc 'Dispara TODOS os templates ativos de uma conta — smoke test completo'
    task :test_all, [:account_id] => :environment do |_, args|
      account = Account.find(Integer(args[:account_id]))

      puts "\n🚀 Disparando TODOS os templates ativos — Account ##{account.id}\n"
      puts '─' * 100

      active = AiAgent::InternalNotificationTemplate
               .where(account_id: account.id)
               .where(enabled: true)
               .where.not(target_type: 'disabled')

      if active.empty?
        puts '  ⚠️  Nenhum template ativo. Use `list` pra ver o estado.'
        next
      end

      active.each { |tpl| fire_one(account, tpl.event_key) }

      puts '─' * 100
      puts "✅ #{active.size} disparos enviados. Abra o Chat Interno pra confirmar."
    end

    # --- helpers ---

    # Dispara 1 evento. Retorna a Message criada (ou nil se Router
    # bloqueou). Imprime cada passo do pipeline pra diagnóstico.
    def fire_one(account, event_key)
      meta = AiAgent::InternalNotifier::EventCatalog.entry(event_key)
      label = meta[:label] || event_key

      puts "\n▶ #{label}  (event_key=#{event_key})"

      vars = AiAgent::InternalNotifierRakeFixtures::FAKE_VARS
             .slice(*meta[:available_vars].map(&:to_sym))

      tpl = AiAgent::InternalNotificationTemplate.find_by(account_id: account.id, event_key: event_key)
      if tpl.nil?
        puts '  ❌ Template não existe nessa conta (não foi seedado).'
        return nil
      end

      if tpl.disabled?
        reason = tpl.target_type == 'disabled' ? 'target_type=disabled' : 'enabled=false'
        puts "  ⏭  Template desabilitado (#{reason}). Router não vai dispatchar."
        return nil
      end

      router_result = AiAgent::InternalNotifier::Router.resolve(account: account, event_key: event_key)
      if router_result.room.nil?
        puts '  ❌ Router não resolveu sala (sala/user removido?). Aviso não enviado.'
        return nil
      end

      puts "  ✓ Router → sala ##{router_result.room.id} (#{router_result.room.name || '[sem nome]'})"

      bea = InternalChat::BeaResolver.for_account(account)
      if bea.nil?
        puts '  ❌ Bea (Captain::Assistant) não existe nesta conta — abort.'
        return nil
      end

      # Dispatcher real — passa por TemplateRenderer + MessageDispatcher + Broadcast.
      message = AiAgent::InternalNotifier::Dispatcher.call(
        account: account,
        event_key: event_key,
        vars: vars,
        dedupe_key: "rake-test:#{event_key}:#{Time.current.to_i}"
      )

      if message.respond_to?(:id) && message&.id
        puts "  ✅ Mensagem ##{message.id} criada na sala. BroadcastMessageJob enfileirado."
      else
        puts '  ⚠️  Dispatcher retornou nil — pode ter sido dedupe (rare) ou falha silenciosa. Cheque Rails.logger.'
      end

      message
    end
  end
end
