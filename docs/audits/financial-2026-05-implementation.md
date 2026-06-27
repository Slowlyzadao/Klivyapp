# Implementação técnica — Módulo Financeiro (Klivy v2 canon)

> Data: 2026-05-22
> Documento companheiro de: [financial-2026-05.md (auditoria)](financial-2026-05.md)
> Fonte de verdade: [mapa-financeiro.json](../../mapa-financeiro.json) + [docs/01-product/modules/financeiro-funcionamento.md](../01-product/modules/financeiro-funcionamento.md)
> Premissa: **módulo ainda não tem cliente real em produção** — podemos fazer breaking changes sem plano de migração de dados.

---

## 0. Sumário de decisões arquiteturais

| Decisão | Escolha | Razão |
|---|---|---|
| **Legacy** | **Drop total** (drop migrations + models + controllers + tabelas) | Sem cliente real, sem migração de dados; legacy só agrega dívida |
| **Importação de clínicas (Clinicorp, Eddental, etc)** | Via tool externa `/super_admin/migrations` (já existente) | Não é responsabilidade do módulo financeiro; consome os endpoints V2 via API |
| **Procedimentos / Serviços** | **Nome em `agenda` (`AgendaService`) · Valor + DRE category + comissão em `financial` (`Financial::ServicePricing`, 1-to-1)** | Separação de domínio: agenda controla agendabilidade (nome, duração, cor, salas); financeiro controla preço + categoria contábil. Campo `price` em `agenda_services` será **removido** na Sprint 2. |
| **Profissional / Agente** | **User core do Klivy** (já gerenciado em `/api/v1/accounts/:id/agents`) **+ extensão `Financial::AgentProfile`** (1-to-1) para campos canon `tipo_vinculo` (PJ/CLT/Sócio), `data_entrada`, `categoria_agente`, `comissionado`, dados bancários para pagamento de comissão | Não duplica usuários; complementa com o que é específico do financeiro |
| **Namespace Ruby** | `Financial::*` único | Único caminho para tudo no módulo |
| **Tabelas DB** | `financial_*` único | Sem dual schema |
| **Valores monetários** | `BIGINT` em centavos sempre | Sem float, sem decimal |
| **Imutabilidade** | `attr_readonly` + validação `if persisted? && X_changed?` + auditoria | Defesa em profundidade |
| **Soft delete** | Sempre via `deleted_at` + `deleted_by_id`; `find`/`find_by` sobrescritos | `default_scope` é traiçoeiro |
| **Multi-tenant** | FK no banco + `validates :account_id` + scope explícito `for_account` em controllers + teste de isolation por endpoint | Regra dura |
| **Idempotência** | Concern `IdempotentAction` em **todas** ações de escrita; persistir 4xx também | Retry com mesmo key não pode reexecutar |
| **Transações** | `ActiveRecord::Base.transaction` + lock pessimista + reload pós-lock | Race conditions financeiras = corrupção |
| **Audit log** | Automático via concern `Auditable` em **todos** modelos V2 | Trilha contábil obrigatória |
| **MDR e taxas** | Configuração versionada `PaymentMethodFee` + snapshot no Installment | Canon central — taxa congela no lançamento |
| **Comissões** | Snapshot da regra (`rule_snapshot` jsonb) no momento do gatilho + estorno proporcional | Mudança de regra não altera histórico |
| **DRE** | Hierarquia 4 níveis via `parent_id` recursivo + `path` materializado para queries | Mapa canon exige 4 níveis |
| **Period closure** | Entidade `PeriodClosure` + middleware que bloqueia edição retroativa | Compliance contábil |
| **Webhooks** | Idempotência por `(account_id, event_id)` + constant-time response + HMAC `secure_compare` + fila com `discard_on`/`retry_on` configurados | Surface pública crítica |
| **Frontend** | Sem `window.prompt`/`confirm`; modais dedicados + `useMoney` + `FormSelect` + `<Tooltip>` | Memória `bug_visual_recorrente_estrutural` |
| **Setup wizard** | Obrigatório, bloqueia módulo via `before_action :ensure_setup_complete!` | Canon §6 — Wizard de configuração inicial |

---

## 1. Princípios de design

### 1.1 Single source of truth
- **Saldo de conta** = soma de `Entry.where(bank_account_id:)` (nunca armazenado).
- **A Receber** = soma de `Installment.alive.open` (calculado).
- **DRE** = projeção de `Entry.alive.where(affects_dre: true)` por `competence_date`.
- **Fluxo de Caixa** = projeção de `Entry.alive` por `cash_date`.

Único lugar onde o dado vive é o ledger (`financial_entries`). Configurações (BankAccount, PaymentMethod, etc.) são metadados — não dados financeiros.

### 1.2 Imutabilidade primeiro
Qualquer dado financeiro:
- **Cria** = novo registro
- **Edita** = inativar + criar novo
- **Exclui** = soft delete + audit log; nunca DELETE físico
- **Estorna** = entrada reversa do dia atual; nunca update no histórico

### 1.3 Snapshot é regra
Toda referência a configuração mutável (taxa, regra de comissão, categoria) gera um **snapshot** (jsonb ou colunas dedicadas) no momento da operação. FK ao registro original existe apenas para rastreabilidade — o valor congelado é o que importa para o cálculo.

### 1.4 Atomicidade absoluta
Operação que toca > 1 modelo:
1. Validações fora da transação
2. `transaction do ... end`
3. Locks pessimistas em ordem estável (sempre `account_id` primeiro, depois IDs ascendentes)
4. Reload pós-lock
5. Mutações
6. `rescue ActiveRecord::Rollback`

### 1.5 Idempotência ubíqua
- Frontend gera `Idempotency-Key` UUID **por intenção** (não por requisição — retry com mesmo key implica "mesma intenção")
- Backend: concern `IdempotentAction` em todo POST/PATCH/DELETE
- Cache de resposta inclui **todos** status codes (2xx + 4xx); 5xx não cacheia (transient)
- TTL = 24h; cleanup job semanal

### 1.6 Multi-tenant defense in depth
1. FK `add_foreign_key on_delete: :restrict` em toda coluna `account_id`
2. `validates :account_id, presence: true` em `Financial::ApplicationRecord` para qualquer modelo com a coluna
3. Scope explícito `for_account(current_account.id)` em todo controller (não `default_scope`)
4. Teste de isolation automatizado: para cada endpoint, criar dado em A, autenticar como B, esperar 404
5. Webhook: `account_id` validado contra `GatewaySetting` antes de qualquer SELECT

### 1.7 Status nunca mente
Memória `feedback_status_no_false_positive`: toast/snackbar reflete o que **de fato aconteceu**. Se webhook é fire-and-forget, toast = "Solicitação enviada", não "Concluído". `Sucesso` só após confirmação real.

---

## 2. Modelagem de dados (schema final)

### 2.1 Convenções de coluna

Toda tabela `financial_*` inclui obrigatoriamente:

| Coluna | Tipo | Notas |
|---|---|---|
| `id` | bigserial PK | |
| `account_id` | bigint NOT NULL | FK `accounts(id)` `on_delete: :restrict` |
| `created_at` | timestamp NOT NULL | |
| `updated_at` | timestamp NOT NULL | |
| `created_by_id` | bigint NULL | FK `users(id)` `on_delete: :nullify` |
| `updated_by_id` | bigint NULL | FK `users(id)` `on_delete: :nullify` |
| `deleted_at` | timestamp NULL | Soft delete |
| `deleted_by_id` | bigint NULL | FK `users(id)` `on_delete: :nullify` |
| `lock_version` | integer NOT NULL DEFAULT 0 | Optimistic locking (Rails built-in) |

Toda tabela com valor monetário usa `_cents BIGINT NOT NULL`. Nunca `DECIMAL`, nunca `FLOAT`.

### 2.2 Schema completo (DDL)

#### 2.2.1 Configurações versionadas

```sql
-- financial_dre_categories (hierarquia 4 níveis)
CREATE TABLE financial_dre_categories (
  id              bigserial PRIMARY KEY,
  account_id      bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  parent_id       bigint NULL REFERENCES financial_dre_categories(id) ON DELETE RESTRICT,
  path            varchar(512) NOT NULL,  -- materialized path: "/1/4/12/47"
  level           integer NOT NULL CHECK (level BETWEEN 1 AND 4),
  kind            varchar(32) NOT NULL CHECK (kind IN ('revenue', 'expense', 'transfer_internal', 'breakage')),
  name            varchar(120) NOT NULL,
  code            varchar(32) NULL,  -- código contábil opcional
  status          varchar(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  system_default  boolean NOT NULL DEFAULT false,  -- "Sem categoria" e seeds canon = não pode deletar/renomear
  position        integer NOT NULL DEFAULT 0,
  -- conventional columns
  created_at      timestamp NOT NULL,
  updated_at      timestamp NOT NULL,
  created_by_id   bigint NULL REFERENCES users(id),
  updated_by_id   bigint NULL REFERENCES users(id),
  deleted_at      timestamp NULL,
  deleted_by_id   bigint NULL REFERENCES users(id),
  lock_version    integer NOT NULL DEFAULT 0
);

CREATE UNIQUE INDEX idx_dre_categories_account_path ON financial_dre_categories(account_id, path) WHERE deleted_at IS NULL;
CREATE INDEX idx_dre_categories_account_parent ON financial_dre_categories(account_id, parent_id);
CREATE INDEX idx_dre_categories_account_kind ON financial_dre_categories(account_id, kind) WHERE deleted_at IS NULL;
```

```sql
-- financial_bank_accounts
CREATE TABLE financial_bank_accounts (
  id                          bigserial PRIMARY KEY,
  account_id                  bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  kind                        varchar(32) NOT NULL CHECK (kind IN ('checking', 'savings', 'cash', 'card_receivable', 'digital_wallet')),
  name                        varchar(120) NOT NULL,
  color                       varchar(16) NULL,
  icon                        varchar(64) NULL,
  bank_name                   varchar(120) NULL,
  agency                      varchar(20) NULL,
  account_number              varchar(40) NULL,
  account_holder_document     varchar(32) NULL,  -- CNPJ
  pix_key                     varchar(120) NULL,
  initial_balance_cents       bigint NOT NULL DEFAULT 0,
  cutoff_date                 date NOT NULL,  -- "Tudo antes dessa data o sistema não sabe"
  is_default_inflow           boolean NOT NULL DEFAULT false,
  is_default_outflow          boolean NOT NULL DEFAULT false,
  show_in_cash_flow           boolean NOT NULL DEFAULT true,
  status                      varchar(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  -- conventional columns
  created_at                  timestamp NOT NULL,
  updated_at                  timestamp NOT NULL,
  created_by_id               bigint NULL REFERENCES users(id),
  updated_by_id               bigint NULL REFERENCES users(id),
  deleted_at                  timestamp NULL,
  deleted_by_id               bigint NULL REFERENCES users(id),
  lock_version                integer NOT NULL DEFAULT 0,
  CHECK (initial_balance_cents >= 0)
);

CREATE UNIQUE INDEX idx_bank_accounts_account_name ON financial_bank_accounts(account_id, lower(name)) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_bank_accounts_default_inflow ON financial_bank_accounts(account_id) WHERE is_default_inflow = true AND deleted_at IS NULL;
CREATE UNIQUE INDEX idx_bank_accounts_default_outflow ON financial_bank_accounts(account_id) WHERE is_default_outflow = true AND deleted_at IS NULL;
```

```sql
-- financial_payment_methods (Pix, Débito, Crédito, Boleto, Dinheiro, Transferência, Convenio, ParcelamentoProprio)
CREATE TABLE financial_payment_methods (
  id              bigserial PRIMARY KEY,
  account_id      bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  kind            varchar(32) NOT NULL CHECK (kind IN ('dinheiro', 'pix', 'debito', 'credito', 'boleto', 'transferencia', 'convenio', 'parcelamento_proprio')),
  name            varchar(120) NOT NULL,  -- "Cielo Crédito", "Pix Banco Itaú"
  provider        varchar(80) NULL,        -- Cielo, GetNet, Itaú, etc.
  default_bank_account_id bigint NULL REFERENCES financial_bank_accounts(id) ON DELETE RESTRICT,
  supports_installments boolean NOT NULL DEFAULT false,
  max_installments     integer NOT NULL DEFAULT 1 CHECK (max_installments BETWEEN 1 AND 24),
  status               varchar(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  -- conventional columns
  created_at      timestamp NOT NULL,
  updated_at      timestamp NOT NULL,
  created_by_id   bigint NULL REFERENCES users(id),
  updated_by_id   bigint NULL REFERENCES users(id),
  deleted_at      timestamp NULL,
  deleted_by_id   bigint NULL REFERENCES users(id),
  lock_version    integer NOT NULL DEFAULT 0
);

CREATE UNIQUE INDEX idx_payment_methods_account_name ON financial_payment_methods(account_id, lower(name)) WHERE deleted_at IS NULL;
```

```sql
-- financial_payment_method_fees (taxas versionadas por parcela)
CREATE TABLE financial_payment_method_fees (
  id                      bigserial PRIMARY KEY,
  account_id              bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  payment_method_id       bigint NOT NULL REFERENCES financial_payment_methods(id) ON DELETE RESTRICT,
  installments_count      integer NOT NULL CHECK (installments_count BETWEEN 1 AND 24),
  -- taxa expressa em basis points para precisão (1% = 100 bps; 3.5% = 350 bps)
  fee_percent_basis_points integer NOT NULL CHECK (fee_percent_basis_points BETWEEN 0 AND 10000),
  fee_fixed_cents         bigint NOT NULL DEFAULT 0 CHECK (fee_fixed_cents >= 0),
  liquidation_days        integer NOT NULL DEFAULT 0 CHECK (liquidation_days >= 0),
  valid_from              date NOT NULL,
  valid_to                date NULL,  -- null = vigente
  status                  varchar(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  -- conventional columns
  created_at              timestamp NOT NULL,
  updated_at              timestamp NOT NULL,
  created_by_id           bigint NULL REFERENCES users(id),
  updated_by_id           bigint NULL REFERENCES users(id),
  deleted_at              timestamp NULL,
  deleted_by_id           bigint NULL REFERENCES users(id),
  lock_version            integer NOT NULL DEFAULT 0,
  CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

-- ÚNICO ativo por (account, method, installments_count, periodo): garantia via exclusion constraint
CREATE INDEX idx_payment_method_fees_lookup ON financial_payment_method_fees(account_id, payment_method_id, installments_count, valid_from, valid_to);
ALTER TABLE financial_payment_method_fees ADD CONSTRAINT no_overlapping_fees
  EXCLUDE USING gist (
    account_id WITH =,
    payment_method_id WITH =,
    installments_count WITH =,
    daterange(valid_from, COALESCE(valid_to, 'infinity'::date), '[]') WITH &&
  ) WHERE (deleted_at IS NULL AND status = 'active');
```

