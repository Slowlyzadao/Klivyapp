module Api
  module V1
    module Accounts
      class BankAccountsController < Api::V1::Accounts::BaseController
        before_action :set_bank_account, only: [:show, :update, :destroy]

        # GET /api/v1/accounts/:account_id/financial/bank_accounts
        def index
          authorize BankAccount

          accounts = Current.account.bank_accounts.ordered
          accounts = accounts.active if params[:active] != 'false'

          render json: {
            bank_accounts: accounts.map { |ba| serialize(ba) },
            total_balance: accounts.sum(&:current_balance).round(2)
          }
        end

        # GET /api/v1/accounts/:account_id/financial/bank_accounts/:id
        def show
          authorize @bank_account
          render json: { bank_account: serialize(@bank_account) }
        end

        # POST /api/v1/accounts/:account_id/financial/bank_accounts
        def create
          authorize BankAccount

          @bank_account = Current.account.bank_accounts.new(bank_account_params)

          if @bank_account.save
            render json: { bank_account: serialize(@bank_account) }, status: :created
          else
            render json: { errors: @bank_account.errors.full_messages }, status: :unprocessable_entity
          end
        end

        # PATCH /api/v1/accounts/:account_id/financial/bank_accounts/:id
        def update
          authorize @bank_account

          if @bank_account.update(bank_account_params)
            render json: { bank_account: serialize(@bank_account) }
          else
            render json: { errors: @bank_account.errors.full_messages }, status: :unprocessable_entity
          end
        end

        # DELETE /api/v1/accounts/:account_id/financial/bank_accounts/:id
        def destroy
          authorize @bank_account

          @bank_account.update!(active: false)
          render json: { message: 'Conta desativada com sucesso' }
        end

        private

        def set_bank_account
          @bank_account = Current.account.bank_accounts.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: 'Conta bancária não encontrada' }, status: :not_found
        end

        def bank_account_params
          params.require(:bank_account).permit(
            :name, :bank_name, :bank_code, :account_type, :initial_balance, :active
          )
        end

        def serialize(ba)
          {
            id: ba.id,
            name: ba.name,
            bank_name: ba.bank_name,
            bank_code: ba.bank_code,
            account_type: ba.account_type,
            initial_balance: ba.initial_balance.to_f,
            current_balance: ba.current_balance.to_f,
            active: ba.active
          }
        end
      end
    end
  end
end
