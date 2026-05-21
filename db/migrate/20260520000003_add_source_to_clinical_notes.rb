# Sprint L — Teleconsulta: rastreabilidade da origem da evolução clínica.
#
# `source='telemed_ai'` identifica evoluções geradas por IA e aprovadas pelo
# profissional. `proposed_evolution_id` aponta de volta pra proposta original
# (necessário pra auditoria CFM — "qual versão a IA gerou? qual o profissional
# aprovou?"). FK `nullify` porque evoluções manuais são a maioria e a proposta
# não deve impedir delete de uma nota assinada.
class AddSourceToClinicalNotes < ActiveRecord::Migration[7.1]
  def change
    add_reference :clinical_notes, :proposed_evolution,
                  null: true,
                  foreign_key: { on_delete: :nullify },
                  index: true

    add_column :clinical_notes, :source, :string, default: 'manual', null: false
    add_index  :clinical_notes, :source
  end
end
