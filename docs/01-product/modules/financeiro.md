> [!CAUTION]
> **STATUS ATUAL (2026-05-11): Este documento é HISTÓRICO — a arquitetura V1 descrita aqui foi superada pela V2.**
>
> Tudo abaixo da linha `# Plano de Ação — Módulo Financeiro Central (BeClinic)` descreve o **plano V1 original** (março/abril 2026, ondas 1-4, tabela `account_transactions`). Mantemos por contexto histórico, mas **não é mais a fonte de verdade** do módulo.
>
> **Para a verdade atual do produto, consulte:**
>
> | O que você quer | Documento |
> |---|---|
> | **Como o financeiro funciona hoje** (regras de negócio canon) | [`docs/01-product/modules/financeiro-funcionamento.md`](./financeiro-funcionamento.md) |
> | **Plano de testes técnico** (QA Analyst) | [`docs/03-engineering/financial-v2-qa-test-plan.md`](../../03-engineering/financial-v2-qa-test-plan.md) |
> | **Teste visual** (recepção/dono da clínica) | [`docs/01-product/financial-v2-teste-visual.md`](../financial-v2-teste-visual.md) |
> | **Runbook de importação Clinicorp** (qualquer próxima migração) | [`docs/03-engineering/runbook-clinicorp-import.md`](../../03-engineering/runbook-clinicorp-import.md) |
>
> **Material histórico** (plano de implementação concluído, arquivado em maio/2026):
>
> | O que era | Onde foi parar |
> |---|---|
> | Cards de desenvolvimento (33 cards F-01 a F-33) | [`docs/03-engineering/archive/financial-v2-implementation/02-cards-desenvolvimento.md`](../../03-engineering/archive/financial-v2-implementation/02-cards-desenvolvimento.md) |
> | Auditoria dos 12 bugs do v1 (todos corrigidos) | [`docs/03-engineering/archive/financial-v2-implementation/03-auditoria.md`](../../03-engineering/archive/financial-v2-implementation/03-auditoria.md) |
> | Backlog técnico (~70 tickets — versão estendida dos cards) | [`docs/03-engineering/archive/financial-v2-implementation/04-backlog-tecnico.md`](../../03-engineering/archive/financial-v2-implementation/04-backlog-tecnico.md) |
>
> ---
>
> ## 📌 Sumário executivo (estado atual, maio/2026)
>
> **Namespace e arquitetura:**
> - Módulo em **V2** sob o namespace Ruby `Financial::*` e tabelas `financial_*` (não mais `account_transactions`).
> - Frontend em `plugins/financial/frontend/features/financial/v2/` (legacy `pages/` ainda no repo até Etapa 4 da deprecação).
> - Backend em `plugins/financial/app/` (Rails Engine).
>
> **Entrega:** 32 dos 33 cards do canon entregues (97%). F-11 (Painel de Importação ADMIN) marcado **OUT-OF-SCOPE** (decisão Mamedes, 2026-05-11) — importação permanece exclusivamente em `/super_admin/migrations`.
>
> **Telas em produção (todas v2):**
> 1. **Dashboard** — KPIs Hoje/Período + Vencimentos + Meta dinâmica (mensal/trimestral/anual) + 6 charts (Fluxo Diário, Composição, Aging, Receita por Profissional, Projeção 60d, Tendência Inadimplência) + sparklines SVG nos KPIs
> 2. **Fluxo de Caixa** — listagem unificada de entries com filtros (conta, período, tipo)
> 3. **A Receber** — parcelas pendentes/vencidas com KPIs
> 4. **A Pagar** — despesas pendentes/vencidas
> 5. **DRE** — em cascata Receita → Lucro Líquido com period selector (Semana/Mês/Trimestre/Ano/Todos)
> 6. **Comissões** — apuração por profissional, marcar como paga (gera Expense atômico + idempotente)
> 7. **Relatórios** — hub com 3 tabs (Despesas por Categoria, Convênio, Ticket Médio)
> 8. **Auditoria** — log global de todas as ações financeiras, com diff e filtros por entidade/ação/usuário/período
> 9. **Backups** — pg_dump diário (Sidekiq cron 3h AM) + mirror Cloudflare R2 + lista local/remoto
> 10. **Contador** — exportação CSV (4 arquivos, UTF-8 BOM + `;`, decimal com vírgula)
> 11. **LGPD** — workflow de anonimização irreversível (SHA256 truncado) preservando FK contábil
> 12. **Caixa físico** — sessão diária (abertura, sangria, suprimento, fechamento com conciliação cega)
> 13. **Reclassificar** — bulk update de categoria DRE em massa
> 14. **Configurações** — 5 tabs (Categorias, Contas e Caixa, Comissões, Despesas Recorrentes, Metas)
>
> **Importação Clinicorp F-10** entregue: aceita 3 CSVs (Budgets + PaymentHeader + PaymentItem) via Super Admin Migrations. Idempotente via `external_id` único. Heurística "single mapped dentist" atribui `professional_id` automaticamente em clínicas unipessoais. Conta Mamedes #31 importada com **1.987 parcelas + 1.617 entries + 32 budgets + ~414 buckets Avulsos**, R$ 378k consolidados.
>
> **Deprecação V1 (Etapa 1 ativa desde 2026-05-11):**
> - Sidebar removeu items "v2 ·" — labels unificados apontando pras rotas v2
> - Redirects 301 de `/financial/*` → `/financial/v2/*` (bookmarks antigos funcionam)
> - Sparklines migradas pro endpoint v2 (zero dependência v1 do v2)
> - Código legacy mantido no repo até **Etapa 4** (+30 dias após go-live real, então DELETE final dos arquivos `.vue` v1 + services v1 + DROP `account_transactions` com backup)
>
> **Stack visual:**
> - Charts: Chart.js + vue-chartjs (line, doughnut, h-bar) + SVG puro pros sparklines
> - Tooltips: `Intl.NumberFormat('pt-BR')` com separador de milhar (`R$ 1.234,56`)
> - Period selector reusable: Semana/Mês/Trimestre/Ano/Todos com brand blue `#1f93ff` no tab ativo
> - Confirmação destrutiva: `ConfirmDangerModal` (nunca `window.confirm` nativo)
> - PIX: ícone SVG oficial do Banco Central (não `i-lucide-qr-code`)
>
> ---
>
> **Nota arquitetural (mantida):** O texto histórico abaixo cita `account_transactions` (V1) como destino de migrations. Em V2, todas as estruturas estão 100% isoladas no plugin Rails Engine (`plugins/financial/`), com tabelas `financial_*` próprias. Leia [`02-architecture/system-architecture.md`](../../02-architecture/system-architecture.md) para ligações sistêmicas atuais.

# Plano de Ação — Módulo Financeiro Central (BeClinic) [HISTÓRICO V1]

---

## 📋 REGRAS DE EXECUÇÃO (LEIA SEMPRE ANTES DE COMEÇAR)

> Estas regras existem para garantir qualidade, rastreabilidade e consistência ao longo de toda a implementação. Devem ser seguidas **sem exceção** em cada sessão de trabalho.

### R1 — Marcar o progresso com ✅
- Toda tarefa concluída recebe um `✅` na frente
- Tarefas em progresso recebem `🔄`
- Tarefas bloqueadas (dependência não resolvida) recebem `⛔`
- **Nunca apagar** uma tarefa — apenas marcar

### R2 — Registro de entrega após cada etapa concluída
Ao finalizar qualquer bloco de trabalho (ex: uma migration, um controller, um componente Vue), adicionar uma entrada na seção **"📝 Log de Entregas"** no final deste arquivo, contendo:
1. **Data/hora** da conclusão
2. **Arquivos criados ou editados** (caminhos completos)
3. **Raciocínio**: por que foi feito dessa forma e não de outra
4. **Próximo passo imediato**: o que deve ser feito na próxima sessão

### R3 — Reler este plano no início de cada sessão
Antes de escrever qualquer linha de código, o assistente **deve**:
1. Ler as **Regras de Execução** (esta seção)
2. Verificar o **Log de Entregas** para entender onde parou
3. Identificar qual é o próximo item ✅ pendente na onda atual
4. Confirmar com o usuário antes de avançar para uma nova onda

### R4 — Nunca pular etapas de uma onda
As ondas têm dependências entre si. Não iniciar a Onda N+1 sem que **todos os itens da Onda N** estejam com ✅. Se o usuário pedir para pular, documentar a decisão no Log.

### R5 — Backend antes de frontend, sempre
Dentro de cada onda: migrations → models → policies → controllers → specs → frontend. Nunca construir um componente Vue sem o endpoint backend correspondente funcionando.

### R6 — Testar antes de avançar
Após cada controller criado, validar com um request direto (ou `curl`/`rails console`) que o endpoint retorna dados corretos antes de partir para o frontend.

### R7 — Commits atômicos por etapa
Cada bloco concluído (ex: "migrations da Onda 1" ou "sidebar + rotas") deve ter seu próprio commit com mensagem no padrão Conventional Commits:
```
feat(financial): create account_transactions and bank_accounts migrations
feat(financial): add FinancialDashboard route and sidebar entry
```

### R8 — Respeitar o spec.financeiro.md como fonte de verdade
Para qualquer decisão de cálculo (KPIs, DRE, fluxo de caixa), consultar **primeiro** o `spec.financeiro.md`. O plano de ação define arquitetura; o spec define regra de negócio. Em conflito, o spec ganha.

### R9 — CSS sempre modular
Todo CSS do módulo financeiro vai em `features/financial/financial.css`. Proibido:
- CSS inline (`:style=""`)
- CSS scoped no componente
- Classes Tailwind ad-hoc que não façam parte do padrão do projeto

### R10 — Sem código defensivo desnecessário
MVP first. Implementar o happy path. Não adicionar fallbacks, retry logic, ou edge cases que a produção ainda não provou necessários.

---

> **Decisões confirmadas pelo dono do produto:**
> 1. Entrega dividida em **ondas**
> 2. **Tabela separada** `account_transactions` para despesas sem paciente
> 3. Multi-tenant: 1 account = 1 clínica (filtro `account_id` resolve tudo)
> 4. Financeiro na sidebar entre **Contatos** e **Relatórios**
> 5. Configurações financeiras **dentro do próprio módulo**
> 6. Gráficos usando **chart.js + vue-chartjs** (já instalados no projeto)

---

## Visão Geral das Ondas

```mermaid
gantt
    title Módulo Financeiro — Ondas de Entrega
    dateFormat  YYYY-MM-DD
    axgriis off

    section Onda 1 — Fundação
    Backend (migrations + models + API)        :o1a, 2026-03-25, 2d
    Frontend (rotas + sidebar + dashboard)     :o1b, after o1a, 3d

    section Onda 2 — Fluxo de Caixa + Relatórios
    Fluxo de Caixa (gráfico + painel)          :o2a, after o1b, 2d
    Relatórios (Fatur. Prof/Proc + Inadimpl.)  :o2b, after o2a, 2d

    section Onda 3 — DRE + Caixa
    DRE Simplificado                           :o3a, after o2b, 2d
    Caixa por Operador                         :o3b, after o3a, 2d

    section Onda 4 — Avançado
    Comissões + Repasse                        :o4a, after o3b, 2d
    Conciliação + Projeção 30/60/90            :o4b, after o4a, 2d
```

---

## ONDA 1 — Fundação (Backend + Dashboard + Sidebar)

### 1A. Backend — Migrations & Models

#### Migration: `create_financial_categories`

```ruby
create_table :financial_categories do |t|
  t.bigint  :account_id,     null: false
  t.string  :name,           null: false
  t.string  :category_type,  null: false  # 'income' / 'expense'
  t.string  :cost_type                     # 'fixo' / 'variavel' (para DRE)
  t.bigint  :parent_id                     # subcategoria
  t.string  :color,          default: '#64748b'
  t.string  :icon,           default: 'i-lucide-tag'
  t.boolean :is_default,     default: false
  t.integer :position,       default: 0
  t.timestamps
end
```

#### Migration: `create_bank_accounts`

```ruby
create_table :bank_accounts do |t|
  t.bigint  :account_id,       null: false
  t.string  :name,             null: false          # "Caixa", "Bradesco PJ"
  t.string  :bank_name                              # "Bradesco", "Itaú"
  t.string  :bank_code                              # "237"
  t.string  :account_type,     default: 'checking'  # checking / savings / cash
  t.decimal :initial_balance,  precision: 12, scale: 2, default: 0.0
  t.boolean :active,           default: true
  t.timestamps
end
```

#### Migration: `create_account_transactions`

> Tabela de transações a nível de account (despesas gerais SEM paciente obrigatório).

```ruby
create_table :account_transactions do |t|
  t.bigint  :account_id,            null: false
  t.bigint  :patient_id                               # opcional (quando vinculado)
  t.bigint  :financial_category_id                     # categoria da despesa/receita
  t.bigint  :bank_account_id                           # conta bancária destino/origem
  t.bigint  :registered_by_id                          # user que registrou
  t.bigint  :professional_id                           # profissional vinculado (faturamento)
  t.bigint  :source_transaction_id                     # link para Transaction do paciente (idempotência)
  t.bigint  :recurring_expense_id                      # link para RecurringExpense que gerou este lançamento
  t.bigint  :estorno_de_id                             # FK → account_transactions (estorno vinculado)

  t.string  :entry_type,            null: false        # 'entrada' / 'saida'
  t.decimal :amount,                precision: 12, scale: 2, null: false
  t.decimal :original_amount,       precision: 12, scale: 2  # valor antes desconto (DRE)
  t.decimal :discount_amount,       precision: 12, scale: 2, default: 0.0
  t.string  :payment_method                            # pix/cartao_credito/etc
  t.string  :status,                null: false, default: 'pendente'
  # pendente / recebido / pago / cancelado / parcial

  # OS 5 CAMPOS DE DATA (spec.financeiro.md seção Regras Gerais)
  t.date    :competence_date                           # data_competencia (DRE — regime competência)
  t.date    :due_date                                  # data_vencimento
  t.date    :received_at                               # data_recebimento (receitas — regime caixa)
  t.date    :paid_at                                   # data_pagamento (despesas — regime caixa)
  # created_at = data_criacao (Rails default)

  t.text    :description
  t.text    :notes
  t.string  :origin                                    # 'manual' / 'orcamento' / 'procedimento' / 'recorrente'
  # NOTA: is_recurring e recurrence_rule foram REMOVIDOS.
  # A recorrência é modelada pela tabela `recurring_expenses` (template).
  # Transações geradas automaticamente têm origin='recorrente' + recurring_expense_id preenchido.

  t.jsonb   :metadata,             default: {}
  t.datetime :deleted_at
  t.timestamps
end

add_index :account_transactions, :account_id
add_index :account_transactions, :patient_id
add_index :account_transactions, :financial_category_id
add_index :account_transactions, :bank_account_id
add_index :account_transactions, :recurring_expense_id
add_index :account_transactions, :source_transaction_id, unique: true  # idempotência
add_index :account_transactions, :status
add_index :account_transactions, :due_date
add_index :account_transactions, :competence_date
add_index :account_transactions, :entry_type
add_index :account_transactions, :deleted_at
add_index :account_transactions, [:account_id, :entry_type, :status]
add_index :account_transactions, [:account_id, :competence_date]       # DRE queries
```

#### Seed de categorias padrão

```ruby
DEFAULTS = [
  # Receitas
  { name: 'Consultas', type: 'income', cost_type: nil, icon: 'i-lucide-stethoscope', color: '#22c55e' },
  { name: 'Procedimentos', type: 'income', cost_type: nil, icon: 'i-lucide-syringe', color: '#3b82f6' },
  { name: 'Convênios', type: 'income', cost_type: nil, icon: 'i-lucide-building', color: '#8b5cf6' },
  { name: 'Outros Recebimentos', type: 'income', cost_type: nil, icon: 'i-lucide-plus', color: '#64748b' },
  # Despesas Fixas
  { name: 'Aluguel', type: 'expense', cost_type: 'fixo', icon: 'i-lucide-home', color: '#ef4444' },
  { name: 'Salários', type: 'expense', cost_type: 'fixo', icon: 'i-lucide-users', color: '#f97316' },
  { name: 'Energia/Água', type: 'expense', cost_type: 'fixo', icon: 'i-lucide-zap', color: '#eab308' },
  { name: 'Software/SaaS', type: 'expense', cost_type: 'fixo', icon: 'i-lucide-monitor', color: '#06b6d4' },
  { name: 'Manutenção', type: 'expense', cost_type: 'fixo', icon: 'i-lucide-wrench', color: '#a855f7' },
  # Despesas Variáveis
  { name: 'Materiais', type: 'expense', cost_type: 'variavel', icon: 'i-lucide-package', color: '#ec4899' },
  { name: 'Laboratório', type: 'expense', cost_type: 'variavel', icon: 'i-lucide-flask-conical', color: '#14b8a6' },
  { name: 'Repasse Profissionais', type: 'expense', cost_type: 'variavel', icon: 'i-lucide-user-check', color: '#f59e0b' },
  { name: 'Comissões', type: 'expense', cost_type: 'variavel', icon: 'i-lucide-percent', color: '#10b981' },
  # Categorias Financeiras
  { name: 'Juros Recebidos', type: 'income', cost_type: nil, icon: 'i-lucide-trending-up', color: '#22d3ee' },
  { name: 'Multas Recebidas', type: 'income', cost_type: nil, icon: 'i-lucide-alert-triangle', color: '#fbbf24' },
  { name: 'Taxas Bancárias', type: 'expense', cost_type: nil, icon: 'i-lucide-landmark', color: '#6b7280' },
  { name: 'Taxas de Cartão', type: 'expense', cost_type: nil, icon: 'i-lucide-credit-card', color: '#9ca3af' },
]
```

#### Migration: `create_commission_rules`

> Modela **como** a comissão de cada profissional é calculada. Sem isso, o relatório de comissões seria apenas texto, não cálculo.

```ruby
create_table :commission_rules do |t|
  t.bigint  :account_id,          null: false
  t.bigint  :professional_id,     null: false   # user (profissional)
  t.string  :commission_type,     null: false   # 'percentage_production' / 'percentage_received' / 'fixed_value'
  t.decimal :value,               precision: 10, scale: 2, null: false  # % ou R$
  t.bigint  :financial_category_id               # se aplica só a uma categoria (ex: "Procedimentos")
  t.string  :procedure_name                      # se aplica a um procedimento específico (ex: "Clareamento")
  t.string  :specialty                           # se aplica a uma especialidade (ex: "Ortodontia")
  t.date    :valid_from                          # início da vigência
  t.date    :valid_until                         # fim da vigência (null = sempre vigente)
  t.boolean :active,              default: true
  t.text    :notes
  t.timestamps
end

add_index :commission_rules, :account_id
add_index :commission_rules, :professional_id
add_index :commission_rules, [:account_id, :professional_id]
add_index :commission_rules, :active
```

**Tipos de comissão suportados:**

| `commission_type` | Fórmula | Exemplo |
|---|---|---|
| `percentage_production` | % sobre o valor **produzido** (faturado) | 30% sobre o subtotal do orçamento do profissional |
| `percentage_received` | % sobre o valor **efetivamente recebido** | 25% sobre pagamentos confirmados (pago) |
| `fixed_value` | Valor fixo por atendimento/procedimento | R$ 150 por consulta realizada |

**Regras de prioridade:** procedimento > categoria > geral. Se existem múltiplas regras para o mesmo profissional, a mais específica ganha.

#### Migration: `create_recurring_expenses`

> Despesas recorrentes com geração automática. Resolve o gap do regime de competência onde aluguel de março é competência março mesmo sendo pago em abril.

```ruby
create_table :recurring_expenses do |t|
  t.bigint  :account_id,           null: false
  t.bigint  :financial_category_id               # categoria ("Aluguel", "Salários")
  t.bigint  :bank_account_id                     # conta de débito
  t.bigint  :registered_by_id                    # quem cadastrou

  t.string  :description,          null: false   # "Aluguel — Sala 201"
  t.decimal :amount,               precision: 12, scale: 2, null: false
  t.string  :payment_method                      # pix/boleto/transferencia etc

  t.string  :frequency,            null: false   # 'monthly' / 'weekly' / 'biweekly' / 'quarterly' / 'yearly'
  t.integer :due_day,              default: 1    # dia do vencimento (1-31)
  t.integer :competence_offset_days, default: 0  # offset em dias: competence_date = due_date - offset
  # Ex: aluguel vence dia 10, competência é mês anterior → offset = 10 (ou usar mês anterior)
  t.string  :competence_rule,      default: 'same_month'  # 'same_month' / 'previous_month'
  # same_month: competência = mês do vencimento
  # previous_month: competência = mês anterior ao vencimento (ex: aluguel março pago em abril)

  t.date    :start_date,           null: false   # quando começa a gerar
  t.date    :end_date                            # quando para (null = indefinido)
  t.date    :last_generated_at                   # última data que gerou account_transaction

  t.boolean :active,               default: true
  t.boolean :auto_confirm,         default: false  # se true, gera já com status 'pago'
  t.text    :notes
  t.timestamps
end

add_index :recurring_expenses, :account_id
add_index :recurring_expenses, :financial_category_id
add_index :recurring_expenses, :active
add_index :recurring_expenses, :frequency
```

