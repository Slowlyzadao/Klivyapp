module Api
  module V1
    module Accounts
      module Patients
        class TransactionsController < Api::V1::Accounts::BaseController
          before_action :set_patient
          before_action :ensure_view_patient_financial!,
                        only: [:index, :show, :financial_summary, :proof_url]
          before_action :ensure_manage_patient_financial!,
                        only: [:create, :destroy, :pay, :refund, :charge_whatsapp, :upload_proof]
          before_action :set_transaction, only: [:show, :destroy, :pay, :refund, :charge_whatsapp, :upload_proof, :proof_url]

          # GET /api/v1/accounts/:account_id/patients/:patient_id/transactions
          def index
            # Transações do prontuário (parcelas de orçamentos)
            patient_txs = @patient.transactions.active
                                  .order(due_date: :asc)

            # Transações manuais do financeiro geral vinculadas a este paciente
            # Excluímos as que têm source_transaction_id pois são espelhos já presentes acima
            manual_account_txs = Current.account.account_transactions.kept
                                         .where(patient_id: @patient.id, origin: 'manual')
                                         .where(source_transaction_id: nil)
                                         .order(due_date: :asc)

            @transactions = patient_txs.page(params[:page]).per(params[:per_page] || 50)

            # Serialização combinada (patient transactions + manual account transactions)
            patient_json = @transactions.map { |t| serialize_patient_tx(t) }
            manual_json  = manual_account_txs.map { |t| serialize_account_tx(t) }

            render json: {
              transactions: (patient_json + manual_json).sort_by { |t| t[:due_date].to_s },
              meta: {
                total_count: @transactions.total_count + manual_account_txs.count,
                page: params[:page] || 1,
                per_page: params[:per_page] || 50
              }
            }
          end

          # GET /api/v1/accounts/:account_id/patients/:patient_id/financial_summary
          def financial_summary
            transactions = @patient.transactions.active

            total_approved = @patient.financial_estimates
                                     .active
                                     .where(status: 'aprovado')
                                     .sum(:total)

            total_paid    = transactions.where(status: 'pago').sum(:amount)
            total_overdue = transactions.where(status: %w[vencido pendente])
                                        .where('due_date < ?', Date.today)
                                        .sum(:amount)
            total_open    = transactions.where(status: 'pendente')
                                        .where('due_date >= ?', Date.today)
                                        .sum(:amount)

            credit_balance = 0.0  # Futuro: refunds negativos

            next_due = transactions.where(status: 'pendente')
                                   .where('due_date >= ?', Date.today)
                                   .order(:due_date)
                                   .first

            overall_status = if total_overdue > 0
                               'inadimplente'
                             elsif total_open > 0
                               'em_aberto'
                             else
                               'em_dia'
                             end

            render json: {
              total_approved: total_approved.to_f,
              total_paid: total_paid.to_f,
              total_overdue: total_overdue.to_f,
              total_open: total_open.to_f,
              credit_balance: credit_balance,
              overall_status: overall_status,
              next_due_date: next_due&.due_date,
              next_due_amount: next_due&.amount&.to_f
            }
          end

          # GET /api/v1/accounts/:account_id/patients/:patient_id/transactions/:id
          def show
            render :show
          end

          # POST /api/v1/accounts/:account_id/patients/:patient_id/transactions
          def create
            @transaction = Transaction.new(transaction_params)
            @transaction.account = Current.account
            @transaction.patient = @patient
            @transaction.registered_by = current_user
            @transaction.status = 'pendente'

            if @transaction.save
              PatientAuditLog.log!(
                account: Current.account, patient: @patient, action: 'create',
                actor: current_user, resource: @transaction, ip_address: request.remote_ip
              )
              render :show, status: :created
            else
              render json: { errors: @transaction.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # PATCH /api/v1/accounts/:account_id/patients/:patient_id/transactions/:id/pay
          # BAIXA DUPLA: marca como pago + injeta no CashEntry
          def pay
            result = ::Patients::InstallmentPayService.call(
              transaction: @transaction,
              actor: current_user,
              payment_method: params[:payment_method],
              paid_at: params[:paid_at].present? ? Date.parse(params[:paid_at]) : Date.today,
              bank_account_id: params[:bank_account_id].present? ? params[:bank_account_id].to_i : nil
            )

            if result.success?
              @transaction = result.transaction
              PatientAuditLog.log!(
                account: Current.account, patient: @patient, action: 'pay',
                actor: current_user, resource: @transaction, ip_address: request.remote_ip
              )
              render :show
            else
              render json: { error: result.error }, status: :unprocessable_entity
            end
          end

          def refund
            ActiveRecord::Base.transaction do
              # Cria uma transação negativa de reembolso
              refund_transaction = Transaction.create!(
                account_id: @transaction.account_id,
                patient_id: @transaction.patient_id,
                financial_estimate_id: @transaction.financial_estimate_id,
                registered_by_id: current_user.id,
                transaction_type: 'reembolso',
                amount: params[:amount].present? ? params[:amount].to_f : @transaction.amount,
                payment_method: params[:payment_method] || @transaction.payment_method,
                status: 'pago',
                paid_at: Date.today,
                description: "Reembolso — #{@transaction.description}",
                notes: params[:notes]
              )

              # Marca a original como reembolsada
              @transaction.update!(status: 'reembolsado')

              # Sync: espelha o reembolso no financeiro central
              Patients::TransactionSyncService.on_refunded(@transaction, refund_transaction)

              render json: {
                message: 'Reembolso registrado com sucesso',
                refund_transaction_id: refund_transaction.id,
                original_transaction_id: @transaction.id
              }, status: :created
            end
          rescue StandardError => e
            render json: { error: e.message }, status: :unprocessable_entity
          end

          # POST /api/v1/accounts/:account_id/patients/:patient_id/transactions/:id/charge_whatsapp
          def charge_whatsapp
            patient = @transaction.patient
            phone = patient.phone.presence || patient.contacts&.first&.dig('value')

            return render json: { error: 'Paciente sem telefone cadastrado' }, status: :unprocessable_entity unless phone

            amount_formatted = "R$ #{'%.2f' % @transaction.amount}".tr('.', ',')
            due_formatted = @transaction.due_date&.strftime('%d/%m/%Y')

            message = "Olá, #{patient.name}! 👋\n\n" \
                      "Identificamos um lançamento financeiro em aberto:\n" \
                      "💰 Valor: #{amount_formatted}\n" \
                      "📅 Vencimento: #{due_formatted}\n\n" \
                      'Entre em contato conosco para regularizar. ' \
                      'Aceitamos PIX, cartão e dinheiro. 😊'

            render json: {
              message: 'Cobrança preparada para envio',
              phone: phone,
              whatsapp_message: message,
              note: 'Use o gateway WhatsApp para enviar esta mensagem'
            }
          end

          # DELETE /api/v1/accounts/:account_id/patients/:patient_id/transactions/:id
          def destroy
            return render json: { error: 'Transações pagas não podem ser removidas' }, status: :forbidden if @transaction.status_pago?

            @transaction.soft_delete!
            PatientAuditLog.log!(
              account: Current.account, patient: @patient, action: 'delete',
              actor: current_user, resource: @transaction, ip_address: request.remote_ip
            )
            render json: { message: 'Transação removida com sucesso' }
          end

          # POST /api/v1/accounts/:account_id/patients/:patient_id/transactions/:id/upload_proof
          def upload_proof
            return render json: { error: 'Arquivo não enviado' }, status: :bad_request unless params[:file].present?

            @transaction.payment_proof.attach(params[:file])

            if @transaction.payment_proof.attached?
              url = rails_blob_url(@transaction.payment_proof, only_path: true)
              render json: { url: url, filename: @transaction.payment_proof.filename.to_s }
            else
              render json: { error: 'Erro ao anexar arquivo' }, status: :unprocessable_entity
            end
          end

          # GET /api/v1/accounts/:account_id/patients/:patient_id/transactions/:id/proof_url
          def proof_url
            if @transaction.payment_proof.attached?
              render json: { url: rails_blob_url(@transaction.payment_proof, only_path: true), filename: @transaction.payment_proof.filename.to_s }
            else
              render json: { url: nil }
            end
          end

          private

          def ensure_view_patient_financial!
            return if Current.user.beclinic_can?(Current.account, :patients, :view_financial)

            render json: { error: 'Você não tem permissão para visualizar o financeiro do paciente' },
                   status: :forbidden
          end

          def ensure_manage_patient_financial!
            return if Current.user.beclinic_can?(Current.account, :patients, :manage_financial)

            render json: { error: 'Você não tem permissão para gerenciar o financeiro do paciente' },
                   status: :forbidden
          end

          def set_patient
            @patient = Current.account.patients.find(params[:patient_id])
          rescue ActiveRecord::RecordNotFound
            render json: { error: 'Paciente não encontrado' }, status: :not_found
          end

          def set_transaction
            @transaction = @patient.transactions.active.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render json: { error: 'Transação não encontrada' }, status: :not_found
          end

          def transaction_params
            params.require(:transaction).permit(
              :transaction_type,
              :amount,
              :payment_method,
              :due_date,
              :description,
              :notes,
              :financial_estimate_id,
              :installment_number,
              :total_installments
            )
          end

          def serialize_patient_tx(t)
            {
              id: t.id,
              account_id: t.account_id,
              patient_id: t.patient_id,
              financial_estimate_id: t.financial_estimate_id,
              transaction_type: t.transaction_type,
              amount: t.amount.to_f,
              payment_method: t.payment_method,
              status: t.status,
              due_date: t.due_date,
              paid_at: t.paid_at,
              description: t.description,
              notes: t.notes,
              installment_number: t.installment_number,
              total_installments: t.total_installments,
              cash_entry_id: t.cash_entry_id,
              is_overdue: t.overdue?,
              is_parcelado: t.parcelado?,
              is_manual: false,
              created_at: t.created_at,
              updated_at: t.updated_at,
              registered_by: t.registered_by ? { id: t.registered_by.id, name: t.registered_by.name } : nil,
              payment_proof_url: t.payment_proof.attached? ? rails_blob_path(t.payment_proof, only_path: true) : nil
            }
          end

          def serialize_account_tx(t)
            # Converte entry_type + status do AccountTransaction para o formato do Transaction
            mapped_status = case t.status
                            when 'recebido', 'pago' then 'pago'
                            when 'cancelado' then 'cancelado'
                            else 'pendente'
                            end

            mapped_type = t.entry_type == 'entrada' ? 'receita' : 'despesa'

            {
              id: "atx_#{t.id}",   # prefixo para não colidir com IDs de Transaction
              account_id: t.account_id,
              patient_id: t.patient_id,
              financial_estimate_id: nil,
              transaction_type: mapped_type,
              amount: t.amount.to_f,
              payment_method: t.payment_method,
              status: mapped_status,
              due_date: t.due_date,
              paid_at: t.paid_at || t.received_at,
              description: t.description,
              notes: t.notes,
              installment_number: nil,
              total_installments: nil,
              cash_entry_id: nil,
              is_overdue: mapped_status == 'pendente' && t.due_date.present? && t.due_date < Date.today,
              is_parcelado: false,
              is_manual: true,
              created_at: t.created_at,
              updated_at: t.updated_at,
              registered_by: t.registered_by ? { id: t.registered_by.id, name: t.registered_by.name } : nil,
              payment_proof_url: nil
            }
          end
        end
      end
    end
  end
end
