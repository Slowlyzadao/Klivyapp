# BE-7 (auditoria 2026-05-18): previne double-booking via race condition
# no `AiAgent::Tools::BookAppointmentTool` (e Internal counterpart).
#
# Hoje o tool faz check de duplicata via Ruby ANTES do create:
#
#   active_match = AgendaEvent.where(account_id:, contact_id:, starts_at:)
#                             .where.not(status: %w[cancelled no_show])
#                             .where(user_id: ...) if user_id
#   return duplicate if active_match.first
#
# Duas calls concorrentes do mesmo paciente no mesmo slot podem ambas
# passar do check (`.first` retorna nil pra ambas) e criar 2 eventos.
# Cenário real: LLM "perde contexto" e re-emite a tool call em paralelo.
#
# Fix: unique partial index no banco — segunda call explode com
# RecordNotUnique, que o tool captura e retorna duplicate-friendly
# (mudança nos tools em commit separado).
#
# Chave: (account_id, contact_id, COALESCE(user_id, 0), starts_at)
#   - `COALESCE(user_id, 0)` cobre quando profissional não é informado
#     (NULL viraria "distinct" no PG default — colapsa pra grupo "sem
#     profissional" via 0).
#   - Partial WHERE `deleted_at IS NULL AND status NOT IN ('cancelled',
#     'no_show')` casa com o scope do tool — eventos mortos não bloqueiam
#     nova reserva no mesmo slot.
#
# CONCURRENTLY: agenda_events sob tráfego em prod — sem trava de write.
#
# ⚠️ PRE-FLIGHT: rodar antes do db:migrate em prod pra confirmar 0 duplicatas:
#
#   docker compose exec rails bundle exec rails runner "
#     dupes = AgendaEvent
#       .where(deleted_at: nil)
#       .where.not(status: %w[cancelled no_show])
#       .group(:account_id, :contact_id, Arel.sql('COALESCE(user_id, 0)'), :starts_at)
#       .having('COUNT(*) > 1')
#       .pluck(:account_id, :contact_id, Arel.sql('COALESCE(user_id, 0)'), :starts_at, Arel.sql('COUNT(*)'))
#     puts \"Duplicatas: #{dupes.size}\"
#     dupes.first(10).each { |d| puts d.inspect }
#   "
#
# Se >0, resolver dados antes (decisão da equipe: soft-delete os mais
# recentes ou consolidar manualmente).
class AddUniqueIndexOnAgendaEventsAntiDoubleBooking < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  INDEX_NAME = 'idx_agenda_events_unique_active_slot_per_patient'.freeze

  def up
    execute <<~SQL.squish
      CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS #{INDEX_NAME}
      ON agenda_events (account_id, contact_id, COALESCE(user_id, 0), starts_at)
      WHERE deleted_at IS NULL
        AND status NOT IN ('cancelled', 'no_show')
    SQL
  end

  def down
    execute <<~SQL.squish
      DROP INDEX CONCURRENTLY IF EXISTS #{INDEX_NAME}
    SQL
  end
end
