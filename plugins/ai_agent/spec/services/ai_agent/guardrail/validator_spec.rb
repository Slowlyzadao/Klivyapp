require 'rails_helper'

RSpec.describe AiAgent::Guardrail::Validator do
  def block?(msg)
    described_class.new(msg).call
  end

  describe 'medical diagnosis bypasses (PT-BR)' do
    [
      'Pode ser cárie no dente 24',
      'Isso indicaria gengivite',
      'Seria alergia alimentar',
      'Você apresenta sintomas de bruxismo',
      'Trata-se de uma pulpite',
      'Tem cara de cárie ali',
      'Isso parece uma cárie',
      'Isso é sinal de gengivite',
      'Pode estar com periodontite'
    ].each do |msg|
      it "bloqueia: #{msg.inspect}" do
        r = block?(msg)
        expect(r.safe?).to be(false), "esperava bloqueio, retornou safe; violations=#{r.violations.inspect}"
        expect(r.violations).to include('medical_diagnosis')
      end
    end
  end

  describe 'prescription patterns' do
    it 'bloqueia dose explícita' do
      expect(block?('Tome 500 mg de paracetamol').safe?).to be(false)
    end

    it 'bloqueia "comece a tomar antibiótico"' do
      expect(block?('Comece a tomar antibiótico').safe?).to be(false)
    end
  end

  describe 'guarantee patterns' do
    it 'bloqueia garantia de cura' do
      expect(block?('Vai sumir em 2 dias').safe?).to be(false)
      expect(block?('Fica curado em 1 semana').safe?).to be(false)
    end
  end

  describe 'falsos positivos que devem PASSAR' do
    [
      'Olá, tudo bem? Em que posso te ajudar?',
      'Isso parece um escurecimento, recomendo avaliação',
      'Posso te ajudar a marcar uma consulta',
      'Indica que você gostaria de remarcar?',
      'Pode ser melhor agendar logo'
    ].each do |msg|
      it "deixa passar: #{msg.inspect}" do
        expect(block?(msg).safe?).to be(true)
      end
    end
  end

  # Regressão 2026-06-12: "Olá, Leandro! Fico muito feliz..." no 6º turno —
  # o prompt proíbe recumprimentar mas o LLM ignora às vezes. Corte
  # determinístico fora do 1º turno.
  describe 'recumprimento no meio da conversa' do
    def sanitize(msg, first_turn:)
      described_class.new(msg, first_turn: first_turn).call.sanitized_message
    end

    it 'corta a saudação fora do 1º turno' do
      expect(sanitize('Olá, Leandro! Fico muito feliz que esse horário deu certo para você.', first_turn: false))
        .to eq('Fico muito feliz que esse horário deu certo para você.')
      expect(sanitize('Bom dia, Leandro! Que ótimo.', first_turn: false)).to eq('Que ótimo.')
      expect(sanitize('Boa tarde! Por aqui está tudo ótimo.', first_turn: false)).to eq('Por aqui está tudo ótimo.')
    end

    it 'preserva a saudação no 1º turno (abertura legítima)' do
      msg = 'Bom dia! Aqui é a Bia, da Clínica Streit. Tudo bem?'
      expect(sanitize(msg, first_turn: true)).to eq(msg)
    end

    it 'não esvazia mensagem que é SÓ saudação' do
      expect(sanitize('Bom dia!', first_turn: false)).to eq('Bom dia!')
    end

    it 'não mexe em frase sem saudação no começo' do
      msg = 'Perfeito! Seu horário ficou pra segunda às 10h.'
      expect(sanitize(msg, first_turn: false)).to eq(msg)
    end
  end
end
