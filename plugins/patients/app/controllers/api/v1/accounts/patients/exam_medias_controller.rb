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
          # Soft delete — nunca apaga fisicamente
          def destroy
            authorize @exam
            @exam.soft_delete!
            PatientAuditLog.log!(
              account: Current.account, patient: @patient, action: 'delete',
              actor: current_user, resource: @exam, ip_address: request.remote_ip
            )
            render json: { message: 'Arquivo removido com sucesso' }
          end

          # GET /api/v1/accounts/:account_id/patients/:patient_id/exams/compare
          # Retorna par de URLs assinadas para slider before/after
          # Params: ?left_id=X&right_id=Y
          def compare
            authorize ExamMedia, :show?
            left  = @patient.exam_medias.active.find(params[:left_id])
            right = @patient.exam_medias.active.find(params[:right_id])

            render json: {
              left: {
                id: left.id,
                file_name: left.file_name,
                category: left.category,
                description: left.description,
                url: left.signed_url,
                created_at: left.created_at
              },
              right: {
                id: right.id,
                file_name: right.file_name,
                category: right.category,
                description: right.description,
                url: right.signed_url,
                created_at: right.created_at
              }
            }
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
              :file,
              tags: []
            )
          rescue ActionController::ParameterMissing
            params.permit(
              :category,
              :description,
              :session_log_id,
              :appointment_id,
              tags: []
            )
          end

          def exam_update_params
            params.permit(:category, :description, tags: [])
          end
        end
      end
    end
  end
end