**Como funciona a geração automática:**

1. Um **job diário** (`Financial::GenerateRecurringExpensesJob`) roda à meia-noite
2. Para cada `recurring_expense` ativa onde `last_generated_at` é anterior ao próximo vencimento:
   - Cria um `AccountTransaction` com:
     - `entry_type: 'saida'`
     - `due_date`: calculada pela frequência + due_day
     - `competence_date`: calculada pela `competence_rule`
     - `status: 'pendente'` (ou `'pago'` se `auto_confirm`)
     - `origin: 'recorrente'`
   - Atualiza `last_generated_at`
3. O dono da clínica vê as despesas geradas em "A Pagar" e confirma o pagamento manualmente (ou automaticamente)

**Exemplo prático:**
```
Aluguel: R$ 5.000 | frequency: monthly | due_day: 10 | competence_rule: previous_month

Abril/2026:
→ Gera AccountTransaction:
  - due_date: 2026-04-10
  - competence_date: 2026-03-01 (previous_month)
  - amount: 5000
  - status: pendente
  - description: "Aluguel — Sala 201 (competência Mar/2026)"
```

#### Models (Rails)

| Model | Arquivo | Notas |
|-------|---------|-------|
| `FinancialCategory` | `app/models/financial_category.rb` | `belongs_to :account`, `has_many :children`, tree structure |
| `BankAccount` | `app/models/bank_account.rb` | `belongs_to :account`, `has_many :account_transactions` |
| `AccountTransaction` | `app/models/account_transaction.rb` | A tabela "mãe" do financeiro central. `belongs_to :account`, `optional: patient, category, bank_account` |
| `CommissionRule` | `app/models/commission_rule.rb` | `belongs_to :account`, `belongs_to :professional (User)`, regras de cálculo de comissão |
| `RecurringExpense` | `app/models/recurring_expense.rb` | `belongs_to :account`, template de despesa recorrente, gera `AccountTransaction` via job |

#### Controllers (Rails)

| Controller | Rota | Propósito |
|-----------|------|-----------|
| `FinancialDashboardController` | `GET /api/v1/accounts/:id/financial/dashboard` | KPIs + dados do dashboard |
| `AccountTransactionsController` | CRUD `/api/v1/accounts/:id/financial/transactions` | Transações centrais (entradas/saídas) |
| `FinancialCategoriesController` | CRUD `/api/v1/accounts/:id/financial/categories` | Categorias |
| `BankAccountsController` | CRUD `/api/v1/accounts/:id/financial/bank_accounts` | Contas bancárias |
| `FinancialReportsController` | `GET /api/v1/accounts/:id/financial/reports/:type` | Relatórios dinâmicos |

#### Integração: Paciente → Financeiro Central (CRÍTICA)

> ⚠️ **Este é o ponto de integração mais delicado do sistema.** Se falhar ou criar duplicata, quebra tanto o fluxo do paciente quanto o financeiro central.

**O que muda no `InstallmentPayService`:**

Hoje o service já usa `ActiveRecord::Base.transaction` para criar `CashEntry` + atualizar `Transaction`. Vamos **adicionar** a criação da `AccountTransaction` **dentro do mesmo bloco transacional**:

```ruby
# Dentro de InstallmentPayService#call, no bloco ActiveRecord::Base.transaction:

# 1. CashEntry (já existe)
cash_entry = create_cash_entry

# 2. Transaction → pago (já existe)
@transaction.update!(status: 'pago', paid_at: @paid_at, ...)

# 3. NOVO: AccountTransaction para o financeiro central
create_account_transaction(cash_entry)
```

**Guard de idempotência:** O índice `unique: true` em `source_transaction_id` garante que **nunca** haverá duplicata. Se o service rodar duas vezes para a mesma Transaction, o segundo `create!` falha com `ActiveRecord::RecordNotUnique` e o `rescue` reverte tudo.

```ruby
def create_account_transaction(cash_entry)
  # Guard: se já existe, não cria (idempotência)
  return if AccountTransaction.exists?(source_transaction_id: @transaction.id)

  AccountTransaction.create!(
    account_id: @transaction.account_id,
    patient_id: @transaction.patient_id,
    source_transaction_id: @transaction.id,
    entry_type: 'entrada',
    amount: @transaction.amount,
    payment_method: @payment_method,
    status: 'recebido',
    received_at: @paid_at,
    due_date: @transaction.due_date,
    competence_date: resolve_competence_date,  # ← regra abaixo
    description: @transaction.description,
    origin: 'orcamento',
    registered_by_id: @actor.id,
    professional_id: resolve_professional_id
  )
end
```

**Specs obrigatórios para esta integração:**
- ✅ Pagamento cria CashEntry + AccountTransaction atomicamente
- ✅ Se AccountTransaction falha, CashEntry e Transaction revertem
- ✅ Pagamento duplicado não cria AccountTransaction duplicada
- ✅ `competence_date` é populada corretamente

---

#### Regra Canônica de `competence_date` (DECISÃO DE ARQUITETURA)

> **Sem esta regra documentada, cada desenvolvedor popula diferente e o DRE fica inconsistente.**

| Tipo de transação | `competence_date` | Justificativa |
|---|---|---|
| **Receita de paciente** (via InstallmentPayService) | Data do **atendimento/procedimento** que gerou a receita. Se não houver evento na agenda vinculado → fallback para `due_date` da Transaction original | O fato gerador da receita é o procedimento realizado, não o pagamento |
| **Despesa manual** (cadastrada pelo usuário) | Default = **1º dia do mês do `due_date`**. Editável pelo usuário no formulário | Permite que o usuário ajuste se necessário |
| **Despesa recorrente** (gerada pelo job) | Calculada pela `competence_rule` da RecurringExpense (`same_month` ou `previous_month`) | Aluguel mar/26 pago em abr/26 → competência = mar/26 |
| **Estorno** | Mesma `competence_date` da transação original sendo estornada | Estorno reverte o lançamento no mesmo período contábil |

**Implementação do `resolve_competence_date`:**

```ruby
def resolve_competence_date
  # 1. Tenta encontrar o evento da agenda vinculado ao paciente + data mais próxima
  agenda_event = find_related_agenda_event
  return agenda_event.start_date.to_date if agenda_event

  # 2. Fallback: due_date da transação original
  @transaction.due_date || @paid_at
end

def find_related_agenda_event
  return nil unless @transaction.patient_id

  # Busca evento da agenda do paciente com data mais próxima da due_date
  AgendaEvent.where(
    patient_id: @transaction.patient_id,
    status: 'completed'
  ).where('start_date <= ?', @transaction.due_date || Date.today)
   .order(start_date: :desc)
   .first
end
```

---

### 1B. Frontend — Rotas, Sidebar e Dashboard

#### Estrutura de arquivos

```
app/javascript/dashboard/
├── features/financial/
│   ├── api/
│   │   ├── dashboard.js              # GET /financial/dashboard
│   │   ├── accountTransactions.js    # CRUD /financial/transactions
│   │   ├── categories.js            # CRUD /financial/categories
│   │   ├── bankAccounts.js          # CRUD /financial/bank_accounts
│   │   └── reports.js               # GET /financial/reports/:type
│   ├── store/
│   │   └── financialStore.js         # Pinia ou Vuex module
│   ├── composables/
│   │   ├── useFinancialFilters.js    # Período, clínica
│   │   └── useFormatCurrency.js      # R$ formatting (extraído do FinancialTab)
│   ├── components/
│   │   ├── FinancialKpiCard.vue      # Card de KPI reutilizável
│   │   ├── FinancialKpiHeader.vue    # 4 KPIs do cabeçalho global
│   │   ├── ReceivablesBlock.vue      # Bloco A Receber
│   │   ├── PayablesBlock.vue         # Bloco A Pagar
│   │   ├── DelinquencyCard.vue       # Card de Inadimplência
│   │   ├── BankAccountsCard.vue      # Contas Financeiras
│   │   ├── MiniCashFlowChart.vue     # Gráfico últimos 7 dias
│   │   ├── MonthlySalesChart.vue     # Gráfico vendas mensal
│   │   ├── PeriodSelector.vue        # Seletor de período (hoje/semana/mês/custom)
│   │   └── TransactionModal.vue      # Modal criar/editar transação
│   ├── pages/
│   │   ├── FinancialDashboard.vue    # /financeiro — Dashboard principal
│   │   ├── CashFlow.vue             # /financeiro/fluxo-de-caixa
│   │   ├── Receivables.vue          # /financeiro/a-receber
│   │   ├── Payables.vue             # /financeiro/a-pagar
│   │   ├── DRE.vue                  # /financeiro/dre
│   │   ├── Reports.vue             # /financeiro/relatorios
│   │   ├── CashRegister.vue         # /financeiro/caixa
│   │   └── FinancialSettings.vue    # /financeiro/configuracoes
│   ├── financial.css                 # CSS modular (seguindo KI)
│   └── routes.js                     # Definição de rotas
```

#### Rotas

```javascript
// features/financial/routes.js
export const routes = [
  {
    path: frontendURL('accounts/:accountId/financial'),
    name: 'financial_dashboard_index',
    component: FinancialDashboard,
    meta: { permissions: [...ROLES], rbac: { module: 'financial', action: 'view_transactions' } },
  },
  {
    path: frontendURL('accounts/:accountId/financial/cash-flow'),
    name: 'financial_cash_flow',
    component: CashFlow,
  },
  {
    path: frontendURL('accounts/:accountId/financial/receivables'),
    name: 'financial_receivables',
    component: Receivables,
  },
  {
    path: frontendURL('accounts/:accountId/financial/payables'),
    name: 'financial_payables',
    component: Payables,
  },
  {
    path: frontendURL('accounts/:accountId/financial/dre'),
    name: 'financial_dre',
    component: DRE,
  },
  {
    path: frontendURL('accounts/:accountId/financial/reports'),
    name: 'financial_reports',
    component: Reports,
  },
  {
    path: frontendURL('accounts/:accountId/financial/cash-register'),
    name: 'financial_cash_register',
    component: CashRegister,
  },
  {
    path: frontendURL('accounts/:accountId/financial/settings'),
    name: 'financial_settings',
    component: FinancialSettings,
  },
];
```

#### Sidebar entry

```javascript
// Em Sidebar.vue, entre Contacts e Reports:
{
  name: 'Financial',
  icon: 'i-lucide-wallet',
  label: t('SIDEBAR.FINANCIAL', 'Financeiro'),
  children: [
    { name: 'Financial Dashboard', label: 'Dashboard', to: accountScopedRoute('financial_dashboard_index') },
    { name: 'Cash Flow', label: 'Fluxo de Caixa', to: accountScopedRoute('financial_cash_flow') },
    { name: 'Receivables', label: 'A Receber', to: accountScopedRoute('financial_receivables') },
    { name: 'Payables', label: 'A Pagar', to: accountScopedRoute('financial_payables') },
    { name: 'DRE', label: 'DRE', to: accountScopedRoute('financial_dre') },
    { name: 'Reports', label: 'Relatórios', to: accountScopedRoute('financial_reports') },
    { name: 'Cash Register', label: 'Caixa', to: accountScopedRoute('financial_cash_register') },
    { name: 'Financial Settings', label: 'Configurações', to: accountScopedRoute('financial_settings') },
  ],
},
```

#### Dashboard — Layout

```
┌──────────────────────────────────────────────────────────────────────┐
│ [PeriodSelector: Hoje | Semana | Mês | Custom]     [Filtro Clínica] │
├─────────────┬──────────────┬──────────────┬──────────────────────────┤
│ Receita     │ Saídas       │ Novas        │ Lucro Líquido            │
│ Líquida     │ R$ 12.500    │ Entradas     │ R$ 23.700                │
│ R$ 45.200   │ ↑ 3.2% 🔴   │ R$ 52.000    │ ↑ 15.8% 🟢              │
│ ↑ 8.3% 🟢  │              │ ↑ 12.1% 🟢  │ Card VERDE               │
├─────────────┴──────────────┴──────────────┴──────────────────────────┤
│                                                                      │
│  ┌─ A Receber ──────────┐  ┌─ A Pagar ──────────────┐               │
│  │ Vencidos:   R$ 3.200 │  │ Vencidas:   R$ 1.500   │               │
│  │ Não venc:   R$ 8.400 │  │ Não venc:   R$ 5.200   │               │
│  │ Vencem hoje: R$ 800  │  │ Vencem hoje: R$ 500    │               │
│  │ [████████░░░] 72%    │  │ [██████░░░░] 55%       │               │
│  └──────────────────────┘  └─────────────────────────┘               │
│                                                                      │
│  ┌─ Inadimplência ──────┐  ┌─ Contas Bancárias ─────┐               │
│  │ R$ 3.200 (4 pac.)    │  │ Caixa: R$ 2.300        │               │
│  │ [Ver inadimplentes]  │  │ Bradesco: R$ 15.400    │               │
│  └──────────────────────┘  │ Itaú: R$ 8.700         │               │
│                            └─────────────────────────┘               │
│  ┌─ Fluxo de Caixa (7 dias) ────────────────────────┐               │
│  │ [gráfico barras verde/vermelho + linha saldo]     │               │
│  └───────────────────────────────────────────────────┘               │
│  ┌─ Faturamento Mensal (6 meses) ────────────────────┐               │
│  │ [gráfico barras azuis]                            │               │
│  └───────────────────────────────────────────────────┘               │
└──────────────────────────────────────────────────────────────────────┘
```

### Arquivos modificados na Onda 1

