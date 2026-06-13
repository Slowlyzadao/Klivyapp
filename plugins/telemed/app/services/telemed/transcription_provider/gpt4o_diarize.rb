# OpenAI gpt-4o-transcribe-diarize — sucessor do whisper-1 (lançado mar/2025,
# production-stable em 2026). Vantagens pro nosso caso de teleconsulta:
#
#   - WER 2.46% (vs 5.3% do whisper-1) → ~54% menos erros.
#   - Diarização nativa por voiceprint — separa speakers pelas
#     características da voz, NÃO por arquivo. Resolve o crosstalk acústico
#     (mic do paciente capta som do speaker dele): mesmo no áudio
#     contaminado, o modelo associa cada trecho ao falante correto.
#   - Mesmo preço do whisper-1 ($0.006/min).
#   - PT-BR em paridade com inglês.
#
# Requisito específico da API: pra áudios > 30s, `chunking_strategy: "auto"`
# é obrigatório. Sem isso a request retorna 400 "chunking_strategy is required".
require 'openai'

module Telemed
  module TranscriptionProvider
    class Gpt4oDiarize
      DEFAULT_MODEL    = 'gpt-4o-transcribe-diarize'.freeze
      DEFAULT_LANGUAGE = 'pt'.freeze
      # Mesmo timeout do Whisper — Diarize tende a ser ligeiramente mais
      # lento (modelo maior) mas dentro da mesma ordem de grandeza.
      REQUEST_TIMEOUT = 900

      # Prompt com vocabulário odontológico — "ancora" o modelo no domínio
      # da consulta, reduz erros tipo "canino" → "caminho", "molar" →
      # "moral", "endodontia" → "endodonsia". A OpenAI documenta que o
      # `prompt` pode conter até 244 tokens de contexto/glossário; pra
      # palavras fora desse glossário o modelo continua "free" — não
      # força a output, só sugere. Genérico o bastante pra cobrir todas
      # as consultas odontológicas sem viesar pra nenhuma especialidade.
      DEFAULT_PROMPT = (
        'Teleconsulta odontológica em português brasileiro entre dentista e paciente. ' \
        'Vocabulário comum: dente, dentes, gengiva, gengivite, periodontite, cárie, ' \
        'restauração, canal, endodontia, extração, cirurgia, ortodontia, aparelho, ' \
        'implante, prótese, coroa, faceta, clareamento, profilaxia, limpeza, ' \
        'molar, pré-molar, canino, incisivo, siso, raiz, esmalte, dentina, polpa, ' \
        'sensibilidade, dor, inchaço, sangramento, abscesso, anestesia, radiografia.'
      ).freeze

      # Mesmos padrões de hallucination do whisper-1 — o modelo novo
      # alucina menos, mas em silêncio total ainda emite "..." vazio em
      # alguns casos. Lista compartilhada via constante na classe Whisper.
      HALLUCINATION_PATTERNS = Whisper::HALLUCINATION_PATTERNS

      def initialize(api_key: nil, model: DEFAULT_MODEL)
        @api_key = api_key.presence || Whisper.new.send(:lookup_api_key)
        @model   = model
      end

      # `audio_io` aceita File/Tempfile/IO. `language` ISO-639-1 ('pt', 'en').
      def call(audio_io:, language: DEFAULT_LANGUAGE)
        raise 'OPENAI_WHISPER_KEY não configurada' if @api_key.blank?

        client = OpenAI::Client.new(access_token: @api_key, request_timeout: REQUEST_TIMEOUT)
        # NÃO passar `prompt`: o `gpt-4o-transcribe-diarize` REJEITA com 400
        # "Prompt is not supported for diarization models". A constante
        # `DEFAULT_PROMPT` continua exposta porque os outros providers
        # (whisper-1 nos arquivos isolados) usam.
        response = client.audio.transcribe(
          parameters: {
            file: audio_io,
            model: @model,
            language: language,
            response_format: 'diarized_json',
            timestamp_granularities: ['segment'],
            # `chunking_strategy: "auto"` é OBRIGATÓRIO pra áudio > 30s.
            # Teleconsulta tem no mínimo 1-2 min, então sempre. "auto"
            # deixa a OpenAI escolher o VAD pra separar em chunks.
            chunking_strategy: 'auto'
          }
        )

        segments = parse_segments(response)

        TranscriptionProvider::Result.new(
          segments: segments,
          raw_text: response['text'].to_s,
          provider: 'gpt-4o-transcribe-diarize'
        )
      end

      private

      # API retorna em `diarized_json`:
      #   { text: "...", segments: [{start, end, text, speaker}], usage: {...} }
      # `speaker` vem como "speaker_0", "speaker_1" etc. (1 por voiceprint).
      def parse_segments(response)
        (response['segments'] || []).filter_map do |seg|
          text = seg['text'].to_s.strip
          next if text.empty? || hallucination?(text)

          TranscriptionProvider::Segment.new(
            start:   seg['start'].to_f,
            end_:    seg['end'].to_f,
            text:    text,
            speaker: seg['speaker'].to_s.presence
          )
        end
      end

      def hallucination?(text)
        HALLUCINATION_PATTERNS.any? { |re| text.match?(re) }
      end
    end
  end
end
