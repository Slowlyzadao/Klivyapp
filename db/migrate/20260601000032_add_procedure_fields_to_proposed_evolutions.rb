class AddProcedureFieldsToProposedEvolutions < ActiveRecord::Migration[7.1]
  # Audit 2026-05-26 — Migração da Evolução para o formato "Registrar
  # Procedimento" (mesmo schema usado em clínica estética). Substitui a
  # visualização em SOAP cards (subjetivo/objetivo/avaliação/plano) por
  # um formulário com 14 campos editáveis pré-preenchidos pela IA.
  #
  # O `soap_structure` antigo continua sendo gerado e persistido para
  # backward-compat com evoluções históricas — o frontend apenas deixa
  # de exibir. Numa próxima iteração podemos remover.
  def change
    add_column :proposed_evolutions, :procedure_fields, :jsonb, null: false, default: {}
  end
end
