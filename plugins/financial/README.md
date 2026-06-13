# Financeiro (Financial::*) — Klivy plugin

Módulo financeiro completo para clínicas. Canon **v2** (namespace `Financial::*`):
orçamentos, parcelas a receber, recebimentos, caixa físico, despesas, comissões,
mensalidades recorrentes, DRE, dashboard e exportação para o contador. Substitui
a "Onda 1A" legacy (tabelas sem namespace, dropadas em
`drop_legacy_financial_tables` em 2026-05-22 — sem cliente real, clean break).

> Canon vivo do produto: [`docs/01-product/modules/financeiro-funcionamento.md`](../../docs/01-product/modules/financeiro-funcionamento.md).
> Contrato da API (OpenAPI): [`swagger/plugins_index.yml`](../../swagger/plugins_index.yml) (tags `Financeiro · *`).

## Invariantes do canon

| Invariante | Como é garantido |
|---|---|
| **Multi-tenant `account_id`** | Toda query usa `.for_account(current_account.id)`. `Account` tem `has_many` de todo modelo `Financial::*` ([engine.rb](lib/financial/engine.rb)). `TenantMismatch` → 403. |
| **Valores em centavos (BIGINT)** | `Financial::Concerns::MoneyAttribute` ([money_attribute.rb](app/models/financial/concerns/money_attribute.rb)) — colunas `*_cents` Integer; helper read/write em reais (BigDecimal, sem perda). Integer SEMPRE é centavos. |
| **Soft-delete** | `Financial::Concerns::SoftDeletable` ([soft_deletable.rb](app/models/financial/concerns/soft_deletable.rb)) — `deleted_at`+`deleted_by_id`, `default_scope` filtra vivos, scope `.alive`/`.with_deleted`. Limpeza física só por job admin com backup. |
| **AuditLog automático** | `Financial::Concerns::Auditable` ([auditable.rb](app/models/financial/concerns/auditable.rb)) — cada CREATE/UPDATE/DELETE/RESTORE grava `Financial::AuditLog` com diff before/after (JSONB), após o commit. `frozen_attributes` torna colunas imutáveis (`attr_readonly` + validação). |
| **Idempotência** | `Financial::IdempotentAction` ([idempotent_action.rb](app/controllers/concerns/financial/idempotent_action.rb)) — header `Idempotency-Key`, guarda `(account_id, key) → response` por 24h. Body diferente com mesma key → 409. |
| **Setup obrigatório** | `BaseController#ensure_setup_complete!` retorna **412** `financial_setup_required` até o wizard concluir os passos obrigatórios. |
| **Período fechado** | `PeriodClosure.closed_for?` + validação `period_not_closed` nos models → `Financial::Errors::PeriodClosed` → **423 Locked**. |

## Fluxo financeiro em 1 página

```
 Plano de Tratamento / Recepção
              │ aprova
              ▼
        ┌───────────┐  approve   ┌──────────────┐
        │  Budget   ├──────────► │ Installment  │  (parcelas a receber)
        │ (orçamento)│           │  pendente    │
        └───────────┘           └──────┬───────┘
              ▲                         │ pay (ReceivePayment)
       RecurringBilling                ▼
   (mensalidade fixa, job 02:30) ┌──────────────┐
   gera Budget+Installment/período│PaymentReceipt│──► comissão provisionada→devida
                                 └──────┬───────┘     (CommissionEntry)
                                        │ cria
                                        ▼
                              ┌──────────────────┐
                              │ Entry (caixa/DRE)│ ──► Dashboard / DRE / Cash Flow
                              └──────────────────┘
                                        ▲
   Expense / RecurringExpense ──────────┘   CashRegister (caixa físico:
   (A Pagar; auto-pay job 03:00)             open/close/withdraw/supplement → CashMovement)

   Baixa automática cartão: AutoSettleCardInstallmentsJob (03:30) baixa parcelas
   de cartão com PaymentMethod.settlement_mode='on_due_date' vencendo hoje.

   Estorno: RefundPayment estorna o PaymentReceipt (devolução real ou PatientCredit).
   Fechamento: PeriodClosure (append-only) bloqueia edição retroativa → 423 Locked.
   Gateway: Webhooks::Financial::Asaas (público, HMAC; 403 constante anti-enumeração).
```

### Modelos centrais

