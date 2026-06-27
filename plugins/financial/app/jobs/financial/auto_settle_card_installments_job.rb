module Financial
  # Cron diario - da baixa automatica (status `recebido`) nas parcelas de
  # cartao vencendo hoje (ou ja vencidas e ainda abertas) cuja forma de
  # pagamento tem `settlement_mode = 'on_due_date'`.
  #
  # Decisao de produto 2026-05-27 (memory project_baixa_automatica_cartao):
  # o operador ja passou o cartao na maquininha e parcelou para o cliente -
  # esse ato e a confirmacao. A adquirente garante o repasse nas datas, entao
  # a clinica NAO precisa clicar "Receber" parcela a parcela. Funciona mesmo
  # sem gateway integrado (Asaas e futuro).
  #
  # Comportamento:
  #   1. Acha Installment open (pendente/parcial) com due_date <= hoje cuja
  #      PaymentMethod.settlement_mode = 'on_due_date' (model garante que so
  #      credito/debito podem ter esse modo - boleto/convenio/parcelamento
  #      proprio ficam de fora porque a clinica assume o risco neles).
  #   2. Conta destino = `default_bank_account` da forma. Sem conta -> pula
  #      (deixa pendente; clinica configura a conta da maquininha em Settings).
  #   3. Chama ReceivePayment.call(actor: nil, auto_settled: true) - congela o
  #      snapshot de MDR, cria Entry/recibo, vira comissao provisionada->devida,
  #      tudo igual a um recebimento manual, marcando `auto_settled` p/ conciliacao.
  #
  # Idempotencia: ao virar `recebido`, a parcela sai do escopo de candidatas -
  # nao ha risco de baixa dupla. Falha (sem conta, caixa, etc.) deixa pendente
  # e tenta de novo no dia seguinte; so loga warn.
  #
  # Roda as 03:30 UTC no schedule.yml.
  class AutoSettleCardInstallmentsJob < ApplicationJob
    queue_as :scheduled

    def perform
      today = Time.zone.today
      counts = { settled: 0, skipped: 0, failed: 0, accounts: 0 }

      Account.find_each do |account|
        result = process_account(account, today)
        counts[:settled] += result[:settled]
        counts[:skipped] += result[:skipped]
        counts[:failed]  += result[:failed]
        counts[:accounts] += 1
      end

      Rails.logger.info(
        "[Financial::AutoSettleCardInstallmentsJob] " \
        "settled=#{counts[:settled]} skipped=#{counts[:skipped]} " \
        "failed=#{counts[:failed]} accounts=#{counts[:accounts]}"
      )
      counts
    end

    private

    def process_account(account, today)
      counts = { settled: 0, skipped: 0, failed: 0 }

      candidates(account, today).find_each do |inst|
        attempt_settle(account, inst, today, counts)
      end

      counts
    end

    # Parcelas abertas de cartao com baixa automatica configurada, vencidas/
    # vencendo hoje. Join em financial_payment_methods pelo payment_method_id
    # (parcelas legadas sem FK nao entram - corretas, nao ha como resolver a
    # conta destino delas automaticamente).
    def candidates(account, today)
      Financial::Installment
        .where(account_id: account.id, status: %w[pendente parcial])
        .where('financial_installments.due_date <= ?', today)
        .joins(
          'INNER JOIN financial_payment_methods pm ' \
          'ON pm.id = financial_installments.payment_method_id'
        )
        .where(
          "pm.settlement_mode = 'on_due_date' AND pm.status = 'active' " \
          "AND pm.deleted_at IS NULL AND pm.kind IN ('credito', 'debito')"
        )
    end

    def attempt_settle(account, inst, today, counts)
      pm = inst.payment_method_id && Financial::PaymentMethod.for_account(account.id).alive.find_by(id: inst.payment_method_id)
      bank = pm&.default_bank_account

      if bank.nil? || !bank.active
        counts[:skipped] += 1
        Rails.logger.warn(
          "[Financial::AutoSettleCardInstallmentsJob] sem conta destino - pula " \
          "inst=#{inst.id} account=#{account.id} pm=#{pm&.id}. " \
          'Configure a conta bancaria padrao da forma em Formas de Pagamento.'
        )
        return
      end

      result = Financial::ReceivePayment.call(
        account: account,
        actor: nil, # nil = sistema (baixa automatica) - registered_by_id=nil
        bank_account: bank,
        installment_amounts: [{ installment_id: inst.id, amount_cents: inst.remaining_cents }],
        payment_method: inst.payment_method,
        payment_method_record: pm,
        received_at: today,
        auto_settled: true,
        notes: 'Baixa automatica - cartao (settlement_mode=on_due_date)'
      )

      if result.success?
        counts[:settled] += 1
      else
        counts[:failed] += 1
        Rails.logger.warn(
          "[Financial::AutoSettleCardInstallmentsJob] falha inst=#{inst.id} " \
          "account=#{account.id}: #{result.errors.join('; ')}"
        )
      end
    end
  end
end
