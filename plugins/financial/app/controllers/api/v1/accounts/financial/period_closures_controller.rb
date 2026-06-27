module Api
  module V1
    module Accounts
      module Financial
        # Fechamento contábil de período. Ações:
        #   POST  /financial/v2/period_closures           → fechar mês (ADMIN)
        #   POST  /financial/v2/period_closures/:id/reopen → reabrir (ADMIN, motivo)
        #   GET   /financial/v2/period_closures            → histórico
        #
        # Não existe `update`/`destroy` — fechamento é evento append-only.
        # Reabrir é registrado no MESMO registro (mudando status + populando
        # campos de reopen). Pra fechar de novo depois, cria NOVO registro.
        class PeriodClosuresController < BaseController
          # Endpoint pode ser acessado pra mostrar status mesmo durante setup
          skip_before_action :ensure_setup_complete!, only: %i[index]

          before_action :authorize_admin!, only: %i[create reopen]

          # GET /financial/v2/period_closures?year=2026
          def index
            scope = ::Financial::PeriodClosure
                      .for_account(current_account.id)
                      .order(period_year: :desc, period_month: :desc)
            scope = scope.where(period_year: params[:year]) if params[:year].present?
            scope = scope.where(status: params[:status]) if params[:status].present?
            render json: { data: scope.map { |c| serialize(c) } }
          end

          def show
            closure = ::Financial::PeriodClosure
                        .for_account(current_account.id)
                        .find(params[:id])
            render json: serialize(closure)
          end

          # POST /financial/v2/period_closures
          # body: { period_closure: { period_year, period_month, notes } }
          def create
            idempotent! do
              result = ::Financial::Governance::ClosePeriod.call(
                account: current_account,
                year: closure_params[:period_year],
                month: closure_params[:period_month],
                actor: current_user,
                notes: closure_params[:notes]
              )

              if result.success?
                status_code = result.errors.include?('already_closed') ? :ok : :created
                render json: serialize(result.closure), status: status_code
              else
                render json: { errors: result.errors }, status: :unprocessable_entity
              end
            end
          end

          # POST /financial/v2/period_closures/:id/reopen
          # body: { reason: "..." }
          def reopen
            closure = ::Financial::PeriodClosure
                        .for_account(current_account.id)
                        .find(params[:id])

            idempotent! do
              result = ::Financial::Governance::ReopenPeriod.call(
                account: current_account,
                year: closure.period_year,
                month: closure.period_month,
                actor: current_user,
                reason: params[:reason].to_s
              )

              if result.success?
                render json: serialize(result.closure)
              else
                render json: { errors: result.errors }, status: :unprocessable_entity
              end
            end
          end

          private

          def authorize_admin!
            require_role!('ADMIN') and return unless user_has_any_role?(%w[ADMIN])
          end

          def closure_params
            params.require(:period_closure).permit(:period_year, :period_month, :notes)
          end

          def serialize(closure)
            {
              id: closure.id,
              period_year: closure.period_year,
              period_month: closure.period_month,
              status: closure.status,
              closed_at: closure.closed_at,
              closed_by_id: closure.closed_by_id,
              notes: closure.notes,
              reopened_at: closure.reopened_at,
              reopened_by_id: closure.reopened_by_id,
              reopen_reason: closure.reopen_reason,
              created_at: closure.created_at,
              updated_at: closure.updated_at
            }
          end
        end
      end
    end
  end
end
