# Sprint L — Teleconsulta: proposta de evolução clínica gerada por LLM.
#
# Separada de `telemed_recordings` (PRD §7.2) pra permitir reprocessar a
# proposta com outro provider sem refazer gravação/transcrição. Cada
# recording pode ter N proposed_evolutions (1 por chamada de LLM), mas
# apenas a última `pending_review`/`approved` é mostrada por padrão.
#
# Workflow:
#   pending_review → (editar) → approved → cria ClinicalNote(source='telemed_ai')
#                            ↘ rejected
class CreateProposedEvolutions < ActiveRecord::Migration[7.1]
  def change
    create_table :proposed_evolutions do |t|
      t.references :telemed_recording, null: false, foreign_key: true, index: true
      # FK pro ClinicalNote criado a partir desta proposta. NULL até aprovação.
      t.references :clinical_note,     null: true,  foreign_key: true, index: true

      # Modelo LLM usado (string livre — versionamento ad-hoc).
      # Ex.: 'claude-sonnet-4.6', 'gpt-4o', 'gemini-2.5-pro'.
      t.string :provider, null: false

      # Estrutura SOAP parseada. Hash com keys ['subjetivo','objetivo','avaliacao','plano'].
      # Mantemos também `raw_markdown` pra UI mostrar versão sem perdas e pra
      # auditoria caso o parser falhe em recortar seções.
      t.jsonb :soap_structure,  default: {}, null: false
      t.text  :raw_markdown
      # Pontos de atenção destacados pelo LLM: alergias, contraindicações, etc.
      # Estrutura: [{type, severity, text}, ...]. Usado pra highlight no editor.
      t.jsonb :attention_points, default: [], null: false

      t.string :status, null: false, default: 'pending_review'
      # values: pending_review | edited | approved | rejected

      t.references :reviewed_by, foreign_key: { to_table: :users }, index: true
      t.datetime   :reviewed_at
      t.text       :reviewer_notes # justificativa em rejeições / observações livres

      # Telemetria de custo. Permite calcular margem real por consulta sem
      # depender de API do provider.
      t.integer :input_tokens
      t.integer :output_tokens

      t.timestamps
    end

    add_index :proposed_evolutions, :status
    add_index :proposed_evolutions, [:telemed_recording_id, :created_at],
              name: 'index_proposed_evolutions_on_recording_and_created'
  end
end
