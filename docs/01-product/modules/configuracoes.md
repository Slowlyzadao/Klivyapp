> [!CAUTION]
> **STATUS: HISTÓRICO — não é mais a fonte de verdade.**
>
> Este documento descreve o **plano RBAC V1** (`BeClinicRole` baseado em Times com base_role `dono/gerente/especialista`), aprovado em março/2026. **Esse sistema foi inteiramente removido em 2026-04-30** — tabela `beclinic_team_profiles` droppada, conceito `dono` extinto, painel `/beclinic_admin/owners` apagado.
>
> O RBAC atual usa **`KlivyRole`** atribuído direto ao `account_user.klivy_role_id` (12 módulos × N sub-permissões via JSONB). Resolução em 3 passos: `super_admin` → `account_user.administrator` → `KlivyRole`.
>
> **Para a verdade atual, consulte:**
>
> | O que você quer | Documento |
> |---|---|
> | Como o RBAC funciona hoje (canon) | [`funcoes-personalizadas.md`](./funcoes-personalizadas.md) |
> | Arquitetura sistêmica (modular monolith) | [`../../02-architecture/system-architecture.md`](../../02-architecture/system-architecture.md) |
> | Configurações do produto (Agenda, Financeiro, templates) | módulos específicos: [`agenda.md`](./agenda.md), [`financeiro-funcionamento.md`](./financeiro-funcionamento.md) |
>
> Mantemos o texto abaixo por contexto histórico — útil para entender por que o sistema legado existia e quais decisões guiaram a migração para `KlivyRole`. **Não use como referência de implementação.**

---

# RBAC Plan — BeClinic (V1 HISTÓRICO)
## Role-Based Access Control — Plano de Ação Completo

> **Versão:** 1.0 — 2026-03-16
> **Status:** Substituído pelo plugin `custom_roles/` (KlivyRole) em 2026-04-30
> **Sessão de Brainstorming:** Concluída e validada com o produto

---

## 1. Visão Geral

O BeClinic implementará um sistema de controle de acesso baseado em papéis (**RBAC — Role-Based Access Control**) **híbrido**: a plataforma entrega perfis pré-configurados como ponto de partida, mas cada clínica pode editar, excluir ou criar perfis totalmente customizados.

O sistema opera em **duas camadas obrigatórias**:
- **Backend (Rails/Pundit):** valida toda requisição no servidor, independente do frontend.
- **Frontend (Vue.js):** exibe/oculta/desabilita UI de acordo com as permissões do usuário autenticado.

---

## 2. Hierarquia de Roles

```
┌─────────────────────────────────────────────────────────┐
│  SUPER ADMIN  (somente time BeClinic — nós)             │
│  → Acesso ao painel Super Admin do Chatwoot             │
│  → Acesso a qualquer conta/clínica do sistema           │
│  → Invisível para as clínicas                           │
└───────────────────────┬─────────────────────────────────┘
                        │ (por conta/clínica)
          ┌─────────────┼──────────────┐
          ▼             ▼              ▼
       [DONO]       [GERENTE]    [ESPECIALISTA]
   Pode tudo na    Pode quase    Acesso operacional
   conta deles      tudo (*)     configurável por perfil
```

| Role | Mapeamento Chatwoot (atual) | Visível para a clínica? |
|------|----------------------------|-------------------------|
| `super_admin` | `administrator` (super admin) | ❌ Não |
| `dono` | `administrator` (account level) | ✅ Sim |
| `gerente` | `agent` + permissions | ✅ Sim |
| `especialista` | `agent` + permissions | ✅ Sim |

> **Nota crítica:** `super_admin` deve ser implementado como uma flag separada (ex: `User#beclinic_superadmin?`) para não colidir com o `administrator` nativo do Chatwoot.

---

## 3. Modelo de Permissões

### 3.1 Estrutura de um Perfil (CustomRole BeClinic)

Cada clínica tem uma coleção de **Perfis** (`BeClinicRole`). Cada perfil é um conjunto de permissões. Um usuário recebe exatamente **um perfil**.

