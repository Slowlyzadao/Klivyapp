module Api
  module V1
    module Accounts
      module Patients
        class SessionLogsController < Api::V1::Accounts::Patients::BaseController
          before_action :set_session_log, only: [:show, :destroy]

          # GET /api/v1/accounts/:account_id/patients/:patient_id/session_logs
          def index
            authorize SessionLog
            @session_logs = @patient.session_logs
                                    .where(deleted_at: nil)
                                    .includes(:professional, :treatment_plan, :treatment_item)
                                    .order(performed_at: :desc)
                                    .page(params[:page]).per(params[:per_page] || 20)

            render 'api/v1/accounts/patients/session_logs/index'
          end

          # GET /api/v1/accounts/:account_id/patients/:patient_id/session_logs/:id
          def show
            authorize @session_log
            render 'api/v1/accounts/patients/session_logs/show'
          end

          # POST /api/v1/accounts/:account_id/patients/:patient_id/session_logs
          def create
            authorize SessionLog
            result = ::Patients::SessionLogger.new(
              session_log_params.merge(patient_id: @patient.id),
              current_user,
              Current.account
            ).call

            if result.success?
              @session_log = result.session_log
              render 'api/v1/accounts/patients/session_logs/show', status: :created
            else
              render json: { error: result.error }, status: :unprocessable_entity
            end
          end

          # DELETE /api/v1/accounts/:account_id/patients/:patient_id/session_logs/:id
          def destroy
            authorize @session_log
            @session_log.soft_delete!
            head :no_content
          end

          private

          def set_session_log
            @session_log = @patient.session_logs.find_by!(id: params[:id], deleted_at: nil)
          rescue ActiveRecord::RecordNotFound
            render json: { error: 'Registro de sessão não encontrado' }, status: :not_found
          end

          def session_log_params
            params.require(:session_log).permit(
              :treatment_plan_id,
              :treatment_item_id,
              :appointment_id,
              :procedure_name,
              :performed_at,
              :duration_minutes,
              :complications,
              :result_observed,
              :post_procedure_guidance,
              :return_needed,
              :return_in_days,
              areas_treated: [:region, :tooth_number, :description, :side],
              products_used: [:product_id, :name, :quantity, :unit, :batch]
            )
          end
        end
      end
    end
  end
end
