module Api
  module V1
    module Accounts
      module Patients
        class AppointmentsController < Api::V1::Accounts::Patients::BaseController
          before_action :set_appointment, only: [:show, :reschedule, :cancel, :no_show]

          private

          # Override: controller_name é 'appointments' mas o modelo é PatientAppointment
          def check_authorization(_model = nil)
            authorize(PatientAppointment)
          end

          public
          # GET /api/v1/accounts/:account_id/patients/:patient_id/appointments
          def index
            events = AgendaEvent
                       .includes(:user)
                       .where(account_id: Current.account.id)
                       .where(
                         "(custom_attributes->>'patient_id' = ?) OR (contact_id = ? AND (custom_attributes->>'patient_id' IS NULL OR custom_attributes->>'patient_id' = ''))",
                         @patient.id.to_s,
                         @patient.contact_id
                       )
                       .order(starts_at: :desc)

            now = Time.current
            appointments_json = events.map do |e|
              custom = e.custom_attributes || {}
              status = e.status.presence || 'scheduled'
              starts = e.starts_at
              ends   = e.ends_at
              duration = ends && starts ? ((ends - starts) / 60).to_i : 60

              upcoming = starts && starts > now
              no_show_statuses = %w[no_show].freeze
              canceled_statuses = %w[canceled cancelled].freeze

              # Profissional: prioridade ao user associado, fallback para custom_attributes
              professional_name = e.user&.name || custom['user_name']
              professional_avatar = e.user&.avatar_url

              {
                id: e.id,
                agenda_event_id: e.id,
                title: e.title,
                appointment_type: e.event_type.presence || custom['appointment_type'] || 'consultation',
                event_type_label: e.event_type.presence || 'consultation',
                priority: custom['priority'] || 'medium',
                treatment: custom['treatment'],
                status: status,
                scheduled_at: starts,
                ends_at: ends,
                duration_minutes: duration,
                notes: e.description,
                cancellation_reason: nil,
                reschedule_reason: nil,
                recall_sent: false,
                recall_sent_at: nil,
                return_in_days: nil,
                session_log_id: nil,
                treatment_plan_id: nil,
                professional: professional_name ? { name: professional_name, avatar_url: professional_avatar } : nil,
                professional_name: professional_name,
                professional_avatar_url: professional_avatar,
                is_upcoming: upcoming && !canceled_statuses.include?(status) && !no_show_statuses.include?(status),
                is_past: starts && starts <= now,
                cancellable: %w[scheduled confirmed arrived].include?(status),
                reschedulable: %w[scheduled confirmed].include?(status),
                created_at: e.created_at,
                updated_at: e.updated_at,
              }
            end

            total = appointments_json.size
            page = (params[:page] || 1).to_i
            per = (params[:per_page] || 25).to_i

            render json: {
              appointments: appointments_json,
              meta: {
                total_count: total,
                page: page,
                per_page: per,
                total_pages: (total.to_f / per).ceil,
              }
            }
          end


          # GET /api/v1/accounts/:account_id/patients/:patient_id/appointments/:id
          def show
            render 'api/v1/accounts/patients/appointments/show'
          end

          # POST /api/v1/accounts/:account_id/patients/:patient_id/appointments
          def create
            result = ::Patients::AppointmentScheduler.call(
              patient: @patient,
              actor: current_user,
              account: Current.account,
              params: appointment_params
            )

            if result.success?
              @appointment = result.appointment
              render 'api/v1/accounts/patients/appointments/show', status: :created
            else
              status = result.error&.include?('patient_overdue') ? :payment_required : :unprocessable_entity
              render json: { error: result.error }, status: status
            end
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/appointments/:id/reschedule
          def reschedule
            result = ::Patients::AppointmentRescheduler.call(
              appointment: @appointment,
              actor: current_user,
              account: Current.account,
              params: reschedule_params
            )

            if result.success?
              @appointment = result.appointment
              render 'api/v1/accounts/patients/appointments/show'
            else
              render json: { error: result.error }, status: :unprocessable_entity
            end
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/appointments/:id/cancel
          def cancel
            unless @appointment.cancellable?
              return render json: {
                error: "Agendamento com status '#{@appointment.status}' não pode ser cancelado"
              }, status: :unprocessable_entity
            end

            unless @appointment.update(
              status: 'canceled',
              cancellation_reason: params[:cancellation_reason]
            )
              return render json: { error: @appointment.errors.full_messages.join(', ') }, status: :unprocessable_entity
            end

            ::Patients::RecordTimelineEventJob.perform_later(
              patient_id: @patient.id,
              account_id: Current.account.id,
              actor_id: current_user.id,
              event_type: 'appointment_canceled',
              label: "Consulta cancelada — #{@appointment.scheduled_at.strftime('%d/%m/%Y às %H:%M')}",
              reference_type: 'PatientAppointment',
              reference_id: @appointment.id,
              metadata: { reason: params[:cancellation_reason] }
            )

            render 'api/v1/accounts/patients/appointments/show'
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/appointments/:id/no_show
          def no_show
            if @appointment
              # Fluxo normal: PatientAppointment encontrado
              unless %w[scheduled confirmed arrived].include?(@appointment.status)
                return render json: {
                  error: "Agendamento com status '#{@appointment.status}' não pode ser marcado como falta"
                }, status: :unprocessable_entity
              end

              @appointment.mark_no_show!
              @patient.update(needs_recall: true)

              ::Patients::RecordTimelineEventJob.perform_later(
                patient_id: @patient.id,
                account_id: Current.account.id,
                actor_id: current_user.id,
                event_type: 'appointment_no_show',
                label: "Falta registrada — #{@appointment.scheduled_at.strftime('%d/%m/%Y às %H:%M')}. Total de faltas: #{@patient.reload.no_show_count}",
                reference_type: 'PatientAppointment',
                reference_id: @appointment.id,
                metadata: {
                  no_show_count: @patient.no_show_count,
                  patient_status: @patient.patient_status
                }
              )

              render 'api/v1/accounts/patients/appointments/show'
            elsif @agenda_event
              # Fallback: só AgendaEvent existe (não há PatientAppointment criado)
              unless %w[scheduled confirmed arrived].include?(@agenda_event.status.to_s)
                return render json: {
                  error: "Agendamento com status '#{@agenda_event.status}' não pode ser marcado como falta"
                }, status: :unprocessable_entity
              end

              @agenda_event.update!(status: 'no_show')
              @patient.increment!(:no_show_count)
              @patient.update(needs_recall: true)

              render json: {
                id: @agenda_event.id,
                status: 'no_show',
                no_show_count: @patient.no_show_count
              }, status: :ok
            else
              render json: { error: 'Agendamento não encontrado' }, status: :not_found
            end
          end

          private

          def set_appointment
            @agenda_event = Current.account.agenda_events.find_by(id: params[:id])
            @appointment  = @patient.patient_appointments.active
                                    .find_by(agenda_event_id: params[:id]) ||
                            @patient.patient_appointments.active.find_by(id: params[:id])
          end

          def apply_filters(scope)
            scope = scope.by_status(params[:status].split(',')) if params[:status].present?
            scope = scope.where('scheduled_at >= ?', Date.parse(params[:from])) if params[:from].present?
            scope = scope.where('scheduled_at <= ?', Date.parse(params[:to])) if params[:to].present?
            scope = scope.where(professional_id: params[:professional_id]) if params[:professional_id].present?
            scope
          end

          def appointment_params
            params.require(:appointment).permit(
              :appointment_type,
              :scheduled_at,
              :ends_at,
              :duration_minutes,
              :professional_id,
              :agenda_event_id,
              :notes,
              :return_in_days,
              :treatment_plan_id
            )
          end

          def reschedule_params
            params.require(:appointment).permit(
              :new_scheduled_at,
              :new_ends_at,
              :duration_minutes,
              :reschedule_reason,
              :professional_id,
              :notes
            )
          end
        end
      end
    end
  end
end
