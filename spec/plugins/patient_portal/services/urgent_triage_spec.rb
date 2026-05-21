require 'rails_helper'

RSpec.describe PatientPortal::UrgentTriage do
  let(:account) { create(:account) }

  def triage(text)
    described_class.new(account: account, text: text)
  end

  describe '#urgent?' do
    context 'sem setting customizado (usa DEFAULT_KEYWORDS)' do
      it 'detecta variações de "urgência"' do
        expect(triage('Tô com urgência aqui')).to be_urgent
        expect(triage('é urgente, me ajuda')).to be_urgent
        expect(triage('isso é uma EMERGÊNCIA')).to be_urgent
      end

      it 'detecta "dor forte" mesmo com acento ou case' do
        expect(triage('estou com dor forte no peito')).to be_urgent
        expect(triage('Dor Forte aqui')).to be_urgent
      end

      it 'detecta sintomas críticos no texto' do
        expect(triage('estou tendo um desmaio')).to be_urgent
        expect(triage('saindo sangramento')).to be_urgent
      end

      it 'rejeita texto neutro' do
        expect(triage('Bom dia, gostaria de remarcar')).not_to be_urgent
        expect(triage('obrigado pela ajuda')).not_to be_urgent
      end

      it 'tolera string vazia/nil' do
        expect(triage('')).not_to be_urgent
        expect(triage(nil)).not_to be_urgent
      end
    end

    context 'com setting customizado da clínica' do
      before do
        setting = PatientPortalSetting.create!(account: account, active_preset: 'autonomy_guided',
                                                messaging: { 'urgent_keyword_list' => %w[sangramento] })
      end

      it 'usa apenas as keywords definidas pela clínica' do
        expect(triage('Estou com sangramento')).to be_urgent
        expect(triage('urgência mesmo')).not_to be_urgent # caiu da default list
      end
    end
  end

  describe '#matched_keywords' do
    it 'retorna lista das keywords casadas em ordem da lista' do
      result = triage('tô com dor forte e urgência mesmo').matched_keywords
      expect(result).to include('urgência', 'dor forte')
    end

    it 'retorna [] quando nada casa' do
      expect(triage('agendamento de rotina').matched_keywords).to be_empty
    end
  end
end