```sql
-- financial_commission_rules (versionadas)
CREATE TABLE financial_commission_rules (
  id                        bigserial PRIMARY KEY,
  account_id                bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  agent_user_id             bigint NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  name                      varchar(120) NOT NULL,
  description               text NULL,
  role                      varchar(16) NOT NULL CHECK (role IN ('DR', 'SDR', 'COMERCIAL')),
  trigger_event             varchar(32) NOT NULL CHECK (trigger_event IN ('paciente_comparece', 'orcamento_aceito', 'profissional_realizou', 'pagamento_confirmado')),
  calc_kind                 varchar(16) NOT NULL CHECK (calc_kind IN ('percent', 'fixed')),
  percent_basis_points      integer NULL CHECK (percent_basis_points IS NULL OR (percent_basis_points BETWEEN 0 AND 10000)),
  fixed_amount_cents        bigint NULL CHECK (fixed_amount_cents IS NULL OR fixed_amount_cents >= 0),
  scope                     varchar(16) NOT NULL CHECK (scope IN ('all_events', 'specific_categories')),
  category_ids              bigint[] NULL,  -- referência fraca: ids de financial_dre_categories quando scope='specific_categories'
  payment_timing            varchar(32) NOT NULL CHECK (payment_timing IN ('end_of_month', 'fortnightly', 'on_demand')),
  valid_from                date NOT NULL,
  valid_to                  date NULL,
  status                    varchar(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  -- conventional columns
  created_at                timestamp NOT NULL,
  updated_at                timestamp NOT NULL,
  created_by_id             bigint NULL REFERENCES users(id),
  updated_by_id             bigint NULL REFERENCES users(id),
  deleted_at                timestamp NULL,
  deleted_by_id             bigint NULL REFERENCES users(id),
  lock_version              integer NOT NULL DEFAULT 0,
  CHECK ((calc_kind = 'percent' AND percent_basis_points IS NOT NULL)
       OR (calc_kind = 'fixed' AND fixed_amount_cents IS NOT NULL))
);

CREATE INDEX idx_commission_rules_lookup ON financial_commission_rules(account_id, agent_user_id, role, valid_from, valid_to) WHERE deleted_at IS NULL;
CREATE INDEX idx_commission_rules_active ON financial_commission_rules(account_id, agent_user_id) WHERE status = 'active' AND deleted_at IS NULL;
```

```sql
-- financial_recurring_expenses
CREATE TABLE financial_recurring_expenses (
  id                        bigserial PRIMARY KEY,
  account_id                bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  dre_category_id           bigint NOT NULL REFERENCES financial_dre_categories(id) ON DELETE RESTRICT,
  bank_account_id           bigint NOT NULL REFERENCES financial_bank_accounts(id) ON DELETE RESTRICT,
  name                      varchar(120) NOT NULL,
  amount_kind               varchar(16) NOT NULL CHECK (amount_kind IN ('fixed', 'estimated')),
  default_amount_cents      bigint NOT NULL CHECK (default_amount_cents >= 0),
  frequency                 varchar(16) NOT NULL CHECK (frequency IN ('monthly', 'bimonthly', 'quarterly', 'semiannual', 'annual')),
  due_day                   integer NOT NULL CHECK (due_day BETWEEN 1 AND 31),
  valid_from                date NOT NULL,
  valid_to                  date NULL,
  status                    varchar(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended')),
  -- conventional columns
  created_at                timestamp NOT NULL,
  updated_at                timestamp NOT NULL,
  created_by_id             bigint NULL REFERENCES users(id),
  updated_by_id             bigint NULL REFERENCES users(id),
  deleted_at                timestamp NULL,
  deleted_by_id             bigint NULL REFERENCES users(id),
  lock_version              integer NOT NULL DEFAULT 0
);

CREATE INDEX idx_recurring_expenses_account_status ON financial_recurring_expenses(account_id, status) WHERE deleted_at IS NULL;
```

```sql
-- financial_revenue_goals
CREATE TABLE financial_revenue_goals (
  id                        bigserial PRIMARY KEY,
  account_id                bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  name                      varchar(120) NOT NULL,
  goal_kind                 varchar(16) NOT NULL CHECK (goal_kind IN ('total', 'by_category', 'by_agent')),
  dre_category_id           bigint NULL REFERENCES financial_dre_categories(id) ON DELETE RESTRICT,
  agent_user_id             bigint NULL REFERENCES users(id) ON DELETE RESTRICT,
  measure                   varchar(16) NOT NULL CHECK (measure IN ('amount_cents', 'count')),
  min_value                 bigint NULL CHECK (min_value IS NULL OR min_value >= 0),
  target_value              bigint NOT NULL CHECK (target_value > 0),
  stretch_value             bigint NULL CHECK (stretch_value IS NULL OR stretch_value > 0),
  period_start              date NOT NULL,
  period_end                date NOT NULL,
  status                    varchar(16) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'closed')),
  -- conventional columns
  created_at                timestamp NOT NULL,
  updated_at                timestamp NOT NULL,
  created_by_id             bigint NULL REFERENCES users(id),
  updated_by_id             bigint NULL REFERENCES users(id),
  deleted_at                timestamp NULL,
  deleted_by_id             bigint NULL REFERENCES users(id),
  lock_version              integer NOT NULL DEFAULT 0,
  CHECK (period_end >= period_start),
  CHECK ((goal_kind = 'by_category' AND dre_category_id IS NOT NULL) OR goal_kind != 'by_category'),
  CHECK ((goal_kind = 'by_agent' AND agent_user_id IS NOT NULL) OR goal_kind != 'by_agent')
);

CREATE INDEX idx_revenue_goals_account_period ON financial_revenue_goals(account_id, period_start, period_end) WHERE deleted_at IS NULL;
```

#### 2.2.1.1 Extensão de domínios externos (agenda + users)

```sql
-- Remove price column do agenda_services. Preço vive em financial agora.
-- Migration: 2026MMDD_remove_price_from_agenda_services
ALTER TABLE agenda_services DROP COLUMN price;
```

```sql
-- financial_service_pricings (1-to-1 com agenda_services)
-- Cada AgendaService cadastrado em /agenda/settings > Serviços tem 0 ou 1
-- ServicePricing aqui. UI em /financial/v2/settings > tab Serviços lista
-- todos os AgendaServices da conta e permite preencher/editar o pricing.
-- Service sem pricing = não pode ser lançado financeiramente (warning na UI).
CREATE TABLE financial_service_pricings (
  id                        bigserial PRIMARY KEY,
  account_id                bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  agenda_service_id         bigint NOT NULL REFERENCES agenda_services(id) ON DELETE RESTRICT,
  dre_category_id           bigint NOT NULL REFERENCES financial_dre_categories(id) ON DELETE RESTRICT,
  particular_price_cents    bigint NOT NULL DEFAULT 0 CHECK (particular_price_cents >= 0),
  convenio_price_cents      bigint NULL CHECK (convenio_price_cents IS NULL OR convenio_price_cents >= 0),
  default_commission_rule_id bigint NULL REFERENCES financial_commission_rules(id) ON DELETE RESTRICT,
  -- código contábil opcional (TUSS para convênios — canon §6)
  tuss_code                 varchar(32) NULL,
  internal_code             varchar(32) NULL,
  notes                     text NULL,
  status                    varchar(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  -- conventional columns
  created_at                timestamp NOT NULL,
  updated_at                timestamp NOT NULL,
  created_by_id             bigint NULL REFERENCES users(id),
  updated_by_id             bigint NULL REFERENCES users(id),
  deleted_at                timestamp NULL,
  deleted_by_id             bigint NULL REFERENCES users(id),
  lock_version              integer NOT NULL DEFAULT 0
);

-- 1-to-1: cada agenda_service tem no máximo 1 pricing ativo por conta
CREATE UNIQUE INDEX idx_service_pricings_uniq ON financial_service_pricings(account_id, agenda_service_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_service_pricings_dre_category ON financial_service_pricings(account_id, dre_category_id) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_service_pricings_tuss ON financial_service_pricings(account_id, tuss_code) WHERE tuss_code IS NOT NULL AND deleted_at IS NULL;
CREATE UNIQUE INDEX idx_service_pricings_internal ON financial_service_pricings(account_id, internal_code) WHERE internal_code IS NOT NULL AND deleted_at IS NULL;
```

```sql
-- financial_agent_profiles (extensão financeira de User existente)
-- Estende User do Klivy core com campos específicos do financeiro:
-- vínculo trabalhista, dados bancários para pagamento de comissão, categoria
-- canon (Profissional / Operacional / Comercial / Administrador).
-- 1-to-1 com User; criado on-demand quando o user vira agente financeiro.
CREATE TABLE financial_agent_profiles (
  id                        bigserial PRIMARY KEY,
  account_id                bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  user_id                   bigint NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  -- canon §1
  cpf                       varchar(20) NULL,
  agent_category            varchar(20) NOT NULL CHECK (agent_category IN ('profissional', 'operacional', 'comercial', 'administrador')),
  bond_type                 varchar(10) NOT NULL CHECK (bond_type IN ('PJ', 'CLT', 'Socio')),
  entry_date                date NOT NULL,
  commissionable            boolean NOT NULL DEFAULT false,
  -- apenas para agent_category='profissional'
  cro                       varchar(40) NULL,
  specialties               varchar[] NULL,
  -- dados bancários para pagamento de comissão
  bank_name                 varchar(120) NULL,
  bank_agency               varchar(20) NULL,
  bank_account_number       varchar(40) NULL,
  pix_key                   varchar(120) NULL,
  -- status
  status                    varchar(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  notes                     text NULL,
  -- conventional columns
  created_at                timestamp NOT NULL,
  updated_at                timestamp NOT NULL,
  created_by_id             bigint NULL REFERENCES users(id),
  updated_by_id             bigint NULL REFERENCES users(id),
  deleted_at                timestamp NULL,
  deleted_by_id             bigint NULL REFERENCES users(id),
  lock_version              integer NOT NULL DEFAULT 0,
  CHECK (agent_category != 'profissional' OR cro IS NOT NULL),
  CHECK (agent_category != 'administrador' OR commissionable = false)
);

CREATE UNIQUE INDEX idx_agent_profiles_uniq ON financial_agent_profiles(account_id, user_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_agent_profiles_category ON financial_agent_profiles(account_id, agent_category) WHERE deleted_at IS NULL;
CREATE INDEX idx_agent_profiles_commissionable ON financial_agent_profiles(account_id, commissionable) WHERE deleted_at IS NULL AND commissionable = true;
```

#### 2.2.2 Operacional

```sql
-- financial_budgets (orçamento ou plano de tratamento)
CREATE TABLE financial_budgets (
  id                        bigserial PRIMARY KEY,
  account_id                bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  patient_id                bigint NULL REFERENCES patients(id) ON DELETE RESTRICT,
  origin                    varchar(32) NOT NULL CHECK (origin IN ('treatment_plan', 'budget', 'monthly_installments', 'direct_entry')),
  professional_dr_user_id   bigint NULL REFERENCES users(id) ON DELETE RESTRICT,
  professional_sdr_user_id  bigint NULL REFERENCES users(id) ON DELETE RESTRICT,
  professional_comm_user_id bigint NULL REFERENCES users(id) ON DELETE RESTRICT,
  status                    varchar(16) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'approved', 'canceled', 'completed')),
  subtotal_cents            bigint NOT NULL CHECK (subtotal_cents >= 0),
  discount_cents            bigint NOT NULL DEFAULT 0 CHECK (discount_cents >= 0),
  total_cents               bigint NOT NULL CHECK (total_cents >= 0),
  approved_at               timestamp NULL,
  approved_by_id            bigint NULL REFERENCES users(id),
  canceled_at               timestamp NULL,
  canceled_by_id            bigint NULL REFERENCES users(id),
  cancel_reason             text NULL,
  notes                     text NULL,
  -- conventional columns
  created_at                timestamp NOT NULL,
  updated_at                timestamp NOT NULL,
  created_by_id             bigint NULL REFERENCES users(id),
  updated_by_id             bigint NULL REFERENCES users(id),
  deleted_at                timestamp NULL,
  deleted_by_id             bigint NULL REFERENCES users(id),
  lock_version              integer NOT NULL DEFAULT 0
);

CREATE INDEX idx_budgets_account_patient ON financial_budgets(account_id, patient_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_budgets_account_status ON financial_budgets(account_id, status) WHERE deleted_at IS NULL;
```

```sql
-- financial_budget_items
-- Snapshot do preço no momento da criação do orçamento — mudanças posteriores
-- em financial_service_pricings.particular_price_cents NÃO alteram orçamentos
-- existentes (imutabilidade histórica do canon).
CREATE TABLE financial_budget_items (
  id                        bigserial PRIMARY KEY,
  account_id                bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  budget_id                 bigint NOT NULL REFERENCES financial_budgets(id) ON DELETE RESTRICT,
  -- vínculo com AgendaService (do plugin agenda) — opcional, lançamento avulso pode não ter
  agenda_service_id         bigint NULL REFERENCES agenda_services(id) ON DELETE RESTRICT,
  service_pricing_id        bigint NULL REFERENCES financial_service_pricings(id) ON DELETE RESTRICT,
  dre_category_id           bigint NOT NULL REFERENCES financial_dre_categories(id) ON DELETE RESTRICT,
  description               varchar(255) NOT NULL,  -- snapshot do nome do serviço
  unit_amount_cents         bigint NOT NULL CHECK (unit_amount_cents >= 0),  -- snapshot do preço
  quantity                  integer NOT NULL DEFAULT 1 CHECK (quantity >= 1),
  total_amount_cents        bigint NOT NULL CHECK (total_amount_cents >= 0),
  position                  integer NOT NULL DEFAULT 0,
  -- conventional columns
  created_at                timestamp NOT NULL,
  updated_at                timestamp NOT NULL,
  created_by_id             bigint NULL REFERENCES users(id),
  updated_by_id             bigint NULL REFERENCES users(id),
  deleted_at                timestamp NULL,
  deleted_by_id             bigint NULL REFERENCES users(id),
  lock_version              integer NOT NULL DEFAULT 0
);

CREATE INDEX idx_budget_items_budget ON financial_budget_items(budget_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_budget_items_agenda_service ON financial_budget_items(agenda_service_id) WHERE agenda_service_id IS NOT NULL AND deleted_at IS NULL;
```

