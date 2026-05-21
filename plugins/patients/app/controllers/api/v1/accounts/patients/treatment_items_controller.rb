module Api
  module V1
    module Accounts
      module Patients
        class TreatmentItemsController < Api::V1::Accounts::Patients::BaseController
          before_action :set_treatment_plan
          before_action :set_treatment_item, only: [:show, :update, :destroy]

          # GET /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans/:treatment_plan_id/treatment_items
          def index
            authorize TreatmentItem
            @treatment_items = @treatment_plan.treatment_items
                                              .where(deleted_at: nil)
                                              .order(created_at: :asc)

            render 'api/v1/accounts/patients/treatment_items/index'
          end

          # GET /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans/:treatment_plan_id/treatment_items/:id
          def show
            authorize @treatment_item
            render 'api/v1/accounts/patients/treatment_items/show'
          end

          # POST /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans/:treatment_plan_id/treatment_items
          def create
            authorize TreatmentItem
            @treatment_item = @treatment_plan.treatment_items.build(treatment_item_params)
            @treatment_item.account = Current.account

            if @treatment_item.save
              PatientAuditLog.log!(
                account: Current.account,
                patient: @patient,
                actor: current_user,
                action: 'create',
                resource: @treatment_item,
                ip_address: request.remote_ip
              )
              log_clinical_override_if_present(@treatment_item, target_action: 'create')
              render 'api/v1/accounts/patients/treatment_items/show', status: :created
            else
              render json: { errors: @treatment_item.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans/:treatment_plan_id/treatment_items/:id
          def update
            authorize @treatment_item
            if @treatment_item.update(treatment_item_params)
              PatientAuditLog.log!(
                account: Current.account,
                patient: @patient,
                actor: current_user,
                action: 'update',
                resource: @treatment_item,
                ip_address: request.remote_ip
              )
              log_clinical_override_if_present(@treatment_item, target_action: 'update')
              render 'api/v1/accounts/patients/treatment_items/show'
            else
              render json: { errors: @treatment_item.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # DELETE /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans/:treatment_plan_id/treatment_items/:id
          def destroy
            authorize @treatment_item
            @treatment_item.soft_delete!
            PatientAuditLog.log!(
              account: Current.account,
              patient: @patient,
              actor: current_user,
              action: 'delete',
              resource: @treatment_item
            )
            head :no_content
          end

          private

          def set_treatment_plan
            @treatment_plan = @patient.treatment_plans.find_by!(id: params[:treatment_plan_id], deleted_at: nil)
          rescue ActiveRecord::RecordNotFound
            render_error('Plano de tratamento não encontrado', status: :not_found)
          end

          def set_treatment_item
            @treatment_item = @treatment_plan.treatment_items.find_by!(id: params[:id], deleted_at: nil)
          rescue ActiveRecord::RecordNotFound
            render_error('Item de tratamento não encontrado', status: :not_found)
          end

          def treatment_item_params
            permitted = params.require(:treatment_item).permit(
              :procedure_code,
              :procedure_name,
              :region,
              :tooth_number,
              :sessions_planned,
              :unit_price,
              :total_price,
              :discount_type,
              :discount_value,
              :priority,
              :clinical_justification,
              :notes,
              :agenda_service_id
            )
            nullify_missing_agenda_service(permitted)
          end

          # PR #6b: mesmo padrão de `agenda_events_controller` — protege contra
          # IDs inválidos (cross-tenant, soft-deletados, inexistentes). Em vez
          # de estourar `ActiveRecord::InvalidForeignKey`, nullifica o campo;
          # o callback do model resolve via `procedure_name` se houver.
          def nullify_missing_agenda_service(safe_params)
            sid = safe_params[:agenda_service_id]
            return safe_params if sid.blank?

            exists = Current.account.agenda_services.kept.where(id: sid).exists?
            exists ? safe_params : safe_params.merge(agenda_service_id: nil)
          end

          # Roadmap #16.1: quando o guard clínico do frontend detecta conflito
          # com a anamnese e o clínico opta por seguir mesmo assim, o motivo
          # vem em `clinical_override_reason` (fora dos strong params).
          # Persistido em PatientAuditLog com action `clinical_override` para
          # rastreabilidade compliance — não polui o TreatmentItem.
          def log_clinical_override_if_present(resource, target_action:)
            reason = params.dig(:treatment_item, :clinical_override_reason).to_s.strip
            return if reason.blank?

            PatientAuditLog.log!(
              account: Current.account,
              patient: @patient,
              actor: current_user,
              action: 'clinical_override',
              resource: resource,
              changes: {
                clinical_override: {
                  reason: reason,
                  source: 'frontend_guard',
                  target_action: target_action
                }
              },
              ip_address: request.remote_ip
            )
          end
        end
      end
    end
  end
end
