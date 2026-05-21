# Sprint L — Enforça quota de gravações ativas por clínica.
#
# Política (PRD §11 reformulado pelo stakeholder em 2026-05-20):
#   - ClinicalNote (evolução clínica) permanece 20 anos — CFM exige.
#   - Áudio da consulta é descartável — clínica tem cota de N gravações
#     ativas no plano. Excedeu → archive! da mais antiga (deleta R2,
#     mantém registro pra audit + a ClinicalNote derivada intacta).
#
# Quota:
#   - Default 15 (config `max_active_recordings` na patient_portal_setting)
#   - Plano futuro pode subir/baixar conforme assinatura
#
# Enfileirado automaticamente ao final do GenerateEvolutionJob (quando
# uma nova gravação fica `ready` e portanto entra na contagem).
# Pode também ser disparado manualmente via Rails console.
module Telemed
  class EnforceRecordingQuotaJob < ApplicationJob
    queue_as :default

    DEFAULT_QUOTA = 15

    def perform(account_id)
      account = Account.find_by(id: account_id)
      return unless account

      quota = resolve_quota(account)
      return if quota.to_i <= 0 # 0 ou negativo desativa quota.

      # Ordem: mais antigos primeiro pela data de criação. Apenas registros
      # NÃO arquivados que ainda têm storage no R2 (composite_audio_key).
      active = TelemedRecording.for_account(account.id)
                               .active_storage
                               .where.not(composite_audio_key: nil)
                               .order(:created_at)

      excess = active.count - quota
      return if excess <= 0

      to_archive = active.limit(excess)
      archived_count = 0

      to_archive.each do |recording|
        begin
          recording.archive!(reason: "quota_exceeded (#{quota})")
          archived_count += 1
        rescue StandardError => e
          Rails.logger.error("[EnforceRecordingQuotaJob] archive #{recording.id} falhou: #{e.message}")
        end
      end

      Rails.logger.info("[EnforceRecordingQuotaJob] account=#{account.id} arquivou=#{archived_count} quota=#{quota}")
    end

    private

    def resolve_quota(account)
      cfg = account.patient_portal_setting&.telemedicine_recording
      return DEFAULT_QUOTA unless cfg.is_a?(Hash)

      cfg.fetch('max_active_recordings', DEFAULT_QUOTA).to_i
    end
  end
end
