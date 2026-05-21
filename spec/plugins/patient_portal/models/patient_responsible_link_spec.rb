require 'rails_helper'

RSpec.describe PatientResponsibleLink do
  let(:account)     { create(:account) }
  let(:responsible) { create(:patient, account: account) }
  let(:dependent)   { create(:patient, account: account) }

  describe 'validations' do
    it 'exige role válido' do
      link = described_class.new(account: account, responsible: responsible, dependent: dependent, role: 'invalid')
      expect(link).to be_invalid
      expect(link.errors[:role]).to be_present
    end

    it 'rejeita responsável == dependente (self-link)' do
      link = described_class.new(account: account, responsible: responsible, dependent: responsible, role: 'guardian')
      expect(link).to be_invalid
      expect(link.errors[:base].join).to include('si mesmo')
    end

    it 'rejeita responsável e dependente de accounts diferentes' do
      other_account = create(:account)
      other_dependent = create(:patient, account: other_account)
      link = described_class.new(account: account, responsible: responsible, dependent: other_dependent, role: 'guardian')
      expect(link).to be_invalid
      expect(link.errors[:base].join).to include('mesma clínica')
    end

    it 'aceita link válido' do
      link = described_class.new(account: account, responsible: responsible, dependent: dependent, role: 'parent')
      expect(link).to be_valid
    end

    it 'enforça unicidade (responsável, dependente)' do
      described_class.create!(account: account, responsible: responsible, dependent: dependent, role: 'parent')
      dup = described_class.new(account: account, responsible: responsible, dependent: dependent, role: 'guardian')
      expect(dup).to be_invalid
    end
  end

  describe '#active?' do
    let(:link) { described_class.create!(account: account, responsible: responsible, dependent: dependent, role: 'parent') }

    it 'true por padrão (sem revoked, sem active_until)' do
      expect(link.active?).to eq(true)
    end

    it 'false após revoke!' do
      link.revoke!
      expect(link.reload.active?).to eq(false)
    end

    it 'false se active_until já passou' do
      link.update_columns(active_until: 1.day.ago)
      expect(link.reload.active?).to eq(false)
    end

    it 'false se active_from ainda no futuro' do
      link.update_columns(active_from: 1.day.from_now)
      expect(link.reload.active?).to eq(false)
    end
  end

  describe '.active scope' do
    it 'inclui apenas vínculos válidos' do
      a = described_class.create!(account: account, responsible: responsible, dependent: dependent, role: 'parent')
      b_dep = create(:patient, account: account)
      b = described_class.create!(account: account, responsible: responsible, dependent: b_dep, role: 'parent')
      b.revoke!

      ids = described_class.active.for_responsible(responsible).pluck(:id)
      expect(ids).to contain_exactly(a.id)
    end
  end
end
