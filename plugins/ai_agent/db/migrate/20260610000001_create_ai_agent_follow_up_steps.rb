# Passos ADICIONAIS da cadência de uma FollowUpRule. O passo 1 é a
# própria regra (colunas `offset_hours`/`offset_unit`/`context_brief`);
# esta tabela guarda os passos 2..N — os "beats" extras de uma sequência
# de acompanhamento (ex: no_response em 3h, depois 1d, depois 3d).
#
# `dispatch_steps` no model junta [passo 1 sintético da regra] + estes
# passos ordenados. Como cada passo tem `offset` próprio, o `target_at`
# de cada disparo é distinto — a idempotência via UNIQUE em
# follow_up_executions já separa um passo do outro sem mudança de índice.
class CreateAiAgentFollowUpSteps < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_follow_up_steps do |t|
      t.references :rule, null: false,
                          foreign_key: { to_table: :ai_agent_follow_up_rules, on_delete: :cascade },
                          index: true

      # Ordem do passo na sequência. O passo 1 (a regra) é posição 0;
      # estes começam em 1. Usado só pra ordenação visual e de disparo.
      t.integer :position, null: false, default: 1

      # Offset POSITIVO + unidade, mesma semântica da regra. A direção
      # (antes/depois) continua vindo do `trigger_type` da regra.
      t.integer :offset_hours, null: false, default: 24
      t.string  :offset_unit, null: false, default: 'hours'

      # Cenário próprio deste passo — cada beat da cadência pode ter um
      # tom/objetivo diferente ("dia 1: lembrete leve" ≠ "dia 7: oferta").
      t.text :context_brief, null: false

      t.timestamps
    end

    add_index :ai_agent_follow_up_steps, %i[rule_id position],
              name: 'idx_ai_agent_follow_up_steps_order'
  end
end
