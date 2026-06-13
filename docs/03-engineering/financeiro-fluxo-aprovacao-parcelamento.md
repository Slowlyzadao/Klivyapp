# Fluxo Financeiro de Aprovação e Parcelamento — Auditoria e Plano de Execução

> Doc de planejamento e auditoria do fluxo completo Plano de Tratamento → Orçamento → Parcelamento → Recebimento → Estorno do módulo financeiro V2 do Klivy/Salus.
>
> Cobre: auditoria do que existe hoje (modelos, services, controllers, frontend, RBAC), gaps reais (UX wizard + 1 endpoint + alinhamento RBAC), proposta de implementação, plano de rollout em 6 fases, checklists de QA/regressão, observabilidade.
>
> **Última atualização:** 2026-05-26
> **Versão do módulo:** 1.8.0.17
> **Status:** Planejamento aprovado. Implementação não iniciada.
> **Canon de referência:** [docs/01-product/modules/financeiro-funcionamento.md](../01-product/modules/financeiro-funcionamento.md), [AGENTS.md](../../AGENTS.md), [CHANGELOG.md](../../CHANGELOG.md)

---

## 0. Como ler este documento

- **Seções 1-6** são auditoria factual: o que existe hoje no código, com paths e linhas.
- **Seções 7-15** são a proposta: modelagem, endpoints, services, estratégia transacional, idempotência, auditoria, testes.
- **Seções 16-20** são execução: rollout, QA, regressão, observabilidade, monitoração.
- **Premissa central:** a base V2 (reescrita 2026-05-07 a 2026-05-25) já cobre ~90% do que parece faltar. Os gaps reais são UX (wizard de configuração de pagamento), um endpoint de simulação de taxa, e alinhamento RBAC.

---

## 1. Auditoria da estrutura atual

### 1.1 Estado da arquitetura — V1 morto, V2 vivo

- **V1 removido em 2026-05-22** (migration `20260522100001_drop_legacy_financial_tables.rb`). Tabelas `transactions`, `account_transactions`, `installments` (global), `financial_estimates` continuam fisicamente no banco; serão dropadas em Fase B.
- **Canon V2 ativo:** namespace `Financial::*`, tabelas `financial_*`, BIGINT cents, [Financial::ApplicationRecord](../../plugins/financial/app/models/financial/application_record.rb) com `SoftDeletable + Auditable + Stamped + MoneyAttribute` e multi-tenant enforce.
- AGENTS.md seção "Financial module v2" formaliza o padrão.

### 1.2 Inventário de modelos (34) em [plugins/financial/app/models/financial/](../../plugins/financial/app/models/financial/)

| Domínio | Modelos | Tabela | Frozen attrs / Imutabilidade |
|---|---|---|---|
| Receita | `Budget`, `BudgetItem`, `Installment`, `PaymentReceipt`, `PaymentReceiptItem`, `Refund` | `financial_budgets`, `financial_budget_items`, `financial_installments`, `financial_payment_receipts`, `financial_payment_receipt_items`, `financial_refunds` | `Installment.{amount_cents, payment_method_fee_id, fee_percent_basis_points, fee_fixed_cents}`; `Refund` 100% imutável após criação |
| Despesa | `Expense`, `RecurringExpense` | `financial_expenses`, `financial_recurring_expenses` | — |
| Ledger | `Entry` (dual-date competência/caixa, source polimórfico) | `financial_entries` | Imutável total — correção = Entry reverso (estorno_*) + novo |
| Caixa | `CashRegister`, `CashMovement` | `financial_cash_registers`, `financial_cash_movements` | — |
| Pagamento | `PaymentMethod`, `PaymentMethodFee` | `financial_payment_methods`, `financial_payment_method_fees` | `PaymentMethod.kind`; `PaymentMethodFee` 100% imutável (deactivate em vez de update) |
| Comissão | `CommissionRule`, `CommissionEntry` | `financial_commission_rules`, `financial_commission_entries` | `CommissionEntry.{installment_id, rule_id, base_amount_cents, mdr_deduction_cents, lab_deduction_cents, calc_base_cents, competence_date}` |
| Conta | `BankAccount` | `financial_bank_accounts` | — (saldo nunca armazenado) |
| Plano de contas | `DreCategory` (hierárquica até 4 níveis, materialized path) | `financial_dre_categories` | `system_default` impede rename/move/delete |
| Auditoria | `AuditLog` (async via `Financial::AuditLogJob`), `IdempotencyKey` (24h TTL) | `financial_audit_logs`, `financial_idempotency_keys` | self-audit desabilitada |
| Crédito | `PatientCredit` | `financial_patient_credits` | — |
| Setup | `SetupState`, `AgentProfile` (CPF encrypted), `ServicePricing`, `RevenueGoal`, `GatewaySetting` (api_key/webhook_secret encrypted) | respectivas `financial_*` | — |
| Governança | `PeriodClosure` | `financial_period_closures` | bloqueia escrita retroativa em período fechado |

### 1.3 Inventário de services (32) em [plugins/financial/app/services/financial/](../../plugins/financial/app/services/financial/)

| Service | Capacidade | Suporta hoje? |
|---|---|---|
| [`ApproveBudget`](../../plugins/financial/app/services/financial/approve_budget.rb) | Aprova budget; aceita `installments_plan` custom (array de hashes com `amount_cents`, `due_date`, `payment_method`, `payment_method_id`, `professional_id` por parcela); provisiona comissão; sincroniza com gateway | **✅ split heterogêneo já existe** |
| [`ReceivePayment`](../../plugins/financial/app/services/financial/receive_payment.rb) | Multi-installment no mesmo PaymentReceipt; baixa parcial (BUG-01) gera installment-filha com `replaces_installment_id`; modifiers juros/multa/desconto em fixo ou %; aplicação de crédito do paciente; lock pessimista sort_by(&:id); freeze de fee snapshot CRIT-CALC-01; commission provisionada→devida | ✅ |
| [`RefundPayment`](../../plugins/financial/app/services/financial/refund_payment.rb) | Estorno proporcional CRIT-SVC-05 com `refund_proportion_bps`; reversão de comissão proporcional via nova entry negativa; opção `as_credit` para virar PatientCredit | ✅ |
| [`EditApprovedBudget`](../../plugins/financial/app/services/financial/edit_approved_budget.rb) | BUG-02: edita parcelas pendentes (valor/data/método); bloqueia recebidas; `cancel` propaga aos installments pendentes | ✅ |
| `Commissions::GenerateCommission` | Resolve regra mais específica por (professional, date, procedure, specialty, category); snapshot frozen | ✅ |
| `Governance::ClosePeriod` / `ReopenPeriod` | Bloqueio retroativo (423 Locked) com motivo obrigatório no reopen | ✅ |
| `TransferBetweenAccounts` | Entry dupla com `transfer_pair_id`, `affects_dre=false`, `affects_cashflow=true` | ✅ |
| `GenerateRecurringExpenses` | Cron diário 00:01, próximos 35 dias, idempotente | ✅ |
| Reports (10x) | DRE, Cash Flow, Account Statement, Commissions, Revenue by Professional/Procedure/Payment Method, Expenses by Category, Goals vs Actual, Ticket Médio, Convênio, Accountant Export | ✅ |

