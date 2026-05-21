require 'rails_helper'

RSpec.describe PatientPortal::PushNotifier do
  let(:account) { create(:account) }
  let(:patient) { create(:patient, account: account) }

  def build_sub(endpoint:, disabled: false)
    sub = PatientPortalPushSubscription.create!(
      account: account, patient: patient,
      endpoint: endpoint, p256dh_key: 'pk', auth_key: 'auth'
    )
    sub.update_columns(disabled_at: Time.current) if disabled
    sub
  end

  subject(:notifier) { described_class.new(patient: patient) }

  describe '#deliver!' do
    it 'retorna zeros quando o paciente não tem subscriptions' do
      stats = notifier.deliver!(title: 'oi')
      expect(stats).to eq(delivered: 0, failed: 0, disabled: 0)
    end

    it 'envia mensagem JSON encodada com title/body/data via WebPush' do
      sub = build_sub(endpoint: 'https://fcm.googleapis.com/fcm/send/ok')

      received = nil
      allow(WebPush).to receive(:payload_send) { |opts| received = opts; true }

      notifier.deliver!(title: 'Pagamento confirmado',
                        body:  'parcela paga',
                        payload: { kind: 'financial_charge', url: '/financial' })

      expect(received[:endpoint]).to eq(sub.endpoint)
      expect(received[:p256dh]).to   eq(sub.p256dh_key)
      expect(received[:auth]).to     eq(sub.auth_key)

      msg = JSON.parse(received[:message])
      expect(msg['title']).to eq('Pagamento confirmado')
      expect(msg['body']).to  eq('parcela paga')
      expect(msg['data']).to  eq('kind' => 'financial_charge', 'url' => '/financial')
    end

    it 'conta sucessos e atualiza last_used_at na subscription' do
      sub = build_sub(endpoint: 'https://fcm.googleapis.com/fcm/send/ok')
      allow(WebPush).to receive(:payload_send).and_return(true)

      stats = notifier.deliver!(title: 'oi')
      expect(stats[:delivered]).to eq(1)
      expect(sub.reload.last_used_at).to be_present
      expect(sub.reload.failure_count).to eq(0)
    end

    it 'desativa subscription permanentemente em ExpiredSubscription' do
      sub = build_sub(endpoint: 'https://fcm.googleapis.com/fcm/send/dead')
      fake_response = double(code: '410', body: 'gone', inspect: '#<Response 410>')
      allow(WebPush).to receive(:payload_send)
        .and_raise(WebPush::ExpiredSubscription.new(fake_response, 'fcm.googleapis.com'))

      stats = notifier.deliver!(title: 'oi')
      expect(stats[:disabled]).to eq(1)
      expect(sub.reload.disabled?).to eq(true)
    end

    it 'incrementa failure_count em erro transiente sem desativar imediatamente' do
      sub = build_sub(endpoint: 'https://fcm.googleapis.com/fcm/send/timeout')
      allow(WebPush).to receive(:payload_send).and_raise(StandardError.new('boom'))

      stats = notifier.deliver!(title: 'oi')
      expect(stats[:failed]).to eq(1)
      expect(sub.reload.failure_count).to eq(1)
      expect(sub.reload.disabled?).to eq(false)
    end

    it 'ignora subscriptions já desativadas' do
      build_sub(endpoint: 'https://fcm.googleapis.com/fcm/send/active')
      build_sub(endpoint: 'https://fcm.googleapis.com/fcm/send/dead', disabled: true)

      allow(WebPush).to receive(:payload_send).and_return(true)
      stats = notifier.deliver!(title: 'oi')
      expect(stats[:delivered]).to eq(1)
    end
  end
end
