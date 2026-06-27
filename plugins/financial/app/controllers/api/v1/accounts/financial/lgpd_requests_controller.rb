module Api
  module V1
    module Accounts
      module Financial
        # LGPD — solicitações de anonimização (canon F-33 §parte 2).
        #
        # Workflow:
        #   POST   /lgpd_requests              → cria (status='pending')
        #   POST   /lgpd_requests/:id/approve  → ADMIN aprova (status='approved')
        #   POST   /lgpd_requests/:id/reject   → ADMIN rejeita
        #   POST   /lgpd_requests/:id/execute  → executa anonimização (irreversível)
        #   POST   /lgpd_requests/:id/cancel   → cancela (paciente desiste antes de executar)
        #
        # Permissões:
        #   - listar/show: ADMIN/AUDITOR/GERENTE
        #   - criar: ADMIN/GERENTE (em produção pode vir do form do paciente)
        #   - approve/reject/execute/cancel: ADMIN apenas
        class LgpdRequestsController < BaseController
          before_action :require_admin_or_auditor!, only: %i[index show]
          before_action :require_admin_or_manager!, only: [:create]
          before_action :require_admin_only!, only: %i[approve reject execute cancel]
          before_action :set_request, only: %i[show approve reject execute cancel]

          def index
            scope = ::Financial::LgpdRequest.where(account_id: current_account.id)
            scope = scope.where(status: params[:status]) if params[:status].present?
            scope = scope.where('created_at >= ?', params[:from]) if params[:from].present?
            scope = scope.where('created_at <= ?', params[:to]) if params[:to].present?

            page = (params[:page] || 1).to_i
            per = [(params[:per_page] || 25).to_i, 100].min
            total = scope.count
            requests = scope.order(created_at: :desc)
                            .includes(:patient, :approved_by, :executed_by, :rejected_by)
                            .offset((page - 1) * per).limit(per)

            render json: {
              data: requests.map(&method(:serialize)),
              meta: {
                page: page, per_page: per, total: total,
                summary: build_summary
              }
            }
          end

          def show
            render json: serialize(@request)
          end

          # Body: { lgpd_request: { patient_id, reason, notes } }
          def create
            idempotent! do
              attrs = request_params.merge(
                account_id: current_account.id,
                status: 'pending',
                requested_at: Time.current,
                created_by_id: current_user&.id
              )
              lgpd_request = ::Financial::LgpdRequest.new(attrs)
              if lgpd_request.save
                render json: serialize(lgpd_request), status: :created
              else
                render json: { errors: lgpd_request.errors.full_messages }, status: :unprocessable_entity
              end
            end
          end

          def approve
            unless @request.pending?
              return render(json: { error: "Apenas solicitações 'pending' podem ser aprovadas (atual: '#{@request.status}')" },
                            status: :unprocessable_entity)
            end

            @request.update!(status: 'approved', approved_at: Time.current,
                             approved_by_id: current_user&.id, notes: params[:notes].presence || @request.notes)
            render json: serialize(@request)
          end

          def reject
            unless @request.pending?
              return render(json: { error: "Apenas solicitações 'pending' podem ser rejeitadas (atual: '#{@request.status}')" },
                            status: :unprocessable_entity)
            end
            reason = params[:rejection_reason].to_s.strip
            return render(json: { error: 'Motivo de rejeição obrigatório' }, status: :unprocessable_entity) if reason.blank?

            @request.update!(status: 'rejected', rejected_at: Time.current,
                             rejected_by_id: current_user&.id, rejection_reason: reason)
            render json: serialize(@request)
          end

          # Executa de fato a anonimização. Irreversível. Só admin via
          # request 'approved'.
          def execute
            unless @request.executable?
              return render(json: { error: "Solicitação precisa estar 'approved' (atual: '#{@request.status}')" },
                            status: :unprocessable_entity)
            end

            idempotent! do
              result = ::Financial::AnonymizePatient.call(
                patient: @request.patient, user: current_user
              )
              if result.success?
                @request.update!(
                  status: 'executed', executed_at: Time.current,
                  executed_by_id: current_user&.id,
                  anonymized_fields: result.anonymized_fields
                )
                render json: serialize(@request)
              else
                render json: { error: result.error }, status: :unprocessable_entity
              end
            end
          end

          def cancel
            unless @request.cancelable?
              return render(json: { error: "Solicitação não pode ser cancelada no status '#{@request.status}'" },
                            status: :unprocessable_entity)
            end
            @request.update!(status: 'cancelled')
            render json: serialize(@request)
          end

          private

          def set_request
            @request = ::Financial::LgpdRequest.where(account_id: current_account.id).find(params[:id])
          end

          def request_params
            params.require(:lgpd_request).permit(:patient_id, :reason, :notes)
          end

          def require_admin_or_auditor!
            render(json: { error: 'forbidden' }, status: :forbidden) \
              unless user_has_any_role?(%w[ADMIN AUDITOR GERENTE])
          end

          def require_admin_or_manager!
            render(json: { error: 'forbidden' }, status: :forbidden) \
              unless user_has_any_role?(%w[ADMIN GERENTE])
          end

          def require_admin_only!
            render(json: { error: 'forbidden' }, status: :forbidden) \
              unless user_has_any_role?(%w[ADMIN])
          end

          def build_summary
            scope = ::Financial::LgpdRequest.where(account_id: current_account.id)
            {
              pending:   scope.pending.count,
              approved:  scope.approved.count,
              executed:  scope.executed.count,
              rejected:  scope.rejected.count,
              cancelled: scope.cancelled.count
            }
          end

          def serialize(r)
            patient = r.patient
            {
              id: r.id,
              status: r.status,
              reason: r.reason,
              notes: r.notes,
              requested_at: r.requested_at,
              approved_at: r.approved_at,
              approved_by: serialize_user(r.approved_by),
              executed_at: r.executed_at,
              executed_by: serialize_user(r.executed_by),
              rejected_at: r.rejected_at,
              rejected_by: serialize_user(r.rejected_by),
              rejection_reason: r.rejection_reason,
              anonymized_fields: r.anonymized_fields,
              patient: patient ? {
                id: patient.id,
                # Quando já anonymized, o `name` já é "Paciente Anonimizado #ID";
                # se ainda não, mostra o real (ADMIN vendo ANTES da execução).
                name: patient.name,
                anonymized_at: patient.anonymized_at,
                avatar_url: patient.try(:resolved_avatar_url)
              } : nil,
              created_at: r.created_at
            }
          end

          def serialize_user(user)
            return nil unless user
            { id: user.id, name: user.name }
          end
        end
      end
    end
  end
end
