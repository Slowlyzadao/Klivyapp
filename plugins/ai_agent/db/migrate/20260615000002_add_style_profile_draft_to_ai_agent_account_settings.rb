# Projeto "Tom de voz da Bea" — Fase 2 (geração).
#
# Rascunho do perfil de estilo, separado do ativo (`style_profile`, Fase 1).
# A geração automática (StyleProfiler/Distiller) escreve AQUI; o ativo só muda
# quando o usuário aprovar (Fase 3). Assim regerar NÃO derruba a voz ao vivo,
# e segue o padrão "sugestão pendente" das FAQs.
#
# Shape: { status: generating|ready|failed, error, summary, greeting, closing,
# emojis[], expressions[], examples:[{paciente,clinica}], sample_count,
# source_conversation_count, generated_at }.
class AddStyleProfileDraftToAiAgentAccountSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agent_account_settings, :style_profile_draft, :jsonb, default: {}, null: false
  end
end
