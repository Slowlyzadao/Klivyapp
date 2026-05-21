# Emite token JWT pro paciente/profissional entrar na sala LiveKit
# (Sprint K — Telemedicina).
#
# Token é descartável e curto (10 min de TTL por default). Cada clique em
# "Entrar agora" gera um novo — sem precisar guardar URL ou token em lugar
# nenhum. Nome da room é determinístico (account + event) → mesma sala pro
# paciente e pro profissional.
#
# Identity é prefixada com role pra que o front consiga distinguir tracks
# do "doctor" vs "patient" visualmente.
require 'livekit'

module Telemed
  class SessionIssuer
    # TTL do JWT do LiveKit. 10min era curto demais — consultas médias duram
    # 30-50min, e quando a rede do paciente quebra e o cliente tenta reconectar,
    # o LiveKit valida o token de novo. Se ele expirou, o reconnect falha e
    # exige novo "Entrar agora" (o que pode confundir o paciente em pleno
    # atendimento). 2h cobre consultas longas + buffer pra reconexões.
    # O token segue sendo descartável (cada clique gera um novo).
    DEFAULT_TTL = 2.hours

    Result = Struct.new(:url, :token, :room, :room_code, :identity, :name, :role, :ttl_seconds, :dev_mode, keyword_init: true) do
      def to_h
        {
          url: url, token: token, room: room, room_code: room_code,
          identity: identity, name: name, role: role,
          ttl_seconds: ttl_seconds, dev_mode: dev_mode
        }
      end
    end

    def initialize(event:, participant:, role: 'patient', ttl: DEFAULT_TTL)
      @event       = event
      @participant = participant
      @role        = role.to_s
      @ttl         = ttl
      @creds       = CredentialsResolver.new(account: event.account).call
    end

    def call
      raise 'Credenciais LiveKit ausentes' unless @creds.configured?

      token = LiveKit::AccessToken.new(
        api_key:    @creds.api_key,
        api_secret: @creds.api_secret,
        identity:   identity,
        name:       participant_name,
        ttl:        @ttl.to_i
      )
      token.video_grant = LiveKit::VideoGrant.new(
        roomJoin:     true,
        room:         room_name,
        canPublish:   true,
        canSubscribe: true
      )

      Result.new(
        url:         @creds.url,
        token:       token.to_jwt,
        room:        room_name,
        room_code:   room_code,
        identity:    identity,
        name:        participant_name,
        role:        @role,
        ttl_seconds: @ttl.to_i,
        dev_mode:    @creds.dev_mode?
      )
    end

    private

    def room_name
      "klivy-acc#{@event.account_id}-event#{@event.id}"
    end

    # "Código da sala" visual estilo Google Meet (`pppp-eeee-aaaa`). Quando
    # o participante é o paciente, usa o id dele direto. Pra doutor, resolve
    # o paciente via event.contact.patient (RoomCode.from_event cuida disso).
    def room_code
      patient_arg = @role == 'patient' ? @participant : nil
      RoomCode.from_event(@event, patient: patient_arg)
    end

    # Identity tem nonce hex de 8 chars pra evitar "duplicate identity" no
    # LiveKit quando o paciente recarrega a página: a sessão antiga ainda
    # pode estar viva no servidor por alguns segundos (timeout default ~30s),
    # e LiveKit rejeita conexão com identity duplicada. Nonce desambigua.
    #
    # Os checks de segurança no frontend casam por PREFIX (`startsWith('doctor-')`,
    # `startsWith('patient-')`), então o sufixo não quebra a defesa do
    # admit/chat_lock. `destinationIdentities` no admit usa a identity COMPLETA
    # vista no ParticipantConnected — também funciona.
    def identity
      "#{@role}-#{@participant.id}-#{SecureRandom.hex(4)}"
    end

    def participant_name
      @participant.try(:name) || @role.capitalize
    end
  end
end
