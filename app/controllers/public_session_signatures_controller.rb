# frozen_string_literal: true

# Controller HTML público — serve a página standalone que o paciente abre via
# link compartilhado pra assinar uma `SessionLog` remotamente. Sem auth — o
# `remote_token` é a credencial.
#
# A página renderiza um canvas + JS inline e fala com o endpoint JSON em
# `/public/api/v1/session_log_signatures/:remote_token` (controller separado,
# já existe em `Public::Api::V1::SessionLogSignaturesController`).
#
# Por que controller separado em vez de `respond_to :html` no controller JSON?
# Porque a API ali é `ActionController::API` (sem helpers de view nem layouts),
# e este precisa renderizar ERB. Manter os dois separados deixa as
# responsabilidades claras: JSON pra dados, HTML pra apresentação.
class PublicSessionSignaturesController < ActionController::Base
  layout 'public_signature'

  # Disponibiliza @public_signature_url e afins pra view sem precisar montar
  # tudo no JS — facilita debug.
  def show
    @token = params[:token].to_s
    redirect_to(root_path) && return if @token.blank?

    # Brand assets (mesmo padrão de `AgendaBookingController#show`).
    @brand_name = GlobalConfigService.load('BRAND_NAME', 'Klivy')
    @brand_logo = GlobalConfigService.load('LOGO', '/brand-assets/logo.svg')

    # Não renderizamos detalhes nem fazemos lookup aqui — quem decide se o
    # token é válido é o endpoint JSON (`/public/api/v1/session_log_signatures/:token`),
    # chamado via fetch da própria página. Mantém a fonte da verdade num lugar
    # só e evita duplicar checagem expirou/usado.
  end
end
