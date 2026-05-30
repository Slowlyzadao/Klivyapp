# Sprint L — Interface (provider-agnostic) de transcrição.
#
# Implementações concretas (cada uma é uma classe `TranscriptionProvider::*`)
# devem expor `call(audio_io:, language:)` e retornar uma estrutura
# `Segments` com array de `{start, end, text}` (em segundos, texto puro —
# sem tag de speaker; speaker é decidido pelo caller via origem do arquivo).
#
# Decisão MVP (PRD §5.2): Whisper. Pra escala/custo críticos, swap pra
# Gemini Flash audio nativo via `with(:gemini_flash)` no provider factory.
module Telemed
  module TranscriptionProvider
    # 2026-05-23 — `speaker` adicionado (opcional). Providers que diarizam
    # internamente (gpt-4o-transcribe-diarize) preenchem com a label que
    # vem da API ("speaker_0", "speaker_1"); providers sem diarização
    # deixam nil e o caller decide o speaker pela origem do arquivo.
    Segment = Struct.new(:start, :end_, :text, :speaker, keyword_init: true) do
      def to_h
        h = { start: start, end: end_, text: text }
        h[:speaker] = speaker if speaker
        h
      end
    end

    Result = Struct.new(:segments, :raw_text, :provider, keyword_init: true) do
      def to_segments_array
        segments.map(&:to_h)
      end
    end

    # Factory simples — string → classe. Adicionar novos providers aqui
    # quando virarem necessários.
    def self.for(name)
      case name.to_s
      when 'gpt-4o-transcribe-diarize', 'diarize'
        Gpt4oDiarize.new
      when 'whisper', '', nil
        Whisper.new
      when 'gemini'
        # Marcador — Fase 2 (Gemini 2.5 Flash audio nativo).
        raise NotImplementedError, "TranscriptionProvider :gemini não implementado neste MVP"
      else
        raise ArgumentError, "TranscriptionProvider desconhecido: #{name}"
      end
    end
  end
end