### 1.4 Controllers em [plugins/financial/app/controllers/api/v1/accounts/financial/](../../plugins/financial/app/controllers/api/v1/accounts/financial/) (25)

- [base_controller.rb](../../plugins/financial/app/controllers/api/v1/accounts/financial/base_controller.rb) com `IdempotentAction`, `ensure_account`, error handling (`PeriodClosed → 423`, `TenantMismatch → 403`, `FrozenAttributeError → 422`, `IdempotencyMismatch → 422`)
- Endpoints críticos do fluxo:
  - `POST /budgets/:id/approve` — aceita `installments_plan` heterogêneo
  - `POST /budgets/:id/cancel`
  - `PATCH /budgets/:id/update_installments` — BUG-02
  - `POST /installments/:id/pay` — multi-modifier, partial
  - `POST /installments/:id/refund` — proporcional
  - `POST /payment_methods/:id/fees` — versionada (sem update; só create + deactivate)
  - `GET /patients/:patient_id/timeline` — view consolidada

### 1.5 Frontend V2 em [plugins/financial/frontend/features/financial/v2/](../../plugins/financial/frontend/features/financial/v2/)

- **14 páginas:** DashboardV2, ReceivablesV2, PayablesV2, CashFlowV2, DreV2, CommissionsV2, CashRegisterV2, SettingsV2, ReportsHubV2, AccountantExportV2, ReclassifyV2, LgpdV2, BackupsV2, AuditLogsV2
- **47 componentes** entre modais, charts, settings tabs, reports
- **State management:** sem Vuex/Pinia. Composables (`useFinancialData`, `useFinancialTimeline`, `useFinancialActions`, `useMoney`, `useInstallmentBreakdown`) + axios direto via [financialV2.js](../../plugins/financial/frontend/features/financial/v2/api/financialV2.js)
- Modais relevantes ao fluxo de aprovação/recebimento:
  - [ReceivePaymentModalV2.vue](../../plugins/financial/frontend/features/financial/v2/components/ReceivePaymentModalV2.vue) — multi-installment, partial, modifiers, credit
  - [BudgetFormModalV2.vue](../../plugins/financial/frontend/features/financial/v2/components/BudgetFormModalV2.vue) — orçamento avulso com custom installment plan
  - [PaymentMethodFeeFormModalV2.vue](../../plugins/financial/frontend/features/financial/v2/components/settings/PaymentMethodFeeFormModalV2.vue) — taxas versionadas

### 1.6 Aba financeira do paciente

- [FinancialTab.vue](../../plugins/patients/frontend/routes/patients/tabs/FinancialTab.vue) é o container; renderiza [FinancialKpiGrid](../../plugins/patients/frontend/features/patient-record/components/financial-tab/FinancialKpiGrid.vue) + [FinancialTimeline](../../plugins/patients/frontend/features/patient-record/components/financial-tab/FinancialTimeline.vue) (628 linhas, substitui 4 sub-abas legadas) + 7 modais contextuais.
- Composable [useFinancialActions.js](../../plugins/patients/frontend/features/patient-record/composables/useFinancialActions.js) expõe `pay/refund/approveEstimate/cancelEstimate/editInstallment/createEstimate/uploadProof`.
- Endpoint [`GET /financial/v2/patients/:patient_id/timeline`](../../plugins/financial/app/controllers/api/v1/accounts/financial/patient_timelines_controller.rb) agrega budgets+installments+credit on-demand (não há entidade `PatientTimelineEvent`).

---

## 2. Problemas encontrados

| # | Severidade | Problema | Evidência |
|---|---|---|---|
| **P1** | 🔴 Alta | UX de aprovação financeira reduzida a 2 botões ("Aprovar orçamento" / "Cancelar orçamento") sem permitir configurar entrada/parcelas heterogêneas/forma diferente por parcela na hora da aprovação | [FinancialTimeline.vue:403-417](../../plugins/patients/frontend/features/patient-record/components/financial-tab/FinancialTimeline.vue) chama `approveEstimate(id)` sem payload de plano custom; backend já aceita `installments_plan` |
| **P2** | 🔴 Alta | Não existe endpoint de simulação de taxa em tempo real — operador escolhe método+parcelas sem ver bruto×líquido×fee | `GET /payment_methods/:id/simulate_fee` inexistente; [`PaymentMethodFee#calculate_fee_cents`](../../plugins/financial/app/models/financial/payment_method_fee.rb) só é chamado dentro de `ReceivePayment#freeze_payment_fee_snapshot!` |
| **P3** | 🟡 Média | Desalinhamento RBAC: frontend declara 14 perms granulares (`approve_estimate`, `manage_estimates`, `create_transaction`…), backend usa role presets (`RECEPCAO/DENTIST/GERENTE/ADMIN/AUDITOR`) via `require_role!` | [plugins/custom_roles/frontend/shared/modules.js:216-233](../../plugins/custom_roles/frontend/shared/modules.js) vs [base_controller.rb](../../plugins/financial/app/controllers/api/v1/accounts/financial/base_controller.rb); memory rbac_klivy_only exige KlivyRole como única fonte |
| **P4** | 🟡 Média | `installments/:id/pay` sem `require_role!` no controller — qualquer autenticado consegue baixar parcela | Mitigação atual = gate frontend `v-can="['financial','create_transaction']"` em defesa em profundidade |
| **P5** | 🟢 Baixa | `Patients::TreatmentPlanBudgetCreator` cria budget com `installments_count: 1` default; informação de comissão per-item perdida (recuperável depois via `CommissionRule#most_specific_for`) | [treatment_plan_budget_creator.rb:43-49](../../plugins/patients/app/services/patients/treatment_plan_budget_creator.rb) |
| **P6** | 🟢 Baixa | i18n: strings financeiras V2 hardcoded em PT-BR; nenhum `pt_BR.yml` em [plugins/financial/config/locales/](../../plugins/financial/config/locales/) | AGENTS.md FE-16/17 do audit 2026-05-18 já registra migração incremental |
| **P7** | 🟢 Baixa | Asaas adapter é skeleton — webhook funcional, mas integração de criação de cobranças não-finalizada | [plugins/financial/lib/financial/gateways/asaas.rb](../../plugins/financial/lib/financial/gateways/asaas.rb); Manual é default |
| **P8** | 🟡 Média | Aba financeira do paciente: backend computa `actions_available` mas não checa permissão correspondente — frontend mostra botão "Aprovar" se backend mandou na lista | Risco de UX inconsistente se rule muda |