```
BeClinicRole
  ├── id
  ├── account_id           # dona do perfil
  ├── name                 # "Recepcionista", "Dentista", etc.
  ├── description
  ├── is_preset            # true = pré-configurado (ainda editável)
  ├── base_role            # :dono | :gerente | :especialista
  └── permissions (JSONB)  # hash completo de permissões
```

### 3.2 Mapa Completo de Permissões

Abaixo está o mapa de **todas as permissões** configuráveis em cada perfil. Cada permissão é uma flag `true/false`.

#### 📋 MÓDULO: Pacientes / Prontuário

| Chave de Permissão | Descrição |
|---|---|
| `patients.scope` | `"all"` (todos) ou `"own"` (apenas os seus) |
| `patients.view` | Ver lista e prontuário |
| `patients.create` | Cadastrar novo paciente |
| `patients.edit` | Editar dados cadastrais e anamnese |
| `patients.delete` | Arquivar/excluir paciente |
| `patients.view_clinical_notes` | Ver evoluções clínicas |
| `patients.create_clinical_notes` | Criar evolução clínica |
| `patients.sign_clinical_notes` | Assinar/finalizar evolução clínica |
| `patients.delete_clinical_notes` | Deletar rascunho de evolução |
| `patients.view_treatment_plans` | Ver planos de tratamento |
| `patients.manage_treatment_plans` | Criar/editar/aprovar planos |
| `patients.view_consents` | Ver termos de consentimento |
| `patients.manage_consents` | Criar, assinar e revogar consentimentos |
| `patients.view_documents` | Ver documentos gerados |
| `patients.manage_documents` | Gerar e excluir documentos (receitas, atestados, etc.) |
| `patients.view_exams` | Ver exames e imagens |
| `patients.manage_exams` | Upload/deleção de exames |
| `patients.view_audit` | Ver log de auditoria do prontuário |
| `patients.view_timeline` | Ver timeline de eventos do paciente |

#### 📅 MÓDULO: Agenda

| Chave de Permissão | Descrição |
|---|---|
| `agenda.scope` | `"all"` (todos especialistas) ou `"own"` (apenas seus eventos) |
| `agenda.view` | Ver a agenda |
| `agenda.create_event` | Criar novo agendamento |
| `agenda.edit_event` | Editar agendamento existente |
| `agenda.cancel_event` | Cancelar agendamento |
| `agenda.drag_and_drop` | Mover agendamentos via drag-and-drop |
| `agenda.manage_blocks` | Gerenciar bloqueios e folgas |
| `agenda.view_notifications` | Ver histórico de notificações automáticas |
| `agenda.manage_notifications` | Configurar regras de notificação |

#### 💰 MÓDULO: Financeiro

> ⚠️ **Correção 2026-05-30 (auditoria de APIs).** As chaves abaixo foram **reescritas** para refletir o catálogo REAL do KlivyRole
> ([`plugins/custom_roles/app/models/klivy_role/permissions_catalog.rb`](../../../plugins/custom_roles/app/models/klivy_role/permissions_catalog.rb)).
> As chaves antigas `financial.view_transactions`, `view_estimates`, `create_estimate`, `edit_estimate`, `delete_estimate` e `export_cashflow`
> **NÃO existem** — eram fantasmas e já fizeram a aba financeira do paciente sumir 2×.
>
> **Atenção crítica:** a **aba Financeira do prontuário do paciente** é gateada por **`patients.view_financial`** / **`patients.manage_financial`** —
> **NUNCA** por `financial.*`. As chaves `financial.*` gateiam apenas o **módulo financeiro standalone** (Dashboard, Fluxo de Caixa, A Receber, A Pagar, DRE).

**Módulo standalone `financial`** (catálogo real):

| Chave de Permissão | Descrição |
|---|---|
| `financial.view_dashboard` | Ver o Dashboard financeiro |
| `financial.view_cashflow` | Ver o Fluxo de Caixa (lançamentos) |
| `financial.view_receivables` | Ver Contas a Receber (parcelas) |
| `financial.view_payables` | Ver Contas a Pagar (despesas) |
| `financial.view_dre` | Ver o DRE |
| `financial.view_reports` | Ver relatórios financeiros |
| `financial.view_cash_register` | Ver sessões de caixa |
| `financial.create_transaction` | Registrar pagamento/lançamento |
| `financial.edit_transaction` | Editar lançamento |
| `financial.delete_transaction` | Excluir/estornar lançamento |
| `financial.manage_estimates` | Criar/editar orçamentos |
| `financial.approve_estimate` | Aprovar orçamento |
| `financial.export_data` | Exportar dados financeiros |
| `financial.manage_settings` | Configurações do módulo (contas, formas de pagamento, comissões…) |

