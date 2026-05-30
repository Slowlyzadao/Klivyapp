# CRUD + ações especiais de DocumentTemplate.
#
# Endpoints:
#   GET    /api/v1/accounts/:id/document_templates
#   GET    /api/v1/accounts/:id/document_templates/variables   (catálogo)
#   GET    /api/v1/accounts/:id/document_templates/klivy_library
#   GET    /api/v1/accounts/:id/document_templates/:id
#   POST   /api/v1/accounts/:id/document_templates
#   PATCH  /api/v1/accounts/:id/document_templates/:id
#   DELETE /api/v1/accounts/:id/document_templates/:id         (soft → archived)
#   POST   /api/v1/accounts/:id/document_templates/:id/duplicate
#   POST   /api/v1/accounts/:id/document_templates/:id/clone_to_account
#   POST   /api/v1/accounts/:id/document_templates/:id/archive
#   POST   /api/v1/accounts/:id/document_templates/:id/unarchive
class Api::V1::Accounts::DocumentTemplatesController < Api::V1::Accounts::BaseController
  before_action :load_template,
                only: [:show, :update, :destroy, :duplicate, :clone_to_account, :archive, :unarchive]

  # GET .../document_templates
  # Params suportados:
  #   document_type — filtra por tipo (ex: 'atestado').
  #   folder_id     — filtra por pasta.
  #   include_archived — se 'true', inclui archived junto com active.
  #   family        — 'clinical' ou 'consent' (filtragem larga).
  def index
    authorize DocumentTemplate, :index?

    scope = policy_scope(DocumentTemplate).includes(:folder, :created_by_user)

    scope = filter_by_account(scope)
    scope = scope.where(document_type: params[:document_type]) if params[:document_type].present?
    scope = scope.where(folder_id: params[:folder_id])         if params[:folder_id].present?
    scope = filter_by_family(scope, params[:family])
    scope = filter_by_status(scope, params[:include_archived])

    render json: { data: scope.order(:name).map { |t| DocumentTemplateSerializer.new(t).as_json } }
  end

  # GET .../document_templates/variables
  # Retorna o catálogo de variáveis disponíveis pra inserção. Endpoint
  # público pra qualquer usuário da conta (read-only).
  def variables
    authorize DocumentTemplate, :variables?
    render json: { data: DocumentTemplates::Catalog.for_frontend }
  end

  # GET .../document_templates/klivy_library
  # Lista os templates Klivy globais (account_id NULL) que a clínica pode
  # clonar. Filtro opcional por document_type.
  def klivy_library
    authorize DocumentTemplate, :klivy_library?

    scope = DocumentTemplate.klivy.active
    scope = scope.where(document_type: params[:document_type]) if params[:document_type].present?
    scope = filter_by_family(scope, params[:family])

    render json: { data: scope.order(:document_type, :name).map { |t| DocumentTemplateSerializer.new(t).as_json } }
  end

  # GET .../document_templates/:id
  def show
    authorize @template
    render json: { data: DocumentTemplateSerializer.new(@template).as_json(include_content: true) }
  end

  # POST .../document_templates
  def create
    @template = DocumentTemplate.new(template_params)
    @template.account = Current.account
    @template.created_by_user = Current.user
    @template.source = 'clinic'

    authorize @template
    if @template.save
      render json: { data: DocumentTemplateSerializer.new(@template).as_json(include_content: true) },
             status: :created
    else
      render json: { errors: @template.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH .../document_templates/:id
  def update
    authorize @template
    if @template.update(template_params)
      render json: { data: DocumentTemplateSerializer.new(@template).as_json(include_content: true) }
    else
      render json: { errors: @template.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE .../document_templates/:id
  # Exclusão DEFINITIVA (hard delete). Só é bloqueada quando o template já
  # gerou Documents/ConsentRecords (FK restrict) — nesse caso o registro
  # precisa ser preservado por integridade, e o caminho é Arquivar.
  # O frontend traduz o code 'has_dependents' numa mensagem amigável.
  def destroy
    authorize @template
    if @template.destroy
      head :no_content
    else
      render json: { error: 'has_dependents' }, status: :unprocessable_entity
    end
  rescue ActiveRecord::DeleteRestrictionError, ActiveRecord::InvalidForeignKey
    render json: { error: 'has_dependents' }, status: :unprocessable_entity
  end

  # POST .../document_templates/:id/duplicate
  # Cria uma cópia do template (mesma account, novo registro, version=1).
  # Útil pra clínica iterar variações ("Contrato — versão promocional").
  def duplicate
    authorize @template, :duplicate?

    copy = @template.dup
    copy.assign_attributes(
      name: "#{@template.name} (cópia)",
      version: 1,
      status: 'active',
      account: Current.account,
      created_by_user: Current.user,
      source: 'clinic',
      source_template_id: nil,
      archived_at: nil,
      # dup copia os JSONB por referência (shallow). deep_dup garante que a
      # cópia tenha hashes próprios — sem aliasing com o template original.
      content_json: @template.content_json.deep_dup,
      metadata: @template.metadata.deep_dup
    )

    if copy.save
      render json: { data: DocumentTemplateSerializer.new(copy).as_json(include_content: true) },
             status: :created
    else
      render json: { errors: copy.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST .../document_templates/:id/clone_to_account
  # Clona um template Klivy global pra account da clínica. Diferente de
  # `duplicate` porque preserva source_template_id e source='cloned'.
  def clone_to_account
    authorize @template, :clone_to_account?

    cloned = DocumentTemplate.new(
      account: Current.account,
      created_by_user: Current.user,
      source: 'cloned',
      source_template: @template,
      folder_id: params[:folder_id],
      name: @template.name,
      description: @template.description,
      document_type: @template.document_type,
      content_json: @template.content_json.deep_dup,
      paper_size: @template.paper_size,
      orientation: @template.orientation,
      status: 'active',
      version: 1
    )

    if cloned.save
      render json: { data: DocumentTemplateSerializer.new(cloned).as_json(include_content: true) },
             status: :created
    else
      render json: { errors: cloned.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST .../document_templates/:id/archive
  def archive
    authorize @template
    @template.update!(status: 'archived')
    render json: { data: DocumentTemplateSerializer.new(@template).as_json }
  end

  # POST .../document_templates/:id/unarchive
  def unarchive
    authorize @template
    @template.update!(status: 'active')
    render json: { data: DocumentTemplateSerializer.new(@template).as_json }
  end

  private

  def load_template
    @template = DocumentTemplate.for_account(Current.account).find(params[:id])
  end

  # `policy_scope` já filtra por account + klivy, mas index pode pedir
  # `only=mine` ou `only=klivy` pra dividir as duas seções no UI.
  def filter_by_account(scope)
    case params[:only]
    when 'mine'  then scope.where(account_id: Current.account.id)
    when 'klivy' then scope.where(account_id: nil)
    else scope
    end
  end

  def filter_by_family(scope, family)
    case family
    when 'clinical' then scope.clinical
    when 'consent'  then scope.consents
    else scope
    end
  end

  # Por padrão a listagem mostra modelos ATIVOS e RASCUNHOS (draft) —
  # um modelo recém-criado nasce como draft e PRECISA aparecer pra clínica
  # continuar editando. Só os arquivados ficam de fora até pedir
  # include_archived=true (que traz os três status pro client filtrar).
  def filter_by_status(scope, include_archived)
    return scope.where(status: %w[active draft archived]) if include_archived == 'true'

    scope.where(status: %w[active draft])
  end

  def template_params
    params.require(:document_template).permit(
      :name,
      :description,
      :document_type,
      :folder_id,
      :paper_size,
      :orientation,
      :status,
      content_json: {},
      metadata: {}
    )
  end
end
