module Financial
  # Extensão financeira de `User` (1-to-1).
  # Canon `mapa-financeiro.json` step 1.
  #
  # `User` core do Klivy gerencia identidade (login, role, availability) via
  # `/api/v1/accounts/:id/agents`. Aqui ficam apenas campos específicos do
  # financeiro: vínculo trabalhista, dados bancários para pagamento de
  # comissão, categoria canon, CRO/especialidades.
  #
  # Sem AgentProfile = user não aparece em selects de DR/SDR/Comercial nos
  # fluxos financeiros (validação no service de Budget/Commission).
  class AgentProfile < ApplicationRecord
    self.table_name = 'financial_agent_profiles'

    AGENT_CATEGORIES = %w[profissional operacional comercial administrador].freeze
    BOND_TYPES = %w[PJ CLT Socio PF].freeze
    STATUSES = %w[active inactive].freeze

    belongs_to :account, class_name: '::Account'
    belongs_to :user,    class_name: '::User'

    # CPF é dado sensível LGPD. `deterministic: true` permite busca/uniqueness
    # query (mesmo plaintext → mesmo ciphertext). Migration 20260523050001
    # converteu coluna pra text.
    encrypts :cpf, deterministic: true

    # Normaliza CPF (só dígitos) antes de validar/salvar. Evita duplicatas
    # por formatação ("123.456.789-00" vs "12345678900").
    before_validation :normalize_cpf

    validates :user_id, uniqueness: {
      scope: :account_id,
      conditions: -> { alive },
      message: 'já tem perfil financeiro cadastrado (1-to-1)'
    }
    validates :agent_category, presence: true, inclusion: { in: AGENT_CATEGORIES }
    validates :bond_type, presence: true, inclusion: { in: BOND_TYPES }
    validates :entry_date, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }

    # CRO obrigatório SE profissional (verificação Ruby — espelha check
    # constraint do banco)
    validates :cro, presence: { if: :profissional? }

    # Administrador NUNCA é comissionável (canon §1)
    validate :admin_not_commissionable

    scope :active,         -> { where(status: 'active') }
    scope :inactive,       -> { where(status: 'inactive') }
    scope :commissionable, -> { where(commissionable: true) }
    scope :profissionais,  -> { where(agent_category: 'profissional') }
    scope :operacionais,   -> { where(agent_category: 'operacional') }
    scope :comerciais,     -> { where(agent_category: 'comercial') }
    scope :administradores, -> { where(agent_category: 'administrador') }

    def profissional?
      agent_category == 'profissional'
    end

    def administrador?
      agent_category == 'administrador'
    end

    # Display name: usa nome do User base (que é gerenciado em /settings/agents/list).
    def display_name
      user&.name || "User ##{user_id}"
    end

    # Resolve a regra de comissão vigente para este profissional + role (DR/SDR/Comercial)
    # numa data. Usado pelo service GenerateCommission.
    def commission_rule_for(role:, on_date: Date.current)
      Financial::CommissionRule
        .for_account(account_id)
        .alive
        .where(professional_id: user_id, role: role, status: 'active')
        .where('valid_from <= ?', on_date)
        .where('valid_to IS NULL OR valid_to >= ?', on_date)
        .order(valid_from: :desc)
        .first
    end

    private

    def admin_not_commissionable
      return unless administrador? && commissionable

      errors.add(:commissionable, 'administrador nunca é comissionável')
    end

    def normalize_cpf
      return if cpf.blank?

      digits = cpf.to_s.gsub(/\D/, '')
      self.cpf = digits.presence
    end
  end
end
