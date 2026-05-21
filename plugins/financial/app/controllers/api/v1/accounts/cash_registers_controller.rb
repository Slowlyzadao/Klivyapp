module Api
  module V1
    module Accounts
      class CashRegistersController < Api::V1::Accounts::BaseController
        before_action :set_cash_register, only: [:show, :update, :destroy]

        # GET /financial/cash_registers
        # Params: date (YYYY-MM-DD), operator_id, status
        def index
          authorize CashRegister
          registers = policy_scope(CashRegister)
                        .where(account: Current.account)
                        .includes(:operator, :cash_register_entries)

          registers = registers.for_date(params[:date]) if params[:date].present?
          registers = registers.for_operator(params[:operator_id]) if params[:operator_id].present?
          registers = registers.where(status: params[:status]) if params[:status].present?

          render json: registers.recent.map { |r| serialize(r) }
        end

        # GET /financial/cash_registers/:id
        def show
          authorize @cash_register
          render json: serialize(@cash_register, detailed: true)
        end

        # POST /financial/cash_registers
        def create
          authorize CashRegister
          register = Current.account.cash_registers.new(create_params)
          register.operator_id = current_user.id unless params[:operator_id].present?
          register.opened_at   = Time.current

          if register.save
            render json: serialize(register, detailed: true), status: :created
          else
            render json: { errors: register.errors.full_messages }, status: :unprocessable_entity
          end
        end

        # PATCH /financial/cash_registers/:id
        # Used for: adding entries (sangria/suprimento) and closing the register
        def update
          authorize @cash_register

          # Handle closing
          if params[:close] == 'true'
            declared = params[:declared_balance].to_f
            calculated = @cash_register.calculated_balance
            @cash_register.assign_attributes(
              status: 'closed',
              closing_balance: calculated,
              declared_balance: declared,
              difference: declared - calculated,
              closing_notes: params[:closing_notes],
              closed_at: Time.current
            )
          elsif params[:reopen] == 'true'
            @cash_register.assign_attributes(
              status: 'open',
              closing_balance: nil,
              declared_balance: nil,
              difference: nil,
              closing_notes: nil,
              closed_at: nil
            )
          elsif params[:entry_type].present?
            # Add a new one-off entry (supplement or withdrawal)
            amount = params[:amount].to_f
            entry_type = params[:entry_type]

            entry = @cash_register.cash_register_entries.build(
              account: Current.account,
              entry_type: entry_type,
              amount: amount,
              payment_method: params[:payment_method],
              description: params[:description]
            )

            if entry_type == 'supplement'
              @cash_register.supplements += amount
            elsif entry_type == 'withdrawal'
              @cash_register.withdrawals += amount
            end

            entry.save
          else
            @cash_register.assign_attributes(update_params)
          end

          if @cash_register.save
            render json: serialize(@cash_register, detailed: true)
          else
            render json: { errors: @cash_register.errors.full_messages }, status: :unprocessable_entity
          end
        end

        # DELETE /financial/cash_registers/:id
        def destroy
          authorize @cash_register
          @cash_register.destroy
          head :no_content
        end

        private

        def set_cash_register
          @cash_register = Current.account.cash_registers.find(params[:id])
        end

        def create_params
          params.permit(
            :register_date, :opening_balance, :operator_id
          )
        end

        def update_params
          params.permit(
            :cash_in, :cash_out, :supplements, :withdrawals, :closing_notes
          )
        end

        def serialize(register, detailed: false)
          data = {
            id:               register.id,
            register_date:    register.register_date,
            status:           register.status,
            operator_id:      register.operator_id,
            operator_name:    register.operator&.name,
            opening_balance:  register.opening_balance.to_f,
            cash_in:          register.cash_in.to_f,
            cash_out:         register.cash_out.to_f,
            supplements:      register.supplements.to_f,
            withdrawals:      register.withdrawals.to_f,
            calculated_balance: register.calculated_balance.to_f,
            closing_balance:  register.closing_balance&.to_f,
            declared_balance: register.declared_balance&.to_f,
            difference:       register.difference&.to_f,
            closing_notes:    register.closing_notes,
            opened_at:        register.opened_at,
            closed_at:        register.closed_at
          }

          if detailed
            data[:entries] = register.cash_register_entries.order(:created_at).map do |e|
              {
                id:             e.id,
                entry_type:     e.entry_type,
                amount:         e.amount.to_f,
                payment_method: e.payment_method,
                description:    e.description,
                created_at:     e.created_at
              }
            end
          end

          data
        end
      end
    end
  end
end
