# Rewrite dos templates de notificação interna que ainda usam a sintaxe
# legada de placeholder do EventCatalog original:
#   `%<patient_name>s`  →  `%{patient_name}`
#
# Por quê:
# O `EventCatalog` original (sprint 7) escrevia o `default_body` usando
# format string sprintf (`%<var>s`). Já o `TemplateRenderer` (introduzido
# junto) usa regex `/%\{(\w+)\}/` que SÓ casa com kformat (`%{var}`).
# Resultado: templates seedados nas contas existentes não tinham as
# variáveis substituídas — o body saía cru no Chat Interno
# (`Tentei agendar para *%<patient_name>s* ...`).
#
# Fix triplo na release 1.7.0.7:
#   1. TemplateRenderer aceita as 2 sintaxes (defense-in-depth)
#   2. EventCatalog: rewrite do código fonte pra `%{var}` (formato canon)
#   3. Esta migration: rewrite dos registros já em produção
#
# Idempotente — só atualiza linhas que de fato contêm `%<x>s`. Roda em
# todas as contas.
class RewriteInternalNotificationTemplatePlaceholders < ActiveRecord::Migration[7.1]
  def up
    return unless table_exists?(:ai_agent_internal_notification_templates)

    AiAgent::InternalNotificationTemplate.find_each do |tpl|
      next unless tpl.body&.match?(/%<\w+>s/)

      tpl.update_columns(body: tpl.body.gsub(/%<(\w+)>s/, '%{\1}'))
    end
  end

  def down
    # Não desfazer — kformat é o formato canônico daqui pra frente.
  end
end
