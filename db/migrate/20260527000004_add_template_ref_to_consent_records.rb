# Adiciona FK + HTML congelado ao ConsentRecord.
#
# Diferença vs Documents (migration 20260527000003): NÃO adicionamos pdf_hash
# aqui porque ConsentRecord já tem `integrity_hash` (criado em migrations
# anteriores, usado pra hash da assinatura). Reusar o campo existente em vez
# de duplicar — o hash do PDF passa a viver lá quando o consentimento é
# renderizado via novo editor.
#
# Comportamento:
#   - document_template_id NULL → consentimento usa o `body` legado.
#   - document_template_id presente → renderiza rendered_html no lugar do body.
class AddTemplateRefToConsentRecords < ActiveRecord::Migration[7.1]
  def change
    change_table :consent_records do |t|
      t.references :document_template,
                   foreign_key: true,
                   index: true,
                   null: true

      # HTML congelado — mesmas regras de imutabilidade de Documents.
      t.text :rendered_html
    end
  end
end
