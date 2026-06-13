require 'rails_helper'

# Cobre a migração Pundit legacy → Klivy RBAC na RoomPolicy.
# Estrutura: 2 camadas — feature gate (internal_chat.view) + membership.
RSpec.describe InternalChat::RoomPolicy, type: :policy do
  subject(:policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:owner) { create(:user, account: account) }
  let(:room) do
    InternalChat::Room.create!(
      account: account,
      kind: 'group',
      name: 'Recepção',
      created_by_user_id: owner.id
    )
  end

  let(:admin_context) do
    { user: administrator, account: account, account_user: account.account_users.find_by(user: administrator) }
  end
  let(:agent_context) do
    { user: agent, account: account, account_user: account.account_users.find_by(user: agent) }
  end
  let(:owner_context) do
    { user: owner, account: account, account_user: account.account_users.find_by(user: owner) }
  end

  def grant!(user_arg, perms)
    role = KlivyRole.create!(account: account, name: "test-#{SecureRandom.hex(4)}", permissions: perms)
    account.account_users.find_by(user: user_arg).update!(klivy_role: role)
  end

  def add_member!(user_arg, role:)
    InternalChat::Membership.create!(room: room, user_id: user_arg.id, role: role)
  end

  permissions :index? do
    it 'allows admin unconditionally' do
      expect(policy).to permit(admin_context, room)
    end

    it 'allows agent with internal_chat.view' do
      grant!(agent, 'internal_chat' => { 'view' => true })
      expect(policy).to permit(agent_context, room)
    end

    it 'denies agent without internal_chat.view' do
      expect(policy).not_to permit(agent_context, room)
    end
  end

  permissions :create? do
    it 'allows admin' do
      expect(policy).to permit(admin_context, room)
    end

    it 'allows agent with internal_chat.create_room' do
      grant!(agent, 'internal_chat' => { 'create_room' => true })
      expect(policy).to permit(agent_context, room)
    end

    it 'denies agent with only internal_chat.view (cannot create rooms)' do
      grant!(agent, 'internal_chat' => { 'view' => true })
      expect(policy).not_to permit(agent_context, room)
    end
  end

  permissions :show? do
    it 'allows admin even without membership' do
      expect(policy).to permit(admin_context, room)
    end

    it 'denies agent with internal_chat.view but not member' do
      grant!(agent, 'internal_chat' => { 'view' => true })
      expect(policy).not_to permit(agent_context, room)
    end

    it 'allows agent member with internal_chat.view' do
      grant!(agent, 'internal_chat' => { 'view' => true })
      add_member!(agent, role: 'member')
      expect(policy).to permit(agent_context, room)
    end

    it 'denies even member without internal_chat.view (feature off via role)' do
      add_member!(agent, role: 'member')
      expect(policy).not_to permit(agent_context, room)
    end
  end

  permissions :update?, :archive? do
    it 'allows admin' do
      expect(policy).to permit(admin_context, room)
    end

    it 'allows member with role=owner + internal_chat.view' do
      grant!(agent, 'internal_chat' => { 'view' => true })
      add_member!(agent, role: 'owner')
      expect(policy).to permit(agent_context, room)
    end

    it 'denies regular member' do
      grant!(agent, 'internal_chat' => { 'view' => true })
      add_member!(agent, role: 'member')
      expect(policy).not_to permit(agent_context, room)
    end
  end

  permissions :destroy? do
    it 'allows admin' do
      expect(policy).to permit(admin_context, room)
    end

    it 'allows the creator with internal_chat.view' do
      grant!(owner, 'internal_chat' => { 'view' => true })
      expect(policy).to permit(owner_context, room)
    end

    it 'denies non-creator even with manage perms' do
      grant!(agent, 'internal_chat' => { 'view' => true, 'create_room' => true })
      add_member!(agent, role: 'owner')
      expect(policy).not_to permit(agent_context, room)
    end
  end
end
