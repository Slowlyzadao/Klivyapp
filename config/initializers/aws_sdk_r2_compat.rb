# Cloudflare R2 ainda não implementa o protocolo de checksum CRC32 introduzido
# pela aws-sdk-s3 >= 1.178. Sem isso, todo PUT volta 501 NotImplemented.
# Removível quando R2 anunciar suporte completo a flexible checksums.
if ENV['ACTIVE_STORAGE_SERVICE'] == 's3_compatible'
  Aws.config.update(
    request_checksum_calculation: 'when_required',
    response_checksum_validation: 'when_required'
  )
end
