# Adiciona o discriminador semântico `recurrence_type` ao FinancialEstimate.
# Faz parte do PR 1 (foundations) do refactor financeiro do prontuário —
# permite separar `avulso` (1 parcela), `parcelamento` (N parcelas com fim
# definido) e `mensalidade` (recorrência) sem entidade nova. Usado pela nova
# timeline financeira; não afeta nenhum write existente.
#
# Backfill conservador: deduzido de `installments_count`. Nenhum registro
# vira `mensalidade` no histórico — usuário marca a partir daqui.
#
# Migration é forward-only por convenção do projeto (down no-op).
#
# `disable_ddl_transaction!` permite criar índice CONCURRENTLY (sem travar
# gravações em produção). `add_column` com default + null:false ainda é
# rápido em PG 11+ (column rewrite evitado para tipos integer).
class AddRecurrenceTypeToFinancialEstimates < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    unless column_exists?(:financial_estimates, :recurrence_type)
      add_column :financial_estimates, :recurrence_type, :integer, default: 0, null: false
    end

    unless index_exists?(:financial_estimates, [:account_id, :recurrence_type])
      add_index :financial_estimates, [:account_id, :recurrence_type], algorithm: :concurrently
    end

    # Backfill: registros com >1 parcela viram :parcelamento (1).
    # :avulso (0) já é o default — não precisa update explícito.
    # Idempotente: só toca registros que ainda estão em 0.
    FinancialEstimate.reset_column_information
    FinancialEstimate.unscoped
                     .where('installments_count > 1')
                     .where(recurrence_type: 0)
                     .in_batches(of: 1000) do |batch|
      batch.update_all(recurrence_type: 1)
    end
  end

  def down
    # No-op: migrations de feature são forward-only no projeto.
  end
end
