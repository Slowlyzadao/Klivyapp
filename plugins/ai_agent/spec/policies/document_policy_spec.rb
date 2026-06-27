require 'rails_helper'

# Cobre a migração Pundit legacy → Klivy RBAC na DocumentPolicy.
# Garante que admin segue com bypass, e non-admin só consegue criar/destruir
# se tiver `captain.manage_documents` no KlivyRole. View precisa de
# `captain.view`.
RSpec.describe AiAgent::DocumentPolicy, type: :policy do
  subject(:policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:document) do
    AiAgent::Document.create!(
      account: account,
      name: 'doc',
      source_type: 'url',
      external_link: 'https://example.com/doc.pdf'
    )
  end

  let(:admin_context) do
    { user: administrator, account: account, account_user: account.account_users.find_by(user: administrator) }
  end
  let(:agent_context) do
    { user: agent, account: account, account_user: account.account_users.find_by(user: agent) }
  end

  def grant!(user_arg, perms)
    role = KlivyRole.create!(account: account, name: "test-#{SecureRandom.hex(4)}", permissions: perms)
    account.account_users.find_by(user: user_arg).update!(klivy_role: role)
  end

  permissions :index?, :show? do
    it 'allows administrator unconditionally' do
      expect(policy).to permit(admin_context, document)
    end

    it 'allows agent with captain.view granted' do
      grant!(agent, 'captain' => { 'view' => true })
      expect(policy).to permit(agent_context, document)
    end

    it 'denies agent without captain.view' do
      expect(policy).not_to permit(agent_context, document)
    end
  end

  permissions :create?, :destroy? do
    it 'allows administrator unconditionally' do
      expect(policy).to permit(admin_context, document)
    end

    it 'allows agent with captain.manage_documents granted' do
      grant!(agent, 'captain' => { 'manage_documents' => true })
      expect(policy).to permit(agent_context, document)
    end

    it 'denies agent with only captain.view (cannot mutate)' do
      grant!(agent, 'captain' => { 'view' => true })
      expect(policy).not_to permit(agent_context, document)
    end

    it 'denies agent without any captain perm' do
      expect(policy).not_to permit(agent_context, document)
    end
  end
end
