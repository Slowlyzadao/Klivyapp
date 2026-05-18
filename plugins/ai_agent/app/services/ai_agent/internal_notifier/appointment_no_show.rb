module AiAgent
  module InternalNotifier
    # Notifica quando um AgendaEvent vira `no_show` (paciente não compareceu).
    # Equipe usa pra reagendamento ativo.
    #
    # Dedupe por agenda_event.id.
    class AppointmentNoShow
      EVENT_KEY = 'appointment_no_show'.freeze

      def self.call(agenda_event)
        new(agenda_event).call
      end

      def initialize(agenda_event)
        @event = agenda_event
      end

      def call
        return unless @event.contact_id.present?
        return unless @event.status == 'no_show'

        AiAgent::InternalNotifier::Dispatcher.dispatch(
          account: @event.account,
          event_key: EVENT_KEY,
          vars: build_vars,
          dedupe_key: "#{EVENT_KEY}:#{@event.id}"
        )
      end

      private

      def build_vars
        {
          patient_name: patient&.name || @event.contact&.name || 'Paciente',
          patient_phone: patient&.phone.presence || @event.contact&.phone_number.presence || 'sem telefone',
          service_name: @event.title.to_s,
          dentist_name: @event.user&.name || 'a definir',
          appointment_starts_at: format_starts_at
        }
      end

      def patient
        @patient ||= defined?(::Patient) ? ::Patient.find_by(contact_id: @event.contact_id, account_id: @event.account_id) : nil
      end

      def format_starts_at
        I18n.l(@event.starts_at.in_time_zone('America/Sao_Paulo'), format: '%d/%m/%Y às %H:%M')
      rescue StandardError
        @event.starts_at.strftime('%d/%m/%Y %H:%M')
      end
    end
  end
end
