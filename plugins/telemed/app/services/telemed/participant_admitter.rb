# Admite um paciente na sala LiveKit (libera canPublish=true).
# Usado pelo dentista quando clica "Aceitar" no card de entrada solicitada.
#
# 2026-05-21 — Antes a admissão era 100% client-side (data channel msg).
# Paciente podia bypassar via DevTools e publicar de qualquer jeito. Agora:
# o token do paciente é emitido com canPublish=false, e quando o dentista
# admite, o BACKEND chama UpdateParticipant no LiveKit pra setar
# canPublish=true server-side. LiveKit dispara ParticipantPermissionsChanged
# no client do paciente, que aí publica câmera/mic (path `applyAdmit`).
#
# Persiste registro em event.custom_attributes['telemed_session']['admissions']
# pra audit + recovery (se dentista recarrega a página, os pacientes já
# admitidos não voltam pro card "ENTRADA SOLICITADA").
require 'livekit'

module Telemed
  class ParticipantAdmitter
    Result = Struct.new(:ok, :admitted_at, :error, keyword_init: true) do
      def ok? = !!ok
    end

    def initialize(event:, identity:)
      @event    = event
      @identity = identity.to_s
      @creds    = CredentialsResolver.new(account: event.account).call
    end

    def call
      return Result.new(ok: false, error: 'credentials_missing') unless @creds.configured?
      return Result.new(ok: false, error: 'identity_blank')      if @identity.blank?
      return Result.new(ok: false, error: 'not_a_patient')       unless @identity.start_with?('patient-')

      admitted_at = Time.current

      # Libera publish do paciente no LiveKit. Permission é cumulativo —
      # passamos só os flags que mudam; o resto (canSubscribe) já estava true.
      client.update_participant(
        room:       room_name,
        identity:   @identity,
        permission: LiveKit::Proto::ParticipantPermission.new(
          can_publish:      true,
          can_subscribe:    true,
          can_publish_data: true
        )
      )

      persist_admission!(admitted_at)
      Result.new(ok: true, admitted_at: admitted_at)
    rescue Twirp::Error, StandardError => e
      Rails.logger.warn("[Telemed::ParticipantAdmitter] falhou identity=#{@identity} event=#{@event.id} err=#{e.class}: #{e.message}")
      Result.new(ok: false, error: e.message)
    end

    private

    def client
      @client ||= LiveKit::RoomServiceClient.new(@creds.url, api_key: @creds.api_key, api_secret: @creds.api_secret)
    end

    def room_name
      "klivy-acc#{@event.account_id}-event#{@event.id}"
    end

    # Extrai patient_id da identity `patient-{ID}-{nonce}`.
    # Identity completa tem nonce hex de 8 chars pra evitar "duplicate identity"
    # no LiveKit em F5/reconnect (ver SessionIssuer#identity). Pra persistir
    # admissão de forma estável (sobrevive reload do paciente), chave por
    # patient_id puro.
    def patient_id_from_identity
      m = @identity.match(/\Apatient-(\d+)/)
      m && m[1]
    end

    # Marca o paciente como admitido no JSONB do evento.
    #
    # 2026-05-21 — Persiste por `patient_id` (não pela identity completa).
    # Se paciente recarregar a página, nova identity (novo nonce) ainda
    # casa via patient_id → patient_sessions_controller emite token com
    # admitted=true direto, sem precisar passar de novo pelo card "Aceitar".
    #
    # `last_identity` registra a identity da última admissão pra dashboard
    # reidratar o card pendente (filtra a identity ativa quando re-monta).
    def persist_admission!(admitted_at)
      pid = patient_id_from_identity
      return unless pid

      attrs = (@event.custom_attributes || {}).deep_dup
      session = (attrs['telemed_session'] || {})
      admissions = (session['admissions'] || {})
      admissions[pid] = {
        'admitted_at'   => admitted_at.iso8601,
        'last_identity' => @identity
      }
      session['admissions'] = admissions
      attrs['telemed_session'] = session
      @event.update_columns(custom_attributes: attrs, updated_at: Time.current)
    end
  end
end
