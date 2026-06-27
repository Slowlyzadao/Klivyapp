# Configuração por account. Estrutura jsonb por categoria — ver PRD §14.7.
# Para resolver um setting respeitando a hierarquia (Account → Profissional →
# Serviço → Procedimento → Tag), use PatientPortal::ConfigResolver, não acesse
# este modelo diretamente nos controllers.
class PatientPortalSetting < ApplicationRecord
  belongs_to :account

  ACTIVE_PRESETS = %w[autonomy_guided reception_digital self_service concierge custom].freeze

  validates :active_preset, inclusion: { in: ACTIVE_PRESETS }
end
