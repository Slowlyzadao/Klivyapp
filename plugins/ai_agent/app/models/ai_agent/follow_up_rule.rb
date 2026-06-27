# Regra configurável de follow-up. A clínica define quantas regras quiser:
# cada uma tem um gatilho (pre_appointment, post_appointment, no_response,
# no_show, custom), um offset (valor + unidade — segundos/minutos/horas) e
# um "cenário" (texto livre que vira contexto pra Bea gerar a mensagem).
#
# O cron `FollowUpDispatcherJob` itera as regras enabled e usa o
# `FollowUps::CandidateFinder` pra descobrir alvos elegíveis. Cada
# disparo cria uma `FollowUpExecution` (audit + idempotência).
class AiAgent::FollowUpRule < ApplicationRecord
  self.table_name = 'ai_agent_follow_up_rules'

  # `appointment_confirmed` é event-driven, não cron — dispara via
  # callback do AgendaEvent quando a clínica muda o status de
  # `pending_confirmation` pra `scheduled`/`confirmed`. CandidateFinder
  # ignora esse trigger (cai no `else []`); a entrada acontece via
  # `AiAgent::FollowUps::DispatchAppointmentConfirmedJob`.
  # `service_recall` (Fase 6) é reativação por serviço: dispara N dias/
  # semanas/meses após a última sessão assinada daquele serviço. Single-shot
  # (sem cadência) — usa `recall_interval_value`+`recall_interval_unit`/
  # `agenda_service_id`, não offset.
  TRIGGER_TYPES = %w[pre_appointment post_appointment no_response no_show appointment_confirmed custom
                     service_recall].freeze
  OFFSET_UNITS  = %w[seconds minutes hours].freeze

  # Modo de ação (Fase 2):
  #   generative → a Bea escreve a mensagem (usa `context_brief` como cenário)
  #   static     → mensagem fixa com variáveis ({{nome}}, ...), sem LLM (usa `static_body`)
  ACTION_TYPES = %w[generative static].freeze

  # Filtro por origem do AgendaEvent. Ignorado em triggers que não usam
  # agenda (`no_response`, `custom`).
  #   both      → qualquer agendamento (default)
  #   ai_agent  → só os que a Bea criou (`source='ai_agent'`)
  #   manual    → só os criados por humano ou importação (`source IN ('manual','public_booking','import')`)
  APPLIES_TO_OPTIONS = %w[both ai_agent manual].freeze

  # Tetos por unidade. Limita pelo lado do bom-senso: até 30 dias em
  # horas, 48h em minutos, 4h em segundos. Cron roda a cada 1min (janela
  # ±1min no CandidateFinder), então offsets em segundos abaixo de ~60s
  # podem disparar tarde — UI avisa.
  OFFSET_LIMITS = {
    'seconds' => (1..14_400),
    'minutes' => (1..2_880),
    'hours' => (1..720)
  }.freeze

  SECONDS_PER_UNIT = { 'seconds' => 1, 'minutes' => 60, 'hours' => 3600 }.freeze

  # Unidades do intervalo de reativação por serviço (espelha o padrão
  # offset_hours/offset_unit). `minutes`/`hours` existem sobretudo pra
  # testar a reativação sem esperar dias (o cron roda a cada 1 min, então
  # o piso prático é ~1 min). Tetos de bom-senso por unidade.
  RECALL_INTERVAL_UNITS  = %w[minutes hours days weeks months years].freeze
  RECALL_INTERVAL_LIMITS = {
    'minutes' => (1..43_200), # até 30 dias em minutos
    'hours' => (1..8_760),    # até 365 dias em horas
    'days' => (1..365),
    'weeks' => (1..52),
    'months' => (1..36),
    'years' => (1..10)
  }.freeze

  belongs_to :account
  has_many :executions,
           class_name: 'AiAgent::FollowUpExecution',
           foreign_key: :rule_id,
           dependent: :destroy,
           inverse_of: :rule

  # Passos ADICIONAIS da cadência (beats 2..N). O passo 1 é a própria
  # regra (colunas offset_* + context_brief). Ver `dispatch_steps`.
  # `autosave` persiste edições in-place e os mark_for_destruction no
  # save! da regra — o controller sincroniza os passos SEM recriá-los
  # (preserva step_id, que chaveia idempotência/cap das execuções).
  has_many :steps,
           -> { ordered },
           class_name: 'AiAgent::FollowUpStep',
           foreign_key: :rule_id,
           dependent: :destroy,
           autosave: true,
           inverse_of: :rule

  validates :name, presence: true, length: { maximum: 120 }
  validates :trigger_type, inclusion: { in: TRIGGER_TYPES }
  validates :offset_unit, inclusion: { in: OFFSET_UNITS }
  validates :recall_interval_unit, inclusion: { in: RECALL_INTERVAL_UNITS }
  validates :applies_to, inclusion: { in: APPLIES_TO_OPTIONS }
  validates :action_type, inclusion: { in: ACTION_TYPES }
  validate :offset_within_unit_limits
  # Presença condicional ao modo: generativo exige cenário (context_brief),
  # estático exige a mensagem fixa (static_body). O outro fica livre.
  validates :context_brief, length: { maximum: 4000 }
  validates :static_body, length: { maximum: 4000 }
  validates :persona_override, length: { maximum: 2000 }
  validate :body_present_for_action_type
  validate :service_recall_config
  validate :distinct_step_offsets
  validate :status_filter_shape
  validates :max_per_target, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  # Cooldown anti-spam por regra (minutos). 0 = sem cooldown; teto 1 semana.
  validates :cooldown_minutes,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 10_080 }

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:position, :id) }
  scope :by_trigger, ->(type) { where(trigger_type: type) }

  # Quantos segundos esse offset representa. CandidateFinder usa pra
  # construir a janela temporal independente da unidade que o usuário
  # configurou. Sempre retorna inteiro.
  def offset_seconds
    offset_hours.to_i * SECONDS_PER_UNIT.fetch(offset_unit.to_s, 3600)
  end

  # Sequência completa de disparo: o passo 1 é a própria regra
  # (sintetizado on-the-fly a partir das colunas offset_*/context_brief)
  # seguido dos passos adicionais persistidos. O CandidateFinder itera
  # essa lista — uma regra sem passos extras se comporta exatamente como
  # antes (1 disparo único), garantindo compatibilidade retroativa.
  #
  # O passo sintético tem `id` nil de propósito: a execução resultante
  # fica com `step_id` nil e o SendFollowUpJob usa o `context_brief` da
  # regra. Os passos persistidos trazem `id` e `context_brief` próprios.
  def dispatch_steps
    # Usa `rule_id:` (coluna FK) e NÃO `rule: self`: passar a associação
    # com `inverse_of` re-injetaria o passo sintético dentro de
    # `self.steps`, duplicando-o na própria lista. O passo base nunca é
    # persistido — só carrega offset/conteúdo pro CandidateFinder.
    base = AiAgent::FollowUpStep.new(
      rule_id: id,
      position: 0,
      offset_hours: offset_hours,
      offset_unit: offset_unit,
      context_brief: context_brief,
      static_body: static_body
    )
    [base] + steps.to_a
  end

  def service_recall?
    trigger_type.to_s == 'service_recall'
  end

  def static?
    action_type.to_s == 'static'
  end

  def generative?
    !static?
  end

  # Tem template aprovado configurado pro fallback fora da janela de 24h.
  def cloud_template?
    cloud_template_name.present?
  end

  # Intervalo da reativação como Duration (ex: 30.minutes, 15.days, 6.months)
  # — ServiceRecallFinder soma à última sessão pra obter o vencimento.
  def recall_interval
    value = recall_interval_value.to_i
    case recall_interval_unit
    when 'minutes' then value.minutes
    when 'hours'   then value.hours
    when 'days'    then value.days
    when 'weeks'   then value.weeks
    when 'years'   then value.years
    else value.months
    end
  end

  # Coage o jsonb (pode voltar nil em rows antigas) — sempre um Array.
  def cloud_template_params
    Array(self[:cloud_template_params])
  end

  # Lista de valores aceitos no `AgendaEvent.source` pra essa regra.
  # Retorna `nil` quando 'both' — caller deve interpretar nil como
  # "não filtra por source". Pra triggers sem agenda (no_response,
  # custom), CandidateFinder ignora isso.
  def agenda_source_filter
    case applies_to
    when 'ai_agent' then %w[ai_agent]
    when 'manual'   then %w[manual public_booking import]
    end
  end

  # Default jsonb fields can come back as nil from older rows in some
  # PG configs — coerce on read so callers can `.dig(:status)` safely.
  def status_filter
    self[:status_filter] || {}
  end

  private

  # Generativo exige `context_brief` (cenário pra Bea); estático exige
  # `static_body` (mensagem fixa). Valida só o campo do modo ativo.
  def body_present_for_action_type
    if static?
      errors.add(:static_body, 'não pode ficar em branco') if static_body.blank?
    elsif context_brief.blank?
      errors.add(:context_brief, 'não pode ficar em branco')
    end
  end

  # Cada passo da cadência precisa de um offset EFETIVO distinto (incluindo
  # o passo base = offset da regra). Offsets iguais gerariam o mesmo
  # target_at e colidiriam na idempotência — um beat sumiria. Ignorado em
  # service_recall (single-shot, sem cadência).
  def distinct_step_offsets
    return if service_recall?

    extra = steps.reject(&:marked_for_destruction?)
    offsets = [offset_seconds] + extra.map(&:offset_seconds)
    return if offsets.uniq.length == offsets.length

    errors.add(:base, 'cada passo da sequência precisa de um tempo diferente do passo 1 e dos outros')
  end

  # service_recall exige serviço-alvo (que PERTENÇA à conta) + intervalo
  # positivo dentro do teto da unidade.
  def service_recall_config
    return unless service_recall?

    if agenda_service_id.blank?
      errors.add(:agenda_service_id, 'é obrigatório na reativação por serviço')
    elsif !owns_agenda_service?
      errors.add(:agenda_service_id, 'não pertence a esta conta')
    end

    range = RECALL_INTERVAL_LIMITS[recall_interval_unit.to_s] || RECALL_INTERVAL_LIMITS['months']
    return if recall_interval_value.is_a?(Integer) && range.cover?(recall_interval_value)

    errors.add(:recall_interval_value, "deve estar entre #{range.first} e #{range.last}")
  end

  # Multi-tenancy: o serviço-alvo tem que ser desta conta. Leitura
  # defensiva do plugin agenda (não acopla o boot se ausente).
  def owns_agenda_service?
    return true unless defined?(::AgendaService)

    ::AgendaService.exists?(account_id: account_id, id: agenda_service_id)
  end

  # `status_filter` é jsonb, mas só a chave `allowed` (array de strings
  # curtas de status) é consumida — o permit `status_filter: {}` do
  # controller aceita qualquer hash, então valida a forma aqui pra API
  # não persistir JSON arbitrário/ilimitado na regra.
  def status_filter_shape
    sf = self[:status_filter]
    return if sf.blank? || status_filter_valid?(sf)

    errors.add(:status_filter, 'formato inválido (esperado {"allowed": ["status", ...]})')
  end

  def status_filter_valid?(filter)
    return false unless filter.is_a?(Hash)
    return false unless filter.keys.map(&:to_s).all?('allowed')

    status_list_valid?(Array(filter['allowed'] || filter[:allowed]))
  end

  def status_list_valid?(list)
    list.size <= 10 && list.all? { |v| v.is_a?(String) && v.length <= 30 }
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
