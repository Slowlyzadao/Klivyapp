# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public::Api::V1::SessionLogSignatures', type: :request do
  let(:account)      { create(:account) }
  let(:patient)      { create(:patient, account: account) }
  let(:professional) { create(:user, account: account) }

  let(:log) do
    create(:session_log, :with_remote_token,
           account: account, patient: patient, professional: professional,
           procedure_name: 'Limpeza de Pele')
  end

  let(:base_path) { '/public/api/v1/session_log_signatures' }
  let(:valid_blob) { 'data:image/webp;base64,UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA' }

  describe 'GET /:remote_token (show)' do
    it 'returns minimal metadata without auth' do
      get "#{base_path}/#{log.patient_signature_remote_token}"

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:patient_name]).to eq(patient.name)
      expect(body[:procedure_name]).to eq('Limpeza de Pele')
      expect(body[:already_signed]).to be false
      expect(body[:expires_at]).to be_present
    end

    it 'returns 404 for invalid token' do
      get "#{base_path}/abc123"
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 410 Gone when link expired' do
      log.update_columns(patient_signature_remote_link_expires_at: 1.minute.ago)
      get "#{base_path}/#{log.patient_signature_remote_token}"
      expect(response).to have_http_status(:gone)
    end

    it 'returns 400 when token blank' do
      get "#{base_path}/%20"
      expect(response).to have_http_status(:not_found).or have_http_status(:bad_request)
    end
  end

  describe 'PATCH /:remote_token (update — signing)' do
    before { allow(Patients::PatientTimelineEventJob).to receive(:perform_later) }

    it 'records the signature with mode remote_link' do
      patch "#{base_path}/#{log.patient_signature_remote_token}",
            params: { signature: valid_blob, device_info: 'Mozilla/5.0' },
            as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:success]).to be true
      expect(body[:signed_at]).to be_present

      log.reload
      expect(log.patient_signed?).to be true
      expect(log.patient_signature_mode).to eq('remote_link')
      # Token is invalidated
      expect(log.patient_signature_remote_token).to be_nil
    end

    it 'rejects already-signed session' do
      patch "#{base_path}/#{log.patient_signature_remote_token}",
            params: { signature: valid_blob }, as: :json

      # Token foi invalidado — segunda tentativa não acha
      old_token = log.patient_signature_remote_token
      patch "#{base_path}/#{old_token}",
            params: { signature: valid_blob }, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 410 when link expired' do
      log.update_columns(patient_signature_remote_link_expires_at: 1.minute.ago)
      patch "#{base_path}/#{log.patient_signature_remote_token}",
            params: { signature: valid_blob }, as: :json
      expect(response).to have_http_status(:gone)
    end

    it 'rejects empty signature' do
      patch "#{base_path}/#{log.patient_signature_remote_token}",
            params: { signature: '' }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'security: no auth required, only token' do
    it 'works without any session/cookie' do
      # Garante que não há leak: token correto = OK; token errado = 404.
      get "#{base_path}/#{log.patient_signature_remote_token}"
      expect(response).to have_http_status(:success)
    end
  end
end
