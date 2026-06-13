module Telemed
  # Plugin de Telemedicina — gravação audio-only (LiveKit), transcrição (Whisper)
  # e geração de evolução SOAP via LLM (Claude/OpenAI).
  #
  # Decisão arquitetural: sem `isolate_namespace` (mesmo padrão dos outros plugins
  # Klivy — patient_portal, agenda). Models vivem no namespace global
  # (`TelemedRecording`, `ProposedEvolution`), services e jobs em `module Telemed`.
  # Engine só serve pra autoload do diretório + injetar associações no core via
  # `to_prepare`.
  class Engine < ::Rails::Engine
    engine_name 'telemed'

    config.to_prepare do
      # Antes da extração, essas associações viviam em patient_portal/engine.rb.
      # Movidas pra cá porque o ownership é deste plugin — patient_portal não
      # precisa conhecer telemedicina pra funcionar.
      if defined?(Account)
        Account.class_eval do
          has_many :telemed_recordings, class_name: 'TelemedRecording', dependent: :destroy_async
          has_many :telemed_consents,   class_name: 'TelemedConsent',   dependent: :destroy_async
        end
      end

      if defined?(Patient)
        Patient.class_eval do
          has_many :telemed_consents, class_name: 'TelemedConsent', dependent: :destroy_async
        end
      end

      if defined?(AgendaEvent)
        AgendaEvent.class_eval do
          # Uma teleconsulta pode ter N gravações (reprocessamento, retries).
          # UI consome a mais recente; histórico serve auditoria.
          has_many :telemed_recordings, class_name: 'TelemedRecording', dependent: :destroy_async
        end
      end

      # Audit Fase 4 (#41) — REMOVIDO `ClinicalNote.class_eval { belongs_to
      # :proposed_evolution }`. Antes criava acoplamento bidirecional
      # core ↔ plugin: se o plugin telemed era desabilitado, ClinicalNote
      # carregava uma associação pra constant inexistente. O FK column
      # `clinical_notes.proposed_evolution_id` permanece (auditoria CFM),
      # mas a navegação reversa agora é via query: quem precisar da
      # proposta original a partir de uma nota usa
      # `ProposedEvolution.find_by(clinical_note_id: note.id)` em vez de
      # `note.proposed_evolution`. Nenhum código no projeto usava a
      # associação na época da remoção (verificado por grep).
    end
  end
end
