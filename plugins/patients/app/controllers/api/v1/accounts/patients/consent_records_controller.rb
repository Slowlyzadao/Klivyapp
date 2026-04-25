module Api
  module V1
    module Accounts
      module Patients
        class ConsentRecordsController < Api::V1::Accounts::BaseController
          before_action :set_patient
          before_action :set_consent_record, only: [:show, :sign, :send_remote, :revoke]

          # GET /api/v1/accounts/:account_id/patients/:patient_id/consents
          def index
            authorize ConsentRecord
            @consents = @patient.consent_records.active
                                .includes(:created_by)
                                .order(created_at: :desc)
            render :index
          end

          # GET /api/v1/accounts/:account_id/patients/:patient_id/consents/pending
          # Retorna apenas os pendentes de hoje (ou os que estiverem abertos)
          def pending
            authorize ConsentRecord, :index?
            @consents = @patient.consent_records.active.pending
                                .includes(:created_by)
                                .order(created_at: :desc)
            render :pending
          end

          # GET /api/v1/accounts/:account_id/patients/:patient_id/consents/:id
          def show
            authorize @consent
            render :show
          end

          # POST /api/v1/accounts/:account_id/patients/:patient_id/consents
          def create
            authorize ConsentRecord
            @consent = ConsentRecord.new(consent_params)
            @consent.patient    = @patient
            @consent.account    = Current.account
            @consent.created_by = current_user
            @consent.status     = 'pendente'

            if @consent.save
              PatientAuditLog.log!(
                account: Current.account, patient: @patient, action: 'create',
                actor: current_user, resource: @consent, ip_address: request.remote_ip
              )
              render :show, status: :created
            else
              render json: { errors: @consent.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # POST /api/v1/accounts/:account_id/patients/:patient_id/consents/:id/sign
          # Registra assinatura (modo: local_tablet ou remote_link)
          def sign
            authorize @consent
            result = ::Patients::ConsentSigner.call(
              consent: @consent,
              mode: params[:mode] || 'local_tablet',
              signature_blob: params[:signature],
              ip_address: request.remote_ip,
              device_info: params[:device_info] || request.user_agent,
              actor: current_user
            )

            if result.success?
              @consent = result.consent
              PatientAuditLog.log!(
                account: Current.account, patient: @patient, action: 'sign',
                actor: current_user, resource: @consent, ip_address: request.remote_ip
              )
              render :show
            else
              render json: { error: result.error }, status: :unprocessable_entity
            end
          end

          # POST /api/v1/accounts/:account_id/patients/:patient_id/consents/:id/send_remote
          # Marca o consentimento para assinatura remota e gera token
          def send_remote
            authorize @consent, :update?
            @consent.send_remote_link!

            # Aqui no futuro poderia disparar o NotificationDispatcher para mandar zap
            render json: {
              message: 'Link de assinatura remota gerado com sucesso',
              remote_token: @consent.remote_token,
              expires_at: @consent.remote_link_expires_at
            }
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/consents/:id/revoke
          def revoke
            authorize @consent
            @consent.revoke!
            PatientAuditLog.log!(
              account: Current.account, patient: @patient, action: 'delete',
              actor: current_user, resource: @consent, ip_address: request.remote_ip
            )
            render :show
          rescue StandardError => e
            render json: { error: e.message }, status: :unprocessable_entity
          end

          private

          def set_patient
            @patient = Current.account.patients.find(params[:patient_id])
          rescue ActiveRecord::RecordNotFound
            render json: { error: 'Paciente não encontrado' }, status: :not_found
          end

          def set_consent_record
            @consent = @patient.consent_records.active.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render json: { error: 'Consentimento não encontrado' }, status: :not_found
          end

          def consent_params
            params.permit(
              :title,
              :document_type,
              :body,
              :observations,
              :form_template_id,
              :expires_after_days
            )
          end
        end
      end
    end
  end
end
