module Api
  module V1
    module Accounts
      module Patients
        class AnamnesesController < Api::V1::Accounts::BaseController
          before_action :set_patient
          before_action :set_anamnesis, only: [:show, :update, :finalize, :destroy]

          # GET /api/v1/accounts/:account_id/patients/:patient_id/anamneses
          def index
            @anamneses = policy_scope(@patient.anamneses.active.order(version_number: :desc))
            render 'api/v1/accounts/patients/anamneses/index'
          end

          # GET /api/v1/accounts/:account_id/patients/:patient_id/anamneses/:id
          def show
            authorize @anamnesis
            render 'api/v1/accounts/patients/anamneses/show'
          end

          # POST /api/v1/accounts/:account_id/patients/:patient_id/anamneses
          def create
            @anamnesis = @patient.anamneses.new(anamnesis_params)
            @anamnesis.account    = current_account
            @anamnesis.professional = current_user
            authorize @anamnesis

            if @anamnesis.save
              PatientAuditLog.log!(
                account: current_account,
                patient: @patient,
                actor: current_user,
                action: 'create',
                resource: @anamnesis
              )
              render 'api/v1/accounts/patients/anamneses/show', status: :created
            else
              render json: { error: @anamnesis.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/anamneses/:id
          def update
            authorize @anamnesis

            if @anamnesis.status_finalized?
              render json: { error: 'Anamnese finalizada não pode ser editada.' }, status: :forbidden
              return
            end

            if @anamnesis.update(anamnesis_params)
              PatientAuditLog.log!(
                account: current_account,
                patient: @patient,
                actor: current_user,
                action: 'update',
                resource: @anamnesis
              )
              render 'api/v1/accounts/patients/anamneses/show'
            else
              render json: { error: @anamnesis.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/anamneses/:id/finalize
          def finalize
            authorize @anamnesis, :update?

            result = ::Patients::AnamnesisFinalizerService.call(
              anamnesis: @anamnesis,
              actor: current_user
            )

            if result.success?
              render json: {
                success: true,
                anamnesis: anamnesis_json(@anamnesis),
                critical_alerts_created: result.critical_alerts_created.count
              }
            else
              render json: { error: result.error }, status: :unprocessable_entity
            end
          end

          # DELETE /api/v1/accounts/:account_id/patients/:patient_id/anamneses/:id
          def destroy
            authorize @anamnesis

            if @anamnesis.status_finalized?
              render json: { error: 'Anamnese finalizada não pode ser excluída.' }, status: :forbidden
              return
            end

            @anamnesis.soft_delete!
            PatientAuditLog.log!(
              account: current_account,
              patient: @patient,
              actor: current_user,
              action: 'delete',
              resource: @anamnesis
            )
            head :no_content
          end

          private

          def set_patient
            @patient = current_account.patients.find(params[:patient_id])
          rescue ActiveRecord::RecordNotFound
            render json: { error: 'Paciente não encontrado.' }, status: :not_found
          end

          def set_anamnesis
            @anamnesis = @patient.anamneses.active.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render json: { error: 'Anamnese não encontrada.' }, status: :not_found
          end

          def anamnesis_params
            params.require(:anamnesis).permit(
              :form_template_id, :specialty, :chief_complaint,
              :surgical_history, :family_history, :additional_notes,
              medical_history: {},
              allergies: [:name, :substance, :severity, :reaction, :description],
              current_medications: [:name, :dosage, :frequency, :alert, :interaction_risk],
              contraindications: [:name, :description, :details],
              pregnancy: {},
              relevant_habits: {}
            )
          end

          def anamnesis_json(anamnesis)
            {
              id: anamnesis.id,
              status: anamnesis.status,
              version_number: anamnesis.version_number,
              finalized_at: anamnesis.finalized_at&.iso8601
            }
          end
        end
      end
    end
  end
end
