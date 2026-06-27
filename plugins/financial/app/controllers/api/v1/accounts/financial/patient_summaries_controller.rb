module Api
  module V1
    module Accounts
      module Financial
        # GET /api/v1/accounts/:account_id/financial/v2/patients/:patient_id/summary
        #
        # Compatibilidade: retorna o MESMO shape que `Patients::TransactionsController#financial_summary`
        # (legacy) entregava, mas calculado a partir das tabelas v2 (Financial::*).
        # Permite que a aba financeira do paciente migre sem mudar UX.
        #
        # Mapeamento canon → legacy field:
        #   total_approved     ← Σ Budget(status=aprovado|concluido).total_cents
        #   total_paid         ← Σ Installment(status=recebido OR parcial).received_amount_cents
        #   total_open         ← Σ Installment(status∈[pendente,parcial,vencido]).remaining (due_date >= hoje)
        #   total_overdue      ← Σ Installment(status∈[pendente,parcial,vencido]).remaining (due_date < hoje)
        #   credit_balance     ← saldo do PatientCredit (sum dos amount_cents — positivos e negativos)
        #   overall_status     ← inadimplente | em_aberto | em_dia
        #   next_due_date      ← min due_date de pendente/parcial/vencido no futuro
        #   next_due_amount    ← remaining da parcela acima
        class PatientSummariesController < BaseController
          # Não bloqueia via setup wizard (igual a transactions#financial_summary legacy).
          skip_before_action :ensure_setup_complete!
          # RBAC: leitura do financeiro do paciente exige `patients.view_financial`
          # (mesma key da aba no frontend). Fecha o fail-open anterior em que
          # qualquer usuário da conta lia o summary direto pela API. Bypass de
          # admin/super_admin embutido em `beclinic_can?`.
          before_action :ensure_view_patient_financial!

          def show
            patient_id = params[:patient_id]
            account_id = current_account.id

            installments = ::Financial::Installment.for_account(account_id).where(patient_id: patient_id)
            budgets = ::Financial::Budget.for_account(account_id).where(patient_id: patient_id)
            today = Date.current

            # Totais dos orçamentos aprovados (regime competência)
            total_approved_cents = budgets.where(status: %w[aprovado concluido]).sum(:total_cents)

            # Recebido (todas as parcelas, parcial inclusive)
            total_paid_cents = installments.where(status: %w[recebido parcial]).sum(:received_amount_cents)

            # Em aberto / Vencido — `open_scope` precisa incluir `vencido` além
            # de `pendente` e `parcial`. O cron `InstallmentStatusJob` (e o
            # importador F-10) grava `status='vencido'` quando due_date < hoje;
            # excluir esse status do scope deixava as parcelas atrasadas
            # invisíveis pros cards "Em Aberto" e "Devedor (Vencido)" da aba
            # financeira do paciente — bug reportado em 2026-05-11 na conta
            # Mamedes #31 (parcelas Clinicorp vencidas mostravam R$ 0,00).
            open_scope = installments.where(status: %w[pendente parcial vencido])

            # "Em Aberto" = ainda dentro do prazo (due_date >= hoje). Aqui só
            # entram pendente/parcial; vencido por definição tem due_date < hoje.
            total_open_cents = open_scope.where('due_date >= ?', today).sum('amount_cents - received_amount_cents')

            # "Devedor (Vencido)" = passou da data. Inclui status=vencido
            # explícito + pendente/parcial cujo due_date já passou (mas o cron
            # ainda não rodou pra promover pra vencido).
            total_overdue_cents = open_scope.where('due_date < ?', today).sum('amount_cents - received_amount_cents')

            # Crédito do paciente (sum de movements no ledger; positivo = a favor)
            credit_balance_cents = ::Financial::PatientCredit.for_account(account_id)
                                                              .where(patient_id: patient_id)
                                                              .sum(:amount_cents)

            # Próxima parcela a vencer
            next_due = open_scope.where('due_date >= ?', today).order(:due_date).first

            overall_status = if total_overdue_cents.to_i.positive?
                               'inadimplente'
                             elsif total_open_cents.to_i.positive?
                               'em_aberto'
                             else
                               'em_dia'
                             end

            render json: {
              # Campos legacy em DECIMAL (BRL) para parity com TransactionsController#financial_summary
              total_approved: cents_to_brl(total_approved_cents),
              total_paid: cents_to_brl(total_paid_cents),
              total_open: cents_to_brl(total_open_cents),
              total_overdue: cents_to_brl(total_overdue_cents),
              credit_balance: cents_to_brl(credit_balance_cents),
              overall_status: overall_status,
              next_due_date: next_due&.due_date,
              next_due_amount: next_due ? cents_to_brl(next_due.remaining_cents) : nil,
              # Campos v2 (em centavos) — preferir esses em código novo
              total_approved_cents: total_approved_cents.to_i,
              total_paid_cents: total_paid_cents.to_i,
              total_open_cents: total_open_cents.to_i,
              total_overdue_cents: total_overdue_cents.to_i,
              credit_balance_cents: credit_balance_cents.to_i,
              next_due_amount_cents: next_due&.remaining_cents
            }
          end

          private

          def cents_to_brl(cents)
            BigDecimal(cents.to_i) / 100
          end
        end
      end
    end
  end
end
