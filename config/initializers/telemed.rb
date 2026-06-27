# AUDIT 2026-05-25 — boot guards do plugin telemed.
#
# `encrypts :transcript_text` (TelemedRecording), `:raw_markdown/:reviewer_notes/
# :summary` (ProposedEvolution) só ativa quando ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
# está no ENV. Em prod SEM essa chave, o app subia sem warning e salvava PII
# clínica em PLAINTEXT (transcrição completa, queixas, medicações). Backup de
# DB vazaria tudo — violação direta da LGPD Art. 46 e Resolução CFM 1.821/2007.
#
# Esse initializer raise no boot em produção quando faltar a chave. Em dev/test
# emite warning pra que devs vejam a flag mas o app continue subindo
# (developer experience > rigidez em ambiente local).
#
# IMPORTANTE: também checamos `support_unencrypted_data`. Se `true` em prod,
# rows antigas em plaintext continuam acessíveis — comportamento OK durante
# migração inicial, mas precisa ter um job rodado uma vez pra reencrypt e
# desligar o suporte. Esse guard só warn (não bloqueia boot) — pra dar room
# pra rollout sem downtime.

Rails.application.config.after_initialize do
  next unless Rails.env.production?

  if ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY'].blank?
    error_msg = <<~MSG
      [Telemed] ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ausente em produção.
      Sem essa chave, `encrypts :transcript_text` (TelemedRecording) e
      `encrypts :raw_markdown/:reviewer_notes/:summary` (ProposedEvolution)
      ficam INERTES — PII clínica salva em plaintext, violação LGPD/CFM.

      Para gerar uma chave:
        bin/rails db:encryption:init

      Setar nas envs do app (ENV ou Rails credentials):
        ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=...
        ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=...
        ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=...

      Bypass intencional (apenas pra ambientes sem dados reais):
        TELEMED_ALLOW_UNENCRYPTED=true
    MSG

    raise error_msg unless ENV['TELEMED_ALLOW_UNENCRYPTED'] == 'true'

    Rails.logger.warn("[Telemed] #{error_msg}")
  end

  if Rails.application.config.active_record.encryption.support_unencrypted_data
    Rails.logger.warn(
      '[Telemed] support_unencrypted_data=true em produção. ' \
      'Rows antigas seguem em plaintext. Rode o job de reencrypt e ' \
      'desligue support_unencrypted_data após verificar.'
    )
  end
end
