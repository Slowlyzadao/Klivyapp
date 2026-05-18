module AiAgent
  # Cron a cada 15min: descobre candidatos elegíveis pra cada FollowUpRule
  # e cria as `FollowUpExecution` (status pending) + enfileira o
  # `SendFollowUpJob` pra cada uma.
  #
  # Idempotência: o índice UNIQUE em (rule_id, contact_id, agenda_event_id,
  # target_at) garante que rodar duas vezes seguidas não duplica disparo.
  # `find_or_create_by` no app camada batendo no UNIQUE garante que a
  # execução existe antes de enfileirar.
  #
  # Cap diário: cada conta dispara no máximo `MAX_PER_ACCOUNT_PER_RUN`
  # follow-ups por execução do cron (anti-flood em caso de erro de
  # configuração — ex: cliente cria regra que bate em 5000 pacientes).
  class FollowUpDispatcherJob < ApplicationJob
    queue_as :scheduled_jobs

    MAX_PER_ACCOUNT_PER_RUN = 200

    # Janela mínima entre 2 follow-ups pra um mesmo contato. Sem isso,
    # múltiplas regras overlapping (pré-consulta + recall + lembrete +
    # pesquisa + reativação) podem mandar 5 mensagens em sequência.
    # Conservador por design — paciente recebe no máximo 1 follow-up
    # automático a cada 2h.
    PER_CONTACT_COOLDOWN = 2.hours

    def perform
      AiAgent::FollowUpRule.enabled.find_each do |rule|
        dispatch_for(rule)
      rescue StandardError => e
        Rails.logger.error("[AiAgent::FollowUpDispatcherJob] rule=#{rule.id} #{e.class}: #{e.message[0, 200]}")
      end
    end

    private

    def dispatch_for(rule)
      candidates = AiAgent::FollowUps::CandidateFinder.new(rule).call
      return if candidates.empty?

      candidates.first(MAX_PER_ACCOUNT_PER_RUN).each do |c|
        execution = AiAgent::FollowUpExecution.create_with(
          status: 'pending',
          conversation_id: c[:conversation_id]
        ).find_or_create_by!(
          rule_id: rule.id,
          account_id: rule.account_id,
          contact_id: c[:contact_id],
          agenda_event_id: c[:agenda_event_id],
          target_at: c[:target_at]
        )

        # Pula se já está sent/failed/skipped — só enfileira pendentes.
        next unless execution.status == 'pending'

        # Cooldown por contato: se já enviamos follow-up nas últimas 2h,
        # marca como skipped e segue. Anti-spam quando regras overlappam.
        if recently_followed_up?(rule.account_id, c[:contact_id])
          execution.update(status: 'skipped', skip_reason: 'per_contact_cooldown')
          Rails.logger.info("[AiAgent::FollowUpDispatcherJob] rule=#{rule.id} contact=#{c[:contact_id]} skip: cooldown")
          next
        end

        AiAgent::SendFollowUpJob.perform_later(execution.id)
      rescue ActiveRecord::RecordNotUnique
        # Race com outro worker do dispatcher — ignora, o outro já criou.
        next
      end
    end

    # True quando existe FollowUpExecution.sent pra esse contato dentro
    # da janela de cooldown. Filtra por account_id pra isolar tenants.
    def recently_followed_up?(account_id, contact_id)
      AiAgent::FollowUpExecution
        .where(account_id: account_id, contact_id: contact_id, status: 'sent')
        .where('sent_at >= ?', PER_CONTACT_COOLDOWN.ago)
        .exists?
    end
  end
end
