# Serve o shell HTML do SPA. Toda navegação dentro do portal é client-side
# (Vue Router). Servidor responde com a mesma view para qualquer path
# (catch-all `/*params` em config/routes.rb deste engine).
class PatientPortalPagesController < ActionController::Base
  layout false
  protect_from_forgery with: :null_session

  def index
    render template: 'patient_portal_pages/index'
  end
end
