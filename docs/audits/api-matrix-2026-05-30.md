# Matriz Completa de APIs — Financial · AI Agent · Internal Chat

> Gerada automaticamente a partir da auditoria de 2026-05-30 (fonte: `config/routes.rb` + controllers reais).
> Coluna **Doc** = endpoint possui swagger; **Acc** = a doc, quando existe, está correta (sim/parcial/não/n-a).

**Totais:** 204 endpoints mapeados · 152 documentados · 52 sem documentação · cobertura de existência 75%.


## Financial — 149 endpoints (106 doc · 43 sem doc · cobertura 71%)

| # | Método | Endpoint | Controller#Action | Auth | RBAC | Doc | Acc |
|---|---|---|---|---|---|---|---|
| 1 | POST | `/webhooks/financial/asaas` | Webhooks::Financial::AsaasController#receive | Pública | — | sim | parcial |
| 2 | GET | `/api/v1/accounts/:account_id/financial/v2/setup` | SetupController#show | authenticate_user! | — | sim | sim |
| 3 | POST | `/api/v1/accounts/:account_id/financial/v2/setup/complete_step` | SetupController#complete_step | authenticate_user! | ADMIN ou GERENTE | sim | sim |
| 4 | GET | `/api/v1/accounts/:account_id/financial/v2/categories` | DreCategoriesController#index | authenticate_user! | — | sim | sim |
| 5 | POST | `/api/v1/accounts/:account_id/financial/v2/categories` | DreCategoriesController#create | authenticate_user! | GERENTE/ADMIN | sim | sim |
| 6 | POST | `/api/v1/accounts/:account_id/financial/v2/categories/restore_defaults` | DreCategoriesController#restore_defaults | authenticate_user! | ADMIN | nao | n-a |
| 7 | GET | `/api/v1/accounts/:account_id/financial/v2/categories/:id` | DreCategoriesController#show | authenticate_user! | — | sim | sim |
| 8 | PATCH/PUT | `/api/v1/accounts/:account_id/financial/v2/categories/:id` | DreCategoriesController#update | authenticate_user! | GERENTE/ADMIN | sim | sim |
| 9 | DELETE | `/api/v1/accounts/:account_id/financial/v2/categories/:id` | DreCategoriesController#destroy | authenticate_user! | ADMIN | sim | parcial |
| 10 | GET | `/api/v1/accounts/:account_id/financial/v2/bank_accounts` | BankAccountsController#index | authenticate_user! | — | sim | sim |
| 11 | POST | `/api/v1/accounts/:account_id/financial/v2/bank_accounts` | BankAccountsController#create | authenticate_user! | GERENTE/ADMIN | sim | sim |
| 12 | GET | `/api/v1/accounts/:account_id/financial/v2/bank_accounts/:id` | BankAccountsController#show | authenticate_user! | — | sim | sim |
| 13 | PATCH/PUT | `/api/v1/accounts/:account_id/financial/v2/bank_accounts/:id` | BankAccountsController#update | authenticate_user! | GERENTE/ADMIN | sim | sim |
| 14 | DELETE | `/api/v1/accounts/:account_id/financial/v2/bank_accounts/:id` | BankAccountsController#destroy | authenticate_user! | ADMIN | sim | sim |
| 15 | POST | `/api/v1/accounts/:account_id/financial/v2/bank_accounts/:id/transfer` | BankAccountsController#transfer | authenticate_user! | GERENTE/ADMIN | sim | sim |
| 16 | GET | `/api/v1/accounts/:account_id/financial/v2/commission_rules` | CommissionRulesController#index | authenticate_user! | ADMIN | sim | sim |
| 17 | POST | `/api/v1/accounts/:account_id/financial/v2/commission_rules` | CommissionRulesController#create | authenticate_user! | ADMIN | sim | sim |
| 18 | GET | `/api/v1/accounts/:account_id/financial/v2/commission_rules/:id` | CommissionRulesController#show | authenticate_user! | ADMIN | sim | sim |
| 19 | PATCH/PUT | `/api/v1/accounts/:account_id/financial/v2/commission_rules/:id` | CommissionRulesController#update | authenticate_user! | ADMIN | sim | sim |
| 20 | DELETE | `/api/v1/accounts/:account_id/financial/v2/commission_rules/:id` | CommissionRulesController#destroy | authenticate_user! | ADMIN | sim | sim |
| 21 | GET | `/api/v1/accounts/:account_id/financial/v2/recurring_expenses` | RecurringExpensesController#index | authenticate_user! | GERENTE/ADMIN (require_manager! em todas) | sim | sim |
| 22 | POST | `/api/v1/accounts/:account_id/financial/v2/recurring_expenses` | RecurringExpensesController#create | authenticate_user! | GERENTE/ADMIN | sim | sim |
| 23 | GET | `/api/v1/accounts/:account_id/financial/v2/recurring_expenses/:id` | RecurringExpensesController#show | authenticate_user! | GERENTE/ADMIN | sim | sim |
| 24 | PATCH/PUT | `/api/v1/accounts/:account_id/financial/v2/recurring_expenses/:id` | RecurringExpensesController#update | authenticate_user! | GERENTE/ADMIN | sim | sim |
| 25 | DELETE | `/api/v1/accounts/:account_id/financial/v2/recurring_expenses/:id` | RecurringExpensesController#destroy | authenticate_user! | GERENTE/ADMIN | sim | sim |
| 26 | GET | `/api/v1/accounts/:account_id/financial/v2/recurring_billings` | RecurringBillingsController#index | authenticate_user! | — | nao | n-a |
| 27 | POST | `/api/v1/accounts/:account_id/financial/v2/recurring_billings` | RecurringBillingsController#create | authenticate_user! | RECEPCAO/GERENTE/ADMIN (authorize_write!) | nao | n-a |
| 28 | GET | `/api/v1/accounts/:account_id/financial/v2/recurring_billings/:id` | RecurringBillingsController#show | authenticate_user! | — | nao | n-a |
| 29 | PATCH/PUT | `/api/v1/accounts/:account_id/financial/v2/recurring_billings/:id` | RecurringBillingsController#update | authenticate_user! | RECEPCAO/GERENTE/ADMIN | nao | n-a |
| 30 | DELETE | `/api/v1/accounts/:account_id/financial/v2/recurring_billings/:id` | RecurringBillingsController#destroy | authenticate_user! | RECEPCAO/GERENTE/ADMIN | nao | n-a |
| 31 | POST | `/api/v1/accounts/:account_id/financial/v2/recurring_billings/:id/pause` | RecurringBillingsController#pause | authenticate_user! | RECEPCAO/GERENTE/ADMIN | nao | n-a |
| 32 | POST | `/api/v1/accounts/:account_id/financial/v2/recurring_billings/:id/resume` | RecurringBillingsController#resume | authenticate_user! | RECEPCAO/GERENTE/ADMIN | nao | n-a |
| 33 | POST | `/api/v1/accounts/:account_id/financial/v2/recurring_billings/:id/cancel` | RecurringBillingsController#cancel | authenticate_user! | RECEPCAO/GERENTE/ADMIN | nao | n-a |
| 34 | GET | `/api/v1/accounts/:account_id/financial/v2/revenue_goals` | RevenueGoalsController#index | authenticate_user! | GERENTE/ADMIN (require_manager! em todas) | sim | sim |
| 35 | POST | `/api/v1/accounts/:account_id/financial/v2/revenue_goals` | RevenueGoalsController#create | authenticate_user! | GERENTE/ADMIN | sim | sim |
| 36 | GET | `/api/v1/accounts/:account_id/financial/v2/revenue_goals/:id` | RevenueGoalsController#show | authenticate_user! | GERENTE/ADMIN | nao | n-a |
| 37 | PATCH/PUT | `/api/v1/accounts/:account_id/financial/v2/revenue_goals/:id` | RevenueGoalsController#update | authenticate_user! | GERENTE/ADMIN | nao | n-a |
| 38 | POST | `/api/v1/accounts/:account_id/financial/v2/revenue_goals/upsert` | RevenueGoalsController#upsert | authenticate_user! | GERENTE/ADMIN | sim | sim |
| 39 | DELETE | `/api/v1/accounts/:account_id/financial/v2/revenue_goals/:id` | RevenueGoalsController#destroy | authenticate_user! | GERENTE/ADMIN | sim | nao |
| 40 | GET | `/api/v1/accounts/:account_id/financial/v2/gateway_setting` | GatewaySettingsController#show | authenticate_user! | ADMIN | sim | sim |
| 41 | PATCH/PUT | `/api/v1/accounts/:account_id/financial/v2/gateway_setting` | GatewaySettingsController#update | authenticate_user! | ADMIN | sim | sim |
| 42 | GET | `/api/v1/accounts/:account_id/financial/v2/budgets` | BudgetsController#index | authenticate_user! | — | sim | sim |
| 43 | POST | `/api/v1/accounts/:account_id/financial/v2/budgets` | BudgetsController#create | authenticate_user! | — | sim | sim |
| 44 | GET | `/api/v1/accounts/:account_id/financial/v2/budgets/:id` | BudgetsController#show | authenticate_user! | — | sim | sim |
| 45 | PATCH/PUT | `/api/v1/accounts/:account_id/financial/v2/budgets/:id` | BudgetsController#update | authenticate_user! | GERENTE/ADMIN sempre; ou rascunho+RECEPCAO/DENTIST | sim | sim |
| 46 | DELETE | `/api/v1/accounts/:account_id/financial/v2/budgets/:id` | BudgetsController#destroy | authenticate_user! | ADMIN | sim | sim |
| 47 | POST | `/api/v1/accounts/:account_id/financial/v2/budgets/:id/approve` | BudgetsController#approve | authenticate_user! | RECEPCAO/GERENTE/ADMIN/DENTIST | sim | sim |
| 48 | POST | `/api/v1/accounts/:account_id/financial/v2/budgets/:id/cancel` | BudgetsController#cancel | authenticate_user! | GERENTE/ADMIN | sim | sim |
| 49 | PATCH | `/api/v1/accounts/:account_id/financial/v2/budgets/:id/update_installments` | BudgetsController#update_installments | authenticate_user! | GERENTE/ADMIN | sim | sim |
| 50 | POST | `/api/v1/accounts/:account_id/financial/v2/budgets/:id/simulate_plan` | BudgetsController#simulate_plan | authenticate_user! | — | nao | n-a |
| 51 | GET | `/api/v1/accounts/:account_id/financial/v2/installments` | InstallmentsController#index | authenticate_user! | — | sim | sim |
| 52 | GET | `/api/v1/accounts/:account_id/financial/v2/installments/by_patient` | InstallmentsController#by_patient | authenticate_user! | — | sim | sim |
| 53 | GET | `/api/v1/accounts/:account_id/financial/v2/installments/:id` | InstallmentsController#show | authenticate_user! | — | sim | sim |
| 54 | POST | `/api/v1/accounts/:account_id/financial/v2/installments/:id/pay` | InstallmentsController#pay | authenticate_user! | — | sim | sim |
| 55 | POST | `/api/v1/accounts/:account_id/financial/v2/installments/:id/refund` | InstallmentsController#refund | authenticate_user! | — | sim | sim |
| 56 | POST | `/api/v1/accounts/:account_id/financial/v2/installments/:id/charge_whatsapp` | InstallmentsController#charge_whatsapp | authenticate_user! | — | sim | sim |
| 57 | POST | `/api/v1/accounts/:account_id/financial/v2/installments/:id/upload_proof` | InstallmentsController#upload_proof | authenticate_user! | — | sim | sim |
| 58 | GET | `/api/v1/accounts/:account_id/financial/v2/installments/:id/proof_url` | InstallmentsController#proof_url | authenticate_user! | — | sim | sim |
| 59 | GET | `/api/v1/accounts/:account_id/financial/v2/payment_receipts` | PaymentReceiptsController#index | authenticate_user! | — | sim | sim |
| 60 | POST | `/api/v1/accounts/:account_id/financial/v2/payment_receipts` | PaymentReceiptsController#create | authenticate_user! | RECEPCAO/GERENTE/ADMIN | sim | sim |
| 61 | GET | `/api/v1/accounts/:account_id/financial/v2/payment_receipts/:id` | PaymentReceiptsController#show | authenticate_user! | — | sim | sim |
| 62 | POST | `/api/v1/accounts/:account_id/financial/v2/payment_receipts/:id/refund` | PaymentReceiptsController#refund | authenticate_user! | GERENTE/ADMIN | sim | sim |
| 63 | GET | `/api/v1/accounts/:account_id/financial/v2/entries` | EntriesController#index | authenticate_user! | — | sim | sim |
| 64 | POST | `/api/v1/accounts/:account_id/financial/v2/entries` | EntriesController#create | authenticate_user! | — | sim | sim |
| 65 | GET | `/api/v1/accounts/:account_id/financial/v2/entries/:id` | EntriesController#show | authenticate_user! | — | sim | sim |
| 66 | PATCH/PUT | `/api/v1/accounts/:account_id/financial/v2/entries/:id` | EntriesController#update | authenticate_user! | — | sim | sim |
| 67 | DELETE | `/api/v1/accounts/:account_id/financial/v2/entries/:id` | EntriesController#destroy | authenticate_user! | — | sim | sim |
| 68 | POST | `/api/v1/accounts/:account_id/financial/v2/entries/bulk_reclassify` | EntriesController#bulk_reclassify | authenticate_user! | — | sim | sim |
| 69 | GET | `/api/v1/accounts/:account_id/financial/v2/expenses` | ExpensesController#index | authenticate_user! | — | sim | sim |
| 70 | POST | `/api/v1/accounts/:account_id/financial/v2/expenses` | ExpensesController#create | authenticate_user! | RECEPCAO/GERENTE/ADMIN | sim | sim |
| 71 | GET | `/api/v1/accounts/:account_id/financial/v2/expenses/:id` | ExpensesController#show | authenticate_user! | — | sim | sim |
| 72 | PATCH/PUT | `/api/v1/accounts/:account_id/financial/v2/expenses/:id` | ExpensesController#update | authenticate_user! | GERENTE/ADMIN | sim | sim |
| 73 | DELETE | `/api/v1/accounts/:account_id/financial/v2/expenses/:id` | ExpensesController#destroy | authenticate_user! | GERENTE/ADMIN | sim | sim |
| 74 | POST | `/api/v1/accounts/:account_id/financial/v2/expenses/:id/pay` | ExpensesController#pay | authenticate_user! | RECEPCAO/GERENTE/ADMIN | sim | sim |
| 75 | POST | `/api/v1/accounts/:account_id/financial/v2/expenses/:id/reverse` | ExpensesController#reverse | authenticate_user! | GERENTE/ADMIN | sim | sim |
| 76 | GET | `/api/v1/accounts/:account_id/financial/v2/cash_registers` | CashRegistersController#index | authenticate_user! | — | sim | sim |
| 77 | GET | `/api/v1/accounts/:account_id/financial/v2/cash_registers/:id` | CashRegistersController#show | authenticate_user! | — | sim | sim |
| 78 | POST | `/api/v1/accounts/:account_id/financial/v2/cash_registers/open` | CashRegistersController#open | authenticate_user! | RECEPCAO/GERENTE/ADMIN | sim | sim |
| 79 | POST | `/api/v1/accounts/:account_id/financial/v2/cash_registers/:id/close` | CashRegistersController#close | authenticate_user! | RECEPCAO/GERENTE/ADMIN | sim | sim |
| 80 | POST | `/api/v1/accounts/:account_id/financial/v2/cash_registers/:id/reopen` | CashRegistersController#reopen | authenticate_user! | GERENTE/ADMIN | sim | sim |
| 81 | POST | `/api/v1/accounts/:account_id/financial/v2/cash_registers/:id/withdraw` | CashRegistersController#withdraw | authenticate_user! | RECEPCAO/GERENTE/ADMIN | sim | sim |
| 82 | POST | `/api/v1/accounts/:account_id/financial/v2/cash_registers/:id/supplement` | CashRegistersController#supplement | authenticate_user! | RECEPCAO/GERENTE/ADMIN | sim | sim |
| 83 | GET | `/api/v1/accounts/:account_id/financial/v2/patient_credits` | PatientCreditsController#index | authenticate_user! | — | sim | sim |
| 84 | POST | `/api/v1/accounts/:account_id/financial/v2/patient_credits` | PatientCreditsController#create | authenticate_user! | GERENTE/ADMIN | sim | sim |
| 85 | POST | `/api/v1/accounts/:account_id/financial/v2/commission_entries/bulk_pay` | CommissionEntriesController#bulk_pay | authenticate_user! | GERENTE/ADMIN (authorize_pay!) | sim | sim |
| 86 | POST | `/api/v1/accounts/:account_id/financial/v2/commission_entries/:id/pay` | CommissionEntriesController#pay | authenticate_user! | GERENTE/ADMIN (authorize_pay!, nao DENTIST) | sim | sim |
| 87 | GET | `/api/v1/accounts/:account_id/financial/v2/audit_logs` | AuditLogsController#index | authenticate_user! | ADMIN/AUDITOR/GERENTE (require_admin_or_auditor!) | sim | sim |
| 88 | GET | `/api/v1/accounts/:account_id/financial/v2/audit_logs/export_csv` | AuditLogsController#export_csv | authenticate_user! | ADMIN/AUDITOR/GERENTE | sim | sim |
| 89 | GET | `/api/v1/accounts/:account_id/financial/v2/backups` | BackupsController#index | authenticate_user! | ADMIN/AUDITOR (require_admin_or_auditor!) | sim | sim |
| 90 | POST | `/api/v1/accounts/:account_id/financial/v2/backups/run` | BackupsController#run | authenticate_user! | ADMIN | sim | sim |
| 91 | POST | `/api/v1/accounts/:account_id/financial/v2/backups/destroy` | BackupsController#destroy | authenticate_user! | ADMIN | sim | sim |
| 92 | GET | `/api/v1/accounts/:account_id/financial/v2/lgpd_requests` | LgpdRequestsController#index | authenticate_user! | ADMIN/AUDITOR/GERENTE (require_admin_or_auditor!) | sim | sim |
| 93 | POST | `/api/v1/accounts/:account_id/financial/v2/lgpd_requests` | LgpdRequestsController#create | authenticate_user! | ADMIN/GERENTE (require_admin_or_manager!) | sim | sim |
| 94 | GET | `/api/v1/accounts/:account_id/financial/v2/lgpd_requests/:id` | LgpdRequestsController#show | authenticate_user! | ADMIN/AUDITOR/GERENTE | sim | sim |
| 95 | POST | `/api/v1/accounts/:account_id/financial/v2/lgpd_requests/:id/approve` | LgpdRequestsController#approve | authenticate_user! | ADMIN | sim | sim |
| 96 | POST | `/api/v1/accounts/:account_id/financial/v2/lgpd_requests/:id/reject` | LgpdRequestsController#reject | authenticate_user! | ADMIN | sim | sim |
| 97 | POST | `/api/v1/accounts/:account_id/financial/v2/lgpd_requests/:id/execute` | LgpdRequestsController#execute | authenticate_user! | ADMIN | sim | sim |
| 98 | POST | `/api/v1/accounts/:account_id/financial/v2/lgpd_requests/:id/cancel` | LgpdRequestsController#cancel | authenticate_user! | ADMIN | sim | sim |
| 99 | GET | `/api/v1/accounts/:account_id/financial/v2/payment_methods` | PaymentMethodsController#index | authenticate_user! | — | nao | n-a |
| 100 | POST | `/api/v1/accounts/:account_id/financial/v2/payment_methods` | PaymentMethodsController#create | authenticate_user! | ADMIN/GERENTE (authorize_write!) | nao | n-a |
| 101 | GET | `/api/v1/accounts/:account_id/financial/v2/payment_methods/:id` | PaymentMethodsController#show | authenticate_user! | — | nao | n-a |
| 102 | PATCH/PUT | `/api/v1/accounts/:account_id/financial/v2/payment_methods/:id` | PaymentMethodsController#update | authenticate_user! | ADMIN/GERENTE | nao | n-a |
| 103 | DELETE | `/api/v1/accounts/:account_id/financial/v2/payment_methods/:id` | PaymentMethodsController#destroy | authenticate_user! | ADMIN/GERENTE | nao | n-a |
| 104 | GET | `/api/v1/accounts/:account_id/financial/v2/payment_methods/:id/simulate_fee` | PaymentMethodsController#simulate_fee | authenticate_user! | — | nao | n-a |
| 105 | POST | `/api/v1/accounts/:account_id/financial/v2/payment_methods/rename_provider` | PaymentMethodsController#rename_provider | authenticate_user! | — | nao | n-a |
| 106 | POST | `/api/v1/accounts/:account_id/financial/v2/payment_methods/destroy_provider` | PaymentMethodsController#destroy_provider | authenticate_user! | ADMIN/GERENTE (authorize_write! inline) | nao | n-a |
| 107 | GET | `/api/v1/accounts/:account_id/financial/v2/payment_methods/:payment_method_id/fees` | PaymentMethodFeesController#index | authenticate_user! | — | nao | n-a |
| 108 | POST | `/api/v1/accounts/:account_id/financial/v2/payment_methods/:payment_method_id/fees` | PaymentMethodFeesController#create | authenticate_user! | ADMIN/GERENTE (authorize_write!) | nao | n-a |
| 109 | GET | `/api/v1/accounts/:account_id/financial/v2/payment_methods/:payment_method_id/fees/:id` | PaymentMethodFeesController#show | authenticate_user! | — | nao | n-a |
| 110 | POST | `/api/v1/accounts/:account_id/financial/v2/payment_methods/:payment_method_id/fees/:id/deactivate` | PaymentMethodFeesController#deactivate | authenticate_user! | ADMIN/GERENTE | nao | n-a |
| 111 | GET | `/api/v1/accounts/:account_id/financial/v2/service_pricings` | ServicePricingsController#index | authenticate_user! | — | nao | n-a |
| 112 | GET | `/api/v1/accounts/:account_id/financial/v2/service_pricings/:id` | ServicePricingsController#show | authenticate_user! | — | nao | n-a |
| 113 | PUT/PATCH | `/api/v1/accounts/:account_id/financial/v2/service_pricings/:id` | ServicePricingsController#upsert | authenticate_user! | ADMIN/GERENTE (authorize_write!) | nao | n-a |
| 114 | DELETE | `/api/v1/accounts/:account_id/financial/v2/service_pricings/:id` | ServicePricingsController#deactivate | authenticate_user! | ADMIN/GERENTE | nao | n-a |
| 115 | GET | `/api/v1/accounts/:account_id/financial/v2/agent_profiles` | AgentProfilesController#index | authenticate_user! | — | nao | n-a |
| 116 | GET | `/api/v1/accounts/:account_id/financial/v2/agent_profiles/:id` | AgentProfilesController#show | authenticate_user! | — | nao | n-a |
| 117 | PUT/PATCH | `/api/v1/accounts/:account_id/financial/v2/agent_profiles/:id` | AgentProfilesController#upsert | authenticate_user! | ADMIN | nao | n-a |
| 118 | DELETE | `/api/v1/accounts/:account_id/financial/v2/agent_profiles/:id` | AgentProfilesController#deactivate | authenticate_user! | ADMIN | nao | n-a |
| 119 | GET | `/api/v1/accounts/:account_id/financial/v2/period_closures` | PeriodClosuresController#index | authenticate_user! | — | nao | n-a |
| 120 | POST | `/api/v1/accounts/:account_id/financial/v2/period_closures` | PeriodClosuresController#create | authenticate_user! | ADMIN (authorize_admin!) | nao | n-a |
| 121 | GET | `/api/v1/accounts/:account_id/financial/v2/period_closures/:id` | PeriodClosuresController#show | authenticate_user! | — | nao | n-a |
| 122 | POST | `/api/v1/accounts/:account_id/financial/v2/period_closures/:id/reopen` | PeriodClosuresController#reopen | authenticate_user! | ADMIN | nao | n-a |
| 123 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/dre` | ReportsController#dre | authenticate_user! | GERENTE/ADMIN/AUDITOR | sim | sim |
| 124 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/dre/category/:category_id` | ReportsController#dre_category | authenticate_user! | GERENTE/ADMIN/AUDITOR | sim | sim |
| 125 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/cash_flow` | ReportsController#cash_flow | authenticate_user! | — | sim | sim |
| 126 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/dashboard` | ReportsController#dashboard | authenticate_user! | — | sim | sim |
| 127 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/commissions` | ReportsController#commissions | authenticate_user! | GERENTE/ADMIN/AUDITOR ve tudo; outro role ve so o proprio (f | sim | sim |
| 128 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/cash_flow_chart` | ReportsController#cash_flow_chart | authenticate_user! | — | sim | sim |
| 129 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/revenue_composition` | ReportsController#revenue_composition | authenticate_user! | — | sim | sim |
| 130 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/delinquency_aging` | ReportsController#delinquency_aging | authenticate_user! | — | sim | sim |
| 131 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/revenue_by_professional` | ReportsController#revenue_by_professional | authenticate_user! | — | sim | sim |
| 132 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/cash_flow_projection` | ReportsController#cash_flow_projection | authenticate_user! | — | sim | sim |
| 133 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/delinquency_trend` | ReportsController#delinquency_trend | authenticate_user! | — | sim | sim |
| 134 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/kpi_sparklines` | ReportsController#kpi_sparklines | authenticate_user! | — | sim | sim |
| 135 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/top_procedures` | ReportsController#top_procedures | authenticate_user! | — | nao | n-a |
| 136 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/revenue_vs_goal` | ReportsController#revenue_vs_goal | authenticate_user! | — | nao | n-a |
| 137 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/expenses_by_category` | ReportsController#expenses_by_category | authenticate_user! | GERENTE/ADMIN/AUDITOR | sim | sim |
| 138 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/expenses_by_category/category/:category_id` | ReportsController#expenses_by_category_drilldown | authenticate_user! | GERENTE/ADMIN/AUDITOR | sim | sim |
| 139 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/ticket_medio` | ReportsController#ticket_medio | authenticate_user! | GERENTE/ADMIN/AUDITOR | sim | sim |
| 140 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/convenio` | ReportsController#convenio | authenticate_user! | GERENTE/ADMIN/AUDITOR | sim | sim |
| 141 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/revenue_by_procedure` | ReportsController#revenue_by_procedure | authenticate_user! | GERENTE/ADMIN/AUDITOR | nao | n-a |
| 142 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/revenue_by_payment_method` | ReportsController#revenue_by_payment_method | authenticate_user! | GERENTE/ADMIN/AUDITOR | nao | n-a |
| 143 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/revenue_by_professional_table` | ReportsController#revenue_by_professional_table | authenticate_user! | GERENTE/ADMIN/AUDITOR | nao | n-a |
| 144 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/account_statement` | ReportsController#account_statement | authenticate_user! | GERENTE/ADMIN/AUDITOR | nao | n-a |
| 145 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/goals_vs_actual` | ReportsController#goals_vs_actual | authenticate_user! | GERENTE/ADMIN/AUDITOR | nao | n-a |
| 146 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/accountant_export/preview` | ReportsController#accountant_export_preview | authenticate_user! | ADMIN/AUDITOR | sim | sim |
| 147 | GET | `/api/v1/accounts/:account_id/financial/v2/reports/accountant_export` | ReportsController#accountant_export | authenticate_user! | ADMIN/AUDITOR | sim | sim |
| 148 | GET | `/api/v1/accounts/:account_id/financial/v2/patients/:patient_id/summary` | PatientSummariesController#show | authenticate_user! | RBAC Klivy patients.view_financial (bypass admin/super_admin | sim | sim |
| 149 | GET | `/api/v1/accounts/:account_id/financial/v2/patients/:patient_id/timeline` | PatientTimelinesController#show | authenticate_user! | RBAC Klivy patients.view_financial (bypass admin/super_admin | sim | sim |

