# frozen_string_literal: true

module DocumentTemplates
  # Orquestra a geração final de PDF a partir de um DocumentTemplate.
  #
  # Pipeline:
  #   1. Monta o Resolver com {patient, clinic, professional, now}
  #   2. Renderer converte template.content_json → HTML completo (com layout)
  #   3. Grover converte HTML → PDF (Chromium headless)
  #   4. Calcula SHA-256 do PDF (integridade + preparação Clicksign)
  #   5. (Opcional) Anexa o PDF + persiste rendered_html + pdf_hash no record
  #      Document ou ConsentRecord passado em `save_to`
  #
  # Result struct compatível com o legado Patients::PdfGenerator pra facilitar
  # o switch dentro do controller (Fase 3.4).
  class PdfGenerator
    Result = Struct.new(:success?, :document, :pdf_data, :html, :pdf_hash, :error, keyword_init: true)

    # Timeout pro Chromium responder. Em prod, jobs sob carga podem precisar
    # bem mais — ajustável via ENV.
    GROVER_TIMEOUT_MS = (ENV['GROVER_TIMEOUT_MS'] || 30_000).to_i

    def self.call(**args)
      new(**args).run
    end

    # @param template      [DocumentTemplate]
    # @param patient       [Patient]
    # @param professional  [User] usuário gerando o documento
    # @param clinic        [Account] opcional; default = patient.account
    # @param save_to       [Document|ConsentRecord|nil] se presente, anexa o
    #                      PDF e persiste rendered_html + pdf_hash. Se nil,
    #                      cria um Document novo automaticamente.
    # @param title         [String] opcional; default = template.name
    # @param now           [Time] opcional; default = Time.current
    def initialize(template:, patient:, professional:, clinic: nil, save_to: nil, title: nil, now: Time.current, inputs: {})
      @template     = template
      @patient      = patient
      @professional = professional
      @clinic       = clinic || patient.account
      @save_to      = save_to
      @title        = title || template.name
      @now          = now
      # Campos de preenchimento (input.*) digitados na geração.
      @inputs       = inputs || {}
    end

    def run
      html = render_html
      pdf_bytes = html_to_pdf(html)
      hash = Digest::SHA256.hexdigest(pdf_bytes)

      document = @save_to || build_document_record
      attach_to_record(document, pdf_bytes, html, hash)

      Result.new(
        success?: true,
        document: document,
        pdf_data: pdf_bytes,
        html: html,
        pdf_hash: hash,
        error: nil
      )
    rescue StandardError => e
      Rails.logger.error("[DocumentTemplates::PdfGenerator] #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
      Result.new(success?: false, error: "#{e.class}: #{e.message}")
    end

    private

    attr_reader :template, :patient, :professional, :clinic, :now

    def render_html
      resolver = Resolver.new(
        patient: @patient,
        clinic: @clinic,
        professional: @professional,
        now: @now,
        inputs: @inputs
      )
      Renderer.new(template: template, resolver: resolver).render
    end

    def html_to_pdf(html)
      Grover.new(
        html,
        format: template.paper_size.presence || 'A4',
        landscape: template.orientation == 'landscape',
        margin: { top: '20mm', right: '15mm', bottom: '20mm', left: '15mm' },
        print_background: true,
        prefer_css_page_size: true,
        timeout: GROVER_TIMEOUT_MS
      ).to_pdf
    end

    # Cria Document novo quando o caller não passou `save_to`. Útil pro fluxo
    # padrão "gerar documento do paciente".
    # Pra templates de CONSENTIMENTO (consent?), o record correto é
    # `ConsentRecord` (schema diferente: body, signature_blob, fluxo de
    # assinatura). Por isso levantamos erro quando `save_to` está ausente —
    # o caller (futuro controller de consentimento) deve passar `save_to:`
    # com o ConsentRecord. Fica explícito que template→Document é só pro
    # caminho clínico.
    def build_document_record
      if template.consent?
        raise ArgumentError,
              "Template '#{template.name}' é de consentimento — passe save_to: " \
              'com um ConsentRecord (Document só aceita tipos clínicos).'
      end

      Document.new(
        patient: patient,
        account: clinic,
        generated_by: professional,
        document_type: template.document_type,
        title: @title,
        is_generated: true,
        status: 'gerado',
        variables: {} # vazio: o conteúdo verdadeiro vive em rendered_html
      )
    end

    def attach_to_record(record, pdf_bytes, html, hash)
      record.transaction do
        # Constrói o hash de atributos dinamicamente — só inclui pdf_hash
        # se o record TEM essa coluna. ConsentRecord não tem (reusa
        # `integrity_hash`, atualizado pelo ConsentRecordBuilder); passar
        # `nil` pra um atributo inexistente dispara UnknownAttributeError.
        attrs = {
          document_template_id: template.id,
          rendered_html: html
        }
        attrs[:pdf_hash] = hash if hash_attribute_supported?(record)
        record.assign_attributes(attrs)

        # Active Storage attach — Document tem :file, ConsentRecord ainda
        # não tem (legado guarda no body). Anexamos só quando o record
        # responde a `file`.
        if record.respond_to?(:file) && record.file
          record.file.attach(
            io: StringIO.new(pdf_bytes),
            filename: filename_for(record),
            content_type: 'application/pdf'
          )
        end

        record.save!
      end
    end

    # Document tem coluna pdf_hash (migration 20260527000003). ConsentRecord
    # reusa integrity_hash existente — tratamos de fora pra não complicar
    # aqui. Se precisar, atualizar integrity_hash no caller.
    def hash_attribute_supported?(record)
      record.respond_to?(:pdf_hash=) &&
        record.class.column_names.include?('pdf_hash')
    end

    def filename_for(record)
      slug = template.document_type.to_s.parameterize
      version = record.respond_to?(:version) ? record.version : 1
      "#{slug}-#{patient.id}-v#{version || 1}.pdf"
    end
  end
end
