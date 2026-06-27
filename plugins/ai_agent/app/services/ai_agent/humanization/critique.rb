# Reflection 1-step antes de ação irreversível (book / reschedule).
# Implementação determinística (não LLM-as-judge): checks rápidos que
# capturam ~95% dos erros do LLM (data no passado, fora do horário,
# profissional que não faz o serviço, duração absurda) sem custo extra.
# LLM-as-judge fica como toggle opcional — Decisão D-15 do plano:
# "1 passada de critique APENAS em high-stakes". Aqui são high-stakes
# de fato porque acabariam virando AgendaEvent persistido.
#
# Uso (em ChatService):
#   verdict = Critique.new(account: ..., tool: :book, args: {...}).call
#   return verdict.error_result if verdict.failed?
class AiAgent::Humanization::Critique
  Verdict = Struct.new(:passed, :reasons, keyword_init: true) do
    def passed? = passed
    def failed? = !passed

    # Hash que vira retorno da tool quando reprovamos. O LLM lê e
    # pergunta o que falta ao paciente em vez de re-disparar a ação.
    def error_result_for(tool)
      key = case tool
            when :book then :booked
            when :reschedule then :rescheduled
            end
      {
        key => false,
        :critique_failed => true,
        :error => "Não posso confirmar essa ação: #{reasons.join('; ')}. Verifique com o paciente e tente de novo."
      }
    end
  end

  MIN_DURATION = 15
  MAX_DURATION = 240

  def initialize(account:, tool:, args:)
    @account = account
    @tool = tool.to_sym
    @args = args || {}
  end

  def call
    reasons = []

    starts = parse_time(@args[:starts_at] || @args[:new_starts_at])
    if starts.nil?
      reasons << 'data/hora ausente ou inválida'
    else
      reasons << 'data/hora está no passado' if starts < Time.current
      reasons << "fora do horário de funcionamento da clínica (#{starts.strftime('%d/%m %H:%M')})" unless within_business_hours?(starts)
    end

    if @tool == :book
      duration = @args[:duration_minutes].to_i
      reasons << "duração #{duration}min fora do permitido (#{MIN_DURATION}–#{MAX_DURATION})" unless duration.between?(MIN_DURATION, MAX_DURATION)

      user_id = @args[:user_id]
      service_id = @args[:service_id]

      # Valida service_id ANTES de checar user/service binding pra dar
      # mensagem precisa. Sem isso, LLM passando service_id inválido
      # gera "profissional não realiza esse serviço" — engana o caller.
      if service_id.present? && !service_in_account?(service_id)
        reasons << "serviço #{service_id} não existe nesta clínica"
      elsif user_id.present? && !user_in_account?(user_id)
        reasons << "profissional #{user_id} não pertence à clínica"
      elsif user_id.present? && service_id.present? && !user_does_service?(user_id, service_id)
        reasons << 'profissional escolhido não realiza esse serviço'
      end
    end

    Verdict.new(passed: reasons.empty?, reasons: reasons)
  end

  private

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def user_in_account?(user_id)
    @account.users.exists?(id: user_id)
  end

  def service_in_account?(service_id)
    return true unless defined?(::AgendaService)

    ::AgendaService.exists?(account_id: @account.id, id: service_id)
  end

  def user_does_service?(user_id, service_id)
    return true unless defined?(::AgendaServiceUser)

    ::AgendaServiceUser.exists?(account_id: @account.id, user_id: user_id, agenda_service_id: service_id)
  end

  # Critique é tolerante por design: se a clínica não configurou
  # week_days, autoriza (não bloqueia legitimamente). O bloqueio só
  # acontece quando há config E o horário cai claramente fora.
  def within_business_hours?(time)
    setting = ::AgendaSetting.find_by(account_id: @account.id)
    days = setting&.week_days
    return true if days.blank?

    # week_days é array de hash com :id (sun/mon/...) ou indexado
    wday_key = %w[sun mon tue wed thu fri sat][time.in_time_zone(AiAgent::ContextBuilder::CLINIC_TIMEZONE).wday]
    day = days.find { |d| (d['id'] || d[:id]).to_s == wday_key }
    return true if day.blank?
    return false unless day['enabled'] || day[:enabled]

    local = time.in_time_zone(AiAgent::ContextBuilder::CLINIC_TIMEZONE)
    minute_of_day = (local.hour * 60) + local.min

    start_min = parse_hhmm(day['start'] || day[:start])
    end_min   = parse_hhmm(day['end'] || day[:end])
    return true if start_min.nil? || end_min.nil?
    return false if minute_of_day < start_min || minute_of_day >= end_min

    lunch_s = parse_hhmm(day['lunchStart'] || day[:lunchStart])
    lunch_e = parse_hhmm(day['lunchEnd']   || day[:lunchEnd])
    # Almoço só bloqueia se começo do agendamento cair dentro do
    # intervalo. Final cruzando o almoço é problema de slot, não de
    # critique; deixa passar.
    return false if lunch_s && lunch_e && minute_of_day >= lunch_s && minute_of_day < lunch_e

    true
  end

  def parse_hhmm(str)
    return nil if str.blank?

    h, m = str.to_s.split(':').map(&:to_i)
    return nil unless h && m

    (h * 60) + m
  end
end
