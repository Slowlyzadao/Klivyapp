class AddProposedEvolutionIdToSessionLogs < ActiveRecord::Migration[7.1]
  # Audit 2026-05-26 — Trilha bidirecional teleconsulta → prontuário.
  #
  # Antes o approve da telemed criava ClinicalNote (modelo legado). O resto
  # do sistema (aba "Evolução" do paciente, ficha clínica, histórico) lê
  # de SessionLog (modelo novo unificado). Resultado: evolução aprovada
  # existia no banco mas não aparecia em lugar nenhum pro dentista.
  #
  # Esta coluna fecha o link novo: SessionLog#proposed_evolution_id →
  # ProposedEvolution. Permite rastrear "este registro veio de qual
  # teleconsulta" e bloquear edição de campos da IA com auditoria.
  def change
    add_reference :session_logs, :proposed_evolution, null: true, index: true
    add_foreign_key :session_logs, :proposed_evolutions, on_delete: :nullify
  end
end
