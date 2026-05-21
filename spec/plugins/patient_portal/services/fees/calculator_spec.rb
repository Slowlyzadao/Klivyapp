require 'rails_helper'

RSpec.describe PatientPortal::Fees::Calculator do
  describe '.compute' do
    it 'retorna 0 quando ambos vazios' do
      expect(described_class.compute(fixed_cents: nil, percent: nil, base_cents: 10_000)).to eq(0)
    end

    it 'usa fixed_cents quando positivo (mesmo com percent também setado — fixo vence)' do
      expect(described_class.compute(fixed_cents: 5_000, percent: 30, base_cents: 10_000)).to eq(5_000)
    end

    it 'usa percent quando fixed ausente' do
      expect(described_class.compute(fixed_cents: nil, percent: 25, base_cents: 20_000)).to eq(5_000)
    end

    it 'arredonda percent corretamente' do
      expect(described_class.compute(fixed_cents: nil, percent: 33.33, base_cents: 9_900)).to eq(3_300)
    end

    it 'retorna 0 se base_cents <= 0 mesmo com percent positivo' do
      expect(described_class.compute(fixed_cents: nil, percent: 50, base_cents: 0)).to eq(0)
    end

    it 'retorna 0 se percent <= 0' do
      expect(described_class.compute(fixed_cents: nil, percent: 0, base_cents: 10_000)).to eq(0)
      expect(described_class.compute(fixed_cents: nil, percent: -10, base_cents: 10_000)).to eq(0)
    end
  end
end
