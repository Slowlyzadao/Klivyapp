# == Schema Information
#
# Table name: agenda_events
#
#  id                 :bigint           not null, primary key
#  account_id         :bigint           not null
#  user_id            :bigint
#  contact_id         :bigint
#  agenda_service_id  :bigint
#  title              :string           not null
#  description        :text
#  starts_at          :datetime         not null
#  ends_at            :datetime         not null
#  custom_attributes  :jsonb
#  status             :string           default("scheduled"), not null
#  event_type         :string           default("appointment"), not null
#  category_id        :bigint
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  index_agenda_events_on_account_id         (account_id)
#  index_agenda_events_on_contact_id         (contact_id)
#  index_agenda_events_on_user_id            (user_id)
#  index_agenda_events_on_agenda_service_id  (agenda_service_id)
#
# Foreign Keys
#
#  agenda_service_id  → agenda_services.id (ON DELETE SET NULL)
#

class AgendaEvent < ApplicationRecord
  include TimelineTrackable

  belongs_to :account
  belongs_to :user, optional: true # Usuário/Dentista
  belongs_to :contact, optional: true # Paciente
  belongs_to :category, class_name: 'Agenda::Category', optional: true, inverse_of: :agenda_events
  belongs_to :deleted_by, class_name: 'User', optional: true
  # PR #4 da auditoria 2026-05-13: FK opcional para AgendaService.
  # `optional: true` porque:
  # 1. Eventos antigos (pré-PR #4) ficam NULL até o backfill rodar.
  # 2. Eventos cujo treatment NAME não casa com nenhum serviço cadastrado
  #    permanecem NULL (manifestação visível de débito histórico).
  # 3. Eventos sem treatment (`event_type` não-clínico) nunca foram associados
  #    a serviço e seguem assim.
  belongs_to :agenda_service, optional: true
  has_many :agenda_notification_logs, dependent: :destroy

  # ─── Soft-delete ─────────────────────────────────────────────────────────────
  # Razões de exclusão alinhadas ao DELETE_REASONS do frontend
  # (plugins/agenda/frontend/utils/agenda-constants.js).
  DELETION_REASONS = %w[cancelamento_usuario cancelamento_paciente reagendamento outro].freeze

  scope :kept,      -> { where(deleted_at: nil) }
  scope :discarded, -> { where.not(deleted_at: nil) }

  validates :title, presence: true
  validates :starts_at, presence: true
  validates :ends_at, presence: true
  validates :status, presence: true
  validates :event_type, presence: true

  # Enumeração ou validação para garantir os status válidos
  validates :status, inclusion: { in: %w[scheduled confirmed arrived in_progress completed cancelled no_show] }

  validate :ends_at_after_starts_at

  # ─── Callbacks ───────────────────────────────────────────────────────────────
  # PR #4: duplo-write — popula `agenda_service_id` derivando de
  # `custom_attributes['treatment']` (NAME) quando o frontend não enviou o FK
  # explicitamente. Permite que o backend já normalize o link enquanto o front
  # ainda envia só o NAME no JSONB (PR #6 migra o front).
  before_save :resolve_agenda_service_id_from_treatment

  after_create_commit :trigger_confirmation_notifications
  after_create_commit :record_timeline_appointment_created
  after_create_commit :assign_patient_responsible_if_missing
  after_update_commit :record_timeline_appointment_status_changed, if: :saved_change_to_status?
  after_update_commit :record_timeline_appointment_deleted,
                      if: -> { saved_change_to_deleted_at? && deleted_at.present? }

  # ─── Public methods ──────────────────────────────────────────────────────────
  def discarded?
    deleted_at.present?
  end

  # Soft-delete: preserva o evento no banco (ainda visível no prontuário do
  # paciente), apenas oculta da agenda via scope `kept`. Razão e nota são
  # registradas para rastreabilidade. Para reason='outro' a nota é obrigatória.
  def soft_delete!(actor:, reason:, note: nil)
    raise 'Agendamento já está excluído.' if discarded?

    reason = reason.to_s.strip
    raise "Motivo inválido. Use um de: #{DELETION_REASONS.join(', ')}" \
      unless DELETION_REASONS.include?(reason)

    note = note.to_s.strip
    raise 'Justificativa é obrigatória ao escolher "Outro motivo".' \
      if reason == 'outro' && note.blank?

    update_columns(
      deleted_at: Time.current,
      deleted_by_id: actor&.id,
      deletion_reason: reason,
      deletion_note: note.presence,
      updated_at: Time.current
    )
    # Disparar timeline manualmente — update_columns bypassa callbacks
    record_timeline_appointment_deleted
    true
  end

  # Resolver compartilhado entre o callback do model e a rake task de backfill.
  # Casa `name` contra `agenda_services.kept` por `lower(btrim(name))` no escopo
  # do `account_id`. Retorna o `AgendaService` ou `nil`.
  def self.find_service_by_treatment_name(account_id, name)
    name = name.to_s.strip
    return nil if name.blank? || account_id.blank?

    AgendaService.kept
                 .where(account_id: account_id)
                 .where('lower(btrim(name)) = ?', name.downcase)
                 .first
  end

  private

  # Duplo-write em saves: se o evento foi salvo sem `agenda_service_id` mas
  # tem `custom_attributes['treatment']` (string com NAME — formato legado),
  # resolve o NAME → ID dentro da conta. Permite migração transparente: o
  # front continua mandando só o NAME, o backend já popula o FK.
  #
  # Skip quando FK já está populado (evita query desnecessária em updates
  # que não mexem no serviço).
  def resolve_agenda_service_id_from_treatment
    return if agenda_service_id.present?

    treatment_name = custom_attributes&.dig('treatment')
    return if treatment_name.to_s.strip.blank?

    service = self.class.find_service_by_treatment_name(account_id, treatment_name)
    self.agenda_service_id = service.id if service
  end

  # ─── Timeline ────────────────────────────────────────────────────────────────
  def timeline_patient
    return nil unless contact_id.present?

    Patient.active.find_by(contact_id: contact_id, account_id: account_id)
  end

  def timeline_account
    account
  end

  def record_timeline_appointment_created
    return unless timeline_patient.present?

    date_str = starts_at&.strftime('%d/%m/%Y %H:%M')
    record_timeline_event!(
      event_type: 'appointment_scheduled',
      label: "Agendamento criado: #{title} para #{date_str}",
      actor: user,
      occurred_at: Time.current,
      metadata: { titulo: title.to_s, data: date_str.to_s, profissional: user&.name.to_s }
    )
  end

  def record_timeline_appointment_status_changed
    return unless timeline_patient.present?

    date_str = starts_at&.strftime('%d/%m/%Y %H:%M')
    evt, lbl = case status
               when 'no_show'
                 ['appointment_no_show', "Falta registrada: #{title} (#{date_str})"]
               when 'completed'
                 ['appointment_done', "Consulta realizada: #{title} (#{date_str})"]
               when 'cancelled'
                 ['appointment_canceled', "Agendamento cancelado: #{title}"]
               when 'confirmed'
                 ['appointment_scheduled', "Agendamento confirmado: #{title} (#{date_str})"]
               else
                 return # Não registra para outros status intermediários
               end

    record_timeline_event!(
      event_type: evt,
      label: lbl,
      actor: user,
      occurred_at: Time.current,
      metadata: { titulo: title.to_s, status: status.to_s, data: date_str.to_s }
    )
  end

  REASON_LABELS = {
    'cancelamento_usuario'  => 'Cancelado pelo usuário',
    'cancelamento_paciente' => 'Cancelado pelo paciente',
    'reagendamento'         => 'Reagendado',
    'outro'                 => 'Excluído (outro motivo)'
  }.freeze

  def record_timeline_appointment_deleted
    return unless timeline_patient.present?

    date_str = starts_at&.strftime('%d/%m/%Y %H:%M')
    reason_label = REASON_LABELS[deletion_reason.to_s] || 'Excluído'
    label_parts = ["#{reason_label}: #{title}"]
    label_parts << "(#{date_str})" if date_str
    label_parts << "— #{deletion_note}" if deletion_note.present?

    record_timeline_event!(
      event_type: 'appointment_deleted',
      label: label_parts.join(' '),
      actor: deleted_by,
      occurred_at: deleted_at || Time.current,
      metadata: {
        titulo: title.to_s,
        data: date_str.to_s,
        deletion_reason: deletion_reason.to_s,
        deletion_reason_label: reason_label,
        deletion_note: deletion_note.to_s,
        deleted_by: deleted_by&.name.to_s
      }
    )
  end

  # ─── Notificações ────────────────────────────────────────────────────────────
  def trigger_confirmation_notifications
    return unless contact_id.present?

    confirmation_rules = account.agenda_notification_rules
                                .enabled
                                .where(rule_type: 'confirmation')

    confirmation_rules.each do |rule|
      Agenda::SendNotificationJob.perform_later(
        account_id: account_id,
        event_id: id,
        rule_id: rule.id
      )
    end
  rescue StandardError => e
    Rails.logger.error("[AgendaEvent] Falha ao enfileirar confirmation para evento #{id}: #{e.message}")
  end

  def ends_at_after_starts_at
    return if starts_at.blank? || ends_at.blank?

    return unless ends_at < starts_at

    errors.add(:ends_at, 'deve ser depois da data de início')
  end

  # Etapa A da auto-atribuição (decisão Mamedes 2026-05-11): quando um
  # agendamento é criado e o paciente AINDA não tem `responsible_professional_id`
  # setado, adota o user (dentista do agendamento) como responsável. Cobre
  # o caso "primeiro a agendar vira o dono do paciente".
  #
  # AgendaEvent usa `contact_id` (não patient_id direto) então navegamos via
  # `Patient.find_by(contact_id:, account_id:)` — mesmo padrão do
  # `timeline_patient` acima.
  def assign_patient_responsible_if_missing
    return if user_id.blank?
    return if contact_id.blank?

    patient = Patient.find_by(contact_id: contact_id, account_id: account_id)
    return unless patient
    return if patient.responsible_professional_id.present?

    patient.update_column(:responsible_professional_id, user_id)
  end
end