**Aba Financeira do prontuário do paciente** (módulo `patients`):

| Chave de Permissão | Descrição |
|---|---|
| `patients.view_financial` | Ver a aba Financeira do paciente (summary + timeline) |
| `patients.manage_financial` | Operar a aba (receber, estornar, lançar) |

#### 💬 MÓDULO: Chat / Conversas (WhatsApp)

| Chave de Permissão | Descrição |
|---|---|
| `chat.view_all` | Ver todas as conversas (não só as atribuídas) |
| `chat.view_unassigned` | Ver conversas sem agente atribuído |
| `chat.reply` | Responder conversas |
| `chat.assign_conversation` | Atribuir conversa a outro especialista |
| `chat.transfer_inbox` | Transferir conversa entre inboxes |
| `chat.delete_message` | Deletar mensagens |
| `chat.send_broadcast` | Disparar campanhas em massa |

#### ⚙️ MÓDULO: Configurações (Settings)

> **Regra fixa:** Apenas `dono` e `gerente` têm acesso a Settings. O módulo abaixo define o que o `gerente` pode fazer dentro das configurações.

| Chave de Permissão | Descrição |
|---|---|
| `settings.manage_users` | Convidar, editar e remover usuários |
| `settings.manage_roles` | Criar e editar perfis RBAC |
| `settings.manage_agenda_config` | Configurar serviços, horários da agenda |
| `settings.manage_inboxes` | Ver inboxes (sem poder add/deletar — restrito ao Dono) |
| `settings.view_reports` | Ver relatórios e métricas gerais |

---

## 4. Perfis Padrão Pré-Configurados

A clínica recebe estes 4 perfis ao criar sua conta. Todos são editáveis e deletáveis.

### 👩‍💼 Perfil: Recepcionista
```
base_role: gerente
Pacientes:      scope=all, view=✅, create=✅, edit=✅, delete=❌
                clinical_notes=❌, treatment_plans=view_only, consents=view_only
                documents=view_only, exams=view_only, audit=❌
Agenda:         scope=all, view=✅, create=✅, edit=✅, cancel=✅, drag=✅, blocks=❌
Financeiro:     transactions=view+create, estimates=view_only, cashflow=❌
Chat:           view_all=✅, reply=✅, assign=✅, transfer=✅, broadcast=❌
Settings:       manage_users=❌, manage_roles=❌, agenda_config=❌
```

### 🦷 Perfil: Especialista / Dentista
```
base_role: especialista
Pacientes:      scope=own, view=✅, create=✅, edit=✅, delete=❌
                clinical_notes=all, treatment_plans=all, consents=all
                documents=all, exams=all, audit=view_only
Agenda:         scope=own, view=✅, create=✅, edit=✅, cancel=✅, drag=✅, blocks=✅
Financeiro:     transactions=view+create, estimates=all, cashflow=❌
Chat:           view_all=❌, view_unassigned=❌, reply=✅, assign=❌
Settings:       ❌ sem acesso
```

### 🏢 Perfil: Gerente
```
base_role: gerente
Pacientes:      scope=all, view=✅, create=✅, edit=✅, delete=✅ (com confirmação)
                Todas as abas do prontuário: view+manage
                audit=✅
Agenda:         scope=all, todas as permissões=✅
Financeiro:     Todas as permissões=✅, cashflow=✅, export=✅
Chat:           Todas as permissões=✅, broadcast=✅
Settings:       manage_users=✅, manage_roles=✅, agenda_config=✅, view_reports=✅
                NÃO pode: adicionar/remover inboxes WhatsApp (restrito ao Dono)
```

