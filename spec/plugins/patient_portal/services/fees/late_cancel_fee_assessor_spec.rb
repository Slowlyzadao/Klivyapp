require 'rails_helper'

RSpec.describe PatientPortal::Fees::LateCancelFeeAssessor do
  let(:account)  { create(:account) }
  let(:contact)  { create(:contact, account: account) }
  let(:patient)  { create(:patient, account: account, contact_id: contact.id) }
  let(:setting) do
    PatientPortalSetting.create!(
      account: account, active_preset: 'autonomy_guided',
      rescheduling: { 'cancel_window_hours' => 24 },
      financial: financial_settings
    )
  end

  # AgendaEvent stub mínimo — não precisamos do model real para testar a lógica.
  # contact_id é o Chatwoot Contact id (mesmo padrão que AgendaEvent real).
  let(:appointment) do
    OpenStruct.new(
      id: 42, starts_at: 12.hours.from_now,
      account: account, contact_id: contact.id,
      user_id: nil, user: nil, agenda_service: nil
    )
  end

  before do
    setting # força criação
    patient # força criação para que find_by encontre via contact_id
  end

  # Passa actor=patient para o controller-path (não depende do Contact↔Patient)
  subject(:assessor) { described_class.new(appointment: appointment, actor: patient) }

  context 'quando late_cancel_auto_invoice = false (default)' do
    let(:financial_settings) { { 'late_cancel_auto_invoice' => false, 'late_cancel_fee_cents' => 5_000 } }

    it 'não cobra (reason=not_enabled)' do
      expect {
        result = assessor.call
        expect(result.assessed?).to eq(false)
        expect(result.reason).to eq('not_enabled')
      }.not_to change { Financial::Budget.where(patient: patient).count }
    end
  end

  context 'quando habilitado mas cancelamento FORA da janela protegida' do
    let(:financial_settings) { { 'late_cancel_auto_invoice' => true, 'late_cancel_fee_cents' => 5_000 } }

    it 'não cobra (reason=cancel_outside_window)' do
      appointment.starts_at = 48.hours.from_now # > 24h
      result = assessor.call
      expect(result.assessed?).to eq(false)
      expect(result.reason).to eq('cancel_outside_window')
    end
  end

  context 'quando habilitado E cancelamento DENTRO da janela (12h < 24h)' do
    let(:financial_settings) { { 'late_cancel_auto_invoice' => true, 'late_cancel_fee_cents' => 5_000 } }

    it 'cria fee Budget + Installment de 50 reais' do
      result = assessor.call
      expect(result.assessed?).to eq(true)
      expect(result.fee_cents).to eq(5_000)
      expect(result.installment).to be_present
      expect(Financial::Installment.last.amount_cents).to eq(5_000)
    end

    it 'dispatcha notificação financial_charge' do
      expect { assessor.call }.to change {
        PatientPortalNotification.where(patient_id: patient.id, kind: 'financial_charge').count
      }.by(1)
      notif = PatientPortalNotification.where(patient_id: patient.id, kind: 'financial_charge').last
      expect(notif.payload['fee_kind']).to eq('late_cancel')
    end

    it 'é idempotente: 2ª chamada não duplica' do
      assessor.call
      expect {
        result = described_class.new(appointment: appointment, actor: patient).call
        expect(result.assessed?).to eq(true)
      }.not_to change { Financial::Budget.where(patient: patient).count }
    end
  end

  context 'amount calculado como 0' do
    let(:financial_settings) { { 'late_cancel_auto_invoice' => true, 'late_cancel_fee_cents' => 0, 'late_cancel_fee_percent' => 0 } }

    it 'pula com reason=amount_zero' do
      result = assessor.call
      expect(result.assessed?).to eq(false)
      expect(result.reason).to eq('amount_zero')
    end
  end
end
