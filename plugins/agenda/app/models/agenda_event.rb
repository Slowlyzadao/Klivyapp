# == Schema Information
#
# Table name: agenda_events
#
#  id                :bigint           not null, primary key
#  account_id        :bigint           not null
#  user_id           :bigint
#  contact_id        :bigint
#  title             :string           not null
#  description       :text
#  starts_at         :datetime         not null
#  ends_at           :datetime         not null
#  custom_attributes :jsonb
#  status            :string           default("scheduled"), not null
#  event_type        :string           default("appointment"), not null
#  category_id       :bigint
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  index_agenda_events_on_account_id  (account_id)
#  index_agenda_events_on_contact_id  (contact_id)
#  index_agenda_events_on_user_id     (user_id)
#

class AgendaEvent < ApplicationRecord
  include TimelineTrackable

  belongs_to :account
  belongs_to :user, optional: true # Usuário/Dentista
  belongs_to :contact, optional: true # Paciente
  belongs_to :category, class_name: 'Agenda::Category', optional: true, inverse_of: :agenda_events
  has_many :agenda_notification_logs, dependent: :destroy

  validates :title, presence: true
  validates :starts_at, presence: true
  validates :ends_at, presence: true
  validates :status, presence: true
  validates :event_type, presence: true

  # Enumeração ou validação para garantir os status válidos.
  # `pending_confirmation`: criado pela Bea (IA), aguardando humano da
  # clínica validar antes de virar `scheduled`. Existe pra trafegar em
  # piloto sem que erro de LLM vire compromisso firme na agenda.
  validates :status, inclusion: { in: %w[pending_confirmation scheduled confirmed arrived in_progress completed cancelled no_show] }

  # Origem do evento — quem o criou. Usado pelo motor de Follow-ups
  # (plugin ai_agent) pra filtrar regras "só se Bea agendou" vs "só se
  # humano agendou" vs "ambos". Default 'manual' cobre o agendamento
  # criado pela recepção via UI/REST. A Bea seta 'ai_agent' ao usar
  # `book_appointment_tool`. `public_booking` é o link público de
  # auto-agendamento. Eventos antigos (pré-coluna) entram como 'manual'.
  SOURCES = %w[manual ai_agent public_booking import].freeze
  validates :source, inclusion: { in: SOURCES }

  validate :ends_at_after_starts_at

  # ─── Callbacks ───────────────────────────────────────────────────────────────
  after_create_commit :trigger_confirmation_notifications
  after_create_commit :record_timeline_appointment_created
  after_update_commit :record_timeline_appointment_status_changed, if: :saved_change_to_status?
  # Quando humano aprova um pending_confirmation (vira scheduled/confirmed),
  # disparam as notificações que ficaram seguradas no create.
  after_update_commit :trigger_confirmation_notifications, if: :approved_after_pending?
  # Disparo de follow-ups event-driven (trigger `appointment_confirmed`):
  # quando a clínica confirma uma reserva criada pela Bea, ela manda
  # WhatsApp pro paciente avisando que está confirmado. Roda em job
  # pra não bloquear o save e sobreviver a falhas do plugin ai_agent.
  after_update_commit :dispatch_appointment_confirmed_followups, if: :approved_after_pending?

  private

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
    label = if status == 'pending_confirmation'
              "Reserva pendente: #{title} para #{date_str} (aguardando confirmação da clínica)"
            else
              "Agendamento criado: #{title} para #{date_str}"
            end

    record_timeline_event!(
      event_type: 'appointment_scheduled',
      label: label,
      actor: user,
      occurred_at: Time.current,
      metadata: { titulo: title.to_s, data: date_str.to_s, profissional: user&.name.to_s, status: status.to_s }
    )
  end

  def approved_after_pending?
    saved_change_to_status? &&
      saved_change_to_status[0] == 'pending_confirmation' &&
      %w[scheduled confirmed].include?(status)
  end

  def record_timeline_appointment_status_changed
    return unless timeline_patient.present?

    date_str = starts_at&.strftime('%d/%m/%Y %H:%M')
    came_from_pending = saved_change_to_status[0] == 'pending_confirmation'

    evt, lbl = case status
               when 'no_show'
                 ['appointment_no_show', "Falta registrada: #{title} (#{date_str})"]
               when 'completed'
                 ['appointment_done', "Consulta realizada: #{title} (#{date_str})"]
               when 'cancelled'
                 ['appointment_canceled', "Agendamento cancelado: #{title}"]
               when 'confirmed'
                 ['appointment_scheduled', "Agendamento confirmado: #{title} (#{date_str})"]
               when 'scheduled'
                 came_from_pending ? ['appointment_scheduled', "Reserva confirmada pela clínica: #{title} (#{date_str})"] : (return)
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

  # ─── Notificações ────────────────────────────────────────────────────────────
  def trigger_confirmation_notifications
    return unless contact_id.present?
    # `pending_confirmation` ainda não é compromisso firme — humano
    # precisa validar primeiro. Disparar notificação (WhatsApp/email)
    # pro paciente nesse momento confunde quem foi reservado provisório.
    # A notificação real sai quando virar `scheduled`/`confirmed`.
    return if status == 'pending_confirmation'

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

  def dispatch_appointment_confirmed_followups
    return unless defined?(::AiAgent::FollowUps::DispatchAppointmentConfirmedJob)

    ::AiAgent::FollowUps::DispatchAppointmentConfirmedJob.perform_later(id)
  rescue StandardError => e
    Rails.logger.error("[AgendaEvent] dispatch_appointment_confirmed_followups falhou para evento #{id}: #{e.message}")
  end

  def ends_at_after_starts_at
    return if starts_at.blank? || ends_at.blank?

    return unless ends_at < starts_at

    errors.add(:ends_at, 'deve ser depois da data de início')
  end
end
