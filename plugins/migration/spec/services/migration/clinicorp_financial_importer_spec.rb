require 'rails_helper'

RSpec.describe Migration::ClinicorpFinancialImporter do
  # ──────────────────────────────────────────────────────────────────────────
  # Mapas de tipo Clinicorp (validados na audit 2026-05-21). Spec garante
  # que o mapeamento não muda silenciosamente — se alguém alterar, força
  # decisão consciente sobre os efeitos em reconciliação financeira.
  # ──────────────────────────────────────────────────────────────────────────
  describe 'TYPE_TO_METHOD' do
    it 'mapeia os 10 tipos conhecidos da Clinicorp para payment_methods do Klivy' do
      # BOLETO_EXTERNAL + PIX_EXTERNAL adicionados ao revisar import real da
      # Streit #37 (2026-05-25). Clinicorp usa sufixo _EXTERNAL pra cobranças
      # processadas fora do gateway interno (Sicoob/PIX bancário etc.).
      expect(described_class::TYPE_TO_METHOD).to eq(
        'OTHER'                => 'dinheiro',
        'CREDIT_CARD_EXTERNAL' => 'credito',
        'DEBIT_CARD_EXTERNAL'  => 'debito',
        'BOLETO_INTERNAL'      => 'boleto',
        'BOLETO_EXTERNAL'      => 'boleto',
        'CREDIT_CARD_INTERNAL' => 'credito',
        'PIX'                  => 'pix',
        'PIX_EXTERNAL'         => 'pix',
        'CASH'                 => 'dinheiro',
        'DINHEIRO'             => 'dinheiro'
      )
    end

    it 'é frozen pra evitar mutação acidental em runtime' do
      expect(described_class::TYPE_TO_METHOD).to be_frozen
    end
  end

  describe 'TYPE_TO_GATEWAY' do
    it 'default é "manual" pra Type desconhecido (Clinicorp não tem gateway integrado)' do
      expect(described_class::TYPE_TO_GATEWAY['GATEWAY_QUE_NAO_EXISTE']).to eq('manual')
    end

    it 'todos os Type conhecidos caem em "manual" (Clinicorp não exporta gateway real)' do
      %w[OTHER CREDIT_CARD_EXTERNAL DEBIT_CARD_EXTERNAL BOLETO_INTERNAL BOLETO_EXTERNAL CREDIT_CARD_INTERNAL PIX PIX_EXTERNAL CASH DINHEIRO].each do |type|
        expect(described_class::TYPE_TO_GATEWAY[type]).to eq('manual'), "esperado 'manual' pra #{type}"
      end
    end

    it 'DEFAULT_GATEWAY é "manual"' do
      expect(described_class::DEFAULT_GATEWAY).to eq('manual')
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # resolve_payment_method — comportamento do fallback documentado:
  # vazio → 'dinheiro' silencioso (esperado, padrão Clinicorp pra muitos itens)
  # desconhecido → 'dinheiro' COM warning (sinal pra adicionar suporte)
  # ──────────────────────────────────────────────────────────────────────────
  describe '#resolve_payment_method (smoke via send)' do
    let(:account) { create(:account) }
    let(:run) do
      MigrationRun.create!(account_id: account.id, kind: 'financial',
                           source: 'clinicorp', csv_filename: 'PaymentItem.csv')
    end
    let(:importer) { described_class.new(run, budgets_csv: '', payment_headers_csv: '', payment_items_csv: '') }

    it 'retorna o método correto pra Type conhecido SEM logar warning' do
      result = importer.send(:resolve_payment_method, { 'Type' => 'PIX' }, 'item-1')
      expect(result).to eq('pix')
      expect(importer.instance_variable_get(:@errors)).to be_empty
    end

    it 'aceita Type em lower-case (faz upcase internamente)' do
      result = importer.send(:resolve_payment_method, { 'Type' => 'pix' }, 'item-1')
      expect(result).to eq('pix')
    end

    it 'Type vazio retorna "dinheiro" sem warning (default silencioso documentado)' do
      result = importer.send(:resolve_payment_method, { 'Type' => '' }, 'item-1')
      expect(result).to eq('dinheiro')
      expect(importer.instance_variable_get(:@errors)).to be_empty
    end

    it 'Type desconhecido (NÃO vazio) retorna "dinheiro" COM warning explícito' do
      result = importer.send(:resolve_payment_method, { 'Type' => 'CRYPTO_BITCOIN' }, 'item-99')
      expect(result).to eq('dinheiro')

      warnings = importer.instance_variable_get(:@errors)
      expect(warnings.size).to eq(1)
      expect(warnings.first[:level]).to eq('warning')
      expect(warnings.first[:line]).to eq('item-99')
      expect(warnings.first[:message]).to include('CRYPTO_BITCOIN')
      expect(warnings.first[:message]).to include('TYPE_TO_METHOD')
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # blank_counters — PR audit 2026-05-21 corrigiu o `created_entries`
  # ausente que ficava em lazy-init e nunca aparecia em flush_progress!.
  # ──────────────────────────────────────────────────────────────────────────
  describe '#blank_counters' do
    let(:account) { create(:account) }
    let(:run) do
      MigrationRun.create!(account_id: account.id, kind: 'financial',
                           source: 'clinicorp', csv_filename: 'PaymentItem.csv')
    end
    let(:importer) { described_class.new(run, budgets_csv: '', payment_headers_csv: '', payment_items_csv: '') }

    it 'inicializa created_entries em 0 (não pode mais cair em lazy-init nil)' do
      counters = importer.send(:blank_counters)
      expect(counters).to have_key(:created_entries)
      expect(counters[:created_entries]).to eq(0)
    end

    it 'contém todos os contadores documentados (regressão se alguém remover)' do
      counters = importer.send(:blank_counters)
      %i[budgets_total headers_total items_total
         processed_budgets processed_items
         created_budgets updated_budgets
         created_buckets created_items updated_items
         created_receipts created_entries
         skipped errors warnings].each do |key|
        expect(counters).to have_key(key), "blank_counters deveria ter :#{key}"
      end
    end
  end
end