**Não-problemas frequentemente assumidos (confirmados que JÁ EXISTEM):**

- ❌ "Não existe split de pagamento" → existe via `installments_plan` no ApproveBudget
- ❌ "Não existe taxa automática" → existe via PaymentMethodFee + freeze no Installment
- ❌ "Não existe auditoria" → existe automática via concern `Auditable` + AuditLogJob
- ❌ "Não existe idempotência" → existe via IdempotentAction concern + header `Idempotency-Key`
- ❌ "Não existe atomicidade transacional" → existe; ReceivePayment todo em transação + lock pessimista (CRIT-SVC-06)
- ❌ "Não existe valores em centavos" → existe; BIGINT + MoneyAttribute + split helper distribuindo resto na última parcela
- ❌ "Não existe multi-tenancy" → existe; `Financial::ApplicationRecord` força `account_id` + scope `for_account`

---

## 3. Riscos de regressão

| Área | Risco | Mitigação |
|---|---|---|
| **PaymentReceipt + Entry imutáveis** | Adicionar campo em `Installment` ou `Entry` exige migration cuidadosa (frozen_attributes) | Novos atributos NÃO devem entrar em frozen_attributes inicialmente; congelar só depois de estabilizar |
| **AuditLog volume** | Cada save de Installment/Budget/Entry gera AuditLog async; uma aprovação com 24 parcelas = ~25-30 logs | Já mitigado por `AuditLogJob` async; monitorar queue `default` durante rollout |
| **Lock pessimista em ReceivePayment** | Multi-parcela com `installment.lock!` + `sort_by(&:id)` para evitar deadlock | Manter ordem; não tocar |
| **PaymentMethodFee exclusion constraint** | GIST `no_overlapping_payment_method_fees` impede sobreposição de vigência ativa | Frontend já tem flow "inativar antiga → criar nova"; manter |
| **Period Closure** | Adicionar feature que escreve em período fechado quebra com 423 | Toda nova feature DEVE invocar `period_not_closed` (já em ApplicationRecord) |
| **Migration de `installments_plan` no frontend** | Hoje `approveEstimate(estimateId)` chama POST sem payload; mudar contrato precisa não quebrar callers existentes | Param `installments_plan` opcional; sem param → usa `installments_count` do budget (comportamento atual preservado) |
| **TreatmentPlanBudgetCreator FORA da transaction clínica** | Falha na criação de budget deixa PT aprovado sem orçamento | Já registra warning; manter pra não acoplar clínico↔financeiro |
| **CommissionEntry estorno proporcional** | CRIT-SVC-05 resolvido via entry negativa | Adicionar teste "estornar estorno" |
| **Gateway Asaas webhook out-of-order** | Pode flipar status | `Idempotency-Key` derivado de event_id + dedupe via `gateway_webhook_events` |

---

## 4. Mapa de dependências

```
                        ┌─────────────────────────────┐
                        │  KlivyRole (RBAC)           │
                        │  - financial.view_*         │
                        │  - financial.create_*       │
                        │  - financial.approve_*      │
                        │  - financial.manage_*       │
                        └──────────────┬──────────────┘
                                       │
                ┌──────────────────────┼──────────────────────┐
                │                      │                      │
                ▼                      ▼                      ▼
┌─────────────────────┐   ┌─────────────────────┐   ┌─────────────────────┐
│ plugins/patients    │   │ plugins/financial   │   │ plugins/financial   │
│  TreatmentPlan      │   │  Financial::Budget  │   │  Financial::        │
│  TreatmentItem      │   │  + items            │   │   PaymentMethod     │
│                     │   │                     │   │   PaymentMethodFee  │
│  ApproveTreatmentP. │──▶│  approve →          │◀──│   (versionada)      │
│  ↓                  │   │   ApproveBudget     │   └─────────────────────┘
│  TreatmentPlanPdfG. │   │   ↓ installments[]  │
└─────────────────────┘   │   ↓ commission      │
                          │   ↓ gateway sync    │
                          └──────────┬──────────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              │                      │                      │
              ▼                      ▼                      ▼
   ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
   │ Financial::      │   │ Financial::      │   │ Financial::      │
   │  Installment     │   │  CommissionEntry │   │  GatewayAdapter  │
   │  (frozen amount) │   │  (provisionada)  │   │  Manual / Asaas  │
   │  + fee snapshot  │   │  (snapshot)      │   │  create_charge() │
   └────────┬─────────┘   └────────┬─────────┘   └──────────────────┘
            │                      │
            │ pay → ReceivePayment │
            ▼                      ▼
   ┌──────────────────────────────────────────┐
   │ Financial::ReceivePayment (transactional) │
   │  1. Lock pessimista + reload              │
   │  2. Freeze fee snapshot (CRIT-CALC-01)    │
   │  3. Update Installment.received_amount    │
   │     (parcial → status='parcial' + nova    │
   │      installment com replaces_installment)│
   │  4. Create PaymentReceipt + Items         │
   │  5. Create Financial::Entry (in, receita) │
   │  6. Update CommissionEntry → devida       │
   │  7. Apply PatientCredit (abatimento)      │
   │  8. Excess → PatientCredit (+)            │
   │  9. Update Budget status (concluído)      │
   │  10. AuditLog async                       │
   │  11. Timeline refresh (view computada)    │
   └──────┬──────────┬──────────┬──────────────┘
          │          │          │
          ▼          ▼          ▼
   ┌──────────┐ ┌──────────┐ ┌──────────────┐
   │ Entry    │ │ Patient  │ │ BankAccount  │
   │ (ledger) │ │ Credit   │ │ balance      │
   │  ↓ DRE   │ │ ledger   │ │ (calculated) │
   │  ↓ Cash  │ └──────────┘ └──────────────┘
   │  Flow    │
   └──────────┘
```

