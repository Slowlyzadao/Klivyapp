# CRUD de pastas de templates.
#
# Pastas existem só pra organizar visualmente templates da clínica.
# Templates Klivy globais NÃO ficam em pastas (vivem numa seção dedicada
# "Biblioteca Klivy" no UI).
class Api::V1::Accounts::DocumentTemplateFoldersController < Api::V1::Accounts::BaseController
  before_action :load_folder, only: [:show, :update, :destroy]

  # GET .../document_template_folders
  def index
    authorize DocumentTemplateFolder, :index?
    folders = policy_scope(DocumentTemplateFolder).roots
    render json: { data: folders.map { |f| DocumentTemplateFolderSerializer.new(f).as_json } }
  end

  def show
    authorize @folder
    render json: { data: DocumentTemplateFolderSerializer.new(@folder).as_json }
  end

  def create
    @folder = DocumentTemplateFolder.new(folder_params.merge(account: Current.account))
    authorize @folder
    if @folder.save
      render json: { data: DocumentTemplateFolderSerializer.new(@folder).as_json }, status: :created
    else
      render json: { errors: @folder.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    authorize @folder
    if @folder.update(folder_params)
      render json: { data: DocumentTemplateFolderSerializer.new(@folder).as_json }
    else
      render json: { errors: @folder.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @folder
    @folder.destroy
    head :no_content
  rescue ActiveRecord::DeleteRestrictionError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def load_folder
    @folder = DocumentTemplateFolder.where(account: Current.account).find(params[:id])
  end

  def folder_params
    params.require(:document_template_folder).permit(:name, :parent_id, :position, :color, :icon)
  end
end
