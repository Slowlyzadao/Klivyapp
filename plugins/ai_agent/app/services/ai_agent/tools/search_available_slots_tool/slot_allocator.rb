module AiAgent
  module Tools
    class SearchAvailableSlotsTool < BaseTool
      # ARCH-3 (audit 2026-05-19): extraído de SearchAvailableSlotsTool#slots_for_day.
      # Gera slots disponíveis pra UMA data específica, dado:
      #   - configuração do dia (cfg: hash com start/end/lunchStart/lunchEnd/enabled)
      #   - duração do serviço (em minutos — step do iterador)
      #   - filtro de período ("manha"/"tarde"/"noite"/"qualquer")
      #   - profissionais habilitados pro serviço
      #   - mapa de eventos bloqueantes por user_id (pré-carregado pela tool)
      #
      # Step pela DURAÇÃO do serviço (não pelo slot_interval da clínica).
      # Slot é incluído se: (a) está dentro da janela aberta, (b) não bate
      # com horário de almoço, (c) atende ao filtro de período, (d) é
      # futuro (>= now_local), (e) tem AO MENOS 1 profissional livre.
      #
      # Cada slot retornado lista `available_with: [{id, name}]` pra Bea
      # poder oferecer pelo nome ("9h com Dra. Ana ou Dr. Carlos").
      class SlotAllocator
        DAY_FULL_LABELS = {
          0 => 'domingo',
          1 => 'segunda-feira',
          2 => 'terça-feira',
          3 => 'quarta-feira',
          4 => 'quinta-feira',
          5 => 'sexta-feira',
          6 => 'sábado'
        }.freeze

        def self.call(**kwargs)
          new(**kwargs).call
        end

        def initialize(date:, cfg:, duration:, period:, zone:, now_local:, professionals:, blocking_per_user:, remaining:,
                       exact_minutes: nil)
          @date = date
          @cfg = cfg
          @duration = duration
          @period = period
          @zone = zone
          @now_local = now_local
          @professionals = professionals
          @blocking_per_user = blocking_per_user
          @remaining = remaining
          @exact_minutes = exact_minutes
        end

        def call
          return [] if @cfg.nil? || !@cfg['enabled']

          open_start = parse_minutes(@cfg['start'])
          open_end   = parse_minutes(@cfg['end'])
          return [] if open_start.nil? || open_end.nil?

          lunch_start = parse_minutes(@cfg['lunchStart'])
          lunch_end   = parse_minutes(@cfg['lunchEnd'])

          # Modo HORÁRIO EXATO: valida o minuto pedido pelo paciente (14:15,
          # 14:30...) com as MESMAS regras da grade. A grade anda pela duração
          # a partir da abertura e nunca contém horário quebrado — sem este
          # modo a Bia negava horário livre de verdade.
          return exact_slot(open_start, open_end, lunch_start, lunch_end) if @exact_minutes

          out = []
          slot_min = open_start

          while slot_min + @duration <= open_end && out.size < @remaining
            unless skip_slot?(slot_min, lunch_start, lunch_end)
              slot_time = @zone.local(@date.year, @date.month, @date.day, slot_min / 60, slot_min % 60)

              if slot_time >= @now_local
                available_with = @professionals.reject do |u|
                  overlaps?(slot_time, @blocking_per_user[u.id] || [])
                end
                out << format_slot(slot_time, available_with) if available_with.any?
              end
            end
            slot_min += @duration
          end

          out
        end

        private

        # Um único slot no minuto exato pedido — mesmas regras da grade:
        # dentro do expediente (com a duração cabendo antes do fechamento),
        # fora do almoço, no futuro e com pelo menos 1 profissional livre.
        def exact_slot(open_start, open_end, lunch_start, lunch_end)
          m = @exact_minutes.to_i
          return [] if m < open_start || (m + @duration) > open_end
          return [] if in_lunch?(m, lunch_start, lunch_end)

          slot_time = @zone.local(@date.year, @date.month, @date.day, m / 60, m % 60)
          return [] if slot_time < @now_local

          available_with = @professionals.reject { |u| overlaps?(slot_time, @blocking_per_user[u.id] || []) }
          available_with.any? ? [format_slot(slot_time, available_with)] : []
        end

        def skip_slot?(slot_min, lunch_start, lunch_end)
          return true if in_lunch?(slot_min, lunch_start, lunch_end)
          return true unless period_match?(slot_min)

          false
        end

        def in_lunch?(slot_min, lunch_start, lunch_end)
          return false if lunch_start.nil? || lunch_end.nil?

          slot_min < lunch_end && (slot_min + @duration) > lunch_start
        end

        def period_match?(slot_min)
          return true if @period == 'qualquer'

          hour = slot_min / 60
          case @period
          when 'manha' then hour.between?(5, 11)
          when 'tarde' then hour.between?(12, 17)
          when 'noite' then hour >= 18
          else true
          end
        end

        def overlaps?(slot_time, intervals)
          slot_end = slot_time + @duration.minutes
          intervals.any? { |evt_start, evt_end| slot_time < evt_end && slot_end > evt_start }
        end

        def format_slot(slot_time, available_with)
          {
            starts_at: slot_time.iso8601,
            date: slot_time.strftime('%d/%m/%Y'),
            time: slot_time.strftime('%H:%M'),
            weekday: DAY_FULL_LABELS[@date.wday],
            available_with: available_with.map do |u|
              { id: u.id, name: AiAgent::Formatters::ProfessionalName.format(u.name) }
            end
          }
        end

        def parse_minutes(value)
          return nil if value.to_s.empty?

          h, m = value.to_s.split(':').map(&:to_i)
          return nil if h.nil? || m.nil?

          (h * 60) + m
        end
      end
    end
  end
end
