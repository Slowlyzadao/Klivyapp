class AddExternalIdsToPatients < ActiveRecord::Migration[7.0]
  # JSONB genérico para guardar IDs de sistemas externos importados
  # (Clinicorp, BeClinic, Dentrix, etc.). Cada chave é o nome do sistema:
  #
  #   { "clinicorp": "5025635697819648", "dentrix": "PT-12345" }
  #
  # Usado pra resolver vínculos em imports subsequentes — ex: ao importar
  # `TreatmentOperation.xlsx`, lookup do paciente se faz por
  # `external_ids ->> 'clinicorp'` em vez de fuzzy match por nome.
  #
  # Índice GIN cobre queries `WHERE external_ids ? 'clinicorp'` e
  # `WHERE external_ids @> '{"clinicorp": "..."}'::jsonb`. Não é unique
  # — caso real de duplicidade (mesmo paciente importado 2x antes do PR
  # ser merged) cai no merge idempotente do importer.
  def change
    add_column :patients, :external_ids, :jsonb, default: {}, null: false
    add_index :patients, :external_ids, using: :gin, name: 'index_patients_on_external_ids'
  end
end
