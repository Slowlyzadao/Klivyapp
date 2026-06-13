class AddMetadataToFinancialInstallments < ActiveRecord::Migration[7.0]
  # `financial_installments` foi criada sem coluna `metadata` jsonb (apenas
  # `gateway_metadata` para info do PSP). Adicionando para suportar:
  #   - rastreamento de migração legacy → v2 (legacy_table, legacy_id)
  #   - flags ad-hoc futuras (auto_generated, import_batch, etc.)
  def change
    add_column :financial_installments, :metadata, :jsonb, default: {}, null: false
    # Index GIN só se houver volume — pular por enquanto (custo de write).
  end
end
