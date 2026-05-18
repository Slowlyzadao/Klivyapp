require 'rails_helper'

RSpec.describe AiAgent::Humanization::Critique do
  let(:account) { create(:account) }
  let(:base_args) { { starts_at: 1.day.from_now.iso8601, duration_minutes: 60 } }

  def critique(args)
    described_class.new(account: account, tool: :book, args: args).call
  end

  describe 'service_id validation' do
    it 'reprova quando service_id não existe na conta' do
      v = critique(base_args.merge(service_id: 999_999))
      expect(v.passed?).to be(false)
      expect(v.reasons).to include(/serviço 999999 não existe/)
    end

    it 'aprova quando service_id existe' do
      service = AgendaService.create!(account: account, name: 'Avaliação', duration_minutes: 30, position: 1)
      v = critique(base_args.merge(service_id: service.id))
      expect(v.passed?).to be(true)
    end

    it 'aprova quando service_id ausente (LLM esqueceu) — fica pra outra camada' do
      expect(critique(base_args).passed?).to be(true)
    end
  end

  describe 'temporal validation' do
    it 'reprova data no passado' do
      v = critique(base_args.merge(starts_at: 1.day.ago.iso8601))
      expect(v.passed?).to be(false)
      expect(v.reasons.join).to match(/passado/)
    end

    it 'reprova data ausente/inválida' do
      v = critique(base_args.merge(starts_at: 'lixo'))
      expect(v.passed?).to be(false)
    end
  end

  describe 'duration validation' do
    it 'reprova duração fora do range' do
      v = critique(base_args.merge(duration_minutes: 1))
      expect(v.passed?).to be(false)

      v = critique(base_args.merge(duration_minutes: 600))
      expect(v.passed?).to be(false)
    end
  end
end
