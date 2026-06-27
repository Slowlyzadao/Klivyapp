# Audit Fase 2 — índices compostos pra queries quentes no pipeline telemed.
#
# Antes desta migration, `latest_recording_for(event)` fazia:
#   SELECT * FROM telemed_recordings
#   WHERE agenda_event_id = ? ORDER BY created_at DESC LIMIT 1
# Sem índice composto, Postgres usa `agenda_event_id` (single) e sort
# externo. Com volume de retries/replays cresce a passos largos.
#
# Quota job (`EnforceRecordingQuotaJob`) faz:
#   SELECT * FROM telemed_recordings
#   WHERE account_id = ? AND archived_at IS NULL
#   ORDER BY created_at
# Index partial `WHERE archived_at IS NULL` mantém tamanho enxuto
# (recordings ativos representam minoria após meses de operação).
#
# `concurrently: true` evita lock pesado em prod — exige
# `disable_ddl_transaction!`.
class AddTelemedAuditPhase2Indexes < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    # Hot path: latest recording por agenda_event (UI + webhook lookup).
    add_index :telemed_recordings,
              [:agenda_event_id, :created_at],
              order: { created_at: :desc },
              algorithm: :concurrently,
              if_not_exists: true,
              name: 'idx_telemed_recordings_event_created_desc'

    # Hot path: quota enforcement varre apenas registros ativos por account.
    # Partial index mantém footprint enxuto — archived passa pra "cold" naturalmente.
    add_index :telemed_recordings,
              [:account_id, :created_at],
              where: 'archived_at IS NULL',
              algorithm: :concurrently,
              if_not_exists: true,
              name: 'idx_telemed_recordings_active_account_created'

    # Hot path: listar proposed_evolutions em "pending review" ordenado.
    # Index existente é `[:telemed_recording_id, :created_at]`; este é
    # ortogonal — filtros globais (lista geral pra admin/superadmin).
    add_index :proposed_evolutions,
              [:status, :updated_at],
              algorithm: :concurrently,
              if_not_exists: true,
              name: 'idx_proposed_evolutions_status_updated'
  end
end
