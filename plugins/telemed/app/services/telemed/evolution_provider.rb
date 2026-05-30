# Sprint L — Interface (provider-agnostic) de geração de evolução clínica.
#
# Implementações concretas devem expor:
#   `call(transcript:, patient_context:)` → Result
#
# Mantemos a interface fina porque o frontend hoje só precisa do `Result`
# parseado (SOAP + attention_points + metadata de tokens). Trocar de
# Claude pra Gemini é trocar a classe — controller/job não muda.
#
# Decisão MVP (PRD §5.3): `claude-sonnet-4.6` via ruby_llm (Anthropic).
# Custo ~$0.06/consulta. Trocável via setting
# `patient_portal_setting.telemedicine_recording.ai_provider`.
module Telemed
  module EvolutionProvider
    DEFAULT_PROVIDER = 'claude-sonnet-4.6'.freeze

    # Resposta normalizada que o caller persiste em ProposedEvolution.
    # `soap_structure` é hash com chaves estáveis em PT-BR (backward-compat,
    # não exibido na UI atual). `raw_markdown` é o markdown bruto retornado.
    # `summary` é o bloco "Resumo Executivo" (Markdown renderizado na UI).
    # `procedure_fields` é hash com 14 chaves do "Registro de Procedimento"
    # (audit 2026-05-26) — formato editável que substituiu os cards SOAP
    # na UI da clínica.
    Result = Struct.new(
      :soap_structure, :raw_markdown, :attention_points, :summary,
      :procedure_fields,
      :provider, :input_tokens, :output_tokens,
      keyword_init: true
    )

    # Atalho de factory. String → instância de provider.
    def self.for(model_identifier = DEFAULT_PROVIDER)
      case model_identifier.to_s
      when /\Aclaude/
        Claude.new(model: claude_model_id(model_identifier))
      when /\Agpt/
        OpenAi.new(model: model_identifier)
      when /\Agemini/
        # Marcador — Fase 2 com Gemini 2.5 Pro/Flash.
        raise NotImplementedError, "EvolutionProvider :gemini não implementado no MVP"
      else
        raise ArgumentError, "EvolutionProvider desconhecido: #{model_identifier}"
      end
    end

    # `claude-sonnet-4.6` é o alias amigável; ruby_llm aceita o id real
    # `claude-sonnet-4-6` (separado por hifens). Normaliza aqui.
    def self.claude_model_id(name)
      case name.to_s
      when 'claude-sonnet-4.6'  then 'claude-sonnet-4-6'
      when 'claude-opus-4.7'    then 'claude-opus-4-7'
      else name.to_s.tr('.', '-')
      end
    end
  end
end
