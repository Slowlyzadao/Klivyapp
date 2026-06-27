module AiAgent
  module Tools
    class SearchAvailableSlotsTool < BaseTool
      # ARCH-3 (audit 2026-05-19): extraído de SearchAvailableSlotsTool#collect_slots
      # e #collect_balanced_slots. Orquestra a coleta multi-dia delegando
      # cada dia pra `SlotAllocator`.
      #
      # Quando period='qualquer' (default), junta manhã + tarde e oferece um
      # LEQUE do dia (cedo → meio → ÚLTIMO horário), limitado a MAX_RESULTS.
      # Representa a faixa INTEIRA pra não esconder os horários mais tarde
      # (ex.: 17h) nem despejar só os primeiros da manhã.
      #
      # Quando period é específico ('manha'/'tarde'/'noite'), pega
      # diretamente até MAX_RESULTS slots desse período.
      #
      # `find_day_config` é exposto como método de classe pra reuso no
      # main tool (`closed_window_gap`).
      class PeriodDistributor
        # Spec BIA (passo 2.1): "oferecer de 2 a 3 horários". Cap em 3 pra
        # nunca metralhar o paciente — a Bia mostra os 2-3 que a tool der.
        MAX_RESULTS = 3
        # Pool coletado antes de escolher o "leque" do período/dia. Maior que
        # MAX_RESULTS pra conseguir representar a FAIXA inteira (cedo→tarde).
        SPREAD_POOL = 16

        DAY_SHORT_LABELS = {
          0 => 'domingo',
          1 => 'segunda',
          2 => 'terça',
          3 => 'quarta',
          4 => 'quinta',
          5 => 'sexta',
          6 => 'sábado'
        }.freeze

        def self.call(**kwargs)
          new(**kwargs).call
        end

        # Compartilhado entre PeriodDistributor (collect_period_slots) e
        # SearchAvailableSlotsTool#closed_window_gap. Pure function.
        def self.find_day_config(week_days, wday)
          target = DAY_SHORT_LABELS[wday]
          week_days.find do |d|
            normalized = d['label'].to_s.downcase.sub(/-feira$/, '').strip
            normalized.start_with?(target)
          end
        end

        def initialize(period:, from:, to:, setting:, duration:, zone:, now_local:, professionals:, blocking_per_user:,
                       requested_minutes: nil)
          @period = normalize(period)
          @from = from
          @to = to
          @setting = setting
          @duration = duration
          @zone = zone
          @now_local = now_local
          @professionals = professionals
          @blocking_per_user = blocking_per_user
          @requested_minutes = requested_minutes
        end

        def call
          # Período específico ('manha'/'tarde'/'noite'): NÃO despeja os 3
          # PRIMEIROS slots (que dão a falsa impressão de que não há nada mais
          # tarde — ex.: oferecer 13h/14h/15h e o paciente achar que 15h é o
          # último, mesmo a clínica indo até 18h). Em vez disso, coleta um pool
          # e oferece um LEQUE (cedo → meio → tarde, sempre incluindo o ÚLTIMO
          # horário) dentro do primeiro dia com vaga. Em 'qualquer', balanceia
          # manhã + tarde.
          base = if @period == 'qualquer'
                   collect_balanced
                 else
                   spread_within_first_day(collect_period_slots(@period, SPREAD_POOL))
                 end
          # Se o paciente pediu um horário EXATO (ex.: "tem às 17h?"), garante
          # que ele apareça se estiver livre — vale TAMBÉM no 'qualquer', que
          # antes saía cedo e ignorava o pedido, negando um horário real.
          ensure_requested_slot(base, requested_time_pool)
        end

        private

        # Oferece um leque representativo do período no primeiro dia com vaga
        # (sempre o primeiro e o ÚLTIMO horário daquele dia). Se o dia tiver
        # poucos slots, completa com o próximo dia.
        def spread_within_first_day(slots)
          return slots if slots.size <= MAX_RESULTS

          picked = []
          slots.group_by { |s| s[:date] }.each_value do |day_slots|
            picked.concat(spread(day_slots, MAX_RESULTS - picked.size))
            break if picked.size >= MAX_RESULTS
          end
          picked.first(MAX_RESULTS)
        end

        # `n` slots distribuídos uniformemente, incluindo SEMPRE o primeiro e o
        # último da lista (representa a faixa inteira).
        def spread(slots, count)
          return [] if count <= 0
          return slots if slots.size <= count
          return [slots.last] if count == 1

          (0...count).map { |i| slots[(i * (slots.size - 1) / (count - 1.0)).round] }.uniq
        end

        # Se o paciente pediu um horário específico e ele EXISTE livre no pool,
        # garante que apareça na oferta — senão a Bia negaria um horário real.
        # Horário QUEBRADO (14:15, 14:30) nunca está no pool (a grade anda
        # pela duração a partir da abertura) — valida o minuto EXATO direto.
        # A oferta espontânea continua só com a grade redonda.
        def ensure_requested_slot(offer, pool)
          return offer if @requested_minutes.nil?
          return offer if offer.any? { |s| slot_minutes(s) == @requested_minutes }

          match = pool.find { |s| slot_minutes(s) == @requested_minutes }
          match ||= exact_requested_slot
          return offer if match.nil?

          ([match] + offer).first(MAX_RESULTS).sort_by { |s| s[:starts_at] }
        end

        # Primeiro dia da janela em que o horário exato pedido está livre.
        def exact_requested_slot
          cursor = @from
          while cursor <= @to
            cfg = self.class.find_day_config(@setting.week_days, cursor.wday)
            hit = SlotAllocator.call(
              date: cursor, cfg: cfg, duration: @duration, period: 'qualquer',
              zone: @zone, now_local: @now_local, professionals: @professionals,
              blocking_per_user: @blocking_per_user, remaining: 1,
              exact_minutes: @requested_minutes
            )
            return hit.first if hit.any?

            cursor = cursor.next_day
          end
          nil
        end

        # Pool fundo NO PERÍODO do horário exato pedido, pra localizar um slot
        # tardio (ex.: 17h) que o leque padrão/balanceado não trouxe.
        def requested_time_pool
          return [] if @requested_minutes.nil?

          collect_period_slots(period_for_minutes(@requested_minutes), SPREAD_POOL)
        end

        def period_for_minutes(minutes)
          return 'manha' if minutes < (12 * 60)
          return 'tarde' if minutes < (18 * 60)

          'noite'
        end

        def slot_minutes(slot)
          h, m = slot[:time].to_s.split(':').map(&:to_i)
          ((h || 0) * 60) + (m || 0)
        end

        # Junta manhã + tarde num pool fundo e oferece o LEQUE do dia (cedo →
        # meio → ÚLTIMO horário). Antes pegava só os 2 primeiros de cada
        # período, escondendo os horários mais tarde (ex.: 17h) e fazendo o
        # paciente achar que a clínica fecha cedo.
        def collect_balanced
          morning   = collect_period_slots('manha', SPREAD_POOL)
          afternoon = collect_period_slots('tarde', SPREAD_POOL)
          pool = (morning + afternoon).sort_by { |s| s[:starts_at] }
          spread_within_first_day(pool)
        end

        def collect_period_slots(period, limit)
          slots = []
          cursor = @from

          while cursor <= @to && slots.size < limit
            cfg = self.class.find_day_config(@setting.week_days, cursor.wday)
            slots.concat(
              SlotAllocator.call(
                date: cursor, cfg: cfg, duration: @duration, period: period,
                zone: @zone, now_local: @now_local, professionals: @professionals,
                blocking_per_user: @blocking_per_user, remaining: limit - slots.size
              )
            )
            cursor = cursor.next_day
          end

          slots
        end

        def normalize(period)
          period.to_s.downcase.tr('ãâá', 'aaa').strip
        end
      end
    end
  end
end
