module AiAgent
  module Health
    # Single source of truth pra "saúde" da Bea. Calcula um snapshot
    # determinístico a partir das últimas 24h de `AiAgent::Trace` + estado
    # de provider configurado + backlog do Sidekiq. Decide status final
    # (ok/degraded/down) e uma lista de `alerts` ativos.
    #
    # Sem efeitos colaterais: nem grava, nem envia mensagem, nem chama LLM.
    # Quem decide o que fazer com o resultado é o caller (controller pra
    # responder ao cliente, MonitorJob pra disparar Notifier).
    class Checker
      WINDOW = 24.hours
      MIN_TRACES_FOR_VALID = 20

      DEFAULT_THRESHOLDS = {
        deflection_floor_pct: 60,
        error_rate_ceil_pct: 10,
        avg_latency_ceil_ms: 8_000,
        cost_24h_ceil_cents: 50_000,
        provider_fallback_ratio_ceil_pct: 50,
        sidekiq_backlog_ceil: 100
      }.freeze

      Snapshot = Struct.new(
        :status, :checked_at, :window_hours, :metrics, :provider, :alerts,
        keyword_init: true
      ) do
        def to_h
          {
            status: status,
            checked_at: checked_at.iso8601,
            window_hours: window_hours,
            metrics: metrics,
            provider: provider,
            alerts: alerts.map(&:to_h)
          }
        end
      end

      Alert = Struct.new(:key, :severity, :message, :value, :threshold, keyword_init: true) do
        def to_h
          { key: key, severity: severity, message: message, value: value, threshold: threshold }
        end
      end

      def self.call(thresholds: nil)
        new(thresholds: thresholds).call
      end

      def initialize(thresholds: nil)
        @thresholds = DEFAULT_THRESHOLDS.merge((thresholds || {}).symbolize_keys)
      end

      def call
        traces = AiAgent::Trace.where(created_at: WINDOW.ago..)
        metrics = compute_metrics(traces)
        provider = provider_snapshot(traces)
        alerts = evaluate_alerts(metrics: metrics, provider: provider)
        status = derive_status(alerts: alerts, metrics: metrics)

        Snapshot.new(
          status: status,
          checked_at: Time.current,
          window_hours: WINDOW.to_i / 3600,
          metrics: metrics,
          provider: provider,
          alerts: alerts
        )
      end

      private

      def compute_metrics(traces)
        count = traces.count
        return empty_metrics if count.zero?

        escalated = traces.where(escalated: true).count
        errored = traces.where.not(error_message: nil).count
        avg_latency = traces.average(:latency_ms).to_f.round
        total_cost = traces.sum(:cost_cents).to_i

        {
          traces_count: count,
          escalated_count: escalated,
          deflection_rate_pct: ((1.0 - (escalated.to_f / count)) * 100).round(1),
          error_count: errored,
          error_rate_pct: ((errored.to_f / count) * 100).round(1),
          avg_latency_ms: avg_latency,
          total_cost_cents: total_cost,
          sidekiq_backlog: sidekiq_backlog
        }
      end

      def empty_metrics
        {
          traces_count: 0,
          escalated_count: 0,
          deflection_rate_pct: nil,
          error_count: 0,
          error_rate_pct: nil,
          avg_latency_ms: nil,
          total_cost_cents: 0,
          sidekiq_backlog: sidekiq_backlog
        }
      end

      def provider_snapshot(traces)
        configured = InstallationConfig.find_by(name: 'CAPTAIN_LLM_PROVIDER')&.value.presence || 'gemini'
        by_provider = traces.group(:provider).count

        total = by_provider.values.sum
        fallback_ratio = if total.positive? && configured == 'gemini'
                          openai = by_provider['openai'].to_i
                          ((openai.to_f / total) * 100).round(1)
                        else
                          0.0
                        end

        {
          configured: configured,
          distribution: by_provider,
          fallback_ratio_pct: fallback_ratio
        }
      end

      def evaluate_alerts(metrics:, provider:)
        alerts = []
        # Não alerta com amostra pequena — distorce qualquer rate.
        statistically_valid = metrics[:traces_count] >= MIN_TRACES_FOR_VALID

        if statistically_valid && metrics[:deflection_rate_pct] && metrics[:deflection_rate_pct] < @thresholds[:deflection_floor_pct]
          alerts << build_alert(:deflection_low, :warning,
                                "Deflection rate caiu para #{metrics[:deflection_rate_pct]}% (mín #{@thresholds[:deflection_floor_pct]}%)",
                                metrics[:deflection_rate_pct], @thresholds[:deflection_floor_pct])
        end

        if statistically_valid && metrics[:error_rate_pct] && metrics[:error_rate_pct] > @thresholds[:error_rate_ceil_pct]
          alerts << build_alert(:error_rate_high, :critical,
                                "Taxa de erro em #{metrics[:error_rate_pct]}% (máx #{@thresholds[:error_rate_ceil_pct]}%)",
                                metrics[:error_rate_pct], @thresholds[:error_rate_ceil_pct])
        end

        if metrics[:avg_latency_ms] && metrics[:avg_latency_ms] > @thresholds[:avg_latency_ceil_ms]
          alerts << build_alert(:latency_high, :warning,
                                "Latência média em #{metrics[:avg_latency_ms]}ms (máx #{@thresholds[:avg_latency_ceil_ms]}ms)",
                                metrics[:avg_latency_ms], @thresholds[:avg_latency_ceil_ms])
        end

        if metrics[:total_cost_cents] > @thresholds[:cost_24h_ceil_cents]
          alerts << build_alert(:cost_high, :warning,
                                "Custo 24h em R$ #{format('%.2f', metrics[:total_cost_cents] / 100.0)} (máx R$ #{format('%.2f', @thresholds[:cost_24h_ceil_cents] / 100.0)})",
                                metrics[:total_cost_cents], @thresholds[:cost_24h_ceil_cents])
        end

        if statistically_valid && provider[:fallback_ratio_pct] > @thresholds[:provider_fallback_ratio_ceil_pct]
          alerts << build_alert(:provider_fallback_high, :critical,
                                "Provider primário falhando: #{provider[:fallback_ratio_pct]}% das chamadas caíram no OpenAI (configurado: Gemini)",
                                provider[:fallback_ratio_pct], @thresholds[:provider_fallback_ratio_ceil_pct])
        end

        if metrics[:sidekiq_backlog] > @thresholds[:sidekiq_backlog_ceil]
          alerts << build_alert(:queue_backlog, :warning,
                                "Backlog do Sidekiq em #{metrics[:sidekiq_backlog]} jobs (máx #{@thresholds[:sidekiq_backlog_ceil]})",
                                metrics[:sidekiq_backlog], @thresholds[:sidekiq_backlog_ceil])
        end

        alerts
      end

      def derive_status(alerts:, metrics:)
        return 'down' if alerts.any? { |a| a.severity == :critical }
        return 'degraded' if alerts.any?
        return 'idle' if metrics[:traces_count].zero?

        'ok'
      end

      def build_alert(key, severity, message, value, threshold)
        Alert.new(key: key, severity: severity, message: message, value: value, threshold: threshold)
      end

      # Backlog combinado das filas que a Bea usa. Conta enqueued — não
      # inclui retry/scheduled set (decisão: scheduled é normal, retry
      # vira backlog só se ficar crescendo).
      def sidekiq_backlog
        return 0 unless defined?(::Sidekiq::Queue)

        %w[default scheduled_jobs].sum { |q| ::Sidekiq::Queue.new(q).size }
      rescue StandardError
        0
      end
    end
  end
end
