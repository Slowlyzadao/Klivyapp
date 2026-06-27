# BE-2 (auditoria 2026-05-18): spec do `AiAgent::ChatResponseJob`.
# Cobre o orquestrador async que consome eventos de Message e dispara
# `ChatService#respond` por turno. Mocka ChatService completamente
# (BE-1 cobre a lógica interna).
#
# Branches críticos:
#   - Message não existe → no-op
#   - MT-5: account_id mismatch (cross-tenant) → no-op + warn
#   - Coalescing: incoming mais nova existe → skip
#   - Idempotência: Trace já existe → skip
#   - Happy path: posta reply + promote pending→open
#   - Handoff: posta nota privada + bot_handoff
#   - Erros silenciados sem retry: BeaDisabled, BudgetExceeded, DuplicateTurnError
require 'rails_helper'

RSpec.describe AiAgent::ChatResponseJob do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) do
    create(:conversation,
           account: account, inbox: inbox, contact: contact,
           contact_inbox: contact_inbox, status: :pending)
  end
  let(:message) do
    create(:message,
           account: account, inbox: inbox, conversation: conversation,
           message_type: :incoming, content: 'Olá, posso marcar?')
  end

  # ── ChatService mockado por completo (BE-1 cobre lógica interna)
  let(:chat_result) do
    AiAgent::ChatService::Result.new(
      message: 'Olá! Posso te ajudar a marcar.',
      tool_executions: [],
      usage: { input_tokens: 100, output_tokens: 30 },
      state: instance_double('AiAgent::ConversationState', status: 'active'),
      handoff: false,
      trace: instance_double('AiAgent::Trace', id: 1)
    )
  end
  let(:chat_service) do
    instance_double(AiAgent::ChatService, respond: chat_result)
  end

  before do
    allow(AiAgent::ChatService).to receive(:new).and_return(chat_service)
    # Dispatcher (typing on/off) é best-effort; stuba pra não logar.
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    # WhatsApp HTTP nunca dispara (Channel::Api inbox).
  end

  describe '#perform (early returns)' do
    it 'no-op quando message_id não existe' do
      described_class.new.perform(999_999_999)

      expect(AiAgent::ChatService).not_to have_received(:new)
    end

    it 'MT-5: no-op quando account_id passado não casa com message.account_id' do
      other_account = create(:account)

      described_class.new.perform(message.id, account_id: other_account.id)

      expect(AiAgent::ChatService).not_to have_received(:new)
    end

    it 'MT-5: processa quando account_id passado CASA' do
      described_class.new.perform(message.id, account_id: account.id)

      expect(AiAgent::ChatService).to have_received(:new)
    end

    it 'MT-5: processa quando account_id é nil (compat com jobs antigos pré-MT-5)' do
      described_class.new.perform(message.id, account_id: nil)

      expect(AiAgent::ChatService).to have_received(:new)
    end
  end

  describe '#perform (coalescing — incoming mais nova existe)' do
    it 'pula quando há incoming mais recente na mesma conv' do
      message # garante que a antiga existe
      # Mensagem mais nova
      create(:message,
             account: account, inbox: inbox, conversation: conversation,
             message_type: :incoming, content: 'segunda mensagem')

      described_class.new.perform(message.id)

      expect(AiAgent::ChatService).not_to have_received(:new)
    end

    it 'NÃO pula quando incoming mais nova é private (não conta)' do
      message
      create(:message,
             account: account, inbox: inbox, conversation: conversation,
             message_type: :incoming, content: 'private note', private: true)

      described_class.new.perform(message.id)

      expect(AiAgent::ChatService).to have_received(:new)
    end
  end

  describe '#perform (idempotência por Trace)' do
    it 'pula quando Trace bem-sucedido já existe pra message_id' do
      AiAgent::Trace.create!(
        account_id: account.id,
        conversation_id: conversation.id,
        message_id: message.id,
        model: 'gpt-4.1-mini', provider: 'openai',
        created_at: 1.minute.ago
      )

      described_class.new.perform(message.id)

      expect(AiAgent::ChatService).not_to have_received(:new)
    end

    it 'PROCESSA mesmo quando Trace de OUTRA message_id existe (não false positive)' do
      AiAgent::Trace.create!(
        account_id: account.id,
        conversation_id: conversation.id,
        message_id: message.id + 1,
        model: 'gpt-4.1-mini', provider: 'openai',
        created_at: 1.minute.ago
      )

      described_class.new.perform(message.id)

      expect(AiAgent::ChatService).to have_received(:new)
    end
  end

  describe '#perform (happy path)' do
    it 'chama ChatService.respond com content da message' do
      described_class.new.perform(message.id)

      expect(chat_service).to have_received(:respond).with(
        'Olá, posso marcar?',
        message_id: message.id
      )
    end

    it 'inicializa ChatService com account, conversation, contact, history' do
      described_class.new.perform(message.id)

      expect(AiAgent::ChatService).to have_received(:new).with(
        hash_including(
          account: account,
          conversation_id: conversation.id,
          contact_id: contact.id,
          history: kind_of(Array)
        )
      )
    end

    it 'posta reply como outgoing message do AgentBot Bea' do
      expect do
        described_class.new.perform(message.id)
      end.to change { conversation.reload.messages.outgoing.count }.by(1)

      reply = conversation.messages.outgoing.last
      expect(reply.content).to eq('Olá! Posso te ajudar a marcar.')
      expect(reply.sender).to be_a(AgentBot)
      expect(reply.private).to be(false)
    end

    it 'promove conversa de pending → open quando há reply' do
      expect do
        described_class.new.perform(message.id)
      end.to change { conversation.reload.status }.from('pending')
    end

    it 'NÃO posta reply quando ChatService retorna message vazia' do
      empty_result = AiAgent::ChatService::Result.new(
        message: '', tool_executions: [], usage: {}, state: nil, handoff: false, trace: nil
      )
      allow(chat_service).to receive(:respond).and_return(empty_result)

      expect do
        described_class.new.perform(message.id)
      end.not_to change { conversation.reload.messages.outgoing.count }
    end
  end

  describe '#perform (handoff)' do
    let(:chat_result) do
      AiAgent::ChatService::Result.new(
        message: 'Vou te passar pra um atendente.',
        tool_executions: [],
        usage: {},
        state: instance_double('AiAgent::ConversationState', status: 'escalated'),
        handoff: true,
        trace: instance_double('AiAgent::Trace', id: 1)
      )
    end

    it 'posta nota privada de handoff (visível só pra equipe)' do
      described_class.new.perform(message.id)

      private_note = conversation.reload.messages.where(private: true).last
      expect(private_note).to be_present
      expect(private_note.content).to include('transferiu')
    end

    it 'promove conversation status (bot_handoff!)' do
      described_class.new.perform(message.id)

      expect(conversation.reload.status).not_to eq('pending')
    end
  end

  describe '#perform (erros silenciados sem retry)' do
    it 'silencia BeaDisabledError (não retenta job)' do
      allow(chat_service).to receive(:respond)
        .and_raise(AiAgent::ChatService::BeaDisabledError, 'desabilitado')

      expect do
        described_class.new.perform(message.id)
      end.not_to raise_error
    end

    it 'silencia BudgetExceededError (não retenta job)' do
      allow(chat_service).to receive(:respond)
        .and_raise(AiAgent::ChatService::BudgetExceededError, 'cap')

      expect { described_class.new.perform(message.id) }.not_to raise_error
    end

    it 'silencia DuplicateTurnError (race entre jobs concorrentes)' do
      allow(chat_service).to receive(:respond)
        .and_raise(AiAgent::ChatService::DuplicateTurnError, 'race')

      expect { described_class.new.perform(message.id) }.not_to raise_error
    end

    it 'PROPAGA StandardError genérico (Sidekiq retry: 0 → não vai retentar, mas Trace de erro registra)' do
      allow(chat_service).to receive(:respond).and_raise(StandardError, 'boom')

      expect { described_class.new.perform(message.id) }.to raise_error(StandardError, 'boom')
    end
  end

  describe '#perform (sidekiq retry: 0)' do
    # Garante que se mexerem na sidekiq_options retry, este spec quebra
    # — proteção contra retentar e postar reply duplicado no paciente.
    it 'job tem retry=0 (evita reply duplicado em retry após partial success)' do
      expect(described_class.sidekiq_options['retry']).to eq(0)
    end
  end

  describe '#perform (audio path)' do
    let(:audio_attachment) do
      double('Attachment', file_type: 'audio')
    end
    let(:transcription_result) do
      instance_double('AudioTranscriber::Result', text: 'transcrito do áudio')
    end

    before do
      # Mensagem sem content + com audio attachment
      message.update_columns(content: '')
      allow(message).to receive(:attachments).and_return([audio_attachment])
      allow(Message).to receive(:find_by).with(id: message.id).and_return(message)

      transcriber = instance_double(AiAgent::Multimodal::AudioTranscriber, call: transcription_result)
      allow(AiAgent::Multimodal::AudioTranscriber).to receive(:new).and_return(transcriber)
    end

    it 'transcreve áudio e passa pro ChatService' do
      described_class.new.perform(message.id)

      expect(chat_service).to have_received(:respond).with(
        'transcrito do áudio', message_id: message.id
      )
    end

    it 'persiste transcrição em message.content (silent update)' do
      expect(message).to receive(:update_columns).with(content: 'transcrito do áudio')

      described_class.new.perform(message.id)
    end
  end

  describe '#perform (audio blob não pronto — race WhatsApp)' do
    let(:audio_attachment) { double('Attachment', file_type: 'audio') }

    before do
      message.update_columns(content: '')
      allow(message).to receive(:attachments).and_return([audio_attachment])
      allow(Message).to receive(:find_by).with(id: message.id).and_return(message)

      transcriber = instance_double(
        AiAgent::Multimodal::AudioTranscriber,
        call: AiAgent::Multimodal::AudioTranscriber::FILE_NOT_READY
      )
      allow(AiAgent::Multimodal::AudioTranscriber).to receive(:new).and_return(transcriber)
    end

    it 'reenfileira job com delay quando attempt < MAX_BLOB_RETRY' do
      expect do
        described_class.new.perform(message.id, attempt: 1)
      end.to have_enqueued_job(described_class).with(
        message.id, attempt: 2, account_id: account.id
      )
      expect(chat_service).not_to have_received(:respond)
    end

    it 'cai pro fallback audio quando esgota MAX_BLOB_RETRY' do
      expect do
        described_class.new.perform(message.id, attempt: described_class::MAX_BLOB_RETRY)
      end.to change { conversation.reload.messages.outgoing.count }.by(1)

      fallback = conversation.messages.outgoing.last
      expect(fallback.content).to include('áudio')
    end
  end

  describe '#perform (audio sem texto e sem transcrição — fallback)' do
    let(:audio_attachment) { double('Attachment', file_type: 'audio') }

    before do
      message.update_columns(content: '')
      allow(message).to receive(:attachments).and_return([audio_attachment])
      allow(Message).to receive(:find_by).with(id: message.id).and_return(message)

      transcriber = instance_double(AiAgent::Multimodal::AudioTranscriber, call: nil)
      allow(AiAgent::Multimodal::AudioTranscriber).to receive(:new).and_return(transcriber)
    end

    it 'posta fallback humanizado pro paciente quando transcrição vazia' do
      described_class.new.perform(message.id)

      fallback = conversation.reload.messages.outgoing.last
      expect(fallback.content).to include('áudio')
      expect(chat_service).not_to have_received(:respond)
    end
  end

  describe '#perform (visual attachment — handoff sempre)' do
    let(:image_attachment) do
      double('Attachment', id: 99, file_type: 'image')
    end
    let(:image_result) do
      double('ImageHandler::Result',
             staff_note: 'imagem recebida, possível receita',
             patient_message: 'Recebi sua imagem! Vou repassar pra equipe.',
             category: :prescription,
             handoff_required: true)
    end

    before do
      allow(message).to receive(:attachments).and_return([image_attachment])
      allow(Message).to receive(:find_by).with(id: message.id).and_return(message)

      handler = instance_double(AiAgent::Multimodal::ImageHandler, call: image_result)
      allow(AiAgent::Multimodal::ImageHandler).to receive(:new).and_return(handler)
    end

    it 'NÃO chama ChatService (CFM — Bea não interpreta imagem médica)' do
      described_class.new.perform(message.id)

      expect(chat_service).not_to have_received(:respond)
    end

    it 'posta nota privada + mensagem ao paciente e promove pra open' do
      expect do
        described_class.new.perform(message.id)
      end.to change { conversation.reload.messages.count }.by(2)

      private_note = conversation.messages.where(private: true).last
      patient_msg = conversation.messages.where(private: false, message_type: :outgoing).last
      expect(private_note.content).to include('possível receita')
      expect(patient_msg.content).to include('imagem')
      expect(conversation.reload.status).not_to eq('pending')
    end

    it 'saudação (greeting): responde com carinho SEM nota pra equipe nem escala' do
      greeting = double('ImageHandler::Result',
                        staff_note: nil,
                        patient_message: 'Aaah, que fofo! Obrigada 🌷',
                        category: :greeting,
                        handoff_required: false)
      handler = instance_double(AiAgent::Multimodal::ImageHandler, call: greeting)
      allow(AiAgent::Multimodal::ImageHandler).to receive(:new).and_return(handler)

      expect do
        described_class.new.perform(message.id)
      end.to change {
        conversation.reload.messages.where(private: false, message_type: :outgoing).count
      }.by(1)

      expect(conversation.messages.where(private: true).count).to eq(0)
    end
  end
end
