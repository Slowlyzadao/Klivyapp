module Api
  module V1
    module Accounts
      module Patients
        class ClinicalNotesController < Api::V1::Accounts::BaseController
          include BeclinicErrorResponse

          before_action :set_patient
          before_action :set_note, only: [:show, :update, :sign, :destroy, :mark_erratum]

          # GET /api/v1/accounts/:account_id/patients/:patient_id/clinical_notes
          def index
            # `.includes(...)` evita N+1: o partial `_clinical_note.json.jbuilder`
            # acessa `note.professional`, `note.signed_by` e `note.erratum_by`
            # — sem preload, cada nota dispara até 3 queries adicionais.
            @notes = policy_scope(
              @patient.clinical_notes
                      .active
                      .includes(:professional, :signed_by, :erratum_by)
                      .order(note_date: :desc, created_at: :desc)
            )
            render 'api/v1/accounts/patients/clinical_notes/index'
          end

          # GET /api/v1/accounts/:account_id/patients/:patient_id/clinical_notes/:id
          def show
            authorize @note
            render 'api/v1/accounts/patients/clinical_notes/show'
          end

          # POST /api/v1/accounts/:account_id/patients/:patient_id/clinical_notes
          def create
            @note = @patient.clinical_notes.new(note_params)
            @note.account      = Current.account
            @note.professional = current_user
            @note.note_date    = Date.current if @note.note_date.blank?
            authorize @note

            if @note.save
              PatientAuditLog.log!(
                account: Current.account,
                patient: @patient,
                actor: current_user,
                action: 'create',
                resource: @note
              )
              ::Patients::RecordTimelineEventJob.perform_later(
                patient_id: @patient.id,
                account_id: Current.account.id,
                actor_id: current_user.id,
                event_type: 'clinical_note',
                reference_type: 'ClinicalNote',
                reference_id: @note.id,
                label: 'Evolução clínica criada'
              )
              render 'api/v1/accounts/patients/clinical_notes/show', status: :created
            else
              render_error(@note.errors.full_messages, status: :unprocessable_entity)
            end
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/clinical_notes/:id
          def update
            authorize @note

            unless @note.editable_by?(current_user)
              render_error('Evolução assinada ou fora da janela de edição.', status: :forbidden)
              return
            end

            if @note.update(note_params)
              PatientAuditLog.log!(
                account: Current.account,
                patient: @patient,
                actor: current_user,
                action: 'update',
                resource: @note
              )
              render 'api/v1/accounts/patients/clinical_notes/show'
            else
              render_error(@note.errors.full_messages, status: :unprocessable_entity)
            end
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/clinical_notes/:id/sign
          # Guard: se já assinado → 403
          def sign
            authorize @note, :update?

            result = ::Patients::ClinicalNoteSignerService.call(note: @note, actor: current_user)

            if result.success?
              ::Patients::RecordTimelineEventJob.perform_later(
                patient_id: @patient.id,
                account_id: Current.account.id,
                actor_id: current_user.id,
                event_type: 'clinical_note',
                reference_type: 'ClinicalNote',
                reference_id: @note.id,
                label: "Evolução clínica assinada por #{current_user.name}"
              )
              render json: { success: true, signed_at: @note.signed_at.iso8601 }
            else
              Rails.logger.error "SIGN ERROR: #{result.error}"
              render_error(result.error, status: :forbidden)
            end
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/clinical_notes/:id/mark_erratum
          # Marca a evolução como errata sem apagar/editar o conteúdo.
          # Body: { reason: "Justificativa..." }
          def mark_erratum
            authorize @note

            reason = params[:reason].to_s.strip
            if reason.blank?
              render_error('Justificativa da errata é obrigatória.', status: :unprocessable_entity)
              return
            end

            begin
              @note.mark_as_erratum!(actor: current_user, reason: reason)
              PatientAuditLog.log!(
                account: Current.account,
                patient: @patient,
                actor: current_user,
                action: 'erratum',
                resource: @note,
                changes: { erratum_reason: reason }
              )
              ::Patients::RecordTimelineEventJob.perform_later(
                patient_id: @patient.id,
                account_id: Current.account.id,
                actor_id: current_user.id,
                event_type: 'clinical_note',
                reference_type: 'ClinicalNote',
                reference_id: @note.id,
                label: "Evolução clínica marcada como errata por #{current_user.name}"
              )
              render 'api/v1/accounts/patients/clinical_notes/show'
            rescue RuntimeError => e
              render_error(e.message, status: :unprocessable_entity)
            end
          end

          # DELETE /api/v1/accounts/:account_id/patients/:patient_id/clinical_notes/:id
          def destroy
            authorize @note

            begin
              @note.soft_delete!
              PatientAuditLog.log!(
                account: Current.account,
                patient: @patient,
                actor: current_user,
                action: 'delete',
                resource: @note
              )
              head :no_content
            rescue RuntimeError => e
              render_error(e.message, status: :forbidden)
            end
          end

          private

          def set_patient
            @patient = Current.account.patients.find(params[:patient_id])
          rescue ActiveRecord::RecordNotFound
            render_error('Paciente não encontrado.', status: :not_found)
          end

          def set_note
            @note = @patient.clinical_notes.active.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_error('Evolução não encontrada.', status: :not_found)
          end

          def note_params
            params.require(:clinical_note).permit(
              :appointment_id, :form_template_id, :note_date,
              :complaint_of_day, :assessment, :conduct,
              :complications, :guidance_given, :return_recommended,
              :lock_version # Roadmap #13 — optimistic locking
            )
          end
        end
      end
    end
  end
end
