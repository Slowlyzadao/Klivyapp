module Api
  module V1
    module AiAgent
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
      class HealthController < ApplicationController
        skip_before_action :authenticate_user!, raise: false
        skip_before_action :verify_authenticity_token, raise: false

        def show
          snapshot = ::AiAgent::Health::Checker.call
          http_status = snapshot.status == 'down' ? :service_unavailable : :ok
          render json: snapshot.to_h, status: http_status
        end
      end
    end
  end
end
