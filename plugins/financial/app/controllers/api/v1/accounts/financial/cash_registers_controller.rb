module Api
  module V1
    module Accounts
      module Financial
        class CashRegistersController < BaseController
          before_action :set_register, only: %i[show close reopen withdraw supplement]

          def index
            scope = ::Financial::CashRegister.for_account(current_account.id)
            scope = scope.where(financial_bank_account_id: params[:bank_account_id]) if params[:bank_account_id].present?
            scope = scope.where('session_date >= ?', params[:from]) if params[:from].present?
            scope = scope.where('session_date <= ?', params[:to]) if params[:to].present?
            scope = scope.where(status: params[:status]) if params[:status].present?
            scope = scope.order(session_date: :desc, id: :desc)
            list = scope.includes(:operator).limit(60)
            render json: { data: list.map { |r| serialize(r) } }
          end

          def show
            render json: serialize(@register, include_movements: true)
          end

          # POST /financial/v2/cash_registers/open
          def open
            require_role!('RECEPCAO', 'GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[RECEPCAO GERENTE ADMIN])

            idempotent! do
              bank = ::Financial::BankAccount.for_account(current_account.id).find(params[:bank_account_id])
              result = ::Financial::CashRegisterService.open(
                account: current_account, actor: current_user, bank_account: bank,
                opening_balance_cents: params[:opening_balance_cents].to_i,
                session_date: params[:session_date],
                note: params[:note]
              )
              if result.success?
                render json: serialize(result[:cash_register]), status: :created
              else
                render json: { errors: result.errors }, status: :unprocessable_entity
              end
            end
          end

          # POST /financial/v2/cash_registers/:id/close
          def close
            require_role!('RECEPCAO', 'GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[RECEPCAO GERENTE ADMIN])

            idempotent! do
              result = ::Financial::CashRegisterService.close(
                register: @register, actor: current_user,
                counted_balance_cents: params[:counted_balance_cents].to_i,
                note: params[:note]
              )
              if result.success?
                render json: serialize(result[:cash_register]).merge(difference_cents: result[:difference_cents]), status: :ok
              else
                render json: { errors: result.errors }, status: :unprocessable_entity
              end
            end
          end

          # POST /financial/v2/cash_registers/:id/reopen
          def reopen
            require_role!('GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[GERENTE ADMIN])
            return render(json: { errors: ['motivo obrigatório'] }, status: :unprocessable_entity) if params[:reason].blank?

            idempotent! do
              result = ::Financial::CashRegisterService.reopen(
                register: @register, actor: current_user, reason: params[:reason]
              )
              if result.success?
                render json: serialize(result[:cash_register]), status: :ok
              else
                render json: { errors: result.errors }, status: :unprocessable_entity
              end
            end
          end

          # POST /financial/v2/cash_registers/:id/withdraw
          def withdraw
            require_role!('RECEPCAO', 'GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[RECEPCAO GERENTE ADMIN])

            idempotent! do
              target = ::Financial::BankAccount.for_account(current_account.id).find(params[:to_bank_account_id])
              result = ::Financial::CashRegisterService.withdraw(
                register: @register, actor: current_user, target_bank_account: target,
                amount_cents: params[:amount_cents].to_i,
                occurred_at: params[:occurred_at],
                notes: params[:notes]
              )
              if result.success?
                render json: { movement: serialize_movement(result[:movement]) }, status: :created
              else
                render json: { errors: result.errors }, status: :unprocessable_entity
              end
            end
          end

          # POST /financial/v2/cash_registers/:id/supplement
          def supplement
            require_role!('RECEPCAO', 'GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[RECEPCAO GERENTE ADMIN])

            idempotent! do
              source = ::Financial::BankAccount.for_account(current_account.id).find(params[:from_bank_account_id])
              result = ::Financial::CashRegisterService.supplement(
                register: @register, actor: current_user, source_bank_account: source,
                amount_cents: params[:amount_cents].to_i,
                occurred_at: params[:occurred_at],
                notes: params[:notes]
              )
              if result.success?
                render json: { movement: serialize_movement(result[:movement]) }, status: :created
              else
                render json: { errors: result.errors }, status: :unprocessable_entity
              end
            end
          end

          private

          def set_register
            @register = ::Financial::CashRegister.for_account(current_account.id).find(params[:id])
          end

          def serialize(r, include_movements: false)
            # `operator` é o User que abriu o caixa (`belongs_to :operator`).
            # Adicionado pra UI exibir coluna "Responsável" na tabela do
            # histórico — wireframe canon §4.8.
            op = r.operator
            data = {
              id: r.id,
              bank_account_id: r.financial_bank_account_id,
              operator_id: r.operator_id,
              operator: op ? {
                id: op.id,
                name: op.name,
                avatar_url: op.try(:avatar_url)
              } : nil,
              session_date: r.session_date,
              status: r.status,
              opening_balance_cents: r.opening_balance_cents,
              expected_balance_cents: r.expected_balance_cents,
              counted_balance_cents: r.counted_balance_cents,
              difference_cents: r.difference_cents,
              opened_at: r.opened_at,
              closed_at: r.closed_at,
              opening_note: r.opening_note,
              closing_note: r.closing_note,
              calculated_expected_cents: r.calculated_expected_cents
            }
            data[:movements] = r.cash_movements.map(&method(:serialize_movement)) if include_movements
            data
          end

          def serialize_movement(m)
            {
              id: m.id, kind: m.kind, amount_cents: m.amount_cents,
              bank_account_id: m.financial_bank_account_id,
              entry_in_id: m.financial_entry_in_id,
              entry_out_id: m.financial_entry_out_id,
              occurred_at: m.occurred_at, notes: m.notes
            }
          end
        end
      end
    end
  end
end