**Bloqueadores transversais** (sempre antes de escrita):

- `Current.account` definido (Chatwoot middleware via `/api/v1/accounts/:account_id/...`)
- `Financial::CurrentUser.id` setado (concern `Stamped`)
- `PeriodClosure.closed_for?` retorna `false` para `competence_date`/`cash_date`
- `IdempotencyKey` resolve no controller via header `Idempotency-Key`
- `CashRegister` aberto se método = dinheiro

---

## 5. Fluxograma atual

```
DENTISTA                RECEPÇÃO                  SISTEMA
   │                       │                         │
   ├─ Cria PT              │                         │
   │  (TreatmentPlan       │                         │
   │   status='proposto')  │                         │
   │                       │                         │
   ├─ Aprova PT clínico    │                         │
   │  PATCH /treatment_    │                         │
   │   plans/:id/approve   │                         │
   │                       │                         │
   │      (transação)─┐    │                         │
   │      PT='aprovado'│   │                         │
   │      Items='aprov'│   │                         │
   │      GeraPDF       │   │                         │
   │                  ─┘   │                         │
   │                       │                         │
   │      (fora transação) │                         │
   │      TreatmentPlanBudgetCreator                 │
   │      ↓                │                         │
   │      Financial::Budget(status='rascunho')       │
   │      + BudgetItems (copy do PT)                 │
   │      + treatment_plan_id link                   │
   │                       │                         │
   │                       │ Vê na aba Financeiro    │
   │                       │ "Precisa aprovação"     │
   │                       │ + total + 2 botões      │
   │                       │                         │
   │                       ├─ Clica "Aprovar"        │
   │                       │  POST /budgets/:id/     │
   │                       │       approve           │
   │                       │  payload: { } ← VAZIO   │
   │                       │                         │
   │                       │     ApproveBudget       │
   │                       │     ↓                   │
   │                       │     Gera N installments │
   │                       │     iguais com método   │
   │                       │     do budget (1 forma) │
   │                       │     Comissão            │
   │                       │     provisionada        │
   │                       │     Gateway sync        │
```

**Limitação visível:** botão "Aprovar" envia payload vazio → backend cai em "distribui em N iguais com forma única". Toda a infra para entrada+parcelas com formas distintas existe (`installments_plan` aceito em `ApproveBudget#call`), mas a UI não usa.

---

## 6. Fluxograma novo

```
DENTISTA                RECEPÇÃO                  SISTEMA
   │                       │                         │
   ├─ Cria PT              │                         │
   ├─ Aprova PT clínico    │                         │
   │  ↓                    │                         │
   │  Budget(rascunho)     │                         │
   │                       │                         │
   │                       │ Aba Financeiro mostra   │
   │                       │ orçamento "Precisa      │
   │                       │ aprovação" com 1 botão  │
   │                       │ "Configurar pagamento"  │
   │                       │                         │
   │                       ├─ Abre wizard            │
   │                       │  PaymentPlanWizardV2    │
   │                       │  Step 1: Resumo         │
   │                       │  Step 2: Desconto       │
   │                       │  Step 3: Modo           │
   │                       │   ├─ Uniforme           │
   │                       │   ├─ Entrada+Restante   │
   │                       │   └─ Customizado split  │
   │                       │  Step 4: Parcelas       │
   │                       │   (PaymentSplitBuilder) │
   │                       │   • Linha por parcela   │
   │                       │   • valor, data, método │
   │                       │   • taxa auto-calc      │
   │                       │     via simulate_fee    │
   │                       │   • InstallmentPreview  │
   │                       │     bruto × líquido     │
   │                       │   • NetAmountCard       │
   │                       │     total + comissão    │
   │                       │  Step 5: Confirma       │
   │                       │   AuditPreview          │
   │                       │                         │
   │                       │  POST /budgets/:id/approve
   │                       │  payload: {             │
   │                       │   installments_plan:[   │
   │                       │     {amount_cents:50000,│
   │                       │      due_date:'today',  │
   │                       │      payment_method:    │
   │                       │      'pix',             │
   │                       │      payment_method_id  │
   │                       │      :1},               │
   │                       │     {amount_cents:30000,│
   │                       │      due_date:'+30d',   │
   │                       │      payment_method:    │
   │                       │      'credito',         │
   │                       │      payment_method_id  │
   │                       │      :7}, ...]          │
   │                       │  }                      │
   │                       │  + Idempotency-Key:UUID │
   │                       │                         │
   │                       │     ApproveBudget       │
   │                       │     (mesmo service, sem │
   │                       │      mudança backend)   │
```

**Backend muda apenas:**
1. **Endpoint novo** `GET /api/v1/accounts/:account_id/financial/v2/payment_methods/:id/simulate_fee?amount_cents=&installments_count=&on_date=`
2. **Endpoint novo** `POST /api/v1/accounts/:account_id/financial/v2/budgets/:id/simulate_plan` (com payload `installments_plan`)
3. **Coluna nova** `Budget.payment_plan` JSONB (intenção original do wizard)
4. **RBAC alignment** atrás de feature flag

---

## 7. Estratégia de migração

**Princípio:** zero migration de dados. Toda a base já está em V2.

