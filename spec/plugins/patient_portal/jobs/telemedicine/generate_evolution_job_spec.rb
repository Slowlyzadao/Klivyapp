# Sprint L — Specs do GenerateEvolutionJob.
#
# Mock o EvolutionProvider pra simular resposta do Claude sem chamada real.
require 'rails_helper'

RSpec.describe Telemed::GenerateEvolutionJob do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Joao') }
  let!(:patient) { create(:patient, account: account, contact: contact) }
  let(:event) {
    create(:agenda_event, account: account, user: user, contact: contact,
                          starts_at: 1.hour.ago, status: 'completed')
  }
  let(:recording) {
    create(:telemed_recording, :transcribed,
           agenda_event: event, account: account,
           transcript_text: "[Doutor] dói? [Paciente] sim")
  }

  let(:fake_provider) { instance_double(Telemed::EvolutionProvider::Claude) }
  let(:fake_result) {
    Telemed::EvolutionProvider::Result.new(
      soap_structure: {
        'subjetivo' => 'dor relatada', 'objetivo' => 'desgaste',
        'avaliacao' => 'hipersensibilidade', 'plano' => 'fluor'
      },
      raw_markdown:     "## S — Subjetivo\ndor relatada",
      attention_points: [{ 'type' => 'allergy', 'severity' => 'high', 'text' => 'penicilina' }],
      provider:         'claude/claude-sonnet-4-6',
      input_tokens:     1000, output_tokens: 200
    )
  }

  before do
    allow(Telemed::EvolutionProvider).to receive(:for).and_return(fake_provider)
    allow(fake_provider).to receive(:call).and_return(fake_result)
  end

  it 'cria ProposedEvolution e move recording pra ready' do
    expect {
      described_class.new.perform(recording.id)
    }.to change(ProposedEvolution, :count).by(1)

    rec = recording.reload
    expect(rec.status).to eq('ready')

    evo = rec.proposed_evolutions.first
    expect(evo.provider).to eq('claude/claude-sonnet-4-6')
    expect(evo.soap_structure['subjetivo']).to eq('dor relatada')
    expect(evo.attention_points.first['type']).to eq('allergy')
    expect(evo.input_tokens).to eq(1000)
  end

  it 'noop se transcript ausente' do
    rec = create(:telemed_recording, :uploaded, transcript_text: nil)
    expect {
      described_class.new.perform(rec.id)
    }.not_to change(ProposedEvolution, :count)
  end

  it 'marca failed após esgotar retries em falha de provider' do
    allow(fake_provider).to receive(:call).and_raise(StandardError, 'boom')

    # Esgotar retries: simulate 3 invocações que estouram retry_count.
    described_class::MAX_RETRIES = 3 unless described_class.const_defined?(:MAX_RETRIES, false)
    3.times do
      begin
        described_class.new.perform(recording.id)
      rescue StandardError
        # esperado em retries
      end
    end

    expect(recording.reload.status).to eq('failed')
  end
end
