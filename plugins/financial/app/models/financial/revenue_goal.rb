module Financial
  # Meta de receita — canon Setup #8 (2026-05-23).
  #
  # Cada meta tem 3 tiers (Mínima / Principal / Desafio) e pode ser de:
  #   - `total`         : receita global da clínica no período
  #   - `por_categoria` : receita restrita a uma categoria DRE
  #   - `por_agente`    : receita atribuída a um profissional
  #
  # Métrica:
  #   - `currency`: valor em centavos (R$). Usa `*_cents`.
  #   - `count`   : quantidade absoluta. Usa `*_qty` (ex: 200 implantes).
  #
  # ATUAL é calculado on-the-fly em `actual_value` somando entries vivas
  # no período (canon §4.5).
  class RevenueGoal < ApplicationRecord
    self.table_name = 'financial_revenue_goals'

    KINDS    = %w[total por_categoria por_agente].freeze
    METRICS  = %w[currency count].freeze

    belongs_to :account,                  class_name: '::Account'
    belongs_to :financial_dre_category,   class_name: 'Financial::DreCategory', optional: true
    belongs_to :professional,             class_name: '::User',                  optional: true

    validates :name, presence: true, length: { maximum: 120 }
    validates :kind, presence: true, inclusion: { in: KINDS }
    validates :metric, presence: true, inclusion: { in: METRICS }
    validates :start_date, :end_date, presence: true
    validate  :date_range_consistency
    validate  :kind_specific_fields
    validate  :targets_present_for_metric

    scope :active_goals, -> { where(active: true) }
    scope :inactive,     -> { where(active: false) }
    scope :covering,     ->(date) { where('start_date <= ? AND end_date >= ?', date, date) }
    scope :totals,       -> { where(kind: 'total') }
    scope :by_category,  -> { where(kind: 'por_categoria') }
    scope :by_agent,     -> { where(kind: 'por_agente') }

    # Cálculo do ATUAL (canon §4.5):
    # - kind=total          → SUM(Entry.amount_cents) com direction=in,
    #                          affects_dre=true, cash_date no período
    # - kind=por_categoria  → mesma soma filtrada por financial_dre_category_id
    # - kind=por_agente     → mesma soma filtrada por professional_id
    # - metric=count        → COUNT(entries) em vez de SUM
    def actual_value
      scope = ::Financial::Entry
                .for_account(account_id)
                .where(direction: 'in', affects_dre: true)
                .where(cash_date: start_date..end_date)

      scope = scope.where(financial_dre_category_id: financial_dre_category_id) if kind == 'por_categoria'
      scope = scope.where(professional_id: professional_id)                     if kind == 'por_agente'

      metric == 'count' ? scope.count : scope.sum(:amount_cents)
    end

    # % de progresso em relação ao tier PRINCIPAL (target_cents | target_qty).
    # Retorna nil se target_principal não definido.
    def progress_percent(actual_override: nil)
      principal = metric == 'count' ? target_qty : target_cents
      return nil if principal.blank? || principal == 0

      val = actual_override || actual_value
      ((val.to_f / principal) * 100).round(2)
    end

    # Encerra (soft) a meta — não excluí pra preservar histórico/auditoria.
    def encerrar!(user: nil)
      update!(active: false)
    end

    private

    def date_range_consistency
      return if start_date.blank? || end_date.blank?
      errors.add(:end_date, 'deve ser >= start_date') if end_date < start_date
    end

    def kind_specific_fields
      case kind
      when 'por_categoria'
        errors.add(:financial_dre_category_id, 'obrigatório para meta Por Categoria') if financial_dre_category_id.blank?
      when 'por_agente'
        errors.add(:professional_id, 'obrigatório para meta Por Agente') if professional_id.blank?
      end
    end

    def targets_present_for_metric
      if metric == 'currency'
        errors.add(:target_cents, 'meta principal é obrigatória') if target_cents.blank?
      else
        errors.add(:target_qty, 'meta principal é obrigatória') if target_qty.blank?
      end
    end
  end
end
