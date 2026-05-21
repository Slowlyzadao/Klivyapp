module Financial
  # Anonimização LGPD — canon F-33 §parte 2.
  #
  # Substitui campos pessoais identificáveis (PII) por hash irreversível
  # ou null, MAS preserva o registro Patient (id, FK, integridade contábil).
  # Lançamentos financeiros e clínicos continuam ligados pelo patient_id.
  #
  # Campos anonimizados:
  #   - name → "Paciente Anonimizado #ID" (legível pra reports/auditoria)
  #   - cpf, rg, email, phone, social_name → SHA256 truncado (irreversível)
  #   - address, contacts, emergency_contact, guardian, billing_info,
  #     external_ids, notes, pinned_note → null/{}/[]
  #   - avatar_url → null + remove Active Storage attachment
  #   - insurance: preserva só `name` da operadora (necessário pro relatório
  #     de Convênio); demais campos limpos.
  #   - lgpd_consent: PRESERVADO (prova legal do consentimento)
  #   - patient_status, sex, birthdate: zerados
  #
  # Marca `patient.anonymized_at = Time.current`. Todos os controllers
  # devem checar esse campo e omitir PII em respostas.
  #
  # Idempotente: se já está anonymized_at, retorna success sem reaplicar.
  # Atomic: tudo numa transaction; falha → rollback completo.
  class AnonymizePatient
    Result = Struct.new(:success?, :patient, :anonymized_fields, :error,
                        keyword_init: true)

    HASH_TRUNCATION = 16  # primeiros 16 chars do SHA256 são suficientes

    attr_reader :patient, :user

    def self.call(**kwargs) = new(**kwargs).call

    def initialize(patient:, user:)
      @patient = patient
      @user = user
    end

    def call
      if patient.anonymized_at.present?
        return Result.new(success?: true, patient: patient,
                          anonymized_fields: { already: true })
      end

      ::ActiveRecord::Base.transaction do
        snapshot = capture_snapshot
        apply_anonymization!
        patient.update!(anonymized_at: Time.current)

        # Auditable hook deve disparar AuditLog automaticamente.
        # Snapshot retornado pra LgpdRequest.anonymized_fields.
        return Result.new(success?: true, patient: patient,
                          anonymized_fields: snapshot)
      end
    rescue => e
      Rails.logger.error("[Financial::AnonymizePatient] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      Result.new(success?: false, error: "#{e.class}: #{e.message}")
    end

    private

    # Snapshot pra registrar quais campos tinham dados antes da
    # anonimização (sem armazenar OS DADOS — só presença).
    def capture_snapshot
      {
        had_name:               patient.name.present?,
        had_cpf:                patient.cpf.present?,
        had_rg:                 patient.rg.present?,
        had_email:              patient.email.present?,
        had_phone:              patient.phone.present?,
        had_social_name:        patient.respond_to?(:social_name) && patient.social_name.present?,
        had_address:            patient.address.is_a?(Hash) && patient.address.present?,
        had_contacts:           patient.contacts.is_a?(Array) && patient.contacts.any?,
        had_emergency_contact:  patient.emergency_contact.is_a?(Hash) && patient.emergency_contact.present?,
        had_guardian:           patient.try(:guardian).is_a?(Hash) && patient.guardian.present?,
        had_billing_info:       patient.billing_info.is_a?(Hash) && patient.billing_info.present?,
        had_insurance:          patient.insurance.is_a?(Hash) && patient.insurance.present?,
        had_external_ids:       patient.try(:external_ids).is_a?(Hash) && patient.external_ids.present?,
        had_notes:              patient.notes.present?,
        had_pinned_note:        patient.pinned_note.present?,
        had_avatar:             patient.avatar_url.present? || patient.try(:avatar)&.attached?,
        had_birthdate:          patient.birthdate.present?,
        had_sex:                patient.sex.present?
      }
    end

    def apply_anonymization!
      attrs = {
        name:               anonymous_name,
        cpf:                hash_or_nil(patient.cpf),
        rg:                 nil,
        email:              hash_or_nil(patient.email),
        phone:              hash_or_nil(patient.phone),
        birthdate:          nil,
        sex:                nil,
        address:            {},
        contacts:           [],
        emergency_contact:  {},
        billing_info:       {},
        # Preserva só `name` da operadora pra Convênio report continuar
        # funcionando (operadora não é PII). Demais campos zerados.
        insurance:          insurance_keep_operator_only,
        notes:              nil,
        pinned_note:        nil
      }
      attrs[:social_name] = nil if patient.respond_to?(:social_name=)
      attrs[:guardian]    = {}  if patient.respond_to?(:guardian=)
      attrs[:external_ids] = {} if patient.respond_to?(:external_ids=)

      # Avatar: limpa URL externa + detacha Active Storage se existir.
      attrs[:avatar_url] = nil if patient.respond_to?(:avatar_url=)

      patient.update!(attrs)

      # Active Storage attachment (caso `Patient has_one_attached :avatar`).
      patient.avatar.detach if patient.respond_to?(:avatar) && patient.avatar.attached?
    end

    def anonymous_name
      "Paciente Anonimizado ##{patient.id}"
    end

    # SHA256 truncado é irreversível (não dá pra reverter o hash) mas
    # determinístico (mesmo CPF gera mesmo hash) — útil pra detectar
    # duplicatas anonimizadas.
    def hash_or_nil(value)
      return nil if value.blank?
      Digest::SHA256.hexdigest(value.to_s)[0, HASH_TRUNCATION]
    end

    def insurance_keep_operator_only
      ins = patient.insurance.is_a?(Hash) ? patient.insurance : {}
      operator = ins['name'].presence || ins[:name].presence
      operator ? { 'name' => operator.to_s.strip } : {}
    end
  end
end
