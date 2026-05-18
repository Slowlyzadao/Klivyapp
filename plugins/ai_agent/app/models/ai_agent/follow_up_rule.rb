module AiAgent
  # Regra configurável de follow-up. A clínica define quantas regras quiser:
  # cada uma tem um gatilho (pre_appointment, post_appointment, no_response,
  # no_show, custom), um offset (valor + unidade — segundos/minutos/horas) e
  # um "cenário" (texto livre que vira contexto pra Bea gerar a mensagem).
  #
  # O cron `FollowUpDispatcherJob` itera as regras enabled e usa o
  # `FollowUps::CandidateFinder` pra descobrir alvos elegíveis. Cada
  # disparo cria uma `FollowUpExecution` (audit + idempotência).
  class FollowUpRule < ApplicationRecord
    self.table_name = 'ai_agent_follow_up_rules'

    # `appointment_confirmed` é event-driven, não cron — dispara via
    # callback do AgendaEvent quando a clínica muda o status de
    # `pending_confirmation` pra `scheduled`/`confirmed`. CandidateFinder
    # ignora esse trigger (cai no `else []`); a entrada acontece via
    # `AiAgent::FollowUps::DispatchAppointmentConfirmedJob`.
    TRIGGER_TYPES = %w[pre_appointment post_appointment no_response no_show appointment_confirmed custom].freeze
    OFFSET_UNITS  = %w[seconds minutes hours].freeze

    # Filtro por origem do AgendaEvent. Ignorado em triggers que não usam
    # agenda (`no_response`, `custom`).
    #   both      → qualquer agendamento (default)
    #   ai_agent  → só os que a Bea criou (`source='ai_agent'`)
    #   manual    → só os criados por humano ou importação (`source IN ('manual','public_booking','import')`)
    APPLIES_TO_OPTIONS = %w[both ai_agent manual].freeze

    # Tetos por unidade. Limita pelo lado do bom-senso: até 30 dias em
    # horas, 48h em minutos, 4h em segundos. Cron roda a cada 15min, então
    # offsets em segundos abaixo de ~30s podem disparar tarde — UI avisa.
    OFFSET_LIMITS = {
      'seconds' => (1..14_400),
      'minutes' => (1..2_880),
      'hours'   => (1..720)
    }.freeze

    SECONDS_PER_UNIT = { 'seconds' => 1, 'minutes' => 60, 'hours' => 3600 }.freeze

    belongs_to :account
    has_many :executions,
             class_name: 'AiAgent::FollowUpExecution',
             foreign_key: :rule_id,
             dependent: :destroy,
             inverse_of: :rule

    validates :name, presence: true, length: { maximum: 120 }
    validates :trigger_type, inclusion: { in: TRIGGER_TYPES }
    validates :offset_unit, inclusion: { in: OFFSET_UNITS }
    validates :applies_to, inclusion: { in: APPLIES_TO_OPTIONS }
    validate :offset_within_unit_limits
    validates :context_brief, presence: true, length: { maximum: 4000 }
    validates :max_per_target, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    scope :enabled, -> { where(enabled: true) }
    scope :ordered, -> { order(:position, :id) }
    scope :by_trigger, ->(type) { where(trigger_type: type) }

    # Quantos segundos esse offset representa. CandidateFinder usa pra
    # construir a janela temporal independente da unidade que o usuário
    # configurou. Sempre retorna inteiro.
    def offset_seconds
      offset_hours.to_i * SECONDS_PER_UNIT.fetch(offset_unit.to_s, 3600)
    end

    # Lista de valores aceitos no `AgendaEvent.source` pra essa regra.
    # Retorna `nil` quando 'both' — caller deve interpretar nil como
    # "não filtra por source". Pra triggers sem agenda (no_response,
    # custom), CandidateFinder ignora isso.
    def agenda_source_filter
      case applies_to
      when 'ai_agent' then %w[ai_agent]
      when 'manual'   then %w[manual public_booking import]
      else nil
      end
    end

    # Default jsonb fields can come back as nil from older rows in some
    # PG configs — coerce on read so callers can `.dig(:status)` safely.
    def status_filter
      self[:status_filter] || {}
    end

    private

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
end
