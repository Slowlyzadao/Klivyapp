module AiAgent
  module Health
    # Despacha alertas pra canais externos (Slack via webhook + email).
    # Dedupe em Redis por `alert.key` com janela de 1h — alerta que ficar
    # ativo por 6 horas dispara 1x (ou no máximo a cada 1h), não 36x.
    #
    # Stateless do ponto de vista do caller: passe um Snapshot, ele
    # cuida do resto. Nenhum side-effect se não houver canal configurado.
    class Notifier
      DEDUP_TTL = 1.hour
      DEDUP_PREFIX = 'ai_agent:health:alert_sent'.freeze

      def self.call(snapshot)
        new(snapshot).call
      end

      def initialize(snapshot)
        @snapshot = snapshot
      end

      def call
        return [] if @snapshot.alerts.empty?

        fresh = @snapshot.alerts.reject { |a| recently_sent?(a) }
        return [] if fresh.empty?

        deliver_slack(fresh) if slack_webhook.present?
        deliver_email(fresh) if alert_emails.any?

        fresh.each { |a| mark_sent(a) }
        fresh
      end

      private

      def recently_sent?(alert)
        return false unless redis_available?

        redis_get(dedup_key(alert)).present?
      end

      def mark_sent(alert)
        return unless redis_available?

        redis_setex(dedup_key(alert), DEDUP_TTL.to_i, '1')
      end

      def dedup_key(alert)
        "#{DEDUP_PREFIX}:#{alert.key}:#{alert.severity}"
      end

      def deliver_slack(alerts)
        payload = {
          text: "[Bea Health] status=#{@snapshot.status} alerts=#{alerts.size}",
          blocks: slack_blocks(alerts)
        }
        Net::HTTP.post(
          URI(slack_webhook),
          payload.to_json,
          'Content-Type' => 'application/json'
        )
      rescue StandardError => e
        Rails.logger.error("[AiAgent::Health::Notifier] slack delivery failed: #{e.class}: #{e.message}")
      end

      def slack_blocks(alerts)
        header = {
          type: 'header',
          text: { type: 'plain_text', text: "Bea: #{@snapshot.status.upcase}" }
        }
        metrics_line = metrics_summary
        context = {
          type: 'section',
          text: { type: 'mrkdwn', text: metrics_line }
        }
        bullets = alerts.map do |a|
          icon = a.severity == :critical ? ':red_circle:' : ':warning:'
          { type: 'section', text: { type: 'mrkdwn', text: "#{icon} *#{a.key}* — #{a.message}" } }
        end

        [header, context, *bullets]
      end

      def metrics_summary
        m = @snapshot.metrics
        parts = []
        parts << "deflection=#{m[:deflection_rate_pct]}%"             if m[:deflection_rate_pct]
        parts << "err=#{m[:error_rate_pct]}%"                          if m[:error_rate_pct]
        parts << "lat=#{m[:avg_latency_ms]}ms"                         if m[:avg_latency_ms]
        parts << "cost24h=R$#{format('%.2f', m[:total_cost_cents] / 100.0)}"
        parts << "turnos=#{m[:traces_count]}"
        "_24h: #{parts.join(' · ')}_"
      end

      def deliver_email(alerts)
        body = build_email_body(alerts)
        mail = ActionMailer::Base.mail(
          to: alert_emails,
          from: ENV.fetch('MAILER_SENDER_EMAIL', 'noreply@klivy.com.br'),
          subject: "[Bea Health] #{@snapshot.status.upcase} — #{alerts.size} alerta(s)",
          body: body,
          content_type: 'text/plain'
        )
        mail.deliver_later
      rescue StandardError => e
        Rails.logger.error("[AiAgent::Health::Notifier] email delivery failed: #{e.class}: #{e.message}")
      end

      def build_email_body(alerts)
        lines = ["Status: #{@snapshot.status.upcase}", "Janela: últimas #{@snapshot.window_hours}h", '', metrics_summary.gsub(/[_*]/, ''), '', 'Alertas ativos:']
        alerts.each do |a|
          tag = a.severity == :critical ? '[CRÍTICO]' : '[AVISO]'
          lines << "  #{tag} #{a.key}: #{a.message}"
        end
        lines << ''
        lines << "Verificado em: #{@snapshot.checked_at.iso8601}"
        lines.join("\n")
      end

      def slack_webhook
        @slack_webhook ||= InstallationConfig.find_by(name: 'AI_AGENT_HEALTH_SLACK_WEBHOOK')&.value.to_s.strip
      end

      def alert_emails
        @alert_emails ||= InstallationConfig.find_by(name: 'AI_AGENT_HEALTH_ALERT_EMAILS')&.value.to_s
                                            .split(/[,;\s]+/).map(&:strip).reject(&:empty?)
      end

      def redis_available?
        defined?($alfred) && $alfred.present?
      end

      def redis_get(key)
        $alfred.with { |c| c.get(key) }
      end

      def redis_setex(key, ttl, value)
        $alfred.with { |c| c.setex(key, ttl, value) }
      end
    end
  end
end
