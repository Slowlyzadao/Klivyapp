# config/initializers/active_storage_transform_job_scoping.rb
#
# Propaga Current.account no ActiveStorage::TransformJob (geracao de variants).
#
# Por que: o initializer active_storage_account_scoping.rb prefixa blobs com
# accounts/<id>/ quando Current.account esta setado. Variants do Active Storage
# (thumbnails 400x400, previews de PDF/video) sao gerados via TransformJob,
# job Sidekiq interno do Rails. Em alguns fluxos, Current.account ja esta nil
# no momento do enqueue (rendering de view em background, retry de variant
# antiga, processamento em job sem contexto de tenancy), entao a middleware
# Sidekiq nao tem o que propagar e a variant cai na raiz do bucket.
#
# Esta around_perform deriva account a partir do BLOB ORIGINAL (que ja tem
# attachment pro record real -- ExamMedia, Contact, Patient, etc.) e seta
# Current.account durante o perform. Ensure restaura no fim, preservando o
# thread pool do Sidekiq sem leak entre jobs.
#
# Edge cases:
#   - Current.account ja setado (fluxo sync com contexto) -> nao sobrescreve
#   - Blob sem attachment (race condition rara) -> no-op, executa sem set
#   - Record nao responde a :account / :account_id -> no-op
#   - Variant de variant (record_type == ActiveStorage::VariantRecord) ->
#     no-op por enquanto; caso raro, pode ser adicionado se aparecer

Rails.application.config.to_prepare do
  ActiveStorage::TransformJob.around_perform do |job, block|
    if Current.account.present?
      block.call
    else
      blob = job.arguments.first
      attachment = blob&.attachments&.first
      record = attachment&.record

      account = if record.respond_to?(:account) && record.account.present?
                  record.account
                elsif record.respond_to?(:account_id)
                  Account.find_by(id: record.account_id)
                end

      if account
        previous = Current.account
        Current.account = account
        begin
          block.call
        ensure
          Current.account = previous
        end
      else
        block.call
      end
    end
  end
end
