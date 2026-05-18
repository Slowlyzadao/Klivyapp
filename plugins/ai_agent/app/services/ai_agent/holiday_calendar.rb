module AiAgent
  # National Brazilian fixed holidays. Easter-based variable holidays
  # (Carnaval, Sexta-Feira Santa, Corpus Christi) intentionally NOT included
  # yet — adding them requires Easter date computation, which expands scope
  # past Sprint A. Add when first clinic asks. State/municipal holidays
  # follow the same path: per-account override list, not hardcoded here.
  class HolidayCalendar
    FIXED_NATIONAL = [
      [1, 1,   'Confraternização Universal'],
      [4, 21,  'Tiradentes'],
      [5, 1,   'Dia do Trabalho'],
      [9, 7,   'Independência'],
      [10, 12, 'Nossa Senhora Aparecida'],
      [11, 2,  'Finados'],
      [11, 15, 'Proclamação da República'],
      [12, 25, 'Natal']
    ].freeze

    # Returns the soonest fixed national holiday on or after `today`, within
    # `days` days. Looks across this year and next so a query in late
    # December still finds January 1. Returns nil if no holiday in window.
    def self.next_within(today, days: 30)
      candidates = []
      [today.year, today.year + 1].each do |year|
        FIXED_NATIONAL.each do |month, day, name|
          date = Date.new(year, month, day)
          delta = (date - today).to_i
          next if delta.negative? || delta > days

          candidates << { date: date, name: name, days_away: delta }
        end
      end
      candidates.min_by { |c| c[:date] }
    end
  end
end
