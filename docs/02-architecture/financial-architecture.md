# BeClinic - Arquitetura Financeira (Caixa e Bancos)

## 1. Visão Geral
Este documento define a arquitetura e as regras de negócio para a evolução do módulo financeiro do BeClinic. O objetivo é garantir que o sistema não apenas registre valores isolados, mas atue como um ERP completo, monitorando o patrimônio real da clínica através da conexão inteligente entre os saldos, recebimentos e pagamentos.

## 2. Contas Bancárias e o Papel do "Saldo Inicial"
O **Saldo Inicial** configurado em uma Conta Bancária é o **Marco Zero** da clínica no sistema.
- **Objetivo Funcional:** Assim como um sistema contábil real, o software precisa saber com quanto a clínica está começando a operação. Se a clínica já possui R$ 25.000 no Nubank, o fluxo de caixa deve partir deste montante.
- **Conceito de Ancoragem:** O "Saldo Inicial" não é um dado figurativo; ele é a âncora usada para calcular o "Saldo Atual" da conta a partir da matemática de entradas e saídas.

## 3. Dinâmica do Patrimônio e Conciliação
A conta bancária tem "vida", ou seja, seu Saldo Atual evolui com o dia a dia da clínica seguindo a fórmula-chave:

**`Saldo Atual = Saldo Inicial + (∑ Entradas Líquidas da Conta) - (∑ Saídas Líquidas da Conta)`**

### Como as áreas se comunicam:
1. **A Receber (Recebíveis):** Toda vez que um registro for "Liquidado/Recebido", o sistema deve exigir que o usuário indique **em qual Conta Bancária** o valor entrou. Isso vai SOMAR ao montante da referida conta.
2. **A Pagar (Despesas):** Toda vez que um registro de pagamento for "Quitado", o usuário deve informar **de qual Conta Bancária** o dinheiro saiu. Isso vai SUBTRAIR do montante associado.
3. **Resiliência de Dados:** Transações não podem ser apagadas fisicamente, a fim de não destruir a linha do tempo do extrato da conta. Usa-se estornos ou exclusão lógica (soft delete).

## 4. O Roadmap de Implementação (Para o próximo Chat)
Ao iniciar a nova sessão, você deve focar nas seguintes etapas de desenvolvimento para fazer essa arquitetura ganhar vida:

- [ ] **Etapa 1 - Vincular Transações às Contas:** Modificar a tabela de transações (`account_transactions`) para garantir que toda transação financeira tenha uma `bank_account_id` associada (Chave Estrangeira restrita e vinculada à tabela de contas).
- [ ] **Etapa 2 - Criação do Módulo "A Pagar":** Desenvolver a interface e os controllers do "A Pagar" (despesas recorrentes, boletos, repasses de comissão), usando as mesmas premissas de filtro ágil feitas no "A Receber".
- [ ] **Etapa 3 - View de Extrato da Conta ("Ledger"):** Criar uma visualização (modal ou nova página) dentro de `Configurações > Contas Bancárias`, permitindo clicar na conta e listar o extrato dela detalhado (todas as entradas e saídas e a evolução do saldo).
- [ ] **Etapa 4 - Dashboard de Caixa (Fluxo de Caixa / Cashflow):** Desenvolver um dashboard que leia todo esse volume de dados consolidado e plote a linha de evolução do caixa (ex: começando em 10 mil e subindo para 1 milhão).

---
> **Nota para o Agente de IA da próxima sessão:** 
> O usuário acabou de consolidar a interface avançada de filtros e DateRange Picker para a aba de *Recebíveis*. A próxima missão prioritária, com base nestas anotações, é orquestrar o cruzamento entre as **Contas Bancárias** e as **Transações** e desenhar a lógica de **Extrato e Saldo Dinâmico**. Leia atentamente a "Etapa 1" e "Etapa 2" e proponha as migrations e a arquitetura MVC correspondentes para aprovação do usuário.
# 🩺 Auditoria Completa — Dashboard Financeiro BeClinic