| Fase | Escopo | Migrations DB | Feature Flag | Risco |
|---|---|---|---|---|
| **F1: Endpoints backend** | `simulate_fee` (read), `simulate_plan` (read), `Budget.payment_plan` JSONB | 1 migration (add column + GIN index) | Não | Nulo |
| **F2: PaymentPlanWizardV2** | Componente isolado em `plugins/financial/frontend/features/financial/v2/components/wizard/`, modal acionado por botão "Configurar pagamento" | Nenhuma | `payment_plan_wizard_v2` (account_features) | Baixo |
| **F3: Substituir botão "Aprovar orçamento" da aba paciente** | [FinancialTimeline.vue:403-410](../../plugins/patients/frontend/features/patient-record/components/financial-tab/FinancialTimeline.vue) chama wizard quando flag = on | Nenhuma | Flag F2 | Médio (UX-facing) |
| **F4: Expandir wizard para ReceivablesV2 + outros entry points** | Mesmo componente reaproveitado | Nenhuma | Flag F2 | Baixo |
| **F5: RBAC alignment** | Backend `require_role!` substituído por `beclinic_can?(:financial, :perm)` em 25 controllers V2 | Nenhuma | `financial_rbac_strict` | Médio |
| **F6: i18n (opcional)** | Strings PT-BR → keys `FINANCIAL.*`; `plugins/financial/config/locales/pt_BR.yml` | Nenhuma | Não | Baixo |
| **F7: Cleanup Fase B** | Drop tabelas V1 (`transactions`, `account_transactions`, `installments`, `financial_estimates`) | `drop_table` em transação | — | Baixo |

**Sem downtime, sem lock pesado.**

---

## 8. Estratégia de rollback

| Fase | Rollback |
|---|---|
| F1 endpoints | Remove rotas; feature toggle no router. Migration JSONB com `default: {}` é segura (no-op se ausente) |
| F2-F4 wizard | Feature flag `payment_plan_wizard_v2 = false` → UI volta ao botão antigo instantaneamente |
| F5 RBAC | Flag `financial_rbac_strict = false` → controllers caem no path antigo `require_role!`. Manter ambos por 2 semanas |
| F6 i18n | I18n fallback em PT-BR explícito |
| F7 drop | Restaurar de backup R2 ([backup_job.rb](../../plugins/financial/app/jobs/financial/backup_job.rb)); atrasar 90 dias após F1-F6 estáveis |

**Salvaguarda crítica:** toda mutação no fluxo continua transacional + idempotente; rollback de UI nunca pode deixar dado em estado inconsistente porque `ApproveBudget` é atômico por design.

---

## 9. Modelagem proposta

**Sem novos modelos.** Toda modelagem necessária já existe.

**Único ajuste estrutural:** adicionar `Budget.payment_plan` JSONB para guardar a "intenção original do plano" do wizard (auditoria visual). Útil porque depois de edições BUG-02, as parcelas vivas podem divergir do que a recepção configurou originalmente.

```ruby
# db/migrate/2026MMDDHHMMSS_add_payment_plan_to_financial_budgets.rb
class AddPaymentPlanToFinancialBudgets < ActiveRecord::Migration[7.1]
  def change
    add_column :financial_budgets, :payment_plan, :jsonb, default: {}, null: false
    add_index  :financial_budgets, :payment_plan, using: :gin
  end
end
```

**Schema do payload `payment_plan`** (controlled em app code, não na coluna):

```json
{
  "version": "v2",
  "wizard_session_id": "uuid",
  "configured_at": "2026-05-26T15:30:00-03:00",
  "configured_by_id": 123,
  "discount": { "kind": "fixo|percentual", "value_cents": 5000 },
  "installments_plan": [
    {
      "amount_cents": 50000,
      "due_date": "2026-05-26",
      "payment_method": "pix",
      "payment_method_id": 1,
      "professional_id": 42,
      "expected_fee_cents": 0,
      "expected_net_cents": 50000
    },
    {
      "amount_cents": 100000,
      "due_date": "2026-06-26",
      "payment_method": "credito",
      "payment_method_id": 7,
      "professional_id": 42,
      "expected_fee_cents": 3500,
      "expected_net_cents": 96500
    }
  ],
  "totals": {
    "gross_cents": 150000,
    "discount_cents": 0,
    "total_fee_cents": 3500,
    "total_net_cents": 146500,
    "expected_commission_cents": 14650
  }
}
```

**Auditoria:** o `payment_plan` é alterado apenas pelo wizard de aprovação; edições posteriores (BUG-02) tocam só `Installment`. Diff `payment_plan` × installments vivas revela quanto a recepção mexeu após a aprovação inicial.

---

## 10. Endpoints necessários

### Novos

| Método | Rota | Service backend | Resposta |
|---|---|---|---|
| `GET` | `/api/v1/accounts/:account_id/financial/v2/payment_methods/:id/simulate_fee?amount_cents=&installments_count=&on_date=` | Inline (chama `PaymentMethod#fee_for` + `PaymentMethodFee#calculate_fee_cents`) | `{ payment_method_id, installments_count, on_date, fee_percent_basis_points, fee_fixed_cents, fee_amount_cents, net_amount_cents, liquidation_days, expected_liquidation_date }` |
| `POST` | `/api/v1/accounts/:account_id/financial/v2/budgets/:id/simulate_plan` | Novo service `Financial::SimulatePaymentPlan` | `{ plan: [{ row_index, amount_cents, payment_method, payment_method_id, fee_percent_basis_points, fee_fixed_cents, fee_amount_cents, net_amount_cents, expected_liquidation_date, due_date }], totals: { gross_cents, total_fee_cents, total_net_cents, total_expected_commission_cents } }` |

### Existentes (reutilizar sem mudança)

| Rota | Já aceita? |
|---|---|
| `POST /budgets/:id/approve` | ✅ `installments_plan` aceito; só falta frontend enviar |
| `POST /budgets/:id/cancel` | ✅ |
| `PATCH /budgets/:id/update_installments` | ✅ BUG-02 |
| `POST /installments/:id/pay` | ✅ multi-modifier, multi-installment, credit |
| `POST /installments/:id/refund` | ✅ proporcional |
| `GET /financial/v2/patients/:id/timeline` | ✅ |
| `GET /payment_methods/:id/fees` | ✅ |

---

## 11. Services necessários

### Novos

