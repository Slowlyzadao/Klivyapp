require 'rails_helper'

RSpec.describe Migration::ClinicorpTreatmentOperationImporter do
  # ──────────────────────────────────────────────────────────────────────────
  # Constantes documentadas (PR audit 2026-05-21): antes eram literais
  # hardcoded em `treatment_item_attributes`. Extraídos pra deixar claro que
  # são DECISÕES DE PRODUTO, não bugs silenciosos. Spec garante que ficaram
  # com os valores combinados — se alguém mudar, o teste quebra e força
  # revisão consciente.
  # ──────────────────────────────────────────────────────────────────────────
  describe 'defaults de TreatmentItem' do
    it 'DEFAULT_ITEM_PRIORITY é "media"' do
      expect(described_class::DEFAULT_ITEM_PRIORITY).to eq('media')
    end

    it 'DEFAULT_ITEM_STATUS é "aprovado"' do
      expect(described_class::DEFAULT_ITEM_STATUS).to eq('aprovado')
    end

    it 'DEFAULT_ITEM_DISCOUNT_CENTS é 0' do
      expect(described_class::DEFAULT_ITEM_DISCOUNT_CENTS).to eq(0)
    end

    it 'constantes são imutáveis (freeze)' do
      expect(described_class::DEFAULT_ITEM_PRIORITY).to be_frozen
      expect(described_class::DEFAULT_ITEM_STATUS).to be_frozen
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Smoke test do treatment_item_attributes — método privado, mas é o ponto
  # onde os defaults batem o disco. Garante que o hash gerado contém o que
  # o spec acima exigir (regressão se alguém trocar nome da chave).
  # ──────────────────────────────────────────────────────────────────────────
  describe '#treatment_item_attributes (smoke via send)' do
    let(:account) { create(:account) }
    let(:run) do
      MigrationRun.create!(account_id: account.id, kind: 'treatment_operations',
                           source: 'clinicorp', csv_filename: 'TreatmentOperation.csv')
    end
    let(:importer) { described_class.new(run, operations_csv: '', dentist_mapping: {}) }
    let(:mapped) do
      {
        procedure_name: 'Limpeza Profilática',
        surface: 'oclusal',
        tooth: '36',
        notes: 'Observação clínica de exemplo',
        operation_id: 'clinicorp-op-1'
      }
    end

    subject(:attrs) { importer.send(:treatment_item_attributes, 42, mapped) }

    it 'aplica DEFAULT_ITEM_PRIORITY no campo priority' do
      expect(attrs[:priority]).to eq(described_class::DEFAULT_ITEM_PRIORITY)
    end

    it 'aplica DEFAULT_ITEM_STATUS no campo status' do
      expect(attrs[:status]).to eq(described_class::DEFAULT_ITEM_STATUS)
    end

    it 'aplica DEFAULT_ITEM_DISCOUNT_CENTS em discount_value' do
      expect(attrs[:discount_value]).to eq(described_class::DEFAULT_ITEM_DISCOUNT_CENTS)
    end

    it 'preserva external_ids com clinicorp_operation_id pra idempotência' do
      expect(attrs[:external_ids]).to eq('clinicorp_operation_id' => 'clinicorp-op-1')
    end

    it 'unit_price fica nil — coluna Amount do CSV é 0% preenchida' do
      expect(attrs[:unit_price]).to be_nil
    end

    it 'trunca procedure_name em 255 chars (limite do banco)' do
      long_name = 'X' * 500
      result = importer.send(:treatment_item_attributes, 42, mapped.merge(procedure_name: long_name))
      expect(result[:procedure_name].length).to eq(255)
    end

    it 'aplica fallback "Procedimento Clinicorp" quando procedure_name é nil' do
      result = importer.send(:treatment_item_attributes, 42, mapped.merge(procedure_name: nil))
      expect(result[:procedure_name]).to eq('Procedimento Clinicorp')
    end
  end
end
