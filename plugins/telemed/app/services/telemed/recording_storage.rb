# Sprint L — Cliente S3-compatible (R2) pro bucket dedicado de teleconsulta.
#
# Bucket separado do ActiveStorage do Klivy (exames) porque:
#   - retenção diferente (CFM exige 20 anos pra prontuário; exames seguem
#     política da clínica)
#   - escopo de permissões distinto (gravações são sensíveis em outro nível)
#   - acesso via signed URL temporário no controller (5 min) — diferente do
#     padrão `rails_blob_url` dos exames
#
# Centralizamos pra que jobs/controllers não precisem reinstanciar o client
# AWS toda vez. Lazy init evita erros em ambientes sem ENV vars (tests).
require 'aws-sdk-s3'

module Telemed
  class RecordingStorage
    DEFAULT_SIGNED_URL_TTL = 5.minutes.to_i

    class << self
      # Baixa o objeto pro path local. Caller é responsável pelo cleanup
      # (Tempfile). Usado pelo TranscribeRecordingJob.
      def download(key, to_path)
        new.download(key, to_path)
      end

      # Gera URL pre-signada GET (default 5min). Usado pelo controller
      # `teleconsultas/:id/recording_url`.
      def signed_url(key, ttl: DEFAULT_SIGNED_URL_TTL)
        new.signed_url(key, ttl: ttl)
      end

      # Deleta objeto do bucket. Usado em `archive!` e `cleanup_temp_files!`.
      # Idempotente: NoSuchKey é silenciosamente ignorado.
      def delete(key)
        new.delete(key)
      end
    end

    def initialize
      @bucket   = env!('TELEMED_STORAGE_BUCKET')
      @endpoint = env!('TELEMED_STORAGE_ENDPOINT')
      @region   = ENV.fetch('TELEMED_STORAGE_REGION', 'auto')
      @client = Aws::S3::Client.new(
        endpoint:           @endpoint,
        region:             @region,
        access_key_id:      env!('TELEMED_STORAGE_ACCESS_KEY_ID'),
        secret_access_key:  env!('TELEMED_STORAGE_SECRET_ACCESS_KEY'),
        force_path_style:   true
      )
    end

    def download(key, to_path)
      @client.get_object(bucket: @bucket, key: normalize(key), response_target: to_path)
      to_path
    end

    def signed_url(key, ttl: DEFAULT_SIGNED_URL_TTL)
      Aws::S3::Presigner.new(client: @client).presigned_url(
        :get_object,
        bucket: @bucket,
        key:    normalize(key),
        expires_in: ttl
      )
    end

    def delete(key)
      @client.delete_object(bucket: @bucket, key: normalize(key))
    rescue Aws::S3::Errors::NoSuchKey
      # Idempotente: chave já não existe → cleanup é no-op.
    end

    private

    # LiveKit pode retornar `location` como URL completa (`https://.../bucket/key`)
    # ou key relativa. Normalizamos pra key relativa.
    def normalize(key)
      return key unless key.to_s.start_with?('http')

      uri = URI(key)
      path = uri.path.sub(%r{\A/}, '')
      # Se path começa com bucket name, remove.
      path.sub(%r{\A#{Regexp.escape(@bucket)}/}, '')
    end

    def env!(name)
      ENV[name].presence || raise("ENV var #{name} obrigatória para Telemed storage")
    end
  end
end
