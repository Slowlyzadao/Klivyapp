class CreateAgendaEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :agenda_events do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true # Dentista/Usuário atribuído
      t.references :contact, null: true, foreign_key: true # Paciente, opcional para poder agendar algo "reservado" no calendário
      
      t.string :title, null: false
      t.text :description
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      
      # Metadados clínicos/financeiros via hstore/jsonb ou colunas diretas? Optando por padrão do chatwoot em custom_attributes (jsonb se preferível)
      t.jsonb :custom_attributes, default: {}
      
      # Controle de status
      t.string :status, default: 'scheduled', null: false # scheduled, confirmed, arrived, in_progress, completed, cancelled, no_show
      t.string :type, default: 'appointment', null: false # type column para ser polimerórfica (se fosse usar STI) mas vamos evitar type.
      
      t.timestamps
    end

    # Alterando type string para evitar problemas de Single Table Inheritance com o Active Record caso não seja a intenção
    rename_column :agenda_events, :type, :event_type
  end
end