```sql
-- financial_installments (parcelas com snapshot de taxa)
CREATE TABLE financial_installments (
  id                            bigserial PRIMARY KEY,
  account_id                    bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  budget_id                     bigint NULL REFERENCES financial_budgets(id) ON DELETE RESTRICT,
  patient_id                    bigint NULL REFERENCES patients(id) ON DELETE RESTRICT,
  sequence                      integer NOT NULL CHECK (sequence >= 1),
  total_count                   integer NOT NULL CHECK (total_count >= 1),
  due_date                      date NOT NULL,
  amount_cents                  bigint NOT NULL CHECK (amount_cents >= 0),
  payment_method_id             bigint NULL REFERENCES financial_payment_methods(id) ON DELETE RESTRICT,
  -- SNAPSHOT (imutável após criação)
  payment_method_fee_id         bigint NULL REFERENCES financial_payment_method_fees(id) ON DELETE RESTRICT,
  fee_percent_basis_points      integer NULL CHECK (fee_percent_basis_points IS NULL OR fee_percent_basis_points BETWEEN 0 AND 10000),
  fee_fixed_cents               bigint NULL DEFAULT 0 CHECK (fee_fixed_cents IS NULL OR fee_fixed_cents >= 0),
  fee_amount_cents              bigint NOT NULL DEFAULT 0,  -- valor calculado da taxa
  net_amount_cents              bigint NOT NULL DEFAULT 0,  -- bruto - taxa
  expected_liquidation_date     date NULL,  -- amount + liquidation_days da taxa
  -- estado
  received_amount_cents         bigint NOT NULL DEFAULT 0 CHECK (received_amount_cents >= 0),
  status                        varchar(16) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'received', 'overdue', 'renegotiated', 'canceled')),
  -- vínculos
  replaces_installment_id       bigint NULL REFERENCES financial_installments(id) ON DELETE RESTRICT,
  renegotiated_to_id            bigint NULL REFERENCES financial_installments(id) ON DELETE RESTRICT,
  -- external integration
  external_id                   varchar(120) NULL,  -- ID Asaas, Pagar.me, etc
  external_provider             varchar(40) NULL,
  metadata                      jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- conventional columns
  created_at                    timestamp NOT NULL,
  updated_at                    timestamp NOT NULL,
  created_by_id                 bigint NULL REFERENCES users(id),
  updated_by_id                 bigint NULL REFERENCES users(id),
  deleted_at                    timestamp NULL,
  deleted_by_id                 bigint NULL REFERENCES users(id),
  lock_version                  integer NOT NULL DEFAULT 0,
  CHECK (received_amount_cents <= amount_cents)
);

CREATE INDEX idx_installments_account_status ON financial_installments(account_id, status) WHERE deleted_at IS NULL;
CREATE INDEX idx_installments_account_due ON financial_installments(account_id, due_date) WHERE deleted_at IS NULL AND status = 'pending';
CREATE INDEX idx_installments_budget ON financial_installments(budget_id) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_installments_external ON financial_installments(account_id, external_provider, external_id) WHERE external_id IS NOT NULL AND deleted_at IS NULL;
CREATE UNIQUE INDEX idx_installments_renegotiated ON financial_installments(renegotiated_to_id) WHERE renegotiated_to_id IS NOT NULL;
```

```sql
-- financial_payment_receipts (recibos — agrupa N installments num evento de pagamento)
CREATE TABLE financial_payment_receipts (
  id                        bigserial PRIMARY KEY,
  account_id                bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  patient_id                bigint NULL REFERENCES patients(id) ON DELETE RESTRICT,
  bank_account_id           bigint NOT NULL REFERENCES financial_bank_accounts(id) ON DELETE RESTRICT,
  receipt_number            varchar(40) NOT NULL,  -- "REC-2026-000001"
  received_at               date NOT NULL,
  total_amount_cents        bigint NOT NULL CHECK (total_amount_cents > 0),
  notes                     text NULL,
  external_id               varchar(120) NULL,
  external_provider         varchar(40) NULL,
  -- conventional columns
  created_at                timestamp NOT NULL,
  updated_at                timestamp NOT NULL,
  created_by_id             bigint NULL REFERENCES users(id),
  updated_by_id             bigint NULL REFERENCES users(id),
  deleted_at                timestamp NULL,
  deleted_by_id             bigint NULL REFERENCES users(id),
  lock_version              integer NOT NULL DEFAULT 0
);

CREATE UNIQUE INDEX idx_payment_receipts_number ON financial_payment_receipts(account_id, receipt_number) WHERE deleted_at IS NULL;
CREATE INDEX idx_payment_receipts_patient ON financial_payment_receipts(account_id, patient_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_payment_receipts_received ON financial_payment_receipts(account_id, received_at);
```

```sql
-- financial_payment_receipt_items
CREATE TABLE financial_payment_receipt_items (
  id                        bigserial PRIMARY KEY,
  account_id                bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  payment_receipt_id        bigint NOT NULL REFERENCES financial_payment_receipts(id) ON DELETE RESTRICT,
  installment_id            bigint NOT NULL REFERENCES financial_installments(id) ON DELETE RESTRICT,
  amount_cents              bigint NOT NULL CHECK (amount_cents > 0),
  -- conventional columns
  created_at                timestamp NOT NULL,
  updated_at                timestamp NOT NULL,
  deleted_at                timestamp NULL,
  lock_version              integer NOT NULL DEFAULT 0
);

CREATE INDEX idx_payment_receipt_items_receipt ON financial_payment_receipt_items(payment_receipt_id);
CREATE INDEX idx_payment_receipt_items_installment ON financial_payment_receipt_items(installment_id);
```

```sql
-- financial_expenses
CREATE TABLE financial_expenses (
  id                            bigserial PRIMARY KEY,
  account_id                    bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  dre_category_id               bigint NOT NULL REFERENCES financial_dre_categories(id) ON DELETE RESTRICT,
  bank_account_id               bigint NOT NULL REFERENCES financial_bank_accounts(id) ON DELETE RESTRICT,
  recurring_expense_id          bigint NULL REFERENCES financial_recurring_expenses(id) ON DELETE RESTRICT,
  description                   varchar(255) NOT NULL,
  supplier                      varchar(255) NULL,
  amount_cents                  bigint NOT NULL CHECK (amount_cents >= 0),
  paid_amount_cents             bigint NOT NULL DEFAULT 0 CHECK (paid_amount_cents >= 0),
  competence_date               date NOT NULL,  -- vencimento ou data de geração
  due_date                      date NOT NULL,
  paid_at                       date NULL,
  status                        varchar(16) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'partially_paid', 'overdue', 'reversed', 'canceled')),
  payment_method_id             bigint NULL REFERENCES financial_payment_methods(id) ON DELETE RESTRICT,
  -- vínculo com source quando gerada automaticamente
  source_type                   varchar(64) NULL CHECK (source_type IS NULL OR source_type IN ('Financial::CommissionEntry', 'Financial::Refund', 'Financial::CashBreakage', 'Financial::MdrFee', 'Financial::RecurringExpense')),
  source_id                     bigint NULL,
  notes                         text NULL,
  -- conventional columns
  created_at                    timestamp NOT NULL,
  updated_at                    timestamp NOT NULL,
  created_by_id                 bigint NULL REFERENCES users(id),
  updated_by_id                 bigint NULL REFERENCES users(id),
  deleted_at                    timestamp NULL,
  deleted_by_id                 bigint NULL REFERENCES users(id),
  lock_version                  integer NOT NULL DEFAULT 0,
  CHECK (paid_amount_cents <= amount_cents),
  CHECK ((source_type IS NULL AND source_id IS NULL) OR (source_type IS NOT NULL AND source_id IS NOT NULL))
);

CREATE INDEX idx_expenses_account_status ON financial_expenses(account_id, status) WHERE deleted_at IS NULL;
CREATE INDEX idx_expenses_account_due ON financial_expenses(account_id, due_date) WHERE deleted_at IS NULL AND status IN ('pending', 'partially_paid');
CREATE INDEX idx_expenses_account_competence ON financial_expenses(account_id, competence_date) WHERE deleted_at IS NULL;
CREATE INDEX idx_expenses_recurring ON financial_expenses(recurring_expense_id, competence_date) WHERE deleted_at IS NULL;
CREATE INDEX idx_expenses_source ON financial_expenses(source_type, source_id);
-- idempotência de geração de despesa recorrente:
CREATE UNIQUE INDEX idx_expenses_recurring_competence ON financial_expenses(recurring_expense_id, date_trunc('month', competence_date))
  WHERE recurring_expense_id IS NOT NULL AND deleted_at IS NULL;
```

```sql
-- financial_commission_entries (com snapshot da regra)
CREATE TABLE financial_commission_entries (
  id                            bigserial PRIMARY KEY,
  account_id                    bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  installment_id                bigint NULL REFERENCES financial_installments(id) ON DELETE RESTRICT,
  budget_id                     bigint NULL REFERENCES financial_budgets(id) ON DELETE RESTRICT,
  agent_user_id                 bigint NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  -- SNAPSHOT da regra (imutável)
  commission_rule_id            bigint NOT NULL REFERENCES financial_commission_rules(id) ON DELETE RESTRICT,
  rule_snapshot                 jsonb NOT NULL,  -- {role, trigger_event, calc_kind, percent_basis_points, fixed_amount_cents, scope}
  -- valores (imutáveis após criação; estorno cria registro NOVO)
  base_amount_cents             bigint NOT NULL CHECK (base_amount_cents >= 0),
  mdr_deduction_cents           bigint NOT NULL DEFAULT 0 CHECK (mdr_deduction_cents >= 0),
  net_base_cents                bigint NOT NULL CHECK (net_base_cents >= 0),
  commission_amount_cents       bigint NOT NULL,  -- pode ser negativo em estorno
  -- ciclo de vida
  status                        varchar(16) NOT NULL DEFAULT 'provisioned' CHECK (status IN ('provisioned', 'due', 'approved', 'to_pay', 'paid', 'reversed')),
  triggered_at                  timestamp NOT NULL,
  approved_at                   timestamp NULL,
  approved_by_id                bigint NULL REFERENCES users(id),
  paid_via_expense_id           bigint NULL REFERENCES financial_expenses(id) ON DELETE RESTRICT,
  reverses_commission_entry_id  bigint NULL REFERENCES financial_commission_entries(id) ON DELETE RESTRICT,
  -- conventional columns
  created_at                    timestamp NOT NULL,
  updated_at                    timestamp NOT NULL,
  created_by_id                 bigint NULL REFERENCES users(id),
  updated_by_id                 bigint NULL REFERENCES users(id),
  deleted_at                    timestamp NULL,
  deleted_by_id                 bigint NULL REFERENCES users(id),
  lock_version                  integer NOT NULL DEFAULT 0
);

CREATE INDEX idx_commission_entries_account_agent ON financial_commission_entries(account_id, agent_user_id, status) WHERE deleted_at IS NULL;
CREATE INDEX idx_commission_entries_installment ON financial_commission_entries(installment_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_commission_entries_budget ON financial_commission_entries(budget_id) WHERE deleted_at IS NULL;
-- evita duplicar comissão da mesma regra+installment+role
CREATE UNIQUE INDEX idx_commission_entries_uniq ON financial_commission_entries(account_id, installment_id, commission_rule_id, agent_user_id)
  WHERE installment_id IS NOT NULL AND deleted_at IS NULL AND status != 'reversed';
```

```sql
-- financial_refunds (estorno é entidade própria, não update)
CREATE TABLE financial_refunds (
  id                            bigserial PRIMARY KEY,
  account_id                    bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  installment_id                bigint NOT NULL REFERENCES financial_installments(id) ON DELETE RESTRICT,
  refund_amount_cents           bigint NOT NULL CHECK (refund_amount_cents > 0),
  refund_proportion_bps         integer NOT NULL CHECK (refund_proportion_bps BETWEEN 1 AND 10000),  -- proporção em bps (100% = 10000)
  reason                        text NOT NULL,
  refund_method                 varchar(16) NOT NULL CHECK (refund_method IN ('cash', 'pix', 'bank_transfer', 'patient_credit')),
  bank_account_id               bigint NULL REFERENCES financial_bank_accounts(id) ON DELETE RESTRICT,
  refunded_at                   date NOT NULL,
  reverses_payment_receipt_id   bigint NULL REFERENCES financial_payment_receipts(id) ON DELETE RESTRICT,
  -- conventional columns
  created_at                    timestamp NOT NULL,
  updated_at                    timestamp NOT NULL,
  created_by_id                 bigint NULL REFERENCES users(id),
  updated_by_id                 bigint NULL REFERENCES users(id),
  deleted_at                    timestamp NULL,
  deleted_by_id                 bigint NULL REFERENCES users(id),
  lock_version                  integer NOT NULL DEFAULT 0
);

CREATE INDEX idx_refunds_installment ON financial_refunds(installment_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_refunds_account_date ON financial_refunds(account_id, refunded_at);
```

```sql
-- financial_patient_credits (saldo a favor)
CREATE TABLE financial_patient_credits (
  id                        bigserial PRIMARY KEY,
  account_id                bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  patient_id                bigint NOT NULL REFERENCES patients(id) ON DELETE RESTRICT,
  amount_cents              bigint NOT NULL,  -- positivo = crédito, negativo = uso
  source_type               varchar(64) NULL,
  source_id                 bigint NULL,
  notes                     text NULL,
  -- conventional columns
  created_at                timestamp NOT NULL,
  updated_at                timestamp NOT NULL,
  created_by_id             bigint NULL REFERENCES users(id),
  updated_by_id             bigint NULL REFERENCES users(id),
  deleted_at                timestamp NULL,
  deleted_by_id             bigint NULL REFERENCES users(id),
  lock_version              integer NOT NULL DEFAULT 0
);

CREATE INDEX idx_patient_credits_account_patient ON financial_patient_credits(account_id, patient_id) WHERE deleted_at IS NULL;
```

```sql
-- financial_cash_registers (sessões de caixa)
CREATE TABLE financial_cash_registers (
  id                        bigserial PRIMARY KEY,
  account_id                bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  bank_account_id           bigint NOT NULL REFERENCES financial_bank_accounts(id) ON DELETE RESTRICT,  -- conta CASH
  session_date              date NOT NULL,
  opened_at                 timestamp NOT NULL,
  opened_by_id              bigint NOT NULL REFERENCES users(id),
  opening_balance_cents     bigint NOT NULL DEFAULT 0 CHECK (opening_balance_cents >= 0),
  closed_at                 timestamp NULL,
  closed_by_id              bigint NULL REFERENCES users(id),
  expected_balance_cents    bigint NULL,
  counted_balance_cents     bigint NULL CHECK (counted_balance_cents IS NULL OR counted_balance_cents >= 0),
  difference_cents          bigint NULL,  -- counted - expected
  reopen_count              integer NOT NULL DEFAULT 0,
  status                    varchar(16) NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed', 'reopened')),
  -- conventional columns
  created_at                timestamp NOT NULL,
  updated_at                timestamp NOT NULL,
  created_by_id             bigint NULL REFERENCES users(id),
  updated_by_id             bigint NULL REFERENCES users(id),
  deleted_at                timestamp NULL,
  deleted_by_id             bigint NULL REFERENCES users(id),
  lock_version              integer NOT NULL DEFAULT 0
);

-- Apenas 1 caixa aberto por dia + conta:
CREATE UNIQUE INDEX idx_cash_registers_open ON financial_cash_registers(account_id, bank_account_id, session_date)
  WHERE status = 'open' AND deleted_at IS NULL;
CREATE INDEX idx_cash_registers_account_date ON financial_cash_registers(account_id, session_date);
```

```sql
-- financial_cash_movements (sangria, suprimento, quebra)
CREATE TABLE financial_cash_movements (
  id                        bigserial PRIMARY KEY,
  account_id                bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  cash_register_id          bigint NOT NULL REFERENCES financial_cash_registers(id) ON DELETE RESTRICT,
  kind                      varchar(16) NOT NULL CHECK (kind IN ('sangria', 'suprimento', 'breakage_in', 'breakage_out')),
  amount_cents              bigint NOT NULL CHECK (amount_cents > 0),
  counterpart_bank_id       bigint NULL REFERENCES financial_bank_accounts(id) ON DELETE RESTRICT,  -- destino sangria / origem suprimento
  notes                     text NULL,
  -- conventional columns
  created_at                timestamp NOT NULL,
  updated_at                timestamp NOT NULL,
  created_by_id             bigint NULL REFERENCES users(id),
  updated_by_id             bigint NULL REFERENCES users(id),
  deleted_at                timestamp NULL,
  deleted_by_id             bigint NULL REFERENCES users(id),
  lock_version              integer NOT NULL DEFAULT 0
);

CREATE INDEX idx_cash_movements_register ON financial_cash_movements(cash_register_id);
```

