Rails.application.routes.draw do
  # Portal do Paciente (SPA + APIs). Montado PRIMEIRO de propósito: o engine tem
  # um catch-all `/*params` constrito ao host `pacientes.*` que precisa ter
  # prioridade sobre o `root`/`/app` do dashboard nesses hosts. Em hosts normais
  # o constraint de host não casa e as rotas caem no resto do arquivo. As APIs
  # do portal (`/api/v1/patient_portal/*`, `/api/v1/accounts/:id/patient_portal/*`)
  # e o webhook ficam dentro do engine; o catch-all exclui prefixos do dashboard.
  mount PatientPortal::Engine, at: '/'

  # AUTH STARTS
  mount_devise_token_auth_for 'User', at: 'auth', controllers: {
    confirmations: 'devise_overrides/confirmations',
    passwords: 'devise_overrides/passwords',
    sessions: 'devise_overrides/sessions',
    token_validations: 'devise_overrides/token_validations',
    omniauth_callbacks: 'devise_overrides/omniauth_callbacks'
  }, via: [:get, :post]

  ## renders the frontend paths only if its not an api only server
  if ActiveModel::Type::Boolean.new.cast(ENV.fetch('CW_API_ONLY_SERVER', false))
    root to: 'api#index'
  else
    root to: 'dashboard#index'

    get '/app', to: 'dashboard#index'
    get '/app/*params', to: 'dashboard#index'
    get '/app/accounts/:account_id/settings/inboxes/new/twitter', to: 'dashboard#index', as: 'app_new_twitter_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/microsoft', to: 'dashboard#index', as: 'app_new_microsoft_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/instagram', to: 'dashboard#index', as: 'app_new_instagram_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/tiktok', to: 'dashboard#index', as: 'app_new_tiktok_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_twitter_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_email_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_instagram_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_tiktok_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/:inbox_id', to: 'dashboard#index', as: 'app_instagram_inbox_settings'
    get '/app/accounts/:account_id/settings/inboxes/:inbox_id', to: 'dashboard#index', as: 'app_tiktok_inbox_settings'
    get '/app/accounts/:account_id/settings/inboxes/:inbox_id', to: 'dashboard#index', as: 'app_email_inbox_settings'

    resource :widget, only: [:show]
    namespace :survey do
      resources :responses, only: [:show]
    end
    resource :slack_uploads, only: [:show]

    # Mini-site de agendamento online público
    get '/agenda/:public_id', to: 'agenda_booking#show', as: 'agenda_booking'

    # Cross-tenant guard para blobs de patients (Roadmap #17.1).
    # Token assinado por message_verifier(:secure_blob) carrega blob_id +
    # account_id; controller valida que current_user pertence à account
    # antes de redirecionar para o signed URL real.
    # Auth via cookie de sessão (Devise default) — preserva click-to-open
    # de `<a href>` e `<img :src>`.
    get '/secure_blobs/:token', to: 'secure_blobs#show', as: 'secure_blob'
  end

  get '/health', to: 'health#show'
  get '/api', to: 'api#index'

  # Bea (AiAgent) — endpoints públicos.
  # health: 200 ok/degraded/idle, 503 down. Pensado pra uptime checker externo.
  # feedback: 👍/👎 do paciente sobre uma resposta; auth via HMAC token gerado
  # pelo TokenSigner — sem login.
  get  'api/v1/ai_agent/health',   to: 'api/v1/ai_agent/health#show'
  post 'api/v1/ai_agent/feedback', to: 'api/v1/ai_agent/feedbacks#create'

  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      # ----------------------------------
      # start of account scoped api routes
      resources :accounts, only: [:create, :show, :update] do
        member do
          post :update_active_at
          get :cache_keys
        end

        scope module: :accounts do
          namespace :actions do
            resource :contact_merge, only: [:create]
          end
          resource :bulk_actions, only: [:create]
          resources :agents, only: [:index, :create, :update, :destroy] do
            post :bulk_create, on: :collection
          end
          namespace :captain do
            resource :preferences, only: [:show, :update]
            resources :assistants do
              member do
                post :playground
              end
              collection do
                get :tools
              end
              resources :inboxes, only: [:index, :create, :destroy], param: :inbox_id
              resources :scenarios
            end
            resources :assistant_responses
            resources :bulk_actions, only: [:create]
            resources :copilot_threads, only: [:index, :create] do
              resources :copilot_messages, only: [:index, :create]
            end
            resources :custom_tools
            resources :documents, only: [:index, :show, :create, :destroy]
            resource :tasks, only: [], controller: 'tasks' do
              post :rewrite
              post :summarize
              post :reply_suggestion
              post :label_suggestion
              post :follow_up
            end
          end
          resource :saml_settings, only: [:show, :create, :update, :destroy]
          resources :agent_bots, only: [:index, :create, :show, :update, :destroy] do
            delete :avatar, on: :member
            post :reset_access_token, on: :member
          end
          resources :contact_inboxes, only: [] do
            collection do
              post :filter
            end
          end
          resources :assignable_agents, only: [:index]
          resource :audit_logs, only: [:show]
          resources :callbacks, only: [] do
            collection do
              post :register_facebook_page
              get :register_facebook_page
              post :facebook_pages
              post :reauthorize_page
            end
          end
          resources :canned_responses, only: [:index, :create, :update, :destroy]
          resources :automation_rules, only: [:index, :create, :show, :update, :destroy] do
            post :clone
          end
          resources :macros, only: [:index, :create, :show, :update, :destroy] do
            post :execute, on: :member
          end
          resources :sla_policies, only: [:index, :create, :show, :update, :destroy]
          resources :custom_roles, only: [:index, :create, :show, :update, :destroy]
          resources :klivy_roles, only: [:index, :create, :show, :update, :destroy] do
            member do
              post :assign
            end
          end
          resources :agent_capacity_policies, only: [:index, :create, :show, :update, :destroy] do
            scope module: :agent_capacity_policies do
              resources :users, only: [:index, :create, :destroy]
              resources :inbox_limits, only: [:create, :update, :destroy]
            end
          end
          resources :campaigns, only: [:index, :create, :show, :update, :destroy]

          # =====================================================
          # AiAgent (Bea) — knowledge base + follow-ups + internal notifications
          # =====================================================
          # Controllers + policies + views vivem em plugins/ai_agent/.
          # `controller: '/ai_agent/...'` é caminho absoluto pra preservar o
          # namespace AiAgent::Api::V1::Accounts::* sem o scope :accounts
          # prefixar `accounts/`.
          resources :ai_agent_documents,
                    path: 'ai_agent/documents',
                    only: [:index, :show, :create, :destroy],
                    controller: '/ai_agent/api/v1/accounts/documents'
          resources :ai_agent_training_conversations,
                    path: 'ai_agent/training_conversations',
                    only: [:index, :show, :create, :destroy],
                    controller: '/ai_agent/api/v1/accounts/training_conversations' do
            collection do
              delete :destroy_all
              get :pending_faqs
              post :approve_all
            end
            member do
              post :publish
              post :select_clinic
            end
          end
          resources :ai_agent_training_faqs,
                    path: 'ai_agent/training_faqs',
                    only: [:index, :update, :destroy],
                    controller: '/ai_agent/api/v1/accounts/training_faqs' do
            collection do
              delete :destroy_all
            end
          end
          resources :ai_agent_follow_up_rules,
                    path: 'ai_agent/follow_up_rules',
                    only: [:index, :show, :create, :update, :destroy],
                    controller: '/ai_agent/api/v1/accounts/follow_up_rules'
          resources :ai_agent_internal_notification_templates,
                    path: 'ai_agent/internal_notification_templates',
                    only: [:index, :show, :create, :update, :destroy],
                    controller: '/ai_agent/api/v1/accounts/internal_notification_templates' do
            collection do
              get :catalog
            end
            member do
              post :reset
            end
          end

          # =====================================================
          # InternalChat — chat interno entre profissionais
          # =====================================================
          # Controllers, models e policies em plugins/internal_chat/.
          namespace :internal_chat do
            resources :rooms, only: [:index, :show, :create, :update, :destroy] do
              collection do
                get :unread_summary
              end
              member do
                patch :archive
                patch :unarchive
                patch :mute
                delete :mute, action: :unmute
                patch :avatar, action: :update_avatar
                delete :avatar, action: :remove_avatar
              end
              resources :messages, only: [:index, :create, :update, :destroy] do
                collection do
                  post :mark_read
                  get :favorites
                end
                member do
                  post :favorite
                  delete :favorite, action: :unfavorite
                  post :react
                  delete :react, action: :unreact
                end
              end
              resources :memberships, only: [:index, :create, :update, :destroy]
              resources :typing, only: [:create]
              resources :attachments, only: [:index] do
                member do
                  get :download
                end
              end
            end
            resources :mentions, only: [:index] do
              collection do
                post :mark_read
                get :unread_count
              end
            end
            resources :stickers, only: [:index, :create, :destroy] do
              member do
                post :favorite
                delete :favorite, action: :unfavorite
              end
            end
          end

          # =====================================================
          # Prontuário Eletrônico — Bloco 1: Fundação de Dados
          # =====================================================
          resources :patients, only: [:index, :show, :create, :update, :destroy] do
            collection do
              get :by_contact
              get :archived
            end
            member do
              get  :summary
              patch :status
              patch :restore
              post :quick_action
              get  :change_history
            end
            scope module: :patients do
              resources :critical_alerts, only: [:index, :create, :update, :destroy] do
                member do
                  patch :deactivate
                end
              end
              resources :audit_logs, only: [:index] do
                collection do
                  get :export
                end
              end

              # Bloco 2: Módulo Clínico Core
              resources :anamneses, only: [:index, :show, :create, :update, :destroy] do
                member do
                  patch :finalize
                end
              end
              resources :clinical_notes, only: [:index, :show, :create, :update, :destroy] do
                member do
                  patch :sign
                  patch :mark_erratum
                end
              end

              # Bloco 3: Plano de Tratamento + Sessões
              resources :treatment_plans, only: [:index, :show, :create, :update, :destroy] do
                member do
                  patch :approve
                  patch :cancel
                  get   :pdf
                end
                resources :treatment_items, only: [:index, :show, :create, :update, :destroy]
              end
              resources :session_logs, only: [:index, :show, :create, :update, :destroy] do
                member do
                  patch :sign
                  patch :mark_erratum
                  post  :sign_patient_locally
                  post  :send_patient_remote_signature_link
                end
              end

              # Bloco 4: Financeiro do Paciente — REMOVIDO v1 (2026-05-11)
              # Endpoints `transactions`, `financial_estimates`, `financial_summary`
              # e `financial_timeline` (v1) foram deletados. Use o módulo v2:
              # - GET    /api/v1/accounts/:id/financial/v2/patient_timelines/:patient_id
              # - GET    /api/v1/accounts/:id/financial/v2/patient_summaries/:patient_id
              # - CRUD   /api/v1/accounts/:id/financial/v2/budgets, /installments, etc.

              # Bloco 5: Mídia, Documentos e Consentimentos
              resources :exam_medias, only: [:index, :show, :create, :update, :destroy], path: 'exams' do
                collection do
                  get :compare
                end
              end
              resources :exam_folders, only: [:index, :create, :update, :destroy] do
                collection do
                  put :reorder
                end
              end
              resources :documents, only: [:index, :show, :destroy] do
                collection do
                  post :generate
                  post :attach
                end
                member do
                  get :download
                  post :send_whatsapp
                  patch :status
                end
              end
              resources :consent_records, only: [:index, :create, :show], path: 'consents' do
                collection do
                  get :pending
                end
                member do
                  post :sign
                  post :send_remote
                  patch :revoke
                end
              end

              # Bloco 6: Agenda do Paciente + Timeline
              #
              # Auditoria UX 2026-05-15: as ações `reschedule`, `cancel` e
              # `no_show` foram removidas da aba do prontuário (decisão de
              # produto Opção 1 — operação de agenda é exclusiva do
              # calendário principal). Eliminou rotas + actions correspondentes
              # do `PatientAppointmentsController` + `AppointmentRescheduler`
              # service. Aba de prontuário agora é read-only para histórico
              # de consultas + envio de recall via WhatsApp.
              resources :patient_appointments, only: [:index, :show, :create], path: 'appointments',
                                               controller: 'appointments'
              resource :recall, only: [:create], controller: 'recalls'
              resources :timeline, only: [:index], controller: 'timeline'
            end
          end

          resources :form_templates, only: [:index, :show, :create, :update, :destroy]
          # =====================================================

          resources :agenda_events, only: [:index, :create, :show, :update, :destroy] do
            collection do
              get :year_stats
            end
          end
          resources :waiting_list_entries, only: [:index, :create, :destroy]
          resources :agenda_notification_rules, only: [:index, :create, :show, :update, :destroy] do
            member do
              patch :toggle
            end
          end
          resources :agenda_notification_logs, only: [:index]
          resource :agenda_online_config, only: [:show, :update], controller: 'agenda_online_config'
          resource :agenda_setting, only: [:show, :update]
          resources :agenda_custom_attributes, only: [:index, :create, :show, :update, :destroy] do
            collection do
              patch :reorder
            end
          end
          resources :agenda_services, only: [:index, :create, :show, :update, :destroy] do
            collection do
              patch :reorder
              # PR de UI overhaul (2026-05-14):
              # GET retorna {count, ids} dos serviços sem nenhum vínculo.
              # POST faz soft-delete em massa desses serviços.
              get :cleanup_unused_preview
              post :cleanup_unused
            end
            member do
              # PR #7 da auditoria: contadores de uso para o modal de delete defensivo.
              get :usage_stats
              # PR de arquivados (2026-05-14): restore desfaz soft-delete;
              # destroy_permanently remove fisicamente (irreversível).
              post :restore
              delete :destroy_permanently
            end
          end
          # Vínculo profissional↔serviço: quais serviços um agente atende.
          # Usado no modal "Editar Agente". Sem vínculo, o serviço fica
          # invisível pra Bia (clinic_info/search_available_slots exigem
          # >=1 profissional). Ver docs/04-ai-agent/clean-architecture.md §3.
          resources :agenda_agent_services, only: [:index, :update]
          resources :agenda_categories, only: [:index, :create, :show, :update, :destroy] do
            collection do
              patch :reorder
            end
          end
          resources :agenda_reports, only: [] do
            collection do
              get :summary
              get :forecast
            end
          end
          resources :dashboard_apps, only: [:index, :show, :create, :update, :destroy]

          # Clinic Profile (especialidades habilitadas e padrão)
          get    'clinic_profile',      to: 'clinic_profile#show'
          patch  'clinic_profile',      to: 'clinic_profile#update'
          put    'clinic_profile',      to: 'clinic_profile#update'

          # =====================================================
          # Módulo Financeiro — canon V2 (Financial::*)
          # Canon: docs/01-product/modules/financeiro-funcionamento.md
          # Controllers em Api::V1::Accounts::Financial::*
          #
          # Legacy "Onda 1A" (rotas `financial/categories`, `financial/dashboard`,
          # `financial/reports/*`, etc) foi REMOVIDO em 2026-05-22 — sem cliente
          # real usando, frontend já migrado, schema legacy dropado em migration
          # `drop_legacy_financial_tables`.
          # =====================================================
          # Setup wizard (canon F-04)
          get  'financial/v2/setup',                to: 'financial/setup#show', as: 'financial_v2_setup'
          post 'financial/v2/setup/complete_step',  to: 'financial/setup#complete_step', as: 'financial_v2_setup_complete_step'

          # Categorias DRE
          get    'financial/v2/categories',         to: 'financial/dre_categories#index',   as: 'financial_v2_categories'
          post   'financial/v2/categories',         to: 'financial/dre_categories#create'
          # Restaura o canon do Plano de Contas (aditivo/idempotente). Declarada
          # ANTES da rota :id pra evitar captura greedy de "restore_defaults".
          post   'financial/v2/categories/restore_defaults', to: 'financial/dre_categories#restore_defaults', as: 'financial_v2_categories_restore_defaults'
          get    'financial/v2/categories/:id',     to: 'financial/dre_categories#show',    as: 'financial_v2_category'
          patch  'financial/v2/categories/:id',     to: 'financial/dre_categories#update'
          put    'financial/v2/categories/:id',     to: 'financial/dre_categories#update'
          delete 'financial/v2/categories/:id',     to: 'financial/dre_categories#destroy'
          # Define a categoria de RECEITA padrão da conta (recebe lançamentos sem
          # categoria explícita). Só uma por conta — marcar outra limpa a anterior.
          post   'financial/v2/categories/:id/set_default', to: 'financial/dre_categories#set_default', as: 'financial_v2_category_set_default'

          # Contas bancárias
          get    'financial/v2/bank_accounts',                   to: 'financial/bank_accounts#index',   as: 'financial_v2_bank_accounts'
          post   'financial/v2/bank_accounts',                   to: 'financial/bank_accounts#create'
          get    'financial/v2/bank_accounts/:id',               to: 'financial/bank_accounts#show',    as: 'financial_v2_bank_account'
          patch  'financial/v2/bank_accounts/:id',               to: 'financial/bank_accounts#update'
          put    'financial/v2/bank_accounts/:id',               to: 'financial/bank_accounts#update'
          delete 'financial/v2/bank_accounts/:id',               to: 'financial/bank_accounts#destroy'
          post   'financial/v2/bank_accounts/:id/transfer',      to: 'financial/bank_accounts#transfer', as: 'financial_v2_bank_account_transfer'

          # Regras de comissão
          get    'financial/v2/commission_rules',     to: 'financial/commission_rules#index',   as: 'financial_v2_commission_rules'
          post   'financial/v2/commission_rules',     to: 'financial/commission_rules#create'
          get    'financial/v2/commission_rules/:id', to: 'financial/commission_rules#show',    as: 'financial_v2_commission_rule'
          patch  'financial/v2/commission_rules/:id', to: 'financial/commission_rules#update'
          put    'financial/v2/commission_rules/:id', to: 'financial/commission_rules#update'
          delete 'financial/v2/commission_rules/:id', to: 'financial/commission_rules#destroy'

          # Despesas recorrentes
          get    'financial/v2/recurring_expenses',     to: 'financial/recurring_expenses#index',   as: 'financial_v2_recurring_expenses'
          post   'financial/v2/recurring_expenses',     to: 'financial/recurring_expenses#create'
          get    'financial/v2/recurring_expenses/:id', to: 'financial/recurring_expenses#show',    as: 'financial_v2_recurring_expense'
          patch  'financial/v2/recurring_expenses/:id', to: 'financial/recurring_expenses#update'
          put    'financial/v2/recurring_expenses/:id', to: 'financial/recurring_expenses#update'
          delete 'financial/v2/recurring_expenses/:id', to: 'financial/recurring_expenses#destroy'

          # Mensalidades fixas (Financial::RecurringBilling) — contrato
          # recorrente que gera Budget+Installment a cada período via
          # Financial::GenerateRecurringBillingsJob (decisão 2026-05-28).
          get    'financial/v2/recurring_billings',           to: 'financial/recurring_billings#index',   as: 'financial_v2_recurring_billings'
          post   'financial/v2/recurring_billings',           to: 'financial/recurring_billings#create'
          get    'financial/v2/recurring_billings/:id',       to: 'financial/recurring_billings#show',    as: 'financial_v2_recurring_billing'
          patch  'financial/v2/recurring_billings/:id',       to: 'financial/recurring_billings#update'
          put    'financial/v2/recurring_billings/:id',       to: 'financial/recurring_billings#update'
          delete 'financial/v2/recurring_billings/:id',       to: 'financial/recurring_billings#destroy'
          post   'financial/v2/recurring_billings/:id/pause', to: 'financial/recurring_billings#pause',   as: 'financial_v2_recurring_billing_pause'
          post   'financial/v2/recurring_billings/:id/resume',to: 'financial/recurring_billings#resume',  as: 'financial_v2_recurring_billing_resume'
          post   'financial/v2/recurring_billings/:id/cancel',to: 'financial/recurring_billings#cancel',  as: 'financial_v2_recurring_billing_cancel'

          # Metas de receita (canon Setup #8 — CRUD completo + upsert legacy)
          get    'financial/v2/revenue_goals',         to: 'financial/revenue_goals#index',   as: 'financial_v2_revenue_goals'
          post   'financial/v2/revenue_goals',         to: 'financial/revenue_goals#create'
          get    'financial/v2/revenue_goals/:id',     to: 'financial/revenue_goals#show',    as: 'financial_v2_revenue_goal'
          patch  'financial/v2/revenue_goals/:id',     to: 'financial/revenue_goals#update'
          put    'financial/v2/revenue_goals/:id',     to: 'financial/revenue_goals#update'
          post   'financial/v2/revenue_goals/upsert',  to: 'financial/revenue_goals#upsert',  as: 'financial_v2_revenue_goals_upsert'
          delete 'financial/v2/revenue_goals/:id',     to: 'financial/revenue_goals#destroy'

          # Gateway settings (Asaas)
          get   'financial/v2/gateway_setting', to: 'financial/gateway_settings#show',   as: 'financial_v2_gateway_setting'
          patch 'financial/v2/gateway_setting', to: 'financial/gateway_settings#update'
          put   'financial/v2/gateway_setting', to: 'financial/gateway_settings#update'

          # A Receber — Budgets
          get    'financial/v2/budgets',                              to: 'financial/budgets#index',  as: 'financial_v2_budgets'
          post   'financial/v2/budgets',                              to: 'financial/budgets#create'
          get    'financial/v2/budgets/:id',                          to: 'financial/budgets#show',   as: 'financial_v2_budget'
          patch  'financial/v2/budgets/:id',                          to: 'financial/budgets#update'
          put    'financial/v2/budgets/:id',                          to: 'financial/budgets#update'
          delete 'financial/v2/budgets/:id',                          to: 'financial/budgets#destroy'
          post   'financial/v2/budgets/:id/approve',                  to: 'financial/budgets#approve', as: 'financial_v2_budget_approve'
          post   'financial/v2/budgets/:id/cancel',                   to: 'financial/budgets#cancel',  as: 'financial_v2_budget_cancel'
          patch  'financial/v2/budgets/:id/update_installments',      to: 'financial/budgets#update_installments', as: 'financial_v2_budget_update_installments'
          post   'financial/v2/budgets/:id/simulate_plan',            to: 'financial/budgets#simulate_plan', as: 'financial_v2_budget_simulate_plan'

          # Installments
          get  'financial/v2/installments',                to: 'financial/installments#index', as: 'financial_v2_installments'
          # Variante agrupada por paciente — DEVE vir antes de `:id` pra evitar
          # que o router interprete `by_patient` como id.
          get  'financial/v2/installments/by_patient',     to: 'financial/installments#by_patient', as: 'financial_v2_installments_by_patient'
          get  'financial/v2/installments/:id',            to: 'financial/installments#show',  as: 'financial_v2_installment'
          post 'financial/v2/installments/:id/pay',   to: 'financial/installments#pay',   as: 'financial_v2_installment_pay'
          post 'financial/v2/installments/:id/refund', to: 'financial/installments#refund', as: 'financial_v2_installment_refund'
          post 'financial/v2/installments/:id/charge_whatsapp', to: 'financial/installments#charge_whatsapp', as: 'financial_v2_installment_charge_whatsapp'
          post 'financial/v2/installments/:id/upload_proof',    to: 'financial/installments#upload_proof',    as: 'financial_v2_installment_upload_proof'
          get  'financial/v2/installments/:id/proof_url',       to: 'financial/installments#proof_url',       as: 'financial_v2_installment_proof_url'

          # Payment receipts
          get    'financial/v2/payment_receipts',            to: 'financial/payment_receipts#index',   as: 'financial_v2_payment_receipts'
          post   'financial/v2/payment_receipts',            to: 'financial/payment_receipts#create'
          get    'financial/v2/payment_receipts/:id',        to: 'financial/payment_receipts#show',    as: 'financial_v2_payment_receipt'
          post   'financial/v2/payment_receipts/:id/refund', to: 'financial/payment_receipts#refund',  as: 'financial_v2_payment_receipt_refund'

          # Lançamentos manuais avulsos (canon F-25) + reclassificação em massa (F-28)
          get    'financial/v2/entries',                  to: 'financial/entries#index',           as: 'financial_v2_entries'
          post   'financial/v2/entries',                  to: 'financial/entries#create'
          get    'financial/v2/entries/:id',              to: 'financial/entries#show',            as: 'financial_v2_entry'
          patch  'financial/v2/entries/:id',              to: 'financial/entries#update'
          put    'financial/v2/entries/:id',              to: 'financial/entries#update'
          delete 'financial/v2/entries/:id',              to: 'financial/entries#destroy'
          post   'financial/v2/entries/bulk_reclassify',  to: 'financial/entries#bulk_reclassify', as: 'financial_v2_entries_bulk_reclassify'

          # A Pagar — Expenses
          get    'financial/v2/expenses',              to: 'financial/expenses#index',  as: 'financial_v2_expenses'
          post   'financial/v2/expenses',              to: 'financial/expenses#create'
          get    'financial/v2/expenses/:id',          to: 'financial/expenses#show',   as: 'financial_v2_expense'
          patch  'financial/v2/expenses/:id',          to: 'financial/expenses#update'
          put    'financial/v2/expenses/:id',          to: 'financial/expenses#update'
          delete 'financial/v2/expenses/:id',          to: 'financial/expenses#destroy'
          post   'financial/v2/expenses/:id/pay',      to: 'financial/expenses#pay',    as: 'financial_v2_expense_pay'
          post   'financial/v2/expenses/:id/reverse',  to: 'financial/expenses#reverse', as: 'financial_v2_expense_reverse'

          # Caixa físico
          get  'financial/v2/cash_registers',                 to: 'financial/cash_registers#index', as: 'financial_v2_cash_registers'
          get  'financial/v2/cash_registers/:id',             to: 'financial/cash_registers#show',  as: 'financial_v2_cash_register'
          post 'financial/v2/cash_registers/open',            to: 'financial/cash_registers#open',  as: 'financial_v2_cash_register_open'
          post 'financial/v2/cash_registers/:id/close',       to: 'financial/cash_registers#close', as: 'financial_v2_cash_register_close'
          post 'financial/v2/cash_registers/:id/reopen',      to: 'financial/cash_registers#reopen', as: 'financial_v2_cash_register_reopen'
          post 'financial/v2/cash_registers/:id/withdraw',    to: 'financial/cash_registers#withdraw', as: 'financial_v2_cash_register_withdraw'
          post 'financial/v2/cash_registers/:id/supplement',  to: 'financial/cash_registers#supplement', as: 'financial_v2_cash_register_supplement'

          # Crédito do paciente
          get  'financial/v2/patient_credits', to: 'financial/patient_credits#index',  as: 'financial_v2_patient_credits'
          post 'financial/v2/patient_credits', to: 'financial/patient_credits#create'

          # Auditoria
          get 'financial/v2/audit_logs',            to: 'financial/audit_logs#index',      as: 'financial_v2_audit_logs'
          get 'financial/v2/audit_logs/export_csv', to: 'financial/audit_logs#export_csv', as: 'financial_v2_audit_logs_export'

          # F-32 — listagem + disparo manual de backup. Cron diário roda via
          # Financial::BackupJob (config/schedule.yml).
          get  'financial/v2/backups',         to: 'financial/backups#index',   as: 'financial_v2_backups'
          post 'financial/v2/backups/run',     to: 'financial/backups#run',     as: 'financial_v2_backups_run'
          # destroy via POST (filename tem dots/pontos — POST + body evita
          # problemas de path matching com :filename na URL).
          post 'financial/v2/backups/destroy', to: 'financial/backups#destroy', as: 'financial_v2_backups_destroy'

          # F-33 §parte 2 — workflow LGPD de anonimização de pacientes.
          get    'financial/v2/lgpd_requests',              to: 'financial/lgpd_requests#index',   as: 'financial_v2_lgpd_requests'
          post   'financial/v2/lgpd_requests',              to: 'financial/lgpd_requests#create'
          get    'financial/v2/lgpd_requests/:id',          to: 'financial/lgpd_requests#show',    as: 'financial_v2_lgpd_request'
          post   'financial/v2/lgpd_requests/:id/approve',  to: 'financial/lgpd_requests#approve'
          post   'financial/v2/lgpd_requests/:id/reject',   to: 'financial/lgpd_requests#reject'
          post   'financial/v2/lgpd_requests/:id/execute',  to: 'financial/lgpd_requests#execute'
          post   'financial/v2/lgpd_requests/:id/cancel',   to: 'financial/lgpd_requests#cancel'

          # ─── Fase 2A (2026-05-22): Configurações canon expandidas ───
          # Payment methods (canon §3)
          get    'financial/v2/payment_methods',         to: 'financial/payment_methods#index',   as: 'financial_v2_payment_methods'
          post   'financial/v2/payment_methods',         to: 'financial/payment_methods#create'
          get    'financial/v2/payment_methods/:id',     to: 'financial/payment_methods#show',    as: 'financial_v2_payment_method'
          patch  'financial/v2/payment_methods/:id',     to: 'financial/payment_methods#update'
          put    'financial/v2/payment_methods/:id',     to: 'financial/payment_methods#update'
          delete 'financial/v2/payment_methods/:id',     to: 'financial/payment_methods#destroy'

          # Simula taxa vigente pra (amount × installments × on_date). Read-only,
          # usado pelo PaymentPlanWizardV2 antes de aprovar orçamento.
          get    'financial/v2/payment_methods/:id/simulate_fee', to: 'financial/payment_methods#simulate_fee', as: 'financial_v2_payment_method_simulate_fee'

          # Rename de provedor — propaga alias em todos os métodos do mesmo
          # (account_id, provider). POST coletivo (fora do RESTful padrão).
          # OK conviver com `:id`: nenhum método HTTP colide (POST extra path).
          post   'financial/v2/payment_methods/rename_provider',  to: 'financial/payment_methods#rename_provider',  as: 'financial_v2_payment_methods_rename_provider'
          # Bulk delete por provedor — soft-delete em todos os métodos do grupo
          # se nenhum tiver sido usado (lançamentos). UX: corrigir cadastro errado.
          post   'financial/v2/payment_methods/destroy_provider', to: 'financial/payment_methods#destroy_provider', as: 'financial_v2_payment_methods_destroy_provider'

          # Payment method fees — taxas versionadas (sem `update`, só create + deactivate)
          get    'financial/v2/payment_methods/:payment_method_id/fees',                to: 'financial/payment_method_fees#index',      as: 'financial_v2_payment_method_fees'
          post   'financial/v2/payment_methods/:payment_method_id/fees',                to: 'financial/payment_method_fees#create'
          get    'financial/v2/payment_methods/:payment_method_id/fees/:id',            to: 'financial/payment_method_fees#show',       as: 'financial_v2_payment_method_fee'
          post   'financial/v2/payment_methods/:payment_method_id/fees/:id/deactivate', to: 'financial/payment_method_fees#deactivate', as: 'financial_v2_payment_method_fee_deactivate'

          # Service pricings — 1-to-1 com AgendaService. URL usa agenda_service_id como :id
          # (não pricing.id) — operador pensa em "configurar preço do serviço X".
          get    'financial/v2/service_pricings',     to: 'financial/service_pricings#index',      as: 'financial_v2_service_pricings'
          get    'financial/v2/service_pricings/:id', to: 'financial/service_pricings#show',       as: 'financial_v2_service_pricing'
          put    'financial/v2/service_pricings/:id', to: 'financial/service_pricings#upsert'
          patch  'financial/v2/service_pricings/:id', to: 'financial/service_pricings#upsert'
          delete 'financial/v2/service_pricings/:id', to: 'financial/service_pricings#deactivate'

          # Agent profiles — 1-to-1 com User. URL usa user_id como :id.
          get    'financial/v2/agent_profiles',     to: 'financial/agent_profiles#index',      as: 'financial_v2_agent_profiles'
          get    'financial/v2/agent_profiles/:id', to: 'financial/agent_profiles#show',       as: 'financial_v2_agent_profile'
          put    'financial/v2/agent_profiles/:id', to: 'financial/agent_profiles#upsert'
          patch  'financial/v2/agent_profiles/:id', to: 'financial/agent_profiles#upsert'
          delete 'financial/v2/agent_profiles/:id', to: 'financial/agent_profiles#deactivate'

          # Period closures — fechamento contábil (ADMIN). Sem update/destroy — append-only.
          get   'financial/v2/period_closures',           to: 'financial/period_closures#index',  as: 'financial_v2_period_closures'
          post  'financial/v2/period_closures',           to: 'financial/period_closures#create'
          get   'financial/v2/period_closures/:id',       to: 'financial/period_closures#show',   as: 'financial_v2_period_closure'
          post  'financial/v2/period_closures/:id/reopen', to: 'financial/period_closures#reopen', as: 'financial_v2_period_closure_reopen'

          # Relatórios
          get 'financial/v2/reports/dre',                          to: 'financial/reports#dre',           as: 'financial_v2_report_dre'
          get 'financial/v2/reports/dre/category/:category_id',    to: 'financial/reports#dre_category',  as: 'financial_v2_report_dre_category'
          get 'financial/v2/reports/cash_flow',                    to: 'financial/reports#cash_flow',     as: 'financial_v2_report_cash_flow'
          get 'financial/v2/reports/dashboard',                    to: 'financial/reports#dashboard',     as: 'financial_v2_report_dashboard'
          get 'financial/v2/reports/commissions',                  to: 'financial/reports#commissions',   as: 'financial_v2_report_commissions'
          # Charts do Dashboard v2 (lêem das tabelas Financial::*) — fix do
          # dashboard v1 que lia de account_transactions e ignorava import F-10.
          get 'financial/v2/reports/cash_flow_chart',              to: 'financial/reports#cash_flow_chart',              as: 'financial_v2_report_cash_flow_chart'
          get 'financial/v2/reports/revenue_composition',          to: 'financial/reports#revenue_composition',          as: 'financial_v2_report_revenue_composition'
          get 'financial/v2/reports/delinquency_aging',            to: 'financial/reports#delinquency_aging',            as: 'financial_v2_report_delinquency_aging'
          get 'financial/v2/reports/revenue_by_professional',      to: 'financial/reports#revenue_by_professional',      as: 'financial_v2_report_revenue_by_professional'
          get 'financial/v2/reports/cash_flow_projection',         to: 'financial/reports#cash_flow_projection',         as: 'financial_v2_report_cash_flow_projection'
          get 'financial/v2/reports/delinquency_trend',            to: 'financial/reports#delinquency_trend',            as: 'financial_v2_report_delinquency_trend'
          get 'financial/v2/reports/kpi_sparklines',               to: 'financial/reports#kpi_sparklines',               as: 'financial_v2_report_kpi_sparklines'
          get 'financial/v2/reports/top_procedures',               to: 'financial/reports#top_procedures',               as: 'financial_v2_report_top_procedures'
          get 'financial/v2/reports/revenue_vs_goal',              to: 'financial/reports#revenue_vs_goal',              as: 'financial_v2_report_revenue_vs_goal'
          # F-30 — relatórios extras
          get 'financial/v2/reports/expenses_by_category',                       to: 'financial/reports#expenses_by_category',           as: 'financial_v2_report_expenses_by_category'
          get 'financial/v2/reports/expenses_by_category/category/:category_id', to: 'financial/reports#expenses_by_category_drilldown', as: 'financial_v2_report_expenses_by_category_drilldown'
          get 'financial/v2/reports/ticket_medio',                               to: 'financial/reports#ticket_medio',                   as: 'financial_v2_report_ticket_medio'
          get 'financial/v2/reports/convenio',                                   to: 'financial/reports#convenio',                       as: 'financial_v2_report_convenio'
          # Hub Relatórios — 5 endpoints novos (2026-05-23 — refator card-grid)
          get 'financial/v2/reports/revenue_by_procedure',                       to: 'financial/reports#revenue_by_procedure',           as: 'financial_v2_report_revenue_by_procedure'
          get 'financial/v2/reports/revenue_by_payment_method',                  to: 'financial/reports#revenue_by_payment_method',      as: 'financial_v2_report_revenue_by_payment_method'
          get 'financial/v2/reports/revenue_by_professional_table',              to: 'financial/reports#revenue_by_professional_table',  as: 'financial_v2_report_revenue_by_professional_table'
          get 'financial/v2/reports/account_statement',                          to: 'financial/reports#account_statement',              as: 'financial_v2_report_account_statement'
          get 'financial/v2/reports/goals_vs_actual',                            to: 'financial/reports#goals_vs_actual',                as: 'financial_v2_report_goals_vs_actual'
          # F-33 — exportação contador (CSV BR-friendly por tipo)
          get 'financial/v2/reports/accountant_export/preview',                  to: 'financial/reports#accountant_export_preview',      as: 'financial_v2_report_accountant_export_preview'
          get 'financial/v2/reports/accountant_export',                          to: 'financial/reports#accountant_export',              as: 'financial_v2_report_accountant_export'

          # Lançamentos de comissão (mark as paid + bulk) — canon F-29
          post 'financial/v2/commission_entries/bulk_pay', to: 'financial/commission_entries#bulk_pay', as: 'financial_v2_commission_entries_bulk_pay'
          post 'financial/v2/commission_entries/:id/pay',  to: 'financial/commission_entries#pay',      as: 'financial_v2_commission_entry_pay'

          # Endpoints "espelho" para a aba financeira do paciente — mesmo shape do
          # legacy `/patients/:id/financial_summary` e `/patients/:id/financial_timeline`
          # mas alimentados pelos modelos v2 (Financial::*). Permite migrar a aba
          # do paciente sem alterar UX (canon decisão 2026-05-08).
          get 'financial/v2/patients/:patient_id/summary',  to: 'financial/patient_summaries#show',  as: 'financial_v2_patient_summary'
          get 'financial/v2/patients/:patient_id/timeline', to: 'financial/patient_timelines#show',  as: 'financial_v2_patient_timeline'
          # =====================================================




          namespace :channels do
            resource :twilio_channel, only: [:create]
          end
          resources :conversations, only: [:index, :create, :show, :update, :destroy] do
            collection do
              get :meta
              get :search
              post :filter
            end
            scope module: :conversations do
              resources :messages, only: [:index, :create, :destroy, :update] do
                member do
                  post :translate
                  post :retry
                end
              end
              resources :assignments, only: [:create]
              resources :labels, only: [:create, :index]
              resource :participants, only: [:show, :create, :update, :destroy]
              resource :direct_uploads, only: [:create]
              resource :draft_messages, only: [:show, :update, :destroy]
            end
            member do
              post :mute
              post :unmute
              post :transcript
              post :toggle_status
              post :toggle_priority
              post :toggle_typing_status
              post :update_last_seen
              post :unread
              post :custom_attributes
              get :attachments
              get :inbox_assistant
              get :reporting_events if ChatwootApp.enterprise?
            end
          end

          resources :search, only: [:index] do
            collection do
              get :conversations
              get :messages
              get :contacts
              get :articles
            end
          end

          resources :companies, only: [:index, :show, :create, :update, :destroy] do
            collection do
              get :search
            end
          end
          resources :contacts, only: [:index, :show, :update, :create, :destroy] do
            collection do
              get :active
              get :search
              post :filter
              post :import
              post :export
            end
            member do
              get :contactable_inboxes
              post :destroy_custom_attributes
              delete :avatar
            end
            scope module: :contacts do
              resources :conversations, only: [:index]
              resources :contact_inboxes, only: [:create]
              resources :labels, only: [:create, :index]
              resources :notes
              post :call, on: :member, to: 'calls#create' if ChatwootApp.enterprise?
            end
          end
          resources :csat_survey_responses, only: [:index] do
            collection do
              get :metrics
              get :download
            end
            member do
              patch :update if ChatwootApp.enterprise?
            end
          end
          resources :applied_slas, only: [:index] do
            collection do
              get :metrics
              get :download
            end
          end
          resources :reporting_events, only: [:index] if ChatwootApp.enterprise?
          resources :custom_attribute_definitions, only: [:index, :show, :create, :update, :destroy]
          resources :custom_filters, only: [:index, :show, :create, :update, :destroy]
          resources :inboxes, only: [:index, :show, :create, :update, :destroy] do
            get :assignable_agents, on: :member
            get :campaigns, on: :member
            get :agent_bot, on: :member
            post :set_agent_bot, on: :member
            delete :avatar, on: :member
            post :sync_templates, on: :member
            get :health, on: :member
            if ChatwootApp.enterprise?
              resource :conference, only: %i[create destroy], controller: 'conference' do
                get :token, on: :member
              end
            end

            resource :csat_template, only: [:show, :create], controller: 'inbox_csat_templates'
          end

          resources :inbox_members, only: [:create, :show], param: :inbox_id do
            collection do
              delete :destroy
              patch :update
            end
          end
          resources :labels, only: [:index, :show, :create, :update, :destroy]

          resources :notifications, only: [:index, :update, :destroy] do
            collection do
              post :read_all
              get :unread_count
              post :destroy_all
            end
            member do
              post :snooze
              post :unread
            end
          end
          resource :notification_settings, only: [:show, :update]

          resources :teams do
            resources :team_members, only: [:index, :create] do
              collection do
                delete :destroy
                patch :update
              end
            end
          end

          # Assignment V2 Routes
          resources :assignment_policies do
            resources :inboxes, only: [:index, :create, :destroy], module: :assignment_policies
          end

          resources :inboxes, only: [] do
            resource :assignment_policy, only: [:show, :create, :destroy], module: :inboxes
          end

          namespace :twitter do
            resource :authorization, only: [:create]
          end

          namespace :microsoft do
            resource :authorization, only: [:create]
          end

          namespace :google do
            resource :authorization, only: [:create]
          end

          namespace :instagram do
            resource :authorization, only: [:create]
          end

          namespace :tiktok do
            resource :authorization, only: [:create]
          end

          namespace :notion do
            resource :authorization, only: [:create]
          end

          namespace :whatsapp do
            resource :authorization, only: [:create]
            # Rotas multi-instância — cada inbox tem seu próprio :inbox_id
            scope 'bridge/:inbox_id', as: 'bridge' do
              get    'qr',         to: 'bridges#qr'
              get    'status',     to: 'bridges#status'
              post   'disconnect', to: 'bridges#disconnect'
              post   'register',   to: 'bridges#register'
              post   'migrate',    to: 'bridges#migrate'
            end
            # "Iniciar conversa com número" estilo WhatsApp Web — valida no
            # WhatsApp e cria contato/conversa de uma vez.
            post 'start_conversation', to: 'start_conversations#create'
          end

          resources :webhooks, only: [:index, :create, :update, :destroy]
          namespace :integrations do
            resources :apps, only: [:index, :show]
            resources :hooks, only: [:show, :create, :update, :destroy] do
              member do
                post :process_event
              end
            end
            resource :slack, only: [:create, :update, :destroy], controller: 'slack' do
              member do
                get :list_all_channels
              end
            end
            resource :dyte, controller: 'dyte', only: [] do
              collection do
                post :create_a_meeting
                post :add_participant_to_meeting
              end
            end
            resource :shopify, controller: 'shopify', only: [:destroy] do
              collection do
                post :auth
                get :orders
              end
            end
            resource :linear, controller: 'linear', only: [] do
              collection do
                delete :destroy
                get :teams
                get :team_entities
                post :create_issue
                post :link_issue
                post :unlink_issue
                get :search_issue
                get :linked_issues
              end
            end
            resource :notion, controller: 'notion', only: [] do
              collection do
                delete :destroy
              end
            end
          end
          resources :working_hours, only: [:update]

          resources :portals do
            member do
              patch :archive
              delete :logo
              post :send_instructions
              get :ssl_status
            end
            resources :categories
            resources :articles do
              post :reorder, on: :collection
            end
          end

          resources :upload, only: [:create]
          resource :beclinic_permissions, only: [:show], controller: 'beclinic_permissions'
          # Busca híbrida (conversas + contatos) usada pelo input "Buscar por contato..."
          # da lista de conversas. Estende o módulo de busca atual sem mexer em core.
          get 'beclinic_unified_search', to: 'beclinic_unified_search#index'
        end
      end
      # end of account scoped api routes
      # ----------------------------------

      namespace :integrations do
        resources :webhooks, only: [:create]
      end

      # Frontend API endpoint to trigger SAML authentication flow
      post 'auth/saml_login', to: 'auth#saml_login'

      resource :profile, only: [:show, :update] do
        delete :avatar, on: :collection
        member do
          post :availability
          post :auto_offline
          put :set_active_account
          post :resend_confirmation
          post :reset_access_token
        end

        # MFA routes
        scope module: 'profile' do
          resource :mfa, controller: 'mfa', only: [:show, :create, :destroy] do
            post :verify
            post :backup_codes
          end
        end
      end

      resource :notification_subscriptions, only: [:create, :destroy]

      namespace :widget do
        resource :direct_uploads, only: [:create]
        resource :config, only: [:create]
        resources :campaigns, only: [:index]
        resources :events, only: [:create]
        resources :messages, only: [:index, :create, :update]
        resources :conversations, only: [:index, :create] do
          collection do
            post :destroy_custom_attributes
            post :set_custom_attributes
            post :update_last_seen
            post :toggle_typing
            post :transcript
            get  :toggle_status
          end
        end
        resource :contact, only: [:show, :update] do
          collection do
            post :destroy_custom_attributes
            patch :set_user
          end
        end
        resources :inbox_members, only: [:index]
        resources :labels, only: [:create, :destroy]
        namespace :integrations do
          resource :dyte, controller: 'dyte', only: [] do
            collection do
              post :add_participant_to_meeting
            end
          end
        end
      end
    end

    namespace :v2 do
      resources :accounts, only: [:create] do
        scope module: :accounts do
          resources :summary_reports, only: [] do
            collection do
              get :agent
              get :team
              get :inbox
              get :label
              get :channel
            end
          end
          resources :reports, only: [:index] do
            collection do
              get :summary
              get :bot_summary
              get :agents
              get :inboxes
              get :labels
              get :teams
              get :conversations
              get :conversations_summary
              get :conversation_traffic
              get :bot_metrics
              get :inbox_label_matrix
              get :first_response_time_distribution
              get :outgoing_messages_count
            end
          end
          resource :year_in_review, only: [:show]
          resources :live_reports, only: [] do
            collection do
              get :conversation_metrics
              get :grouped_conversation_metrics
            end
          end
        end
      end
    end
  end

  if ChatwootApp.enterprise?
    namespace :enterprise, defaults: { format: 'json' } do
      namespace :api do
        namespace :v1 do
          resources :accounts do
            member do
              post :checkout
              post :subscription
              get :limits
              post :toggle_deletion
              post :topup_checkout
            end
          end
        end
      end

      post 'webhooks/stripe', to: 'webhooks/stripe#process_payload'
      post 'webhooks/firecrawl', to: 'webhooks/firecrawl#process_payload'
    end
  end

  # ----------------------------------------------------------------------
  # Routes for platform APIs
  namespace :platform, defaults: { format: 'json' } do
    namespace :api do
      namespace :v1 do
        resources :users, only: [:create, :show, :update, :destroy] do
          member do
            get :login
            post :token
          end
        end
        resources :agent_bots, only: [:index, :create, :show, :update, :destroy] do
          delete :avatar, on: :member
        end
        resources :accounts, only: [:index, :create, :show, :update, :destroy] do
          resources :account_users, only: [:index, :create] do
            collection do
              delete :destroy
            end
          end
        end
      end
    end
  end

  # ----------------------------------------------------------------------
  # Página HTML pública para assinatura remota — link compartilhado que o
  # paciente abre direto no celular (canvas de assinatura + confirmação).
  # FORA do namespace `:public` JSON porque renderiza HTML, não JSON.
  # O endpoint JSON correspondente (que esta página chama via fetch) está
  # em `/public/api/v1/session_log_signatures/:remote_token`.
  get '/public/sessao/:token',
      to: 'public_session_signatures#show',
      as: :public_session_signature

  # ----------------------------------------------------------------------
  # Routes for inbox APIs Exposed to contacts
  namespace :public, defaults: { format: 'json' } do
    namespace :api do
      namespace :v1 do
        resources :inboxes do
          scope module: :inboxes do
            resources :contacts, only: [:create, :show, :update] do
              resources :conversations, only: [:index, :create, :show] do
                member do
                  post :toggle_status
                  post :toggle_typing
                  post :update_last_seen
                end

                resources :messages, only: [:index, :create, :update]
              end
            end
          end
        end

        resources :csat_survey, only: [:show, :update]

        namespace :agenda do
          get ':public_id', to: 'public#show'
          get ':public_id/services', to: 'public#services'
          get ':public_id/slots', to: 'public#slots'
          # Auditoria 9.13: variante batch — recebe `from` e `to` (YYYY-MM-DD)
          # e retorna `{ slots: { "YYYY-MM-DD": [...], ... } }`. Reduz N round-trips
          # ao navegar mês a mês para 1.
          get ':public_id/slots_range', to: 'public#slots_range'
          post ':public_id/book', to: 'public#book'
          # Auditoria 9.11: paciente cancela seu próprio agendamento via link
          # com token assinado. NÃO depende de `:public_id` porque o token já
          # carrega account_id + event_id (não-falsificável sem secret_key_base).
          get  'booking/:token',        to: 'public#booking_show', as: :agenda_booking_show
          post 'booking/:token/cancel', to: 'public#booking_cancel', as: :agenda_booking_cancel
        end

        # Assinatura remota de SessionLog pelo paciente (acesso por token único)
        resources :session_log_signatures,
                  only: [:show, :update],
                  param: :remote_token

        resources :help_articles, only: [:index, :show] do
          collection do
            get :categories
            get :faqs
          end
        end
      end
    end
  end

  get 'hc/:slug', to: 'public/api/v1/portals#show'
  get 'hc/:slug/sitemap.xml', to: 'public/api/v1/portals#sitemap'
  get 'hc/:slug/:locale', to: 'public/api/v1/portals#show'
  get 'hc/:slug/:locale/articles', to: 'public/api/v1/portals/articles#index'
  get 'hc/:slug/:locale/categories', to: 'public/api/v1/portals/categories#index'
  get 'hc/:slug/:locale/categories/:category_slug', to: 'public/api/v1/portals/categories#show'
  get 'hc/:slug/:locale/categories/:category_slug/articles', to: 'public/api/v1/portals/articles#index'
  get 'hc/:slug/articles/:article_slug.png', to: 'public/api/v1/portals/articles#tracking_pixel'
  get 'hc/:slug/articles/:article_slug', to: 'public/api/v1/portals/articles#show'

  # ----------------------------------------------------------------------
  # Used in mailer templates
  resource :app, only: [:index] do
    resources :accounts do
      resources :conversations, only: [:show]
    end
  end

  # ----------------------------------------------------------------------
  # Routes for channel integrations
  mount Facebook::Messenger::Server, at: 'bot'
  get 'webhooks/twitter', to: 'api/v1/webhooks#twitter_crc'
  post 'webhooks/twitter', to: 'api/v1/webhooks#twitter_events'
  post 'webhooks/line/:line_channel_id', to: 'webhooks/line#process_payload'
  post 'webhooks/telegram/:bot_token', to: 'webhooks/telegram#process_payload'
  post 'webhooks/sms/:phone_number', to: 'webhooks/sms#process_payload'
  get 'webhooks/whatsapp/:phone_number', to: 'webhooks/whatsapp#verify'
  post 'webhooks/whatsapp/:phone_number', to: 'webhooks/whatsapp#process_payload'
  post 'webhooks/whatsapp_qr/:phone_number', to: 'webhooks/whatsapp_qr#process_payload'
  get 'webhooks/instagram', to: 'webhooks/instagram#verify'
  post 'webhooks/instagram', to: 'webhooks/instagram#events'
  post 'webhooks/tiktok', to: 'webhooks/tiktok#events'
  post 'webhooks/shopify', to: 'webhooks/shopify#events'

  # Financeiro v2 — webhook do gateway Asaas. Verificação por header asaas-access-token.
  post 'webhooks/financial/asaas', to: 'webhooks/financial/asaas#receive'

  namespace :twitter do
    resource :callback, only: [:show]
  end

  namespace :linear do
    resource :callback, only: [:show]
  end

  namespace :shopify do
    resource :callback, only: [:show]
  end

  namespace :twilio do
    resources :callback, only: [:create]
    resources :delivery_status, only: [:create]

    if ChatwootApp.enterprise?
      post 'voice/call/:phone', to: 'voice#call_twiml', as: :voice_call
      post 'voice/status/:phone', to: 'voice#status', as: :voice_status
      post 'voice/conference_status/:phone', to: 'voice#conference_status', as: :voice_conference_status
    end
  end

  get 'microsoft/callback', to: 'microsoft/callbacks#show'
  get 'google/callback', to: 'google/callbacks#show'
  get 'instagram/callback', to: 'instagram/callbacks#show'
  get 'tiktok/callback', to: 'tiktok/callbacks#show'
  get 'notion/callback', to: 'notion/callbacks#show'
  # ----------------------------------------------------------------------
  # Routes for external service verifications
  get '.well-known/assetlinks.json' => 'android_app#assetlinks'
  get '.well-known/apple-app-site-association' => 'apple_app#site_association'
  get '.well-known/microsoft-identity-association.json' => 'microsoft#identity_association'
  get '.well-known/cf-custom-hostname-challenge/:id', to: 'custom_domains#verify'

  # ----------------------------------------------------------------------
  # Internal Monitoring Routes
  require 'sidekiq/web'
  require 'sidekiq/cron/web'

  devise_for :super_admins, path: 'super_admin', controllers: { sessions: 'super_admin/devise/sessions' }
  devise_scope :super_admin do
    get 'super_admin/logout', to: 'super_admin/devise/sessions#destroy'
    namespace :super_admin do
      root to: 'dashboard#index'

      resource :app_config, only: [:show, :create]

      # order of resources affect the order of sidebar navigation in super admin
      resources :accounts, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
        post :seed, on: :member
        post :reset_cache, on: :member
        member do
          get  :bea
          patch :bea, action: :update_bea
        end
        resources :ai_agent_documents, only: [:index, :create, :destroy], controller: 'ai_agent_documents'
      end
      resources :users, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
        delete :avatar, on: :member, action: :destroy_avatar
      end

      resources :access_tokens, only: [:index, :show]
      resources :installation_configs, only: [:index, :new, :create, :show, :edit, :update]
      resources :agent_bots, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
        delete :avatar, on: :member, action: :destroy_avatar
      end
      resources :platform_apps, only: [:index, :new, :create, :show, :edit, :update, :destroy]
      resource :instance_status, only: [:show]

      resource :settings, only: [:show] do
        get :refresh, on: :collection
      end

      # resources that doesn't appear in primary navigation in super admin
      resources :account_users, only: [:new, :create, :show, :destroy]

      # ── Beclinic / Klivy custom modules ─────────────────────────────────────
      # Módulos customizados ficam agrupados no fim da sidebar do Super Admin
      # para separar visualmente do que é Chatwoot OSS.

      # Central de Ajuda — plugin `ajuda` (CMS de artigos/categorias/FAQs).
      resources :help_categories, only: [:index, :new, :create, :show, :edit, :update, :destroy]
      resources :help_articles, only: [:index, :new, :create, :show, :edit, :update, :destroy]
      resources :help_faqs, only: [:index, :new, :create, :show, :edit, :update, :destroy]

      # Widget de suporte (bubble do canto inferior direito) — UI dedicada
      # com 3 campos (enabled/token/url). Lê e grava em InstallationConfig.
      resource :klivy_widget, only: [:show, :update]

      # Bea — agente de IA da Klivy. UI dedicada para o super admin
      # configurar provider (OpenAI/Gemini), modelos e chaves. Lê/grava
      # em InstallationConfig (CAPTAIN_*).
      resource :bea, only: [:show, :update], controller: 'bea'

      # Migração de dados de outras plataformas (Clinicorp etc.) — plugin migration.
      resources :migrations, only: [:index, :create, :show] do
        collection do
          post :preview
          # Lista usuários da conta pra mapear DentistName→user_id na importação
          # de TreatmentOperation. Usado pelo passo de mapeamento na UI.
          get  :professional_users
          # Lista PaymentMethods + BankAccounts ativos da conta pra mapear
          # "kind Clinicorp → PaymentMethod Klivy" no F-10 Financeiro.
          get  :payment_methods
        end
      end
    end

    authenticated :super_admin do
      mount Sidekiq::Web => '/monitoring/sidekiq'
    end
  end

  namespace :installation do
    get 'onboarding', to: 'onboarding#index'
    post 'onboarding', to: 'onboarding#create'
  end

  # ---------------------------------------------------------------------
  # Routes for swagger docs
  get '/docs/plugins', to: 'swagger#respond', defaults: { path: 'plugins_scalar.html' }
  get '/docs/core', to: 'swagger#respond', defaults: { path: 'core_scalar.html' }
  get '/swagger/*path', to: 'swagger#respond'
  get '/swagger', to: 'swagger#respond'

  # ----------------------------------------------------------------------
  # Routes for testing
  resources :widget_tests, only: [:index] unless Rails.env.production?

  mount Billing::Engine, at: '/'

  # Plugin document_templates (editor TipTap + biblioteca Klivy + PDF Grover).
  # Engine não-isolada: suas rotas vivem em plugins/document_templates/config/routes.rb
  # e expõem /api/v1/accounts/:account_id/document_templates(+folders).
  mount DocumentTemplates::Engine, at: '/'

  # Plugin signatures (assinatura eletrônica: Mock em dev, Clicksign em prod).
  # Expõe /api/v1/accounts/:account_id/signature_requests + webhook público
  # POST /webhooks/clicksign. Componentes embutidos nas abas do paciente.
  mount Signatures::Engine, at: '/'

  # Plugin telemed (teleconsulta LiveKit + transcrição + evolução SOAP por IA).
  # Expõe /api/v1/accounts/:account_id/telemed/*, /api/v1/patient_portal/telemed/*
  # e o webhook público POST /webhooks/livekit/egress.
  mount Telemed::Engine, at: '/'
end
