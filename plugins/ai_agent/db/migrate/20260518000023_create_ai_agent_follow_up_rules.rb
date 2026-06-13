class CreateAiAgentFollowUpRules < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_follow_up_rules do |t|
      t.references :account, null: false, foreign_key: true, index: true

      t.string :name, null: false, limit: 120
      t.boolean :enabled, null: false, default: true
      t.integer :position, null: false, default: 0

      # Tipo de gatilho — controla qual query CandidateFinder roda:
      #   pre_appointment   — N horas ANTES de AgendaEvent.starts_at
      #   post_appointment  — N horas DEPOIS de AgendaEvent.starts_at
      #   no_response       — paciente não responde há N horas (engajamento parado)
      #   no_show           — AgendaEvent.status='no_show' há N horas
      #   custom            — apenas dispara via API explícita (sem cron)
      t.string :trigger_type, null: false

      # Offset em horas. Sempre POSITIVO no banco. A direção (antes/depois)
      # vem do trigger_type. Ex: trigger=pre_appointment + offset_hours=24
      # = "24h antes da consulta". Para no_response/no_show é "horas após
      # o evento de referência".
      t.integer :offset_hours, null: false, default: 24

      # Filtros adicionais por tipo. Ex: pra pre_appointment, restringir a
      # status=['scheduled','confirmed']. Pra post_appointment, status=
      # ['completed','no_show']. Estrutura jsonb pra evoluir sem migration.
      t.jsonb :status_filter, null: false, default: {}

      # O "cenário" que vira contexto pro MessageGenerator. Texto livre
      # explicando o objetivo desse follow-up — Bea usa pra gerar a
      # mensagem em PT-BR. Ex: "Lembrar paciente da consulta amanhã,
      # confirmar presença, oferecer remarcar se não puder vir."
      t.text :context_brief, null: false

      # Anti-flood: cada (rule, target_appointment_or_contact) só recebe
      # follow-up dessa rule N vezes. 1 = uma vez por consulta;
      # 0 = ilimitado.
      t.integer :max_per_target, null: false, default: 1

      t.timestamps
    end

    add_index :ai_agent_follow_up_rules, %i[account_id enabled trigger_type], name: 'idx_ai_agent_follow_up_rules_dispatch'
  end
end