| Modelo | Papel |
|---|---|
| [`Budget`](app/models/financial/budget.rb) | Orçamento/plano aprovado. `origin`: `orcamento`/`plano_tratamento`/`mensalidade`/`mensalidade_recorrente`. Status `rascunho→enviado→aprovado→concluido`/`cancelado`. |
| [`BudgetItem`](app/models/financial/budget_item.rb) | Item do orçamento. `unit_amount_cents` é snapshot imutável do preço na aprovação. |
| [`Installment`](app/models/financial/installment.rb) | Parcela a receber. `amount_cents`/MDR são `frozen_attributes`. Status `pendente`/`parcial`/`recebido`/`vencido`/`cancelado`. |
| [`PaymentReceipt`](app/models/financial/payment_receipt.rb) + `PaymentReceiptItem` | Recibo de recebimento (juros/multa/desconto/crédito aplicado). |
| [`Entry`](app/models/financial/entry.rb) | Movimentação do Fluxo de Caixa (manual + automática). Alimenta DRE/Dashboard. |
| [`Expense`](app/models/financial/expense.rb) / [`RecurringExpense`](app/models/financial/recurring_expense.rb) | A Pagar avulsa / recorrente (motor de despesas fixas). |
| [`RecurringBilling`](app/models/financial/recurring_billing.rb) | Mensalidade fixa — gera `Budget`+`Installment` por período (frequência mensal→anual). |
| [`CashRegister`](app/models/financial/cash_register.rb) / `CashMovement` | Caixa físico (abertura/fechamento/sangria/suprimento). |
| [`CommissionRule`](app/models/financial/commission_rule.rb) / `CommissionEntry` | Regra e lançamento de comissão por profissional. |
| [`PaymentMethod`](app/models/financial/payment_method.rb) / `PaymentMethodFee` | Forma de pagamento + taxas versionadas (sem update — só create+deactivate). |
| [`ServicePricing`](app/models/financial/service_pricing.rb) | Preço 1-to-1 com `AgendaService` (preço/DRE/comissão; nome/duração ficam na Agenda). |
| [`AgentProfile`](app/models/financial/agent_profile.rb) | Perfil financeiro 1-to-1 com `User` (profissional). |
| [`DreCategory`](app/models/financial/dre_category.rb) | Hierarquia do Plano de Contas. Canon semeado por conta nova (`BootstrapAccountJob`). |
| [`PeriodClosure`](app/models/financial/period_closure.rb) | Fechamento contábil append-only (`closed`/`reopened`). |
| [`PatientCredit`](app/models/financial/patient_credit.rb) | Crédito do paciente (estorno como crédito / pré-pagamento). |
| [`Refund`](app/models/financial/refund.rb) | Registro de estorno (via `RefundPayment`). |
| [`GatewaySetting`](app/models/financial/gateway_setting.rb) / `GatewayWebhookEvent` | Config Asaas + fila de eventos de webhook. |
| [`AuditLog`](app/models/financial/audit_log.rb) / [`IdempotencyKey`](app/models/financial/idempotency_key.rb) | Trilha de auditoria + idempotência server-side. |

## Recursos / controllers (28)

Todos sob `Api::V1::Accounts::Financial::*`, prefixo de rota `financial/v2/*`
(ver [`config/routes.rb`](../../config/routes.rb)). O webhook fica fora do namespace
autenticado (`Webhooks::Financial::*`).

