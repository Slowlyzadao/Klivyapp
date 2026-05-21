module Financial
  # Marca uma CommissionEntry como paga e cria a Expense correspondente
  # em "A Pagar" — canon F-29 §"Marcar como pago → gera Expense em A Pagar
  # com categoria Comissões".
  #
  # Não efetiva o pagamento real (saída de caixa). Só joga no fluxo de
  # despesas pra ser pago via tela A Pagar (que aí gera o Entry no caixa).
  # Isso preserva o ciclo: aprovar comissão (aqui) → pagar despesa (A Pagar).
  #
  # Idempotente: se a entry já está paga, retorna a expense existente
  # sem criar uma nova (proteção contra clique duplo).
  class PayCommission
    Result = Struct.new(:success?, :commission_entry, :expense, :errors,
                        keyword_init: true)

    DEFAULT_CATEGORY_NAME = 'Comissões'.freeze

    attr_reader :commission_entry, :user, :due_date, :description_override

    def self.call(**kwargs) = new(**kwargs).call

    def initialize(commission_entry:, user:, due_date: nil, description: nil)
      @commission_entry = commission_entry
      @user = user
      @due_date = due_date || Date.current
      @description_override = description
    end

    def call
      return idempotent_result if commission_entry.status == 'paga' && commission_entry.expense.present?

      unless commission_entry.status.in?(%w[devida provisionada])
        return Result.new(
          success?: false,
          errors: ["Comissão precisa estar em 'devida' pra ser paga (atual: '#{commission_entry.status}')"]
        )
      end

      ActiveRecord::Base.transaction do
        category = commission_category
        unless category
          return Result.new(
            success?: false,
            errors: ['Categoria "Comissões" não encontrada. Crie em Configurações > Categorias DRE.']
          )
        end

        expense = build_expense(category)
        unless expense.save
          raise ActiveRecord::Rollback
        end

        commission_entry.update!(
          status: 'paga',
          paid_at: due_date,
          paid_by_id: user.id,
          financial_expense_id: expense.id
        )

        return Result.new(success?: true, commission_entry: commission_entry, expense: expense)
      end

      Result.new(success?: false, errors: ['Falha ao gerar despesa de comissão. Verifique os dados.'])
    end

    private

    def idempotent_result
      Result.new(success?: true, commission_entry: commission_entry,
                 expense: commission_entry.expense)
    end

    # Acha a categoria "Comissões" do account. Padrão `kind: 'custo_variavel'`
    # — alinhado com DEFAULT_CATEGORIES da SettingsCategoriesTab.
    def commission_category
      account_id = commission_entry.account_id
      ::Financial::DreCategory
        .where(account_id: account_id)
        .where('LOWER(name) = ?', DEFAULT_CATEGORY_NAME.downcase)
        .first
    end

    def build_expense(category)
      prof_name = commission_entry.professional&.name || "Profissional ##{commission_entry.professional_id}"
      desc = description_override.presence || default_description(prof_name)

      ::Financial::Expense.new(
        account_id: commission_entry.account_id,
        financial_dre_category_id: category.id,
        financial_commission_entry_id: commission_entry.id,
        description: desc,
        amount_cents: commission_entry.commission_amount_cents,
        paid_amount_cents: 0,
        status: 'pendente',
        competence_date: commission_entry.competence_date,
        due_date: due_date,
        registered_by_id: user.id
      )
    end

    def default_description(prof_name)
      receipt = commission_entry.payment_receipt
      patient_name = commission_entry.installment&.patient&.name
      parts = ["Comissão #{prof_name}"]
      parts << "(Recibo #{receipt.receipt_number})" if receipt&.receipt_number.present?
      parts << "— #{patient_name}" if patient_name.present?
      parts.join(' ')
    end
  end
end
