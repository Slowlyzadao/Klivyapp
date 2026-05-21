require 'rails_helper'

RSpec.describe PatientPortal::NotificationDispatcher do
  let(:account) { create(:account) }
  let(:patient) { create(:patient, account: account) }

  describe '.dispatch' do
    it 'cria uma PatientPortalNotification persistida' do
      expect {
        described_class.dispatch(
          account: account, patient: patient,
          kind: 'appointment_confirmed',
          title: 'Consulta confirmada',
          body:  'Sua consulta foi confirmada'
        )
      }.to change(PatientPortalNotification, :count).by(1)
    end

    it 'persiste payload customizado como jsonb' do
      notif = described_class.dispatch(
        account: account, patient: patient, kind: 'document_ready',
        title: 'Documento pronto', payload: { document_id: 42, type: 'atestado' }
      )

      expect(notif.payload['document_id']).to eq(42)
      expect(notif.payload['type']).to eq('atestado')
    end

    it 'retorna nil e LOGA quando o kind é inválido (não levanta)' do
      expect(Rails.logger).to receive(:error).with(/NotificationDispatcher/)
      result = described_class.dispatch(
        account: account, patient: patient, kind: 'foo_invalido',
        title: 'x'
      )
      expect(result).to be_nil
    end

    it 'retorna nil quando o título está em branco (validação no model)' do
      expect(Rails.logger).to receive(:error)
      result = described_class.dispatch(account: account, patient: patient,
                                        kind: 'generic', title: '')
      expect(result).to be_nil
    end

    it 'cria notificação não lida por padrão (read_at nil)' do
      notif = described_class.dispatch(account: account, patient: patient,
                                       kind: 'recall', title: 'Faz tempo')
      expect(notif.read_at).to be_nil
      expect(notif).to be_unread
    end
  end

  describe 'PatientPortalNotification#mark_read!' do
    it 'carimba read_at e marca lida' do
      notif = described_class.dispatch(account: account, patient: patient,
                                       kind: 'message_received', title: 'Nova mensagem')
      expect { notif.mark_read! }.to change { notif.reload.read? }.from(false).to(true)
    end

    it 'é idempotente — não muda read_at se já lida' do
      notif = described_class.dispatch(account: account, patient: patient,
                                       kind: 'message_received', title: 'Nova mensagem')
      notif.mark_read!
      original = notif.reload.read_at
      sleep 0.01
      notif.mark_read!
      expect(notif.reload.read_at).to eq(original)
    end
  end
end
