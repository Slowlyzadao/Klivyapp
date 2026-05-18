require_relative 'skip_beatriz_legacy_response'
require_relative 'gemini_thought_signature_patch'

module AiAgent
  class Engine < ::Rails::Engine
    isolate_namespace AiAgent
    engine_name 'ai_agent'

    initializer :append_ai_agent_migrations do |app|
      app.config.paths['db/migrate'] << root.join('db/migrate').to_s
      ActiveRecord::Migrator.migrations_paths << root.join('db/migrate').to_s
    end

    # Gemini 3 Preview rejects function calls missing `thoughtSignature`.
    # The official Python/Node SDKs handle the round-trip transparently;
    # RubyLLM 1.9.2 does not. We monkey-patch the Gemini provider to capture
    # the signature on the way in and re-attach it on the way out. Once
    # RubyLLM ships native support, drop both this initializer and the
    # `gemini_thought_signature_patch.rb` file.
    initializer :ai_agent_gemini_thought_signature_patch, after: :load_config_initializers do
      AiAgent::GeminiThoughtSignaturePatch.apply!
    rescue StandardError => e
      Rails.logger.error("[AiAgent] gemini thought signature patch failed: #{e.class}: #{e.message}")
    end

    # Registra o cron diário do recall proativo direto via
    # Sidekiq::Cron::Job em vez de editar `config/schedule.yml` (core).
    # Roda só quando Sidekiq estiver em modo server pra evitar criar
    # entries fantasma durante console / specs / web boot.
    config.after_initialize do
      next unless defined?(::Sidekiq) && Sidekiq.server?
      next unless defined?(::Sidekiq::Cron::Job)

      # 17h UTC = 14h America/Sao_Paulo (BRT, UTC-3). Hora de baixo
      # tráfego de paciente; equipe ainda está disponível pra
      # responder se alguém engajar com o recall.
      ::Sidekiq::Cron::Job.create(
        name: 'AiAgent::ProactiveOutreachJob',
        cron: '0 17 * * *',
        class: 'AiAgent::ProactiveOutreachJob',
        queue: 'scheduled_jobs'
      )

      # Consolidação semântica diária (Sprint D). 7h UTC = 4h SP, hora
      # de tráfego mínimo. Roda Distiller pra cada PatientMemory ativo
      # nas últimas 24h e atualiza `preferences` com perfil destilado.
      ::Sidekiq::Cron::Job.create(
        name: 'AiAgent::ConsolidatePatientMemoryJob',
        cron: '0 7 * * *',
        class: 'AiAgent::ConsolidatePatientMemoryJob',
        queue: 'scheduled_jobs'
      )

      # Follow-ups configuráveis (Sprint G2). Roda a cada 1 minuto pra
      # suportar offsets em segundos (testes + casos genuínos). A janela
      # do CandidateFinder é ±1min, casando com a frequência do cron.
      # Custo é baixo: 1 query simples por regra enabled, sem LLM aqui.
      ::Sidekiq::Cron::Job.create(
        name: 'AiAgent::FollowUpDispatcherJob',
        cron: '* * * * *',
        class: 'AiAgent::FollowUpDispatcherJob',
        queue: 'scheduled_jobs'
      )

      # Health check a cada 10min. Snapshot das últimas 24h vai pro
      # Checker; se algum threshold estourar, Notifier dispara Slack/email
      # com dedup TTL 1h por alert.key — alerta persistente não floda.
      ::Sidekiq::Cron::Job.create(
        name: 'AiAgent::Health::MonitorJob',
        cron: '*/10 * * * *',
        class: 'AiAgent::Health::MonitorJob',
        queue: 'scheduled_jobs'
      )

    rescue StandardError => e
      Rails.logger.error("[AiAgent] proactive cron register failed: #{e.class}: #{e.message}")
    end

    # Visibilidade do Sentinel (2ª camada pós-LLM, LLM-as-judge). Default
    # é OFF — logamos pra deixar claro no boot se está rodando ou não.
    # Sem isso, time deploya achando que tem a camada e na real ela tá
    # silenciosa. Lê o InstallationConfig direto pra não depender do
    # autoloader ter carregado AiAgent::Humanization::Sentinel ainda
    # (depende da ordem de boot do Zeitwerk).
    config.after_initialize do
      flag = InstallationConfig.find_by(name: 'CAPTAIN_BEA_SENTINEL_ENABLED')&.value.to_s == 'true'
      Rails.logger.info("[AiAgent] Sentinel #{flag ? 'ENABLED' : 'DISABLED'} (CAPTAIN_BEA_SENTINEL_ENABLED)")
    rescue StandardError => e
      Rails.logger.warn("[AiAgent] Sentinel state log failed: #{e.class}: #{e.message}")
    end

    # The user-facing routes are wired up in the host app's
    # config/routes.rb (see `scope :ai_agent` block inside the accounts
    # namespace). Tried `initializer + routes.append` and
    # `routes_reloader.paths` here, but Rails finalizes the app's route set
    # before plugin engines get a hook into the same accounts scope, so
    # appended routes never resolved. The host edit is one block; the
    # controllers/views/policies still live entirely in this plugin.

    # Account associations + listener subscription.
    #
    # Both must live in `to_prepare` because Chatwoot's own
    # `config/initializers/event_handlers.rb` puts `dispatcher.load_listeners`
    # inside `to_prepare` too — meaning every dev reload rewires the
    # dispatcher's Wisper subscribers. If we subscribed only once at boot,
    # our listener would silently disappear after the first code edit
    # triggers a reload, breaking automatic Bea responses intermittently.
    #
    # We dedupe ourselves on every `to_prepare` so we don't stack duplicate
    # subscriptions across reloads.
    config.to_prepare do
      Account.class_eval do
        unless reflect_on_association(:ai_agent_setting)
          has_one :ai_agent_setting,
                  class_name: 'AiAgent::AccountSetting',
                  dependent: :destroy
        end
        unless reflect_on_association(:ai_agent_usage_counters)
          has_many :ai_agent_usage_counters,
                   class_name: 'AiAgent::UsageCounter',
                   dependent: :destroy_async
        end
        unless reflect_on_association(:documents_for_bea)
          has_many :documents_for_bea,
                   class_name: 'AiAgent::Document',
                   dependent: :destroy_async
        end

        # Brand new accounts ship with a Captain::Assistant called "Beatriz"
        # already wired up. Without this, the Bea sidebar lands on an empty
        # "Não há assistentes disponíveis" screen and the user thinks they
        # need to create one manually. Idempotent: skips when an assistant
        # already exists for the account, so reloads and existing accounts
        # don't get duplicate Beatrizes (backfill is done separately).
        unless method_defined?(:ensure_default_bea_assistant)
          after_create_commit :ensure_default_bea_assistant

          def ensure_default_bea_assistant
            return unless defined?(::Captain::Assistant)
            return if ::Captain::Assistant.where(account_id: id).exists?

            ::Captain::Assistant.create!(
              account_id: id,
              name: 'Beatriz',
              description: 'Beatriz é a assistente virtual da Klivy. Responde dúvidas, agenda consultas e transfere para um humano quando necessário.',
              config: AiAgent::BeatrizDefaults.config
            )
          rescue StandardError => e
            Rails.logger.error(
              "[AiAgent] ensure_default_bea_assistant failed for account #{id}: #{e.class}: #{e.message}"
            )
          end
        end
      end

      # Beatriz is a "system assistant" — she ships pre-configured with every
      # account, her name is part of the brand, and her config feeds the Bea
      # AI agent's prompt. Allowing rename or destroy would orphan everything
      # downstream (PromptBuilder lookups, sidebar entry, agent_bot binding).
      # We block both at the model level so frontend hacks can't bypass it.
      # Captain legacy auto-responds to incoming messages whenever
      # `inbox.captain_assistant.present?`. Connecting Beatriz to an inbox
      # for the UI ("Caixas de entrada" tab) accidentally turned that on,
      # so for every message we got two replies: ours (correct) and the
      # legacy's ("não encontrei o endereço…", because legacy reads from
      # Captain::Document which is empty by design — Bea's RAG lives in
      # AiAgent::Document). We short-circuit the legacy job whenever its
      # target assistant is Beatriz, leaving the rest of the Captain stack
      # untouched for any other custom assistant a clinic might wire up.
      if defined?(::Captain::Conversation::ResponseBuilderJob) &&
         !::Captain::Conversation::ResponseBuilderJob.include?(AiAgent::SkipBeatrizLegacyResponse)
        ::Captain::Conversation::ResponseBuilderJob.prepend(AiAgent::SkipBeatrizLegacyResponse)
      end

      if defined?(::Captain::Assistant)
        ::Captain::Assistant.class_eval do
          unless method_defined?(:protect_beatriz_destroy)
            before_destroy :protect_beatriz_destroy
            before_update :protect_beatriz_rename
            # Mirrors the on/off toggle from Beatriz's settings page into
            # AiAgent::AccountSetting.enabled, which is what ChatService /
            # ConfigResolver actually consult before answering. Without this
            # mirror, the user could flip the switch and Bea would still
            # reply (or vice versa).
            after_save :sync_bea_enabled_to_account_setting

            def protect_beatriz_destroy
              return unless name_was == 'Beatriz' || name == 'Beatriz'

              errors.add(:base, 'A assistente Beatriz não pode ser excluída.')
              throw :abort
            end

            def protect_beatriz_rename
              return unless name_was == 'Beatriz' && name_changed?

              self.name = 'Beatriz'
            end

            def sync_bea_enabled_to_account_setting
              return unless name == 'Beatriz'

              enabled_flag = config['bea_enabled'] != false
              setting = AiAgent::AccountSetting.find_or_initialize_by(account_id: account_id)
              return if setting.enabled == enabled_flag

              setting.enabled = enabled_flag
              setting.save
            rescue StandardError => e
              Rails.logger.warn("[AiAgent] sync_bea_enabled failed for assistant #{id}: #{e.message}")
            end
          end
        end
      end

      # Hook directly into Message#after_create_commit instead of relying on
      # Wisper subscribers via SyncDispatcher / AsyncDispatcher. We tried
      # both and Wisper subscriptions kept evaporating on dev reloads,
      # causing the Bea to silently miss messages. The callback below runs
      # in the same transaction commit as the message is persisted — there
      # is no Redis or Sidekiq dependency in the dispatch path; only the
      # job itself goes through Sidekiq, with rescue around enqueue.
      Message.class_eval do
        unless method_defined?(:trigger_ai_agent_listener)
          after_create_commit :trigger_ai_agent_listener

          def trigger_ai_agent_listener
            event = Struct.new(:data).new
            event.data = { message: self }
            AiAgent::EventListeners::MessageListener.instance.message_created(event)
          rescue StandardError => e
            Rails.logger.error(
              "[AiAgent] trigger_ai_agent_listener failed for msg #{id}: #{e.class}: #{e.message}"
            )
          end
        end
      end

      # Auto-seed dos 10 templates default de notificação interna pra cada
      # Account nova. Templates nascem DESATIVADOS — clínica configura destino
      # depois de criar os grupos no Chat Interno. Sem dependência de sala
      # sistêmica (que não existe mais — decisão Apêndice F).
      Account.class_eval do
        unless method_defined?(:seed_ai_agent_internal_notification_templates)
          after_create_commit :seed_ai_agent_internal_notification_templates

          def seed_ai_agent_internal_notification_templates
            AiAgent::InternalNotifier::DefaultTemplatesSeeder.seed_for_account(self)
          rescue StandardError => e
            Rails.logger.warn(
              "[AiAgent::InternalNotifier] seed templates failed for account #{id}: #{e.class}: #{e.message}"
            )
          end
        end
      end

      # Pipeline A — quando BookAppointmentTool retorna falha não-trivial
      # (slot ocupou, profissional não realiza serviço, etc), notifica equipe
      # interna. Plugado via prepend pra não inflar o método `execute` (250+ LOC).
      # Idempotente — `unless include?` evita stacking de prepends em reload.
      if defined?(::AiAgent::Tools::BookAppointmentTool) &&
         !::AiAgent::Tools::BookAppointmentTool.include?(AiAgent::InternalNotifier::BookAppointmentToolPrepend)
        ::AiAgent::Tools::BookAppointmentTool.prepend(AiAgent::InternalNotifier::BookAppointmentToolPrepend)
      end

      # Pipeline A — Bea avisa o grupo Recepção quando ela mesma reserva um
      # agendamento que ficou em pending_confirmation (D-16). Filtramos por
      # source='ai_agent' pra não notificar agendamentos criados manualmente
      # pela equipe ou pelo link público. Roda síncrono no callback porque o
      # serviço é templated (sem LLM, ~10ms) e o broadcast efetivo já é
      # async via BroadcastMessageJob.
      if defined?(::AgendaEvent)
        ::AgendaEvent.class_eval do
          unless method_defined?(:notify_internal_chat_pending_confirmation)
            # NÃO usar `after_create_commit :sym` + `after_update_commit :sym`
            # com mesmo símbolo — Rails MERGE em um único callback e o último
            # `on:` sobrescreve o anterior, fazendo o callback só disparar em
            # update. Usamos `after_commit on: [:create, :update]` com guard
            # interno + idempotência via notifier_key no service.
            after_commit :notify_internal_chat_pending_confirmation, on: [:create, :update]
            after_commit :notify_internal_chat_lifecycle_change, on: :update

            def notify_internal_chat_pending_confirmation
              return unless status == 'pending_confirmation' && source == 'ai_agent'

              AiAgent::InternalNotifier::AppointmentPendingConfirmation.call(self)
            rescue StandardError => e
              Rails.logger.error(
                "[AiAgent::InternalNotifier] pending_confirmation failed for agenda_event #{id}: #{e.class}: #{e.message}"
              )
            end

            # Cancelamento e no-show — independente de quem criou (ai_agent ou
            # manual). Filtra pelos status finais de interesse e dispara só na
            # transição (não em todo update).
            def notify_internal_chat_lifecycle_change
              return unless saved_change_to_status?

              case status
              when 'cancelled'
                AiAgent::InternalNotifier::AppointmentCancelled.call(self)
              when 'no_show'
                AiAgent::InternalNotifier::AppointmentNoShow.call(self)
              end
            rescue StandardError => e
              Rails.logger.error(
                "[AiAgent::InternalNotifier] lifecycle_change failed for agenda_event #{id}: #{e.class}: #{e.message}"
              )
            end
          end
        end
      end

      # When a Chatwoot conversation is marked `resolved`, flip our
      # ConversationState back to `active` so the patient's NEXT message
      # in this same conversation reaches Bea again. Without this, the
      # state stays escalated forever and Bea is silenced after a single
      # handoff cycle, even if the human already wrapped up.
      Conversation.class_eval do
        unless method_defined?(:reset_ai_agent_state_on_resolve)
          after_update_commit :reset_ai_agent_state_on_resolve

          def reset_ai_agent_state_on_resolve
            return unless saved_change_to_status? && status == 'resolved'

            state = AiAgent::ConversationState.find_by(account_id: account_id, conversation_id: id)
            state&.update(status: 'active', consecutive_negative_count: 0, consecutive_tool_failures: 0, last_intent: nil)
          rescue StandardError => e
            Rails.logger.warn("[AiAgent] reset state on resolve failed for conv #{id}: #{e.message}")
          end
        end
      end
    end
  end

  # Adds AiAgent listeners to the AsyncDispatcher's listener list.
  module DispatcherExtension
    def listeners
      super + [AiAgent::EventListeners::MessageListener.instance]
    end
  end
end
