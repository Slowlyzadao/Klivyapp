# Sprint L — Specs do EnforceRecordingQuotaJob.
#
# Política: quando uma clínica passa do `max_active_recordings` definido em
# patient_portal_setting.telemedicine_recording, arquiva as mais antigas
# (deleta R2, mantém registro pra audit, NÃO toca em ClinicalNote).
require 'rails_helper'

RSpec.describe Telemed::EnforceRecordingQuotaJob do
  let(:account) { create(:account) }
  let!(:setting) {
    PatientPortalSetting.create!(
      account: account,
      active_preset: 'autonomy_guided',
      telemedicine_recording: { 'max_active_recordings' => 3 }
    )
  }

  before do
    allow(Telemed::RecordingStorage).to receive(:delete)
  end

  it 'não arquiva nada se total <= quota' do
    create_list(:telemed_recording, 3, :ready, account: account,
                                               agenda_event: create(:agenda_event, account: account))
    expect {
      described_class.new.perform(account.id)
    }.not_to change { TelemedRecording.archived.count }
  end

  it 'arquiva as mais antigas quando total > quota' do
    olds = 5.times.map do |i|
      create(:telemed_recording, :ready, account: account,
                                         agenda_event: create(:agenda_event, account: account),
                                         created_at: i.days.ago)
    end

    described_class.new.perform(account.id)

    # quota=3, total=5 → 2 mais antigas arquivadas (created_at maior tempo atrás)
    archived = TelemedRecording.archived.where(account_id: account.id)
    expect(archived.count).to eq(2)
    expect(archived.pluck(:id)).to match_array([olds[4].id, olds[3].id]) # 4 e 3 dias atrás
  end

  it 'quota=0 desativa o job (sem arquivamento)' do
    setting.update!(telemedicine_recording: { 'max_active_recordings' => 0 })
    create_list(:telemed_recording, 5, :ready, account: account,
                                                agenda_event: create(:agenda_event, account: account))
    expect {
      described_class.new.perform(account.id)
    }.not_to change { TelemedRecording.archived.count }
  end

  it 'usa default 15 se config ausente' do
    setting.update!(telemedicine_recording: {})
    create_list(:telemed_recording, 5, :ready, account: account,
                                                agenda_event: create(:agenda_event, account: account))
    described_class.new.perform(account.id)
    expect(TelemedRecording.archived.count).to eq(0)
  end

  it 'noop em account inexistente' do
    expect { described_class.new.perform(99_999_999) }.not_to raise_error
  end
end
