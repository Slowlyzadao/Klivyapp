module Api
  module V1
    module Accounts
      module Financial
        class BudgetsController < BaseController
          before_action :set_budget, only: %i[show update destroy approve cancel update_installments]

          def index
            scope = ::Financial::Budget.for_account(current_account.id)
            scope = scope.where(status: params[:status]) if params[:status].present?
            scope = scope.where(patient_id: params[:patient_id]) if params[:patient_id].present?
            scope = scope.where(origin: params[:origin]) if params[:origin].present?
            scope = scope.order(created_at: :desc)
            render json: { data: scope.limit(100).map { |b| serialize(b) } }
          end

          def show
            render json: serialize(@budget, include_items: true, include_installments: true)
          end

          def create
            idempotent! do
              budget = ::Financial::Budget.new(budget_params.merge(account_id: current_account.id))
              ::ActiveRecord::Base.transaction do
                budget.save!
                items_param.each_with_index do |item_attrs, idx|
                  budget.items.create!(item_attrs.merge(account_id: current_account.id, position: idx))
                end
                budget.update!(
                  subtotal_cents: budget.items.sum(:total_cents),
                  total_cents: budget.items.sum(:total_cents) - budget.discount_cents.to_i
                )
              end
              render json: serialize(budget.reload, include_items: true), status: :created
            end
          rescue ActiveRecord::RecordInvalid => e
            render json: { errors: [e.record.errors.full_messages.join('; ')] }, status: :unprocessable_entity
          end

          def update
            require_role!('GERENTE', 'ADMIN') and return unless can_edit_budget?

            return render(json: { error: 'orçamento concluído não pode ser editado' }, status: :unprocessable_entity) if @budget.concluded?

            if @budget.approved? && @budget.has_paid_installments?
              return render(json: { error: 'orçamento com parcela paga só pode ter parcelas pendentes editadas via /update_installments' }, status: :unprocessable_entity)
            end

            if @budget.update(budget_params)
              render json: serialize(@budget, include_items: true)
            else
              render json: { errors: @budget.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def destroy
            require_role!('ADMIN') and return unless user_has_any_role?(%w[ADMIN])

            unless @budget.deletable?
              return render(json: { error: 'orçamento com parcela paga não pode ser excluído. Use cancel.' }, status: :unprocessable_entity)
            end
            @budget.soft_delete!(user: current_user)
            head :no_content
          end

          # POST /budgets/:id/approve
          def approve
            require_role!('RECEPCAO', 'GERENTE', 'ADMIN', 'DENTIST') and return unless user_has_any_role?(%w[RECEPCAO GERENTE ADMIN DENTIST])

            idempotent! do
              result = ::Financial::ApproveBudget.call(
                budget: @budget,
                actor: current_user,
                installments_plan: params[:installments_plan],
                payment_method: params[:payment_method],
                first_due_date: params[:first_due_date],
                interval_days: (params[:interval_days] || 30).to_i
              )
              if result.success?
                render json: serialize(result[:budget].reload, include_installments: true), status: :ok
              else
                render json: { errors: result.errors }, status: :unprocessable_entity
              end
            end
          end

          # POST /budgets/:id/cancel  (BUG-02)
          def cancel
            require_role!('GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[GERENTE ADMIN])

            idempotent! do
              result = ::Financial::EditApprovedBudget.cancel(budget: @budget, actor: current_user, reason: params[:reason])
              if result.success?
                render json: serialize(result[:budget], include_installments: true)
              else
                render json: { errors: result.errors }, status: :unprocessable_entity
              end
            end
          end

          # PATCH /budgets/:id/update_installments  (BUG-02)
          def update_installments
            require_role!('GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[GERENTE ADMIN])

            idempotent! do
              changes = Array(params[:installments]).map do |c|
                {
                  id: c[:id].to_i,
                  amount_cents: c[:amount_cents],
                  due_date: c[:due_date],
                  payment_method: c[:payment_method]
                }.compact
              end
              result = ::Financial::EditApprovedBudget.update_installments(
                budget: @budget, actor: current_user, installment_changes: changes
              )
              if result.success?
                render json: serialize(result[:budget], include_installments: true)
              else
                render json: { errors: result.errors }, status: :unprocessable_entity
              end
            end
          end

          private

          def can_edit_budget?
            user_has_any_role?(%w[GERENTE ADMIN]) || (@budget.draft? && user_has_any_role?(%w[RECEPCAO DENTIST]))
          end

          def set_budget
            @budget = ::Financial::Budget.for_account(current_account.id).find(params[:id])
          end

          def budget_params
            params.require(:budget).permit(
              :patient_id, :professional_id, :treatment_plan_id, :origin, :status,
              :subtotal_cents, :discount_cents, :discount_kind, :discount_basis_points, :total_cents,
              :installments_count, :payment_method, :notes, :valid_until, :external_id
            )
          end

          def items_param
            Array(params.dig(:budget, :items)).map do |i|
              i.permit(:treatment_item_id, :description, :procedure_code, :quantity,
                       :unit_price_cents, :discount_cents, :total_cents, :professional_id, :position).to_h
            end
          end

          def serialize(b, include_items: false, include_installments: false)
            data = {
              id: b.id,
              patient_id: b.patient_id,
              professional_id: b.professional_id,
              treatment_plan_id: b.treatment_plan_id,
              origin: b.origin,
              status: b.status,
              subtotal_cents: b.subtotal_cents,
              discount_cents: b.discount_cents,
              total_cents: b.total_cents,
              installments_count: b.installments_count,
              payment_method: b.payment_method,
              notes: b.notes,
              valid_until: b.valid_until,
              approved_at: b.approved_at,
              canceled_at: b.canceled_at,
              has_paid_installments: b.has_paid_installments?,
              deletable: b.deletable?,
              created_at: b.created_at,
              updated_at: b.updated_at
            }
            data[:items] = b.items.map { |i| serialize_item(i) } if include_items
            data[:installments] = b.installments.order(:number).map { |i| serialize_installment(i) } if include_installments
            data
          end

          def serialize_item(i)
            {
              id: i.id, description: i.description, procedure_code: i.procedure_code,
              quantity: i.quantity, unit_price_cents: i.unit_price_cents,
              discount_cents: i.discount_cents, total_cents: i.total_cents,
              professional_id: i.professional_id, position: i.position
            }
          end

          def serialize_installment(i)
            {
              id: i.id,
              number: i.number,
              total_in_series: i.total_in_series,
              amount_cents: i.amount_cents,
              received_amount_cents: i.received_amount_cents,
              remaining_cents: i.remaining_cents,
              status: i.status,
              payment_method: i.payment_method,
              due_date: i.due_date,
              competence_date: i.competence_date,
              received_at: i.received_at,
              gateway: i.gateway,
              gateway_id: i.gateway_id,
              gateway_status: i.gateway_status,
              payment_link: i.payment_link,
              barcode_line: i.barcode_line,
              pix_qr_code: i.pix_qr_code
            }
          end
        end
      end
    end
  end
end
