# frozen_string_literal: true

module DocumentTemplates
  module Readers
    # Lê valores brutos do Patient pra chaves `patient.*`.
    #
    # Schema real do Patient (auditado 2026-05-27):
    #   - `name` (string) — patient.full_name é alias
    #   - `birthdate` (date) — não `birth_date`
    #   - `address` (jsonb): street, number, complement, neighborhood, city, state, zip_code
    #     (chave do CEP é `zip_code` neste projeto — NÃO `zip`)
    #   - `guardian` (jsonb): name, cpf, phone, relationship quando has_guardian=true
    #     (NÃO grava `rg` — não há campo de RG no cadastro do responsável)
    #
    # Retorna nil pra campos vazios — Resolver decide o fallback.
    class PatientReader
      def initialize(patient)
        @patient = patient
      end

      def read(key)
        return nil if @patient.nil?

        case key
        when 'patient.full_name'        then @patient.name
        when 'patient.first_name'       then @patient.name.to_s.split.first
        when 'patient.social_name'      then @patient.social_name.presence || @patient.name
        when 'patient.cpf'              then @patient.cpf
        when 'patient.rg'               then @patient.rg
        when 'patient.birthdate'        then @patient.birthdate
        when 'patient.birthdate_long'   then @patient.birthdate
        when 'patient.age'              then @patient.birthdate # formatter :age calcula
        when 'patient.sex'              then @patient.sex
        when 'patient.marital_status'   then @patient.marital_status
        when 'patient.phone'            then @patient.phone
        when 'patient.email'            then @patient.email

        when 'patient.address_full'         then format_full_address(address)
        when 'patient.address_street'       then [address['street'], address['number']].compact.reject(&:blank?).join(', ')
        when 'patient.address_complement'   then address['complement']
        when 'patient.address_neighborhood' then address['neighborhood']
        when 'patient.address_city'         then address['city']
        when 'patient.address_state'        then address['state']
        when 'patient.address_zip'          then address['zip_code']

        when 'patient.guardian_name'         then guardian['name']
        when 'patient.guardian_cpf'          then guardian['cpf']
        when 'patient.guardian_relationship' then guardian['relationship']
        when 'patient.guardian_phone'        then guardian['phone']

        when 'patient.medical_record_id' then @patient.id.to_s
        end
      end

      private

      def address
        @address ||= (@patient.address.presence || {}).with_indifferent_access
      end

      def guardian
        return @guardian if defined?(@guardian)
        @guardian = if @patient.has_guardian
                      (@patient.guardian.presence || {}).with_indifferent_access
                    else
                      {}.with_indifferent_access
                    end
      end

      def format_full_address(addr)
        parts = [
          [addr['street'], addr['number']].compact.reject(&:blank?).join(', '),
          addr['complement'],
          addr['neighborhood'],
          [addr['city'], addr['state']].compact.reject(&:blank?).join('-'),
          addr['zip_code']
        ].compact.reject(&:blank?)
        parts.join(', ').presence
      end
    end
  end
end