### 📣 Perfil: SDR / Comercial
```
base_role: especialista
Pacientes:      scope=all, view=✅, create=✅, edit=❌, delete=❌
                Nenhuma aba clínica (notas, planos, consentimentos, exames)
                audit=❌
Agenda:         scope=all, view=✅, create=✅, edit=✅, cancel=✅, blocks=❌
Financeiro:     estimates=view+create+edit (apenas orçamentos!), transactions=❌, cashflow=❌
Chat:           view_all=✅, reply=✅, assign=✅, broadcast=✅, transfer=❌
Settings:       ❌ sem acesso
```

---

## 5. Comportamento de UI para Elementos Bloqueados

| Tipo de elemento | Comportamento quando sem permissão |
|---|---|
| **Botão de ação** (Deletar, Assinar, Aprovar) | Oculto completamente (`v-if`) |
| **Aba do prontuário** (Financeiro, Auditoria, etc.) | Visível com ícone de cadeado 🔒, desabilitada ao clicar, tooltip explicativo |
| **Página/rota inteira** (ex: `/settings`) | Redireciona para `/403` com mensagem |
| **Campo de formulário** | Exibido como read-only (não editável) |
| **Item de menu lateral** | Oculto ou com cadeado, dependendo do módulo |

---

## 6. Arquitetura Técnica

### 6.1 Backend (Rails)

#### Novos modelos
```ruby
# app/models/beclinic_role.rb
# Tabela: beclinic_roles
# Colunas: id, account_id, name, description, is_preset, base_role (enum), permissions (jsonb), timestamps

# app/models/concerns/beclinic_permissible.rb
# Concern incluído no User com helpers:
#   current_user.can?(:patients, :view)
#   current_user.patient_scope  # => :all | :own
```

#### Novas migrations
```
db/migrate/TIMESTAMP_create_beclinic_roles.rb
db/migrate/TIMESTAMP_add_beclinic_role_id_to_account_users.rb
```

#### Policy (Pundit)
```ruby
# app/policies/patient_policy.rb  (expandir o existente)
# app/policies/agenda_event_policy.rb
# app/policies/transaction_policy.rb
# etc.
```

#### Seed de perfis padrão
```ruby
# db/seeds/beclinic_roles.rb
# Cria os 4 perfis (Recepcionista, Especialista, Gerente, SDR)
# para cada conta ao criar conta nova
```

#### Novo controller
```ruby
# app/controllers/api/v1/accounts/beclinic_roles_controller.rb
# CRUD completo de perfis + endpoint de assign role ao user
```

---

### 6.2 Frontend (Vue.js)

#### Composable central
```javascript
// app/javascript/dashboard/composables/usePermissions.js
//
// Expõe:
//   const { can, scope } = usePermissions()
//   can('patients', 'view')            // => true | false
//   can('financial', 'view_cashflow')  // => true | false
//   scope('agenda')                    // => 'all' | 'own'
```

#### Store (Pinia)
```javascript
// app/javascript/dashboard/store/permissions.js
// Carrega permissões do usuário logado no boot da aplicação
// junto com o auth store
```

#### Componente de UI
```vue
<!-- app/javascript/dashboard/components/PermissionGate.vue -->
<!--
  Uso:
  <PermissionGate module="financial" action="view_cashflow">
    <CashflowReport />
    <template #locked>
      <LockedTab message="Apenas Gerentes têm acesso ao relatório de caixa" />
    </template>
  </PermissionGate>
-->
```

#### Diretiva Vue (para botões)
```javascript
// app/javascript/dashboard/directives/vCan.js
// Uso: <button v-can="['financial', 'delete_transaction']">Deletar</button>
// Comportamento: v-if automático se não tiver permissão
```

---


## 7. Plano de Implementação — Fases

### ✅ FASE 1 — Fundação (Backend) — CONCLUÍDA
**Objetivo:** Criar a estrutura de dados e a lógica de autorização no servidor.

- [x] Migration: criar tabela `beclinic_roles`
- [x] Migration: adicionar `beclinic_role_id` em `account_users`
- [x] Model: `BeClinicRole` com validações e defaults
- [x] Concern: `BeClinicPermissible` no `User` (método `can?`)
- [x] Seed: 4 perfis padrão criados automaticamente para novas contas
- [x] Controller CRUD: `BeClinicRolesController` (listar, criar, editar, deletar, assign)
- [x] Expandir Pundit policies: `PatientPolicy`, `AgendaEventPolicy`, `TransactionPolicy`, `FinancialEstimatePolicy`
- [x] Testes manuais via Rails console

