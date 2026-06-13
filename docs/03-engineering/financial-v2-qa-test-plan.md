# Plano de Testes QA — Módulo Financeiro Klivy/Salus

> Roteiro de testes end-to-end para o Analista de QA validar o módulo financeiro v2 antes de release em produção.
>
> Cobre: Setup → Configuração → Operação dia-a-dia → Aba Financeiro do Paciente → Relatórios → Importação Clinicorp → Auditoria/LGPD/Backups → Cenários de erro → Multi-tenancy → RBAC.
>
> **Última atualização:** 2026-05-11
> **Versão do módulo:** 1.6.0.5 (32 cards canon entregues, F-11 OUT-OF-SCOPE)

---

## 0. Como usar este documento

- Cada **fase** representa uma área funcional. Execute na ordem (algumas dependem de pré-condições da fase anterior).
- Cada **caso de teste** tem:
  - **Pré-condição** — o que precisa estar configurado
  - **Passos** — clicks e ações
  - **Resultado esperado** — o que tem que aparecer/acontecer
  - **Status** — `[ ] PASS / [ ] FAIL` (marque depois de testar)
  - **Observação** — espaço pra anotações se falhar
- **Critério de aprovação:** todas as fases obrigatórias com 100% PASS. Fases opcionais (marcadas com 🟡) podem ter falhas registradas pra próximo sprint.
- **Em caso de falha crítica** (🔴): pause os testes, reporte ao dev. Não tente contornar.

---

## 1. Ambiente de testes

### 1.1 Pré-requisitos do ambiente

- [ ] Klivy/Salus rodando em ambiente de **staging** (não produção)
- [ ] Banco de dados **com dados de seed** ou recém-resetado
- [ ] Conta de teste criada (anote `account_id`: ________)
- [ ] Acesso ao **Sidekiq Dashboard** (`/sidekiq`) — pra ver jobs em background
- [ ] Acesso ao **PostgreSQL** ou Rails console — pra verificações de banco quando necessário
- [ ] Cloudflare R2 configurado (se for testar backups com mirror remoto)

### 1.2 Usuários de teste necessários (5 perfis RBAC)

Cadastre os 5 perfis antes de começar. Anote o email/senha de cada:

| Perfil | Email | Senha | O que pode fazer |
|---|---|---|---|
| **Administrador** | qa-admin@test.com | _____ | Tudo, inclusive deletar |
| **Gerente** | qa-gerente@test.com | _____ | Operacional sem deletar contas/categorias |
| **Especialista** (DENTIST) | qa-dentist@test.com | _____ | Vê só próprios pacientes/comissões |
| **Recepção** | qa-recepcao@test.com | _____ | Cobrar, receber, gerar recibo |
| **Auditor** (read-only) | qa-auditor@test.com | _____ | Só leitura, sem ações |

### 1.3 Dados sample mínimos

Antes de qualquer teste funcional, garanta que existem:

- [ ] **3 pacientes** com CPF cadastrado (para testes de cobrança/anonimização)
- [ ] **2 profissionais** (Especialistas) cadastrados
- [ ] **1 conta corrente** ativa (kind=checking)
- [ ] **1 caixa físico** ativo (kind=cash) — necessário para Fase 7 (Caixa)

---

## 2. Fase A — Configuração inicial obrigatória (F-04 Wizard)

### A.1 Setup Wizard bloqueia operação até configuração mínima

**Pré-condição:** conta novinha sem categorias/contas cadastradas. Login como **Administrador**.

**Passos:**
1. Acesse `/app/accounts/:id/financial/v2/dashboard`
2. Observe se a tela mostra um wizard de setup em vez do dashboard normal

**Resultado esperado:**
- [ ] **PASS** — Tela exibe o `SetupWizardV2` com 5 passos: Categorias, Contas, Profissionais, Comissões, Metas
- [ ] Backend retorna `412 financial_setup_required` na chamada `/v2/reports/dashboard`
- [ ] Não é possível acessar nenhuma tela financeira sem completar o setup

🔴 **Falha crítica** se o dashboard abre normalmente sem setup (RBAC quebrado).

### A.2 Completar o Setup Wizard

**Passos:**
1. Step 1 — **Categorias**: criar pelo menos 4
   - "Consultas particulares" (receita)
   - "Convênios" (receita)
   - "Folha" (despesa)
   - "Aluguel" (despesa)
2. Step 2 — **Contas**: criar 1 corrente + 1 caixa físico
3. Step 3 — **Profissionais**: vincular 2 usuários como Especialistas
4. Step 4 — **Regras de Comissão**: criar 1 regra (ex: 30% sobre recebido para cada profissional)
5. Step 5 — **Metas**: meta mensal R$ 50.000

**Resultado esperado:**
- [ ] **PASS** — Wizard exibe progresso em cada passo
- [ ] Salvar passo gera linha no `AuditLog` (verificar em **Auditoria** depois)
- [ ] Após Step 5, redireciona pro Dashboard v2 normal
- [ ] Dashboard carrega sem o wizard mais

---

## 3. Fase B — Configurações Financeiras (F-05/F-06/F-07)

### B.1 Tab Categorias — CRUD + soft-delete

**Localização:** `/financial/v2/settings/categories`

**Passos:**
1. Clicar **"Nova categoria"** → criar "Cartão"  (receita)
2. Editar a categoria → renomear para "Cartão (operadoras)" → salvar
3. Tentar deletar uma categoria que tem lançamentos vinculados (escolher uma que tenha entries)
4. Deletar uma categoria sem lançamentos

**Resultados esperados:**
- [ ] **PASS** B.1.a — Criar com nome único OK
- [ ] **PASS** B.1.b — Editar nome aplica e mostra no DRE
- [ ] **PASS** B.1.c — Deletar categoria com lançamentos: **bloqueado** com mensagem clara
- [ ] **PASS** B.1.d — Deletar categoria limpa: **ConfirmDangerModal** abre (NÃO `window.confirm()` nativo)

### B.2 Tab Contas e Caixa

**Passos:**
1. Criar conta "Itaú PJ" (kind=checking, saldo inicial R$ 1.000)
2. Tentar criar outra conta com nome idêntico → deve bloquear
3. Inativar uma conta → deve sumir do dropdown de "conta destino" em modais
4. Reativar

**Resultados esperados:**
- [ ] **PASS** B.2.a — Unique constraint name + account_id funciona
- [ ] **PASS** B.2.b — Conta inativa não aparece em dropdowns
- [ ] **PASS** B.2.c — Saldo calculado dinamicamente (não armazenado)

### B.3 Tab Comissões — Regras

**Passos:**
1. Criar regra: "Especialista geral" → 30% sobre recebido → aplica a TODOS profissionais
2. Criar regra específica: "Daniele 25%" só para 1 user_id (override)
3. Receber um pagamento (Fase D) e verificar se commission_entry foi gerada com a regra certa

