# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'SessionLogs API', type: :request do
  let!(:account)      { create(:account) }
  let!(:patient)      { create(:patient, account: account) }
  let!(:professional) { create(:user, account: account) }
  let!(:admin)        { create(:user, account: account, role: 'administrator') }

  let(:base_path) { "/api/v1/accounts/#{account.id}/patients/#{patient.id}/session_logs" }

  describe 'GET /index' do
    context 'unauthenticated' do
      it 'returns unauthorized' do
        get base_path
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'authenticated as admin' do
      it 'returns all session logs of the patient' do
        create(:session_log, account: account, patient: patient, professional: professional)
        create(:session_log, account: account, patient: patient, professional: professional)

        get base_path, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'POST /' do
    let(:valid_payload) do
      {
        session_log: {
          performed_at: Time.current.iso8601,
          procedure_name: 'Limpeza de Pele',
          complaint_of_day: 'Oleosidade',
          assessment: 'Pele oleosa',
          duration_minutes: 30
        }
      }
    end

    it 'creates a session log as admin' do
      expect {
        post base_path, params: valid_payload,
             headers: admin.create_new_auth_token, as: :json
      }.to change(SessionLog, :count).by(1)

      expect(response).to have_http_status(:created)
      sl = SessionLog.last
      expect(sl.procedure_name).to eq('Limpeza de Pele')
      expect(sl.complaint_of_day).to eq('Oleosidade')
      expect(sl.account_id).to eq(account.id)
      expect(sl.patient_id).to eq(patient.id)
    end

    it 'rejects request without authentication' do
      post base_path, params: valid_payload, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /:id (update)' do
    let!(:log) { create(:session_log, account: account, patient: patient, professional: professional) }

    it 'updates a draft session' do
      patch "#{base_path}/#{log.id}",
            params: { session_log: { complaint_of_day: 'Atualizada' } },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(log.reload.complaint_of_day).to eq('Atualizada')
    end

    it 'rejects update on signed sessions (forbidden via editable_by?)' do
      log.sign!(actor: admin)

      patch "#{base_path}/#{log.id}",
            params: { session_log: { complaint_of_day: 'Hack' } },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH /:id/sign' do
    let!(:log) { create(:session_log, account: account, patient: patient, professional: professional) }

    it 'signs a draft session' do
      patch "#{base_path}/#{log.id}/sign",
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(log.reload.status).to eq('signed')
      expect(log.signed_by_id).to eq(admin.id)
    end

    it 'fails on already-signed session' do
      log.sign!(actor: admin)

      patch "#{base_path}/#{log.id}/sign",
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH /:id/mark_erratum' do
    let!(:log) { create(:session_log, :signed, account: account, patient: patient, professional: professional) }

    it 'marks erratum with reason' do
      patch "#{base_path}/#{log.id}/mark_erratum",
            params: { reason: 'Lote informado errado' },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      log.reload
      expect(log.erratum_at).to be_present
      expect(log.erratum_reason).to eq('Lote informado errado')
    end

    it 'rejects empty reason' do
      patch "#{base_path}/#{log.id}/mark_erratum",
            params: { reason: '' },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejects erratum on draft session' do
      draft = create(:session_log, account: account, patient: patient, professional: professional)

      patch "#{base_path}/#{draft.id}/mark_erratum",
            params: { reason: 'qualquer' },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST /:id/sign_patient_locally' do
    let!(:log) { create(:session_log, account: account, patient: patient, professional: professional) }

    let(:valid_blob) { 'data:image/webp;base64,UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA' }

    before { allow(Patients::PatientTimelineEventJob).to receive(:perform_later) }

    it 'records patient signature' do
      post "#{base_path}/#{log.id}/sign_patient_locally",
           params: { signature: valid_blob, device_info: 'TestUA' },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      log.reload
      expect(log.patient_signed?).to be true
      expect(log.patient_signature_mode).to eq('local_tablet')
    end

    it 'rejects empty signature' do
      post "#{base_path}/#{log.id}/sign_patient_locally",
           params: { signature: '' },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'POST /:id/send_patient_remote_signature_link' do
    let!(:log) { create(:session_log, account: account, patient: patient, professional: professional) }

    it 'generates remote_token and 48h expiry' do
      post "#{base_path}/#{log.id}/send_patient_remote_signature_link",
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:remote_token]).to be_present
      expect(body[:remote_token].length).to eq(64)

      log.reload
      expect(log.patient_signature_remote_link_expires_at).to be_within(1.minute).of(48.hours.from_now)
    end
  end

  describe 'DELETE /:id' do
    it 'soft deletes a draft session' do
      log = create(:session_log, account: account, patient: patient, professional: professional)

      delete "#{base_path}/#{log.id}",
             headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
      expect(log.reload.deleted_at).to be_present
    end

    it 'forbids delete of signed session' do
      log = create(:session_log, :signed, account: account, patient: patient, professional: professional)

      delete "#{base_path}/#{log.id}",
             headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'cross-tenant isolation' do
    it '404s when patient belongs to a different account' do
      other_account = create(:account)
      other_patient = create(:patient, account: other_account)

      get "/api/v1/accounts/#{account.id}/patients/#{other_patient.id}/session_logs",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
