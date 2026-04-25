class Api::V1::Accounts::Whatsapp::BridgesController < Api::V1::Accounts::BaseController
  before_action :set_bridge_url
  before_action :set_inbox_id

  # GET /api/v1/accounts/:account_id/whatsapp/bridge/:inbox_id/qr
  def qr
    Rails.logger.info "[WHATSAPP_BRIDGE_PROXY] QR solicitado para inbox #{@inbox_id}"
    response = Net::HTTP.get_response(URI("#{@bridge_url}/sessions/#{@inbox_id}/qr"))
    render json: JSON.parse(response.body), status: response.code
  rescue StandardError => e
    render_bridge_error(e)
  end

  # GET /api/v1/accounts/:account_id/whatsapp/bridge/:inbox_id/status
  def status
    response = Net::HTTP.get_response(URI("#{@bridge_url}/sessions/#{@inbox_id}/status"))
    render json: JSON.parse(response.body), status: response.code
  rescue StandardError => e
    render_bridge_error(e)
  end

  # POST /api/v1/accounts/:account_id/whatsapp/bridge/:inbox_id/disconnect
  def disconnect
    Rails.logger.info "[WHATSAPP_BRIDGE_PROXY] Disconnect solicitado para inbox #{@inbox_id}"
    uri = URI("#{@bridge_url}/sessions/#{@inbox_id}/disconnect")
    response = Net::HTTP.post_form(uri, {})
    render json: JSON.parse(response.body), status: response.code
  rescue StandardError => e
    render_bridge_error(e)
  end

  # POST /api/v1/accounts/:account_id/whatsapp/bridge/:inbox_id/register
  def register
    Rails.logger.info "[WHATSAPP_BRIDGE_PROXY] Register para inbox #{@inbox_id}: #{params[:phone_number]}"
    uri = URI("#{@bridge_url}/sessions/#{@inbox_id}/register")
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
    request.body = { phone_number: params[:phone_number] }.to_json

    response = http.request(request)
    render json: JSON.parse(response.body), status: response.code
  rescue StandardError => e
    render_bridge_error(e)
  end

  # POST /api/v1/accounts/:account_id/whatsapp/bridge/:inbox_id/migrate
  # Move uma sessão temporária (migrate_from) para o inbox_id permanente
  def migrate
    Rails.logger.info "[WHATSAPP_BRIDGE_PROXY] Migrate para inbox #{@inbox_id} de #{params[:migrate_from]}"
    uri = URI("#{@bridge_url}/sessions/#{@inbox_id}/migrate")
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
    request.body = {
      migrate_from: params[:migrate_from],
      phone_number: params[:phone_number]
    }.to_json

    response = http.request(request)
    render json: JSON.parse(response.body), status: response.code
  rescue StandardError => e
    render_bridge_error(e)
  end

  private

  def set_inbox_id
    @inbox_id = params[:inbox_id]
  end

  def set_bridge_url
    @bridge_url = ENV.fetch('WHATSAPP_QR_BRIDGE_URL') { ENV.fetch('WHATSAPP_BRIDGE_URL', 'http://localhost:3002') }
  end

  def render_bridge_error(error)
    Rails.logger.error "[WHATSAPP_BRIDGE_PROXY] Error: #{error.message}"
    render json: { success: false, error: 'Não foi possível conectar ao motor do WhatsApp' }, status: :service_unavailable
  end
end