---

### ✅ FASE 2 — Fundação (Frontend) — CONCLUÍDA
**Objetivo:** Criar a infraestrutura de permissões no Vue sem ainda aplicar nas telas.

- [x] Pinia store: `usePermissionsStore` (carrega permissões no boot) → implementado como Vuex module `beclinicPermissions`
- [x] Composable: `usePermissions()` com métodos `can()` e `scope()`
- [x] Componente: `<PermissionGate>` com slot `#locked`
- [x] Diretiva: `v-can` para botões de ação
- [x] Componente: `<LockedTab>` (visual de cadeado + tooltip)
- [x] Componente: `<Page403>` para rotas sem acesso

---

### ✅ FASE 3 — Prontuário do Paciente — CONCLUÍDA
**Objetivo:** Aplicar permissões em todas as abas do prontuário.

- [x] Filtro de escopo na listagem (`scope=own` → filtra por `responsible_professional_id`)
- [x] Gate em cada aba: Evoluções, Planos, Consentimentos, Documentos, Exames, Financeiro, Auditoria
- [x] Ocultar botões: Deletar Paciente, Assinar Nota, Aprovar Plano, Gerar Documento, etc.
- [x] Read-only em campos de cadastro para perfis sem `patients.edit`

---

### ✅ FASE 4 — Configurações de Times (Settings/Teams) — CONCLUÍDA
**Objetivo:** Interface para configurar permissões RBAC por time nas configurações.

- [x] Criado componente `TeamPermissions.vue` — passo de Permissões no wizard de edição de times
- [x] Dois modos: "Perfis Predefinidos" (Recepcionista, Especialista, Gerente, SDR) e "Customizado" (toggles granulares)
- [x] Integrado como nova etapa no wizard `Edit/Index.vue` (Detalhes → Agentes → Permissões → Finalizar)
- [x] Rota `/permissions` adicionada em `teams.routes.js`
- [x] Redirecionamento pós-salvar agentes agora vai para a etapa de Permissões
- [x] Traduções adicionadas em `teamsSettings.json`

---

### ✅ FASE 5 — Financeiro — CONCLUÍDA (⚠️ histórico — modelo V1 superado)

> ⚠️ **Esta fase descreve o modelo Pundit/`financial.*` V1, substituído pelo KlivyRole desde 2026-04-30.**
> Em particular, a aba "Financeiro" do prontuário **NÃO** é mais filtrada por `financial.view_transactions` (chave fantasma) —
> o gate real é **`patients.view_financial`**. Mantido apenas como registro histórico; ver a tabela corrigida em "MÓDULO: Financeiro" acima.

**Objetivo:** Aplicar permissões no módulo financeiro.

- [x] Gate no sub-módulo Transações (ver / criar / deletar)
- [x] Gate no sub-módulo Orçamentos (ver / criar / editar / aprovar / deletar)
- [x] Aba "Financeiro" filtrada por `financial.view_transactions` no `allTabs` do `Record.vue`
- [x] Botão "Novo Orçamento" → `v-can="['financial', 'create_estimate']"`
- [x] Botão "Receber Pagamento" (header) → `v-can="['financial', 'create_transaction']"`
- [x] Botão "Receber" (linha da tabela) → `v-can="['financial', 'create_transaction']"`
- [x] Botão "Estornar" → `v-can="['financial', 'delete_transaction']"`
- [x] Botão "Aprovar Orçamento" → `v-can="['financial', 'approve_estimate']"`
- [x] Botão "Cancelar Orçamento" → `v-can="['financial', 'edit_estimate']"`

---

### ✅ FASE 6 — Chat / Conversas — CONCLUÍDA
**Objetivo:** Integrar RBAC com o sistema de permissões de conversas do Chatwoot.

