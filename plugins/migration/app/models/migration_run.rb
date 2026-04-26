class MigrationRun < ApplicationRecord
  belongs_to :account

  KINDS = %w[patients agenda anamnesis financial].freeze
  STATUSES = %w[pending processing completed failed].freeze
  SOURCES = %w[clinicorp generic].freeze

  validates :kind,   inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }

  scope :recent, -> { order(created_at: :desc) }

  def mark_processing!
    update!(status: 'processing', started_at: Time.current)
  end

  def mark_completed!
    update!(status: 'completed', finished_at: Time.current)
  end

  def mark_failed!(message)
    update!(status: 'failed', error_message: message.to_s.truncate(2000), finished_at: Time.current)
  end

  def progress_percent
    return 0 if total_rows.to_i.zero?

    ((processed_rows.to_f / total_rows) * 100).round(1)
  end
end
