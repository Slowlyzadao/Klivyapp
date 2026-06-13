# Audit Fase 2 — partial unique index pra impedir múltiplas
# ProposedEvolutions em `pending_review` pro mesmo telemed_recording.
#
# Cenário do audit (#31): admin re-enqueue manual de
# GenerateEvolutionJob (ex: via Sidekiq UI) sobre um recording cuja primeira
# evolução já foi criada → segunda `ProposedEvolution.create!` insere uma
# nova com status `pending_review`. UI mostra apenas a mais recente
# (latest_proposed_evolution) mas a antiga fica órfã.
#
# `partial unique` permite múltiplas `edited/approved/rejected` (histórico)
# mas só UMA `pending_review` por vez — o caminho de pipeline normal nunca
# colide; só pega retries indevidos.
#
# Aplicação:
#   - `concurrently` + `if_not_exists` pra rollouts seguros
#   - se DB tem dados existentes que violam (raro mas possível em produção
#     pré-fix), migration falha — limpar manualmente antes de aplicar
class AddProposedEvolutionUniquenessGuard < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :proposed_evolutions,
              :telemed_recording_id,
              where: "status = 'pending_review'",
              unique: true,
              algorithm: :concurrently,
              if_not_exists: true,
              name: 'idx_proposed_evolutions_unique_pending_per_recording'
  end
end