| Ação | Arquivo |
|------|---------|
| ✅ **Criar** | `db/migrate/20260324120001_create_financial_categories.rb` |
| ✅ **Criar** | `db/migrate/20260324120002_create_bank_accounts.rb` |
| ✅ **Criar** | `db/migrate/20260324120003_create_account_transactions.rb` |
| ✅ **Criar** | `db/migrate/20260324120004_create_commission_rules.rb` |
| ✅ **Criar** | `db/migrate/20260324120005_create_recurring_expenses.rb` |
| ✅ **Criar** | `app/models/financial_category.rb` |
| ✅ **Criar** | `app/models/bank_account.rb` |
| ✅ **Criar** | `app/models/account_transaction.rb` |
| ✅ **Criar** | `app/models/commission_rule.rb` |
| ✅ **Criar** | `app/models/recurring_expense.rb` |
| **Criar** | `app/controllers/api/v1/accounts/financial_dashboard_controller.rb` |
| **Criar** | `app/controllers/api/v1/accounts/account_transactions_controller.rb` |
| **Criar** | `app/controllers/api/v1/accounts/financial_categories_controller.rb` |
| **Criar** | `app/controllers/api/v1/accounts/bank_accounts_controller.rb` |
| **Criar** | `app/policies/account_transaction_policy.rb` |
| **Criar** | `app/policies/financial_category_policy.rb` |
| **Criar** | `app/policies/bank_account_policy.rb` |
| **Criar** | `app/policies/commission_rule_policy.rb` |
| **Criar** | `app/policies/recurring_expense_policy.rb` |
| **Criar** | `app/jobs/financial/generate_recurring_expenses_job.rb` |
| **Editar** | `config/routes.rb` — namespace `financial` |
| **Criar** | `app/javascript/dashboard/features/financial/` (todo o diretório) |
| **Editar** | `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` — importar financialRoutes |
| **Editar** | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` — adicionar entry |
| **Editar** | `app/javascript/dashboard/i18n/locale/en/sidebar.json` — chaves FINANCIAL |
| **Editar** | `app/javascript/dashboard/i18n/locale/pt_BR/sidebar.json` — chaves FINANCIAL |
| **Editar** | `app/services/patients/installment_pay_service.rb` — criar AccountTransaction na baixa |

---

## ONDA 2 — Fluxo de Caixa + Relatórios

### 2A. Fluxo de Caixa (gráfico principal)

**Backend:** Endpoint `GET /financial/cash_flow?start_date=&end_date=`
- Retorna array de dias, cada um com: `entradas_efetivas`, `saidas_efetivas`, `a_receber`, `a_pagar`, `saldo_diario`, `saldo_acumulado`
- Painel lateral: totais do mês, saldo previsto

**Frontend:** `CashFlow.vue`
- Gráfico combinado (barras + linhas) usando `vue-chartjs`
- Cards de forma de pagamento (PIX, Cartão, Dinheiro, etc.)
- Painel lateral com resumo do mês

| Ação | Arquivo |
|------|---------|
| **Criar** | `app/controllers/api/v1/accounts/financial_cash_flow_controller.rb` |
| **Criar** | `app/services/financial/cash_flow_calculator.rb` |
| **Criar** | `features/financial/pages/CashFlow.vue` |
| **Criar** | `features/financial/components/CashFlowChart.vue` |
| **Criar** | `features/financial/components/CashFlowSidebar.vue` |
| **Criar** | `features/financial/components/PaymentMethodCards.vue` |

### 2B. Relatórios (Faturamento + Inadimplência + Despesas)

**Backend:** `GET /financial/reports/:type`
- `type=revenue_by_professional` → join com `users` (profissional do evento/transação)
- `type=revenue_by_procedure` → join com procedimentos do prontuário
- `type=delinquency` → aging da dívida por paciente (faixas 1-30, 31-60, 61-90, 90+)
- `type=expenses_by_category` → join com `financial_categories`

**Frontend:** `Reports.vue` com tabs internas para cada relatório

| Ação | Arquivo |
|------|---------|
| **Criar** | `app/controllers/api/v1/accounts/financial_reports_controller.rb` |
| **Criar** | `app/services/financial/report_builder.rb` |
| **Criar** | `features/financial/pages/Reports.vue` |
| **Criar** | `features/financial/components/reports/RevenueByProfessional.vue` |
| **Criar** | `features/financial/components/reports/RevenueByProcedure.vue` |
| **Criar** | `features/financial/components/reports/DelinquencyReport.vue` |
| **Criar** | `features/financial/components/reports/ExpensesByCategory.vue` |

---

## ONDA 3 — DRE + Caixa por Operador

### 3A. DRE Simplificado

**Backend:** `GET /financial/dre?period=month&date=2026-03`
- Calcula cada linha do DRE por competência
- Retorna comparação com período anterior

**Frontend:** `DRE.vue`
- Tabela com linhas hierárquicas (receita bruta → descontos → receita líquida → etc)
- Coluna de margem %
- Toggle comparação: mês anterior vs mesmo mês ano anterior

| Ação | Arquivo |
|------|---------|
| **Criar** | `app/services/financial/dre_calculator.rb` |
| **Criar** | `features/financial/pages/DRE.vue` |
| **Criar** | `features/financial/components/DreTable.vue` |

### 3B. Caixa por Operador

**Backend:** `GET /financial/cash_register?date=2026-03-24&operator_id=X`
- Abertura, entradas, saídas, sangrias, suprimentos, fechamento
- Cálculo de quebra

**Frontend:** `CashRegister.vue`
- Seletor de operador + data
- Cards por forma de pagamento
- Botões: Abrir Caixa, Sangria, Suprimento, Fechar Caixa

| Ação | Arquivo |
|------|---------|
| **Criar** | `db/migrate/XXXX_create_cash_registers.rb` |
| **Criar** | `app/models/cash_register.rb` |
| **Criar** | `app/controllers/api/v1/accounts/cash_registers_controller.rb` |
| **Criar** | `features/financial/pages/CashRegister.vue` |
| **Criar** | `features/financial/components/CashRegisterPanel.vue` |

---

## ONDA 4 — Funcionalidades Avançadas

### 4A. Comissões + Repasse a Profissionais

As tabelas `commission_rules` e o model `CommissionRule` já existem desde a Onda 1.
Nesta onda o foco é o **cálculo e os relatórios**.

**Como o cálculo funciona:**

1. O `CommissionCalculator` recebe um profissional + período
2. Busca todas as `AccountTransaction` onde `professional_id` = profissional no período
3. Para cada transação, encontra a `CommissionRule` mais específica aplicável (procedimento > categoria > geral)
4. Aplica a fórmula conforme o `commission_type`:
   - `percentage_production` → `valor_orcamento * rule.value / 100`
   - `percentage_received` → `valor_pago * rule.value / 100`
   - `fixed_value` → `rule.value` por atendimento
5. Gera o relatório detalhado e o total de repasse

| Ação | Arquivo |
|------|---------|
| **Criar** | `app/services/financial/commission_calculator.rb` |
| **Criar** | `app/services/financial/professional_payout_calculator.rb` |
| **Criar** | `app/controllers/api/v1/accounts/financial/commission_rules_controller.rb` (CRUD) |
| **Criar** | Componentes: `CommissionsReport.vue`, `PayoutReport.vue`, `CommissionRulesSettings.vue` |

### 4B. Conciliação de Cartões + Projeção 30/60/90

| Ação | Arquivo |
|------|---------|
| **Criar** | `app/services/financial/card_reconciliation_service.rb` |
| **Criar** | `app/services/financial/cash_flow_projection_service.rb` |
| **Criar** | Componentes: `CardReconciliation.vue`, `CashFlowProjection.vue` |

### 4C. Faturamento por Convênio + Ticket Médio

| Ação | Arquivo |
|------|---------|
| **Criar** | Componentes: `RevenueByInsurance.vue`, `AverageTicket.vue` |

---

## Configurações Financeiras (dentro do módulo)

A página `FinancialSettings.vue` terá tabs:

| Tab | Conteúdo |
|-----|----------|
| **Categorias** | CRUD de categorias de receita/despesa com árvore pai→filho, cores, ícones |
| **Contas Bancárias** | CRUD de contas com nome, banco, saldo inicial |
| **Formas de Pagamento** | Ativar/desativar métodos, configurar taxas de cartão |
| **Comissões** | CRUD de `commission_rules`: profissional, tipo (% produção / % recebido / fixo), procedimento, vigência |
| **Despesas Recorrentes** | CRUD de `recurring_expenses`: descrição, valor, frequência, dia de vencimento, regra de competência |
| **Repasse** | Regras de repasse por profissional (%, fixo, híbrido) |
| **Geral** | Regime padrão, meta mensal, alertas |

---

## 12 Ideias Complementares

### Quick Wins (fácil + alto impacto)
1. **Badge na sidebar** — Número de parcelas vencidas (tipo unreads do chat)
2. **Alerta de vencimento** — Toast no dashboard geral: "3 parcelas venceram hoje"
3. **Widget "Caixa do Dia"** — Mini-card no dashboard principal com entradas/saídas do dia
4. **Botão "Receber" global** — Na lista de pacientes, atalho para modal de pagamento

### Integrações cross-módulo
5. **Agenda → Popup de pagamento** — Ao marcar atendimento como "realizado", oferecer: "Registrar pagamento agora?"
6. **Timeline financeira** — No financeiro central, timeline unificada de todas movimentações
7. **WhatsApp + Inadimplência** — Botão de cobrança em lote na lista de inadimplentes
8. **Banner de inadimplência no prontuário** — Se o paciente tem parcelas vencidas, banner amarelo/vermelho no topo do prontuário

### Funcionalidades diferenciadas
9. **Meta mensal** — Gauge visual com progresso de faturamento vs meta configurada
10. **Alertas inteligentes** — "Saldo projetado fica negativo dia 25" ou "Faturamento 20% abaixo do mês passado"
11. **Exportação PDF/Excel** — Todos os relatórios com PDF branded (logo da clínica) + CSV
12. **Comparativo de períodos** — Toggle: março vs fevereiro OU março/2026 vs março/2025

---

## Resumo de Arquivos por Onda

| Onda | Arquivos novos | Arquivos editados | Estimativa |
|------|---------------|-------------------|-----------|
| **1 — Fundação** | ~30 | ~5 | 5-6 dias |
| **2 — Fluxo + Relatórios** | ~12 | ~2 | 3-4 dias |
| **3 — DRE + Caixa** | ~8 | ~1 | 3-4 dias |
| **4 — Avançado** | ~12 | ~2 | 4-5 dias |
| **Total** | **~62** | **~10** | **15-19 dias** |

---

## 📝 Log de Entregas

> Atualizado ao final de cada sessão de trabalho. Se estiver vazio, nenhuma onda foi iniciada ainda.
> Formato obrigatório por entrada: Data · Arquivos · Raciocínio · Próximo passo.

---

### [INÍCIO] — 2026-03-24
**Status:** Planejamento concluído. Nenhum código implementado ainda.

**O que foi feito nesta sessão:**
- Criado `spec.financeiro.md` com regras de negócio completas
- Criado `financeiro_plan.md` com arquitetura de 4 ondas, 7 tabelas, decisões documentadas
- Definida regra canônica de `competence_date`
- Modeladas `commission_rules` e `recurring_expenses`
- Corrigido gap de idempotência no `InstallmentPayService`

**Próximo passo:** Iniciar **Onda 1 — Backend**: criar as 5 migrations (`financial_categories`, `bank_accounts`, `account_transactions`, `commission_rules`, `recurring_expenses`), rodar `db:migrate`, criar os 5 models com validações e scopes.

---

### ✅ Onda 1A — Backend: Migrations + Models — 2026-03-24T12:35:00-03:00

**Status:** Concluído com sucesso.

**Arquivos criados:**
- `db/migrate/20260324120001_create_financial_categories.rb`
- `db/migrate/20260324120002_create_bank_accounts.rb`
- `db/migrate/20260324120003_create_account_transactions.rb`
- `db/migrate/20260324120004_create_commission_rules.rb`
- `db/migrate/20260324120005_create_recurring_expenses.rb`
- `app/models/financial_category.rb`
- `app/models/bank_account.rb`
- `app/models/account_transaction.rb`
- `app/models/commission_rule.rb`
- `app/models/recurring_expense.rb`

**Raciocínio:**
- Migrations criadas com timestamps sequenciais `20260324120001`→`20260324120005` após confirmar que o último timestamp existente era `20260322200005`.
- Índice composto `[:account_id, :entry_type, :status]` recebeu nome explícito curto (`idx_acct_txns_account_type_status`) para respeitar o limite de 63 chars do PostgreSQL.
- `AccountTransaction` usa soft delete (`deleted_at`) em vez de destroy para preservar rastreabilidade contábil.
- `CommissionRule.most_specific_for` implementa a regra de prioridade: procedimento > categoria > geral, conforme especificado no plano.
- `RecurringExpense.next_competence_date` encapsula a lógica de `same_month` / `previous_month` para uso futuro no `GenerateRecurringExpensesJob`.
- Validado com `rails runner` — todos os 5 models carregam sem erro, contagem = 0.
- Commit atômico: `feat(financial): create financial tables migrations and models (Onda 1A)`

**Próximo passo imediato:** Onda 1A continua — criar os **5 controllers** + **5 policies** + **rotas** listados na seção "Arquivos modificados na Onda 1" (financial_dashboard_controller, account_transactions_controller, financial_categories_controller, bank_accounts_controller + policies correspondentes + namespace em routes.rb).

---

### ✅ Onda 1A — Controllers + Policies + Rotas — 2026-03-24T12:45:00-03:00

**Status:** Concluído.

**Arquivos criados/editados:**
- `app/controllers/api/v1/accounts/financial_dashboard_controller.rb` — KPIs, receivables, payables, inadimplência, contas, gráficos
- `app/controllers/api/v1/accounts/account_transactions_controller.rb` — CRUD com filtros, paginação, soft delete
- `app/controllers/api/v1/accounts/financial_categories_controller.rb` — CRUD, proteção de categorias padrão
- `app/controllers/api/v1/accounts/bank_accounts_controller.rb` — CRUD, soft destroy (desativa)
- `app/policies/financial_dashboard_policy.rb`, `account_transaction_policy.rb`, `financial_category_policy.rb`, `bank_account_policy.rb`, `commission_rule_policy.rb`, `recurring_expense_policy.rb`
- `config/routes.rb` — `namespace :financial` com dashboard, transactions, categories, bank_accounts
- `app/models/account.rb` — `has_many` das 5 tabelas financeiras
- `CHANGELOG.md` — entrada v1.4.4.8

**Raciocínio:**
- Dashboard controller calcula os 4 KPIs (regime caixa) + inadimplência + mini cash flow + monthly sales em método privados separados para facilitar testes
- `FinancialDashboardPolicy` usa `authorize :financial_dashboard, :show?` (symbol-based Pundit para recurso sem ID)
- Controllers de categorias e bank_accounts só permitem escrita para `administrator` (configurações da clínica)
- Rotas geradas: `GET /api/v1/accounts/:id/financial/dashboard`, CRUD em `/financial/transactions`, `/financial/categories`, `/financial/bank_accounts`
- Validado: `routes.url_helpers.respond_to?(:api_v1_account_financial_dashboard_path)` retorna `true`

**Próximo passo imediato (Onda 1B — Frontend):** Criar a estrutura de pastas `features/financial/`, CSS modular, rotas do Vue, entrada na sidebar e o `FinancialDashboard.vue` inicial.

---

### ✅ Onda 1B — Frontend: Rotas + Sidebar + i18n + Dashboard — 2026-03-24T12:55:00-03:00

**Status:** Concluído.

**Arquivos criados:**
- `app/javascript/dashboard/features/financial/routes.js` — 8 rotas lazy-loaded
- `app/javascript/dashboard/features/financial/financial.css` — CSS modular dual-theme (240 linhas, zero inline/scoped)
- `app/javascript/dashboard/features/financial/api/dashboard.js`
- `app/javascript/dashboard/features/financial/api/accountTransactions.js`
- `app/javascript/dashboard/features/financial/api/categories.js`
- `app/javascript/dashboard/features/financial/api/bankAccounts.js`
- `app/javascript/dashboard/features/financial/api/reports.js`
- `app/javascript/dashboard/features/financial/composables/useFormatCurrency.js`
- `app/javascript/dashboard/features/financial/composables/useFinancialFilters.js`
- `app/javascript/dashboard/features/financial/pages/FinancialDashboard.vue` — Dashboard principal com KPIs reais, A Receber, A Pagar, Inadimplência, Contas
- `app/javascript/dashboard/features/financial/pages/CashFlow.vue` — Placeholder (Onda 2)
- `app/javascript/dashboard/features/financial/pages/Receivables.vue` — Placeholder (Onda 2)
- `app/javascript/dashboard/features/financial/pages/Payables.vue` — Placeholder (Onda 2)
- `app/javascript/dashboard/features/financial/pages/DRE.vue` — Placeholder (Onda 3)
- `app/javascript/dashboard/features/financial/pages/Reports.vue` — Placeholder (Onda 2)
- `app/javascript/dashboard/features/financial/pages/CashRegister.vue` — Placeholder (Onda 3)
- `app/javascript/dashboard/features/financial/pages/FinancialSettings.vue` — Placeholder
- `app/javascript/dashboard/i18n/locale/en/financial.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json`

**Arquivos editados:**
- `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` — `...financialRoutes` adicionado
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` — bloco `Financial` com 8 subitens entre Patients e Contacts
- `app/javascript/dashboard/i18n/locale/en/index.js` — `financial.json` registrado
- `app/javascript/dashboard/i18n/locale/pt_BR/index.js` — `financial.json` registrado

**Raciocínio:**
- CSS 100% em arquivo dedicado `financial.css`, sem `style=""` ou `<style scoped>` (R9)
- Todas as páginas futuras entregues como placeholder com visual `coming-soon` para não bloquear a rota
- `FinancialDashboard.vue` consome a API real (`/financial/dashboard`) e exibe skeleton durante loading
- i18n registrado nos index de EN e pt_BR — a Sidebar usa `t()` sem strings hardcoded
- Rotas lazy-loaded com `() => import()` para não impactar o bundle inicial

**Próximo passo imediato (Onda 2):** Implementar `CashFlow.vue` (gráfico `vue-chartjs`) + `financial_cash_flow_controller.rb` + `CashFlowCalculator` service.

---

_[Próximas entradas serão adicionadas aqui conforme o progresso]_

### ✅ Onda 2A — Cash Flow — 2026-03-24T13:00:00-03:00

**Status:** Concluído.

**Arquivos criados:**
- `app/controllers/api/v1/accounts/financial_reports_controller.rb` — `GET cash_flow` (breakdown diário + saldo inicial) + `GET monthly_summary`
- `app/javascript/dashboard/features/financial/pages/CashFlow.vue` — Página funcional com seletor de período, 3 KPI cards, gráfico de barras CSS-only e tabela diária

**Arquivos editados:**
- `config/routes.rb` — `resources :reports` com `get :cash_flow` e `get :monthly_summary`
- `app/javascript/dashboard/features/financial/api/reports.js` — métodos `cashFlow()` e `monthlySummary()`
- `app/javascript/dashboard/features/financial/composables/useFinancialFilters.js` — adicionado `periods[]` e `dateParams`
- `app/javascript/dashboard/i18n/locale/en/financial.json` — `FINANCIAL.PERIOD.*` e `FINANCIAL.CASH_FLOW.*`
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json` — idem em português

---

### Bugfix — Sidebar i18n quebrada — 2026-03-24T13:01:00-03:00

**Root cause:** `financial.json` tinha chave top-level `SIDEBAR` que sobrescrevia o objeto inteiro do `settings.json` via spread (`...financial`), apagando `INBOX`, `CONVERSATIONS` etc.

**Fix:** Removido bloco `SIDEBAR` de `financial.json`; chaves `FINANCIAL_*` adicionadas dentro do `SIDEBAR` do `settings.json` (EN + pt_BR).

---

### ✅ Onda 2B — A Receber + A Pagar — 2026-03-24T13:05:00-03:00

**Status:** Concluído.

**Arquivos criados:**
- `app/javascript/dashboard/features/financial/pages/Receivables.vue` — Listagem de entradas com filtros (status, vencido, busca), KPIs, tabela com badges de status e paginação
- `app/javascript/dashboard/features/financial/pages/Payables.vue` — Idem para saídas

**Arquivos editados:**
- `app/controllers/api/v1/accounts/account_transactions_controller.rb` — filtros `due_start/due_end`, `overdue`, busca textual `q`; `meta.total_amount`; ordenação por `due_date asc`
- `app/javascript/dashboard/features/financial/api/accountTransactions.js` — método `list()`
- `app/javascript/dashboard/i18n/locale/en/financial.json` — `FINANCIAL.RECEIVABLES.*`, `FINANCIAL.PAYABLES.*`, `FINANCIAL.PAGINATION.*`
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json` — idem em português

**Próximo passo imediato (Onda 3):** Implementar DRE.

---

### ✅ Onda 3A — DRE — 2026-03-24T13:15:00-03:00

**Status:** Concluído.

**Arquivos criados:**
- `app/javascript/dashboard/features/financial/pages/DRE.vue` — Página funcional com seletor de período (mês/trimestre/ano/personalizado), tabela hierárquica expansível por categoria, coluna de variação % vs período anterior, badge de tendência

**Arquivos editados:**
- `app/controllers/api/v1/accounts/financial_reports_controller.rb` — action `dre` + métodos privados `resolve_dre_period`, `prior_period`, `build_dre`, `dre_rows`
- `config/routes.rb` — `get :dre` em `/financial/reports`
- `app/javascript/dashboard/features/financial/api/reports.js` — método `dre(params)`
- `app/javascript/dashboard/features/financial/financial.css` — classes DRE + `.financial-title`, `.financial-subtitle`, `.financial-loading`
- `app/javascript/dashboard/i18n/locale/en/financial.json` — chaves `FINANCIAL.DRE.*`
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json` — chaves `FINANCIAL.DRE.*`

**Raciocínio:**
- DRE usa `competence_date` (regime de competência), não `received_at`/`paid_at` — conforme spec
- `build_dre` agrega por `financial_category.cost_type` (`fixo`/`variavel`) para calcular as linhas: receita bruta → deduções → receita líquida → custos variáveis → margem bruta → despesas fixas → EBITDA → outras despesas → lucro líquido
- `prior_period` calcula o período anterior com a mesma duração do período atual (shift simples)
- `dre_rows` usa LEFT JOIN para incluir transações sem categoria (agrupadas como "Sem categoria")
- Frontend exibe chevron expansível nas seções com subcategorias; seções de resultado têm visual diferenciado
- Botão de exportação presente mas desabilitado (implementação futura)

**Próximo passo imediato (Onda 3B):** Implementar CashRegister.vue (Caixa por Operador).

---

### ✅ Onda 3B — Caixa por Operador — 2026-03-24T13:24:00-03:00

**Status:** Concluído.

**Arquivos criados:**
- `db/migrate/20260324132400_create_cash_registers.rb`
- `db/migrate/20260324132401_create_cash_register_entries.rb`
- `app/models/cash_register.rb` — enum status open/closed, `calculated_balance`, `difference`
- `app/models/cash_register_entry.rb` — tipos: supplement/withdrawal/note
- `app/policies/cash_register_policy.rb` — account_user: CRUD; administrator: destroy
- `app/controllers/api/v1/accounts/cash_registers_controller.rb` — index/show/create/update(close+entry)/destroy
- `app/javascript/dashboard/features/financial/api/cashRegisters.js`
- `app/javascript/dashboard/features/financial/pages/CashRegister.vue` — substituiu placeholder

**Arquivos modificados:**
- `config/routes.rb` — `resources :cash_registers` dentro do namespace `:financial`
- `app/models/account.rb` — `has_many :cash_registers` e `:cash_register_entries`
- `app/javascript/dashboard/features/financial/financial.css` — +250 linhas `cr-*` (status badge, KPI grid, form panel, entry list, dark mode)
- `app/javascript/dashboard/i18n/locale/en/financial.json` — chaves `FINANCIAL.CASH_REGISTER.*` (37 chaves)
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json` — idem em português

**Raciocínio:**
- Modelo com 2 tabelas: `cash_registers` (sessão diária) + `cash_register_entries` (movimentações individuais)
- Saldo calculado = `opening_balance + supplements - withdrawals` (sem vincular a `account_transactions` por ora — coupling mínimo)
- Abertura cria nova sessão; Sangria/Suprimento fazem PATCH com `entry_type` que atualiza acumulados e cria entry de log
- Fechamento: PATCH com `close: 'true'` — calcula diferença entre saldo declarado e calculado para detecção de quebra de caixa
- CSS dual-theme completo: `body.dark` overrides para todos os blocos principais

**Próximo passo imediato (Onda 4A):** Implementar Comissões por Profissional (`CommissionsReport.vue` + `commission_calculator.rb`).

---

### ✅ Onda 4A — Comissões por Profissional — 2026-03-24T13:33:00-03:00

**Status:** Concluído.

**Arquivos criados:**
- `app/services/financial/commission_calculator.rb` — Recebe account, professional e period. Busca transações recebidas do profissional. Aplica `CommissionRule.most_specific_for` por transação. Suporta os 3 tipos: `percentage_production`, `percentage_received`, `fixed_value`. Retorna breakdown completo por transação.
- `app/javascript/dashboard/features/financial/pages/Reports.vue` (substituiu placeholder) — 2 abas: Comissões (select de profissional + período + tabela breakdown) + Despesas por Categoria (gráfico de barras CSS-only + tabela, reutilizando endpoint DRE).

**Arquivos modificados:**
- `app/controllers/api/v1/accounts/financial_reports_controller.rb` — action `commissions` + helper `resolve_commission_period`
- `config/routes.rb` — `get :commissions` na collection de reports
- `app/javascript/dashboard/features/financial/api/reports.js` — método `commissions(params)`
- `app/javascript/dashboard/features/financial/financial.css` — +340 linhas `rep-*`, `comm-*`, `exp-cat-*` (dual theme)
- `app/javascript/dashboard/i18n/locale/en/financial.json` — chaves `FINANCIAL.REPORTS.*` e `FINANCIAL.COMMISSIONS.*`
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json` — idem em português

**Raciocínio:**
- `CommissionCalculator` lê `transaction.metadata['procedure_name']` para a busca de regra por procedimento, mantendo forward-compatibility com a integração futura com procedimentos
- Aba de Despesas por Categoria reutiliza o endpoint `/dre` existente em vez de criar endpoint redundante — princípio de menor código
- Input de Ano usa `type=number` (não `type=month`) para compatibilidade cross-browser
- Commit: `feat(financial): implement commissions report (Onda 4A)`

**Próximo passo:** Onda 4B — Configurações Financeiras (`FinancialSettings.vue`): gestão de regras de comissão + despesas recorrentes.

---

### ✅ Onda 4B — Configurações Financeiras — 2026-03-24T13:56:50-03:00

**Status:** Concluído.

**Arquivos criados:**
- `app/controllers/api/v1/accounts/commission_rules_controller.rb` — CRUD multi-tenant, policy via `CommissionRulePolicy`
- `app/controllers/api/v1/accounts/recurring_expenses_controller.rb` — CRUD multi-tenant, destroy = soft delete (active: false)
- `app/javascript/dashboard/features/financial/api/commissionRules.js` — API client padrão
- `app/javascript/dashboard/features/financial/api/recurringExpenses.js` — API client padrão

**Arquivos modificados:**
- `app/javascript/dashboard/features/financial/pages/FinancialSettings.vue` — substituiu placeholder com 2 abas CRUD completas
- `config/routes.rb` — `resources :commission_rules` e `resources :recurring_expenses`
- `app/javascript/dashboard/features/financial/financial.css` — +420 linhas `sets-*` (tabs, modal animado, table, form, badges, dark mode)
- `app/javascript/dashboard/i18n/locale/en/financial.json` — +67 chaves `FINANCIAL.SETTINGS.*`
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json` — idem

**Commit:** `feat(financial): implement settings page — commission rules + recurring expenses (Onda 4B)`

---

### [Onda 4C] — 2026-03-24T14:05:17-03:00
**Status:** ✅ Concluída

