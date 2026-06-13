# Estende `financial_commission_rules` com campos do wireframe canon
# "Regras de Comissão" — Setup #5:
#
#   - `name`           Nome custom da regra (ex: "Rafael Streit · DR Padrão").
#                      Sem ele a UI gerava label dinâmico — agora operador
#                      escreve um identificador legível pra cada regra.
#   - `role`           Papel do profissional NA REGRA: DR (Dentist Recommender,
#                      o principal) / SDR (Sales Dev — origina venda) /
#                      Comercial (consultor de vendas). NÃO confundir com
#                      AgentProfile.agent_category (categoria geral do user).
#   - `trigger_event`  Quando a comissão é gerada:
#                        paciente_comparece    → AgendaEvent.status=presente
#                        orcamento_aceito      → Budget.status=aprovado
#                        profissional_realizou → TreatmentItem.sessions_done++
#                        pagamento_confirmado  → Installment.status=pago (default)
#                      A lógica de geração automática vem em Fase B (canon §4.3.6).
#   - `scope`          todos | por_procedimento | por_especialidade.
#                      Combina com `procedure_name`/`specialty` quando aplicável.
#   - `pay_when`       fechamento_mes | imediato | no_recebimento.
#                      Quando a comissão fica disponível pra pagar ao profissional.
#
# Campos antigos (`base`, `deduct_mdr`, `deduct_lab`, `kind`) permanecem como
# "advanced settings" no modal — não removemos pra preservar regras existentes.
class ExtendCommissionRulesForV2Ui < ActiveRecord::Migration[7.1]
  def change
    add_column :financial_commission_rules, :name,          :string, limit: 120
    add_column :financial_commission_rules, :role,          :string, limit: 20
    add_column :financial_commission_rules, :trigger_event, :string, limit: 30, default: 'pagamento_confirmado', null: false
    add_column :financial_commission_rules, :scope,         :string, limit: 20, default: 'todos', null: false
    add_column :financial_commission_rules, :pay_when,      :string, limit: 30, default: 'fechamento_mes', null: false

    add_index :financial_commission_rules, [:account_id, :role], name: 'idx_commission_rules_role'
    add_index :financial_commission_rules, [:account_id, :trigger_event], name: 'idx_commission_rules_trigger'

    add_check_constraint :financial_commission_rules,
                         "role IS NULL OR role IN ('DR', 'SDR', 'Comercial')",
                         name: 'chk_commission_rules_role'

    add_check_constraint :financial_commission_rules,
                         "trigger_event IN ('paciente_comparece', 'orcamento_aceito', 'profissional_realizou', 'pagamento_confirmado')",
                         name: 'chk_commission_rules_trigger'

    add_check_constraint :financial_commission_rules,
                         "scope IN ('todos', 'por_procedimento', 'por_especialidade')",
                         name: 'chk_commission_rules_scope'

    add_check_constraint :financial_commission_rules,
                         "pay_when IN ('fechamento_mes', 'imediato', 'no_recebimento')",
                         name: 'chk_commission_rules_pay_when'
  end
end
