# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Patients::BetaFeatureChecker do
  let(:account) { create(:account) }

  describe '.enabled?' do
    context 'account sem custom_attributes ou sem chave beta_features' do
      it 'retorna false' do
        expect(described_class.enabled?(account, 'financial_timeline_v2')).to be(false)
      end
    end

    context 'account com beta_features vazio' do
      before { account.update!(custom_attributes: { 'beta_features' => [] }) }

      it 'retorna false' do
        expect(described_class.enabled?(account, 'financial_timeline_v2')).to be(false)
      end
    end

    context 'account com a feature ligada' do
      before do
        account.update!(custom_attributes: { 'beta_features' => ['financial_timeline_v2'] })
      end

      it 'retorna true para a feature ativa' do
        expect(described_class.enabled?(account, 'financial_timeline_v2')).to be(true)
      end

      it 'aceita symbol como nome' do
        expect(described_class.enabled?(account, :financial_timeline_v2)).to be(true)
      end

      it 'retorna false para outra feature não listada' do
        expect(described_class.enabled?(account, 'inexistent_feature')).to be(false)
      end
    end

    context 'account com múltiplas features beta' do
      before do
        account.update!(custom_attributes: { 'beta_features' => %w[a financial_timeline_v2 b] })
      end

      it 'detecta a feature dentre múltiplas' do
        expect(described_class.enabled?(account, 'financial_timeline_v2')).to be(true)
      end
    end

    context 'feature em outra account (cross-tenant)' do
      let(:other_account) { create(:account) }

      before do
        other_account.update!(custom_attributes: { 'beta_features' => ['financial_timeline_v2'] })
      end

      it 'não vaza para account sem a flag' do
        expect(described_class.enabled?(account, 'financial_timeline_v2')).to be(false)
      end
    end

    context 'inputs inválidos' do
      it 'retorna false para account nil' do
        expect(described_class.enabled?(nil, 'financial_timeline_v2')).to be(false)
      end

      it 'retorna false para feature_name nil' do
        expect(described_class.enabled?(account, nil)).to be(false)
      end

      it 'retorna false para feature_name vazia' do
        expect(described_class.enabled?(account, '')).to be(false)
      end
    end
  end

  describe '.list_for' do
    it 'retorna [] para account sem beta_features' do
      expect(described_class.list_for(account)).to eq([])
    end

    it 'retorna lista normalizada como strings' do
      account.update!(custom_attributes: { 'beta_features' => [:financial_timeline_v2, 'other'] })

      expect(described_class.list_for(account)).to eq(%w[financial_timeline_v2 other])
    end

    it 'retorna [] para account nil' do
      expect(described_class.list_for(nil)).to eq([])
    end
  end
end
