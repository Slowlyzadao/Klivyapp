# 2026-05-25 — Limpa rows órfãs do `installation_configs` após remoção da
# camada de pós-revisão Gemini do pipeline de transcrição telemed.
#
# Contexto: até o commit anterior, o pipeline de teleconsulta tinha 2 camadas
# de IA na transcrição — `gpt-4o-transcribe-diarize` (OpenAI) seguido de
# revisão cross-modal pelo `gemini-2.5-flash` (toggle via `TELEMED_GEMINI_REVIEW`).
# A revisão Gemini foi descontinuada (decisão de produto: não trouxe ganho
# perceptível de qualidade, só latência e custo). O código, yml de seed e UI
# do Super Admin foram removidos no mesmo commit.
#
# Esta migration apaga as rows que podem ter sido criadas em prod quando o
# admin habilitou as configs via Super Admin > AI (o `installation_config.yml`
# só fornece defaults; valores reais ficam no DB).
#
# Idempotente: `DELETE WHERE name IN (...)` é no-op se as rows não existem.
# Safe pra rodar 2× ou em ambientes onde nunca foram configuradas.
#
# Down: NÃO recria as rows. A `GEMINI_API_KEY` era um secret cujo valor real
# não está no código — recriar com value vazio criaria uma row inválida que
# o admin teria que repopular manualmente. Rollback intencional é no-op.
class RemoveGeminiReviewConfigs < ActiveRecord::Migration[7.1]
  REMOVED_CONFIGS = %w[GEMINI_API_KEY TELEMED_GEMINI_REVIEW].freeze

  def up
    deleted = InstallationConfig.where(name: REMOVED_CONFIGS).delete_all
    say_with_time("Removidas #{deleted} rows órfãs de installation_configs") { deleted }
  end

  def down
    say 'No-op: GEMINI_API_KEY é secret cujo valor original não está no código. ' \
        'Se precisar reativar, recadastre via Super Admin > AI.'
  end
end
