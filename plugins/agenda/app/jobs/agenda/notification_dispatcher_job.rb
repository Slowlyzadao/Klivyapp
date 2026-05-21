# Agenda::NotificationDispatcherJob
#
# Job principal que roda a cada 5 minutos (via schedule.yml / sidekiq-cron).
# Processa TODOS os tipos de regras de notificação:
#
#   reminder     → enviar X horas ANTES da consulta
#   followup     → enviar X horas APÓS a consulta (trigger_offset_hours após starts_at)
#   birthday     → enviar quando hoje é aniversário do contato (via additional_attributes ou custom_attributes)
#   confirmation → disparado via callback no AgendaEvent (não precisa de polling aqui)

class Agenda::NotificationDispatcherJob < ApplicationJob
  queue_as :scheduled_jobs

  WINDOW_MINUTES = 10 # ± 5 minutos em torno do horário exato

  def perform
    Account.all.find_each(batch_size: 50) do |account|
      process_account(account)
    end
  end

  private

  def process_account(account)
    rules = account.agenda_notification_rules.enabled.ordered

    rules.each do |rule|
      case rule.rule_type
      when 'reminder'
        dispatch_reminder(account, rule)
      when 'followup'
        dispatch_followup(account, rule)
      when 'birthday'
        dispatch_birthday(account, rule)
        # 'confirmation' é tratado via after_create_commit no AgendaEvent
      end
    end
  rescue StandardError => e
    Rails.logger.error("[Agenda::NotificationDispatcher] Erro na conta #{account.id}: #{e.message}")
  end

  # ─── REMINDER: X horas ANTES de starts_at ────────────────────────────────────
  def dispatch_reminder(account, rule)
    return unless rule.trigger_offset_hours.present?

    offset_seconds = rule.trigger_offset_hours * 3600
    window_start   = Time.current + offset_seconds.seconds - (WINDOW_MINUTES / 2.0).minutes
    window_end     = Time.current + offset_seconds.seconds + (WINDOW_MINUTES / 2.0).minutes

    events_in_window(account, window_start..window_end).each do |event|
      enqueue_if_not_sent(event, rule)
    end
  rescue StandardError => e
    log_rule_error(rule, e)
  end

  # ─── FOLLOWUP: X horas APÓS ends_at (final da consulta) ───────────────────────
  def dispatch_followup(account, rule)
    offset_hours = rule.trigger_offset_hours || 2.0 # padrão: 2h após
    offset_seconds = offset_hours * 3600

    # O evento TERMINOU há exatamente offset_hours
    window_start = Time.current - offset_seconds.seconds - (WINDOW_MINUTES / 2.0).minutes
    window_end   = Time.current - offset_seconds.seconds + (WINDOW_MINUTES / 2.0).minutes

    account.agenda_events
           .where(ends_at: window_start..window_end)
           .where.not(contact_id: nil).each do |event|
      enqueue_if_not_sent(event, rule)
    end
  rescue StandardError => e
    log_rule_error(rule, e)
  end

  # ─── BIRTHDAY: hoje é aniversário do contato ─────────────────────────────────
  def dispatch_birthday(account, rule)
    today = Date.today

    # Busca contatos com aniversário hoje via additional_attributes ou custom_attributes
    # O campo pode ser 'birthdate', 'data_nascimento', 'birthday' dependendo da clínica
    birthday_contacts = account.contacts.select do |contact|
      contact_birthday_today?(contact, today)
    end

    birthday_contacts.each do |contact|
      # Para birthday, precisamos de um "evento" virtual ou enviar diretamente
      # Usamos o evento mais recente do contato como âncora para o log
      last_event = account.agenda_events.where(contact_id: contact.id).order(:starts_at).last
      next unless last_event

      enqueue_if_not_sent(last_event, rule, force_today_window: true)
    end
  rescue StandardError => e
    log_rule_error(rule, e)
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────────

  def events_in_window(account, range)
    account.agenda_events
           .where(starts_at: range)
           .where.not(contact_id: nil)
  end

  def enqueue_if_not_sent(event, rule, force_today_window: false)
    # Para birthday com force_today_window, verifica apenas se já enviou hoje
    if force_today_window
      already_sent = AgendaNotificationLog.where(
        agenda_event_id: event.id,
        agenda_notification_rule_id: rule.id
      ).where('sent_at >= ?', Date.today.beginning_of_day).exists?
      return if already_sent
    elsif AgendaNotificationLog.exists?(
      agenda_event_id: event.id,
      agenda_notification_rule_id: rule.id
    )
      return
    end

    Agenda::SendNotificationJob.perform_later(
      account_id: event.account_id,
      event_id: event.id,
      rule_id: rule.id
    )
  end

  def contact_birthday_today?(contact, today)
    birthday_str = contact.additional_attributes&.[]('birthdate') ||
                   contact.additional_attributes&.[]('birthday') ||
                   contact.custom_attributes&.[]('data_nascimento') ||
                   contact.custom_attributes&.[]('birthdate')

    return false if birthday_str.blank?

    birthday = Date.parse(birthday_str.to_s)
    birthday.month == today.month && birthday.day == today.day
  rescue ArgumentError, TypeError
    false
  end

  def log_rule_error(rule, error)
    Rails.logger.error("[Agenda::NotificationDispatcher] Erro na regra #{rule.id} (tipo=#{rule.rule_type}): #{error.message}")
  end
end
