module PatientPortal
  class Engine < ::Rails::Engine
    # Não usamos isolate_namespace porque os modelos (PatientPortalSetting etc.)
    # e controllers (Api::V1::PatientPortal::...) vivem no namespace global —
    # mesmo padrão que `plugins/agenda` segue. Engine só serve pra autoload
    # do diretório + inject de associações via to_prepare.
    engine_name 'patient_portal'

    config.to_prepare do
      # Injeção nos modelos do core sem editar nenhum arquivo do Chatwoot/Klivy.
      Account.class_eval do
        has_one  :patient_portal_setting, class_name: 'PatientPortalSetting', dependent: :destroy
        has_many :professional_portal_settings, class_name: 'ProfessionalPortalSetting', dependent: :destroy
        has_many :patient_portal_otps, class_name: 'PatientPortalOtp', dependent: :destroy_async
        has_many :patient_portal_sessions, class_name: 'PatientPortalSession', dependent: :destroy_async
        has_many :patient_portal_access_logs, class_name: 'PatientPortalAccessLog', dependent: :destroy_async
        has_many :portal_invites, class_name: 'PortalInvite', dependent: :destroy_async
        # Telemed: a associação `has_many :telemed_recordings` foi movida para
        # plugins/telemed/lib/telemed/engine.rb. Patient portal não conhece
        # telemedicina diretamente.
      end

      Patient.class_eval do
        has_many :patient_portal_sessions, class_name: 'PatientPortalSession', dependent: :destroy_async
        has_many :patient_portal_access_logs, class_name: 'PatientPortalAccessLog', dependent: :destroy_async
        has_many :portal_invites, class_name: 'PortalInvite', dependent: :destroy_async

        # portal_status: 'active' | 'suspended_temporary' | 'suspended_permanent' | 'restricted'
        # Migration garante NOT NULL DEFAULT 'active'.
        def portal_active?
          ps = self[:portal_status] || 'active'
          return true if ps == 'active'
          return false if ps == 'suspended_permanent'

          if ps == 'suspended_temporary'
            self[:portal_suspended_until].blank? || self[:portal_suspended_until] > Time.current
          else
            true # 'restricted' loga, mas tem acesso parcial
          end
        end
      end if defined?(Patient)

      User.class_eval do
        has_one :professional_portal_setting, class_name: 'ProfessionalPortalSetting', dependent: :destroy
      end

      # Sprint H — Hook em AgendaEvent: quando status transita pra `no_show`
      # (qualquer caminho — recepção, profissional, job), dispara a avaliação
      # de fee. O assessor é idempotente e nunca quebra o save (rescue dentro).
      if defined?(AgendaEvent)
        AgendaEvent.class_eval do
          after_update_commit :patient_portal_assess_no_show_fee, if: :saved_change_to_status?

          def patient_portal_assess_no_show_fee
            return unless status == 'no_show'

            PatientPortal::Fees::NoShowFeeAssessor.new(event: self).call
          rescue StandardError => e
            Rails.logger.error("[AgendaEvent#patient_portal_assess_no_show_fee] #{e.class} #{e.message}")
          end
        end
      end

      # Telemed: associações `has_many :telemed_recordings` em AgendaEvent e
      # `belongs_to :proposed_evolution` em ClinicalNote foram movidas para
      # plugins/telemed/lib/telemed/engine.rb.
    end
  end
end
