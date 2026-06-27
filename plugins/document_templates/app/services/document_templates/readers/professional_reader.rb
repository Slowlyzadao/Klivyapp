# frozen_string_literal: true

module DocumentTemplates
  module Readers
    # Lê valores brutos do User (profissional logado) pra chaves
    # `professional.*`.
    #
    # FONTE dos dados clínicos: `Financial::AgentProfile` (1-to-1 User×Account,
    # tela Financeiro > Configurações > Agentes). É lá que o conselho (`cro`,
    # ex.: "CRO-SP 12345") e as `specialties` são cadastrados — User core não
    # tem colunas pra isso. Acesso defensivo (`defined?`) pra degradar gracioso
    # se o plugin financial não estiver carregado; fallback pra
    # `user.custom_attributes` (legado) quando não há AgentProfile.
    #
    # `cro` é um texto livre; council_full devolve ele inteiro, e
    # acronym/number/state saem de um parse best-effort de "ACR-UF NNN".
    class ProfessionalReader
      def initialize(user, account = nil)
        @user = user
        @account = account
      end

      def read(key)
        return nil if @user.nil?

        case key
        when 'professional.name'         then @user.name
        when 'professional.display_name' then @user.display_name.presence || @user.name
        when 'professional.email'        then @user.email
        when 'professional.council_acronym' then parsed_cro[:acronym] || attr('council_acronym')
        when 'professional.council_number'  then parsed_cro[:number]  || attr('council_number')
        when 'professional.council_state'   then parsed_cro[:state]   || attr('council_state')
        when 'professional.council_full'    then council_full
        when 'professional.specialty'       then specialty
        when 'professional.signature_image_url' then signature_url
        end
      end

      private

      # ── Financial::AgentProfile (fonte real do conselho/especialidades) ─────
      def agent_profile
        return @agent_profile if defined?(@agent_profile)

        @agent_profile =
          if defined?(::Financial::AgentProfile) && @account && @user
            ::Financial::AgentProfile
              .where(account_id: @account.id, user_id: @user.id, deleted_at: nil)
              .first
          end
      rescue StandardError
        @agent_profile = nil
      end

      def specialty
        list = agent_profile&.specialties
        return list.compact_blank.join(', ').presence if list.present?

        attr('specialty')
      end

      # CRO é texto livre ("CRO-SP 12345"). council_full = o valor cru; quando
      # não há AgentProfile, recompõe do custom_attributes (legado).
      def council_full
        return agent_profile.cro.presence if agent_profile&.cro.present?

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

      # Parse best-effort de "ACR-UF NNN" / "ACR/UF NNN" / "ACR NNN" / "NNN".
      def parsed_cro
        @parsed_cro ||= begin
          raw = agent_profile&.cro.to_s.strip
          m = raw.match(/\A([A-Za-zÀ-ÿ]+)?[\s\/\-]*([A-Za-z]{2})?[\s\/\-]*(\d[\d.\-]*)?/)
          {
            acronym: m && m[1].presence&.upcase,
            state:   m && m[2].presence&.upcase,
            number:  m && m[3]&.gsub(/\D/, '').presence
          }
        end
      end

      def attr(name)
        custom_attributes[name].presence
      end

      def custom_attributes
        @custom_attributes ||= (@user.custom_attributes.presence || {}).with_indifferent_access
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
