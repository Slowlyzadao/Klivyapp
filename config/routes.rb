Rails.application.routes.draw do
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
  end

  get '/health', to: 'health#show'
  get '/api', to: 'api#index'
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
          # AiAgent (Bea) plugin — user-facing knowledge base endpoints.
          # Controllers + policies + views live in plugins/ai_agent/.
          # The fully-qualified controller path keeps the plugin namespace
          # intact (AiAgent::Api::V1::Accounts::DocumentsController).
          resources :ai_agent_documents,
                    path: 'ai_agent/documents',
                    only: [:index, :show, :create, :destroy],
                    controller: '/ai_agent/api/v1/accounts/documents'
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

          # InternalChat plugin — chat interno entre profissionais.
          # Controllers, models, policies em plugins/internal_chat/.
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
                end
              end

              # Bloco 3: Plano de Tratamento + Sessões
              resources :treatment_plans, only: [:index, :show, :create, :update, :destroy] do
                member do
                  patch :approve
                  patch :cancel
                end
                resources :treatment_items, only: [:index, :show, :create, :update, :destroy]
              end
              resources :session_logs, only: [:index, :show, :create, :destroy]

              # Bloco 4: Financeiro do Paciente
              get :financial_summary, to: 'transactions#financial_summary'
              resources :financial_estimates, only: [:index, :show, :create, :update, :destroy] do
                member do
                  patch :approve
                  patch :cancel
                end
              end
              resources :transactions, only: [:index, :show, :create, :destroy] do
                member do
                  patch :pay
                  post :refund
                  post :charge_whatsapp
                  post :upload_proof
                  get :proof_url
                end
              end

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
              resources :patient_appointments, only: [:index, :show, :create], path: 'appointments',
                                               controller: 'appointments' do
                member do
                  patch :reschedule
                  patch :cancel
                  patch :no_show
                end
              end
              resource :recall, only: [:create], controller: 'recalls'
              resources :timeline, only: [:index], controller: 'timeline'
            end
          end

          resources :form_templates, only: [:index, :show, :create, :update, :destroy]
          # =====================================================

          resources :agenda_events, only: [:index, :create, :show, :update, :destroy]
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
            end
          end
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

          # =====================================================
          # Módulo Financeiro Central — Onda 1A
          # =====================================================
          # Dashboard
          get  'financial/dashboard', to: 'financial_dashboard#show'

          # Transactions
          get    'financial/transactions',          to: 'account_transactions#index'
          post   'financial/transactions',          to: 'account_transactions#create'
          get    'financial/transactions/:id',      to: 'account_transactions#show'
          patch  'financial/transactions/:id',      to: 'account_transactions#update'
          put    'financial/transactions/:id',      to: 'account_transactions#update'
          delete 'financial/transactions/:id',      to: 'account_transactions#destroy'
          post   'financial/transactions/:id/receive', to: 'account_transactions#receive'

          # Categories
          get    'financial/categories',     to: 'financial_categories#index'
          post   'financial/categories',     to: 'financial_categories#create'
          get    'financial/categories/:id', to: 'financial_categories#show'
          patch  'financial/categories/:id', to: 'financial_categories#update'
          put    'financial/categories/:id', to: 'financial_categories#update'
          delete 'financial/categories/:id', to: 'financial_categories#destroy'

          # Bank Accounts
          get    'financial/bank_accounts',     to: 'bank_accounts#index'
          post   'financial/bank_accounts',     to: 'bank_accounts#create'
          get    'financial/bank_accounts/:id', to: 'bank_accounts#show'
          patch  'financial/bank_accounts/:id', to: 'bank_accounts#update'
          put    'financial/bank_accounts/:id', to: 'bank_accounts#update'
          delete 'financial/bank_accounts/:id', to: 'bank_accounts#destroy'

          # Cash Registers
          get    'financial/cash_registers',     to: 'cash_registers#index'
          post   'financial/cash_registers',     to: 'cash_registers#create'
          get    'financial/cash_registers/:id', to: 'cash_registers#show'
          patch  'financial/cash_registers/:id', to: 'cash_registers#update'
          put    'financial/cash_registers/:id', to: 'cash_registers#update'
          delete 'financial/cash_registers/:id', to: 'cash_registers#destroy'

          # Commission Rules
          get    'financial/commission_rules',     to: 'commission_rules#index'
          post   'financial/commission_rules',     to: 'commission_rules#create'
          patch  'financial/commission_rules/:id', to: 'commission_rules#update'
          put    'financial/commission_rules/:id', to: 'commission_rules#update'
          delete 'financial/commission_rules/:id', to: 'commission_rules#destroy'

          # Recurring Expenses
          get    'financial/recurring_expenses',     to: 'recurring_expenses#index'
          post   'financial/recurring_expenses',     to: 'recurring_expenses#create'
          get    'financial/recurring_expenses/:id', to: 'recurring_expenses#show'
          patch  'financial/recurring_expenses/:id', to: 'recurring_expenses#update'
          put    'financial/recurring_expenses/:id', to: 'recurring_expenses#update'
          delete 'financial/recurring_expenses/:id', to: 'recurring_expenses#destroy'
          # Financial Goals
          get    'financial/goals',     to: 'financial_goals#show'
          patch  'financial/goals',     to: 'financial_goals#update'
          put    'financial/goals',     to: 'financial_goals#update'

          # Reports
          get 'financial/reports/cash_flow',         to: 'financial_reports#cash_flow'
          get 'financial/reports/monthly_summary',    to: 'financial_reports#monthly_summary'
          get 'financial/reports/dre',               to: 'financial_reports#dre'
          get 'financial/reports/commissions',       to: 'financial_reports#commissions'
          get 'financial/reports/insurance',         to: 'financial_reports#insurance'
          get 'financial/reports/average_ticket',    to: 'financial_reports#average_ticket'
          # Gráficos Onda 1
          get 'financial/reports/cash_flow_chart',   to: 'financial_reports#cash_flow_chart'
          get 'financial/dashboard/kpis',            to: 'financial_dashboard#dashboard_kpis'
          get 'financial/dashboard/revenue_goal',    to: 'financial_dashboard#revenue_goal'
          # Gráficos Onda 2
          get 'financial/reports/cash_flow_projection',        to: 'financial_reports#cash_flow_projection'
          get 'financial/reports/receivables_forecast',        to: 'financial_reports#receivables_forecast'
          get 'financial/reports/delinquency_aging',           to: 'financial_reports#delinquency_aging'
          get 'financial/reports/delinquency_trend',           to: 'financial_reports#delinquency_trend'
          get 'financial/reports/delinquency_by_professional', to: 'financial_reports#delinquency_by_professional'
          # Gráficos Onda 3
          get 'financial/reports/dre_waterfall',        to: 'financial_reports#dre_waterfall'
          get 'financial/reports/ticket_trend',         to: 'financial_reports#ticket_trend'
          get 'financial/reports/revenue_by_professional', to: 'financial_reports#revenue_by_professional'
          get 'financial/reports/revenue_composition',  to: 'financial_reports#revenue_composition'
          get 'financial/reports/expenses_by_category', to: 'financial_reports#expenses_by_category'
          get 'financial/reports/cost_structure',       to: 'financial_reports#cost_structure'
          # Gráficos Onda 4
          get 'financial/reports/conversion_funnel',    to: 'financial_reports#conversion_funnel'
          get 'financial/reports/agenda_heatmap',       to: 'financial_reports#agenda_heatmap'
          get 'financial/reports/patient_retention',    to: 'financial_reports#patient_retention'

          # PDF Exports
          get 'financial/pdfs/cash_flow',           to: 'financial_pdfs#cash_flow'
          get 'financial/pdfs/receivables',         to: 'financial_pdfs#receivables'
          get 'financial/pdfs/payables',            to: 'financial_pdfs#payables'
          get 'financial/pdfs/dre',                 to: 'financial_pdfs#dre'
          get 'financial/pdfs/commissions',         to: 'financial_pdfs#commissions'
          get 'financial/pdfs/expenses_by_category', to: 'financial_pdfs#expenses_by_category'
          get 'financial/pdfs/insurance',           to: 'financial_pdfs#insurance'
          get 'financial/pdfs/average_ticket',      to: 'financial_pdfs#average_ticket'
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
          get ':public_id/slots', to: 'public#slots'
          post ':public_id/book', to: 'public#book'
        end

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
  # Bea health endpoint (público, pro uptime checker externo).
  # 200 ok/degraded/idle; 503 down. Não autenticado por design.
  get 'api/v1/ai_agent/health', to: 'api/v1/ai_agent/health#show'

  # Bea feedback público (👍/👎 do paciente sobre uma resposta).
  # Autenticação via HMAC token gerado por TokenSigner — sem login.
  post 'api/v1/ai_agent/feedback', to: 'api/v1/ai_agent/feedbacks#create'

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
        end
      end
    end

    authenticated :super_admin do
      mount Sidekiq::Web => '/monitoring/sidekiq'
    end
  end

  # BeClinicCore: manual owner promotion panel (see plugins/beclinic_core).
  # Deliberately NOT under the `super_admin/` path or controller tree:
  # Administrate's Namespace.resources scans all routes whose controller
  # starts with "super_admin/" and tries to render dashboards for each —
  # any unknown path there breaks the admin navigation. This feature uses
  # its own minimal layout and authenticates via super_admin Devise session.
  namespace :beclinic_admin do
    resources :owners, only: [:index, :show] do
      post :promote, on: :member
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
end
