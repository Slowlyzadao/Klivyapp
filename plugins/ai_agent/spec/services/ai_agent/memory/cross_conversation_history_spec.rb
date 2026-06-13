require 'rails_helper'

RSpec.describe AiAgent::Memory::CrossConversationHistory do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  def incoming!(content)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :incoming, content: content)
  end

  def outgoing!(content)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :outgoing, content: content)
  end

  def history_for(current, limit: AiAgent::ChatResponseJob::HISTORY_LIMIT)
    described_class.new(
      account_id: account.id, contact_id: contact.id,
      current_message: current, limit: limit, ttl_hours: 24
    ).build
  end

  # Regressão 2026-06-11: a Bia re-perguntou "é pra você mesmo?" porque a
  # resposta (dada por áudio, transcrita pra content) tinha saído da janela
  # de 10 mensagens — cada bolha da Bia é uma Message separada, então 10
  # mensagens eram só ~3 turnos.
  it 'resposta do paciente a 11+ mensagens de distância continua na janela (limite 40)' do
    outgoing!('Você gostaria de agendar para você mesmo ou para outra pessoa?')
    incoming!('Seria pra mim mesmo') # resposta por áudio (transcrição vira content)
    12.times do |i|
      outgoing!("bolha #{i} da Bia")
      incoming!("resposta #{i}")
    end
    current = incoming!('Podemos as 16:00')

    history = history_for(current)
    all_text = history.map { |e| e[:content] }.join("\n")

    expect(all_text).to include('Seria pra mim mesmo')
    expect(all_text).to include('para você mesmo ou para outra pessoa')
  end

  it 'mescla bolhas consecutivas do mesmo lado num item só' do
    incoming!('Oi')
    outgoing!('Olá, Leandro!')
    outgoing!('Como posso te ajudar?')
    current = incoming!('Quero agendar')

    history = history_for(current)

    expect(history.map { |e| e[:role] }).to eq(%w[user assistant])
    expect(history.last[:content]).to eq("Olá, Leandro!\nComo posso te ajudar?")
  end

  it 'imagem sem texto vira placeholder em vez de turno vazio' do
    msg = incoming!(nil)
    attachment = msg.attachments.new(account_id: account.id, file_type: :image)
    attachment.file.attach(io: StringIO.new('fake'), filename: 'flor.jpg', content_type: 'image/jpeg')
    attachment.save!
    current = incoming!('Bom dia')

    history = history_for(current)

    expect(history.first[:content]).to include('[paciente enviou: image]')
  end

  # Regressão 2026-06-12: o "Olá, Fulano" do follow-up automático fazia o
  # LLM tratar o turno seguinte como conversa nova e recumprimentar.
  it 'follow-up automático entra rotulado no histórico (não parece reabertura)' do
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :outgoing, content: 'Olá, Leandro, ficou alguma dúvida?',
                     content_attributes: { 'ai_follow_up' => true })
    current = incoming!('Seria para mim mesmo')

    history = history_for(current)

    expect(history.first[:content]).to include('[follow-up automático enviado pela clínica')
    expect(history.first[:content]).to include('ficou alguma dúvida?')
  end

  it 'exclui mensagens privadas (notas internas) e vazias' do
    incoming!('Oi')
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :outgoing, content: 'nota interna', private: true)
    incoming!(nil) # sem texto e sem anexo → some
    current = incoming!('Continua')

    history = history_for(current)
    all_text = history.map { |e| e[:content] }.join("\n")

    expect(all_text).not_to include('nota interna')
    expect(history.none? { |e| e[:content].empty? }).to be(true)
  end
end
