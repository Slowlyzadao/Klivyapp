module Api
  module V1
    module Accounts
      class AccountTransactionsController < Api::V1::Accounts::BaseController
        before_action :set_transaction, only: [:show, :update, :destroy, :receive]

        # GET /api/v1/accounts/:account_id/financial/transactions
        def index
          authorize AccountTransaction

          @transactions = filter_scope
            .order(due_date: :asc, created_at: :desc)
            .page(params[:page])
            .per(params[:per_page] || 25)

          # Calc global metrics for the current entry_type (e.g., 'entrada')
          base_metrics_scope = Current.account.account_transactions.kept
          base_metrics_scope = base_metrics_scope.where(entry_type: params[:entry_type]) if params[:entry_type].present?

          total_to_receive = base_metrics_scope.where(status: %w[pendente parcial vencido]).sum(:amount).to_f
          total_received   = base_metrics_scope.where(status: %w[recebido pago]).sum(:amount).to_f
          total_overdue    = base_metrics_scope.where(status: %w[pendente parcial vencido]).where('due_date < ?', Date.today).sum(:amount).to_f

          # Cálculos dinâmicos extras para a visão atual (filter_scope) e Payables
          total_recurring = filter_scope.where('recurring_expense_id IS NOT NULL OR origin = ?', 'recorrente').sum(:amount).to_f
          
          upcoming_scope = filter_scope.where(status: %w[pendente parcial]).where(due_date: Date.today..(Date.today + 3.days))
          total_upcoming = upcoming_scope.sum(:amount).to_f
          count_upcoming = upcoming_scope.count

          render json: {
            transactions: @transactions.map { |t| serialize(t) },
            meta: {
              total_count: filter_scope.count,
              page: params[:page]&.to_i || 1,
              total_amount: filter_scope.sum(:amount).to_f,
              total_to_receive: total_to_receive,
              total_received: total_received,
              total_overdue: total_overdue,
              total_recurring: total_recurring,
              total_upcoming: total_upcoming,
              count_upcoming: count_upcoming
            }
          }
        end

        # GET /api/v1/accounts/:account_id/financial/transactions/:id
        def show
          authorize @transaction
          render json: { transaction: serialize(@transaction) }
        end

        # POST /api/v1/accounts/:account_id/financial/transactions
        def create
          authorize AccountTransaction

          @transaction = Current.account.account_transactions.new(transaction_params)
          @transaction.registered_by = current_user

          if @transaction.competence_date.blank? && @transaction.due_date.present?
            @transaction.competence_date = @transaction.due_date.beginning_of_month
          end

          if @transaction.save
            render json: { transaction: serialize(@transaction) }, status: :created
          else
            render json: { errors: @transaction.errors.full_messages }, status: :unprocessable_entity
          end
        end

        # PATCH /api/v1/accounts/:account_id/financial/transactions/:id
        def update
          authorize @transaction

          if @transaction.update(transaction_params)
            render json: { transaction: serialize(@transaction) }
          else
            render json: { errors: @transaction.errors.full_messages }, status: :unprocessable_entity
          end
        end

        # DELETE /api/v1/accounts/:account_id/financial/transactions/:id
        def destroy
          authorize @transaction

          @transaction.soft_delete!
          render json: { message: 'Transação removida com sucesso' }
        end

        # POST /api/v1/accounts/:account_id/financial/transactions/:id/receive
        def receive
          authorize @transaction, :update?

          received_at    = params[:received_at].presence || Date.today.to_s
          payment_method = params[:payment_method].presence
          bank_account_id = params[:bank_account_id].presence

          attrs = {
            status:         'recebido',
            received_at:    received_at,
            payment_method: payment_method
          }
          attrs[:bank_account_id] = bank_account_id if bank_account_id

          @transaction.update!(attrs)

          if params[:proof_file].present?
            @transaction.payment_proof.attach(params[:proof_file])
          end

          render json: { transaction: serialize(@transaction) }
        rescue ActiveRecord::RecordInvalid => e
          render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
        end

        private

        def set_transaction
          @transaction = Current.account.account_transactions.kept.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: 'Transação não encontrada' }, status: :not_found
        end

        def filter_scope
          scope = Current.account.account_transactions.kept

          scope = scope.where(entry_type: params[:entry_type]) if params[:entry_type].present?
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.where(financial_category_id: params[:category_id]) if params[:category_id].present?
          scope = scope.where(bank_account_id: params[:bank_account_id]) if params[:bank_account_id].present?
          scope = scope.where(origin: params[:origin]) if params[:origin].present?

          # Filtro por data de criação
          if params[:start_date].present? && params[:end_date].present?
            scope = scope.where(created_at: Date.parse(params[:start_date]).beginning_of_day..Date.parse(params[:end_date]).end_of_day)
          end

          # Filtro por vencimento (usado em Receivables / Payables)
          if params[:due_start].present? && params[:due_end].present?
            scope = scope.where(due_date: Date.parse(params[:due_start])..Date.parse(params[:due_end]))
          end

          # Filtro de Situação (Status / Vencidos)
          if params[:status_filter].present?
            case params[:status_filter]
            when 'Vencidos'
              scope = scope.where(status: %w[pendente parcial]).where('due_date < ?', Date.today)
            when 'Pendente'
              scope = scope.where(status: 'pendente')
            when 'Recebidos'
              scope = scope.where(status: %w[recebido pago])
            end
          end

          # Filtro de Método de Pagamento
          if params[:payment_method_filter].present? && params[:payment_method_filter] != 'Todos'
            payment_methods_map = {
              'PIX' => 'pix',
              'Cartão de Crédito' => 'cartao_credito',
              'Cartão de Débito' => 'cartao_debito',
              'Dinheiro' => 'dinheiro',
              'Boleto' => 'boleto',
              'Transferência' => 'transferencia'
            }
            if payment_methods_map.key?(params[:payment_method_filter])
              scope = scope.where(payment_method: payment_methods_map[params[:payment_method_filter]])
            end
          end

          # Busca textual por descrição ou nome do paciente
          if params[:q].present?
            query = "%#{params[:q].strip}%"
            scope = scope.left_joins(:patient).where(
              'account_transactions.description ILIKE :q OR patients.name ILIKE :q', q: query
            )
          end

          scope
        end

        def transaction_params
          params.require(:account_transaction).permit(
            :entry_type, :amount, :original_amount, :discount_amount,
            :payment_method, :payment_source, :status, :financial_category_id, :bank_account_id,
            :professional_id, :patient_id, :competence_date, :due_date,
            :received_at, :paid_at, :description, :notes, :origin, :metadata
          )
        end

        def serialize(t)
          proof_url = if t.respond_to?(:payment_proof) && t.payment_proof.attached?
                        url_for(t.payment_proof)
                      elsif t.source_transaction_id.present?
                        original = Transaction.find_by(id: t.source_transaction_id)
                        original&.payment_proof&.attached? ? url_for(original.payment_proof) : nil
                      else
                        nil
                      end

          {
            id: t.id,
            entry_type: t.entry_type,
            amount: t.amount.to_f,
            original_amount: t.original_amount&.to_f,
            discount_amount: t.discount_amount&.to_f,
            payment_method: t.payment_method,
            payment_source: t.payment_source,
            status: t.status,
            origin: t.origin,
            competence_date: t.competence_date,
            due_date: t.due_date,
            received_at: t.received_at,
            paid_at: t.paid_at,
            description: t.description,
            notes: t.notes,
            financial_category_id: t.financial_category_id,
            bank_account_id: t.bank_account_id,
            professional_id: t.professional_id,
            patient_id: t.patient_id,
            patient_name: t.patient&.name,
            source_transaction_id: t.source_transaction_id,
            recurring: t.recurring_expense_id.present? || t.origin == 'recorrente',
            proof_url: proof_url,
            created_at: t.created_at
          }
        end
      end
    end
  end
end
