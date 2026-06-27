# Resolve estado de telemedicina de um AgendaEvent para exibição no portal
# (Sprint J — PRD Fase 3).
#
# Escopo MVP: só o lado do PACIENTE — botão "Entrar na consulta" + janela de
# liberação. A clínica (futuro Sprint) configura `telemedicine_url` e
# `telemedicine_provider` em `AgendaEvent.custom_attributes`. A integração real
# de vídeo (LiveKit) é responsabilidade da clínica/admin.
#
# Janela default (configurável via setting `appointments.telemedicine_pre_minutes`
# e `appointments.telemedicine_post_minutes`):
#   - pre  = 60 min antes de starts_at  (paciente entra em sala de espera até
#            dentista admitir — padrão Google Meet)
#   - post = 30 min depois de ends_at
#
# Service idempotente, leitura pura. Pode ser chamado em qualquer ponto sem
# side effect (controllers, jobs, serializers).
module Telemed
  class Session
    DEFAULT_PRE_MINUTES  = 60
    DEFAULT_POST_MINUTES = 30
    JOINABLE_STATUSES    = %w[scheduled confirmed arrived in_progress].freeze

    # ─── Razões que CLASSIFICAMOS por gravidade ──────────────────────────
    # Permanentes (a sala não vai abrir nunca pra esse evento):
    PERMANENT_REASONS = %w[no_event event_cancelled event_not_joinable
                            event_missing_times not_configured].freeze
    # Fora da janela mas reabertáveis (cliente entra em "sala de espera"
    # — 2026-05-19, Google Meet pattern):
    WINDOW_REASONS    = %w[too_early window_closed].freeze

    Result = Struct.new(
      :enabled, :url, :provider, :can_join_now,
      :starts_in_seconds, :ends_in_seconds, :reason, :room_code,
      keyword_init: true
    ) do
      def enabled?       = !!enabled
      def can_join_now?  = !!can_join_now

      # Bloqueio definitivo — controllers usam pra recusar emissão de token.
      # Reasons que entram aqui: evento ausente/cancelado, status já encerrado
      # (completed/no_show/cancelled), sem horário, telemed flag desligado.
      def permanently_blocked?
        return true unless enabled?
        PERMANENT_REASONS.include?(reason.to_s)
      end

      # Fora da janela (too_early/window_closed). Controllers EMITEM token
      # mesmo assim — cliente coloca o paciente na sala de espera.
      def outside_window?
        WINDOW_REASONS.include?(reason.to_s)
      end

      def to_h
        {
          enabled: enabled?, url: url, provider: provider,
          can_join_now: can_join_now?,
          permanently_blocked: permanently_blocked?,
          outside_window: outside_window?,
          starts_in_seconds: starts_in_seconds,
          ends_in_seconds: ends_in_seconds,
          reason: reason,
          room_code: room_code
        }
      end
    end

    def initialize(event:, account: nil, now: Time.current)
      @event   = event
      @account = account || event&.account
      @now     = now
    end

    # Verdadeiro se `at` cai dentro da janela [starts_at - pre_min,
    # ends_at + post_min] desse evento. Fonte ÚNICA da verdade da
    # janela — `Telemed::AdmissionWindow` delega aqui pra decidir se
    # uma admissão de paciente continua válida (ver comentário longo
    # nesse service sobre por que a admissão segue a janela do evento,
    # não o ciclo de vida da sala LiveKit).
    #
    # NÃO checa status do evento aqui — só horários. Status final
    # (completed/cancelled/no_show) é responsabilidade do caller, pra
    # esse método continuar com responsabilidade única e reutilizável.
    def in_admission_window?(at:)
      return false unless @event&.starts_at && @event&.ends_at
      open  = @event.starts_at - pre_minutes.minutes
      close = @event.ends_at   + post_minutes.minutes
      at >= open && at <= close
    end

    def call
      attrs = telemedicine_attrs
      return disabled('no_event') unless @event

      # Sprint K — URL não precisa mais ser pre-salva. A sala é gerada on-demand
      # via SessionIssuer. URL no custom_attributes vira opcional (override pra
      # casos externos tipo Zoom/Meet); por default fica vazio.
      url      = attrs['telemedicine_url'].to_s.strip.presence
      provider = attrs['telemedicine_provider'].to_s.presence || 'livekit'
      enabled  = attrs['telemedicine_enabled'] == true

      return Result.new(
        enabled: false, url: nil, provider: provider,
        can_join_now: false, reason: 'not_configured',
        starts_in_seconds: starts_in_seconds, ends_in_seconds: ends_in_seconds,
        room_code: nil
      ) unless enabled

      window = compute_window
      Result.new(
        enabled: true,
        url:     url,
        provider: provider,
        can_join_now: window[:can_join],
        starts_in_seconds: starts_in_seconds,
        ends_in_seconds:   ends_in_seconds,
        reason:  window[:reason],
        # Slug "pppp-eeee-aaaa" — usado pra display no header da sala e pra
        # montar URL bonita estilo Google Meet (`/appointments/0017-0284-0076/telemed`).
        room_code: Telemed::RoomCode.from_event(@event)
      )
    end

    private

    def disabled(reason)
      Result.new(enabled: false, url: nil, provider: nil, can_join_now: false, reason: reason, room_code: nil)
    end

    def telemedicine_attrs
      attrs = @event.respond_to?(:custom_attributes) ? @event.custom_attributes : nil
      attrs.is_a?(Hash) ? attrs : {}
    end

    def starts_in_seconds
      return nil unless @event&.starts_at

      (@event.starts_at - @now).to_i
    end

    def ends_in_seconds
      return nil unless @event&.ends_at

      (@event.ends_at - @now).to_i
    end

    def compute_window
      return { can_join: false, reason: 'event_cancelled' } if @event.try(:discarded?)
      return { can_join: false, reason: 'event_not_joinable' } unless JOINABLE_STATUSES.include?(@event.status)
      return { can_join: false, reason: 'event_missing_times' } unless @event.starts_at && @event.ends_at

      pre_min  = pre_minutes
      post_min = post_minutes

      window_open  = @event.starts_at - pre_min.minutes
      window_close = @event.ends_at   + post_min.minutes

      if @now < window_open
        { can_join: false, reason: 'too_early' }
      elsif @now > window_close
        { can_join: false, reason: 'window_closed' }
      else
        { can_join: true, reason: 'in_window' }
      end
    end

    def setting_int(key, fallback)
      sched = @account&.patient_portal_setting&.scheduling
      v = sched.is_a?(Hash) ? sched[key.to_s] : nil
      v.present? ? v.to_i : fallback
    end

    def pre_minutes
      setting_int('telemedicine_pre_minutes', DEFAULT_PRE_MINUTES)
    end

    def post_minutes
      setting_int('telemedicine_post_minutes', DEFAULT_POST_MINUTES)
    end
  end
end
