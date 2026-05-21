# Vínculos paciente↔responsável (Sprint I, PRD §13.2).
#
# Um Patient (responsável) pode acessar o portal de N outros Patients
# (dependentes). Caso clássico: pediatria — pais acessam dados dos filhos.
#
# `role` qualifica o vínculo (parent | guardian | curator | spouse | other) —
# útil pra log de auditoria e para regras futuras (curator pode ver financeiro
# do curatelado, por exemplo).
#
# `is_primary` marca o responsável principal (1 por dependente) — usado em
# notificações e em fluxos que precisam de "responsável único" (ex: assinatura
# de termo de menor).
class CreatePatientResponsibleLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :patient_responsible_links do |t|
      t.references :account, null: false, foreign_key: true, index: true

      # Patient que age (faz login, vê dependente)
      t.bigint :responsible_patient_id, null: false
      # Patient cujos dados são acessados
      t.bigint :dependent_patient_id,   null: false

      t.string  :role,        null: false, default: 'guardian'
      t.boolean :is_primary,  null: false, default: false
      t.datetime :active_from, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.datetime :active_until            # nil = ativo indefinidamente
      t.datetime :revoked_at              # nil = válido

      # Observações livres (parentesco específico, restrição etc).
      t.text :notes

      t.timestamps
    end

    add_index :patient_responsible_links, :responsible_patient_id,
              name: 'idx_resp_links_responsible'
    add_index :patient_responsible_links, :dependent_patient_id,
              name: 'idx_resp_links_dependent'
    add_index :patient_responsible_links,
              %i[responsible_patient_id dependent_patient_id],
              unique: true, name: 'idx_resp_links_unique_pair'

    add_foreign_key :patient_responsible_links, :patients,
                    column: :responsible_patient_id
    add_foreign_key :patient_responsible_links, :patients,
                    column: :dependent_patient_id
  end
end
