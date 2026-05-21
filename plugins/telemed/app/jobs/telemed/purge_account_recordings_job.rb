# Sprint L — Purge total das gravações de uma account.
#
# Caso de uso: clínica cancela a assinatura. Política do produto:
#   - Gravações de áudio são purgadas após N dias (default 365)
#   - ClinicalNote (evolução clínica) permanece — vira responsabilidade do
#     usuário (clínica pode exportar prontuário antes do prazo)
#
# Como hookar:
#   Quando o lifecycle de cancelamento da Account fechar, agendar:
#     PurgeAccountRecordingsJob
#       .set(wait: purge_after_cancellation_days.days)
#       .perform_later(account_id)
#
# Idempotente — pode rodar 2x sem dano (já arquivados são pulados).
# Pode ser cancelado antes de rodar se a clínica reativar a assinatura.
module Telemed
  class PurgeAccountRecordingsJob < ApplicationJob
    # Housekeeping pesado (deleta dezenas/centenas de objetos R2) —
    # mesma queue do EnforceRecordingQuotaJob. Audit Fase 2.
    queue_as :purgable

    def perform(account_id)
      account = Account.find_by(id: account_id)
      unless account
        Rails.logger.warn("[PurgeAccountRecordingsJob] account=#{account_id} não encontrada")
        return
      end

      active = TelemedRecording.for_account(account.id).active_storage
      total = active.count

      archived_count = 0
      active.find_each do |recording|
        begin
          recording.archive!(reason: 'account_subscription_cancelled')
          archived_count += 1
        rescue StandardError => e
          Rails.logger.error("[PurgeAccountRecordingsJob] archive #{recording.id} falhou: #{e.message}")
        end
      end

      Rails.logger.info("[PurgeAccountRecordingsJob] account=#{account.id} purgou=#{archived_count}/#{total}")
    end
  end
end
