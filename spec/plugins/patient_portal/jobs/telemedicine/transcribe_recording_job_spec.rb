# Sprint L — Specs do TranscribeRecordingJob (audio-only com cleanup).
#
# Cobre: Whisper × 2 nos arquivos isolados, merge cronológico, DELETE dos
# temps no R2, ENQUEUE do GenerateEvolutionJob, e idempotência.
require 'rails_helper'

RSpec.describe Telemed::TranscribeRecordingJob do
  let(:recording) {
    create(:telemed_recording, :uploaded,
           doctor_audio_key:    'rec/doctor-temp.ogg',
           patient_audio_key:   'rec/patient-temp.ogg',
           composite_audio_key: 'rec/composite.ogg')
  }

  let(:doctor_segments) {
    [
      Telemed::TranscriptionProvider::Segment.new(start: 0.0, end_: 2.0, text: 'Bom dia, João'),
      Telemed::TranscriptionProvider::Segment.new(start: 5.0, end_: 7.0, text: 'Como você está?')
    ]
  }
  let(:patient_segments) {
    [
      Telemed::TranscriptionProvider::Segment.new(start: 3.0, end_: 4.5, text: 'Bom dia, doutor'),
      Telemed::TranscriptionProvider::Segment.new(start: 8.0, end_: 10.0, text: 'Estou bem')
    ]
  }

  let(:whisper) { instance_double(Telemed::TranscriptionProvider::Whisper) }

  before do
    allow(Telemed::RecordingStorage).to receive(:download) do |_key, path|
      File.write(path, 'fake ogg binary')
      path
    end
    allow(Telemed::RecordingStorage).to receive(:delete)
    allow(Telemed::TranscriptionProvider).to receive(:for).with('whisper').and_return(whisper)
    allow(whisper).to receive(:call).and_return(
      Telemed::TranscriptionProvider::Result.new(
        segments: doctor_segments, raw_text: 'doctor', provider: 'whisper'
      ),
      Telemed::TranscriptionProvider::Result.new(
        segments: patient_segments, raw_text: 'patient', provider: 'whisper'
      )
    )
  end

  it 'persiste transcript_text mesclado cronologicamente' do
    described_class.new.perform(recording.id)
    rec = recording.reload
    expect(rec.status).to eq('transcribed')
    expect(rec.transcript_text).to include('[Doutor] Bom dia, João')
    expect(rec.transcript_text).to include('[Paciente] Bom dia, doutor')

    # ordem cronológica: doctor@0, patient@3, doctor@5, patient@8
    actual_order = rec.transcript_text.scan(/\[(Doutor|Paciente)\]/).flatten
    expect(actual_order).to eq(%w[Doutor Paciente Doutor Paciente])
  end

  it 'enfileira GenerateEvolutionJob ao terminar' do
    expect {
      described_class.new.perform(recording.id)
    }.to have_enqueued_job(Telemed::GenerateEvolutionJob).with(recording.id)
  end

  it 'deleta os 2 arquivos temp do R2 e zera as colunas' do
    described_class.new.perform(recording.id)

    expect(Telemed::RecordingStorage).to have_received(:delete).with('rec/doctor-temp.ogg')
    expect(Telemed::RecordingStorage).to have_received(:delete).with('rec/patient-temp.ogg')
    # composite NÃO é deletado — só os temps.
    expect(Telemed::RecordingStorage).not_to have_received(:delete).with('rec/composite.ogg')

    rec = recording.reload
    expect(rec.doctor_audio_key).to be_nil
    expect(rec.patient_audio_key).to be_nil
    expect(rec.composite_audio_key).to eq('rec/composite.ogg')
  end

  it 'marca failed se temps faltam (composite-only sem isolados)' do
    rec = create(:telemed_recording, :recording, composite_audio_key: 'c.ogg')
    described_class.new.perform(rec.id)
    expect(rec.reload.status).to eq('failed')
  end

  it 'noop se já está ready/failed/archived (idempotência)' do
    rec = create(:telemed_recording, :ready)
    expect(whisper).not_to receive(:call)
    described_class.new.perform(rec.id)
  end
end
