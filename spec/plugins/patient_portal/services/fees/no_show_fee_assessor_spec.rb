require 'rails_helper'

RSpec.describe PatientPortal::Fees::NoShowFeeAssessor do
  let(:account)  { create(:account) }
  let(:contact)  { create(:contact, account: account) }
  let(:patient)  { create(:patient, account: account, contact_id: contact.id) }
  let(:setting) do
    PatientPortalSetting.create!(
      account: account, active_preset: 'autonomy_guided',
      financial: financial_settings
    )
  end

  let(:event) do
    OpenStruct.new(
      id: 99, status: status,
      account: account, contact_id: contact.id,
      user_id: nil, user: nil, agenda_service: nil
    )
  end

  before do
    setting
    patient # força criação pra que find_by encontre via contact_id
  end

  subject(:assessor) { described_class.new(event: event) }

  context 'evento ainda não está em no_show' do
    let(:status) { 'scheduled' }
    let(:financial_settings) { { 'no_show_auto_invoice' => true, 'no_show_fee_cents' => 6_000 } }

    it 'não cobra (reason=event_not_no_show)' do
      result = assessor.call
      expect(result.assessed?).to eq(false)
      expect(result.reason).to eq('event_not_no_show')
    end
  end

  context 'no_show com setting desligado' do
    let(:status) { 'no_show' }
    let(:financial_settings) { { 'no_show_auto_invoice' => false, 'no_show_fee_cents' => 6_000 } }

    it 'não cobra (reason=not_enabled)' do
      result = assessor.call
      expect(result.assessed?).to eq(false)
      expect(result.reason).to eq('not_enabled')
    end
  end

  context 'no_show com setting ligado e valor configurado' do
    let(:status) { 'no_show' }
    let(:financial_settings) { { 'no_show_auto_invoice' => true, 'no_show_fee_cents' => 6_000 } }

    it 'cria fee Budget + Installment' do
      result = assessor.call
      expect(result.assessed?).to eq(true)
      expect(result.fee_cents).to eq(6_000)
      expect(Financial::Installment.last.amount_cents).to eq(6_000)
    end

    it 'notifica paciente' do
      expect { assessor.call }.to change {
        PatientPortalNotification.where(patient_id: patient.id, kind: 'financial_charge').count
      }.by(1)
    end

    it 'é idempotente' do
      assessor.call
      expect {
        described_class.new(event: event).call
      }.not_to change { Financial::Budget.where(patient: patient).count }
    end
  end
end
