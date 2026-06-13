# ESC-2 (auditoria 2026-05-18): worker per-account criado pra escalar
# a consolidação noturna de PatientMemory. Antes o dispatcher iterava
# todos os AccountSetting.enabled sequencialmente, gastando ~tempo do
# LLM × pacientes_eligible × contas. Em 1000 contas × 10 pacientes ×
# 3s LLM = 8h+ de janela noturna excedida. Agora o cron despacha 1
# job por conta e Sidekiq paraleliza.
#
# Cada call do Distiller já gateia por cost cap (BE-26) — workers
# paralelos não bypass'am o cap.
class AiAgent::ConsolidatePatientMemoryPerAccountJob < ApplicationJob
  queue_as :scheduled_jobs

  DAILY_CAP_PER_ACCOUNT = AiAgent::ConsolidatePatientMemoryJob::DAILY_CAP_PER_ACCOUNT
  MIN_HISTORY_ENTRIES = AiAgent::ConsolidatePatientMemoryJob::MIN_HISTORY_ENTRIES
  ACTIVE_WINDOW = AiAgent::ConsolidatePatientMemoryJob::ACTIVE_WINDOW
  RECONSOLIDATE_AFTER = AiAgent::ConsolidatePatientMemoryJob::RECONSOLIDATE_AFTER
  PURGE_TTL = AiAgent::ConsolidatePatientMemoryJob::PURGE_TTL
  SEMANTIC_KEYS = AiAgent::Memory::Distiller::PROFILE_KEYS

  def perform(account_id)
    account = ::Account.find_by(id: account_id)
    return unless account

    consolidate_account(account)
    purge_account(account)
  rescue StandardError => e
    Rails.logger.error(
      "[AiAgent::ConsolidatePatientMemoryPerAccountJob] account=#{account_id} falhou: " \
      "#{e.class}: #{e.message}"
    )
  end

  private

  def consolidate_account(account)
    candidates = eligible_memories(account)
    return if candidates.empty?

    Rails.logger.info(
      "[AiAgent::ConsolidatePatientMemoryPerAccountJob] account=#{account.id} consolidar=#{candidates.size}"
    )

    candidates.each { |m| consolidate(m) }
  end

  def eligible_memories(account)
    AiAgent::PatientMemory
      .where(account_id: account.id)
      .where('jsonb_array_length(history) >= ?', MIN_HISTORY_ENTRIES)
      .where('last_consolidated_at IS NULL OR last_consolidated_at < ?', RECONSOLIDATE_AFTER.ago)
      .where(contact_id: recently_active_contact_ids(account))
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

    Rails.logger.info(
      "[AiAgent::ConsolidatePatientMemoryPerAccountJob] memory=#{memory.id} " \
      "consolidada keys=#{result.profile.keys}"
    )
  rescue StandardError => e
    Rails.logger.warn(
      "[AiAgent::ConsolidatePatientMemoryPerAccountJob] memory=#{memory.id} falhou: " \
      "#{e.class}: #{e.message}"
    )
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
    Rails.logger.info(
      "[AiAgent::ConsolidatePatientMemoryPerAccountJob] account=#{account.id} purge_history=#{count}"
    )
  end
end
