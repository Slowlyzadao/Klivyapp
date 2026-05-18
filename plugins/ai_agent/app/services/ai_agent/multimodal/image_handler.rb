require 'net/http'
require 'json'
require 'base64'

module AiAgent
  module Multimodal
    # Recebe um Attachment de imagem ou vídeo e decide o que a Bea
    # deve responder + qual nota interna abrir + se escala humano.
    #
    # **NÃO interpreta clinicamente.** CFM 2.454/2026 proíbe IA de
    # opinar sobre imagem médica. Aqui só CLASSIFICA o tipo da
    # imagem (receita / foto clínica / exame / documento / outro)
    # e devolve o roteamento — a equipe humana vê o conteúdo real.
    #
    # Tolerante: classificador falhando vira fallback `other` que
    # ainda escala humano e posta nota — paciente nunca fica sem
    # retorno, mesmo se OpenAI/internet estiverem fora.
    class ImageHandler
      Result = Struct.new(:category, :patient_message, :staff_note,
                          :priority, :handoff_required, keyword_init: true)

      OPENAI_ENDPOINT = 'https://api.openai.com/v1/chat/completions'.freeze
      VISION_MODEL = 'gpt-4o-mini'.freeze
      VALID_CATEGORIES = %w[prescription clinical_photo exam_image document other].freeze
      MAX_IMAGE_BYTES = 20 * 1024 * 1024
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 30

      def initialize(attachment:)
        @attachment = attachment
      end

      # Vídeo nunca é classificado — escala humano direto. CFM
      # proíbe interpretação automática e o custo de processar
      # vídeo via Vision não compensa o sinal extra.
      def self.video_result
        Result.new(
          category: 'video',
          patient_message: 'Recebi seu vídeo. Vou encaminhar pra nossa equipe avaliar e te retornam por aqui em instantes. 🎥',
          staff_note: '🎥 [Bea] Paciente enviou vídeo. Bea não interpreta vídeo — equipe deve revisar e responder.',
          priority: 'high',
          handoff_required: true
        )
      end

      def call
        return fallback_result('attachment_invalid') unless @attachment&.file&.attached?
        return fallback_result('too_large') if @attachment.file.byte_size > MAX_IMAGE_BYTES

        category = classify
        build_result(category)
      rescue StandardError => e
        Rails.logger.warn("[AiAgent::Multimodal::ImageHandler] attachment=#{@attachment&.id} #{e.class}: #{e.message[0, 200]}")
        fallback_result('classifier_error')
      end

      private

      def classify
        api_key = openai_api_key
        return 'other' if api_key.blank?

        @attachment.file.blob.open do |tempfile|
          base64 = Base64.strict_encode64(File.binread(tempfile.path))
          mime = @attachment.file.content_type.presence || 'image/jpeg'
          response = post_to_openai(api_key, base64, mime)
          return 'other' unless response.is_a?(Net::HTTPSuccess)

          payload = JSON.parse(response.body)
          raw = payload.dig('choices', 0, 'message', 'content').to_s.strip.downcase
          # Modelo às vezes inclui pontuação ou frase — extrai o
          # primeiro termo válido.
          match = raw[/\b(prescription|clinical_photo|exam_image|document|other)\b/]
          VALID_CATEGORIES.include?(match) ? match : 'other'
        end
      end

      def post_to_openai(api_key, base64_image, mime)
        uri = URI(OPENAI_ENDPOINT)

        body = {
          model: VISION_MODEL,
          messages: [
            {
              role: 'user',
              content: [
                { type: 'text', text: classification_prompt },
                { type: 'image_url',
                  image_url: { url: "data:#{mime};base64,#{base64_image}", detail: 'low' } }
              ]
            }
          ],
          max_tokens: 12,
          temperature: 0
        }.to_json

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        req = Net::HTTP::Post.new(uri,
                                   'Authorization' => "Bearer #{api_key}",
                                   'Content-Type' => 'application/json')
        req.body = body
        http.request(req)
      end

      def classification_prompt
        <<~PROMPT
          Classifique esta imagem em UMA categoria de uma clínica de saúde brasileira.
          Responda APENAS uma palavra (sem explicação, sem pontuação):

          - prescription   → receita médica, atestado, laudo, encaminhamento, relatório clínico (texto impresso/manuscrito em folha)
          - clinical_photo → foto de boca, dente, gengiva, pele, lesão, ferida, parte do corpo do paciente
          - exam_image    → raio-x, tomografia, ressonância, ultrassom, periapical, panorâmica
          - document      → RG, CPF, CNH, comprovante de pagamento, carteirinha de plano de saúde
          - other         → qualquer outra (selfie sem contexto clínico, paisagem, screenshot, meme, foto pessoal genérica)

          Resposta:
        PROMPT
      end

      def build_result(category)
        case category
        when 'prescription'
          Result.new(
            category: category,
            patient_message: 'Recebi sua receita. Vou encaminhar para nossa equipe avaliar e te retornam por aqui em instantes. 📄',
            staff_note: '📄 [Bea] Paciente enviou receita/laudo médico. Bea NÃO interpretou conteúdo. Equipe deve revisar a imagem e responder.',
            priority: 'high',
            handoff_required: true
          )
        when 'clinical_photo'
          Result.new(
            category: category,
            patient_message: 'Recebi sua foto. Vou encaminhar pra equipe clínica avaliar e te retornam aqui assim que possível. 🦷',
            staff_note: '🩺 [Bea — atenção] Paciente enviou FOTO CLÍNICA (boca/lesão/parte do corpo). CFM proíbe interpretação automática — equipe clínica deve avaliar com urgência e responder.',
            priority: 'high',
            handoff_required: true
          )
        when 'exam_image'
          Result.new(
            category: category,
            patient_message: 'Recebi sua imagem de exame. Eu não posso interpretar exames por aqui, mas vou encaminhar pra equipe clínica. Te retornamos em breve. 🔍',
            staff_note: '🔬 [Bea — atenção] Paciente enviou IMAGEM DE EXAME (RX/TC/RM/USG). CFM proíbe interpretação por IA — equipe clínica avalia e responde.',
            priority: 'high',
            handoff_required: true
          )
        when 'document'
          Result.new(
            category: category,
            patient_message: 'Recebi seu documento. A equipe vai validar e te confirmo aqui em instantes. 📑',
            staff_note: 'ℹ️ [Bea] Paciente enviou documento (RG/CPF/comprovante/carteirinha). Equipe deve cadastrar/validar.',
            priority: 'normal',
            handoff_required: true
          )
        else
          Result.new(
            category: 'other',
            patient_message: 'Recebi sua imagem. Vou encaminhar pra nossa equipe dar uma olhada. 📸',
            staff_note: 'ℹ️ [Bea] Paciente enviou imagem que Bea não conseguiu classificar. Equipe deve revisar.',
            priority: 'normal',
            handoff_required: true
          )
        end
      end

      def fallback_result(reason)
        Rails.logger.info("[AiAgent::Multimodal::ImageHandler] fallback=#{reason} attachment=#{@attachment&.id}")
        build_result('other')
      end

      def openai_api_key
        ::RubyLLM.config.openai_api_key.presence ||
          InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value.presence ||
          ENV.fetch('OPENAI_API_KEY', nil)
      end
    end
  end
end
