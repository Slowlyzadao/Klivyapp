# frozen_string_literal: true

# Spec da migration `BackfillClinicalNotesIntoSessionLogs` (1.5.2.0).
#
# Cobre:
#   - Mapeamento campo a campo (note_date → performed_at em BRT 00:00,
#     conduct → procedure_name, return_recommended → return_in_days etc.)
#   - Soft-deleted notes são puladas
#   - Idempotência (rodar 2x não duplica)
#   - Fallback "Evolução clínica (migrada)" quando conduct está vazio

require 'rails_helper'
require Rails.root.join('db/migrate/20260504000002_backfill_clinical_notes_into_session_logs.rb')

RSpec.describe BackfillClinicalNotesIntoSessionLogs do
  let(:account)      { create(:account) }
  let(:patient)      { create(:patient, account: account) }
  let(:professional) { create(:user, account: account) }

  # Limpa SessionLogs antes (factory de ClinicalNote pode ter callbacks que tocam
  # outras tabelas — isolar pra contar só o que a migration cria).
  before { SessionLog.delete_all }

  def run_migration
    described_class.new.up
  end

  describe 'mapeamento de campos' do
    let!(:note) do
      create(:clinical_note,
             account: account,
             patient: patient,
             professional: professional,
             note_date: Date.new(2026, 5, 2),
             complaint_of_day: 'Queixa X',
             assessment: 'Avaliação Y',
             conduct: 'Limpeza profissional',
             complications: 'Nenhuma',
             guidance_given: 'Cuidados pós',
             return_recommended: Date.new(2026, 5, 16),
             status: 'signed')
    end

    it 'cria um SessionLog com migrated_from_clinical_note_id' do
      expect { run_migration }.to change {
        SessionLog.where.not(migrated_from_clinical_note_id: nil).count
      }.by(1)
    end

    it 'mapeia conduct → procedure_name' do
      run_migration
      sl = SessionLog.find_by(migrated_from_clinical_note_id: note.id)
      expect(sl.procedure_name).to eq('Limpeza profissional')
    end

    it 'mapeia complaint_of_day, assessment, complications' do
      run_migration
      sl = SessionLog.find_by(migrated_from_clinical_note_id: note.id)
      expect(sl.complaint_of_day).to eq('Queixa X')
      expect(sl.assessment).to eq('Avaliação Y')
      expect(sl.complications).to eq('Nenhuma')
    end

    it 'mapeia guidance_given → post_procedure_guidance' do
      run_migration
      sl = SessionLog.find_by(migrated_from_clinical_note_id: note.id)
      expect(sl.post_procedure_guidance).to eq('Cuidados pós')
    end

    it 'calcula return_in_days a partir de return_recommended' do
      run_migration
      sl = SessionLog.find_by(migrated_from_clinical_note_id: note.id)
      expect(sl.return_in_days).to eq(14)
      expect(sl.return_needed).to be true
    end

    it 'mapeia note_date → performed_at em BRT 00:00' do
      run_migration
      sl = SessionLog.find_by(migrated_from_clinical_note_id: note.id)
      expect(sl.performed_at.in_time_zone('America/Sao_Paulo').to_date).to eq(Date.new(2026, 5, 2))
      expect(sl.performed_at.in_time_zone('America/Sao_Paulo').hour).to eq(0)
    end

    it 'preserva status' do
      run_migration
      sl = SessionLog.find_by(migrated_from_clinical_note_id: note.id)
      expect(sl.status).to eq('signed')
    end
  end

  describe 'fallback de procedure_name quando conduct vazio' do
    it 'usa "Evolução clínica (migrada)" se conduct é nil' do
      note = create(:clinical_note, account: account, patient: patient, conduct: nil)
      run_migration
      sl = SessionLog.find_by(migrated_from_clinical_note_id: note.id)
      expect(sl.procedure_name).to eq('Evolução clínica (migrada)')
    end
  end

  describe 'soft-deleted notes' do
    it 'pula notes com deleted_at != nil' do
      create(:clinical_note, :soft_deleted, account: account, patient: patient)
      expect { run_migration }.not_to change {
        SessionLog.where.not(migrated_from_clinical_note_id: nil).count
      }
    end
  end

  describe 'idempotência' do
    before do
      create_list(:clinical_note, 3, account: account, patient: patient)
    end

    it 'não duplica registros ao rodar 2x' do
      run_migration
      first_run_count = SessionLog.where.not(migrated_from_clinical_note_id: nil).count

      run_migration
      second_run_count = SessionLog.where.not(migrated_from_clinical_note_id: nil).count

      expect(first_run_count).to eq(3)
      expect(second_run_count).to eq(3)
    end
  end

  describe '#down' do
    it 'levanta IrreversibleMigration' do
      expect { described_class.new.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end
end