- [x] Mapear `chat.view_all` → item "Todas as Conversas" filtrado da sidebar
- [x] Mapear `chat.send_broadcast` → grupo "Campanhas" oculto da sidebar para não-autorizados
- [x] Ocultar botão "Deletar mensagem" no context menu para perfis sem `chat.delete_message`
- [ ] Mapear `chat.view_unassigned` → filtro de conversas não atribuídas (não exposto nativamente na sidebar — necessita investigação de API do Chatwoot)
- [ ] Ocultar transferência de inbox para perfis sem `chat.transfer_inbox` (feature não identificada no codebase atual)

---

### ✅ FASE 7 — Tela de Gestão de Perfis (Settings) — CONCLUÍDA
**Objetivo:** Interface para o Dono e Gerente gerenciarem os perfis da clínica.

- [x] Rota: `/settings/roles` (acessível apenas por `dono` e `gerente` com `settings.manage_roles`)
- [x] Listagem de perfis com badges (Padrão vs. Customizado)
- [x] Formulário de criação/edição com checkboxes organizados por módulo
- [x] Assign de perfil ao usuário na tela de gestão de agentes
- [ ] Proteção: não permite deletar o único `dono` da conta (verificação no frontend parcial — backend pendente para Fase 8)

---

### ⚠️ FASE 8 — Hardening & QA — PARCIALMENTE CONCLUÍDA
**Objetivo:** Garantir que a segurança não depende só do frontend.

- [ ] ~~Testar todos os endpoints via API diretamente (sem UI) com diferentes roles~~ — **AUDITORIA: 5 controllers NÃO chamam `authorize` (policies são código morto)**
- [ ] ~~Garantir que `scope=own` no backend rejeita requests~~ — **AUDITORIA: funciona para Patient e ClinicalNote, mas AgendaEvents.index NÃO usa `policy_scope`**
- [x] Verificar que `super_admin` tem bypass total (`beclinic_super_admin?` ativo no concern)
- [ ] ~~Cobrir casos de borda: usuário sem perfil atribuído~~ — **AUDITORIA: `beclinic_scope` retorna `'all'` para users sem time (contradiz deny-by-default)**
- [x] Retrocompatibilidade: Rake tasks `beclinic:rbac:ensure_default_profiles` e `beclinic:rbac:assign_missing_users`

---

## 8. Log de Decisões

| # | Decisão | Alternativas Consideradas | Motivo da Escolha |
|---|---------|--------------------------|-------------------|
| D1 | Perfis Híbridos | A) Fixos; B) 100% customizáveis | Equilibra praticidade e flexibilidade para clínicas |
| D2 | 4 perfis padrão | Criar ao criar a conta vs. seed global | Por conta = cada clínica tem seus próprios editáveis |
| D3 | Escopo configurável (all/own) por perfil | Fixo por role; só por módulo | Máxima flexibilidade com implementação simples |
| D4 | Financeiro granular por ação + sub-módulo | Tudo ou nada; granular só por ação | Clínicas reais precisam de controles precisos no financeiro |
| D5 | Agenda granular por ação + escopo | Herdar escopo do prontuário | Recepcionistas precisam agendar para todos os dentistas |
| D6 | Chat integrado ao RBAC | Herdar do Chatwoot nativo; fora do RBAC | Consistência — um único lugar para configurar acesso |
| D7 | Settings: Dono + Gerente restrito | Totalmente livre por perfil | Over-engineering para v1; cobre 95% dos casos reais |
| D8 | UI contextual (oculto/cadeado) | Tudo oculto; tudo desabilitado | Padrão de software premium; educa o usuário sobre o sistema |
| D9 | `super_admin` via flag separada | Usar role nativo do Chatwoot | Evita colisão com lógica interna do Chatwoot |
| D10 | Pundit para backend | CanCanCan; custom middleware | Pundit já está em uso no projeto |

---

## 9. Non-Goals (Fora do Escopo da v1)

- ❌ Permissões por **paciente individual** (ex: ver só paciente X)
- ❌ Histórico/auditoria de **mudanças nos perfis RBAC**
- ❌ RBAC diferente para **app mobile**
- ❌ Permissões por **Inbox específica** do WhatsApp
- ❌ Herança de permissões entre perfis (ex: Gerente herda tudo do Especialista)

