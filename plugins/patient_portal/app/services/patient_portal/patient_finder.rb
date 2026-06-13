# Encontra Patients por identifier (e-mail ou telefone) — cross-account
# (paciente pode ter cadastro em N clínicas, PRD §5.2).
#
# IMPORTANTE: e-mail/telefone podem estar em **dois lugares** no Klivy:
#   1. `Patient.email` / `Patient.phone`        — cadastro clínico
#   2. `Contact.email` / `Contact.phone_number` — identidade omnichannel (Chatwoot)
#
# **REGRA DE FONTE DA VERDADE (2026-05-19, fix de bug crítico de auth):**
# Quando `Patient.email` está preenchido, ele é a ÚNICA fonte considerada
# pra esse paciente. O `Contact.email` só vale como fallback pra patients
# SEM email próprio (vieram via WhatsApp e nunca foram editados no admin).
#
# Por quê: um mesmo `Contact` pode estar linkado a múltiplos `Patient`s
# (ex.: responsável legal + dependente compartilhando phone/contact_id de
# família, ou merges históricos no Chatwoot). Quando o admin edita o email
# de UM dos pacientes pelo módulo Pacientes, isso atualiza só `Patient.email`
# — `Contact.email` fica "preso" no valor antigo. Antes desta regra, o
# fallback retornava AMBOS os pacientes do Contact ao buscar pelo email
# antigo, permitindo que a pessoa de email-antigo recebesse OTP e visse
# a tela "Em qual clínica entrar?" listando dados de outro paciente que
# nunca consentiu o vínculo. Isso é vazamento de dados.
#
# Trade-off: paciente que tinha email só no Contact (canal WhatsApp) E
# depois editou pelo admin pra um email diferente, NÃO consegue mais logar
# pelo email antigo do Contact. Isso é o comportamento certo — o email
# atual no cadastro do paciente é o que vale.
module PatientPortal
  class PatientFinder
    Result = Struct.new(:patients, :accounts, keyword_init: true) do
      def empty?
        patients.empty?
      end
    end

    def initialize(identifier_kind:, normalized_value:)
      @kind  = identifier_kind
      @value = normalized_value
    end

    def call
      patients = matching_patients.includes(:account, :contact)
      patients = patients.select { |p| p.portal_active? }
      accounts = patients.map(&:account).uniq
      Result.new(patients: patients, accounts: accounts)
    end

    private

    def matching_patients
      # 1) Match autoritativo: Patient.email / Patient.phone bate exatamente.
      ids_from_patient = case @kind
                         when :email then Patient.where('LOWER(email) = ?', @value).pluck(:id)
                         when :phone then Patient.where(phone: @value).pluck(:id)
                         else []
                         end

      # 2) Fallback CONDICIONAL via Contact — só retorna patients que NÃO
      #    têm o próprio Patient.email/phone preenchido. Sem essa cláusula,
      #    o fallback vazaria patients editados no admin com identidade
      #    nova mas Contact stale (bug do David Feliciano, 2026-05-19).
      ids_from_contact = case @kind
                         when :email
                           contact_ids = Contact.where('LOWER(email) = ?', @value).pluck(:id)
                           Patient.where(contact_id: contact_ids)
                                  .where("email IS NULL OR LENGTH(TRIM(email)) = 0")
                                  .pluck(:id)
                         when :phone
                           contact_ids = Contact.where(phone_number: @value).pluck(:id)
                           Patient.where(contact_id: contact_ids)
                                  .where("phone IS NULL OR LENGTH(TRIM(phone)) = 0")
                                  .pluck(:id)
                         else []
                         end

      Patient.where(id: (ids_from_patient + ids_from_contact).uniq)
    end
  end
end
