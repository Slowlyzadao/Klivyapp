# frozen_string_literal: true

# Rotas do plugin document_templates.
#
# Convenção Klivy: rotas administrativas vivem sob
# /api/v1/accounts/:account_id/<resource>. Controllers herdam de
# Api::V1::Accounts::BaseController (autenticação devise + Current.account).
DocumentTemplates::Engine.routes.draw do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          resources :document_template_folders

          resources :document_templates do
            collection do
              get :variables       # catálogo de variáveis disponíveis pra inserção
              get :klivy_library   # templates Klivy globais (cloneáveis)
            end
            member do
              post :duplicate       # cria cópia local do template (mesma account)
              post :clone_to_account # clona um template Klivy pra account
              post :archive
              post :unarchive
            end
          end
        end
      end
    end
  end
end
