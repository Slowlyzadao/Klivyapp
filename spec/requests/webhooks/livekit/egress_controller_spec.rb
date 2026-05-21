# Sprint L — Specs do webhook do LiveKit Egress (3 egress audio-only).
require 'rails_helper'

RSpec.describe 'Webhooks::Livekit::EgressController', type: :request do
  let(:api_key)    { 'test-livekit-key' }
  let(:api_secret) { 'test-livekit-secret' }

  before do
    stub_const('ENV', ENV.to_hash.merge('LIVEKIT_API_KEY' => api_key, 'LIVEKIT_API_SECRET' => api_secret))
  end

  def sign(body)
    sha = Base64.strict_encode64(Digest::SHA256.digest(body))
    JWT.encode({ iss: api_key, sha256: sha, exp: 10.minutes.from_now.to_i }, api_secret, 'HS256')
  end

  def post_event(payload)
    body = payload.to_json
    token = sign(body)
    post '/webhooks/livekit/egress',
         params: body,
         headers: { 'Authorization' => token, 'CONTENT_TYPE' => 'application/json' }
  end

  describe 'POST /webhooks/livekit/egress' do
    let!(:recording) {
      create(:telemed_recording, :recording,
             doctor_egress_id: 'EG_doctor_x',
             patient_egress_id: 'EG_patient_y',
             composite_egress_id: 'EG_composite_z')
    }

    it 'rejeita sem JWT' do
      post '/webhooks/livekit/egress', params: '{}', headers: { 'CONTENT_TYPE' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejeita com JWT inválido' do
      body = { event: 'egress_started', egressInfo: { egressId: 'EG_doctor_x' } }.to_json
      post '/webhooks/livekit/egress',
           params: body,
           headers: { 'Authorization' => sign('outro body'), 'CONTENT_TYPE' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'aceita egress_started válido e marca status=recording' do
      recording.update!(status: 'pending')
      post_event(event: 'egress_started', egressInfo: { egressId: 'EG_doctor_x' })
      expect(response).to have_http_status(:ok)
      expect(recording.reload.status).to eq('recording')
    end

    it 'em egress_ended de 1 só job, persiste storage_key mas mantém status=recording' do
      post_event(
        event: 'egress_ended',
        egressInfo: {
          egressId: 'EG_doctor_x',
          fileResults: [{ location: 'rec/doctor-temp.ogg', size: 100, duration: 5_000_000_000 }]
        }
      )
      expect(response).to have_http_status(:ok)
      rec = recording.reload
      expect(rec.doctor_audio_key).to eq('rec/doctor-temp.ogg')
      expect(rec.status).to eq('recording') # ainda esperando os outros 2
    end

    it 'quando os 3 egress terminaram, marca uploaded e enfileira TranscribeJob' do
      recording.update!(
        doctor_audio_key:    'rec/doctor-temp.ogg',
        patient_audio_key:   'rec/patient-temp.ogg'
      )
      expect {
        post_event(
          event: 'egress_ended',
          egressInfo: {
            egressId: 'EG_composite_z',
            fileResults: [{ location: 'rec/composite.ogg', size: 200, duration: 6_000_000_000 }]
          }
        )
      }.to have_enqueued_job(Telemed::TranscribeRecordingJob).with(recording.id)

      expect(recording.reload.status).to eq('uploaded')
      expect(recording.composite_audio_key).to eq('rec/composite.ogg')
    end

    it 'ignora egress_id desconhecido (200 OK)' do
      post_event(event: 'egress_ended', egressInfo: { egressId: 'EG_unknown' })
      expect(response).to have_http_status(:ok)
    end
  end
end