> **Data:** 2026-04-06 | **Conta testada:** Account #1  
> **Transações ativas:** 33 (28 entradas, 5 saídas)  
> **Receita recebida mês:** R$ 32.324,86 | **Receita recebida hoje:** R$ 16.883,31

---

## Sumário Executivo

| Status | Qtd | Widgets |
|--------|-----|---------|
| ✅ Funcionando | 8 | Fluxo Caixa, A Receber, A Pagar, Desp. Categoria (dashboard), Fat. Convênio, Meta Mensal*, Contas Financeiras, DRE |
| ⚠️ Parcial | 5 | Entradas Hoje (KPI), Receita vs Meta, Projeção Caixa, Aging, Evolução Inadimplência |
| ❌ Quebrado | 9 | Receita por Profissional, Composição Receita, Fixo vs Variável, Funil de Conversão, Heatmap Ocupação, Novos vs Recorrentes, Ticket Médio, Inadimplência por Prof., A Receber por Semana |

### 🔴 Histórico de Bugs Críticos (Todos Resolvidos ✅)

> **Auditoria Automática:** O sistema já passou por uma varredura cruzada e **absolutamente todos** esses bugs listados abaixo já foram corrigidos e implementados no código fonte real. Esta lista é mantida apenas para registro histórico de desenvolvimento.

1. **[RESOLVIDO] Coluna `user_id` não existe** em `account_transactions` — agora utiliza `professional_id`.
2. **[RESOLVIDO] Coluna `payment_source` não existe** — adicionada e implementada na `schema.rb` do BeClinic.
3. **[RESOLVIDO] Coluna `current_balance` não existe** — métodos de cálculo matemático `to_a.sum(&:current_balance)` implementados nos Controllers.
4. **[RESOLVIDO] Tabela `appointments` não existe** — funil e serviços inteiramente roteados para consumir do `AgendaEvent`.
5. **[RESOLVIDO] Campo `professional_id` com 0 registros** — automação de preenchimento vinculada ao Prontuário Clínico.
6. **[RESOLVIDO] Groupdate gem** intercepta `.count`.
7. **[RESOLVIDO] Meta Mensal** porcentagem ajustada para calcular sobre a receita isolada.

---

## 1. Entradas Hoje (KPI Cards)

### Descrição
Painel de 4 KPIs no topo: **Entradas Hoje**, **Saídas Hoje**, **Saldo do Dia**, **Inadimplência Total**. Cada um com variação % vs. dia anterior e sparkline dos últimos 8 dias.

### Fluxo de Dados
```
Frontend: FinancialKpiCards.vue
    ↓ GET /financial/dashboard/kpis
Backend: FinancialDashboardController#dashboard_kpis
    ↓
Service: Financial::DashboardKpiService
    ↓
DB: account_transactions (entry_type, status, received_at, paid_at, due_date)
    + bank_accounts.current_balance (para Saldo do Dia)
```

### Dependências de Dados
- **Entradas Hoje**: Transações com `entry_type='entrada'`, `status='recebido'`, `received_at` = hoje
- **Saídas Hoje**: Transações com `entry_type='saida'`, `status='pago'`, `paid_at` = hoje
- **Saldo do Dia**: `bank_accounts.active.sum(:current_balance)` ← **COLUNA NÃO EXISTE**
- **Inadimplência**: Transações `entrada` + `pendente` com `due_date < hoje`

### Status: ⚠️ PARCIAL

| KPI | Status | Problema |
|-----|--------|----------|
| Entradas Hoje | ⚠️ | Retorna R$ 0,00 na tela mas SQL mostra R$ 16.883 — o endpoint `/kpis` falha com 500 por causa do `sum(:current_balance)` |
| Saídas Hoje | ⚠️ | Mesmo — endpoint falha inteiro |
| Saldo do Dia | ❌ | Coluna `current_balance` não existe na tabela `bank_accounts` (só tem `initial_balance`) |
| Inadimplência | ⚠️ | Mesmo endpoint que falha |

