# Detecta se uma mensagem do paciente contém termos de urgência (PRD §12.3).
# Keyword list vem do PatientPortalSetting.messaging.urgent_keyword_list.
#
# Quando detecta, o controller marca a mensagem com `urgent=true` e o front
# exibe um modal "isso é uma urgência? ligue agora" antes de confirmar o envio.
#
# Por enquanto é match simples por substring (case-insensitive, ignora acentos
# básicos). NLP fica como F2 — pra MVP keyword list resolve.
module PatientPortal
  class UrgentTriage
    DEFAULT_KEYWORDS = %w[urgência urgente emergência sangramento desmaio
                          dor\ forte dor\ muito\ forte febre\ alta convulsão].freeze

    def initialize(account:, text:)
      @account = account
      @text    = text.to_s
    end

    def urgent?
      return false if @text.blank?

      normalized = normalize(@text)
      keywords.any? { |k| normalized.include?(normalize(k)) }
    end

    def matched_keywords
      return [] if @text.blank?

      normalized = normalize(@text)
      keywords.select { |k| normalized.include?(normalize(k)) }
    end

    def clinic_phone
      # Tenta extrair do setting; fallback pra nada (front mostra "fale com a clínica")
      @account.patient_portal_setting&.business_hours&.dig('emergency_phone') ||
        @account.patient_portal_setting&.messaging&.dig('emergency_phone')
    end

    private

    def keywords
      list = @account.patient_portal_setting&.messaging&.dig('urgent_keyword_list')
      list.presence || DEFAULT_KEYWORDS
    end

    def normalize(s)
      s.to_s.downcase.tr('áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc')
    end
  end
end
