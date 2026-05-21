# == Schema Information
#
# Table name: agenda_notification_rules
#
#  id                    :bigint           not null, primary key
#  account_id            :bigint           not null
#  title                 :string           not null
#  rule_type             :string           not null, default: "reminder"
#  icon                  :string           not null, default: "i-lucide-bell"
#  icon_color            :string           not null, default: "blue"
#  trigger_offset_hours  :decimal(8,2)
#  message_template      :text             not null
#  inboxes               :jsonb            default: []
#  enabled               :boolean          not null, default: true
#  position              :integer          not null, default: 0
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#

class AgendaNotificationRule < ApplicationRecord
  belongs_to :account
  has_many :agenda_notification_logs, dependent: :destroy

  RULE_TYPES = %w[reminder confirmation followup birthday custom].freeze

  validates :title,            presence: true
  validates :rule_type,        presence: true, inclusion: { in: RULE_TYPES }
  validates :message_template, presence: true
  validates :trigger_offset_hours,
            numericality: { greater_than_or_equal_to: 0 },
            allow_nil: true
  validate  :offset_required_for_reminder

  scope :enabled,  -> { where(enabled: true) }
  scope :ordered,  -> { order(:position, :created_at) }
  scope :reminders, -> { where(rule_type: 'reminder').where.not(trigger_offset_hours: nil) }

  # Retorna regras de lembrete ordenadas por offset (maiores primeiro: 72h, 24h, 2h...)
  scope :reminders_by_offset, -> { reminders.order(trigger_offset_hours: :desc) }

  private

  def offset_required_for_reminder
    return unless rule_type == 'reminder'
    return if trigger_offset_hours.present?

    errors.add(:trigger_offset_hours, 'é obrigatório para regras do tipo Lembrete')
  end
end
