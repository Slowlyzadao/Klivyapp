module Financial
  # Marca uma CommissionEntry como paga e cria a Expense correspondente
  # em "A Pagar" — canon F-29.
  #
  # Não efetiva o pagamento real (saída de caixa). Só joga no fluxo de
  # despesas pra ser pago via tela A Pagar (que aí gera o Entry no caixa).
  # Preserva o ciclo: aprovar comissão (aqui) → pagar despesa (A Pagar).
  #
  # Refatorado 2026-05-22 (Fase 3) — corrige `CRIT-SVC-01` e `CRIT-SVC-02`:
  #
  # CRIT-SVC-01: validações que retornavam `Result.failure` de dentro da
  # transaction eram problemáticas — `return` dentro de bloco `transaction`
  # no Rails encerra o método E commita o que já foi feito. Agora TODAS
  # as validações ficam fora da transação; apenas a mutation está dentro.
  #
  # CRIT-SVC-02: idempotência forte — checa expense existente ANTES de
  # entrar na transação E re-checa DENTRO (com lock) pra evitar TOCTOU.
  # Antes, retry com mesma commission_entry em status='devida' criava
  # 2ª Expense — A Pagar inflado.
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
      # ─── Idempotência forte (pre-check) ─────────────────────────────────
      # Auditoria `CRIT-SVC-02`: se já tem expense vinculada, retorna
      # sucesso imediatamente. Não cria 2ª expense em retry.
      if commission_entry.respond_to?(:financial_expense_id) && commission_entry.financial_expense_id.present?
        existing = ::Financial::Expense.find_by(id: commission_entry.financial_expense_id)
        return Result.new(
          success?: true,
          commission_entry: commission_entry,
          expense: existing,
          errors: ['already_paid']
        ) if existing
      end

      # ─── Validações FORA da transação ─────────────────────────────────
      # Auditoria `CRIT-SVC-01`: validar antes de entrar em tx evita
      # commits parciais quando há `return` no meio.
      unless commission_entry.status.in?(%w[devida provisionada aprovada a_pagar])
        return Result.new(
          success?: false,
          errors: ["Comissão precisa estar em status pagável (atual: '#{commission_entry.status}')"]
        )
      end

      category = commission_category
      unless category
        return Result.new(
          success?: false,
          errors: ['Categoria "Comissões" não encontrada. Crie em Configurações > Categorias DRE.']
        )
      end

      # ─── Transação atômica (lock + recheck + mutate) ──────────────────
      expense = nil
      ActiveRecord::Base.transaction do
        # Lock pessimista — bloqueia race condition de 2 cliques simultâneos
        # na mesma comissão.
        commission_entry.lock!
        commission_entry.reload

        # Recheck idempotência pós-lock (TOCTOU defense)
        if commission_entry.financial_expense_id.present?
          expense = ::Financial::Expense.find_by(id: commission_entry.financial_expense_id)
          # Sai do block sem rollback — estado tá consistente
          raise ::ActiveRecord::Rollback if expense.nil? # safety
        else
          expense = build_expense(category)
          expense.save!

          commission_entry.update!(
            status: 'paga',
            paid_at: @due_date,
            paid_by_id: user.id,
            financial_expense_id: expense.id
          )
        end
      end

      Result.new(success?: true, commission_entry: commission_entry, expense: expense)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, errors: e.record.errors.full_messages)
    end

    private

    # Acha a categoria "Comissões" do account. Padrão `kind: 'custo_variavel'`
    # — alinhado com DEFAULT_CATEGORIES da SettingsCategoriesTab.
    # Aceita variações de nome ("Comissões de Profissionais" do seed canon).
    def commission_category
      account_id = commission_entry.account_id
      ::Financial::DreCategory
        .where(account_id: account_id, deleted_at: nil)
        .where("LOWER(name) = ? OR LOWER(name) = ?",
               DEFAULT_CATEGORY_NAME.downcase,
               'comissões de profissionais')
        .order(:level)  # prefere o de nível mais alto (grupo > subgrupo)
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
        due_date: @due_date,
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