#### 2.2.3 Ledger (canonical)

```sql
-- financial_entries — registro contábil canônico (DRE + Fluxo derivam daqui)
CREATE TABLE financial_entries (
  id                        bigserial PRIMARY KEY,
  account_id                bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  bank_account_id           bigint NOT NULL REFERENCES financial_bank_accounts(id) ON DELETE RESTRICT,
  dre_category_id           bigint NULL REFERENCES financial_dre_categories(id) ON DELETE RESTRICT,
  direction                 varchar(8) NOT NULL CHECK (direction IN ('inflow', 'outflow')),
  kind                      varchar(32) NOT NULL CHECK (kind IN ('revenue', 'expense', 'transfer_internal', 'mdr_fee', 'commission', 'refund', 'cash_breakage')),
  amount_cents              bigint NOT NULL CHECK (amount_cents > 0),
  competence_date           date NOT NULL,  -- DRE
  cash_date                 date NOT NULL,  -- Fluxo de Caixa
  affects_dre               boolean NOT NULL DEFAULT true,
  description               varchar(255) NOT NULL,
  patient_id                bigint NULL REFERENCES patients(id) ON DELETE RESTRICT,
  -- source polymorphic (rastreabilidade)
  source_type               varchar(64) NULL CHECK (source_type IS NULL OR source_type IN ('Financial::PaymentReceiptItem', 'Financial::Expense', 'Financial::CashMovement', 'Financial::CommissionEntry', 'Financial::Refund')),
  source_id                 bigint NULL,
  -- transfer linking
  transfer_pair_id          bigint NULL REFERENCES financial_entries(id) ON DELETE RESTRICT,
  -- conventional columns
  created_at                timestamp NOT NULL,
  updated_at                timestamp NOT NULL,
  created_by_id             bigint NULL REFERENCES users(id),
  updated_by_id             bigint NULL REFERENCES users(id),
  deleted_at                timestamp NULL,
  deleted_by_id             bigint NULL REFERENCES users(id),
  lock_version              integer NOT NULL DEFAULT 0,
  CHECK (kind != 'transfer_internal' OR affects_dre = false),
  CHECK ((source_type IS NULL AND source_id IS NULL) OR (source_type IS NOT NULL AND source_id IS NOT NULL))
);

CREATE INDEX idx_entries_account_competence ON financial_entries(account_id, competence_date) WHERE deleted_at IS NULL AND affects_dre = true;
CREATE INDEX idx_entries_account_cash ON financial_entries(account_id, cash_date) WHERE deleted_at IS NULL;
CREATE INDEX idx_entries_bank ON financial_entries(bank_account_id, cash_date) WHERE deleted_at IS NULL;
CREATE INDEX idx_entries_source ON financial_entries(source_type, source_id);
CREATE INDEX idx_entries_dre_category ON financial_entries(dre_category_id, competence_date) WHERE deleted_at IS NULL AND affects_dre = true;
CREATE INDEX idx_entries_patient ON financial_entries(account_id, patient_id, competence_date) WHERE patient_id IS NOT NULL AND deleted_at IS NULL;
```

#### 2.2.4 Governança

```sql
-- financial_period_closures (fechamento de período contábil)
CREATE TABLE financial_period_closures (
  id                        bigserial PRIMARY KEY,
  account_id                bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  period_year               integer NOT NULL CHECK (period_year BETWEEN 2020 AND 2100),
  period_month              integer NOT NULL CHECK (period_month BETWEEN 1 AND 12),
  closed_at                 timestamp NOT NULL,
  closed_by_id              bigint NOT NULL REFERENCES users(id),
  notes                     text NULL,
  reopened_at               timestamp NULL,
  reopened_by_id            bigint NULL REFERENCES users(id),
  reopen_reason             text NULL,
  status                    varchar(16) NOT NULL DEFAULT 'closed' CHECK (status IN ('closed', 'reopened')),
  -- conventional columns
  created_at                timestamp NOT NULL,
  updated_at                timestamp NOT NULL,
  lock_version              integer NOT NULL DEFAULT 0
);

CREATE UNIQUE INDEX idx_period_closures_uniq ON financial_period_closures(account_id, period_year, period_month) WHERE status = 'closed';
CREATE INDEX idx_period_closures_account ON financial_period_closures(account_id, period_year, period_month);
```

```sql
-- financial_audit_logs (toda mudança de estado)
CREATE TABLE financial_audit_logs (
  id                        bigserial PRIMARY KEY,
  account_id                bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  user_id                   bigint NULL REFERENCES users(id),
  action                    varchar(32) NOT NULL CHECK (action IN ('create', 'update', 'destroy', 'restore', 'soft_delete', 'state_transition')),
  entity_type               varchar(64) NOT NULL,
  entity_id                 bigint NOT NULL,
  changes_diff              jsonb NULL,  -- {field: [before, after]}
  metadata                  jsonb NOT NULL DEFAULT '{}'::jsonb,
  ip_address                inet NULL,
  user_agent                varchar(512) NULL,
  request_id                varchar(64) NULL,
  created_at                timestamp NOT NULL
);

CREATE INDEX idx_audit_logs_entity ON financial_audit_logs(account_id, entity_type, entity_id);
CREATE INDEX idx_audit_logs_user ON financial_audit_logs(account_id, user_id, created_at);
CREATE INDEX idx_audit_logs_created ON financial_audit_logs(account_id, created_at);
```

```sql
-- financial_idempotency_keys
CREATE TABLE financial_idempotency_keys (
  id                        bigserial PRIMARY KEY,
  account_id                bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  key                       varchar(128) NOT NULL,
  fingerprint               varchar(64) NOT NULL,  -- hash de (path, body) — detecta reuso de key com payload diferente
  response_status           integer NOT NULL,
  response_body             jsonb NOT NULL,
  response_headers          jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at                timestamp NOT NULL
);

CREATE UNIQUE INDEX idx_idempotency_keys_uniq ON financial_idempotency_keys(account_id, key);
CREATE INDEX idx_idempotency_keys_created ON financial_idempotency_keys(created_at);  -- para cleanup job
```

```sql
-- financial_setup_states (wizard)
CREATE TABLE financial_setup_states (
  id                          bigserial PRIMARY KEY,
  account_id                  bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  step_professionals          boolean NOT NULL DEFAULT false,
  step_categories             boolean NOT NULL DEFAULT false,
  step_payment_methods        boolean NOT NULL DEFAULT false,
  step_bank_accounts          boolean NOT NULL DEFAULT false,
  step_commission_rules       boolean NOT NULL DEFAULT false,
  step_procedures             boolean NOT NULL DEFAULT false,  -- futuro
  step_recurring_expenses     boolean NOT NULL DEFAULT false,
  step_goals                  boolean NOT NULL DEFAULT false,
  completed_at                timestamp NULL,
  completed_by_id             bigint NULL REFERENCES users(id),
  -- conventional columns
  created_at                  timestamp NOT NULL,
  updated_at                  timestamp NOT NULL,
  lock_version                integer NOT NULL DEFAULT 0
);

CREATE UNIQUE INDEX idx_setup_states_account ON financial_setup_states(account_id);
```

```sql
-- financial_gateway_settings (config Asaas, Pagar.me, etc — com criptografia REAL)
CREATE TABLE financial_gateway_settings (
  id                        bigserial PRIMARY KEY,
  account_id                bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  gateway                   varchar(32) NOT NULL CHECK (gateway IN ('manual', 'asaas', 'pagarme', 'mercadopago')),
  -- valores criptografados via Rails ActiveRecord Encryption (não Base64!)
  encrypted_api_key         text NULL,
  encrypted_webhook_secret  text NULL,
  webhook_url               varchar(255) NULL,  -- URL pública pra config no provider
  metadata                  jsonb NOT NULL DEFAULT '{}'::jsonb,
  status                    varchar(16) NOT NULL DEFAULT 'inactive' CHECK (status IN ('active', 'inactive', 'error')),
  last_verified_at          timestamp NULL,
  -- conventional columns
  created_at                timestamp NOT NULL,
  updated_at                timestamp NOT NULL,
  created_by_id             bigint NULL REFERENCES users(id),
  updated_by_id             bigint NULL REFERENCES users(id),
  deleted_at                timestamp NULL,
  deleted_by_id             bigint NULL REFERENCES users(id),
  lock_version              integer NOT NULL DEFAULT 0
);

CREATE UNIQUE INDEX idx_gateway_settings_uniq ON financial_gateway_settings(account_id, gateway) WHERE deleted_at IS NULL;
```

```sql
-- financial_gateway_webhook_events (idempotência de webhooks)
CREATE TABLE financial_gateway_webhook_events (
  id                        bigserial PRIMARY KEY,
  account_id                bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  gateway                   varchar(32) NOT NULL,
  event_id                  varchar(120) NOT NULL,  -- ID enviado pelo provider
  event_type                varchar(80) NOT NULL,
  payload                   jsonb NOT NULL,
  signature                 varchar(255) NULL,
  status                    varchar(16) NOT NULL DEFAULT 'received' CHECK (status IN ('received', 'processed', 'failed', 'skipped')),
  processed_at              timestamp NULL,
  failed_at                 timestamp NULL,
  failure_reason            text NULL,
  attempt_count             integer NOT NULL DEFAULT 0,
  created_at                timestamp NOT NULL,
  updated_at                timestamp NOT NULL
);

CREATE UNIQUE INDEX idx_gateway_webhook_events_uniq ON financial_gateway_webhook_events(account_id, gateway, event_id);
CREATE INDEX idx_gateway_webhook_events_status ON financial_gateway_webhook_events(status, created_at);
```

```sql
-- financial_lgpd_requests
CREATE TABLE financial_lgpd_requests (
  id                        bigserial PRIMARY KEY,
  account_id                bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  patient_id                bigint NOT NULL REFERENCES patients(id) ON DELETE RESTRICT,
  request_kind              varchar(16) NOT NULL CHECK (request_kind IN ('access', 'anonymize', 'delete', 'export')),
  status                    varchar(16) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'executed', 'canceled')),
  requested_at              timestamp NOT NULL,
  requested_by_id           bigint NULL REFERENCES users(id),
  approved_at               timestamp NULL,
  approved_by_id            bigint NULL REFERENCES users(id),
  rejected_at               timestamp NULL,
  rejected_by_id            bigint NULL REFERENCES users(id),
  rejection_reason          text NULL,
  executed_at               timestamp NULL,
  executed_by_id            bigint NULL REFERENCES users(id),
  notes                     text NULL,
  -- conventional columns
  created_at                timestamp NOT NULL,
  updated_at                timestamp NOT NULL,
  lock_version              integer NOT NULL DEFAULT 0
);

CREATE INDEX idx_lgpd_requests_account_patient ON financial_lgpd_requests(account_id, patient_id);
CREATE INDEX idx_lgpd_requests_status ON financial_lgpd_requests(account_id, status);
```

---

## 3. Concerns Ruby compartilhados

### 3.1 `Financial::ApplicationRecord`

```ruby
module Financial
  class ApplicationRecord < ::ApplicationRecord
    self.abstract_class = true
    self.table_name_prefix = 'financial_'

    # Multi-tenant defense in depth
    validates :account_id,
              presence: true,
              numericality: { only_integer: true },
              if: -> { self.class.column_names.include?('account_id') }

    # Soft delete enforcement: find/find_by aplicam scope `alive` automaticamente.
    # default_scope é evitado intencionalmente — comportamento implícito é traiçoeiro.
    class << self
      def find(*ids)
        return super if ids.flatten.compact.empty?
        scoped_for_alive.find(*ids)
      end

      def find_by(*args)
        scoped_for_alive.find_by(*args)
      end

      def find_by!(*args)
        scoped_for_alive.find_by!(*args)
      end

      def scoped_for_alive
        column_names.include?('deleted_at') ? alive : all
      end

      # Scope explícito que deve ser invocado nos controllers
      def for_account(account_id)
        raise ArgumentError, 'account_id required' if account_id.blank?
        where(account_id: account_id)
      end
    end
  end
end
```

### 3.2 `Financial::Concerns::SoftDeletable`

```ruby
module Financial
  module Concerns
    module SoftDeletable
      extend ActiveSupport::Concern

      included do
        scope :alive,   -> { where(deleted_at: nil) }
        scope :deleted, -> { where.not(deleted_at: nil) }
      end

      def soft_delete!(actor: Financial::CurrentUser.user)
        return if deleted_at.present?
        update_columns(
          deleted_at: Time.current,
          deleted_by_id: actor&.id,
          updated_at: Time.current
        )
        # Audit log
        ::Financial::Concerns::Auditable.audit_event(self, action: 'soft_delete', actor: actor)
      end

      def restore!(actor: Financial::CurrentUser.user)
        return unless deleted_at.present?
        update_columns(deleted_at: nil, deleted_by_id: nil, updated_at: Time.current)
        ::Financial::Concerns::Auditable.audit_event(self, action: 'restore', actor: actor)
      end
    end
  end
end
```

### 3.3 `Financial::Concerns::Auditable`

```ruby
module Financial
  module Concerns
    module Auditable
      extend ActiveSupport::Concern

      included do
        after_create :audit_create
        after_update :audit_update
        after_destroy :audit_destroy

        # Frozen snapshot fields — declarado por modelo via `frozen_attributes :foo, :bar`
        class_attribute :_frozen_attributes, default: []
      end

      class_methods do
        def frozen_attributes(*attrs)
          self._frozen_attributes = (_frozen_attributes + attrs.flatten).uniq
          attr_readonly(*attrs)
          validate :frozen_attributes_not_changed, on: :update
        end
      end

      def frozen_attributes_not_changed
        self.class._frozen_attributes.each do |attr|
          if persisted? && public_send("#{attr}_changed?")
            errors.add(attr, 'is frozen and cannot be changed')
          end
        end
      end

      def audit_create
        self.class.audit_event(self, action: 'create')
      end

      def audit_update
        return if saved_changes.empty?
        changes_diff = saved_changes.except('updated_at', 'lock_version').transform_values { |(b, a)| [b, a] }
        return if changes_diff.empty?
        self.class.audit_event(self, action: 'update', changes_diff: changes_diff)
      end

      def audit_destroy
        self.class.audit_event(self, action: 'destroy')
      end

      def self.audit_event(record, action:, actor: nil, changes_diff: nil)
        actor ||= Financial::CurrentUser.user
        Financial::AuditLogJob.perform_later(
          account_id: record.account_id,
          user_id: actor&.id,
          action: action,
          entity_type: record.class.name,
          entity_id: record.id,
          changes_diff: changes_diff,
          metadata: Financial::CurrentUser.request_metadata,
        )
      end

      def self.included(base)
        base.extend(ClassMethods)
      end
    end
  end
end
```

### 3.4 `Financial::Concerns::Stamped`

```ruby
module Financial
  module Concerns
    module Stamped
      extend ActiveSupport::Concern

      included do
        before_validation :stamp_actor
      end

      def stamp_actor
        actor = Financial::CurrentUser.user
        return unless actor

        self.created_by_id ||= actor.id if new_record? && self.class.column_names.include?('created_by_id')
        self.updated_by_id = actor.id if self.class.column_names.include?('updated_by_id')
      end
    end
  end
end
```

