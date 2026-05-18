module AiAgent
  # Template editável da clínica para cada tipo de notificação interna que a
  # Bea pode postar no Chat Interno. UNIQUE por (account, event_key) — uma
  # clínica tem 1 template por evento.
  #
  # Spec: docs/01-product/ai-agent-configuration-plan.md (Apêndice F.2)
  class InternalNotificationTemplate < ApplicationRecord
    self.table_name = 'ai_agent_internal_notification_templates'

    TARGET_TYPES = %w[room user disabled].freeze

    belongs_to :account

    validates :event_key, presence: true,
                          uniqueness: { scope: :account_id },
                          inclusion: { in: ->(_) { AiAgent::InternalNotifier::EventCatalog.keys } }
    validates :name, presence: true, length: { maximum: 120 }
    validates :body, presence: true, length: { maximum: 4000 }
    validates :target_type, inclusion: { in: TARGET_TYPES }
    validate :target_id_consistent_with_type

    scope :enabled, -> { where(enabled: true) }

    def disabled?
      target_type == 'disabled' || !enabled
    end

    def event_label
      AiAgent::InternalNotifier::EventCatalog.label_for(event_key)
    end

    def available_vars
      AiAgent::InternalNotifier::EventCatalog.vars_for(event_key)
    end

    private

    def target_id_consistent_with_type
      case target_type
      when 'room', 'user'
        errors.add(:target_id, 'é obrigatório quando o destino é sala ou DM') if target_id.blank?
      when 'disabled'
        errors.add(:target_id, 'deve ser nulo quando desativado') if target_id.present?
      end
    end
  end
end
