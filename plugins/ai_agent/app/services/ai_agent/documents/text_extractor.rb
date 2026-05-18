require 'pdf-reader'

module AiAgent
  module Documents
    # Extracts plain text from a Document, depending on its source_type.
    #   - pdf  → reads the attached file with PDF::Reader
    #   - text → returns whatever was passed in (currently no field; reserved)
    #   - url  → fetches the URL and strips HTML
    class TextExtractor
      class ExtractionError < StandardError; end

      def initialize(document)
        @document = document
      end

      def call
        case @document.source_type
        when 'pdf' then extract_pdf
        when 'url' then extract_url
        else raise ExtractionError, "unsupported source_type: #{@document.source_type}"
        end
      end

      private

      def extract_pdf
        raise ExtractionError, 'no PDF attached' unless @document.pdf_file.attached?

        pages = []
        @document.pdf_file.blob.open do |file|
          reader = PDF::Reader.new(file)
          reader.pages.each { |p| pages << p.text.to_s }
        end
        pages.join("\n\n")
      rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
        raise ExtractionError, "PDF parse error: #{e.message}"
      end

      def extract_url
        raise ExtractionError, 'external_link missing' if @document.external_link.blank?

        html = Faraday.get(@document.external_link).body
        Html2Text.convert(html)
      rescue Faraday::Error => e
        raise ExtractionError, "URL fetch error: #{e.message}"
      end
    end
  end
end
