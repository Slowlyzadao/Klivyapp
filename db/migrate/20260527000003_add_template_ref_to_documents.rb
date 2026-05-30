# Adiciona FK + HTML congelado + hash de integridade ao Document.
#
# Comportamento esperado (lógica vai no model concern):
#   - document_template_id IS NULL  → Document gerado pelo caminho legado
#     (Prawn). Backward-compatible: linhas antigas seguem funcionando.
#   - document_template_id presente → Document gerado pelo editor novo via
#     Grover. rendered_html é o HTML congelado (imutável após criação).
#     pdf_hash é SHA-256 do arquivo PDF (preparação Clicksign + auditoria).
class AddTemplateRefToDocuments < ActiveRecord::Migration[7.1]
  def change
    change_table :documents do |t|
      t.references :document_template,
                   foreign_key: true,
                   index: true,
                   null: true  # NULL = caminho legado (Prawn)

      # HTML completo com variáveis JÁ RESOLVIDAS, congelado no momento da
      # geração. Imutável — fonte da verdade pra reimprimir e auditoria.
      # Validação `rendered_html_immutability` no concern impede UPDATE.
      t.text :rendered_html

      # SHA-256 hex (64 chars) do PDF anexado. Permite verificar integridade
      # do arquivo após backup/restore e dá base pra assinatura eletrônica
      # futura (Clicksign).
      t.string :pdf_hash, limit: 64
    end

    add_index :documents, :pdf_hash
  end
end
