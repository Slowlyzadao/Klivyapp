module Api
  module V1
    module Accounts
      module Patients
        class ExamMediasController < Api::V1::Accounts::BaseController
          before_action :set_patient
          before_action :set_exam_media, only: [:show, :update, :destroy]

          # GET /api/v1/accounts/:account_id/patients/:patient_id/exams
          # Suporta filtros: ?category=rx&page=1&per_page=20
          def index
            authorize ExamMedia
            @exams = @patient.exam_medias.active
            @exams = @exams.by_category(params[:category]) if params[:category].present?
            @exams = @exams.order(created_at: :desc)
                           .page(params[:page])
                           .per(params[:per_page] || 20)
            render :index
          end

          # GET /api/v1/accounts/:account_id/patients/:patient_id/exams/:id
          def show
            authorize @exam
            render :show
          end

          # POST /api/v1/accounts/:account_id/patients/:patient_id/exams
          # Multipart/form-data — campo "file" + metadados
          def create
            authorize ExamMedia
            @exam = ExamMedia.new(exam_params)
            @exam.patient     = @patient
            @exam.account     = Current.account
            @exam.uploaded_by = current_user
            @exam.category  ||= 'outro'

            file_param = params[:file] || params.dig(:exam_media, :file)
            @exam.file.attach(file_param) if file_param.present?

            if @exam.save
              ::Patients::PatientTimelineEventJob.perform_later(
                patient_id: @patient.id,
                event_type: 'exam_uploaded',
                label: "Exame/Imagem enviado: #{@exam.file_name || @exam.category}",
                actor_id: current_user.id,
                actor: current_user.name,
                reference_id: @exam.id,
                reference_type: 'ExamMedia',
                metadata: { category: @exam.category }
              )

              PatientAuditLog.log!(
                account: Current.account, patient: @patient, action: 'create',
                actor: current_user, resource: @exam, ip_address: request.remote_ip
              )

              render :show, status: :created
            else
              render json: { errors: @exam.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/exams/:id
          # Só atualiza metadados (categoria, descrição) — não troca o arquivo
          def update
            authorize @exam
            if @exam.update(exam_update_params)
              PatientAuditLog.log!(
                account: Current.account, patient: @patient, action: 'update',
                actor: current_user, resource: @exam, ip_address: request.remote_ip
              )
              render :show
            else
              render json: { errors: @exam.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # DELETE /api/v1/accounts/:account_id/patients/:patient_id/exams/:id
          # Soft delete (purge físico em 30 dias via ExamMediaPurgeJob).
          # Recusa se o arquivo estiver bloqueado — a verificação client-side
          # de `media.locked` é apenas UX; a integridade real é aqui.
          def destroy
            authorize @exam

            if @exam.locked?
              render json: {
                errors: ['Arquivo bloqueado. Desbloqueie antes de excluir.']
              }, status: :unprocessable_entity
              return
            end

            @exam.soft_delete!
            PatientAuditLog.log!(
              account: Current.account, patient: @patient, action: 'delete',
              actor: current_user, resource: @exam, ip_address: request.remote_ip
            )
            render json: { message: 'Arquivo removido com sucesso' }
          end

          # GET /api/v1/accounts/:account_id/patients/:patient_id/exams/compare
          # Retorna par de URLs assinadas para slider before/after.
          # Params: ?left_id=X&right_id=Y
          def compare
            authorize ExamMedia, :show?
            @left  = @patient.exam_medias.active.find(params[:left_id])
            @right = @patient.exam_medias.active.find(params[:right_id])
            render :compare
          rescue ActiveRecord::RecordNotFound
            render json: { error: 'Uma ou mais imagens não foram encontradas' }, status: :not_found
          end

          private

          def set_patient
            @patient = Current.account.patients.find(params[:patient_id])
          rescue ActiveRecord::RecordNotFound
            render json: { error: 'Paciente não encontrado' }, status: :not_found
          end

          def set_exam_media
            @exam = @patient.exam_medias.active.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render json: { error: 'Arquivo não encontrado' }, status: :not_found
          end

          def exam_params
            params.require(:exam_media).permit(
              :category,
              :description,
              :session_log_id,
              :appointment_id,
              :exam_folder_id,
              :file,
              tags: []
            )
          rescue ActionController::ParameterMissing
            params.permit(
              :category,
              :description,
              :session_log_id,
              :appointment_id,
              :exam_folder_id,
              tags: []
            )
          end

          # PATCH metadata: aceita renomear, mover entre pastas e (un)lock.
          # Não troca o blob — para isso, faça delete + new upload.
          def exam_update_params
            permitted = if params[:exam_media].present?
                          params.require(:exam_media).permit(
                            :category, :description, :file_name, :exam_folder_id, :locked, tags: []
                          )
                        else
                          params.permit(:category, :description, :file_name, :exam_folder_id, :locked, tags: [])
                        end

            permitted[:exam_folder_id] = normalize_folder_id(permitted[:exam_folder_id]) if permitted.key?(:exam_folder_id)
            permitted
          end

          # Garante que a pasta-alvo pertence ao mesmo paciente (defesa cross-tenant).
          # Aceita 'root', null e string vazia como "sem pasta".
          def normalize_folder_id(value)
            return nil if value.blank? || value.to_s == 'root'

            @patient.exam_folders.where(id: value).pick(:id)
          end
        end
      end
    end
  end
end
