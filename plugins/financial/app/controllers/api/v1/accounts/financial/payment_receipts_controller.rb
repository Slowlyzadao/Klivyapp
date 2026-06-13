module Api
  module V1
    module Accounts
      module Financial
        class PaymentReceiptsController < BaseController
          before_action :set_receipt, only: %i[show refund]

          def index
            scope = ::Financial::PaymentReceipt.for_account(current_account.id)
            scope = scope.where(patient_id: params[:patient_id]) if params[:patient_id].present?
            scope = scope.where('received_at >= ?', params[:from]) if params[:from].present?
            scope = scope.where('received_at <= ?', params[:to]) if params[:to].present?
            scope = scope.order(received_at: :desc, id: :desc)
            render json: { data: scope.limit(100).map { |r| serialize(r) } }
          end

          def show
            render json: serialize(@receipt, include_items: true)
          end

          # POST /financial/v2/payment_receipts  ← BAIXA DE PAGAMENTO (BUG-01 fix)
          # Body:
          #   bank_account_id: 1
          #   payment_method: 'pix'
          #   received_at: '2026-05-07'
          #   interest_cents: 0
          #   fine_cents: 0
          #   discount_cents: 0
          #   apply_patient_credit_cents: 0
          #   keep_installment_open: true
          #   notes: '...'
          #   installment_amounts: [{ installment_id: 1, amount_cents: 27600 }, ...]
          def create
            require_role!('RECEPCAO', 'GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[RECEPCAO GERENTE ADMIN])

            idempotent! do
              bank = ::Financial::BankAccount.for_account(current_account.id).find(params[:bank_account_id])
              rows = Array(params[:installment_amounts]).map do |row|
                { installment_id: row[:installment_id].to_i, amount_cents: row[:amount_cents].to_i }
              end

              # Refactor 2026-05-24: aceita `payment_method_id` (novo, opcional)
              # — referência ao PaymentMethod configurado em Settings. Quando vier,
              # deriva `payment_method` (kind canon) automaticamente. Compat: se
              # vier só `payment_method` (legacy), continua aceitando.
              pm_record = nil
              if params[:payment_method_id].present?
                pm_record = ::Financial::PaymentMethod
                              .for_account(current_account.id).alive
                              .find_by(id: params[:payment_method_id])
                unless pm_record
                  return render(json: { errors: ['Forma de pagamento não encontrada.'] }, status: :unprocessable_entity)
                end
              end
              kind = pm_record&.kind || params[:payment_method]

              # Modificadores: aceita tipo+value (padrão de mercado) E cents
              # legacy. Backend é source of truth — recalcula cents do tipo+value
              # quando vier (ignora o `cents` enviado pelo frontend pra blindar
               # contra adulteração). Fallback pra cents legacy quando tipo
              # ausente, preservando compat com clients antigos.
              gross_cents_for_calc = rows.sum { |r| r[:amount_cents].to_i }
              modifiers = build_modifier_amounts(gross_cents_for_calc)

              result = ::Financial::ReceivePayment.call(
                account: current_account,
                actor: current_user,
                bank_account: bank,
                installment_amounts: rows,
                payment_method: kind,
                payment_method_record: pm_record,
                received_at: params[:received_at],
                interest_cents: modifiers[:interest_cents],
                interest_type:  modifiers[:interest_type],
                interest_value: modifiers[:interest_value],
                fine_cents:     modifiers[:fine_cents],
                fine_type:      modifiers[:fine_type],
                fine_value:     modifiers[:fine_value],
                discount_cents: modifiers[:discount_cents],
                discount_type:  modifiers[:discount_type],
                discount_value: modifiers[:discount_value],
                apply_patient_credit_cents: params[:apply_patient_credit_cents].to_i,
                notes: params[:notes],
                keep_installment_open: params[:keep_installment_open] != false
              )

              if result.success?
                render json: serialize(result[:receipt], include_items: true).merge(
                  new_installments: result[:new_installments]&.map { |i| { id: i.id, amount_cents: i.amount_cents, due_date: i.due_date } } || []
                ), status: :created
              else
                render json: { errors: result.errors }, status: :unprocessable_entity
              end
            end
          end

          # POST /financial/v2/payment_receipts/:id/refund — estorno completo.
          def refund
            require_role!('GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[GERENTE ADMIN])

            idempotent! do
              result = ::Financial::RefundPayment.call(
                receipt: @receipt,
                actor: current_user,
                reason: params[:reason],
                refunded_at: params[:refunded_at],
                refund_via_gateway: params[:refund_via_gateway] != false
              )
              if result.success?
                render json: serialize(@receipt.reload, include_items: true), status: :ok
              else
                render json: { errors: result.errors }, status: :unprocessable_entity
              end
            end
          end

          private

          # Resolve tipo+value pra cada modificador (juros/multa/desconto) e
          # calcula os cents finais. Backend é source of truth — operador pode
          # enviar 10% mas se o gross mudar, recalculamos. Frontend manda
          # `interest_type/value` (novo) OU `interest_cents` (legacy).
          def build_modifier_amounts(gross_cents)
            %w[interest fine discount].each_with_object({}) do |kind, h|
              type_param  = params["#{kind}_type"].to_s.presence
              value_param = params["#{kind}_value"]

              if type_param == 'percent'
                pct = value_param.to_f
                cents = (gross_cents * pct / 100.0).round
                h["#{kind}_type".to_sym]  = 'percent'
                h["#{kind}_value".to_sym] = pct
                h["#{kind}_cents".to_sym] = cents
              elsif type_param == 'fixed'
                cents = if value_param.present?
                  # Recebido como decimal R$ (ex: "12.50") OU já em centavos legacy
                  v = value_param.to_f
                  v < 1000 ? (v * 100).round : params["#{kind}_cents"].to_i
                else
                  params["#{kind}_cents"].to_i
                end
                h["#{kind}_type".to_sym]  = 'fixed'
                h["#{kind}_value".to_sym] = (cents / 100.0).round(2)
                h["#{kind}_cents".to_sym] = cents
              else
                # Compat: só cents (cliente legacy). Tipo implícito = fixed.
                cents = params["#{kind}_cents"].to_i
                h["#{kind}_type".to_sym]  = 'fixed'
                h["#{kind}_value".to_sym] = (cents / 100.0).round(2)
                h["#{kind}_cents".to_sym] = cents
              end
            end
          end

          def set_receipt
            @receipt = ::Financial::PaymentReceipt.for_account(current_account.id).find(params[:id])
          end

          def serialize(r, include_items: false)
            data = {
              id: r.id,
              receipt_number: r.receipt_number,
              patient_id: r.patient_id,
              bank_account_id: r.financial_bank_account_id,
              entry_id: r.financial_entry_id,
              payment_method: r.payment_method,
              gross_amount_cents: r.gross_amount_cents,
              interest_amount_cents: r.interest_amount_cents,
              interest_type: r.interest_type,
              interest_value: r.interest_value.to_f,
              fine_amount_cents: r.fine_amount_cents,
              fine_type: r.fine_type,
              fine_value: r.fine_value.to_f,
              discount_amount_cents: r.discount_amount_cents,
              discount_type: r.discount_type,
              discount_value: r.discount_value.to_f,
              credit_applied_cents: r.credit_applied_cents,
              net_amount_cents: r.net_amount_cents,
              received_at: r.received_at,
              notes: r.notes,
              created_at: r.created_at
            }
            data[:items] = r.items.map { |it|
              { id: it.id, installment_id: it.financial_installment_id, amount_cents: it.amount_cents }
            } if include_items
            data
          end
        end
      end
    end
  end
end
