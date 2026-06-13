require 'rails_helper'

# Tenant isolation regression test pros endpoints user-facing do plugin
# internal_chat. Garante que um admin da Account A NÃO acessa Rooms/Messages
# da Account B, mesmo conhecendo IDs.
#
# Padrão: controllers usam `Current.account.internal_chat_rooms.find(...)` —
# o scope vem da `has_many :internal_chat_rooms` no Account.class_eval da
# engine. Messages/Memberships/Mentions scopam transitivamente via
# `room_id IN (Current.account.internal_chat_rooms.select(:id))`.

RSpec.describe 'Tenant isolation: InternalChat endpoints', type: :request do
  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }
  let(:admin_a)   { create(:user, account: account_a, role: :administrator) }
  let(:headers_a) { admin_a.create_new_auth_token }

  describe 'InternalChat::Room endpoints' do
    let!(:room_b) do
      InternalChat::Room.create!(
        account: account_b,
        kind: 'group',
        name: 'B-only group'
      )
    end

    it 'GET show returns 404 when admin from A tries to fetch room from B' do
      get "/api/v1/accounts/#{account_a.id}/internal_chat/rooms/#{room_b.id}",
          headers: headers_a, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'PATCH archive returns 404 across tenants' do
      patch "/api/v1/accounts/#{account_a.id}/internal_chat/rooms/#{room_b.id}/archive",
            headers: headers_a, as: :json

      expect(response).to have_http_status(:not_found)
      expect(room_b.reload.archived_at).to be_nil
    end

    it 'DELETE returns 404 across tenants' do
      delete "/api/v1/accounts/#{account_a.id}/internal_chat/rooms/#{room_b.id}",
             headers: headers_a, as: :json

      expect(response).to have_http_status(:not_found)
      expect(InternalChat::Room.exists?(room_b.id)).to be(true)
    end

    it 'index in account A does not list account B rooms' do
      get "/api/v1/accounts/#{account_a.id}/internal_chat/rooms",
          headers: headers_a, as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      ids = (body['data'] || body).map { |r| r['id'] }
      expect(ids).not_to include(room_b.id)
    end
  end

  describe 'InternalChat::Message endpoints (transitive scope via room)' do
    let(:user_b) { create(:user, account: account_b, role: :administrator) }
    let!(:room_b) do
      InternalChat::Room.create!(
        account: account_b,
        kind: 'group',
        name: 'B-only group',
        created_by_user_id: user_b.id
      )
    end
    let!(:membership_b) do
      InternalChat::Membership.create!(
        room: room_b,
        user_id: user_b.id,
        role: 'owner'
      )
    end
    let!(:message_b) do
      InternalChat::Message.create!(
        room: room_b,
        sender_user_id: user_b.id,
        content: 'secret from B'
      )
    end

    it 'GET index returns 404 when admin A queries messages of room B' do
      get "/api/v1/accounts/#{account_a.id}/internal_chat/rooms/#{room_b.id}/messages",
          headers: headers_a, as: :json

      # Aqui esperamos 404 (room não encontrado no scope da account A) — não
      # 403, porque o controller resolve a room ANTES de chegar na policy.
      expect(response).to have_http_status(:not_found)
    end
  end
end
