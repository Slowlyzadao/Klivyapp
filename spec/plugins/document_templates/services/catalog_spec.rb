# Specs do Catalog — PORO que agrega 55 variáveis em 4 categorias.
require 'rails_helper'

RSpec.describe DocumentTemplates::Catalog do
  describe '.all' do
    it 'retorna lista de Variables (estrutura imutável)' do
      expect(described_class.all).to all(be_a(DocumentTemplates::Variable))
    end

    it 'inclui pelo menos as 51 variáveis previstas no plano MVP' do
      # Plano §7.10: ~51 vars. Acima de 51 é OK (categoria expandida).
      expect(described_class.all.size).to be >= 51
    end

    it 'todas as keys são únicas' do
      keys = described_class.all.map(&:key)
      expect(keys.uniq.size).to eq(keys.size)
    end

    it 'todas as keys usam namespace.atributo' do
      described_class.all.each do |v|
        expect(v.key).to match(/\A[a-z_]+\.[a-z_]+\z/),
                         "Key #{v.key.inspect} fora do padrão namespace.atributo"
      end
    end
  end

  describe '.find' do
    it 'encontra variável por chave string' do
      v = described_class.find('patient.cpf')
      expect(v).to be_a(DocumentTemplates::Variable)
      expect(v.label).to eq('CPF')
      expect(v.formatter).to eq(:cpf)
    end

    it 'aceita Symbol também' do
      expect(described_class.find(:'patient.cpf')).to be_a(DocumentTemplates::Variable)
    end

    it 'retorna nil pra chave inexistente' do
      expect(described_class.find('foo.bar')).to be_nil
    end
  end

  describe '.find!' do
    it 'levanta ArgumentError pra chave inexistente' do
      expect { described_class.find!('foo.bar') }.to raise_error(ArgumentError, /Unknown variable/)
    end
  end

  describe '.categories' do
    it 'expõe as 4 categorias do MVP' do
      expect(described_class.categories).to match_array(%w[Paciente Clínica Profissional Data])
    end
  end

  describe '.for_frontend' do
    it 'retorna hashes planos com keys públicas' do
      payload = described_class.for_frontend
      expect(payload.first).to include(:key, :label, :category)
      expect(payload.first.keys).not_to include(:formatter) # formatter é detalhe interno
    end
  end

  describe '.grouped_for_frontend' do
    it 'agrupa por categoria' do
      grouped = described_class.grouped_for_frontend
      expect(grouped['Paciente']).to be_an(Array)
      expect(grouped['Paciente'].first[:key]).to start_with('patient.')
    end
  end
end
