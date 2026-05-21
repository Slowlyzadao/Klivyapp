module Api
  module V1
    module Accounts
      module Financial
        class BankAccountsController < BaseController
          # Setup wizard precisa criar contas antes do setup estar completo.
          skip_before_action :ensure_setup_complete!
          before_action :set_bank_account, only: %i[show update destroy transfer]

          def index
            scope = ::Financial::BankAccount.for_account(current_account.id)
            scope = scope.where(active: true) if params[:active] == 'true'
            scope = scope.where(kind: params[:kind]) if params[:kind].present?
            render json: { data: scope.map { |a| serialize(a) } }
          end

          def show
            render json: serialize(@bank_account)
          end

          def create
            require_role!('GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[GERENTE ADMIN])

            idempotent_optional! do
              bank = ::Financial::BankAccount.new(bank_params.merge(account_id: current_account.id))
              if bank.save
                render json: serialize(bank), status: :created
              else
                render json: { errors: bank.errors.full_messages }, status: :unprocessable_entity
              end
            end
          end

          def update
            require_role!('GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[GERENTE ADMIN])

            forbid_balance_change_after_create
            if @bank_account.update(bank_params.except(:initial_balance, :initial_balance_cents))
              render json: serialize(@bank_account)
            else
              render json: { errors: @bank_account.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def destroy
            require_role!('ADMIN') and return unless user_has_any_role?(%w[ADMIN])
            if @bank_account.current_balance_cents != 0
              return render(json: { error: 'conta com saldo ≠ 0. Transfira o saldo antes de excluir.' }, status: :unprocessable_entity)
            end

            @bank_account.soft_delete!(user: current_user)
            head :no_content
          end

          # POST /financial/v2/bank_accounts/:id/transfer
          def transfer
            require_role!('GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[GERENTE ADMIN])

            idempotent! do
              to = ::Financial::BankAccount.for_account(current_account.id).find(params[:to_bank_account_id])
              result = ::Financial::TransferBetweenAccounts.call(
                account: current_account,
                actor: current_user,
                from_bank_account: @bank_account,
                to_bank_account: to,
                amount_cents: params[:amount_cents].to_i,
                occurred_at: params[:occurred_at],
                notes: params[:notes]
              )
              if result.success?
                render json: { entry_in: serialize_entry(result[:entry_in]), entry_out: serialize_entry(result[:entry_out]) },
                       status: :created
              else
                render json: { errors: result.errors }, status: :unprocessable_entity
              end
            end
          end

          private

          def scope
            ::Financial::BankAccount.for_account(current_account.id)
          end

          def set_bank_account
            @bank_account = scope.find(params[:id])
          end

          def bank_params
            params.require(:bank_account).permit(
              :name, :kind, :bank_name, :bank_code, :agency, :account_number,
              :initial_balance, :initial_balance_cents, :active, :card_settlement_days
            )
          end

          def forbid_balance_change_after_create
            if bank_params.keys.intersect?(%w[initial_balance initial_balance_cents])
              # silently drop — não permitido após criação (canon §4.2 "saldo inicial editável só na criação")
            end
          end

          def serialize(a)
            {
              id: a.id,
              name: a.name,
              kind: a.kind,
              bank_name: a.bank_name,
              bank_code: a.bank_code,
              agency: a.agency,
              account_number: a.account_number,
              initial_balance_cents: a.initial_balance_cents,
              current_balance_cents: a.current_balance_cents,
              active: a.active,
              card_settlement_days: a.card_settlement_days
            }
          end

          def serialize_entry(e)
            return nil unless e
            {
              id: e.id,
              direction: e.direction,
              kind: e.kind,
              amount_cents: e.amount_cents,
              cash_date: e.cash_date,
              competence_date: e.competence_date,
              description: e.description
            }
          end
        end
      end
    end
  end
end
