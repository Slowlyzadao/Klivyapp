# Sprint L — Specs do model TelemedRecording (audio-only com 3 egress).
require 'rails_helper'

RSpec.describe TelemedRecording do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:event)   { create(:agenda_event, account: account, user: user) }

  describe 'validações' do
    it 'aceita registro pending sem egress_ids' do
      rec = described_class.new(agenda_event: event, account: account,
                                status: 'pending', recording_kind: 'audio')
      expect(rec).to be_valid
    end

    it 'recusa status != pending sem qualquer egress_id' do
      rec = described_class.new(agenda_event: event, account: account,
                                status: 'recording', recording_kind: 'audio')
      expect(rec).not_to be_valid
      expect(rec.errors[:base].first).to include('egress_id')
    end

    it 'aceita status recording quando ao menos um egress_id está presente' do
      rec = described_class.new(
        agenda_event: event, account: account, recording_kind: 'audio',
        status: 'recording', composite_egress_id: 'EG_comp_x'
      )
      expect(rec).to be_valid
    end

    it 'status fora do whitelist falha' do
      rec = described_class.new(agenda_event: event, account: account,
                                status: 'bogus', recording_kind: 'audio')
      expect(rec).not_to be_valid
    end

    it 'recording_kind fora do whitelist falha' do
      rec = described_class.new(agenda_event: event, account: account,
                                status: 'pending', recording_kind: 'bogus')
      expect(rec).not_to be_valid
    end
  end

  describe '#role_for_egress_id' do
    let(:rec) {
      create(:telemed_recording, agenda_event: event, account: account,
                                 status: 'recording', recording_kind: 'audio',
                                 doctor_egress_id: 'D1', patient_egress_id: 'P1',
                                 composite_egress_id: 'C1')
    }

    it { expect(rec.role_for_egress_id('D1')).to eq('doctor') }
    it { expect(rec.role_for_egress_id('P1')).to eq('patient') }
    it { expect(rec.role_for_egress_id('C1')).to eq('composite') }
    it { expect(rec.role_for_egress_id('xxx')).to be_nil }
  end

  describe '#all_files_uploaded?' do
    it 'true só quando as 3 keys estão presentes' do
      rec = create(:telemed_recording, :uploaded)
      expect(rec.all_files_uploaded?).to be(true)
    end

    it 'false se uma das keys estiver ausente' do
      rec = create(:telemed_recording, :recording)
      rec.update!(doctor_audio_key: 'd.ogg', composite_audio_key: 'c.ogg')
      expect(rec.all_files_uploaded?).to be(false)
    end
  end

  describe '#composite_only?' do
    it 'true após cleanup dos temps (estado pós-transcribe)' do
      rec = create(:telemed_recording, :transcribed)
      expect(rec.composite_only?).to be(true)
    end
  end

  describe '#fail!' do
    it 'marca status=failed e seta razão' do
      rec = create(:telemed_recording, :recording)
      rec.fail!('boom')
      expect(rec.reload.status).to eq('failed')
      expect(rec.failure_reason).to eq('boom')
    end
  end

  describe '#archive!' do
    let!(:rec) { create(:telemed_recording, :ready) }

    before do
      allow(Telemed::RecordingStorage).to receive(:delete)
    end

    it 'marca archived_at + zera todos audio keys' do
      rec.archive!(reason: 'teste')
      rec.reload
      expect(rec.archived?).to be(true)
      expect(rec.archived_at).to be_present
      expect(rec.composite_audio_key).to be_nil
      expect(rec.doctor_audio_key).to be_nil
      expect(rec.patient_audio_key).to be_nil
      expect(rec.failure_reason).to eq('teste')
    end

    it 'chama delete no R2 pra cada key existente' do
      key = rec.composite_audio_key
      rec.archive!
      expect(Telemed::RecordingStorage)
        .to have_received(:delete).with(key)
    end

    it 'idempotente — segundo archive! é noop' do
      rec.archive!
      expect { rec.archive! }.not_to change { rec.reload.archived_at }
    end
  end

  describe '#retries_exhausted?' do
    it 'verdadeiro após MAX_RETRIES bumps' do
      rec = create(:telemed_recording, :recording)
      described_class::MAX_RETRIES.times { rec.bump_retry! }
      expect(rec.retries_exhausted?).to be(true)
    end
  end

  describe 'scopes' do
    let!(:active)   { create(:telemed_recording, :ready) }
    let!(:archived) { create(:telemed_recording, :archived) }

    it '#active_storage exclui archived' do
      expect(described_class.active_storage).to include(active)
      expect(described_class.active_storage).not_to include(archived)
    end

    it '#archived só inclui archived' do
      expect(described_class.archived).to contain_exactly(archived)
    end

    it '#by_egress_id encontra por qualquer dos 3 ids' do
      rec = create(:telemed_recording, agenda_event: event, account: account,
                                       status: 'recording', recording_kind: 'audio',
                                       doctor_egress_id: 'D9', patient_egress_id: 'P9',
                                       composite_egress_id: 'C9')
      expect(described_class.by_egress_id('D9').first).to eq(rec)
      expect(described_class.by_egress_id('P9').first).to eq(rec)
      expect(described_class.by_egress_id('C9').first).to eq(rec)
      expect(described_class.by_egress_id('zzz')).to be_empty
    end
  end
end
