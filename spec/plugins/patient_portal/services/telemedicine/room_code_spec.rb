require 'rails_helper'

# Sprint K — slug estilo Google Meet pra sala de telemedicina.
# Foco do spec: formato + parsing reverso. Não exercita persistência —
# o service é puro (sem DB).
RSpec.describe Telemed::RoomCode do
  describe '.from_event' do
    let(:event) { instance_double('AgendaEvent', id: 284, account_id: 76) }

    it 'gera slug pppp-eeee-aaaa zero-padded com 4 dígitos por segmento' do
      patient = double('Patient', id: 17)
      expect(described_class.from_event(event, patient: patient))
        .to eq('0017-0284-0076')
    end

    it 'aceita patient como integer direto' do
      expect(described_class.from_event(event, patient: 17))
        .to eq('0017-0284-0076')
    end

    it 'cai pra 0000 quando patient é nil e o evento não resolve patient' do
      allow(event).to receive(:try).with(:patient).and_return(nil)
      allow(event).to receive(:try).with(:contact).and_return(nil)
      expect(described_class.from_event(event))
        .to eq('0000-0284-0076')
    end

    it 'preserva números maiores que 9999 (clínica com 10k+ eventos)' do
      big_event = instance_double('AgendaEvent', id: 12_345, account_id: 76)
      patient = double('Patient', id: 17)
      expect(described_class.from_event(big_event, patient: patient))
        .to eq('0017-12345-0076')
    end

    it 'retorna nil quando event é nil' do
      expect(described_class.from_event(nil)).to be_nil
    end
  end

  describe '.parse' do
    it 'retorna hash com IDs inteiros' do
      expect(described_class.parse('0017-0284-0076'))
        .to eq(patient_id: 17, event_id: 284, account_id: 76)
    end

    it 'aceita IDs sem zero-pad' do
      expect(described_class.parse('17-284-76'))
        .to eq(patient_id: 17, event_id: 284, account_id: 76)
    end

    it 'retorna nil quando slug tem menos de 3 segmentos' do
      expect(described_class.parse('17-284')).to be_nil
    end

    it 'retorna nil quando segmentos não são numéricos' do
      expect(described_class.parse('17-abc-76')).to be_nil
    end

    it 'retorna nil quando input não é string' do
      expect(described_class.parse(nil)).to be_nil
      expect(described_class.parse(17)).to be_nil
    end
  end

  describe '.slug?' do
    it 'true pra strings com hífen' do
      expect(described_class.slug?('0017-0284-0076')).to be(true)
    end

    it 'false pra id puro numérico (string ou integer)' do
      expect(described_class.slug?('284')).to be(false)
      expect(described_class.slug?(284)).to be(false)
    end

    it 'false pra nil' do
      expect(described_class.slug?(nil)).to be(false)
    end
  end
end
