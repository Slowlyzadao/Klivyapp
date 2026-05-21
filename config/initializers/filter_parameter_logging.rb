# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
Rails.application.config.filter_parameters += [
  :password, :secret, :_key, :auth, :crypt, :salt, :certificate, :otp, :access, :private, :protected, :ssn,
  :otp_secret, :otp_code, :backup_code, :mfa_token, :otp_backup_codes,
  :number, :ccv, :cvv, :expiryMonth, :expiryYear, :holderName
]

# Regex to filter all occurrences of 'token' in keys except for 'website_token'
filter_regex = /\A(?!.*\bwebsite_token\b).*token/i

# Apply the regex for filtering
Rails.application.config.filter_parameters += [filter_regex]

# Telemed (audit Fase 3 — LGPD): mascara conteúdo clínico em logs de
# request — transcrição completa, SOAP estruturado, motivo de rejeição,
# anotações de revisor são dados sensíveis de saúde (LGPD Art. 5º II) e
# nunca devem aparecer em production.log nem em error trackers
# (Sentry et al — também respeitam filter_parameters).
Rails.application.config.filter_parameters += %i[
  transcript_text
  transcript_segments
  soap_structure
  raw_markdown
  reviewer_notes
  attention_points
]
