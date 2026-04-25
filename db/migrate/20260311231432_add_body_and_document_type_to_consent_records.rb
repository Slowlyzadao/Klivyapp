class AddBodyAndDocumentTypeToConsentRecords < ActiveRecord::Migration[7.1]
  def change
    add_column :consent_records, :body, :text
    add_column :consent_records, :document_type, :string
    add_column :consent_records, :observations, :text
  end
end
