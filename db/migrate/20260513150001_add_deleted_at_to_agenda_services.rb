class AddDeletedAtToAgendaServices < ActiveRecord::Migration[7.0]
  # PR #1 da auditoria de 2026-05-13 (plugins/agenda/AUDITORIA_2026-05-13.md).
  #
  # Adiciona soft-delete em `agenda_services`. Justificativa:
  # `AgendaService` é referenciada por `agenda_events.custom_attributes['treatment']`
  # (string com o NOME do serviço, sem FK) — milhares de eventos antigos em
  # produção dependem desse nome para renderizar cor/filtro no calendário e
  # para casar preços no plano de tratamento (TreatmentItemModal).
  #
  # Com `destroy!` físico (comportamento atual), excluir um serviço deixa
  # todos os eventos antigos órfãos silenciosamente. Soft-delete preserva
  # a linha para que o histórico continue legível enquanto a Fase 3 da
  # migração (backfill de `agenda_service_id` nos eventos) não terminar.
  #
  # O índice parcial `(account_id, deleted_at)` cobre o scope `kept` (que
  # filtra `deleted_at IS NULL`) e o scope reverso `discarded`.
  #
  # Migration aditiva — zero risco. Não toca dados existentes.

  def change
    add_column :agenda_services, :deleted_at, :datetime
    add_index :agenda_services, [:account_id, :deleted_at],
              name: 'index_agenda_services_on_account_id_and_deleted_at'
  end
end
