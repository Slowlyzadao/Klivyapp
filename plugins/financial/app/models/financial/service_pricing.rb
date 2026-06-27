module Financial
  # Preço financeiro 1-to-1 com `AgendaService`.
  #
  # Separação de domínio (canon): nome/duração/cor/sala/profissionais vinculados
  # vivem em `AgendaService` (plugin agenda); preço/categoria DRE/comissão
  # padrão/TUSS vivem aqui.
  #
  # Reglas:
  # - 1-to-1 com AgendaService (unique constraint no banco)
  # - Sem ServicePricing = AgendaService não pode ser lançado financeiramente
  #   (validado no service de criação de Budget)
  # - Mudar preço NÃO afeta orçamentos passados — eles fazem snapshot em
  #   `BudgetItem.unit_amount_cents` no momento da aprovação (imutabilidade)
  class ServicePricing < ApplicationRecord
    self.table_name = 'financial_service_pricings'

    STATUSES = %w[active inactive].freeze

    belongs_to :account, class_name: '::Account'
    belongs_to :agenda_service, class_name: '::AgendaService'
    belongs_to :financial_dre_category,
               class_name: 'Financial::DreCategory',
               foreign_key: :financial_dre_category_id
    belongs_to :default_commission_rule,
               class_name: 'Financial::CommissionRule',
               foreign_key: :default_commission_rule_id,
               optional: true

    money_attribute :particular_price_cents, as: :particular_price
    money_attribute :convenio_price_cents,   as: :convenio_price

    validates :particular_price_cents, presence: true,
              numericality: { greater_than_or_equal_to: 0, only_integer: true }
    validates :convenio_price_cents,
              numericality: { greater_than_or_equal_to: 0, only_integer: true, allow_nil: true }
    validates :status, presence: true, inclusion: { in: STATUSES }

    validates :agenda_service_id, uniqueness: {
      scope: :account_id,
      conditions: -> { alive },
      message: 'já tem precificação cadastrada (1-to-1)'
    }
    validates :tuss_code, uniqueness: {
      scope: :account_id,
      conditions: -> { alive },
      allow_nil: true
    }
    validates :internal_code, uniqueness: {
      scope: :account_id,
      conditions: -> { alive },
      allow_nil: true
    }

    scope :active,   -> { where(status: 'active') }
    scope :inactive, -> { where(status: 'inactive') }
    scope :for_agenda_service, ->(agenda_service_id) { where(agenda_service_id: agenda_service_id) }

    # Resolve preço para uma forma de pagamento.
    # Usado no momento de criar BudgetItem — congela snapshot do valor aqui.
    def price_for(payment_method_kind:)
      if payment_method_kind == 'convenio'
        convenio_price_cents || particular_price_cents
      else
        particular_price_cents
      end
    end

    def accepts_convenio?
      convenio_price_cents.present?
    end

    # Desativa pricing (canon: inativar em vez de deletar).
    # AgendaService permanece intacto — apenas perde precificação financeira.
    def deactivate!(user: nil)
      update!(status: 'inactive', updated_by_id: user&.id)
    end
  end
end
