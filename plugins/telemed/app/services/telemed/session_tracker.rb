# Rastreia quem está conectado na sala de teleconsulta (Sprint K).
#
# Persiste em `AgendaEvent#custom_attributes['telemed_session']` —
# escolhemos JSONB ao invés de tabela dedicada pra manter o MVP simples,
# já que o estado é leve (4-5 timestamps) e tem ciclo de vida atrelado ao
# próprio evento. Quando a feature evoluir pra ter histórico de
# reconexões/analytics, migrar pra tabela é mecânico.
#
# Idempotência: `record_joined!` é chamado várias vezes pela UI (refresh,
# reconnect). Apenas a PRIMEIRA marcação persiste o timestamp — reconexões
# subsequentes não sobrescrevem `*_joined_at`, mantendo a leitura coerente
# pros jobs do timer.
#
# Concurrency: tudo dentro de `with_lock` (SELECT FOR UPDATE). Dois eventos
# concorrentes (doutor reportando join + paciente saindo) se serializam no
# row lock do AgendaEvent.
module Telemed
  class SessionTracker
    KEY = 'telemed_session'.freeze

    # Snapshot imutável da sessão. Métodos de conveniência pra os jobs
    # raciocinarem sem mexer no Hash cru.
    Session = Struct.new(
      :doctor_joined_at, :patient_joined_at, :both_started_at,
      :doctor_left_at,   :patient_left_at,
      keyword_init: true
    ) do
      def doctor_present?  = doctor_joined_at.present? && doctor_left_at.blank?
      def patient_present? = patient_joined_at.present? && patient_left_at.blank?
      def both_present?    = doctor_present? && patient_present?
      def nobody_present?  = !doctor_present? && !patient_present?

      def to_h
        {
          'doctor_joined_at'  => doctor_joined_at&.iso8601,
          'patient_joined_at' => patient_joined_at&.iso8601,
          'both_started_at'   => both_started_at&.iso8601,
          'doctor_left_at'    => doctor_left_at&.iso8601,
          'patient_left_at'   => patient_left_at&.iso8601
        }
      end
    end

    def initialize(event)
      @event = event
    end

    # Snapshot atual (não trava — leitura só). Use record_*! pra mutações.
    def session
      raw = @event.custom_attributes&.dig(KEY) || {}
      build_session(raw)
    end

    # Marca entrada do participante. `role` ∈ ['doctor', 'patient'].
    # Idempotente — segunda chamada com mesma role não sobrescreve o
    # timestamp original. Retorna o Session atualizado.
    def record_joined!(role, at: Time.current)
      validate_role!(role)
      mutate do |raw|
        joined_key = "#{role}_joined_at"
        # Reseta o left_at correspondente — se o usuário saiu e voltou,
        # a sessão "renasce" pro role dele. _joined_at permanece o
        # original (primeira entrada).
        raw["#{role}_left_at"] = nil
        raw[joined_key] ||= at.iso8601

        # Calcula both_started_at na primeira coincidência de presença.
        if raw['both_started_at'].blank? &&
           raw['doctor_joined_at'].present? &&
           raw['patient_joined_at'].present?
          raw['both_started_at'] = at.iso8601
        end
        raw
      end
    end

    # Marca saída. Idempotente por sobrescrita (último left_at vence).
    def record_left!(role, at: Time.current)
      validate_role!(role)
      mutate do |raw|
        raw["#{role}_left_at"] = at.iso8601
        raw
      end
    end

    # Reseta a sessão (uso restrito a testes ou recomeço explícito).
    def reset!
      mutate { |_| {} }
    end

    private

    # Lock + read-modify-write do JSONB. Não usamos UPDATE atômico
    # (jsonb_set) porque a regra de both_started_at depende do estado
    # antes da mutação — precisamos ler, decidir, escrever.
    def mutate
      @event.with_lock do
        attrs = (@event.custom_attributes || {}).deep_dup
        raw = (attrs[KEY] || {}).dup
        updated = yield(raw)
        attrs[KEY] = updated
        @event.update!(custom_attributes: attrs)
        build_session(updated)
      end
    end

    def build_session(raw)
      raw = raw || {}
      Session.new(
        doctor_joined_at:  parse_time(raw['doctor_joined_at']),
        patient_joined_at: parse_time(raw['patient_joined_at']),
        both_started_at:   parse_time(raw['both_started_at']),
        doctor_left_at:    parse_time(raw['doctor_left_at']),
        patient_left_at:   parse_time(raw['patient_left_at'])
      )
    end

    def parse_time(value)
      return nil if value.blank?
      return value if value.is_a?(Time)

      Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def validate_role!(role)
      return if %w[doctor patient].include?(role.to_s)

      raise ArgumentError, "role inválido: #{role.inspect} (esperado 'doctor' ou 'patient')"
    end
  end
end
