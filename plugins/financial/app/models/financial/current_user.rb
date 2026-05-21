module Financial
  # Wrapper sobre Current.user que tolera ausência (jobs, console, seeds).
  # Centraliza acesso para evitar `defined?(Current)` espalhado nos concerns.
  module CurrentUser
    module_function

    def id
      return nil unless defined?(::Current)

      ::Current.user&.id
    rescue NoMethodError
      nil
    end

    def ip
      return nil unless defined?(::Current)

      ::Current.try(:request_ip) || ::Current.try(:ip)
    rescue NoMethodError
      nil
    end

    def user_agent
      return nil unless defined?(::Current)

      ::Current.try(:user_agent)
    rescue NoMethodError
      nil
    end

    def account_id
      return nil unless defined?(::Current)

      ::Current.account&.id
    rescue NoMethodError
      nil
    end
  end
end
