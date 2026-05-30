# CRUD + ações de SignatureRequest.
#
# Endpoints:
#   GET    /api/v1/accounts/:id/signature_requests           — list
#       params: signable_type, signable_id, status, page, per_page
#   GET    /api/v1/accounts/:id/signature_requests/:id       — show
#   POST   /api/v1/accounts/:id/signature_requests           — create
#       body: { signable_type, signable_id, signer_name, signer_email,
#               signer_phone?, signer_cpf?, message?, provider? }
#   POST   /api/v1/accounts/:id/signature_requests/:id/cancel
#   POST   /api/v1/accounts/:id/signature_requests/:id/resend
#   POST   /api/v1/accounts/:id/signature_requests/:id/refresh_status
#   DELETE /api/v1/accounts/:id/signature_requests/:id       — alias de cancel
class Api::V1::Accounts::SignatureRequestsController < Api::V1::Accounts::BaseController
  before_action :load_request, only: [:show, :destroy, :cancel, :resend, :refresh_status]

  def index
    authorize SignatureRequest, :index?
    scope = policy_scope(SignatureRequest)
    scope = scope.where(signable_type: params[:signable_type]) if params[:signable_type].present?
    scope = scope.where(signable_id: params[:signable_id])     if params[:signable_id].present?
    scope = scope.where(status: params[:status])               if params[:status].present?
    render json: {
      data: scope.order(created_at: :desc).limit(50).map { |r| SignatureRequestSerializer.new(r).as_json }
    }
  end

  def show
    authorize @request
    render json: { data: SignatureRequestSerializer.new(@request).as_json(include_audit: true) }
  end

  def create
    signable = locate_signable
    return render_error('Documento não encontrado', status: :not_found) unless signable

    authorize SignatureRequest.new(account: Current.account, signable: signable), :create?

    result = ::Signatures::RequestCreator.call(
      signable: signable,
      requested_by: current_user,
      signer_name: params[:signer_name],
      signer_email: params[:signer_email],
      signer_phone: params[:signer_phone],
      signer_cpf: params[:signer_cpf],
      message: params[:message],
      provider_name: params[:provider]
    )

    if result.success?
      render json: { data: SignatureRequestSerializer.new(result.request).as_json }, status: :created
    else
      render_error(result.error, status: :unprocessable_entity)
    end
  end

  def cancel
    authorize @request
    reason = params[:reason]
    provider = ::Signatures::ProviderResolver.for_name(@request.provider)

    begin
      provider.cancel_envelope(request: @request, reason: reason)
    rescue NotImplementedError => e
      Rails.logger.warn("[SignatureRequests#cancel] #{e.message} — proseguindo com cancel local apenas.")
    end

    @request.mark_cancelled!(reason: reason, meta: { actor_id: current_user.id })
    render json: { data: SignatureRequestSerializer.new(@request).as_json }
  end

  def destroy
    cancel
  end

  def resend
    authorize @request
    provider = ::Signatures::ProviderResolver.for_name(@request.provider)
    result = provider.resend_envelope(request: @request)

    if result.success?
      @request.append_audit!(kind: 'resend', meta: { actor_id: current_user.id })
      render json: { data: SignatureRequestSerializer.new(@request).as_json }
    else
      render_error(result.error, status: :unprocessable_entity)
    end
  rescue NotImplementedError => e
    render_error("Provider ainda não implementado: #{e.message}", status: :not_implemented)
  end

  def refresh_status
    authorize @request
    provider = ::Signatures::ProviderResolver.for_name(@request.provider)
    result = provider.fetch_status(request: @request)

    if result.success?
      @request.append_audit!(kind: 'status_refreshed', meta: { remote: result.data })
      render json: { data: SignatureRequestSerializer.new(@request).as_json }
    else
      render_error(result.error, status: :bad_gateway)
    end
  rescue NotImplementedError => e
    render_error("Provider ainda não implementado: #{e.message}", status: :not_implemented)
  end

  private

  def load_request
    @request = SignatureRequest.where(account: Current.account).find(params[:id])
  end

  # Resolve o `signable` polimórfico. Hoje aceita Document e ConsentRecord.
  def locate_signable
    type = params[:signable_type].to_s
    id   = params[:signable_id]
    return nil if type.blank? || id.blank?

    klass = { 'Document' => Document, 'ConsentRecord' => ConsentRecord }[type]
    return nil unless klass

    klass.where(account: Current.account).find_by(id: id)
  end
end
