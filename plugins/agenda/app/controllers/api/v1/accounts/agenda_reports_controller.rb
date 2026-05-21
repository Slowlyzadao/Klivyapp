class Api::V1::Accounts::AgendaReportsController < Api::V1::Accounts::BaseController
  def summary
    events = Current.account.agenda_events
    events = events.where(user_id: params[:user_id]) if params[:user_id].present?

    current_range = parse_range(params[:since], params[:until])
    previous_range = compute_previous_range(current_range)

    current_events = events.where(starts_at: current_range[:from]..current_range[:to])
    previous_events = events.where(starts_at: previous_range[:from]..previous_range[:to])

    schedule = parse_schedule_params

    render json: {
      current: build_metrics(current_events, current_range, schedule),
      previous: build_metrics(previous_events, previous_range, schedule),
      range: { from: current_range[:from], to: current_range[:to] },
      previous_range: { from: previous_range[:from], to: previous_range[:to] },
      status_breakdown: status_breakdown(current_events),
      daily_distribution: daily_distribution(current_events, current_range),
      agent_performance: agent_performance(current_events),
      schedule_info: schedule
    }
  end

  # GET /api/v1/accounts/:account_id/agenda_reports/forecast
  # Returns predicted appointments for the next N days based on historical patterns
  def forecast
    events = Current.account.agenda_events
    events = events.where(user_id: params[:user_id]) if params[:user_id].present?

    horizon_days = (params[:days] || 7).to_i.clamp(1, 90)
    schedule = parse_schedule_params

    # Historical window: look at the previous 28 days for pattern
    history_days = 28
    history_from = history_days.days.ago.beginning_of_day
    history_to   = Time.zone.now.end_of_day

    historical = events.where(starts_at: history_from..history_to)

    render json: {
      forecast: build_forecast(historical, horizon_days, schedule),
      horizon_days: horizon_days,
      history_days: history_days
    }
  end

  private

  def parse_range(since_param, until_param)
    tz = Time.zone
    from = since_param.present? ? tz.parse(since_param).beginning_of_day : tz.now.beginning_of_day
    to = until_param.present? ? tz.parse(until_param).end_of_day : tz.now.end_of_day
    { from: from, to: to }
  end

  def compute_previous_range(current_range)
    duration = current_range[:to] - current_range[:from]
    {
      from: current_range[:from] - duration,
      to: current_range[:from] - 1.second
    }
  end

  # Parse schedule params sent from frontend localStorage settings
  # Expected: open_hour, close_hour, lunch_duration_minutes, slot_minutes, open_days (comma-separated day indices 0-6)
  def parse_schedule_params
    open_hour   = (params[:open_hour]   || 9).to_i.clamp(0, 23)
    close_hour  = (params[:close_hour]  || 18).to_i.clamp(0, 23)
    lunch_mins  = (params[:lunch_duration_minutes] || 0).to_i.clamp(0, 120)
    slot_mins   = (params[:slot_minutes] || 30).to_i.clamp(15, 120)

    # open_days: 0=Sun,1=Mon,...,6=Sat — default Mon-Fri + Sat(half)
    open_days = if params[:open_days].present?
                  params[:open_days].split(',').map(&:to_i).select { |d| (0..6).cover?(d) }
                else
                  [1, 2, 3, 4, 5, 6] # Mon-Sat default
                end

    work_minutes_per_day = ((close_hour - open_hour) * 60) - lunch_mins
    work_minutes_per_day = [work_minutes_per_day, 0].max
    slots_per_day = (work_minutes_per_day.to_f / slot_mins).floor

    {
      open_hour: open_hour,
      close_hour: close_hour,
      lunch_duration_minutes: lunch_mins,
      slot_minutes: slot_mins,
      work_minutes_per_day: work_minutes_per_day,
      slots_per_day: slots_per_day,
      open_days: open_days
    }
  end

  def build_metrics(events, range, schedule)
    total        = events.count
    confirmed    = events.where(status: 'confirmed').count
    unconfirmed  = events.where(status: 'scheduled').count
    completed    = events.where(status: 'completed').count
    in_progress  = events.where(status: 'in_progress').count
    arrived      = events.where(status: 'arrived').count
    no_show      = events.where(status: 'no_show').count
    cancelled    = events.where(status: 'cancelled').count

    attended     = completed + in_progress + arrived
    # no_show_rate: faltas / total agendamentos (exclui cancelados para não inflar base)
    effective_total = total - cancelled
    no_show_rate    = effective_total.positive? ? (no_show.to_f / effective_total * 100).round(1) : 0.0
    # completion_rate (eficiência): consultados / total efetivo
    completion_rate = effective_total.positive? ? (completed.to_f / effective_total * 100).round(1) : 0.0

    occupancy_rate = compute_occupancy_rate(events, range, schedule)

    {
      total: total,
      confirmed: confirmed,
      unconfirmed: unconfirmed,
      completed: completed,
      in_progress: in_progress,
      arrived: arrived,
      no_show: no_show,
      cancelled: cancelled,
      attended: attended,
      no_show_rate: no_show_rate,
      completion_rate: completion_rate,
      occupancy_rate: occupancy_rate
    }
  end

  def compute_occupancy_rate(events, range, schedule)
    agents = Current.account.users.where(id: events.select(:user_id).distinct)
    return 0.0 if agents.empty? || schedule[:slots_per_day].zero?

    # Count only non-cancelled events (filled slots)
    filled_slots = events.where.not(status: 'cancelled').count

    # Count working days in range respecting open_days config
    working_days = count_working_days(range[:from].to_date, range[:to].to_date, schedule[:open_days])
    working_days = [working_days, 1].max

    total_slots = agents.count * working_days * schedule[:slots_per_day]
    return 0.0 if total_slots.zero?

    (filled_slots.to_f / total_slots * 100).round(1)
  end

  # Count calendar days that fall on open weekdays
  def count_working_days(from_date, to_date, open_days)
    count = 0
    (from_date..to_date).each do |date|
      count += 1 if open_days.include?(date.wday)
    end
    count
  end

  def status_breakdown(events)
    statuses = %w[scheduled confirmed arrived in_progress completed cancelled no_show]
    statuses.index_with { |s| events.where(status: s).count }
  end

  def daily_distribution(events, range)
    days = []
    current_day = range[:from].to_date
    end_day = range[:to].to_date

    while current_day <= end_day
      day_start = current_day.beginning_of_day
      day_end = current_day.end_of_day
      day_events = events.where(starts_at: day_start..day_end)

      days << {
        date: current_day.iso8601,
        label: I18n.l(current_day, format: '%A'),
        total: day_events.count,
        completed: day_events.where(status: 'completed').count,
        no_show: day_events.where(status: 'no_show').count,
        cancelled: day_events.where(status: 'cancelled').count,
        confirmed: day_events.where(status: 'confirmed').count
      }

      current_day += 1.day
    end

    days
  end

  def agent_performance(events)
    agent_ids = events.where.not(user_id: nil).select(:user_id).distinct.pluck(:user_id)
    agents = Current.account.users.where(id: agent_ids)
    agents.map { |agent| agent_metrics(events, agent) }
  end

  def agent_metrics(events, agent)
    agent_events = events.where(user_id: agent.id)
    total        = agent_events.count
    completed    = agent_events.where(status: 'completed').count
    no_show      = agent_events.where(status: 'no_show').count
    cancelled    = agent_events.where(status: 'cancelled').count
    effective    = total - cancelled

    {
      id: agent.id, name: agent.name, avatar_url: agent.avatar_url,
      total: total, completed: completed, no_show: no_show, cancelled: cancelled,
      completion_rate: effective.positive? ? (completed.to_f / effective * 100).round(1) : 0.0,
      no_show_rate: effective.positive? ? (no_show.to_f / effective * 100).round(1) : 0.0
    }
  end

  # Build n-day forecast based on historical day-of-week averages
  def build_forecast(historical, horizon_days, schedule)
    # Group historical events by day-of-week (wday 0=Sun...6=Sat)
    # Calculate average per weekday from full weeks seen
    events_by_wday = Hash.new { |h, k| h[k] = [] }

    # Group historical events by date
    historical.each do |ev|
      wday = ev.starts_at.to_date.wday
      date = ev.starts_at.to_date.iso8601
      events_by_wday[wday] << date
    end

    # Count unique dates per weekday seen in history
    wday_dates = events_by_wday.transform_values { |dates| dates.uniq }
    wday_event_count = events_by_wday.transform_values(&:count)

    # Average events per weekday occurrence
    wday_avg = {}
    (0..6).each do |wday|
      occurrences = wday_dates[wday]&.length || 0
      total_events = wday_event_count[wday] || 0
      wday_avg[wday] = occurrences.positive? ? (total_events.to_f / occurrences).round(1) : 0.0
    end

    forecast_days = []
    today = Time.zone.today
    (1..horizon_days).each do |i|
      date = today + i.days
      next unless schedule[:open_days].include?(date.wday)

      avg = wday_avg[date.wday] || 0.0
      slots = schedule[:slots_per_day]
      occ = slots.positive? ? [(avg / slots * 100).round(1), 100.0].min : 0.0

      forecast_days << {
        date: date.iso8601,
        label: I18n.l(date, format: '%A'),
        predicted_total: avg.round(1),
        predicted_occupancy: occ,
        slots_available: slots,
        day_of_week: date.wday
      }
    end

    forecast_days
  end
end
