# frozen_string_literal: true

module DocumentTemplates
  module Readers
    # Lê valores brutos do User (profissional logado) pra chaves
    # `professional.*`.
    #
    # Schema real do User (auditado 2026-05-27): NÃO tem `council_number`,
    # `specialty`, etc. — campos institucionais vivem em
    # `user.custom_attributes` JSONB. Acesso defensivo.
    #
    # Convenção pra montar professional.council_full (ex: "CRM/SP 123456"):
    # se tem acronym + state + number → 'ACR/UF NNN'
    # se falta state                  → 'ACR NNN'
    # se falta number                 → nil
    class ProfessionalReader
      def initialize(user)
        @user = user
      end

      def read(key)
        return nil if @user.nil?

        case key
        when 'professional.name'         then @user.name
        when 'professional.display_name' then @user.display_name.presence || @user.name
        when 'professional.email'        then @user.email
        when 'professional.council_acronym' then attr('council_acronym')
        when 'professional.council_number'  then attr('council_number')
        when 'professional.council_state'   then attr('council_state')
        when 'professional.council_full'    then council_full
        when 'professional.specialty'       then attr('specialty')
        when 'professional.signature_image_url' then signature_url
        end
      end

      private

      def attr(name)
        custom_attributes[name].presence
      end

      def custom_attributes
        @custom_attributes ||= (@user.custom_attributes.presence || {}).with_indifferent_access
      end

      def council_full
        acronym = attr('council_acronym')
        number  = attr('council_number')
        state   = attr('council_state')

        return nil if number.blank?

        prefix = if acronym.present? && state.present?
                   "#{acronym}/#{state}"
                 elsif acronym.present?
                   acronym
                 end
        [prefix, number].compact.join(' ').presence
      end

      def signature_url
        return nil unless @user.respond_to?(:signature_image)
        return nil unless @user.signature_image.attached?

        Rails.application.routes.url_helpers.rails_blob_url(@user.signature_image, only_path: false)
      rescue StandardError
        nil
      end
    end
  end
end
