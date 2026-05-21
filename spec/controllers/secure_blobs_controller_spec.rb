require 'rails_helper'

RSpec.describe 'SecureBlobsController', type: :request do
  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }
  let(:user_a)    { create(:user, account: account_a) }
  let(:user_b)    { create(:user, account: account_b) }

  # Cria um blob de teste (não anexado) — só precisamos do ID + presença em
  # ActiveStorage::Blob pra o controller validar antes de redirecionar.
  let(:blob) do
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('hello'),
      filename: 'hello.txt',
      content_type: 'text/plain'
    )
  end

  let(:pdf_blob) do
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('%PDF-1.4 fake'),
      filename: 'doc.pdf',
      content_type: 'application/pdf'
    )
  end

  let(:valid_token) do
    Patients::SecureBlobTokenService.encode(blob_id: blob.id, account_id: account_a.id)
  end

  describe 'GET /secure_blobs/:token' do
    context 'when unauthenticated (no warden session)' do
      it 'returns 401 — controller bypassa Devise e lê warden session direto' do
        get "/secure_blobs/#{valid_token}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as a user from the same account as the token' do
      before { sign_in(user_a, scope: :user) }

      it 'redirects (302) to the storage backend URL' do
        get "/secure_blobs/#{valid_token}"
        expect(response).to have_http_status(:redirect)
        # blob.url retorna URL do backend de storage (disk em test → /rails/active_storage/disk/...).
        expect(response.location).to be_present
      end

      it 'returns 404 when the blob no longer exists' do
        deleted_token = Patients::SecureBlobTokenService.encode(blob_id: 999_999_999, account_id: account_a.id)
        get "/secure_blobs/#{deleted_token}"
        expect(response).to have_http_status(:not_found)
      end

      it 'streams PDFs same-origin via send_data (não redirect)' do
        pdf_token = Patients::SecureBlobTokenService.encode(blob_id: pdf_blob.id, account_id: account_a.id)
        get "/secure_blobs/#{pdf_token}"
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to start_with('application/pdf')
        expect(response.body).to eq('%PDF-1.4 fake')
      end
    end

    context 'cross-tenant: authenticated user belongs to a different account than the token' do
      before { sign_in(user_b, scope: :user) }

      it 'returns 403 (does NOT leak the blob)' do
        get "/secure_blobs/#{valid_token}"
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when token is expired' do
      before { sign_in(user_a, scope: :user) }

      it 'returns 410 Gone' do
        expired_token = Patients::SecureBlobTokenService.encode(
          blob_id: blob.id, account_id: account_a.id, expires_in: 1.second
        )
        travel_to(2.seconds.from_now) do
          get "/secure_blobs/#{expired_token}"
          expect(response).to have_http_status(:gone)
        end
      end
    end

    context 'when token is tampered' do
      before { sign_in(user_a, scope: :user) }

      it 'returns 422 Unprocessable Entity' do
        get "/secure_blobs/#{valid_token}-tampered"
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when token is malformed' do
      before { sign_in(user_a, scope: :user) }

      it 'returns 422 Unprocessable Entity' do
        get '/secure_blobs/totally-not-a-token'
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when user has access to multiple accounts including the token account' do
      let!(:account_user_b) { create(:account_user, account: account_a, user: user_b) }

      before { sign_in(user_b, scope: :user) }

      it 'allows access (account_users contains the token account_id)' do
        get "/secure_blobs/#{valid_token}"
        expect(response).to have_http_status(:redirect)
      end
    end
  end
end
