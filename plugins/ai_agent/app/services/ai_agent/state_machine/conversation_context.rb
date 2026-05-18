module AiAgent
  module StateMachine
    # Layer determinística por cima da `ConversationState.working_memory`
    # pra rastrear (a) qual oferta a Bea acabou de fazer ao paciente
    # (`pending_offer`) e (b) qual ação ela acabou de executar
    # (`last_completed`). Resolve dois bugs crônicos do LLM:
    #
    #   1. Paciente responde "Sim" depois de uma oferta, e o LLM perde
    #      o contexto de qual oferta foi. Aqui guardamos a oferta na
    #      hora que a tool `search_available_slots` roda; quando o
    #      próximo turno chega com confirmação curta, agimos sem o LLM.
    #
    #   2. Paciente responde "Sim" DEPOIS de uma ação já ter sido
    #      executada (book/reschedule/cancel). Sem state, o LLM tende
    #      a re-disparar a mesma ação. Aqui marcamos a conclusão
    #      assim que a tool retorna sucesso, e respondemos
    #      determinísticamente "já está feito".
    #
    # TTL de 10 min: ofertas e conclusões mais antigas que isso são
    # ignoradas — paciente provavelmente está em outro contexto.
    class ConversationContext
      # Confirmação pura. Não captura "sim, mas mais tarde" porque tem
      # conteúdo extra — esses caem no LLM normal.
      CONFIRMATION_REGEX = /\A\s*(sim|s|ok|pode|quero|confirmo|confirmado|fechado|beleza|isso|claro|por favor|com certeza|certo|aceito|combinado)[\s.!?]*\z/i

      TTL_SECONDS = 600

      def initialize(state)
        @state = state
      end

      def confirmation?(message)
        message.to_s.strip.match?(CONFIRMATION_REGEX)
      end

      def memory
        @state.working_memory ||= {}
      end

      # ─── pending_offer ────────────────────────────────────────────

      # `starts_at` (e demais campos do "primeiro slot") existem por
      # compat — confirmação simples ("Sim") ainda usa esse slot.
      # `alternatives` é a lista completa de slots oferecidos no turno —
      # quando o paciente menciona um horário específico ("Podemos as
      # 11h?"), o pre-LLM matcher procura aqui pra disparar book direto
      # em vez de deixar o LLM responder e arriscar alucinar
      # "esse horário acabou de ser preenchido".
      def offer_slot!(starts_at:, duration_minutes:, service_id:, service_name:,
                      user_id:, professional_name:, target_appointment_id: nil,
                      alternatives: [])
        memory['pending_offer'] = {
          'starts_at' => starts_at,
          'duration_minutes' => duration_minutes.to_i,
          'service_id' => service_id,
          'service_name' => service_name,
          'user_id' => user_id,
          'professional_name' => professional_name,
          # Quando preenchido, indica que o "Sim" do paciente deve
          # disparar reschedule_appointment com esse id, não criar
          # um agendamento novo.
          'target_appointment_id' => target_appointment_id,
          # Lista completa de slots oferecidos: [{starts_at, user_id, professional_name, time, date}, ...]
          'alternatives' => alternatives,
          'at' => Time.current.to_i
        }
        memory.delete('last_completed')
        save!
      end

      # Procura entre os slots oferecidos qual bate com o horário
      # mencionado pelo paciente. Retorna o slot inteiro (mesma forma
      # que pending_offer principal) pra que `book_from_offer` consiga
      # executar deterministicamente.
      #
      # Regex pega "11h", "11:00", "11:30", "às 11", "as 11", "11 da
      # manhã/tarde", etc. Sempre extrai HH e (opcional) MM.
      def offer_match_for(message)
        offer = pending_offer
        return nil if offer.nil?

        alternatives = offer['alternatives']
        return nil unless alternatives.is_a?(Array) && alternatives.any?

        wanted_minutes = parse_hour_from_message(message)
        return nil if wanted_minutes.nil?

        alt = alternatives.find { |a| slot_minutes_of(a) == wanted_minutes }
        return nil if alt.nil?

        # Reconstrói o offer principal apontando pro slot escolhido,
        # preservando o resto dos campos (service_id, name, target).
        offer.merge(
          'starts_at' => alt['starts_at'],
          'user_id' => alt['user_id'],
          'professional_name' => alt['professional_name']
        )
      end

      private

      def parse_hour_from_message(message)
        s = message.to_s.downcase
        # "11h", "11:00", "11:30", "11h30", "as 11", "às 11", "11 da manhã"
        m = s.match(/\b(\d{1,2})\s*[h:]?(?:\s*(\d{2}))?\s*(?:da\s+manh[aã]|da\s+tarde|da\s+noite)?\b/)
        return nil if m.nil?

        hour = m[1].to_i
        minutes = m[2].to_i
        return nil unless hour.between?(0, 23) && minutes.between?(0, 59)

        (hour * 60) + minutes
      end

      def slot_minutes_of(alt)
        # alt['starts_at'] é ISO8601 com timezone — ex: "2026-05-13T11:00:00-03:00"
        s = alt['starts_at'].to_s
        m = s.match(/T(\d{2}):(\d{2})/)
        return nil if m.nil?

        (m[1].to_i * 60) + m[2].to_i
      end

      public

      # ─── recent listing (pra distinguir book de reschedule) ──────

      def remember_listed_appointment!(appointment_id)
        memory['recent_listed_appointment_id'] = appointment_id
        memory['recent_listed_at'] = Time.current.to_i
        save!
      end

      def recent_listed_appointment_id
        return nil unless memory['recent_listed_at']
        return nil if memory['recent_listed_at'].to_i < (Time.current.to_i - 60)

        memory['recent_listed_appointment_id']
      end

      def pending_offer
        offer = memory['pending_offer']
        return nil if offer.nil?
        return nil if offer['at'].to_i < (Time.current.to_i - TTL_SECONDS)

        offer
      end

      def clear_offer!
        memory.delete('pending_offer')
        save!
      end

      # ─── last_completed ───────────────────────────────────────────

      # type: 'booked' | 'rescheduled' | 'cancelled'
      def mark_completed!(type:, summary:)
        memory['last_completed'] = {
          'type' => type,
          'summary' => summary,
          'at' => Time.current.to_i
        }
        memory.delete('pending_offer')
        save!
      end

      def recent_completed
        c = memory['last_completed']
        return nil if c.nil?
        return nil if c['at'].to_i < (Time.current.to_i - TTL_SECONDS)

        c
      end

      def clear_completed!
        memory.delete('last_completed')
        save!
      end

      # ─── active_service (qual serviço está em discussão) ─────────

      # Marca qual serviço está sendo agendado/discutido AGORA.
      # Setado quando search_available_slots roda (LLM já decidiu o
      # service_id). Se um turno seguinte do paciente for ambíguo
      # ("agende pra depois de amanhã"), Bea continua nesse serviço
      # em vez de pular pra outro só porque há outro mais recente
      # bem-sucedido no histórico — bug clássico de anchor bias do LLM.
      def set_active_service!(id:, name:)
        memory['active_service'] = {
          'id' => id,
          'name' => name,
          'at' => Time.current.to_i
        }
        save!
      end

      def active_service
        s = memory['active_service']
        return nil if s.nil?
        return nil if s['at'].to_i < (Time.current.to_i - TTL_SECONDS)

        s
      end

      def clear_active_service!
        memory.delete('active_service')
        save!
      end

      # ─── active_patient (paciente alvo do agendamento atual) ─────
      #
      # Setado quando `create_patient_minimal` cria uma ficha (especialmente
      # is_third_party: pai agendando pra filho). Persiste por 10min pra
      # sobreviver à conversa típica de coleta de info.
      #
      # O bug que isso resolve: depois de criar a ficha do terceiro, a
      # conversa segue por vários turnos (perguntar serviço, dia, horário).
      # No turno final do book_appointment, o LLM às vezes esqueceu o
      # patient_id (caiu fora da janela de 10 mensagens) e o evento foi
      # parar no Patient da pessoa que tava conversando, não no terceiro.
      # O wrapper do book_appointment usa esse estado pra auto-injetar o
      # patient_id quando o LLM omite.
      def set_active_patient!(id:, name:, is_third_party: false, is_minor: false)
        memory['active_patient'] = {
          'id' => id,
          'name' => name,
          'is_third_party' => is_third_party,
          'is_minor' => is_minor,
          'at' => Time.current.to_i
        }
        save!
      end

      def active_patient
        p = memory['active_patient']
        return nil if p.nil?
        return nil if p['at'].to_i < (Time.current.to_i - TTL_SECONDS)

        p
      end

      def clear_active_patient!
        memory.delete('active_patient')
        save!
      end

      private

      def save!
        @state.update!(working_memory: memory)
      end
    end
  end
end
