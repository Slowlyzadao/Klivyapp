# Resolve setting respeitando hierarquia (PRD §14.6):
#   Account → Profissional → Serviço → Procedimento → Tag (mais específica vence)
#
# MVP usa apenas Account + Profissional (demais entram na Fase 2).
module PatientPortal
  class ConfigResolver
    def initialize(account:, professional: nil, service: nil, procedure: nil, patient_tags: [])
      @account = account
      @professional = professional
      @service = service
      @procedure = procedure
      @tags = patient_tags
    end

    def get(category, key)
      lookup_chain.each do |source|
        value = source.call
        return value unless value.nil?
      end
      nil
    end

    private

    def lookup_chain
      [
        -> { fetch_from_tag(@tags) },                          # F2
        -> { fetch_from_procedure(@procedure) },               # F2
        -> { fetch_from_service(@service) },                   # F2
        -> { fetch_from_professional(@professional) },         # MVP
        -> { fetch_from_account }                              # MVP
      ]
    end

    def fetch_from_tag(_tags); nil; end       # placeholder F2
    def fetch_from_procedure(_proc); nil; end  # placeholder F2
    def fetch_from_service(_svc); nil; end     # placeholder F2

    def fetch_from_professional(user)
      return nil if user.blank?

      setting = ProfessionalPortalSetting.find_by(account: @account, user: user)
      return nil if setting.blank?

      setting.overrides&.dig(@category_label, @key_label)
    end

    def fetch_from_account
      setting = @account.patient_portal_setting
      return nil if setting.blank?

      bucket = setting.public_send(@category_label) rescue nil
      bucket.is_a?(Hash) ? bucket[@key_label] : nil
    end

    # Convenience: aceita `get(:scheduling, :scheduling_mode)`
    def get_with_labels(category, key)
      @category_label = category.to_s
      @key_label = key.to_s
      get(category, key)
    end

    # Override público para guardar labels antes do lookup.
    public

    def get(category, key)
      @category_label = category.to_s
      @key_label      = key.to_s
      lookup_chain.each do |source|
        value = source.call
        return value unless value.nil?
      end
      nil
    end
  end
end
