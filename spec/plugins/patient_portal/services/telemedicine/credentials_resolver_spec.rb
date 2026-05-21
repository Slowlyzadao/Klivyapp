require 'rails_helper'

RSpec.describe Telemed::CredentialsResolver do
  let(:account) { create(:account) }

  subject(:resolver) { described_class.new(account: account) }

  describe '#call' do
    context 'sem nada configurado' do
      it 'retorna defaults dev (ws://localhost:7880, devkey/secret)' do
        creds = with_clean_env { resolver.call }
        expect(creds.source).to eq(:dev_defaults)
        expect(creds.url).to eq('ws://localhost:7880')
        expect(creds.api_key).to eq('devkey')
        expect(creds.api_secret).to eq('secret')
        expect(creds.dev_mode?).to eq(true)
      end
    end

    context 'com ENV vars setadas' do
      it 'retorna source=env e valores das vars' do
        creds = with_env('LIVEKIT_URL' => 'wss://prod.example/ws',
                         'LIVEKIT_API_KEY' => 'APIabc',
                         'LIVEKIT_API_SECRET' => 'super-secret') { resolver.call }
        expect(creds.source).to eq(:env)
        expect(creds.url).to eq('wss://prod.example/ws')
        expect(creds.api_key).to eq('APIabc')
        expect(creds.dev_mode?).to eq(false)
      end

      it 'ignora ENV incompleto (falta a secret) e cai pros defaults' do
        creds = with_env('LIVEKIT_URL' => 'wss://x', 'LIVEKIT_API_KEY' => 'k') { resolver.call }
        expect(creds.source).to eq(:dev_defaults)
      end
    end

    context 'com setting self_hosted da clínica' do
      before do
        PatientPortalSetting.create!(
          account: account, active_preset: 'autonomy_guided',
          scheduling: {
            'telemedicine' => {
              'mode' => 'self_hosted',
              'url' => 'wss://lk.clinica.com',
              'api_key' => 'clinic_key',
              'api_secret' => 'clinic_secret'
            }
          }
        )
      end

      it 'retorna source=account_setting com credenciais da clínica' do
        creds = with_clean_env { resolver.call }
        expect(creds.source).to eq(:account_setting)
        expect(creds.url).to eq('wss://lk.clinica.com')
        expect(creds.api_key).to eq('clinic_key')
      end

      it 'tem prioridade sobre ENV' do
        creds = with_env('LIVEKIT_URL' => 'wss://env',
                         'LIVEKIT_API_KEY' => 'envk',
                         'LIVEKIT_API_SECRET' => 'envs') { resolver.call }
        expect(creds.source).to eq(:account_setting)
      end
    end

    context 'setting mode=klivy_hosted (não self_hosted)' do
      before do
        PatientPortalSetting.create!(
          account: account, active_preset: 'autonomy_guided',
          scheduling: { 'telemedicine' => { 'mode' => 'klivy_hosted' } }
        )
      end

      it 'ignora setting e usa ENV/defaults' do
        creds = with_clean_env { resolver.call }
        expect(creds.source).to eq(:dev_defaults)
      end
    end
  end

  private

  def with_env(vars)
    orig = vars.transform_values { |_| nil }
    vars.each { |k, _| orig[k] = ENV[k] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    orig.each { |k, v| ENV[k] = v }
  end

  def with_clean_env(&block)
    with_env('LIVEKIT_URL' => nil, 'LIVEKIT_API_KEY' => nil, 'LIVEKIT_API_SECRET' => nil, &block)
  end
end
