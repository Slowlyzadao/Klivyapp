require 'rails_helper'

RSpec.describe Telemed::SessionIssuer do
  let(:account) { create(:account) }
  let(:patient) { create(:patient, account: account, name: 'Maria Teste') }

  # AgendaEvent stub mínimo — service só usa id, account_id.
  let(:event) { OpenStruct.new(id: 42, account_id: account.id, account: account) }

  describe '#call' do
    it 'gera token, URL e nome de sala determinístico' do
      result = described_class.new(event: event, participant: patient, role: 'patient').call

      expect(result.url).to eq('ws://localhost:7880')
      expect(result.room).to eq("klivy-acc#{account.id}-event42")
      # Identity tem prefix estável + nonce hex de 8 chars (anti-duplicate
      # ao recarregar a página). Validação por prefix + formato.
      expect(result.identity).to match(/\Apatient-#{patient.id}-[0-9a-f]{8}\z/)
      expect(result.name).to eq('Maria Teste')
      expect(result.token).to be_present
      expect(result.dev_mode).to eq(true)
    end

    it 'inclui o role na identity (paciente vs profissional na mesma room)' do
      r1 = described_class.new(event: event, participant: patient, role: 'patient').call
      r2 = described_class.new(event: event, participant: patient, role: 'doctor').call

      expect(r1.identity).to start_with('patient-')
      expect(r2.identity).to start_with('doctor-')
      expect(r1.room).to eq(r2.room) # mesma sala
    end

    it 'TTL default 2 horas (cobre consulta longa + reconexões)' do
      result = described_class.new(event: event, participant: patient).call
      expect(result.ttl_seconds).to eq(2.hours.to_i)
    end

    it 'TTL custom respeitado' do
      result = described_class.new(event: event, participant: patient, ttl: 5.minutes).call
      expect(result.ttl_seconds).to eq(300)
    end

    it 'token JWT decoda com a secret correta e contém grants esperados' do
      result = described_class.new(event: event, participant: patient).call
      decoded, _header = JWT.decode(result.token, 'secret', true, algorithm: 'HS256')
      expect(decoded['sub'] || decoded['identity']).to be_present
      # video grant fica no claim "video" do livekit-server-sdk
      expect(decoded['video']).to include('roomJoin' => true, 'room' => result.room)
    end

    it 'levanta quando credenciais não estão configuradas' do
      bad_creds = Telemed::CredentialsResolver::Credentials.new(
        url: nil, api_key: nil, api_secret: nil, source: :missing
      )
      allow_any_instance_of(Telemed::CredentialsResolver)
        .to receive(:call).and_return(bad_creds)

      expect {
        described_class.new(event: event, participant: patient).call
      }.to raise_error(/Credenciais LiveKit/)
    end
  end
end
