module Api
  module V1
    module Accounts
      module Patients
        class TreatmentPlansController < Api::V1::Accounts::Patients::BaseController
          before_action :set_treatment_plan, only: [:show, :update, :destroy, :approve, :cancel, :pdf]

          # GET /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans
          def index
            authorize TreatmentPlan
            # `.includes(...)` evita N+1 contra jbuilder do plan, que acessa:
            #   - approved_by&.name
            #   - professional&.name + professional&.avatar_url (User Avatarable: avatar.attached? + url_for)
            #   - pdf.attached? + rails_blob_url(...pdf)
            #   - treatment_items + cada item com sessions/discount/etc
            # Sem preload completo de avatar_attachment + blob, cada plano dispara
            # 2-3 queries extras ao Active Storage por causa do avatar do profissional.
            @treatment_plans = @patient.treatment_plans
                                       .where(deleted_at: nil)
                                       .includes(
                                         :treatment_items,
                                         :approved_by,
                                         { professional: { avatar_attachment: :blob } },
                                         { pdf_attachment: :blob }
                                       )
                                       .order(created_at: :desc)

            render 'api/v1/accounts/patients/treatment_plans/index'
          end

          # GET /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans/:id
          def show
            authorize @treatment_plan
            render 'api/v1/accounts/patients/treatment_plans/show'
          end

          # POST /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans
          def create
            authorize TreatmentPlan
            @treatment_plan = @patient.treatment_plans.build(treatment_plan_params)
            @treatment_plan.account = Current.account
            @treatment_plan.professional = current_user

            if @treatment_plan.save
              PatientAuditLog.log!(
                account: Current.account,
                patient: @patient,
                actor: current_user,
                action: 'create',
                resource: @treatment_plan
              )
              PatientTimelineEvent.record!(
                patient: @patient,
                account: Current.account,
                event_type: 'treatment_plan_created',
                label: "Plano de tratamento criado: #{@treatment_plan.title.presence || 'Sem título'}",
                actor: current_user,
                reference: @treatment_plan
              )
              render 'api/v1/accounts/patients/treatment_plans/show', status: :created
            else
              render json: { errors: @treatment_plan.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans/:id
          def update
            authorize @treatment_plan
            if @treatment_plan.update(treatment_plan_params)
              PatientAuditLog.log!(
                account: Current.account,
                patient: @patient,
                actor: current_user,
                action: 'update',
                resource: @treatment_plan
              )
              render 'api/v1/accounts/patients/treatment_plans/show'
            else
              render json: { errors: @treatment_plan.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # DELETE /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans/:id
          def destroy
            authorize @treatment_plan

            # Regra 3 (canon — alinha com Clinicorp/Conta Azul):
            # Excluir PT com Budget v2 vinculado tem 3 cenários distintos:
            #   1. Sem Budget aprovado → exclui livre (cascata).
            #   2. Budget aprovado mas SEM parcela paga → cancela Budget + soft-delete PT
            #      (operador precisa confirmar via header X-Confirm-Cascade).
            #   3. Budget com parcela paga → BLOQUEIA exclusão com mensagem clara.
            #      "Há R$ X recebido. Estorne primeiro."
            linked_budget = ::Financial::Budget.where(
              account_id: @treatment_plan.account_id,
              treatment_plan_id: @treatment_plan.id
            ).where.not(status: 'cancelado').first

            if linked_budget
              if linked_budget.has_paid_installments?
                paid_total_brl = format('%.2f', (linked_budget.installments.sum(:received_amount_cents).to_i / 100.0))
                return render json: {
                  error: "Este plano tem orçamento financeiro com R$ #{paid_total_brl} já recebido(s). " \
                         'Estorne os recebimentos antes de excluir o plano.'
                }, status: :unprocessable_entity
              end

              unless request.headers['X-Confirm-Cascade'] == 'true'
                return render json: {
                  error: 'Este plano tem orçamento financeiro vinculado (sem pagamentos). ' \
                         'Excluir o plano vai cancelar o orçamento. Confirme reenviando com X-Confirm-Cascade: true.',
                  cascade_required: true,
                  budget: { id: linked_budget.id, status: linked_budget.status, total: linked_budget.total_cents / 100.0 }
                }, status: :conflict
              end

              # Cancela o Budget primeiro (mesma transação para atomicidade).
              ActiveRecord::Base.transaction do
                ::Financial::EditApprovedBudget.cancel(
                  budget: linked_budget,
                  actor: current_user,
                  reason: "PT ##{@treatment_plan.id} excluído (cascata canon Regra 3)"
                )
                @treatment_plan.soft_delete!
              end
            else
              @treatment_plan.soft_delete!
            end

            PatientAuditLog.log!(
              account: Current.account,
              patient: @patient,
              actor: current_user,
              action: 'delete',
              resource: @treatment_plan
            )
            PatientTimelineEvent.record!(
              patient: @patient,
              account: Current.account,
              event_type: 'treatment_plan_archived',
              label: "Plano de tratamento arquivado: #{@treatment_plan.title.presence || 'Sem título'}",
              actor: current_user,
              reference: @treatment_plan
            )
            head :no_content
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans/:id/approve
          #
          # Aprova o plano de tratamento clinicamente E gera o orçamento
          # (`Financial::Budget` v2) em RASCUNHO. Substitui o pipeline v1
          # `TreatmentPlanApprover` → `FinancialEstimateGenerator` (deletado
          # em 2026-05-11) — mesma UX 2-step, agora alimentando `financial_*`.
          #
          # Fluxo 2-step (preserva separação clínica/financeira v1):
          #   1. Dentista aprova plano aqui → Budget rascunho aparece em "Precisa
          #      aprovação" no Financial Tab
          #   2. Recepção valida números e clica "Aprovar orçamento" → aí v2
          #      `Financial::ApproveBudget` gera parcelas em A Receber
          #
          # Params opcionais (mesma semântica do v1):
          #   item_ids[]          → aprovação parcial (subset dos itens). Nil = todos.
          #   installments_count  → número de parcelas sugerido (recepção pode
          #                         ajustar antes de aprovar). Default 1.
          #   payment_method      → método default das parcelas.
          def approve
            authorize @treatment_plan

            unless @treatment_plan.status_proposto?
              return render_error('Plano não está em status proposto', status: :unprocessable_entity)
            end

            item_ids = params[:item_ids]

            ActiveRecord::Base.transaction do
              if item_ids.present?
                @treatment_plan.treatment_items
                  .where(deleted_at: nil, id: item_ids, status: 'proposto')
                  .update_all(status: 'aprovado')

                all_ids = @treatment_plan.treatment_items.where(deleted_at: nil).pluck(:id)
                approved_ids = @treatment_plan.treatment_items.where(deleted_at: nil, status: 'aprovado').pluck(:id)
                partially = (all_ids - approved_ids).any?

                @treatment_plan.update!(status: 'aprovado', partially_approved: partially,
                                       approved_by: current_user, approved_at: Date.current)
              else
                @treatment_plan.treatment_items.where(deleted_at: nil, status: 'proposto')
                  .update_all(status: 'aprovado')
                @treatment_plan.update!(status: 'aprovado', partially_approved: false,
                                       approved_by: current_user, approved_at: Date.current)
              end

              ::Patients::TreatmentPlanPdfGenerator.call(
                treatment_plan: @treatment_plan,
                actor: current_user
              )
            end

            # Gera o orçamento em rascunho ("Precisa aprovação" no Financial
            # Tab). Roda FORA da transaction do approve clínico — se falhar
            # (ex: itens sem preço), o plano fica aprovado, e o erro vai pro
            # log como warning sem reverter a aprovação clínica.
            budget_result = ::Patients::TreatmentPlanBudgetCreator.call(
              treatment_plan: @treatment_plan.reload,
              actor: current_user,
              installments_count: params[:installments_count].presence || 1,
              payment_method: params[:payment_method]
            )

            unless budget_result.success?
              Rails.logger.warn(
                "[TreatmentPlan##{@treatment_plan.id}] Plano aprovado mas " \
                "geração de orçamento falhou: #{budget_result.error}"
              )
            end

            PatientAuditLog.log!(
              account: Current.account,
              patient: @patient,
              actor: current_user,
              action: 'approve',
              resource: @treatment_plan
            )
            PatientTimelineEvent.record!(
              patient: @patient,
              account: Current.account,
              event_type: 'treatment_plan_approved',
              label: "Plano de tratamento aprovado: #{@treatment_plan.title.presence || 'Sem título'}",
              actor: current_user,
              reference: @treatment_plan
            )
            render 'api/v1/accounts/patients/treatment_plans/show'
          rescue ActiveRecord::RecordInvalid => e
            render_error(e.message, status: :unprocessable_entity)
          end

          # GET /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans/:id/pdf
          # URL stable que sempre serve o blob ATUAL do PDF — evita o problema
          # de cache do `rails_blob_url(signed_id)` no frontend, que aponta
          # pro blob antigo após regeneração.
          def pdf
            authorize @treatment_plan, :show?

            return render_error('PDF não gerado para este plano.', status: :not_found) unless @treatment_plan.pdf.attached?

            send_data @treatment_plan.pdf.download,
                      filename: "plano_tratamento_#{@treatment_plan.id}.pdf",
                      type: 'application/pdf',
                      disposition: 'inline'
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/treatment_plans/:id/cancel
          def cancel
            authorize @treatment_plan

            if @treatment_plan.status_concluido?
              return render_error(I18n.t('errors.treatment_plan.cannot_cancel_concluded'))
            end

            if @treatment_plan.update(status: 'cancelado', cancellation_reason: params[:cancellation_reason])
              PatientAuditLog.log!(
                account: Current.account,
                patient: @patient,
                actor: current_user,
                action: 'update',
                resource: @treatment_plan,
                changes: { status: %w[aprovado cancelado] }
              )
              render 'api/v1/accounts/patients/treatment_plans/show'
            else
              render json: { errors: @treatment_plan.errors.full_messages }, status: :unprocessable_entity
            end
          end

          private

          def set_treatment_plan
            @treatment_plan = @patient.treatment_plans.find_by!(id: params[:id], deleted_at: nil)
          rescue ActiveRecord::RecordNotFound
            render_error('Plano de tratamento não encontrado', status: :not_found)
          end

          def treatment_plan_params
            params.require(:treatment_plan).permit(
              :title,
              :description,
              :estimated_duration,
              :lock_version # Roadmap #13 — optimistic locking
            )
          end
        end
      end
    end
  end
end
