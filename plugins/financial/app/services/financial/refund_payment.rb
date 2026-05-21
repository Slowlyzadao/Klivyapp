module Financial
  # Estorna um PaymentReceipt: reverte os 5 efeitos da baixa.
  # Canon §7.3 + backlog §2.2 (Estornar parcela recebida):
  #   1. parcela → estornado
  #   2. saldo da conta destino -valor (entry de saída no dia do estorno, NÃO retroativo)
  #   3. lançar entry de saída no Fluxo de Caixa do dia do estorno
  #   4. reverter comissão (CommissionEntry: devida → estornada)
  #   5. se era a única parcela paga, Budget volta a aprovado
  #   6. se origem de baixa parcial gerou nova parcela (replaces), cancelar a nova também
  #   7. devolver crédito do paciente aplicado (lançar credit reverso)
  #   8. opcionalmente devolver via gateway (refund_charge)
  class RefundPayment
    Result = Financial::ServiceResult

    # @param receipt [Financial::PaymentReceipt]
    # @param actor   [User]
    # @param reason  [String]
    # @param refunded_at [Date] data do estorno (default hoje, NUNCA retroativo)
    # @param refund_via_gateway [Boolean] se true, chama adapter.refund_charge
    def self.call(**kwargs) = new(**kwargs).call

    # @param refund_amount_cents [Integer, nil] valor a estornar (em centavos).
    #   nil = estorno integral (default canon). Menor que receipt.net_amount_cents
    #   = estorno parcial: parcela vira 'parcial' (received_amount reduzido), entry
    #   de saída tem o valor parcial, gateway recebe pedido com valor parcial.
    # @param as_credit [Boolean] se true, NÃO lança Entry de saída de caixa —
    #   o valor estornado vira saldo credit do paciente (PatientCredit positivo)
    #   para uso futuro. Útil quando paciente concordou em deixar como crédito
    #   em vez de devolução real via PIX/cartão.
    def initialize(receipt:, actor:, reason: nil, refunded_at: nil, refund_via_gateway: true,
                   refund_amount_cents: nil, as_credit: false)
      @receipt = receipt
      @actor = actor
      @reason = reason
      @refunded_at = refunded_at || Date.current
      @refund_via_gateway = refund_via_gateway
      @refund_amount_cents = refund_amount_cents
      @as_credit = as_credit
    end

    def call
      # Valida valor de estorno parcial. Default = saldo ainda não estornado.
      already_refunded_cents = sum_refunded_cents
      remaining_cents = @receipt.net_amount_cents - already_refunded_cents
      return Result.failure('Recibo já estornado integralmente') if remaining_cents <= 0

      requested_refund = @refund_amount_cents.presence || remaining_cents
      return Result.failure('Valor de estorno deve ser positivo') if requested_refund <= 0
      if requested_refund > remaining_cents
        return Result.failure(
          "Valor de estorno (R$ #{format('%.2f', requested_refund / 100.0)}) excede o saldo " \
          "do recibo a estornar (R$ #{format('%.2f', remaining_cents / 100.0)})"
        )
      end

      reversal_entry = nil
      # "partial" = ainda sobra valor no recibo APÓS este estorno.
      # Importante pra rotular Entry, parcela e nota do recibo corretamente.
      partial = requested_refund < remaining_cents
      fully_refunded_now = (already_refunded_cents + requested_refund) >= @receipt.net_amount_cents

      ActiveRecord::Base.transaction do
        # 1) Lock receipt + items + installments
        @receipt.lock!
        items = @receipt.items.lock(true).to_a
        installments = items.map(&:installment).compact

        # 2) Para cada item, devolve received_amount na parcela.
        # Em estorno parcial, distribui o valor proporcionalmente entre os items
        # (caso comum: 1 receipt = 1 item = 1 parcela; proporção é 100%).
        # Em estorno integral, devolve item.amount_cents (mesmo comportamento canon).
        total_items_cents = items.sum(&:amount_cents)
        items.each do |item|
          inst = item.installment
          inst.lock!

          item_refund_cents =
            if partial && total_items_cents.positive?
              # Distribui proporcionalmente; arredonda pra centavo (último ajusta resto).
              (requested_refund * item.amount_cents / total_items_cents.to_f).round
            else
              item.amount_cents
            end

          new_received = [inst.received_amount_cents - item_refund_cents, 0].max
          new_status =
            if new_received.zero?
              'estornado'
            else
              # Recebido parcial: parcela ainda tem valor pago. Em UI, isso
              # aparece como "parcela com R$ X recebido + R$ Y estornado".
              'parcial'
            end

          inst.update!(
            received_amount_cents: new_received,
            status: new_status
          )

          # 6) Em estorno integral, se a parcela era de baixa parcial
          # (replaces_installment_id), cancela a "filha" também.
          # Em estorno parcial, NÃO mexe na filha — paciente ainda deve o saldo.
          unless partial
            inst.budget.installments
                .where(replaces_installment_id: inst.id)
                .where(status: %w[pendente vencido])
                .update_all(status: 'cancelado', updated_at: Time.current)
          end
        end

        # 3) Lança Entry de saída de caixa pelo valor estornado.
        # Pulado se @as_credit=true (valor vira crédito do paciente, não sai do caixa).
        unless @as_credit
          reversal_entry = Financial::Entry.create!(
            account_id: @receipt.account_id,
            financial_bank_account_id: @receipt.financial_bank_account_id,
            financial_dre_category_id: @receipt.financial_entry&.financial_dre_category_id,
            patient_id: @receipt.patient_id,
            direction: 'out',
            kind: 'estorno_receita',
            amount_cents: requested_refund,
            payment_method: @receipt.payment_method,
            competence_date: @refunded_at,
            cash_date: @refunded_at,
            description: build_entry_description(partial: partial, requested_refund: requested_refund),
            source_type: 'Financial::PaymentReceipt',
            source_id: @receipt.id,
            reverses_entry_id: @receipt.financial_entry_id,
            affects_dre: true,
            affects_cashflow: true,
            registered_by_id: @actor&.id
          )
        end

        # 3b) Em estorno-como-crédito, gera PatientCredit positivo.
        if @as_credit
          Financial::PatientCredit.create!(
            account_id: @receipt.account_id,
            patient_id: @receipt.patient_id,
            amount_cents: requested_refund,
            origin: 'estorno',
            origin_type: 'Financial::PaymentReceipt',
            origin_id: @receipt.id,
            registered_by_id: @actor&.id,
            occurred_at: Time.current,
            description: "Crédito do estorno #{partial ? 'parcial ' : ''}do recibo #{@receipt.receipt_number}"
          )
        end

        # 4) Reverte CommissionEntry: devida → estornada
        installments.each do |inst|
          inst.commission_entries.where(status: 'devida').update_all(
            status: 'estornada',
            updated_at: Time.current
          )
        end

        # 5) Status do Budget: se ficou sem nenhuma parcela paga, volta para aprovado.
        budget_ids = installments.map(&:financial_budget_id).uniq
        Financial::Budget.where(id: budget_ids).find_each do |b|
          paid_count = b.installments.where(status: %w[recebido parcial]).where('received_amount_cents > 0').count
          if paid_count.zero? && b.status == 'concluido'
            b.update!(status: 'aprovado')
          end
        end

        # 7) Devolve crédito do paciente aplicado (se houver)
        if @receipt.credit_applied_cents.positive?
          Financial::PatientCredit.create!(
            account_id: @receipt.account_id,
            patient_id: @receipt.patient_id,
            amount_cents: @receipt.credit_applied_cents,
            origin: 'estorno',
            origin_type: 'Financial::PaymentReceipt',
            origin_id: @receipt.id,
            registered_by_id: @actor&.id,
            occurred_at: Time.current,
            description: "Devolução do crédito aplicado no recibo estornado #{@receipt.receipt_number}"
          )
        end

        # Marca o receipt como estornado (não soft-deleta — vira histórico).
        # Em estorno parcial, indica isso na nota; só usa "ESTORNADO" cheio quando
        # o saldo zera (`fully_refunded_now`).
        marker =
          if fully_refunded_now
            "[ESTORNADO em #{@refunded_at}]"
          else
            "[ESTORNO PARCIAL R$ #{format('%.2f', requested_refund / 100.0)} em #{@refunded_at}]"
          end
        @receipt.update!(notes: [@receipt.notes, marker, @reason].compact.reject(&:blank?).join(' '))

        # 8) Refund externo no gateway (se aplicável)
        if @refund_via_gateway && installments.any? { |i| i.gateway_id.present? && i.gateway != 'manual' }
          adapter = Financial::Gateways.adapter_for(@receipt.account)
          installments.each do |inst|
            next if inst.gateway_id.blank? || inst.gateway == 'manual'

            adapter.refund_charge(installment: inst, amount_cents: inst.received_amount_cents)
          end
        end
      end

      Result.success(reversal_entry: reversal_entry, receipt: @receipt.reload)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.join('; '))
    end

    private

    # Soma centavos já estornados deste recibo (pode haver múltiplos parciais).
    # Considera tanto Entries de saída (estorno via método) quanto PatientCredits
    # com origin='estorno' deste recibo (estorno-como-crédito).
    def sum_refunded_cents
      from_entries = Financial::Entry
                     .where(account_id: @receipt.account_id, source_type: 'Financial::PaymentReceipt',
                            source_id: @receipt.id, kind: 'estorno_receita')
                     .sum(:amount_cents)
      from_credits = Financial::PatientCredit
                     .where(account_id: @receipt.account_id, origin: 'estorno',
                            origin_type: 'Financial::PaymentReceipt', origin_id: @receipt.id)
                     .where('amount_cents > 0') # exclui devolução de credit_applied (não conta como estorno)
                     .sum(:amount_cents)
      from_entries.to_i + from_credits.to_i
    end

    def build_entry_description(partial:, requested_refund:)
      base = partial ? 'Estorno parcial' : 'Estorno'
      brl = format('%.2f', requested_refund / 100.0).tr('.', ',')
      desc = "#{base} R$ #{brl} do recibo #{@receipt.receipt_number}"
      desc += " - #{@reason}" if @reason.present?
      desc
    end
  end
end