**Resultados esperados:**
- [ ] **PASS** B.3.a — Regra geral é fallback quando não há específica
- [ ] **PASS** B.3.b — Regra específica sobrescreve geral
- [ ] **PASS** B.3.c — `Financial::CommissionEntry` é criada com `status=provisionada` no ato do receipt

### B.4 Tab Despesas Recorrentes

**Passos:**
1. Criar recorrência: "Aluguel R$ 4.000, dia 5, mensal"
2. Aguardar cron job ou disparar manualmente (Sidekiq)
3. Verificar se `Financial::Expense` foi gerada com `parent_expense_id` apontando para a recorrência

**Resultados esperados:**
- [ ] **PASS** B.4.a — Cron `RecurringExpenseSchedulerJob` está agendado em `config/schedule.yml`
- [ ] **PASS** B.4.b — Expense gerada com status=pendente
- [ ] **PASS** B.4.c — Idempotência: rodar 2x no mesmo dia não duplica

### B.5 Tab Metas (mensal/trimestral/anual)

**Passos:**
1. Criar meta mensal R$ 50k para Maio/2026
2. Criar meta trimestral R$ 150k para 2º trim/2026
3. Criar meta anual R$ 600k para 2026
4. Voltar ao Dashboard, mudar período entre Mês/Trimestre/Ano e verificar se o título do gauge muda

**Resultados esperados:**
- [ ] **PASS** B.5.a — Cada nível de meta tem campo distinto (não confundir)
- [ ] **PASS** B.5.b — Dashboard exibe a meta CORRESPONDENTE ao período filtrado
- [ ] **PASS** B.5.c — Trocando "Mês" → "Ano", o gauge muda automaticamente de "Meta mensal" → "Meta anual"

---

## 4. Fase C — Lançamentos Manuais (F-25)

### C.1 Nova Entrada (manual)

**Pré-condição:** Dashboard v2 aberto. Pelo menos 1 conta ativa.

**Passos:**
1. Clicar **"Nova entrada"** no header
2. Preencher: Valor R$ 100, descrição "Sangria caixa", categoria "Outras receitas", conta=Itaú PJ
3. Salvar

**Resultados esperados:**
- [ ] **PASS** C.1.a — Toast de sucesso aparece com mensagem clara
- [ ] **PASS** C.1.b — Modal fecha automaticamente
- [ ] **PASS** C.1.c — KPIs do Dashboard atualizam (Saldo + Receita do mês)
- [ ] **PASS** C.1.d — Lançamento aparece em `v2 · Fluxo de Caixa` com badge "Lançamento avulso"
- [ ] **PASS** C.1.e — Aparece em `v2 · Reclassificar` se categoria=null (não deve no caso, foi escolhida)

### C.2 Nova Saída (manual)

**Passos:**
1. Clicar **"Nova saída"**
2. Preencher: Valor R$ 50, descrição "Material limpeza", categoria "Despesas variáveis", conta=Itaú PJ
3. Salvar

**Resultados esperados:**
- [ ] **PASS** C.2.a — KPI Despesa do mês incrementa em R$ 50
- [ ] **PASS** C.2.b — Saldo da conta Itaú PJ decrementa em R$ 50

### C.3 Lançamento manual pode ser excluído

**Passos:**
1. Voltar ao Fluxo de Caixa
2. Clicar na lixeira ao lado de "Sangria caixa"
3. Confirmar exclusão via **ConfirmDangerModal**

**Resultados esperados:**
- [ ] **PASS** C.3.a — `ConfirmDangerModal` abre (não `window.confirm`)
- [ ] **PASS** C.3.b — Lançamento some da lista
- [ ] **PASS** C.3.c — Saldo da conta volta ao valor anterior

🟡 **Importante:** apenas lançamentos manuais (kind=manual_entry) podem ser excluídos. Tentar excluir um Recibo (kind=receita) deve dar erro 422.

---

## 5. Fase D — Fluxo do Paciente (orçamento → receber → estornar)

> **Esta é a fase mais crítica.** Cobre o core do negócio: cadastrar orçamento → receber → emitir recibo → estornar se necessário.

### D.1 Criar orçamento pela aba Financeiro do paciente

**Pré-condição:** Paciente cadastrado. Login como **Recepção** ou **Administrador**.

**Passos:**
1. Acessar `/app/accounts/:id/patients/:patient_id/record?tab=financial`
2. Clicar **"Novo Lançamento"** ou **"Cobrar"**
3. Preencher orçamento:
   - Item 1: "Limpeza", R$ 200, profissional=Daniele
   - Item 2: "Fluoretação", R$ 50, profissional=Daniele
   - Forma: PIX
   - Parcelamento: 1× R$ 250
   - Status: Aprovado
4. Salvar

**Resultados esperados:**
- [ ] **PASS** D.1.a — `Financial::Budget` criado com `status=aprovado`
- [ ] **PASS** D.1.b — 2 `Financial::BudgetItem` criados
- [ ] **PASS** D.1.c — 1 `Financial::Installment` criado com `status=pendente`, `due_date=hoje+30d` (default canon)
- [ ] **PASS** D.1.d — KPI "Total Aprovado" no header do paciente vira R$ 250
- [ ] **PASS** D.1.e — KPI "Em Aberto" também R$ 250

### D.2 Receber pagamento (à vista PIX)

**Passos:**
1. Mesma tela do paciente → clicar **"Receber Pagamento"**
2. Selecionar a parcela R$ 250
3. Forma: **PIX** (verificar se o ícone SVG do BC aparece, não o lucide qr-code)
4. Valor recebido: R$ 250 (cheio)
5. Data de recebimento: hoje
6. Conta de destino: Itaú PJ
7. Confirmar

**Resultados esperados:**
- [ ] **PASS** D.2.a — Toast "Pagamento registrado"
- [ ] **PASS** D.2.b — Parcela vai de `pendente` → `recebido`
- [ ] **PASS** D.2.c — `Financial::PaymentReceipt` criado com `receipt_number=REC-2026-NNNNNN`
- [ ] **PASS** D.2.d — `Financial::Entry` criado com `direction=in, kind=receita`
- [ ] **PASS** D.2.e — `Financial::CommissionEntry` criada para Daniele (30% × R$ 250 = R$ 75) com `status=devida`
- [ ] **PASS** D.2.f — KPI "Pago/Recebido" do paciente: R$ 250
- [ ] **PASS** D.2.g — KPI "Em Aberto" volta para R$ 0,00
- [ ] **PASS** D.2.h — Saldo da conta Itaú PJ incrementa em R$ 250
- [ ] **PASS** D.2.i — Visual: aparece como "PAGO" verde na lista de parcelas

### D.3 Imprimir Extrato/Recibo