### 3.5 `Financial::Concerns::MoneyAttribute`

```ruby
module Financial
  module Concerns
    module MoneyAttribute
      extend ActiveSupport::Concern

      class_methods do
        # money_attribute :amount_cents, as: :amount
        def money_attribute(cents_column, as:)
          define_method(as) do
            cents = public_send(cents_column)
            return nil if cents.nil?
            cents.to_d / 100
          end

          define_method("#{as}=") do |value|
            if value.nil?
              public_send("#{cents_column}=", nil)
            else
              public_send("#{cents_column}=", (BigDecimal(value.to_s) * 100).round.to_i)
            end
          end
        end

        # Distribui valor inteiro em N partes, resto na última
        def split_cents(total_cents, n)
          raise ArgumentError, 'n must be > 0' if n <= 0
          base = total_cents / n
          remainder = total_cents - (base * n)
          [base] * (n - 1) + [base + remainder]
        end
      end
    end
  end
end
```

### 3.6 `Financial::CurrentUser` (thread-local)

```ruby
module Financial
  class CurrentUser < ActiveSupport::CurrentAttributes
    attribute :user, :account, :request_id, :ip_address, :user_agent

    def request_metadata
      {
        ip_address: ip_address,
        user_agent: user_agent,
        request_id: request_id,
      }
    end
  end
end
```

Configurado via `before_action` no `BaseController`:
```ruby
before_action :populate_financial_current
def populate_financial_current
  Financial::CurrentUser.user = current_user
  Financial::CurrentUser.account = current_account
  Financial::CurrentUser.request_id = request.request_id
  Financial::CurrentUser.ip_address = request.remote_ip
  Financial::CurrentUser.user_agent = request.user_agent
end
```

---

## 4. Padrão de Service

### 4.1 `Financial::ServiceResult`

```ruby
module Financial
  class ServiceResult
    attr_reader :data, :errors

    def self.success(data = {})
      new(success: true, data: data, errors: [])
    end

    def self.failure(errors)
      new(success: false, data: {}, errors: Array(errors))
    end

    def initialize(success:, data:, errors:)
      @success = success
      @data = data.is_a?(Hash) ? data.with_indifferent_access : data
      @errors = errors
    end

    def success?
      @success
    end

    def failure?
      !@success
    end

    def [](key)
      @data[key]
    end
  end
end
```

### 4.2 Template canônico (`Financial::Payments::ReceivePayment`)

```ruby
module Financial
  module Payments
    class ReceivePayment
      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(account:, bank_account:, installment_amounts:, received_at:, actor:, idempotency_key: nil, notes: nil)
        @account = account
        @bank_account = bank_account
        @installment_amounts = installment_amounts  # [{installment_id:, amount_cents:}, ...]
        @received_at = received_at
        @actor = actor
        @idempotency_key = idempotency_key
        @notes = notes
      end

      def call
        # 1. Validações leves (sem DB)
        return failure('account required') if @account.nil?
        return failure('bank_account required') if @bank_account.nil?
        return failure('received_at required') if @received_at.nil?
        return failure('installment_amounts required') if @installment_amounts.blank?

        # 2. Validação de período fechado
        if Financial::PeriodClosure.closed_for?(@account, @received_at)
          return failure("Período #{@received_at.strftime('%m/%Y')} está fechado")
        end

        # 3. Carrega entidades (sem lock ainda)
        ids = @installment_amounts.map { |r| r[:installment_id] }
        installments = Financial::Installment
                          .for_account(@account.id)
                          .alive
                          .where(id: ids)
                          .to_a
        return failure('parcelas não encontradas') if installments.size != ids.size

        # 4. Validação de coerência (mesmo budget, mesmo patient)
        budget_ids = installments.map(&:budget_id).compact.uniq
        return failure('parcelas pertencem a orçamentos diferentes') if budget_ids.size > 1

        patient_ids = installments.map(&:patient_id).compact.uniq
        return failure('parcelas pertencem a pacientes diferentes') if patient_ids.size > 1

        # 5. Transação atômica
        receipt = nil
        ActiveRecord::Base.transaction do
          # Lock pessimista em ordem estável (sempre por ID ASC)
          locked = installments.sort_by(&:id).map do |i|
            i.lock!
            i.reload  # snapshot pós-lock
          end

          # Re-validar pós-lock
          locked.zip(@installment_amounts.sort_by { |r| r[:installment_id] }).each do |inst, row|
            applied = row[:amount_cents].to_i
            raise ActiveRecord::Rollback, "valor inválido na parcela #{inst.id}" if applied <= 0
            raise ActiveRecord::Rollback, "parcela #{inst.id} já paga" if inst.received_amount_cents + applied > inst.amount_cents
          end

          # Cria recibo
          receipt = Financial::PaymentReceipt.create!(
            account_id: @account.id,
            patient_id: patient_ids.first,
            bank_account_id: @bank_account.id,
            receipt_number: next_receipt_number,
            received_at: @received_at,
            total_amount_cents: @installment_amounts.sum { |r| r[:amount_cents].to_i },
            notes: @notes
          )

          # Aplica em cada parcela + cria items + entries
          locked.zip(@installment_amounts.sort_by { |r| r[:installment_id] }).each do |inst, row|
            applied_cents = row[:amount_cents].to_i

            Financial::PaymentReceiptItem.create!(
              account_id: @account.id,
              payment_receipt_id: receipt.id,
              installment_id: inst.id,
              amount_cents: applied_cents
            )

            new_received = inst.received_amount_cents + applied_cents
            new_status = new_received >= inst.amount_cents ? 'received' : 'pending'
            inst.update!(received_amount_cents: new_received, status: new_status)

            # Entry: receita bruta
            Financial::Entry.create!(
              account_id: @account.id,
              bank_account_id: @bank_account.id,
              dre_category_id: resolve_revenue_category(inst),
              direction: 'inflow',
              kind: 'revenue',
              amount_cents: applied_cents,
              competence_date: inst.budget&.approved_at&.to_date || @received_at,
              cash_date: @received_at,
              affects_dre: true,
              description: "Recebimento parcela #{inst.sequence}/#{inst.total_count}",
              patient_id: inst.patient_id,
              source_type: 'Financial::PaymentReceiptItem',
              source_id: receipt.items.last.id
            )

            # Entry: MDR fee (se aplicável) — taxa congelada na parcela
            if inst.fee_amount_cents.to_i > 0
              proportion = applied_cents.to_d / inst.amount_cents
              fee_applied = (inst.fee_amount_cents * proportion).round
              Financial::Entry.create!(
                account_id: @account.id,
                bank_account_id: @bank_account.id,
                dre_category_id: mdr_category(@account),
                direction: 'outflow',
                kind: 'mdr_fee',
                amount_cents: fee_applied,
                competence_date: @received_at,
                cash_date: @received_at,
                affects_dre: true,
                description: "Taxa de maquininha (#{inst.payment_method&.name})",
                patient_id: inst.patient_id,
                source_type: 'Financial::PaymentReceiptItem',
                source_id: receipt.items.last.id
              )
            end

            # Commission entries — disparado por gatilho "pagamento_confirmado"
            Financial::Commissions::GenerateCommission.call(
              account: @account,
              installment: inst,
              applied_cents: applied_cents,
              trigger_event: 'pagamento_confirmado'
            )
          end
        end

        Financial::ServiceResult.success(payment_receipt: receipt)
      rescue ActiveRecord::Rollback => e
        Financial::ServiceResult.failure(e.message)
      end

      private

      def failure(msg)
        Financial::ServiceResult.failure(msg)
      end

      def next_receipt_number
        # Gera atomicamente via advisory lock + SELECT MAX
        ActiveRecord::Base.transaction(requires_new: true) do
          year = @received_at.year
          ActiveRecord::Base.connection.execute(
            "SELECT pg_advisory_xact_lock(hashtext('receipt_number_#{@account.id}_#{year}'))"
          )
          last = Financial::PaymentReceipt
                   .for_account(@account.id)
                   .where("receipt_number LIKE ?", "REC-#{year}-%")
                   .order(receipt_number: :desc)
                   .pluck(:receipt_number)
                   .first
          seq = last ? last.split('-').last.to_i + 1 : 1
          "REC-#{year}-#{seq.to_s.rjust(6, '0')}"
        end
      end

      def resolve_revenue_category(installment)
        # Resolve categoria do plano de contas via Budget Item ou padrão
        installment.budget&.items&.first&.dre_category_id ||
          Financial::DreCategory.for_account(@account.id).find_by!(system_default: true, kind: 'revenue', name: 'Sem categoria').id
      end

      def mdr_category(account)
        Financial::DreCategory.for_account(account.id)
                                .where(kind: 'expense')
                                .find_by!(name: 'Taxa de Maquininha e Cartão')
                                .id
      end
    end
  end
end
```

### 4.3 Refund proporcional (`Financial::Payments::RefundPayment`)

```ruby
module Financial
  module Payments
    class RefundPayment
      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(account:, installment:, refund_amount_cents:, reason:, refund_method:, bank_account:, actor:)
        @account = account
        @installment = installment
        @refund_amount_cents = refund_amount_cents
        @reason = reason
        @refund_method = refund_method  # 'cash' | 'pix' | 'bank_transfer' | 'patient_credit'
        @bank_account = bank_account
        @actor = actor
      end

      def call
        return failure('valor inválido') if @refund_amount_cents <= 0
        return failure('motivo obrigatório') if @reason.blank?
        return failure('parcela não foi paga') if @installment.received_amount_cents <= 0
        return failure('valor maior que pago') if @refund_amount_cents > @installment.received_amount_cents

        refund = nil
        ActiveRecord::Base.transaction do
          @installment.lock!
          @installment.reload

          # Proporção do estorno
          proportion_bps = (@refund_amount_cents.to_d / @installment.received_amount_cents * 10_000).round.clamp(1, 10_000)

          refund = Financial::Refund.create!(
            account_id: @account.id,
            installment_id: @installment.id,
            refund_amount_cents: @refund_amount_cents,
            refund_proportion_bps: proportion_bps,
            reason: @reason,
            refund_method: @refund_method,
            bank_account_id: @refund_method == 'patient_credit' ? nil : @bank_account&.id,
            refunded_at: Date.current
          )

          # Reduz received_amount na parcela
          @installment.update!(
            received_amount_cents: @installment.received_amount_cents - @refund_amount_cents,
            status: @installment.received_amount_cents - @refund_amount_cents == 0 ? 'pending' : 'pending'
          )

          # Entry: estorno (outflow) — data atual, não retroativa
          Financial::Entry.create!(
            account_id: @account.id,
            bank_account_id: @bank_account&.id || patient_credit_holding_account.id,
            dre_category_id: refund_category(@account),
            direction: 'outflow',
            kind: 'refund',
            amount_cents: @refund_amount_cents,
            competence_date: Date.current,
            cash_date: Date.current,
            affects_dre: true,
            description: "Estorno parcela #{@installment.sequence}/#{@installment.total_count} — #{@reason.truncate(80)}",
            patient_id: @installment.patient_id,
            source_type: 'Financial::Refund',
            source_id: refund.id
          )

          # Patient credit (se for crédito)
          if @refund_method == 'patient_credit'
            Financial::PatientCredit.create!(
              account_id: @account.id,
              patient_id: @installment.patient_id,
              amount_cents: @refund_amount_cents,
              source_type: 'Financial::Refund',
              source_id: refund.id,
              notes: "Crédito de estorno — #{@reason.truncate(80)}"
            )
          end

          # Comissões: reverso PROPORCIONAL
          @installment.commission_entries
                      .where(status: %w[due provisioned approved to_pay])
                      .find_each do |comm|
            partial = (comm.commission_amount_cents * proportion_bps / 10_000.0).round

            Financial::CommissionEntry.create!(
              account_id: @account.id,
              installment_id: @installment.id,
              budget_id: comm.budget_id,
              agent_user_id: comm.agent_user_id,
              commission_rule_id: comm.commission_rule_id,
              rule_snapshot: comm.rule_snapshot,
              base_amount_cents: comm.base_amount_cents,
              mdr_deduction_cents: comm.mdr_deduction_cents,
              net_base_cents: comm.net_base_cents,
              commission_amount_cents: -partial,  # negativo
              status: 'reversed',
              triggered_at: Time.current,
              reverses_commission_entry_id: comm.id
            )

            # Se a original já tinha sido paga (via Expense), criar nota de débito
            if comm.status == 'paid' && comm.paid_via_expense_id.present?
              # Estorno gera "Adiantamento de comissão" pendente — operador resolve manualmente
              # (não devolve automaticamente Expense paga; isso é decisão operacional)
            end
          end
        end

        Financial::ServiceResult.success(refund: refund)
      rescue ActiveRecord::Rollback => e
        failure(e.message)
      end

      private

      def failure(msg)
        Financial::ServiceResult.failure(msg)
      end

      def patient_credit_holding_account
        # Conta sintética para reter crédito do paciente (não afeta saldo real)
        Financial::BankAccount.for_account(@account.id).alive.find_by!(kind: 'digital_wallet', system_default: true)
      end

      def refund_category(account)
        Financial::DreCategory.for_account(account.id)
                                .where(kind: 'revenue')
                                .find_by!(name: 'Estornos')  # subtrai da receita
                                .id
      end
    end
  end
end
```

### 4.4 PayCommission (idempotente, validação fora da transação)

```ruby
module Financial
  module Commissions
    class PayCommission
      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(account:, commission_entry:, bank_account:, actor:)
        @account = account
        @commission_entry = commission_entry
        @bank_account = bank_account
        @actor = actor
      end

      def call
        # Idempotência forte: se já tem expense vinculada, retorna sucesso
        if @commission_entry.paid_via_expense_id.present?
          return Financial::ServiceResult.success(
            commission_entry: @commission_entry,
            expense: Financial::Expense.find(@commission_entry.paid_via_expense_id),
            already_paid: true
          )
        end

        # Validações leves (fora da transação)
        unless %w[due approved to_pay].include?(@commission_entry.status)
          return Financial::ServiceResult.failure("status inválido: #{@commission_entry.status}")
        end

        return Financial::ServiceResult.failure('bank_account required') if @bank_account.nil?

        category = Financial::DreCategory.for_account(@account.id)
                                            .where(kind: 'expense')
                                            .find_by(name: 'Comissões de Profissionais')
        return Financial::ServiceResult.failure('categoria de Comissões de Profissionais não cadastrada') if category.nil?

        expense = nil
        ActiveRecord::Base.transaction do
          @commission_entry.lock!
          @commission_entry.reload

          # Re-check idempotência pós-lock
          if @commission_entry.paid_via_expense_id.present?
            expense = Financial::Expense.find(@commission_entry.paid_via_expense_id)
            raise ActiveRecord::Rollback, '__idempotent__'
          end

          expense = Financial::Expense.create!(
            account_id: @account.id,
            dre_category_id: category.id,
            bank_account_id: @bank_account.id,
            description: "Comissão #{@commission_entry.agent_user&.full_name}",
            amount_cents: @commission_entry.commission_amount_cents,
            paid_amount_cents: 0,
            competence_date: Date.current,
            due_date: Date.current,
            status: 'pending',
            source_type: 'Financial::CommissionEntry',
            source_id: @commission_entry.id
          )

          @commission_entry.update!(status: 'paid', paid_via_expense_id: expense.id)
        end

        Financial::ServiceResult.success(commission_entry: @commission_entry, expense: expense)
      end
    end
  end
end
```

