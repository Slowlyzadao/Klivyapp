# Roadmap #18.1 — backfill `consent_records.status` de valores legacy
# (`assinado_localmente`, `assinado_remotamente`) para o canônico `signed`.
#
# Pré-condições (entrada CHANGELOG 1.5.1.70 — forward-compat):
#   - O modelo já trata os 3 valores como "assinado" via `SIGNED_STATUSES`.
#   - O frontend já renderiza ambos como "Assinado".
#   - Toda nova assinatura grava `signed`. A diferenciação local/remoto
#     vive na coluna `mode` (`local_tablet` / `remote_link`), exposta via
#     `signature_method` ('local'/'remote') no JSON.
#
# Esta migration:
#   1. Atualiza linhas legacy para `signed` em batches de 500 (evita lock
#      longo em tabelas grandes).
#   2. NÃO altera `mode` — ele já carrega a diferenciação.
#   3. É idempotente — rodar duas vezes não tem efeito.
#
# PÓS-MIGRATION (manual, em PR separado):
#   - Remover `LEGACY_SIGNED_STATUSES` da constante em `consent_record.rb`.
#   - Simplificar `SIGNED_STATUSES = %w[signed].freeze`.

class BackfillConsentSignedStatus < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  BATCH_SIZE = 500

  def up
    # Conta antes para log/observabilidade.
    legacy_count = ConsentRecord.where(status: %w[assinado_localmente assinado_remotamente]).count
    say "[BackfillConsentSignedStatus] linhas legacy a migrar: #{legacy_count}"

    return if legacy_count.zero?

    migrated = 0
    loop do
      affected = ConsentRecord
                 .where(status: %w[assinado_localmente assinado_remotamente])
                 .limit(BATCH_SIZE)
                 .update_all(status: 'signed', updated_at: Time.current)
      break if affected.zero?

      migrated += affected
      say "[BackfillConsentSignedStatus] batch concluído — total #{migrated}/#{legacy_count}"
    end

    say "[BackfillConsentSignedStatus] migração concluída — #{migrated} linhas atualizadas"
  end

  def down
    # Sem rollback automático — o mapeamento `signed` → original
    # (`assinado_localmente` vs `assinado_remotamente`) só é recuperável
    # cruzando com a coluna `mode` (`local_tablet` → `assinado_localmente`).
    say '[BackfillConsentSignedStatus] rollback não é automático — restaurar a partir do `mode` se necessário:'
    say "  UPDATE consent_records SET status = 'assinado_localmente' WHERE status = 'signed' AND mode = 'local_tablet';"
    say "  UPDATE consent_records SET status = 'assinado_remotamente' WHERE status = 'signed' AND mode = 'remote_link';"
  end
end
