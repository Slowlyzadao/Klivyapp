# == Schema Information
#
# Table name: agenda_categories
#
#  id         :bigint           not null, primary key
#  account_id :bigint           not null
#  name       :string           not null
#  color      :string           not null, default: '#3b82f6'
#  position   :integer          not null, default: 0
#  active     :boolean          not null, default: true
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_agenda_categories_on_account_id_and_name      (account_id, name) UNIQUE
#  index_agenda_categories_on_account_id_and_position  (account_id, position)
#

module Agenda
  class Category < ApplicationRecord
    self.table_name = 'agenda_categories'

    belongs_to :account
    has_many :agenda_events,
             class_name: '::AgendaEvent',
             foreign_key: :category_id,
             dependent: :nullify,
             inverse_of: :category

    validates :name, presence: true, uniqueness: { scope: :account_id, case_sensitive: false }
    validates :color, presence: true

    scope :active, -> { where(active: true) }
    scope :ordered, -> { order(:position, :created_at) }

    before_create :assign_next_position

    def appointments_count
      agenda_events.count
    end

    private

    def assign_next_position
      return if position.present? && position.positive?

      max_pos = account.agenda_categories.maximum(:position) || -1
      self.position = max_pos + 1
    end
  end
end