### 4.5 Outros services (interfaces)

| Service | Responsabilidade | Lock crítico |
|---|---|---|
| `Financial::Budgets::ApproveBudget` | Aprova budget, gera installments com snapshot de taxa | `Budget`, `Installment` |
| `Financial::Budgets::EditApprovedBudget` | Edita installments. Recalcula comissão proporcional. | `Budget`, `Installments` |
| `Financial::Budgets::CancelBudget` | Cancela budget, marca installments pending como canceled, reverte comissões provisionadas | `Budget`, `Installments`, `CommissionEntries` |
| `Financial::Payments::PayExpense` | Paga ou paga parcial uma despesa | `Expense` |
| `Financial::Payments::ReverseExpense` | Cria Entry inverso de uma despesa paga | `Expense` |
| `Financial::Commissions::GenerateCommission` | Por gatilho — chamado por ReceivePayment, ApproveBudget, etc. Não duplica via unique index | `Installment`, `CommissionRule` lookup |
| `Financial::Commissions::ApproveCommission` | Muda status `due` → `approved` | `CommissionEntry` |
| `Financial::CashRegister::OpenSession` | Abre caixa | `BankAccount` (cash kind) |
| `Financial::CashRegister::CloseSession` | Fecha, calcula esperado, registra quebra | `CashRegister`, `BankAccount` |
| `Financial::CashRegister::ReopenSession` | Reabre (GERENTE/ADMIN), incrementa `reopen_count` | `CashRegister` |
| `Financial::CashRegister::Sangria` | Transfer interno: caixa → conta bancária | 2 `BankAccount`s |
| `Financial::CashRegister::Suprimento` | Transfer interno: conta bancária → caixa | 2 `BankAccount`s |
| `Financial::Recurring::GenerateRecurringExpenses` | Cron: gera Expenses para próximos 35 dias. Idempotente por unique index. | `RecurringExpense`, batch insert |
| `Financial::Transfers::TransferBetweenAccounts` | Move dinheiro entre contas. Cria 2 entries (transfer_internal) com `transfer_pair_id`. NÃO afeta DRE. | 2 `BankAccount`s |
| `Financial::Governance::ClosePeriod` | Fecha mês contábil. Bloqueia edição retroativa via middleware. | — |
| `Financial::Governance::ReopenPeriod` | Reabre (ADMIN only). | — |
| `Financial::Governance::AnonymizePatient` | LGPD: anonimiza nome/email/telefone em todas Entries/Installments | Em massa, em batches |

---

## 5. Padrão de Controllers

### 5.1 `BaseController`

```ruby
module Api::V1::Accounts::Financial
  class BaseController < ::Api::V1::Accounts::BaseController
    include IdempotentAction
    include RequireRole
    include EnsureSetupComplete

    before_action :populate_financial_current
    before_action :ensure_setup_complete!

    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from ActiveRecord::RecordInvalid,  with: :render_unprocessable
    rescue_from Financial::Errors::PeriodClosed, with: :render_period_closed
    rescue_from Financial::Errors::TenantMismatch, with: :render_forbidden
    rescue_from Financial::Gateways::GatewayError, with: :render_gateway_error

    private

    def populate_financial_current
      Financial::CurrentUser.user = current_user
      Financial::CurrentUser.account = current_account
      Financial::CurrentUser.request_id = request.request_id
      Financial::CurrentUser.ip_address = request.remote_ip
      Financial::CurrentUser.user_agent = request.user_agent
    end

    def ensure_setup_complete!
      return if action_belongs_to_setup_wizard?
      return if Financial::SetupState.completed_for?(current_account.id)
      render json: { error: 'setup_incomplete', setup_url: financial_setup_path }, status: :precondition_required
    end

    def action_belongs_to_setup_wizard?
      controller_name == 'setup' || (controller_path.start_with?('api/v1/accounts/financial/') && %w[dre_categories bank_accounts commission_rules recurring_expenses revenue_goals payment_methods].include?(controller_name) && action_name.in?(%w[index create]))
    end

    def render_not_found(e)
      render json: { error: e.message }, status: :not_found
    end

    def render_unprocessable(e)
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def render_period_closed(e)
      render json: { error: 'period_closed', message: e.message }, status: :locked
    end

    def render_forbidden(_e)
      render json: { error: 'forbidden' }, status: :forbidden
    end

    def render_gateway_error(e)
      render json: { error: 'gateway_error', message: e.message }, status: :bad_gateway
    end
  end
end
```

### 5.2 `RequireRole` concern

```ruby
module Api::V1::Accounts::Financial
  module RequireRole
    extend ActiveSupport::Concern

    ROLE_MAP = {
      'RECEPCAO' => 1, 'DENTIST' => 2, 'GERENTE' => 3, 'ADMIN' => 4, 'AUDITOR' => 2
    }.freeze

    def require_role!(*roles)
      return if user_has_any_role?(roles)
      render json: { error: 'insufficient_role', required: roles }, status: :forbidden
    end

    def require_min_role!(min_role)
      min_level = ROLE_MAP.fetch(min_role)
      user_level = ROLE_MAP[current_user_role] || 0
      return if user_level >= min_level
      render json: { error: 'insufficient_role', required: min_role }, status: :forbidden
    end

    def user_has_any_role?(roles)
      roles.flatten.include?(current_user_role)
    end

    def current_user_role
      # Integração com RBAC Klivy (memória: project_rbac_klivy_only)
      ::Klivy::Rbac.role_for(account: current_account, user: current_user)
    end
  end
end
```

### 5.3 `IdempotentAction` (com persistência de 4xx)

```ruby
module Api::V1::Accounts::Financial
  module IdempotentAction
    extend ActiveSupport::Concern

    def idempotent!(&block)
      key = request.headers['Idempotency-Key']
      if key.blank?
        return yield  # sem key, executa normal (mas em ações de escrita, deve ser obrigatória)
      end

      fingerprint = Digest::SHA256.hexdigest("#{request.method}|#{request.path}|#{request.raw_post}")

      cached = Financial::IdempotencyKey.find_by(account_id: current_account.id, key: key)
      if cached
        if cached.fingerprint != fingerprint
          render json: { error: 'idempotency_key_mismatch', message: 'Key reused with different payload' },
                 status: :unprocessable_entity
          return
        end
        render json: cached.response_body, status: cached.response_status
        return
      end

      yield

      # Persistir TODOS os status code (2xx e 4xx). 5xx é transient — não cacheia.
      if response.status >= 200 && response.status < 500
        body = response.body.present? ? JSON.parse(response.body) : {}
        Financial::IdempotencyKey.create!(
          account_id: current_account.id,
          key: key,
          fingerprint: fingerprint,
          response_status: response.status,
          response_body: body
        )
      end
    rescue ActiveRecord::RecordNotUnique
      # Outra request com mesmo key acabou de gravar — retry lookup
      cached = Financial::IdempotencyKey.find_by!(account_id: current_account.id, key: key)
      render json: cached.response_body, status: cached.response_status
    end
  end
end
```

### 5.4 Template de controller

```ruby
module Api::V1::Accounts::Financial
  class PaymentReceiptsController < BaseController
    before_action :require_role!, only: %i[create destroy refund]

    def index
      receipts = Financial::PaymentReceipt
                   .for_account(current_account.id)
                   .alive
                   .includes(:items)
                   .order(received_at: :desc)
                   .page(params[:page]).per(params[:per_page] || 25)
      render json: serialize_list(receipts)
    end

    def show
      receipt = Financial::PaymentReceipt.for_account(current_account.id).alive.find(params[:id])
      render json: serialize(receipt)
    end

    def create
      idempotent! do
        result = Financial::Payments::ReceivePayment.call(
          account: current_account,
          bank_account: bank_account!,
          installment_amounts: receipt_params[:installments].map(&:to_h),
          received_at: Date.parse(receipt_params[:received_at]),
          actor: current_user,
          idempotency_key: request.headers['Idempotency-Key'],
          notes: receipt_params[:notes]
        )

        if result.success?
          render json: serialize(result[:payment_receipt]), status: :created
        else
          render json: { errors: result.errors }, status: :unprocessable_entity
        end
      end
    end

    private

    def required_roles_for(_)
      %w[RECEPCAO GERENTE ADMIN]
    end

    def bank_account!
      Financial::BankAccount.for_account(current_account.id).alive.find(receipt_params[:bank_account_id])
    end

    def receipt_params
      params.require(:payment_receipt).permit(
        :bank_account_id, :received_at, :notes,
        installments: %i[installment_id amount_cents]
      )
    end
  end
end
```

---

## 6. Webhooks e gateways

### 6.1 Adapter base

```ruby
module Financial
  module Gateways
    class Base
      class GatewayError < StandardError; end

      def initialize(setting)
        @setting = setting
      end

      def verify_webhook(headers:, body:)
        raise NotImplementedError
      end

      def parse_event(headers:, body:)
        raise NotImplementedError
      end
    end
  end
end
```

### 6.2 Adapter Asaas (timing-safe)

```ruby
module Financial
  module Gateways
    class Asaas < Base
      def verify_webhook(headers:, body:)
        provided = headers['Asaas-Access-Token'].to_s
        expected = @setting.webhook_secret.to_s
        return false if provided.empty? || expected.empty?
        # CRÍTICO: timing-safe compare
        ActiveSupport::SecurityUtils.secure_compare(provided, expected)
      end

      def parse_event(headers:, body:)
        payload = JSON.parse(body, symbolize_names: true)
        {
          event_id: payload[:id] || "#{payload[:event]}_#{payload.dig(:payment, :id)}_#{payload.dig(:payment, :status)}",
          event_type: payload[:event].to_s,
          payload: payload,
          paid_date: payload.dig(:payment, :paymentDate)
        }
      end
    end
  end
end
```

### 6.3 Webhook controller (constant-time response)

```ruby
module Webhooks::Financial
  class AsaasController < ::ActionController::API
    skip_forgery_protection

    def receive
      account = ::Account.find_by(id: params[:account_id])
      setting = account ? Financial::GatewaySetting.find_by(account_id: account.id, gateway: 'asaas', status: 'active') : nil

      # Constant-time response — não distinguir account inexistente de setting inativo
      unless setting&.webhook_secret.present?
        return head :forbidden
      end

      adapter = Financial::Gateways::Asaas.new(setting)
      unless adapter.verify_webhook(headers: request.headers, body: request.raw_post)
        return head :unauthorized
      end

      parsed = adapter.parse_event(headers: request.headers, body: request.raw_post)

      event = Financial::GatewayWebhookEvent.create!(
        account_id: account.id,
        gateway: 'asaas',
        event_id: parsed[:event_id],
        event_type: parsed[:event_type],
        payload: parsed[:payload],
        signature: request.headers['Asaas-Access-Token']
      )

      Financial::Webhooks::ProcessAsaasEventJob.perform_later(event.id)

      head :ok
    rescue ActiveRecord::RecordNotUnique
      # Replay — já processamos esse event_id
      head :ok
    end
  end
end
```

### 6.4 Job de processamento

```ruby
module Financial
  module Webhooks
    class ProcessAsaasEventJob < ApplicationJob
      queue_as :financial_webhooks
      retry_on Net::ReadTimeout, ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5
      discard_on ActiveJob::DeserializationError

      def perform(event_id)
        event = Financial::GatewayWebhookEvent.find(event_id)
        return if event.status == 'processed'

        event.update!(attempt_count: event.attempt_count + 1)

        result = case event.event_type
                 when 'PAYMENT_RECEIVED', 'PAYMENT_CONFIRMED'
                   handle_payment_received(event)
                 when 'PAYMENT_REFUNDED'
                   handle_payment_refunded(event)
                 when 'PAYMENT_OVERDUE'
                   handle_payment_overdue(event)
                 else
                   Financial::ServiceResult.success(skipped: true, reason: 'unsupported_event')
                 end

        if result.success?
          event.update!(status: result[:skipped] ? 'skipped' : 'processed', processed_at: Time.current)
        else
          event.update!(status: 'failed', failed_at: Time.current, failure_reason: result.errors.join('; '))
          # Não re-raise para falha de domínio (não é transient). Re-raise apenas em erros estruturais.
        end
      end

      private

      def handle_payment_received(event)
        payment = event.payload[:payment]
        return Financial::ServiceResult.failure('payment payload missing') if payment.blank?

        # CRÍTICO: paid_date do payload, NÃO Date.current
        paid_date = begin
          Date.parse(payment[:paymentDate].to_s)
        rescue ArgumentError
          Date.current  # fallback se ausente/inválido
        end

        installment = Financial::Installment
                        .for_account(event.account_id)
                        .alive
                        .find_by(external_provider: 'asaas', external_id: payment[:id])
        return Financial::ServiceResult.failure("installment not found for asaas:#{payment[:id]}") if installment.nil?

        bank = Financial::BankAccount.for_account(event.account_id).alive.find_by(is_default_inflow: true)
        return Financial::ServiceResult.failure('default inflow bank account missing') if bank.nil?

        Financial::Payments::ReceivePayment.call(
          account: ::Account.find(event.account_id),
          bank_account: bank,
          installment_amounts: [{ installment_id: installment.id, amount_cents: installment.amount_cents }],
          received_at: paid_date,
          actor: nil,
          idempotency_key: "asaas:#{event.event_id}",
          notes: "[Asaas webhook] event_id=#{event.event_id}"
        )
      end

      def handle_payment_refunded(event)
        # similar pattern
      end

      def handle_payment_overdue(event)
        # marca installment como overdue
      end
    end
  end
end
```

---

## 7. Multi-tenant enforcement

### 7.1 Camadas

1. **Banco**: FK `add_foreign_key on_delete: :restrict` em todo `account_id`.
2. **Model**: `validates :account_id, presence: true` em `Financial::ApplicationRecord`.
3. **Controller**: `for_account(current_account.id)` em todo query inicial.
4. **Webhook**: `account_id` validado contra `GatewaySetting` com constant-time response.
5. **Test**: cada controller tem teste de tenant isolation.

### 7.2 Helper de teste

```ruby
# spec/support/financial_tenant_isolation.rb
module FinancialTenantIsolation
  def isolate_tenants
    @account_a = create(:account)
    @account_b = create(:account)
    @user_a = create(:user, account: @account_a)
    @user_b = create(:user, account: @account_b)
  end

  def expect_tenant_isolated(model:, create_in:, find_via:)
    record = create(model, account: @account_a)
    sign_in(@user_b)
    response = find_via.call(record.id)
    expect(response.status).to eq(404)
  end
end

# spec/requests/api/v1/accounts/financial/installments_spec.rb
RSpec.describe 'Financial::Installments' do
  include FinancialTenantIsolation

  before { isolate_tenants }

  describe 'tenant isolation' do
    it 'GET /installments/:id 404 when from other tenant' do
      installment = create(:financial_installment, account: @account_a)
      sign_in(@user_b)
      get "/api/v1/accounts/#{@account_b.id}/financial/v2/installments/#{installment.id}"
      expect(response).to have_http_status(:not_found)
    end

    it 'PATCH /installments/:id 404 when from other tenant' do
      # ...
    end

    # ... para cada endpoint sensível
  end
end
```