```ruby
# plugins/financial/app/services/financial/simulate_payment_plan.rb
module Financial
  class SimulatePaymentPlan
    def self.call(budget:, installments_plan:)
      new(budget, installments_plan).call
    end

    def initialize(budget, installments_plan)
      @budget = budget
      @plan   = installments_plan
    end

    def call
      rows = @plan.each_with_index.map do |item, idx|
        pm  = Financial::PaymentMethod.find(item[:payment_method_id])
        fee = pm.fee_for(installments_count: 1, on_date: item[:due_date])

        fee_cents = fee ? fee.calculate_fee_cents(item[:amount_cents]) : 0
        net_cents = item[:amount_cents] - fee_cents

        {
          row_index: idx,
          amount_cents: item[:amount_cents],
          payment_method: item[:payment_method],
          payment_method_id: pm.id,
          fee_percent_basis_points: fee&.fee_percent_basis_points || 0,
          fee_fixed_cents: fee&.fee_fixed_cents || 0,
          fee_amount_cents: fee_cents,
          net_amount_cents: net_cents,
          liquidation_days: fee&.liquidation_days || 0,
          expected_liquidation_date: item[:due_date] + (fee&.liquidation_days || 0).days,
          due_date: item[:due_date]
        }
      end

      totals = {
        gross_cents: rows.sum { |r| r[:amount_cents] },
        total_fee_cents: rows.sum { |r| r[:fee_amount_cents] },
        total_net_cents: rows.sum { |r| r[:net_amount_cents] },
        # comissão estimada calculada à parte por CommissionRule#most_specific_for
        total_expected_commission_cents: estimate_commission(rows)
      }

      Financial::ServiceResult.success(plan: rows, totals: totals)
    end

    private

    def estimate_commission(rows)
      # Aplica CommissionRule mais específica do profissional da parcela,
      # base 'recebido_menos_mdr' (canon), sobre net_amount_cents.
      # Pure read, sem efeito colateral.
    end
  end
end
```

### Existentes (reutilizar)

`Financial::ApproveBudget`, `Financial::ReceivePayment`, `Financial::RefundPayment`, `Financial::EditApprovedBudget`, `Financial::Commissions::GenerateCommission`, `Financial::CurrentUser`, `Financial::AuditLogJob`.

---

## 12. Estratégia transacional

**Já implementada e canônica** em `ReceivePayment` e `ApproveBudget`.

Padrão a respeitar em qualquer service novo:

```ruby
ActiveRecord::Base.transaction do
  installments.sort_by(&:id).each(&:lock!)  # ordem fixa anti-deadlock
  installments.each(&:reload)                # snapshot pós-lock (CRIT-SVC-06)

  installments.each do |inst|
    freeze_payment_fee_snapshot!(inst)       # CRIT-CALC-01
    update_received_amount!(inst)
    create_replacement_if_partial!(inst)     # BUG-01
  end

  receipt = create_payment_receipt!
  entry   = create_ledger_entry!             # Financial::Entry frozen
  update_commission_entries!(receipt)
  apply_patient_credit!
  record_excess_as_credit!
  update_budget_status!
end
# AuditLog async via after_commit (Auditable concern)
```

`SimulatePaymentPlan` é leitura pura → dispensa transação. `ApproveBudget` (já existente) já garante atomicidade quando recebe `installments_plan` — nenhuma mudança necessária.

---

## 13. Estratégia de auditoria

**Já automática via [`Financial::Concerns::Auditable`](../../plugins/financial/app/models/financial/concerns/auditable.rb).**

- before_save captura diff JSONB
- after_commit enfileira `Financial::AuditLogJob` (async)
- Excluded columns: `created_at, updated_at, lock_version, gateway_metadata, gateway_synced_at`
- Scrub PII automático: `password, secret, api_key, token, ciphertext`
- frozen_attributes validation impede mutação imutável

**Adições mínimas para o wizard:**

1. Quando wizard aprova budget com `installments_plan`: cada Installment criado gera 1 AuditLog automaticamente (já cobre).
2. Adicionar `metadata.wizard_version = 'v2'` e `metadata.wizard_session_id = <uuid>` no controller que recebe a request — útil para drill-down "quais aprovações vieram do wizard".
3. Persistir `Budget.payment_plan` (seção 9) — fica visível como "intenção original" mesmo após edição BUG-02.

**Eventos cobertos automaticamente:**

- Orçamento criado/aprovado/cancelado
- Parcela criada/editada/cancelada
- Recebimento realizado
- Estorno proporcional
- Comissão provisionada/devida/paga/estornada
- Entry de caixa criado

---

## 14. Estratégia de idempotência

**Já implementada** via [`Financial::IdempotentAction`](../../plugins/financial/app/controllers/concerns/financial/idempotent_action.rb).

- Header `Idempotency-Key` (UUID v4 gerado em [financialV2.js](../../plugins/financial/frontend/features/financial/v2/api/financialV2.js))
- TTL: 24h
- Fingerprint SHA-256 do body
- 2xx/3xx/4xx persistidos; 5xx não (cliente pode retry)
- Mismatch → 409 Conflict

**Frontend wizard contract:**

- Gerar 1 UUID na abertura do wizard, armazenar em `wizardSessionId`
- Toda chamada de simulação NÃO envia key (apenas read)
- Submit final (ApproveBudget) envia `Idempotency-Key: <wizardSessionId>`
- Duplo-clique no "Confirmar" devolve mesma resposta cacheada

---

## 15. Estratégia de testes

| Camada | Cobertura nova | Spec sugerida |
|---|---|---|
| Service `SimulatePaymentPlan` | 4 cenários canon | `spec/services/financial/simulate_payment_plan_spec.rb` |
| Endpoint `simulate_fee` | Multi-tenant, taxa vigente, taxa nula, data fora vigência | `spec/requests/api/v1/accounts/financial/payment_methods_simulate_fee_spec.rb` |
| Endpoint `simulate_plan` | Plan vazio, plan heterogêneo, plan com soma ≠ total budget, plan com data em período fechado | `spec/requests/api/v1/accounts/financial/budgets_simulate_plan_spec.rb` |
| `ApproveBudget` com `installments_plan` | Caso "entrada PIX + 10x crédito" (já cobre, adicionar regressão) | `spec/services/financial/approve_budget_spec.rb` |
| Wizard e2e | Caminho dourado: dentista aprova PT → recepção abre wizard → split → confirma → parcelas com formas diferentes | Cypress ou Playwright |
| Regressão BUG-01 + BUG-02 | Cobertura existente; manter |
| Estorno proporcional | "estornar estorno" e "estornar parcial pós-wizard" | `spec/services/financial/refund_payment_spec.rb` |

Política do projeto (AGENTS.md "Avoid writing specs unless explicitly asked"): testes só nos services novos + endpoint novo + 1 e2e do golden path.

---

## 16. Plano de rollout

