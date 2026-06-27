module AiAgent
  module Tools
    class SearchAvailableSlotsTool < BaseTool
      # ARCH-3 (audit 2026-05-19): extraído de SearchAvailableSlotsTool#parse_window.
      # Validador puro de janela de busca pra agenda — parsing + bound checks.
      #
      # Retorna `Result` (Struct keyword-init) com `from`/`to`/`error_message`.
      # Quando `error_message` está presente, o caller deve usar o `failure(...)`
      # padrão do BaseTool pra responder ao LLM.
      #
      # Limites:
      # - `from` no passado é silenciosamente bumpado pra `Date.current`
      # - `to` no passado retorna erro (intencional — janela inteira no passado é erro do LLM)
      # - Janela > MAX_WINDOW_DAYS retorna erro (evita LLM pedir 60 dias de slots)
      class DateRangeValidator
        MAX_WINDOW_DAYS = 14
        DEFAULT_WINDOW_DAYS = 7

        Result = Struct.new(:from, :to, :error_message, keyword_init: true)

        def self.call(from_date:, to_date: nil)
          from = Date.parse(from_date.to_s)
          to   = to_date.present? ? Date.parse(to_date.to_s) : from + DEFAULT_WINDOW_DAYS
          from = Date.current if from < Date.current

          return Result.new(error_message: 'Data final no passado.') if to < Date.current

          if (to - from) > MAX_WINDOW_DAYS
            return Result.new(error_message: "Janela maior que #{MAX_WINDOW_DAYS} dias — quebre a busca em pedaços.")
          end

          Result.new(from: from, to: to)
        rescue ArgumentError
          Result.new(error_message: 'Data inválida. Use formato YYYY-MM-DD.')
        end
      end
    end
  end
end
