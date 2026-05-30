# frozen_string_literal: true

module DocumentTemplates
  # Resolve uma chave de variável (`patient.full_name`) num valor final
  # pronto pra inserir no HTML do PDF.
  #
  # Fluxo:
  #   1. Pega definição no Catalog → encontra categoria + formatter.
  #   2. Delega leitura do valor cru pro Reader certo (patient/clinic/...).
  #   3. Aplica formatter (CPF, data, currency, image_tag, etc.).
  #   4. Se valor final ficar blank, devolve fallback (passado pelo template
  #      ou padrão global '_______').
  #
  # Usado pelo Renderer (Fase 3) na hora de produzir o HTML que vai pro Grover.
  class Resolver
    DEFAULT_FALLBACK = '_______'

    # Expostos pro Renderer poder acessar contexto sem duplicar passagem
    # (ex: ClinicReader pra header/footer do PDF).
    attr_reader :patient, :clinic, :professional, :now

    def initialize(patient:, clinic:, professional:, now: Time.current)
      @patient = patient
      @clinic = clinic
      @professional = professional
      @now = now

      city = Readers::ClinicReader.new(clinic).read('clinic.address_city')

      @readers = {
        'patient'      => Readers::PatientReader.new(patient),
        'clinic'       => Readers::ClinicReader.new(clinic),
        'professional' => Readers::ProfessionalReader.new(professional),
        'date'         => Readers::DateReader.new(now: now, city: city)
      }
    end

    # Resolve uma chave e retorna string pronta pra HTML.
    # `fallback` permite override por nó do template (atributo `fallback`
    # no chip da variável). Quando blank, usa DEFAULT_FALLBACK.
    def resolve(key, fallback: nil)
      definition = Catalog.find(key)
      return safe_fallback(fallback) if definition.nil?

      raw = read_raw(key)
      formatted = Formatters.apply(raw, definition.formatter)

      return formatted if formatted.present?

      safe_fallback(fallback)
    end

    # Resolve todas as chaves de uma vez — útil pra preview no editor.
    # Retorna hash { key => valor_resolvido }.
    def resolve_all
      Catalog.all.each_with_object({}) { |v, h| h[v.key] = resolve(v.key) }
    end

    private

    def read_raw(key)
      namespace = key.split('.', 2).first
      reader = @readers[namespace]
      reader&.read(key)
    end

    def safe_fallback(custom)
      (custom.presence || DEFAULT_FALLBACK).to_s
    end
  end
end
