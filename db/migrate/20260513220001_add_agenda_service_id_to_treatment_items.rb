class AddAgendaServiceIdToTreatmentItems < ActiveRecord::Migration[7.0]
  # PR #6b da auditoria de 2026-05-13 (docs/audits/agenda-2026-05-13.md).
  #
  # Fim do débito de NAME-string em `treatment_items` — mesma classe de bug que
  # PR #4 resolveu em `agenda_events`. Hoje a tabela tem `procedure_name`
  # (string), o que causa:
  # - **B9**: ao editar um item de plano, o `TreatmentItemModal` casa o nome
  #   armazenado contra `agendaServices.find(s => s.name === procedure_name)`.
  #   Se o serviço foi renomeado, o match falha, o preço-base é resetado pra 0
  #   e o operador edita um item achando que está OK. Bug silencioso.
  # - Match cross-tenant impossível de garantir sem FK.
  # - Plano de tratamento (documento "contrato") perde rastreabilidade do
  #   serviço original quando renomeado em massa.
  #
  # Convivência das duas chaves (`procedure_name` + `agenda_service_id`):
  # - `procedure_name` permanece como **snapshot histórico** — qual era o nome
  #   do procedimento no momento que o plano foi assinado. Audit trail.
  # - `agenda_service_id` é a **referência viva** — usado para auto-select,
  #   match de preço, e relatórios atualizados.
  #
  # FK com `on_delete: :nullify`: se um serviço for hard-deletado, o item de
  # tratamento preserva `procedure_name` (snapshot) mas perde o FK.
  # Soft-delete (PR #1) preserva o FK porque a linha continua existindo.
  #
  # Migration aditiva — coluna nullable, zero risco em produção.

  disable_ddl_transaction!

  def change
    add_reference :treatment_items, :agenda_service,
                  null: true,
                  foreign_key: { on_delete: :nullify },
                  index: { algorithm: :concurrently }
  end
end
