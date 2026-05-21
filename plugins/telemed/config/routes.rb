Telemed::Engine.routes.draw do
  # ─── Webhooks externos (LiveKit Egress) ─────────────────────────────────────
  # LiveKit assina via JWT no header Authorization. Validação no controller.
  post '/webhooks/livekit/egress', to: 'webhooks/livekit/egress#process_payload'

  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      # ─── API admin (clínica/dentista) ────────────────────────────────────────
      # Convenção Klivy: rotas administrativas vivem sob /accounts/:account_id/...
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :telemed do
            # Lista + detalhe + ações (ex-teleconsultas_controller). Pundit
            # reaproveita AgendaEventPolicy (quem vê na agenda vê aqui).
            resources :teleconsultas, only: [:index, :show] do
              collection do
                get :counts           # contagens por aba (upcoming/in_progress/finished/no_show)
              end
              member do
                get  :recording_url   # signed URL R2 (TTL 5min)
                post :retranscribe    # re-roda TranscribeRecordingJob
                post :reevolve        # re-roda GenerateEvolutionJob
              end
            end

            # Proposta de evolução gerada pela IA. update edita SOAP; approve
            # cria ClinicalNote(source='telemed_ai'); reject descarta.
            resources :proposed_evolutions, only: [:update] do
              member do
                post :approve
                post :reject
              end
            end

            # Sessão (token JWT pro dentista entrar na sala LiveKit) e eventos
            # (joined/left → automação de status). Ex-actions de agenda_events_controller.
            resources :sessions, only: [:create] do
              collection do
                post :event
              end
            end
          end
        end
      end

      # ─── API paciente (consumida pelo SPA pacientes.*) ──────────────────────
      # Antes morava em patient_portal/appointments_controller — extraída pra cá.
      namespace :patient_portal do
        namespace :telemed do
          # Token JWT + reportagem de joined/left pro lado paciente. JWT carrega
          # account_id, então não precisa de :account_id no path.
          resources :sessions, only: [:create] do
            collection do
              post :event
            end
          end
        end
      end
    end
  end
end