**Docs órfãos (swagger sem rota):** nenhum.

## AI Agent (Bea) — 21 endpoints (18 doc · 3 sem doc · cobertura 100%)

| # | Método | Endpoint | Controller#Action | Auth | RBAC | Doc | Acc |
|---|---|---|---|---|---|---|---|
| 1 | GET | `/api/v1/ai_agent/health` | Api::V1::AiAgent::HealthController#show | Pública | — | sim | nao |
| 2 | POST | `/api/v1/ai_agent/feedback` | Api::V1::AiAgent::FeedbacksController#create | Pública | Sem Pundit. Autorização por HMAC sobre {trace_id, account_id | parcial | nao |
| 3 | GET | `/api/v1/accounts/:account_id/ai_agent/documents` | AiAgent::Api::V1::Accounts::DocumentsController#index | authenticate_user! | check_authorization(::AiAgent::Document)→index?. DocumentPol | sim | parcial |
| 4 | GET | `/api/v1/accounts/:account_id/ai_agent/documents/:id` | AiAgent::Api::V1::Accounts::DocumentsController#show | autenticado (api::basecontroller:4-6 + c | check_authorization→show?. DocumentPolicy#show? = administra | sim | nao |
| 5 | POST | `/api/v1/accounts/:account_id/ai_agent/documents` | AiAgent::Api::V1::Accounts::DocumentsController#create | autenticado (api::basecontroller:4-6 + c | check_authorization→create?. DocumentPolicy#create? = admini | sim | nao |
| 6 | DELETE | `/api/v1/accounts/:account_id/ai_agent/documents/:id` | AiAgent::Api::V1::Accounts::DocumentsController#destroy | autenticado (api::basecontroller:4-6 + c | check_authorization→destroy?. DocumentPolicy#destroy? = admi | sim | sim |
| 7 | GET | `/api/v1/accounts/:account_id/ai_agent/follow_up_rules` | AiAgent::Api::V1::Accounts::FollowUpRulesController#index | autenticado (api::basecontroller:4-6 + c | check_authorization(::AiAgent::FollowUpRule)→index?. FollowU | sim | parcial |
| 8 | GET | `/api/v1/accounts/:account_id/ai_agent/follow_up_rules/:id` | AiAgent::Api::V1::Accounts::FollowUpRulesController#show | autenticado (api::basecontroller:4-6 + c | check_authorization→show?. FollowUpRulePolicy#show? = admini | sim | parcial |
| 9 | POST | `/api/v1/accounts/:account_id/ai_agent/follow_up_rules` | AiAgent::Api::V1::Accounts::FollowUpRulesController#create | autenticado (api::basecontroller:4-6 + c | check_authorization→create?. FollowUpRulePolicy#create? = ad | sim | nao |
| 10 | PATCH/PUT | `/api/v1/accounts/:account_id/ai_agent/follow_up_rules/:id` | AiAgent::Api::V1::Accounts::FollowUpRulesController#update | autenticado (api::basecontroller:4-6 + c | check_authorization→update?. FollowUpRulePolicy#update? = ad | parcial | parcial |
| 11 | DELETE | `/api/v1/accounts/:account_id/ai_agent/follow_up_rules/:id` | AiAgent::Api::V1::Accounts::FollowUpRulesController#destroy | autenticado (api::basecontroller:4-6 + c | check_authorization→destroy?. FollowUpRulePolicy#destroy? =  | sim | sim |
| 12 | GET | `/api/v1/accounts/:account_id/ai_agent/internal_notification_templates` | AiAgent::Api::V1::Accounts::InternalNotificationTemplatesController#index | autenticado (api::basecontroller:4-6 + c | check_authorization(AiAgent::InternalNotificationTemplate)→i | sim | parcial |
| 13 | GET | `/api/v1/accounts/:account_id/ai_agent/internal_notification_templates/catalog` | AiAgent::Api::V1::Accounts::InternalNotificationTemplatesController#catalog | autenticado (api::basecontroller:4-6 + c | check_authorization (before_action class | sim | parcial |
| 14 | GET | `/api/v1/accounts/:account_id/ai_agent/internal_notification_templates/:id` | AiAgent::Api::V1::Accounts::InternalNotificationTemplatesController#show | autenticado (api::basecontroller:4-6 + c | check_authorization→show?. Policy#show? = administrator? //  | sim | parcial |
| 15 | POST | `/api/v1/accounts/:account_id/ai_agent/internal_notification_templates` | AiAgent::Api::V1::Accounts::InternalNotificationTemplatesController#create | autenticado (api::basecontroller:4-6 + c | check_authorization→create?. Policy#create? = administrator? | sim | parcial |
| 16 | PATCH/PUT | `/api/v1/accounts/:account_id/ai_agent/internal_notification_templates/:id` | AiAgent::Api::V1::Accounts::InternalNotificationTemplatesController#update | autenticado (api::basecontroller:4-6 + c | check_authorization→update?. Policy#update? = administrator? | parcial | parcial |
| 17 | POST | `/api/v1/accounts/:account_id/ai_agent/internal_notification_templates/:id/reset` | AiAgent::Api::V1::Accounts::InternalNotificationTemplatesController#reset | autenticado (api::basecontroller:4-6 + c | check_authorization→reset?. Policy#reset? = administrator? / | sim | nao |
| 18 | DELETE | `/api/v1/accounts/:account_id/ai_agent/internal_notification_templates/:id` | AiAgent::Api::V1::Accounts::InternalNotificationTemplatesController#destroy | autenticado (api::basecontroller:4-6 + c | check_authorization→destroy?. Policy#destroy? = administrato | sim | sim |
| 19 | GET | `/super_admin/accounts/:account_id/ai_agent_documents` | SuperAdmin::AiAgentDocumentsController#index | Sessão super_admin | — | nao | n-a |
| 20 | POST | `/super_admin/accounts/:account_id/ai_agent_documents` | SuperAdmin::AiAgentDocumentsController#create | Sessão super_admin | — | nao | n-a |
| 21 | DELETE | `/super_admin/accounts/:account_id/ai_agent_documents/:id` | SuperAdmin::AiAgentDocumentsController#destroy | Sessão super_admin | — | nao | n-a |

