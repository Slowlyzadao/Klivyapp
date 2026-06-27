# Um passo ADICIONAL na cadência de uma FollowUpRule (beats 2..N).
# O passo 1 é a própria regra (colunas offset_* + context_brief); este
# model representa os disparos seguintes de uma sequência de
# acompanhamento. Ver `AiAgent::FollowUpRule#dispatch_steps`.
#
# Reaproveita os limites/validações de offset da regra pra manter uma
# única fonte de verdade — qualifica a constante irmã (AiAgent::*) por
# ser classe compacta.
class AiAgent::FollowUpStep < ApplicationRecord
  self.table_name = 'ai_agent_follow_up_steps'

  OFFSET_UNITS     = AiAgent::FollowUpRule::OFFSET_UNITS
  OFFSET_LIMITS    = AiAgent::FollowUpRule::OFFSET_LIMITS
  SECONDS_PER_UNIT = AiAgent::FollowUpRule::SECONDS_PER_UNIT

  belongs_to :rule, class_name: 'AiAgent::FollowUpRule', inverse_of: :steps

  validates :offset_unit, inclusion: { in: OFFSET_UNITS }
  validates :context_brief, length: { maximum: 4000 }
  validates :static_body, length: { maximum: 4000 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :offset_within_unit_limits
  validate :body_present_for_action_type

  scope :ordered, -> { order(:position, :id) }

  # Mesma conta da regra: quantos segundos esse offset representa,
  # independente da unidade configurada. CandidateFinder usa pra montar
  # a janela temporal do disparo.
  def offset_seconds
    offset_hours.to_i * SECONDS_PER_UNIT.fetch(offset_unit.to_s, 3600)
  end

  private

  # Espelha a regra: no modo estático exige `static_body`; no generativo,
  # `context_brief`. Lê o modo da regra-mãe (`rule.action_type`).
  def body_present_for_action_type
    if rule&.static?
      errors.add(:static_body, 'não pode ficar em branco') if static_body.blank?
    elsif context_brief.blank?
      errors.add(:context_brief, 'não pode ficar em branco')
    end
  end

  def offset_within_unit_limits
    range = OFFSET_LIMITS[offset_unit.to_s]
    return if range.nil?
    return if offset_hours.is_a?(Integer) && range.cover?(offset_hours)

    label = case offset_unit
            when 'seconds' then 'segundos'
            when 'minutes' then 'minutos'
            else 'horas'
            end
    errors.add(:offset_hours, "deve estar entre #{range.first} e #{range.last} #{label}")
  end
end
