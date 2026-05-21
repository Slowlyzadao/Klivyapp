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
      DEFAULT_MODEL = 'whisper-1'.freeze
      DEFAULT_LANGUAGE = 'pt'.freeze
      # 1h de áudio em condições ideais leva 1-2 min, mas Portuguese médico
      # denso + diarização frequentemente sobe pra 3-5 min. 900s (15min) cobre
      # consultas longas (até ~2h) com folga sem travar workers indefinido.
      REQUEST_TIMEOUT = 900

      def initialize(api_key: nil, model: DEFAULT_MODEL)
        @api_key = api_key.presence || lookup_api_key
        @model   = model
      end

      # `audio_io` aceita File/Tempfile/IO. `language` ISO-639-1 ('pt', 'en').
      def call(audio_io:, language: DEFAULT_LANGUAGE)
        raise 'OPENAI_WHISPER_KEY não configurada' if @api_key.blank?

        client = OpenAI::Client.new(access_token: @api_key, request_timeout: REQUEST_TIMEOUT)
        response = client.audio.translate_or_transcribe(
          parameters: {
            file: audio_io,
            model: @model,
            language: language,
            response_format: 'verbose_json',
            timestamp_granularities: ['segment']
          }
        )

        segments = (response['segments'] || []).map do |seg|
          TranscriptionProvider::Segment.new(
            start: seg['start'].to_f,
            end_:  seg['end'].to_f,
            text:  seg['text'].to_s.strip
          )
        end

        TranscriptionProvider::Result.new(
          segments: segments,
          raw_text: response['text'].to_s,
          provider: 'whisper'
        )
      end

      private

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