---

## 8. Imutabilidade e versionamento

### 8.1 Campos congelados por modelo

| Modelo | Campos congelados (`frozen_attributes`) |
|---|---|
| `Financial::Installment` | `amount_cents`, `payment_method_id`, `payment_method_fee_id`, `fee_percent_basis_points`, `fee_fixed_cents`, `fee_amount_cents` (após criação) |
| `Financial::CommissionEntry` | TODOS exceto `status`, `approved_at`, `approved_by_id`, `paid_via_expense_id` |
| `Financial::Entry` | TODOS exceto soft-delete columns |
| `Financial::PaymentReceiptItem` | TODOS (após criação) |
| `Financial::Refund` | TODOS (após criação) |
| `Financial::PaymentMethodFee` | `fee_percent_basis_points`, `fee_fixed_cents`, `valid_from`, `installments_count`, `payment_method_id`, `account_id` |
| `Financial::CommissionRule` | `percent_basis_points`, `fixed_amount_cents`, `valid_from`, `role`, `trigger_event`, `calc_kind` |
| `Financial::RecurringExpense` | `default_amount_cents`, `frequency`, `due_day`, `valid_from` |

Implementação:
```ruby
class Financial::Installment < Financial::ApplicationRecord
  include Financial::Concerns::SoftDeletable
  include Financial::Concerns::Auditable
  include Financial::Concerns::Stamped
  include Financial::Concerns::MoneyAttribute

  frozen_attributes :amount_cents, :payment_method_id, :payment_method_fee_id,
                    :fee_percent_basis_points, :fee_fixed_cents, :fee_amount_cents

  money_attribute :amount_cents, as: :amount
  money_attribute :received_amount_cents, as: :received_amount

  belongs_to :budget, class_name: 'Financial::Budget', optional: true
  belongs_to :patient, class_name: '::Patient', optional: true
  has_many :payment_receipt_items, class_name: 'Financial::PaymentReceiptItem'
  has_many :commission_entries, class_name: 'Financial::CommissionEntry'

  STATUSES = %w[pending received overdue renegotiated canceled].freeze
  validates :status, inclusion: { in: STATUSES }
end
```

### 8.2 Versionamento (sempre criar nova versão)

UI/Backend nunca permite `UPDATE` em `PaymentMethodFee.fee_percent_basis_points`. Para "alterar taxa":
1. `PUT /payment_method_fees/:id` retorna 422 com instrução: "Use POST /payment_method_fees com valid_from futuro".
2. Frontend mostra modal "Inativar taxa atual e criar nova" com data de início.

---

## 9. Period closure

### 9.1 Modelo

```ruby
class Financial::PeriodClosure < Financial::ApplicationRecord
  validates :period_year, :period_month, presence: true
  validates :period_month, inclusion: { in: 1..12 }

  def self.closed_for?(account, date)
    where(account_id: account.id, period_year: date.year, period_month: date.month, status: 'closed').exists?
  end
end
```

### 9.2 Middleware / before_action

```ruby
# Em cada model com competence_date / cash_date:
class Financial::Entry < Financial::ApplicationRecord
  validate :period_not_closed, on: %i[create update]

  def period_not_closed
    return unless competence_date.present?
    if Financial::PeriodClosure.closed_for?(Financial::CurrentUser.account, competence_date)
      raise Financial::Errors::PeriodClosed,
            "competence_date #{competence_date} cai em período fechado (#{competence_date.strftime('%m/%Y')})"
    end
    if cash_date.present? && Financial::PeriodClosure.closed_for?(Financial::CurrentUser.account, cash_date)
      raise Financial::Errors::PeriodClosed,
            "cash_date #{cash_date} cai em período fechado"
    end
  end
end
```

### 9.3 Reopen (ADMIN only)

```ruby
# Financial::Governance::ReopenPeriod
def call
  return failure('apenas ADMIN pode reabrir período') unless @actor.role == 'ADMIN'
  return failure('motivo obrigatório') if @reason.blank?

  closure.update!(
    status: 'reopened',
    reopened_at: Time.current,
    reopened_by_id: @actor.id,
    reopen_reason: @reason
  )
  # Auditoria detalhada (já automática via concern)
end
```

---

## 10. Setup wizard

### 10.1 Steps obrigatórios (canon)

1. Profissionais cadastrados (≥1 ativo)
2. Plano de Contas — categorias seed criadas + "Sem categoria"
3. Formas de Pagamento — pelo menos Dinheiro ativo
4. Contas Bancárias — ≥1 conta corrente + 1 caixa físico
5. Regras de Comissão — pelo menos uma regra por profissional ativo
6. Procedimentos (futuro — pode ser opcional inicialmente)
7. Despesas Recorrentes (opcional — pode ser pulado)
8. Metas (opcional)

### 10.2 Model

```ruby
class Financial::SetupState < Financial::ApplicationRecord
  REQUIRED_STEPS = %i[step_categories step_payment_methods step_bank_accounts step_commission_rules].freeze

  def required_completed?
    REQUIRED_STEPS.all? { |s| public_send(s) }
  end

  def self.completed_for?(account_id)
    find_by(account_id: account_id)&.required_completed? == true
  end

  def recompute!
    update!(
      step_categories: Financial::DreCategory.for_account(account_id).alive.exists?,
      step_payment_methods: Financial::PaymentMethod.for_account(account_id).alive.where(status: 'active').exists?,
      step_bank_accounts: Financial::BankAccount.for_account(account_id).alive.where(status: 'active').exists?,
      step_commission_rules: Financial::CommissionRule.for_account(account_id).alive.where(status: 'active').exists?,
      step_recurring_expenses: Financial::RecurringExpense.for_account(account_id).alive.exists?,
      step_goals: Financial::RevenueGoal.for_account(account_id).alive.where(status: 'active').exists?,
      completed_at: required_completed? ? (completed_at || Time.current) : nil,
      completed_by_id: required_completed? ? (completed_by_id || Financial::CurrentUser.user&.id) : nil
    )
  end
end
```

### 10.3 Controller

```ruby
class Api::V1::Accounts::Financial::SetupController < BaseController
  skip_before_action :ensure_setup_complete!

  def show
    state = Financial::SetupState.find_or_create_by!(account_id: current_account.id)
    state.recompute!
    render json: serialize(state)
  end

  def complete_step
    require_role!('GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[GERENTE ADMIN])
    state = Financial::SetupState.find_or_create_by!(account_id: current_account.id)
    state.recompute!
    render json: serialize(state)
  end
end
```

---

## 11. Frontend patterns

### 11.1 useMoney (canonical, já existe — pequenos ajustes)

```js
// plugins/financial/frontend/features/financial/v2/composables/useMoney.js
export function useMoney() {
  const centsToBRL = (cents) => {
    if (cents == null) return 'R$ 0,00';
    return (cents / 100).toLocaleString('pt-BR', {
      style: 'currency',
      currency: 'BRL',
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    });
  };

  const brlInputToCents = (str) => {
    if (str == null || str === '') return null;
    const clean = String(str).replace(/[^\d,.-]/g, '').replace(/\./g, '').replace(',', '.');
    const num = parseFloat(clean);
    if (Number.isNaN(num)) return null;
    return Math.round(num * 100);
  };

  const splitCents = (totalCents, n) => {
    if (n <= 0) return [];
    const base = Math.floor(totalCents / n);
    const remainder = totalCents - base * n;
    return Array.from({ length: n - 1 }, () => base).concat([base + remainder]);
  };

  return { centsToBRL, brlInputToCents, splitCents };
}
```

### 11.2 Idempotency-Key client

```js
// plugins/financial/frontend/features/financial/v2/api/financialV2.js
const generateIdempotencyKey = () => crypto.randomUUID();

// Idempotency-Key é gerada POR INTENÇÃO — armazenada num ref durante a sessão de submit.
// Retry com o MESMO key = mesma intenção. Submit novo = key nova.
const submitWithIdempotency = async (action, payload) => {
  const key = generateIdempotencyKey();
  const headers = { 'Idempotency-Key': key };
  try {
    return await action(payload, { headers });
  } catch (err) {
    if (err.response?.status === 5xx_transient) {
      // Retry com MESMO key
      return await action(payload, { headers });
    }
    throw err;
  }
};
```

### 11.3 Modais que substituem `window.prompt`/`confirm`

Criar em `plugins/financial/frontend/features/financial/v2/components/modals/`:

1. `CashRegisterOpenModal.vue` — campo `FormInput` com máscara de moeda, valida client-side.
2. `CashRegisterCloseModal.vue` — mostra "Saldo esperado: R$X". Input "Saldo contado". Mostra diferença em vermelho/verde.
3. `CashRegisterSangriaModal.vue` — select conta destino + input valor.
4. `CashRegisterSuprimentoModal.vue` — select conta origem + input valor.
5. `CashRegisterReopenModal.vue` — textarea motivo obrigatório (max 500), input só GERENTE/ADMIN.
6. `RefundReasonModal.vue` — textarea motivo (max 500), select método de devolução (Crédito do paciente / Dinheiro / Pix / Transferência), input valor (proporção mostrada em real-time).
7. `ConfirmSeedCategoriesModal.vue` — lista categorias que serão criadas, checkbox por uma.

Padrão de modal:
```vue
<template>
  <Modal v-model="isOpen" @close="onCancel">
    <header>
      <h2>{{ title }}</h2>
    </header>
    <main>
      <FormInput v-model="amount" type="money" :error="errors.amount" />
      <ErrorBanner v-if="loadError" :error="loadError" @retry="loadAux" />
    </main>
    <footer>
      <BeclinicButton @click="onCancel" :disabled="submitting">Cancelar</BeclinicButton>
      <BeclinicButton variant="primary" @click="onSubmit" :loading="submitting" :disabled="!canSubmit">Confirmar</BeclinicButton>
    </footer>
  </Modal>
</template>

<script setup>
const submitting = ref(false);
const loadError = ref(null);
const errors = reactive({});

async function onSubmit() {
  if (!validateClient()) return;
  submitting.value = true;
  try {
    await FinancialV2.cashRegisters.open(payload);
    notifySuccess('Caixa aberto');
    emit('confirmed');
  } catch (err) {
    notifyError(err.response?.data?.error || 'Falha ao abrir caixa');
  } finally {
    submitting.value = false;
  }
}
</script>
```

### 11.4 Pages com paginação server-side

`CashRegisterV2.vue` precisa de:
```js
const fetchHistory = async () => {
  const { data } = await FinancialV2.cashRegisters.index({
    page: currentPage.value,
    per_page: 20,
    from: filterFrom.value,
    to: filterTo.value
  });
  history.value = data.data;
  totalCount.value = data.meta.total;
};
```

### 11.5 Error banners obrigatórios em modais

Quando `loadBankAccounts()` (ou similar) falha, modal mostra banner visível com botão "Tentar novamente". Nunca silent fail.

---

## 12. Cálculos financeiros (regras)

### 12.1 Distribuição de centavos

```ruby
# Sempre via Financial::Concerns::MoneyAttribute.split_cents
# 920_00 cents ÷ 3 = [306_66, 306_66, 306_68]
```

### 12.2 Taxa MDR

```ruby
def lookup_fee(account_id:, payment_method_id:, installments_count:, date:)
  Financial::PaymentMethodFee
    .for_account(account_id)
    .alive
    .where(payment_method_id: payment_method_id, installments_count: installments_count, status: 'active')
    .where('valid_from <= ?', date)
    .where('valid_to IS NULL OR valid_to >= ?', date)
    .order(valid_from: :desc)
    .first
end

def calculate_fee(amount_cents, fee)
  return 0 if fee.nil?
  pct_part = (amount_cents * fee.fee_percent_basis_points / 10_000.0).round
  fixed_part = fee.fee_fixed_cents
  pct_part + fixed_part
end
```

### 12.3 Comissão (proportional refund)

```ruby
# Estorno de R$300 de parcela de R$1000 com comissão R$100:
# proportion_bps = (30_000 / 100_000 * 10_000).round = 3000
# partial_reversion = (10_000 * 3000 / 10_000).round = 3_000  (R$30)
# CommissionEntry created with commission_amount_cents: -3_000
```

### 12.4 DRE com filtro defensivo

```ruby
def entries_for_dre(account_id:, from:, to:)
  Financial::Entry
    .for_account(account_id)
    .alive
    .where(affects_dre: true)
    .where.not(kind: 'transfer_internal')  # defesa explícita
    .where(competence_date: from..to)
end
```

### 12.5 Ticket médio (corrigido)

Definição: `Receita ÷ atendimentos` (NÃO pacientes únicos). Atendimento ≈ procedimento executado no período.

```ruby
def ticket_medio(account_id:, from:, to:)
  revenue_cents = entries_for_dre(account_id:, from:, to:).inflow.sum(:amount_cents)
  appointments_count = ::Appointment.for_account(account_id).where(performed_at: from..to).count
  return 0 if appointments_count.zero?
  (revenue_cents / appointments_count.to_d).round.to_i
end
```

---

## 13. Performance e escalabilidade

### 13.1 Indexes (já incluídos no DDL)

- `idx_entries_account_competence` (partial, `affects_dre = true`) — DRE
- `idx_entries_account_cash` (partial, alive) — Fluxo de Caixa
- `idx_entries_bank` (bank_account_id, cash_date) — Saldo
- `idx_installments_account_due` (partial, status='pending') — A Receber
- `idx_expenses_account_due` (partial, status IN ('pending','partially_paid')) — A Pagar
- `idx_payment_method_fees_lookup` — Lookup de taxa

### 13.2 Cache de Dashboard KPIs

```ruby
class Financial::Reports::DashboardKpis
  def call
    Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
      compute
    end
  end

  def cache_key
    last_modified = Financial::Entry.for_account(@account.id).maximum(:updated_at)
    "fin_dashboard:#{@account.id}:#{@period_from}:#{@period_to}:#{last_modified&.to_i}"
  end
end
```

### 13.3 Async exports

Audit log export, DRE PDF, backup full — todos via job + email com link assinado expirando 1h.

### 13.4 Rate limiting

`Rack::Attack` em:
- `POST /financial/v2/payment_receipts` — 60/min/user (UI normal não passa disso)
- `GET /financial/v2/audit_logs/export_csv` — 1/24h/user
- `POST /webhooks/financial/asaas` — 100/min/account_id

---

## 14. Plano de execução (sprints)

### Sprint 1 (semana 1-2) — Foundation

> **Nota sobre importação de dados**: clínicas que vierem da Clinicorp/Eddental/etc usarão o tool já existente em `/super_admin/migrations`. Ele consome os endpoints V2 do módulo via API — o módulo financeiro não precisa de código de migração de schema legacy → V2 (não existe legacy com dado real). Drop pode ser destrutivo.

- [ ] Drop legacy: migrations, models, controllers, frontend api legacy
- [ ] Refactor `Financial::ApplicationRecord` (find/find_by override, validates account_id)
- [ ] Refactor concerns (Auditable com frozen_attributes, SoftDeletable, Stamped, MoneyAttribute)
- [ ] Migrations completas do schema (drop + create all)
- [ ] Seed mínimo (categorias padrão por canon, formas de pagamento padrão)
- [ ] Testes de isolation por endpoint (gera 1 test file por controller)

