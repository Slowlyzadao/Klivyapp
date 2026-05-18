module AiAgent
  # Cron noturno (4h SP). Pra cada PatientMemory elegível:
  #   1. Roda Distiller → perfil semântico estruturado
  #   2. Faz merge no `preferences` preservando keys manuais
  #      (recall_opt_out, last_recall_at, etc)
  #   3. Marca `last_consolidated_at = now`
  #
  # Também executa purge TTL 12m: memórias inativas há mais de 12 meses
  # têm `history` zerado pra economizar espaço (preferences ficam).
  #
  # Critérios de elegibilidade:
  #   - history >= 5 entries (paciente tem material pra destilar)
  #   - atividade nas últimas 24h (mensagem recente do contato)
  #   - last_consolidated_at < 23h ago (anti-reconsolidação no mesmo dia)
  #
  # Cap diário 100 pacientes/conta — evita custo desproporcional em
  # contas grandes. Em produção pode subir conforme volume.
  class ConsolidatePatientMemoryJob < ApplicationJob
    queue_as :scheduled_jobs

    DAILY_CAP_PER_ACCOUNT = 100
    MIN_HISTORY_ENTRIES = 5
    ACTIVE_WINDOW = 24.hours
    RECONSOLIDATE_AFTER = 23.hours
    PURGE_TTL = 12.months

    # Keys que o Distiller pode preencher; merge sempre sobrescreve essas.
    SEMANTIC_KEYS = AiAgent::Memory::Distiller::PROFILE_KEYS

    def perform
      AiAgent::AccountSetting.where(enabled: true).find_each do |setting|
        consolidate_account(setting.account)
        purge_account(setting.account)
      rescue StandardError => e
        Rails.logger.error("[AiAgent::ConsolidatePatientMemoryJob] account=#{setting.account_id} falhou: #{e.class}: #{e.message}")
      end
    end

    private

    def consolidate_account(account)
      candidates = eligible_memories(account)
      return if candidates.empty?

      Rails.logger.info("[AiAgent::ConsolidatePatientMemoryJob] account=#{account.id} consolidar=#{candidates.size}")

      candidates.each { |m| consolidate(m) }
    end

    def eligible_memories(account)
      AiAgent::PatientMemory
        .where(account_id: account.id)
        .where('jsonb_array_length(history) >= ?', MIN_HISTORY_ENTRIES)
        .where('last_consolidated_at IS NULL OR last_consolidated_at < ?', RECONSOLIDATE_AFTER.ago)
        .where('contact_id IN (?)', recently_active_contact_ids(account))
        .limit(DAILY_CAP_PER_ACCOUNT)
        .to_a
    end

    # Contatos com mensagem nas últimas 24h. Limita o universo pra
    # evitar passar todo paciente histórico no LLM. `reorder(nil)`
    # remove o default order do Message — sem isso PG reclama do
    # DISTINCT + ORDER BY expressions misturados.
    def recently_active_contact_ids(account)
      ::Message.joins(:conversation)
               .where(conversations: { account_id: account.id })
               .where('messages.created_at >= ?', ACTIVE_WINDOW.ago)
               .where.not(conversations: { contact_id: nil })
               .reorder(nil)
               .pluck('conversations.contact_id')
               .uniq
    end

    def consolidate(memory)
      result = AiAgent::Memory::Distiller.new(memory: memory).call
      return if result.nil? || result.profile.blank?

      current_prefs = memory.preferences.is_a?(Hash) ? memory.preferences.dup : {}

      # Sobrescreve só as semantic keys; preserva todas as outras
      # (recall_opt_out, last_recall_at, etc).
      SEMANTIC_KEYS.each { |k| current_prefs.delete(k) }
      merged = current_prefs.merge(result.profile)
      merged['_distiller_at'] = Time.current.iso8601

      memory.update!(preferences: merged, last_consolidated_at: Time.current)

      Rails.logger.info("[AiAgent::ConsolidatePatientMemoryJob] memory=#{memory.id} consolidada keys=#{result.profile.keys}")
    rescue StandardError => e
      Rails.logger.warn("[AiAgent::ConsolidatePatientMemoryJob] memory=#{memory.id} falhou: #{e.class}: #{e.message}")
    end

    def purge_account(account)
      cutoff = PURGE_TTL.ago
      stale = AiAgent::PatientMemory.where(account_id: account.id)
                                     .where('updated_at < ?', cutoff)
                                     .where("history <> '[]'::jsonb")
      count = stale.count
      return if count.zero?

      stale.find_each(batch_size: 50) do |m|
        m.update!(history: [])
      end
      Rails.logger.info("[AiAgent::ConsolidatePatientMemoryJob] account=#{account.id} purge_history=#{count}")
    end
  end
end
