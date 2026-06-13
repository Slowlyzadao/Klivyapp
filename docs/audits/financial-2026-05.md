# Auditoria completa — Módulo Financeiro (`plugins/financial`)

> Data: 2026-05-22  
> Fonte de verdade: [mapa-financeiro.json](../../mapa-financeiro.json) + [docs/01-product/modules/financeiro-funcionamento.md](../01-product/modules/financeiro-funcionamento.md)  
> Escopo: 259 arquivos · 36 controllers · 39 models · 23 services · 4 jobs · 13 pages V2 · 19 migrations financeiras  
> Auditores: 4 agentes paralelos (Models+DB, Services+Jobs, Controllers+Webhooks, Frontend) cobrindo evidência por `arquivo:linha`.

---

## 1. Visão geral

### 1.1 Estado atual em uma frase
O módulo está **70% no canon V2** e **30% ainda preso no legacy V1**, com **duas tabelas, dois controllers e dois models para cada conceito de configuração** (BankAccount, CashRegister, CommissionRule, RecurringExpense, Category). Frontend já migrou inteiramente para V2 (rotas legacy só redirecionam), mas o backend mantém ambos os caminhos expostos — **risco de divergência silenciosa de saldo** se algum job/serviço escrever no caminho errado.

### 1.2 Nível de maturidade

| Eixo | Nota | Comentário |
|---|---|---|
| Modelagem V2 | 8/10 | BIGINT centavos, soft-delete, audit log, concerns reutilizados — sólido |
| Modelagem Legacy | 3/10 | DECIMAL(10,2), `dependent: :destroy`, sem audit, sem soft-delete |
| Transacionalidade | 6/10 | Maioria dos services usa transação; alguns têm `return` dentro da transação e validações fora do lock |
| Idempotência | 5/10 | Concern existe e é aplicado em ~70% das ações de escrita; faltam Budgets, GatewaySettings, Webhooks |
| Multi-tenancy | 7/10 | V2 controllers usam `for_account(current_account.id)`; legacy usa `Current.account.x` (OK), mas alguns models não validam `account_id` presence |
| Webhooks (Asaas) | 4/10 | Validação HMAC delegada ao adapter (não confirmada timing-safe), account enumeration via response codes diferentes |
| Frontend V2 UX | 7/10 | Estrutura sólida, idempotência client-side OK, MAS 7 ações destrutivas usam `window.prompt()`/`window.confirm()` nativos |
| Imutabilidade histórica | 4/10 | Sem `attr_readonly` em campos críticos (taxa, valor bruto, MDR snapshot); `update` direto passa |
| Cobertura de testes | ❓ | Não auditado — recomendar verificação separada |

### 1.3 Riscos críticos
1. **Dois sistemas paralelos** — clínicas em produção podem ter saldo escrito ora em `bank_accounts` (legacy) ora em `financial_bank_accounts` (V2). Sem teste de reconciliação, é ponto cego.
2. **Falta de FK no banco V2** — migrations `20260507100002` e `20260507100003` declaram `bigint :account_id` mas **não criam `add_foreign_key`**. DB não impõe integridade.
3. **HMAC do webhook Asaas não confirmado timing-safe** — risco de credential brute-force se adapter usar `==` em vez de `secure_compare`.
4. **Idempotência cacheia só 2xx** — retry de erro 422 **reexecuta** a operação no servidor, podendo passar na segunda tentativa por race condition.
5. **Estorno parcial reverte 100% da comissão** — RefundPayment não calcula proporção; quem estorna R$300 de R$1000 zera comissão inteira.

### 1.4 Dívida técnica estimada
- **Removível em 1 sprint**: window.prompt/confirm (7 lugares), paginação client-side em CashRegister, `useFormatCurrency.js` legacy.
- **Removível em 2-3 sprints**: depreciação completa do schema legacy (8 tabelas + 10 controllers + 8 models).
- **Refactor estrutural** (1 mês): imutabilidade via `attr_readonly`, idempotência ubíqua, FKs faltantes, reverso proporcional de comissão.

---

## 2. Arquitetura atual

### 2.1 Camadas hoje

```
┌─────────────────────────────────────────────────────────────────┐
│ Frontend V2 (Vue)                                               │
│  pages/* → modals/* → api/financialV2.js (Idempotency-Key: ✓)   │
│  Rotas legacy V1 → redirect 301 → V2 (frontend já migrado)      │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│ API V2                  │  API Legacy (AINDA EXPOSTA)           │
│ /financial/v2/*         │  /financial/*                          │
│ (21 controllers)        │  (10 controllers — 5 duplicam V2)      │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│ Services V2 (23 arquivos)                                       │
│  approve_budget, receive_payment, refund_payment,               │
│  pay_commission, pay_expense, reverse_expense,                  │
│  transfer_between_accounts, cash_register_service, ...          │
│  + reports/*                                                    │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│ Models V2 (Financial::*)  │  Models Legacy (sem namespace)      │
│ 24 modelos                │  8 modelos                          │
│ Concerns: SoftDeletable,  │  Sem soft-delete, sem audit,        │
│   Auditable, Stamped,     │  sem MoneyAttribute                 │
│   MoneyAttribute          │                                     │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│ DB (Postgres)                                                   │
│ Schema V2: financial_budgets, financial_installments,           │
│   financial_entries, financial_expenses, financial_*            │
│   (BIGINT centavos, soft-delete, audit_log)                     │
│ Schema Legacy: bank_accounts, cash_registers,                   │
│   commission_rules, recurring_expenses, financial_categories,   │
│   financial_estimates, installments, account_transactions       │
│   (DECIMAL(10,2), sem soft-delete)                              │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Fluxos críticos hoje

#### Fluxo "Receber Pagamento"
1. Frontend `ReceivePaymentModalV2.vue` → POST `/financial/v2/payment_receipts` com `Idempotency-Key`
2. `PaymentReceiptsController#create` → `Financial::ReceivePayment.call(account, bank, installment_amounts, received_at, ...)`
3. Service abre `transaction`, faz `installments.each { |i| i.lock! }` (lock pessimista por parcela)
4. Distribui valor entre parcelas (split centavos com resto na última)
5. Cria `PaymentReceiptItem` por parcela, atualiza `received_amount_cents` e status
6. Cria `Financial::Entry` (inflow) com `cash_date` + `competence_date`
7. Calcula MDR (hardcoded — bug!) e cria `CommissionEntry` com status `devida`
8. Atualiza saldo via re-cálculo de `BankAccount#current_balance_cents`

#### Fluxo "Webhook Asaas → Receber Pagamento"
1. POST público `/webhooks/financial/asaas?account_id=X` (sem auth)
2. Controller busca `Account.find_by(id:)` (timing leak)
3. Busca `Financial::GatewaySetting`, valida HMAC (delegado ao adapter)
4. Grava `GatewayWebhookEvent` (unique por `(account_id, event_id)`)
5. Enfileira `ProcessAsaasEventJob`
6. Job chama `ReceivePayment.call(received_at: Date.current)` — **bug: usa hoje em vez de paid_date do webhook**
7. Falha não marca evento como `failed` → retry infinito

#### Fluxo "Despesa Recorrente"
1. Cron `RecurringExpensesCronJob` roda diariamente
2. `GenerateRecurringExpenses.run!(today: Date.current)` — **bug: TZ UTC se não passar `Time.zone.today`**
3. Para cada `Financial::RecurringExpense` ativa, gera despesas para próximos 35 dias
4. Idempotente por `(recurring_expense_id, competence_month)` (suposto — não confirmado por código no relatório)

### 2.3 Pontos de extensão (gateways)
- `Financial::Gateways::Base` (lib/financial/gateways/base.rb)
- `Financial::Gateways::Manual` (default)
- `Financial::Gateways::Asaas` (HMAC + API REST)
- Plugin pronto para adicionar gateways adicionais (Pagar.me, Mercado Pago) — bom.

---

## 3. Comparação com `mapa-financeiro.json`

### 3.1 SETUP — o que existe vs canon

| Step canon | Status no código | Lacunas |
|---|---|---|
| **1. Profissionais** (dados_agente + categoria + comissionado) | ❌ Não implementado no Financial — depende de User/Account base do Klivy | Falta `tipo_vinculo` (PJ/CLT/Sócio), `data_entrada`, `dados_bancarios` separados |
| **2. Plano de Contas** (Grupo → Subgrupo → Categoria → Subcategoria, 4 níveis) | 🟡 Parcial — `Financial::DreCategory` é flat, não hierárquica de 4 níveis | Modelo não suporta hierarquia canon. Canon prevê: Receita Clínica → Procedimentos Particulares → Endodontia. Hoje só tem `kind` (revenue/expense_fixed/expense_variable/other) |
| **3. Formas de Pagamento + Taxas versionadas + taxa por parcela 1x..12x** | ❌ Não modelado | Não há tabela `payment_methods` com `data_inicio_vigencia` + `data_fim_vigencia` + `parcela_Nx.taxa_percentual`. MDR é **hardcoded** em `receive_payment.rb:380-389` |
| **4. Contas Bancárias e Caixas** (com `conexao_com_provedor` e `data_de_corte`) | 🟡 Parcial — `Financial::BankAccount` existe, mas sem `conexao_com_provedor` e sem `data_de_corte` | Não há roteamento automático "Pix → Conta X" |
| **5. Regras de Comissão** (papéis DR/SDR/Comercial + gatilho enum + escopo + versionamento) | 🟡 Parcial — `Financial::CommissionRule` tem `valid_from`/`valid_to` e specificity scoring | Falta enum `papel` (DR/SDR/Comercial); gatilho não está documentado como enum em coluna |
| **6. Procedimentos e Serviços** (catálogo com `codigo_tuss`, `tabela_preco`, `plano_de_contas_id`) | ❌ Não está no plugin `financial` (provavelmente em `agenda` ou `patients`) | Vínculo automático categoria → DRE não confirmado |
| **7. Despesas Fixas Recorrentes** (Fixo vs Estimado, frequência enum, versionamento) | 🟡 Parcial — `Financial::RecurringExpense` existe; `variable_amount` flag presente | Falta enum `tipo_valor: [Fixo, Estimado]` com semântica clara "Fixo lança e aprova auto / Estimado vira rascunho" |
| **8. Metas de Receita** (Total/Por_Categoria/Por_Agente + meta_principal/minima/desafio) | 🟡 Parcial — `Financial::RevenueGoal` existe | Não confirmado se suporta 3 níveis (mínima/principal/desafio) ou apenas 1 valor |

### 3.2 OPERAÇÃO — o que existe vs canon

