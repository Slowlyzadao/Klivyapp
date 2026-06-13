class TreatmentItem < ApplicationRecord
  DISCOUNT_TYPES = %w[fixo percentual].freeze

  # Soft delete
  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  # Associations
  belongs_to :account
  belongs_to :treatment_plan
  # PR #6b da auditoria 2026-05-13: FK opcional para AgendaService — referência
  # viva que sobrevive a rename do serviço. `procedure_name` continua sendo a
  # string histórica (audit trail do que foi acordado quando o plano foi feito).
  belongs_to :agenda_service, optional: true
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
  validates :discount_type, inclusion: { in: DISCOUNT_TYPES }, allow_blank: true
  validates :discount_value, numericality: { greater_than_or_equal_to: 0 }
  validate :discount_percentage_within_bounds
  validate :sessions_done_within_planned

  # Callbacks
  before_save :calculate_total_price
  before_save :update_status_from_sessions
  # PR #6b: duplo-write — popula `agenda_service_id` quando o item é salvo
  # sem FK explícito mas com `procedure_name` (formato legado pré-PR #6b).
  # Permite backfill incremental conforme itens antigos são editados.
  before_save :resolve_agenda_service_id_from_procedure_name

  # Regenera o PDF do plano pai assincronamente quando há mudança no item
  # APÓS o plano já ter PDF anexado. `update_all` em massa (ex: aprovação)
  # não dispara callbacks — então o approve não causa double-generate.
  after_commit :enqueue_plan_pdf_refresh, if: :plan_pdf_attached?

  # Scopes
  scope :approved_items, -> { where(status: %w[aprovado em_execucao]) }
  scope :in_progress, -> { where(status: 'em_execucao') }
  scope :completed, -> { where(status: 'concluido') }

  # PR #6b: resolver compartilhado entre callback do model e rake task de backfill.
  # Casa `name` contra `agenda_services.kept` por `lower(btrim(name))` no escopo
  # do account_id. Retorna o AgendaService ou nil.
  def self.find_service_by_procedure_name(account_id, name)
    name = name.to_s.strip
    return nil if name.blank? || account_id.blank?

    AgendaService.kept
                 .where(account_id: account_id)
                 .where('lower(btrim(name)) = ?', name.downcase)
                 .first
  end

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

  # Subtotal antes do desconto: unit_price × sessões.
  def gross_subtotal
    return BigDecimal('0') if unit_price.blank? || sessions_planned.blank?

    BigDecimal(unit_price.to_s) * sessions_planned
  end

  # Valor do desconto em R$. Para `percentual`, calcula sobre o subtotal bruto.
  def discount_amount
    return BigDecimal('0') if discount_value.blank? || discount_value.to_d <= 0

    case discount_type
    when 'percentual'
      gross_subtotal * (BigDecimal(discount_value.to_s) / 100)
    when 'fixo'
      [BigDecimal(discount_value.to_s), gross_subtotal].min
    else
      BigDecimal('0')
    end
  end

  # Subtotal final (após desconto). Nunca negativo.
  def net_subtotal
    [gross_subtotal - discount_amount, BigDecimal('0')].max
  end

  private

  # PR #6b: duplo-write transparente.
  # Skip se FK já está populado (evita query desnecessária em updates de
  # campos não relacionados ao serviço).
  def resolve_agenda_service_id_from_procedure_name
    return if agenda_service_id.present?
    return if procedure_name.to_s.strip.blank?

    service = self.class.find_service_by_procedure_name(account_id, procedure_name)
    self.agenda_service_id = service.id if service
  end

  def plan_pdf_attached?
    treatment_plan&.pdf&.attached?
  end

  def enqueue_plan_pdf_refresh
    Patients::RegenerateTreatmentPlanPdfJob.perform_later(treatment_plan_id)
  end

  # Sobrescreve sempre — refletir alterações em unit_price/sessões/desconto.
  def calculate_total_price
    self.total_price = net_subtotal
  end

  def discount_percentage_within_bounds
    return unless discount_type == 'percentual'
    return if discount_value.blank?
    return if discount_value.to_d.between?(0, 100)

    errors.add(:discount_value, :must_be_between_0_and_100)
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
