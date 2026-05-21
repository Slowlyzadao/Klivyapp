module Financial
  # Categoria do DRE (plano de contas).
  # Canon §4.1. Tipos: receita, despesa_fixa, custo_variavel, outra_despesa.
  class DreCategory < ApplicationRecord
    self.table_name = 'financial_dre_categories'

    KINDS = %w[receita despesa_fixa custo_variavel outra_despesa].freeze
    DEFAULT_NAME = 'Sem categoria'.freeze

    belongs_to :account, class_name: '::Account'
    belongs_to :parent, class_name: 'Financial::DreCategory', optional: true
    has_many :children, class_name: 'Financial::DreCategory', foreign_key: :parent_id, dependent: :restrict_with_error

    has_many :installments, class_name: 'Financial::Installment', foreign_key: :financial_dre_category_id
    has_many :expenses,     class_name: 'Financial::Expense',     foreign_key: :financial_dre_category_id
    has_many :entries,      class_name: 'Financial::Entry',       foreign_key: :financial_dre_category_id

    validates :name, presence: true, length: { maximum: 120 }
    validates :kind, presence: true, inclusion: { in: KINDS }
    validates :name, uniqueness: { scope: %i[account_id kind], conditions: -> { alive } }
    validate  :default_category_immutability

    scope :receitas,         -> { where(kind: 'receita') }
    scope :despesas_fixas,   -> { where(kind: 'despesa_fixa') }
    scope :custos_variaveis, -> { where(kind: 'custo_variavel') }
    scope :outras_despesas,  -> { where(kind: 'outra_despesa') }
    scope :income,           -> { where(kind: 'receita') }
    scope :expense,          -> { where.not(kind: 'receita') }
    scope :ordered,          -> { order(:position, :name) }

    def income?
      kind == 'receita'
    end

    def expense?
      !income?
    end

    def default?
      is_default == true
    end

    def has_entries?
      entries.exists? || installments.exists? || expenses.exists?
    end

    private

    # "Sem categoria" não pode ser excluída nem renomeada.
    def default_category_immutability
      return unless default?
      return unless persisted?

      if name_changed? && name_was == DEFAULT_NAME
        errors.add(:name, 'categoria default não pode ser renomeada')
      end
    end
  end
end
