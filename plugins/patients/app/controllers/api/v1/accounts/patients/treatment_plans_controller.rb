module Api
  module V1
    module Accounts
      module Patients
        class TreatmentPlansController < Api::V1::Accounts::Patients::BaseController
          before_action :set_treatment_plan, only: [:show, :update, :destroy, :approve, :cancel]

          # GET /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans
          def index
            authorize TreatmentPlan
            @treatment_plans = @patient.treatment_plans
                                       .where(deleted_at: nil)
                                       .includes(:treatment_items, :professional)
                                       .order(created_at: :desc)

            render 'api/v1/accounts/patients/treatment_plans/index'
          end

          # GET /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans/:id
          def show
            authorize @treatment_plan
            render 'api/v1/accounts/patients/treatment_plans/show'
          end

          # POST /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans
          def create
            authorize TreatmentPlan
            @treatment_plan = @patient.treatment_plans.build(treatment_plan_params)
            @treatment_plan.account = Current.account
            @treatment_plan.professional = current_user

            if @treatment_plan.save
              PatientAuditLog.log!(
                account: Current.account,
                patient: @patient,
                actor: current_user,
                action: 'create',
                resource: @treatment_plan
              )
              render 'api/v1/accounts/patients/treatment_plans/show', status: :created
            else
              render json: { errors: @treatment_plan.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans/:id
          def update
            authorize @treatment_plan
            if @treatment_plan.update(treatment_plan_params)
              PatientAuditLog.log!(
                account: Current.account,
                patient: @patient,
                actor: current_user,
                action: 'update',
                resource: @treatment_plan
              )
              render 'api/v1/accounts/patients/treatment_plans/show'
            else
              render json: { errors: @treatment_plan.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # DELETE /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans/:id
          def destroy
            authorize @treatment_plan
            @treatment_plan.soft_delete!
            PatientAuditLog.log!(
              account: Current.account,
              patient: @patient,
              actor: current_user,
              action: 'delete',
              resource: @treatment_plan
            )
            head :no_content
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans/:id/approve
          def approve
            authorize @treatment_plan

            result = ::Patients::TreatmentPlanApprover.new(
              @treatment_plan,
              approved_by: current_user,
              item_ids: params[:item_ids]
            ).call

            if result.success?
              @treatment_plan = result.plan
              PatientAuditLog.log!(
                account: Current.account,
                patient: @patient,
                actor: current_user,
                action: 'approve',
                resource: @treatment_plan
              )
              render 'api/v1/accounts/patients/treatment_plans/show'
            else
              render json: { error: result.error }, status: :unprocessable_entity
            end
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans/:id/cancel
          def cancel
            authorize @treatment_plan

            if @treatment_plan.status_concluido?
              return render json: { error: I18n.t('errors.treatment_plan.cannot_cancel_concluded') },
                            status: :unprocessable_entity
            end

            if @treatment_plan.update(status: 'cancelado', cancellation_reason: params[:cancellation_reason])
              PatientAuditLog.log!(
                account: Current.account,
                patient: @patient,
                actor: current_user,
                action: 'update',
                resource: @treatment_plan,
                changes: { status: %w[aprovado cancelado] }
              )
              render 'api/v1/accounts/patients/treatment_plans/show'
            else
              render json: { errors: @treatment_plan.errors.full_messages }, status: :unprocessable_entity
            end
          end

          private

          def set_treatment_plan
            @treatment_plan = @patient.treatment_plans.find_by!(id: params[:id], deleted_at: nil)
          rescue ActiveRecord::RecordNotFound
            render json: { error: 'Plano de tratamento não encontrado' }, status: :not_found
          end

          def treatment_plan_params
            params.require(:treatment_plan).permit(
              :title,
              :description,
              :estimated_duration
            )
          end
        end
      end
    end
  end
end
