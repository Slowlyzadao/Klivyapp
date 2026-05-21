require 'rails_helper'

# State machine de transições automáticas — Sprint K.
# Foco: matriz de origens válidas por destino + idempotência + bloqueio
# de eventos descartados (soft-deleted).
RSpec.describe Telemed::StatusTransition do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:event)   { create(:agenda_event, account: account, user: user, status: 'scheduled') }

  subject(:service) { described_class.new(event) }

  describe '#mark_arrived!' do
    it 'transiciona de scheduled' do
      expect(service.mark_arrived!.success?).to be(true)
      expect(event.reload.status).to eq('arrived')
    end

    it 'transiciona de confirmed' do
      event.update!(status: 'confirmed')
      expect(service.mark_arrived!.success?).to be(true)
      expect(event.reload.status).to eq('arrived')
    end

    it 'é idempotente (segunda chamada noop)' do
      service.mark_arrived!
      result = service.mark_arrived!
      expect(result.success?).to be(false)
      expect(result.noop?).to be(true)
      expect(result.reason).to eq(:already_in_target)
      expect(event.reload.status).to eq('arrived')
    end

    it 'NÃO transiciona de completed' do
      event.update!(status: 'completed')
      result = service.mark_arrived!
      expect(result.success?).to be(false)
      expect(result.reason).to eq(:not_allowed)
      expect(event.reload.status).to eq('completed')
    end

    it 'NÃO transiciona de no_show' do
      event.update!(status: 'no_show')
      expect(service.mark_arrived!.success?).to be(false)
      expect(event.reload.status).to eq('no_show')
    end
  end

  describe '#mark_in_progress!' do
    it 'transiciona de arrived' do
      event.update!(status: 'arrived')
      expect(service.mark_in_progress!.success?).to be(true)
      expect(event.reload.status).to eq('in_progress')
    end

    it 'NÃO transiciona de scheduled (pulou arrived)' do
      result = service.mark_in_progress!
      expect(result.reason).to eq(:not_allowed)
    end

    it 'NÃO transiciona de completed' do
      event.update!(status: 'completed')
      expect(service.mark_in_progress!.success?).to be(false)
    end
  end

  describe '#mark_completed!' do
    it 'transiciona de in_progress' do
      event.update!(status: 'in_progress')
      expect(service.mark_completed!.success?).to be(true)
      expect(event.reload.status).to eq('completed')
    end

    it 'NÃO transiciona de arrived (precisa passar por in_progress)' do
      event.update!(status: 'arrived')
      expect(service.mark_completed!.success?).to be(false)
    end
  end

  describe '#mark_no_show!' do
    it 'transiciona de scheduled' do
      expect(service.mark_no_show!.success?).to be(true)
      expect(event.reload.status).to eq('no_show')
    end

    it 'transiciona de confirmed' do
      event.update!(status: 'confirmed')
      expect(service.mark_no_show!.success?).to be(true)
    end

    it 'NÃO transiciona de in_progress (paciente já chegou)' do
      event.update!(status: 'in_progress')
      expect(service.mark_no_show!.success?).to be(false)
      expect(event.reload.status).to eq('in_progress')
    end

    it 'NÃO transiciona de completed' do
      event.update!(status: 'completed')
      expect(service.mark_no_show!.success?).to be(false)
    end
  end

  describe 'evento descartado (soft-deleted)' do
    before { event.soft_delete!(actor: nil, reason: 'cancelamento_paciente') }

    it 'não transiciona mesmo com origem válida' do
      result = service.mark_arrived!
      expect(result.success?).to be(false)
      expect(result.reason).to eq(:discarded)
    end
  end

  describe '#transition!' do
    it 'rejeita destino fora da whitelist' do
      result = service.transition!('foo_bar')
      expect(result.success?).to be(false)
      expect(result.reason).to eq(:invalid_target)
    end

    it 'preenche Result com from/to/reason corretamente' do
      result = service.transition!('arrived', source: 'spec')
      expect(result.from).to eq('scheduled')
      expect(result.to).to eq('arrived')
      expect(result.reason).to eq(:transitioned)
    end
  end
end
