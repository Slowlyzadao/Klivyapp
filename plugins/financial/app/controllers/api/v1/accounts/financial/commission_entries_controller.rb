module Api
  module V1
    module Accounts
      module Financial
        # Ações sobre lançamentos de comissão — canon F-29.
        # O LISTING vive em ReportsController#commissions (relatório agregado
        # por profissional). Aqui só ficam ações que MUTAM (pay, bulk_pay).
        #
        # Permissões:
        #   - Marcar como pago: GERENTE/ADMIN (não DENTIST — profissional não
        #     aprova a própria comissão).
        class CommissionEntriesController < BaseController
          before_action :set_entry, only: [:pay]

          # POST /financial/v2/commission_entries/:id/pay
          # Body opcional: { due_date: 'YYYY-MM-DD', description: '...' }
          def pay
            return unless authorize_pay!

            idempotent! do
              result = ::Financial::PayCommission.call(
                commission_entry: @entry,
                user: current_user,
                due_date: parse_optional_date(params[:due_date]),
                description: params[:description]
              )

              if result.success?
                render json: serialize(result.commission_entry, result.expense)
              else
                render json: { errors: result.errors }, status: :unprocessable_entity
              end
            end
          end

          # POST /financial/v2/commission_entries/bulk_pay
          # Body: { entry_ids: [1, 2, 3], due_date: '...', description: '...' }
          def bulk_pay
            return unless authorize_pay!

            ids = Array(params[:entry_ids]).map(&:to_i).reject(&:zero?)
            return render(json: { errors: ['Selecione ao menos 1 comissão'] }, status: :unprocessable_entity) if ids.empty?

            idempotent! do
              entries = ::Financial::CommissionEntry
                          .for_account(current_account.id)
                          .where(id: ids)

              succeeded = []
              failed = []
              due = parse_optional_date(params[:due_date])

              entries.each do |entry|
                result = ::Financial::PayCommission.call(
                  commission_entry: entry, user: current_user,
                  due_date: due, description: params[:description]
                )
                if result.success?
                  succeeded << serialize(result.commission_entry, result.expense)
                else
                  failed << { id: entry.id, errors: result.errors }
                end
              end

              render json: {
                succeeded: succeeded,
                failed: failed,
                summary: { paid: succeeded.size, errors: failed.size }
              }
            end
          end

          private

          def set_entry
            @entry = ::Financial::CommissionEntry
                       .for_account(current_account.id)
                       .find(params[:id])
          end

          def authorize_pay!
            return true if user_has_any_role?(%w[GERENTE ADMIN])

            render json: { error: 'forbidden', required_roles: %w[GERENTE ADMIN] }, status: :forbidden
            false
          end

          def parse_optional_date(value)
            return nil if value.blank?
            Date.parse(value.to_s)
          rescue ArgumentError
            nil
          end

          def serialize(entry, expense)
            {
              id: entry.id,
              status: entry.status,
              paid_at: entry.paid_at,
              paid_by_id: entry.paid_by_id,
              expense: expense ? {
                id: expense.id,
                description: expense.description,
                amount_cents: expense.amount_cents.to_i,
                status: expense.status,
                due_date: expense.due_date
              } : nil
            }
          end
        end
      end
    end
  end
end
