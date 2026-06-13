require 'rails_helper'

# Bug #4 (auditoria 2026-05-30): SuperAdmin::AiAgentDocumentsController#destroy
# usava AiAgent::Document.find(id) GLOBAL — um super_admin operando na conta A
# conseguia apagar documento da conta B (e a auditoria registrava na conta errada).
# Corrigido para @account.documents_for_bea.find(id) — scoped, igual ao index.
#
# NB: rode com RAILS_ENV=test — em development o forgery protection (CSRF) está
# ligado e DELETEs de super_admin retornam 422 "Request rejected".
RSpec.describe 'SuperAdmin::AiAgentDocuments — isolamento por conta', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account_a)   { create(:account) }
  let(:account_b)   { create(:account) }
  let!(:doc_b) do
    # source_type 'url' + external_link satisfaz must_have_payload (sem anexar PDF real).
    AiAgent::Document.create!(
      account: account_b, name: 'doc da conta B',
      source_type: 'url', external_link: 'https://example.com/doc-b'
    )
  end

  it 'NÃO apaga documento de outra conta (id de B sob a URL da conta A)' do
    sign_in(super_admin, scope: :super_admin)
    begin
      delete "/super_admin/accounts/#{account_a.id}/ai_agent_documents/#{doc_b.id}"
    rescue ActiveRecord::RecordNotFound
      # Esperado com show_exceptions=:none — o contrato é NÃO apagar.
    end
    expect(AiAgent::Document.exists?(doc_b.id)).to be(true)
  end

  it 'apaga normalmente quando o id pertence à conta da URL' do
    sign_in(super_admin, scope: :super_admin)
    expect do
      delete "/super_admin/accounts/#{account_b.id}/ai_agent_documents/#{doc_b.id}"
    end.to change { AiAgent::Document.exists?(doc_b.id) }.from(true).to(false)
  end
end
