# System message (system prompt) POR CONTA.
#
# Até aqui o system prompt da Bea era ÚNICO e global (InstallationConfig
# 'CAPTAIN_BEA_SYSTEM_PROMPT', editável em /super_admin/bea), aplicado a todas
# as contas. Esta coluna dá a cada conta o SEU próprio system message:
#
#   - vazio  → a Bea usa o default global do super admin (a Bea nunca roda
#              sem prompt; é também a fonte do botão "Restaurar padrão");
#   - preenchido → a conta segue 100% o texto dela, CONGELADO — melhorias
#              futuras no default global NÃO a alcançam (decisão do dono).
#
# Resolvido em AiAgent::ConfigResolver#system_prompt e injetado pelo
# PromptBuilder com precedência conta > default global. Isolado por conta:
# editar o de uma conta nunca afeta outra (nem o cache de prompt do LLM, que é
# por-conteúdo).
class AddSystemPromptToAiAgentAccountSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agent_account_settings, :system_prompt, :text
  end
end
