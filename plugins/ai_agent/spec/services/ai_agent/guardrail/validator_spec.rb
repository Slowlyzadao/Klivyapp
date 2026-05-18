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
end