**Passos:**
1. Mesma tela do paciente → clicar **"Imprimir Extrato"** ou ícone de impressora no recibo
2. PDF deve gerar e abrir (ou baixar)

**Resultados esperados:**
- [ ] **PASS** D.3.a — PDF abre com cabeçalho da clínica + dados do paciente
- [ ] **PASS** D.3.b — Lista as parcelas pagas com data, valor, forma
- [ ] **PASS** D.3.c — `Financial::PaymentReceipt.pdf_status` vira `generated`
- [ ] **PASS** D.3.d — Arquivo PDF persiste em Active Storage (não regenera a cada clique)

### D.4 Baixa parcial em Dinheiro (BUG-01 fix)

**Pré-condição:** Criar novo orçamento de R$ 500 em 1 parcela.

**Passos:**
1. Receber pagamento da parcela R$ 500
2. Selecionar forma=Dinheiro
3. Valor recebido: **R$ 300** (parcial — menor que o total)
4. Confirmar

**Resultados esperados:**
- [ ] **PASS** D.4.a — Toast "Pagamento parcial registrado · saldo restante R$ 200"
- [ ] **PASS** D.4.b — Parcela original fica com `status=parcial`, `received_amount_cents=30000`
- [ ] **PASS** D.4.c — **Nova parcela criada** com `replaces_installment_id` apontando para a original
- [ ] **PASS** D.4.d — Nova parcela tem `amount_cents=20000` (R$ 200, o saldo), status=pendente
- [ ] **PASS** D.4.e — Total da aba do paciente continua R$ 500 (não duplica)

### D.5 Estorno de pagamento

**Pré-condição:** Pagamento da D.2 (R$ 250) recebido.

**Passos:**
1. Localizar o recibo R$ 250 na aba financeiro do paciente
2. Clicar no botão **"Estornar"** (ícone de undo)
3. Motivo: "Cliente solicitou cancelamento"
4. Confirmar via ConfirmDangerModal

**Resultados esperados:**
- [ ] **PASS** D.5.a — `ConfirmDangerModal` (não nativo) abre
- [ ] **PASS** D.5.b — Recibo fica marcado como **estornado** (não some)
- [ ] **PASS** D.5.c — Nova `Financial::Entry` criada com `kind=estorno_receita`, valor NEGATIVO
- [ ] **PASS** D.5.d — `Financial::CommissionEntry` da Daniele vira `status=estornada`
- [ ] **PASS** D.5.e — Saldo conta Itaú PJ DECREMENTA em R$ 250 (entry negativa)
- [ ] **PASS** D.5.f — Aba financeiro mostra estorno na timeline
- [ ] **PASS** D.5.g — Visual: badge "ESTORNADO" violet no recibo
- [ ] **PASS** D.5.h — Patient.credit_balance pode aumentar em R$ 250 (se a regra for "crédito ao paciente")

### D.6 Crédito do paciente (após estorno)

**Passos:**
1. Verificar KPI "Crédito" no header da aba financeiro
2. Criar novo orçamento R$ 100
3. Aplicar crédito ao receber pagamento

**Resultados esperados:**
- [ ] **PASS** D.6.a — KPI Crédito mostra R$ 250 (do estorno anterior)
- [ ] **PASS** D.6.b — Modal de receber pagamento oferece "Aplicar crédito"
- [ ] **PASS** D.6.c — Aplicando R$ 100 de crédito quita o orçamento sem entrada nova de caixa
- [ ] **PASS** D.6.d — `Financial::PatientCredit` decrementa em R$ 100, sobra R$ 150

---

## 6. Fase E — A Receber (F-16)

### E.1 Tela A Receber

**Localização:** `/financial/v2/receivables`

**Passos:**
1. Conferir KPIs:
   - **Total a Receber** = soma das parcelas pendentes + parciais
   - **Vencido** = parcelas com due_date < hoje em aberto
   - **A vencer 7 dias** = parcelas com due_date em [hoje, hoje+7]
2. Filtrar por status: pendente / vencido / parcial / recebido
3. Filtrar por profissional
4. Filtrar por intervalo de data
5. Buscar por nome do paciente

**Resultados esperados:**
- [ ] **PASS** E.1.a — KPIs batem com soma das listas filtradas
- [ ] **PASS** E.1.b — Filtros são aditivos (combinam)
- [ ] **PASS** E.1.c — Paginação funciona (testar com >50 parcelas)

### E.2 Cobrar diretamente da lista

**Passos:**
1. Clicar no botão "Cobrar" de uma parcela pendente
2. Mesmo modal de receber pagamento

**Resultados esperados:**
- [ ] **PASS** E.2.a — Modal pré-preenchido com o paciente + parcela
- [ ] Mesmos comportamentos da D.2

### E.3 Cron de status (pendente → vencido)

**Pré-condição:** ter parcela com due_date <= ontem.

**Passos:**
1. Disparar o job `Financial::InstallmentStatusJob` manualmente no Sidekiq
2. Voltar à tela A Receber

**Resultados esperados:**
- [ ] **PASS** E.3.a — Parcela muda de `status=pendente` para `status=vencido`
- [ ] **PASS** E.3.b — KPI Vencido incrementa

---

## 7. Fase F — A Pagar (F-20/F-21)

### F.1 Cadastrar despesa avulsa

**Localização:** `/financial/v2/payables`

**Passos:**
1. Clicar **"Nova saída avulsa"**
2. Descrição "Internet", valor R$ 199, categoria "Despesas fixas", due_date hoje+15d
3. Salvar

**Resultados esperados:**
- [ ] **PASS** F.1.a — `Financial::Expense` criada com `status=pendente`
- [ ] **PASS** F.1.b — KPI "Total a Pagar" no header da tela incrementa

### F.2 Pagar despesa

**Passos:**
1. Localizar a despesa "Internet"
2. Clicar **"Pagar"**
3. Confirmar conta de origem (Itaú PJ) + data hoje

**Resultados esperados:**
- [ ] **PASS** F.2.a — `Financial::Entry` criada com `kind=despesa, direction=out`
- [ ] **PASS** F.2.b — Despesa vira `status=pago` com `paid_at=hoje`
- [ ] **PASS** F.2.c — Saldo Itaú PJ decrementa R$ 199
- [ ] **PASS** F.2.d — Visual: badge "PAGO" verde

### F.3 Estorno de despesa

**Passos:**
1. Localizar despesa paga
2. Clicar "Estornar"
3. Confirmar

**Resultados esperados:**
- [ ] **PASS** F.3.a — `kind=estorno_despesa` Entry criada com valor negativo
- [ ] **PASS** F.3.b — Despesa volta para `status=pendente`
- [ ] **PASS** F.3.c — Saldo Itaú PJ volta ao valor anterior

---

## 8. Fase G — Caixa físico (F-24, OPCIONAL)

