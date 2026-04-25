# app/services/patients/appointment_rescheduler.rb
#
# Service para remarcar um agendamento existente.
# Guarda o histórico via timeline e bloqueia reagendamento de consultas finalizadas.

module Patients
  class AppointmentRescheduler
    Result = Struct.new(:success?, :appointment, :error, keyword_init: true)

    def self.call(appointment:, actor:, account:, params:)
      new(appointment: appointment, actor: actor, account: account, params: params).call
    end

    def initialize(appointment:, actor:, account:, params:)
      @appointment = appointment
      @actor       = actor
      @account     = account
      @params      = params
    end

    def call
      unless appointment.reschedulable?
        return Result.new(
          success?: false,
          appointment: nil,
          error: "Agendamento com status '#{appointment.status}' não pode ser reagendado"
        )
      end

      old_scheduled_at = appointment.scheduled_at

      unless appointment.update(
        status: 'rescheduled',
        scheduled_at: params[:new_scheduled_at],
        ends_at: params[:new_ends_at],
        duration_minutes: params[:duration_minutes] || appointment.duration_minutes,
        reschedule_reason: params[:reschedule_reason],
        professional_id: params[:professional_id] || appointment.professional_id,
        notes: params[:notes] || appointment.notes
      )
        return Result.new(success?: false, appointment: nil, error: appointment.errors.full_messages.join(', '))
      end

      dispatch_timeline_event(appointment, old_scheduled_at)
      Result.new(success?: true, appointment: appointment, error: nil)
    rescue StandardError => e
      Rails.logger.error("[AppointmentRescheduler] Erro ao reagendar: #{e.message}")
      Result.new(success?: false, appointment: nil, error: e.message)
    end

    private

    attr_reader :appointment, :actor, :account, :params

    def dispatch_timeline_event(appt, old_date)
      Patients::RecordTimelineEventJob.perform_later(
        patient_id: appt.patient_id,
        account_id: account.id,
        actor_id: actor.id,
        event_type: 'appointment_rescheduled',
        label: "Consulta reagendada de #{old_date.strftime('%d/%m/%Y às %H:%M')} para #{appt.scheduled_at.strftime('%d/%m/%Y às %H:%M')}",
        reference_type: 'PatientAppointment',
        reference_id: appt.id,
        metadata: {
          old_scheduled_at: old_date.iso8601,
          new_scheduled_at: appt.scheduled_at.iso8601,
          reason: appt.reschedule_reason
        }
      )
    end
  end
end