---

## 10. Assumptions Documentadas

1. `super_admin` será implementado como `User#beclinic_superadmin?` (coluna booleana separada ou config)
2. O `dono` será o primeiro usuário ao criar a conta — os próximos são `gerente` ou `especialista` por padrão
3. Usuários existentes que não têm perfil atribuído recebem o perfil "Especialista" como fallback na migração
4. As permissões são armazenadas em JSONB no banco (flexível, sem migrations para novas permissões futuras)
5. O composable `usePermissions()` é carregado uma única vez no boot e atualizado apenas em login/logout
6. O escopo `own` para pacientes usa o campo `responsible_professional_id` como chave de filtragem

---

---

## 11. Fase 9 — Auditoria & Correções (2026-03-16)

> **Resultado da auditoria completa do código pós Fase 8.**
> Identificados **6 problemas críticos de segurança**, **4 problemas moderados** e **2 itens de backlog**.

### 🔴 CRÍTICO — Segurança (Prioridade 1)

| # | Problema | Impacto | Status |
|---|----------|---------|--------|
| R1 | `TransactionsController` NÃO chama `authorize` — `TransactionPolicy` é código morto | Qualquer user autenticado cria/deleta transações via API | [x] |
| R2 | `FinancialEstimatesController` NÃO chama `authorize` — `FinancialEstimatePolicy` é código morto | Qualquer user aprova/deleta orçamentos via API | [x] |
| R3 | `ConsentRecordsController` NÃO chama `authorize` — `ConsentRecordPolicy` é código morto | Qualquer user assina/revoga consentimentos via API | [x] |
| R4 | `DocumentsController` NÃO chama `authorize` — `DocumentPolicy` é código morto | Qualquer user gera/deleta documentos via API | [x] |
| R5 | `ExamMediasController` NÃO chama `authorize` — `ExamMediaPolicy` é código morto | Qualquer user faz upload/deleta exames via API | [x] |
| R6 | `AgendaEventsController` usa `check_authorization` genérico (Chatwoot admin/agent), NÃO Pundit. Index não usa `policy_scope` → `scope=own` não funciona | Todos veem todos os eventos, ignorando escopo | [x] |
| R7 | Não impede remoção do último time `dono` da conta | Conta pode ficar sem administrador | [x] |

### 🟡 MODERADO — Consistência (Prioridade 2)

| # | Problema | Impacto | Status |
|---|----------|---------|--------|
| R8 | `beclinic_scope` retorna `'all'` quando user não tem time (deveria ser `'own'` ou deny) | Contradiz princípio deny-by-default | [x] |
| R9 | `clearPermissions` (logout) nunca é chamado em nenhum lugar | Permissões stale entre sessões/contas | [x] |
| R10 | `beclinicPermissions/fetch` é chamado no mount do `Sidebar.vue`, não no boot da app | Se Sidebar não monta, permissões nunca carregam | [x] |
| R11 | `LockedTab.vue` — prometido na Fase 2 e listado no CHANGELOG, mas NÃO existe no filesystem | Slot `#locked` do PermissionGate não tem componente padrão | [x] |
| R12 | `Page403.vue` — prometido na Fase 2 e listado no CHANGELOG, mas NÃO existe no filesystem | Rotas protegidas não têm página de acesso negado | [x] |
| R13 | Navigation guards nas rotas de Settings não implementados | Usuários sem permissão podem navegar diretamente para `/settings/*` | [x] |

### 🔵 BACKLOG — Funcionalidades Pendentes (Prioridade 3)

| # | Item | Nota | Status |
|---|------|------|--------|
| R14 | `chat.view_unassigned` — filtro de conversas não atribuídas | Implementado: sidebar oculta “Unattended” se user não tem permissão | [x] |
| R15 | `chat.transfer_inbox` — ocultar transferência de inbox | N/A — feature não existe como UI no codebase atual | [x] |

---

*Plano criado em sessão de brainstorming em 2026-03-16. Atualizado em 2026-03-16: **Fases 1–7 concluídas. Fase 8 parcial. Fase 9 (Auditoria) — Todos os 15 itens (R1–R15) resolvidos. ✅***
