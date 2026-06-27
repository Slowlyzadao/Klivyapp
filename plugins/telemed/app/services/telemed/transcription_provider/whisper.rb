# Sprint L — Implementação Whisper API da interface TranscriptionProvider.
#
# Modelo: `whisper-1` (single SKU). Custo $0.006/min — ~$0.36/h por faixa
# (PRD §5.2). Retorna response com `segments[]` quando passamos
# `response_format: 'verbose_json'`. Diarização *não* faz parte do Whisper
# — o caller combina pelos arquivos separados (1 arquivo = 1 speaker).
#
# Idempotência: chamadas são puras — mesma entrada produz mesma saída
# (com leve variação probabilística, mas estrutura idêntica).
require 'openai'

module Telemed
  module TranscriptionProvider
    class Whisper
      # `whisper-1` mantido como default porque é o ÚNICO modelo OpenAI que
      # retorna segments com timestamps via `verbose_json` — necessário pro
      # modo fallback do TranscribeJob (transcrever doctor.ogg/patient.ogg
      # cronologicamente). `gpt-4o-transcribe` é mais preciso (WER 2.46%
      # vs 5.3%) mas só retorna texto sem timestamps. Caller pode passar
      # `model: 'gpt-4o-transcribe'` quando quiser só o texto (caso
      # `transcribe_text_only` no TranscribeJob).
      DEFAULT_MODEL = 'whisper-1'.freeze
      DEFAULT_LANGUAGE = 'pt'.freeze
      # 1h de áudio em condições ideais leva 1-2 min, mas Portuguese médico
      # denso + diarização frequentemente sobe pra 3-5 min. 900s (15min) cobre
      # consultas longas (até ~2h) com folga sem travar workers indefinido.
      REQUEST_TIMEOUT = 900

      # Padrões de hallucination conhecidos do whisper-1 em PT-BR. Quando
      # o modelo recebe trecho silencioso ou com crosstalk baixo, ele
      # preenche com frases do dataset de treino (YouTube/legendas, sites
      # de subtítulo etc.) ou só pontuação. Lista cresce conforme aparecem
      # novos — `text.match?(REGEX)` descarta o segment inteiro.
      # `temperature: 0` no Whisper já reduz variabilidade, mas o output
      # determinístico em silêncio ainda é texto aluciado — daí o
      # combinador `temp 0 + denoise pré-API + filtro pós-API`.
      HALLUCINATION_PATTERNS = [
        /\A[.…\-\s]*\z/,                              # só pontuação/vazio
        /\Aobrigad[oa]\s+por\s+(assistir|ver)/i,      # YT
        /\Alegendad[oa]\s+por/i,                      # legendas
        /\Asubtitled\s+by/i,                          # legendas EN
        /\Atranscri(çã|cao)o\s+(automática|por)/i,    # auto-caption
        /\Aal[oô],?\s+galera/i,                       # YT streamer ("alô galera", "alô galera de casa")
        /\Anão\s+tenho\s+dinheiro/i,                  # loop comum em silêncio
        /\A(muito\s+)?obrigad[oa]\.?\z/i,             # genérico curto
        /\A(legenda(s)?|tradução|tradutor)\s*:/i      # crédito de legenda
      ].freeze

      def initialize(api_key: nil, model: DEFAULT_MODEL)
        @api_key = api_key.presence || lookup_api_key
        @model   = model
      end

      # `audio_io` aceita File/Tempfile/IO. `language` ISO-639-1 ('pt', 'en').
      def call(audio_io:, language: DEFAULT_LANGUAGE)
        raise 'OPENAI_WHISPER_KEY não configurada' if @api_key.blank?

        # ruby-openai 7.x separou em `transcribe` (mantém língua original)
        # e `translate` (traduz pra EN). Antes era `translate_or_transcribe`
        # (deprecated). Queremos PT-BR no áudio → PT-BR no texto = transcribe.
        # `temperature: 0` é o que a OpenAI recomenda pra reduzir variância
        # entre runs e cortar hallucinations probabilísticas.
        client = OpenAI::Client.new(access_token: @api_key, request_timeout: REQUEST_TIMEOUT)
        # `gpt-4o-transcribe` (default novo) só aceita `response_format: 'json'`
        # — sem timestamps. Whisper-1 (legado) suporta `verbose_json` com
        # segments. Decide o formato pelo modelo. Pra modelos gpt-4o-*,
        # caller deve usar `Gpt4oDiarize` se quiser timestamps + speakers.
        params = {
          file: audio_io,
          model: @model,
          language: language,
          temperature: 0,
          prompt: Gpt4oDiarize::DEFAULT_PROMPT
        }
        if @model.start_with?('whisper')
          params[:response_format] = 'verbose_json'
          params[:timestamp_granularities] = ['segment']
        else
          params[:response_format] = 'json'
        end

        response = client.audio.transcribe(parameters: params)

        segments = (response['segments'] || []).filter_map do |seg|
          text = seg['text'].to_s.strip
          next if text.empty? || hallucination?(text)

          TranscriptionProvider::Segment.new(
            start: seg['start'].to_f,
            end_:  seg['end'].to_f,
            text:  text
          )
        end

        TranscriptionProvider::Result.new(
          segments: segments,
          raw_text: response['text'].to_s,
          provider: 'whisper'
        )
      end

      private

      def hallucination?(text)
        HALLUCINATION_PATTERNS.any? { |re| text.match?(re) }
      end

      # `OPENAI_WHISPER_KEY` permite usar conta dedicada com billing isolado
      # do Captain (que usa `CAPTAIN_OPEN_AI_API_KEY`). Fallback é a chave
      # do Captain se a dedicada não estiver setada.
      def lookup_api_key
        ENV['OPENAI_WHISPER_KEY'].presence ||
          InstallationConfig.find_by(name: 'OPENAI_WHISPER_KEY')&.value ||
          InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
      end
    end
  end
end