> Pula esta fase se a clínica não opera com dinheiro vivo. Cadastre a conta `kind=cash` se for testar.

### G.1 Abrir sessão de caixa

**Pré-condição:** conta `kind=cash` ativa (ex: "Caixa Recepção").

**Passos:**
1. Acessar `/financial/v2/cash-register`
2. Selecionar "Caixa Recepção" no dropdown
3. Clicar **"Abrir sessão"**
4. Valor inicial: R$ 200 (troco)
5. Confirmar

**Resultados esperados:**
- [ ] **PASS** G.1.a — Sessão criada com `started_at=now, opening_balance_cents=20000`
- [ ] **PASS** G.1.b — Entry kind=suprimento criada (R$ 200 entrada)
- [ ] **PASS** G.1.c — UI mostra "Sessão aberta às HH:MM"

### G.2 Sangria

**Passos:**
1. Durante sessão aberta, clicar **"Sangria"**
2. Valor: R$ 500, destino: Itaú PJ
3. Confirmar

**Resultados esperados:**
- [ ] **PASS** G.2.a — 2 Entries criadas (uma kind=sangria saída de Caixa, outra kind=transferencia entrada em Itaú)
- [ ] **PASS** G.2.b — `transfer_pair_id` linka as duas Entries
- [ ] **PASS** G.2.c — `affects_dre=false` (transferência interna não conta no DRE)

### G.3 Fechar sessão (conciliação cega)

**Passos:**
1. Clicar **"Fechar sessão"**
2. Sistema mostra "Esperado: R$ X". **NÃO mostra o valor antes de você digitar**
3. Digite valor físico contado (faça propositalmente R$ 5 a menos pra testar quebra)
4. Confirmar

**Resultados esperados:**
- [ ] **PASS** G.3.a — Conciliação ocorre (esperado vs contado)
- [ ] **PASS** G.3.b — Diferença R$ 5 vira Entry kind=quebra_caixa
- [ ] **PASS** G.3.c — Sessão fica com `closed_at=now`, `closing_balance_cents=...`
- [ ] **PASS** G.3.d — Auditoria registra a quebra com responsável (current_user)

---

## 9. Fase H — Fluxo de Caixa (F-23)

**Localização:** `/financial/v2/cash-flow`

### H.1 Listagem unificada

**Passos:**
1. Abrir Fluxo de Caixa
2. Conferir todos os tipos de Entries aparecem:
   - Recibos da Fase D
   - Despesas pagas da Fase F
   - Estornos da Fase D.5
   - Lançamentos avulsos da Fase C
   - Sangrias da Fase G
3. Aplicar filtro **conta** = "Caixa Recepção"
4. Aplicar filtro **período** = mês atual

**Resultados esperados:**
- [ ] **PASS** H.1.a — Cada tipo tem badge colorido próprio (Receita verde, Despesa ruby, Estorno violet, Sangria amber, etc)
- [ ] **PASS** H.1.b — Filtros combinam (conta + período)
- [ ] **PASS** H.1.c — Painel lateral de filtros abre/fecha suavemente
- [ ] **PASS** H.1.d — KPIs (Saldo da conta, Entradas, Saídas, Resultado líquido) batem com as linhas

### H.2 Excluir lançamento manual

**Passos:**
1. Localizar um lançamento `kind=manual_entry`
2. Clicar lixeira

**Resultados esperados:**
- [ ] **PASS** H.2.a — Tentar excluir um Recibo (kind=receita) deve dar erro
- [ ] **PASS** H.2.b — Manual entry deleta com confirmação

---

## 10. Fase I — DRE (F-26)

**Localização:** `/financial/v2/dre`

### I.1 Estrutura DRE

**Passos:**
1. Abrir DRE
2. Conferir sections:
   - Receita Bruta (detalhado por categoria + período anterior + variação %)
   - Deduções
   - Receita Líquida
   - Custos Variáveis
   - Margem Bruta
   - Despesas Fixas
   - EBITDA
   - Outras Despesas
   - Lucro Líquido

**Resultados esperados:**
- [ ] **PASS** I.1.a — Cada section expansível (clique abre detalhes por categoria)
- [ ] **PASS** I.1.b — Variação % vs período anterior aparece em badge (verde/ruby)
- [ ] **PASS** I.1.c — "Receita Bruta + Deduções = Receita Líquida" matematicamente correto

### I.2 Period Selector (Semana/Mês/Trimestre/Ano/Todos)

**Passos:**
1. Clicar em **Semana** → conferir label "DD/MM – DD/MM/YYYY"
2. Clicar em **Trimestre** → "T1/2026", "T2/2026", etc
3. Clicar em **Ano** → "2026"
4. Clicar em **Todos** → "Todo o período" + chevrons desabilitados
5. Usar chevrons em Mês/Trimestre/Ano para navegar

