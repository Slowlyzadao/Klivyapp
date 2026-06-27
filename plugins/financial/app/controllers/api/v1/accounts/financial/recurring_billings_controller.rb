module Api
  module V1
    module Accounts
      module Financial
        # CRUD de mensalidades fixas (Financial::RecurringBilling).
        # Decisão 2026-05-28: contrato recorrente real, separado do "tipo
        # Mensalidade" do modal Novo Lançamento (que era só uma label).
        class RecurringBillingsController < BaseController
          before_action :set_billing, only: %i[show update destroy pause resume cancel]
          before_action :authorize_write!, only: %i[create update destroy pause resume cancel]

          def index
            scope = ::Financial::RecurringBilling
                      .where(account_id: current_account.id, deleted_at: nil)
                      .order(created_at: :desc)

            scope = scope.where(patient_id: params[:patient_id]) if params[:patient_id].present?
            scope = scope.where(status: params[:status]) if params[:status].present?

            render json: { data: scope.map { |b| serialize(b) } }
          end

          def show
            render json: serialize(@billing)
          end

          def create
            idempotent! do
              billing = ::Financial::RecurringBilling.new(
                billing_params.merge(
                  account_id: current_account.id,
                  status: 'active',
                  created_by_id: current_user&.id,
                  next_generation_at: billing_params[:next_generation_at] || billing_params[:start_date]
                )
              )
              if billing.save
                render json: serialize(billing), status: :created
              else
                render json: { errors: billing.errors.full_messages }, status: :unprocessable_entity
              end
            end
          end

          def update
            idempotent_optional! do
              # Bloqueio: billing canceled/completed é imutável (proteção contábil).
              if %w[canceled completed].include?(@billing.status)
                return render(json: {
                  error: 'billing_immutable',
                  message: 'Mensalidade encerrada/cancelada não pode ser editada.'
                }, status: :unprocessable_entity)
              end

              if @billing.update(billing_params)
                render json: serialize(@billing)
              else
                render json: { errors: @billing.errors.full_messages }, status: :unprocessable_entity
              end
            end
          end

          # Soft delete — só permite se NUNCA gerou. Se já gerou pelo menos
          # uma cobrança, força usar #cancel (preserva histórico contábil).
          def destroy
            idempotent_optional! do
              if @billing.last_generated_at.present?
                return render(json: {
                  error: 'billing_in_use',
                  message: 'Mensalidade já gerou cobranças — use Cancelar (preserva histórico) em vez de Excluir.'
                }, status: :unprocessable_entity)
              end

              @billing.update!(
                deleted_at: Time.current,
                deleted_by_id: current_user&.id,
                status: 'canceled'
              )
              render json: { ok: true }
            end
          end

          # Pausa: para de gerar até retomar. Mantém next_generation_at.
          def pause
            idempotent_optional! do
              unless @billing.active?
                return render(json: { error: 'invalid_transition', message: "Só billings ativos podem ser pausados (status atual: #{@billing.status})." }, status: :unprocessable_entity)
              end
              @billing.update!(
                status: 'paused',
                paused_at: Time.current,
                paused_by_id: current_user&.id
              )
              render json: serialize(@billing)
            end
          end

          # Retoma: volta a gerar. Se next_generation_at ficou pra trás
          # enquanto estava pausado, **não dispara catch-up** — operador
          # decide o que fazer (gerar manual ou ajustar next_generation_at).
          def resume
            idempotent_optional! do
              unless @billing.paused?
                return render(json: { error: 'invalid_transition', message: "Só billings pausados podem ser retomados (status atual: #{@billing.status})." }, status: :unprocessable_entity)
              end
              @billing.update!(
                status: 'active',
                paused_at: nil,
                paused_by_id: nil
              )
              render json: serialize(@billing)
            end
          end

          # Cancelar: encerra definitivamente. Preserva o histórico (não soft-delete).
          # Pra excluir billing que nunca gerou nada → DELETE /destroy.
          def cancel
            idempotent_optional! do
              if %w[canceled completed].include?(@billing.status)
                return render(json: { error: 'already_closed', message: 'Mensalidade já encerrada.' }, status: :unprocessable_entity)
              end
              @billing.update!(
                status: 'canceled',
                canceled_at: Time.current,
                canceled_by_id: current_user&.id,
                cancel_reason: params[:reason]
              )
              render json: serialize(@billing)
            end
          end

          private

          def set_billing
            @billing = ::Financial::RecurringBilling
                         .where(account_id: current_account.id, deleted_at: nil)
                         .find(params[:id])
          end

          def authorize_write!
            require_role!('RECEPCAO', 'GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[RECEPCAO GERENTE ADMIN])
          end

          def billing_params
            params.require(:recurring_billing).permit(
              :patient_id, :professional_id, :financial_dre_category_id,
              :financial_bank_account_id, :payment_method_id,
              :description, :amount_cents, :frequency,
              :start_date, :end_date, :next_generation_at, :notes
            )
          end

          def serialize(b)
            pm = b.payment_method
            {
              id: b.id,
              patient_id: b.patient_id,
              professional_id: b.professional_id,
              financial_dre_category_id: b.financial_dre_category_id,
              financial_bank_account_id: b.financial_bank_account_id,
              payment_method_id: b.payment_method_id,
              payment_method: {
                id: pm&.id,
                kind: pm&.kind,
                name: pm&.name,
                provider: pm&.provider,
                provider_alias: pm&.provider_alias,
                settlement_mode: pm&.settlement_mode
              },
              description: b.description,
              amount_cents: b.amount_cents,
              frequency: b.frequency,
              start_date: b.start_date,
              end_date: b.end_date,
              next_generation_at: b.next_generation_at,
              last_generated_at: b.last_generated_at,
              status: b.status,
              notes: b.notes,
              paused_at: b.paused_at,
              canceled_at: b.canceled_at,
              cancel_reason: b.cancel_reason,
              created_at: b.created_at,
              updated_at: b.updated_at
            }
          end
        end
      end
    end
  end
end
