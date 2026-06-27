# Endpoint público de health da Bea — pensado pra ser plugado em
# uptime checker externo (UptimeRobot, BetterUptime, etc).
#
# Retorna 200 quando ok/degraded/idle e 503 quando down (algum alerta
# critical). A diferença entre "degraded" e "down" é deliberada:
# degraded continua respondendo a paciente (alguma métrica fora do
# ideal); down quer dizer que a Bea está efetivamente quebrada
# (provider primário fora, taxa de erro acima do teto).
#
# Sem auth — é health check, deve ser acessível pra qualquer probe.
#
# SEC-27 (auditoria 2026-05-18): retorna SOMENTE `status` + `checked_at`.
# Antes vazava `snapshot.to_h` completo — error rates por provider,
# names de modelo configurados, alert counts. Atacante mapeava estado
# operacional da plataforma sem auth. Detalhes operacionais migraram
# pro endpoint autenticado `dashboard/health` (super admin only).
class Api::V1::AiAgent::HealthController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :verify_authenticity_token, raise: false

  PUBLIC_FIELDS = %i[status checked_at].freeze

  def show
    snapshot = ::AiAgent::Health::Checker.call
    http_status = snapshot.status == 'down' ? :service_unavailable : :ok
    full = snapshot.to_h
    public_payload = PUBLIC_FIELDS.each_with_object({}) do |key, h|
      h[key] = full[key] if full.key?(key)
    end
    # `checked_at` pode não existir no snapshot — adiciona timestamp atual
    # como fallback pra probes saberem que a resposta é "fresca".
    public_payload[:checked_at] ||= Time.current.iso8601
    render json: public_payload, status: http_status
  end
end
