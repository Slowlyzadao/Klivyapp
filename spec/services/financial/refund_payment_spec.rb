# frozen_string_literal: true

require 'rails_helper'

# Cobre os 3 caminhos críticos do RefundPayment:
#   1. Integral via método (PIX/dinheiro/etc) — cria Entry de saída + Refund 100%
#   2. Parcial via método — parcela vira 'parcial' + Refund com proportion_bps proporcional
#   3. Como crédito do paciente — NÃO cria Entry, cria PatientCredit positivo
#
# Pegaria a regressão de 2026-05-25 (NoMethodError `installment_id` no loop de
# comissão proporcional — coluna real é `financial_installment_id`).
RSpec.describe Financial::RefundPayment do
  let!(:account) { create(:account) }
  let!(:user)    { create(:user, account: account) }
  let!(:patient) { create(:patient, account: account) }
  let!(:bank)    { create(:financial_bank_account, account: account) }

  let!(:budget) do
    Financial::Budget.create!(
      account: account,
      patient: patient,
      origin: 'orcamento',
      status: 'concluido',
      installments_count: 1,
      subtotal_cents: 50_000,
      total_cents: 50_000
    )
  end

  let!(:installment) do
    Financial::Installment.create!(
      account: account,
      patient: patient,
      budget: budget,
      number: 1,
      total_in_series: 1,
      amount_cents: 50_000,
      received_amount_cents: 50_000,
      status: 'recebido',
      payment_method: 'pix',
      due_date: Date.current,
      competence_date: Date.current
    )
  end

  let!(:original_entry) do
    Financial::Entry.create!(
      account: account,
      financial_bank_account: bank,
      patient: patient,
      direction: 'in',
      kind: 'receita',
      amount_cents: 50_000,
      payment_method: 'pix',
      competence_date: Date.current,
      cash_date: Date.current,
      description: 'Recebimento original'
    )
  end

  let!(:receipt) do
    r = Financial::PaymentReceipt.create!(
      account: account,
      patient: patient,
      financial_bank_account: bank,
      financial_entry: original_entry,
      receipt_number: 'REC-TEST-001',
      payment_method: 'pix',
      received_at: Time.current,
      gross_amount_cents: 50_000,
      net_amount_cents: 50_000
    )
    Financial::PaymentReceiptItem.create!(
      account: account,
      receipt: r,
      installment: installment,
      amount_cents: 50_000
    )
    r
  end

  describe 'estorno integral em método (PIX)' do
    it 'marca parcela como estornada, cria Entry de saída e Refund 100%' do
      result = described_class.call(receipt: receipt, actor: user)

      expect(result.success?).to be true

      installment.reload
      expect(installment.status).to eq('estornado')
      expect(installment.received_amount_cents).to eq(0)

      reversal = Financial::Entry.where(
        source_type: 'Financial::PaymentReceipt',
        source_id: receipt.id,
        kind: 'estorno_receita'
      ).first
      expect(reversal).to be_present
      expect(reversal.direction).to eq('out')
      expect(reversal.amount_cents).to eq(50_000)

      refund = Financial::Refund.find_by(installment_id: installment.id)
      expect(refund).to be_present
      expect(refund.refund_amount_cents).to eq(50_000)
      expect(refund.refund_proportion_bps).to eq(10_000) # 100%
      expect(refund.refund_method).to eq('pix')
    end
  end

  describe 'estorno parcial' do
    it 'parcela vira parcial, Refund tem proportion_bps proporcional' do
      result = described_class.call(receipt: receipt, actor: user, refund_amount_cents: 20_000)

      expect(result.success?).to be true

      installment.reload
      expect(installment.status).to eq('parcial')
      expect(installment.received_amount_cents).to eq(30_000)

      reversal = Financial::Entry.where(
        source_type: 'Financial::PaymentReceipt',
        source_id: receipt.id,
        kind: 'estorno_receita'
      ).first
      expect(reversal.amount_cents).to eq(20_000)

      refund = Financial::Refund.find_by(installment_id: installment.id)
      expect(refund.refund_amount_cents).to eq(20_000)
      expect(refund.refund_proportion_bps).to eq(4_000) # 40% de 50_000
    end
  end

  describe 'estorno como crédito do paciente' do
    it 'NÃO cria Entry de saída, cria PatientCredit positivo' do
      result = described_class.call(receipt: receipt, actor: user, as_credit: true)

      expect(result.success?).to be true

      reversal_entries = Financial::Entry.where(
        source_type: 'Financial::PaymentReceipt',
        source_id: receipt.id,
        kind: 'estorno_receita'
      )
      expect(reversal_entries).to be_empty

      credit = Financial::PatientCredit.find_by(
        patient_id: patient.id,
        origin: 'estorno',
        origin_type: 'Financial::PaymentReceipt',
        origin_id: receipt.id
      )
      expect(credit).to be_present
      expect(credit.amount_cents).to eq(50_000)

      refund = Financial::Refund.find_by(installment_id: installment.id)
      expect(refund.refund_method).to eq('patient_credit')
      expect(refund.bank_account_id).to be_nil
    end
  end

  describe 'guards' do
    it 'rejeita estorno acima do saldo do recibo' do
      result = described_class.call(receipt: receipt, actor: user, refund_amount_cents: 60_000)
      expect(result.success?).to be false
      expect(result.errors.first).to match(/excede o saldo/)
    end

    it 'rejeita estorno de recibo já estornado integralmente' do
      described_class.call(receipt: receipt, actor: user)
      result = described_class.call(receipt: receipt.reload, actor: user)
      expect(result.success?).to be false
      expect(result.errors.first).to match(/já estornado integralmente/)
    end
  end
end
