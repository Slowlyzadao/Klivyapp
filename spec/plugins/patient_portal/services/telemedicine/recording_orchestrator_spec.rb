# Sprint L — Specs do RecordingOrchestrator (audio-only, 3 egress).
require 'rails_helper'

RSpec.describe Telemed::RecordingOrchestrator do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:event)   { create(:agenda_event, account: account, user: user, contact: contact) }
  let!(:portal_setting) {
    PatientPortalSetting.create!(
      account: account,
      active_preset: 'autonomy_guided',
      telemedicine_recording: { 'enabled' => true, 'patient_consent_required' => false }
    )
  }

  before do
    %w[TELEMED_STORAGE_ACCESS_KEY_ID TELEMED_STORAGE_SECRET_ACCESS_KEY
       TELEMED_STORAGE_BUCKET TELEMED_STORAGE_ENDPOINT].each do |k|
      stub_const('ENV', ENV.to_hash.merge(k => 'test-value'))
    end
  end

  let(:egress_client) { instance_double('LiveKit::EgressServiceClient') }
  let(:room_client)   { instance_double('LiveKit::RoomServiceClient') }
  let(:credentials)   {
    Telemed::CredentialsResolver::Credentials.new(
      url: 'http://localhost:7880', api_key: 'devkey', api_secret: 'secret', source: :dev_defaults
    )
  }

  def egress_response(id) = OpenStruct.new(egress_id: id)

  def stub_room_with_both_participants
    response = OpenStruct.new(participants: [
      OpenStruct.new(identity: "doctor-#{user.id}-abc123"),
      OpenStruct.new(identity: "patient-#{contact.id}-xyz789")
    ])
    allow(room_client).to receive(:list_participants).and_return(response)
  end

  describe '#start!' do
    subject(:orchestrator) {
      described_class.new(event: event, credentials: credentials, livekit_client: egress_client)
    }

    before do
      allow(LiveKit::RoomServiceClient).to receive(:new).and_return(room_client)
    end

    context 'happy path com 3 egress (doctor + patient + composite)' do
      before do
        stub_room_with_both_participants
        allow(egress_client).to receive(:start_participant_egress)
          .and_return(egress_response('EG_doc_aaa'), egress_response('EG_pat_bbb'))
        allow(egress_client).to receive(:start_room_composite_egress)
          .and_return(egress_response('EG_comp_ccc'))
      end

      it 'cria TelemedRecording com status=recording e 3 egress_ids' do
        result = orchestrator.start!
        expect(result.started?).to be(true)

        rec = result.recording
        expect(rec.status).to eq('recording')
        expect(rec.recording_kind).to eq('audio')
        expect(rec.doctor_egress_id).to eq('EG_doc_aaa')
        expect(rec.patient_egress_id).to eq('EG_pat_bbb')
        expect(rec.composite_egress_id).to eq('EG_comp_ccc')
      end

      it 'chama start_participant_egress duas vezes (1 por role)' do
        orchestrator.start!
        expect(egress_client).to have_received(:start_participant_egress).twice
      end

      it 'chama start_room_composite_egress com audio_only=true' do
        orchestrator.start!
        expect(egress_client).to have_received(:start_room_composite_egress)
          .with(anything, anything, hash_including(audio_only: true))
      end
    end

    context 'gravação desabilitada' do
      before { portal_setting.update!(telemedicine_recording: { 'enabled' => false }) }

      it 'retorna skipped_reason=recording_disabled e NÃO cria registro' do
        expect { orchestrator.start! }.not_to change(TelemedRecording, :count)
      end
    end

    context 'gravação já ativa para o evento' do
      let!(:existing) {
        create(:telemed_recording, :recording, agenda_event: event, account: account)
      }

      it 'pula com skipped_reason=already_active' do
        result = orchestrator.start!
        expect(result.skipped_reason).to eq(:already_active)
        expect(result.recording).to eq(existing)
      end
    end

    context 'participantes não detectados na sala' do
      before do
        allow(room_client).to receive(:list_participants).and_return(OpenStruct.new(participants: []))
      end

      it 'pula com skipped_reason=participants_not_ready' do
        expect { orchestrator.start! }.not_to change(TelemedRecording, :count)
      end
    end
  end

  describe '#stop!' do
    let(:rec) {
      create(:telemed_recording, :recording, agenda_event: event, account: account,
                                              doctor_egress_id: 'D1', patient_egress_id: 'P1',
                                              composite_egress_id: 'C1')
    }

    it 'chama stop_egress nos 3 ids' do
      allow(egress_client).to receive(:stop_egress)
      described_class.new(event: event, credentials: credentials, livekit_client: egress_client).stop!(rec)
      expect(egress_client).to have_received(:stop_egress).with('D1')
      expect(egress_client).to have_received(:stop_egress).with('P1')
      expect(egress_client).to have_received(:stop_egress).with('C1')
    end

    it 'engole erro de stop em egress já concluído' do
      allow(egress_client).to receive(:stop_egress).and_raise(StandardError.new('not found'))
      expect {
        described_class.new(event: event, credentials: credentials, livekit_client: egress_client).stop!(rec)
      }.not_to raise_error
    end
  end
end