| Semana | Entrega | Quem testa | Gate |
|---|---|---|---|
| W0 (hoje) | Este documento | User | Aprovação |
| W1 | F1 endpoint `simulate_fee` + spec | QA interna | Merge sem flag |
| W1 | F1 endpoint `simulate_plan` + service `SimulatePaymentPlan` + spec | QA interna | Merge sem flag |
| W1 | F1 migration `Budget.payment_plan` JSONB | DBA | Merge |
| W2 | F2 wizard frontend isolado (rota oculta de preview) | Dev local | Sem flag |
| W3 | F3 integração wizard na aba do paciente atrás de flag `payment_plan_wizard_v2` | Clínica piloto (1 conta) | Flag ON apenas piloto |
| W4 | Monitorar 7 dias produção piloto | Clínica piloto | Decisão go/no-go |
| W5 | F4 expansão wizard pra ReceivablesV2 e outros entry points | Clínica piloto | Flag ON piloto |
| W6 | F5 RBAC alignment atrás de `financial_rbac_strict` | Clínica piloto | Flag ON piloto |
| W7 | GA — flag ON pra todas contas | Suporte | Decisão final |
| W8-W10 | Estabilização | Suporte | — |
| W12+ | F6 i18n migration (incremental) | — | — |
| W90 | F7 drop tabelas V1 | DBA | Backup verificado |

**Stop conditions:** regressão > 0.1% das aprovações falham; tempo médio de aprovação > 60s; qualquer inconsistência de saldo detectada em audit; reclamação de cliente sobre cobrança duplicada.

---

## 17. Checklist de QA

### Caminho dourado

- [ ] Dentista cria PT com 2 procedimentos (R$ 1.000 cada)
- [ ] Aprova PT clinicamente → PT='aprovado', PDF gerado
- [ ] Aba financeira do paciente mostra orçamento "Precisa aprovação" R$ 2.000
- [ ] Clica "Configurar pagamento" → wizard abre
- [ ] Step 3: escolhe modo "Customizado"
- [ ] Step 4: configura entrada R$ 500 PIX hoje + R$ 500 dinheiro +15d + R$ 1.000 cartão crédito 10x +30d
- [ ] Step 4: vê preview de taxas (Cartão 3.5%) e líquido por parcela
- [ ] Step 4: vê comissão estimada
- [ ] Step 5: confirma → AuditPreview lista 10+3 eventos
- [ ] Submit → toast sucesso, modal fecha
- [ ] Aba financeira refresh: vê 1 entrada + 11 parcelas com formas e datas corretas
- [ ] AuditLogs: 1 budget.update (status), 1 budget.update (approve_at), 12 installment.create
- [ ] `Budget.payment_plan` JSONB persistido com snapshot do wizard

### Edge cases

- [ ] Plan com soma ≠ total budget → 422, modal não fecha
- [ ] Plan com data passada (não em período fechado) → permitido com warning
- [ ] Plan com data em período fechado → 423 Locked
- [ ] Duplo-clique "Confirmar" → mesma resposta (idempotência)
- [ ] PaymentMethod sem fee cadastrada → fee_amount=0, sem erro
- [ ] PaymentMethod inativo → não aparece no select
- [ ] Forma "dinheiro" + caixa fechado → 422 com mensagem
- [ ] Crédito do paciente cobre toda a primeira parcela → forma vira `credito_paciente` automaticamente
- [ ] Concorrência: 2 abas tentam aprovar → 1 sucesso, 1 erro (Idempotency-Key diferente, budget.status mudou)

### Multi-tenant

- [ ] Recepção da conta A tenta acessar budget de conta B → 403
- [ ] AuditLog scopado por `account_id`
- [ ] Toda parcela criada tem `account_id` correto

### Performance

- [ ] Aprovação de plan com 24 parcelas → < 2s response
- [ ] AuditLogJob queue não estoura (medir antes/depois)
- [ ] Simulação de plan com 24 parcelas → < 500ms

---

## 18. Checklist de regressão

| Cenário | Comportamento esperado |
|---|---|
| Aprovar budget sem `installments_plan` (chamada antiga) | Funciona idêntico ao hoje (distribui em N iguais) |
| Aprovar budget com `installments_count=1` | Cria 1 parcela com total do budget |
| Receber parcela parcial (BUG-01) | Gera installment-filha; original vira 'parcial' |
| Editar parcela pendente (BUG-02) | Só pendentes; bloqueia recebidas |
| Estornar pagamento integral | Comissão estornada; saldo -via Entry; status='estornado' |
| Estornar pagamento parcial (CRIT-SVC-05) | CommissionEntry reversa proporcional gerada |
| Aplicar crédito do paciente até cobrir 100% | `payment_method='credito_paciente'` automático |
| Pagar com método cuja fee tem `valid_to` no passado | Fee não encontrada → fee_amount=0 (sem erro) |
| Aprovar budget em período fechado | 423 Locked |
| Receber em caixa fechado (dinheiro) | 422 com mensagem |
| Webhook Asaas → atualiza Installment | Idempotente; reprocesso não duplica |
| ImportExport CSV antigo | Continua funcionando |
| Importação Clinicorp (CHANGELOG 1.8.0.6) | Continua usando ApproveBudget; sem regressão |
| Aba Patient Timeline V2 | Mostra todos os eventos novos; sem entries órfãs |
| Dashboard V2 | Receita líquida agrega Entry.amount como sempre |

---

## 19. Plano de observabilidade / logs

**Logs estruturados** (padrão já existe em [base_controller.rb](../../plugins/financial/app/controllers/api/v1/accounts/financial/base_controller.rb)):

```ruby
Rails.logger.info(
  event: 'financial.budget.approved',
  account_id: budget.account_id,
  budget_id: budget.id,
  installments_count: installments.size,
  payment_methods: installments.pluck(:payment_method).uniq,
  source: params[:metadata]&.dig(:source) || 'legacy', # 'wizard_v2' quando vier
  user_id: current_user.id,
  idempotency_key: request.headers['Idempotency-Key']
)
```

**Métricas a instrumentar** (Sentry custom + StatsD se disponível):

- `financial.budget.approve.duration` (timer)
- `financial.budget.approve.installments_count` (histogram)
- `financial.budget.approve.payment_methods_count` (histogram — quantas formas diferentes por approval)
- `financial.simulate_fee.duration` (timer)
- `financial.receive_payment.lock_wait_time` (timer)
- `financial.audit_log_job.queue_depth` (gauge)

