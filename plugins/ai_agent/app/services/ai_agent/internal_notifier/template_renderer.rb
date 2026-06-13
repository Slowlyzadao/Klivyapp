# Substitui variáveis %{nome} no body do template pelos valores fornecidos.
# Variáveis ausentes em `vars` viram string vazia (não rebenta com KeyError).
# Linhas que ficaram só com whitespace são preservadas (templates dependem
# delas pra parágrafos), mas linhas que viraram só "%{var}" e ficaram
# vazias podem ser removidas via `compact_blank_lines: true`.
#
# SEC-26 (auditoria 2026-05-18): cada var é truncada e sanitizada antes
# da substituição. Sem isso, `terms` user-controlled de OffensiveTone /
# RefundRequest poderia injetar:
#   - mensagens enormes (DoS do canal interno),
#   - quebras de linha forjando estrutura visual do template,
#   - sequências `%{outra_var}` que NÃO eram substituídas (gsub não-
#     recursivo) mas geravam confusão em logs.
# Truncate hard em 500 chars por var + normaliza newlines (max 2 seguidas
# por var). Frontend já faz auto-escape via Vue `{{ }}` — XSS via tags
# HTML não é vetor aqui.
#
# Spec: docs/01-product/ai-agent-configuration-plan.md (Apêndice F)
module AiAgent::InternalNotifier::TemplateRenderer
  MAX_VAR_LENGTH = 500

  def self.render(body, vars, compact_blank_lines: true)
    normalized = vars.transform_keys(&:to_sym).transform_values { |v| sanitize_var(v) }

    # Aceita 2 sintaxes (defense-in-depth + backward-compat):
    #   %{var}    → kformat Ruby (formato CANÔNICO — usado pela UI/preview)
    #   %<var>s   → sprintf Ruby (formato legado dos EventCatalog originais)
    # Templates seedados antes da `1.7.0.7` ainda têm `%<var>s` no body.
    # Migration `20260520000001_rewrite_internal_notification_template_placeholders`
    # converte os existentes, mas mantemos suporte aqui pra resiliência.
    rendered = body
               .gsub(/%\{(\w+)\}/) { normalized[Regexp.last_match(1).to_sym].to_s }
               .gsub(/%<(\w+)>s/)  { normalized[Regexp.last_match(1).to_sym].to_s }

    return rendered.strip unless compact_blank_lines

    # Colapsa 3+ quebras consecutivas em 2 (preserva parágrafos mas não acumula vazios).
    rendered.gsub(/\n{3,}/, "\n\n").strip
  end

  # SEC-26: hard truncate + normaliza newlines. Idempotente — passar
  # vars já sanitizadas é no-op. Aceita qualquer tipo (Integer, nil etc.).
  def self.sanitize_var(value)
    str = value.to_s
    str = str[0, MAX_VAR_LENGTH] if str.length > MAX_VAR_LENGTH
    # Normaliza CR/LF e colapsa runs de >=2 newlines em 1 (paciente não
    # consegue forjar parágrafos no template via input).
    str.gsub(/\r\n?/, "\n").gsub(/\n{2,}/, "\n")
  end
end
