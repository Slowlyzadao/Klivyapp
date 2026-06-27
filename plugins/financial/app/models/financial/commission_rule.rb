module Financial
  # Regra de comissão por profissional. Canon §4.3.
  # - Vigência por intervalo (valid_from, valid_until).
  # - Mudança de regra NÃO recalcula histórico (CommissionEntry guarda snapshot).
  # - Tipos: percentual_geral | percentual_por_procedimento | percentual_por_especialidade | valor_fixo
  class CommissionRule < ApplicationRecord
    self.table_name = 'financial_commission_rules'

    KINDS = %w[percentual_geral percentual_por_procedimento percentual_por_especialidade valor_fixo].freeze
    BASES = %w[bruto recebido recebido_menos_mdr recebido_menos_lab].freeze

    # Canon Setup #5 (2026-05-23). Ver migration `20260523070001`.
    ROLES = %w[DR SDR Comercial].freeze
    TRIGGER_EVENTS = %w[
      paciente_comparece
      orcamento_aceito
      profissional_realizou
      pagamento_confirmado
    ].freeze
    SCOPES = %w[todos por_procedimento por_especialidade].freeze
    PAY_WHEN_OPTIONS = %w[fechamento_mes imediato no_recebimento].freeze

    belongs_to :account,            class_name: '::Account'
    belongs_to :professional,       class_name: '::User'
    belongs_to :financial_dre_category, class_name: 'Financial::DreCategory', optional: true
    has_many :commission_entries,   class_name: 'Financial::CommissionEntry', foreign_key: :financial_commission_rule_id

    money_attribute :fixed_amount_cents, as: :fixed_amount

    validates :kind, presence: true, inclusion: { in: KINDS }
    validates :base, presence: true, inclusion: { in: BASES }
    validates :valid_from, presence: true
    validates :role, inclusion: { in: ROLES }, allow_nil: true
    validates :trigger_event, presence: true, inclusion: { in: TRIGGER_EVENTS }
    validates :scope, presence: true, inclusion: { in: SCOPES }
    validates :pay_when, presence: true, inclusion: { in: PAY_WHEN_OPTIONS }
    validate  :percent_or_fixed_present
    validate  :date_range_consistency

    scope :active_rules, -> { where(active: true) }
    scope :for_professional, ->(prof_id) { where(professional_id: prof_id) }
    scope :for_role, ->(role) { where(role: role) }
    scope :for_trigger, ->(event) { where(trigger_event: event) }
    scope :effective_on, ->(date) {
      where('valid_from <= ?', date)
        .where('valid_until IS NULL OR valid_until >= ?', date)
    }

    # Display name: usa `name` se setado, senão monta dinâmico
    # "<professional.name> · <role>" (compat com regras antigas sem name).
    def display_name
      return name if name.present?
      "#{professional&.name} · #{role || 'Geral'}"
    end

    # Regra vigente para um profissional na data. Mais específica > mais recente.
    # Ordem: procedimento > categoria > especialidade > geral.
    SPECIFICITY = {
      'percentual_por_procedimento'   => 100,
      'percentual_por_especialidade'  =>  50,
      'percentual_geral'              =>  10,
      'valor_fixo'                    =>   5
    }.freeze

    def self.most_specific_for(professional_id:, date:, procedure_name: nil, specialty: nil, category_id: nil)
      candidates = active_rules
                   .for_professional(professional_id)
                   .effective_on(date)

      best = nil
      best_score = -1

      candidates.find_each do |rule|
        score = rule.specificity_score(procedure_name: procedure_name, specialty: specialty, category_id: category_id)
        next if score < 0

        if score > best_score
          best = rule
          best_score = score
        end
      end

      best
    end

    def specificity_score(procedure_name:, specialty:, category_id:)
      base_score = SPECIFICITY[kind] || 0

      case kind
      when 'percentual_por_procedimento'
        return -1 if self.procedure_name.blank? || procedure_name.blank?
        return -1 unless self.procedure_name.casecmp(procedure_name.to_s).zero?
      when 'percentual_por_especialidade'
        return -1 if self.specialty.blank? || specialty.blank?
        return -1 unless self.specialty.casecmp(specialty.to_s).zero?
      end

      # Categoria opcional aumenta a especificidade.
      base_score += 5 if financial_dre_category_id.present? && category_id.present? && financial_dre_category_id == category_id

      base_score
    end

    def percent
      return nil if percent_basis_points.blank?

      BigDecimal(percent_basis_points) / 100  # 4000 → 40.00
    end

    def percent=(value)
      if value.nil?
        self.percent_basis_points = nil
      else
        self.percent_basis_points = (BigDecimal(value.to_s) * 100).round.to_i
      end
    end

    private

    def percent_or_fixed_present
      if kind == 'valor_fixo'
        errors.add(:fixed_amount_cents, 'obrigatório para valor_fixo') if fixed_amount_cents.blank?
      else
        errors.add(:percent_basis_points, 'obrigatório para regra percentual') if percent_basis_points.blank?
      end
    end

    def date_range_consistency
      return if valid_until.blank? || valid_from.blank?

      errors.add(:valid_until, 'deve ser >= valid_from') if valid_until < valid_from
    end
  end
end
