module Financial
  module Backup
    # Adapter pra Cloudflare R2 (S3-compatible). Reaproveita as envs
    # STORAGE_* já usadas pelo Active Storage (config/storage.yml -
    # service `s3_compatible`) — mesma infra dos uploads de exames.
    #
    # Envs (Chatwoot-style):
    #   STORAGE_ACCESS_KEY_ID
    #   STORAGE_SECRET_ACCESS_KEY
    #   STORAGE_BUCKET_NAME
    #   STORAGE_ENDPOINT       — ex.: https://<account>.r2.cloudflarestorage.com
    #   STORAGE_REGION         — default 'auto' (R2)
    #
    # Override opcional (pra usar bucket diferente só pros backups):
    #   FINANCIAL_BACKUP_BUCKET — sobrescreve STORAGE_BUCKET_NAME
    #   FINANCIAL_BACKUP_PREFIX — default 'postgres-backups/'
    #
    # Use `enabled?` antes de chamar — se faltar envs, não derruba a app
    # (backup local continua funcionando).
    class R2Storage
      DEFAULT_PREFIX = 'postgres-backups/'.freeze

      class << self
        def enabled?
          %w[STORAGE_ACCESS_KEY_ID STORAGE_SECRET_ACCESS_KEY STORAGE_ENDPOINT]
            .all? { |k| ENV[k].present? } && bucket_name.present?
        end

        def bucket_name
          ENV['FINANCIAL_BACKUP_BUCKET'].presence || ENV['STORAGE_BUCKET_NAME'].presence
        end

        def call_or_skip(action, *args, **kwargs)
          return :skipped unless enabled?
          new.public_send(action, *args, **kwargs)
        end
      end

      attr_reader :bucket, :prefix

      def initialize
        require 'aws-sdk-s3'
        @bucket = self.class.bucket_name
        @prefix = ENV['FINANCIAL_BACKUP_PREFIX'].presence || DEFAULT_PREFIX
        @client = build_client
      end

      # Sobe um arquivo local pra R2. Retorna hash com {key, size, etag}.
      def upload(local_path, key: nil)
        key ||= "#{prefix}#{File.basename(local_path)}"
        File.open(local_path, 'rb') do |io|
          @client.put_object(
            bucket: bucket,
            key: key,
            body: io,
            content_type: 'application/gzip',
            metadata: {
              'created-by' => 'klivy-backup-job',
              'created-at' => Time.current.iso8601
            }
          )
        end
        {
          key: key,
          size: File.size(local_path),
          uploaded_at: Time.current
        }
      end

      # Lista objetos com o prefixo. Retorna array de hashes:
      # [{key, name, size_bytes, last_modified, age_days}]
      def list
        objects = []
        @client.list_objects_v2(bucket: bucket, prefix: prefix).each do |response|
          response.contents.each do |obj|
            next if obj.key == prefix # diretório-marker
            age = ((Time.current - obj.last_modified) / 1.day).floor
            objects << {
              key: obj.key,
              name: File.basename(obj.key),
              size_bytes: obj.size,
              last_modified: obj.last_modified.iso8601,
              age_days: age
            }
          end
        end
        objects.sort_by { |o| -Time.parse(o[:last_modified]).to_i }
      end

      # Apaga um objeto.
      def delete(key)
        @client.delete_object(bucket: bucket, key: key)
        true
      end

      # Apaga objetos do prefixo mais antigos que `retention_days`.
      # Retorna count.
      def prune(retention_days:)
        cutoff = retention_days.days.ago
        count = 0
        list.each do |obj|
          modified = Time.parse(obj[:last_modified])
          next if modified >= cutoff
          delete(obj[:key])
          count += 1
        end
        count
      end

      private

      # Mesmo client config do `config/storage.yml` § s3_compatible.
      # R2: region='auto', force_path_style=true.
      def build_client
        Aws::S3::Client.new(
          access_key_id: ENV['STORAGE_ACCESS_KEY_ID'],
          secret_access_key: ENV['STORAGE_SECRET_ACCESS_KEY'],
          endpoint: ENV['STORAGE_ENDPOINT'],
          region: ENV['STORAGE_REGION'].presence || 'auto',
          force_path_style: ActiveModel::Type::Boolean.new.cast(
            ENV['STORAGE_FORCE_PATH_STYLE'].presence || 'true'
          )
        )
      end
    end
  end
end