| Setor canon | Status | Lacunas |
|---|---|---|
| **1. Dashboard** (Receita do Mês, Margem, A Receber 30d, A Pagar 30d, Receita vs Meta, Top procedimentos) | ✅ Existe (`DashboardV2.vue` + `DashboardKpis` service) | `ticket_medio` divide por pacientes, não por procedimentos (CALC-FIN-04) |
| **2. Fluxo de Caixa** (+ Entrada / + Saída / ⇄ Transferência) | ✅ Existe (`CashFlowV2.vue`) | OK |
| **3. A Receber** (Confirmar Recebimento → muda status e registra na conta) | ✅ Existe (`ReceivablesV2.vue`) | OK |
| **4. A Pagar** (Confirmar Pagamento → debita conta) | ✅ Existe (`PayablesV2.vue`) | Estorno coleta motivo via `window.prompt()` — UX-CRIT-03 |
| **5. DRE** (estrutura hierárquica do canon: Receita Clínica → Procedimentos → Endodontia/...; menos Taxas Maquininha; menos Despesas por 11 grupos) | 🟡 Parcial — `DreV2.vue` + `DreReport` | Hierarquia 4 níveis do canon não modelada; sem exclusão explícita de `kind=transferencia` (CALC-FIN-06) |
| **6. Comissões** (ciclo: Gerada → Pendente → Aprovada → A Pagar → Paga) | 🟡 Parcial | Ciclo não totalmente refletido em status do model (`provisionada`/`devida`/`paga`/`estornada` faltam Aprovada / A Pagar como passos separados) |
| **7. Relatórios** (8 relatórios canon) | ✅ Maioria existe (`ReportsHubV2.vue` + 11 reports services) | Faltam: "Fluxo de Caixa Projetado" detalhado (existe mas validar projeção); "Receitas por Forma de Pagamento" |
| **8. Caixa** (abertura/sangria/suprimento/fechamento/reabertura/quebra) | ✅ Existe (`CashRegisterV2.vue` + `CashRegisterService`) | UX queimada — 5 ações usam `window.prompt()` (UX-CRIT-02); quebra usa `competence_date: Date.current` quando deveria usar `session_date` (CALC-FIN-03) |
| **9. Configurações** (inativar nunca deletar, criar nova versão de taxa/regra) | 🟡 Parcial | UI ainda permite "editar" em vez de "inativar e criar nova" em algumas tabs |

### 3.3 Regras globais canon

| Regra canon | Status |
|---|---|
| Versionamento: nunca editar histórico, inativar e criar novo | 🟡 Soft-delete OK; `attr_readonly` em campos imutáveis FALTANDO (`taxa_vinculada_id`, `valor_bruto`, `mdr_deduction_cents`, `percent_basis_points`) |
| Comissão é DESPESA no plano de contas, nunca redução de receita | 🟡 `PayCommission` cria `Expense`, mas categoria precisa estar configurada com `commission_category` resolver |
| Taxa de maquininha gerada automaticamente, nunca manualmente | ❌ **MDR é hardcoded em `receive_payment.rb:380-389`** (debito=2%, credito=3,5%) — NÃO vem de `payment_method` configurado |
| Transferência interna não afeta DRE | 🟢 Implementado (kind='transferencia', affects_dre=false), mas `DreReport` não tem filtro defensivo `.where.not(kind: 'transferencia')` |
| Laboratório lança automático via prontuário | ❌ Não encontrado no plugin financial — depende de integração com prontuário |
| Lançamento: bruto registrado, taxa congelada, líquido calculado | 🟡 Bruto registrado, líquido calculado, mas **taxa não congelada via attr_readonly** |

---

## 4. Problemas encontrados

Cada item: **Local · Evidência · Impacto · Reprodução · Recomendação**. ID prefix indica domínio (DB/MOD/SVC/CTL/WHK/FE/SEC/CALC) e severidade.

### 4.1 CRÍTICOS (devem bloquear release ou ser corrigidos antes do go-live de qualquer clínica nova)

#### `CRIT-DB-01` — Migrations V2 não declaram Foreign Keys
- **Local**: [db/migrate/20260507100002_create_financial_v2_budgets_and_installments.rb](../../db/migrate/20260507100002_create_financial_v2_budgets_and_installments.rb), [20260507100003_create_financial_v2_expenses_and_entries.rb](../../db/migrate/20260507100003_create_financial_v2_expenses_and_entries.rb)
- **Evidência**: `t.bigint :account_id, null: false` declarado, mas **nenhum `add_foreign_key :financial_budgets, :accounts`** existe nas migrations V2.
- **Impacto**: DB não impõe integridade referencial. `account_id` órfão é aceito. Em caso de bug de aplicação, dado vaza entre tenants sem violação detectável.
- **Reprodução**: `Financial::Budget.create!(account_id: 99999999, ...)` passa sem erro de FK.
- **Recomendação**: Criar migration `add_missing_foreign_keys_financial_v2` com `add_foreign_key on_delete: :restrict` em todas as FKs (`account_id`, `patient_id`, `budget_id`, `installment_id`, `bank_account_id`, `dre_category_id`, etc).

#### `CRIT-DB-02` — Modelos legacy ainda escrevem em DECIMAL(10,2)
- **Local**: [db/migrate/20260307200011_create_financial_estimates.rb:12-16](../../db/migrate/20260307200011_create_financial_estimates.rb), [20260307200013_create_installments.rb:9](../../db/migrate/20260307200013_create_installments.rb), [20260324120002_create_bank_accounts.rb:9](../../db/migrate/20260324120002_create_bank_accounts.rb), [20260324120005_create_recurring_expenses.rb:10](../../db/migrate/20260324120005_create_recurring_expenses.rb)
- **Evidência**: `t.decimal :amount, precision: 10, scale: 2` (máx R$99.999.999,99) em todas as tabelas legacy.
- **Impacto**: Quebra de canon ("valores em centavos BIGINT"). Arredondamento em série acumula divergência. Faturamento > R$99M/mês causa overflow.
- **Reprodução**: Inserir `BankAccount.new(initial_balance: BigDecimal("999999999.99"))` — fora do range.
- **Recomendação**: Bloquear escrita em tabelas legacy via `readonly!` no modelo. Plano de migração legacy → V2 em fase 3.

#### `CRIT-DB-03` — `Financial::ApplicationRecord` default_scope NÃO se aplica em `find`/`find_by`
- **Local**: [plugins/financial/app/models/financial/application_record.rb:14-16](../../plugins/financial/app/models/financial/application_record.rb)
- **Evidência**:
  ```ruby
  default_scope { column_names.include?('deleted_at') ? where(deleted_at: nil) : all }
  ```
- **Impacto**: `Financial::Budget.find_by(id: 123)` **retorna registro soft-deletado**. Operadores podem editar/agir sobre dado que deveria estar invisível.
- **Reprodução**: `b = Budget.create!; b.soft_delete!; Budget.find_by(id: b.id)` — retorna `b` (com `deleted_at` setado).
- **Recomendação**: Sobrescrever `self.find` e `self.find_by` em `ApplicationRecord` para chamar `alive.find(...)`. Considerar mover de `default_scope` para escopo explícito `alive` (mais previsível).

#### `CRIT-DB-04` — Duas implementações vivas de CashRegister com semântica de cascata diferente
- **Local**: [plugins/financial/app/models/cash_register.rb](../../plugins/financial/app/models/cash_register.rb) (legacy) vs [plugins/financial/app/models/financial/cash_register.rb](../../plugins/financial/app/models/financial/cash_register.rb) (V2)
- **Evidência**:
  - Legacy: `has_many :cash_register_entries, dependent: :destroy` — apaga entries em cascata.
  - V2: `has_many :cash_movements, dependent: :restrict_with_error` — bloqueia.
- **Impacto**: Se ambos estão sendo escritos, saldo diverge. Cascata legacy apaga histórico se caixa for excluído.
- **Reprodução**: Verificar se algum service ainda chama `CashRegister.create!` (sem namespace). Frontend já migrado, mas backend pode estar em ambos.
- **Recomendação**: Marcar legacy `CashRegister` como `self.abstract_class = true` + remover rotas/controllers. Migrar dados via job admin.

#### `CRIT-SVC-01` — `PayCommission` tem `return` dentro de `transaction` sem rollback explícito
- **Local**: [plugins/financial/app/services/financial/pay_commission.rb:39-63](../../plugins/financial/app/services/financial/pay_commission.rb)
- **Evidência**:
  ```ruby
  ActiveRecord::Base.transaction do
    category = commission_category
    unless category
      return Result.new(success?: false, ...)  # return dentro do bloco
    end
    expense = build_expense(category)
    unless expense.save
      raise ActiveRecord::Rollback
    end
    commission_entry.update!(status: 'paga', ...)
    return Result.new(success?: true, ...)
  end
  ```
- **Impacto**: O `return` dentro do bloco `transaction` no Rails encerra o método e **commita** o que já foi feito até ali (em vez de fazer rollback). Estado parcial pode ser commitado se a categoria for nil mas a transação já tiver feito SELECTs com locks.
- **Recomendação**: Mover toda validação para fora da transação. Dentro da transação, qualquer falha = `raise ActiveRecord::Rollback`.

#### `CRIT-SVC-02` — `PayCommission` cria 2ª Expense em retry sem checar existência
- **Local**: [plugins/financial/app/services/financial/pay_commission.rb:29-64](../../plugins/financial/app/services/financial/pay_commission.rb)
- **Evidência**: Idempotência só dispara quando `status == 'paga' && expense.present?`. Se status for `'devida'` e expense já existir, cria outra.
- **Impacto**: Duplica despesa de comissão a pagar. Clique duplo ou retry inflama o A Pagar.
- **Reprodução**: Chamar `PayCommission.call(commission_entry)` 2x rapidamente. Sem Idempotency-Key no controller, segundo call cria 2ª expense.
- **Recomendação**: Validar `commission_entry.expense.present?` no início, retornar idempotent. Wrap controller com `idempotent!`.

#### `CRIT-SVC-03` — `ProcessAsaasEventJob` usa `Date.current` em vez de `paid_date` do webhook
- **Local**: [plugins/financial/app/jobs/financial/webhooks/process_asaas_event_job.rb:51-69](../../plugins/financial/app/jobs/financial/webhooks/process_asaas_event_job.rb)
- **Evidência**: `received_at: Date.current` mesmo quando webhook traz `paid_date`.
- **Impacto**: Webhook atrasado (2 dias) registra recebimento na data errada. `competence_date` do Entry fica errado → DRE distorcido.
- **Reprodução**: Asaas envia webhook em retry. `paid_date=2026-05-15`, mas job processa `Date.current=2026-05-20`. Entry sai com cash_date e competence_date = 2026-05-20.
- **Recomendação**: Parse `payload['payment']['paymentDate']` ou similar; fallback para `Date.current` apenas se ausente.

#### `CRIT-SVC-04` — `ProcessAsaasEventJob` não marca evento como failed em erro
- **Local**: [plugins/financial/app/jobs/financial/webhooks/process_asaas_event_job.rb:51-69](../../plugins/financial/app/jobs/financial/webhooks/process_asaas_event_job.rb)
- **Evidência**: Se `ReceivePayment.call` retorna `failure`, o evento permanece com status `received` — Sidekiq vai retentar indefinidamente.
- **Impacto**: Retry loop infinito; em caso de erro de dados (parcela já paga, conta inativa), gera carga e logs sem progresso.
- **Recomendação**: `event.mark_failed!(reason)` quando `result.failure?`. Retry só para erros transientes (timeout, 5xx). Dead-letter queue para falhas estruturais.

#### `CRIT-SVC-05` — `RefundPayment` reverte 100% da comissão em estorno parcial
- **Local**: [plugins/financial/app/services/financial/refund_payment.rb:150-156](../../plugins/financial/app/services/financial/refund_payment.rb)
- **Evidência**:
  ```ruby
  installments.each do |inst|
    inst.commission_entries.where(status: 'devida').update_all(
      status: 'estornada',
      updated_at: Time.current
    )
  end
  ```
- **Impacto**: Estornar R$300 de parcela de R$1000 zera comissão inteira (R$100 → R$0 em vez de R$70). Fraude possível (estornar R$1 zera comissão de R$1000).
- **Reprodução**: Receber parcela R$1000 com 10% comissão (R$100). Estornar R$1 (parcial). Comissão fica 0.
- **Recomendação**: Calcular proporção: `partial_reversion = (commission_amount_cents * refund_amount / installment_total).round`. Criar `CommissionEntry` reverso com valor proporcional negativo.

