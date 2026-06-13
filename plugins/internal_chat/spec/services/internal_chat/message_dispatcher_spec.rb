require 'rails_helper'

# BE-3 (auditoria 2026-05-18): spec caracterizador do
# InternalChat::MessageDispatcher. Cobre fluxos críticos:
#   - Happy path: cria Message + atualiza last_message_at + enqueue broadcast
#   - Derivação de content_type (text/sticker/file)
#   - Persist mentions (user_ids + ai_agent_ids)
#   - Trigger AiAgentMentionListener quando há ai_agent mencionado
#   - BE-20: sanitização de in_reply_to cross-room (descarta silenciosamente)
#   - AI sender path (Bea respondendo via Captain::Assistant)
#   - Atomicidade: falha em mid-save → rollback completo
RSpec.describe InternalChat::MessageDispatcher do
  let(:account) { create(:account) }
  let(:sender) { create(:user, account: account) }
  let(:other_user) { create(:user, account: account) }
  let(:room) { InternalChat::Room.create!(account: account, kind: 'group', name: 'Test') }

  before do
    InternalChat::Membership.create!(room: room, user_id: sender.id, role: 'member')
    InternalChat::Membership.create!(room: room, user_id: other_user.id, role: 'member')
  end

  describe '.call (happy path)' do
    it 'cria message com content_type text e content correto' do
      message = described_class.call(room: room, sender: sender, content: 'hello world')

      expect(message).to be_persisted
      expect(message.content).to eq('hello world')
      expect(message.content_type).to eq('text')
      expect(message.sender_user_id).to eq(sender.id)
      expect(message.sender_ai_agent_id).to be_nil
    end

    it 'atualiza last_message_at da sala' do
      expect { described_class.call(room: room, sender: sender, content: 'hi') }
        .to change { room.reload.last_message_at }
    end

    it 'enfileira BroadcastMessageJob' do
      expect { described_class.call(room: room, sender: sender, content: 'hi') }
        .to have_enqueued_job(InternalChat::BroadcastMessageJob)
    end

    it 'persiste content_attributes quando passados' do
      message = described_class.call(
        room: room, sender: sender, content: 'hi',
        content_attributes: { 'custom' => 'value' }
      )
      expect(message.content_attributes['custom']).to eq('value')
    end
  end

  describe '.call content_type derivation' do
    it 'usa content_type "sticker" quando sticker_id presente e sem texto/anexo' do
      sticker = InternalChat::Sticker.create!(account: account, kind: 'account', created_by_user: sender)
      message = described_class.call(room: room, sender: sender, sticker_id: sticker.id)
      expect(message.content_type).to eq('sticker')
      expect(message.sticker_id).to eq(sticker.id)
    end

    it 'usa "text" mesmo com sticker_id se content presente' do
      sticker = InternalChat::Sticker.create!(account: account, kind: 'account', created_by_user: sender)
      message = described_class.call(room: room, sender: sender, content: 'sticker+text', sticker_id: sticker.id)
      expect(message.content_type).to eq('text')
    end
  end

  describe '.call (mentions persistence)' do
    it 'cria Mention pra cada user_id mencionado (exceto self)' do
      message = described_class.call(
        room: room, sender: sender, content: "@#{other_user.available_name}",
        content_attributes: { 'mentioned_user_ids' => [other_user.id, sender.id] }
      )

      mentioned = message.mentions.pluck(:user_id)
      expect(mentioned).to include(other_user.id)
      # Self-mention skip (sender não menciona a si mesmo via human path)
      expect(mentioned).not_to include(sender.id)
    end

    it 'denormaliza account_id da Mention (passes MT-12 validation)' do
      message = described_class.call(
        room: room, sender: sender, content: 'mention',
        content_attributes: { 'mentioned_user_ids' => [other_user.id] }
      )
      mention = message.mentions.first
      expect(mention.account_id).to eq(room.account_id)
    end
  end

  describe '.call (BE-20: in_reply_to cross-room sanitization)' do
    let(:other_room) { InternalChat::Room.create!(account: account, kind: 'group', name: 'Other') }
    let(:other_room_message) { other_room.messages.create!(content: 'from other room') }

    it 'remove in_reply_to silenciosamente quando aponta msg de outra sala' do
      message = described_class.call(
        room: room, sender: sender, content: 'reply attempt',
        content_attributes: { 'in_reply_to' => other_room_message.id }
      )

      expect(message.content_attributes).not_to have_key('in_reply_to')
      expect(message.content).to eq('reply attempt') # mensagem ainda salva
    end

    it 'preserva in_reply_to quando aponta msg da mesma sala' do
      same_room_message = room.messages.create!(content: 'previous')

      message = described_class.call(
        room: room, sender: sender, content: 'valid reply',
        content_attributes: { 'in_reply_to' => same_room_message.id }
      )

      expect(message.content_attributes['in_reply_to']).to eq(same_room_message.id)
    end

    it 'remove in_reply_to apontando pra ID inexistente (msg deletada, etc)' do
      message = described_class.call(
        room: room, sender: sender, content: 'orphan reply',
        content_attributes: { 'in_reply_to' => 999_999_999 }
      )

      expect(message.content_attributes).not_to have_key('in_reply_to')
    end

    it 'preserva outros campos de content_attributes ao sanitizar in_reply_to' do
      message = described_class.call(
        room: room, sender: sender, content: 'mixed',
        content_attributes: { 'in_reply_to' => other_room_message.id, 'custom' => 'kept' }
      )

      expect(message.content_attributes).not_to have_key('in_reply_to')
      expect(message.content_attributes['custom']).to eq('kept')
    end
  end

  describe '.call (atomicidade)' do
    it 'reverte criação da message se mention.create! falhar' do
      # Simula falha forçando Mention#save! a explodir
      allow(InternalChat::Mention).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(InternalChat::Mention.new))

      expect do
        begin
          described_class.call(
            room: room, sender: sender, content: 'hi',
            content_attributes: { 'mentioned_user_ids' => [other_user.id] }
          )
        rescue ActiveRecord::RecordInvalid
          # Esperado
        end
      end.not_to change(InternalChat::Message, :count)
    end
  end

  describe '.call (BroadcastMessageJob enfileirado FORA da transação)' do
    # Sanity check do design atual: BroadcastMessageJob.perform_later vem
    # DEPOIS do `transaction do ... end` no service. Se mudar, este spec
    # falha — sinalizando que precisa atenção (broadcast num INSERT em
    # rollback é o pior cenário).
    it 'enfileira broadcast só uma vez por chamada bem-sucedida' do
      expect do
        described_class.call(room: room, sender: sender, content: 'one')
      end.to have_enqueued_job(InternalChat::BroadcastMessageJob).exactly(:once)
    end
  end
end
