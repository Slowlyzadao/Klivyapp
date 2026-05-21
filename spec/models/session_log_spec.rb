# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SessionLog, type: :model do
  let(:account)      { create(:account) }
  let(:patient)      { create(:patient, account: account) }
  let(:professional) { create(:user, account: account) }
  let(:actor)        { create(:user, account: account, role: 'administrator') }

  describe 'validations' do
    it 'requires performed_at' do
      log = build(:session_log, account: account, patient: patient, performed_at: nil)
      expect(log).not_to be_valid
      expect(log.errors[:performed_at]).to be_present
    end

    it 'aceita status draft ou signed' do
      expect(build(:session_log, account: account, patient: patient, status: 'draft')).to be_valid
      expect(build(:session_log, account: account, patient: patient, status: 'signed')).to be_valid
    end

    it 'rejeita status fora do enum' do
      expect {
        build(:session_log, account: account, patient: patient, status: 'aprovado')
      }.to raise_error(ArgumentError) # enum :status raises na assignment de valor inválido
    end

    it 'requer return_needed se return_in_days presente' do
      log = build(:session_log,
                  account: account, patient: patient,
                  return_needed: false, return_in_days: 14)
      expect(log).not_to be_valid
      expect(log.errors[:return_in_days]).to be_present
    end
  end

  describe '#within_draft_window?' do
    it 'retorna true para sessão criada agora' do
      log = create(:session_log, account: account, patient: patient)
      expect(log.within_draft_window?).to be true
    end

    it 'retorna false para sessão criada há mais de 48h' do
      log = create(:session_log, account: account, patient: patient)
      log.update_columns(created_at: 49.hours.ago)
      expect(log.within_draft_window?).to be false
    end
  end

  describe '#sign!' do
    let(:log) { create(:session_log, account: account, patient: patient, professional: professional) }

    it 'muda status para signed e registra signed_at/signed_by' do
      log.sign!(actor: actor)
      log.reload
      expect(log.status).to eq('signed')
      expect(log.signed_at).to be_present
      expect(log.signed_by_id).to eq(actor.id)
    end

    it 'cria PatientAuditLog com action sign' do
      expect { log.sign!(actor: actor) }.to change(PatientAuditLog, :count).by(1)
      audit = PatientAuditLog.last
      expect(audit.action).to eq('sign')
      expect(audit.actor_id).to eq(actor.id)
    end

    it 'rejeita sessão já assinada' do
      log.sign!(actor: actor)
      expect { log.sign!(actor: actor) }.to raise_error(Pundit::NotAuthorizedError)
    end

    it 'rejeita sessão fora da janela de edição' do
      log.update_columns(created_at: 49.hours.ago)
      expect { log.sign!(actor: actor) }.to raise_error(Pundit::NotAuthorizedError)
    end
  end

  describe '#mark_as_erratum!' do
    let(:log) { create(:session_log, :signed, account: account, patient: patient, professional: professional) }

    it 'registra erratum_at, erratum_by_id, erratum_reason' do
      log.mark_as_erratum!(actor: actor, reason: 'Lote errado')
      log.reload
      expect(log.erratum_at).to be_present
      expect(log.erratum_by_id).to eq(actor.id)
      expect(log.erratum_reason).to eq('Lote errado')
    end

    it 'rejeita errata em sessão draft' do
      draft = create(:session_log, account: account, patient: patient)
      expect {
        draft.mark_as_erratum!(actor: actor, reason: 'qualquer')
      }.to raise_error(/sessões assinadas/)
    end

    it 'rejeita errata duplicada' do
      log.mark_as_erratum!(actor: actor, reason: 'primeiro')
      expect {
        log.mark_as_erratum!(actor: actor, reason: 'segundo')
      }.to raise_error(/já está marcada/)
    end

    it 'rejeita reason vazio' do
      expect {
        log.mark_as_erratum!(actor: actor, reason: '')
      }.to raise_error(/Justificativa/)
    end
  end

  describe 'callback :prevent_edit_if_signed' do
    let(:log) { create(:session_log, :signed, account: account, patient: patient, professional: professional) }

    it 'bloqueia mudança de conteúdo clínico em sessão assinada' do
      log.assessment = 'Tentando alterar'
      expect(log.save).to be false
      expect(log.errors[:base]).to include(/não pode ser alterada/)
    end

    it 'permite atualizar campos de assinatura paciente em sessão assinada' do
      expect {
        log.update!(
          patient_signature_blob: 'data:image/png;base64,xxx',
          patient_signature_mode: 'local_tablet',
          patient_signed_at: Time.current,
          patient_signature_integrity_hash: 'hash',
          patient_signature_ip: '127.0.0.1'
        )
      }.not_to raise_error
    end

    it 'permite marcar errata em sessão assinada' do
      log.mark_as_erratum!(actor: actor, reason: 'errata teste')
      expect(log.reload.erratum_at).to be_present
    end
  end

  describe '#sign_patient_locally!' do
    let(:log) { create(:session_log, account: account, patient: patient) }

    it 'grava blob, mode local_tablet e timestamps' do
      log.sign_patient_locally!(
        signature_blob: 'data:image/png;base64,xxx',
        ip_address: '127.0.0.1',
        device_info: 'Test UA'
      )
      log.reload
      expect(log.patient_signature_mode).to eq('local_tablet')
      expect(log.patient_signed_at).to be_present
      expect(log.patient_signature_integrity_hash).to be_present
    end

    it 'rejeita assinatura duplicada' do
      log.sign_patient_locally!(signature_blob: 'data:x', ip_address: '127.0.0.1')
      expect {
        log.sign_patient_locally!(signature_blob: 'data:y', ip_address: '127.0.0.1')
      }.to raise_error(/já assinada/)
    end

    it 'rejeita blob vazio' do
      expect {
        log.sign_patient_locally!(signature_blob: '', ip_address: '127.0.0.1')
      }.to raise_error(/obrigatória/)
    end
  end

  describe '#sign_patient_remotely!' do
    let(:log) do
      create(:session_log, :with_remote_token, account: account, patient: patient)
    end

    it 'grava blob, mode remote_link e invalida o token' do
      log.sign_patient_remotely!(
        signature_blob: 'data:image/png;base64,xxx',
        ip_address: '127.0.0.1'
      )
      log.reload
      expect(log.patient_signature_mode).to eq('remote_link')
      expect(log.patient_signature_remote_token).to be_nil
    end

    it 'rejeita token expirado' do
      log.update_columns(patient_signature_remote_link_expires_at: 1.minute.ago)
      expect {
        log.sign_patient_remotely!(signature_blob: 'data:x', ip_address: '127.0.0.1')
      }.to raise_error(/expirado/)
    end
  end

  describe '#send_patient_remote_signature_link!' do
    let(:log) { create(:session_log, account: account, patient: patient) }

    it 'gera token único e expiração de 48h' do
      log.send_patient_remote_signature_link!
      log.reload
      expect(log.patient_signature_remote_token).to be_present
      expect(log.patient_signature_remote_token.length).to eq(64) # SecureRandom.hex(32)
      expect(log.patient_signature_remote_link_expires_at).to be_within(1.minute).of(48.hours.from_now)
    end
  end

  describe '#patient_signature_method' do
    it 'retorna "local" para local_tablet' do
      log = build(:session_log, patient_signature_mode: 'local_tablet')
      expect(log.patient_signature_method).to eq('local')
    end

    it 'retorna "remote" para remote_link' do
      log = build(:session_log, patient_signature_mode: 'remote_link')
      expect(log.patient_signature_method).to eq('remote')
    end

    it 'retorna nil sem mode' do
      log = build(:session_log, patient_signature_mode: nil)
      expect(log.patient_signature_method).to be_nil
    end
  end

  describe '#soft_delete!' do
    it 'marca deleted_at em sessão draft' do
      log = create(:session_log, account: account, patient: patient)
      expect { log.soft_delete! }.to change { log.deleted? }.from(false).to(true)
    end

    it 'rejeita soft_delete em sessão assinada' do
      log = create(:session_log, :signed, account: account, patient: patient)
      expect { log.soft_delete! }.to raise_error(/não pode ser excluída/)
    end
  end
end
