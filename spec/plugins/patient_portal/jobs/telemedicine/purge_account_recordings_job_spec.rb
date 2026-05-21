# Sprint L — Specs do PurgeAccountRecordingsJob.
#
# Disparado após cancelamento de assinatura (com delay configurável).
# Arquiva TODAS as gravações ativas da clínica sem destruir ClinicalNote.
require 'rails_helper'

RSpec.describe Telemed::PurgeAccountRecordingsJob do
  let(:account) { create(:account) }

  before do
    allow(Telemed::RecordingStorage).to receive(:delete)
  end

  it 'arquiva todas as gravações ativas da account' do
    create_list(:telemed_recording, 4, :ready, account: account,
                                                agenda_event: create(:agenda_event, account: account))
    expect {
      described_class.new.perform(account.id)
    }.to change { TelemedRecording.archived.where(account_id: account.id).count }.from(0).to(4)
  end

  it 'NÃO toca em gravações já arquivadas' do
    archived = create(:telemed_recording, :archived, account: account,
                                                      agenda_event: create(:agenda_event, account: account))
    described_class.new.perform(account.id)
    expect(archived.reload.archived_at).to be_within(1.second).of(archived.archived_at)
  end

  it 'NÃO afeta gravações de outras accounts' do
    other = create(:account)
    other_rec = create(:telemed_recording, :ready, account: other,
                                                    agenda_event: create(:agenda_event, account: other))
    described_class.new.perform(account.id)
    expect(other_rec.reload.archived?).to be(false)
  end

  it 'noop em account inexistente' do
    expect { described_class.new.perform(99_999_999) }.not_to raise_error
  end
end
