class AddExternalMetadataAndIdsForTreatmentOperationImport < ActiveRecord::Migration[7.0]
  # Suporta a importação de `TreatmentOperation.xlsx` (Fase 7 do roadmap):
  #
  # 1. `external_metadata` em `session_logs` e `treatment_items` — guarda os
  #    campos livres do Clinicorp que não têm coluna dedicada no Klivy
  #    (`ProcedureCondition`, `Type`, `NextAppointmentNotes`, `Surface`, `Tooth`,
  #    `Notes` brutas, etc.). JSONB genérico com índice GIN pra permitir queries
  #    futuras tipo `WHERE external_metadata @> '{"source": "clinicorp"}'`.
  #
  # 2. `external_ids` em `treatment_plans`, `treatment_items` e `session_logs`
  #    — segue o mesmo padrão de `patients.external_ids` adicionado em
  #    [1.5.2.7]. Permite idempotência do importer: na 2ª passada, lookup por
  #    `external_ids ->> 'clinicorp_operation_id' = OperationId` evita criar
  #    registros duplicados. Cada chave é o nome do sistema externo:
  #
  #      { "clinicorp_operation_id": "16498", "clinicorp_plan_seed": "patient_42" }
  #
  # Índices GIN nas duas colunas pra cobrir as queries do importer/previewer.
  def change
    %i[session_logs treatment_items treatment_plans].each do |table|
      add_column table, :external_metadata, :jsonb, default: {}, null: false
      add_column table, :external_ids,      :jsonb, default: {}, null: false
      add_index  table, :external_metadata, using: :gin, name: "index_#{table}_on_external_metadata"
      add_index  table, :external_ids,      using: :gin, name: "index_#{table}_on_external_ids"
    end
  end
end
