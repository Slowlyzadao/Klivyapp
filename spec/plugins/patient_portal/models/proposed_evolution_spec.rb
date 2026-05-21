# Sprint L — Specs do model ProposedEvolution.
require 'rails_helper'

RSpec.describe ProposedEvolution do
  let(:account)  { create(:account) }
  let(:user)     { create(:user, account: account) }
  let(:contact)  { create(:contact, account: account, name: 'Joao Silva') }
  let!(:patient) { create(:patient, account: account, contact: contact) }
  let(:event) {
    create(:agenda_event, account: account, user: user, contact: contact,
                          starts_at: 1.hour.ago, status: 'completed')
  }
  let(:recording) {
    create(:telemed_recording, agenda_event: event, account: account,
                               status: 'ready', doctor_egress_id: 'D1', patient_egress_id: 'P1',
                               transcript_text: '[Doutor] oi [Paciente] oi')
  }

  describe '#approve!' do
    let(:soap) {
      {
        'subjetivo' => 'paciente relata dor',
        'objetivo'  => 'desgaste cervical',
        'avaliacao' => 'hipersensibilidade',
        'plano'     => 'fluor topico'
      }
    }
    let!(:evolution) {
      create(:proposed_evolution, telemed_recording: recording, provider: 'claude-sonnet-4-6',
                                  soap_structure: soap, status: 'pending_review')
    }

    it 'cria ClinicalNote com source=telemed_ai' do
      expect { evolution.approve!(actor: user) }.to change(ClinicalNote, :count).by(1)
      note = ClinicalNote.last
      expect(note.source).to eq('telemed_ai')
      expect(note.complaint_of_day).to include('paciente relata dor')
      expect(note.conduct).to include('fluor topico')
      expect(note.proposed_evolution_id).to eq(evolution.id)
      expect(note.status).to eq('draft')
    end

    it 'marca proposta aprovada com reviewer' do
      evolution.approve!(actor: user)
      expect(evolution.reload.status).to eq('approved')
      expect(evolution.reviewed_by_id).to eq(user.id)
      expect(evolution.clinical_note_id).to be_present
    end

    it 'recusa double-approve' do
      evolution.approve!(actor: user)
      expect { evolution.approve!(actor: user) }.to raise_error(/já aprovada/)
    end
  end

  describe '#reject!' do
    let!(:evolution) {
      create(:proposed_evolution, telemed_recording: recording, provider: 'claude-sonnet-4-6')
    }

    it 'requer reason' do
      expect { evolution.reject!(actor: user, reason: '') }.to raise_error(/obrigat/)
    end

    it 'persiste status + reviewer_notes' do
      evolution.reject!(actor: user, reason: 'paciente nao consentiu')
      expect(evolution.reload.status).to eq('rejected')
      expect(evolution.reviewer_notes).to eq('paciente nao consentiu')
    end
  end

  describe '#apply_edit!' do
    let!(:evolution) {
      create(:proposed_evolution, telemed_recording: recording, provider: 'claude-sonnet-4-6',
                                  status: 'pending_review')
    }

    it 'muda status pra edited na primeira edicao' do
      evolution.apply_edit!(raw_markdown: 'novo md', actor: user)
      expect(evolution.reload.status).to eq('edited')
    end

    it 'preserva edited nas edicoes subsequentes' do
      evolution.apply_edit!(raw_markdown: 'a', actor: user)
      evolution.apply_edit!(raw_markdown: 'b', actor: user)
      expect(evolution.reload.status).to eq('edited')
    end

    it 'recusa edicao em aprovada' do
      evolution.update!(status: 'approved')
      expect { evolution.apply_edit!(raw_markdown: 'x', actor: user) }.to raise_error(/aprovada/)
    end
  end
end
