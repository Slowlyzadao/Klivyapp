# == Schema Information
#
# Table name: agenda_notification_logs
#
#  id                           :bigint           not null, primary key
#  account_id                   :bigint           not null
#  agenda_event_id              :bigint           not null
#  agenda_notification_rule_id  :bigint           not null
#  sent_at                      :datetime         not null
#  status                       :string           not null, default: "sent"
#  error_message                :text
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#

class AgendaNotificationLog < ApplicationRecord
  belongs_to :account
  belongs_to :agenda_event
  belongs_to :agenda_notification_rule

  STATUSES = %w[sent failed skipped].freeze

  validates :sent_at, presence: true
  validates :status,  presence: true, inclusion: { in: STATUSES }

  scope :sent,   -> { where(status: 'sent') }
  scope :failed, -> { where(status: 'failed') }
end
