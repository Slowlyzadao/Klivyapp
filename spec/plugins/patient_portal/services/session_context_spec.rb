require 'rails_helper'

RSpec.describe PatientPortal::SessionContext do
  let(:account)     { create(:account) }
  let(:responsible) { create(:patient, account: account, name: 'João Pai') }
  let(:child1)      { create(:patient, account: account, name: 'Maria Filha') }
  let(:child2)      { create(:patient, account: account, name: 'Pedro Filho') }

  let(:session) do
    PatientPortalSession.create!(
      account: account, patient: responsible, active_patient_id: responsible.id,
      jwt_jti: SecureRandom.hex(8), expires_at: 7.days.from_now
    )
  end

  subject(:ctx) { described_class.new(session: session) }

  describe '#resolve' do
    context 'sem dependentes' do
      it 'retorna apenas o self em accessible_patients' do
        result = ctx.resolve
        expect(result.acting_patient).to eq(responsible)
        expect(result.active_patient).to eq(responsible)
        expect(result.accessible_patients).to contain_exactly(responsible)
        expect(result.acting_on_dependent?).to eq(false)
      end
    end

    context 'com dependentes ativos' do
      before do
        PatientResponsibleLink.create!(account: account, responsible: responsible, dependent: child1, role: 'parent')
        PatientResponsibleLink.create!(account: account, responsible: responsible, dependent: child2, role: 'parent')
      end

      it 'inclui self + dependentes' do
        result = ctx.resolve
        expect(result.accessible_patients.map(&:id)).to contain_exactly(responsible.id, child1.id, child2.id)
      end

      it 'ignora vínculos revogados' do
        PatientResponsibleLink.for_responsible(responsible).for_dependent(child1).first.revoke!
        result = ctx.resolve
        expect(result.accessible_patients.map(&:id)).to contain_exactly(responsible.id, child2.id)
      end
    end

    context 'sessão com active_patient_id != patient_id' do
      before do
        PatientResponsibleLink.create!(account: account, responsible: responsible, dependent: child1, role: 'parent')
        session.update!(active_patient_id: child1.id)
      end

      it 'expõe child1 como active e responsible como acting' do
        result = ctx.resolve
        expect(result.acting_patient.id).to eq(responsible.id)
        expect(result.active_patient.id).to eq(child1.id)
        expect(result.acting_on_dependent?).to eq(true)
      end

      it 'serializa is_self corretamente no payload' do
        payload = ctx.resolve.to_h
        self_entry = payload[:accessible].find { |p| p[:id] == responsible.id }
        dep_entry  = payload[:accessible].find { |p| p[:id] == child1.id }
        expect(self_entry[:is_self]).to eq(true)
        expect(dep_entry[:is_self]).to  eq(false)
      end
    end
  end

  describe '#can_act_on?' do
    let!(:link) { PatientResponsibleLink.create!(account: account, responsible: responsible, dependent: child1, role: 'parent') }

    it 'true para self' do
      expect(ctx.can_act_on?(responsible)).to eq(true)
    end

    it 'true para dependente ativo' do
      expect(ctx.can_act_on?(child1)).to eq(true)
    end

    it 'false para paciente não-vinculado' do
      stranger = create(:patient, account: account)
      expect(ctx.can_act_on?(stranger)).to eq(false)
    end

    it 'false para dependente revogado' do
      link.revoke!
      expect(ctx.can_act_on?(child1)).to eq(false)
    end

    it 'false para nil' do
      expect(ctx.can_act_on?(nil)).to eq(false)
    end
  end
end