**Docs órfãos (swagger sem rota):** nenhum.

## Internal Chat — 37 endpoints (28 doc · 8 sem doc · cobertura 76%)

| # | Método | Endpoint | Controller#Action | Auth | RBAC | Doc | Acc |
|---|---|---|---|---|---|---|---|
| 1 | GET | `/api/v1/accounts/:account_id/internal_chat/rooms` | InternalChat::RoomsController#index | authenticate_user! | RoomPolicy#index? = can_view_feature? (admin OR beclinic_can | parcial | nao |
| 2 | POST | `/api/v1/accounts/:account_id/internal_chat/rooms` | InternalChat::RoomsController#create | authenticate_user! | RoomPolicy#create? = admin OR beclinic_can?(:internal_chat,: | parcial | nao |
| 3 | GET | `/api/v1/accounts/:account_id/internal_chat/rooms/:id` | InternalChat::RoomsController#show | account-scoped; fetch_room (rooms_contro | RoomPolicy#show? = admin bypass OR (can_view_feature? AND me | sim | parcial |
| 4 | PATCH/PUT | `/api/v1/accounts/:account_id/internal_chat/rooms/:id` | InternalChat::RoomsController#update | account-scoped; fetch_room | RoomPolicy#update? = admin bypass OR (can_view_feature? AND  | sim | parcial |
| 5 | DELETE | `/api/v1/accounts/:account_id/internal_chat/rooms/:id` | InternalChat::RoomsController#destroy | account-scoped; fetch_room | RoomPolicy#destroy? = admin bypass (logado se não | sim | nao |
| 6 | GET | `/api/v1/accounts/:account_id/internal_chat/rooms/unread_summary` | InternalChat::RoomsController#unread_summary | account-scoped (collection, sem fetch_ro | RoomPolicy#unread_summary? = can_view_feature? | sim | nao |
| 7 | PATCH | `/api/v1/accounts/:account_id/internal_chat/rooms/:id/archive` | InternalChat::RoomsController#archive | account-scoped; fetch_room | 2 camadas: RoomPolicy#archive? (admin OR owner/admin role, r | sim | parcial |
| 8 | PATCH | `/api/v1/accounts/:account_id/internal_chat/rooms/:id/unarchive` | InternalChat::RoomsController#unarchive | account-scoped; fetch_room | RoomPolicy#unarchive? = archive? (admin OR owner/admin) | nao | n-a |
| 9 | PATCH | `/api/v1/accounts/:account_id/internal_chat/rooms/:id/mute` | InternalChat::RoomsController#mute | account-scoped; fetch_room | RoomPolicy#mute? = admin bypass OR (can_view_feature? AND me | sim | parcial |
| 10 | DELETE | `/api/v1/accounts/:account_id/internal_chat/rooms/:id/mute` | InternalChat::RoomsController#unmute | account-scoped; fetch_room | RoomPolicy#unmute? = mute? (admin OR member) | sim | nao |
| 11 | PATCH | `/api/v1/accounts/:account_id/internal_chat/rooms/:id/avatar` | InternalChat::RoomsController#update_avatar | account-scoped; fetch_room | RoomPolicy#update_avatar? = update? (admin OR owner/admin) | sim | parcial |
| 12 | DELETE | `/api/v1/accounts/:account_id/internal_chat/rooms/:id/avatar` | InternalChat::RoomsController#remove_avatar | account-scoped; fetch_room | RoomPolicy#remove_avatar? = update? (admin OR owner/admin) | sim | nao |
| 13 | GET | `/api/v1/accounts/:account_id/internal_chat/rooms/:room_id/messages` | InternalChat::MessagesController#index | account-scoped; fetch_room (messages_con | NÃO Pundit: authorize_room_access = @room.member?(Current.us | sim | nao |
| 14 | POST | `/api/v1/accounts/:account_id/internal_chat/rooms/:room_id/messages` | InternalChat::MessagesController#create | account-scoped; fetch_room | authorize_room_access (member OR admin) | sim | nao |
| 15 | PATCH/PUT | `/api/v1/accounts/:account_id/internal_chat/rooms/:room_id/messages/:id` | InternalChat::MessagesController#update | account-scoped; fetch_room + fetch_messa | authorize_room_access + in | sim | nao |
| 16 | DELETE | `/api/v1/accounts/:account_id/internal_chat/rooms/:room_id/messages/:id` | InternalChat::MessagesController#destroy | account-scoped; fetch_room + fetch_messa | authorize_room_access + can_delete? = sender_user_id==user O | sim | nao |
| 17 | POST | `/api/v1/accounts/:account_id/internal_chat/rooms/:room_id/messages/mark_read` | InternalChat::MessagesController#mark_read | account-scoped; fetch_room (collection) | authorize_room_access (member OR admin) | sim | nao |
| 18 | GET | `/api/v1/accounts/:account_id/internal_chat/rooms/:room_id/messages/favorites` | InternalChat::MessagesController#favorites | account-scoped; fetch_room | authorize_room_access (member OR admin) | sim | parcial |
| 19 | POST | `/api/v1/accounts/:account_id/internal_chat/rooms/:room_id/messages/:id/favorite` | InternalChat::MessagesController#favorite | account-scoped; fetch_room + fetch_messa | authorize_room_access (member OR admin) | sim | nao |
| 20 | DELETE | `/api/v1/accounts/:account_id/internal_chat/rooms/:room_id/messages/:id/favorite` | InternalChat::MessagesController#unfavorite | account-scoped; fetch_room + fetch_messa | authorize_room_access (member OR admin) | sim | nao |
| 21 | POST | `/api/v1/accounts/:account_id/internal_chat/rooms/:room_id/messages/:id/react` | InternalChat::MessagesController#react | account-scoped; fetch_room + fetch_messa | authorize_room_access (member OR admin) | sim | nao |
| 22 | DELETE | `/api/v1/accounts/:account_id/internal_chat/rooms/:room_id/messages/:id/react` | InternalChat::MessagesController#unreact | account-scoped; fetch_room + fetch_messa | authorize_room_access (member OR admin) | sim | nao |
| 23 | GET | `/api/v1/accounts/:account_id/internal_chat/rooms/:room_id/memberships` | InternalChat::MembershipsController#index | account-scoped; fetch_room (memberships_ | Pundit MembershipPolicy#index? = admin bypass OR (can_view_f | nao | n-a |
| 24 | POST | `/api/v1/accounts/:account_id/internal_chat/rooms/:room_id/memberships` | InternalChat::MembershipsController#create | account-scoped; fetch_room | Pundit MembershipPolicy#create? = admin bypass OR (can_view_ | nao | n-a |
| 25 | PATCH/PUT | `/api/v1/accounts/:account_id/internal_chat/rooms/:room_id/memberships/:id` | InternalChat::MembershipsController#update | account-scoped; fetch_room + fetch_membe | Pundit MembershipPolicy#update? = create? (admin OR room_man | nao | n-a |
| 26 | DELETE | `/api/v1/accounts/:account_id/internal_chat/rooms/:room_id/memberships/:id` | InternalChat::MembershipsController#destroy | account-scoped; fetch_room + fetch_membe | Pundit MembershipPolicy#destroy? = leaving_self? sempre perm | nao | n-a |
| 27 | POST | `/api/v1/accounts/:account_id/internal_chat/rooms/:room_id/typing` | InternalChat::TypingController#create | account-scoped; fetch_room (typing_contr | Pundit TypingPolicy#create? = can_view_feature? AND member? | nao | n-a |
| 28 | GET | `/api/v1/accounts/:account_id/internal_chat/rooms/:room_id/attachments` | InternalChat::AttachmentsController#index | account-scoped; fetch_room (attachments_ | Pundit AttachmentPolicy#index? = admin bypass OR (can_view_f | nao | n-a |
| 29 | GET | `/api/v1/accounts/:account_id/internal_chat/rooms/:room_id/attachments/:id/download` | InternalChat::AttachmentsController#download | account-scoped; fetch_room | Pundit AttachmentPolicy#download? = index? (admin OR member) | nao | n-a |
| 30 | GET | `/api/v1/accounts/:account_id/internal_chat/mentions` | InternalChat::MentionsController#index | account-scoped | Pundit MentionPolicy#index? = can_view_feature? | sim | nao |
| 31 | POST | `/api/v1/accounts/:account_id/internal_chat/mentions/mark_read` | InternalChat::MentionsController#mark_read | account-scoped | Pundit MentionPolicy#mark_read? = can_view_feature? | sim | nao |
| 32 | GET | `/api/v1/accounts/:account_id/internal_chat/mentions/unread_count` | InternalChat::MentionsController#unread_count | account-scoped | Pundit MentionPolicy#unread_count? = can_view_feature? | sim | nao |
| 33 | GET | `/api/v1/accounts/:account_id/internal_chat/stickers` | InternalChat::StickersController#index | account-scoped | Pundit StickerPolicy#index? = admin OR beclinic_can?(:intern | sim | nao |
| 34 | POST | `/api/v1/accounts/:account_id/internal_chat/stickers` | InternalChat::StickersController#create | account-scoped | Pundit StickerPolicy#create? = admin OR beclinic_can?(:inter | sim | parcial |
| 35 | DELETE | `/api/v1/accounts/:account_id/internal_chat/stickers/:id` | InternalChat::StickersController#destroy | account-scoped; fetch_sticker (account o | Pundit StickerPolicy#destroy? = false se kind=='default' (AN | sim | nao |
| 36 | POST | `/api/v1/accounts/:account_id/internal_chat/stickers/:id/favorite` | InternalChat::StickersController#favorite | account-scoped; fetch_sticker | Pundit StickerPolicy#favorite? = admin OR beclinic_can?(:int | sim | nao |
| 37 | DELETE | `/api/v1/accounts/:account_id/internal_chat/stickers/:id/favorite` | InternalChat::StickersController#unfavorite | account-scoped; fetch_sticker | Pundit StickerPolicy#unfavorite? = favorite? (admin OR inter | sim | nao |

**Docs órfãos (swagger sem rota):** nenhum.
