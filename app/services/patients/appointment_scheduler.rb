# app/services/patients/appointment_scheduler.rb
#
# Service responsável por criar e gerenciar agendamentos do paciente.
# Encapsula todas as validações de negócio e dispara eventos de timeline.
#
# Uso:
#   Patients::AppointmentScheduler.call(
#     patient: @patient,
#     actor: current_user,
#     account: Current.account,
#     params: appointment_params
#   )

module Patients
  class AppointmentScheduler
    Result = Struct.new(:success?, :appointment, :error, keyword_init: true)

    def self.call(patient:, actor:, account:, params:)
      new(patient: patient, actor: actor, account: account, params: params).call
    end

    def initialize(patient:, actor:, account:, params:)
      @patient  = patient
      @actor    = actor
      @account  = account
      @params   = params
    end

    def call
      return inadimplente_bloqueado if patient_is_overdue_blocked?

      appointment = build_appointment
      return build_error(appointment.errors.full_messages.join(', ')) unless appointment.save

      dispatch_timeline_event(appointment)
      Result.new(success?: true, appointment: appointment, error: nil)
    rescue StandardError => e
      Rails.logger.error("[AppointmentScheduler] Erro ao criar agendamento: #{e.message}")
      Result.new(success?: false, appointment: nil, error: e.message)
    end

    private

    attr_reader :patient, :actor, :account, :params

    def build_appointment
      PatientAppointment.new(
        account: account,
        patient: patient,
        professional_id: params[:professional_id],
        agenda_event_id: params[:agenda_event_id],
        appointment_type: params[:appointment_type] || 'avaliacao',
        status: 'scheduled',
        scheduled_at: params[:scheduled_at],
        ends_at: params[:ends_at],
        duration_minutes: params[:duration_minutes] || 60,
        notes: params[:notes],
        return_in_days: params[:return_in_days],
        treatment_plan_id: params[:treatment_plan_id]
      )
    end

    def dispatch_timeline_event(appointment)
      Patients::RecordTimelineEventJob.perform_later(
        patient_id: patient.id,
        account_id: account.id,
        actor_id: actor.id,
        event_type: 'appointment_scheduled',
        label: "Consulta agendada: #{appointment.appointment_type} em #{appointment.scheduled_at.strftime('%d/%m/%Y às %H:%M')}",
        reference_type: 'PatientAppointment',
        reference_id: appointment.id,
        metadata: {
          appointment_type: appointment.appointment_type,
          scheduled_at: appointment.scheduled_at.iso8601,
          professional_id: appointment.professional_id
        }
      )
    end

    def patient_is_overdue_blocked?
      return false unless account.settings&.dig('block_scheduling_on_overdue') == true

      # Migrado para v2 em 2026-05-11 (Fase A): lê de `financial_installments`
      # em vez do legacy `Transaction`. Em v2 valores são BIGINT em centavos,
      # mas `> 0` continua resultando no mesmo bloqueio (qualquer pendência
      # vencida bloqueia o agendamento).
      overdue_cents = ::Financial::Installment
                        .where(account_id: patient.account_id,
                               patient_id: patient.id,
                               status: %w[vencido pendente])
                        .where('due_date < ?', Date.today)
                        .sum('amount_cents - received_amount_cents')
      overdue_cents > 0
    end

    def inadimplente_bloqueado
      Result.new(
        success?: false,
        appointment: nil,
        error: 'patient_overdue — Paciente com pendência financeira vencida. Regularize antes de agendar.'
      )
    end

    def build_error(message)
      Result.new(success?: false, appointment: nil, error: message)
    end
  end
end
