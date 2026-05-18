module Api
  module V1
    module AiAgent
      # Endpoint público de feedback do paciente (👍/👎) sobre uma resposta
      # específica da Bea. Autenticação por HMAC token: cada Trace gera um
      # token único que vai pro widget junto com o trace_id. Frontend POSTa
      # esse par + rating; backend valida o token antes de gravar.
      #
      # Idempotente: 1 feedback por trace_id (UNIQUE no banco se houver).
      # Re-POSTa atualiza o feedback existente.
      #
      # Sem auth do Rails — é endpoint público de widget. Segurança vem
      # do HMAC, não do session/cookie.
      class FeedbacksController < ApplicationController
        skip_before_action :authenticate_user!, raise: false
        skip_before_action :verify_authenticity_token, raise: false

        def create
          trace_id = params[:trace_id]
          token    = params[:token]
          rating   = params[:rating].to_i

          unless ::AiAgent::FeedbackTokenSigner.verify(trace_id, token)
            return render json: { error: 'invalid_token' }, status: :unauthorized
          end

          unless [1, -1].include?(rating)
            return render json: { error: 'rating must be 1 or -1' }, status: :unprocessable_entity
          end

          trace = ::AiAgent::Trace.find_by(id: trace_id)
          return render json: { error: 'trace_not_found' }, status: :not_found if trace.nil?

          feedback = ::AiAgent::Feedback.find_or_initialize_by(trace_id: trace.id)
          feedback.assign_attributes(
            account_id: trace.account_id,
            conversation_id: trace.conversation_id,
            message_id: trace.message_id,
            contact_id: trace.contact_id,
            rating: rating,
            comment: params[:comment].to_s.strip[0, 500].presence
          )

          if feedback.save
            render json: { ok: true, id: feedback.id, rating: feedback.rating }, status: :ok
          else
            render json: { error: 'invalid', details: feedback.errors.full_messages }, status: :unprocessable_entity
          end
        end
      end
    end
  end
end
