# Upload e listagem de documentos da Bea por conta. Cada documento dispara
# AiAgent::IngestDocumentJob no create — extração + chunking + embeddings
# acontecem em background.
class SuperAdmin::AiAgentDocumentsController < SuperAdmin::ApplicationController
  before_action :load_account

  def index
    @documents = @account.documents_for_bea.order(created_at: :desc)
  end

  def create
    name = params.dig(:document, :name).presence || uploaded_file&.original_filename || 'documento'
    @document = AiAgent::Document.new(
      account: @account,
      name: name,
      source_type: 'pdf'
    )
    @document.pdf_file.attach(uploaded_file) if uploaded_file

    if @document.save
      AiAgent::IngestDocumentJob.perform_later(@document.id)
      AiAgent::AuditLog.record(
        scope: 'account',
        action: 'upload_document',
        actor: current_super_admin,
        account_id: @account.id,
        ip: request.remote_ip,
        changes: { document_id: @document.id, name: @document.name }
      )
      redirect_to super_admin_account_ai_agent_documents_path(@account),
                  notice: "Documento '#{@document.name}' enviado. Processamento em background."
    else
      redirect_to super_admin_account_ai_agent_documents_path(@account),
                  alert: @document.errors.full_messages.join(', ')
    end
  end

  def destroy
    # Scoped à conta da URL (igual ao index) — evita apagar documento de OUTRA
    # conta via id forjado e auditoria atribuída à conta errada (auditoria 2026-05-30).
    document = @account.documents_for_bea.find(params[:id])
    document.destroy!
    AiAgent::AuditLog.record(
      scope: 'account',
      action: 'delete_document',
      actor: current_super_admin,
      account_id: @account.id,
      ip: request.remote_ip,
      changes: { document_id: document.id, name: document.name }
    )
    redirect_to super_admin_account_ai_agent_documents_path(@account),
                notice: 'Documento removido.'
  end

  private

  def load_account
    @account = Account.find(params[:account_id])
  end

  def uploaded_file
    params.dig(:document, :pdf_file)
  end
end
