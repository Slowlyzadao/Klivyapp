class CreateFinancialV2BudgetsAndInstallments < ActiveRecord::Migration[7.0]
  # Budget (orçamento ou plano de tratamento aprovado), Installment (parcela) e PaymentReceipt (recibo).
  # Canon: 01-funcionamento §3 (1ª e 2ª origens) + glossário Parte 7.
  # 04-backlog-tecnico Parte I §3 — separação Installment ↔ PaymentReceipt:
  #   "Um pagamento PIX único pode quitar 3 parcelas de uma vez. PaymentReceipt como entidade
  #    própria com 1..N parcelas dentro permite registrar isso sem duplicar o FinancialEntry."
  def change
    # ---------------------------------------------------------------
    # Budgets — orçamentos e planos de tratamento aprovados.
    # Inclui Budget (avulso) E TreatmentPlan-derived (vínculo opcional com plano clínico).
    # ---------------------------------------------------------------
    create_table :financial_budgets do |t|
      t.bigint  :account_id,             null: false
      t.bigint  :patient_id,             null: false
      t.bigint  :professional_id          # User dono do orçamento (quem cria/aprova)
      t.bigint  :treatment_plan_id        # se origem clínica (PT)
      t.string  :external_id,            limit: 60  # importação Clinicorp (CheckoutUuid)
      t.string  :origin,                 null: false, default: 'orcamento', limit: 30
      # origin: orcamento (avulso, recepção) | plano_tratamento (clínica) | mensalidade
      t.string  :status,                 null: false, default: 'rascunho', limit: 20
      # status: rascunho | enviado | aprovado | cancelado | concluido
      t.bigint  :subtotal_cents,         null: false, default: 0
      t.bigint  :discount_cents,         null: false, default: 0
      t.string  :discount_kind,          limit: 16  # percentual | fixo
      t.integer :discount_basis_points  # se percentual: 500 = 5,00%
      t.bigint  :total_cents,            null: false, default: 0
      t.integer :installments_count,     null: false, default: 1
      t.string  :payment_method,         limit: 30  # forma padrão
      t.text    :notes
      t.date    :valid_until
      t.datetime :sent_at
      t.datetime :approved_at
      t.bigint  :approved_by_id
      t.datetime :canceled_at
      t.bigint  :canceled_by_id
      t.text    :cancel_reason
      t.jsonb   :metadata,               default: {}
      t.bigint  :created_by_id
      t.bigint  :updated_by_id
      t.bigint  :deleted_by_id
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :financial_budgets, :account_id
    add_index :financial_budgets, [:account_id, :patient_id]
    add_index :financial_budgets, [:account_id, :status]
    add_index :financial_budgets, :professional_id
    add_index :financial_budgets, :treatment_plan_id
    add_index :financial_budgets, [:account_id, :external_id], unique: true,
              where: 'external_id IS NOT NULL', name: 'idx_uniq_budget_external_id'
    add_index :financial_budgets, :deleted_at

    # ---------------------------------------------------------------
    # Budget items — procedimentos/produtos dentro do orçamento.
    # ---------------------------------------------------------------
    create_table :financial_budget_items do |t|
      t.bigint  :account_id,           null: false
      t.bigint  :financial_budget_id,  null: false
      t.bigint  :treatment_item_id      # se origem clínica (vínculo com TreatmentItem)
      t.string  :description,          null: false, limit: 240
      t.string  :procedure_code,       limit: 40
      t.integer :quantity,             null: false, default: 1
      t.bigint  :unit_price_cents,     null: false, default: 0
      t.bigint  :discount_cents,       null: false, default: 0
      t.bigint  :total_cents,          null: false, default: 0
      t.bigint  :professional_id        # se procedimento atribuído a profissional específico
      t.integer :position,             null: false, default: 0
      t.timestamps
    end
    add_index :financial_budget_items, :account_id
    add_index :financial_budget_items, :financial_budget_id, name: 'idx_budget_items_on_budget'
    add_index :financial_budget_items, :treatment_item_id

    # ---------------------------------------------------------------
    # Installments — parcelas a receber.
    # status canon: pendente | recebido | vencido | estornado | cancelado | renegociado
    # Suporte a baixa parcial: amount_cents é o valor da parcela; received_amount_cents
    # rastreia quanto já foi recebido. Para baixa parcial, o serviço cria uma nova
    # parcela com o saldo restante (BUG-01 fix).
    # ---------------------------------------------------------------
    create_table :financial_installments do |t|
      t.bigint  :account_id,             null: false
      t.bigint  :financial_budget_id,    null: false
      t.bigint  :patient_id,             null: false
      t.bigint  :professional_id          # comissão recai aqui
      t.bigint  :financial_dre_category_id  # Receitas (override do default Particulares se necessário)
      t.integer :number,                 null: false  # 1..N
      t.integer :total_in_series,        null: false  # N
      t.bigint  :amount_cents,           null: false
      t.bigint  :received_amount_cents,  null: false, default: 0
      t.string  :status,                 null: false, default: 'pendente', limit: 20
      t.string  :payment_method,         limit: 30
      # payment_method: dinheiro | pix | debito | credito | boleto | transferencia | multiplas
      t.date    :due_date,               null: false
      t.date    :competence_date,        null: false  # data da aprovação do orçamento (regime competência)
      t.date    :received_at
      t.bigint  :renegotiated_to_id        # se status=renegociado, aponta para a nova parcela inicial
      t.bigint  :replaces_installment_id   # parcela criada como saldo de baixa parcial
      t.text    :notes

      # Asaas / gateway integration
      t.string  :gateway,                limit: 30, default: 'manual'
      t.string  :gateway_id,             limit: 100
      t.string  :gateway_status,         limit: 40
      t.string  :payment_link
      t.string  :barcode_line             # boleto digitável
      t.text    :pix_qr_code
      t.string  :pix_qr_code_image_url
      t.jsonb   :gateway_metadata,       default: {}
      t.datetime :gateway_synced_at

      t.bigint  :created_by_id
      t.bigint  :updated_by_id
      t.bigint  :deleted_by_id
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :financial_installments, :account_id
    add_index :financial_installments, [:account_id, :status]
    add_index :financial_installments, [:account_id, :due_date]
    add_index :financial_installments, [:account_id, :status, :due_date],
              name: 'idx_installments_account_status_due'
    add_index :financial_installments, :financial_budget_id
    add_index :financial_installments, :patient_id
    add_index :financial_installments, :professional_id
    add_index :financial_installments, [:financial_budget_id, :number],
              unique: true, where: 'deleted_at IS NULL', name: 'idx_uniq_installment_number_per_budget'
    add_index :financial_installments, :gateway_id, where: 'gateway_id IS NOT NULL'
    add_index :financial_installments, :deleted_at

    # ---------------------------------------------------------------
    # Payment receipts — agrupam 1..N installments quitadas em um único recebimento.
    # Necessário porque um único PIX pode quitar várias parcelas (canon §3 backlog).
    # 1 PaymentReceipt → 1 FinancialEntry (entrada efetiva no caixa) → N Installments.
    # ---------------------------------------------------------------
    create_table :financial_payment_receipts do |t|
      t.bigint  :account_id,             null: false
      t.bigint  :patient_id,             null: false
      t.bigint  :financial_bank_account_id, null: false
      t.bigint  :financial_entry_id      # vinculo com a entrada efetiva (criada pelo serviço ReceivePayment)
      t.bigint  :received_by_id          # User (operador)
      t.string  :receipt_number,         null: false, limit: 30
      t.string  :payment_method,         null: false, limit: 30
      t.bigint  :gross_amount_cents,     null: false  # soma do recebido das parcelas
      t.bigint  :interest_amount_cents,  null: false, default: 0  # juros
      t.bigint  :fine_amount_cents,      null: false, default: 0  # multa
      t.bigint  :discount_amount_cents,  null: false, default: 0  # desconto concedido na hora
      t.bigint  :credit_applied_cents,   null: false, default: 0  # crédito do paciente abatido
      t.bigint  :net_amount_cents,       null: false  # valor efetivamente recebido pela clínica
      t.date    :received_at,            null: false
      t.text    :notes
      t.string  :pdf_status,             limit: 20, default: 'pending'  # pending | generated | failed
      t.string  :pdf_url
      t.bigint  :created_by_id
      t.bigint  :updated_by_id
      t.bigint  :deleted_by_id
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :financial_payment_receipts, :account_id
    add_index :financial_payment_receipts, [:account_id, :patient_id]
    add_index :financial_payment_receipts, [:account_id, :receipt_number],
              unique: true, where: 'deleted_at IS NULL', name: 'idx_uniq_receipt_number_per_account'
    add_index :financial_payment_receipts, :financial_entry_id
    add_index :financial_payment_receipts, :deleted_at

    # Junction: receipt pode quitar múltiplas parcelas, parcela só pode estar em um receipt vivo.
    create_table :financial_payment_receipt_items do |t|
      t.bigint  :account_id,                    null: false
      t.bigint  :financial_payment_receipt_id,  null: false
      t.bigint  :financial_installment_id,      null: false
      t.bigint  :amount_cents,                  null: false  # quanto desta parcela foi quitado neste receipt
      t.timestamps
    end
    add_index :financial_payment_receipt_items, :account_id
    add_index :financial_payment_receipt_items, :financial_payment_receipt_id,
              name: 'idx_receipt_items_on_receipt'
    add_index :financial_payment_receipt_items, :financial_installment_id,
              name: 'idx_receipt_items_on_installment'
    add_index :financial_payment_receipt_items, [:financial_payment_receipt_id, :financial_installment_id],
              unique: true, name: 'idx_uniq_receipt_installment_pair'
  end
end
