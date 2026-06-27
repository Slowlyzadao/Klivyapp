# Fase 4 do motor de follow-up: fallback de template aprovado pra envios
# FORA da janela de 24h no WhatsApp oficial (Cloud API / 360dialog).
#
# Quando `conversation.can_reply?` é false (paciente não fala há +24h num
# canal com janela), texto livre é rejeitado pela Meta — só template HSM.
# `whatsapp_qr` (bridge) não tem janela, então isso nunca se aplica a ele.
#
#   cloud_template_name   → nome do template aprovado na Meta
#   cloud_template_lang   → código de idioma (ex: pt_BR)
#   cloud_template_params → variáveis ORDENADAS que preenchem {{1}}, {{2}}...
#                           (ex: ["nome", "data"]); [] = template sem variável.
#
# Sem template configurado e fora da janela → a execução é pulada com
# motivo `outside_messaging_window` (nunca falha em silêncio).
class AddCloudTemplateToAiAgentFollowUpRules < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agent_follow_up_rules, :cloud_template_name, :string
    add_column :ai_agent_follow_up_rules, :cloud_template_lang, :string, null: false, default: 'pt_BR'
    add_column :ai_agent_follow_up_rules, :cloud_template_params, :jsonb, null: false, default: []
  end
end
