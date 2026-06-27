module Financial
  # Categoria do DRE (plano de contas) — hierarquia até 4 níveis.
  # Canon `mapa-financeiro.json` step 2: Grupo → Subgrupo → Categoria → Subcategoria
  #
  # `path` é materialized path "/<id1>/<id2>/<id3>/<id4>" — calculado
  # automaticamente via callback. Permite query por subárvore com `LIKE 'prefix%'`
  # sem RECURSIVE CTE.
  #
  # `level` é 1..4 — usado pelo DreReport pra agrupar por nível.
  #
  # `system_default` marca categorias seed canon que NÃO podem ser deletadas
  # nem renomeadas (ex: "Sem categoria", "Taxa de Maquininha e Cartão",
  # "Estornos"). Migração legacy de `is_default` migrou via ALTER.
  class DreCategory < ApplicationRecord
    self.table_name = 'financial_dre_categories'

    # Mantém compatibilidade com kinds legacy + adiciona canon kinds.
    # Canon estrito: receita | despesa | transfer_internal | breakage
    # Legacy: receita | despesa_fixa | custo_variavel | outra_despesa
    # Em Fase 2 do refactor, consolidar para 4 canon kinds via migration.
    KINDS = %w[receita despesa_fixa custo_variavel outra_despesa transfer_internal breakage].freeze
    DEFAULT_NAME = 'Sem categoria'.freeze
    MAX_LEVEL = 4

    belongs_to :account, class_name: '::Account'
    belongs_to :parent, class_name: 'Financial::DreCategory', optional: true
    has_many :children, class_name: 'Financial::DreCategory', foreign_key: :parent_id, dependent: :restrict_with_error

    has_many :installments, class_name: 'Financial::Installment', foreign_key: :financial_dre_category_id
    has_many :expenses,     class_name: 'Financial::Expense',     foreign_key: :financial_dre_category_id
    has_many :entries,      class_name: 'Financial::Entry',       foreign_key: :financial_dre_category_id
    has_many :service_pricings,
             class_name: 'Financial::ServicePricing',
             foreign_key: :financial_dre_category_id

    validates :name, presence: true, length: { maximum: 120 }
    validates :kind, presence: true, inclusion: { in: KINDS }
    validates :name, uniqueness: { scope: %i[account_id kind parent_id], conditions: -> { alive } }
    validates :level, presence: true, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: MAX_LEVEL, only_integer: true }
    validate  :system_default_immutability
    validate  :parent_kind_must_match
    validate  :hierarchy_depth_limit
    validate  :no_self_parent

    before_validation :compute_level_from_parent
    before_save       :compute_path
    # Bug fix 2026-05-23: `before_save :compute_path` não funciona pra
    # registros novos porque `self.id` é nil antes do INSERT. Adicionar
    # `after_create` que recomputa path com id já gerado e grava via
    # `update_column` (bypass callbacks pra evitar loop).
    after_create      :assign_path_after_insert
    after_save        :update_descendants_path, if: :saved_change_to_path?

    scope :receitas,         -> { where(kind: 'receita') }
    scope :despesas_fixas,   -> { where(kind: 'despesa_fixa') }
    scope :custos_variaveis, -> { where(kind: 'custo_variavel') }
    scope :outras_despesas,  -> { where(kind: 'outra_despesa') }
    scope :transferencias,   -> { where(kind: 'transfer_internal') }
    scope :income,           -> { where(kind: 'receita') }
    scope :expense,          -> { where.not(kind: %w[receita transfer_internal]) }
    scope :ordered,          -> { order(:position, :name) }
    scope :roots,            -> { where(parent_id: nil) }
    scope :at_level,         ->(lvl) { where(level: lvl) }

    # Retorna todos os descendentes (recursivo via path LIKE prefix%).
    def descendants
      return self.class.none unless path.present?

      self.class.where(account_id: account_id)
                .where('path LIKE ?', "#{path}/%")
                .where.not(id: id)
    end

    # Retorna ancestors em ordem (root → parent → ...).
    def ancestors
      return self.class.none unless path.present?

      ids = path.split('/').reject(&:empty?).map(&:to_i)
      ids.pop # remove self
      return self.class.none if ids.empty?

      self.class.where(account_id: account_id, id: ids).order(:level)
    end

    def income?
      kind == 'receita'
    end

    def expense?
      !income? && kind != 'transfer_internal'
    end

    def transfer?
      kind == 'transfer_internal'
    end

    def default?
      system_default == true
    end

    def has_entries?
      entries.exists? || installments.exists? || expenses.exists?
    end

    # Pricings ativas referenciando essa categoria. Quando algum
    # ServicePricing aponta pra cá, deletar a categoria deixaria o
    # serviço sem categoria DRE → próximas vendas caem em "Sem categoria",
    # poluindo o relatório. Bloqueia preventivamente.
    def has_pricings?
      respond_to?(:service_pricings) && service_pricings.exists?
    end

    # Conta filhos VIVOS (alive). O model já tem `dependent: :restrict_with_error`
    # em `children`, mas a checagem explícita permite mensagem clara antes do
    # ActiveRecord disparar exceção.
    def has_children?
      children.exists?
    end

    def root?
      parent_id.nil?
    end

    private

    # `level` = parent.level + 1; root = 1
    def compute_level_from_parent
      self.level = parent.present? ? parent.level + 1 : 1
    end

    # `path` = parent.path + '/' + self.id (root = '/self.id')
    # Para registros JÁ persistidos (update), computa direto.
    # Para registros novos, fica nil até after_create rodar — limitação do
    # ciclo de vida AR (id só existe pós-INSERT).
    def compute_path
      if parent.present?
        base = parent.path.presence || "/#{parent.id}"
        self.path = id.present? ? "#{base}/#{id}" : nil
      else
        self.path = id.present? ? "/#{id}" : nil
      end
    end

    # Bug fix 2026-05-23: roda APÓS o INSERT (id agora disponível). Grava
    # via update_column pra bypassar callbacks (evita loop infinito de
    # save → before_save → compute_path → save).
    def assign_path_after_insert
      new_path =
        if parent.present?
          base = parent.path.presence || "/#{parent.id}"
          "#{base}/#{id}"
        else
          "/#{id}"
        end
      update_column(:path, new_path) if path != new_path
    end

    # Quando uma categoria muda de parent_id, todos os descendentes precisam
    # ter o path recalculado.
    def update_descendants_path
      return unless path.present?

      descendants.find_each do |child|
        child.send(:compute_path)
        child.update_column(:path, child.path) if child.path_changed?
      end
    end

    def system_default_immutability
      return unless default?
      return unless persisted?

      errors.add(:name, 'categoria default não pode ser renomeada') if name_changed?
      errors.add(:kind, 'categoria default não pode ter kind alterado') if kind_changed?
      errors.add(:parent_id, 'categoria default não pode ser movida') if parent_id_changed?
    end

    def parent_kind_must_match
      return unless parent.present?
      return if parent.kind == kind

      errors.add(:kind, "deve coincidir com kind do parent (#{parent.kind})")
    end

    def hierarchy_depth_limit
      return unless level && level > MAX_LEVEL

      errors.add(:level, "máximo #{MAX_LEVEL} níveis (canon Grupo→Subgrupo→Categoria→Subcategoria)")
    end

    def no_self_parent
      return unless persisted? && parent_id == id

      errors.add(:parent_id, 'não pode ser ela mesma')
    end
  end
end
