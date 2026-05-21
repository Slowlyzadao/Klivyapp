class CreateAgendaServiceUsers < ActiveRecord::Migration[7.0]
  # Auditoria agendamento público (item 9.7): hoje todos os serviços da conta
  # aparecem para qualquer profissional. Paciente pode marcar via link público
  # de Dr. A um serviço que só Dr. B oferece — `agenda_service_id` e `user_id`
  # do AgendaEvent ficam inconsistentes (serviço de uma especialidade marcada
  # com profissional de outra).
  #
  # Tabela de junção entre `agenda_services` e `users`. Fallback de compat:
  # serviço SEM nenhum vínculo continua acessível a todos os profissionais
  # da conta (preserva comportamento pré-9.7 até a clínica configurar via UI).
  # Quando 1+ vínculos existem, só os profissionais vinculados aparecem.
  def change
    create_table :agenda_service_users do |t|
      t.references :agenda_service, null: false, foreign_key: true
      t.references :user,           null: false, foreign_key: true
      t.timestamps
    end

    # 1 vínculo por par (service, user) — evita duplicação no painel.
    add_index :agenda_service_users, [:agenda_service_id, :user_id],
              unique: true, name: 'index_agenda_service_users_unique'
  end
end
