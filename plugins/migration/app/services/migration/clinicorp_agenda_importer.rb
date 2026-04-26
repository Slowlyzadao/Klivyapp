require 'csv'

module Migration
  class ClinicorpAgendaImporter
    BATCH_SIZE = 250
    BR_TZ = 'America/Sao_Paulo'.freeze

    # Default fallback when neither Procedures nor CategoryDescription have value.
    DEFAULT_SERVICE_NAME = 'Consulta'.freeze

    SERVICE_COLOR_PALETTE = %w[
      #ef4444 #f97316 #f59e0b #eab308 #84cc16 #22c55e #10b981 #14b8a6
      #06b6d4 #0ea5e9 #3b82f6 #6366f1 #8b5cf6 #a855f7 #d946ef #ec4899 #f43f5e
    ].freeze

    STATUS_MAP = {
      ''             => 'scheduled',
      'SCHEDULED'    => 'scheduled',
      'PENDING'      => 'scheduled',
      'CONFIRMED'    => 'confirmed',
      'CONFIRMADO'   => 'confirmed',
      'ARRIVED'      => 'arrived',
      'CHECKED_IN'   => 'arrived',
      'CHECKEDIN'    => 'arrived',
      'IN_PROGRESS'  => 'in_progress',
      'INPROGRESS'   => 'in_progress',
      'STARTED'      => 'in_progress',
      'ATTENDED'     => 'completed',
      'COMPLETED'    => 'completed',
      'DONE'         => 'completed',
      'FINISHED'     => 'completed',
      'NO_SHOW'      => 'no_show',
      'NOSHOW'       => 'no_show',
      'MISSED'       => 'no_show',
      'CANCELED'     => 'cancelled',
      'CANCELLED'    => 'cancelled'
    }.freeze

    def initialize(migration_run, csv_content)
      @run = migration_run
      @csv_content = csv_content
      @account = migration_run.account
      @errors = []
      @counters = { created: 0, updated: 0, skipped: 0, errors: 0, processed: 0 }
      @service_cache = {}
      @user_cache = {}
      @patient_cache = {}
      @category_attr = nil
    end

    # AgendaCustomAttribute "Categoria" — created as a SELECT (dropdown) so the
    # event modal shows a friendly picker instead of free text. Options come
    # from the unique CategoryDescription values in the imported CSV; the union
    # of existing options + new options is preserved on re-imports.
    def ensure_category_custom_attribute(category_values)
      values = category_values.compact_blank.uniq
      attr = AgendaCustomAttribute.where(account_id: @account.id)
                                  .where('LOWER(name) = ?', 'categoria').first
      if attr
        existing = attr.options.to_s.split(',').map(&:strip).reject(&:blank?)
        merged = (existing | values).uniq
        attr.update!(field_type: 'select', options: merged.join(',')) if attr.field_type != 'select' || merged != existing
      else
        attr = AgendaCustomAttribute.create!(
          account_id: @account.id,
          name: 'Categoria',
          field_type: 'select',
          required: false,
          options: values.join(','),
          position: AgendaCustomAttribute.where(account_id: @account.id).count
        )
      end
      attr
    end

    def call
      rows = parse_csv
      @run.update!(total_rows: rows.size, processed_rows: 0)

      categories = rows.map { |r| r['CategoryDescription'].to_s.strip }
      @category_attr = ensure_category_custom_attribute(categories)

      rows.each_slice(BATCH_SIZE).with_index do |slice, batch_index|
        slice.each_with_index do |row, idx|
          line_number = (batch_index * BATCH_SIZE) + idx + 2
          process_row(row, line_number)
          @counters[:processed] += 1
        end
        flush_progress!
      end

      flush_progress!(final: true)
      @counters
    end

    private

    def parse_csv
      content = @csv_content.to_s.sub(/\A\xEF\xBB\xBF/, '')
      delim = detect_delimiter(content)
      CSV.parse(content, headers: true, col_sep: delim, liberal_parsing: true).map(&:to_h)
    end

    def detect_delimiter(content)
      first_line = content.lines.first.to_s
      counts = { ',' => first_line.count(','), ';' => first_line.count(';'), "\t" => first_line.count("\t") }
      counts.max_by { |_, v| v }.first
    end

    def process_row(row, line_number)
      h = row.transform_keys { |k| k.to_s.strip }

      patient_name = h['PatientName'].to_s.strip
      dentist_name = h['DentistName'].to_s.strip
      starts_at, ends_at = parse_window(h['date'], h['fromTime'], h['toTime'])

      if starts_at.nil? || ends_at.nil?
        @counters[:skipped] += 1
        log_error(line_number, 'Data ou horário inválido — linha ignorada.')
        return
      end

      if patient_name.blank?
        @counters[:skipped] += 1
        log_error(line_number, 'Sem PatientName — linha ignorada.')
        return
      end

      contact, patient = find_or_create_contact(patient_name, h['MobilePhone'])
      user = find_user(dentist_name)

      # Service (treatment) is created ONLY when the planilha has a real
      # Procedures value. Empty Procedures → no service, treatment stays blank,
      # the event modal shows "Selecione o tratamento".
      proc_name = h['Procedures'].to_s.strip
      service = proc_name.present? ? find_or_create_service(proc_name) : nil

      raw_status = h['Status'].to_s.strip.upcase
      status = STATUS_MAP[raw_status] || 'scheduled'
      status = 'cancelled' if truthy?(h['Canceled']) || truthy?(h['Deleted'])

      external_id = h['id'].to_s.strip
      title = patient_name.presence || 'Compromisso'

      event = AgendaEvent.find_by(account_id: @account.id, custom_attributes: { source: 'clinicorp', external_id: external_id }) if external_id.present?
      if event
        event.update!(
          title: title,
          description: h['Notes'].presence,
          starts_at: starts_at,
          ends_at: ends_at,
          status: status,
          user_id: user&.id,
          contact_id: contact&.id,
          custom_attributes: build_custom_attrs(h, service, external_id, contact, patient)
        )
        @counters[:updated] += 1
      else
        AgendaEvent.create!(
          account_id: @account.id,
          user_id: user&.id,
          contact_id: contact&.id,
          title: title,
          description: h['Notes'].presence,
          starts_at: starts_at,
          ends_at: ends_at,
          status: status,
          event_type: 'appointment',
          custom_attributes: build_custom_attrs(h, service, external_id, contact, patient)
        )
        @counters[:created] += 1
      end

      log_info(line_number, "Sem dentista identificado: '#{dentist_name}'.") if dentist_name.present? && user.nil?
    rescue StandardError => e
      @counters[:errors] += 1
      log_error(line_number, "#{e.class}: #{e.message}")
    end

    # ──────────────────────────────────────────────────────────────────────────
    # Helpers
    # ──────────────────────────────────────────────────────────────────────────

    def truthy?(val)
      %w[true 1 yes sim t].include?(val.to_s.strip.downcase)
    end

    # The Clinicorp `date` column is an ISO-8601 string with Z that, decoded into
    # America/Sao_Paulo, gives the local calendar day at 00:00. Combine that day
    # with `fromTime` / `toTime` (HH:MM, 24h) in the local zone.
    def parse_window(date_iso, from_time, to_time)
      return [nil, nil] if date_iso.blank? || from_time.blank? || to_time.blank?

      tz = ActiveSupport::TimeZone[BR_TZ]
      utc = Time.iso8601(date_iso.to_s)
      local_day = utc.in_time_zone(tz).to_date
      starts = tz.parse("#{local_day} #{from_time}")
      ends   = tz.parse("#{local_day} #{to_time}")
      ends   = ends + 1.day if ends < starts # crosses midnight
      [starts, ends]
    rescue StandardError
      [nil, nil]
    end

    def find_user(name)
      return nil if name.blank?
      return @user_cache[name] if @user_cache.key?(name)

      norm = normalize(name)
      candidate = @account.users.find { |u| normalize(u.name) == norm }
      @user_cache[name] = candidate
    end

    def find_or_create_contact(name, mobile_phone)
      cache_key = "#{normalize(name)}|#{mobile_phone}"
      return @patient_cache[cache_key] if @patient_cache.key?(cache_key)

      norm = normalize(name)
      patient = Patient.where(account_id: @account.id, deleted_at: nil)
                       .where('LOWER(name) = ?', norm).first
      contact = patient&.contact

      contact ||= Contact.where(account_id: @account.id)
                         .where('LOWER(name) = ?', norm).first

      if contact.nil?
        phone = normalize_phone(mobile_phone)
        contact = Contact.create!(
          account_id: @account.id,
          name: name,
          phone_number: phone,
          additional_attributes: { source: 'migration_clinicorp_agenda' }
        )
      end

      # Ensure a Patient row exists and is linked to the Contact so the
      # AgendaEventModal can show it correctly and the timeline keeps working.
      if patient.nil?
        patient = Patient.create!(
          account_id: @account.id,
          name: name,
          phone: contact.phone_number,
          contact_id: contact.id,
          origin: 'migration_clinicorp_agenda'
        )
      elsif patient.contact_id.nil?
        patient.update_columns(contact_id: contact.id)
      end

      @patient_cache[cache_key] = [contact, patient]
    end

    def find_or_create_service(name)
      key = normalize(name)
      return @service_cache[key] if @service_cache.key?(key)

      service = AgendaService.where(account_id: @account.id)
                             .where('LOWER(name) = ?', key).first
      service ||= AgendaService.create!(
        account_id: @account.id,
        name: name,
        duration_minutes: 60,
        color: random_color,
        position: AgendaService.where(account_id: @account.id).count
      )
      @service_cache[key] = service
    end

    def random_color
      SERVICE_COLOR_PALETTE.sample
    end

    def build_custom_attrs(row, service, external_id, contact, patient)
      attrs = {
        'source' => 'clinicorp',
        'external_id' => external_id,
        'service_id' => service&.id,
        'service_name' => service&.name,
        # Display fields the AgendaEventModal expects for showing patient/treatment
        'patient_id' => patient&.id,
        'patient_name' => contact&.name,
        'patient_phone' => contact&.phone_number,
        'patient_avatar_url' => nil,
        # If Procedures is empty, treatment stays nil so the modal renders the
        # placeholder "Selecione o tratamento".
        'treatment' => service&.name,
        'priority' => 'medium',
        'clinicorp_status' => row['Status'].to_s.strip.presence,
        'clinicorp_canceled' => truthy?(row['Canceled']),
        'clinicorp_deleted'  => truthy?(row['Deleted']),
        'cancel_reason' => row['CancelReason'].to_s.strip.presence,
        'cancel_by'     => row['CancelBy'].to_s.strip.presence,
        'canceled_date' => row['CanceledDate'].to_s.strip.presence,
        'mobile_phone' => row['MobilePhone'].to_s.strip.presence
      }.compact

      # Categoria as a real AgendaCustomAttribute (attr_<id>) so it appears in
      # the event modal under "Atributos Personalizados".
      category = row['CategoryDescription'].to_s.strip.presence
      attrs["attr_#{@category_attr.id}"] = category if category
      attrs
    end

    def normalize_phone(value)
      digits = value.to_s.gsub(/\D/, '')
      return nil if digits.length < 8

      digits.start_with?('55') ? "+#{digits}" : "+55#{digits}"
    end

    def normalize(str)
      str.to_s.strip.downcase
    end

    def flush_progress!(final: false)
      @run.update_columns(
        processed_rows: @counters[:processed],
        created_count: @counters[:created],
        updated_count: @counters[:updated],
        skipped_count: @counters[:skipped],
        error_count: @counters[:errors],
        errors_log: @errors.last(200),
        updated_at: Time.current
      )
    end

    def log_error(line, message)
      @errors << { line: line, level: 'error', message: message }
    end

    def log_info(line, message)
      @errors << { line: line, level: 'info', message: message }
    end
  end
end
