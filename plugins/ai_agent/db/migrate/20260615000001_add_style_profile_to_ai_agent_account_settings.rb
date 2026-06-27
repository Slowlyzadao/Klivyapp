# Projeto "Tom de voz da Bea" — Fase 1 (backbone).
#
# Perfil de estilo de comunicação POR CONTA: emoji real, saudação, bordões,
# ritmo e exemplos verbatim destilados das conversas reais da clínica. É
# camada de SUPERFÍCIE (muda só COMO a Bea fala), aplicada no system prompt
# do atendimento reativo (PromptBuilder) e dos follow-ups (MessageGenerator).
#
# JSONB pra acompanhar o ciclo "rascunho → aprovado" sem migration nova a
# cada campo. Só é aplicado quando `style_profile['enabled'] == true` — um
# rascunho gerado e não aprovado NUNCA vaza pro prompt.
class AddStyleProfileToAiAgentAccountSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agent_account_settings, :style_profile, :jsonb, default: {}, null: false
  end
end
