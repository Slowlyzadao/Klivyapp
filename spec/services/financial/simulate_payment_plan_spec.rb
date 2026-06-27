# frozen_string_literal: true

require 'rails_helper'

# Cobre os caminhos críticos do SimulatePaymentPlan:
#   1. Plan vazio → failure
#   2. Plan com 1 row PIX sem fee cadastrada → fee=0, net=gross, fee_resolved=false
#   3. Plan heterogêneo (PIX + Crédito) com fee versionada → fee aplicada só no Crédito
#   4. Plan com payment_method_id explícito (canon) → resolve fee daquele método
#
# Read-only: nenhum efeito colateral persistido (sem Installment/Entry/CommissionEntry).
RSpec.describe Financial::SimulatePaymentPlan do
  let!(:account) { create(:account) }
  let!(:patient) { create(:patient, account: account) }

  let!(:budget) do
    Financial::Budget.create!(
      account: account,
      patient: patient,
      origin: 'orcamento',
      status: 'rascunho',
      installments_count: 1,
      subtotal_cents: 100_000,
      total_cents: 100_000
    )
  end

  let!(:pix_method) do
    Financial::PaymentMethod.create!(
      account: account,
      kind: 'pix',
      name: 'PIX',
      status: 'active',
      supports_installments: false,
      max_installments: 1
    )
  end

  let!(:credito_method) do
    Financial::PaymentMethod.create!(
      account: account,
      kind: 'credito',
      name: 'Cielo Crédito',
      status: 'active',
      supports_installments: true,
      max_installments: 12,
      provider: 'Cielo'
    )
  end

  describe '.call' do
    context 'plan vazio' do
      it 'retorna failure' do
        result = described_class.call(budget: budget, installments_plan: [])

        expect(result.failure?).to be true
        expect(result.errors).to include('installments_plan vazio')
      end
    end

    context 'sem fee cadastrada' do
      it 'retorna fee=0 e fee_resolved=false' do
        result = described_class.call(
          budget: budget,
          installments_plan: [
            { amount_cents: 50_000, due_date: Date.current, payment_method_id: pix_method.id }
          ]
        )

        expect(result.success?).to be true
        row = result[:plan].first
        expect(row[:fee_amount_cents]).to eq(0)
        expect(row[:net_amount_cents]).to eq(50_000)
        expect(row[:fee_resolved]).to be false
        expect(result[:totals][:all_fees_resolved]).to be false
      end
    end

    context 'plan heterogêneo (PIX + Crédito) com fee versionada no crédito' do
      let!(:credito_fee) do
        # Cartão crédito 2x: 3.5% + R$0,00, liquidação D+30
        Financial::PaymentMethodFee.create!(
          account: account,
          payment_method: credito_method,
          installments_count: 2,
          fee_percent_basis_points: 350,
          fee_fixed_cents: 0,
          liquidation_days: 30,
          valid_from: Date.current - 30.days,
          status: 'active'
        )
      end

      it 'aplica fee apenas no método com fee vigente e gera totals corretos' do
        plan = [
          { amount_cents: 30_000, due_date: Date.current, payment_method_id: pix_method.id },
          { amount_cents: 70_000, due_date: Date.current + 30.days, payment_method_id: credito_method.id }
        ]

        result = described_class.call(budget: budget, installments_plan: plan)

        expect(result.success?).to be true

        pix_row = result[:plan].first
        credito_row = result[:plan].last

        # PIX sem fee
        expect(pix_row[:fee_amount_cents]).to eq(0)
        expect(pix_row[:net_amount_cents]).to eq(30_000)
        expect(pix_row[:fee_resolved]).to be false

        # Crédito com fee: 70000 × 3.5% = 2450 cents (R$ 24,50)
        # NOTE: total_in_series = plan.size = 2, e a fee é cadastrada com installments_count=2
        expect(credito_row[:fee_amount_cents]).to eq(2_450)
        expect(credito_row[:net_amount_cents]).to eq(67_550)
        expect(credito_row[:fee_resolved]).to be true
        expect(credito_row[:liquidation_days]).to eq(30)
        expect(credito_row[:expected_liquidation_date]).to eq(Date.current + 60.days)

        # Totals
        totals = result[:totals]
        expect(totals[:gross_cents]).to eq(100_000)
        expect(totals[:total_fee_cents]).to eq(2_450)
        expect(totals[:total_net_cents]).to eq(97_550)
        expect(totals[:installments_count]).to eq(2)
        expect(totals[:all_fees_resolved]).to be false # PIX sem fee
      end
    end

    context 'lookup determinístico por payment_method_id (canon)' do
      let!(:other_credito) do
        Financial::PaymentMethod.create!(
          account: account,
          kind: 'credito',
          name: 'GetNet Crédito',
          status: 'active',
          supports_installments: true,
          max_installments: 12,
          provider: 'GetNet'
        )
      end

      let!(:other_credito_fee) do
        # Fee diferente — 5% (não 3.5%) — para validar que lookup é por id, não por kind
        Financial::PaymentMethodFee.create!(
          account: account,
          payment_method: other_credito,
          installments_count: 1,
          fee_percent_basis_points: 500,
          fee_fixed_cents: 0,
          liquidation_days: 1,
          valid_from: Date.current - 1.day,
          status: 'active'
        )
      end

      it 'busca fee do PaymentMethod específico passado por id' do
        result = described_class.call(
          budget: budget,
          installments_plan: [
            { amount_cents: 10_000, due_date: Date.current, payment_method_id: other_credito.id }
          ]
        )

        row = result[:plan].first
        expect(row[:payment_method_id]).to eq(other_credito.id)
        expect(row[:payment_method_name]).to eq('GetNet Crédito')
        expect(row[:fee_percent_basis_points]).to eq(500)
        expect(row[:fee_amount_cents]).to eq(500) # 10000 × 5%
      end
    end

    context 'multi-tenant isolation' do
      let!(:other_account) { create(:account) }
      let!(:other_pm) do
        Financial::PaymentMethod.create!(
          account: other_account,
          kind: 'pix',
          name: 'PIX outra conta',
          status: 'active'
        )
      end

      it 'não resolve PaymentMethod de outra conta — fee fica zerada' do
        result = described_class.call(
          budget: budget,
          installments_plan: [
            { amount_cents: 50_000, due_date: Date.current, payment_method_id: other_pm.id }
          ]
        )

        row = result[:plan].first
        expect(row[:payment_method_id]).to be_nil # não resolveu
        expect(row[:fee_amount_cents]).to eq(0)
        expect(row[:fee_resolved]).to be false
      end
    end
  end
end
