class ApplicationController < ActionController::Base
  include DeviseTokenAuth::Concerns::SetUserByToken
  include RequestExceptionHandler
  include Pundit::Authorization
  include SwitchLocale

  skip_before_action :verify_authenticity_token

  before_action :set_current_user, unless: :devise_controller?
  around_action :switch_locale, unless: :devise_controller?
  around_action :handle_with_exception, unless: :devise_controller?
  after_action :ensure_session_cookie, unless: :devise_controller?

  private

  def set_current_user
    @user ||= current_user
    Current.user = @user
  end

  # Roadmap #17.1 — devise_token_auth autentica via header `access-token` mas
  # browsers em GET de `<img src>`/`<iframe src>`/`<a href>` só enviam cookies.
  # Sem o cookie `_chatwoot_session`, o SecureBlobsController não consegue
  # autenticar usuários logados via token.
  #
  # Escrevemos diretamente na warden session — bypassa Devise sign_in (que
  # faz no-op se o user já está autenticado via warden). `session_serializer`
  # escreve em `session["warden.user.user.key"]`, marcando a sessão como
  # modificada e emitindo Set-Cookie automaticamente.
  def ensure_session_cookie
    return unless current_user

    Rails.logger.info { "[ensure_session_cookie] storing user #{current_user.id}" }
    warden.session_serializer.store(current_user, :user)
  rescue StandardError => e
    Rails.logger.warn { "[ensure_session_cookie] failed: #{e.class} #{e.message}" }
  end

  def pundit_user
    {
      user: Current.user,
      account: Current.account,
      account_user: Current.account_user
    }
  end
end
ApplicationController.include_mod_with('Concerns::ApplicationControllerConcern')
