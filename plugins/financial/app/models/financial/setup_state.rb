module Financial
  # Estado do wizard de configuração inicial. Canon F-04.
  # Bloqueia acesso ao módulo financeiro até completar passos obrigatórios.
  class SetupState < ::ApplicationRecord
    self.table_name = 'financial_setup_states'
    self.inheritance_column = :_type_disabled

    STATUSES = %w[pending in_progress completed skipped].freeze

    belongs_to :account, class_name: '::Account'
    belongs_to :completed_by, class_name: '::User', optional: true

    validates :status, presence: true, inclusion: { in: STATUSES }

    REQUIRED_STEPS = %i[step_categories_done step_bank_accounts_done].freeze
    OPTIONAL_STEPS = %i[step_commission_rules_done step_recurring_expenses_done step_revenue_goal_done].freeze

    def required_steps_done?
      REQUIRED_STEPS.all? { |step| public_send(step) }
    end

    def all_steps_done?
      (REQUIRED_STEPS + OPTIONAL_STEPS).all? { |step| public_send(step) }
    end

    def progress_percent
      total = REQUIRED_STEPS + OPTIONAL_STEPS
      done = total.count { |step| public_send(step) }
      ((done.to_f / total.size) * 100).round
    end

    def self.for_account(account_id)
      find_or_create_by(account_id: account_id) { |s| s.status = 'pending' }
    end
  end
end
