class Financial::PatientRetentionService
  def initialize(account:, months: 12)
    @account = account
    @months  = months.to_i
  end

  def call
    monthly_data = []

    @months.downto(1).map do |n|
      ref   = n.months.ago
      range = ref.beginning_of_month..ref.end_of_month.end_of_day
      monthly_data << build_month(ref, range)
    end

    alert = consecutive_low_returning?(monthly_data)

    {
      monthly: monthly_data,
      alert: alert,
      meta_pct: 65.0
    }
  end

  private

  def patient_ids_in(range)
    AgendaEvent
      .where(account_id: @account.id, starts_at: range)
      .where.not(contact_id: nil)
      .distinct
      .pluck(:contact_id)
  end

  # Single query to load first event month for all contacts (eliminates N+1)
  def first_event_months
    @first_event_months ||= AgendaEvent
      .where(account_id: @account.id)
      .where.not(contact_id: nil)
      .group(:contact_id)
      .minimum(:starts_at)
      .transform_values { |v| v&.to_date&.beginning_of_month }
  end

  def build_month(ref, range)
    patients = patient_ids_in(range)
    novos, recorrentes = classify_patients(patients, ref.beginning_of_month)
    build_totals(ref, novos, recorrentes)
  end

  def classify_patients(patients, month_start)
    novos = 0
    recorrentes = 0
    firsts = first_event_months
    patients.each do |cid|
      first = firsts[cid]
      first.nil? || first >= month_start ? (novos += 1) : (recorrentes += 1)
    end
    [novos, recorrentes]
  end

  def build_totals(ref, novos, recorrentes)
    total = novos + recorrentes
    pct   = total.positive? ? (recorrentes.to_f / total * 100).round(1) : 0.0
    { mes: ref.strftime('%b/%y'), novos: novos, recorrentes: recorrentes, total: total, pct_recorrentes: pct }
  end

  def consecutive_low_returning?(data)
    last_two = data.last(2)
    last_two.length == 2 && last_two.all? { |m| m[:pct_recorrentes] < 50 }
  end
end