**O que foi feito:**
- Backend: `#insurance` e `#average_ticket` adicionados ao `FinancialReportsController`
- Exportação CSV: `?format=csv` suportado em `commissions` e `insurance`
- Rotas: `get :insurance` e `get :average_ticket` no namespace `financial/reports`
- API client: `insurance()`, `averageTicket()`, `downloadReportCSV()` em `reports.js`
- UI: `Reports.vue` reescrito com 4 abas (Comissões · Despesas · Convênio · Ticket Médio)
- CSS: +50 linhas novas (`.rep-export-btn`, `.rep-ins-*`, `.rep-tick-*`, utilitários)
- i18n: +35 chaves `FINANCIAL.REPORTS.*` em EN e pt_BR

**Commit:** `feat(financial): Onda 4C — insurance billing, average ticket reports + CSV export`

**Próximo passo:** Docker build `v1.4.4.16` ou iniciar funcionalidades complementares (Quick Wins: badge na sidebar, alerta de vencimento, meta mensal).
**BCLINIC**

Especificação Técnica Completa

Módulo Financeiro --- Indicadores, KPIs, Relatórios e Tabelas

Fórmulas, fontes de dados, variáveis e edge cases

*Para o time de desenvolvimento --- zero ambiguidade*

**1. Cabeçalho Global --- 4 KPIs Principais**

Visível em todas as abas do financeiro. Reage ao seletor de período e ao
filtro de clínica.

**1.1 Receita Líquida**

**Definição**

Total de dinheiro que efetivamente ENTROU no caixa/contas da clínica no
período. São recebimentos confirmados, não faturamento.

**Fórmula**

  -----------------------------------------------------------------------
  **receita_liquida = SUM(valor) WHERE tipo = \'entrada\' AND status =
  \'recebido\' AND data_recebimento IN periodo**

  -----------------------------------------------------------------------

**Fonte de dados**

Tabela: lancamentos financeiros (entradas confirmadas/baixadas)

**Variáveis que afetam**

- **data_recebimento:** data em que o dinheiro efetivamente entrou
    (não a data de vencimento). Para PIX/dinheiro = no ato. Para cartão
    crédito = data do repasse da operadora. Para boleto = data de
    compensação.

