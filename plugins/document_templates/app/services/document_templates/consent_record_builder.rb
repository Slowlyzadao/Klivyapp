# frozen_string_literal: true

module DocumentTemplates
  # Cria um ConsentRecord novo gerado a partir de um DocumentTemplate de
  # consentimento. Diferente do fluxo de Document (que aceita só tipos
  # clínicos), aqui criamos ConsentRecord e passamos como `save_to:` pro
  # PdfGenerator gerar o HTML/PDF e popular `rendered_html`.
  #
  # ConsentRecord não tem coluna `pdf_hash` própria — usamos o
  # `integrity_hash` existente pra guardar o SHA-256 do PDF (preparação
  # Clicksign + auditoria).
  #
  # Pipeline:
  #   1. Cria ConsentRecord(status: 'pendente', body: nil, title, etc.)
  #   2. Roda PdfGenerator com save_to: consent → renderiza HTML, gera PDF,
  #      persiste rendered_html no consent.
  #   3. Calcula hash SHA-256 do PDF, salva em integrity_hash.
  #   4. Retorna Result struct compatível com o resto do sistema.
  class ConsentRecordBuilder
    Result = Struct.new(:success?, :consent, :pdf_data, :error, keyword_init: true)

    def self.call(**args)
      new(**args).run
    end

    # @param template            [DocumentTemplate] template de consentimento
    # @param patient             [Patient]
    # @param professional        [User] usuário gerando (vira created_by)
    # @param clinic              [Account] opcional; default = patient.account
    # @param title               [String] opcional; default = template.name
    # @param observations        [String] opcional
    # @param expires_after_days  [Integer] opcional
    def initialize(template:, patient:, professional:, clinic: nil, title: nil,
                   observations: nil, expires_after_days: nil)
      @template           = template
      @patient            = patient
      @professional       = professional
      @clinic             = clinic || patient.account
      @title              = title || template.name
      @observations       = observations
      @expires_after_days = expires_after_days
    end

    def run
      raise ArgumentError, "Template '#{@template.name}' não é de consentimento" unless @template.consent?

      # ConsentRecord NÃO tem `has_one_attached :file` (legado guarda o
      # conteúdo em `body`). Quando geramos via template, o PdfGenerator
      # detecta isso e pula o attach — só persiste rendered_html. O PDF é
      # regerado on-demand do rendered_html via Grover quando o user pede
      # download (fluxo a integrar no controller de download, fora deste
      # MVP).
      consent = build_consent_record

      pdf_result = DocumentTemplates::PdfGenerator.call(
        template: @template,
        patient: @patient,
        professional: @professional,
        clinic: @clinic,
        title: @title,
        save_to: consent
      )

      if pdf_result.success?
        # ConsentRecord reusa `integrity_hash` no lugar de pdf_hash.
        consent.update!(integrity_hash: pdf_result.pdf_hash) if pdf_result.pdf_hash.present?

        Result.new(success?: true, consent: consent, pdf_data: pdf_result.pdf_data, error: nil)
      else
        # PDF falhou e o save aconteceu dentro do attach_to_record — só
        # reportamos o erro. Caso a row tenha sido salva antes do erro real,
        # o caller pode decidir se reverte ou notifica.
        Result.new(success?: false, error: pdf_result.error)
      end
    rescue StandardError => e
      Rails.logger.error("[DocumentTemplates::ConsentRecordBuilder] #{e.class}: #{e.message}")
      Result.new(success?: false, error: "#{e.class}: #{e.message}")
    end

    private

    def build_consent_record
      ConsentRecord.new(
        patient: @patient,
        account: @clinic,
        created_by: @professional,
        title: @title,
        document_type: @template.document_type,
        status: 'pendente',
        observations: @observations,
        expires_after_days: @expires_after_days,
        # body fica vazio quando geramos via template — fonte da verdade
        # é rendered_html (preenchido pelo PdfGenerator).
        body: nil
      )
    end
  end
end
