class AgendaSetting < ApplicationRecord
  belongs_to :account

  after_initialize :set_defaults, if: :new_record?

  validates :account_id, presence: true, uniqueness: true
  validates :slot_interval_minutes, inclusion: { in: [15, 30, 60] }

  # Default weekday config matching what the frontend used to hardcode
  DEFAULT_WEEK_DAYS = [
    { id: 'sun', label: 'Domingo', enabled: false, start: '', end: '', lunchStart: '', lunchEnd: '' },
    { id: 'mon', label: 'Segunda-feira', enabled: true, start: '09:00', end: '18:00', lunchStart: '12:00', lunchEnd: '13:00' },
    { id: 'tue', label: 'Terça-feira', enabled: true, start: '09:00', end: '18:00', lunchStart: '12:00', lunchEnd: '13:00' },
    { id: 'wed', label: 'Quarta-feira', enabled: true, start: '09:00', end: '18:00', lunchStart: '12:00', lunchEnd: '13:00' },
    { id: 'thu', label: 'Quinta-feira', enabled: true, start: '09:00', end: '18:00', lunchStart: '12:00', lunchEnd: '13:00' },
    { id: 'fri', label: 'Sexta-feira', enabled: true, start: '09:00', end: '18:00', lunchStart: '12:00', lunchEnd: '13:00' },
    { id: 'sat', label: 'Sábado', enabled: true, start: '09:00', end: '13:00', lunchStart: '', lunchEnd: '' }
  ].freeze

  SLOT_INTERVAL_OPTIONS = [15, 30, 60].freeze

  DEFAULT_HOLIDAYS = [
    { 'date' => '01/01', 'name' => 'Confraternização Universal', 'status' => 'closed' },
    { 'date' => '21/04', 'name' => 'Tiradentes', 'status' => 'closed' },
    { 'date' => '01/05', 'name' => 'Dia do Trabalho', 'status' => 'closed' },
    { 'date' => '07/09', 'name' => 'Independência do Brasil', 'status' => 'closed' },
    { 'date' => '12/10', 'name' => 'Nossa Senhora Aparecida', 'status' => 'closed' },
    { 'date' => '02/11', 'name' => 'Finados', 'status' => 'closed' },
    { 'date' => '15/11', 'name' => 'Proclamação da República', 'status' => 'closed' },
    { 'date' => '20/11', 'name' => 'Dia da Consciência Negra', 'status' => 'closed' },
    { 'date' => '25/12', 'name' => 'Natal', 'status' => 'closed' }
  ].freeze

  private

  def set_defaults
    self.week_days = DEFAULT_WEEK_DAYS if week_days.blank?
    self.holidays = DEFAULT_HOLIDAYS if holidays.blank?
  end
end
