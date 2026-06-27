# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TreatmentItem, type: :model do
  let(:account) { create(:account) }
  let(:plan)    { create(:treatment_plan, account: account) }

  describe 'validations' do
    it 'requires procedure_name' do
      item = build(:treatment_item, account: account, treatment_plan: plan, procedure_name: nil)
      expect(item).not_to be_valid
      expect(item.errors[:procedure_name]).to be_present
    end

    it 'requires sessions_planned > 0' do
      item = build(:treatment_item, account: account, treatment_plan: plan, sessions_planned: 0)
      expect(item).not_to be_valid
      expect(item.errors[:sessions_planned]).to be_present
    end

    it 'rejects discount_type fora do enum' do
      item = build(:treatment_item, account: account, treatment_plan: plan, discount_type: 'malabsurdo')
      expect(item).not_to be_valid
      expect(item.errors[:discount_type]).to be_present
    end

    it 'aceita discount_type vazio (sem desconto)' do
      item = build(:treatment_item, account: account, treatment_plan: plan, discount_type: '')
      expect(item).to be_valid
    end

    it 'rejeita percentual > 100' do
      item = build(:treatment_item,
                   account: account,
                   treatment_plan: plan,
                   discount_type: 'percentual',
                   discount_value: 150)
      expect(item).not_to be_valid
      expect(item.errors[:discount_value]).to be_present
    end

    it 'aceita percentual 0..100' do
      item = build(:treatment_item,
                   account: account,
                   treatment_plan: plan,
                   discount_type: 'percentual',
                   discount_value: 100)
      expect(item).to be_valid
    end

    it 'aceita fixo > 100 (não há cap em fixo, só em percentual)' do
      item = build(:treatment_item,
                   account: account,
                   treatment_plan: plan,
                   discount_type: 'fixo',
                   discount_value: 9_999)
      expect(item).to be_valid
    end
  end

  describe '#gross_subtotal' do
    it 'multiplica unit_price por sessions_planned' do
      item = build(:treatment_item, account: account, treatment_plan: plan,
                   unit_price: 100, sessions_planned: 3)
      expect(item.gross_subtotal).to eq(BigDecimal('300'))
    end

    it 'retorna 0 quando unit_price é nil' do
      item = build(:treatment_item, account: account, treatment_plan: plan, unit_price: nil)
      expect(item.gross_subtotal).to eq(BigDecimal('0'))
    end
  end

  describe '#discount_amount' do
    it 'retorna 0 quando discount_type vazio' do
      item = build(:treatment_item, account: account, treatment_plan: plan,
                   unit_price: 100, sessions_planned: 2, discount_type: nil, discount_value: 50)
      expect(item.discount_amount).to eq(BigDecimal('0'))
    end

    it 'calcula percentual sobre o subtotal bruto' do
      item = build(:treatment_item, account: account, treatment_plan: plan,
                   unit_price: 100, sessions_planned: 2, discount_type: 'percentual', discount_value: 10)
      # gross = 200; 10% = 20
      expect(item.discount_amount).to eq(BigDecimal('20'))
    end

    it 'aplica desconto fixo direto' do
      item = build(:treatment_item, account: account, treatment_plan: plan,
                   unit_price: 100, sessions_planned: 2, discount_type: 'fixo', discount_value: 30)
      expect(item.discount_amount).to eq(BigDecimal('30'))
    end

    it 'limita desconto fixo ao subtotal bruto (não vai negativo)' do
      item = build(:treatment_item, account: account, treatment_plan: plan,
                   unit_price: 100, sessions_planned: 1, discount_type: 'fixo', discount_value: 500)
      # gross = 100; min(500, 100) = 100
      expect(item.discount_amount).to eq(BigDecimal('100'))
    end
  end

  describe '#net_subtotal' do
    it 'subtrai desconto do bruto' do
      item = build(:treatment_item, account: account, treatment_plan: plan,
                   unit_price: 100, sessions_planned: 5, discount_type: 'percentual', discount_value: 20)
      # gross = 500; discount = 100; net = 400
      expect(item.net_subtotal).to eq(BigDecimal('400'))
    end

    it 'nunca retorna negativo' do
      item = build(:treatment_item, account: account, treatment_plan: plan,
                   unit_price: 100, sessions_planned: 1, discount_type: 'fixo', discount_value: 999)
      expect(item.net_subtotal).to eq(BigDecimal('0'))
    end
  end

  describe 'callback :calculate_total_price' do
    it 'persiste total_price = net_subtotal ao salvar' do
      item = create(:treatment_item, account: account, treatment_plan: plan,
                    unit_price: 200, sessions_planned: 3, discount_type: 'percentual', discount_value: 10)
      # gross = 600; 10% = 60; net = 540
      expect(item.reload.total_price).to eq(BigDecimal('540'))
    end

    it 'atualiza total_price ao mudar desconto' do
      item = create(:treatment_item, account: account, treatment_plan: plan,
                    unit_price: 100, sessions_planned: 2)
      expect(item.total_price).to eq(BigDecimal('200'))

      item.update!(discount_type: 'fixo', discount_value: 50)
      expect(item.reload.total_price).to eq(BigDecimal('150'))
    end
  end
end