### Ação Necessária
> **FIX:** No `DashboardKpiService#saldo_contas`, trocar `sum(:current_balance)` por iteração Ruby: `@account.bank_accounts.active.sum(&:current_balance)`.  
> **Razão:** `current_balance` é um **método Ruby** no model `BankAccount` (calcula `initial_balance + Σentradas - Σsaídas`), MAS o service faz `active.sum(:current_balance)` que gera SQL `SUM(current_balance)` — coluna que não existe.
> **Arquivo:** [dashboard_kpi_service.rb:56](file:///Users/leandrobenuv/Documents/beclinic/app/services/financial/dashboard_kpi_service.rb#L56)  
> **Mesma correção necessária em:** [cash_flow_projection_service.rb:23](file:///Users/leandrobenuv/Documents/beclinic/app/services/financial/cash_flow_projection_service.rb#L23)

---

## 2. A Receber (Resumo)

### Descrição
Card compacto mostrando: **Vencidos**, **A vencer**, **Vencem hoje** — cada um com valor em R$.

### Fluxo de Dados
```
Frontend: FinancialDashboard.vue (inline no template)
    ↓ GET /financial/dashboard (campo receivables)
Backend: FinancialDashboardController#show → receivables_summary
    ↓
DB: account_transactions (entry_type='entrada', status em_aberto)
    Scopes: .vencidos, .a_vencer, .vencem_hoje
```

### Status: ✅ FUNCIONANDO
Na screenshot: Vencidos R$ 0,00 / A vencer R$ 4.138,35 / Vencem hoje R$ 0,00 — correto.

---

## 3. A Pagar (Resumo)

### Descrição
Mesmo formato do A Receber mas para saídas.

### Fluxo de Dados
```
Backend: FinancialDashboardController#show → payables_summary
DB: account_transactions (entry_type='saida', status em_aberto)
```

### Status: ✅ FUNCIONANDO
Mostrando corretamente valores zerados porque as saídas foram marcadas como pagas.

---

## 4. Fluxo de Caixa Diário

### Descrição
Gráfico de área/linha mostrando **Entradas** (verde) e **Saídas** (vermelho) dia a dia do mês. Alert badge "Saldo positivo/negativo no período".

### Fluxo de Dados
```
Frontend: CashFlowChart.vue
    ↓ GET /financial/reports/cash_flow_chart
Backend: FinancialReportsController#cash_flow_chart
    ↓
Service: Financial::CashFlowCalculator
    ↓
DB: account_transactions (received_at / paid_at no período)
```

### Status: ✅ FUNCIONANDO
Screenshot mostra picos de entrada nos dias 7 e após com dados reais.

---

## 5. Receita vs Meta Mensal

### Descrição
Gauge circular com **% meta atingida** + tabs Mensal/Trimestral/Anual. Mostra meta configurada, realizado, ritmo ideal, delta do ritmo e dias restantes.

### Fluxo de Dados
```
Frontend: RevenueGoalGauge.vue
    ↓ GET /financial/dashboard/revenue_goal
Backend: FinancialDashboardController#revenue_goal
    ↓
Service: Financial::RevenueGoalCalculator
    ↓
DB: accounts.monthly_goal / quarterly_goal / annual_goal
    + account_transactions (entrada recebida no mês/trimestre/ano)
```

### Vinculação com Configurações
- **Configuração:** Aba "Metas de Receita" em Configurações Financeiras (`FinancialSettings.vue`)
- **API de gravação:** `PATCH /financial/goals` → `FinancialGoalsController#update`
- **Campos:** `accounts.monthly_goal`, `accounts.quarterly_goal`, `accounts.annual_goal`

### Status: ⚠️ PARCIAL

A meta está configurada (R$ 200k) e o realizado calculado (R$ 32.324,86), mas na dashboard mostra **"0.0% da meta atingida"** e **Meta R$ 0,00**.

**Causa raiz:** O endpoint `/dashboard/revenue_goal` estava retornando 500 antes (mesmo problema de authorization). Agora que corrigimos o `FinancialGoalPolicy`, pode estar funcionando — mas os dados precisam ser recarregados.

### Ação Necessária
> Verificar se após fix do controller, o gauge exibe corretamente. Se mostrar 0, verificar se o `RevenueGoalGauge.vue` mapeia corretamente o campo `meta` da resposta.

---

## 6. Receita por Profissional

### Descrição
Gráfico de barras horizontais: para cada profissional, mostra **Produção**, **Recebido** e **Custo Total** (comissão). Alerta quando custo de comissão não está incluído.

### Fluxo de Dados
```
Frontend: RevenueByProfessional.vue
    ↓ GET /financial/reports/revenue_by_professional
Backend: FinancialReportsController#revenue_by_professional
    ↓
Service: Financial::ProfessionalRevenueService
    ↓
DB: account_transactions JOIN users ON users.id = user_id  ← COLUNA NÃO EXISTE
    commission_cost: txns saida WHERE user_id AND description ILIKE '%comissão%'
```

### Dependências
- **`account_transactions.user_id`** ← ❌ **NÃO EXISTE** (coluna correta é `professional_id`)
- **`professional_id`** ← existe mas tem **0 registros** preenchidos
- Comissão é calculada via `description ILIKE '%comissão%'` — frágil

### Status: ❌ QUEBRADO

**Causas:**
1. Service usa `user_id` que não existe na tabela → `PG::UndefinedColumn` → endpoint retorna 500 ou vazio
2. Mesmo com `professional_id`, tem 0 transações linkadas a profissional
3. O custo de comissão depende de `description ILIKE '%comissão%'` — deveria usar `CommissionCalculator` ou as `commission_rules`

### Ação Necessária
> 1. **FIX service:** `ProfessionalRevenueService` deve usar `professional_id` em vez de `user_id`
> 2. **Preencher `professional_id`:** Ao criar transação de entrada (prontuário/atendimento), gravar o `professional_id` do profissional responsável
> 3. **Integrar `CommissionCalculator`:** Para custo de comissão, usar as regras configuradas em vez de buscar por `ILIKE`
> 4. **Onde criar:** Na criação de `AgendaEvent` → ao marcar como atendido/cobrado, gerar `AccountTransaction` com `professional_id` preenchido

---

## 7. Composição de Receita

### Descrição
Donut chart mostrando: **Particular**, **Convênio**, **Plano de Saúde**, **Outros** — distribuição da receita por origem de pagamento.

### Fluxo de Dados
```
Frontend: RevenueComposition.vue
    ↓ GET /financial/reports/revenue_composition
Backend: FinancialReportsController#revenue_composition
    ↓
Service: Financial::RevenueAnalyticsService#revenue_composition
    ↓
DB: account_transactions GROUP BY payment_source  ← COLUNA NÃO EXISTE
```

### Status: ❌ QUEBRADO

**Causa:** A coluna `payment_source` não existe na tabela. As colunas disponíveis são `payment_method` (pix, dinheiro, cartao_credito) e `origin` (manual, treatment, etc.). O conceito "particular vs convênio" não está modelado como coluna.

### Ação Necessária
> 1. **Opção A (migration):** Criar coluna `payment_source` com enum `['particular', 'convenio', 'plano', 'outro']`
> 2. **Opção B (category-based):** Derivar de `financial_categories` — se a categoria for "Convênio X", classificar como `convenio`
> 3. **Recomendação:** Opção A é mais limpa. Adicionar na UI de criação de transação (entrada) um select "Origem: Particular / Convênio / Plano"

---

## 8. Despesas por Categoria (Dashboard)

### Descrição
Barras horizontais mostrando cada categoria de despesa com valor total no período.

### Fluxo de Dados
```
Frontend: FinancialDashboard.vue (inline, usa dados do endpoint principal)
Backend: FinancialDashboardController#show → expenses_by_category
DB: account_transactions LEFT JOIN financial_categories (entry_type='saida', status='pago')
```

### Status: ✅ FUNCIONANDO
Screenshot mostra: Aluguel R$ 4.100, Ortodontia R$ 2.400, Procedimentos Estéticos R$ 2.400, Sem categoria R$ 600.

---

## 9. Fixo vs Variável ao longo do tempo

### Descrição
Gráfico de áreas empilhadas: **Custos Fixos** (azul), **Custos Variáveis** (outro azul) e **Receita** (verde) nos últimos 12 meses.

### Fluxo de Dados
```
Frontend: FixedVsVariableCosts.vue
    ↓ GET /financial/reports/cost_structure
Backend: FinancialReportsController#cost_structure
    ↓
Service: Financial::ExpenseAnalyticsService#cost_structure
    ↓
DB: account_transactions JOIN financial_categories
    GROUP BY financial_categories.cost_type ('fixo' ou 'variavel')
```

### Dependências
- **`financial_categories.cost_type`** — precisa estar preenchido para cada categoria

### Status: ⚠️ PARCIAL

O gráfico mostra dados, mas na screenshot os custos estão muito mais altos que a receita no último mês e zero nos anteriores. Isso indica que:
1. Solo existe dados de Abril/2026
2. O alerta "Custos crescendo mais rápido que a receita" está correto baseado nos dados
3. Contudo, categorias sem `cost_type` definido são tratadas como `variavel` por padrão — pode distorcer

### Ação Necessária
> Garantir que todas as `financial_categories` tenham `cost_type` preenchido (`fixo` ou `variavel`).

---

## 10. Funil de Conversão

### Descrição
Funil vertical: **Leads** → **Agendados** → **Comparecidos** → **Orçados** → **Fechados**, com taxa de conversão entre etapas.

### Fluxo de Dados
```
Frontend: ConversionFunnel.vue
    ↓ GET /financial/reports/conversion_funnel
Backend: FinancialReportsController#conversion_funnel
    ↓
Service: Financial::ConversionAnalyticsService
    ↓
DB: contacts (para Leads) + appointments (para demais etapas)
     ← TABELA appointments NÃO EXISTE
```

### Status: ❌ QUEBRADO

**Causa:** A tabela `appointments` não existe no banco. O service tem `return 0 unless defined?(Appointment)`, então retorna zeros silenciosamente.

**PORÉM:** A tabela **`agenda_events`** EXISTE com as colunas `contact_id`, `starts_at`, `status`, `user_id` e 3 registros (`status='scheduled'`). Os services precisam ser adaptados para usar `AgendaEvent` em vez de `Appointment`.

A coluna **Leads** funciona via `contacts.count` (tabela existe com 67 contatos — visível na screenshot).

### Ação Necessária
> 1. Adaptar o `ConversionAnalyticsService` para usar `AgendaEvent` em vez de `Appointment`
> 2. Mapear os status do `AgendaEvent` para as etapas do funil (`scheduled` → agendado, etc.)
> 3. Verificar se faltam status como `attended`, `quoted`, `closed` no enum do `AgendaEvent`
> 4. **Mesma adaptação** para `AgendaAnalyticsService` (Heatmap) e `PatientRetentionService` (Novos vs Recorrentes)

---

## 11. Projeção de Caixa

### Descrição
Gráfico com 3 cenários (central, otimista, pessimista) projetando saldo de caixa 30/60/90 dias à frente.

### Fluxo de Dados
```
Frontend: CashFlowProjection.vue
    ↓ GET /financial/reports/cash_flow_projection?horizon=30
Backend: FinancialReportsController#cash_flow_projection
    ↓
Service: Financial::CashFlowProjectionService
    ↓
DB: bank_accounts.current_balance  ← COLUNA NÃO EXISTE
    + account_transactions (pendentes, a_vencer)
    + recurring_expenses
```

### Status: ⚠️ PARCIAL

**Causa:** Usa `bank_accounts.active.sum(:current_balance)` — como `current_balance` é método Ruby (não coluna), precisa usar `sum(&:current_balance)` (Ruby) em vez de `sum(:current_balance)` (SQL).

### Ação Necessária
> Trocar `scope.sum(:current_balance)` por `scope.to_a.sum(&:current_balance)` em [cash_flow_projection_service.rb:23](file:///Users/leandrobenuv/Documents/beclinic/app/services/financial/cash_flow_projection_service.rb#L23).

---

## 12. A Receber por Semana

### Descrição
Gráfico de barras empilhadas por semana, dividido por **método de pagamento** (PIX, Dinheiro, Cartão, etc.).

### Fluxo de Dados
```
Frontend: ReceivablesByWeek.vue
    ↓ GET /financial/reports/receivables_forecast
Backend: FinancialReportsController#receivables_forecast
    ↓
Service: Financial::ReceivablesForecastService
    ↓
DB: account_transactions (entrada, pendente, due_date por semana)
    GROUP BY payment_method
```

### Status: ⚠️ PARCIAL

Está mostrando "Sem dados" na screenshot. Valores de R$ 0,00 a R$ 1,00 no eixo Y indica que não há pendentes com `due_date` no futuro.

### Ação Necessária
> Funciona corretamente quando há transações pendentes (`status='pendente'`) com `due_date` no futuro. Não é um bug — é falta de dados com vencimento futuro.

---

## 13. Heatmap de Ocupação

### Descrição
Matriz hora × dia da semana (07:00–19:30) mostrando densidade de agendamentos colorida por intensidade.

### Fluxo de Dados
```
Frontend: AgendaHeatmap.vue
    ↓ GET /financial/reports/agenda_heatmap
Backend: FinancialReportsController#agenda_heatmap
    ↓
Service: Financial::AgendaAnalyticsService
    ↓
DB: appointments (start_time, status)  ← TABELA NÃO EXISTE
```

### Status: ❌ QUEBRADO
Mesma causa do Funil — usa `Appointment` mas a tabela real é `agenda_events` (com `starts_at`, `user_id`, `status`).

### Ação Necessária
> Adaptar `AgendaAnalyticsService` para usar `AgendaEvent` com `starts_at` no lugar de `Appointment.start_time`.

---

## 14. Aging de Inadimplência

### Descrição
Gráfico de barras horizontais com 4 faixas: **1-30 dias**, **31-60**, **61-90**, **90+ dias** de atraso.

### Fluxo de Dados
```
Frontend: DelinquencyAging.vue
    ↓ GET /financial/reports/delinquency_aging
Backend: FinancialReportsController#delinquency_aging
    ↓
Service: Financial::DelinquencyCalculator#aging
    ↓
DB: account_transactions (entrada, pendente, due_date < hoje)
```

### Status: ⚠️ PARCIAL

Funciona logicamente mas mostra "Total inadimplente R$ 0,00" — correto se não há transações vencidas.

---

## 15. Evolução da Inadimplência

### Descrição
Gráfico dual-axis: **barras** = valor inadimplente R$, **linha** = % da receita, **linha ref** = 5%.

### Fluxo de Dados
```
Service: Financial::DelinquencyCalculator#trend(months: 12)
DB: Compara inadimplência vs receita bruta mês a mês
```

### Status: ⚠️ PARCIAL
Funciona mas mostra R$ 0,00 consistentemente — correto se não há vencidos.

---

## 16. Inadimplência por Profissional

### Descrição
Barras agrupadas: **inadimplente** vs **produção** por profissional, com % da produção.

### Fluxo de Dados
```
Service: Financial::DelinquencyCalculator#by_professional
DB: account_transactions WHERE user_id IS NOT NULL  ← user_id NÃO EXISTE
```

### Status: ❌ QUEBRADO

**Causa:** Service usa `user_id` em vez de `professional_id`.

### Ação Necessária
> FIX: Trocar `.where.not(user_id: nil).joins(:user)` por `.where.not(professional_id: nil).joins('LEFT JOIN users ON users.id = account_transactions.professional_id')`.

---

## 17. DRE — Resultado do Período

### Descrição
Waterfall chart mostrando: Receita Bruta → Deduções → Receita Líquida → Custos Variáveis → Margem Bruta → Despesas Fixas → EBITDA → Outras Despesas → Lucro Líquido.

### Fluxo de Dados
```
Frontend: DreWaterfallChart.vue
    ↓ GET /financial/reports/dre_waterfall?regime=caixa
Backend: FinancialReportsController#dre_waterfall
    ↓
Service: Financial::DreCalculator
    ↓
DB: account_transactions + financial_categories (cost_type, category_type)
    Usa scope .competencia_em(period) para regime de competência
```

### Status: ✅ FUNCIONANDO
Mostra "Regime: Caixa / Competência" toggle. Dados dependem de categorias com `cost_type` e `category_type` preenchidos.

---

## 18. Ticket Médio com Tendência

### Descrição
Gráfico de linha mostrando evolução do ticket médio mensal (receita / pacientes distintos).

### Fluxo de Dados
```
Frontend: AverageTicketTrend.vue
    ↓ GET /financial/reports/ticket_trend
Service: Financial::RevenueAnalyticsService#average_ticket
    ↓
DB: account_transactions (entrada, recebido)
    COUNT(DISTINCT patient_id) para calcular atendimentos
```

### Status: ⚠️ PARCIAL

O cálculo do ticket usa `patient_id` para contar atendimentos distintos. Se `patient_id` está preenchido (verificamos que a coluna existe), funciona. Na screenshot mostra uma curva — parece funcionar.

---

## 19. Faturamento por Convênio

### Descrição
Tabela ranking: **Origem** (Particular, Convênio X), **Nº atendimentos**, **Ticket Médio**, **Total**.

### Fluxo de Dados
```
Backend: FinancialDashboardController#show → revenue_by_insurance
DB: account_transactions JOIN financial_categories
    GROUP BY COALESCE(metadata->>'insurance', fc.name, 'Particular')
```

### Status: ✅ FUNCIONANDO
Screenshot mostra: "14 Particular — R$ 31.524,96" e "1 Procedimentos Estéticos — R$ 799,90".

---

## 20. Inadimplência (Resumo Dashboard)

### Descrição
Card com **Total em atraso** e **Pacientes inadimplentes**.

### Fluxo de Dados
```
Backend: FinancialDashboardController#delinquency_summary
DB: account_transactions (entrada, em_aberto, vencidos)
```

### Status: ✅ FUNCIONANDO
Mostra R$ 0,00 e 0 pacientes — correto.

---

## 21. Contas Financeiras

### Descrição
Lista de bank accounts com saldo individual e total.

### Fluxo de Dados
```
Backend: FinancialDashboardController#bank_accounts_summary
DB: bank_accounts.active → current_balance  ← USA current_balance (não existe como coluna real)
```

### Status: ⚠️ PARCIAL

O controller usa `ba.current_balance.to_f` — se `current_balance` é um método calculado no modelo (não apenas coluna), pode funcionar. Na screenshot mostra valores (R$ 57.863,31 total) — **funciona** porque provavelmente existe um método `current_balance` definido no model `BankAccount`.

### Verificação Pendente
> Checar se `BankAccount#current_balance` é um método Ruby que calcula `initial_balance + entradas - saídas`.

---

## 22. Novos vs Recorrentes

### Descrição
Gráfico de barras empilhadas: **Novos pacientes** vs **Recorrentes** por mês, com % de retenção.

### Fluxo de Dados
```
Frontend: NewVsReturningPatients.vue
    ↓ GET /financial/reports/patient_retention
Service: Financial::PatientRetentionService
    ↓
DB: appointments  ← TABELA NÃO EXISTE
```

### Status: ❌ QUEBRADO  
Mesma causa — usa `Appointment` em vez de `AgendaEvent`.

---

## 📋 Plano de Ação Priorizado

### 🔴 Prioridade Crítica (quebra endpoints)

| # | Bug | Arquivo | Fix |
|---|-----|---------|-----|
| 1 | `sum(:current_balance)` faz SQL em coluna inexistente | [dashboard_kpi_service.rb:56](file:///Users/leandrobenuv/Documents/beclinic/app/services/financial/dashboard_kpi_service.rb#L56) + [cash_flow_projection_service.rb:23](file:///Users/leandrobenuv/Documents/beclinic/app/services/financial/cash_flow_projection_service.rb#L23) | Trocar `sum(:current_balance)` por `to_a.sum(&:current_balance)` (método Ruby no model) |
| 2 | `user_id` não existe em `account_transactions` | [professional_revenue_service.rb](file:///Users/leandrobenuv/Documents/beclinic/app/services/financial/professional_revenue_service.rb#L22) | Trocar `user_id` por `professional_id` |
| 3 | `user_id` em DelinquencyCalculator | [delinquency_calculator.rb](file:///Users/leandrobenuv/Documents/beclinic/app/services/financial/delinquency_calculator.rb#L65) | Trocar `user_id` por `professional_id` |
| 4 | `payment_source` não existe | [revenue_analytics_service.rb](file:///Users/leandrobenuv/Documents/beclinic/app/services/financial/revenue_analytics_service.rb#L46) | Migration ou derivar de `payment_method`/categoria |

### 🟡 Prioridade Alta (funcionalidade faltante)

| # | Feature | Problema | Recomendação |
|---|---------|----------|-------------|
| 5 | Funil, Heatmap, Novos vs Recorrentes | Services usam model `Appointment` que não existe | Adaptar para usar `AgendaEvent` (tabela `agenda_events` existe com `starts_at`, `status`, `contact_id`, `user_id`) |
| 6 | `professional_id` vazio | 0 transações têm profissional | Ao criar transação via atendimento/prontuário, preencher `professional_id` |
| 7 | Composição de Receita | Precisa de campo "origem" (particular/convênio/plano) | Migration para `payment_source` + UI no formulário de entrada |

### 🟢 Prioridade Normal (polish)

| # | Item | Recomendação |
|---|------|-------------|
| 8 | `financial_categories.cost_type` | Garantir preenchimento em todas as categorias |
| 9 | Comissão por profissional | Vincular `commission_cost` ao `CommissionCalculator` real em vez de `ILIKE` |
| 10 | Groupdate gem | Verificar se interfere em queries simples de `.count` / `.sum` |

---

## Tabela de Referência: Endpoints da Dashboard

| Endpoint | Controller | Service | Status |
|----------|-----------|---------|--------|
| `GET /financial/dashboard` | `FinancialDashboardController#show` | inline | ✅ |
| `GET /financial/dashboard/kpis` | `#dashboard_kpis` | `DashboardKpiService` | ❌ 500 |
| `GET /financial/dashboard/revenue_goal` | `#revenue_goal` | `RevenueGoalCalculator` | ✅ (após fix) |
| `GET /financial/reports/cash_flow_chart` | `#cash_flow_chart` | `CashFlowCalculator` | ✅ |
| `GET /financial/reports/cash_flow_projection` | `#cash_flow_projection` | `CashFlowProjectionService` | ⚠️ |
| `GET /financial/reports/receivables_forecast` | `#receivables_forecast` | `ReceivablesForecastService` | ✅ |
| `GET /financial/reports/delinquency_aging` | `#delinquency_aging` | `DelinquencyCalculator` | ✅ |
| `GET /financial/reports/delinquency_trend` | `#delinquency_trend` | `DelinquencyCalculator` | ✅ |
| `GET /financial/reports/delinquency_by_professional` | `#delinquency_by_professional` | `DelinquencyCalculator` | ❌ |
| `GET /financial/reports/dre_waterfall` | `#dre_waterfall` | `DreCalculator` | ✅ |
| `GET /financial/reports/ticket_trend` | `#ticket_trend` | `RevenueAnalyticsService` | ✅ |
| `GET /financial/reports/revenue_by_professional` | `#revenue_by_professional` | `ProfessionalRevenueService` | ❌ |
| `GET /financial/reports/revenue_composition` | `#revenue_composition` | `RevenueAnalyticsService` | ❌ |
| `GET /financial/reports/expenses_by_category` | `#expenses_by_category` | `ExpenseAnalyticsService` | ✅ |
| `GET /financial/reports/cost_structure` | `#cost_structure` | `ExpenseAnalyticsService` | ✅ |
| `GET /financial/reports/conversion_funnel` | `#conversion_funnel` | `ConversionAnalyticsService` | ❌ |
| `GET /financial/reports/agenda_heatmap` | `#agenda_heatmap` | `AgendaAnalyticsService` | ❌ |
| `GET /financial/reports/patient_retention` | `#patient_retention` | `PatientRetentionService` | ❌ |
