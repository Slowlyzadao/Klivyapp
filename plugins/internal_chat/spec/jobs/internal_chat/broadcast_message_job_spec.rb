require 'rails_helper'

# BE-4 (auditoria 2026-05-18): spec do InternalChat::BroadcastMessageJob.
# Cobre:
#   - Fan-out pra todos os membros ativos via user.pubsub_token
#   - Skip silencioso se message_id não existe (job em queue após delete)
#   - MT-20: usa scope .active (não .where(left_at: nil) hardcoded)
#   - left_at membros NÃO recebem broadcast
#   - Mention broadcast extra pros usuários mencionados
#   - Mention.created event com account_id + room_id (multi-tenant guard frontend)
RSpec.describe InternalChat::BroadcastMessageJob do
  let(:account) { create(:account) }
  let(:sender) { create(:user, account: account) }
  let(:member) { create(:user, account: account) }
  let(:room) { InternalChat::Room.create!(account: account, kind: 'group', name: 'Test') }

  before do
    InternalChat::Membership.create!(room: room, user_id: sender.id, role: 'member')
    InternalChat::Membership.create!(room: room, user_id: member.id, role: 'member')
  end

  describe '#perform' do
    let(:message) do
      InternalChat::Message.create!(room: room, sender_user_id: sender.id, content: 'hello')
    end

    it 'faz broadcast pra TODOS os membros ativos (incluindo sender)' do
      expect(ActionCable.server).to receive(:broadcast).with(sender.pubsub_token, hash_including(event: 'internal_chat.message.created'))
      expect(ActionCable.server).to receive(:broadcast).with(member.pubsub_token, hash_including(event: 'internal_chat.message.created'))

      described_class.new.perform(message.id)
    end

    it 'skip silencioso se message não existe (race: deletada após enqueue)' do
      expect(ActionCable.server).not_to receive(:broadcast)
      described_class.new.perform(999_999_999)
    end

    it 'inclui MessageSerializer payload no data' do
      allow(ActionCable.server).to receive(:broadcast)
      described_class.new.perform(message.id)

      expect(ActionCable.server).to have_received(:broadcast).at_least(:once) do |_token, payload|
        expect(payload[:event]).to eq('internal_chat.message.created')
        expect(payload[:data]).to include(id: message.id, content: 'hello')
      end
    end
  end

  describe '#perform (MT-20: scope .active)' do
    let(:left_member) { create(:user, account: account) }
    let(:message) do
      InternalChat::Message.create!(room: room, sender_user_id: sender.id, content: 'hi')
    end

    before do
      # Membro que saiu (left_at NOT NULL) NÃO deveria receber broadcast
      InternalChat::Membership.create!(room: room, user_id: left_member.id, role: 'member', left_at: 1.day.ago)
    end

    it 'NÃO broadcasta pro membro que saiu da sala' do
      expect(ActionCable.server).not_to receive(:broadcast).with(left_member.pubsub_token, anything)
      allow(ActionCable.server).to receive(:broadcast) # permite outras chamadas

      described_class.new.perform(message.id)
    end

    it 'broadcasta pros membros ativos restantes' do
      allow(ActionCable.server).to receive(:broadcast)
      described_class.new.perform(message.id)

      expect(ActionCable.server).to have_received(:broadcast).with(sender.pubsub_token, anything)
      expect(ActionCable.server).to have_received(:broadcast).with(member.pubsub_token, anything)
    end
  end

  describe '#perform (mention broadcast)' do
    let(:message) do
      InternalChat::Message.create!(room: room, sender_user_id: sender.id, content: "@#{member.available_name}")
    end

    before do
      # Cria mention de `member`
      InternalChat::Mention.create!(
        message_id: message.id, user_id: member.id, account_id: account.id
      )
    end

    it 'envia message.created + mention.created pro user mencionado' do
      received = []
      allow(ActionCable.server).to receive(:broadcast) do |token, payload|
        received << { token: token, event: payload[:event] }
      end

      described_class.new.perform(message.id)

      member_events = received.select { |r| r[:token] == member.pubsub_token }.map { |r| r[:event] }
      expect(member_events).to include('internal_chat.message.created', 'internal_chat.mention.created')
    end

    it 'envia SÓ message.created pra membros NÃO mencionados (não duplica)' do
      received = []
      allow(ActionCable.server).to receive(:broadcast) do |token, payload|
        received << { token: token, event: payload[:event] }
      end

      described_class.new.perform(message.id)

      sender_events = received.select { |r| r[:token] == sender.pubsub_token }.map { |r| r[:event] }
      expect(sender_events).to eq(['internal_chat.message.created']) # sem mention
    end

    it 'mention.created payload inclui account_id (multi-tenant guard frontend ActionCableConnector)' do
      received_mention = nil
      allow(ActionCable.server).to receive(:broadcast) do |_token, payload|
        received_mention = payload if payload[:event] == 'internal_chat.mention.created'
      end

      described_class.new.perform(message.id)

      expect(received_mention[:data][:account_id]).to eq(account.id)
      expect(received_mention[:data][:room_id]).to eq(room.id)
      expect(received_mention[:data][:message_id]).to eq(message.id)
    end
  end

  describe '#perform (memberships com user_id nil — Bea/AI)' do
    let(:ai_membership_room) do
      InternalChat::Room.create!(account: account, kind: 'group', name: 'AI Room').tap do |r|
        InternalChat::Membership.create!(room: r, user_id: sender.id, role: 'member')
        # Membership da Bea (sem user_id, só ai_agent_id) — não deve receber broadcast
        # NOTE: ai_agent_id pode ser nil em test simples; só checamos que user_id nil é skipado
      end
    end

    let(:message) do
      InternalChat::Message.create!(room: ai_membership_room, sender_user_id: sender.id, content: 'hi')
    end

    it 'NÃO tenta broadcastar pra membership sem user_id (AI agent)' do
      # Adiciona membership AI (user_id nil) diretamente
      ai_membership_room.memberships.create!(ai_agent_id: 1, role: 'member', user_id: nil)

      allow(ActionCable.server).to receive(:broadcast)
      described_class.new.perform(message.id)

      # Sender é o único user real — só ele recebe
      expect(ActionCable.server).to have_received(:broadcast).with(sender.pubsub_token, anything).at_least(:once)
      # Não tenta broadcast pra nil/AI pubsub_token (que daria NoMethodError)
    end
  end
end
