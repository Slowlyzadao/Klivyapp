require 'rails_helper'

# Cobre a migração legacy → Klivy RBAC na StickerPolicy.
# Inclui o caso especial dos stickers default (kind='default', account_id=nil)
# que são imutáveis pra qualquer role no nível policy.
RSpec.describe InternalChat::StickerPolicy, type: :policy do
  subject(:policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:other_agent) { create(:user, account: account) }

  # Stickers usam ActiveStorage pra imagem (has_one_attached :image) e não têm
  # validação obrigatória dela. Spec foca só na lógica de policy.
  let(:custom_sticker) do
    InternalChat::Sticker.create!(
      account: account,
      kind: 'account',
      name: 'flame',
      created_by_user_id: agent.id
    )
  end

  let(:default_sticker) do
    InternalChat::Sticker.create!(
      account_id: nil,
      kind: 'default',
      name: 'wave',
      category: 'bem_estar'
    )
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

  permissions :index?, :favorite?, :unfavorite? do
    it 'allows admin' do
      expect(policy).to permit(admin_context, custom_sticker)
    end

    it 'allows agent with internal_chat.view' do
      grant!(agent, 'internal_chat' => { 'view' => true })
      expect(policy).to permit(agent_context, custom_sticker)
    end

    it 'denies agent without internal_chat.view' do
      expect(policy).not_to permit(agent_context, custom_sticker)
    end
  end

  permissions :create? do
    it 'allows admin' do
      expect(policy).to permit(admin_context, custom_sticker)
    end

    it 'allows agent with internal_chat.manage_stickers' do
      grant!(agent, 'internal_chat' => { 'manage_stickers' => true })
      expect(policy).to permit(agent_context, custom_sticker)
    end

    it 'denies agent with only view' do
      grant!(agent, 'internal_chat' => { 'view' => true })
      expect(policy).not_to permit(agent_context, custom_sticker)
    end
  end

  permissions :destroy? do
    it 'allows admin to delete custom sticker' do
      expect(policy).to permit(admin_context, custom_sticker)
    end

    it 'denies admin to delete default sticker (immutable)' do
      expect(policy).not_to permit(admin_context, default_sticker)
    end

    it 'allows manage_stickers to delete any custom sticker (even from other user)' do
      grant!(other_agent, 'internal_chat' => { 'manage_stickers' => true })
      expect(policy).to permit(other_agent_context, custom_sticker)
    end

    it 'allows author to delete own custom sticker without manage_stickers' do
      grant!(agent, 'internal_chat' => { 'view' => true })
      expect(policy).to permit(agent_context, custom_sticker)
    end

    it 'denies non-author non-manage agent' do
      grant!(other_agent, 'internal_chat' => { 'view' => true })
      expect(policy).not_to permit(other_agent_context, custom_sticker)
    end

    it 'denies default sticker deletion even with manage_stickers' do
      grant!(other_agent, 'internal_chat' => { 'manage_stickers' => true })
      expect(policy).not_to permit(other_agent_context, default_sticker)
    end
  end
end
