require 'rails_helper'

RSpec.describe PatientPortal::OverdueRestrictionChecker do
  let(:account) { create(:account) }
  let(:patient) { create(:patient, account: account) }
  let(:setting) do
    PatientPortalSetting.create!(
      account: account, active_preset: 'autonomy_guided',
      financial: financial_settings
    )
  end

  before { setting }

  def create_overdue_installment(due_date:, amount_cents: 10_000)
    inst = build_paid_installment_target(account: account, patient: patient, amount_cents: amount_cents)
    inst.update_columns(due_date: due_date, competence_date: due_date, status: 'vencido')
    inst
  end

  subject(:checker) { described_class.new(account: account, patient: patient) }

  context 'paciente sem parcelas vencidas' do
    let(:financial_settings) { {} }

    it 'retorna level=none' do
      result = checker.call
      expect(result.level).to eq(:none)
      expect(result.restricted?).to eq(false)
    end
  end

  context 'paciente com vencidas, mas sem setting de bloqueio configurado' do
    let(:financial_settings) { {} } # default → warn only

    before { create_overdue_installment(due_date: 5.days.ago.to_date) }

    it 'retorna level=warn (sempre alerta)' do
      result = checker.call
      expect(result.level).to eq(:warn)
      expect(result.restricted?).to eq(true)
      expect(result.blocks_scheduling?).to eq(false)
      expect(result.days_overdue).to eq(5)
    end
  end

  context 'setting limit_scheduling após 30 dias' do
    let(:financial_settings) do
      { 'overdue_restriction_level' => 'limit_scheduling', 'block_portal_if_overdue_days' => 30 }
    end

    it 'antes de 30 dias retorna warn' do
      create_overdue_installment(due_date: 10.days.ago.to_date)
      expect(checker.call.level).to eq(:warn)
    end

    it 'após 30 dias retorna limit_scheduling' do
      create_overdue_installment(due_date: 45.days.ago.to_date)
      result = checker.call
      expect(result.level).to eq(:limit_scheduling)
      expect(result.blocks_scheduling?).to eq(true)
      expect(result.blocks_messaging?).to eq(false)
    end
  end

  context 'setting full_block após 60 dias' do
    let(:financial_settings) do
      { 'overdue_restriction_level' => 'full_block', 'block_portal_if_overdue_days' => 60 }
    end

    it 'após 90 dias retorna full_block' do
      create_overdue_installment(due_date: 90.days.ago.to_date)
      result = checker.call
      expect(result.level).to eq(:full_block)
      expect(result.full_blocked?).to eq(true)
      expect(result.blocks_messaging?).to eq(true)
      expect(result.blocks_scheduling?).to eq(true)
    end
  end

  context 'múltiplas parcelas vencidas — usa a mais antiga' do
    let(:financial_settings) do
      { 'overdue_restriction_level' => 'limit_messaging', 'block_portal_if_overdue_days' => 14 }
    end

    it 'days_overdue vem da parcela mais antiga; total soma todas' do
      create_overdue_installment(due_date: 20.days.ago.to_date, amount_cents: 10_000)
      create_overdue_installment(due_date: 3.days.ago.to_date,  amount_cents: 5_000)

      result = checker.call
      expect(result.days_overdue).to eq(20)
      expect(result.overdue_count).to eq(2)
      expect(result.overdue_total_cents).to eq(15_000)
      expect(result.level).to eq(:limit_messaging)
    end
  end
end
