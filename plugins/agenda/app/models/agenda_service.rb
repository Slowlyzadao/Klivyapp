# == Schema Information
#
# Table name: agenda_services
#
#  id               :bigint           not null, primary key
#  account_id       :bigint           not null
#  name             :string           not null
#  duration_minutes :integer          not null, default: 60
#  price            :decimal          precision: 10, scale: 2, default: 0
#  requires_room    :boolean          not null, default: false
#  color            :string           default: '#3b82f6'
#  position         :integer          default: 0
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#

class AgendaService < ApplicationRecord
  belongs_to :account
  # Categoria sugerida ao agendar este serviço. Recepção pode trocar
  # manualmente no momento da consulta. Bea usa esse valor pra preencher
  # `AgendaEvent.category_id` automaticamente — sem ele, evento fica
  # sem categoria. Ver plugins/ai_agent tools book_appointment_tool /
  # reschedule_appointment_tool.
  belongs_to :default_category, class_name: 'Agenda::Category', optional: true

  validates :name, presence: true
  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :ordered, -> { order(:position, :created_at) }

  before_create :set_position

  private

  def set_position
    max_pos = account.agenda_services.maximum(:position) || -1
    self.position = max_pos + 1
  end
end
