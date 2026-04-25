# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Anamnesis, type: :model do
  let(:account) { create(:account) }
  let(:patient) { create(:patient, account: account) }

  describe 'JSONB persistence (regression: checkboxes não persistiam)' do
    it 'persists boolean false values in medical_history without stripping them' do
      anamnesis = create(
        :anamnesis,
        patient: patient,
        account: account,
        medical_history: {
          hypertension: true,
          diabetes: false,
          bleeding_disorder: false,
          pregnant: false,
          oncology: false,
          hepatitis: false,
          has_recent_surgeries: true,
          has_implants: false,
          has_anesthesia_complications: false,
          other: ''
        }
      )

      anamnesis.reload
      mh = anamnesis.medical_history

      expect(mh['hypertension']).to eq(true)
      expect(mh['diabetes']).to eq(false)
      expect(mh['has_recent_surgeries']).to eq(true)
      expect(mh['has_implants']).to eq(false)
      expect(mh).to have_key('other')
    end

    it 'keeps default {} / [] for empty JSONB columns' do
      anamnesis = create(:anamnesis, patient: patient, account: account)
      anamnesis.reload

      expect(anamnesis.medical_history).to eq({})
      expect(anamnesis.allergies).to eq([])
      expect(anamnesis.current_medications).to eq([])
      expect(anamnesis.contraindications).to eq([])
    end
  end

  describe 'versioning (multi-tenant)' do
    it 'scopes version_number per patient within the account' do
      a1 = create(:anamnesis, patient: patient, account: account)
      a2 = create(:anamnesis, patient: patient, account: account)

      expect(a1.version_number).to eq(1)
      expect(a2.version_number).to eq(2)
    end

    it 'does not share version sequence across accounts' do
      other_account = create(:account)
      other_patient = create(:patient, account: other_account)

      local = create(:anamnesis, patient: patient, account: account)
      foreign = create(:anamnesis, patient: other_patient, account: other_account)

      expect(local.version_number).to eq(1)
      expect(foreign.version_number).to eq(1)
    end
  end

  describe '#finalize!' do
    let(:anamnesis) do
      create(
        :anamnesis,
        patient: patient,
        account: account,
        medical_history: { hypertension: true, diabetes: false }
      )
    end

    it 'flips status to finalized and stamps finalized_at without touching clinical data' do
      expect { anamnesis.finalize! }
        .to change { anamnesis.reload.status }.from('draft').to('finalized')

      expect(anamnesis.finalized_at).to be_present
      expect(anamnesis.medical_history).to eq(
        'hypertension' => true,
        'diabetes' => false
      )
    end

    it 'blocks subsequent updates (prevent_edit_if_finalized)' do
      anamnesis.finalize!
      anamnesis.reload

      expect(anamnesis.update(chief_complaint: 'novo valor')).to eq(false)
      expect(anamnesis.reload.chief_complaint).not_to eq('novo valor')
    end
  end
end
