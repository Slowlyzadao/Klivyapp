class TreatmentItem < ApplicationRecord
  # Soft delete
  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  # Associations
  belongs_to :account
  belongs_to :treatment_plan
  has_many :session_logs, -> { where(deleted_at: nil) }, dependent: :nullify

  # Enums
  enum :status, {
    proposto: 'proposto',
    aprovado: 'aprovado',
    em_execucao: 'em_execucao',
    concluido: 'concluido',
    cancelado: 'cancelado'
  }, prefix: true

  enum :priority, {
    baixa: 'baixa',
    media: 'media',
    alta: 'alta',
    urgente: 'urgente'
  }, prefix: true, _default: 'media'

  # Validations
  validates :account, presence: true
  validates :treatment_plan, presence: true
  validates :procedure_name, presence: true, length: { minimum: 2, maximum: 255 }
  validates :sessions_planned, numericality: { greater_than: 0, only_integer: true }
  validates :sessions_done, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0, allow_nil: true }
  validates :total_price, numericality: { greater_than_or_equal_to: 0, allow_nil: true }
  validate :sessions_done_within_planned

  # Callbacks
  before_save :calculate_total_price
  before_save :update_status_from_sessions

  # Scopes
  scope :approved_items, -> { where(status: %w[aprovado em_execucao]) }
  scope :in_progress, -> { where(status: 'em_execucao') }
  scope :completed, -> { where(status: 'concluido') }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  def remaining_sessions
    [sessions_planned - sessions_done, 0].max
  end

  def completion_percentage
    return 0 if sessions_planned.zero?

    ((sessions_done.to_f / sessions_planned) * 100).round(1)
  end

  def increment_sessions_done!
    return false if sessions_done >= sessions_planned

    new_count = sessions_done + 1
    new_status = if new_count >= sessions_planned
                   'concluido'
                 elsif new_count > 0
                   'em_execucao'
                 else
                   status
                 end

    update!(sessions_done: new_count, status: new_status)
  end

  private

  def calculate_total_price
    return unless unit_price.present? && sessions_planned.present?

    self.total_price ||= unit_price * sessions_planned
  end

  def update_status_from_sessions
    return unless sessions_done_changed? || sessions_planned_changed?

    if sessions_done >= sessions_planned && !status_concluido?
      self.status = 'concluido'
    elsif sessions_done > 0 && sessions_done < sessions_planned && status_proposto?
      self.status = 'em_execucao'
    end
  end

  def sessions_done_within_planned
    return unless sessions_done.present? && sessions_planned.present?
    return unless sessions_done > sessions_planned

    errors.add(:sessions_done, :exceeds_planned, count: sessions_planned)
  end
end
