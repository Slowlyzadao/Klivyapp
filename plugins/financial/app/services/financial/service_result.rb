module Financial
  # Resultado padrão dos services Financial::*. Não levanta exceções de domínio
  # — retorna result.failure? com mensagem amigável. Erros inesperados
  # (banco indisponível etc.) sobem como exceções normais.
  class ServiceResult
    attr_reader :data, :errors

    def initialize(success:, data: {}, errors: [])
      @success = success
      @data = data
      @errors = Array(errors)
    end

    def success? = @success
    def failure? = !@success

    def [](key) = data[key]

    def to_h
      { success: @success, data: data, errors: errors }
    end

    def self.success(**data)
      new(success: true, data: data)
    end

    def self.failure(*errors, data: {})
      new(success: false, errors: errors, data: data)
    end
  end
end
