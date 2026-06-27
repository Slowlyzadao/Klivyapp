# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Patients::SessionLogFinalizer do
  let(:account)      { create(:account) }
  let(:patient)      { create(:patient, account: account) }
  let(:professional) { create(:user, account: account) }
  let(:admin)        { create(:user, account: account, role: 'administrator') }
  let(:other_user)   { create(:user, account: account) }

  let(:log) do
    create(:session_log,
           account: account, patient: patient, professional: professional)
  end

  describe '.call' do
    context 'quando o ator é o profissional que criou' do
      it 'assina e retorna success' do
        result = described_class.call(session_log: log, actor: professional)
        expect(result.success?).to be true
        expect(log.reload.status).to eq('signed')
      end
    end

    context 'quando o ator é admin' do
      it 'assina mesmo sem ser o criador' do
        result = described_class.call(session_log: log, actor: admin)
        expect(result.success?).to be true
        expect(log.reload.signed_by_id).to eq(admin.id)
      end
    end

    context 'quando o ator é outro user (não criador, não admin)' do
      it 'retorna erro de autorização' do
        result = described_class.call(session_log: log, actor: other_user)
        expect(result.success?).to be false
        expect(result.error).to match(/não tem permissão/)
        expect(log.reload.status).to eq('draft')
      end
    end

    context 'quando a sessão já está assinada' do
      it 'retorna erro' do
        log.sign!(actor: professional)
        result = described_class.call(session_log: log, actor: professional)
        expect(result.success?).to be false
        expect(result.error).to match(/já está assinada/)
      end
    end

    context 'quando fora da janela de edição' do
      it 'retorna erro' do
        log.update_columns(created_at: 49.hours.ago)
        result = described_class.call(session_log: log, actor: professional)
        expect(result.success?).to be false
        expect(result.error).to match(/Janela de edição/)
      end
    end
  end
end
