module Financial
  # Estado do wizard de configuração inicial — canon Setup #1..#8 (2026-05-23).
  #
  # 3 grupos de passos:
  #   REQUIRED      (bloqueia operação): Plano de Contas + Contas Bancárias + Formas de Pagamento
  #   RECOMMENDED   (não bloqueia, mas avisa): Profissionais + Procedimentos
  #   OPTIONAL      (puramente informativo): Regras Comissão + Despesas Fixas + Metas
  #
  # Cada passo é considerado "feito" via query real nas tabelas-alvo
  # (`refresh!` recalcula tudo a partir do banco). Flag booleana persistida
  # serve como cache pra evitar queries em cada request.
  class SetupState < ::ApplicationRecord
    self.table_name = 'financial_setup_states'
    self.inheritance_column = :_type_disabled

    STATUSES = %w[pending in_progress completed skipped].freeze

    belongs_to :account, class_name: '::Account'
    belongs_to :completed_by, class_name: '::User', optional: true

    validates :status, presence: true, inclusion: { in: STATUSES }

    REQUIRED_STEPS    = %i[step_categories_done step_bank_accounts_done step_payment_methods_done].freeze
    RECOMMENDED_STEPS = %i[step_agent_profiles_done step_services_done].freeze
    OPTIONAL_STEPS    = %i[step_commission_rules_done step_recurring_expenses_done step_revenue_goal_done].freeze
    ALL_STEPS         = (REQUIRED_STEPS + RECOMMENDED_STEPS + OPTIONAL_STEPS).freeze

    def required_steps_done?
      REQUIRED_STEPS.all? { |step| public_send(step) }
    end

    def all_steps_done?
      ALL_STEPS.all? { |step| public_send(step) }
    end

    def progress_percent
      done = ALL_STEPS.count { |step| public_send(step) }
      ((done.to_f / ALL_STEPS.size) * 100).round
    end

    def required_progress_percent
      done = REQUIRED_STEPS.count { |step| public_send(step) }
      ((done.to_f / REQUIRED_STEPS.size) * 100).round
    end

    # Recalcula TODOS os passos a partir das tabelas-alvo. Idempotente — pode
    # rodar a cada request sem efeito colateral (só DB writes quando muda).
    # Útil quando operador faz uma operação fora do wizard (ex: cria conta
    # bancária direto em Configurações) e queremos atualizar o estado.
    def refresh!
      updates = {
        step_categories_done:        ::Financial::DreCategory
                                       .for_account(account_id).alive
                                       .where(kind: 'receita').exists? &&
                                     ::Financial::DreCategory
                                       .for_account(account_id).alive
                                       .where(kind: %w[despesa outra_despesa]).exists?,
        step_bank_accounts_done:     ::Financial::BankAccount
                                       .for_account(account_id).alive
                                       .where(active: true).exists?,
        step_payment_methods_done:   ::Financial::PaymentMethod
                                       .for_account(account_id).alive
                                       .where(status: 'active').exists?,
        step_agent_profiles_done:    ::Financial::AgentProfile
                                       .for_account(account_id).alive
                                       .where(status: 'active').exists?,
        step_services_done:          ::Financial::ServicePricing
                                       .for_account(account_id).alive
                                       .where(status: 'active').exists?,
        step_commission_rules_done:  ::Financial::CommissionRule
                                       .for_account(account_id).alive
                                       .where(active: true).exists?,
        step_recurring_expenses_done: ::Financial::RecurringExpense
                                       .for_account(account_id).alive
                                       .where(active: true).exists?,
        step_revenue_goal_done:      ::Financial::RevenueGoal
                                       .for_account(account_id)
                                       .where(active: true).exists?
      }

      # Status calculado:
      # - completed: TODOS os obrigatórios + ao menos os recomendados feitos
      # - in_progress: pelo menos 1 passo feito
      # - pending: nenhum
      done_count = updates.values.count(true)
      new_status = if updates.values_at(*REQUIRED_STEPS).all? && updates.values_at(*RECOMMENDED_STEPS).all?
                     'completed'
                   elsif done_count.zero?
                     'pending'
                   else
                     'in_progress'
                   end

      attrs = updates.merge(status: new_status)
      attrs[:completed_at] = Time.current if new_status == 'completed' && completed_at.blank?

      changed = attrs.any? { |k, v| read_attribute(k) != v }
      update!(attrs) if changed
      self
    end

    def self.for_account(account_id)
      find_or_create_by(account_id: account_id) { |s| s.status = 'pending' }
    end
  end
end
