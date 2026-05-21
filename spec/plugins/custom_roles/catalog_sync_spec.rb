require 'rails_helper'

# Detector de drift entre os 2 catálogos de permissões do Klivy:
#
#   - Ruby:   plugins/custom_roles/app/models/klivy_role/permissions_catalog.rb
#             (usado pelo sanitize_and_migrate no model + enforce_delegation_limit!
#              no controller + seed presets)
#
#   - JS:     plugins/custom_roles/frontend/shared/modules.js
#             (fonte da UI do editor de role + sidebar gating + router guards)
#
# Drift entre os dois causa bugs sutis:
#
#   - Perm SÓ no Ruby (faltando no JS): backend reconhece mas admin não
#     consegue marcar no editor → perm inacessível pra non-admin.
#
#   - Perm SÓ no JS (faltando no Ruby): admin marca no editor, mas
#     sanitize_and_migrate DROPA silenciosamente no save → admin acha que
#     salvou mas a perm volta false ao recarregar (confusão UX).
#
# Este spec roda no CI e falha se houver drift. Estratégia: extrair todas as
# `key: 'xxx'` strings do modules.js via regex e verificar que cada
# (módulo, permissão) declarada no Ruby catalog também existe textualmente
# no JS. Cobertura assimétrica intencional — Ruby → JS é o drift mais comum.
#
# Workflow obrigatório ao adicionar uma perm nova:
#   1. modules.js — adicionar entrada `{ key: 'novo_perm', label: '...' }`
#   2. permissions_catalog.rb — adicionar 'novo_perm' no array do módulo
#   3. (opcional) presets.js + preset_definitions.rb — setar true no preset
#   4. usar `beclinic_can?(:mod, :novo_perm)` no policy/controller relevante
#   5. usar `usePermissions().can('mod', 'novo_perm')` no frontend
#
# Detalhes em docs/AGENTS.md seção "RBAC Klivy / Custom Roles".

RSpec.describe KlivyRole::PermissionsCatalog do
  let(:modules_js_path) { Rails.root.join('plugins/custom_roles/frontend/shared/modules.js') }
  let(:modules_js_content) { File.read(modules_js_path) }

  # Extrai TODAS as ocorrências de `key: 'xxx'` ou `key: "xxx"` do modules.js.
  # Cobre tanto module keys quanto permission keys quanto group keys.
  # Suficiente pra "esta perm existe no JS?" sem precisar parser AST.
  let(:js_key_strings) do
    modules_js_content.scan(/\bkey:\s*['"]([a-z_]+)['"]/).flatten.to_set
  end

  it 'Ruby catalog has at least 1 module' do
    expect(described_class::CATALOG).not_to be_empty
  end

  it 'every module key in Ruby catalog appears in modules.js' do
    missing = described_class::CATALOG.keys.reject { |mod| js_key_strings.include?(mod) }
    expect(missing).to be_empty,
      "Module keys no Ruby catalog mas FALTANDO em modules.js: #{missing.inspect}\n" \
      "Solução: adicionar a entrada `{ key: '<mod>', label: '...', permissions: [...] }` " \
      "em modules.js, ou remover do permissions_catalog.rb."
  end

  it 'every permission key in Ruby catalog appears in modules.js' do
    missing = []
    described_class::CATALOG.each do |mod_key, perms|
      perms.each do |perm_key|
        missing << "#{mod_key}.#{perm_key}" unless js_key_strings.include?(perm_key)
      end
    end
    expect(missing).to be_empty,
      "Permissões no Ruby catalog mas FALTANDO em modules.js: #{missing.inspect}\n" \
      "Solução: adicionar `{ key: '<perm>', label: '...' }` em modules.js no módulo " \
      "correspondente, OU remover do array do módulo no permissions_catalog.rb."
  end

  it 'LEGACY_KEY_MIGRATIONS keys de destino existem no Ruby catalog' do
    invalid = []
    described_class::LEGACY_KEY_MIGRATIONS.each do |mod_key, migrations|
      migrations.each do |legacy_key, new_keys|
        new_keys.each do |new_key|
          unless described_class::CATALOG[mod_key]&.include?(new_key)
            invalid << "#{mod_key}.#{legacy_key} → #{mod_key}.#{new_key}"
          end
        end
      end
    end
    expect(invalid).to be_empty,
      "LEGACY_KEY_MIGRATIONS aponta pra keys que NÃO estão no CATALOG: #{invalid.inspect}\n" \
      "Solução: adicionar a key nova no CATALOG ou ajustar a migração legada."
  end

  it 'sanitize_and_migrate é idempotente (rodar 2x = rodar 1x)' do
    sample = {
      'patients' => { 'view' => true, 'create' => true, 'scope' => 'own' },
      'agenda' => { 'view' => true },
      'unknown_module' => { 'foo' => true },
      'chat' => { 'reply' => true, 'invalid_key' => true }
    }
    first  = described_class.sanitize_and_migrate(sample)
    second = described_class.sanitize_and_migrate(first)
    expect(second).to eq(first)
  end

  it 'sanitize_and_migrate dropa módulos desconhecidos' do
    out = described_class.sanitize_and_migrate('fakemodule' => { 'view' => true })
    expect(out).not_to have_key('fakemodule')
  end

  it 'sanitize_and_migrate dropa permissões desconhecidas dentro de módulo válido' do
    out = described_class.sanitize_and_migrate('patients' => { 'view' => true, 'definitely_invalid_perm' => true })
    expect(out['patients']).to have_key('view')
    expect(out['patients']).not_to have_key('definitely_invalid_perm')
  end

  it 'sanitize_and_migrate aceita ActionController::Parameters' do
    params = ActionController::Parameters.new(patients: { view: true })
    out = described_class.sanitize_and_migrate(params)
    expect(out['patients']).to eq('view' => true)
  end

  it 'sanitize_and_migrate migra LEGACY_KEY_MIGRATIONS automaticamente' do
    out = described_class.sanitize_and_migrate('settings' => { 'manage_users' => true })
    expect(out['settings']).to include(
      'users_view' => true, 'users_invite' => true,
      'users_edit' => true, 'users_remove' => true
    )
  end

  it 'sanitize_and_migrate valida scope ∈ {all, own}' do
    out_valid = described_class.sanitize_and_migrate('patients' => { 'scope' => 'own', 'view' => true })
    expect(out_valid['patients']['scope']).to eq('own')

    out_invalid = described_class.sanitize_and_migrate('patients' => { 'scope' => 'invalid', 'view' => true })
    expect(out_invalid['patients']).not_to have_key('scope')
  end
end
