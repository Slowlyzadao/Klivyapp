module Financial
  module Reports
    # Exportação para contador externo — canon F-33 §sub-aba 1.
    #
    # 4 CSVs separados por tipo (receitas, despesas, comissões, caixa)
    # cobrindo um período. Format Brazilian-Excel-friendly:
    #   - UTF-8 com BOM (Excel BR detecta encoding)
    #   - Separador `;` (Excel BR usa "," como decimal)
    #   - Decimais com vírgula
    #
    # Uso:
    #   service = Financial::Reports::AccountantExport.new(account:, from:, to:)
    #   csv = service.csv_for(:receitas)  # → string CSV
    #
    # Tipos disponíveis: :receitas | :despesas | :comissoes | :caixa
    class AccountantExport
      TYPES = %i[receitas despesas comissoes caixa].freeze
      BOM = "﻿".freeze

      attr_reader :account, :from, :to

      def initialize(account:, from:, to:)
        @account = account
        @from = from.to_date
        @to = to.to_date
      end

      def csv_for(type)
        sym = type.to_sym
        raise ArgumentError, "tipo inválido: #{type}" unless TYPES.include?(sym)
        send("build_#{sym}")
      end

      # Counts pra preview na UI antes de baixar — evita o contador
      # baixar CSVs vazios sem saber.
      def counts
        {
          receitas:  receipts_scope.count,
          despesas:  expenses_scope.count,
          comissoes: commissions_scope.count,
          caixa:     entries_scope.count
        }
      end

      private

      # ── Receitas (PaymentReceipts) ─────────────────────────────────
      def receipts_scope
        ::Financial::PaymentReceipt
          .where(account_id: @account.id)
          .where(received_at: @from..@to)
          .includes(:patient, :financial_bank_account, items: { installment: { budget: :professional } })
          .order(received_at: :asc, id: :asc)
      end

      def build_receitas
        require 'csv'
        bom_csv do |csv|
          csv << %w[
            data numero_recibo paciente bruto juros multa desconto credito_aplicado
            liquido forma_pagamento conta profissional
          ]
          receipts_scope.find_each do |r|
            prof = r.items.first&.installment&.budget&.professional
            csv << [
              fmt_date(r.received_at),
              r.receipt_number,
              r.patient&.name,
              fmt_money(r.gross_amount_cents),
              fmt_money(r.interest_amount_cents),
              fmt_money(r.fine_amount_cents),
              fmt_money(r.discount_amount_cents),
              fmt_money(r.credit_applied_cents),
              fmt_money(r.net_amount_cents),
              r.payment_method,
              r.financial_bank_account&.name,
              prof&.name
            ]
          end
        end
      end

      # ── Despesas (Expenses) ────────────────────────────────────────
      def expenses_scope
        ::Financial::Expense
          .where(account_id: @account.id)
          .where(competence_date: @from..@to)
          .includes(:financial_dre_category, :financial_bank_account)
          .order(due_date: :asc, id: :asc)
      end

      def build_despesas
        require 'csv'
        bom_csv do |csv|
          csv << %w[
            data_competencia data_vencimento descricao categoria categoria_tipo
            valor pago_em valor_pago status forma_pagamento conta
          ]
          expenses_scope.find_each do |e|
            cat = e.financial_dre_category
            csv << [
              fmt_date(e.competence_date),
              fmt_date(e.due_date),
              e.description,
              cat&.name,
              cat&.kind,
              fmt_money(e.amount_cents),
              fmt_date(e.paid_at),
              fmt_money(e.paid_amount_cents),
              e.status,
              e.payment_method,
              e.financial_bank_account&.name
            ]
          end
        end
      end

      # ── Comissões (CommissionEntries) ──────────────────────────────
      def commissions_scope
        ::Financial::CommissionEntry
          .where(account_id: @account.id)
          .where(competence_date: @from..@to)
          .where(status: %w[devida paga estornada])
          .includes(:professional, installment: :patient)
          .order(competence_date: :asc, id: :asc)
      end

      def build_comissoes
        require 'csv'
        bom_csv do |csv|
          csv << %w[
            data_competencia profissional paciente status
            base_calculo percentual valor_comissao pago_em
          ]
          commissions_scope.find_each do |c|
            csv << [
              fmt_date(c.competence_date),
              c.professional&.name,
              c.installment&.patient&.name,
              c.status,
              fmt_money(c.calc_base_cents),
              fmt_percent(c.percent_basis_points),
              fmt_money(c.commission_amount_cents),
              fmt_date(c.paid_at)
            ]
          end
        end
      end

      # ── Caixa (Entries — fluxo de caixa completo) ─────────────────
      def entries_scope
        ::Financial::Entry
          .where(account_id: @account.id)
          .where(cash_date: @from..@to)
          .includes(:financial_bank_account, :financial_dre_category, :patient)
          .order(cash_date: :asc, id: :asc)
      end

      def build_caixa
        require 'csv'
        bom_csv do |csv|
          csv << %w[
            data_caixa data_competencia direcao tipo descricao valor
            categoria conta paciente forma_pagamento
          ]
          entries_scope.find_each do |e|
            csv << [
              fmt_date(e.cash_date),
              fmt_date(e.competence_date),
              e.direction,                 # in | out
              e.kind,
              e.description,
              fmt_money(e.amount_cents),
              e.financial_dre_category&.name,
              e.financial_bank_account&.name,
              e.patient&.name,
              e.payment_method
            ]
          end
        end
      end

      # ── Helpers de formatação ──────────────────────────────────────

      # CSV BR-friendly: BOM + ; + força string entre aspas se contiver ;
      def bom_csv
        out = BOM.dup
        CSV.generate(out, col_sep: ';', force_quotes: true) do |csv|
          yield csv
        end
        out
      end

      def fmt_date(d)
        return '' if d.blank?
        d.respond_to?(:strftime) ? d.strftime('%Y-%m-%d') : d.to_s
      end

      # Centavos → string "1234,56" (vírgula decimal, BR-style).
      def fmt_money(cents)
        return '' if cents.blank?
        v = cents.to_i
        sign = v.negative? ? '-' : ''
        abs = v.abs
        whole = abs / 100
        cent  = abs % 100
        "#{sign}#{whole},#{cent.to_s.rjust(2, '0')}"
      end

      # Basis points (4000) → "40,00%"
      def fmt_percent(bp)
        return '' if bp.blank?
        whole = bp.to_i / 100
        rest  = bp.to_i % 100
        "#{whole},#{rest.to_s.rjust(2, '0')}%"
      end
    end
  end
end
