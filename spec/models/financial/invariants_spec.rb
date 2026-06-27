# frozen_string_literal: true

require 'rails_helper'

# Invariantes críticos do módulo financeiro v2.
#
# Cada bloco aqui defende uma garantia que o canon `mapa-financeiro.json`
# considera inegociável. Se um teste cair, é regressão de segurança/dado.
#
# Fase 5 (housekeeping pós-reescrita 2026-05-22). Cobre:
#   1. Multi-tenant: find scoping por account_id
#   2. Soft-delete: find_by alive
#   3. Frozen attributes: imutabilidade após criação
#   4. Period closure: bloqueia mutação em mês fechado
#   5. AuditLog automático em CRUD
RSpec.describe 'Financial invariants', type: :model do
  let!(:account)       { create(:account) }
  let!(:other_account) { create(:account) }
  let!(:user)          { create(:user, account: account) }
  let!(:bank)          { create(:financial_bank_account, account: account) }

  describe 'Multi-tenant scoping (CRIT)' do
    it 'find pelo ID retorna nil quando o registro pertence a outra account' do
      foreign_bank = create(:financial_bank_account, account: other_account)

      # for_account é o padrão correto — deve filtrar
      expect(
        Financial::BankAccount.for_account(account.id).find_by(id: foreign_bank.id)
      ).to be_nil

      # Sem for_account, find() ainda enxerga (uso global é responsabilidade do controller)
      expect(Financial::BankAccount.find_by(id: foreign_bank.id)).to be_present
    end

    it 'rejeita save sem account_id' do
      bank.account_id = nil
      expect(bank.save).to be false
      expect(bank.errors[:account_id]).to be_present
    end
  end

  describe 'Soft delete (CRIT-DB-03)' do
    it 'find_by(id:) ignora registros soft-deletados' do
      bank.soft_delete!(user: user)

      expect(Financial::BankAccount.find_by(id: bank.id)).to be_nil
      # alive scope explícito também ignora
      expect(Financial::BankAccount.alive.find_by(id: bank.id)).to be_nil
    end

    it 'find(id) levanta ActiveRecord::RecordNotFound para soft-deletados' do
      bank.soft_delete!(user: user)
      expect { Financial::BankAccount.find(bank.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'Frozen attributes (ALTO-DB-03)' do
    let(:entry) do
      create(:financial_entry,
             account: account,
             financial_bank_account: bank)
    end

    it 'rejeita mudança de direction após criação' do
      entry.direction = 'out'
      expect(entry.save).to be false
      expect(entry.errors[:direction]).to include('é imutável após criação (snapshot histórico)')
    end

    it 'rejeita mudança de amount_cents após criação' do
      entry.amount_cents = 99_999
      expect(entry.save).to be false
      expect(entry.errors[:amount_cents]).to be_present
    end

    it 'permite update de campos não-frozen (description)' do
      entry.description = 'Nova descrição'
      expect(entry.save).to be true
    end

    it 'permite soft_delete (update legítimo de deleted_at)' do
      expect { entry.soft_delete!(user: user) }.not_to raise_error
      expect(entry.reload.deleted_at).to be_present
    end
  end

  describe 'Period closure (canon "Imutabilidade primeiro")' do
    before do
      create(:financial_period_closure,
             account: account,
             period_year: 2026,
             period_month: 4,
             status: 'closed')
    end

    it 'bloqueia create de Entry com competence_date em mês fechado' do
      expect do
        build(:financial_entry,
              account: account,
              financial_bank_account: bank,
              competence_date: Date.new(2026, 4, 15),
              cash_date: Date.new(2026, 4, 15)).save
      end.to raise_error(Financial::Errors::PeriodClosed, /04\/2026/)
    end

    it 'permite create em mês aberto' do
      expect do
        create(:financial_entry,
               account: account,
               financial_bank_account: bank,
               competence_date: Date.new(2026, 5, 15),
               cash_date: Date.new(2026, 5, 15))
      end.not_to raise_error
    end

    it 'NÃO bloqueia soft delete (LGPD compliance)' do
      entry = create(:financial_entry,
                     account: account,
                     financial_bank_account: bank,
                     competence_date: Date.new(2026, 5, 15),
                     cash_date: Date.new(2026, 5, 15))

      # Fecha o mês 05/2026 depois de criar o entry
      create(:financial_period_closure,
             account: account,
             period_year: 2026,
             period_month: 5,
             status: 'closed')

      expect { entry.soft_delete!(user: user) }.not_to raise_error
    end

    it 'período reaberto libera mutação novamente' do
      pc = Financial::PeriodClosure.for_account(account.id)
                                   .for_period(2026, 4)
                                   .first
      pc.update!(status: 'reopened', reopened_at: Time.current,
                 reopened_by_id: user.id, reopen_reason: 'Correção')

      expect do
        create(:financial_entry,
               account: account,
               financial_bank_account: bank,
               competence_date: Date.new(2026, 4, 15),
               cash_date: Date.new(2026, 4, 15))
      end.not_to raise_error
    end
  end

  describe 'AuditLog automático (BUG-12, F-02)' do
    # Por que validar a chamada de `async_record` em vez do efeito final no DB:
    # `Financial::AuditLog.async_record` enfileira via Sidekiq (`AuditLogJob`).
    # No spec o adapter é :test (não roda) e `use_transactional_fixtures=true`
    # faria rollback do AuditLog mesmo com :inline. O invariante REAL é
    # "Auditable concern dispara audit logging em CRUD" — testar a chamada
    # cobre isso sem depender do pipeline async. O job em si é trivial
    # (AuditLog.create!) e testado indiretamente em prod.

    it 'CREATE de Financial::BankAccount chama async_record(action: create)' do
      expect(Financial::AuditLog).to receive(:async_record)
        .with(instance_of(Financial::BankAccount), hash_including(action: 'create'))
        .at_least(:once)

      create(:financial_bank_account, account: account)
    end

    it 'UPDATE chama async_record(action: update) com diff before/after' do
      captured = nil
      allow(Financial::AuditLog).to receive(:async_record) do |_, action:, before:, after:|
        captured = { action: action, before: before, after: after } if action == 'update'
      end

      bank.update!(name: 'Nome Novo')

      expect(captured).to be_present
      expect(captured[:action]).to eq('update')
      expect(captured[:after]['name']).to eq('Nome Novo')
      expect(captured[:before]['name']).not_to eq('Nome Novo')
    end

    # Trade-off documentado no Auditable concern:
    # `soft_delete!` usa `update_columns` (SQL direto, bypassa callbacks).
    # → `after_commit` não roda → AuditLog automático NÃO acontece.
    # Comentário em `auditable.rb`: "NÃO bloqueia `update_columns` ...
    # pra esses casos, a auditoria registra a mudança e o usuário fica com trilha".
    # Isso é OK pra delete (que tem deleted_by_id stamped), mas significa que
    # o invariante "soft_delete gera AuditLog destroy" precisa ser validado
    # pela rota normal de update — não pela helper `soft_delete!`.
    it 'UPDATE explícito de deleted_at (sem update_columns) chama async_record(action: destroy)' do
      actions_received = []
      allow(Financial::AuditLog).to receive(:async_record) do |_, action:, **_kw|
        actions_received << action
      end

      # Update normal (não update_columns) — dispara `record_audit_update`
      # que detecta `soft_delete_update?` e converte em action='destroy'.
      bank.update!(deleted_at: Time.current, deleted_by_id: user.id)

      expect(actions_received).to include('destroy')
    end

    it 'soft_delete! (update_columns) NÃO dispara AuditLog automático — uso de deleted_by_id é a trilha' do
      actions_received = []
      allow(Financial::AuditLog).to receive(:async_record) do |_, action:, **_kw|
        actions_received << action
      end

      bank.soft_delete!(user: user)

      # Validamos o gap conhecido. Quem precisar de audit explícito em
      # soft_delete deve chamar `Financial::AuditLog.async_record` manualmente
      # no service que orquestra a deleção.
      expect(actions_received).to be_empty
      expect(bank.reload.deleted_by_id).to eq(user.id)
    end
  end
end
