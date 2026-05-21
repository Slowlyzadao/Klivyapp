# Sprint L — Specs da Pundit policy de ProposedEvolution.
#
# ApplicationPolicy.new aceita user_context (hash com :user/:account/...)
# como primeiro argumento — não User direto. Por isso construímos um hash
# em cada exemplo. Stubs de beclinic_can?/beclinic_scope usam a assinatura
# completa (account, module, action) → (account, module) que a User
# expõe via concern BeclinicPermissible.
require 'rails_helper'

RSpec.describe ProposedEvolutionPolicy do
  let(:account)       { create(:account) }
  let(:owner)         { create(:user, account: account, role: :agent) }
  let(:other_doctor)  { create(:user, account: account, role: :agent) }
  let(:admin)         { create(:user, account: account, role: :administrator) }
  let(:event)         { create(:agenda_event, account: account, user: owner) }
  let(:recording) {
    create(:telemed_recording, :ready, agenda_event: event, account: account)
  }
  let(:evolution) {
    create(:proposed_evolution, telemed_recording: recording)
  }

  def context_for(user, scope: 'own', can_create_note: true)
    allow(user).to receive(:beclinic_can?).and_call_original
    allow(user).to receive(:beclinic_can?).with(account, :agenda, :view).and_return(true)
    allow(user).to receive(:beclinic_can?).with(account, :agenda, :edit_event).and_return(true)
    allow(user).to receive(:beclinic_can?).with(account, :patients, :create_clinical_note).and_return(can_create_note)
    allow(user).to receive(:beclinic_scope).with(account, :agenda).and_return(scope)
    { user: user, account: account, account_user: nil }
  end

  describe '#show?' do
    it 'permite o dentista dono' do
      expect(described_class.new(context_for(owner), evolution).show?).to be(true)
    end

    it 'recusa outro dentista (scope=own e nao e o dono)' do
      expect(described_class.new(context_for(other_doctor), evolution).show?).to be(false)
    end

    it 'permite admin com beclinic_scope=all' do
      expect(described_class.new(context_for(admin, scope: 'all'), evolution).show?).to be(true)
    end
  end

  describe '#approve?' do
    it 'recusa quando dentista nao tem permissao de criar nota clinica' do
      ctx = context_for(owner, can_create_note: false)
      expect(described_class.new(ctx, evolution).approve?).to be(false)
    end

    it 'permite quando dono + tem permissao de nota clinica' do
      expect(described_class.new(context_for(owner), evolution).approve?).to be(true)
    end
  end
end
