require 'rails_helper'

RSpec.describe PatientPortal::PatientFinder do
  let(:account) { create(:account) }
  # Emails únicos por execução pra evitar colisão com dados leftover do test DB
  # (test DB do Klivy local tem seeds + dados de execuções anteriores).
  let(:tag) { SecureRandom.hex(4) }
  let(:email_a) { "spec-a-#{tag}@example.test" }
  let(:email_b) { "spec-b-#{tag}@example.test" }
  let(:phone_a) { "+5511#{rand(900_000_000..999_999_999)}" }

  describe '#call (email)' do
    context 'happy path — Patient.email bate exato' do
      let!(:patient) do
        create(:patient, account: account, name: 'Leandro', email: email_a)
      end

      it 'retorna o paciente' do
        result = described_class.new(identifier_kind: :email, normalized_value: email_a).call
        expect(result.patients.map(&:id)).to contain_exactly(patient.id)
      end

      it 'é case-insensitive' do
        patient.update_column(:email, email_a.upcase)
        result = described_class.new(identifier_kind: :email, normalized_value: email_a.downcase).call
        expect(result.patients.map(&:id)).to contain_exactly(patient.id)
      end
    end

    context 'paciente sem Patient.email, identidade via Contact' do
      let!(:contact) { create(:contact, account: account, email: email_a) }
      let!(:patient) do
        create(:patient, account: account, name: 'Paciente WhatsApp',
                          email: nil, contact: contact)
      end

      it 'cai no fallback Contact.email e encontra' do
        result = described_class.new(identifier_kind: :email, normalized_value: email_a).call
        expect(result.patients.map(&:id)).to include(patient.id)
      end

      it 'aceita Patient.email com whitespace como vazio' do
        patient.update_column(:email, '   ')
        result = described_class.new(identifier_kind: :email, normalized_value: email_a).call
        expect(result.patients.map(&:id)).to include(patient.id)
      end
    end

    # ─── Regressão crítica (2026-05-19) ─────────────────────────────────────
    # Antes do fix, o fallback Contact.email vazava patients que tinham
    # Patient.email DIFERENTE. Cenário real: David Feliciano e Leandro
    # compartilhavam o mesmo Contact (mesma família/phone). O admin editou
    # o email do David pra um email novo, mas Contact.email continuou com o
    # email do Leandro. Ao Leandro logar pelo email dele, o flow listava
    # ambos os pacientes → vazamento de dados cross-patient.
    context 'shared Contact entre múltiplos patients (bug do David Feliciano)' do
      let!(:shared_contact) do
        create(:contact, account: account, email: email_a, phone_number: phone_a)
      end
      let!(:leandro) do
        create(:patient, account: account, name: 'Leandro',
                          email: email_a, contact: shared_contact)
      end
      let!(:david) do
        # David tem email PRÓPRIO diferente do Contact stale.
        create(:patient, account: account, name: 'David Feliciano',
                          email: email_b, contact: shared_contact)
      end

      it 'retorna SÓ o paciente cujo Patient.email bate (Leandro), não o David' do
        result = described_class.new(identifier_kind: :email, normalized_value: email_a).call
        ids = result.patients.map(&:id)
        expect(ids).to include(leandro.id)
        expect(ids).not_to include(david.id),
                            'David tem Patient.email próprio — não deve aparecer via fallback de Contact'
      end

      it 'busca pelo email próprio do David encontra só ele' do
        result = described_class.new(identifier_kind: :email, normalized_value: email_b).call
        expect(result.patients.map(&:id)).to contain_exactly(david.id)
      end
    end

    context 'paciente suspenso permanente' do
      let!(:patient) do
        p = create(:patient, account: account, email: email_a)
        p.update_column(:portal_status, 'suspended_permanent')
        p
      end

      it 'não retorna patient suspenso' do
        result = described_class.new(identifier_kind: :email, normalized_value: email_a).call
        expect(result.patients).to be_empty
      end
    end
  end

  describe '#call (phone)' do
    context 'mesma regra aplicada a phone' do
      let!(:shared_contact) do
        create(:contact, account: account, phone_number: phone_a)
      end
      let!(:patient_with_own_phone) do
        create(:patient, account: account, name: 'Tem phone próprio',
                          phone: "+5511#{rand(900_000_000..999_999_999)}", contact: shared_contact)
      end
      let!(:patient_without_phone) do
        create(:patient, account: account, name: 'Sem phone próprio',
                          phone: nil, contact: shared_contact)
      end

      it 'fallback Contact.phone_number só retorna patient sem phone próprio' do
        result = described_class.new(identifier_kind: :phone, normalized_value: phone_a).call
        ids = result.patients.map(&:id)
        expect(ids).to include(patient_without_phone.id)
        expect(ids).not_to include(patient_with_own_phone.id)
      end
    end
  end
end
