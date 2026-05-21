# Roadmap (fora-de-escopo) — `patients_controller#index` JSONB query lenta.
#
# A query principal de [appointments_controller#index] em
# `plugins/patients/app/controllers/api/v1/accounts/patients/appointments_controller.rb:28`
# faz:
#
#   WHERE (custom_attributes->>'patient_id' = ?)
#     OR (contact_id = ? AND custom_attributes->>'patient_id' IS NULL/'')
#
# Sem índice na expressão `custom_attributes->>'patient_id'`, todo lookup
# faz seq scan em `agenda_events`. Com escala (10k+ eventos) isso vira
# minutos de latência ao abrir a aba "Agenda e Histórico" do prontuário.
#
# Solução: índice B-tree em expressão. É mais eficiente que GIN para o
# caso específico de equality (= '123') do que containment.
#
# Índice **parcial** (WHERE NOT NULL) mantém o tamanho do índice baixo —
# a maioria dos eventos da agenda não tem `patient_id` no JSONB
# (vinculados via `contact_id` direto), apenas os de pacientes
# explicitamente associados.
#
# `disable_ddl_transaction!` permite criar índice CONCURRENTLY (sem
# travar gravações na tabela durante a criação — crítico em produção).

class IndexAgendaEventsPatientIdInCustomAttributes < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  INDEX_NAME = 'index_agenda_events_on_patient_id_in_custom_attrs'

  def up
    return if index_exists?(:agenda_events, "(custom_attributes->>'patient_id')", name: INDEX_NAME)

    add_index :agenda_events,
              "(custom_attributes->>'patient_id')",
              name: INDEX_NAME,
              where: "(custom_attributes->>'patient_id') IS NOT NULL AND (custom_attributes->>'patient_id') <> ''",
              algorithm: :concurrently
  end

  def down
    return unless index_exists?(:agenda_events, nil, name: INDEX_NAME)

    remove_index :agenda_events, name: INDEX_NAME, algorithm: :concurrently
  end
end
