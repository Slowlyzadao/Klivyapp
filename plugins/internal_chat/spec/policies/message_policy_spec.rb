require 'rails_helper'

# Cobre migração legacy → Klivy na MessagePolicy. Foco no feature gate
# (`internal_chat.view`) + ownership (autor edita/deleta a própria msg).
RSpec.describe InternalChat::MessagePolicy, type: :policy do
  subject(:policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:other_agent) { create(:user, account: account) }
  let(:room) do
    InternalChat::Room.create!(account: account, kind: 'group', name: 'Room')
  end
  let(:message) do
    InternalChat::Message.create!(room: room, sender_user_id: agent.id, content: 'hi')
  end

  let(:admin_context) do
    { user: administrator, account: account, account_user: account.account_users.find_by(user: administrator) }
  end
  let(:agent_context) do
    { user: agent, account: account, account_user: account.account_users.find_by(user: agent) }
  end
  let(:other_agent_context) do
    { user: other_agent, account: account, account_user: account.account_users.find_by(user: other_agent) }
  end

  def grant!(user_arg, perms)
    role = KlivyRole.create!(account: account, name: "test-#{SecureRandom.hex(4)}", permissions: perms)
    account.account_users.find_by(user: user_arg).update!(klivy_role: role)
  end

  def add_member!(user_arg)
    InternalChat::Membership.create!(room: room, user_id: user_arg.id, role: 'member')
  end

  permissions :index?, :create? do
    it 'allows admin' do
      expect(policy).to permit(admin_context, message)
    end

    it 'allows member with internal_chat.view' do
      grant!(agent, 'internal_chat' => { 'view' => true })
      add_member!(agent)
      expect(policy).to permit(agent_context, message)
    end

    it 'denies non-member even with view' do
      grant!(other_agent, 'internal_chat' => { 'view' => true })
      expect(policy).not_to permit(other_agent_context, message)
    end

    it 'denies member without view (feature gate)' do
      add_member!(agent)
      expect(policy).not_to permit(agent_context, message)
    end
  end

  permissions :update?, :destroy? do
    it 'allows admin even on others message' do
      expect(policy).to permit(admin_context, message)
    end

    it 'allows author with internal_chat.view' do
      grant!(agent, 'internal_chat' => { 'view' => true })
      expect(policy).to permit(agent_context, message)
    end

    it 'denies non-author member' do
      grant!(other_agent, 'internal_chat' => { 'view' => true })
      add_member!(other_agent)
      expect(policy).not_to permit(other_agent_context, message)
    end
  end
end
