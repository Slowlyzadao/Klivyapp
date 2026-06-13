# Aplica um preset (PRD §4.5) em `PatientPortalSetting`. MVP só entrega
# `autonomy_guided`; demais ficam como stubs até a Fase 2.
#
# O service faz **deep merge**: valores já customizados pela clínica são
# preservados (override do paciente vence; preset preenche o resto).
module PatientPortal
  class PresetApplier
    PRESETS = {
      autonomy_guided: {
        scheduling: {
          scheduling_mode: 'request_only',
          first_visit_mode: 'request_only',
          min_lead_time_hours: 24,
          max_future_days: 60,
          allow_same_day: false,
          block_if_overdue: false,
          block_if_pending_consent: true,
          require_anamnesis_before_scheduling: false,
          max_active_appointments: nil
        },
        rescheduling: {
          reschedule_mode: 'request_only',
          reschedule_window_hours: 24,
          max_reschedules_per_event: 2,
          cancel_mode: 'self_within_window',
          cancel_window_hours: 24
        },
        financial: {
          payment_methods: [],         # MVP read-only — pagamento entra na F2
          show_paid_history: true,
          installment_max: 1,
          block_portal_if_overdue_days: 0
        },
        documents: {
          document_types_exposed: %w[atestado encaminhamento receita recibo plano_tratamento],
          allow_document_request: true,
          requestable_document_types: %w[atestado_2via recibo_2via],
          auto_approve_simple_requests: true,
          document_link_ttl_minutes: 15,
          share_via_external_link: true,
          allow_self_upload: false
        },
        clinical: {
          clinical_visibility: 'none',
          expose_clinical_note_fields: [],
          expose_treatment_plan: false,
          expose_session_logs: false,
          expose_anamnesis_to_patient: false,
          prescription_visibility: 'active_only'
        },
        messaging: {
          messaging_enabled: true,
          allow_direct_professional: false,
          urgent_keyword_list: %w[urgência urgente emergência sangue dor\ forte],
          urgent_action: 'force_phone'
        },
        engagement: {
          recall_enabled: true,
          recall_after_months: 6,
          recall_max_per_year: 2,
          nps_enabled: false,
          referral_program_enabled: false
        },
        invite: {
          auto_invite_on_create: false,
          invite_message_template: 'Olá {{patient_name}}, a {{clinic_name}} criou seu acesso ao portal. Entre em pacientes.klivy.app',
          welcome_message_post_first_login: 'Seja bem-vindo(a)!'
        },
        business_hours: {
          mon: { open: '08:00', close: '18:00' },
          tue: { open: '08:00', close: '18:00' },
          wed: { open: '08:00', close: '18:00' },
          thu: { open: '08:00', close: '18:00' },
          fri: { open: '08:00', close: '18:00' }
        },
        notification_events_enabled: {
          appointment_confirmation: true,
          appointment_reminder_24h: true,
          new_document: true,
          new_charge: true,
          recall: true,
          consent_expiring: true
        }
      }
    }.with_indifferent_access.freeze

    def initialize(setting:, preset_key:)
      @setting = setting
      @key     = preset_key.to_s
    end

    def call
      raise ArgumentError, "Preset desconhecido: #{@key}" unless PRESETS.key?(@key)
      raise ArgumentError, 'Preset disponível apenas na Fase 2.' if Rails.env.production? && @key != 'autonomy_guided'

      preset = PRESETS[@key]
      @setting.active_preset = @key
      PRESETS[@key].each do |category, values|
        existing = @setting.public_send(category) || {}
        merged   = values.merge(existing) # existing wins — preset só preenche faltantes
        @setting.public_send("#{category}=", merged)
      end
      @setting.save!
      @setting
    end
  end
end
