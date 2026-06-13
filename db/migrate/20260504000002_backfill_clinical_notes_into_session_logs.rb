class BackfillClinicalNotesIntoSessionLogs < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  BRT = 'America/Sao_Paulo'.freeze
  FALLBACK_PROCEDURE_NAME = 'Evolução clínica (migrada)'.freeze

  def up
    return unless table_exists?(:clinical_notes) && table_exists?(:session_logs)

    notes_table = Arel::Table.new(:clinical_notes)
    sessions_table = Arel::Table.new(:session_logs)

    rows = ActiveRecord::Base.connection.select_all(
      notes_table.project(Arel.star).where(notes_table[:deleted_at].eq(nil)).to_sql
    ).to_a

    say_with_time "Backfilling #{rows.size} clinical notes into session_logs" do
      rows.each_slice(200) do |batch|
        ids = batch.map { |n| n['id'].to_i }
        existing_ids = ActiveRecord::Base.connection.select_values(
          sessions_table.project(:migrated_from_clinical_note_id)
                        .where(sessions_table[:migrated_from_clinical_note_id].in(ids))
                        .to_sql
        ).map(&:to_i).to_set

        inserts = batch.reject { |n| existing_ids.include?(n['id'].to_i) }
                       .map { |n| build_insert_row(n) }

        next if inserts.empty?

        ActiveRecord::Base.connection.execute(insert_sql(inserts))
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Reverter manualmente: SessionLog.where.not(migrated_from_clinical_note_id: nil).delete_all"
  end

  private

  def build_insert_row(note)
    note_date = parse_date(note['note_date'])
    performed_at = note_date ? note_date.in_time_zone(BRT).beginning_of_day : Time.zone.now
    return_recommended = parse_date(note['return_recommended'])
    return_in_days = nil
    return_needed = false
    if return_recommended && note_date
      diff = (return_recommended - note_date).to_i
      if diff.positive?
        return_in_days = diff
        return_needed = true
      end
    end

    {
      account_id:                     note['account_id'],
      patient_id:                     note['patient_id'],
      professional_id:                note['professional_id'],
      appointment_id:                 note['appointment_id'],
      form_template_id:               note['form_template_id'],
      performed_at:                   performed_at,
      duration_minutes:               nil,
      areas_treated:                  '[]',
      products_used:                  '[]',
      complications:                  note['complications'],
      result_observed:                nil,
      post_procedure_guidance:        note['guidance_given'],
      return_needed:                  return_needed,
      return_in_days:                 return_in_days,
      complaint_of_day:               note['complaint_of_day'],
      assessment:                     note['assessment'],
      next_consultation_details:      nil,
      observation:                    nil,
      status:                         note['status'].presence || 'draft',
      signed_at:                      note['signed_at'],
      signed_by_id:                   note['signed_by_id'],
      erratum_at:                     note['erratum_at'],
      erratum_by_id:                  note['erratum_by_id'],
      erratum_reason:                 note['erratum_reason'],
      lock_version:                   0,
      migrated_from_clinical_note_id: note['id'],
      procedure_name:                 note['conduct'].presence || FALLBACK_PROCEDURE_NAME,
      created_at:                     note['created_at'],
      updated_at:                     note['updated_at']
    }
  end

  def insert_sql(rows)
    conn = ActiveRecord::Base.connection
    columns = rows.first.keys
    quoted_columns = columns.map { |c| conn.quote_column_name(c) }.join(',')

    values_sql = rows.map do |row|
      "(#{columns.map { |c| conn.quote(row[c]) }.join(',')})"
    end.join(",\n")

    "INSERT INTO session_logs (#{quoted_columns}) VALUES #{values_sql}"
  end

  def parse_date(value)
    return nil if value.blank?
    return value if value.is_a?(Date)
    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
