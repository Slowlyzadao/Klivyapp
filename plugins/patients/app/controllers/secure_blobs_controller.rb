# frozen_string_literal: true

# Cross-tenant guard para Active Storage blobs (Roadmap #17.1).
#
# Resolve o problema de `rails_blob_url` não codificar `account_id`: se um
# signed URL vaza dentro da janela de expiração, era acessível por qualquer
# usuário logado (de qualquer account). Agora cada link passa por aqui,
# que valida que o usuário atual pertence à account dona do blob.
#
# Fluxo:
#   1. Caller (Document#signed_url etc.) gera token via
#      Patients::SecureBlobTokenService — carrega { blob_id, account_id,
#      expires_at, transformations? }, assinado com message_verifier.
#   2. Frontend renderiza `<img src="/secure_blobs/<token>">` ou
#      `<iframe src=...>`.
#   3. Browser faz GET com cookie de sessão `_chatwoot_session` (mantido
#      fresco pelo ApplicationController#ensure_session_cookie em toda
#      request autenticada via token).
#   4. Aqui: lê warden session direto pra obter user_id (Devise current_user
#      é overridado pelo devise_token_auth e retorna nil sem token header,
#      mesmo com cookie válido) → busca User → cross-tenant guard →
#      redirect/stream pra blob.
#
# Estratégia de entrega final (após guard passar):
#   - Variants (thumbnails) → redirect 302 pra URL signed do storage backend.
#   - PDFs → stream same-origin via send_data (R2/CDN cross-origin é
#     bloqueado pelo Chrome em iframes).
#   - Imagens, vídeos → redirect 302 pra URL signed do storage (CDN benefit).
#
# Janela curta de 30s na URL final do storage = defesa em profundidade.
#
# Herda de ActionController::Base (não Api::BaseController) porque:
#   - Aceita cookie session pra GET de assets do browser.
#   - Permite redirect 302 / send_data sem JSON envelope.
class SecureBlobsController < ActionController::Base
  # CSRF não se aplica a GET. Mas mantemos paranoid mode caso adicionem
  # POST/PUT a esse controller no futuro — token signed já é o gate real.
  protect_from_forgery with: :exception, prepend: true

  before_action :authenticate_via_session
  before_action :decode_token
  before_action :authorize_account_access

  # GET /secure_blobs/:token
  def show
    blob = ActiveStorage::Blob.find_by(id: @token_data[:blob_id])
    return head(:not_found) unless blob

    if @token_data[:transformations].present?
      # Thumbnails (variants) — sempre imagem, redirect direto pra CDN.
      variant = blob.variant(@token_data[:transformations]).processed
      redirect_to variant.url(expires_in: 30.seconds, disposition: :inline),
                  allow_other_host: true
    elsif iframe_proxy_required?(blob)
      # PDFs (e tipos similares) precisam ser servidos same-origin pra
      # renderizar em `<iframe>` — R2/CDN cross-origin é bloqueado pelo
      # Chrome (X-Frame-Options ou política de PDF cross-origin).
      # Custo: blob carregado em memória (max 10MB por config do produto).
      send_data blob.download,
                type: blob.content_type,
                disposition: :inline,
                filename: blob.filename.to_s
    else
      # Imagens, vídeos, áudio — redirect pro storage backend (CDN benefit).
      redirect_to blob.url(expires_in: 30.seconds, disposition: :inline),
                  allow_other_host: true
    end
  end

  private

  # Lê user_id da warden session diretamente. Não usamos `authenticate_user!`
  # da Devise porque devise_token_auth sobrescreve `current_user` e retorna
  # nil quando não há token header — mesmo com session válida.
  #
  # A session do Rails (_chatwoot_session) é assinada pela secret_key_base —
  # se o key está lá com user_id correto, é fonte confiável (não pode ter
  # sido forjado sem a chave). O ApplicationController#ensure_session_cookie
  # garante que o key seja escrito a cada request autenticada via token.
  #
  # Formato do warden key: [[user_id], authenticatable_salt]
  def authenticate_via_session
    user_key = session['warden.user.user.key']
    return head(:unauthorized) unless valid_warden_key?(user_key)

    user_id = user_key.first.first
    @current_blob_user = User.find_by(id: user_id)
    return head(:unauthorized) unless @current_blob_user
  end

  def valid_warden_key?(user_key)
    user_key.is_a?(Array) &&
      user_key.first.is_a?(Array) &&
      user_key.first.first.is_a?(Integer)
  end

  # Tipos que precisam ser servidos same-origin pra renderizar em iframe.
  # PDFs cross-origin em iframe são bloqueados pelo Chrome (chrome-error
  # frame), mesmo com signed URL válida e disposition: :inline.
  IFRAME_PROXY_CONTENT_TYPES = %w[application/pdf].freeze

  def iframe_proxy_required?(blob)
    IFRAME_PROXY_CONTENT_TYPES.include?(blob.content_type)
  end

  def decode_token
    @token_data = Patients::SecureBlobTokenService.decode!(params[:token])
  rescue Patients::SecureBlobTokenService::Expired
    head :gone # 410 — token expirou; UX: usuário precisa voltar e gerar link novo
  rescue Patients::SecureBlobTokenService::Tampered,
         Patients::SecureBlobTokenService::Malformed
    head :unprocessable_entity # 422 — token corrompido
  end

  # Cross-tenant guard: usuário logado precisa pertencer à account
  # codificada no token. Ignora super_admin (eles têm visão geral via
  # backoffice próprio, não via signed URLs de account específico).
  def authorize_account_access
    return if performed? # decode_token já respondeu (410/422)

    user_account_ids = @current_blob_user.account_users.pluck(:account_id)
    return if user_account_ids.include?(@token_data[:account_id])

    head :forbidden # 403
  end
end