- **status = \'recebido\':** somente lançamentos já
    baixados/confirmados. Parcelas em aberto NÃO contam aqui (contam em
    \'Novas Entradas\').

- **tipo = \'entrada\':** exclui saídas, estornos são tratados como
    entrada negativa (valor negativo com tipo \'entrada\').

- **filtro_clinica:** se multi-clínica, filtrar por clinica_id. Se
    \'Todas\', somar todas.

**Edge cases**

- **Estorno:** quando um recebimento é estornado, gera um lançamento
    de entrada com valor NEGATIVO. A receita líquida naturalmente
    diminui.

- **Cartão crédito parcelado:** a clínica recebeu do paciente no ato,
    mas o repasse da operadora vem em parcelas. Regra: contabilizar na
    data em que a clínica RECEBEU do paciente (momento da venda), não na
    data do repasse. O repasse da operadora é conciliação, não receita.

- **Convênio:** contabilizar na data em que o convênio pagou, não na
    data do atendimento.

**Comportamento visual**

- Seta verde = mais receita que período anterior (bom). Seta vermelha
    = menos.

- Variação em percentual: ((atual - anterior) / anterior) \* 100

- Clicável: abre modal com lista de todos os recebimentos do período,
    agrupados por dia.

**1.2 Saídas**

**Definição**

Total de dinheiro que efetivamente SAIU do caixa/contas da clínica no
período. Despesas pagas.

**Fórmula**

  -----------------------------------------------------------------------
  **saidas = SUM(valor) WHERE tipo = \'saida\' AND status = \'pago\' AND
  data_pagamento IN periodo**

  -----------------------------------------------------------------------

**Fonte de dados**

Tabela: lancamentos financeiros (saídas confirmadas/pagas)

**Variáveis que afetam**

- **data_pagamento:** data em que o pagamento foi efetivado. Para
    despesas recorrentes (aluguel), é a data em que foi de fato pago,
    não o vencimento.

- **status = \'pago\':** somente despesas efetivamente pagas. Despesas
    em aberto ou a vencer NÃO contam (aparecem em Contas a Pagar).

- **Inclui:** aluguel, salários, materiais, impostos, repasses a
    profissionais, sangrias registradas, transferências para contas
    bancárias (se saíram do caixa).

- **NÃO inclui:** transferências internas entre contas próprias (não é
    saída, é movimentação).

**Edge case**

- **Repasse a profissional:** é uma saída. Categoria = \'repasse\'.
    Registrada quando o pagamento ao profissional é efetivado.

- Seta VERMELHA quando sobe (mais saídas = ruim). Seta VERDE quando
    desce. Lógica invertida.

  -----------------------------------------------------------------------
  *REGRA INVERTIDA: Para Saídas, subir é RUIM. Seta vermelha. Descer é
  bom, seta verde. Mesma lógica da \'Faltas\' na Agenda.*

  -----------------------------------------------------------------------

**1.3 Novas Entradas**

**Definição**

Total de receitas GERADAS (faturadas) no período, independente de terem
sido recebidas. É o faturamento bruto: orçamentos aprovados,
procedimentos realizados, cobranças criadas.

**Fórmula**

  -----------------------------------------------------------------------
  **novas_entradas = SUM(valor) WHERE tipo = \'entrada\' AND data_criacao
  IN periodo**

  -----------------------------------------------------------------------

**Diferença crucial vs Receita Líquida**

  -----------------------------------------------------------------------
  **Receita Líquida**                 **Novas Entradas**
  ----------------------------------- -----------------------------------
  Dinheiro que JA ENTROU              Dinheiro que FOI FATURADO

  Usa data_recebimento                Usa data_criacao (data do
                                      lancamento)

  Status = recebido                   Qualquer status (aberto, recebido,
                                      parcial)

Mede o caixa real                   Mede a producao comercial
  -----------------------------------------------------------------------

- **Origem automática (Módulo Comercial):** orçamento aprovado gera
    lançamento com data_criacao = data da aprovação.

- **Origem automática (Prontuário):** procedimento marcado
    \'realizado\' gera lançamento com data_criacao = data do
    atendimento.

- **Origem manual:** recepcionista cria cobrança manualmente.

- Seta verde = mais faturamento (bom).

**1.4 Lucro Líquido**

**Definição**

Diferença entre o que entrou e o que saiu efetivamente no período. Mede
o resultado financeiro real.

**Fórmula**

  -----------------------------------------------------------------------
  **lucro_liquido = receita_liquida - saidas**

  -----------------------------------------------------------------------

**Variáveis**

- **receita_liquida:** conforme seção 1.1

- **saidas:** conforme seção 1.2

**Toggle \'Incluir valores adicionais\'**

Quando ativado, adiciona ao cálculo:

- **Juros recebidos** (lançamentos com categoria =
    \'juros_recebidos\')

- **Multas recebidas** (categoria = \'multa_recebida\')

- **Rendimentos** (categoria = \'rendimento\')

  -----------------------------------------------------------------------
  **lucro_ajustado = receita_liquida + juros + multas + rendimentos -
  saidas**

  -----------------------------------------------------------------------

- **Cor do card:** VERDE se lucro \> 0 (lucro). VERMELHO se lucro \< 0
    (prejuízo). O próprio card muda de cor, não só a seta.

- Seta: variação em percentual vs período anterior. Verde se melhorou,
    vermelho se piorou.

**2. Visão Geral --- Blocos de Dashboard**

**2.1 Bloco A Receber**

**Dados e fórmulas**

  ------------------------------------------------------------------------
  **Indicador**    **Fórmula**                 **Fonte / Regras**
  ---------------- --------------------------- ---------------------------
  **Vencidos       SUM(valor_restante) WHERE   Tabela: contas_a_receber.
  (R\$)**          tipo=\'entrada\' AND status valor_restante =
                   IN (\'aberto\',\'parcial\') valor_total -
                   AND data_vencimento \< HOJE valor_ja_recebido. Cor
                                               VERMELHA.

  **Não vencidos   SUM(valor_restante) WHERE   Parcelas futuras dentro do
  (R\$)**          status IN                   filtro de período. Cor
                   (\'aberto\',\'parcial\')    AZUL.
                   AND data_vencimento \>=
                   HOJE

  **Vencem hoje**  SUM(valor_restante) WHERE   Urgente: precisa
                   data_vencimento = HOJE AND  cobrar/receber hoje. Cor
                   status IN                   LARANJA.
                   (\'aberto\',\'parcial\')

  **Depositado**   SUM(valor) WHERE            Ja entrou no caixa/conta.
                   status=\'recebido\' AND     Barra de progresso verde.
                   data_recebimento IN periodo

  **Não            vencem_hoje + vencidos (do  Ainda não entrou. Barra de
  depositado**     periodo)                    progresso cinza/vermelha.

**Restante do    SUM(valor_restante) WHERE   Quanto ainda espera receber
  mês**            data_vencimento BETWEEN     até o fim do mês.
                   HOJE AND ultimo_dia_mes AND
                   status != \'recebido\'
  ------------------------------------------------------------------------

**Barra de progresso**

  -----------------------------------------------------------------------
  **progresso = depositado / (depositado + nao_depositado) \* 100**

  -----------------------------------------------------------------------

- Parte verde = depositado. Parte cinza = não depositado. Se vencidos
    \> 0, parte vermelha dentro do cinza.

**2.2 Bloco A Pagar**

Mesma estrutura espelhada. Trocar \'recebido\' por \'pago\', \'entrada\'
por \'saida\', \'depositado\' por \'pago\'. Fontes: tabela
contas_a_pagar.

**2.3 Card de Inadimplência (adição)**

  -----------------------------------------------------------------------
  **total_inadimplencia = SUM(valor_restante) WHERE tipo=\'entrada\' AND
  status IN (\'aberto\',\'parcial\') AND data_vencimento \< HOJE**

  -----------------------------------------------------------------------

  -----------------------------------------------------------------------
  **qtd_pacientes_inadimplentes = COUNT(DISTINCT paciente_id) WHERE
  \[mesma condicao acima\]**

  -----------------------------------------------------------------------

- Mostra: valor total + quantidade de pacientes. Botão \'Ver
    inadimplentes\' abre relatório filtrado.

**2.4 Contas Financeiras**

**Dados**

- Lista de contas bancárias cadastradas nas configurações

- Para cada conta: nome, banco (com logo), saldo_atual

**Cálculo do saldo**

  -----------------------------------------------------------------------
  **saldo_conta = saldo_inicial + SUM(entradas na conta) - SUM(saidas da
  conta)**

  -----------------------------------------------------------------------

- **saldo_inicial:** valor informado no cadastro da conta

- **Entradas:** recebimentos vinculados àquela conta_id

- **Saídas:** pagamentos feitos a partir daquela conta_id

- **Transferências:** saída da conta origem, entrada na conta destino.
    Saldo total não muda.

**2.5 Fluxo de Caixa Mini**

Gráfico de barras resumido dos últimos 7 dias. Para cada dia:

  -----------------------------------------------------------------------
  **entrada_dia = SUM(valor) WHERE tipo=\'entrada\' AND
  status=\'recebido\' AND data_recebimento = dia**

  -----------------------------------------------------------------------

  -----------------------------------------------------------------------
  **saida_dia = SUM(valor) WHERE tipo=\'saida\' AND status=\'pago\' AND
  data_pagamento = dia**

  -----------------------------------------------------------------------

  -----------------------------------------------------------------------
  **saldo_dia = entrada_dia - saida_dia**

  -----------------------------------------------------------------------

- Barra verde = entradas. Barra vermelha = saídas. Linha = saldo
    acumulado.

**2.6 Gráfico de Vendas (Faturamento Mensal)**

  -----------------------------------------------------------------------
  **faturamento_mes = SUM(valor) WHERE tipo=\'entrada\' AND
  MONTH(data_criacao) = mes**

  -----------------------------------------------------------------------

- Barra para cada um dos últimos 6 meses. Usa data_criacao
    (faturamento, não recebimento).

**3. Fluxo de Caixa --- Gráfico Principal**

**Para cada dia do período, calcular 6 variáveis:**

  ------------------------------------------------------------------------
  **Variável**        **Fórmula**                **Visual**
  ------------------- -------------------------- -------------------------
  **Entradas          SUM(valor) WHERE           Barra verde sólida
  efetivas**          tipo=\'entrada\' AND
                      status=\'recebido\' AND
                      data_recebimento = dia

  **Saídas efetivas** SUM(valor) WHERE           Barra vermelha sólida
                      tipo=\'saida\' AND
                      status=\'pago\' AND
                      data_pagamento = dia

  **A receber**       SUM(valor_restante) WHERE  Barra azul translúcida
                      tipo=\'entrada\' AND
                      status IN
                      (\'aberto\',\'parcial\')
                      AND data_vencimento = dia  

  **A pagar**         SUM(valor_restante) WHERE  Barra rosa translúcida
                      tipo=\'saida\' AND status  
                      IN
                      (\'aberto\',\'parcial\')
                      AND data_vencimento = dia  

  **Saldo diário**    entradas_efetivas -        Linha amarela (pontos por
                      saidas_efetivas            dia)

**Saldo acumulado** saldo_inicial_periodo +    Linha azul contínua
                      SUM(saldo_diario) ate o
                      dia
  ------------------------------------------------------------------------

**Painel Lateral --- Resumo do Mês**

  -----------------------------------------------------------------------
  **Campo**              **Fórmula**
  ---------------------- ------------------------------------------------
  **Entradas totais**    SUM(entradas efetivas de todos os dias do mes)

  **Saídas totais**      SUM(saidas efetivas de todos os dias do mes)

  **Saldo parcial**      entradas_totais - saidas_totais (realizado ate
                         hoje)

  **A Receber restante** SUM(valor_restante) WHERE tipo=\'entrada\' AND
                         status!=\'recebido\' AND data_vencimento IN
                         mes_restante

  **A Pagar restante**   SUM(valor_restante) WHERE tipo=\'saida\' AND
                         status!=\'pago\' AND data_vencimento IN
                         mes_restante

  **Saldo pendente**     a_receber_restante - a_pagar_restante

**Saldo previsto**     saldo_parcial + saldo_pendente (projecao de fim
                         de mes)
  -----------------------------------------------------------------------

**Resumo Entradas por Forma de Pagamento**

  -----------------------------------------------------------------------
  **valor_por_forma = SUM(valor) WHERE tipo=\'entrada\' AND
  status=\'recebido\' AND forma_pagamento = X AND data_recebimento IN
  periodo**

  -----------------------------------------------------------------------

Cards: Boleto, Cartão Crédito, Cartão Débito, Dinheiro, Juros, Multas,
PIX, Transferência.

**4. DRE Simplificado --- Fórmulas Linha a Linha**

Cada linha do DRE tem uma fórmula e uma fonte de dados específica. O DRE
é baseado em COMPETÊNCIA (data do fato gerador), não em CAIXA (data do
recebimento/pagamento).

  -----------------------------------------------------------------------
  *REGRA CRÍTICA: O DRE usa regime de COMPETÊNCIA. Receita conta na data
  do atendimento/venda, não na data do recebimento. Despesa conta na data
  de competência (mês a que se refere), não na data de pagamento. Isso é
  diferente do Fluxo de Caixa (que usa regime de CAIXA).*

  -----------------------------------------------------------------------

  ------------------------------------------------------------------------
  **Linha DRE**      **Fórmula**                **Fonte / Variáveis**
  ------------------ -------------------------- --------------------------
  **(+) Receita      SUM(valor_original) WHERE  valor_original = valor
  Bruta**            tipo=\'entrada\' AND       antes de descontos.
                     data_competencia IN        data_competencia = data do
                     periodo                    atendimento ou venda.

  **(-) Descontos**  SUM(valor_desconto) para   valor_desconto = diferenca
                     todos os lancamentos de    entre valor de tabela e
                     entrada do periodo         valor cobrado. Vem do
                                                orcamento aprovado.

  **(=) Receita      receita_bruta - descontos  Calculado, nao armazenado.
  Liquida**

  **(-) Custos       SUM(valor) WHERE           Categorias marcadas como
  variaveis**        tipo=\'saida\' AND         \'variavel\' nas
                     categoria IN (material,    configuracoes. Inclui
                     laboratorio,               comissoes do comercial e
                     comissoes_sdr,             repasses a profissionais
                     comissoes_closer) AND      se baseados em %.
                     data_competencia IN
                     periodo

  **(=) Margem       receita_liquida -          Calculado.
  contribuicao**     custos_variaveis

  **(-) Custos       SUM(valor) WHERE           Categorias marcadas como
  fixos**            tipo=\'saida\' AND         \'fixo\' nas
                     categoria IN (aluguel,     configuracoes. Despesas
                     salarios, energia,         que existem independente
                     software, manutencao,      do volume.
                     \...) AND data_competencia
                     IN periodo

  **(=) Resultado    margem_contribuicao -      Calculado.
  operac.**          custos_fixos

  **(-/+) Resultado  SUM(juros_recebidos +      Categorias financeiras
  financ.**          multas_recebidas +         especificas.
                     rendimentos) -
                     SUM(juros_pagos +
                     taxas_bancarias +
                     taxas_cartao)

**(=) Resultado    resultado_operacional +    Lucro ou prejuizo do
  liquido**          resultado_financeiro       periodo. VERDE se \> 0,
                                                VERMELHO se \< 0
  ------------------------------------------------------------------------

**Margem percentual (coluna adicional)**

  -----------------------------------------------------------------------
  **margem\_% = (valor_da_linha / receita_bruta) \* 100**

  -----------------------------------------------------------------------

- Exibir em cada linha. Ex: Custos fixos = R\$15.000 (25.0%)

- Se receita_bruta = 0, exibir 0% (evitar divisão por zero)

**Comparação**

- Coluna extra com valores do período de comparação + variação %

- Mes atual vs mes anterior, OU mes atual vs mesmo mes ano passado
    (toggle)

**5. Relatórios Financeiros --- Especificação Completa**

**5.1 Faturamento por Profissional**

**Query base**

  -----------------------------------------------------------------------
  **SELECT profissional, SUM(valor) as faturamento, COUNT(\*) as
  atendimentos FROM lancamentos WHERE tipo=\'entrada\' AND origem IN
  (\'procedimento\',\'orcamento\') AND data_competencia IN periodo GROUP
  BY profissional ORDER BY faturamento DESC**

  -----------------------------------------------------------------------

**Colunas da tabela**

  -----------------------------------------------------------------------
  **Coluna**         **Cálculo / Regra**
  ------------------ ----------------------------------------------------
  **Profissional**   Nome do profissional. Avatar com iniciais.

  **Atendimentos**   COUNT de lancamentos de entrada vinculados ao
                     profissional.

  **Faturamento      SUM(valor_original) dos lancamentos do profissional.
  bruto**

  **Descontos**      SUM(valor_desconto) nos lancamentos do profissional.

  **Faturamento      faturamento_bruto - descontos.
  líquido**

  **Ticket médio**   faturamento_liquido / atendimentos. Se
                     atendimentos=0, exibir R\$0.

  **% do total**     faturamento_liquido_profissional /
                     faturamento_liquido_total \* 100.

**Repasse          Aplica regra de repasse configurada (% sobre
  estimado**         producao ou fixo). Base: faturamento liquido ou
                     valor recebido (configuravel)
  -----------------------------------------------------------------------

- **Filtros:** período, clínica, especialidade

- Gráfico de barras horizontais com ranking visual

**5.2 Faturamento por Procedimento**

  -----------------------------------------------------------------------
  **SELECT procedimento, COUNT(\*) as qtd, SUM(valor) as faturamento,
  AVG(valor) as ticket_medio FROM lancamentos WHERE tipo=\'entrada\' AND
  procedimento IS NOT NULL AND data_competencia IN periodo GROUP BY
  procedimento ORDER BY faturamento DESC**

  -----------------------------------------------------------------------

**Colunas**

- Procedimento, Quantidade, Faturamento bruto, Ticket médio, % do
    total

- **Adicional (cross-módulo):** custo médio do material (se cadastrado
    no procedimento), margem estimada = faturamento - custo_material

**5.3 Faturamento por Convênio**

  -----------------------------------------------------------------------
  **SELECT convenio, COUNT(\*) as qtd, SUM(valor) as faturamento FROM
  lancamentos WHERE tipo=\'entrada\' AND convenio_id IS NOT NULL AND
  data_competencia IN periodo GROUP BY convenio**

  -----------------------------------------------------------------------

- Colunas: Convênio, Quantidade de atendimentos, Faturamento, Ticket
    médio, % do total

- **Adicional:** comparar valor cobrado do convênio vs valor da tabela
    particular. Diferença = desconto implícito do convênio.

**5.4 Relatório de Inadimplência**

**Aging (envelhecimento da dívida)**

  -----------------------------------------------------------------------
  **SELECT paciente, SUM(CASE WHEN dias_atraso BETWEEN 1 AND 30 THEN
  valor_restante END) as faixa_1_30, SUM(CASE WHEN dias_atraso BETWEEN 31
  AND 60 THEN valor_restante END) as faixa_31_60, SUM(CASE WHEN
  dias_atraso BETWEEN 61 AND 90 THEN valor_restante END) as faixa_61_90,
  SUM(CASE WHEN dias_atraso \> 90 THEN valor_restante END) as
  faixa_90_mais FROM contas_a_receber WHERE status != \'recebido\' AND
  data_vencimento \< HOJE GROUP BY paciente**

  -----------------------------------------------------------------------

- dias_atraso = HOJE - data_vencimento

- Colunas: Paciente, Telefone, 1-30 dias, 31-60 dias, 61-90 dias, 90+
    dias, Total, Último contato, Ações

- Ações: Enviar cobrança (Bia), Registrar contato, Ver histórico,
    Negociar

- Totalizadores por faixa no topo (cards coloridos: verde 1-30,
    amarelo 31-60, laranja 61-90, vermelho 90+)

**5.5 Despesas por Categoria**

  -----------------------------------------------------------------------
  **SELECT categoria, subcategoria, SUM(valor) as total FROM lancamentos
  WHERE tipo=\'saida\' AND data_competencia IN periodo GROUP BY
  categoria, subcategoria ORDER BY total DESC**

  -----------------------------------------------------------------------

- **Visão principal:** gráfico de pizza/donut por categoria principal.
    Clicar na fatia expande subcategorias.

- **Tabela:** Categoria, Subcategoria, Valor, % do total de despesas,
    % da receita bruta (quanto da receita vai para aquela despesa).

- **Comparativo:** coluna com período anterior e variação. Identifica
    despesas que subiram.

**5.6 Fluxo de Caixa Projetado (30/60/90 dias)**

**Lógica de projeção**

- **Componente 1 --- Recorrências:** despesas recorrentes (aluguel,
    salários) projetadas para os próximos meses com base no valor atual.

- **Componente 2 --- Contas a receber:** parcelas futuras já
    cadastradas (orçamentos parcelados).

- **Componente 3 --- Contas a pagar:** despesas futuras já
    cadastradas.

- **Componente 4 --- Estimativa de receita:** média dos últimos 3
    meses de faturamento projetada para frente (opcional, toggle).

  -----------------------------------------------------------------------
  **saldo_projetado_dia_X = saldo_atual + SUM(entradas_previstas ate dia
  X) - SUM(saidas_previstas ate dia X)**

  -----------------------------------------------------------------------

- Alerta se saldo projetado ficar negativo em algum dia futuro. Exibir
    \'Atenção: saldo negativo previsto em dd/mm\'.

**5.7 Comissões**

  -----------------------------------------------------------------------
  **comissao_sdr = SUM(valor_orcamento \* percentual_sdr) WHERE
  orcamento.status = \'fechado\' AND orcamento.data_fechamento IN periodo
  AND orcamento.sdr_id = X**

  -----------------------------------------------------------------------

  -----------------------------------------------------------------------
  **comissao_closer = SUM(valor_orcamento \* percentual_closer) WHERE
  orcamento.status = \'fechado\' AND orcamento.data_fechamento IN periodo
  AND orcamento.closer_id = X**

  -----------------------------------------------------------------------

- Colunas: Membro, Cargo (SDR/Closer), Orçamentos fechados, Valor
    total, % comissão, Valor comissão, Status (pendente/pago)

- **Integração com Módulo Comercial:** puxa orcamento_id, sdr_id,
    closer_id, valor, data_fechamento

- **Base configurável:** sobre valor cobrado OU sobre valor
    efetivamente recebido (importante para parcelamentos)

**5.8 Ticket Médio**

  -----------------------------------------------------------------------
  **ticket_medio_geral = SUM(valor_lancamentos_entrada) / COUNT(DISTINCT
  paciente_id) WHERE data_competencia IN periodo**

  -----------------------------------------------------------------------

  -----------------------------------------------------------------------
  **ticket_medio_atendimento = SUM(valor_lancamentos_entrada) /
  COUNT(lancamentos) WHERE data_competencia IN periodo**

  -----------------------------------------------------------------------

- Duas visões: por paciente (quanto cada paciente gasta em média) e
    por atendimento (valor médio por consulta).

- Filtros: profissional, procedimento, período. Gráfico de tendência
    (linha ao longo dos meses).

**5.9 Conciliação de Cartões**

**Para cada venda em cartão:**

  -----------------------------------------------------------------------
  **Campo**          **Cálculo**
  ------------------ ----------------------------------------------------
  **Valor vendido**  Valor cobrado do paciente no ato.

  **Taxa             \% cadastrada nas configuracoes para aquela
  configurada**      operadora/bandeira.

  **Valor líquido    valor_vendido \* (1 - taxa_configurada / 100)
  esperado**

  **Valor recebido** Valor efetivamente depositado pela operadora
                     (informado manual ou via integracao).

  **Diferença**      valor_recebido - valor_liquido_esperado. Se != 0,
                     ALERTA de discrepância.

  **Data prevista    data_venda + prazo_recebimento_configurado (ex: 30
  repasse**          dias para credito).

**Status**         Pendente (antes da data prevista), Recebido (valor
                     conferido), Divergente (diferenca != 0), Atrasado
                     (passou da data e nao recebeu)
  -----------------------------------------------------------------------

**5.10 Repasse a Profissionais**

  -----------------------------------------------------------------------
  **repasse = CASE WHEN regra = \'percentual\' THEN base_calculo \*
  (percentual / 100) WHEN regra = \'fixo\' THEN valor_fixo WHEN regra =
  \'hibrido\' THEN valor_fixo + (base_calculo \* percentual / 100) END**

  -----------------------------------------------------------------------

- **base_calculo (configurável):** valor cobrado (faturamento) OU
    valor efetivamente recebido. Se \'recebido\', parcelas não pagas
    pelo paciente não geram repasse.

- Colunas: Profissional, Atendimentos, Faturamento bruto, Base de
    cálculo, Regra (X%), Valor repasse, Status (calculado/aprovado/pago)

- Workflow: Sistema calcula → Gestor aprova → Financeiro paga → Status
    = pago.

**6. Caixa por Operador --- Fórmulas**

**Ciclo do caixa**

  -----------------------------------------------------------------------
  **saldo_esperado = saldo_inicial + SUM(entradas_no_caixa) -
  SUM(saidas_do_caixa) - SUM(sangrias) + SUM(suprimentos)**

  -----------------------------------------------------------------------

  -----------------------------------------------------------------------
  **quebra_caixa = saldo_informado_fechamento - saldo_esperado**

  -----------------------------------------------------------------------

- **Se quebra \> 0:** sobra de caixa (operador tem mais dinheiro do
    que deveria).

- **Se quebra \< 0:** falta de caixa (operador tem menos do que
    deveria). ALERTA.

- **Se quebra = 0:** caixa bate. Badge verde \'✓ Conferido\'.

**Detalhamento por forma de pagamento**

  -----------------------------------------------------------------------
  **saldo_dinheiro = saldo_inicial_dinheiro + SUM(entradas WHERE
  forma=\'dinheiro\') - SUM(sangrias)**

  -----------------------------------------------------------------------

  -----------------------------------------------------------------------
  **saldo_credito = SUM(entradas WHERE forma=\'cartao_credito\')**

  -----------------------------------------------------------------------

  -----------------------------------------------------------------------
  **saldo_debito = SUM(entradas WHERE forma=\'cartao_debito\')**

  -----------------------------------------------------------------------

  -----------------------------------------------------------------------
  **saldo_cheque = SUM(entradas WHERE forma=\'cheque\')**

  -----------------------------------------------------------------------

  -----------------------------------------------------------------------
  **saldo_pix = SUM(entradas WHERE forma=\'pix\')**

  -----------------------------------------------------------------------

- Sangria só afeta dinheiro físico. Cartão/PIX não têm sangria.

**7. Regras Gerais para o Desenvolvedor**

**Arredondamento**

- **Valores monetários:** sempre 2 casas decimais. Separador de milhar
    com ponto, decimal com vírgula (padrão BR). Ex: R\$ 15.234,50

- **Percentuais:** 1 casa decimal. Ex: 12.5%

- **Variação de KPI:** 1 casa decimal com seta. Ex: ↑ 8.3%

**Divisão por zero**

Em TODA divisão, verificar denominador = 0. Se for, exibir R\$ 0,00 ou
0%. Nunca NaN ou Infinity.

**Estorno nunca deleção**

Nenhum lançamento financeiro é deletado. Cancelamentos geram lançamento
de estorno (valor negativo) com vínculo (estorno_de_id) ao lançamento
original.

**Regime de competência vs caixa**

  ------------------------------------------------------------------------
  **Tela / Relatório**   **Regime**               **Qual data usa**
  ---------------------- ------------------------ ------------------------
  Cabecalho KPIs         CAIXA                    data_recebimento /
  (Receita/Saidas)                                data_pagamento

  Cabecalho KPIs (Novas  COMPETENCIA              data_criacao
  entradas)

  Fluxo de caixa         CAIXA                    data_recebimento /
                                                  data_pagamento

  Contas a pagar/receber COMPETENCIA              data_vencimento

  DRE                    COMPETENCIA              data_competencia

  Relatórios de          COMPETENCIA              data_competencia (data
  faturamento                                     do atendimento)

Conciliação de cartões CAIXA                    data_recebimento do
                                                  repasse
  ------------------------------------------------------------------------

  -----------------------------------------------------------------------
  *REGRA CRÍTICA: Todo lançamento financeiro deve ter 3 campos de data:
  data_criacao (quando foi gerado), data_competencia (a que mês se
  refere), data_vencimento (quando vence). Receitas têm também
  data_recebimento (quando o dinheiro entrou). Despesas têm
  data_pagamento (quando foi pago). Sem esses 5 campos, o sistema não
  consegue fazer DRE + Fluxo de Caixa corretamente.*

  -----------------------------------------------------------------------

**Setas verde/vermelha --- Resumo**

  ------------------------------------------------------------------------
  **KPI**                **Sobe = ?**             **Desce = ?**
  ---------------------- ------------------------ ------------------------
  Receita Liquida        ↑ Verde (bom)            ↓ Vermelho

  **Saidas**             ↑ Vermelho (ruim)        ↓ Verde (bom)

  Novas entradas         ↑ Verde (bom)            ↓ Vermelho

  Lucro Liquido          ↑ Verde (bom)            ↓ Vermelho

  **Inadimplencia**      ↑ Vermelho (ruim)        ↓ Verde (bom)

Taxa Ocupacao          ↑ Verde                  ↓ Vermelho
  ------------------------------------------------------------------------

**Bclinic --- Cada centavo com fórmula. Cada relatório com query.**

*Competência no DRE. Caixa no fluxo. 5 campos de data. Zero
ambiguidade.*
# Módulo Financeiro BeClinic — Manual Completo de Uso [HISTÓRICO V1]

> ⚠️ **Este manual descreve a interface V1 (legacy, março-abril 2026).** A interface foi totalmente refeita em V2 (telas com prefixo `/financial/v2/*`, 6 charts no Dashboard, period selector Semana/Mês/Trimestre/Ano/Todos, etc).
>
> Para o **manual atualizado da V2** (com print das telas reais em produção), use:
> - [`docs/01-product/modules/financeiro-funcionamento.md`](./financeiro-funcionamento.md) — regras de negócio canon
> - [`docs/01-product/financial-v2-teste-visual.md`](../financial-v2-teste-visual.md) — roteiro de uso passo a passo (escrito pra recepção/dono da clínica)
>
> O conteúdo abaixo foi preservado por valor histórico (mostra a evolução do produto), mas **NÃO É REPRESENTATIVO** das telas atuais em produção.

Este é o documento definitivo e detalhado sobre o funcionamento, regras de negócio e limites do Módulo Financeiro Centralizado da plataforma BeClinic. Ele foi desenhado para ser a masterclass de uso, cobrindo cada tela, cada botão, o que você pode fazer, e principalmente: **o que não se pode fazer e por quê**.

---

## 🧭 Visão Geral Escopo do Sistema

O módulo financeiro do BeClinic não é um simples "caderninho de anotações". Ele foi projetado para seguir **Regras Contábeis Profissionais**. Isso significa que ele opera ativamente com dois regimes diferentes simultaneamente:
1. **Regime de Caixa:** Usado no *Dashboard*, *Fluxo de Caixa*, *A Pagar* e *A Receber*. O dinheiro é contado **no dia em que ele entra ou sai do banco**.
2. **Regime de Competência:** Usado no *DRE*. O dinheiro é contado **no mês em que o serviço foi prestado / a obrigação foi gerada**, independentemente de quando o paciente vai pagar. Isso mostra se a clínica deu lucro ou prejuízo real no exercício de um mês isolado.

Todas as telas acessadas pelo Menu Lateral (abaixo de "Pacientes") refletem essa centralização.

---

## 1. 📊 Dashboard Principal

A tela inicial que te dá o pulso da clínica no momento que você abre o sistema.

### O que essa tela faz?
Mostra em tempo real os 4 KPIs centrais (Receita Líquida, Saídas, Novas Entradas e Lucro Líquido), comparando com o período anterior. Além disso, mostra atalhos rápidos das contas vencidas e a vencer hoje, junto com o saldo em tempo real de todas as contas bancárias cadastradas.

### O que tem lá dentro (Funcionalidades e Botões)?
- **Seletor de Período (Botões Hoje, Semana, Mês):** Recalcula instantaneamente todos os KPIs e blocos de resumo sem recarregar a página.
- **Card A Receber / A Pagar:** Dá a volumetria financeira do que está atrasado (vermelho), o que vence hoje (laranja) e o que ainda vai vencer.
- **Card Inadimplência:** Te conta rapidamente quantos pacientes estão com boletos/parcelas atrasadas na clínica inteira.
- **Contas Bancárias:** Mostra o saldo acumulado de acordo com o que entrou e saiu.

### O que NÃO dá para fazer lá?
- **Você não pode criar uma transação direto do Dashboard.** Ele é uma tela puramente de **leitura e atalho**.
- **Você não edita saldos por ali.** O saldo do Bradesco ou Itaú refletido ali é o somatório estrito da tela "Configurações > Banco" mais o que rolou no Caixa e Pagamentos. Não há um botão "Alterar Saldo" no dashboard.

---

## 2. 📉 Fluxo de Caixa

A visão cirúrgica de entradas e saídas diárias, com projeções.

### O que essa tela faz?
Mostra graficamente, dia após dia, as barras verdes (entradas) e vermelhas (saídas), mesclado com a linha de saldo.

### O que tem lá dentro?
- **Filtro de Calendário Personalizado:** Você pode prever o futuro. Se jogar para o próximo mês, o sistema lerá tudo o que está em "A Receber e A Pagar", e desenhará como seu saldo vai se comportar lá na frente.
- **Cards de Meios de Pagamento:** Resumo de quanto entrou em PIX, Cartão, Boleto, etc., e o Total Entradas / Saídas.

### O que NÃO dá para fazer lá?
- O gráfico é intocável. **Você não pode clicar na barra verde e arrastá-la ou excluir um lançamento através do gráfico**. Ele é uma fotografia dos dados concretos em `/financeiro/a-pagar` e `/financeiro/a-receber`.

---

## 3. 📥 A Receber (Receitas)

A lista de todas as contas que a clínica tem a receber.

### O que essa tela faz?
É o livro-caixa de entradas. Lista detalhadamente cada parcela de pagamento, quem é o paciente, o tipo de transação (ex: "Consulta" ou "Procedimento"), se está atrasado ou recebido.

### Como a conta vai parar aqui? (Liberdades e Restrições)
No fluxo ideal arquitetado no sistema, **as Receitas são geradas automaticamente através do plano de tratamento do Paciente**. Quando o doutor negocia com o paciente e cria o orçamento (ex: 5x no PIX), o módulo central capta isso e já joga 5 parcelas no "A Receber".
- **Filtros e Buscas:** Você pode buscar pelo nome do paciente, filtrar contas vencidas ou pagas, e filtrar pelo mês.
- **Mudança de Status (Se implementado via modal):** Confirmação de que o dinheiro caiu na conta.

### O que NÃO se faz:
- Não tente adulterar o valor de um orçamento de paciente vindo do prontuário por aqui. O ideal é renegociar no contrato do paciente para manter a consistência contábil (Auditoria).

---

## 4. 📤 A Pagar (Despesas)

O livro-caixa das contas da clínica (água, luz, compra de luvas, salário de dentista).

### O que essa tela faz?
Lista os boletos e obrigações da clínica. Tem uma separação clara por Categoria (ex: Aluguel, Materiais, Repasse de Profissionais).

### Como a conta vai parar aqui?
1. **Manualmente:** Quando a recepcionista ou o administrador clica para lançar uma compra avulsa (Ex: "Compramos pó de café"). *(Nota: se os botões explícitos foram ocultados da UI no MVP, isso se faz via aba Configurações nas regras recorrentes)*.
2. **Via Despesa Recorrente:** Cadastrada na aba "Configurações". O sistema todo dia meia-noite lê as configurações e "gera" os boletos do mês automaticamente aqui no "A Pagar".

### Limitações:
- Se você deletar uma conta de "Luz" gerada, o sistema entende que você cancelou aquela fatura.

---

## 5. 🧮 DRE (Demonstrativo do Resultado do Exercício)

O relatório máximo de saúde financeira, para o sócio / dono da clínica.

### O que essa tela faz?
Separa o balanço fatiado de forma contábil de verdade:
> Receita Bruta
> (-) Descontos / Impostos
> (=) Receita Líquida
> (-) Custos Variáveis (O que gasta junto com o procedimento: Materiais, Resinas, Comissão de Dentista)
> (=) Margem Bruta
> (-) Despesas Fixas (O que gasta independente se houver paciente ou não: Aluguel, Sistema, Recepção)
> (=) Lucro Líquido

### O que tem lá dentro?
- Tabela de árvore (Você pode clicar na setinha para expandir e ver de onde veio os 15% gastos com materiais).
- Comparativo: Mostra a coluna "Mês Anterior" para você ver se seu custo fixo subiu ou caiu em porcentagem (%).

### O que NÃO dá para fazer lá? (IMPORTANTE)
**O DRE é completamente travado (Read-Only).** Você não altera NENHUM número dentro do DRE. Ele é calculado **por competência**. Ou seja:
- Se um paciente pagou R$ 10.000,00 adiantados em PIX pelo tratamento de 1 ano, no Fluxo de Caixa aparecerá +R$ 10.000. Mas no DRE do mês atual só aparecerá a proporção do tratamento feito naquele mês! O DRE blinda você da falsa sensação de "ter dinheiro em caixa" e mostrar se a sua operação daquele mês foi rentável.

---

## 6. 📊 Relatórios Específicos

Relatórios avançados para gestão e repasse. É dividida em 4 sub-abas:

1. **Comissões:** Permite você selecionar "Dentista X" no "Mês Y". O sistema agrupa todos os procedimentos que o dentista fez (e que já foram efetivamente pagos pelo paciente) e calcula a comissão usando a "Regra de Comissão" aplicada a ele.
2. **Despesas (Gráfico Cascata):** Mostra aonde foi seu dinheiro, num gráfico visual separado pelas suas Categorias.
3. **Faturamento por Convênio:** Quanto a clínica recebeu dividindo por Bradesco Odonto, Unimed, Amil, Particular, etc.
4. **Ticket Médio:** Pega toda a sua receita e divide pela quantidade de pacientes que vieram no mês, dizendo "cada paciente, em média, gasta R$ 850,00 quando pisa aqui".

### Ações Possíveis:
- **Exportação CSV:** Nas abas de Comissões e Convênio, possui o botão "Baixar CSV" no canto superior que puxa a planilha formatada para enviar pro contador ou analisar no Excel.

---

## 7. 🏪 Caixa (Cash Register / Operador)

O módulo do recepcionista para lidar com dinheiro físico e maquininha do balcão na clínica.

### O que essa tela faz?
Organiza sessões "Abrir Caixa" de manhã e "Fechar Caixa" a noite. Mostra exatamente as movimentações no escopo fechado de um dia.

### Ações e Botões:
- **Abrir Caixa:** Informar com quanto de dinheiro o caixa amanheceu na gaveta.
- **Sangria (Retirada):** Quando o caminhão de água vem e a recepcionista precisa tirar R$ 40 do caixa em dinheiro, ela clica ali e justifica.
- **Suprimento (Adição):** Quando o administrador colocar "trocado" de moedas no caixa.
- **Fechar Caixa:** Função final. A recepcionista informa quanto contou na gaveta. Se o sistema registrou R$ 100 de atendimento, e a gaveta tem R$ 90, o sistema fechará com alerta vermelho (Quebra de R$ -10).

### Limites:
- Só se atende um caixa "Aberto" por operador. É cravado no usuário logado.
- Fechar o caixa finaliza a sessão. É impossível alterar uma entrada de paciente na maquininha depois do caixa ser congelado (precisa de estorno administrador).

---

## 8. ⚙️ Configurações (Financial Settings)

O coração e "motor" de cálculos da contabilidade do BeClinic. Diferente da tela de A Pagar, aqui você configura coisas que "iniciam processos por debaixo dos panos".

1. **Regras de Comissão:**
   - **O que faz:** Botão "Adicionar Regra". Você seleciona um Dentista e diz: *"Cobre 30% do valor Recebido"*, ou *"Pague um valor Fixo de R$ 50"*.
   - **Lógica:** A partir daí, **qualquer** procedimento que envolver aquele dentista passará pelo `CommissionCalculator` e cairá na aba de Relatórios. Sem essa regra configurada aqui, o cálculo na aba "Relatórios > Comissão" não funcionará.
   - **Limites:** Pode-se cadastrar regras conflitantes? O sistema usa prioridade: "Regra para o procedimento específico" ganha da "Regra geral 30%".

2. **Despesas Recorrentes:**
   - **O que faz:** Botão "Adicionar Despesa". Exemplo: Aluguel R$ 5000 todo dia 10. Você escreve e salva.
   - **Lógica:** Todo santo dia, às 00:00 (meia-noite), o servidor da BeClinic confere essa configuração. Se faltar dias para o Dia 10 do Aluguel, ele silenciosamente criará um boleto da aba **"A Pagar"**.
   - **Por que isso fica em Configurações?** Porque isso não é você pagando um boleto. É o sistema fabricando boletos para o seu futuro. Quando você exclui uma Despesa Recorrente aqui, os boletos *antigos* que já foram gerados não somem, apenas não serão gerados novos nos meses que virão.

---

> _**Dica de Fluxo Maestro:**_ Cadastre suas "Contas de Banco" e suas "Regras de Comissão" no primeiro dia. Treine sua recepção a operar a página "Caixa" e gerar os tratamentos no escopo do "Paciente". Observe os relatórios DRE e Dashboard tomarem vida de forma mágica, centralizada e blindada sem precisar gastar horas fechando planilhas!
# Especificação Técnica de Gráficos — Módulo Financeiro BeClinic [HISTÓRICO V1]

> ⚠️ **Esta especificação de 18 gráficos é HISTÓRICA (V1).** A V2 entregue em produção tem **6 charts curados** (decisão "premium sem fricção" — Mamedes, 2026-05-11):
>
> | Chart V2 entregue | Localização | Endpoint |
> |---|---|---|
> | Fluxo de Caixa Diário (line, 3 séries) | Dashboard > Análises | `/v2/reports/cash_flow_chart` |
> | Composição de Receita (donut top 5) | Dashboard > Análises | `/v2/reports/revenue_composition` |
> | Aging Inadimplência (h-bar 4 faixas) | Dashboard > Análises | `/v2/reports/delinquency_aging` |
> | Receita por Profissional (h-bar top 5) | Dashboard > Análises | `/v2/reports/revenue_by_professional` |
> | Projeção Fluxo de Caixa (line forward 60d) | Dashboard > Previsões | `/v2/reports/cash_flow_projection` |
> | Tendência de Inadimplência (line 12 meses) | Dashboard > Previsões | `/v2/reports/delinquency_trend` |
>
> Mais **sparklines SVG** mini-line inline em 4 KPIs (saldo, entradas, saídas).
>
> Charts **descartados intencionalmente** da spec original V1 de 18 (over-engineering pra clínica SMB):
> - DRE Waterfall (duplica a página DRE)
> - Heatmap agenda (pertence ao módulo Agenda)
> - CAC/ROI por canal (overlap com marketing)
> - Funnel completo, cohort retention, etc.
>
> **Para a verdade atual dos gráficos:** veja o código em [`plugins/financial/frontend/features/financial/v2/components/charts/`](../../../plugins/financial/frontend/features/financial/v2/components/charts/).
>
> O conteúdo abaixo foi preservado por valor histórico (mostra o brainstorm original de gráficos).

> **18 gráficos · 4 ondas · Pronto para implementação**
>
> Para cada gráfico estão documentados: componente Vue, endpoint Rails, lógica de query SQL, shape do payload JSON, configuração Chart.js e regras de alerta. Implemente na ordem das ondas — os gráficos de Onda 1 dependem apenas das migrations básicas, enquanto os de Onda 4 requerem dados históricos e integrações externas.

---

## Índice

| # | Gráfico | Tipo | Componente | Onda | Categoria |
|---|---------|------|-----------|------|-----------|
| 1 | Fluxo de caixa diário | Barras + linha acumulada | `CashFlowChart.vue` | 1 — MVP | Visão em tempo real |
| 2 | Receita vs meta mensal | Gauge + linha de progresso | `RevenueGoalGauge.vue` | 1 — MVP | Visão em tempo real |
| 3 | KPI cards com sparkline | 4 cards + mini sparkline | `FinancialKpiCards.vue` | 1 — MVP | Visão em tempo real |
| 4 | Projeção de caixa 30/60/90 dias | Linha com faixa de incerteza | `CashFlowProjection.vue` | 2 — Relatórios | Previsão e controle |
| 5 | A receber por semana | Barras agrupadas por forma de pagamento | `ReceivablesByWeek.vue` | 2 — Relatórios | Previsão e controle |
| 6 | Aging de inadimplência | Barras horizontais por faixa | `DelinquencyAging.vue` | 2 — Relatórios | Inadimplência |
| 7 | Evolução da inadimplência | Linha dupla (valor + % receita) | `DelinquencyTrend.vue` | 2 — Relatórios | Inadimplência |
| 8 | Inadimplência por profissional | Barras horizontais rankeadas | `DelinquencyByProfessional.vue` | 2 — Relatórios | Inadimplência |
| 9 | DRE em cascata (waterfall) | Waterfall chart | `DreWaterfallChart.vue` | 3 — DRE | Receita e rentabilidade |
| 10 | Ticket médio com tendência | Linha + regressão linear | `AverageTicketTrend.vue` | 3 — DRE | Receita e rentabilidade |
| 11 | Receita por profissional | Barras agrupadas horizontais | `RevenueByProfessional.vue` | 3 — DRE | Receita e rentabilidade |
| 12 | Composição de receita | Donut + barras empilhadas | `RevenueComposition.vue` | 3 — DRE | Receita e rentabilidade |
| 13 | Despesas por categoria | Barras horizontais rankeadas | `ExpensesByCategory.vue` | 3 — DRE | Custos e despesas |
| 14 | Fixo vs variável | Área empilhada + linha receita | `FixedVsVariableCosts.vue` | 3 — DRE | Custos e despesas |
| 15 | Funil de conversão | Funil horizontal | `ConversionFunnel.vue` | 4 — Avançado | Operacional e comercial |
| 16 | Heatmap de agenda | Grid calor dias × horários | `AgendaHeatmap.vue` | 4 — Avançado | Operacional e comercial |
| 17 | Novos vs recorrentes | Barras empilhadas + linha % | `NewVsReturningPatients.vue` | 4 — Avançado | Operacional e comercial |
| 18 | CAC e ROI por canal | Barras agrupadas + linha ROI | `MarketingRoiByChannel.vue` | 4 — Avançado | Operacional e comercial |

---

## Onda 1 — MVP

> Gráficos que o gestor precisa no primeiro dia. Dependem apenas das migrations básicas da Onda 1.

---

### Gráfico 1 — Fluxo de caixa diário

> 🔴 **PRIORIDADE CRÍTICA**

**Tipo:** Barras empilhadas + linha de saldo acumulado (Chart.js — tipo `mixed`)

**Insight para o gestor:**
É o gráfico mais consultado diariamente. Mostra entradas, saídas e saldo acumulado dia a dia no mês corrente. O gestor vê em segundos se o caixa vai negativar antes dos próximos vencimentos — permitindo ação preventiva como acionar cobrança ou renegociar prazo de fornecedor.

| Campo | Especificação |
|-------|--------------|
| **Componente Vue** | `CashFlowChart.vue` |
| **Localização** | `features/financial/components/CashFlowChart.vue` |
| **Endpoint Rails** | `GET /api/v1/accounts/financial/cash_flow?start_date=&end_date=&bank_account_id=` |
| **Eixo X** | Dias do mês (1 a 31) |
| **Eixo Y esquerdo** | Valor em R$ (entradas como barras verdes, saídas como barras vermelhas) |
| **Eixo Y direito** | Saldo acumulado em R$ (linha azul) |
| **Cores** | Entradas: `#10B981` · Saídas: `#EF4444` · Saldo acumulado: `#3B82F6` (linha, espessura 2px) |
| **Filtros** | Período (mês/semana), Conta bancária, Todas as contas consolidadas |
| **Service Rails** | `app/services/financial/cash_flow_calculator.rb` |

**Lógica de query SQL:**

```sql
-- Entradas
SELECT date(received_at) AS day, SUM(amount) AS entradas
FROM account_transactions
WHERE entry_type = 'entrada' AND status = 'recebido'
GROUP BY day

-- Saídas
SELECT date(paid_at) AS day, SUM(amount) AS saidas
FROM account_transactions
WHERE entry_type = 'saida' AND status = 'pago'
GROUP BY day

-- saldo_acumulado: calcular como running SUM no Ruby (CashFlowCalculator) ou no frontend
```

**Shape do payload JSON:**

```json
[
  { "date": "2026-03-01", "entradas": 4500.00, "saidas": 1200.00, "saldo_acumulado": 3300.00 },
  { "date": "2026-03-02", "entradas": 2100.00, "saidas": 800.00,  "saldo_acumulado": 4600.00 }
]
```

**Configuração Chart.js:**

```javascript
{
  type: 'bar',
  datasets: [
    { label: 'Entradas', type: 'bar',  data: [...], backgroundColor: '#10B981', stack: 'a' },
    { label: 'Saidas',   type: 'bar',  data: [...], backgroundColor: '#EF4444', stack: 'a' },
    { label: 'Saldo',    type: 'line', data: [...], borderColor: '#3B82F6', tension: 0.3, yAxisID: 'y2' }
  ],
  options: {
    scales: {
      y:  { stacked: true },
      y2: { position: 'right', grid: { drawOnChartArea: false } }
    }
  }
}
```

**Alertas e estados especiais:**
Exibir linha horizontal vermelha tracejada no saldo zero. Se `saldo_acumulado` projetado ficar negativo em algum dia futuro do mês, mostrar badge de alerta vermelho acima do gráfico.

---

### Gráfico 2 — Receita vs meta mensal

> 🔴 **PRIORIDADE CRÍTICA**

**Tipo:** Gauge semicircular + linha de progresso diário (Chart.js doughnut customizado)

**Insight para o gestor:**
O dono da clínica precisa saber em 2 segundos se o mês está bom. O gauge mostra percentual da meta atingida até hoje. A linha de progresso mostra o ritmo: se hoje é dia 20 e atingimos só 55% da meta, estamos abaixo do ritmo necessário (66%). Esse delta de ritmo é o número mais importante.

| Campo | Especificação |
|-------|--------------|
| **Componente Vue** | `RevenueGoalGauge.vue` |
| **Localização** | `features/financial/components/RevenueGoalGauge.vue` |
| **Endpoint Rails** | `GET /api/v1/accounts/financial/revenue_goal?month=2026-03` |
| **Eixo X** | Gauge: arco de 0% a 100% · Linha: dias do mês |
| **Eixo Y esquerdo** | Gauge: percentual · Linha: R$ acumulado vs linha de meta ideal (`meta / 31 * dia`) |
| **Eixo Y direito** | N/A |
| **Cores** | 0–60%: `#EF4444` · 60–85%: `#F59E0B` · 85–100%: `#10B981` · Linha meta ideal: tracejada `#94A3B8` |
| **Filtros** | Mês/ano (default: mês corrente) |
| **Service Rails** | `app/services/financial/revenue_goal_calculator.rb` |

**Lógica de query SQL:**

```sql
SELECT SUM(amount) AS receita_realizada
FROM account_transactions
WHERE entry_type = 'entrada'
  AND status = 'recebido'
  AND MONTH(received_at) = :month
-- JOIN accounts.monthly_goal para buscar a meta configurada
```

**Shape do payload JSON:**

```json
{
  "meta": 50000.00,
  "realizado": 31500.00,
  "percentual": 63.0,
  "ritmo_ideal": 32258.06,
  "delta_ritmo": -758.06,
  "dias_restantes": 11
}
```

**Configuração Chart.js:**

```javascript
// Gauge = doughnut com rotation e circumference customizados
{
  type: 'doughnut',
  data: {
    datasets: [{
      data: [percentual, 100 - percentual],
      backgroundColor: [corDoGauge(percentual), '#F1F5F9'],
      borderWidth: 0
    }]
  },
  options: {
    rotation: -90,
    circumference: 180,
    cutout: '75%',
    plugins: { legend: { display: false } }
  }
}
// Texto central: renderizar via plugin customizado ou HTML absoluto sobre o canvas
```

**Alertas e estados especiais:**
Se `delta_ritmo` for negativo E `dias_restantes` < 10, exibir alerta: `"Faltam R$ X para bater a meta em N dias."`

---

### Gráfico 3 — KPI cards com sparkline do dia

> 🔴 **PRIORIDADE CRÍTICA**

**Tipo:** 4 cards com mini sparkline (Chart.js line, height 40px)

**Insight para o gestor:**
Quatro números que o gestor lê assim que abre o financeiro: Entradas hoje, Saídas hoje, Saldo do dia e Inadimplência total vencida. Cada card tem uma sparkline dos últimos 7 dias para contexto imediato. Variação percentual vs dia anterior (seta verde/vermelha).

| Campo | Especificação |
|-------|--------------|
| **Componente Vue** | `FinancialKpiCards.vue` |
| **Localização** | `features/financial/components/FinancialKpiCards.vue` |
| **Endpoint Rails** | `GET /api/v1/accounts/financial/dashboard_kpis` |
| **Visual** | 4 cards: Entradas hoje (verde), Saídas hoje (vermelho), Saldo do dia (azul), Inadimplência total (âmbar) |
| **Filtros** | Sem filtro — sempre mostra o dia corrente |
| **Service Rails** | `app/services/financial/dashboard_kpi_service.rb` |

**Lógica de query SQL:**

```sql
-- (1) Entradas hoje
SELECT SUM(amount) FROM account_transactions
WHERE entry_type = 'entrada' AND status = 'recebido' AND DATE(received_at) = CURDATE()

-- (2) Saídas hoje
SELECT SUM(amount) FROM account_transactions
WHERE entry_type = 'saida' AND status = 'pago' AND DATE(paid_at) = CURDATE()

-- (3) Saldo atual
SELECT initial_balance + SUM(entradas) - SUM(saidas) FROM bank_accounts WHERE account_id = :id

-- (4) Inadimplência total
SELECT SUM(amount) FROM installments WHERE status = 'pendente' AND due_date < CURDATE()

-- Sparklines: mesmas queries agrupadas por day para os últimos 7 dias
```

**Shape do payload JSON:**

```json
{
  "entradas_hoje": 3200.00,
  "entradas_variacao": 12.5,
  "saidas_hoje": 800.00,
  "saidas_variacao": -3.2,
  "saldo_dia": 2400.00,
  "inadimplencia_total": 12400.00,
  "sparklines": {
    "entradas":     [2100, 3800, 2900, 4100, 2700, 3500, 3200],
    "saidas":       [900, 1200, 750, 1100, 800, 850, 800],
    "saldo":        [24000, 26600, 28750, 31750, 33650, 36300, 38700],
    "inadimplencia":[11200, 11500, 11900, 12100, 12000, 12300, 12400]
  }
}
```

**Configuração Chart.js (sparkline — igual para os 4 cards):**

```javascript
{
  type: 'line',
  options: {
    responsive: true,
    maintainAspectRatio: false,
    scales: {
      x: { display: false },
      y: { display: false }
    },
    plugins: {
      legend:  { display: false },
      tooltip: { enabled: false }
    },
    elements: {
      point: { radius: 0 },
      line:  { tension: 0.4, borderWidth: 1.5 }
    }
  }
}
// Wrapper div: width 100%, height 40px
```

**Alertas e estados especiais:**
Badge vermelho no card de inadimplência se valor > threshold configurado nas settings financeiras.

---

## Onda 2 — Relatórios

> Dependem de dados históricos (mínimo 30 dias de uso). Implementar após Onda 1 estabilizada.

---

### Gráfico 4 — Projeção de caixa 30/60/90 dias

> 🟡 **ALTA PRIORIDADE**

**Tipo:** Linha com faixa de incerteza (área entre cenário otimista e pessimista)

**Insight para o gestor:**
O gráfico mais preditivo do sistema. Plota o saldo projetado com base em todas as contas a receber e a pagar em aberto, mais as despesas recorrentes com `next_occurrence_date`. A faixa de incerteza cresce com o tempo porque eventos futuros têm menor certeza. O gestor vê ANTES se o caixa vai negativar — tempo para renegociar prazo, acionar cobrança ou buscar antecipação de recebíveis.

| Campo | Especificação |
|-------|--------------|
| **Componente Vue** | `CashFlowProjection.vue` |
| **Localização** | `features/financial/components/CashFlowProjection.vue` |
| **Endpoint Rails** | `GET /api/v1/accounts/financial/cash_flow_projection?horizon=30&bank_account_id=` |
| **Eixo X** | Dias (próximos 30, 60 ou 90 dias — botão toggle) |
| **Eixo Y** | Saldo projetado em R$ |
| **Cores** | Linha central: `#3B82F6` · Área de incerteza: `#3B82F620` · Linha zero: tracejada `#EF4444` · Pontos de vencimento: marcadores `#F59E0B` |
| **Filtros** | Horizonte: 30 / 60 / 90 dias · Conta bancária |
| **Service Rails** | `app/services/financial/cash_flow_projection_service.rb` |

**Lógica de projeção (Ruby — CashFlowProjectionService):**

```
saldo_inicial = saldo_atual das contas

Para cada dia futuro no horizonte:
  + installments.amount onde due_date = dia (receitas esperadas)
  - account_transactions.amount onde entry_type = 'saida' e due_date = dia
  - recurring_expenses projetadas via next_occurrence_date e frequency

Cenário otimista:  assume 100% das receitas sendo pagas
Cenário pessimista: desconta taxa histórica de inadimplência (últimos 3 meses)
```

**Shape do payload JSON:**

```json
{
  "atual": 28000.00,
  "projecao": [
    { "date": "2026-03-26", "central": 26400.00, "otimista": 28100.00, "pessimista": 24300.00 },
    { "date": "2026-03-27", "central": 25800.00, "otimista": 27900.00, "pessimista": 23500.00 }
  ]
}
```

**Configuração Chart.js:**

```javascript
{
  type: 'line',
  datasets: [
    { label: 'Projecao central', data: central,   borderColor: '#3B82F6', fill: false },
    { label: 'Otimista',         data: otimista,   borderColor: 'transparent', fill: '+1', backgroundColor: '#3B82F620' },
    { label: 'Pessimista',       data: pessimista, borderColor: 'transparent', fill: false },
  ]
}
// Linha zero: dataset adicional constante em 0 com borderDash: [4, 4], borderColor: '#EF4444'
```

**Alertas e estados especiais:**
Se linha central cruzar zero em qualquer ponto do horizonte: exibir alerta vermelho `"Saldo projetado negativo em DD/MM — tome ação agora."`

---

### Gráfico 5 — A receber por semana (próximos 30 dias)

**Tipo:** Barras agrupadas por forma de pagamento

**Insight para o gestor:**
Mostra quanto vai entrar semana a semana nos próximos 30 dias, separado por forma de pagamento. Permite planejar pagamentos de fornecedores sabendo antecipadamente quais semanas terão mais liquidez. PIX e dinheiro entram imediatamente; cartão crédito tem delay de 28–32 dias — a distinção é crítica para planejamento de caixa.

| Campo | Especificação |
|-------|--------------|
| **Componente Vue** | `ReceivablesByWeek.vue` |
| **Localização** | `features/financial/components/ReceivablesByWeek.vue` |
| **Endpoint Rails** | `GET /api/v1/accounts/financial/receivables_forecast?month=2026-04` |
| **Eixo X** | 4 semanas (S1, S2, S3, S4 do próximo mês) |
| **Eixo Y** | Valor em R$ |
| **Cores** | PIX/Dinheiro: `#10B981` · Cartão débito: `#3B82F6` · Cartão crédito: `#8B5CF6` · Boleto: `#F59E0B` · Convênio: `#6B7280` |
| **Filtros** | Mês de referência, Profissional, Forma de pagamento |
| **Service Rails** | `app/services/financial/receivables_forecast_service.rb` |

**Lógica de query SQL:**

```sql
SELECT
  CEIL(DAY(due_date) / 7.0) AS semana,
  payment_method,
  SUM(amount) AS total
FROM installments
WHERE status = 'pendente'
  AND due_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 30 DAY)
GROUP BY semana, payment_method
ORDER BY semana
```

**Shape do payload JSON:**

```json
[
  { "semana": "S1 (01-07)", "pix": 8200.00, "cartao_credito": 3400.00, "boleto": 1200.00, "convenio": 2100.00 },
  { "semana": "S2 (08-14)", "pix": 6100.00, "cartao_credito": 4800.00, "boleto": 900.00,  "convenio": 1800.00 }
]
```

**Configuração Chart.js:**

```javascript
{
  type: 'bar',
  datasets: [
    { label: 'PIX / Dinheiro',  data: [...], backgroundColor: '#10B981' },
    { label: 'Cartao Credito',  data: [...], backgroundColor: '#8B5CF6' },
    { label: 'Cartao Debito',   data: [...], backgroundColor: '#3B82F6' },
    { label: 'Boleto',          data: [...], backgroundColor: '#F59E0B' },
    { label: 'Convenio',        data: [...], backgroundColor: '#6B7280' },
  ],
  options: {
    scales: { x: { stacked: false }, y: { stacked: false } }
  }
}
// Tooltip customizado: mostrar total da semana + breakdown por forma de pagamento
```

---

### Gráfico 6 — Aging de inadimplência por faixa

> 🔴 **PRIORIDADE CRÍTICA**

**Tipo:** Barras horizontais com gradiente de cor por risco

**Insight para o gestor:**
A view mais importante para gestão de risco de crédito. Quatro faixas de atraso — 1–30, 31–60, 61–90 e 90+ dias — com valor total e número de pacientes em cada faixa. A barra 90+ é a que tem menor probabilidade de recuperação. A cor progride do amarelo para vermelho escuro, tornando o risco visualmente óbvio. Clicar em uma faixa abre a lista de pacientes daquela faixa com botão de enviar cobrança via WhatsApp.

| Campo | Especificação |
|-------|--------------|
| **Componente Vue** | `DelinquencyAging.vue` |
| **Localização** | `features/financial/components/reports/DelinquencyAging.vue` |
| **Endpoint Rails** | `GET /api/v1/accounts/financial/delinquency_aging` |
| **Eixo X** | Valor em R$ (barras horizontais) |
| **Eixo Y** | Faixas: 1–30 dias, 31–60, 61–90, 90+ |
| **Label direito** | Nº de pacientes e % do total inadimplente |
| **Cores** | 1–30d: `#FCD34D` · 31–60d: `#F97316` · 61–90d: `#EF4444` · 90+d: `#991B1B` |
| **Filtros** | Profissional, Especialidade, Período de corte |
| **Service Rails** | `app/services/financial/delinquency_calculator.rb` |

**Lógica de query SQL:**

```sql
SELECT
  CASE
    WHEN DATEDIFF(CURDATE(), due_date) BETWEEN 1  AND 30 THEN '1-30 dias'
    WHEN DATEDIFF(CURDATE(), due_date) BETWEEN 31 AND 60 THEN '31-60 dias'
    WHEN DATEDIFF(CURDATE(), due_date) BETWEEN 61 AND 90 THEN '61-90 dias'
    ELSE '90+ dias'
  END AS faixa,
  COUNT(DISTINCT patient_id) AS pacientes,
  SUM(amount) AS total
FROM installments
WHERE status = 'pendente' AND due_date < CURDATE()
GROUP BY faixa
ORDER BY MIN(DATEDIFF(CURDATE(), due_date))
```

**Shape do payload JSON:**

```json
[
  { "faixa": "1-30 dias",  "valor": 8400.00,  "pacientes": 12, "percentual": 32.1 },
  { "faixa": "31-60 dias", "valor": 5200.00,  "pacientes": 7,  "percentual": 19.8 },
  { "faixa": "61-90 dias", "valor": 4100.00,  "pacientes": 5,  "percentual": 15.6 },
  { "faixa": "90+ dias",   "valor": 8500.00,  "pacientes": 9,  "percentual": 32.5 }
]
```

**Configuração Chart.js:**

```javascript
{
  type: 'bar',
  indexAxis: 'y',
  datasets: [{
    data: [8400, 5200, 4100, 8500],
    backgroundColor: ['#FCD34D', '#F97316', '#EF4444', '#991B1B'],
    borderRadius: 4
  }],
  options: {
    plugins: { legend: { display: false } },
    scales: {
      x: { ticks: { callback: v => 'R$ ' + v.toLocaleString('pt-BR') } }
    },
    onClick: (e, elements) => { /* abre lista de pacientes da faixa clicada */ }
  }
}
```

**Alertas e estados especiais:**
Total de inadimplência exibido no topo do card. Se total > threshold configurado nas settings, card com borda vermelha e texto `"Atenção: inadimplência acima do limite configurado."`

---

### Gráfico 7 — Evolução da inadimplência mensal

**Tipo:** Linha dupla (valor absoluto em barras + % sobre receita em linha)

**Insight para o gestor:**
Tendência da inadimplência nos últimos 12 meses. O insight crítico: se a porcentagem sobe mesmo com receita crescendo, há um problema de política de crédito — a clínica está vendendo para pacientes que não pagam. Esse gráfico separa o crescimento real do crescimento problemático.

| Campo | Especificação |
|-------|--------------|
| **Componente Vue** | `DelinquencyTrend.vue` |
| **Localização** | `features/financial/components/reports/DelinquencyTrend.vue` |
| **Endpoint Rails** | `GET /api/v1/accounts/financial/delinquency_trend?months=12` |
| **Eixo X** | Últimos 12 meses |
| **Eixo Y esquerdo** | Valor inadimplente em R$ (barras) |
| **Eixo Y direito** | % sobre receita bruta (linha, escala 0–20%) |
| **Cores** | Barras: `#FCA5A5` · Linha %: `#DC2626` (espessura 2px) · Linha referência 5%: tracejada cinza |
| **Filtros** | Profissional |
| **Service Rails** | `app/services/financial/delinquency_calculator.rb` (método `trend`) |

**Lógica de query SQL:**

```sql
-- Para cada mês dos últimos 12:
SELECT
  DATE_FORMAT(due_date, '%Y-%m') AS mes,
  SUM(i.amount) AS valor_inadimplente,
  (SELECT SUM(amount) FROM account_transactions
   WHERE entry_type = 'entrada' AND status = 'recebido'
   AND DATE_FORMAT(received_at, '%Y-%m') = mes) AS receita_bruta
FROM installments i
WHERE status = 'pendente' AND due_date < CURDATE()
GROUP BY mes
ORDER BY mes
-- percentual calculado no Ruby: valor_inadimplente / receita_bruta * 100
```

**Shape do payload JSON:**

```json
[
  { "mes": "2025-04", "valor_inadimplente": 6200.00,  "receita_bruta": 44000.00, "percentual": 14.1 },
  { "mes": "2025-05", "valor_inadimplente": 7100.00,  "receita_bruta": 46000.00, "percentual": 15.4 },
  { "mes": "2026-03", "valor_inadimplente": 8400.00,  "receita_bruta": 48000.00, "percentual": 17.5 }
]
```

**Configuração Chart.js:**

```javascript
{
  type: 'bar',
  datasets: [
    { type: 'bar',  label: 'Inadimplencia R$', data: [...], backgroundColor: '#FCA5A5', yAxisID: 'y' },
    { type: 'line', label: '% da Receita',     data: [...], borderColor: '#DC2626', tension: 0.3, yAxisID: 'y2' },
  ],
  options: {
    scales: {
      y2: { position: 'right', ticks: { callback: v => v + '%' } }
    }
  }
}
```

**Alertas e estados especiais:**
Se `percentual` do mês atual > `media_12_meses * 1.3` (30% acima da média histórica), exibir badge âmbar no card.

---

### Gráfico 8 — Inadimplência por profissional

**Tipo:** Barras horizontais rankeadas com % da produção

**Insight para o gestor:**
Qual profissional tem a carteira com maior inadimplência em valor absoluto e como percentual da sua produção. Um profissional com 25% de inadimplência pode estar concedendo descontos excessivos, não cobrando entrada, ou atendendo um perfil de paciente com maior risco. É um dado de gestão de carteira e de política comercial.

| Campo | Especificação |
|-------|--------------|
| **Componente Vue** | `DelinquencyByProfessional.vue` |
| **Localização** | `features/financial/components/reports/DelinquencyByProfessional.vue` |
| **Endpoint Rails** | `GET /api/v1/accounts/financial/delinquency_by_professional?period=2026-03` |
| **Eixo X** | Valor inadimplente em R$ |
| **Eixo Y** | Nome do profissional (ordenado do maior para o menor percentual) |
| **Label** | % da produção ao lado de cada barra |
| **Cores** | Verde `#10B981` se < 5% · Amarelo `#F59E0B` se 5–15% · Vermelho `#EF4444` se > 15% |
| **Filtros** | Período, Especialidade |
| **Service Rails** | `app/services/financial/delinquency_calculator.rb` |

**Lógica de query SQL:**

```sql
SELECT
  u.name AS nome,
  SUM(i.amount) AS inadimplente,
  (SELECT SUM(amount) FROM account_transactions
   WHERE professional_id = at.professional_id
   AND entry_type = 'entrada' AND MONTH(received_at) = :month) AS producao
FROM installments i
JOIN account_transactions at ON i.transaction_id = at.id
JOIN users u ON at.professional_id = u.id
WHERE i.status = 'pendente' AND i.due_date < CURDATE()
GROUP BY at.professional_id
ORDER BY (inadimplente / producao) DESC
```

**Shape do payload JSON:**

```json
[
  { "professional_id": 1, "nome": "Dr. João",  "inadimplente": 3200.00, "producao": 18000.00, "percentual": 17.8 },
  { "professional_id": 2, "nome": "Dra. Ana",  "inadimplente": 1100.00, "producao": 22000.00, "percentual": 5.0  },
  { "professional_id": 3, "nome": "Dr. Pedro", "inadimplente": 400.00,  "producao": 14000.00, "percentual": 2.9  }
]
```

**Configuração Chart.js:**

```javascript
{
  type: 'bar',
  indexAxis: 'y',
  datasets: [{
    data: valores,
    backgroundColor: valores.map(v =>
      v.percentual < 5  ? '#10B981' :
      v.percentual < 15 ? '#F59E0B' : '#EF4444'
    ),
    borderRadius: 4
  }],
  options: { plugins: { legend: { display: false } } }
}
// Plugin customizado para label externo com percentual ao lado de cada barra
```

---

## Onda 3 — DRE

> Dependem do `competence_date` populado corretamente em todos os lançamentos. Implementar após Onda 2.

---

### Gráfico 9 — DRE em cascata (waterfall)

> ⭐ **ALTA DIFERENCIAÇÃO** — Nenhum concorrente direto implementa isso de forma visual.

**Tipo:** Waterfall chart — Chart.js com dataset de barras flutuantes `[base, topo]`

**Insight para o gestor:**
A visualização mais poderosa e diferenciada do sistema. Começa na receita bruta e cada barra subtrai até chegar no resultado líquido. Ao contrário de uma tabela de linhas, o waterfall torna imediatamente visível onde a margem está sendo corroída. Se a barra de custos fixos é gigante, o problema é estrutural. Se a de marketing é desproporcional, o CAC está alto.

| Campo | Especificação |
|-------|--------------|
| **Componente Vue** | `DreWaterfallChart.vue` |
| **Localização** | `features/financial/components/DreWaterfallChart.vue` |
| **Endpoint Rails** | `GET /api/v1/accounts/financial/dre?period=2026-03&regime=competencia` |
| **Eixo X** | Linhas do DRE em sequência |
| **Eixo Y** | Valor em R$ |
| **Labels** | Percentual sobre receita bruta em cada barra |
| **Cores** | Receita bruta e subtotais: `#10B981` · Deduções e custos: `#EF4444` · Resultado negativo: `#DC2626` |
| **Filtros** | Mês/período · Regime: competência ou caixa (toggle) · Comparar com mês anterior |
| **Service Rails** | `app/services/financial/dre_calculator.rb` |

**Linhas do DRE em ordem:**

```
1. Receita bruta         (total)
2. (-) Deduções          (reducao)
3. = Receita líquida     (subtotal)
4. (-) Custos assistenciais (reducao)
5. = Margem bruta        (subtotal)
6. (-) Custos fixos      (reducao)
7. (-) Marketing         (reducao)
8. (-) Despesas financeiras (reducao)
9. (-) Impostos          (reducao)
10. = Resultado líquido  (final)
```

**Lógica de query SQL:**

```sql
SELECT dre_line, SUM(amount) AS total
FROM account_transactions
WHERE competence_date BETWEEN :start AND :end
  AND account_id = :account_id
GROUP BY dre_line
ORDER BY dre_line_order
-- subtotais e percentuais calculados no DreCalculator (Ruby)
```

**Shape do payload JSON:**

```json
[
  { "linha": "Receita bruta",          "valor": 52000.00,  "percentual": 100.0, "tipo": "total"    },
  { "linha": "(-) Deducoes",           "valor": -3100.00,  "percentual": -6.0,  "tipo": "reducao"  },
  { "linha": "= Receita liquida",      "valor": 48900.00,  "percentual": 94.0,  "tipo": "subtotal" },
  { "linha": "(-) Custos assistenciais","valor": -14200.00, "percentual": -27.3, "tipo": "reducao"  },
  { "linha": "= Margem bruta",         "valor": 34700.00,  "percentual": 66.7,  "tipo": "subtotal" },
  { "linha": "(-) Custos fixos",       "valor": -18000.00, "percentual": -34.6, "tipo": "reducao"  },
  { "linha": "(-) Marketing",          "valor": -4200.00,  "percentual": -8.1,  "tipo": "reducao"  },
  { "linha": "(-) Desp. financeiras",  "valor": -1800.00,  "percentual": -3.5,  "tipo": "reducao"  },
  { "linha": "(-) Impostos",           "valor": -3120.00,  "percentual": -6.0,  "tipo": "reducao"  },
  { "linha": "= Resultado liquido",    "valor": 7580.00,   "percentual": 14.6,  "tipo": "final"    }
]
```

**Configuração Chart.js:**

```javascript
// Waterfall com barras flutuantes: cada barra é [base, topo]
// base = acumulado até a linha anterior; topo = base + valor da linha

{
  type: 'bar',
  datasets: [{
    data: linhas.map(l => [l.base, l.topo]),
    backgroundColor: linhas.map(l =>
      l.tipo === 'reducao'  ? '#EF4444' :
      l.tipo === 'subtotal' ? '#10B981' :
      l.tipo === 'final'    ? (l.valor >= 0 ? '#059669' : '#DC2626') :
      '#64748B'
    ),
    borderSkipped: false,
    borderRadius: 3
  }],
  options: {
    plugins: { legend: { display: false } },
    scales: { y: { ticks: { callback: v => 'R$ ' + v.toLocaleString('pt-BR') } } }
  }
}
// Linhas conectoras entre barras: renderizar via afterDraw plugin customizado
```

**Alertas e estados especiais:**
Se `resultado_liquido < 0`: card com borda vermelha e label `"Resultado negativo no período."`

---

### Gráfico 10 — Ticket médio com tendência

**Tipo:** Linha + linha de regressão linear tracejada

**Insight para o gestor:**
Ticket médio mensal dos últimos 12 meses com linha de tendência. Uma queda no ticket médio com agenda cheia é o sinal mais claro de perda de procedimentos de alto valor — implantes e ortodontia sendo substituídos por restaurações. A tendência mostra se a clínica está evoluindo ou encolhendo em valor por paciente, independente do volume.

| Campo | Especificação |
|-------|--------------|
| **Componente Vue** | `AverageTicketTrend.vue` |
| **Localização** | `features/financial/components/AverageTicketTrend.vue` |
| **Endpoint Rails** | `GET /api/v1/accounts/financial/average_ticket?months=12` |
| **Eixo X** | Últimos 12 meses |
| **Eixo Y** | Ticket médio em R$ |
| **Cores** | Linha principal: `#3B82F6` · Regressão: tracejada `#94A3B8` · Ponto mês atual: círculo `#1E40AF` |
| **Filtros** | Profissional, Especialidade, Tipo de procedimento |
| **Service Rails** | `app/services/financial/revenue_analytics_service.rb` |

**Lógica de query SQL:**

```sql
SELECT
  DATE_FORMAT(received_at, '%Y-%m') AS mes,
  SUM(amount) AS receita_total,
  COUNT(DISTINCT patient_id) AS atendimentos,
  SUM(amount) / COUNT(DISTINCT patient_id) AS ticket_medio
FROM account_transactions
WHERE entry_type = 'entrada' AND status = 'recebido'
GROUP BY mes
ORDER BY mes
LIMIT 12
```

**Shape do payload JSON:**

```json
[
  { "mes": "2025-04", "ticket_medio": 420.00, "atendimentos": 91, "receita_total": 38220.00 },
  { "mes": "2026-03", "ticket_medio": 485.00, "atendimentos": 98, "receita_total": 47530.00 }
]
```

**Configuração Chart.js:**

```javascript
{
  type: 'line',
  datasets: [
    {
      label: 'Ticket medio',
      data: ticketsMedios,
      borderColor: '#3B82F6',
      tension: 0.3,
      fill: false
    },
    {
      label: 'Tendencia',
      data: regressaoLinear(ticketsMedios), // calcular no frontend com minimos quadrados
      borderColor: '#94A3B8',
      borderDash: [5, 5],
      pointRadius: 0,
      fill: false
    }
  ]
}

// Regressão linear (frontend):
function regressaoLinear(dados) {
  const n = dados.length
  const sumX = dados.reduce((s, _, i) => s + i, 0)
  const sumY = dados.reduce((s, v) => s + v, 0)
  const sumXY = dados.reduce((s, v, i) => s + i * v, 0)
  const sumX2 = dados.reduce((s, _, i) => s + i * i, 0)
  const m = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX)
  const b = (sumY - m * sumX) / n
  return dados.map((_, i) => Math.round((m * i + b) * 100) / 100)
}
```

**Alertas e estados especiais:**
Se inclinação da regressão for negativa nos últimos 3 meses: badge âmbar `"Tendência de queda no ticket médio."`

---

### Gráfico 11 — Receita por profissional: produção vs recebido

**Tipo:** Barras agrupadas horizontais (produção, recebido, custo total)

**Insight para o gestor:**
Para cada profissional: barra da produção (procedimentos executados), barra do que foi efetivamente recebido (liquidado) e barra do custo total (folha + comissão). O gap entre produção e recebido é inadimplência atribuída àquele profissional. Esse é o gráfico que muda a conversa de "quem fatura mais" para "quem gera mais margem".

| Campo | Especificação |
|-------|--------------|
| **Componente Vue** | `RevenueByProfessional.vue` |
| **Localização** | `features/financial/components/reports/RevenueByProfessional.vue` |
| **Endpoint Rails** | `GET /api/v1/accounts/financial/revenue_by_professional?period=2026-03` |
| **Eixo X** | Valor em R$ |
| **Eixo Y** | Profissional (ordenado por margem decrescente) |
| **Cores** | Produção: `#BFDBFE` · Recebido: `#3B82F6` · Custo total: `#EF444460` |
| **Filtros** | Período, Especialidade, Unidade |
| **Service Rails** | `app/services/financial/professional_revenue_service.rb` |

**Lógica de query SQL:**

```sql
SELECT
  u.name AS nome,
  SUM(CASE WHEN at.origin = 'procedimento' THEN at.amount ELSE 0 END) AS producao,
  SUM(CASE WHEN at.status = 'recebido' THEN at.amount ELSE 0 END) AS recebido
  -- custo_total: folha proporcional + comissões (calculado no Ruby com CommissionCalculator)
FROM account_transactions at
JOIN users u ON at.professional_id = u.id
WHERE at.entry_type = 'entrada'
  AND MONTH(at.competence_date) = :month
  AND at.account_id = :account_id
GROUP BY at.professional_id
ORDER BY (recebido - custo_total) DESC
```

**Shape do payload JSON:**

```json
[
  { "professional_id": 1, "nome": "Dra. Ana",  "producao": 22000.00, "recebido": 19800.00, "custo_total": 7200.00, "margem": 12600.00, "margem_pct": 57.3 },
  { "professional_id": 2, "nome": "Dr. João",  "producao": 18000.00, "recebido": 14800.00, "custo_total": 6400.00, "margem": 8400.00,  "margem_pct": 46.7 }
]
```

**Configuração Chart.js:**

```javascript
{
  type: 'bar',
  indexAxis: 'y',
  datasets: [
    { label: 'Producao',    data: [...], backgroundColor: '#BFDBFE' },
    { label: 'Recebido',    data: [...], backgroundColor: '#3B82F6' },
    { label: 'Custo total', data: [...], backgroundColor: '#EF444460' },
  ],
  options: { scales: { x: { stacked: false } } }
}
```

**Alertas e estados especiais:**
Custo total só é preciso quando `commission_rules` estiver configurado. Exibir disclaimer se não configurado: `"Custo de comissão não incluído — configure as regras de comissão nas settings."`

---

### Gráfico 12 — Composição de receita (donut + empilhado)

**Tipo:** Donut (composição atual) + barras empilhadas mensais (evolução — dois charts lado a lado)

**Insight para o gestor:**
O donut mostra a fatia de receita por tipo no mês atual; as barras empilhadas mostram a evolução nos últimos 6 meses. Dependência excessiva de convênio é risco concentrado — se o convênio representar 70% da receita e renegociar tabela, o impacto é imediato. O gráfico torna esse risco visível antes que ele vire crise.

| Campo | Especificação |
|-------|--------------|
| **Componente Vue** | `RevenueComposition.vue` |
| **Localização** | `features/financial/components/RevenueComposition.vue` |
| **Endpoint Rails** | `GET /api/v1/accounts/financial/revenue_composition?months=6` |
| **Cores** | Particular: `#10B981` · Convênio: `#3B82F6` · Plano: `#8B5CF6` · Outros: `#94A3B8` |
| **Filtros** | Período, Profissional, Unidade |
| **Service Rails** | `app/services/financial/revenue_analytics_service.rb` |

**Shape do payload JSON:**

```json
{
  "atual": { "particular": 31200.00, "convenio": 14400.00, "plano": 4800.00, "outros": 1600.00 },
  "historico": [
    { "mes": "2025-10", "particular": 28000.00, "convenio": 15000.00, "plano": 4200.00, "outros": 1400.00 },
    { "mes": "2026-03", "particular": 31200.00, "convenio": 14400.00, "plano": 4800.00, "outros": 1600.00 }
  ]
}
```

**Configuração Chart.js:**

```javascript
// Dois charts separados no Vue via flex layout

// Donut (composição atual):
{ type: 'doughnut', options: { cutout: '65%' } }
// Valor total no centro: via plugin customizado
// centerText: { text: 'R$ 52.000', subtext: 'receita total' }

// Barras empilhadas (evolução):
{ type: 'bar', options: { scales: { x: { stacked: true }, y: { stacked: true } } } }
```

**Alertas e estados especiais:**
Se uma categoria > 60% do total: badge âmbar `"Alta concentração em [categoria] — risco de dependência."`

---

### Gráfico 13 — Despesas por categoria rankeadas

**Tipo:** Barras horizontais rankeadas com variação vs mês anterior

**Insight para o gestor:**
Top 10 categorias de despesa do mês ordenadas por valor, com seta e percentual de variação vs mês anterior. É o gráfico que mais identifica vazamentos financeiros — qualquer categoria subindo sistematicamente aparece imediatamente. Clicar em uma categoria abre os lançamentos individuais daquela categoria no período.

| Campo | Especificação |
|-------|--------------|
| **Componente Vue** | `ExpensesByCategory.vue` |
| **Localização** | `features/financial/components/reports/ExpensesByCategory.vue` |
| **Endpoint Rails** | `GET /api/v1/accounts/financial/expenses_by_category?period=2026-03&limit=10` |
| **Eixo X** | Valor em R$ |
| **Eixo Y** | Categoria de despesa (top 10, ordenadas por valor) |
| **Label** | Variação % vs mês anterior (↑ vermelho se subiu, ↓ verde se caiu) |
| **Cores** | Escala de âmbar proporcional ao valor: maior = `#92400E`, menor = `#FDE68A` |
| **Filtros** | Período, Tipo (fixo/variável) |
| **Service Rails** | `app/services/financial/expense_analytics_service.rb` |

**Lógica de query SQL:**

```sql
SELECT
  fc.name AS categoria,
  SUM(at.amount) AS total,
  (SELECT SUM(amount) FROM account_transactions at2
   WHERE at2.financial_category_id = at.financial_category_id
   AND MONTH(at2.paid_at) = MONTH(:period) - 1) AS total_anterior
FROM account_transactions at
JOIN financial_categories fc ON at.financial_category_id = fc.id
WHERE at.entry_type = 'saida'
  AND MONTH(at.paid_at) = MONTH(:period)
  AND at.account_id = :account_id
GROUP BY at.financial_category_id
ORDER BY total DESC
LIMIT 10
-- variacao_pct calculada no Ruby: (total - total_anterior) / total_anterior * 100
```

**Shape do payload JSON:**

```json
[
  { "categoria": "Salarios",    "total": 18000.00, "total_anterior": 17500.00, "variacao_pct": 2.9  },
  { "categoria": "Aluguel",     "total": 8500.00,  "total_anterior": 8500.00,  "variacao_pct": 0.0  },
  { "categoria": "Materiais",   "total": 4200.00,  "total_anterior": 3100.00,  "variacao_pct": 35.5 },
  { "categoria": "Laboratorio", "total": 3800.00,  "total_anterior": 3900.00,  "variacao_pct": -2.6 }
]
```

**Configuração Chart.js:**

```javascript
{
  type: 'bar',
  indexAxis: 'y',
  datasets: [{
    data: totais,
    backgroundColor: escalaAmbar(totais), // interpolação entre #FDE68A e #92400E
    borderRadius: 4
  }],
  options: {
    plugins: { legend: { display: false } },
    onClick: (e, elements) => { /* abre drill-down da categoria */ }
  }
}
// Variação: renderizar como labels customizados via afterDatasetsDraw plugin
```

**Alertas e estados especiais:**
Se alguma categoria variou > 20% positivamente vs mês anterior: borda âmbar na barra e tooltip `"Aumento de X% — clique para ver lançamentos."`

---

### Gráfico 14 — Fixo vs variável ao longo do tempo

**Tipo:** Área empilhada mensal + linha de receita sobreposta

**Insight para o gestor:**
Mostra a evolução dos custos fixos e variáveis mês a mês, com a linha de receita sobreposta. O insight estrutural: se a área de custos fixos cresce mais rápido que a linha de receita, a clínica está numa trajetória de compressão de margem — antecipa uma crise antes que aconteça.

| Campo | Especificação |
|-------|--------------|
| **Componente Vue** | `FixedVsVariableCosts.vue` |
| **Localização** | `features/financial/components/FixedVsVariableCosts.vue` |
| **Endpoint Rails** | `GET /api/v1/accounts/financial/cost_structure?months=12` |
| **Eixo X** | Últimos 12 meses |
| **Eixo Y esquerdo** | Valor em R$ (áreas empilhadas) |
| **Eixo Y direito** | Receita em R$ (linha) |
| **Cores** | Área fixo: `#FCA5A5` · Área variável: `#FED7AA` · Linha receita: `#10B981` (espessura 2px) |
| **Service Rails** | `app/services/financial/expense_analytics_service.rb` |

**Shape do payload JSON:**

```json
[
  { "mes": "2025-04", "fixo": 25000.00, "variavel": 12000.00, "receita": 44000.00 },
  { "mes": "2026-03", "fixo": 28000.00, "variavel": 14000.00, "receita": 52000.00 }
]
```

**Configuração Chart.js:**

```javascript
{
  type: 'bar',
  datasets: [
    { type: 'bar',  label: 'Custos fixos',     data: [...], backgroundColor: '#FCA5A5', stack: 's' },
    { type: 'bar',  label: 'Custos variaveis', data: [...], backgroundColor: '#FED7AA', stack: 's' },
    { type: 'line', label: 'Receita',           data: [...], borderColor: '#10B981', yAxisID: 'y2', fill: false }
  ]
}
```

---

## Onda 4 — Avançado

> Requerem dados históricos maduros (mínimo 3 meses) e, para os gráficos 16–18, integrações externas.

---

### Gráfico 15 — Funil de conversão completo

**Tipo:** Funil horizontal com taxa de conversão entre etapas

**Insight para o gestor:**
O gráfico diagnóstico mais valioso para gestão comercial. A queda em cada etapa indica onde está o problema: no-show alto = falta de confirmação; queda entre orçado e fechado = preço ou apresentação; queda entre lead e agendado = processo de recepção. Permite ação cirúrgica no gargalo correto.

| Campo | Especificação |
|-------|--------------|
| **Componente Vue** | `ConversionFunnel.vue` |
| **Localização** | `features/financial/components/ConversionFunnel.vue` |
| **Endpoint Rails** | `GET /api/v1/accounts/financial/conversion_funnel?period=2026-03` |
| **Cores** | Lead: `#C7D2FE` · Agendado: `#818CF8` · Comparecido: `#6366F1` · Orçado: `#4F46E5` · Fechado: `#3730A3` |
| **Filtros** | Período, Profissional, Especialidade, Canal de origem |
| **Service Rails** | `app/services/financial/conversion_analytics_service.rb` |

**Shape do payload JSON:**

```json
{
  "leads": 145,
  "agendados": 98,
  "comparecidos": 71,
  "orcados": 58,
  "fechados": 34,
  "conversoes": {
    "lead_agendado":         67.6,
    "agendado_comparecido":  72.4,
    "comparecido_orcado":    81.7,
    "orcado_fechado":        58.6,
    "geral":                 23.4
  }
}
```

**Configuração Chart.js:**

```javascript
// Chart.js não tem tipo funil nativo
// Implementar como barras horizontais com padding lateral para efeito visual de funil

{
  type: 'bar',
  indexAxis: 'y',
  datasets: [{
    data: [145, 98, 71, 58, 34],
    backgroundColor: ['#C7D2FE', '#818CF8', '#6366F1', '#4F46E5', '#3730A3'],
    borderRadius: 4
  }],
  options: {
    // Cada barra recebe padding-left = (maxVolume - volume) * escala / 2
    // Isso cria o efeito visual de funil centralizado
  }
}
// Taxas de conversão entre etapas: renderizar como labels entre as barras
```

**Alertas e estados especiais:**
Destacar em vermelho a etapa com maior queda percentual de conversão — é o gargalo principal da operação comercial.

---

### Gráfico 16 — Heatmap de ocupação de agenda

> ⭐ **ALTA DIFERENCIAÇÃO** — Nenhum concorrente direto implementa isso.

**Tipo:** Grid de calor (dias da semana × horários) — **renderizado em HTML/CSS, não Chart.js**

**Insight para o gestor:**
Torna óbvios os padrões de ociosidade: terça às 10h sempre vazia, sexta às 14h sempre cheia. Permite redistribuir confirmações para horários ociosos, criar promoções direcionadas e otimizar a rentabilidade por hora. Cada célula mostra também a receita média gerada naquele slot.

| Campo | Especificação |
|-------|--------------|
| **Componente Vue** | `AgendaHeatmap.vue` |
| **Localização** | `features/financial/components/AgendaHeatmap.vue` |
| **Endpoint Rails** | `GET /api/v1/accounts/financial/agenda_heatmap?period=2026-03` |
| **Colunas** | Dias da semana: Seg, Ter, Qua, Qui, Sex, Sáb |
| **Linhas** | Horários: 07:00 às 20:00 em intervalos de 30 minutos |
| **Escala de cor** | `#F1F5F9` (0%) → `#BFDBFE` (25%) → `#60A5FA` (50%) → `#1D4ED8` (75%) → `#1E3A8A` (100%) |
| **Tooltip** | Horário, % de ocupação, receita média, nº de agendamentos |
| **Filtros** | Período, Profissional, Sala/cadeira |
| **Service Rails** | `app/services/financial/agenda_analytics_service.rb` |

**Lógica de query SQL:**

```sql
SELECT
  DAYOFWEEK(start_time) AS dia,
  HOUR(start_time) AS hora,
  COUNT(*) AS agendamentos,
  COUNT(CASE WHEN status = 'comparecido' THEN 1 END) AS comparecidos,
  COUNT(CASE WHEN status = 'comparecido' THEN 1 END) * 100.0 / COUNT(*) AS ocupacao_pct,
  AVG(CASE WHEN status = 'comparecido' THEN receita ELSE NULL END) AS receita_media
FROM appointments
WHERE account_id = :account_id
  AND start_time BETWEEN :start AND :end
GROUP BY dia, hora
ORDER BY dia, hora
```

**Shape do payload JSON:**

```json
[
  { "dia": "Seg", "hora": "09:00", "ocupacao_pct": 87.5, "agendamentos": 16, "comparecidos": 14, "receita_media": 320.00 },
  { "dia": "Seg", "hora": "09:30", "ocupacao_pct": 62.5, "agendamentos": 16, "comparecidos": 10, "receita_media": 285.00 },
  { "dia": "Ter", "hora": "10:00", "ocupacao_pct": 18.8, "agendamentos": 16, "comparecidos": 3,  "receita_media": 190.00 }
]
```

**Implementação Vue (NÃO usar Chart.js):**

```javascript
// computed: matrix[hora][dia] = { ocupacao_pct, receita_media, agendamentos }
// template: grid CSS com células coloridas por ocupacao_pct

// Interpolação de cor por ocupacao_pct:
function corCelula(pct) {
  if (pct === 0)   return '#F1F5F9'
  if (pct < 25)    return '#DBEAFE'
  if (pct < 50)    return '#BFDBFE'
  if (pct < 75)    return '#60A5FA'
  if (pct < 90)    return '#1D4ED8'
  return '#1E3A8A'
}

// Tooltip nativo do browser via title attribute ou Tippy.js
```

---

### Gráfico 17 — Novos pacientes vs recorrentes

**Tipo:** Barras empilhadas mensais + linha de % recorrentes

**Insight para o gestor:**
Se a fatia de pacientes recorrentes encolhe mês a mês, a clínica está perdendo retenção e dependendo cada vez mais de aquisição cara. Uma clínica saudável tem 60–70% de atendimentos de retorno. Queda nesse percentual indica abandono de tratamento e necessidade de campanhas de reativação.

| Campo | Especificação |
|-------|--------------|
| **Componente Vue** | `NewVsReturningPatients.vue` |
| **Localização** | `features/financial/components/NewVsReturningPatients.vue` |
| **Endpoint Rails** | `GET /api/v1/accounts/financial/patient_retention?months=12` |
| **Eixo Y esquerdo** | Número de atendimentos (barras) |
| **Eixo Y direito** | % recorrentes (linha — meta ideal: tracejada em 65%) |
| **Cores** | Novos: `#BFDBFE` · Recorrentes: `#1D4ED8` · Linha %: `#7C3AED` |
| **Service Rails** | `app/services/financial/patient_retention_service.rb` |

**Lógica de query SQL:**

```sql
SELECT
  DATE_FORMAT(a.start_time, '%Y-%m') AS mes,
  COUNT(CASE WHEN a.start_time = MIN(a2.start_time) THEN 1 END) AS novos,
  COUNT(CASE WHEN a.start_time > MIN(a2.start_time) THEN 1 END) AS recorrentes
FROM appointments a
JOIN (SELECT patient_id, MIN(start_time) AS start_time FROM appointments GROUP BY patient_id) a2
  ON a.patient_id = a2.patient_id
WHERE a.status = 'comparecido' AND a.account_id = :account_id
GROUP BY mes
ORDER BY mes
```

**Shape do payload JSON:**

```json
[
  { "mes": "2025-04", "novos": 25, "recorrentes": 66, "total": 91, "pct_recorrentes": 72.5 },
  { "mes": "2026-03", "novos": 28, "recorrentes": 70, "total": 98, "pct_recorrentes": 71.4 }
]
```

**Configuração Chart.js:**

```javascript
{
  type: 'bar',
  datasets: [
    { type: 'bar',  label: 'Novos',        data: [...], backgroundColor: '#BFDBFE', stack: 's' },
    { type: 'bar',  label: 'Recorrentes',  data: [...], backgroundColor: '#1D4ED8', stack: 's' },
    { type: 'line', label: '% Recorrentes', data: pcts,  borderColor: '#7C3AED', yAxisID: 'y2', fill: false }
  ]
}
```

**Alertas e estados especiais:**
Se `pct_recorrentes` < 50% em 2 meses consecutivos: badge vermelho `"Queda de retenção — considere campanha de reativação."`

---

### Gráfico 18 — CAC e ROI por canal de aquisição

> ⚠️ **Depende das integrações Meta Ads API e Google Ads API (Onda 4)**

**Tipo:** Barras agrupadas (investimento + pacientes) + linha de ROI

**Insight para o gestor:**
Fecha o loop entre investimento em marketing e receita gerada. Para cada canal: investimento do mês, número de pacientes gerados, CAC e ROI. O dado que muda decisões: canal com CAC alto mas LTV alto pode ser o mais eficiente. O que destrói margem é canal com CAC alto e LTV baixo.

| Campo | Especificação |
|-------|--------------|
| **Componente Vue** | `MarketingRoiByChannel.vue` |
| **Localização** | `features/financial/components/MarketingRoiByChannel.vue` |
| **Endpoint Rails** | `GET /api/v1/accounts/financial/marketing_roi?period=2026-03` |
| **Eixo Y esquerdo** | Investimento em R$ (barras) |
| **Eixo Y direito** | ROI % (linha) |
| **Cores** | Investimento: `#FCA5A5` · Pacientes gerados: `#86EFAC` · Linha ROI: `#7C3AED` · Break-even (ROI=100%): tracejada cinza |
| **Filtros** | Período, Comparativo com meses anteriores |
| **Service Rails** | `app/services/financial/marketing_roi_service.rb` |

**Fontes de dados por canal:**

- `Meta Ads`: via `MetaAdsService` (API Meta Business — importado automaticamente na Onda 4)
- `Google Ads`: via `GoogleAdsService` (Google Ads API — importado automaticamente)
- `Indicação` e `Orgânico`: via `utm_source` dos leads cadastrados no CRM

**Shape do payload JSON:**

```json
[
  { "canal": "Meta Ads",   "investimento": 3200.00, "pacientes": 8,  "cac": 400.00, "receita_gerada": 14400.00, "roi_pct": 350.0 },
  { "canal": "Google Ads", "investimento": 2800.00, "pacientes": 6,  "cac": 466.67, "receita_gerada": 9600.00,  "roi_pct": 242.9 },
  { "canal": "Indicacao",  "investimento": 0.00,    "pacientes": 12, "cac": 0.00,   "receita_gerada": 19200.00, "roi_pct": null  },
  { "canal": "Organico",   "investimento": 0.00,    "pacientes": 8,  "cac": 0.00,   "receita_gerada": 11200.00, "roi_pct": null  }
]
```

**Configuração Chart.js:**

```javascript
{
  type: 'bar',
  datasets: [
    { type: 'bar',  label: 'Investimento R$', data: [...], backgroundColor: '#FCA5A5', yAxisID: 'y' },
    { type: 'line', label: 'ROI %',           data: [...], borderColor: '#7C3AED',     yAxisID: 'y2' },
  ],
  options: {
    scales: {
      y2: { position: 'right', ticks: { callback: v => v + '%' } }
    }
  }
}
// Label customizado em cada barra: 'CAC: R$ X | N pacientes'
// canais sem investimento (indicação, orgânico): não exibir linha de ROI
```

**Alertas e estados especiais:**
Exibir estado vazio explicativo se as integrações de Meta Ads ou Google Ads não estiverem configuradas. Versão manual: enquanto as APIs não estão ativas, permitir que o usuário insira o investimento por canal manualmente — substituir pela versão automática quando a integração for ativada.

---

## Regras gerais de implementação

| Regra | Especificação |
|-------|--------------|
| **Biblioteca** | Chart.js 4.x via `vue-chartjs` (já instalado). Heatmap de agenda (Gráfico 16): grid CSS puro — Chart.js não tem suporte nativo a heatmap bidimensional. |
| **Legends** | NUNCA usar a legend padrão do Chart.js (dots pequenos). Sempre construir legend em HTML com quadrados 10×10px, label e valor/percentual. |
| **Formatação de números** | Todo número monetário via `Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })`. Percentuais com 1 casa decimal. Nunca exibir float bruto JS. |
| **Loading state** | Todo gráfico com skeleton loader durante fetch. Usar `ChartSkeleton.vue` com barras placeholder em `--color-background-secondary`. |
| **Empty state** | Se endpoint retornar array vazio: ilustração + mensagem contextual. Ex: `"Nenhuma despesa registrada neste período."` com link de ação. |
| **Responsividade** | Todos com `responsive: true` e `maintainAspectRatio: false`. Altura definida no wrapper div, nunca no canvas. Mobile: altura reduzida para 200px. |
| **Tooltips** | Customizados via plugin de tooltip do Chart.js. Sempre mostrar: label, valor em R$, percentual quando aplicável. Background `#1E293B`, texto branco, `border-radius: 8px`. |
| **Drill-down** | Gráficos de aging, despesas por categoria e receita por profissional: ao clicar em barra, emitir evento Vue que abre painel lateral com lançamentos de origem. |
| **Performance** | Gráficos com mais de 30 pontos de dados: usar plugin `decimation` do Chart.js. Queries com `GROUP BY` precisam ter índices nas colunas de agrupamento (já definidos nas migrations). |
| **Tema claro/escuro** | Não hardcodar cores de eixos e grid. Usar: `gridColor: isDark ? '#334155' : '#E2E8F0'`, `tickColor: isDark ? '#94A3B8' : '#64748B'`. Detectar via `window.matchMedia('(prefers-color-scheme: dark)').matches`. |

---

## Como usar este documento para comandar a IA

Para cada onda, envie o documento junto com o seguinte prompt:

```
Implemente os gráficos da [Onda X] conforme a especificação neste documento.
Para cada gráfico:
1. Crie o service Rails no caminho especificado
2. Crie o controller com o endpoint indicado
3. Crie o componente Vue na localização definida
4. Use exatamente o shape de payload documentado
5. Implemente a configuração Chart.js conforme especificado
6. Adicione os alertas e estados especiais descritos

Comece pelo Gráfico [N] e aguarde confirmação antes de passar para o próximo.
```

> **Importante:** Implemente um gráfico por vez. Enviar todos de uma onda simultaneamente gera contexto demais e aumenta a chance de erros.
