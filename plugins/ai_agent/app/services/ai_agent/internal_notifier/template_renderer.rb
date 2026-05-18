module AiAgent
  module InternalNotifier
    # Substitui variáveis %{nome} no body do template pelos valores fornecidos.
    # Variáveis ausentes em `vars` viram string vazia (não rebenta com KeyError).
    # Linhas que ficaram só com whitespace são preservadas (templates dependem
    # delas pra parágrafos), mas linhas que viraram só "%{var}" e ficaram
    # vazias podem ser removidas via `compact_blank_lines: true`.
    #
    # Spec: docs/01-product/ai-agent-configuration-plan.md (Apêndice F)
    module TemplateRenderer
      def self.render(body, vars, compact_blank_lines: true)
        normalized = vars.transform_keys(&:to_sym)
        rendered = body.gsub(/%\{(\w+)\}/) do |_match|
          key = Regexp.last_match(1).to_sym
          normalized[key].to_s
        end

        return rendered.strip unless compact_blank_lines

        # Colapsa 3+ quebras consecutivas em 2 (preserva parágrafos mas não acumula vazios).
        rendered.gsub(/\n{3,}/, "\n\n").strip
      end
    end
  end
end
