require 'rails_helper'

# Tenant isolation regression test pros endpoints user-facing do plugin
# ai_agent. Garante que um admin da Account A NÃO consegue ler/editar/destruir
# recursos que vivem na Account B, mesmo conhecendo o ID. Padrão: scope
# `Current.account.<assoc>.find(params[:id])` → 404 quando ID é de outro tenant.
#
# Cobertura:
#   - AiAgent::Document            (controllers/ai_agent/api/v1/accounts/documents)
#   - AiAgent::FollowUpRule        (controllers/ai_agent/api/v1/accounts/follow_up_rules)
#   - AiAgent::InternalNotificationTemplate
#                                  (controllers/ai_agent/api/v1/accounts/internal_notification_templates)
#
# Anti-pattern que este spec pega: alguém remover o filtro `Current.account.id`
# num controller e deixar `Model.find(params[:id])` sem scope → vazaria entre
# tenants. CI quebra antes de chegar em prod.

RSpec.describe 'Tenant isolation: AiAgent endpoints', type: :request do
  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }
  let(:admin_a)   { create(:user, account: account_a, role: :administrator) }
  let(:headers_a) { admin_a.create_new_auth_token }

  describe 'GET /api/v1/accounts/:id/ai_agent/documents/:document_id' do
    let!(:document_b) do
      AiAgent::Document.create!(
        account: account_b,
        name: 'doc-b',
        source_type: 'url',
        external_link: 'https://example.com/doc-b.pdf',
        status: 0
      )
    end

    it 'returns 404 when admin from account A tries to fetch document from account B by ID' do
      get "/api/v1/accounts/#{account_a.id}/ai_agent/documents/#{document_b.id}",
          headers: headers_a, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'does not include account B documents in account A index' do
      get "/api/v1/accounts/#{account_a.id}/ai_agent/documents",
          headers: headers_a, as: :json

      expect(response).to have_http_status(:success)
      ids = JSON.parse(response.body).dig('payload')&.map { |d| d['id'] } || []
      expect(ids).not_to include(document_b.id)
    end
  end

  describe 'AiAgent::FollowUpRule endpoints' do
    let!(:rule_b) do
      AiAgent::FollowUpRule.create!(
        account: account_b,
        name: 'B-only rule',
        trigger_type: 'pre_appointment',
        offset_hours: 24,
        offset_unit: 'hours',
        applies_to: 'both',
        context_brief: 'restricted'
      )
    end

    it 'GET show returns 404 across tenants' do
      get "/api/v1/accounts/#{account_a.id}/ai_agent/follow_up_rules/#{rule_b.id}",
          headers: headers_a, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'PUT update returns 404 across tenants (no data leak via params)' do
      put "/api/v1/accounts/#{account_a.id}/ai_agent/follow_up_rules/#{rule_b.id}",
          params: { follow_up_rule: { name: 'hijacked' } },
          headers: headers_a, as: :json

      expect(response).to have_http_status(:not_found)
      expect(rule_b.reload.name).to eq('B-only rule')
    end

    it 'DELETE returns 404 across tenants' do
      delete "/api/v1/accounts/#{account_a.id}/ai_agent/follow_up_rules/#{rule_b.id}",
             headers: headers_a, as: :json

      expect(response).to have_http_status(:not_found)
      expect(AiAgent::FollowUpRule.exists?(rule_b.id)).to be(true)
    end

    it 'index in account A scope does not leak rule_b' do
      get "/api/v1/accounts/#{account_a.id}/ai_agent/follow_up_rules",
          headers: headers_a, as: :json

      expect(response).to have_http_status(:success)
      ids = JSON.parse(response.body).map { |r| r['id'] }
      expect(ids).not_to include(rule_b.id)
    end
  end

  describe 'AiAgent::InternalNotificationTemplate endpoints' do
    # account_b é criado e a engine semeia 10 templates default automaticamente
    # via `Account.after_create_commit :seed_ai_agent_internal_notification_templates`.
    # Em vez de criar mais um (que colide no UNIQUE (account_id, event_key)),
    # reusamos um dos seedados pra testar isolamento.
    let!(:template_b) do
      AiAgent::InternalNotificationTemplate.where(account_id: account_b.id).first ||
        AiAgent::InternalNotificationTemplate.create!(
          account: account_b,
          event_key: 'tenant_isolation_test_event',
          name: 'B template',
          body: 'B body',
          target_type: 'disabled',
          enabled: false
        )
    end

    it 'GET show returns 404 across tenants' do
      get "/api/v1/accounts/#{account_a.id}/ai_agent/internal_notification_templates/#{template_b.id}",
          headers: headers_a, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'index does not leak across tenants' do
      get "/api/v1/accounts/#{account_a.id}/ai_agent/internal_notification_templates",
          headers: headers_a, as: :json

      expect(response).to have_http_status(:success)
      ids = JSON.parse(response.body).map { |t| t['id'] }
      expect(ids).not_to include(template_b.id)
    end
  end
end
