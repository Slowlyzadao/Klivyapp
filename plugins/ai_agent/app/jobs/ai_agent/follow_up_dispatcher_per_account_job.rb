# ESC-1 (auditoria 2026-05-18): worker per-account criado pra escalar o
# FollowUpDispatcherJob. Antes, o dispatcher iterava `FollowUpRule.enabled`
# global numa única execução do cron (a cada 1 minuto), processando todos
# os tenants sequencialmente. Em escala (1000+ contas × N rules cada), a
# execução excedia o intervalo de 1 minuto e backlog acumulava — próxima
# rodada começava antes da anterior terminar.
#
# Agora o cron só enfileira 1 job deste tipo por conta (FollowUpDispatcherJob
# vira despachante), e o Sidekiq paraleliza N workers concorrentes — tempo
# total de execução escala horizontalmente com workers, não linearmente
# com tenants.
#
# Idempotência preservada: o índice UNIQUE em
# `ai_agent_follow_up_executions(rule_id, contact_id, agenda_event_id, target_at)`
# garante que enfileiramentos concorrentes do mesmo job não duplicam disparo.
class AiAgent::FollowUpDispatcherPerAccountJob < ApplicationJob
  queue_as :scheduled_jobs

  MAX_PER_ACCOUNT_PER_RUN = AiAgent::FollowUpDispatcherJob::MAX_PER_ACCOUNT_PER_RUN

  def perform(account_id)
    # Contatos que JÁ receberam um envio enfileirado nesta rodada — evita
    # que regras diferentes mandem várias mensagens ao mesmo paciente no
    # mesmo run (o cooldown só vê status 'sent', que ainda não aconteceu).
    @enqueued_contacts = Set.new

    AiAgent::FollowUpRule.enabled.where(account_id: account_id).find_each do |rule|
      dispatch_for(rule)
    rescue StandardError => e
      Rails.logger.error(
        "[AiAgent::FollowUpDispatcherPerAccountJob] account=#{account_id} rule=#{rule.id} " \
        "#{e.class}: #{e.message[0, 200]}"
      )
    end
  end

  private

  def dispatch_for(rule)
    candidates = AiAgent::FollowUps::CandidateFinder.new(rule).call
    candidates.first(MAX_PER_ACCOUNT_PER_RUN).each { |c| process_candidate(rule, c) }
  end

  def process_candidate(rule, candidate)
    execution = upsert_execution(rule, candidate)
    # Pula se já está sent/failed/skipped — só enfileira pendentes.
    return unless execution.status == 'pending'

    # Anti-spam: cooldown da regra (envios já 'sent' de OUTRAS regras) OU já
    # enfileiramos algo pra esse contato nesta rodada (trava de rajada).
    if recently_followed_up?(rule, candidate[:contact_id]) || enqueued_this_run?(candidate[:contact_id])
      execution.update(status: 'skipped', skip_reason: 'per_contact_cooldown')
      return
    end

    @enqueued_contacts << candidate[:contact_id] if candidate[:contact_id]
    AiAgent::SendFollowUpJob.perform_later(execution.id)
  rescue ActiveRecord::RecordNotUnique
    # Race com outro worker do dispatcher — ignora, o outro já criou.
    nil
  end

  # `step_id` ENTRA na identidade de idempotência (casa com o índice único
  # COALESCE): passos distintos com o mesmo target_at viram execuções
  # distintas em vez de um beat sumir; o NULL do passo base é casado por
  # `IS NULL` no find_or_create_by!.
  def upsert_execution(rule, candidate)
    AiAgent::FollowUpExecution.create_with(
      status: 'pending',
      conversation_id: candidate[:conversation_id]
    ).find_or_create_by!(
      rule_id: rule.id,
      account_id: rule.account_id,
      contact_id: candidate[:contact_id],
      agenda_event_id: candidate[:agenda_event_id],
      step_id: candidate[:step_id],
      target_at: candidate[:target_at]
    )
  end

  def enqueued_this_run?(contact_id)
    contact_id.present? && @enqueued_contacts.include?(contact_id)
  end

  # True quando existe FollowUpExecution.sent pra esse contato dentro da
  # janela de cooldown DA REGRA (`cooldown_minutes`), vinda de OUTRA regra —
  # beats da própria cadência não contam (o espaçamento entre eles é escolha
  # explícita da regra). `cooldown_minutes = 0` desliga a trava de tempo
  # (a rajada no MESMO tick ainda é barrada por `enqueued_this_run?`).
  # Filtra por account_id pra isolar tenants.
  def recently_followed_up?(rule, contact_id)
    minutes = rule.cooldown_minutes.to_i
    return false if minutes.zero?

    AiAgent::FollowUpExecution
      .where(account_id: rule.account_id, contact_id: contact_id, status: 'sent')
      .where.not(rule_id: rule.id)
      .exists?(['sent_at >= ?', minutes.minutes.ago])
  end
end
