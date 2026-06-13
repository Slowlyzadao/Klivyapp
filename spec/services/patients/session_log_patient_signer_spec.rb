# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Patients::SessionLogPatientSigner do
  let(:account) { create(:account) }
  let(:patient) { create(:patient, account: account) }
  let(:actor)   { create(:user, account: account) }
  let(:log)     { create(:session_log, account: account, patient: patient) }

  let(:valid_blob) { 'data:image/webp;base64,UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA' }

  describe '.call (modo local_tablet)' do
    it 'assina, anexa imagem e dispara timeline event' do
      expect(Patients::PatientTimelineEventJob).to receive(:perform_later).with(hash_including(
        event_type: 'session_log_patient_signed'
      ))

      result = described_class.call(
        session_log: log,
        mode: 'local_tablet',
        signature_blob: valid_blob,
        ip_address: '127.0.0.1',
        device_info: 'Mozilla/5.0',
        actor: actor
      )

      expect(result.success?).to be true
      log.reload
      expect(log.patient_signed?).to be true
      expect(log.patient_signature_mode).to eq('local_tablet')
      expect(log.patient_signature_image).to be_attached
    end
  end

  describe '.call (modo remote_link)' do
    let(:log) { create(:session_log, :with_remote_token, account: account, patient: patient) }

    it 'assina e invalida o token' do
      allow(Patients::PatientTimelineEventJob).to receive(:perform_later)

      result = described_class.call(
        session_log: log,
        mode: 'remote_link',
        signature_blob: valid_blob,
        ip_address: '127.0.0.1'
      )

      expect(result.success?).to be true
      expect(log.reload.patient_signature_remote_token).to be_nil
    end
  end

  describe 'validações' do
    it 'rejeita blob vazio' do
      result = described_class.call(
        session_log: log, mode: 'local_tablet',
        signature_blob: '', ip_address: '127.0.0.1'
      )
      expect(result.success?).to be false
      expect(result.error).to match(/obrigatória/)
    end

    it 'rejeita IP vazio' do
      result = described_class.call(
        session_log: log, mode: 'local_tablet',
        signature_blob: valid_blob, ip_address: ''
      )
      expect(result.success?).to be false
      expect(result.error).to match(/IP/)
    end

    it 'rejeita modo inválido' do
      result = described_class.call(
        session_log: log, mode: 'whatever',
        signature_blob: valid_blob, ip_address: '127.0.0.1'
      )
      expect(result.success?).to be false
      expect(result.error).to match(/Modo/)
    end

    it 'rejeita assinar duas vezes' do
      allow(Patients::PatientTimelineEventJob).to receive(:perform_later)
      described_class.call(
        session_log: log, mode: 'local_tablet',
        signature_blob: valid_blob, ip_address: '127.0.0.1'
      )

      result = described_class.call(
        session_log: log.reload, mode: 'local_tablet',
        signature_blob: valid_blob, ip_address: '127.0.0.1'
      )
      expect(result.success?).to be false
      expect(result.error).to match(/já foi assinada/)
    end
  end
end
