module Api
  module V1
    module Accounts
      module Patients
        class ExamFoldersController < Api::V1::Accounts::BaseController
          include BeclinicErrorResponse

          before_action :set_patient
          before_action :set_folder, only: [:update, :destroy]
          before_action :ensure_view_exams!, only: [:index]
          before_action :ensure_manage_exams!, only: [:create, :update, :destroy, :reorder]

          # GET /api/v1/accounts/:account_id/patients/:patient_id/exam_folders
          def index
            @folders = @patient.exam_folders.ordered
            render :index
          end

          # POST /api/v1/accounts/:account_id/patients/:patient_id/exam_folders
          def create
            @folder = @patient.exam_folders.new(folder_params)
            @folder.account = Current.account
            @folder.position ||= next_position(@folder.parent_id)

            if @folder.save
              render :show, status: :created
            else
              render json: { errors: @folder.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/exam_folders/:id
          def update
            if @folder.update(folder_params)
              render :show
            else
              render json: { errors: @folder.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # DELETE /api/v1/accounts/:account_id/patients/:patient_id/exam_folders/:id
          # Move arquivos da pasta para a raiz e exclui (subpastas vão junto via dependent: :destroy).
          def destroy
            ActiveRecord::Base.transaction do
              # Move medias direto para raiz (não para a pasta-pai, alinhado com a UX atual).
              @folder.exam_medias.update_all(exam_folder_id: nil)
              @folder.children.find_each do |child|
                child.exam_medias.update_all(exam_folder_id: nil)
              end
              @folder.destroy!
            end

            head :no_content
          end

          # PUT /api/v1/accounts/:account_id/patients/:patient_id/exam_folders/reorder
          # Body: { items: [{ id, parent_id, position }, ...] }
          # Aplica todas as mudanças em uma transação. IDs não pertencentes ao paciente são ignorados.
          def reorder
            items = Array(params[:items])
            return head(:ok) if items.empty?

            ActiveRecord::Base.transaction do
              items.each do |item|
                folder = @patient.exam_folders.find_by(id: item[:id])
                next unless folder

                attrs = {}
                attrs[:position]  = item[:position].to_i if item.key?(:position)
                attrs[:parent_id] = normalize_parent_id(item[:parent_id]) if item.key?(:parent_id)

                folder.update!(attrs) if attrs.any?
              end
            end

            head :ok
          rescue ActiveRecord::RecordInvalid => e
            render json: { errors: [e.message] }, status: :unprocessable_entity
          end

          private

          def ensure_view_exams!
            return if Current.account_user&.administrator?
            return if Current.user.beclinic_can?(Current.account, :patients, :view_exams)

            render_error('Sem permissão para visualizar exames.', status: :forbidden)
          end

          def ensure_manage_exams!
            return if Current.account_user&.administrator?
            return if Current.user.beclinic_can?(Current.account, :patients, :manage_exams)

            render_error('Sem permissão para gerenciar exames.', status: :forbidden)
          end

          def set_patient
            @patient = Current.account.patients.find(params[:patient_id])
          rescue ActiveRecord::RecordNotFound
            render_error('Paciente não encontrado', status: :not_found)
          end

          def set_folder
            @folder = @patient.exam_folders.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_error('Pasta não encontrada', status: :not_found)
          end

          def folder_params
            params.require(:exam_folder).permit(:name, :color, :parent_id, :position)
          rescue ActionController::ParameterMissing
            params.permit(:name, :color, :parent_id, :position)
          end

          def next_position(parent_id)
            scope = @patient.exam_folders.where(parent_id: parent_id)
            (scope.maximum(:position) || -1) + 1
          end

          def normalize_parent_id(value)
            return nil if value.blank? || value == 'root'

            # Garante que o pai é do mesmo paciente — defesa em profundidade contra IDs cross-tenant.
            @patient.exam_folders.where(id: value).pick(:id)
          end
        end
      end
    end
  end
end
