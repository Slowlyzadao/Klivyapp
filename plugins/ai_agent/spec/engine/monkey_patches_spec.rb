# ARCH-12 (auditoria 2026-05-19): spec de DRIFT DETECTION pros
# monkey-patches que o engine `AiAgent` aplica em classes do Chatwoot
# core (`Captain::Assistant`, `Captain::Conversation::ResponseBuilderJob`).
#
# Esses patches existem porque a Bea é uma "system assistant" — ela
# vem pré-configurada em toda conta e seu nome é parte da marca.
# Permitir rename/destroy via API quebra TODO o stack downstream
# (PromptBuilder lookups, sidebar entry, AgentBot binding).
#
# Se Chatwoot upgradar e mudar:
#   - O nome/módulo do model `Captain::Assistant` → patches silenciosamente
#     não aplicam (o `if defined?(...)` retorna false sem erro)
#   - A API de callbacks (`before_destroy`/`after_save`) → comportamento
#     muda silenciosamente
#   - O `Captain::Conversation::ResponseBuilderJob` (legacy autoresponder)
#     → Bea responde DUAS vezes pra cada mensagem
#
# Essas specs FALHAM ALTO quando o drift acontece, dando sinal cedo
# em CI antes do bug atingir produção.

require 'rails_helper'

RSpec.describe 'AiAgent engine monkey-patches drift detection' do
  describe 'Captain::Assistant' do
    it 'classe ainda existe no Chatwoot core' do
      expect(defined?(::Captain::Assistant)).to eq('constant')
      expect(::Captain::Assistant).to be < ApplicationRecord
    end

    it 'tem o atributo :name esperado pelos patches' do
      expect(::Captain::Assistant.column_names).to include('name', 'account_id', 'config')
    end

    it 'protect_beatriz_destroy callback foi instalado' do
      callbacks = ::Captain::Assistant._destroy_callbacks.map { |cb| cb.filter.to_s }
      expect(callbacks).to include('protect_beatriz_destroy'),
                           "drift: before_destroy :protect_beatriz_destroy não está registrado em Captain::Assistant. " \
                           "Patch em plugins/ai_agent/lib/ai_agent/engine.rb#L189 falhou silenciosamente."
    end

    it 'protect_beatriz_rename callback foi instalado' do
      callbacks = ::Captain::Assistant._update_callbacks.map { |cb| cb.filter.to_s }
      expect(callbacks).to include('protect_beatriz_rename'),
                           'drift: before_update :protect_beatriz_rename não está registrado em Captain::Assistant.'
    end

    it 'sync_bea_enabled_to_account_setting callback foi instalado' do
      callbacks = ::Captain::Assistant._save_callbacks.map { |cb| cb.filter.to_s }
      expect(callbacks).to include('sync_bea_enabled_to_account_setting'),
                           'drift: after_save :sync_bea_enabled_to_account_setting não está registrado.'
    end

    describe 'comportamento — protect_beatriz_destroy' do
      let(:account) { create(:account) }
      # Beatriz é auto-criada via `Account.after_create_commit :ensure_default_bea_assistant`.
      let!(:beatriz) { ::Captain::Assistant.find_by!(account_id: account.id, name: 'Beatriz') }

      it 'NÃO permite destruir Beatriz via API normal' do
        beatriz_id = beatriz.id
        result = beatriz.destroy
        expect(result).to be_falsey
        expect(beatriz.errors[:base]).to include('A assistente Beatriz não pode ser excluída.')
        expect(::Captain::Assistant.exists?(beatriz_id)).to be(true)
      end

      it 'PERMITE destruir outras assistentes (proteção é só pra Beatriz)' do
        other = ::Captain::Assistant.create!(account: account, name: 'Atendente X', description: 'desc')
        expect { other.destroy }.to change(::Captain::Assistant, :count).by(-1)
      end
    end

    describe 'comportamento — protect_beatriz_rename' do
      let(:account) { create(:account) }
      let(:beatriz) { ::Captain::Assistant.find_by!(account_id: account.id, name: 'Beatriz') }

      it 'reverte o nome se alguém tentar renomear Beatriz' do
        beatriz.name = 'Maria'
        beatriz.save!
        expect(beatriz.reload.name).to eq('Beatriz')
      end

      it 'permite renomear outras assistentes' do
        other = ::Captain::Assistant.create!(account: account, name: 'Atendente Z', description: 'd')
        other.update!(name: 'Recepcionista')
        expect(other.reload.name).to eq('Recepcionista')
      end
    end

    describe 'comportamento — sync_bea_enabled_to_account_setting' do
      let(:account) { create(:account) }
      let(:beatriz) { ::Captain::Assistant.find_by!(account_id: account.id, name: 'Beatriz') }

      it 'mirrora config["bea_enabled"]=false pra AccountSetting.enabled=false' do
        AiAgent::AccountSetting.find_or_initialize_by(account_id: account.id).tap do |s|
          s.enabled = true
          s.save!
        end

        beatriz.update!(config: beatriz.config.merge('bea_enabled' => false))

        setting = AiAgent::AccountSetting.find_by!(account_id: account.id)
        expect(setting.enabled).to be(false)
      end

      it 'mirrora bea_enabled=true (default) pra AccountSetting.enabled=true' do
        AiAgent::AccountSetting.find_or_initialize_by(account_id: account.id).tap do |s|
          s.enabled = false
          s.save!
        end

        beatriz.update!(config: beatriz.config.merge('bea_enabled' => true))

        setting = AiAgent::AccountSetting.find_by!(account_id: account.id)
        expect(setting.enabled).to be(true)
      end
    end
  end

  describe 'Captain::Conversation::ResponseBuilderJob' do
    it 'classe ainda existe no Chatwoot core' do
      expect(defined?(::Captain::Conversation::ResponseBuilderJob)).to eq('constant')
    end

    it 'SkipBeatrizLegacyResponse foi prepended (curto-circuito do legacy autoresponder pra Bea)' do
      expect(::Captain::Conversation::ResponseBuilderJob.include?(AiAgent::SkipBeatrizLegacyResponse)).to be(true),
                                                                                                         'drift: AiAgent::SkipBeatrizLegacyResponse não foi prepended em ' \
                                                                                                         'Captain::Conversation::ResponseBuilderJob. Sem isso, mensagens da Bea ' \
                                                                                                         'recebem RESPOSTA DUPLA (nossa + legacy autoresponder do Captain).'
    end
  end

  describe 'Account auto-create Beatriz' do
    it 'ensure_default_bea_assistant callback foi instalado' do
      callbacks = Account._commit_callbacks.map { |cb| cb.filter.to_s }
      expect(callbacks).to include('ensure_default_bea_assistant')
    end

    it 'cria Beatriz automaticamente em accounts novas' do
      account = create(:account)
      beatriz = ::Captain::Assistant.find_by(account_id: account.id, name: 'Beatriz')
      expect(beatriz).to be_present
      expect(beatriz.description).to include('Beatriz é a assistente virtual da Klivy')
    end

    it 'NÃO duplica Beatriz se já existir' do
      account = create(:account)
      original = ::Captain::Assistant.find_by!(account_id: account.id, name: 'Beatriz')
      # Re-trigger callback manualmente — simula reload em dev
      account.send(:ensure_default_bea_assistant)
      expect(::Captain::Assistant.where(account_id: account.id, name: 'Beatriz').count).to eq(1)
      expect(::Captain::Assistant.find_by(account_id: account.id, name: 'Beatriz').id).to eq(original.id)
    end
  end
end
