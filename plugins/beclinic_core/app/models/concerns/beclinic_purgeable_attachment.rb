# plugins/beclinic_core/app/models/concerns/beclinic_purgeable_attachment.rb
#
# Concern para padronizar o purge físico de attachments (R2/S3) após período
# de retenção pós soft-delete.
#
# Fluxo de uso:
#   1. Model declara `purges_attachment_with(job_class: MeuPurgeJob)`
#   2. Model implementa `soft_delete!` chamando `schedule_attachment_purge!`
#   3. Job removido após `after:` (default 30 dias) checa se record continua
#      soft-deleted e roda `attachment.purge_later + record.destroy!`
#
# Padrão herdado de Patients::ExamMediaPurgeJob, agora generalizado para
# Document, ConsentRecord, Transaction (e qualquer model novo com attachment
# em retenção).
#
# Por que cross-plugin: Document/ConsentRecord vivem em `patients`, Transaction
# em `financial`. Concern compartilhado vive em `beclinic_core`.

module BeclinicPurgeableAttachment
  extend ActiveSupport::Concern

  DEFAULT_PURGE_AFTER = 30.days

  class_methods do
    # Configura o job que será enfileirado quando `schedule_attachment_purge!`
    # for chamado. O job deve aceitar o `id` do record como único argumento e
    # ser idempotente (record já destruído = no-op).
    #
    # @param job_class [Class] Classe do job (ex.: Patients::DocumentPurgeJob)
    # @param after [ActiveSupport::Duration] janela de retenção (default 30.days)
    def purges_attachment_with(job_class:, after: DEFAULT_PURGE_AFTER)
      @beclinic_purge_job_class = job_class
      @beclinic_purge_window = after
    end

    def beclinic_purge_job_class
      @beclinic_purge_job_class
    end

    def beclinic_purge_window
      @beclinic_purge_window || DEFAULT_PURGE_AFTER
    end
  end

  # Enfileira o job de purga. Chamar dentro do soft_delete! do model após
  # marcar `deleted_at`. Ignora silenciosamente se o model não declarou
  # `purges_attachment_with`.
  def schedule_attachment_purge!
    job_class = self.class.beclinic_purge_job_class
    return unless job_class

    job_class.set(wait: self.class.beclinic_purge_window).perform_later(id)
  end
end