**Resultados esperados:**
- [ ] **PASS** I.2.a — Tab ativo com fundo azul brand (#1f93ff)
- [ ] **PASS** I.2.b — Chevrons funcionam por +/- da granularidade
- [ ] **PASS** I.2.c — Valores recalculam ao mudar período (não cacheia stale)

### I.3 Aviso de lançamentos sem categoria

**Pré-condição:** crie 1 lançamento sem categoria (forçando)

**Resultado esperado:**
- [ ] **PASS** I.3.a — Alert amber no topo: "X lançamentos sem categoria · Reclassificar"
- [ ] **PASS** I.3.b — Link "Reclassificar" leva à tela F-28

### I.4 Drill-down (clicar em categoria)

**Passos:**
1. Clicar em uma categoria no DRE (ex: "Consultas particulares")
2. Modal/sidepanel deve abrir mostrando as Entries individuais

**Resultados esperados:**
- [ ] **PASS** I.4.a — Lista paginada de Entries da categoria
- [ ] **PASS** I.4.b — Clicar em uma Entry navega pra origem (Recibo do paciente, etc)

---

## 11. Fase J — Dashboard v2 com charts

**Localização:** `/financial/v2/dashboard`

### J.1 KPIs Hoje

**Passos:**
1. Abrir Dashboard
2. Conferir 2 KPIs grandes: Resultado de Hoje + Saldo Disponível Hoje
3. Sparklines mini aparecem abaixo dos valores

**Resultados esperados:**
- [ ] **PASS** J.1.a — Sparklines populam após 1-2s (lazy load, não bloqueia paint)
- [ ] **PASS** J.1.b — Valores batem com Fluxo de Caixa filtrado por hoje

### J.2 KPIs Período + Sparklines

**Passos:**
1. Conferir 4 KPIs: Receita Bruta + Despesa + Lucro Líquido + Ticket Médio
2. Mudar período via selector → todos KPIs recalculam

### J.3 Bloco Vencimentos

**Resultados esperados:**
- [ ] **PASS** J.3.a — 4 KPIs: A Receber, Vencido, A Pagar, A vencer em 3 dias
- [ ] **PASS** J.3.b — Aparecem **antes** dos charts (acima do fold)

### J.4 Bloco Meta dinâmica

**Passos:**
1. Cadastrar meta mensal, trimestral, anual (já feito em B.5)
2. Mudar period selector → conferir que o título e o valor da meta MUDA

**Resultados esperados:**
- [ ] **PASS** J.4.a — Período = Mês → "Meta de receita mensal" com valor mensal
- [ ] **PASS** J.4.b — Período = Trimestre → "Meta de receita trimestral"
- [ ] **PASS** J.4.c — Período = Ano → "Meta de receita anual"
- [ ] **PASS** J.4.d — Gauge fill correto (% atingido)

### J.5 6 Charts

Conferir os 6 charts populam:

1. **Fluxo de Caixa Diário** (line, último período filtrado)
   - [ ] 3 séries: Entradas (verde), Saídas (ruby), Saldo acumulado (azul tracejado)
   - [ ] Eixo Y compactado (R$ 5.0k, R$ 1.0k)
   - [ ] Tooltip mostra valor com separador de milhar (R$ 1.234,56)

2. **Composição de Receita** (donut, top 5 categorias)
   - [ ] Donut com cutout central mostrando Total
   - [ ] Legenda lateral com R$ + %
   - [ ] Top 5 + "Outras" se houver

3. **Aging Inadimplência** (h-bar)
   - [ ] 4 faixas: 1-30d, 31-60d, 61-90d, 90+d
   - [ ] Gradiente amber → ruby
   - [ ] Snapshot atual (não filtra por período)
   - [ ] Tooltip mostra valor + quantidade de parcelas

4. **Receita por Profissional** (h-bar, top 5)
   - [ ] Barras azul brand
   - [ ] Ticket médio aparece no tooltip

5. **Projeção de Fluxo de Caixa** (line forward 60d)
   - [ ] Linha começa do saldo atual
   - [ ] Crescente/decrescente baseado em A Receber/Pagar futuros
   - [ ] Alert amber se saldo projetado fica negativo: "Saldo mínimo R$ X"
   - [ ] Header info "saldo final estimado R$ Y"

6. **Tendência de Inadimplência** (line 12 meses)
   - [ ] Linha ruby
   - [ ] Badge no header: "Piorando" / "Estável" / "Melhorando"
   - [ ] Tooltip mostra % + valor

**Resultados esperados:**
- [ ] **PASS** J.5.a — Todos os 6 charts carregam dados
- [ ] **PASS** J.5.b — Tooltips com formato BR (separador de milhar)
- [ ] **PASS** J.5.c — Empty states amigáveis quando não há dados
- [ ] **PASS** J.5.d — Skeletons shimmer enquanto carrega

---

## 12. Fase K — Reclassificar (F-28)

**Localização:** `/financial/v2/reclassify`

### K.1 Lista de lançamentos sem categoria

**Pré-condição:** ter alguns lançamentos com `financial_dre_category_id=null`.

**Passos:**
1. Abrir Reclassificar
2. Conferir KPIs: Sem categoria (count), Total Entradas, Total Saídas

**Resultados esperados:**
- [ ] **PASS** K.1.a — Apenas Entries sem categoria aparecem
- [ ] **PASS** K.1.b — Subtítulo correto: "Lançamentos sem categoria caem na linha 'Sem categoria' do DRE..."

### K.2 Reclassificação em massa

**Passos:**
1. Selecionar 5 lançamentos via checkboxes
2. Escolher categoria "Consultas particulares" no dropdown
3. Clicar "Aplicar"

**Resultados esperados:**
- [ ] **PASS** K.2.a — `bulkReclassify` API chamada com array de IDs
- [ ] **PASS** K.2.b — Entries somem da lista (mudou categoria)
- [ ] **PASS** K.2.c — DRE atualiza categoria correspondente

---

## 13. Fase L — Comissões (F-29)

**Localização:** `/financial/v2/commissions`

### L.1 Lista por profissional

**Passos:**
1. Abrir Comissões
2. Lista em acordeão por profissional (Daniele, Aline, etc)
3. Cada profissional mostra: Total Devida, Total Paga, Total Estornada, Líquido

**Resultados esperados:**
- [ ] **PASS** L.1.a — Total devida = sum de `Financial::CommissionEntry` com `status=devida`
- [ ] **PASS** L.1.b — Estornadas entram NEGATIVO no líquido (canon §critérios)
- [ ] **PASS** L.1.c — Especialista vê só própria; Gerente/Admin/Auditor veem tudo

### L.2 Marcar como paga

**Passos:**
1. Selecionar 1+ commission entries devidas
2. Clicar "Marcar como paga"

**Resultados esperados:**
- [ ] **PASS** L.2.a — `Financial::PayCommission` service executa atomicamente
- [ ] **PASS** L.2.b — `Financial::Expense` criada em A Pagar com categoria "Comissões"
- [ ] **PASS** L.2.c — CommissionEntry vira `status=paga`
- [ ] **PASS** L.2.d — Idempotência: clique duplo NÃO duplica a expense (verifica via `Idempotency-Key`)

---

## 14. Fase M — Relatórios (F-30)

**Localização:** `/financial/v2/reports/expenses`

### M.1 Tab Despesas por Categoria

**Passos:**
1. Abrir Reports Hub → tab "Despesas"
2. Mudar período via tabs (mês/trimestre/ano)
3. Conferir lista por categoria

### M.2 Tab Convênio (se aplicável)

**Passos:**
1. Cadastrar Patient.insurance['name']='Unimed' em 1 paciente
2. Receber pagamento desse paciente
3. Tab Convênio mostra "Unimed: R$ X · 1 paciente"

### M.3 Tab Ticket Médio

**Passos:**
1. Abrir tab "Ticket"
2. Ticket médio = receita / pacientes únicos no período
3. Detalhamento por profissional

**Resultados esperados:**
- [ ] **PASS** M.1/M.2/M.3 — Cada tab carrega dados próprios
- [ ] **PASS** Mostra "—" quando base é zero (BUG-05 fix)
- [ ] **PASS** Filtros de período afetam todos

---

## 15. Fase N — Aba Financeiro do Paciente (F-13) — TESTE PROFUNDO

> Esta fase consolida o uso real diário pela recepção. Faça com vários pacientes em estados diferentes.

### N.1 Paciente novo sem orçamento

**Acessar:** `/app/accounts/:id/patients/:patient_id/record?tab=financial`

**Resultados esperados:**
- [ ] **PASS** N.1.a — KPIs zerados (Total Aprovado R$ 0,00, etc)
- [ ] **PASS** N.1.b — Empty state amigável
- [ ] **PASS** N.1.c — Botões "Cobrar" + "Receber Pagamento" + "Novo Lançamento" + "Imprimir Extrato" visíveis

### N.2 Paciente com orçamento parcelado

**Pré-condição:** criar orçamento R$ 1.000 em 4× R$ 250 mensal.

**Resultados esperados:**
- [ ] **PASS** N.2.a — Bloco do orçamento mostra "Parcelamento" badge
- [ ] **PASS** N.2.b — Progresso visual: "0/4 pagas"
- [ ] **PASS** N.2.c — 4 parcelas listadas com datas escalonadas

### N.3 Paciente com adimplente vs inadimplente

**Cenário A — Adimplente:**
- Todas parcelas pagas em dia
- [ ] Badge verde "Adimplente" no header

**Cenário B — Inadimplente:**
- 1+ parcelas vencidas em aberto
- [ ] Badge ruby "Inadimplente" no header
- [ ] Visualmente destacado

### N.4 Filtros na aba

**Passos:**
1. Filtrar por status: Todos / Pendentes / Pagos / Vencidos / Estornados

**Resultados esperados:**
- [ ] **PASS** N.4.a — Filtros funcionam isoladamente
- [ ] **PASS** N.4.b — Contagens em cada filtro pré-calculadas

### N.5 Cancelar orçamento

**Passos:**
1. Localizar orçamento com parcelas SEM pagamento ainda
2. Clicar "Cancelar orçamento"
3. Motivo: "Paciente desistiu"
4. Confirmar via ConfirmDangerModal

**Resultados esperados:**
- [ ] **PASS** N.5.a — Tentar cancelar orçamento com parcela já paga: bloqueado
- [ ] **PASS** N.5.b — Orçamento sem pagamentos: cancela, parcelas viram canceladas
- [ ] **PASS** N.5.c — Auditoria registra a ação

### N.6 Sincronização cross-tela

**Passos:**
1. Em tab Financeiro do paciente, fazer um pagamento
2. Sem fechar a janela, ir em outra aba: `/financial/v2/receivables`
3. A parcela deve estar marcada como recebida

**Resultados esperados:**
- [ ] **PASS** N.6.a — Não há cache stale entre as duas telas
- [ ] **PASS** N.6.b — Reload da tela A Receber traz dado fresco

---

## 16. Fase O — Importação Clinicorp (F-08/F-09/F-10, super_admin)

> Esta fase só é executada por super_admin/time Klivy. Skip se você não tem acesso.

**Localização:** `/super_admin/migrations`

### O.1 Preview com 3 CSVs financeiros

**Pré-condição:** ter 3 CSVs: Budgets.csv + PaymentHeader.csv + PaymentItem.csv

**Passos:**
1. Selecionar conta de destino
2. Tipo: Financeiro
3. Upload dos 3 CSVs
4. Estratégia conta bancária: "Criar conta dedicada"
5. Clicar **Pré-visualizar**

**Resultados esperados:**
- [ ] **PASS** O.1.a — Counters aparecem: Total, Orçamentos, Cobranças, Parcelas, Criar, Atualizar, Pular
- [ ] **PASS** O.1.b — Conciliação canon §4 aparece: Total a receber, Recebido, Pendente, % batem com canon
- [ ] **PASS** O.1.c — Lista de dentistas distintos para mapeamento
- [ ] **PASS** O.1.d — Alert se houver collision de PatientId (scientific notation)

### O.2 Mapeamento de dentistas

**Passos:**
1. Para cada dentista distinto, selecionar user_id correspondente
2. Re-gerar pré-visualização
3. Conferir que "Atualizar" muda conforme mapeamento

### O.3 Confirmar e iniciar

**Passos:**
1. Clicar "Confirmar e iniciar"
2. Aguardar status CONCLUÍDO na tabela de histórico

**Resultados esperados:**
- [ ] **PASS** O.3.a — Job Sidekiq dispara em background
- [ ] **PASS** O.3.b — Status muda: enfileirada → processando → concluído
- [ ] **PASS** O.3.c — Contadores finais: Criadas, Atualizadas, Ignoradas, Erros

### O.4 Idempotência (re-rodar mesmos CSVs)

**Passos:**
1. Rodar de novo com mesmos arquivos
2. Conferir resultado: 0 criados novos, N atualizados (mesmas linhas), 0 duplicados

**Resultados esperados:**
- [ ] **PASS** O.4.a — `external_id` único por conta evita duplicação
- [ ] **PASS** O.4.b — Conta bancária "Importação Clinicorp" reutilizada (não cria nova)

### O.5 Heurística single mapped dentist

**Pré-condição:** mapeamento tem APENAS 1 dentista mapeado.

**Resultado esperado:**
- [ ] **PASS** O.5.a — Todas as installments/entries criadas com `professional_id` daquele dentista
- [ ] **PASS** O.5.b — Chart "Receita por Profissional" do Dashboard mostra esse profissional

---

## 17. Fase P — Auditoria (F-31)

**Localização:** `/financial/v2/audit`

### P.1 Tela global de logs

**Passos:**
1. Abrir Auditoria
2. Filtros: entidade (Budget/Installment/Receipt/Expense/...), ação (create/update/destroy/...), usuário, período
3. Cada linha mostra: data, usuário, ação, entidade, link pra entidade

**Resultados esperados:**
- [ ] **PASS** P.1.a — Filtros combinam (entidade + ação + usuário)
- [ ] **PASS** P.1.b — Clicar na linha abre drawer com **diff** dos campos alterados
- [ ] **PASS** P.1.c — Cada ação financeira da Fase D-K aparece aqui

### P.2 Aba Auditoria por entidade

**Passos:**
1. Em prontuário do paciente → aba "Auditoria"
2. Mostra apenas logs daquele paciente (Budget/Installment/Receipt dele)

**Resultados esperados:**
- [ ] **PASS** P.2.a — Filtro implícito por paciente
- [ ] **PASS** P.2.b — Diff visível por entry

### P.3 Auditable concern via `after_commit`

**Passos:**
1. Criar/atualizar uma entidade financeira
2. Aguardar 1s
3. Conferir log foi criado

**Resultados esperados:**
- [ ] **PASS** P.3.a — Log criado em `audit_logs` table
- [ ] **PASS** P.3.b — `entity_type, entity_id, action, changed_keys, before, after, account_id, user_id` populados

---

## 18. Fase Q — Backups (F-32)

**Localização:** `/financial/v2/backups`

### Q.1 Backup manual

**Passos:**
1. Clicar "Rodar backup agora"
2. Aguardar conclusão

**Resultados esperados:**
- [ ] **PASS** Q.1.a — Sidekiq job `Financial::BackupJob` dispara
- [ ] **PASS** Q.1.b — Arquivo `.sql.gz` criado em `/app/storage/postgres-backups/`
- [ ] **PASS** Q.1.c — Tamanho > 1KB (sanity check de pg_dump não vazio)
- [ ] **PASS** Q.1.d — Se R2 configurado, arquivo replicado pra `klivy-storage-dev/postgres-backups/`
- [ ] **PASS** Q.1.e — Aparece na lista local + remoto (com badges de origem)

### Q.2 Backup agendado

**Passos:**
1. Conferir `config/schedule.yml` tem `financial_backup_job: '0 3 * * *'`
2. (Opcional) Aguardar 3h da manhã ou disparar manualmente

**Resultados esperados:**
- [ ] **PASS** Q.2.a — Job dispara automático às 3h
- [ ] **PASS** Q.2.b — Lista de backups cresce a cada dia

### Q.3 Excluir backup pela UI

**Passos:**
1. Clicar lixeira em um backup
2. Confirmar via ConfirmDangerModal

**Resultados esperados:**
- [ ] **PASS** Q.3.a — Arquivo local deletado
- [ ] **PASS** Q.3.b — Se remoto, também deletado do R2
- [ ] **PASS** Q.3.c — Path traversal guard (não deixa apagar arquivos fora do diretório de backups)

---

## 19. Fase R — Contador + LGPD (F-33)

### R.1 Exportação para Contador

**Localização:** `/financial/v2/accountant`

**Passos:**
1. Selecionar período (mês fechado)
2. Clicar "Pré-visualizar"
3. Conferir contadores: Receitas, Despesas, Estornos, Entries totais
4. Clicar "Baixar CSVs"

**Resultados esperados:**
- [ ] **PASS** R.1.a — 4 CSVs baixados separadamente (receitas/despesas/recebimentos/comissões)
- [ ] **PASS** R.1.b — Encoding UTF-8 com BOM (compatível Excel BR)
- [ ] **PASS** R.1.c — Separador `;`, decimal com vírgula
- [ ] **PASS** R.1.d — Cada linha tem campos do contador (data, valor, CPF/CNPJ, descrição, categoria)

### R.2 LGPD — Solicitar anonimização

**Localização:** `/financial/v2/lgpd`

**Passos:**
1. Buscar paciente por nome/CPF
2. Clicar "Nova solicitação"
3. Tipo: anonimização
4. Motivo: "Solicitação do titular"
5. Salvar (status=pendente)

### R.3 Aprovar + Executar anonimização

**Passos:**
1. Localizar solicitação pendente
2. Aprovar (vira aprovada)
3. Executar (clica "Executar anonimização")
4. Confirmar via ConfirmDangerModal — operação IRREVERSÍVEL
5. Conferir paciente

**Resultados esperados:**
- [ ] **PASS** R.3.a — `Patient.name` vira hash SHA256 truncado: "Anônimo (#A1B2C3)"
- [ ] **PASS** R.3.b — `Patient.cpf`, email, phone, address todos nullificados
- [ ] **PASS** R.3.c — `Patient.anonymized_at` populado com timestamp
- [ ] **PASS** R.3.d — `Financial::Installment` do paciente CONTINUA EXISTINDO (FK preservada — exigência fiscal CFM)
- [ ] **PASS** R.3.e — Em A Receber, parcela mostra "Anônimo (#A1B2C3)" como nome
- [ ] **PASS** R.3.f — `Financial::LgpdRequest.status=executada`, `executed_at=timestamp`
- [ ] **PASS** R.3.g — Audit log da execução com usuário responsável

### R.4 Cancelar solicitação LGPD

**Passos:**
1. Criar nova solicitação pendente
2. Cancelar antes de aprovar/executar
3. Conferir status=cancelada

**Resultados esperados:**
- [ ] **PASS** R.4.a — Cancelamento possível em pendente/aprovada (não em executada)

---

## 20. Fase S — RBAC (F-03) — Testes negativos

> Cada perfil tenta acessar funcionalidades que **não pode** acessar. Esperado: bloqueio ou ocultação.

### S.1 Especialista (DENTIST)

**Login como qa-dentist@test.com**

| Tentar acessar/fazer | Esperado |
|---|---|
| Tela Configurações (Categorias/Contas/etc) | ❌ 403 ou item oculto da sidebar |
| Tela A Pagar | ❌ Oculto |
| Tela Backups | ❌ Oculto |
| Tela LGPD | ❌ Oculto |
| Comissões: ver SÓ as próprias | ✅ Vê só as dele(a) |
| Aba Financeiro do paciente | ✅ Vê só pacientes vinculados a ele(a) |

### S.2 Gerente

**Login como qa-gerente@test.com**

| Tentar acessar/fazer | Esperado |
|---|---|
| Criar/excluir categorias | ✅ Pode |
| Deletar conta bancária com saldo > 0 | ❌ Bloqueado |
| Comissões: ver TODAS | ✅ Pode |
| Executar anonimização LGPD | ❌ Apenas Admin |

### S.3 Auditor

**Login como qa-auditor@test.com**

| Tentar acessar/fazer | Esperado |
|---|---|
| Ver tudo (read-only) | ✅ Tudo visível |
| Tentar criar/editar/deletar QUALQUER coisa | ❌ Botões ocultos ou 403 |
| Audit logs | ✅ Pode ver |

### S.4 Recepção

| Tentar acessar/fazer | Esperado |
|---|---|
| Receber pagamento + emitir recibo | ✅ Core |
| Cancelar orçamento | ✅ |
| DRE / Comissões / Relatórios | ❌ Talvez bloqueado |
| Cadastrar regra de comissão | ❌ |

### S.5 Administrador

| Tentar acessar/fazer | Esperado |
|---|---|
| Tudo | ✅ |

---

## 21. Fase T — Multi-tenancy (account_id isolation)

> **Crítico.** Toda query/route/policy DEVE filtrar por account_id. Sem exceção.

### T.1 2 contas, mesmo super_admin

**Setup:**
- Conta A (account_id=31)
- Conta B (account_id=42)
- Dados financeiros em ambas

**Passos:**
1. Logar como user da Conta A
2. Acessar Dashboard → conferir que NÃO vê dados da Conta B
3. Forçar URL `/api/v1/accounts/42/financial/v2/reports/dashboard` no devtools
4. Conferir resposta 403 (não 200 com dados)

**Resultados esperados:**
- [ ] **PASS** T.1.a — Cross-account API call bloqueada por Pundit
- [ ] **PASS** T.1.b — UI nunca mostra dados de outra account
- [ ] **PASS** T.1.c — Categoria/conta/categoria com mesmo nome em A vs B coexistem (não conflitam)

### T.2 Backup é por-conta?

**Atenção:** o backup atual no canon §F-32 backup is GLOBAL (pg_dump da DB toda). Isso é intencional para super_admin. Não testar isolation aqui.

---

## 22. Fase U — Testes de Erro/Edge Cases

### U.1 Concorrência

**Passos:**
1. 2 usuários abrem a mesma parcela ao mesmo tempo
2. Ambos clicam "Receber Pagamento" e confirmam
3. Esperado: 1 sucede, 1 falha com lock/idempotency

**Resultados esperados:**
- [ ] **PASS** U.1.a — `Idempotency-Key` UUID v4 enviado pelo frontend
- [ ] **PASS** U.1.b — Replay retorna mesma resposta sem duplicar Recibo

### U.2 Backend timeout

**Passos:**
1. Forçar timeout no backend (parar Rails, manter front aberto)
2. Tentar ação

**Resultados esperados:**
- [ ] **PASS** U.2.a — Toast erro claro
- [ ] **PASS** U.2.b — UI não trava (loading state termina com fallback)

### U.3 Valores negativos

**Passos:**
1. Tentar criar Installment com `amount_cents=-100`
2. Tentar criar Expense com valor 0

**Resultados esperados:**
- [ ] **PASS** U.3.a — Validation: `amount_cents > 0` rejeita
- [ ] **PASS** U.3.b — Erro mostrado pro user

### U.4 Datas inválidas

**Passos:**
1. due_date no passado distante (1999)
2. due_date no futuro distante (2099)

**Resultados esperados:**
- [ ] **PASS** U.4.a — Aceita range razoável; bloqueia se claramente errado
- [ ] **PASS** U.4.b — Não quebra o cron de status

### U.5 Caracteres especiais

**Passos:**
1. Nome de categoria com aspas, emoji, scripts: `'; DROP TABLE; -- 🔥 <script>alert(1)</script>`
2. Salvar e visualizar

**Resultados esperados:**
- [ ] **PASS** U.5.a — Sanitizado, sem SQL injection
- [ ] **PASS** U.5.b — XSS: script NÃO executa, mostra texto literal

---

## 23. Critério final de Go/No-Go para produção

| Fase | Obrigatório? | Status |
|---|---|---|
| A — Wizard inicial | 🔴 Sim | [ ] |
| B — Configurações | 🔴 Sim | [ ] |
| C — Lançamentos manuais | 🔴 Sim | [ ] |
| D — Paciente core (orçamento → receber → estornar) | 🔴 Sim | [ ] |
| E — A Receber | 🔴 Sim | [ ] |
| F — A Pagar | 🔴 Sim | [ ] |
| G — Caixa físico | 🟡 Opcional (se a clínica usar) | [ ] |
| H — Fluxo de Caixa | 🔴 Sim | [ ] |
| I — DRE | 🔴 Sim | [ ] |
| J — Dashboard + charts | 🟠 Importante | [ ] |
| K — Reclassificar | 🟠 Importante | [ ] |
| L — Comissões | 🟠 Importante | [ ] |
| M — Relatórios | 🟡 Opcional | [ ] |
| N — Aba Paciente | 🔴 Sim | [ ] |
| O — Importação Clinicorp | 🟡 Se for cliente migrando | [ ] |
| P — Auditoria | 🟠 Importante | [ ] |
| Q — Backups | 🟠 Importante | [ ] |
| R — Contador + LGPD | 🟠 Importante | [ ] |
| S — RBAC | 🔴 Sim | [ ] |
| T — Multi-tenancy | 🔴 Sim | [ ] |
| U — Edge cases | 🟠 Importante | [ ] |

**Critério de aprovação:**
- **100% PASS** nas fases 🔴 críticas → libera produção
- ≥80% PASS nas fases 🟠 importantes → libera com follow-up
- 🟡 opcionais podem ter falhas registradas

---

## 24. Apêndice — Endpoints úteis para QA

### API endpoints

| Endpoint | Método | Uso |
|---|---|---|
| `/api/v1/accounts/:id/financial/v2/reports/dashboard?from=&to=` | GET | KPIs do dashboard |
| `/api/v1/accounts/:id/financial/v2/reports/dre?from=&to=` | GET | DRE com from/to |
| `/api/v1/accounts/:id/financial/v2/reports/cash_flow_chart?from=&to=` | GET | Line chart |
| `/api/v1/accounts/:id/financial/v2/reports/delinquency_aging` | GET | Aging snapshot |
| `/api/v1/accounts/:id/financial/v2/installments?status=&page=` | GET | Lista de parcelas |
| `/api/v1/accounts/:id/financial/v2/installments/:id/receive` | POST | Receber pagamento |
| `/api/v1/accounts/:id/financial/v2/entries` | POST | Lançamento manual |
| `/api/v1/accounts/:id/financial/v2/entries/bulk_reclassify` | POST | Reclassificar em massa |
| `/api/v1/accounts/:id/financial/v2/commission_entries/:id/pay` | POST | Marcar comissão paga |

### Tabelas (Rails console)

```ruby
# Conferências comuns
Financial::Budget.where(account_id: 31).count
Financial::Installment.where(account_id: 31, status: 'vencido').sum(:amount_cents)
Financial::Entry.where(account_id: 31).group(:kind).sum(:amount_cents)
Financial::AuditLog.where(account_id: 31).order(created_at: :desc).limit(10)
```

### Sidekiq jobs relevantes

| Job | Função |
|---|---|
| `Financial::InstallmentStatusJob` | Pendente → Vencido (cron diário) |
| `Financial::RecurringExpenseSchedulerJob` | Gera Expense de recorrência |
| `Financial::BackupJob` | pg_dump + upload R2 (cron 3h AM) |
| `Migration::ProcessCsvJob` | Importação Clinicorp em background |

### Cron schedule

```yaml
# config/schedule.yml
financial_backup_job:
  cron: "0 3 * * *"
  class: "Financial::BackupJob"

financial_installment_status_job:
  cron: "0 1 * * *"
  class: "Financial::InstallmentStatusJob"
```

---

## 25. Reportagem de bugs

Se encontrar bug durante os testes, abrir issue com:

```markdown
**Fase:** D.5 (Estorno de pagamento)
**Severidade:** 🔴 Crítica / 🟠 Importante / 🟡 Menor
**Reprodução:**
1. [...passos exatos...]

**Esperado:** [...]
**Atual:** [...]
**Screenshot/vídeo:** [...]
**Console errors:** [...]
**Network request/response:** [...]
**Account ID + user:** account_id=31, user_id=42 (admin)
**Versão:** Klivy 1.6.0.X
```

---

## 26. Observações finais

- **Tempo estimado total:** 8-12h para 1 analista executando completo
- **Pode dividir:** Fase A-G (operacional, 4h) + Fase H-N (analítico + paciente, 4h) + Fase O-U (importação + segurança, 4h)
- **Rodar pelo menos 2x** em ambientes distintos antes de produção: staging com dados sample + staging com dados reais migrados
- **Quem aprova:** Tech Lead + Product Owner + 1 representante da clínica (Dra. Cláudia ou equivalente)

Boa caça aos bugs! 🐛
