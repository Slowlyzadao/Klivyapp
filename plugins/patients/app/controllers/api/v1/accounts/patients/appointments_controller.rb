module Api
  module V1
    module Accounts
      module Patients
        class AppointmentsController < Api::V1::Accounts::Patients::BaseController
          # Auditoria UX 2026-05-15: actions `reschedule`, `cancel` e `no_show`
          # foram removidas — operação de agenda agora é exclusiva do
          # calendário principal. Aba do prontuário fica read-only para
          # histórico + recall via WhatsApp. Removidos junto: rotas
          # correspondentes (config/routes.rb) e o service
          # `Patients::AppointmentRescheduler`.
          before_action :set_appointment, only: [:show]

          private

          # Override: controller_name é 'appointments' mas o modelo é PatientAppointment
          def check_authorization(_model = nil)
            authorize(PatientAppointment)
          end

          public
          # GET /api/v1/accounts/:account_id/patients/:patient_id/appointments
          # IMPORTANTE: inclui eventos soft-deletados (deleted_at != nil)
          # para rastreabilidade no prontuário do paciente. Status efetivo
          # de eventos deletados é derivado do `deletion_reason` (ex.:
          # `deleted_user`, `deleted_patient`, `deleted_reschedule`,
          # `deleted_other`) — tabela `Agenda e Histórico` mostra com badge
          # próprio + motivo/nota.
          def index
            events = AgendaEvent
                       .includes(:user, :deleted_by)
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
              starts = e.starts_at
              ends   = e.ends_at
              duration = ends && starts ? ((ends - starts) / 60).to_i : 60

              # Status efetivo: se soft-deletado, deriva do deletion_reason
              status = if e.deleted_at.present?
                         derived_deleted_status(e.deletion_reason)
                       else
                         e.status.presence || 'scheduled'
                       end

              upcoming = starts && starts > now
              no_show_statuses = %w[no_show].freeze
              canceled_statuses = %w[canceled cancelled deleted_user deleted_patient deleted_reschedule deleted_other].freeze

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
                # Soft-delete metadata exposta para o prontuário
                deleted_at: e.deleted_at&.iso8601,
                deletion_reason: e.deletion_reason,
                deletion_reason_label: AgendaEvent::REASON_LABELS[e.deletion_reason.to_s],
                deletion_note: e.deletion_note,
                deleted_by: e.deleted_by ? { id: e.deleted_by.id, name: e.deleted_by.available_name } : nil,
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
                cancellable: e.deleted_at.nil? && %w[scheduled confirmed arrived].include?(status),
                reschedulable: e.deleted_at.nil? && %w[scheduled confirmed].include?(status),
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
              render_error(result.error, status: status)
            end
          end

          # Actions `reschedule`, `cancel`, `no_show` removidas em 2026-05-15
          # (auditoria UX Opção 1). Operação de agenda passou a ser exclusiva
          # do calendário principal — elimina duplicação que causava
          # AgendaEvent ↔ PatientAppointment divergentes.

          private

          # Mapeia deletion_reason → status virtual usado pelo frontend.
          # Os valores aqui devem casar com o APPOINTMENT_STATUS_CONFIG da
          # ScheduleTab (plugins/patients/frontend/routes/patients/tabs/ScheduleTab.vue).
          def derived_deleted_status(reason)
            case reason.to_s
            when 'cancelamento_usuario'  then 'deleted_user'
            when 'cancelamento_paciente' then 'deleted_patient'
            when 'reagendamento'         then 'deleted_reschedule'
            when 'outro'                 then 'deleted_other'
            else 'deleted_other'
            end
          end

          def set_appointment
            @appointment = @patient.patient_appointments.active
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

          # `reschedule_params` removido junto com a action `reschedule` na
          # auditoria UX 2026-05-15 (Opção 1).
        end
      end
    end
  end
end
