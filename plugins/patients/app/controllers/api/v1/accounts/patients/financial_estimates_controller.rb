module Api
  module V1
    module Accounts
      module Patients
        class FinancialEstimatesController < Api::V1::Accounts::BaseController
          before_action :set_patient
          before_action :set_estimate, only: [:show, :update, :destroy, :approve, :cancel]

          # GET /api/v1/accounts/:account_id/patients/:patient_id/financial_estimates
          def index
            authorize FinancialEstimate
            @estimates = @patient.financial_estimates.active.order(created_at: :desc)
            render :index
          end

          # GET /api/v1/accounts/:account_id/patients/:patient_id/financial_estimates/:id
          def show
            authorize @estimate
            render :show
          end

          # POST /api/v1/accounts/:account_id/patients/:patient_id/financial_estimates
          def create
            authorize FinancialEstimate
            @estimate = FinancialEstimate.new(estimate_params)
            @estimate.account = Current.account
            @estimate.patient = @patient
            @estimate.generated_by = current_user

            if @estimate.save
              PatientAuditLog.log!(
                account: Current.account, patient: @patient, action: 'create',
                actor: current_user, resource: @estimate, ip_address: request.remote_ip
              )
              render :show, status: :created
            else
              render json: { errors: @estimate.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/financial_estimates/:id
          def update
            authorize @estimate
            return render json: { error: 'Orçamento aprovado não pode ser editado' }, status: :forbidden if @estimate.status_aprovado?

            if @estimate.update(estimate_params)
              PatientAuditLog.log!(
                account: Current.account, patient: @patient, action: 'update',
                actor: current_user, resource: @estimate, ip_address: request.remote_ip
              )
              render :show
            else
              render json: { errors: @estimate.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # DELETE /api/v1/accounts/:account_id/patients/:patient_id/financial_estimates/:id
          def destroy
            authorize @estimate
            if @estimate.status_aprovado?
              return render json: { error: 'Orçamento aprovado não pode ser cancelado por esta rota. Use PATCH /cancel.' }, status: :forbidden
            end

            @estimate.soft_delete!
            PatientAuditLog.log!(
              account: Current.account, patient: @patient, action: 'delete',
              actor: current_user, resource: @estimate, ip_address: request.remote_ip
            )
            render json: { message: 'Orçamento removido com sucesso' }
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/financial_estimates/:id/approve
          def approve
            authorize @estimate
            unless @estimate.status_rascunho? || @estimate.status_enviado?
              return render json: { error: "Orçamento com status '#{@estimate.status}' não pode ser aprovado" }, status: :unprocessable_entity
            end

            @estimate.update!(status: 'aprovado', approved_at: Time.current)
            @estimate.generate_transactions!(current_user)
            PatientAuditLog.log!(
              account: Current.account, patient: @patient, action: 'approve',
              actor: current_user, resource: @estimate, ip_address: request.remote_ip
            )
            render :show
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/financial_estimates/:id/cancel
          def cancel
            authorize @estimate
            return render json: { error: 'Orçamento já cancelado' }, status: :unprocessable_entity if @estimate.status_cancelado?

            @estimate.update!(status: 'cancelado')
            render :show
          end

          private

          def set_patient
            @patient = Current.account.patients.find(params[:patient_id])
          rescue ActiveRecord::RecordNotFound
            render json: { error: 'Paciente não encontrado' }, status: :not_found
          end

          def set_estimate
            @estimate = @patient.financial_estimates.active.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render json: { error: 'Orçamento não encontrado' }, status: :not_found
          end

          def estimate_params
            params.require(:financial_estimate).permit(
              :status,
              :subtotal,
              :discount_type,
              :discount_value,
              :installments_count,
              :payment_method,
              :notes,
              :valid_until
            )
          end
        end
      end
    end
  end
end
