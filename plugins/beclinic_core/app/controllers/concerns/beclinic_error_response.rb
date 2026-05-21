# Concern para padronizar resposta de erro JSON em controllers do Klivy.
#
# Problema diagnosticado na auditoria de 2026-05-03 (item #10): ~100 endpoints
# do plugin patients usam formatos inconsistentes — `{ error: "msg" }` em uns
# e `{ errors: ["msg"] }` em outros. Frontend precisa tratar ambos.
#
# Solução: helper `render_error` que emite **AMBOS os formatos** (forward-
# compatibility). Permite migrar gradualmente sem quebrar frontend existente
# que lê `data.error`. Quando todos os consumers tiverem migrado para
# `data.errors[0]`, podemos remover o `error:` legado.
#
# ## Uso
#
#   class MeuController < ApplicationController
#     include BeclinicErrorResponse
#
#     def algum_metodo
#       return render_error('Recurso inválido') unless valid?
#       render_error(record.errors.full_messages, status: :unprocessable_entity)
#       render_error('Não autorizado', status: :forbidden)
#     end
#   end
#
# ## Forma do JSON gerado
#
#   render_error('Senha errada')
#   #=> { "error": "Senha errada", "errors": ["Senha errada"] }
#
#   render_error(['CPF inválido', 'Email já existe'])
#   #=> { "error": "CPF inválido", "errors": ["CPF inválido", "Email já existe"] }
#
#   render_error(record.errors.full_messages)
#   #=> { "error": "Nome não pode ficar em branco", "errors": [...] }
#
module BeclinicErrorResponse
  extend ActiveSupport::Concern

  # Roadmap #13 — captura `ActiveRecord::StaleObjectError` (lançada pelo
  # optimistic locking do Rails quando `lock_version` no payload diverge do
  # banco) e responde 409 Conflict com payload estruturado. Frontend pode
  # detectar via `code: 'version_conflict'` e prompt o usuário a recarregar.
  included do
    rescue_from ActiveRecord::StaleObjectError, with: :handle_stale_object_error
  end

  # Status default :unprocessable_entity é o mais comum em APIs REST quando
  # o cliente mandou dados que falharam validação. Use :not_found pra 404,
  # :forbidden pra 403, :bad_request pra 400, etc.
  def render_error(message_or_messages, status: :unprocessable_entity)
    messages = Array(message_or_messages).compact.map(&:to_s)
    messages = ['Erro inesperado'] if messages.empty?

    render json: {
      error: messages.first,    # Legacy: clientes antigos que leem `data.error`
      errors: messages          # Novo padrão: array sempre presente
    }, status: status
  end

  private

  def handle_stale_object_error(_error)
    msg = 'Conflito de versão: outro usuário editou este registro. Recarregue a página antes de salvar novamente.'
    render json: {
      error: msg,
      errors: [msg],
      code: 'version_conflict'
    }, status: :conflict
  end
end
