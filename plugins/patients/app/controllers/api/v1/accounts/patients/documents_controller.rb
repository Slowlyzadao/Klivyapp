module Api
  module V1
    module Accounts
      module Patients
        class DocumentsController < Api::V1::Accounts::BaseController
          include BeclinicErrorResponse

          before_action :set_patient
          before_action :set_document, only: [:show, :destroy, :download, :send_whatsapp, :status]

          # GET /api/v1/accounts/:account_id/patients/:patient_id/documents
          # Filtros: ?document_type=receita&status=gerado&page=1
          def index
            authorize Document
            @documents = @patient.documents.active
            @documents = @documents.by_type(params[:document_type]) if params[:document_type].present?
            @documents = @documents.by_status(params[:status]) if params[:status].present?
            @documents = @documents.order(created_at: :desc)
                                   .page(params[:page])
                                   .per(params[:per_page] || 20)
            render :index
          end

          # GET /api/v1/accounts/:account_id/patients/:patient_id/documents/:id
          def show
            authorize @document
            render :show
          end

          # POST /api/v1/accounts/:account_id/patients/:patient_id/documents/generate
          # Gera PDF server-side a partir de um template Prawn
          # Body: { document_type: "atestado", variables: { ... }, title: "...", form_template_id: 1 }
          def generate
            authorize Document
            result = ::Patients::PdfGenerator.call(
              patient: @patient,
              document_type: params[:document_type],
              variables: (params[:variables]&.to_unsafe_h || {}).symbolize_keys,
              generated_by: current_user,
              title: params[:title],
              form_template_id: params[:form_template_id],
              # Fase 3 do projeto document-editor: se passar template_id, o
              # Patients::PdfGenerator delega pra DocumentTemplates::PdfGenerator
              # (Grover/Chromium). Sem template_id, Prawn legado continua.
              document_template_id: params[:document_template_id]
            )

            if result.success?
              @document = result.document

              ::Patients::PatientTimelineEventJob.perform_later(
                patient_id: @patient.id,
                event_type: 'document_generated',
                label: "Documento gerado: #{@document.title}",
                actor_id: current_user.id,
                actor: current_user.name,
                reference_id: @document.id,
                reference_type: 'Document',
                metadata: { document_type: @document.document_type }
              )

              PatientAuditLog.log!(
                account: Current.account, patient: @patient, action: 'create',
                actor: current_user, resource: @document, ip_address: request.remote_ip
              )

              render :show, status: :created
            else
              render_error(result.error, status: :unprocessable_entity)
            end
          end

          # POST /api/v1/accounts/:account_id/patients/:patient_id/documents/attach
          # Anexa PDF externo — multipart/form-data
          def attach
            authorize Document
            @document = Document.new(
              patient: @patient,
              account: Current.account,
              generated_by: current_user,
              document_type: params[:document_type] || 'outro',
              title: params[:title] || 'Documento Anexado',
              is_generated: false,
              status: 'gerado'
            )

            return render_error('Arquivo é obrigatório', status: :unprocessable_entity) unless params[:file].present?

            @document.file.attach(params[:file])

            if @document.save
              PatientAuditLog.log!(
                account: Current.account, patient: @patient, action: 'create',
                actor: current_user, resource: @document, ip_address: request.remote_ip
              )
              render :show, status: :created
            else
              render json: { errors: @document.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # GET /api/v1/accounts/:account_id/patients/:patient_id/documents/:id/download
          # Retorna URL assinada para download/preview (15min de validade)
          def download
            authorize @document, :show?
            return render_error('Documento sem arquivo anexado', status: :not_found) unless @document.file.attached?

            signed_url = @document.signed_url(expires_in: 15.minutes, disposition: :inline)

            render json: {
              document_id: @document.id,
              title: @document.title,
              file_name: @document.file_name,
              url: signed_url,
              expires_in_seconds: 900,
              content_type: @document.mime_type || 'application/pdf'
            }
          end

          # POST /api/v1/accounts/:account_id/patients/:patient_id/documents/:id/send_whatsapp
          def send_whatsapp
            authorize @document, :update?
            result = ::Patients::DocumentWhatsappSender.call(
              document: @document,
              patient: @patient,
              actor: current_user
            )

            if result.success?
              render json: {
                message: 'Documento preparado para envio via WhatsApp',
                whatsapp_payload: result.whatsapp_payload
              }
            else
              render_error(result.error, status: :unprocessable_entity)
            end
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/documents/:id/status
          # Atualiza status do documento
          def status
            authorize @document, :update?
            allowed_statuses = Document::STATUSES
            new_status = params[:status]

            unless allowed_statuses.include?(new_status)
              return render json: {
                error: "Status inválido. Valores aceitos: #{allowed_statuses.join(', ')}"
              }, status: :unprocessable_entity
            end

            if @document.update(status: new_status)
              PatientAuditLog.log!(
                account: Current.account, patient: @patient, action: 'update',
                actor: current_user, resource: @document, ip_address: request.remote_ip,
                changes: { status: [nil, new_status] }
              )
              render :show
            else
              render json: { errors: @document.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # DELETE /api/v1/accounts/:account_id/patients/:patient_id/documents/:id
          def destroy
            authorize @document
            @document.soft_delete!
            PatientAuditLog.log!(
              account: Current.account, patient: @patient, action: 'delete',
              actor: current_user, resource: @document, ip_address: request.remote_ip
            )
            PatientTimelineEvent.record!(
              patient: @patient,
              account: Current.account,
              event_type: 'document_deleted',
              label: "Documento removido: #{@document.title.presence || @document.document_type}",
              actor: current_user,
              reference: @document
            )
            render json: { message: 'Documento removido com sucesso' }
          end

          private

          def set_patient
            @patient = Current.account.patients.find(params[:patient_id])
          rescue ActiveRecord::RecordNotFound
            render_error('Paciente não encontrado', status: :not_found)
          end

          def set_document
            @document = @patient.documents.active.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_error('Documento não encontrado', status: :not_found)
          end
        end
      end
    end
  end
end
