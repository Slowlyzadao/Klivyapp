module Api
  module V1
    module Accounts
      module Patients
        class SessionLogsController < Api::V1::Accounts::Patients::BaseController
          before_action :set_session_log,
                        only: [:show, :update, :destroy, :sign, :mark_erratum,
                               :sign_patient_locally, :send_patient_remote_signature_link]

          # GET /api/v1/accounts/:account_id/patients/:patient_id/session_logs
          def index
            authorize SessionLog
            # Eager load de avatar_attachment cobre acesso futuro a
            # `professional.avatar_url` no jbuilder. patient_signature_image
            # também é preloaded — usado em `patient_signature_image_url` que
            # gera token via SecureBlobTokenService.
            @session_logs = @patient.session_logs
                                    .where(deleted_at: nil)
                                    .includes(
                                      :treatment_plan,
                                      :treatment_item,
                                      { professional: { avatar_attachment: :blob } },
                                      { signed_by: { avatar_attachment: :blob } },
                                      { erratum_by: { avatar_attachment: :blob } },
                                      { patient_signature_image_attachment: :blob }
                                    )
                                    .order(performed_at: :desc)
                                    .page(params[:page]).per(params[:per_page] || 20)

            render 'api/v1/accounts/patients/session_logs/index'
          end

          # GET .../session_logs/:id
          def show
            authorize @session_log
            render 'api/v1/accounts/patients/session_logs/show'
          end

          # POST .../session_logs
          def create
            authorize SessionLog
            result = ::Patients::SessionLogger.new(
              session_log_params.merge(patient_id: @patient.id),
              current_user,
              Current.account
            ).call

            if result.success?
              @session_log = result.session_log
              log_clinical_override_if_present(@session_log, target_action: 'create')
              render 'api/v1/accounts/patients/session_logs/show', status: :created
            else
              render_error(result.error, status: :unprocessable_entity)
            end
          end

          # PATCH .../session_logs/:id
          def update
            authorize @session_log

            unless @session_log.editable_by?(current_user)
              render_error('Sessão assinada ou fora da janela de edição.', status: :forbidden)
              return
            end

            if @session_log.update(session_log_params)
              PatientAuditLog.log!(
                account: Current.account,
                patient: @patient,
                actor: current_user,
                action: 'update',
                resource: @session_log,
                ip_address: request.remote_ip
              )
              log_clinical_override_if_present(@session_log, target_action: 'update')
              render 'api/v1/accounts/patients/session_logs/show'
            else
              render_error(@session_log.errors.full_messages, status: :unprocessable_entity)
            end
          end

          # DELETE .../session_logs/:id
          def destroy
            authorize @session_log

            begin
              @session_log.soft_delete!
              PatientAuditLog.log!(
                account: Current.account,
                patient: @patient,
                actor: current_user,
                action: 'delete',
                resource: @session_log,
                ip_address: request.remote_ip
              )
              head :no_content
            rescue RuntimeError => e
              render_error(e.message, status: :forbidden)
            end
          end

          # PATCH .../session_logs/:id/sign — profissional assina
          def sign
            authorize @session_log

            result = ::Patients::SessionLogFinalizer.call(session_log: @session_log, actor: current_user)

            if result.success?
              render 'api/v1/accounts/patients/session_logs/show'
            else
              render_error(result.error, status: :forbidden)
            end
          end

          # PATCH .../session_logs/:id/mark_erratum
          def mark_erratum
            authorize @session_log

            reason = params[:reason].to_s.strip
            if reason.blank?
              render_error('Justificativa da errata é obrigatória.', status: :unprocessable_entity)
              return
            end

            begin
              @session_log.mark_as_erratum!(actor: current_user, reason: reason)
              PatientAuditLog.log!(
                account: Current.account,
                patient: @patient,
                actor: current_user,
                action: 'erratum',
                resource: @session_log,
                changes: { erratum_reason: reason },
                ip_address: request.remote_ip
              )
              render 'api/v1/accounts/patients/session_logs/show'
            rescue RuntimeError => e
              render_error(e.message, status: :unprocessable_entity)
            end
          end

          # POST .../session_logs/:id/sign_patient_locally
          # Body: { signature: 'data:image/webp;base64,...', device_info? }
          def sign_patient_locally
            authorize @session_log

            result = ::Patients::SessionLogPatientSigner.call(
              session_log: @session_log,
              mode: 'local_tablet',
              signature_blob: params[:signature],
              ip_address: request.remote_ip,
              device_info: params[:device_info] || request.user_agent,
              actor: current_user
            )

            if result.success?
              @session_log = result.session_log
              PatientAuditLog.log!(
                account: Current.account,
                patient: @patient,
                actor: current_user,
                action: 'patient_sign_local',
                resource: @session_log,
                ip_address: request.remote_ip
              )
              render 'api/v1/accounts/patients/session_logs/show'
            else
              render_error(result.error, status: :unprocessable_entity)
            end
          end

          # POST .../session_logs/:id/send_patient_remote_signature_link
          def send_patient_remote_signature_link
            authorize @session_log

            @session_log.send_patient_remote_signature_link!
            PatientAuditLog.log!(
              account: Current.account,
              patient: @patient,
              actor: current_user,
              action: 'patient_signature_link_sent',
              resource: @session_log,
              ip_address: request.remote_ip
            )

            # Disparo via WhatsApp/SMS é feito em PR follow-up — aqui só geramos o token.
            render json: {
              message: 'Link de assinatura remota gerado com sucesso',
              remote_token: @session_log.patient_signature_remote_token,
              expires_at: @session_log.patient_signature_remote_link_expires_at
            }
          end

          private

          def set_session_log
            @session_log = @patient.session_logs.find_by!(id: params[:id], deleted_at: nil)
          rescue ActiveRecord::RecordNotFound
            render_error('Registro de sessão não encontrado', status: :not_found)
          end

          def session_log_params
            params.require(:session_log).permit(
              :treatment_plan_id,
              :treatment_item_id,
              :appointment_id,
              :form_template_id,
              :procedure_name,
              :performed_at,
              :duration_minutes,
              :complications,
              :result_observed,
              :post_procedure_guidance,
              :return_needed,
              :return_in_days,
              :complaint_of_day,
              :assessment,
              :next_consultation_details,
              :observation,
              :status,
              :professional_id,
              :lock_version,
              areas_treated: [:region, :tooth_number, :description, :side],
              products_used: [:product_id, :name, :quantity, :unit, :batch, :expires_at]
            )
          end

          def log_clinical_override_if_present(resource, target_action:)
            reason = params.dig(:session_log, :clinical_override_reason).to_s.strip
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
