module Api
  module V1
    module Accounts
      module Financial
        # Endpoints de leitura — DRE, Fluxo de Caixa, Dashboard.
        # Acesso: GERENTE, ADMIN, AUDITOR.
        class ReportsController < BaseController
          # GET /financial/v2/reports/dre?from=2026-05-01&to=2026-05-31
          def dre
            require_role!('GERENTE', 'ADMIN', 'AUDITOR') and return unless user_has_any_role?(%w[GERENTE ADMIN AUDITOR])

            from = parse_date(params[:from], :start)
            to   = parse_date(params[:to],   :end)
            data = ::Financial::Reports::DreReport.call(account: current_account, from: from, to: to)
            render json: data
          end

          # GET /financial/v2/reports/dre/category/:category_id?from=...&to=...
          def dre_category
            require_role!('GERENTE', 'ADMIN', 'AUDITOR') and return unless user_has_any_role?(%w[GERENTE ADMIN AUDITOR])

            from = parse_date(params[:from], :start)
            to   = parse_date(params[:to],   :end)
            entries = ::Financial::Reports::DreReport.new(account: current_account, from: from, to: to)
                                                      .entries_in_category(params[:category_id].presence)
            render json: { data: entries.limit(500).map(&method(:serialize_entry)) }
          end

          # GET /financial/v2/reports/cash_flow?from=...&to=...&bank_account_id=...
          def cash_flow
            from = parse_date(params[:from], :start)
            to   = parse_date(params[:to], :end)
            data = ::Financial::Reports::CashFlowReport.call(
              account: current_account, from: from, to: to,
              bank_account_id: params[:bank_account_id]
            )
            render json: data
          end

          # GET /financial/v2/reports/dashboard?date=2026-05-07
          def dashboard
            from = parse_date(params[:from], :start)
            to   = parse_date(params[:to],   :end)
            if from && to
              data = ::Financial::Reports::DashboardKpis.call(account: current_account, from: from, to: to)
            else
              date = parse_date(params[:date], :start) || Date.current
              data = ::Financial::Reports::DashboardKpis.call(account: current_account, date: date)
            end
            render json: data
          end

          # ── Charts v2 ─────────────────────────────────────────────────────
          # GET /financial/v2/reports/cash_flow_chart?from=..&to=..
          def cash_flow_chart
            from = parse_date(params[:from], :start) || 29.days.ago.to_date
            to   = parse_date(params[:to],   :end)   || Date.current
            render json: ::Financial::Reports::Charts.cash_flow(account: current_account, from: from, to: to)
          end

          # GET /financial/v2/reports/revenue_composition?from=..&to=..
          def revenue_composition
            from = parse_date(params[:from], :start) || 6.months.ago.to_date
            to   = parse_date(params[:to],   :end)   || Date.current
            render json: ::Financial::Reports::Charts.revenue_composition(account: current_account, from: from, to: to)
          end

          # GET /financial/v2/reports/delinquency_aging — snapshot atual, sem período.
          def delinquency_aging
            render json: ::Financial::Reports::Charts.aging(account: current_account)
          end

          # GET /financial/v2/reports/revenue_by_professional?from=..&to=..
          def revenue_by_professional
            from = parse_date(params[:from], :start) || Date.current.beginning_of_month
            to   = parse_date(params[:to],   :end)   || Date.current.end_of_month
            render json: ::Financial::Reports::Charts.revenue_by_professional(account: current_account, from: from, to: to)
          end

          # GET /financial/v2/reports/cash_flow_projection?horizon=60
          def cash_flow_projection
            horizon = (params[:horizon] || 60).to_i.clamp(7, 365)
            render json: ::Financial::Reports::Charts.cash_flow_projection(account: current_account, horizon: horizon)
          end

          # GET /financial/v2/reports/delinquency_trend?months=12
          def delinquency_trend
            months = (params[:months] || 12).to_i.clamp(3, 36)
            render json: ::Financial::Reports::Charts.delinquency_trend(account: current_account, months: months)
          end

          # GET /financial/v2/reports/kpi_sparklines?days=14 — mini-séries pros
          # KPIs do Dashboard v2. Substitui o endpoint legado v1
          # `/financial/dashboard/kpis` (que lia de account_transactions).
          def kpi_sparklines
            days = (params[:days] || 14).to_i.clamp(7, 90)
            render json: ::Financial::Reports::Charts.kpi_sparklines(account: current_account, days: days)
          end

          # GET /financial/v2/reports/commissions?from=...&to=...&professional_id=...
          # Canon F-29 — apuração de comissões por profissional.
          # Profissional comum só vê o próprio (validação em filter); GERENTE/
          # ADMIN/AUDITOR veem tudo.
          def commissions
            allowed = user_has_any_role?(%w[GERENTE ADMIN AUDITOR])
            unless allowed
              # Fallback: profissional vê SÓ as próprias comissões.
              params[:professional_id] = current_user.id.to_s
            end

            from = parse_date(params[:from], :start)
            to   = parse_date(params[:to],   :end)
            data = ::Financial::Reports::CommissionsReport.call(
              account: current_account,
              from: from,
              to: to,
              professional_id: params[:professional_id]
            )
            render json: data
          end

          # GET /financial/v2/reports/expenses_by_category?from=...&to=...
          # Canon F-30 §sub-aba 1.
          def expenses_by_category
            require_role!('GERENTE', 'ADMIN', 'AUDITOR') and return unless user_has_any_role?(%w[GERENTE ADMIN AUDITOR])

            from = parse_date(params[:from], :start)
            to   = parse_date(params[:to],   :end)
            data = ::Financial::Reports::ExpensesByCategoryReport.call(
              account: current_account, from: from, to: to
            )
            render json: data
          end

          # GET /financial/v2/reports/expenses_by_category/category/:category_id?from=...&to=...
          # Drill-down: lista as despesas de uma categoria. category_id pode
          # vir como 'null' (string) ou vazio para listar "Sem categoria".
          def expenses_by_category_drilldown
            require_role!('GERENTE', 'ADMIN', 'AUDITOR') and return unless user_has_any_role?(%w[GERENTE ADMIN AUDITOR])

            from = parse_date(params[:from], :start)
            to   = parse_date(params[:to],   :end)
            cat_id = params[:category_id].to_s == 'null' ? nil : params[:category_id].presence
            expenses = ::Financial::Reports::ExpensesByCategoryReport
                         .new(account: current_account, from: from, to: to)
                         .expenses_in_category(cat_id)
            render json: { data: expenses.limit(500).map { |e| serialize_expense(e) } }
          end

          # GET /financial/v2/reports/ticket_medio?from=...&to=...
          # Canon F-30 §sub-aba 3.
          def ticket_medio
            require_role!('GERENTE', 'ADMIN', 'AUDITOR') and return unless user_has_any_role?(%w[GERENTE ADMIN AUDITOR])

            from = parse_date(params[:from], :start)
            to   = parse_date(params[:to],   :end)
            data = ::Financial::Reports::TicketMedioReport.call(
              account: current_account, from: from, to: to
            )
            render json: data
          end

          # GET /financial/v2/reports/convenio?from=...&to=...&mode=all|convenio|particular
          # Canon F-30 §sub-aba 2.
          def convenio
            require_role!('GERENTE', 'ADMIN', 'AUDITOR') and return unless user_has_any_role?(%w[GERENTE ADMIN AUDITOR])

            from = parse_date(params[:from], :start)
            to   = parse_date(params[:to],   :end)
            data = ::Financial::Reports::ConvenioReport.call(
              account: current_account, from: from, to: to,
              mode: params[:mode]
            )
            render json: data
          end

          # GET /financial/v2/reports/accountant_export/preview?from=...&to=...
          # Canon F-33 §exportação contador. Retorna counts dos 4 datasets
          # pra UI mostrar antes do contador baixar (evita CSV vazio).
          def accountant_export_preview
            require_role!('ADMIN', 'AUDITOR') and return unless user_has_any_role?(%w[ADMIN AUDITOR])

            from = parse_date(params[:from], :start)
            to   = parse_date(params[:to],   :end)
            svc = ::Financial::Reports::AccountantExport.new(
              account: current_account, from: from, to: to
            )
            render json: { period: { from: from, to: to }, counts: svc.counts }
          end

          # GET /financial/v2/reports/accountant_export?from=...&to=...&type=receitas
          # Canon F-33 — gera o CSV do tipo solicitado e devolve como
          # download. Filename: "<tipo>_<from>_a_<to>.csv".
          def accountant_export
            require_role!('ADMIN', 'AUDITOR') and return unless user_has_any_role?(%w[ADMIN AUDITOR])

            type = params[:type].to_s
            unless ::Financial::Reports::AccountantExport::TYPES.map(&:to_s).include?(type)
              return render(json: { error: 'invalid_type', allowed: ::Financial::Reports::AccountantExport::TYPES }, status: :bad_request)
            end

            from = parse_date(params[:from], :start)
            to   = parse_date(params[:to],   :end)
            svc = ::Financial::Reports::AccountantExport.new(
              account: current_account, from: from, to: to
            )
            csv = svc.csv_for(type)
            filename = "#{type}_#{from.strftime('%Y%m%d')}_a_#{to.strftime('%Y%m%d')}.csv"
            send_data csv, type: 'text/csv; charset=utf-8', filename: filename
          end

          private

          def parse_date(value, edge)
            return nil if value.blank?
            return value.to_date if value.is_a?(Date) || value.is_a?(Time)

            Date.parse(value.to_s)
          rescue ArgumentError
            edge == :start ? Date.current.beginning_of_month : Date.current.end_of_month
          end

          def serialize_entry(e)
            {
              id: e.id,
              direction: e.direction,
              kind: e.kind,
              amount_cents: e.amount_cents,
              competence_date: e.competence_date,
              cash_date: e.cash_date,
              description: e.description,
              category_id: e.financial_dre_category_id,
              patient_id: e.patient_id,
              professional_id: e.professional_id
            }
          end

          def serialize_expense(e)
            cat = e.financial_dre_category
            bank = e.financial_bank_account
            {
              id: e.id,
              description: e.description,
              status: e.status,
              amount_cents: e.amount_cents.to_i,
              paid_amount_cents: e.paid_amount_cents.to_i,
              competence_date: e.competence_date,
              due_date: e.due_date,
              payment_method: e.payment_method,
              category: cat ? { id: cat.id, name: cat.name, kind: cat.kind } : nil,
              bank_account: bank ? { id: bank.id, name: bank.name } : nil
            }
          end
        end
      end
    end
  end
end