| Recurso (rota base) | Controller | Ações principais |
|---|---|---|
| `setup` | `SetupController` | `show`, `complete_step` |
| `categories` | `DreCategoriesController` | CRUD, `restore_defaults` |
| `bank_accounts` | `BankAccountsController` | CRUD, `transfer` |
| `commission_rules` | `CommissionRulesController` | CRUD |
| `commission_entries` | `CommissionEntriesController` | `pay`, `bulk_pay` |
| `recurring_expenses` | `RecurringExpensesController` | CRUD |
| `recurring_billings` | `RecurringBillingsController` | CRUD, `pause`/`resume`/`cancel` |
| `revenue_goals` | `RevenueGoalsController` | CRUD, `upsert` |
| `gateway_setting` | `GatewaySettingsController` | `show`, `update` |
| `budgets` | `BudgetsController` | CRUD, `approve`/`cancel`, `update_installments`, `simulate_plan` |
| `installments` | `InstallmentsController` | `index`/`by_patient`, `pay`/`refund`, `charge_whatsapp`, `upload_proof`/`proof_url` |
| `payment_receipts` | `PaymentReceiptsController` | `index`/`create`/`show`, `refund` |
| `entries` | `EntriesController` | CRUD, `bulk_reclassify` |
| `expenses` | `ExpensesController` | CRUD, `pay`/`reverse` |
| `cash_registers` | `CashRegistersController` | `open`/`close`/`reopen`, `withdraw`/`supplement` |
| `patient_credits` | `PatientCreditsController` | `index`, `create` |
| `audit_logs` | `AuditLogsController` | `index`, `export_csv` |
| `backups` | `BackupsController` | `index`, `run`, `destroy` |
| `lgpd_requests` | `LgpdRequestsController` | CRUD-ish, `approve`/`reject`/`execute`/`cancel` |
| `payment_methods` | `PaymentMethodsController` | CRUD, `simulate_fee`, `rename_provider`, `destroy_provider` |
| `payment_methods/:id/fees` | `PaymentMethodFeesController` | `index`/`create`/`show`, `deactivate` |
| `service_pricings` | `ServicePricingsController` | `index`/`show`, `upsert` (PUT/PATCH), `deactivate` |
| `agent_profiles` | `AgentProfilesController` | `index`/`show`, `upsert`, `deactivate` |
| `period_closures` | `PeriodClosuresController` | `index`/`show`/`create`, `reopen` |
| `reports` | `ReportsController` | `dre`, `cash_flow`, `dashboard`, `commissions` + ~20 charts/exports |
| `patients/:id/summary` | `PatientSummariesController` | `show` (aba do paciente) |
| `patients/:id/timeline` | `PatientTimelinesController` | `show` (aba do paciente) |
| `webhooks/financial/asaas` | `Webhooks::Financial::AsaasController` | `receive` (público, HMAC) |

## RBAC (real, via `BaseController`)

RBAC Klivy é o único sistema de permissões. O `BaseController` mapeia 5 presets
canon → `klivy_role.preset_key` (`ROLE_PRESETS`):

| Preset | preset_keys aceitos |
|---|---|
| `ADMIN` | `admin`, `administrator`, `dono` (+ `account_user.administrator?`) |
| `GERENTE` | `gerente`, `coordenador` |
| `RECEPCAO` | `recepcao`, `recepcionista` |
| `DENTIST` | `dentista`, `profissional` |
| `AUDITOR` | `auditor`, `contador` |

`super_admin` e `administrator` nativo da conta têm bypass. Helpers de gate
(`require_role!`/`authorize_write!`/`authorize_admin!`) chamam `user_has_any_role?`
e, quando negam, gravam `AuditLog` `action: 'denied'` e retornam **403**
`{ error: 'forbidden', required_roles: [...] }`.

Matriz real (resumo):

| Ação | Roles exigidos |
|---|---|
| `reports/*`, dashboard, DRE | GERENTE / ADMIN / AUDITOR |
| accountant_export | ADMIN / AUDITOR |
| `audit_logs`, `backups` | ADMIN / AUDITOR (`require_admin_or_auditor!`) |
| `commission_rules`, `gateway_setting`, `agent_profiles` (write) | ADMIN |
| `period_closures` create/reopen | ADMIN |
| `revenue_goals`, `recurring_expenses` (write) | GERENTE+ (`require_manager!`) |
| `bank_accounts`/`categories`/`payment_methods`/`payment_method_fees`/`service_pricings`/`patient_credits` (write) | GERENTE / ADMIN |
| `bank_accounts#destroy`, `categories#destroy`/`restore_defaults` | ADMIN |
| `budgets#approve` | ADMIN; create/update GERENTE+; `simulate_plan` RECEPCAO/GERENTE/ADMIN/DENTIST |
| `expenses`/`cash_registers`/`payment_receipts`/`recurring_billings` (write) | RECEPCAO / GERENTE / ADMIN |
| `lgpd_requests` | index/show ADMIN/AUDITOR; create ADMIN/GERENTE; approve/reject/execute/cancel ADMIN |

### Aba financeira do paciente

`PatientSummariesController` e `PatientTimelinesController` (endpoints exclusivos
da aba do prontuário) são gateados por `ensure_view_patient_financial!`, que checa
**`patients.view_financial`** via `beclinic_can?` — a MESMA permission que o
frontend usa pra renderizar a aba. **NUNCA usar `financial.*` aqui**: essas perms
gateiam o módulo standalone (sidebar/dashboard), não o financeiro de UM paciente.
Recepção/SDR podem ter `financial.view_dashboard` sem `patients.view_financial`.

### Alertas (endpoints sem gate de role)

Auditável e intencional documentar:

