# Solicitações de documento criadas pelo paciente via portal (PRD §8).
#
# Cobre dois cenários:
#   1. "2ª via" de documento específico (atestado, recibo, receita anteriores)
#      → `source_document_id` aponta para o original.
#   2. Solicitação genérica por tipo (paciente pede "atestado da última consulta")
#      → `document_type` preenchido, `source_document_id` nulo.
#
# Quando a clínica aprova e emite, `fulfilled_document_id` aponta para o novo
# `Document` gerado — o front pode mostrar "Aprovado — baixar aqui".
class CreatePortalDocumentRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :portal_document_requests do |t|
      t.references :account, null: false, foreign_key: true
      t.references :patient, null: false, foreign_key: true

      t.bigint :source_document_id   # 2ª via de documento específico
      t.string :document_type         # quando solicitação genérica por tipo
      t.text   :reason, null: false

      t.string   :status, null: false, default: 'pending'
      # 'pending' | 'approved' | 'rejected' | 'fulfilled' | 'cancelled'

      t.bigint   :processed_by_id
      t.datetime :processed_at
      t.text     :processed_notes
      t.bigint   :fulfilled_document_id

      t.timestamps

      t.index :status
      t.index [:patient_id, :status]
    end
  end
end
