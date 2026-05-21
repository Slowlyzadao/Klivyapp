PatientPortal::Engine.routes.draw do
  # ─── Diagnóstico de rede (dev only) — acessível em qualquer host. ───────────
  # Página HTML pura que faz fetch para a API e mostra erro completo na tela.
  # Útil quando "Load failed" acontece no celular e DevTools não está acessível.
  if Rails.env.development?
    get '/portal-diag',       to: 'patient_portal_diag#index'
    get '/portal-diag/ping',  to: ->(_env) { [200, { 'Content-Type' => 'application/json' }, ['{"pong":true}']] }
  end

  # ─── API do paciente (consumida pelo SPA) ───────────────────────────────────
  # Declarada ANTES da catch-all do SPA (senão o catch-all engole as APIs).
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      namespace :patient_portal do
        # Autenticação OTP (sem account_id no path — account vem do JWT)
        namespace :auth do
          post   :request_otp
          post   :verify_otp
          post   :select_account
          delete :logout
          get    :me
        end

        # Home agregada
        get :home, to: 'home#show'

        # Consentimentos do paciente (termos Klivy — portal_terms + lgpd)
        # Sprint B entrega só esses dois; consentimento clínico por procedimento
        # (ConsentRecord) vem na Sprint D.
        post 'consents/portal_terms/accept', to: 'consents#accept_portal_terms'
        post 'consents/lgpd/accept',         to: 'consents#accept_lgpd'

        # Notificações (Sprint E: modelo real)
        get  :notifications,                       to: 'notifications#index'
        post 'notifications/mark_all_read',        to: 'notifications#mark_all_read'
        post 'notifications/:id/mark_read',        to: 'notifications#mark_read', as: :mark_read_notification

        # Sprint E — Mensagens (ponte com Chatwoot Conversation/Message)
        resources :messages, only: [:index, :create] do
          collection { post :triage }
        end

        # Sprint E — Perfil editável pelo paciente
        resource :profile, only: [:show, :update], controller: 'profile'

        # Sprint E — LGPD export
        resources :lgpd_exports, only: [:create], path: 'lgpd/exports'

        # Sprint F — Pagamento online
        resources :payments, only: [:create, :show] do
          member do
            post :cancel
            post :simulate_paid # dev-only
          end
        end

        # Sprint G — Web Push
        scope :push_subscriptions, controller: 'push_subscriptions' do
          get  :public_key, action: :public_key
          post '',          action: :create,  as: :push_subscription_create
          delete '',        action: :destroy, as: :push_subscription_destroy
        end

        # Sprint I — Dependentes / responsável legal
        scope :dependents, controller: 'dependents' do
          get  '',       action: :index,  as: :dependents_index
          post :switch,  action: :switch, as: :dependents_switch
        end

        # Sprint C — Consultas, documentos e pedidos
        resources :appointments, only: [:index, :show] do
          member do
            post :confirm
            post :cancel
          end
        end
        # Telemed: rotas `:telemedicine_token`/`:telemedicine_event` foram
        # movidas para plugins/telemed/config/routes.rb sob
        # /api/v1/patient_portal/telemed/sessions(/event).
        resources :appointment_requests, only: [:index, :create, :destroy]

        resources :documents, only: [:index, :show] do
          member { get :download }
        end
        resources :document_requests, only: [:index, :create, :destroy]

        # Preflight consultivo — "posso solicitar agendamento agora?"
        get 'preflight/appointment', to: 'preflight#appointment'

        # Sprint D — Financeiro (read), Consentimentos clínicos, Anamnese, Recall
        scope :financial do
          get  :summary,                       to: 'financial#summary'
          get  :installments,                  to: 'financial#index_installments'
          get  'installments/:id',             to: 'financial#show_installment', as: :financial_installment
          get  'installments/:id/proof',       to: 'financial#proof',            as: :financial_installment_proof
        end

        resources :consent_records, only: [:index, :show] do
          member { post :sign }
        end

        resources :anamneses, only: [:index, :show]

        scope :recall do
          post :dismiss,         to: 'recall#dismiss'
          post :schedule_intent, to: 'recall#schedule_intent'
        end
      end
    end
  end

  # ─── API administrativa (consumida pelo painel da clínica) ──────────────────
  # Reside em /api/v1/accounts/:account_id/patient_portal/ — segue padrão dos demais plugins.
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :patient_portal do
            resources :invites, only: [:create, :index, :destroy]
            resource  :setting, only: [:show, :update] do
              post :apply_preset
            end
            resources :patients, only: [] do
              resource :portal_suspension, only: [:create, :destroy], controller: 'portal_suspensions'
            end
          end
        end
      end
    end
  end

  # ─── SPA: serve a view do portal quando o host bate em `pacientes.*` ─────────
  # DEPOIS das APIs porque a catch-all `/*params` casaria com qualquer path.
  # Produção:   pacientes.klivy.app
  # Dev local:  pacientes.lvh.me:3000  OU  pacientes.localhost:3000
  #             (`.localhost` é tratado como secure context pelo Chrome — RFC 6761 —
  #              permite getUserMedia em HTTP sem flag, importante pra telemed)
  # Dev tunnel: *.ngrok-free.app / *.ngrok.app / *.trycloudflare.com (acesso
  #             pelo celular sem precisar de subdomínio próprio).
  # Usamos `host:` em vez de `subdomain:` porque com hostnames multi-level (lvh.me),
  # Rails extrai subdomain="pacientes.lvh" — o regex de host é mais previsível.
  constraints(host: /^pacientes\.|\.localhost$|\.ngrok-free\.app$|\.ngrok\.app$|\.ngrok\.io$|\.trycloudflare\.com$/) do
    root to: 'patient_portal_pages#index', as: :patient_portal_root
    get '/*params', to: 'patient_portal_pages#index', as: :patient_portal_catchall, format: false
  end
end