- **`installments#pay` / `installments#refund`** — só `set_installment` antes; NÃO
  exigem `require_role!`. Qualquer usuário autenticado com setup completo recebe/
  estorna parcela (decisão: simplificar a aba do paciente). A baixa real continua
  passando por `ReceivePayment`/`RefundPayment` (idempotência + auditoria).
- **`entries` create/update/destroy** — só `set_entry`; sem `require_role!`.
  Lançamento manual de caixa não tem gate de role hoje.
- **`payment_methods#rename_provider`** — NÃO está no `before_action :authorize_write!`
  (que cobre só `create`/`update`/`destroy`); diferente de `destroy_provider`, que
  chama `authorize_write!` no corpo. Rename de alias de provedor roda sem gate de role.

> Revisar esses três ao endurecer o RBAC do módulo.

## Jobs (`config/schedule.yml`)

| Job | Cron (UTC) | Função |
|---|---|---|
| `Financial::RecurringExpensesCronJob` | `0 2 * * *` (02:00) | Propaga despesas recorrentes → gera `Expense`. |
| `Financial::GenerateRecurringBillingsJob` | `30 2 * * *` (02:30) | Gera `Budget`+`Installment` de cada `RecurringBilling` com `next_generation_at <= hoje`. Roda ANTES do auto-settle. |
| `Financial::AutoPayDueExpensesJob` | `0 3 * * *` (03:00) | Paga despesas vencendo com `auto_pay=true`. Falha → `Expense.metadata.auto_pay_error`. |
| `Financial::BackupJob` | `0 3 * * *` (03:00) | Dump comprimido em `FINANCIAL_BACKUP_PATH`, retenção 30 dias (F-32). |
| `Financial::AutoSettleCardInstallmentsJob` | `30 3 * * *` (03:30) | Baixa automática de parcelas de cartão com `settlement_mode='on_due_date'` vencendo hoje. |
| `Financial::Webhooks::ProcessAsaasEventJob` | event-driven | Processa `GatewayWebhookEvent` recebido do webhook Asaas (atualiza Installment/Receipt/Entry). |

Auxiliares (sob demanda): `Financial::BootstrapAccountJob` (semeia DRE canon em
conta nova), `Financial::AuditLogJob`/`AuditLogsExportJob`.

### Baixa automática de cartão (`settlement_mode`)

Política por forma de pagamento — sem gateway integrado. `settlement_mode`:
`manual` | `on_confirm` | `on_due_date`. O operador já passou o cartão na
maquininha = confirmação; a adquirente garante o repasse. Guardrail no model:
`on_due_date` **só** para crédito/débito — boleto/convênio/parcelamento_proprio
NUNCA, porque nesses a clínica assume o risco. Sem conta destino → fica pendente
e tenta no dia seguinte (só loga warn). Marca `auto_settled` para conciliação.

## Integrações

| Domínio | Ponto de integração |
|---|---|
| **Pacientes** | `Budget`/`Installment`/`RecurringBilling` `belongs_to :patient`. Aba do prontuário via `PatientSummaries`/`PatientTimelines` (gate `patients.view_financial`). |
| **Agenda** | `ServicePricing` 1-to-1 com `AgendaService` (unique no banco) — preço/DRE/comissão aqui; nome/duração na Agenda. Sem `ServicePricing`, o serviço não pode ser lançado financeiramente. |
| **Usuários** | `AgentProfile` 1-to-1 com `User` (rota usa `user_id` como `:id`); `professional`/`approved_by`/comissões referenciam `User`. |
| **Migração Clinicorp** | Importação de clínicas legadas via `/super_admin/migrations` (Budget guarda `metadata.legacy_id` para preservar o número visível). |
| **Active Storage (R2)** | Comprovantes (`installment.payment_proof`) e backups; URLs assinadas (15 min), blobs scoped por `accounts/<id>/`. Upload de comprovante valida MIME (PDF/JPG/PNG/WEBP) e tamanho (10MB). |
| **Gateway Asaas** | Webhook público `POST /webhooks/financial/asaas?account_id=:id`, verificado por HMAC (`asaas-access-token`). Anti-enumeração: **403 constante** em qualquer pré-condição falha; replay protection por `event_id` único. Processamento assíncrono. |

## Documentação

- Canon do produto: [`docs/01-product/modules/financeiro-funcionamento.md`](../../docs/01-product/modules/financeiro-funcionamento.md)
- OpenAPI consolidado: [`swagger/plugins_index.yml`](../../swagger/plugins_index.yml) (tags `Financeiro · *`)
- Multi-tenancy: [AGENTS.md → Multi-tenancy](../../AGENTS.md)
