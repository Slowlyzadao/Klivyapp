module Financial
  module IdempotentAction
    extend ActiveSupport::Concern
    # Concern para endpoints de escrita que aceitam header Idempotency-Key.
    # Canon Parte 6 §"Idempotência" — armazena (account_id, key) → response por 24h.
    #
    # Uso:
    #   class ReceivePaymentsController < ApplicationController
    #     include Financial::IdempotentAction
    #
    #     def create
    #       idempotent! do
    #         result = Financial::ReceivePayment.call(...)
    #         render json: result.to_h, status: :created
    #       end
    #     end
    #   end
    #
    # Segurança: o fingerprint do request (SHA-256 do body) é comparado com o
    # registrado. Se a mesma key chegar com body diferente, retorna 409 Conflict
    # (proteção contra reuso de key acidentalmente).

    HEADER = 'Idempotency-Key'.freeze
    TTL_HOURS = 24
    MAX_KEY_LENGTH = 80

    included do
      attr_reader :_financial_idempotency_key
    end

    private

    def idempotent!
      key = request.headers[HEADER]
      if key.blank?
        # Endpoint exige Idempotency-Key. Se quiser tornar opcional, use
        # idempotent_optional! em vez de idempotent!.
        return render(json: { error: "missing #{HEADER} header" }, status: :bad_request)
      end

      idempotent_with_key(key) { yield }
    end

    def idempotent_optional!
      key = request.headers[HEADER]
      return yield if key.blank?

      idempotent_with_key(key) { yield }
    end

    def idempotent_with_key(key)
      validate_key!(key)

      account_id = current_account_id
      fingerprint = compute_fingerprint
      Thread.current[:financial_idempotency_key] = key

      existing = Financial::IdempotencyKey.find_by(account_id: account_id, key: key)

      if existing
        if existing.fresh? && existing.matches_request?(request_path, request_method, fingerprint)
          response.set_header('Idempotency-Replayed', 'true')
          render json: existing.response_body, status: existing.response_status
          return
        elsif existing.fresh?
          render json: { error: 'idempotency key reused with different request' }, status: :conflict
          return
        end
        # Stale: limpa para reutilizar chave.
        existing.destroy
      end

      yield

      # Captura response para gravar (serializa apenas se o controller renderizou JSON com sucesso).
      persist_idempotency!(account_id, key, fingerprint)
    ensure
      Thread.current[:financial_idempotency_key] = nil
    end

    def validate_key!(key)
      if key.length > MAX_KEY_LENGTH
        raise ActionController::BadRequest, "#{HEADER} too long"
      end
    end

    def compute_fingerprint
      raw = request.raw_post.to_s
      Digest::SHA256.hexdigest(raw)
    end

    def request_path
      request.fullpath.split('?').first
    end

    def request_method
      request.method
    end

    def current_account_id
      # Padrão Klivy: Current.account ou before_action setou @account / @current_account
      Current.try(:account)&.id ||
        instance_variable_get(:@current_account)&.id ||
        instance_variable_get(:@account)&.id ||
        params[:account_id]
    end

    def persist_idempotency!(account_id, key, fingerprint)
      # Auditoria 2026-05-22 (`ALTO-SVC-04`): persiste TODOS os status code
      # exceto 5xx. Antes só gravava 2xx — retry com mesmo key após 422
      # reexecutava a operação, podendo passar na 2ª tentativa por race
      # condition (ex: validação que dependia de estado externo já mudou).
      #
      # Política nova:
      #   2xx, 3xx, 4xx → grava resposta (idempotência completa)
      #   5xx → não grava (server error é transient; cliente pode retry)
      return if response.status >= 500
      return if response.body.blank?

      body = begin
        JSON.parse(response.body)
      rescue JSON::ParserError
        { 'raw' => response.body }
      end

      Financial::IdempotencyKey.create!(
        account_id: account_id,
        key: key,
        request_path: request_path,
        request_method: request_method,
        request_fingerprint: fingerprint,
        response_status: response.status,
        response_body: body,
        user_id: Financial::CurrentUser.id,
        created_at: Time.current
      )
    rescue ActiveRecord::RecordNotUnique
      # corrida com outro request da mesma key — segundo request perde, ok.
    end
  end
end
