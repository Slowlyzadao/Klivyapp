# app/jobs/patients/exam_media_purge_job.rb
#
# Purga definitiva de ExamMedia soft-deleted após o período de retenção.
#
# Fluxo:
#   1. ExamMediasController#destroy → exam.soft_delete! → enfileira job com wait: 30.days
#   2. Após 30 dias, job verifica:
#      - Se o registro ainda está soft-deleted (não foi restaurado): apaga blob + destrói record.
#      - Se foi restaurado (deleted_at = nil): no-op silencioso.
#
# Idempotente: se job rodar duas vezes (ex.: retry), a segunda execução é no-op
# porque o record já não existe mais.

module Patients
  class ExamMediaPurgeJob < ApplicationJob
    queue_as :patients

    sidekiq_options retry: 3, dead: true

    def perform(exam_media_id)
      media = ExamMedia.deleted.find_by(id: exam_media_id)
      return unless media # já foi destruído manualmente OU foi restaurado

      # `purge_later` enfileira o purge do blob no Active Storage; aceitamos a
      # reentrância: se a transação destroy! falhar, o blob ainda é purgado.
      media.file.purge_later if media.file.attached?
      media.destroy!
      Rails.logger.info("[ExamMediaPurgeJob] purged exam_media=#{exam_media_id}")
    end
  end
end
