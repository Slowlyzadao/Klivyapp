module Financial
  # Base de todos os modelos `Financial::*`.
  #
  # Carrega concerns nucleares (soft delete, audit log, stamping, money attrs)
  # e impõe **multi-tenant defense in depth** + **soft-delete enforcement**
  # acima do que `default_scope` consegue garantir sozinho.
  #
  # Por que `find`/`find_by` override
  # --------------------------------
  # `default_scope { where(deleted_at: nil) }` do `SoftDeletable` aplica-se em
  # `.where`/`.all` mas NÃO em `find_by(id:)` direto — Rails passa por outro
  # caminho. Resultado: `Budget.find_by(id: 123)` retornava registro soft-deletado.
  # Sobrescrever aqui força `alive` em qualquer lookup por ID, fechando o gap.
  # Auditoria 2026-05: `CRIT-DB-03`.
  #
  # Por que `validates :account_id, presence: true`
  # ----------------------------------------------
  # `belongs_to :account` no Rails 5+ já valida por padrão, MAS qualquer modelo
  # que use `belongs_to :account, optional: true` (ou que use `update_columns`
  # bypass) quebra a garantia. Validação explícita na base fecha o gap.
  # Auditoria 2026-05: `MT-02`.
  class ApplicationRecord < ::ApplicationRecord
    self.abstract_class = true

    include Financial::Concerns::SoftDeletable
    include Financial::Concerns::Auditable
    include Financial::Concerns::Stamped
    include Financial::Concerns::MoneyAttribute

    # Convenção: tudo no namespace `Financial::*` mora em tabelas `financial_*`.
    self.table_name_prefix = 'financial_'

    # Multi-tenant: scope explícito (preferido em controllers/services em vez
    # de `default_scope` por tenant, que esconde regras).
    scope :for_account, lambda { |account_id|
      raise ArgumentError, 'account_id é obrigatório em for_account' if account_id.blank?

      where(account_id: account_id)
    }

    # Validação base: account_id presente em qualquer modelo que tenha a coluna.
    # Não usa `belongs_to :account` aqui (model é abstract); cada subclasse
    # ainda declara `belongs_to :account` pra ter a associação. Esta validação
    # é defense in depth.
    validate :account_id_presence_when_column_exists

    class << self
      # `find` força scope `alive` quando a tabela tem `deleted_at`.
      # Comportamento idêntico ao Rails para tabelas sem `deleted_at`.
      def find(*ids)
        return super if ids.flatten.compact.empty?

        if column_names.include?('deleted_at')
          alive.find(*ids)
        else
          super
        end
      end

      def find_by(*args)
        if column_names.include?('deleted_at')
          alive.find_by(*args)
        else
          super
        end
      end

      def find_by!(*args)
        if column_names.include?('deleted_at')
          alive.find_by!(*args)
        else
          super
        end
      end
    end

    private

    def account_id_presence_when_column_exists
      return unless self.class.column_names.include?('account_id')
      return if account_id.present?

      errors.add(:account_id, 'é obrigatório (multi-tenant)')
    end

    # Helper compartilhado para validar que uma data não cai em período
    # contábil fechado. Modelos que tenham `competence_date` ou `cash_date`
    # podem usar via `validate :period_not_closed`.
    #
    # Levanta `Financial::Errors::PeriodClosed` (mapped pelo BaseController
    # como 423 Locked). Apenas em create/update — soft_delete continua OK
    # pra LGPD compliance mesmo em período fechado.
    def period_not_closed
      return unless persisted? || new_record?  # qualquer mutation
      return unless account_id.present?

      dates_to_check = []
      dates_to_check << competence_date if respond_to?(:competence_date) && competence_date.present?
      dates_to_check << cash_date       if respond_to?(:cash_date) && cash_date.present?
      return if dates_to_check.empty?

      dates_to_check.each do |date|
        next unless ::Financial::PeriodClosure.closed_for?(account_id, date)

        raise ::Financial::Errors::PeriodClosed.new(
          "Operação bloqueada — período #{date.strftime('%m/%Y')} está fechado contabilmente. " \
          'Reabrir via Governance::ReopenPeriod (ADMIN, motivo obrigatório).',
          period_date: date
        )
      end
    end
  end
end