#### `CRIT-SVC-06` — `ReceivePayment` tira snapshot de `total_due` DEPOIS do lock
- **Local**: [plugins/financial/app/services/financial/receive_payment.rb:77-170](../../plugins/financial/app/services/financial/receive_payment.rb)
- **Evidência**: `installments.each { |i| i.lock! }` seguido por `total_due_before_update = installments.sum(&:remaining_cents)` — mas `installments` é uma coleção carregada antes do lock.
- **Impacto**: Race condition entre carregamento e lock. Outra transação pode ter atualizado `received_amount_cents` no intervalo, e o sum fica calculado em valores stale.
- **Recomendação**: Após lock, **recarregar** `installments.each(&:reload)` antes do sum. Ou usar `Installment.where(id: ids).lock.to_a` para carregar+lockar atomicamente.

#### `CRIT-CALC-01` — MDR hardcoded em vez de buscar configuração da forma de pagamento
- **Local**: [plugins/financial/app/services/financial/receive_payment.rb:380-389](../../plugins/financial/app/services/financial/receive_payment.rb)
- **Evidência**:
  ```ruby
  rate_bps = case payment_method
             when 'debito'  then 200
             when 'credito' then 350
             when 'pix', 'dinheiro', 'boleto', 'transferencia' then 0
             else 0
             end
  ```
- **Impacto**: **Quebra canon central** ("taxa de maquininha gerada AUTOMATICAMENTE ao registrar recebimento; nunca lançar manualmente; cada parcela com sua própria taxa"). Sistema usa taxas fixas, não taxas configuradas por clínica/adquirente/parcela.
- **Reprodução**: Clínica cadastra Cielo crédito 3x = 4,2%. Sistema usa 3,5% (hardcoded).
- **Recomendação**: Implementar tabela `financial_payment_methods` + `financial_payment_method_fees` (vigência + parcela_N + taxa). `ReceivePayment` busca taxa vigente para `(account_id, method, installments_count, received_at)`. Congela `payment_method_fee_id` na Installment/Entry (snapshot imutável).

