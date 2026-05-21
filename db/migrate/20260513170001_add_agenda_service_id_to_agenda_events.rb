class AddAgendaServiceIdToAgendaEvents < ActiveRecord::Migration[7.0]
  # PR #4 da auditoria de 2026-05-13 (plugins/agenda/AUDITORIA_2026-05-13.md).
  #
  # Adiciona FK reversa `agenda_events.agenda_service_id`. Fim do débito raiz
  # do JSONB: até agora `agenda_events` linkava com `agenda_services` só via
  # `custom_attributes['treatment']` (string com NAME do serviço), causando:
  # - regressão visual em rename (cor pelo NAME quebra)
  # - órfão em delete (deletei mas string continua apontando para nada)
  # - filtros/relatórios impossíveis de fazer corretamente
  #
  # Estratégia:
  # - Coluna `bigint null: true` — eventos antigos ficam NULL até o backfill rodar.
  # - FK com `on_delete: :nullify` — se o serviço for HARD-deletado (raro;
  #   convenção é soft-delete via PR #1), Postgres limpa o FK
  #   automaticamente. Soft-delete preserva a linha → FK continua válido,
  #   evento ainda referencia o serviço arquivado.
  # - Index criado `concurrently` — sem LOCK exclusivo em produção
  #   (Mamedes ~2.500 eventos, mas escala pra dezenas de milhares conforme
  #   clínicas crescem).
  #
  # Aplicação:
  # 1. Esta migration sobe (aditiva — coluna nullable, zero risco em prod).
  # 2. Após deploy, o callback `before_save :resolve_agenda_service_id_from_treatment`
  #    em AgendaEvent começa a popular o FK em saves novos (duplo-write).
  # 3. Rake task `agenda_events:backfill_service_id` cobre eventos antigos.
  #
  # Para tabelas MUITO grandes (>1M de eventos), pode valer split em 3 migrations:
  # add_column → add_foreign_key validate: false → validate_foreign_key. No
  # nosso porte atual, esta migration única é segura.

  disable_ddl_transaction!

  def change
    add_reference :agenda_events, :agenda_service,
                  null: true,
                  foreign_key: { on_delete: :nullify },
                  index: { algorithm: :concurrently }
  end
end
