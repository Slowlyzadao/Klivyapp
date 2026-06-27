module Financial
  # Meio de pagamento configurado pela clínica.
  # Canon `mapa-financeiro.json` step 3.
  #
  # Múltiplos métodos podem derivar do mesmo `kind` canon
  # (ex: "Cielo Crédito" e "GetNet Crédito" são dois `kind=credito` diferentes).
  # A taxa percentual + por parcela vive em `PaymentMethodFee` com vigência.
  #
  # Imutabilidade: `kind` é congelado após criação — mudar de "dinheiro" pra
  # "credito" alteraria histórico de lançamentos vinculados. Para "trocar",
  # inativar e criar novo.
  class PaymentMethod < ApplicationRecord
    self.table_name = 'financial_payment_methods'

    KINDS = %w[
      dinheiro pix debito credito boleto
      transferencia convenio parcelamento_proprio
    ].freeze
    STATUSES = %w[active inactive].freeze

    # Política de baixa (settlement). Decisão 2026-05-27.
    #   manual      → operador clica "Receber".
    #   on_confirm  → baixa na confirmação do wizard (à vista — dinheiro/PIX/débito).
    #   on_due_date → baixa automática na data (cartão — adquirente garante).
    SETTLEMENT_MODES = %w[manual on_confirm on_due_date].freeze

    # Baixa automática na data SÓ é legítima quando a adquirente garante o
    # repasse (cartão). Boleto/convênio/parcelamento próprio dependem do
    # pagador honrar — auto-baixa ali mentiria sucesso. Guardrail duro.
    AUTO_SETTLE_ALLOWED_KINDS = %w[credito debito].freeze

    # `kind` congelado após criação — alterar quebraria histórico vinculado
    frozen_attributes :kind

    belongs_to :account, class_name: '::Account'
    belongs_to :default_bank_account,
               class_name: 'Financial::BankAccount',
               foreign_key: :default_bank_account_id,
               optional: true

    has_many :payment_method_fees,
             class_name: 'Financial::PaymentMethodFee',
             foreign_key: :payment_method_id,
             dependent: :restrict_with_error

    validates :kind, presence: true, inclusion: { in: KINDS }
    validates :name, presence: true, length: { maximum: 120 }
    validates :name, uniqueness: { scope: :account_id, case_sensitive: false, conditions: -> { alive } }
    validates :max_installments, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 24, only_integer: true }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :provider_alias, length: { maximum: 120 }, allow_blank: true
    validates :settlement_mode, presence: true, inclusion: { in: SETTLEMENT_MODES }
    validate  :credito_must_support_installments
    validate  :auto_settle_only_for_card_kinds

    # Display name do provedor — usa alias se setado, senão raw provider.
    # UI agrupa por display_provider; backend cru por provider pra não
    # quebrar idempotência de queries existentes.
    def display_provider
      provider_alias.presence || provider
    end

    scope :active,   -> { where(status: 'active') }
    scope :inactive, -> { where(status: 'inactive') }
    scope :by_kind,  ->(kind) { where(kind: kind) }
    scope :ordered,  -> { order(:kind, :name) }

    # Busca a taxa vigente para esta forma + quantidade de parcelas + data.
    # Usado por `Financial::Payments::ReceivePayment` no momento de congelar
    # snapshot no Installment. Retorna nil se não houver fee ativa.
    def fee_for(installments_count:, on_date: Date.current)
      payment_method_fees
        .alive
        .where(status: 'active')
        .where(installments_count: installments_count)
        .where('valid_from <= ?', on_date)
        .where('valid_to IS NULL OR valid_to >= ?', on_date)
        .order(valid_from: :desc)
        .first
    end

    # Parcela vinculada a este método deve ser recebida na confirmação do
    # wizard (à vista: dinheiro/PIX/débito que o operador já viu entrar).
    def settle_on_confirm?
      settlement_mode == 'on_confirm'
    end

    # Parcela vinculada deve ter baixa automática na data (cartão garantido
    # pela adquirente). Consumido pelo AutoSettleCardInstallmentsJob.
    def auto_settle_on_due_date?
      settlement_mode == 'on_due_date'
    end

    private

    # Guardrail: `on_due_date` só p/ cartão (kinds garantidos pela adquirente).
    # Bloqueia configurar boleto/convênio/parcelamento próprio com baixa
    # automática — neles a clínica assume o risco e a baixa mentiria sucesso.
    def auto_settle_only_for_card_kinds
      return unless settlement_mode == 'on_due_date'
      return if AUTO_SETTLE_ALLOWED_KINDS.include?(kind)

      errors.add(:settlement_mode,
                 'baixa automática na data só é permitida para cartão (crédito/débito) — ' \
                 'boleto, convênio e parcelamento próprio dependem do pagador e devem ' \
                 'ficar como manual')
    end

    # Cartão de crédito sempre suporta parcelas. Sem essa validação, regra
    # de UI pode esquecer e operador cadastraria "Cielo Crédito" sem
    # `max_installments`.
    def credito_must_support_installments
      return unless kind == 'credito'
      return if supports_installments && max_installments >= 1

      errors.add(:supports_installments, 'crédito deve suportar parcelas')
    end
  end
end