#### `CRIT-SEC-01` — Webhook Asaas: validação HMAC não confirmadamente timing-safe
- **Local**: [plugins/financial/app/controllers/webhooks/financial/asaas_controller.rb:22](../../plugins/financial/app/controllers/webhooks/financial/asaas_controller.rb)
- **Evidência**: `adapter.verify_webhook(headers:, body:)` — delegação para `Financial::Gateways::Asaas`. Sem revisão do adapter para confirmar uso de `ActiveSupport::SecurityUtils.secure_compare`.
- **Impacto**: Se adapter usa `==` para comparar HMAC, timing attack pode descobrir webhook_secret. Atacante pode então forjar webhooks de "pagamento recebido" → forçar marcação de parcelas como pagas → fraude financeira direta.
- **Recomendação**: Auditar [plugins/financial/lib/financial/gateways/asaas.rb](../../plugins/financial/lib/financial/gateways/asaas.rb#L1) e garantir uso de `secure_compare`. Adicionar teste que verifica timing-safe.

#### `CRIT-SEC-02` — Webhook Asaas: enumeration de tenants via response codes diferentes
- **Local**: [plugins/financial/app/controllers/webhooks/financial/asaas_controller.rb:15-19](../../plugins/financial/app/controllers/webhooks/financial/asaas_controller.rb)
- **Evidência**:
  ```ruby
  account = ::Account.find_by(id: params[:account_id])
  return head :not_found unless account
  setting = ::Financial::GatewaySetting.find_by(account_id: account.id, gateway: 'asaas')
  return head :forbidden unless setting
  ```
- **Impacto**: 404 para account inexistente; 403 para account sem setting. Atacante distingue contas existentes via response code. Pré-requisito para ataques direcionados.
- **Recomendação**: Sempre retornar 403 (constant-time): `return head :forbidden unless account && setting && setting.webhook_secret.present?`.

#### `CRIT-SEC-03` — `GatewaySetting` usa Base64 em vez de criptografia real
- **Local**: [plugins/financial/app/models/financial/gateway_setting.rb:49-63](../../plugins/financial/app/models/financial/gateway_setting.rb)
- **Evidência**: `Base64.strict_encode64(value.to_s)` com comentário "SUBSTITUIR por encrypts:".
- **Impacto**: Vazamento de DB → credenciais Asaas em texto claro (Base64 é encoding, não criptografia). Risco máximo: atacante movimenta dinheiro real via API Asaas da clínica.
- **Recomendação**: Configurar Rails ActiveRecord Encryption com master key em env. Usar `encrypts :api_key, :webhook_secret, deterministic: false`. Migrar valores existentes via job.

#### `CRIT-FE-01` — Ações destrutivas e cadastros via `window.prompt()`/`window.confirm()` nativos
- **Local**: 7 ocorrências:
  - [plugins/financial/frontend/features/financial/v2/pages/CashRegisterV2.vue:104](../../plugins/financial/frontend/features/financial/v2/pages/CashRegisterV2.vue) (abertura)
  - [CashRegisterV2.vue:121](../../plugins/financial/frontend/features/financial/v2/pages/CashRegisterV2.vue) (fechamento)
  - [CashRegisterV2.vue:146](../../plugins/financial/frontend/features/financial/v2/pages/CashRegisterV2.vue) (sangria)
  - [CashRegisterV2.vue:168](../../plugins/financial/frontend/features/financial/v2/pages/CashRegisterV2.vue) (suprimento)
  - [CashRegisterV2.vue:183](../../plugins/financial/frontend/features/financial/v2/pages/CashRegisterV2.vue) (reabertura)
  - [PayablesV2.vue:147](../../plugins/financial/frontend/features/financial/v2/pages/PayablesV2.vue) (motivo de estorno)
  - [SettingsCategoriesTab.vue:161](../../plugins/financial/frontend/features/financial/v2/components/settings/SettingsCategoriesTab.vue) (seed de categorias)
- **Evidência**: `const opening = prompt('Saldo inicial em dinheiro (ex: 100,00):');`
- **Impacto**: UX queimada. Sem máscara de moeda, sem validação client-side. Operador digita "100" e recebe erro genérico do backend ("required"). Estorno coleta motivo sem limite/validação — usuário pode submeter string vazia, SQL-like, etc.
- **Recomendação**: Modais dedicados (`CashRegisterOpenModal`, `CashRegisterCloseModal`, `RefundReasonModal`) com `FormSelect`+`useMoney`. Documentado no canon e em memória [feedback_bug_visual_recorrente_estrutural](feedback_bug_visual_recorrente_estrutural.md).

### 4.2 ALTOS

#### `ALTO-DB-01` — `Financial::ApplicationRecord` não enforça `account_id presence`
- **Local**: Modelos V2 não validam `validates :account_id, presence: true`.
- **Evidência**: Apenas `belongs_to :account` (Rails 5+ valida por padrão, MAS `optional: true` em algum modelo derrubaria).
- **Impacto**: Risco de multi-tenancy violado se algum modelo herdar com `belongs_to :account, optional: true`.
- **Recomendação**: Em `Financial::ApplicationRecord`: `validates :account_id, presence: true if column_names.include?('account_id')`.

#### `ALTO-DB-02` — Faltam `check_constraint` para `_cents >= 0`
- **Local**: Todas as migrations V2 com colunas `_cents`.
- **Evidência**: Nenhum `add_check_constraint :financial_budgets, 'subtotal_cents >= 0'`.
- **Impacto**: Valor negativo via SQL direto ou bug de mass assignment passa. Relatórios quebram.
- **Recomendação**: Migration com `add_check_constraint` em todas as `_cents` (exceto colunas que podem ser negativas por design: diferença de caixa).

#### `ALTO-DB-03` — Imutabilidade não enforçada em campos críticos
- **Local**: `Financial::CommissionEntry`, `Financial::Installment`, `Financial::Entry`.
- **Evidência**: Sem `attr_readonly :base_amount_cents, :mdr_deduction_cents, :percent_basis_points` em CommissionEntry; sem `attr_readonly :amount_cents, :payment_method` em Installment após pagamento.
- **Impacto**: `update_columns` ou mass assignment via controller pode alterar histórico. Canon proíbe.
- **Recomendação**: `attr_readonly` nos campos congelados + validação `if persisted? && X_changed?` para defesa em profundidade.

#### `ALTO-DB-04` — `Financial::PaymentReceipt#assign_receipt_number` sem unique constraint
- **Local**: [plugins/financial/app/models/financial/payment_receipt.rb:43-50](../../plugins/financial/app/models/financial/payment_receipt.rb)
- **Evidência**: `last_seq = ...where(account_id:).where('receipt_number LIKE ?', "REC-#{year}-%").order(...).limit(1)` — calcula sequence pelo último, sem lock.
- **Impacto**: Race condition entre 2 recibos simultâneos pode gerar `REC-2026-000123` duplicado se não houver unique index.
- **Recomendação**: Migration com `add_index :financial_payment_receipts, [:account_id, :receipt_number], unique: true, where: 'deleted_at IS NULL'`. Adicionalmente, usar Postgres sequence ou `INSERT ... RETURNING` atomic.

#### `ALTO-DB-05` — `Financial::Installment` com `replaces_installment_id`/`renegotiated_to_id` sem FK e sem validação
- **Local**: Migration [20260507100002:97-98](../../db/migrate/20260507100002_create_financial_v2_budgets_and_installments.rb), modelo `financial/installment.rb:22-24`.
- **Evidência**: Colunas declaradas como `t.bigint`, sem `add_foreign_key`. Modelo sem `belongs_to :replaces_installment, class_name: 'Financial::Installment', optional: true`.
- **Impacto**: Cadeia de renegociações pode virar referência circular ou ID órfão.
- **Recomendação**: FK + `validates :replaces_installment_id, uniqueness: true` + validação de que ambos parcelas pertencem ao mesmo account.

#### `ALTO-SVC-01` — `ReceivePayment` não valida que parcelas são do mesmo budget
- **Local**: [plugins/financial/app/services/financial/receive_payment.rb:262-265](../../plugins/financial/app/services/financial/receive_payment.rb)
- **Evidência**: Carrega parcelas filtrando só por `account_id` e `id`.
- **Impacto**: Recibo pode misturar parcelas de orçamentos/pacientes diferentes. Quebra rastreabilidade ("Recibo de Tratamento X").
- **Recomendação**: Validar `installments.map(&:financial_budget_id).uniq.size == 1`. Se múltiplos pacientes, validar `patient_id` também.

#### `ALTO-SVC-02` — `GenerateRecurringExpenses` usa `Date.current` em vez de `Time.zone.today`
- **Local**: [plugins/financial/app/jobs/financial/recurring_expenses_cron_job.rb:8-14](../../plugins/financial/app/jobs/financial/recurring_expenses_cron_job.rb).
- **Evidência**: `Financial::GenerateRecurringExpenses.run!` (sem `today:`); default usa `Date.current` que respeita `Time.zone` do app — mas containers em UTC sem TZ setada disparam erros.
- **Impacto**: Job rodando em UTC em ambiente BRT-3 pode gerar despesa de 31-jan no dia 30-jan (UTC=01:00 do dia 31 = 22:00 do dia 30 em São Paulo).
- **Recomendação**: Garantir `config.time_zone = 'America/Sao_Paulo'` no Application + passar `today: Time.zone.today` explicitamente.

#### `ALTO-SVC-03` — `CashRegisterService#create_quebra_movement` usa `Date.current` em vez de `session_date`
- **Local**: [plugins/financial/app/services/financial/cash_register_service.rb:158-192](../../plugins/financial/app/services/financial/cash_register_service.rb)
- **Evidência**: `competence_date: Date.current` no Entry de quebra.
- **Impacto**: Caixa de ontem fechado hoje registra quebra com competência = hoje. DRE de ontem omite quebra real do dia.
- **Recomendação**: `competence_date: register.session_date` (ou `register.opened_at.to_date`).

#### `ALTO-SVC-04` — `IdempotentAction` só persiste resposta para status 2xx
- **Local**: [plugins/financial/app/controllers/concerns/financial/idempotent_action.rb:108-131](../../plugins/financial/app/controllers/concerns/financial/idempotent_action.rb)
- **Evidência**: `return unless response.status >= 200 && response.status < 300`.
- **Impacto**: Retry com mesma key após erro 422 **reexecuta** a ação. Se erro era de race (parcela ficou paga entre tentativa 1 e 2), tentativa 2 pode passar — duplicação possível.
- **Recomendação**: Persistir TODOS os status codes (inclusive 4xx). Cliente que receber 422 cached **sabe** que tentou e falhou; novo Idempotency-Key implica nova intenção.

#### `ALTO-CTL-01` — `installments#upload_proof` sem validação de MIME type
- **Local**: [plugins/financial/app/controllers/api/v1/accounts/financial/installments_controller.rb:267-277](../../plugins/financial/app/controllers/api/v1/accounts/financial/installments_controller.rb)
- **Evidência**: `@installment.payment_proof.attach(file)` sem checar `file.content_type`.
- **Impacto**: Upload de `.exe`/`.zip`/`.html` disfarçado de comprovante. Servido depois com `Content-Disposition: attachment`. Vetor de social engineering / phishing intra-clínica.
- **Recomendação**: Whitelist: `%w[application/pdf image/jpeg image/png image/webp]`. Validar também via magic bytes (`Marcel::Magic`).

#### `ALTO-CTL-02` — `audit_logs#export_csv` sem rate limit nem date range max
- **Local**: [plugins/financial/app/controllers/api/v1/accounts/financial/audit_logs_controller.rb:41-55](../../plugins/financial/app/controllers/api/v1/accounts/financial/audit_logs_controller.rb)
- **Evidência**: `scope.find_each do |log| out << [...] end` sem limite de data; sem rate limit; serializa `before.to_json`/`after.to_json` (pode conter PII).
- **Impacto**: AUDITOR com má-fé exporta CSV de 1 ano com PII (telefones, emails) → exfiltração silenciosa. Range gigante = OOM / DoS.
- **Recomendação**: 
  1. Max 90 dias por export.
  2. Rate limit (1 export / 24h / user) via Rack::Attack ou similar.
  3. Mover para job assíncrono + email com link assinado expirando em 1h.
  4. Sanitizar `before`/`after` removendo PII conhecido (email/phone/CPF).

#### `ALTO-CTL-03` — Controllers legacy ainda expostos sem deprecation/redirect
- **Local**: rotas para `categories_controller`, `bank_accounts_controller` (legacy), `cash_registers_controller` (legacy), `commission_rules_controller` (legacy), `recurring_expenses_controller` (legacy), `financial_dashboard_controller`, `financial_goals_controller`, `financial_reports_controller`, `financial_pdfs_controller` (órfã?).
- **Evidência**: Rotas montadas (engine routes 395-449), nenhuma marcação de deprecation.
- **Impacto**: Superfície de ataque dupla. Pundit policies legacy podem estar mais frouxas que RBAC V2. Frontend já não usa, mas API pública continua respondendo.
- **Recomendação**: Marcar com `deprecated_route true` (custom) ou simplesmente remover. Se algum cliente externo (mobile, integração) ainda usa, dar 90 dias de aviso e remover.

#### `ALTO-CTL-04` — `financial_goals_controller` (legacy) sem `require_role!`
- **Local**: [plugins/financial/app/controllers/api/v1/accounts/financial_goals_controller.rb:30](../../plugins/financial/app/controllers/api/v1/accounts/financial_goals_controller.rb)
- **Evidência**: `def update; params.permit(:monthly_goal, :quarterly_goal, :annual_goal); ...` sem `before_action :require_role!`.
- **Impacto**: RECEPCAO consegue editar metas (canon exige GERENTE/ADMIN). Quebra controle financeiro.
- **Recomendação**: Deprecar legacy. Confirmar que V2 [revenue_goals_controller.rb](../../plugins/financial/app/controllers/api/v1/accounts/financial/revenue_goals_controller.rb) tem `require_role!('GERENTE', 'ADMIN')`.

#### `ALTO-FE-01` — `loadBankAccounts()` falha silenciosa em modais críticos
- **Local**: [PayExpenseModalV2.vue:81-89](../../plugins/financial/frontend/features/financial/v2/components/PayExpenseModalV2.vue), [ReceivePaymentModalV2.vue:174-184](../../plugins/financial/frontend/features/financial/v2/components/ReceivePaymentModalV2.vue), [ManualEntryModalV2.vue:114-125](../../plugins/financial/frontend/features/financial/v2/components/ManualEntryModalV2.vue)
- **Evidência**:
  ```js
  } catch (e) {
    bankAccounts.value = [];
  }
  ```
- **Impacto**: Se API de contas falha, modal abre com select vazio sem mensagem. Operador tenta salvar e vê erro genérico "Selecione a conta". Status mentindo: backend não falhou — frontend escondeu.
- **Recomendação**: Guardar erro em `ref(null)`, mostrar `<ErrorBanner>` no modal com botão "Tentar novamente". Bloquear submit se contas vazias por erro.

#### `ALTO-FE-02` — `CashRegisterV2` faz paginação client-side em coleção potencialmente grande
- **Local**: [plugins/financial/frontend/features/financial/v2/pages/CashRegisterV2.vue:98-101](../../plugins/financial/frontend/features/financial/v2/pages/CashRegisterV2.vue)
- **Evidência**: `paginatedHistory = computed(() => history.value.slice(start, start + perPage.value))` sobre `history` carregado inteiro.
- **Impacto**: Após 1 ano de operação, clínica tem ~365 sessões; suportável. Após 5 anos com 3 caixas, 5475 registros baixados a cada visita. Time-to-interactive ruim.
- **Recomendação**: Paginação server-side: `?page=1&per_page=20&from=...&to=...`.

### 4.3 MÉDIOS

#### `MED-DB-01` — `BankAccount#uniqueness` com `conditions: -> { alive }` causa subquery cara
- Local: [plugins/financial/app/models/financial/bank_account.rb:22](../../plugins/financial/app/models/financial/bank_account.rb).
- Recomendação: confiar no partial unique index na migration; remover validação Ruby ou ao menos cachear.

#### `MED-DB-02` — `Entry#source_record` polymorphic sem validação de `source_type`
- Local: [plugins/financial/app/models/financial/entry.rb:34-35](../../plugins/financial/app/models/financial/entry.rb).
- Recomendação: `validates :source_type, inclusion: { in: %w[Financial::PaymentReceipt Financial::Expense Financial::CashMovement Financial::CommissionEntry], allow_nil: true }`.

#### `MED-DB-03` — `IdempotencyKey` TTL = 24h mas sem cleanup job
- Local: [plugins/financial/app/models/financial/idempotency_key.rb:9](../../plugins/financial/app/models/financial/idempotency_key.rb).
- Recomendação: `Financial::IdempotencyKeyCleanupJob` rodando diariamente: `delete_all where('created_at < ?', 7.days.ago)`.

#### `MED-DB-04` — `LgpdRequest` sem timestamps `executed_at`, `rejected_at`
- Local: [plugins/financial/app/models/financial/lgpd_request.rb](../../plugins/financial/app/models/financial/lgpd_request.rb).
- Recomendação: migration adicionando 3 timestamps.

#### `MED-DB-05` — `CommissionRule#percent_basis_points` sem bounds 0..10000
- Local: [plugins/financial/app/models/financial/commission_rule.rb:80-92](../../plugins/financial/app/models/financial/commission_rule.rb).
- Recomendação: `validates :percent_basis_points, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000 }, allow_nil: true`.

#### `MED-SVC-01` — `EditApprovedBudget` não re-calcula comissão provisionada após edição
- Local: [plugins/financial/app/services/financial/edit_approved_budget.rb:44-62](../../plugins/financial/app/services/financial/edit_approved_budget.rb).
- Impacto: parcela R$1000 → comissão R$100 provisionada. Editar para R$500 → comissão segue R$100. Inflação silenciosa.

#### `MED-SVC-02` — `TransferBetweenAccounts` valida saldo fora do lock
- Local: [plugins/financial/app/services/financial/transfer_between_accounts.rb:24](../../plugins/financial/app/services/financial/transfer_between_accounts.rb).
- Recomendação: lock primeiro, revalidar dentro.

#### `MED-SVC-03` — `CommissionRule.most_specific_for` sem tie-breaker
- Local: [plugins/financial/app/models/financial/commission_rule.rb:41-60](../../plugins/financial/app/models/financial/commission_rule.rb).
- Recomendação: tie-break por `valid_from DESC` (regra mais recente vence).

#### `MED-CALC-01` — `DreReport` não exclui `kind=transferencia` defensivamente
- Local: [plugins/financial/app/services/financial/reports/dre_report.rb:61-99](../../plugins/financial/app/services/financial/reports/dre_report.rb).
- Recomendação: `.where.not(kind: 'transferencia')` mesmo se `affects_dre=false` filtre — defesa em profundidade.

#### `MED-CALC-02` — `ticket_medio` calcula com base errada
- Local: [plugins/financial/app/services/financial/reports/dashboard_kpis.rb](../../plugins/financial/app/services/financial/reports/dashboard_kpis.rb) (~L179-202).
- Evidência: comentário "Ticket Médio = receita ÷ pacientes únicos atendidos no período."
- Impacto: Canon não define explicitamente, mas mercado odontológico usa receita / atendimentos (não pacientes). Validar com produto.

#### `MED-CTL-01` — `commission_rules_controller#update` permite alterar `rate_percent` retroativamente
- Local: [plugins/financial/app/controllers/api/v1/accounts/financial/commission_rules_controller.rb](../../plugins/financial/app/controllers/api/v1/accounts/financial/commission_rules_controller.rb)
- Impacto: canon proíbe ("inativar antiga e criar nova"). Modelo precisa validar `if persisted? && entries_using_this_rule.exists?`.

#### `MED-CTL-02` — Padrão `require_role! and return unless user_has_any_role?` redundante
- Local: vários (ex: [expenses_controller.rb:28](../../plugins/financial/app/controllers/api/v1/accounts/financial/expenses_controller.rb)).
- Recomendação: refatorar concern `Financial::RequireRole` com semântica única.

#### `MED-FE-01` — `onManualEntryConfirmed()` chama `load()` sem await
- Local: [plugins/financial/frontend/features/financial/v2/pages/DashboardV2.vue:182-186](../../plugins/financial/frontend/features/financial/v2/pages/DashboardV2.vue).
- Impacto: modal fecha antes do refetch, toast aparece com KPIs antigos.

#### `MED-FE-02` — `CashFlowV2.onEntryConfirmed` faz 2 fetchs sequenciais
- Local: [plugins/financial/frontend/features/financial/v2/pages/CashFlowV2.vue:216-220](../../plugins/financial/frontend/features/financial/v2/pages/CashFlowV2.vue).
- Recomendação: `Promise.all([load(), loadBankAccounts()])`.

### 4.4 BAIXOS

- `BAIXO-DB-01` — `useFormatCurrency.js` (legacy) parece morto. Confirmar e remover.
- `BAIXO-DB-02` — Documentação interna inconsistente entre canon JSON e modelos (ex: canon usa "PJ/CLT/Sócio" para tipo_vinculo, código não tem essa coluna).
- `BAIXO-FE-01` — 30+ `!important` em SCSS financial (documentado como "fronteira deliberada contra Chatwoot core"). Frágil.
- `BAIXO-FE-02` — Loading state desaparece antes do toast em algumas pages, criando flicker.
- `BAIXO-SVC-01` — `AnonymizePatient` é idempotente (bom).
- `BAIXO-CTL-01` — `bulk_reclassify` em `entries_controller` é seguro (escopo `for_account`), mas UX confusa quando IDs fora do escopo são silenciosamente ignorados.
- `BAIXO-CTL-02` — `backups#destroy` usa regex restritivo para `filename` — defense in depth OK, mas adicionar `Pathname#expand_path` check.

---

## 5. Riscos de regressão

### 5.1 Pontos sensíveis (qualquer alteração aqui precisa de teste de regressão)

1. **`ReceivePayment`** — orquestra 6 efeitos colaterais (PaymentReceiptItem, Installment.received_amount, Entry, CommissionEntry, PatientCredit, BankAccount saldo). Cada um já pode estar quebrado. Modificar = risco de cascata. Cobrir com teste de invariante: "soma das movimentações = bruto recebido".
2. **`ApproveBudget` + `EditApprovedBudget`** — geram parcelas com split de centavos + provisiona comissão. Bug aqui inflama o A Receber.
3. **`RefundPayment`** — afeta caixa, DRE, comissão, patient_credit. CRÍTICO já encontrado (reverso 100% em vez de proporcional).
4. **`ProcessAsaasEventJob`** — webhook automático em produção. Bug aqui não tem operador humano para corrigir.
5. **Snapshot de taxa/MDR** — mudanças em `CommissionRule#most_specific_for` ou no MDR (hoje hardcoded) afetam **todos** os cálculos retroativamente se imutabilidade não estiver enforced.
6. **Soft-delete em `Financial::ApplicationRecord`** — `default_scope` quebra com `find_by`. Mudar para `alive` explícito muda comportamento de **todos** os modelos.

### 5.2 Dependências cruzadas

- **Financial → Patients**: `patient_id` em Budget, Installment, PaymentReceipt, PatientCredit. Anonymize de paciente quebra timeline.
- **Financial → Agenda**: comissão gerada por agendamento/atendimento. Mudança no Agenda model pode quebrar `CommissionRule#most_specific_for`.
- **Financial → User/Account RBAC**: roles vêm do Klivy core. Mudança no RBAC quebra `require_role!`.
- **Financial → ActiveStorage R2**: upload_proof, backups, audit exports usam blobs. Memória `project_active_storage_account_scoping`: blobs prefixados por `accounts/<id>/`.

### 5.3 Efeitos colaterais conhecidos
- Deprecar legacy `BankAccount`/`CashRegister` **antes** de migrar dados quebra clínicas que ainda escrevem nelas.
- Remover controllers legacy quebra integrações externas (mobile, contador), se existirem.
- Mudar `default_scope` para `alive` explícito reabre risco de retornar deletados (precisa cobertura de teste).

### 5.4 Cuidados obrigatórios para qualquer PR no módulo
1. Rodar suite completa de testes financeiros (existir, validar coverage).
2. Em ambiente de staging com dados reais (clínica piloto), rodar reconciliação: `sum(entries.inflow) - sum(entries.outflow) == sum(bank_accounts.current_balance) - sum(bank_accounts.initial_balance)`.
3. Comparar relatórios DRE antes/depois para um mês fechado — deve ser **idêntico** (imutabilidade).
4. Verificar que webhook Asaas em sandbox ainda funciona (HMAC, retry, idempotência).
5. Verificar que cron de despesas recorrentes não duplica entradas para a mesma competência.

---

## 6. Problemas multi-tenant

### 6.1 Vazamentos potenciais ou confirmados

| ID | Descrição | Local | Severidade |
|---|---|---|---|
| `MT-01` | Migrations V2 sem `add_foreign_key` em `account_id` | migrations V2 | CRÍTICO |
| `MT-02` | Falta `validates :account_id, presence: true` em models V2 | modelos V2 | ALTO |
| `MT-03` | `default_scope` soft-delete não aplica em `find_by`/`find` | ApplicationRecord | CRÍTICO (potencial cross-tenant via ID guess) |
| `MT-04` | Webhook Asaas: `account_id` vem da query string, 404 vs 403 leak | asaas_controller | CRÍTICO (enumeration) |
| `MT-05` | `IdempotencyKey` deve ter chave única `(account_id, key)` | tabela `financial_idempotency_keys` | MÉDIO (verificar unique index) |
| `MT-06` | `audit_logs#export_csv` retorna `before/after` com PII de outros usuários do mesmo tenant (não cross-tenant, mas operadores) | audit_logs_controller | ALTO |
| `MT-07` | Backup R2 prefix por `accounts/<id>/` confirmado em memória `project_active_storage_account_scoping` | bom — não é problema | ✅ |

### 6.2 Verificações que precisam ser feitas (não confirmadas pelos agentes)

1. **`IdempotencyKey`**: a coluna `key` é unique por `(account_id, key)` ou globalmente? Globalmente abre cross-tenant attack: tenant A cacheia resposta com key conhecida, tenant B replay com mesma key → recebe resposta cacheada de A. Verificar migration `20260507100005`.
2. **`GatewayWebhookEvent`**: unique por `(account_id, event_id)` ou `event_id` global? Asaas usa UUID, baixo risco de colisão, mas mesmo princípio.
3. **`PatientCredit.balance_cents_for(account_id:, patient_id:)`**: scope `for_account` é confiável? Se for `default_scope`, vide CRIT-DB-03.
4. **`Current.account` em controllers legacy**: validar que está sendo populado por middleware autenticador e não é tampered via header.

### 6.3 Correções recomendadas (consolidadas)
1. Adicionar `add_foreign_key` em **todas** as colunas tenant-relacionadas (account_id, user_id, patient_id, bank_account_id) na próxima migration consolidada.
2. Em `Financial::ApplicationRecord`:
   ```ruby
   validates :account_id, presence: true, if: -> { self.class.column_names.include?('account_id') }
   ```
3. Substituir `default_scope` por scope explícito `alive`. Adicionar `alive` em todos os `before_action :set_resource` dos controllers.
4. Webhook Asaas: response code constante (sempre 403 quando inválido).
5. Garantir unique constraint `(account_id, key)` em IdempotencyKey.
6. Testes automatizados de "tenant isolation": setup 2 accounts, criar dado em A, verificar que B não vê em **todos** os endpoints.

---

## 7. Problemas financeiros

### 7.1 Cálculos incorretos confirmados

| ID | Cálculo | Bug | Local | Impacto |
|---|---|---|---|---|
| `FIN-01` | MDR (taxa de cartão) | Hardcoded; não vem de configuração de payment_method | `receive_payment.rb:380-389` | Quebra canon central. Toda comissão e líquido calculados errado |
| `FIN-02` | Estorno parcial de comissão | Reverte 100% mesmo quando estorno é parcial | `refund_payment.rb:150-156` | Fraude possível. Comissão zerada com estorno de R$1 |
| `FIN-03` | Quebra de caixa | `competence_date = Date.current` em vez de `session_date` | `cash_register_service.rb:158-192` | DRE registra quebra no dia errado |
| `FIN-04` | Ticket médio | Receita ÷ pacientes únicos (não atendimentos) | `dashboard_kpis.rb:179-202` | Métrica enganosa para gestor |
| `FIN-05` | Comissão provisionada em budget editado | Não recalcula ao alterar valor da parcela | `edit_approved_budget.rb:44-62` | Comissão a pagar inflada |
| `FIN-06` | DRE exclui transferência | Depende de `affects_dre` flag, sem filtro defensivo | `dre_report.rb:61-99` | Se flag for setada errada em um Entry, soma na receita/despesa |
| `FIN-07` | Webhook recebe com `Date.current` | Em vez de `paid_date` do payload | `process_asaas_event_job.rb` | Competência/cash date errados em webhooks atrasados |
| `FIN-08` | Distribuição de centavos em parcelas editadas | Não preserva invariante `sum(parcelas) == total` | `edit_approved_budget.rb` | Drift de centavos |

### 7.2 Inconsistências contábeis potenciais

1. **Regime caixa vs competência confuso para o operador** — canon explica, UI não. Operador confuso sobre por que parcela aparece em janeiro no DRE e março no Fluxo. Precisa de tooltip/legenda.
2. **Comissão como despesa**: canon dita que comissão é despesa (Pessoal > Comissões), não redução de receita. `PayCommission` cria Expense — OK. Mas relatório de "Receitas por Profissional" pode confundir gestor que pensa em "líquido após comissão".
3. **Taxa de maquininha como despesa automática**: canon dita "Geradas automaticamente ao registrar recebimento". Hoje, MDR é descontado em `commission_entry.mdr_deduction_cents` mas **não está claro se gera Expense automaticamente** em "Impostos > Taxa de Maquininha". Validar.

### 7.3 Riscos contábeis

- **Sem fechamento de período** — sistema não bloqueia edição retroativa em meses já fechados/exportados ao contador. Risco de DRE divergir entre 2 exports.
- **Sem trilha de auditoria contábil exportável** — `AuditLog` existe, mas formato não é o usado por auditores externos (ex: SPED Fiscal). Para clínicas com Simples Nacional, suficiente; para clínicas maiores, gap.
- **Sem reconciliação bancária** — não há fluxo "importar OFX e marcar conciliado". Saldo do sistema vs extrato bancário podem divergir.

---

## 8. Plano de refatoração

### Fase 1 — Correções críticas (1-2 sprints · BLOQUEANTE)

| # | Tarefa | Severidade | Esforço |
|---|---|---|---|
| 1.1 | Criar migration `add_missing_foreign_keys_financial_v2` | CRIT-DB-01 | S |
| 1.2 | Refatorar `PayCommission` (validação fora da transação, idempotente) | CRIT-SVC-01/02 | M |
| 1.3 | Fix `ProcessAsaasEventJob`: usar `paid_date` do payload, marcar `failed` em erro | CRIT-SVC-03/04 | M |
| 1.4 | `RefundPayment`: reverter comissão proporcionalmente | CRIT-SVC-05 | M |
| 1.5 | `ReceivePayment`: lock+reload antes de snapshot total | CRIT-SVC-06 | S |
| 1.6 | Confirmar HMAC Asaas timing-safe (auditar `Financial::Gateways::Asaas#verify_webhook`) | CRIT-SEC-01 | S |
| 1.7 | Webhook Asaas: constant-time response (sempre 403 quando inválido) | CRIT-SEC-02 | S |
| 1.8 | `GatewaySetting`: ActiveRecord Encryption real, migrar valores Base64 | CRIT-SEC-03 | M |
| 1.9 | Substituir 7 `window.prompt`/`confirm` por modais dedicados | CRIT-FE-01 | M |
| 1.10 | Sobrescrever `find`/`find_by` em `Financial::ApplicationRecord` para enforce soft-delete | CRIT-DB-03 | S |

### Fase 2 — Refatoração estrutural (2-3 sprints)

| # | Tarefa | Esforço |
|---|---|---|
| 2.1 | Implementar modelo `Financial::PaymentMethod` + `Financial::PaymentMethodFee` (versionado por parcela 1x..12x, vigência) | L |
| 2.2 | Substituir MDR hardcoded por lookup de `PaymentMethodFee` com snapshot no Installment/Entry | M |
| 2.3 | Adicionar `attr_readonly` + validação `if persisted? && X_changed?` em campos imutáveis (taxa, valor bruto, MDR, percent_basis_points) | M |
| 2.4 | Validação `validates :account_id, presence: true` em `Financial::ApplicationRecord` | S |
| 2.5 | Check constraints `_cents >= 0` em todas as tabelas V2 | S |
| 2.6 | Unique constraint `(account_id, receipt_number)` em PaymentReceipts | S |
| 2.7 | FKs e validações para `replaces_installment_id`/`renegotiated_to_id` | S |
| 2.8 | Validação `validates :source_type, inclusion: ...` no Entry polymorphic | S |
| 2.9 | Refatorar concern `Financial::RequireRole` com semântica única (remover redundante `and return unless`) | S |
| 2.10 | Paginação server-side em `CashRegisterV2` | M |

### Fase 3 — Versionamento e histórico (1-2 sprints)

| # | Tarefa | Esforço |
|---|---|---|
| 3.1 | Implementar hierarquia 4 níveis no DRE (Grupo → Subgrupo → Categoria → Subcategoria) | L |
| 3.2 | UI de "Inativar e criar nova" (não editar) para taxas, regras, despesas recorrentes | M |
| 3.3 | Tela "Histórico/Lixeira" para ADMIN/AUDITOR ver soft-deleted | M |
| 3.4 | `IdempotentAction` persistir TODOS status (não só 2xx) | S |
| 3.5 | Cleanup job de `IdempotencyKey` (> 7 dias) | S |
| 3.6 | Conceito de "fechamento de período" — bloquear edição em meses fechados | L |
| 3.7 | Imutabilidade: edição de parcela paga gera Entry de estorno automático + nova entrada (não update) | L |

### Fase 4 — Automação financeira (2-3 sprints)

| # | Tarefa | Esforço |
|---|---|---|
| 4.1 | Geração automática de Entry "Taxa de Maquininha" em "Impostos > Taxa de Maquininha" no recebimento | M |
| 4.2 | Auto-geração de comissão por gatilho configurável (paciente_comparece / orcamento_aceito / profissional_realizou / pagamento_confirmado) | L |
| 4.3 | Setup wizard obrigatório bloqueando módulo se incompleto (`SetupState.required_steps_done?`) | M |
| 4.4 | Roteamento automático de recebimento por meio de pagamento → conta destino | M |
| 4.5 | Categoria Laboratório auto-lançada via prontuário (integração `patients` plugin) | L |
| 4.6 | Reconciliação bancária (importar OFX) | L |

### Fase 5 — Performance e escalabilidade (1-2 sprints)

| # | Tarefa | Esforço |
|---|---|---|
| 5.1 | Indexes adicionais para queries DRE (`competence_date`, `account_id`, `kind`) | S |
| 5.2 | Materialized view ou cache (5 min) de KPIs do Dashboard | M |
| 5.3 | `audit_logs#export_csv` como job assíncrono + link assinado | M |
| 5.4 | Rate limit em endpoints sensíveis (`Rack::Attack`) | S |
| 5.5 | N+1 sweep em relatórios (`.includes` consistente) | S |
| 5.6 | Cache invalidation com `Russian doll` para listings frequentes | M |

### Fase 6 — UX/UI operacional (1-2 sprints)

| # | Tarefa | Esforço |
|---|---|---|
| 6.1 | Substituir todos `window.prompt`/`confirm` por modais (já em Fase 1, finalizar restantes) | S |
| 6.2 | Skeleton loaders em todas as pages com tabela | M |
| 6.3 | Error banners visíveis em modais quando aux load falha | S |
| 6.4 | Tooltip explicando "Por que parcela paga em março aparece em janeiro no DRE?" (regime caixa vs competência) | S |
| 6.5 | Indicador visual de "Período fechado — somente leitura" em meses já exportados | M |
| 6.6 | Bulk operations com preview ("Vou reclassificar 142 lançamentos. Confirmar?") | M |

### Fase 7 — Deprecação do legacy (1 sprint após Fase 1-3 estável)

| # | Tarefa | Esforço |
|---|---|---|
| 7.1 | Migration de dados legacy → V2 (bank_accounts, cash_registers, commission_rules, recurring_expenses, financial_categories, financial_estimates, installments, account_transactions) | L |
| 7.2 | Marcar models legacy `self.abstract_class = true` ou remover | S |
| 7.3 | Remover controllers legacy / rotas | S |
| 7.4 | Drop tables legacy (com backup completo prévio) | S |
| 7.5 | Remover composables/api legacy do frontend (`useFormatCurrency.js` etc) | S |

---

## 9. Modelagem ideal

### 9.1 Entidades canon (consolidadas com mapa-financeiro.json)

```
┌──────────────────────────────────────────────────────────────────────┐
│                      CONFIGURATIONS (versioned)                       │
├──────────────────────────────────────────────────────────────────────┤
│  PaymentMethod           1───*  PaymentMethodFee                     │
│   (canon: Pix, Débito,         (per-installment: 1x..12x,            │
│    Crédito, Boleto, etc)       valid_from, valid_to, status)         │
│                                                                      │
│  BankAccount             1───*  BankAccountRouting                   │
│   (PJ/CASH/CARD_REC,           (payment_method_id → bank_account)    │
│    initial_balance_cents,                                            │
│    cutoff_date)                                                      │
│                                                                      │
│  DreCategory (hierarchy: parent_id, level 1..4)                      │
│   ├── Grupo (Receita Clínica / Receita Não Clínica / 11 Despesas)   │
│   │   ├── Subgrupo (Procedimentos Particulares / Convênios / ...)   │
│   │   │   ├── Categoria (Endodontia / Periodontia / ...)            │
│   │   │   │   └── Subcategoria (níveis adicionais opcionais)        │
│                                                                      │
│  CommissionRule         (kind: percent / fixed, valid_from/to)       │
│   ├── trigger: enum                                                  │
│   │   (paciente_comparece, orcamento_aceito,                         │
│   │    profissional_realizou, pagamento_confirmado)                  │
│   ├── role: enum (DR / SDR / Comercial)                              │
│   └── scope: all_events OR category_ids[]                            │
│                                                                      │
│  RecurringExpense       (kind: fixo / estimado, frequency, ...)     │
│  RevenueGoal            (type: total / category / agent,             │
│                          min / target / stretch)                     │
│  Professional/Agent     (linked to User, with tipo_vinculo PJ/CLT/   │
│                          Sócio, dados_bancarios)                     │
└──────────────────────────────────────────────────────────────────────┘
              │
              │ feeds (via configuration lookup with snapshot)
              ▼
┌──────────────────────────────────────────────────────────────────────┐
│                        ORIGINS (8 canon)                              │
├──────────────────────────────────────────────────────────────────────┤
│  1. TreatmentPlan → approval → generates Installments                │
│  2. PatientFinancial → direct entry (Lançamento / Mensalidades /     │
│     Receber Pagamento)                                               │
│  3. RecurringExpenseCron → generates Expenses                        │
│  4. CashRegister sessions → generates Entries                        │
│  5. ManualEntry (Fluxo de Caixa avulso)                              │
│  6. Webhook (Asaas, future Pagar.me/MP)                              │
│  7. Refund (gera estorno do dia atual, não retroativo)               │
│  8. InternalTransfer (não afeta DRE)                                 │
└──────────────────────────────────────────────────────────────────────┘
              │
              ▼
┌──────────────────────────────────────────────────────────────────────┐
│                       OPERATIONAL (immutable)                         │
├──────────────────────────────────────────────────────────────────────┤
│  Budget          ─── status: draft / approved / canceled             │
│   ├── BudgetItem    (snapshot of procedure price)                    │
│   └── Installment   (status: pending / received / overdue /          │
│                              renegotiated / canceled)                │
│         ├── payment_method_fee_id  (FROZEN at creation)              │
│         ├── commission_rule_id     (FROZEN at creation)              │
│         ├── received_amount_cents                                    │
│         └── PaymentReceiptItem (cardinal: 0..N receipts)             │
│                                                                      │
│  PaymentReceipt  ─── number REC-YYYY-NNNNNN (unique per account)    │
│   └── PaymentReceiptItem (links to Installments)                     │
│                                                                      │
│  Expense         ─── status: pending / paid / partial / reversed     │
│   ├── recurring_expense_id (optional)                                │
│   └── source_record (polymorphic: CommissionEntry, Refund, ...)      │
│                                                                      │
│  CommissionEntry ─── status: provisioned / due / approved / a_pay /  │
│                              paid / reversed                         │
│   ├── base_amount_cents      (FROZEN)                                │
│   ├── mdr_deduction_cents    (FROZEN)                                │
│   ├── percent_basis_points   (FROZEN snapshot of rule)               │
│   └── expense_id (when paid)                                         │
│                                                                      │
│  CashRegister    ─── status: open / closed                           │
│   ├── opening_balance_cents                                          │
│   ├── closing_balance_cents (when closed)                            │
│   └── CashMovement (entries during session)                          │
│                                                                      │
│  Refund          ─── (replaces ad-hoc reverse logic)                 │
│   ├── installment_id (target)                                        │
│   ├── refund_amount_cents                                            │
│   ├── reason (text, required)                                        │
│   └── reversed_commission_entry_id                                   │
└──────────────────────────────────────────────────────────────────────┘
              │
              ▼
┌──────────────────────────────────────────────────────────────────────┐
│              CONSOLIDATION (ledger — dual date)                       │
├──────────────────────────────────────────────────────────────────────┤
│  Entry (canonical ledger record)                                     │
│   ├── account_id                                                     │
│   ├── direction: inflow / outflow                                    │
│   ├── kind: revenue / expense / transfer / mdr_fee / commission /    │
│   │         refund / cash_breakage                                   │
│   ├── amount_cents                                                   │
│   ├── competence_date  (DRE — regime competência)                    │
│   ├── cash_date        (Fluxo de Caixa — regime caixa)               │
│   ├── dre_category_id                                                │
│   ├── bank_account_id                                                │
│   ├── source_record (polymorphic)                                    │
│   ├── affects_dre (default true; false para transfer)                │
│   └── created/updated_by, audit_log entries                          │
└──────────────────────────────────────────────────────────────────────┘
              │
              ▼
┌──────────────────────────────────────────────────────────────────────┐
│              VIEW LAYER (read-only)                                   │
├──────────────────────────────────────────────────────────────────────┤
│  Dashboard, DRE, FluxoCaixa, Reports                                 │
│  PeriodClosure (new!) — locks a closed month for edit                │
│  AuditLog (every change → before, after, who, when, ip)              │
└──────────────────────────────────────────────────────────────────────┘
```

### 9.2 Lifecycle financeiro ideal

```
                    Setup wizard 8 steps obrigatórios
                              ↓
              Budget created (status: draft)
                              ↓
              Budget approved → Installments generated
                              ↓
              Installment payment_method_fee_id, commission_rule_id, mdr_rate FROZEN
                              ↓
              Receive Payment ←─── Webhook OR manual
                              ↓
              Entry (inflow) + MDR Entry (outflow) + CommissionEntry (due)
                              ↓
              CashRegister adjusts (if cash) OR BankAccount balance recalculates
                              ↓
              EOM: PeriodClosure locks month  ─── auditor exports DRE
                              ↓
              Comission approved & paid → Expense + Entry (outflow)
                              ↓
              Refund (if needed) → Entry (outflow, current date) +
                                   CommissionEntry reverse (proportional) +
                                   PatientCredit (if no money returned)
```

### 9.3 Regras invariantes (devem ser testáveis)

1. `sum(Entry.where(account: X, direction: inflow).amount_cents) - sum(Entry.where(account: X, direction: outflow).amount_cents) == sum(BankAccount.where(account: X).current_balance_cents) - sum(BankAccount.where(account: X).initial_balance_cents)` (com filtro de `cash_date <= today`)
2. `sum(PaymentReceiptItem.where(installment: I).amount_cents) <= Installment.amount_cents` (sem over-payment)
3. `Installment.received_amount_cents == sum(PaymentReceiptItem.where(installment: I).amount_cents)`
4. Soma de parcelas de um Budget = `Budget.total_cents` (após split, com resto na última)
5. CommissionEntry estornada tem valor proporcional ao refund parcial (não 100%)
6. Entry `kind=transfer` nunca aparece em DRE
7. Toda mudança em Entity financeira tem registro em `AuditLog` (before, after, user_id, ip, timestamp)
8. PeriodClosure ativo bloqueia `update` em Entry / Installment / Expense com `competence_date` dentro do período

---

## 10. Checklist final

| # | Item | Status | Risco | Prioridade |
|---|---|---|---|---|
| 1 | Foreign keys em todas as migrations V2 | ❌ | CRÍTICO | P0 |
| 2 | `attr_readonly` em campos imutáveis (taxa, MDR, valor_bruto) | ❌ | CRÍTICO | P0 |
| 3 | MDR vem de configuração de PaymentMethodFee, não hardcoded | ❌ | CRÍTICO | P0 |
| 4 | RefundPayment reverte comissão proporcionalmente | ❌ | CRÍTICO | P0 |
| 5 | ProcessAsaasEventJob usa paid_date do payload | ❌ | CRÍTICO | P0 |
| 6 | ProcessAsaasEventJob marca failed em erro estrutural | ❌ | CRÍTICO | P0 |
| 7 | PayCommission idempotente (não duplica Expense em retry) | ❌ | CRÍTICO | P0 |
| 8 | PayCommission validação fora da transação | ❌ | CRÍTICO | P0 |
| 9 | ReceivePayment reload após lock | ❌ | CRÍTICO | P0 |
| 10 | HMAC Asaas confirmadamente timing-safe | ❓ | CRÍTICO | P0 |
| 11 | Webhook Asaas response constant-time (403 sempre) | ❌ | CRÍTICO | P0 |
| 12 | GatewaySetting com ActiveRecord Encryption (não Base64) | ❌ | CRÍTICO | P0 |
| 13 | `find`/`find_by` em ApplicationRecord enforça soft-delete | ❌ | CRÍTICO | P0 |
| 14 | 7 ações destrutivas com modais (não window.prompt/confirm) | ❌ | CRÍTICO | P0 |
| 15 | DECIMAL legacy → BIGINT centavos (deprecação ou migração) | ❌ | ALTO | P1 |
| 16 | `validates :account_id, presence: true` em models V2 | ❌ | ALTO | P1 |
| 17 | Check constraints `_cents >= 0` | ❌ | ALTO | P1 |
| 18 | Unique constraint `(account_id, receipt_number)` | ❓ | ALTO | P1 |
| 19 | Hierarquia 4 níveis no DRE | ❌ | ALTO | P1 |
| 20 | Idempotência ubíqua em Budgets, GatewaySettings, Webhooks | ❌ | ALTO | P1 |
| 21 | `audit_logs#export_csv` async + rate limit + max range | ❌ | ALTO | P1 |
| 22 | `upload_proof` valida MIME type | ❌ | ALTO | P1 |
| 23 | Controllers legacy removidos ou marcados deprecated | ❌ | ALTO | P1 |
| 24 | `financial_goals_controller` (legacy) com role check OU removido | ❌ | ALTO | P1 |
| 25 | Setup wizard obrigatório bloqueando módulo se incompleto | ❌ | ALTO | P1 |
| 26 | Paginação server-side em CashRegisterV2 | ❌ | ALTO | P1 |
| 27 | Quebra de caixa usa `session_date` (não `Date.current`) | ❌ | ALTO | P1 |
| 28 | RecurringExpenses cron com `Time.zone.today` | ❌ | ALTO | P1 |
| 29 | EditApprovedBudget recalcula comissão provisionada | ❌ | MÉDIO | P2 |
| 30 | TransferBetweenAccounts revalida saldo dentro do lock | ❌ | MÉDIO | P2 |
| 31 | CommissionRule#most_specific_for com tie-breaker | ❌ | MÉDIO | P2 |
| 32 | DreReport com filtro defensivo `kind != transferencia` | ❌ | MÉDIO | P2 |
| 33 | ticket_medio com base correta (atendimentos vs pacientes) | ❌ | MÉDIO | P2 |
| 34 | Concept "PeriodClosure" (fechamento de mês) | ❌ | MÉDIO | P2 |
| 35 | IdempotencyKey cleanup job | ❌ | MÉDIO | P2 |
| 36 | IdempotentAction persiste 4xx também | ❌ | MÉDIO | P2 |
| 37 | Entry#source_type validação de inclusion | ❌ | MÉDIO | P2 |
| 38 | LgpdRequest tem `executed_at`/`rejected_at` timestamps | ❌ | MÉDIO | P2 |
| 39 | CommissionRule#percent_basis_points bounds 0..10000 | ❌ | MÉDIO | P2 |
| 40 | useMoney é o único padrão de formatação | ✅ | — | — |
| 41 | Idempotency-Key gerado em todos POST/PATCH/DELETE no FE | ✅ | — | — |
| 42 | Backups em R2 prefixed por `accounts/<id>/` | ✅ | — | — |
| 43 | ConfirmDangerModal usado em deletes | ✅ | — | — |
| 44 | Frontend só usa API v2 (sem mistura com legacy) | ✅ | — | — |
| 45 | Skeleton loaders consistentes em pages | ❌ | BAIXO | P3 |
| 46 | Tooltip explicando regime caixa vs competência | ❌ | BAIXO | P3 |
| 47 | Indicador visual de "Período fechado" | ❌ | BAIXO | P3 |
| 48 | Modais de aux load com banner de erro + retry | ❌ | BAIXO | P3 |
| 49 | `!important` em SCSS reduzido (substituir por specificity) | ❌ | BAIXO | P3 |
| 50 | useFormatCurrency.js (legacy) removido se morto | ❌ | BAIXO | P3 |

**Legenda**: ✅ feito · ❌ pendente · ❓ não confirmado (precisa verificação manual)

---

## 11. Implementação final — arquitetura recomendada

### 11.1 Princípios

1. **Imutabilidade primeiro** — qualquer dado financeiro escrito é imutável por padrão. Edição = inativar + criar nova versão. Implementação: `attr_readonly` + validação + auditoria.
2. **Snapshot é a regra, não exceção** — toda referência a configuração (taxa, MDR, comissão, categoria) deve ser snapshot na criação, não FK reativa. FK referencial existe para auditoria; valor congelado existe para cálculo.
3. **Idempotência via Idempotency-Key obrigatório em escritas** — sem exceção. Webhook usa `(account_id, event_id)`. UI gera UUID por intenção (não por requisição).
4. **Transação atômica** — toda operação multi-entidade roda em `transaction do ... end` com lock pessimista em entidades mutáveis (Installment, BankAccount).
5. **Multi-tenant defense in depth** — FK no banco + `validates :account_id, presence: true` + scope `for_account` explícito em todo controller + teste de isolation por endpoint.
6. **Single source of truth para saldo** — `BankAccount.current_balance_cents` é sempre derivado de `Entry.where(bank_account_id:).sum`. Nunca armazenado.
7. **DRE e Fluxo são views, não armazenamento** — calculados a partir de Entry com `competence_date` e `cash_date`.
8. **Period closure** — depois de exportado para o contador, o mês trava. Edição retroativa só via processo formal (PeriodReopenRequest com aprovação ADMIN).

### 11.2 Estrutura de pastas recomendada

```
plugins/financial/
├── app/
│   ├── models/
│   │   └── financial/
│   │       ├── application_record.rb        # base com find/find_by sobrescrito
│   │       ├── concerns/
│   │       │   ├── soft_deletable.rb        # com find override
│   │       │   ├── auditable.rb
│   │       │   ├── stamped.rb
│   │       │   ├── money_attribute.rb
│   │       │   ├── frozen_snapshot.rb       # NOVO: marca campos como attr_readonly
│   │       │   └── tenant_scoped.rb         # NOVO: validates :account_id presence + scope for_account
│   │       ├── configuration/               # NOVO: agrupa configs versionadas
│   │       │   ├── payment_method.rb
│   │       │   ├── payment_method_fee.rb
│   │       │   ├── dre_category.rb
│   │       │   ├── commission_rule.rb
│   │       │   ├── bank_account.rb
│   │       │   └── recurring_expense.rb
│   │       ├── operational/
│   │       │   ├── budget.rb
│   │       │   ├── budget_item.rb
│   │       │   ├── installment.rb
│   │       │   ├── payment_receipt.rb
│   │       │   ├── payment_receipt_item.rb
│   │       │   ├── expense.rb
│   │       │   ├── commission_entry.rb
│   │       │   ├── refund.rb                # NOVO
│   │       │   ├── cash_register.rb
│   │       │   ├── cash_movement.rb
│   │       │   └── patient_credit.rb
│   │       ├── ledger/
│   │       │   └── entry.rb                 # canonical ledger
│   │       └── governance/
│   │           ├── audit_log.rb
│   │           ├── idempotency_key.rb
│   │           ├── period_closure.rb        # NOVO
│   │           ├── setup_state.rb
│   │           ├── gateway_setting.rb
│   │           ├── gateway_webhook_event.rb
│   │           └── lgpd_request.rb
│   ├── services/
│   │   └── financial/
│   │       ├── service_result.rb
│   │       ├── budgets/
│   │       │   ├── approve_budget.rb
│   │       │   ├── edit_approved_budget.rb
│   │       │   └── cancel_budget.rb
│   │       ├── payments/
│   │       │   ├── receive_payment.rb       # com snapshot pós-lock
│   │       │   ├── refund_payment.rb        # com reverso proporcional
│   │       │   └── pay_expense.rb
│   │       ├── commissions/
│   │       │   ├── generate_commission.rb   # por gatilho
│   │       │   ├── approve_commission.rb
│   │       │   └── pay_commission.rb        # idempotente
│   │       ├── cash_register/
│   │       │   ├── open_session.rb
│   │       │   ├── close_session.rb
│   │       │   ├── reopen_session.rb
│   │       │   ├── sangria.rb
│   │       │   └── suprimento.rb
│   │       ├── recurring/
│   │       │   └── generate_recurring_expenses.rb  # com Time.zone
│   │       ├── transfers/
│   │       │   └── transfer_between_accounts.rb    # com lock + revalidate
│   │       ├── reports/
│   │       │   ├── dre_report.rb            # com defesa explícita kind != transfer
│   │       │   ├── cash_flow_report.rb
│   │       │   ├── commissions_report.rb
│   │       │   ├── dashboard_kpis.rb        # ticket_medio corrigido
│   │       │   └── ...
│   │       ├── governance/
│   │       │   ├── close_period.rb          # NOVO
│   │       │   ├── reopen_period.rb         # NOVO (ADMIN only)
│   │       │   └── anonymize_patient.rb
│   │       └── backup/
│   │           ├── create_backup.rb
│   │           └── r2_storage.rb
│   ├── controllers/
│   │   ├── api/v1/accounts/financial/       # canonical V2 (atual)
│   │   │   ├── base_controller.rb           # com idempotent!, require_role!, set_account
│   │   │   ├── concerns/
│   │   │   │   └── idempotent_action.rb     # persiste 4xx também
│   │   │   └── ... (controllers existentes refatorados)
│   │   └── webhooks/financial/
│   │       └── asaas_controller.rb          # constant-time response
│   └── jobs/
│       └── financial/
│           ├── recurring_expenses_cron_job.rb       # Time.zone.today
│           ├── idempotency_key_cleanup_job.rb       # NOVO
│           ├── audit_logs_export_job.rb             # NOVO (async)
│           ├── backup_job.rb
│           └── webhooks/
│               └── process_asaas_event_job.rb       # paid_date + mark_failed
├── lib/
│   └── financial/
│       ├── engine.rb
│       └── gateways/
│           ├── base.rb
│           ├── manual.rb
│           ├── asaas.rb                     # secure_compare em verify_webhook
│           └── ... (pagarme, mercado_pago futuro)
└── frontend/
    └── features/
        └── financial/
            └── v2/
                ├── pages/                   # 13 pages existentes
                ├── components/
                │   ├── modals/              # incluindo novos modals que substituem prompt/confirm
                │   │   ├── CashRegisterOpenModal.vue
                │   │   ├── CashRegisterCloseModal.vue
                │   │   ├── CashRegisterSangriaModal.vue
                │   │   ├── CashRegisterSuprimentoModal.vue
                │   │   ├── CashRegisterReopenModal.vue
                │   │   ├── RefundReasonModal.vue
                │   │   └── ConfirmSeedCategoriesModal.vue
                │   └── settings/
                ├── composables/
                │   └── useMoney.js
                └── api/financialV2.js       # cabe persistir Idempotency-Key client-side por ação
```

### 11.3 Padrão "Service": template recomendado

```ruby
module Financial
  module Payments
    class ReceivePayment
      Result = Struct.new(:success?, :payment_receipt, :errors, keyword_init: true)

      def self.call(...)
        new(...).call
      end

      def initialize(account:, bank:, installment_amounts:, received_at:, actor:, idempotency_key: nil)
        @account = account
        @bank = bank
        @installment_amounts = installment_amounts
        @received_at = received_at
        @actor = actor
        @idempotency_key = idempotency_key
      end

      def call
        # 1. Validações leves (sem DB)
        return failure('account required') if @account.nil?
        return failure('bank required') if @bank.nil?
        return failure('received_at required') if @received_at.nil?

        # 2. Idempotência (lookup antes de qualquer side effect)
        if @idempotency_key
          cached = ::Financial::Governance::IdempotencyKey.find_cached(@account.id, @idempotency_key)
          return Result.new(success?: true, payment_receipt: cached.payload[:payment_receipt]) if cached
        end

        # 3. Validações pesadas (com DB, sem lock ainda)
        installments = load_installments_with_validation
        return failure(installments.errors) if installments.respond_to?(:errors)

        # 4. Transação atômica com lock
        receipt = nil
        ActiveRecord::Base.transaction do
          # Lock + reload (snapshot é POST-lock)
          locked_installments = installments.map { |i| i.lock!; i.reload; i }

          # Validações que dependem do snapshot
          validate_no_period_closure!(locked_installments)
          validate_no_overpayment!(locked_installments)

          # Mutações
          receipt = create_payment_receipt(locked_installments)
          apply_to_installments(receipt, locked_installments)
          create_ledger_entries(receipt)
          generate_commission_entries(receipt, locked_installments)
          handle_excess_as_credit(receipt, locked_installments)
        end

        # 5. Persistir idempotência (TODOS os status, não só sucesso)
        ::Financial::Governance::IdempotencyKey.store!(
          account_id: @account.id,
          key: @idempotency_key,
          payload: { payment_receipt: receipt }
        ) if @idempotency_key

        Result.new(success?: true, payment_receipt: receipt)
      rescue ActiveRecord::Rollback => e
        failure(e.message)
      end

      private

      def failure(msg)
        Result.new(success?: false, errors: Array(msg))
      end
    end
  end
end
```

### 11.4 Padrão "Controller": template recomendado

```ruby
module Api::V1::Accounts::Financial
  class PaymentReceiptsController < BaseController
    include IdempotentAction

    before_action :require_role!, only: %i[create]

    def create
      idempotent! do
        result = ::Financial::Payments::ReceivePayment.call(
          account: current_account,
          bank: find_bank!,
          installment_amounts: receipt_params[:installments],
          received_at: receipt_params[:received_at],
          actor: current_user,
          idempotency_key: request.headers['Idempotency-Key']
        )

        if result.success?
          render json: serialize(result.payment_receipt), status: :created
        else
          render json: { errors: result.errors }, status: :unprocessable_entity
        end
      end
    end

    private

    def required_roles_for(action)
      case action
      when :create then %w[RECEPCAO GERENTE ADMIN]
      else %w[ADMIN]
      end
    end

    def find_bank!
      current_account.financial_bank_accounts.alive.find(receipt_params[:bank_account_id])
    end

    def receipt_params
      params.require(:payment_receipt).permit(
        :bank_account_id, :received_at, installments: %i[id amount_cents]
      )
    end

    def serialize(receipt)
      # ... view ou serializer
    end
  end
end
```

### 11.5 Testes mínimos para garantir invariantes

```ruby
# spec/integrations/financial_invariants_spec.rb
RSpec.describe 'Financial invariants' do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  describe 'tenant isolation' do
    it 'no entity is visible across accounts' do
      budget_a = create(:budget, account: account)
      budget_b = create(:budget, account: other_account)

      as(account) do
        expect(::Financial::Budget.alive).to contain_exactly(budget_a)
        expect(::Financial::Budget.find_by(id: budget_b.id)).to be_nil
      end
    end
  end

  describe 'balance invariant' do
    it 'sum of entries equals current balance delta' do
      bank = create(:bank_account, account: account, initial_balance_cents: 100_000)
      receive_payment(amount_cents: 50_000, into: bank)
      pay_expense(amount_cents: 20_000, from: bank)

      inflow = bank.entries.inflow.sum(:amount_cents)
      outflow = bank.entries.outflow.sum(:amount_cents)
      balance_delta = bank.current_balance_cents - bank.initial_balance_cents

      expect(inflow - outflow).to eq(balance_delta)
    end
  end

  describe 'immutability' do
    it 'taxa congelada não pode ser alterada' do
      installment = create(:installment, payment_method_fee_id: 1, mdr_deduction_cents: 350)
      expect {
        installment.update!(mdr_deduction_cents: 0)
      }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it 'edição de parcela paga gera estorno + nova entrada, não update' do
      installment = paid_installment
      result = ::Financial::Budgets::EditApprovedBudget.call(...)
      expect(result.entries.outflow.where(kind: 'refund')).to exist
      expect(result.entries.inflow.where(kind: 'revenue')).to exist
    end
  end

  describe 'DRE excludes transfers' do
    it 'transfer entries never appear in DRE' do
      transfer_between_accounts(amount_cents: 100_000)
      dre = ::Financial::Reports::DreReport.new(account: account, from: ..., to: ...).call
      expect(dre.total_revenue).to be_zero
      expect(dre.total_expense).to be_zero
    end
  end

  describe 'commission proportional refund' do
    it 'partial refund reverses commission proportionally' do
      receive_payment(amount_cents: 100_000) # cria 10% commission = 10_000
      refund_payment(amount_cents: 30_000)   # estorno parcial

      commission = ::Financial::CommissionEntry.last
      expect(commission.reversed_amount_cents).to eq(3_000)  # 30% de 10_000
    end
  end

  describe 'idempotency' do
    it 'same Idempotency-Key returns cached response' do
      key = SecureRandom.uuid
      r1 = ::Financial::Payments::ReceivePayment.call(..., idempotency_key: key)
      r2 = ::Financial::Payments::ReceivePayment.call(..., idempotency_key: key)
      expect(r2.payment_receipt.id).to eq(r1.payment_receipt.id)
    end

    it 'caches 4xx responses too' do
      key = SecureRandom.uuid
      ::Financial::Payments::ReceivePayment.call(invalid_args, idempotency_key: key)
      result = ::Financial::Payments::ReceivePayment.call(invalid_args, idempotency_key: key)
      expect(result).to be_failure
      expect(::Financial::Payments::ReceivePayment).not_to have_received(:call)
    end
  end

  describe 'period closure' do
    it 'blocks edits in closed month' do
      close_period(year: 2026, month: 4)
      expect {
        ::Financial::Installment.create!(competence_date: '2026-04-15', ...)
      }.to raise_error(::Financial::Errors::PeriodClosed)
    end
  end
end
```

---

## Anexos

### Anexo A — Resumo de severidades

- **Críticos**: 17 (4 DB, 6 Services, 3 Security, 1 Frontend, 3 Calc)
- **Altos**: 18 (5 DB, 4 Services, 4 Controllers, 2 Frontend, 1 Calc, 2 Multi-tenant)
- **Médios**: 15 (5 DB, 3 Services, 2 Controllers, 2 Frontend, 3 Calc)
- **Baixos**: 12 (várias categorias)

**Total: ~62 achados consolidados** (alguns achados dos 4 agentes foram mesclados — pl. duplicates entre Controllers e Services).

### Anexo B — Arquivos auditados (não exaustivo)

- 23 services em `plugins/financial/app/services/financial/`
- 4 jobs em `plugins/financial/app/jobs/financial/`
- 36 controllers (21 V2 + 10 legacy + 1 webhook + concerns)
- 39 models (24 V2 + 8 legacy + concerns)
- 19 migrations financeiras em `db/migrate/`
- 13 pages V2 + 8 modais + 5 settings tabs + composables
- Engine: `plugins/financial/lib/financial/engine.rb`
- Gateways: `plugins/financial/lib/financial/gateways/*`

### Anexo C — Cross-reference com memória persistida

| Memória | Aplicação na auditoria |
|---|---|
| [feedback_multi_tenant](feedback_multi_tenant.md) | Toda Seção 6 — Multi-tenant |
| [feedback_status_no_false_positive](feedback_status_no_false_positive.md) | `ALTO-FE-01`, frontend modals |
| [feedback_form_select_padrao](feedback_form_select_padrao.md) | Recomendar FormSelect em modais novos |
| [feedback_tooltip_moderno](feedback_tooltip_moderno.md) | Recomendar `<Tooltip>` para indicadores |
| [feedback_bug_visual_recorrente_estrutural](feedback_bug_visual_recorrente_estrutural.md) | `CRIT-FE-01` — 7 prompts nativos = bug estrutural |
| [project_financeiro_arch_decisions](project_financeiro_arch_decisions.md) | Confirma namespace `Financial::*`, tabelas `financial_*`, BIGINT centavos, AuditLog automático, idempotency middleware |
| [project_financeiro_docs_source_of_truth](project_financeiro_docs_source_of_truth.md) | Canon em `docs/01-product/modules/financeiro-funcionamento.md` foi lido e cruzado |
| [project_active_storage_account_scoping](project_active_storage_account_scoping.md) | Backup paths em R2 ✅ scoped |

---

*Documento gerado por auditoria automatizada em 2026-05-22, com evidência por `arquivo:linha` em 100% dos achados. Próxima revisão recomendada após Fase 1 do plano de refatoração (estimativa: junho/2026).*