**Alertas críticos:**

1. `financial.budget.approve.error_rate > 1%` em 5min
2. `financial.receive_payment.error_rate > 0.5%` em 5min
3. `financial.audit_log_job.queue_depth > 1000` por 10min
4. Period closure bypass (qualquer 200 OK com data em período fechado)
5. Tenant mismatch events (deve ser 0)

---

## 20. Plano de monitoração financeira

**Dashboards necessários** (Grafana ou similar; se ainda não existem):

| Painel | Métrica | Janela |
|---|---|---|
| Saúde de aprovações | budget.approve rate, error rate, p50/p95/p99 duration | 24h |
| Saúde de recebimentos | installments.pay rate, partial vs full, modifier usage | 24h |
| Saúde de estornos | refund rate, proportional vs full | 7d |
| Comissão | provisionada→devida lag, devida→paga lag | 30d |
| AuditLog | volume por entity_type, atraso médio do AuditLogJob | 24h |
| Period closure | tentativas bloqueadas (423) por dia | 30d |
| Idempotência | hit rate, conflict rate (409) | 24h |
| Gateway | webhook lag, success rate, dedupe rate | 24h |
| Tenant isolation | TenantMismatch events (deve ser 0) | 24h |
| Wizard usage | % approvals via wizard vs legacy | 30d (durante rollout) |

**Reconciliação contábil semanal** (jobs já existem via `Reports::CashFlowReport` e `DreReport`):

- Σ(Entry.in onde affects_dre) - Σ(Entry.out onde affects_dre) deve bater com soma de margens DRE
- Σ(BankAccount.current_balance_cents) deve bater com initial + Entry net
- Σ(Installment.received_amount_cents) deve bater com Σ(PaymentReceipt.gross_amount_cents) - modifiers

**Auditoria forense disponível:**

- AuditLog por entity_type/id ([audit_logs_controller.rb](../../plugins/financial/app/controllers/api/v1/accounts/financial/audit_logs_controller.rb))
- Export CSV via `audit_logs/export_csv` ([AuditLogsExportJob](../../plugins/financial/app/jobs/financial/audit_logs_export_job.rb))
- Frozen attributes garantem que Installment/Entry/CommissionEntry históricos nunca foram mutados

---

## Anexo A — Componentes frontend necessários

Em [plugins/financial/frontend/features/financial/v2/components/wizard/](../../plugins/financial/frontend/features/financial/v2/components/wizard/) (criar):

| Componente | Responsabilidade |
|---|---|
| `PaymentPlanWizardV2.vue` | Container do wizard 5 steps |
| `WizardStepSummary.vue` | Step 1 — resumo do orçamento |
| `WizardStepDiscount.vue` | Step 2 — desconto opcional (fixo/percentual) |
| `WizardStepMode.vue` | Step 3 — escolha entre uniforme / entrada+restante / customizado |
| `WizardStepInstallments.vue` | Step 4 — `PaymentSplitBuilder` + `InstallmentPreviewTable` + `FeeSimulationCard` + `NetAmountCard` |
| `WizardStepConfirm.vue` | Step 5 — confirmação + `AuditPreview` |
| `PaymentSplitBuilder.vue` | Tabela editável: linha por parcela com (valor, data, método); add/remove linha; soma deve bater com total |
| `InstallmentPreviewTable.vue` | Read-only: bruto × taxa × líquido × liquidação esperada por parcela |
| `FeeSimulationCard.vue` | Card que invoca `simulate_fee` em onChange (debounced); mostra fee_percent + fee_fixed + fee_amount + net_amount |
| `NetAmountCard.vue` | Sumário: total bruto, total taxa, total líquido, comissão estimada |
| `AuditPreview.vue` | Lista de eventos que serão gerados ao confirmar (1 budget.approve + N installment.create + N commission.provision) |

Reaproveitar de `plugins/beclinic_core/frontend/components/`: `BeclinicButton`, `Tooltip`, `FormSelect`, `Badge`, `Checkbox`, `ConfirmDangerModal`.

Cores: `color="blue"` para primário ([memory financial_color_teal](#)) — não teal.

---

## Anexo B — Permissões RBAC (alvo Fase F5)

Em [plugins/custom_roles/frontend/shared/modules.js:216-233](../../plugins/custom_roles/frontend/shared/modules.js) já existem 14 perms. Mapping target backend:

| Permissão Klivy | Action Controller | Hoje |
|---|---|---|
| `financial.view_dashboard` | `Api::V1::Accounts::Financial::ReportsController#dashboard` | role-based |
| `financial.view_cashflow` | `CashFlow#index`, `Reports#cash_flow` | role-based |
| `financial.view_receivables` | `InstallmentsController#index`, `#by_patient` | role-based |
| `financial.view_payables` | `ExpensesController#index` | role-based |
| `financial.view_dre` | `Reports#dre` | role-based |
| `financial.view_reports` | `ReportsController#*` | role-based |
| `financial.view_cash_register` | `CashRegistersController#index`, `#show` | role-based |
| `financial.create_transaction` | `InstallmentsController#pay`, `ExpensesController#pay`, `EntriesController#create` | **ausente backend** |
| `financial.edit_transaction` | `BudgetsController#update_installments`, `InstallmentsController#update` | role-based parcial |
| `financial.delete_transaction` | `InstallmentsController#refund`, `BudgetsController#cancel`, `ExpensesController#reverse` | role-based parcial |
| `financial.manage_estimates` | `BudgetsController#{create,update}` | role-based |
| `financial.approve_estimate` | `BudgetsController#approve` | role-based |
| `financial.export_data` | `Reports#accountant_export`, `AuditLogsController#export_csv` | role-based |
| `financial.manage_settings` | `PaymentMethodsController#*`, `BankAccountsController#*`, `CommissionRulesController#*`, `DreCategoriesController#*` | role-based |

Migração: substituir `require_role!('ADMIN', 'GERENTE')` por `authorize_can!(:financial, :manage_settings)` (helper a criar reusando `beclinic_can?` do KlivyRole). Flag `financial_rbac_strict` mantém ambos caminhos por 2 semanas.

---

*Documento de planejamento. Atualizar conforme decisões evoluírem. Revisões devem ser comunicadas à equipe de desenvolvimento e ao analista QA simultaneamente.*
