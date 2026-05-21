module Api
  module V1
    module Accounts
      module Financial
        # GET /api/v1/accounts/:account_id/financial/v2/patients/:patient_id/timeline
        #
        # Espelha o shape que `Patients::TransactionsController#financial_timeline`
        # entregava (já consumido por `useFinancialTimeline.js` na aba do paciente),
        # mas alimentado pelas tabelas v2 (Financial::Budget + Financial::Installment).
        #
        # entries[] mistura Budget (linha-pai) + Installment (linha-filha agrupada).
        # Cada entry tem `source_type` apontando o modelo (Financial::Budget ou
        # Financial::Installment avulsa quando não há orçamento associado).
        class PatientTimelinesController < BaseController
          skip_before_action :ensure_setup_complete!

          def show
            patient_id = params[:patient_id].to_i
            account_id = current_account.id
            today = Date.current

            budgets = ::Financial::Budget.for_account(account_id).where(patient_id: patient_id)
                                          .includes(:installments)
                                          .order(created_at: :desc)

            entries = budgets.map { |b| build_budget_entry(b, today) }

            installments = ::Financial::Installment.for_account(account_id).where(patient_id: patient_id)
            credit_balance_cents = ::Financial::PatientCredit.for_account(account_id)
                                                              .where(patient_id: patient_id).sum(:amount_cents)

            summary = build_summary(budgets, installments, credit_balance_cents, today)

            render json: {
              meta: {
                request_id: request.request_id,
                generated_at: Time.current.iso8601,
                schema_version: 2
              },
              entries: entries,
              summary: summary,
              credit: {
                balance: cents_to_brl(credit_balance_cents),
                balance_cents: credit_balance_cents.to_i,
                source: 'financial_patient_credits'
              }
            }
          end

          private

          def build_budget_entry(budget, today)
            # Ordena por `due_date` (não `number`) porque buckets "Avulsos" do
            # importador Clinicorp recebem `number` sequencial na ordem que as
            # linhas vêm no PaymentItem.xlsx (aleatória / por id de export), o
            # que não bate com a ordem cronológica de vencimento. Ver
            # `Migration::ClinicorpFinancialImporter#process_items!`. `:number`
            # fica como tiebreaker pra parcelas com `due_date` igual no mesmo
            # bucket (caso comum em Avulsos quando várias vendas vencem no
            # mesmo dia). Bug reportado 2026-05-12 na Mamedes #31.
            installments = budget.installments.order(:due_date, :number)
            paid_cents = installments.sum(:received_amount_cents)
            total_cents = budget.total_cents.to_i
            # `open_scope` inclui `vencido` além de `pendente`/`parcial` — o cron
            # `InstallmentStatusJob` e o importador F-10 gravam parcelas como
            # `status='vencido'` quando due_date < hoje, então excluir esse
            # status fazia o badge "Devedor (Vencido)" e o card "Em Aberto" da
            # aba financeira do paciente ficarem em R$ 0,00 mesmo com 7
            # parcelas atrasadas. Bug reportado 2026-05-11 na Mamedes #31.
            open_scope = installments.where(status: %w[pendente parcial vencido])
            open_cents = open_scope.where('due_date >= ?', today)
                                   .sum('amount_cents - received_amount_cents')
            overdue_cents = open_scope.where('due_date < ?', today)
                                      .sum('amount_cents - received_amount_cents')

            # Counts de parcelas — `InstallmentProgress.vue` usa esses para
            # renderizar "X/Y pagas · N vencida(s) · M cancelada(s)" no UI
            # (não os valores em reais). `canceled_count` é separado pra
            # não inflar `open_count` (bug 2026-05-12: parcelas canceladas
            # apareciam como "em aberto" pq eram só `total - paid - overdue`).
            paid_count = installments.where(status: 'recebido').count
            total_count = installments.count
            overdue_count = open_scope.where('due_date < ?', today).count
            canceled_count = installments.where(status: 'cancelado').count
            open_count = total_count - paid_count - overdue_count - canceled_count

            # Mantém visual legacy: exibe o número do orçamento original quando
            # existe (migração preservou em `metadata.legacy_id`). Para budgets
            # criados originalmente em v2, fallback para o id próprio.
            display_id = budget.metadata&.dig('legacy_id') || budget.id

            {
              id: budget.id,
              display_id: display_id,
              source_type: 'Financial::Budget',
              source_id: budget.id,
              # recurrence_type compat: orçamento avulso ou plano de tratamento
              recurrence_type: derive_recurrence_type(budget),
              origin: {
                kind: budget.treatment_plan_id.present? ? 'treatment_plan' : 'estimate',
                label: derive_origin_label(budget),
                link: budget.treatment_plan_id
              },
              date: budget.approved_at&.to_date || budget.created_at.to_date,
              description: budget.notes.presence || derive_description(budget),
              total: cents_to_brl(total_cents),
              paid: cents_to_brl(paid_cents),
              open: cents_to_brl(open_cents),
              overdue: cents_to_brl(overdue_cents),
              total_cents: total_cents,
              paid_cents: paid_cents.to_i,
              open_cents: open_cents.to_i,
              overdue_cents: overdue_cents.to_i,
              # progress: counts de parcelas (não valores) — espelha o que o
              # legacy retornava e o que `InstallmentProgress.vue` espera para
              # renderizar "7/14 pagas". Valores em reais ficam em `total/paid/open/overdue`.
              progress: {
                paid: paid_count, open: open_count,
                overdue: overdue_count, canceled: canceled_count,
                total: total_count,
                # Valores em centavos pra UI calcular % real da barra. Sem
                # esses campos, a barra usaria só `paid / total` (contagem)
                # e ignoraria baixa parcial — orçamento R$ 285 com R$ 200
                # recebido mostraria 0% em vez de ~70%.
                paid_amount_cents: paid_cents.to_i,
                total_amount_cents: total_cents.to_i
              },
              status: derive_overall_status(budget, installments, today),
              installments: installments.map { |i| serialize_installment(i, today) },
              actions_available: derive_actions(budget)
            }
          end

          def serialize_installment(inst, today)
            # Mapeia status v2 → status do frontend (TX_STATUS_CONFIG em
            # plugins/patients/frontend/constants/financial.js):
            #   recebido    → pago
            #   estornado   → reembolsado
            #   parcial     → parcial (preservado — frontend exibe saldo +
            #                 valor original riscado, igual A Receber faz)
            #   renegociado → cancelado (não há equivalente direto)
            #   pendente/vencido/cancelado → idem
            effective_status = case inst.status
                               when 'recebido'    then 'pago'
                               when 'estornado'   then 'reembolsado'
                               when 'renegociado' then 'cancelado'
                               else inst.status
                               end
            # Override pra vencido se pendente/parcial sem pagamento e venceu.
            # `parcial` vencida ainda exibe label "parcial" mas com cor de
            # alerta — recepção precisa ver que está em atraso.
            if %w[pendente parcial].include?(effective_status) && inst.due_date && inst.due_date < today
              effective_status = 'vencido' if effective_status == 'pendente'
            end

            # Total já estornado desta parcela (estorno parcial deixa a parcela
            # em status='parcial' com received_amount_cents reduzido — o frontend
            # precisa saber explicitamente quanto foi devolvido pra mostrar
            # "Recebido R$ X / Estornado R$ Y" no card).
            refunded_cents = compute_refunded_cents(inst)

            {
              id: inst.id,
              number: inst.number,
              total: inst.total_in_series,
              amount: cents_to_brl(inst.amount_cents),
              amount_cents: inst.amount_cents.to_i,
              received_amount: cents_to_brl(inst.received_amount_cents),
              received_amount_cents: inst.received_amount_cents.to_i,
              remaining: cents_to_brl(inst.remaining_cents),
              remaining_cents: inst.remaining_cents.to_i,
              refunded_cents: refunded_cents,
              refunded: cents_to_brl(refunded_cents),
              partially_refunded: refunded_cents.positive? && inst.status != 'estornado',
              status: effective_status,
              due_date: inst.due_date,
              paid_at: inst.received_at,
              payment_method: inst.payment_method,
              # URL signed (15min TTL) do comprovante anexado quando há blob
              # vinculado à parcela. Nil quando não tem anexo — frontend usa
              # pra decidir se renderiza botão "Ver comprovante" vs "Anexar".
              payment_proof_url: inst.payment_proof.attached? ? signed_payment_proof_url(inst) : nil,
              gateway: inst.gateway,
              payment_link: inst.payment_link
            }
          end

          # Soma centavos estornados (Entries de saída + crédito gerado por estorno)
          # vinculados aos recibos que essa parcela teve. Considera múltiplos
          # estornos parciais cumulativos no mesmo recibo.
          def compute_refunded_cents(inst)
            receipt_ids = inst.payment_receipt_items.pluck(:financial_payment_receipt_id).uniq
            return 0 if receipt_ids.empty?

            from_entries = ::Financial::Entry
                           .where(account_id: inst.account_id, source_type: 'Financial::PaymentReceipt',
                                  source_id: receipt_ids, kind: 'estorno_receita')
                           .sum(:amount_cents)
            from_credits = ::Financial::PatientCredit
                           .where(account_id: inst.account_id, origin: 'estorno',
                                  origin_type: 'Financial::PaymentReceipt', origin_id: receipt_ids)
                           .where('amount_cents > 0')
                           .sum(:amount_cents)
            (from_entries.to_i + from_credits.to_i)
          end

          def build_summary(budgets, installments, credit_balance_cents, today)
            total_approved_cents = budgets.where(status: %w[aprovado concluido]).sum(:total_cents)
            total_paid_cents = installments.where(status: %w[recebido parcial]).sum(:received_amount_cents)
            open_scope = installments.where(status: %w[pendente parcial])
            total_open_cents = open_scope.where('due_date >= ?', today).sum('amount_cents - received_amount_cents')
            total_overdue_cents = open_scope.where('due_date < ?', today).sum('amount_cents - received_amount_cents')
            next_due = open_scope.where('due_date >= ?', today).order(:due_date).first

            overall_status = if total_overdue_cents.to_i.positive?
                               'inadimplente'
                             elsif total_open_cents.to_i.positive?
                               'em_aberto'
                             else
                               'em_dia'
                             end

            {
              total_approved: cents_to_brl(total_approved_cents),
              total_paid: cents_to_brl(total_paid_cents),
              total_open: cents_to_brl(total_open_cents),
              total_overdue: cents_to_brl(total_overdue_cents),
              credit_balance: cents_to_brl(credit_balance_cents),
              overall_status: overall_status,
              next_due_date: next_due&.due_date,
              next_due_amount: next_due ? cents_to_brl(next_due.remaining_cents) : nil
            }
          end

          def derive_recurrence_type(budget)
            # Orçamento gerado da aprovação de plano de tratamento — prioriza
            # essa info sobre n° de parcelas, pra UI mostrar badge "Plano"
            # mesmo em planos de 1 parcela (pagamento à vista).
            return 'plano_tratamento' if budget.treatment_plan_id.present?
            return 'mensalidade' if budget.origin == 'mensalidade'
            return 'avulso' if budget.installments_count <= 1

            'parcelamento'
          end

          def derive_origin_label(budget)
            return "Plano de Tratamento ##{budget.treatment_plan_id}" if budget.treatment_plan_id.present?

            # Preserva o número visível do orçamento original do legacy quando a
            # migração registrou em `metadata.legacy_id`. Sem isso, números mudam
            # após a migração (ex: #31 → #38) e o usuário perde rastreabilidade.
            display_id = budget.metadata&.dig('legacy_id') || budget.id
            return "Mensalidade ##{display_id}" if budget.origin == 'mensalidade'

            "Orçamento ##{display_id}"
          end

          def derive_description(budget)
            first_item = budget.items.first
            return first_item.description if first_item
            return "Orçamento ##{budget.id}"
          end

          def derive_overall_status(budget, installments, today)
            return 'cancelado' if budget.status == 'cancelado'
            return 'rascunho' if budget.status == 'rascunho'
            return 'enviado' if budget.status == 'enviado'

            # Todas as parcelas estornadas → orçamento estornado (frontend
            # mapeia pra `reembolsado` no TX_STATUS_CONFIG). Antes dessa
            # checagem o orçamento ficaria como `pendente` mesmo sem ter
            # parcela ativa nenhuma — "EM ABERTO" enganoso.
            active_installments = installments.reject { |i| i.status == 'cancelado' }
            if active_installments.any? && active_installments.all? { |i| i.status == 'estornado' }
              return 'reembolsado'
            end

            has_overdue = installments.any? { |i| %w[pendente parcial].include?(i.status) && i.due_date && i.due_date < today }
            return 'vencido' if has_overdue

            all_paid = installments.any? && installments.all? { |i| i.status == 'recebido' }
            return 'pago' if all_paid

            any_paid = installments.any? { |i| %w[recebido parcial].include?(i.status) }
            return 'parcial' if any_paid

            'pendente'
          end

          def derive_actions(budget)
            actions = []
            actions << 'approve_estimate' if budget.status == 'rascunho' || budget.status == 'enviado'
            actions << 'cancel_estimate' if %w[rascunho enviado aprovado].include?(budget.status)
            actions
          end

          def cents_to_brl(cents)
            BigDecimal(cents.to_i) / 100
          end

          # URL signed (15min TTL) do comprovante de pagamento da parcela.
          # Mesma helper usada no `installments_controller#proof_url` —
          # garante visualização sem expor signed_id no payload da timeline.
          def signed_payment_proof_url(installment)
            Rails.application.routes.url_helpers.rails_blob_url(
              installment.payment_proof,
              host: ENV.fetch('FRONTEND_URL', 'http://localhost:3000'),
              expires_in: 15.minutes
            )
          end
        end
      end
    end
  end
end
