require 'rails_helper'

RSpec.describe 'Agenda Events API', type: :request do
  let(:account) { create(:account) }

  describe 'GET /api/v1/accounts/{account.id}/agenda_events' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/agenda_events"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }
      let!(:agenda_event) { create(:agenda_event, account: account, user: agent) }

      it 'returns all agenda events for agents' do
        get "/api/v1/accounts/#{account.id}/agenda_events",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body.length).to eq(1)
        expect(body.first[:title]).to eq(agenda_event.title)
      end

      it 'returns all agenda events for administrators' do
        get "/api/v1/accounts/#{account.id}/agenda_events",
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body.length).to eq(1)
      end

      it 'filters by user_id' do
        other_agent = create(:user, account: account, role: :agent)
        create(:agenda_event, account: account, user: other_agent)

        get "/api/v1/accounts/#{account.id}/agenda_events",
            params: { user_id: agent.id },
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body.length).to eq(1)
        expect(body.first[:user_id]).to eq(agent.id)
      end

      it 'filters by status' do
        create(:agenda_event, :confirmed, account: account)

        get "/api/v1/accounts/#{account.id}/agenda_events",
            params: { status: 'confirmed' },
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body.all? { |e| e[:status] == 'confirmed' }).to be true
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/agenda_events/:id' do
    let(:agenda_event) { create(:agenda_event, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/agenda_events/#{agenda_event.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'shows the agenda event' do
        get "/api/v1/accounts/#{account.id}/agenda_events/#{agenda_event.id}",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:id]).to eq(agenda_event.id)
        expect(body[:title]).to eq(agenda_event.title)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/agenda_events' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/agenda_events",
             params: { agenda_event: { title: 'Test' } },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:contact) { create(:contact, account: account) }

      it 'creates a new agenda event for agents' do
        event_params = {
          agenda_event: {
            title: 'Consulta Dr. Silva',
            description: 'Checkup anual',
            starts_at: 1.day.from_now.iso8601,
            ends_at: (1.day.from_now + 1.hour).iso8601,
            user_id: agent.id,
            contact_id: contact.id,
            status: 'scheduled',
            event_type: 'consultation'
          }
        }

        post "/api/v1/accounts/#{account.id}/agenda_events",
             params: event_params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:title]).to eq('Consulta Dr. Silva')
        expect(body[:status]).to eq('scheduled')
        expect(body[:contact][:id]).to eq(contact.id)
      end

      it 'returns error when title is missing' do
        post "/api/v1/accounts/#{account.id}/agenda_events",
             params: {
               agenda_event: {
                 starts_at: 1.day.from_now.iso8601,
                 ends_at: (1.day.from_now + 1.hour).iso8601,
                 user_id: agent.id,
                 contact_id: contact.id
               }
             },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns error when ends_at is before starts_at' do
        post "/api/v1/accounts/#{account.id}/agenda_events",
             params: {
               agenda_event: {
                 title: 'Test',
                 starts_at: 1.day.from_now.iso8601,
                 ends_at: (1.day.from_now - 1.hour).iso8601,
                 user_id: agent.id,
                 contact_id: contact.id
               }
             },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/agenda_events/:id' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let!(:agenda_event) { create(:agenda_event, account: account, user: agent) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/agenda_events/#{agenda_event.id}",
              params: { agenda_event: { title: 'Updated' } },
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'updates the agenda event for agents' do
        patch "/api/v1/accounts/#{account.id}/agenda_events/#{agenda_event.id}",
              params: { agenda_event: { title: 'Consulta Atualizada', status: 'confirmed' } },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:title]).to eq('Consulta Atualizada')
        expect(body[:status]).to eq('confirmed')
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/agenda_events/:id' do
    let!(:agenda_event) { create(:agenda_event, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/agenda_events/#{agenda_event.id}",
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unauthorized for agents' do
        delete "/api/v1/accounts/#{account.id}/agenda_events/#{agenda_event.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'deletes the agenda event for administrators' do
        delete "/api/v1/accounts/#{account.id}/agenda_events/#{agenda_event.id}",
               headers: administrator.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(AgendaEvent.exists?(agenda_event.id)).to be false
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/agenda_events/:id/telemedicine_token' do
    # Sprint K — admin-side: token LiveKit pro profissional responsável.
    # O service real (Telemed::SessionIssuer) precisa de
    # credenciais LiveKit; aqui mockamos a chamada e validamos só
    # autorização + estado do evento.
    #
    # Owner sai como `:administrator` (não `:agent`) pra contornar a falta
    # de klivy_role default nos factories de agent. A regra real testada é
    # `record.user_id == user.id` — funciona pra qualquer role contanto
    # que o user passe na permissão `:agenda, :view` (admin sempre passa).
    let(:owner) { create(:user, account: account, role: :administrator) }
    let(:starts_at) { 5.minutes.from_now }
    let(:event) do
      create(:agenda_event, :telemedicine,
             account: account, user: owner,
             starts_at: starts_at, ends_at: starts_at + 30.minutes)
    end

    let(:fake_session) do
      Telemed::SessionIssuer::Result.new(
        url: 'ws://localhost:7880', token: 'fake-jwt', room: 'klivy-acc1-event1',
        identity: 'doctor-1', name: 'Doutor', role: 'doctor',
        ttl_seconds: 600, dev_mode: true
      )
    end

    before do
      allow_any_instance_of(Telemed::SessionIssuer)
        .to receive(:call).and_return(fake_session)
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/agenda_events/#{event.id}/telemedicine_token"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the responsible professional requests the token' do
      it 'returns a LiveKit session payload' do
        post "/api/v1/accounts/#{account.id}/agenda_events/#{event.id}/telemedicine_token",
             headers: owner.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body.dig(:data, :token)).to eq('fake-jwt')
        expect(body.dig(:data, :room)).to eq('klivy-acc1-event1')
      end
    end

    context 'when another user (not the event owner) requests the token' do
      let(:other_agent) { create(:user, account: account, role: :agent) }

      it 'returns unauthorized — only the responsible professional can join' do
        post "/api/v1/accounts/#{account.id}/agenda_events/#{event.id}/telemedicine_token",
             headers: other_agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when admin (not owner) requests the token' do
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unauthorized even for admins — identity must match the dentist' do
        post "/api/v1/accounts/#{account.id}/agenda_events/#{event.id}/telemedicine_token",
             headers: administrator.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the event is not marked as telemedicine' do
      let(:event) { create(:agenda_event, account: account, user: owner) } # sem trait

      it 'returns 422 telemedicine_not_enabled' do
        post "/api/v1/accounts/#{account.id}/agenda_events/#{event.id}/telemedicine_token",
             headers: owner.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:code]).to eq('telemedicine_not_enabled')
      end
    end

    # 2026-05-19 — Google Meet pattern: doutor entra a qualquer hora.
    # Fora da janela retorna 200 + meta.outside_window=true (front mostra
    # "doutor entrou antes do horário" / segue normalmente).
    context 'when the event is far in the future (outside window)' do
      let(:starts_at) { 2.hours.from_now }

      it 'still emits a token but flags outside_window in meta' do
        post "/api/v1/accounts/#{account.id}/agenda_events/#{event.id}/telemedicine_token",
             headers: owner.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body.dig(:data, :token)).to eq('fake-jwt')
        expect(body.dig(:meta, :outside_window)).to eq(true)
        expect(body.dig(:meta, :reason)).to eq('too_early')
      end
    end

    context 'when the event is cancelled (permanent block)' do
      before { event.update!(status: 'cancelled') }

      it 'returns 422 event_not_joinable' do
        post "/api/v1/accounts/#{account.id}/agenda_events/#{event.id}/telemedicine_token",
             headers: owner.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:code]).to eq('event_not_joinable')
      end
    end
  end
end
