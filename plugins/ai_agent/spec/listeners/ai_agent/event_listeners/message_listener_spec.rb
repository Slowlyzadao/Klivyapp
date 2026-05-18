require 'rails_helper'

RSpec.describe AiAgent::EventListeners::MessageListener do
  let(:listener) { described_class.instance }

  describe '#from_real_contact?' do
    def stub_msg(sender_type:, sender_id: 1)
      Struct.new(:sender_type, :sender_id).new(sender_type, sender_id)
    end

    it 'aceita sender Contact com id' do
      expect(listener.send(:from_real_contact?, stub_msg(sender_type: 'Contact', sender_id: 42))).to be(true)
    end

    it 'rejeita AgentBot' do
      expect(listener.send(:from_real_contact?, stub_msg(sender_type: 'AgentBot'))).to be(false)
    end

    it 'rejeita User (agente humano)' do
      expect(listener.send(:from_real_contact?, stub_msg(sender_type: 'User'))).to be(false)
    end

    it 'rejeita sender nil' do
      expect(listener.send(:from_real_contact?, stub_msg(sender_type: nil, sender_id: nil))).to be(false)
    end

    it 'rejeita Contact sem id (raro mas defensivo)' do
      expect(listener.send(:from_real_contact?, stub_msg(sender_type: 'Contact', sender_id: nil))).to be(false)
    end
  end

  describe '#sent_via_api?' do
    def stub_msg(ca:)
      Struct.new(:content_attributes).new(ca)
    end

    it 'detecta flag sent_via_api=true' do
      expect(listener.send(:sent_via_api?, stub_msg(ca: { 'sent_via_api' => true }))).to be(true)
    end

    it 'ignora content_attributes vazio' do
      expect(listener.send(:sent_via_api?, stub_msg(ca: {}))).to be(false)
    end

    it 'ignora content_attributes nil' do
      expect(listener.send(:sent_via_api?, stub_msg(ca: nil))).to be(false)
    end

    it 'ignora flag false' do
      expect(listener.send(:sent_via_api?, stub_msg(ca: { 'sent_via_api' => false }))).to be(false)
    end
  end
end
