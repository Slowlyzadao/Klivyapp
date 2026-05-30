module Api
  module V1
    module Accounts
      module Patients
        class ConsentRecordsController < Api::V1::Accounts::BaseController
          include BeclinicErrorResponse

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
          #
          # Dois caminhos:
          #   - `document_template_id` presente → gera via plugin
          #     document_templates (Renderer + Grover → rendered_html).
          #   - Sem template_id → caminho legado (body em texto puro,
          #     preenchido pelo frontend a partir de consentTemplates.js).
          def create
            authorize ConsentRecord

            return create_from_template if params[:document_template_id].present?

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

          # Caminho novo via DocumentTemplate. Espera `document_template_id`
          # com escopo da account corrente. O builder valida que o template
          # é de consentimento e popula rendered_html + integrity_hash.
          def create_from_template
            template = ::DocumentTemplate.for_account(Current.account)
                                         .find(params[:document_template_id])

            result = ::DocumentTemplates::ConsentRecordBuilder.call(
              template: template,
              patient: @patient,
              professional: current_user,
              clinic: Current.account,
              title: params[:title].presence || template.name,
              observations: params[:observations],
              expires_after_days: params[:expires_after_days]
            )

            if result.success?
              @consent = result.consent
              PatientAuditLog.log!(
                account: Current.account, patient: @patient, action: 'create',
                actor: current_user, resource: @consent, ip_address: request.remote_ip
              )
              render :show, status: :created
            else
              render_error(result.error, status: :unprocessable_entity)
            end
          rescue ActiveRecord::RecordNotFound
            render_error('Template não encontrado ou sem acesso', status: :not_found)
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
              render_error(result.error, status: :unprocessable_entity)
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
            PatientTimelineEvent.record!(
              patient: @patient,
              account: Current.account,
              event_type: 'consent_revoked',
              label: "Consentimento revogado: #{@consent.title.presence || @consent.consent_type}",
              actor: current_user,
              reference: @consent
            )
            render :show
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_entity)
          end

          private

          # Usa `policy_scope` (não `Current.account.patients.find` cru) para que
          # o lookup do paciente respeite o `scope=own` do `PatientPolicy::Scope`.
          # Sem isso (auditoria A-6), profissional com `patients` `scope=own` +
          # `view_consents` conseguia listar consents de qualquer paciente da
          # conta passando `patient_id` arbitrário na URL — vazamento de PHI
          # (LGPD/HIPAA).
          def set_patient
            @patient = policy_scope(Current.account.patients).find(params[:patient_id])
          rescue ActiveRecord::RecordNotFound
            render_error('Paciente não encontrado', status: :not_found)
          end

          def set_consent_record
            @consent = @patient.consent_records.active.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_error('Consentimento não encontrado', status: :not_found)
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
