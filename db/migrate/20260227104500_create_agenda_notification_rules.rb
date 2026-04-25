class CreateAgendaNotificationRules < ActiveRecord::Migration[7.1]
  def change
    create_table :agenda_notification_rules do |t|
      t.references :account, null: false, foreign_key: true

      # Identificação visual
      t.string  :title,                null: false
      t.string  :rule_type,            null: false, default: 'reminder'
      # reminder | confirmation | followup | birthday | custom
      t.string  :icon,                 null: false, default: 'i-lucide-bell'
      t.string  :icon_color,           null: false, default: 'blue'

      # Configuração de disparo
      # Para rule_type 'reminder': número de horas ANTES da consulta (ex: 24.0, 2.0, 0.5)
      # Para outros tipos: null (sem offset temporal)
      t.decimal :trigger_offset_hours, precision: 8, scale: 2

      # Template da mensagem com variáveis ({nome_paciente}, {horario_consulta}, etc.)
      t.text    :message_template,     null: false

      # Caixas de entrada associadas (jsonb array de {label, inbox_id, color})
      t.jsonb   :inboxes,              null: false, default: []

      t.boolean :enabled,              null: false, default: true

      # Ordem de exibição no frontend
      t.integer :position,             null: false, default: 0

      t.timestamps
    end

    add_index :agenda_notification_rules, [:account_id, :rule_type]
    add_index :agenda_notification_rules, [:account_id, :enabled]
  end
end
