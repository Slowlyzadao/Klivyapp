# frozen_string_literal: true

# app/services/patients/session_log_finalizer.rb
#
# Responsabilidade: profissional assina uma sessão de evolução (draft → signed).
# Após assinatura, a sessão torna-se imutável; só podemos marcar errata.
#
# Uso:
#   result = Patients::SessionLogFinalizer.call(session_log: @log, actor: current_user)
#   result.success?

module Patients
  class SessionLogFinalizer
    Result = Struct.new(:success, :session_log, :error, keyword_init: true) do
      def success? = success
    end

    def self.call(session_log:, actor:)
      new(session_log: session_log, actor: actor).call
    end

    def initialize(session_log:, actor:)
      @session_log = session_log
      @actor = actor
    end

    def call
      return error_result('Sessão já está assinada.') if @session_log.status_signed?
      return error_result('Janela de edição encerrada. Contate um administrador.') unless @session_log.within_draft_window?
      return error_result('Você não tem permissão para assinar esta sessão.') unless authorized?

      ActiveRecord::Base.transaction do
        @session_log.sign!(actor: @actor)
      end

      Result.new(success: true, session_log: @session_log)
    rescue StandardError => e
      Result.new(success: false, session_log: @session_log, error: e.message)
    end

    private

    def authorized?
      @session_log.professional_id == @actor.id ||
        @actor.administrator? ||
        @actor.custom_role&.name.to_s.in?(%w[supervisor])
    end

    def error_result(msg)
      Result.new(success: false, session_log: @session_log, error: msg)
    end
  end
end
