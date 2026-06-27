class Financial::AgendaAnalyticsService
  DAYS   = %w[Segunda Terça Quarta Quinta Sexta Sábado].freeze
  # Slots de 30min das 07h às 20h = 26 slots
  SLOTS  = (7..19).flat_map { |h| ["#{h.to_s.rjust(2, '0')}:00", "#{h.to_s.rjust(2, '0')}:30"] }.freeze

  # Status que indicam que o paciente efetivamente compareceu
  ATTENDANCE_STATUS = %w[arrived in_progress completed].freeze

  def initialize(account:, weeks: 12)
    @account = account
    @weeks   = weeks.to_i
    @range   = @weeks.weeks.ago.beginning_of_week..Time.zone.now
  end

  def call
    rows = fetch_rows

    # Montar matriz [hora_slot][dia_semana] → {ocupacao_pct, agendamentos, receita_media}
    matrix = build_matrix(rows)

    pico = find_peak(matrix)

    {
      matrix: matrix,
      days: DAYS,
      slots: SLOTS,
      peak: pico,
      period_weeks: @weeks
    }
  end

  private

  def fetch_rows
    AgendaEvent
      .where(account_id: @account.id, starts_at: @range)
      .select(
        'EXTRACT(DOW FROM starts_at)::integer AS dow',
        'EXTRACT(HOUR FROM starts_at)::integer AS hora',
        'CASE WHEN EXTRACT(MINUTE FROM starts_at) < 30 THEN 0 ELSE 1 END AS slot_half',
        'COUNT(*) AS total',
        "SUM(CASE WHEN status IN ('arrived', 'in_progress', 'completed') THEN 1 ELSE 0 END) AS comparecidos"
      )
      .group('dow', 'hora', 'slot_half')
  end

  def build_matrix(rows)
    matrix = empty_matrix
    global_max = rows.map { |r| r.total.to_i }.max.to_f
    rows.each { |r| fill_cell(matrix, r, global_max) }
    matrix
  end

  def empty_matrix
    Array.new(SLOTS.size) { Array.new(DAYS.size) { { ocupacao_pct: 0, agendamentos: 0, comparecidos: 0, receita_media: 0.0 } } }
  end

  def fill_cell(matrix, row, global_max)
    dia_idx, slot_idx = resolve_indexes(row)
    return if dia_idx.nil?

    total = row.total.to_i
    pct   = global_max.positive? ? (total.to_f / global_max * 100).round(1) : 0.0
    write_cell(matrix, slot_idx, dia_idx, { total: total, pct: pct, row: row })
  end

  def resolve_indexes(row)
    # DOW: 0=domingo, 1=segunda … 6=sábado → queremos segunda=0 … sábado=5
    dia_idx  = row.dow.to_i - 1
    return [nil, nil] unless dia_idx.between?(0, DAYS.size - 1)

    slot_idx = ((row.hora.to_i - 7) * 2) + row.slot_half.to_i
    return [nil, nil] unless slot_idx.between?(0, SLOTS.size - 1)

    [dia_idx, slot_idx]
  end

  def write_cell(matrix, slot_idx, dia_idx, opts)
    matrix[slot_idx][dia_idx] = {
      ocupacao_pct: opts[:pct],
      agendamentos: opts[:total],
      comparecidos: opts[:row].comparecidos.to_i,
      receita_media: 0.0  # AgendaEvent não possui campo de valor — futuro: vincular Financial::Entry
    }
  end

  def find_peak(matrix)
    best = { pct: 0, slot: nil, day: nil }
    matrix.each_with_index do |slots, si|
      slots.each_with_index do |cell, di|
        best = { pct: cell[:ocupacao_pct], slot: SLOTS[si], day: DAYS[di] } if cell[:ocupacao_pct] > best[:pct]
      end
    end
    best
  end
end