### Sprint 2 (semana 3-4) — Configurações

- [ ] `Financial::PaymentMethod` + `Financial::PaymentMethodFee` (modelo + controller + UI)
- [ ] `Financial::DreCategory` com hierarquia 4 níveis + seed canon
- [ ] `Financial::BankAccount` com `conexao_com_provedor` + `cutoff_date`
- [ ] `Financial::CommissionRule` com role + trigger_event + scope
- [ ] `Financial::RecurringExpense` com amount_kind (fixed/estimated)
- [ ] `Financial::RevenueGoal` com 3 níveis (min/target/stretch)
- [ ] Setup wizard obrigatório bloqueando módulo (`ensure_setup_complete!`)
- [ ] Frontend: SettingsV2 tabs reformatadas para versionamento (inativar+criar nova)
- [ ] **Migration: `DROP COLUMN price` em `agenda_services`** (clean break — sem cliente real)
- [ ] **`Financial::ServicePricing` (1-to-1 com `AgendaService`)** + controller + UI
  - UI em `/agenda/settings > aba Serviços` mantém só campos não-financeiros (nome, duração, cor, sala, profissionais vinculados)
  - UI em `/financial/v2/settings > tab Serviços` (NOVA tab) lista todos os AgendaServices ativos e permite definir/editar preço particular, preço convênio, DRE category, regra de comissão padrão, código TUSS
  - Serviço sem pricing cadastrado = warning visual ("Falta configurar preço") + bloqueio ao tentar lançar financeiramente
- [ ] **`Financial::AgentProfile` (1-to-1 com `User`)** + controller + UI
  - UI em `/settings/agents/list` mantém gerenciamento existente de User (não muda)
  - UI em `/financial/v2/settings > tab Agentes` (NOVA tab) lista users existentes e permite criar/editar perfil financeiro: tipo_vinculo, data_entrada, categoria, comissionado, CRO, especialidades, dados bancários
  - User sem AgentProfile cadastrado = não aparece em selects de profissional em fluxos financeiros (DR/SDR/Comercial)

### Sprint 3 (semana 5-6) — Operacional

- [ ] `Financial::Budgets::ApproveBudget` com snapshot de taxa
- [ ] `Financial::Budgets::EditApprovedBudget` com recálculo proporcional de comissão
- [ ] `Financial::Payments::ReceivePayment` com snapshot pós-lock + MDR via lookup
- [ ] `Financial::Payments::RefundPayment` com reverso proporcional
- [ ] `Financial::Commissions::GenerateCommission` com unique index + gatilhos configuráveis
- [ ] `Financial::Commissions::PayCommission` idempotente (validação fora da tx)
- [ ] `Financial::Transfers::TransferBetweenAccounts` com transfer_pair_id

### Sprint 4 (semana 7-8) — Caixa, recorrente, webhooks

- [ ] `Financial::CashRegister::*` services (Open/Close/Reopen/Sangria/Suprimento) com session_date correto
- [ ] `Financial::Recurring::GenerateRecurringExpenses` com Time.zone.today + unique index
- [ ] `Financial::Webhooks::ProcessAsaasEventJob` com paid_date do payload + mark_failed
- [ ] `Financial::Gateways::Asaas#verify_webhook` com `secure_compare`
- [ ] `Webhooks::Financial::AsaasController` com constant-time response
- [ ] `Financial::GatewaySetting` com ActiveRecord Encryption
- [ ] Idempotency em todas as ações de escrita (Budgets, GatewaySettings, PaymentMethods)
- [ ] Frontend: substituir 7 `window.prompt/confirm` por modais

### Sprint 5 (semana 9-10) — DRE, Reports, Governance

- [ ] `Financial::DreReport` com hierarquia 4 níveis + filtro defensivo transfer_internal
- [ ] `Financial::Reports::*` refatorados (ticket_medio corrigido, includes p/ N+1)
- [ ] `Financial::Governance::ClosePeriod` + `ReopenPeriod`
- [ ] Period closure validation em Entry/Installment/Expense
- [ ] `Financial::AuditLogsExportJob` (async + link assinado 1h)
- [ ] Rate limiting via Rack::Attack
- [ ] Cleanup job: `Financial::IdempotencyKeyCleanupJob`

### Sprint 6 (semana 11-12) — UX, Frontend polish, Performance

- [ ] Modais novos (7) finalizados e testados
- [ ] Paginação server-side em CashRegisterV2
- [ ] Error banners em modais quando aux load falha
- [ ] Tooltip "Regime caixa vs competência" no DRE
- [ ] Indicador visual "Período fechado" em pages
- [ ] Cache de Dashboard KPIs (5min)
- [ ] Indexes adicionais conforme observação de queries lentas
- [ ] Testes de invariantes (saldo, no over-payment, transfer não em DRE, etc)
- [ ] Acessibilidade: aria-labels, foco em modais

### Sprint 7 (semana 13) — Verificação final

- [ ] Teste E2E manual cobrindo todos os fluxos canon
- [ ] Teste de tenant isolation por endpoint (cobertura 100%)
- [ ] Teste de invariantes financeiros automatizado
- [ ] Documentação interna (este doc + canon atualizados)
- [ ] Treinamento da equipe Klivy
- [ ] Onboarding de 1 clínica piloto

---

## 15. Testes obrigatórios

### 15.1 Suite de invariantes (`spec/integrations/financial_invariants_spec.rb`)

```ruby
RSpec.describe 'Financial invariants' do
  let(:account) { create(:account) }

  describe 'tenant isolation' do
    let(:other) { create(:account) }
    %i[budget installment expense entry commission_entry payment_receipt bank_account dre_category
       commission_rule recurring_expense revenue_goal cash_register payment_method].each do |entity|
      it "no #{entity} is visible across accounts" do
        a = create(:"financial_#{entity}", account: account)
        b = create(:"financial_#{entity}", account: other)

        as(account) do
          all_visible = Financial.const_get(entity.to_s.camelize).for_account(account.id).alive.pluck(:id)
          expect(all_visible).to include(a.id)
          expect(all_visible).not_to include(b.id)
        end
      end
    end
  end

  describe 'balance invariant per bank account' do
    it 'sum(inflow) - sum(outflow) == current_balance - initial_balance' do
      bank = create(:financial_bank_account, account: account, initial_balance_cents: 100_000)
      receive_payment(amount_cents: 50_000, into: bank)
      pay_expense(amount_cents: 20_000, from: bank)
      transfer(amount_cents: 10_000, from: bank, to: other_bank)

      inflow = bank.entries.alive.inflow.sum(:amount_cents)
      outflow = bank.entries.alive.outflow.sum(:amount_cents)
      delta = bank.current_balance_cents - bank.initial_balance_cents
      expect(inflow - outflow).to eq(delta)
    end
  end

  describe 'no over-payment' do
    it 'cannot receive more than installment amount' do
      inst = create(:financial_installment, amount_cents: 100_000, account: account)
      expect {
        Financial::Payments::ReceivePayment.call(
          account: account, bank_account: bank, actor: user,
          installment_amounts: [{installment_id: inst.id, amount_cents: 150_000}],
          received_at: Date.current
        )
      }.not_to change { Financial::Entry.count }  # rollback
    end
  end

  describe 'immutability' do
    it 'frozen field raises on update attempt' do
      inst = create(:financial_installment, amount_cents: 100_000, account: account)
      expect {
        inst.update!(amount_cents: 50_000)
      }.to raise_error(ActiveRecord::RecordInvalid, /amount_cents.*frozen/)
    end

    it 'taxa snapshot is preserved when underlying fee changes' do
      fee = create(:financial_payment_method_fee, fee_percent_basis_points: 350)
      inst = create(:financial_installment, payment_method_fee_id: fee.id, fee_percent_basis_points: 350)
      fee.soft_delete!
      new_fee = create(:financial_payment_method_fee, fee_percent_basis_points: 200)
      expect(inst.reload.fee_percent_basis_points).to eq(350)  # snapshot intacto
    end
  end

  describe 'DRE excludes transfers' do
    it 'transfer entries never appear in DRE' do
      transfer(amount_cents: 100_000, from: bank_a, to: bank_b)
      dre = Financial::Reports::DreReport.new(account: account, from: 30.days.ago.to_date, to: Date.current).call
      transfer_kinds = dre.entries.pluck(:kind)
      expect(transfer_kinds).not_to include('transfer_internal')
    end
  end

  describe 'commission proportional refund' do
    it 'partial refund of 30% reverses 30% of commission' do
      # ... setup
      expect(reversal.commission_amount_cents).to eq(-3_000)  # 30% de R$100
    end
  end

  describe 'idempotency' do
    let(:key) { SecureRandom.uuid }

    it 'same key returns cached response (2xx)' do
      r1 = api_call(key)
      r2 = api_call(key)
      expect(r2.body).to eq(r1.body)
    end

    it 'caches 4xx responses' do
      r1 = api_call(key, invalid_payload)
      expect(r1.status).to eq(422)
      r2 = api_call(key, invalid_payload)
      expect(r2.status).to eq(422)
      expect(r2.body).to eq(r1.body)
    end

    it 'rejects key reuse with different fingerprint' do
      api_call(key, payload_a)
      r2 = api_call(key, payload_b)
      expect(r2.status).to eq(422)
      expect(r2.body).to include('idempotency_key_mismatch')
    end
  end

  describe 'period closure' do
    it 'blocks creation of entry in closed period' do
      Financial::Governance::ClosePeriod.call(account: account, year: 2026, month: 4, actor: admin)
      expect {
        Financial::Entry.create!(
          account_id: account.id,
          competence_date: Date.new(2026, 4, 15),
          # ...
        )
      }.to raise_error(Financial::Errors::PeriodClosed)
    end

    it 'reopen by ADMIN unlocks' do
      Financial::Governance::ClosePeriod.call(account: account, year: 2026, month: 4, actor: admin)
      Financial::Governance::ReopenPeriod.call(account: account, year: 2026, month: 4, actor: admin, reason: 'corrige erro contábil')
      expect {
        Financial::Entry.create!(account_id: account.id, competence_date: Date.new(2026, 4, 15), ...)
      }.not_to raise_error
    end
  end

  describe 'webhook security' do
    it 'rejects invalid HMAC with 401' do
      post '/webhooks/financial/asaas?account_id=1', headers: { 'Asaas-Access-Token' => 'wrong' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 (not 404) for missing account — constant time' do
      post '/webhooks/financial/asaas?account_id=99999'
      expect(response).to have_http_status(:forbidden)
    end

    it 'is idempotent on event_id replay' do
      payload = valid_asaas_payload
      post '/webhooks/financial/asaas?account_id=1', params: payload, headers: valid_hmac_headers
      expect { post '/webhooks/financial/asaas?account_id=1', params: payload, headers: valid_hmac_headers }
        .not_to change { Financial::PaymentReceipt.count }
    end
  end
end
```

### 15.2 Cobertura mínima por sprint

| Sprint | Cobertura mínima |
|---|---|
| 1 | 90% concerns, ApplicationRecord, migrations |
| 2 | 85% modelos config + setup wizard |
| 3 | 90% services principais + invariantes |
| 4 | 85% caixa, recurring, webhooks |
| 5 | 80% reports, governance |
| 6 | 70% frontend (lib + composables) |

---

## 16. Riscos e mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|
| Refactor introduz regressão em fluxo crítico | Média | Alto | Suite de invariantes + clínica piloto antes de rollout |
| Performance degrada com snapshot json em CommissionEntry | Baixa | Médio | Indexes adequados + monitoramento; jsonb tem boa performance |
| Setup wizard frustra onboarding | Média | Baixo | Wizard guiado com defaults sugeridos; pode pular passos opcionais |
| ActiveRecord Encryption falha em rollover de key | Baixa | Alto | Documentar processo de rotação; mantém pares ativos durante migração |
| Period closure trava operação legítima | Média | Médio | Reopen process formal com auditoria |
| Hierarquia 4 níveis confunde gestor | Média | Baixo | UI com expand/collapse + seed canon completo |
| Webhook Asaas retry causa duplicação | Baixa | Alto | Unique index `(account_id, event_id)` + Idempotency-Key no service |

---

## 17. Critérios de aceitação para go-live de 1ª clínica

- [ ] 100% dos itens P0 da auditoria resolvidos
- [ ] Cobertura de testes ≥ 80%
- [ ] Suite de invariantes 100% passando
- [ ] Tenant isolation testado em 100% dos endpoints
- [ ] HMAC Asaas verificado timing-safe via teste automatizado
- [ ] ActiveRecord Encryption configurado em produção (master key em env, sem fallback Base64)
- [ ] Setup wizard testado E2E com clínica real
- [ ] Reconciliação manual de saldo após 1 semana de operação (saldo sistema = extrato bancário)
- [ ] Webhook Asaas testado em sandbox (10 cenários: payment_received, refunded, overdue, retry, replay, invalid HMAC, etc)
- [ ] Backup/restore testado
- [ ] LGPD: anonymize testado, audit log auditado
- [ ] Documentação operacional para clínica (manual + vídeo)
- [ ] Monitoramento configurado (Sentry, métricas Sidekiq, alertas em jobs falhos)

---

## 18. Decisões em aberto (para discutir antes de Sprint 1)

### Resolvidas (2026-05-22)
- ~~**Profissionais — onde modelar?**~~ → User existente do Klivy core (gerenciado em `/api/v1/accounts/:id/agents`) **+** extensão `Financial::AgentProfile` 1-to-1 com User para campos canon (`tipo_vinculo`, `data_entrada`, `categoria_agente`, `comissionado`, dados bancários, CRO, especialidades). Sem AgentProfile = user não aparece em selects financeiros.
- ~~**Procedimentos — agenda ou financial?**~~ → **Ambos, separação por domínio.** Nome/duração/cor/profissionais vinculados ficam em `AgendaService` (plugin agenda); preço particular, preço convênio, DRE category, regra de comissão padrão, código TUSS ficam em `Financial::ServicePricing` 1-to-1. Campo `price` será **removido de `agenda_services`** na Sprint 2 (clean break). Sem `ServicePricing` = serviço não pode ser lançado financeiramente.

### Ainda em aberto
1. **Vínculo com prontuário** — quem cria PT (treatment plan) com efeito financeiro? Hoje frontend tem fluxo separado. Validar com PM antes de codar.
2. **Sub-categorias do DRE seed** — implementar nível 4 imediatamente ou só níveis 1-3 e nível 4 só em demanda?
3. **Conta `digital_wallet` para reter crédito de paciente** — criar automaticamente no setup ou via seed?
4. **Comissão paga (commission_entry.status = 'paid')** quando estorno acontece — devolver via Expense de "Adiantamento de comissão" manual ou gerar débito automático? **Recomendação**: manual com aviso explícito (operador decide).
5. **Webhooks adicionais** — Pagar.me, Mercado Pago? Manter adapter base genérico e adicionar quando demanda surgir.
6. **Caixa físico — múltiplos por dia ou um único?** Canon diz "Apenas 1 caixa aberto por dia". Validar se isso é por `BankAccount(kind=cash)` (permitindo múltiplos caixas em clínicas com 2 recepções) ou por `account_id`.

---

*Documento de implementação técnica — Klivy Financial v2 canon. Versão 1.0 · 2026-05-22. Próxima revisão após Sprint 1 (fim de junho/2026).*
