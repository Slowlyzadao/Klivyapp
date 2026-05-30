# frozen_string_literal: true

module DocumentTemplates
  module Readers
    # Lê valores brutos do Account (clínica) pra chaves `clinic.*`.
    #
    # Schema real do Account (auditado 2026-05-27): NÃO tem colunas dedicadas
    # pra CNPJ, endereço, telefone — tudo vive em `custom_attributes` JSONB
    # ou `settings` JSONB. Acesso defensivo com fallback gracioso.
    #
    # Convenção de leitura (resolução em ordem):
    #   1. custom_attributes[key]
    #   2. settings[key]
    #   3. nil
    class ClinicReader
      def initialize(account)
        @account = account
      end

      def read(key)
        return nil if @account.nil?

        case key
        when 'clinic.name'         then @account.name
        when 'clinic.fantasy_name' then attr('fantasy_name')
        when 'clinic.cnpj'         then attr('cnpj')

        when 'clinic.address_full'   then format_full_address
        when 'clinic.address_street' then attr('address_street') || attr('address') # fallback livre
        when 'clinic.address_city'   then attr('address_city') || attr('city')
        when 'clinic.address_state'  then attr('address_state') || attr('state')
        when 'clinic.address_zip'    then attr('address_zip') || attr('zip')

        when 'clinic.phone'   then attr('phone')   || @account.try(:support_email).then { |_| nil } # placeholder
        when 'clinic.email'   then attr('email')   || @account.support_email
        when 'clinic.website' then attr('website')
        when 'clinic.logo_url' then logo_url
        end
      end

      private

      def attr(name)
        custom_attributes[name].presence || settings[name].presence
      end

      def custom_attributes
        @custom_attributes ||= (@account.custom_attributes.presence || {}).with_indifferent_access
      end

      def settings
        @settings ||= (@account.settings.presence || {}).with_indifferent_access
      end

      def format_full_address
        parts = [
          [attr('address_street'), attr('address_number')].compact.reject(&:blank?).join(', '),
          attr('address_complement'),
          attr('address_neighborhood'),
          [attr('address_city'), attr('address_state')].compact.reject(&:blank?).join('-'),
          attr('address_zip')
        ].compact.reject(&:blank?)
        parts.join(', ').presence
      end

      def logo_url
        return nil unless @account.respond_to?(:logo)
        return nil unless @account.logo.attached?

        # Em produção, URL completa exige host config. Em dev pode ser path
        # relativo. Quem renderiza o HTML do PDF tem que se virar pra prefixar.
        Rails.application.routes.url_helpers.rails_blob_url(@account.logo, only_path: false)
      rescue StandardError
        nil
      end
    end
  end
end
