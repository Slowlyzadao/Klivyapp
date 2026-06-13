# frozen_string_literal: true

# Rotas do plugin signatures. Endpoints da clínica vivem em
# /api/v1/accounts/:account_id/signature_requests/*. Webhook do Clicksign
# vive fora do account scope (público com assinatura HMAC).
Signatures::Engine.routes.draw do
  # Webhook do Clicksign — chama essa URL pra notificar mudanças de status
  # do envelope. Validação HMAC dentro do controller.
  post '/webhooks/clicksign', to: 'webhooks/clicksign#process_payload'

  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          resources :signature_requests, only: [:index, :show, :create, :destroy] do
            member do
              post :cancel
              post :resend
              post :refresh_status # força sync com o provider (poll manual)
            end
          end
        end
      end
    end
  end
end
