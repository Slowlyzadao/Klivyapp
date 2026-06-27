class AddUuidAndExternalIdToAgendaServices < ActiveRecord::Migration[7.0]
  # PR #2 da auditoria 2026-05-13: identificadores estáveis para integrações.
  #
  # Por que UUID + external_id (e não só um):
  # - `uuid`: identificador público estável e não-sequencial (não-enumerável).
  #   Para URLs públicas (catálogo de serviços), webhooks, e qualquer integração
  #   externa onde expor `id` numérico revela tamanho da base e permite scraping.
  # - `external_id`: identificador idempotente para importadores. Ex.: importador
  #   Clinicorp armazena o ID original do sistema externo aqui — rerun da
  #   importação encontra o mesmo serviço em vez de duplicar (C8 da auditoria).
  #
  # Ambos opcionais (`null: true`):
  # - `uuid` ganha default `gen_random_uuid()` para preencher novos registros
  #   automaticamente. Registros existentes recebem UUID no próximo save
  #   (não há backfill em massa nesta migration; eles podem rodar sem UUID
  #   até serem editados).
  # - `external_id` fica nulo para serviços não-importados. Quando setado,
  #   é unique por `(account_id, external_id)` — o importador garante isso.
  #
  # Índices:
  # - `uuid` UNIQUE (global) — pra URL pública sempre funcionar.
  # - `(account_id, external_id)` UNIQUE WHERE external_id IS NOT NULL — só
  #   garante unicidade quando preenchido; serviços manuais sem external_id
  #   não colidem.

  disable_ddl_transaction!

  def change
    # gen_random_uuid() requer pgcrypto extension; Postgres 13+ tem como built-in.
    enable_extension 'pgcrypto' unless extension_enabled?('pgcrypto')

    add_column :agenda_services, :uuid, :uuid, default: -> { 'gen_random_uuid()' }
    add_column :agenda_services, :external_id, :string, limit: 100

    # Backfill: o `default` só popula INSERTs novos; rows pré-existentes ficam
    # com NULL. Esta migration garante que TODOS os 2050+ serviços históricos
    # ganhem um UUID válido antes do unique index. Operação rápida (2050 rows
    # × 1 chamada por row de função volátil) — segundos no Mamedes.
    reversible do |dir|
      dir.up do
        execute 'UPDATE agenda_services SET uuid = gen_random_uuid() WHERE uuid IS NULL'
      end
    end

    add_index :agenda_services, :uuid,
              unique: true,
              name: 'uniq_agenda_services_uuid',
              algorithm: :concurrently

    # Index parcial: só impõe unicidade quando external_id está preenchido.
    # Serviços manuais (sem importador) seguem com NULL e não colidem.
    add_index :agenda_services, [:account_id, :external_id],
              unique: true,
              where: 'external_id IS NOT NULL',
              name: 'uniq_agenda_services_account_external_id',
              algorithm: :concurrently
  end
end
