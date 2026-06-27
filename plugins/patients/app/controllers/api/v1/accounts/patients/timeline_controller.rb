module Api
  module V1
    module Accounts
      module Patients
        class TimelineController < Api::V1::Accounts::Patients::BaseController
          HIDDEN_EVENT_TYPES = %w[payment refund].freeze

          # GET /api/v1/accounts/:account_id/patients/:patient_id/timeline
          # Parâmetros opcionais:
          #   ?type=payment,appointment_done  (filtra por tipo de evento)
          #   ?from=2026-01-01               (a partir de)
          #   ?to=2026-12-31                 (até)
          #   ?page=1&per_page=50
          def index
            authorize @patient, :timeline?

            # Eventos financeiros (`payment`/`refund`) ficaram órfãos quando o
            # `Patients::FinancialTimelineBuilder` (v1) foi removido em 2026-05-11
            # (commit 9b3383a1). Os snapshots antigos travaram com status="pendente"
            # e o Financial V2 não emite novos. Visão consolidada do dinheiro vive
            # na aba Financeiro do prontuário — Timeline foca em clínico/agenda/docs.
            @events = @patient.patient_timeline_events
                              .where.not(event_type: HIDDEN_EVENT_TYPES)
                              .then { |q| apply_filters(q) }
                              .chronological
                              .page(params[:page])
                              .per(params[:per_page] || 50)

            render 'api/v1/accounts/patients/timeline/index'
          end

          private

          # Padrão Pundit deste controller: a action `index` chama
          # `authorize @patient, :timeline?` explicitamente (linha 13). O
          # auto-call do Api::BaseController é desligado pra evitar conflito
          # (BaseController tentaria autorizar `Timeline` ao invés de @patient).
          #
          # ⚠️ CRÍTICO: ao adicionar nova action neste controller, garanta que
          # ela chama `authorize @patient, :alguma_action?` explicitamente.
          # Sem isso, a action ficará SEM proteção de autorização.
          def check_authorization
            true
          end

          def apply_filters(scope)
            if params[:type].present?
              types = params[:type].split(',').map(&:strip)
              scope = scope.by_type(types)
            end

            scope = scope.after_date(Date.parse(params[:from])) if params[:from].present?
            scope = scope.before_date(Date.parse(params[:to]).end_of_day) if params[:to].present?

            scope
          end
        end
      end
    end
  end
end
