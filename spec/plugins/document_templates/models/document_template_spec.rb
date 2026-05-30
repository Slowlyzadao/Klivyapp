# Specs do DocumentTemplate — model central do plugin document_templates.
# Cobertura: validações estruturais, regras de consistência (account/source),
# scopes, callbacks (bump_version, archived_at sync), helpers (family).
require 'rails_helper'

RSpec.describe DocumentTemplate do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:valid_content) { { 'type' => 'doc', 'content' => [{ 'type' => 'paragraph' }] } }

  def build_template(**overrides)
    described_class.new(
      account: account,
      name: 'Atestado teste',
      document_type: 'atestado',
      source: 'clinic',
      status: 'active',
      content_json: valid_content,
      **overrides
    )
  end

  describe 'validações estruturais' do
    it 'aceita um template clinic válido' do
      expect(build_template).to be_valid
    end

    it 'requer name' do
      tpl = build_template(name: nil)
      expect(tpl).not_to be_valid
      expect(tpl.errors[:name]).to be_present
    end

    it 'requer document_type' do
      tpl = build_template(document_type: nil)
      expect(tpl).not_to be_valid
      expect(tpl.errors[:document_type]).to be_present
    end

    it 'recusa document_type fora do whitelist' do
      tpl = build_template(document_type: 'tipo_inexistente')
      expect(tpl).not_to be_valid
    end

    it 'recusa content_json sem type:doc' do
      tpl = build_template(content_json: { 'foo' => 'bar' })
      expect(tpl).not_to be_valid
      expect(tpl.errors[:content_json]).to be_present
    end

    it 'recusa content_json com node forbidden (script)' do
      payload = {
        'type' => 'doc',
        'content' => [{ 'type' => 'script', 'content' => [] }]
      }
      tpl = build_template(content_json: payload)
      expect(tpl).not_to be_valid
      expect(tpl.errors[:content_json].join).to include('forbidden')
    end

    it 'recusa content_json acima do limite de bytes' do
      huge_text = 'a' * (DocumentTemplate::MAX_CONTENT_JSON_BYTES + 100)
      payload = {
        'type' => 'doc',
        'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => huge_text }] }]
      }
      tpl = build_template(content_json: payload)
      expect(tpl).not_to be_valid
      expect(tpl.errors[:content_json].join).to match(/exceeds/i)
    end
  end

  describe 'consistência account ↔ source' do
    it 'klivy templates devem ter account_id NULL' do
      tpl = build_template(source: 'klivy')
      expect(tpl).not_to be_valid
      expect(tpl.errors[:account_id]).to be_present
    end

    it 'klivy template é válido sem account' do
      tpl = build_template(account: nil, source: 'klivy')
      expect(tpl).to be_valid
    end

    it 'clinic templates devem ter account_id' do
      tpl = build_template(account: nil, source: 'clinic')
      expect(tpl).not_to be_valid
    end

    it 'cloned exige source_template_id' do
      tpl = build_template(source: 'cloned')
      expect(tpl).not_to be_valid
      expect(tpl.errors[:source_template_id]).to be_present
    end
  end

  describe 'scopes' do
    let!(:klivy)     { described_class.create!(account: nil, name: 'K', document_type: 'atestado', source: 'klivy',  status: 'active', content_json: valid_content) }
    let!(:clinic)    { described_class.create!(account: account, name: 'C', document_type: 'atestado', source: 'clinic', status: 'active', content_json: valid_content) }
    let!(:archived)  { described_class.create!(account: account, name: 'A', document_type: 'atestado', source: 'clinic', status: 'archived', content_json: valid_content) }
    let!(:consent)   { described_class.create!(account: account, name: 'Cnsnt', document_type: 'consentimento_lgpd', source: 'clinic', status: 'active', content_json: valid_content) }

    it 'active filtra archived fora' do
      expect(described_class.active).to include(klivy, clinic, consent)
      expect(described_class.active).not_to include(archived)
    end

    it 'klivy retorna só templates globais (account_id NULL)' do
      # Usa `include` em vez de `contain_exactly` porque o seed da Fase 2
      # popula 22 Klivy globais que coexistem com os criados no test.
      expect(described_class.klivy).to include(klivy)
      expect(described_class.klivy).not_to include(clinic, consent)
    end

    it 'for_account inclui templates próprios + Klivy globais' do
      result = described_class.for_account(account)
      expect(result).to include(klivy, clinic, archived, consent)
    end

    it 'clinical exclui consents' do
      expect(described_class.clinical).to include(klivy, clinic)
      expect(described_class.clinical).not_to include(consent)
    end

    it 'consents inclui o tipo consentimento_*' do
      expect(described_class.consents).to include(consent)
      expect(described_class.consents).not_to include(klivy, clinic, archived)
    end
  end

  describe '#family' do
    it 'retorna :clinical pra tipos clínicos' do
      expect(build_template(document_type: 'atestado').family).to eq(:clinical)
    end

    it 'retorna :consent pra consentimentos' do
      expect(build_template(document_type: 'consentimento_lgpd').family).to eq(:consent)
    end
  end

  describe 'callbacks de versão' do
    it 'create começa com version=1' do
      tpl = described_class.create!(account: account, name: 'V1', document_type: 'atestado', source: 'clinic', status: 'active', content_json: valid_content)
      expect(tpl.version).to eq(1)
    end

    it 'update no content_json bumpa version' do
      tpl = described_class.create!(account: account, name: 'V', document_type: 'atestado', source: 'clinic', status: 'active', content_json: valid_content)
      new_content = valid_content.deep_dup
      new_content['content'] << { 'type' => 'paragraph' }
      tpl.update!(content_json: new_content)
      expect(tpl.reload.version).to eq(2)
    end

    it 'update em name (sem mudar content) NÃO bumpa version' do
      tpl = described_class.create!(account: account, name: 'V', document_type: 'atestado', source: 'clinic', status: 'active', content_json: valid_content)
      tpl.update!(name: 'V renamed')
      expect(tpl.reload.version).to eq(1)
    end
  end

  describe 'archived_at sync' do
    it 'preenche archived_at quando status vira archived' do
      tpl = described_class.create!(account: account, name: 'X', document_type: 'atestado', source: 'clinic', status: 'active', content_json: valid_content)
      tpl.update!(status: 'archived')
      expect(tpl.archived_at).to be_present
    end

    it 'limpa archived_at quando reativa' do
      tpl = described_class.create!(account: account, name: 'X', document_type: 'atestado', source: 'clinic', status: 'archived', content_json: valid_content)
      expect(tpl.archived_at).to be_present
      tpl.update!(status: 'active')
      expect(tpl.archived_at).to be_nil
    end
  end
end
