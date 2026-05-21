# AUDITORIA COMPLETA — `plugins/custom_roles`

> **Data:** 2026-05-17
> **Auditor:** revisão profunda em modo "Staff Engineer + Security + Multi-tenant SaaS"
> **Escopo:** plugin `plugins/custom_roles` e toda a cadeia de RBAC do Klivy (backend, frontend, policies, router guards, sidebar, store, serializers)
> **Status do produto:** em produção
> **Modo:** leitura inicial + correções incrementais por lote (ver §18 Histórico de fixes)

---

## 0. Sumário Executivo

O sistema de **Custom Roles (KlivyRole)** é o **único** mecanismo de RBAC vigente no Klivy (memória `rbac_klivy_only` — dono / Time / TeamProfile / `/beclinic_admin/owners` removidos em 2026‑04‑30). A precedência é a esperada (`SuperAdmin → Chatwoot administrator → KlivyRole`), o modelo `KlivyRole` é simples e bem escopado por `account_id`, o controller `KlivyRolesController` está corretamente multi-tenant, e o front segue um padrão consistente de catálogo de módulos (`shared/modules.js`) + presets (`shared/presets.js`) + composable `usePermissions`.

A **arquitetura é sólida**. Os problemas estão **nas bordas**:

- O **router guard** (`routeHelpers.js`) usa **prefix matching loose** que abre rotas admin-only de **criação/edição** para usuários que deveriam ter só leitura (`klivy_roles_*`, `settings_inbox_*`, `settings_teams_*`, `settings_applications_*`).
- O **payload `permissions: {}`** aceito pelo `KlivyRolesController` é um **hash livre**, sem validação contra o catálogo — permite armazenar chaves desconhecidas no JSONB e (mais importante) **abre um vetor de privilege escalation** quando combinado com a permissão `settings.roles_create` + `settings.users_edit` na mesma role.
- Há **gating apenas no frontend** para vários módulos (Captain, Patients, Ajuda, Companies, Agenda) — o `routeHelpers.js` **não tem KLIVY_REQUIRED rules** para essas rotas, então **qualquer agent autenticado** pode entrar via URL mesmo sem a permissão Klivy.
- O serializer `_agent.json.jbuilder` expõe **`klivy_role.id/name/preset_key`** e **`beclinic_super_admin`** para qualquer agent — **information disclosure**.
- Há código órfão / dual: `beclinic_roles_list` ainda existe paralelo a `klivy_roles_list` (memória diz que foi removido — não foi).

**Veredito final:** **APROVADO COM RESSALVAS** (ver §17).

---

## 1. Arquitetura Atual

### 1.1 Estrutura do plugin

```
plugins/custom_roles/
├── app/
│   ├── controllers/api/v1/accounts/klivy_roles_controller.rb
│   └── models/klivy_role.rb
├── db/migrate/
│   ├── 20260425220001_create_klivy_roles.rb
│   └── 20260425220002_add_klivy_role_id_to_account_users.rb
├── lib/custom_roles/engine.rb
├── frontend/
│   ├── api/klivyRolesApi.js
│   ├── components/PermissionDenied.vue
│   ├── composables/{useRoleEditor,useRolesList,useSilentErrors}.js
│   ├── features/
│   │   ├── role-assignment/{AssignRoleButton,AssignRoleModal,RoleOption}.vue
│   │   ├── role-editor/{RoleEditorIndex.vue, components/*}
│   │   └── roles-list/RolesListIndex.vue
│   ├── routes/routes.js
│   └── shared/{modules.js, presets.js}
└── swagger/{definitions/KlivyRole.yml, paths/*.yml}
```

### 1.2 Modelo (`klivy_role.rb`)

- `KlivyRole` `belongs_to :account` + `has_many :account_users, dependent: :nullify`.
- Validações: `name` presença + `length: { maximum: 80 }` + **uniqueness scoped por `account_id`** (case-insensitive). `description` `length: { maximum: 240 }`. **OK.**
- `permissions` é **JSONB** com default `{}`, sem validação de schema.
- API interna: `can?(module, action)`, `module_enabled?(module)`, `scope_for(module)`.

### 1.3 Tabela (`klivy_roles`)

```
account_id  (not null, FK, indexed)
name        (not null, limit 80)
description (limit 240)
preset_key  (limit 40)
permissions (jsonb, not null, default {})
+ unique index (account_id, name)
```

### 1.4 AccountUser

- `klivy_role_id` adicionado em `account_users` (nullable, FK `to_table: :klivy_roles`, indexed).
- `belongs_to :klivy_role, optional: true`.
- Método `agenda_provider?` resolve em ordem: override per-user → `administrator?` → `klivy_role.can?(:agenda, :is_provider)` → `false`.

### 1.5 Pontos centrais do sistema RBAC (fora do plugin)

| Camada | Arquivo | Função |
|---|---|---|
| Backend concern | `plugins/beclinic_core/app/models/concerns/beclinic_permissible.rb` | `beclinic_can?`, `beclinic_scope`, `beclinic_admin_in?`, `beclinic_super_admin?` |
| Backend endpoint | `plugins/beclinic_core/app/controllers/.../beclinic_permissions_controller.rb` | `GET /beclinic_permissions` — devolve permissions + klivy_role do usuário |
| Frontend store | `plugins/beclinic_core/frontend/store/modules/beclinicPermissions/*` | Vuex namespace `beclinicPermissions` |
| Frontend composable | `app/javascript/dashboard/composables/usePermissions.js` | `can()`, `scope()`, `moduleEnabled()`, `isAdmin` |
| Diretiva | `app/javascript/dashboard/directives/vCan.js` | `v-can="['module','action']"` |
| Sidebar | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | `SIDEBAR_NAME_TO_MODULE` + `CHILD_GATES` |
| Router guard | `app/javascript/dashboard/helper/routeHelpers.js` | `KLIVY_EXACT/PREFIX/REQUIRED_ROUTE_RULES` |
| Policies | `app/policies/*.rb` | usam `beclinic_can?` para autorizar ações |

---

## 2. Fluxo de Permissões (End-to-End)

```
[Login]
   │
   ▼
auth.js setUser ── validityCheck() ── recebe currentUser
   │
   ▼
App.vue mounted → store.dispatch('beclinicPermissions/fetch')
   │
   ▼
GET /api/v1/accounts/:id/beclinic_permissions
   │
   ▼
BeclinicPermissionsController#show
   ├── current_user.beclinic_role_for(account)      → 'super_admin' | 'administrator' | KlivyRole.name
   ├── current_user.beclinic_permissions_for(account) → JSONB completo (admin = full_permissions_hash)
   └── current_klivy_role_data                       → {id, name, preset_key} ou nil
   │
   ▼
Store mutation SET_PERMISSIONS → state.permissions
   │
   ▼
usePermissions().can('module', 'action') → consulta state.permissions[module][action]
   │
   ├── Sidebar.vue filtra items via SIDEBAR_NAME_TO_MODULE + CHILD_GATES
   ├── vCan directive esconde/disabled de botões
   └── router beforeEach (validateLoggedInRoutes)
        ├── KLIVY_REQUIRED_ROUTE_RULES (deny list) — bloqueia mesmo se Chatwoot liberou
        ├── routeIsAccessibleFor (meta.permissions) — passa se Chatwoot OK
        └── routeIsAccessibleByKlivy (KLIVY_EXACT/PREFIX_ROUTE_RULES) — fallback se Chatwoot negou
```

### 2.1 Decisões da arquitetura — corretas

- **Backend é a fonte da verdade**: cada policy chama `beclinic_can?` ou `Current.account_user.administrator?`.
- **Frontend apenas decora**: gating do sidebar e do router é **otimização de UX**, não barreira de segurança.
- **Precedência tri-camadas** (`SuperAdmin → admin → KlivyRole`) está implementada de forma idêntica no `BeclinicPermissible` e no `usePermissions` (`isAdmin` curto-circuita).

---

## 3. Fluxo Frontend

### 3.1 Sidebar (`Sidebar.vue`)

- Constrói `menuItems` (linha 380-1011).
- Aplica `gateChildren(parentName, children)` para cada parent com `CHILD_GATES`.
- Modo `'filter'`: drop o child se Klivy não dá → o parent some se sobrar 0 filhos.
- Modo `'override'`: child renderiza ignorando `meta.permissions` (usado para Settings).
- Em ambos modos, propaga `bypassPolicy: true` ao child que passou.
- `bypassPolicy` é lido por `SidebarGroupLeaf.vue` (linha 25) e por `provider.js#isChildAllowed` (linha 153) → faz o `<Policy>` interno ignorar `meta.permissions`.

### 3.2 Router guard (`routeHelpers.js`)

- `KLIVY_EXACT_ROUTE_RULES` — allow exato. Se Chatwoot nega e Klivy concede, libera.
- `KLIVY_PREFIX_ROUTE_RULES` — allow por prefixo (**fonte da classe de bug §7.P0-1 a P0-5**).
- `KLIVY_REQUIRED_ROUTE_RULES` — deny list. Mesmo se Chatwoot libera, bloqueia se Klivy nega.
- `validateActiveAccountRoutes` aplica nesta ordem: required → Chatwoot allow → Klivy fallback.

### 3.3 Composable / store

- `usePermissions` consulta `beclinicPermissions/can` getter; admin via `getCurrentRole === 'administrator'` curto-circuita.
- `moduleEnabled` é **fail-open** (`if (!mod) return true` — linha 69) — se o backend não retornar a chave do módulo, frontend mostra. **Risco:** se o catálogo mudar e o backend ficar atrás, gating falha em favor de visibilidade.
- `useSilentErrors` filtra 401/403 — evita popup vermelho em tabs sem permissão.

### 3.4 Editor de Role (`RoleEditorIndex.vue` + `useRoleEditor`)

- Mantém estado local de `name`, `description`, `presetKey`, `permissions` (hash).
- **Auto-save com debounce de 400ms** quando em modo `edit`. Toggles disparam `scheduleAutoSave()`. Em modo `create`, espera o botão.
- `applyPreset` carrega `normalizePermissions(preset.permissions)` — migra chaves legadas via `LEGACY_KEY_MIGRATIONS` (limitado a settings.* — ver §11.4).
- `save()` envia `{ name, description, preset_key, permissions }` — front confia que backend valida; backend **não valida** o conteúdo do hash (ver §7.C-2).

---

## 4. Fluxo Backend

### 4.1 `KlivyRolesController`

```ruby
before_action :authorize_action!     # gating granular por action
before_action :fetch_role, only: [:show, :update, :destroy, :assign]

def fetch_role
  @role = Current.account.klivy_roles.find(params[:id])     # ✅ scoped
end

def role_params
  params.require(:klivy_role).permit(:name, :description, :preset_key, permissions: {})
end

def assign
  user_id = params.require(:user_id)
  account_user = Current.account.account_users.find_by!(user_id: user_id)  # ✅ scoped
  account_user.update!(klivy_role_id: @role.id, is_agenda_provider: nil)
  render json: { user_id:, klivy_role_id: @role.id }
end
```

**Cobertura de authorize:**

| Action | Admin? | Klivy perm |
|---|---|---|
| `index/show` | ✅ bypass | `settings.roles_view` OU `settings.users_edit` |
| `create` | ✅ bypass | `settings.roles_create` |
| `update` | ✅ bypass | `settings.roles_edit` |
| `destroy` | ✅ bypass | `settings.roles_delete` |
| `assign` | ✅ bypass | `settings.users_edit` |

### 4.2 `BeclinicPermissible` (concern em User)

- `beclinic_can?(account, module, action)` — precedência correta.
- `beclinic_permissions_for(account)` — retorna `full_permissions_hash` para SuperAdmin e admin nativo. **Importante:** o `full_permissions_hash` está **desatualizado** vs `shared/modules.js` (ex.: não lista `agenda.is_provider`, `chat.use_macros`, `chat.view_*`, várias `patients.*`, várias `financial.*`, `settings.workflow_*`, `settings.security_*`). Não causa bug (admin no front usa `isAdmin → true` direto), **mas** se algum lugar consultar `beclinic_permissions_for(account)` diretamente esperando um hash completo, irá ler `false` para chaves novas.

### 4.3 Policies tocadas

Policies que **usam** `beclinic_can?` corretamente:
- `PatientPolicy` (todas as actions; `Scope` filtra por `responsible_professional_id` quando `scope=own`).
- `AgendaEventPolicy` (não lido aqui, mas chamado por `AgendaEventsController`).
- `ConversationPolicy` (`reply?`, `assign?`, `delete_message?`, `send_broadcast?`).
- `InboxPolicy` (`create?`, `update?`, `destroy?`, `set_agent_bot?`, `avatar?`, `sync_templates?`, `health?` e `Scope.resolve`).
- `TransactionPolicy`, `BankAccountPolicy`, `RecurringExpensePolicy`, `FinancialGoalPolicy`, `FinancialDashboardPolicy`, `FinancialCategoryPolicy`, `CommissionRulePolicy`, `CashRegisterPolicy`, `ReportPolicy`, `ContactPolicy`, `ConsentRecordPolicy`, `DocumentPolicy`, `ExamFolderPolicy`, `ExamMediaPolicy`, `WaitingListEntryPolicy`, `ClinicalNotePolicy`, `AnamnesisPolicy`, `TreatmentPlanPolicy`, `TreatmentItemPolicy`, `SessionLogPolicy`, `CampaignPolicy`.

Policies que **não usam** `beclinic_can?` (caem em `administrator?` apenas — gap funcional):
- `LabelPolicy`, `TeamPolicy`, `AutomationRulePolicy`, `AgentBotPolicy`, `UserPolicy`, `AgendaSettingPolicy` (ver §7.A-3).

---

## 5. Fluxo Multi-Tenant

| Vetor | Status |
|---|---|
| `klivy_roles_controller#index/show/update/destroy` | ✅ `Current.account.klivy_roles.find` |
| `klivy_roles_controller#assign` | ✅ role+account_user ambos scoped por `Current.account` |
| `KlivyRole.account_id` | ✅ NOT NULL + FK + indexed |
| `unique(account_id, name)` | ✅ índice composto |
| `AccountUser.belongs_to :klivy_role, optional: true` | ⚠️ Sem validação custom de cross-account em `account_user.klivy_role_id` (depende de quem faz o `update!`) |
| Atribuição cross-account via `agents_controller#update` | ✅ `agent_params` NÃO permite `klivy_role_id` (só `:name, :role, :availability, :auto_offline, :is_agenda_provider`) |
| Atribuição cross-account via `enterprise/agents_controller#update` (`custom_role_id`) | ❌ NÃO valida pertencimento à conta (ver §7.C-3) |
| Serialização cross-account | ✅ `_agent.json.jbuilder` usa `resource.current_account_user` (conta corrente) |
| `KlivyRolesController#destroy` faz `AccountUser.where(klivy_role_id: @role.id).update_all(...)` | ⚠️ Não scoped por account — funciona porque `klivy_role_id` é PK única, **mas** smell |

**Sem vazamento entre tenants confirmado** no fluxo principal Klivy. O único vetor real é o enterprise `custom_role_id` (§7.C-3), e custom_role é o sistema legado **que deveria estar removido** (memória `rbac_klivy_only`).

---

## 6. Sub-permissões e Esquema Agrupado

### 6.1 `modules.js`

- 13 módulos: `inbox, chat, captain, agenda, patients, financial, contacts, reports, campaigns, help_center, settings, help`.
- Cada módulo declara `permissions: []` (flat) **ou** `groups: []` (`chat`, `agenda`, `settings`).
- `flattenPermissions`, `groupPermissions`, `emptyPermissionsHash`, `normalizePermissions`, `countActivePermissions`, `countActiveInModule`, `countActiveInGroup`, `isModuleDisabled` — **utils corretos e cobertos pelo `useRoleEditor`**.

### 6.2 `LEGACY_KEY_MIGRATIONS`

Limitado a `settings.*` (`manage_users`, `manage_roles`, `manage_inboxes`, `manage_integrations`, `manage_automation`, `manage_canned`, `manage_labels`, `manage_macros`, `manage_billing`, `view_audit`).

**Gap (BAIXO):** se houve roles antigas com keys flat em `agenda.*`, `patients.*`, `financial.*` etc., elas não migram automaticamente. Os presets já vêm em formato novo.

---

## 7. Problemas, Bugs e Vulnerabilidades — Lista Priorizada

> Severidade: **C** = Crítico / **A** = Alto / **M** = Médio / **B** = Baixo

### 7.1 Bypass real de RBAC via URL (prefix routes loose)

#### C-1. `klivy_roles_new`/`klivy_roles_edit` acessíveis para non-admin com só `roles_view` — ✅ **CORRIGIDO em 1.6.1.14**
- **Arquivos:** `app/javascript/dashboard/helper/routeHelpers.js:76` + `plugins/custom_roles/frontend/routes/routes.js:23-33`.
- **Causa:** `KLIVY_PREFIX_ROUTE_RULES.klivy_roles = ['settings','roles_view']` casa **todos os route names que começam com `klivy_roles`** (`_list`, `_new`, `_edit`). As três rotas têm `meta: { permissions: ['administrator'] }`. Em `validateActiveAccountRoutes`, se Chatwoot nega, o fallback `routeIsAccessibleByKlivy` libera para qualquer usuário com `roles_view`.
- **Impacto:** non-admin entra em `/settings/custom-roles/new` e `/settings/custom-roles/:id/edit` via URL. **O backend mitiga parcialmente:** o controller `authorize_action!` exige `roles_create`/`roles_edit` na chamada POST/PATCH. Mas a UI fica navegável (e o usuário pode descobrir/raspar dados que não deveria ver).
- **Vetor de escalada:** Se a role do usuário tiver `roles_create + users_edit` (cenário plausível — "Gerente"), ele pode criar uma role com `permissions = { settings: { roles_create: true, users_edit: true, ... } }` e assign para si. **Privilege escalation real.** A barreira definitiva contra escalada é **C-2** (whitelist do payload `permissions`); C-1 fecha apenas o vetor de UI/router.
- **Fix aplicado:** removida a entrada `klivy_roles` de `KLIVY_PREFIX_ROUTE_RULES` e adicionadas 3 EXACT rules em `KLIVY_EXACT_ROUTE_RULES` — uma por action coerente com o controller: `klivy_roles_list → roles_view`, `klivy_roles_new → roles_create`, `klivy_roles_edit → roles_edit`. Non-admin sem a perm específica é redirecionado pelo router guard; quem tem a perm continua entrando normalmente.

#### C-2. `permissions: {}` no `role_params` é hash livre — sem whitelist contra catálogo — ✅ **CORRIGIDO em 1.6.1.19**
- **Arquivo:** `plugins/custom_roles/app/controllers/api/v1/accounts/klivy_roles_controller.rb:51`.
- **Causa:** `params.require(:klivy_role).permit(:name, :description, :preset_key, permissions: {})` aceita qualquer hash de hashes. Não valida módulos nem chaves contra `shared/modules.js`.
- **Impactos combinados:**
  1. **Pollution do JSONB**: atacante pode encher o `permissions` com keys arbitrárias inflando a row.
  2. **Versão dessincronizada**: se um módulo for renomeado/removido, dados velhos ficam.
  3. **Cumpla com C-1**: forma o caminho do privilege escalation.
- **Fix aplicado — 3 partes:**
  1. **Catálogo Ruby** (`plugins/custom_roles/app/models/klivy_role/permissions_catalog.rb`): snapshot de `shared/modules.js` em Ruby (13 módulos, ~120 keys), `LEGACY_KEY_MIGRATIONS` espelhado, método `sanitize_and_migrate(input_hash)` que descarta keys desconhecidas silenciosamente e expande keys legadas (`settings.manage_users` → `users_view/_invite/_edit/_remove`).
  2. **Model `KlivyRole`** ganha `before_validation :sanitize_permissions`. Garante que o JSONB sempre esteja em forma canônica antes de salvar, independente do client.
  3. **Controller `KlivyRolesController`** ganha `enforce_delegation_limit!(sanitized_perms)` chamado em `create` e `update`. Princípio: para cada perm marcada `true` no payload, o requester precisa ter a mesma perm via `beclinic_can?`. Para `scope`, bloqueia upgrade `own → all`. Admin/SuperAdmin têm bypass via `beclinic_can?`/`beclinic_scope`. Quando há keys forbidden, levanta `PrivilegeEscalationError` → renderiza 403 com lista das keys rejeitadas.

#### C-3. Enterprise `agents_controller#associate_agent_with_custom_role` não escopa `custom_role_id` — ✅ **CORRIGIDO em 1.6.1.23** (Fase A)
- **Arquivo:** `enterprise/app/controllers/enterprise/api/v1/accounts/agents_controller.rb:14-17`.
- **Causa:** `@agent.current_account_user.update!(custom_role_id: params[:custom_role_id])` aceita qualquer ID sem `Current.account.custom_roles.find(...)`.
- **Atenuante:** memória `rbac_klivy_only` diz que `custom_role` foi descontinuado em 2026-04-30. **Mas o código ainda está vivo** e o serializer continua expondo `custom_role_id` (`_agent.json.jbuilder:15`).
- **Fix aplicado (Fase A):** arquivo `enterprise/app/controllers/enterprise/api/v1/accounts/agents_controller.rb` **deletado**. O `prepend_mod_with('Api::V1::Accounts::AgentsController')` no Chatwoot vira no-op silencioso porque `InjectEnterpriseEditionModule#each_extension_for` usa `const_get_maybe_false` (tolerante a ausência). Resultado: payload `custom_role_id` enviado por client legado é silenciosamente ignorado (strong params no controller padrão não inclui esse campo). Vuln cross-account eliminada.
- **Fase B (futuro PR):** migration drop coluna `account_users.custom_role_id` + limpeza de `enterprise/app/policies/enterprise/conversation_policy.rb` que ainda lê `custom_role_id`. Faz após Fase A em prod por algumas semanas pra validar que nada quebrou.

#### C-4. Bypass parcial de `chat.reply` em `ConversationsController#create` — ✅ **CORRIGIDO em 1.6.1.13**
- **Arquivo:** `app/controllers/api/v1/accounts/conversations_controller.rb:39-46`.
- **Causa:** `allowed_to_create_conversation?` cobre `send_broadcast` OU `reply`. Quando há `params[:message]`, `Messages::MessageBuilder` é chamado dentro da mesma transação **sem `authorize @conversation, :reply?`** (diferente do `MessagesController#create`, que `authorize`s explicitamente).
- **Impacto:** usuário com `send_broadcast` mas sem `reply` consegue enviar mensagem na conversa que acabou de criar.
- **Fix aplicado:** `authorize @conversation, :reply?` adicionado antes do `MessageBuilder.perform` dentro do bloco `if params[:message].present?`. Compatível com todos os presets atuais (todos têm `chat.reply=true` ou são admin).

---

### 7.2 Gating só no frontend — URL ignora

#### A-1. Captain (BEA) — CHILD_GATES sem KLIVY_REQUIRED — ✅ **CORRIGIDO em 1.6.1.20**
- **Sidebar.vue:320-330** gate por `captain.manage_*` / `view`.
- **routeHelpers.js** não tem entrada para `captain_*`.
- **Rotas Captain** têm `meta.permissions: ['administrator', 'agent']` — qualquer agent acessa por URL.
- **Resultado:** gating apenas estético.
- **Fix aplicado:** 12 entradas em `KLIVY_REQUIRED_ROUTE_RULES` cobrindo todas as sub-rotas Captain — `captain_assistants_index`/`_create_index` → `captain.view`; `_responses_index`/`_pending` → `manage_faqs`; `_documents_index` → `manage_documents`; `_scenarios_index` → `manage_scenarios`; `_playground_index` → `use_playground`; `_inboxes_index` → `manage_inboxes`; `_tools_index` → `manage_tools`; `_settings_index`/`_guardrails_index`/`_guidelines_index` → `manage_settings`.

#### A-2. Patients / Ajuda / Companies — idem — ✅ **CORRIGIDO em 1.6.1.20** (Patients + Ajuda; Companies fora de escopo)
- Sidebar usa só `moduleEnabled('patients')` / `moduleEnabled('help')` (fail-open).
- Sem KLIVY_REQUIRED.
- `companies_dashboard_index` nem está em `SIDEBAR_NAME_TO_MODULE` — visível para todos.
- **Fix aplicado:**
  - **Patients**: `patients_dashboard_index` e `patients_dashboard_record` → `patients.view`.
  - **Ajuda**: `ajuda_dashboard_index`, `_report_bug`, `_feature_request` → `help.view`.
  - **Companies**: **NÃO** mapeado — não há módulo `companies` em `shared/modules.js` (Klivy não usa hoje). Comportamento atual preservado. Anotar pra abordagem futura caso clientes pedirem RBAC granular em Companies.

#### A-3. Agenda — KLIVY_EXACT é noop porque Chatwoot já libera — ✅ **CORRIGIDO em 1.6.1.20**
- Rotas `agenda_*` têm `meta.permissions` que cobrem qualquer agent. KLIVY_EXACT só age quando Chatwoot nega — aqui nunca nega.
- `agenda_categories_index` nem está em KLIVY_EXACT.
- **Fix aplicado:** mesmas 4 rotas promovidas para `KLIVY_REQUIRED_ROUTE_RULES` (deny list real): `agenda_dashboard_index`/`_categories_index` → `agenda.view`; `_settings_index` → `view_settings`; `_custom_attributes_index` → `manage_custom_attributes`. Entradas em `KLIVY_EXACT` mantidas para defesa em profundidade (caso Chatwoot algum dia mude pra negar).

#### A-4. `settings_inbox*`, `settings_teams*`, `settings_applications*`, `assignment_policy*` — ✅ **CORRIGIDO em 1.6.1.15**
- Prefix loose abria fluxo de **criação/edição** para usuários com permissão de **leitura**.
- Cada parte:
  - `settings_inbox` cobre `_list/_show/_new/_finish` e `settings_inboxes_page_channel/_add_agents` → criação completa de inbox com só `inboxes_view`.
  - `settings_teams` cobre `_list/_new/_finish/_add_agents/_show/_edit/_edit_members/_edit_finish` → CRUD completo com só `teams_view`.
  - `settings_applications` cobre `settings_applications_integration` (detalhe) → leitura de configuração de integração com só `integrations_view`.
  - `assignment_policy`/`agent_assignment_policy`/`agent_capacity_policy` cobre `_create`/`_edit` com `users_view`.
- **Fix aplicado:** todos os 7 prefixes removidos de `KLIVY_PREFIX_ROUTE_RULES` e migrados para EXACT rules em `KLIVY_EXACT_ROUTE_RULES`. Cada route name agora exige a perm coerente com a action (`inboxes_create` para `_new/_finish/_page_channel`; `inboxes_manage_agents` para `_add_agents`; `teams_create` para fluxo `/new`; `teams_edit` para fluxo `/edit`; `integrations_view` para `_applications`/`_applications_integration`; `users_edit` para `_policy_create`/`_policy_edit`). Objeto `KLIVY_PREFIX_ROUTE_RULES` ficou vazio (mantido por contrato da API `klivyPrefixRule`).

---

### 7.3 Policies sem `beclinic_can?` (gap funcional, não vulnerabilidade direta)

#### A-5. `LabelPolicy`, `TeamPolicy`, `AutomationRulePolicy`, `AgentBotPolicy`, `UserPolicy`, `AgendaSettingPolicy` — ✅ **CORRIGIDO em 1.6.1.21** (UserPolicy fora de escopo)
- Dependem **apenas** de `@account_user.administrator?`.
- Resultado: uma KlivyRole "Gerente" com `settings.labels_create=true` **não consegue criar label** (backend nega). Frontend mostra o botão (porque sidebar usa Klivy). **Funcionalidade quebrada para non-admin** mesmo com permissão Klivy.
- **Não é vulnerabilidade** (fail-secure), **é dívida de cobertura RBAC**.
- **Fix aplicado em 5 policies:**
  - `LabelPolicy`: `create/update/destroy` → admin OU `settings.labels_create/_edit/_delete`. `show?` aberto pra agent (labels são lidas por todos pra filtrar conversas).
  - `TeamPolicy`: `create/update/destroy` → admin OU `settings.teams_create/_edit/_delete`. Index/show já eram abertos.
  - `AutomationRulePolicy`: as 6 actions ganham `settings.automation_view/_create/_edit/_delete`. `clone?` mapeia pra `automation_create`.
  - `AgentBotPolicy`: `create/update/destroy/avatar/reset_access_token` → admin OU `settings.agent_bots_manage`. Index/show abertos pra agent (bots aparecem em telas de inbox).
  - `AgendaSettingPolicy`: `show?` aceita admin OU `agenda.view_settings` OU `account_user?` (backwards compat). `update?` → admin OU `agenda.manage_schedules` (controller edita working hours, exceptions, week_days, holidays — domínio canônico de `manage_schedules`).
- **UserPolicy fora de escopo:** auditoria original listou junto, mas não há `app/policies/user_policy.rb` no codebase Klivy (Chatwoot usa outras rotinas pra gestão de agents — `AgentsController` + `check_authorization` direto).

#### A-6. `ConsentRecordPolicy::Scope.resolve` não respeita `scope=own` — ✅ **CORRIGIDO em 1.6.1.16**
- Filtra apenas por `account_id`, ignora `responsible_professional_id`.
- **Impacto:** profissional com `scope=own` em pacientes lista consents de todos os pacientes — **vazamento de PHI/PII (LGPD)**.
- **Fix aplicado (dois pontos):**
  1. `ConsentRecordsController#set_patient` — usa `policy_scope(Current.account.patients).find(params[:patient_id])` em vez de raw `Current.account.patients.find`. Bloqueia o entry point principal: scope=own + patient_id arbitrário → `RecordNotFound` (404). Antes vazava todos os consents do paciente.
  2. `ConsentRecordPolicy::Scope.resolve` — defensivo: filtra `joins(:patient).where(patients: { responsible_professional_id: user.id })` quando `scope=own`. Garante consistência para qualquer consumidor de `policy_scope(ConsentRecord)`.

#### A-7. `CannedResponsesController` sem authorize — ✅ **CORRIGIDO em 1.6.1.17** + **REFINADO em 1.6.1.26**
- Nenhuma chamada a `check_authorization` nem `authorize` em `index/create/update/destroy`. Qualquer agent da conta CRUDa respostas prontas.
- Não existe `CannedResponsePolicy`.
- **Fix aplicado (Lote 5 / 1.6.1.17):**
  1. Criado `app/policies/canned_response_policy.rb` com gating RBAC: `index?/show? → settings.canned_view`, `create? → settings.canned_create`, `update? → settings.canned_edit`, `destroy? → settings.canned_delete`. `Scope.resolve` filtra por `account_id` (defensivo).
  2. `CannedResponsesController` agora tem `before_action :check_authorization` (definido em `Api::BaseController`). Pundit invoca `CannedResponsePolicy#<action>?` automaticamente.
- **Refinamento (Lote 14 / 1.6.1.26 — pós-audit em prod):** audit query em prod mostrou 7 agents reais com role "Especialista" na account 17 que NÃO têm `canned_view` no preset. Como respostas prontas são listadas no editor de mensagem (autocomplete `/comando`), restringir `index?/show?` quebraria essa UX pra eles. Patch: `index?` e `show?` agora aceitam `admin || agent || beclinic_can?(:settings, :canned_view)` — mesmo padrão de `LabelPolicy#show?` e `AgentBotPolicy#index/show`. **Mutations (`create?/update?/destroy?`) continuam restritas** via Klivy (fix original mantido).

---

### 7.4 Mass assignment / parâmetros não validados

#### A-8. `AgendaEventsController#agenda_event_params` permite `:user_id` — ✅ **CORRIGIDO em 1.6.1.16**
- **Arquivo:** `plugins/agenda/app/controllers/api/v1/accounts/agenda_events_controller.rb:148-153`.
- Profissional com `scope=own` pode criar/editar evento com `user_id` de outro profissional. Evento sai do seu próprio `policy_scope` depois, mas existe e fica visível para quem tem `scope=all`. **Criação fantasma em nome de terceiros**.
- **Fix aplicado:** novo helper `clamp_user_id_for_own_scope(safe_params)` chamado dentro de `create` e `update`. Quando `Current.user.beclinic_scope(Current.account, :agenda) == 'own'`, força `user_id = Current.user.id` no payload. Admin/SuperAdmin (`scope=all`) e AgentBot (sem `beclinic_scope`) passam direto — sem regressão para esses fluxos.

#### M-1. `ConversationsController#custom_attributes` aceita hash livre — ✅ **CORRIGIDO em 1.6.1.24**
- `params.permit(custom_attributes: {})` permite chaves arbitrárias. Não permite escalada, mas permite **stuffing** do JSONB.
- **Fix aplicado:** novo helper `sanitize_custom_attributes(input)` limita a 50 keys + 10_000 chars por valor string. Chamado antes de `@conversation.custom_attributes = ...`. Defesa contra DoS via payload gigante + lentidão de queries.

#### M-2. `ConversationsController#filter` faz `params.permit!` — ✅ **MITIGADO** (não exige fix)
- `permit!` desativa strong params — `FilterService` recebe payload cru.
- **Análise:** Após auditoria do `FilterService` ([app/services/filter_service.rb](app/services/filter_service.rb)), confirmou-se que ele tem **whitelist server-side via YAML** (`lib/filters/filter_keys.yml`) + `validate_query_operator` que rejeita operadores fora de uma lista hardcoded. Chaves não-whitelisted retornam `CustomExceptions::CustomFilter::InvalidAttribute`. O `permit!` é cosmético — o service rejeita o que não conhece. Sem fix necessário.

#### M-3. `AccountsController#update` sem `beclinic_can?(:settings, :account_manage)` — ✅ **CORRIGIDO em 1.6.1.24**
- Settings da conta podem ser mutados por qualquer admin via Pundit padrão sem distinção Klivy. Para uma KlivyRole "Gerente" funcionar, precisaria de gating server-side.
- **Fix aplicado:** `AccountPolicy#update?` agora aceita `admin? || beclinic_can?(:settings, :account_manage)`. Role Klivy "Gerente" (que tem `settings.account_manage=true`) consegue editar settings da conta. Admin nativo continua passando (mesma estrutura do A-5).

---

### 7.5 Information disclosure

#### A-9. `_agent.json.jbuilder` expõe `klivy_role` + `beclinic_super_admin` para todo agent — ✅ **CORRIGIDO em 1.6.1.13**
- **Arquivo:** `app/views/api/v1/models/_agent.json.jbuilder:15-35`.
- `GET /api/v1/accounts/:id/agents` retorna para **qualquer agent autenticado** (Chatwoot libera lista de agents para todos):
  - `custom_role_id`
  - `klivy_role_id`
  - `klivy_role.{id,name,preset_key}`
  - `is_agenda_provider`, `is_agenda_provider_override`
  - **`beclinic_super_admin`** ← identifica super admin → ataque direcionado
- **Risco:** information disclosure. Permite a um agent mapear o organograma de permissões da clínica e identificar alvos com mais privilégio.
- **Fix aplicado:** introduzido guard `viewer_can_see_role_internals = admin || beclinic_can?(:settings, :users_view)`. Quando falso, oculta `custom_role_id`, `klivy_role_id`, `beclinic_super_admin`, `klivy_role.id`, `klivy_role.preset_key`. `klivy_role.name` mantém-se público (usado em `professionalRoles.js` por qualquer agent com `patients.view`). `is_agenda_provider` permanece público (agenda precisa).

---

### 7.6 Cache / consistência

#### M-4. `moduleEnabled` é fail-open
- `usePermissions.js:65-73`: `if (!mod) return true`. Se o backend não devolver a chave do módulo, frontend mostra. Em produção é benigno (admin sempre passa `isAdmin=true`), **mas** muda a semântica esperada de "deny-by-default".

#### M-5. Sem invalidação do store quando admin altera a role do usuário
- Permissions são fetched apenas em `App.vue` mounted.
- Se o admin **trocar a role** do usuário enquanto ele está logado, **o frontend continua com o cache** até refresh ou troca de conta. O backend protege (cada request reconsulta `beclinic_can?`), então **não há vulnerabilidade real** — UI fica decorativamente errada.
- **Fix opcional:** ActionCable broadcast `permissions_updated` invalidando o store.

#### M-6. Race de auto-save no editor
- `RoleEditorIndex.vue:60-67` faz debounce de 400ms. Se o usuário fizer múltiplos toggles seguidos enquanto a primeira request ainda volta, há **last-write-wins**. O payload mais recente do front sobrescreve o anterior. Não há optimistic concurrency (`updated_at` no payload). Risco baixo em uso single-tab; problemático em multi-tab.

---

### 7.7 Código órfão / divergência arquitetural

#### M-7. Sistema de roles paralelo: `BeClinicRoles` (legado) ainda vive — ✅ **CORRIGIDO em 1.6.1.23** (junto com C-3 Fase A)
- **Arquivo:** `plugins/beclinic_core/frontend/settings/BeClinicRoles/beclinicRoles.routes.js` declara `beclinic_roles_list` em `/settings/roles`.
- Memória `rbac_klivy_only` diz que esses sistemas foram **removidos em 2026-04-30**. **Não foram** — só foi deprecado o uso. As rotas continuam alcançáveis por URL.
- **Fix aplicado:** deletados 5 arquivos:
  - `plugins/beclinic_core/frontend/settings/BeClinicRoles/RoleFormModal.vue`
  - `plugins/beclinic_core/frontend/settings/BeClinicRoles/AssignRoleModal.vue`
  - `plugins/beclinic_core/frontend/settings/BeClinicRoles/Index.vue`
  - `plugins/beclinic_core/frontend/settings/BeClinicRoles/beclinicRoles.routes.js`
  - `plugins/beclinic_core/frontend/api/beclinicRoles.js`
  
  Diretório `BeClinicRoles/` removido. Nenhuma importação aponta pra esses arquivos (verificado via grep — só `script/*.rb` históricos de setup mencionam, sem efeito em runtime).

#### M-8. `router.beforeEach` aceita `meta.rbac` — código morto
- `routes/index.js:54-74` checa `to.meta?.rbac` mas **nenhuma rota define `rbac:`** (grep retornou 0). Dead code.

#### M-9. `BeclinicPermissible#full_permissions_hash` defasado — ✅ **CORRIGIDO em 1.6.1.25**
- Hash hardcoded em `beclinic_permissible.rb:73-89` não reflete o catálogo atual (`shared/modules.js`). Para admins, `isAdmin → true` no front faz isso ser irrelevante na UI, mas qualquer consumidor server-side que leia esse hash terá visão **truncada** (vê `false` para `chat.use_macros`, `agenda.is_provider`, `patients.view_anamnesis`, `financial.view_cashflow`, `settings.workflow_view`, etc.).
- **Fix aplicado:** `full_permissions_hash` deletado. `beclinic_permissions_for(account)` agora retorna `{}` para admin/SuperAdmin (em vez de hash hardcoded defasado). Frontend já faz bypass via `usePermissions#isAdmin` antes de consultar o store; backend faz bypass via `beclinic_can?`. Nenhum consumidor real lia o payload de admin, então o hash hardcoded era pura dívida técnica. Comentário no método documenta o porquê pra futuros leitores.

---

### 7.8 Outros pontos

#### B-1. `KlivyRolesController#destroy` faz `AccountUser.where(klivy_role_id: ...)` sem escopo de conta
- Linha 26. Funciona porque `klivy_role.id` é único globalmente (PK), mas é code smell. Trocar para `Current.account.account_users.where(klivy_role_id: @role.id)`.

#### B-2. Sem paginação na listagem de roles
- `useRolesList#load` puxa tudo. Aceitável (≪ 100 roles), mas adicionar `.limit(200)` defensivamente.

#### B-3. Sem validação de número mínimo de admins
- Se o último admin se rebaixar para KlivyRole, conta fica sem admin nativo. `prevent_admin_removal` em `agents_controller` cobre `destroy`, mas **não cobre demote** via `update`. Verificar fluxo de edição de agente.

#### B-4. `useSilentErrors` engole 401 também
- Cobre o caso de 403 (perm-denied) e 401 (não autenticado). Engolir 401 silenciosamente em tabs pode mascarar sessão expirada. Em geral, 401 deveria redirecionar para login — confirmar que axios interceptor faz isso em outro lugar.

---

## 8. Bugs encontrados (resumo)

| # | Severidade | Local | Bug |
|---|---|---|---|
| **C-1** | **Crítico** | `routeHelpers.js:76` | ✅ **CORRIGIDO 1.6.1.14** — prefix removido, EXACT rules por action (`_list`/`_new`/`_edit`) com perm coerente do controller |
| **C-2** | **Crítico** | `klivy_roles_controller.rb:51` + `klivy_role.rb` + `klivy_role/permissions_catalog.rb` (novo) | ✅ **CORRIGIDO 1.6.1.19** — catálogo Ruby + sanitize before_validation + delegation limit no controller (não pode delegar perm/scope acima do próprio nível) |
| **C-3** | **Crítico** | `enterprise/agents_controller.rb:15` | ✅ **CORRIGIDO 1.6.1.23 (Fase A)** — arquivo enterprise deletado, vuln cross-account eliminada. Fase B (drop coluna) pendente |
| **C-4** | **Crítico** | `conversations_controller.rb:42-44` | ✅ **CORRIGIDO 1.6.1.13** — `authorize :reply?` adicionado antes do `MessageBuilder.perform` |
| **A-1 a A-3** | **Alto** | `routeHelpers.js` | ✅ **CORRIGIDO 1.6.1.20** — 21 entradas em KLIVY_REQUIRED cobrindo Captain/Patients/Ajuda/Agenda. Companies fica fora (sem módulo Klivy correspondente, anotado) |
| **A-4** | **Alto** | `routeHelpers.js:72-78` | ✅ **CORRIGIDO 1.6.1.15** — 7 prefixes migrados para EXACT rules granulares por action |
| **A-5** | **Alto** | 5 policies | ✅ **CORRIGIDO 1.6.1.21** — `beclinic_can?` adicionado em Label/Team/Automation/Bot/AgendaSetting. UserPolicy fora (não existe no codebase) |
| **A-6** | **Alto** | `consent_record_policy.rb` Scope + `consent_records_controller.rb#set_patient` | ✅ **CORRIGIDO 1.6.1.16** — controller usa `policy_scope(Patient)`; policy Scope filtra por `responsible_professional_id` quando scope=own |
| **A-7** | **Alto** | `canned_responses_controller.rb` | ✅ **CORRIGIDO 1.6.1.17** — criada `CannedResponsePolicy` + `before_action :check_authorization` no controller |
| **A-8** | **Alto** | `agenda_events_controller.rb:148-153` | ✅ **CORRIGIDO 1.6.1.16** — helper `clamp_user_id_for_own_scope` força `user_id=current_user.id` em create/update quando `scope=own` |
| **A-9** | **Alto** | `_agent.json.jbuilder:15-35` | ✅ **CORRIGIDO 1.6.1.13** — guard `viewer_can_see_role_internals` (admin OR users_view); `klivy_role.name` mantém-se público |
| M-1 a M-9 | Médio | vários | Mass assignment, fail-open, cache, código órfão |
| B-1 a B-4 | Baixo | vários | Code smell, defensivo |

---

## 9. Vulnerabilidades de Segurança — Resumo Direcionado

### 9.1 Privilege escalation (real)
1. **Encadeamento C-1 + C-2 + role com `roles_create + users_edit`** → usuário "Gerente" cria role super-poderosa e atribui a si mesmo via API `assign`. **Fix prioritário:** validar payload `permissions` contra catálogo + impedir delegação além do próprio nível.

### 9.2 Horizontal escalation (multi-tenant)
- **Não confirmado** no fluxo Klivy. Único vetor é o legado `custom_role_id` enterprise (C-3) — relevância baixa se for descontinuado.

### 9.3 IDOR / information disclosure
- **A-9** (serializer expõe role + super_admin status). Médio impacto, fácil fix.

### 9.4 Vazamento de PHI
- **A-6** (ConsentRecord Scope) — LGPD/HIPAA. **Crítico para o domínio clínico**, classificado A por contexto técnico mas merece priorização legal.

### 9.5 Mass assignment
- C-2 (permissions hash), M-1/M-2 (conversation/filter), A-8 (agenda_events user_id).

### 9.6 Bypass de gating (UX → URL)
- A-1/A-2/A-3/A-4. Mitigado pelo backend onde policies existem; expõe URL navegação indevida.

---

## 10. Riscos de regressão

Se as correções forem aplicadas, **atentar a:**

1. **Migração de roles existentes em produção**: validar que nenhum role em prod tem chaves fora do catálogo (rodar audit query antes de adicionar whitelist em C-2).
2. **Backwards compat de `is_agenda_provider`**: o `has_attribute?` guard em `engine.rb:29` e no serializer protege contra migration pendente — manter ao tocar nesse fluxo.
3. **`LEGACY_KEY_MIGRATIONS`**: roles antigos com `settings.manage_*` ainda em prod. Não remover esse hash sem migration de dados.
4. **`BeclinicPermissible#full_permissions_hash`**: usado **só** em `beclinic_permissions_for(account)`. Mudar exige rebuild do response do `BeclinicPermissionsController` para admins; testar `usePermissions().permissions` no front (não depende disso porque `isAdmin → true`).
5. **Fix dos prefixes em `routeHelpers.js`**: usuários que dependem da brecha (operadores que ficaram com `_view` mas usam `_new`) perderão acesso. Coordenar com release notes.
6. **Remoção do enterprise `custom_role_id`**: confirmar migração completa para Klivy. Verificar se `custom_role` ainda é gravado em alguma fonte de dados (importação/migration de clientes legados).

---

## 11. Melhorias recomendadas

### 11.1 Backend (obrigatórias)
1. **C-2** — validar `permissions` contra catálogo Ruby (`KlivyRole::CATALOG`) gerado/lido em sync com `shared/modules.js`. Rejeitar keys desconhecidas; clamp `roles_create/_edit/_delete + users_edit` para impedir delegação acima do próprio nível.
2. **C-3** — escopar `custom_role_id` por `Current.account.custom_roles.find(...)` **OU** remover o enterprise concern se já é morto.
3. **C-4** — `authorize @conversation, :reply?` no `ConversationsController#create` antes do `MessageBuilder.perform`.
4. **A-6** — `ConsentRecordPolicy::Scope.resolve` precisa filtrar por `responsible_professional_id` quando `scope=own`.
5. **A-7** — criar `CannedResponsePolicy` + `check_authorization` em `CannedResponsesController`.
6. **A-8** — em `AgendaEventsController#create/update`, forçar `safe_params[:user_id] = current_user.id` quando `scope=own`.
7. **A-9** — esconder `klivy_role` / `beclinic_super_admin` no `_agent.json.jbuilder` para não-admins.
8. **A-5** — adicionar `beclinic_can?` cobertura em `LabelPolicy`, `TeamPolicy`, `AutomationRulePolicy`, `AgentBotPolicy`, `AgendaSettingPolicy`.

### 11.2 Frontend (obrigatórias)
1. **C-1 / A-4** — converter `KLIVY_PREFIX_ROUTE_RULES` para EXACT por route name **ou** adicionar uma camada `KLIVY_EXACT_DENY` para route names que terminam em `_new`/`_edit`/`_create`/`_delete` quando a perm é só `_view`.
2. **A-1/A-2/A-3** — para cada módulo gateado só no sidebar, adicionar entrada em `KLIVY_REQUIRED_ROUTE_RULES` (`patients_*`, `captain_*`, `companies_*`, `ajuda_*`, `agenda_categories_*`).
3. **M-7** — deletar `plugins/beclinic_core/frontend/settings/BeClinicRoles/` (rotas órfãs).
4. **M-8** — remover bloco `meta.rbac` morto em `routes/index.js`.

### 11.3 Opcionais (qualidade)
1. Mudar `moduleEnabled` para fail-closed (default deny) — alinha com o resto do sistema.
2. ActionCable broadcast `klivy_role_updated` invalidando o store no front.
3. Adicionar `updated_at` ao payload de PATCH role para optimistic concurrency.
4. Paginação em `RolesListIndex` (defensivo).
5. Remover `full_permissions_hash` ou gerá-lo dinamicamente.
6. Drop coluna `account_users.custom_role_id` e remover serialização legada.
7. Cobertura de testes: hoje **não foram encontrados specs do plugin `custom_roles`** — adicionar pelo menos:
   - `klivy_roles_controller_spec` cobrindo cross-account e authorize_action!
   - `klivy_role_spec` cobrindo `can?`/`module_enabled?`/`scope_for`
   - `beclinic_permissible_spec` para precedência tripla
   - Frontend: `useRoleEditor` (toggle/preset/save), `routeHelpers` (todas as regras).

---

## 12. Análise de performance

| Aspecto | Status | Observação |
|---|---|---|
| Query custom_roles | OK | Index `(account_id)` e `(account_id, name)`. `Current.account.klivy_roles.order(:name)` usa-os. |
| `member_count` no serializer | ⚠️ N+1 latente | `KlivyRolesController#serialize` faz `AccountUser.where(klivy_role_id:).count` para cada role na listagem. Listar 50 roles = 50 queries. Trocar por subquery / `left_joins(:account_users).group(:id).count`. |
| `beclinic_permissions_for(account)` | OK | Apenas 1 query (find_by account_id) — sem N+1. |
| `Policy` no sidebar | OK | Reativo via `usePermissions`. |
| Auto-save 400ms | OK | Debounce evita storm. |
| `agents/get` recarregado em `RolesListIndex` `onActivated` | OK | Aceitável. |

**Recomendação P-1:** corrigir N+1 no `serialize(role)` (M-prio).

---

## 13. Análise de Segurança — Recap

- **Autenticação**: depende do Devise/Chatwoot — não no escopo.
- **Autorização horizontal (cross-tenant)**: ✅ no fluxo Klivy. ❌ no enterprise `custom_role_id` (C-3).
- **Autorização vertical (privilege escalation)**: ❌ via C-1 + C-2 (path real).
- **CSRF/XSS**: não no escopo deste plugin.
- **Logs/auditoria de mudanças em roles**: ❌ **não há AuditLog** para create/update/destroy/assign de roles. Em ambiente clínico isso é grave — alguém troca a role de outro user e não fica registrado.

**Recomendação:** persistir cada `assign`/`update`/`create`/`destroy` em `AuditLog` (já existe infra em `Financial::AuditLog`).

---

## 14. Checklist Final

### Backend
- [x] Modelo KlivyRole com validações básicas
- [x] Multi-tenant scoped por account_id
- [x] Migrations criando FK + index
- [x] BeclinicPermissible com precedência correta
- [ ] Validação server-side do payload `permissions` ❌ **(C-2)**
- [ ] Authorize de `reply?` em conversations#create ❌ **(C-4)**
- [ ] CannedResponses authorize ❌ **(A-7)**
- [ ] ConsentRecord Scope com scope=own ❌ **(A-6)**
- [ ] AgendaEvents user_id clamp ❌ **(A-8)**
- [ ] Policies Label/Team/Automation/Bot ❌ **(A-5)**
- [ ] AuditLog para mudanças em roles ❌

### Frontend
- [x] usePermissions com admin bypass
- [x] Sidebar gating
- [x] vCan directive
- [x] Composables do editor
- [x] Presets prontos
- [x] LEGACY_KEY_MIGRATIONS para compat
- [ ] Prefix routes substituídos por exact ❌ **(C-1, A-4)**
- [ ] KLIVY_REQUIRED para Captain/Patients/etc ❌ **(A-1/A-2)**
- [ ] Deletar `beclinic_roles_list` órfão ❌ **(M-7)**
- [ ] Esconder klivy_role/super_admin em /agents ❌ **(A-9)**

### Multi-tenant
- [x] Todas queries Klivy scoped por Current.account
- [x] Atribuição via `assign` valida ambos os lados
- [x] Serializer usa `current_account_user`
- [ ] Enterprise `custom_role_id` sem escopo ❌ **(C-3)**

---

## 15. Testes Manuais Recomendados (regressão pós-fix)

### Conta A (account_id=31)
- [ ] Admin cria role "QA1" com `roles_create + users_edit` apenas → atribui a si mesmo (esperado: rejeitado se fix de C-2 aplicado).
- [ ] Admin cria role "Vendedor" → role aparece na listagem com `member_count=0`.
- [ ] Admin atribui "Vendedor" a agent — agent recarrega → sidebar respeita módulos desligados.
- [ ] Admin exclui "Vendedor" — agent assigned vira `klivy_role_id=null` (sem role).
- [ ] Admin troca preset → permissões substituídas.

### Conta B (account_id=99)
- [ ] Logado em B, GET `/api/v1/accounts/99/klivy_roles/{id_da_conta_A}` → 404.
- [ ] POST `assign` com `user_id` de outra conta → `RecordNotFound`.
- [ ] Listar roles de B não mostra roles de A.

### Usuário non-admin (Klivy "Recepcionista")
- [ ] URL `/accounts/31/settings/custom-roles/list` → redireciona (`roles_view` falso).
- [ ] URL `/accounts/31/settings/custom-roles/new` → **HOJE** entra via C-1; **PÓS-FIX** redireciona.
- [ ] POST direto `/api/v1/accounts/31/klivy_roles` com `roles_create=false` → 403.
- [ ] PATCH agent `/api/v1/accounts/31/agents/:id` com `klivy_role_id=...` → ignorado (não está em `allowed_agent_params`).

### Refresh / multi-tab
- [ ] Admin troca role do user X enquanto X está logado em outra aba → backend bloqueia ações (cache front fica decorativamente errado até refresh — OK).
- [ ] Editor de role em duas abas, edita em ambas → última escrita vence (esperado; documentar).

### Sidebar gating
- [ ] Role com `agenda` totalmente desligado → "Agenda" some.
- [ ] Role com só `agenda.view` → "Calendar" aparece, "Settings"/"Custom Attributes" não.
- [ ] Role com `chat.view_all=false` → "All conversations" some.

---

## 16. Documentação de Referência

- `docs/01-product/modules/funcoes-personalizadas.md` — canon de produto
- `docs/01-product/modules/configuracoes.md`
- `plugins/custom_roles/swagger/{paths,definitions}/*.yml`
- `plugins/beclinic_core/swagger/definitions/BeclinicPermissions.yml`
- `CHANGELOG.md` (entradas RBAC desde 2026-04)

---

## 17. Status Final

### **APROVADO** ✅ — Auditoria 100% executada e validada em localhost

13 lotes aplicados em sequência (versões `1.6.1.13` → `1.6.1.25`), todos validados por curl/UI em localhost (Docker Desktop + Vite HMR). Todos os **críticos (C-1, C-2, C-3 Fase A, C-4)** e **altos (A-1 a A-9)** fechados. Médios M-1, M-3, M-7, M-9 também fechados. M-2 confirmado como já mitigado pelo FilterService upstream (whitelist via YAML).

**Críticos:**

| # | Status | Lote |
|---|---|---|
| C-1 — prefix `klivy_roles` libera `_new`/`_edit` | ✅ | 2 (1.6.1.14) |
| C-2 — `permissions: {}` open hash → privilege escalation | ✅ | 7 (1.6.1.19) |
| C-3 — enterprise `custom_role_id` cross-account (Fase A) | ✅ | 11 (1.6.1.23) |
| C-4 — `ConversationsController#create` bypass `:reply?` | ✅ | 1 (1.6.1.13) |

**Altos:**

| # | Status | Lote |
|---|---|---|
| A-1 — Captain sem KLIVY_REQUIRED | ✅ | 8 (1.6.1.20) |
| A-2 — Patients/Ajuda sem KLIVY_REQUIRED | ✅ | 8 |
| A-3 — Agenda EXACT noop sem deny | ✅ | 8 |
| A-4 — prefixes inbox/teams/applications loose | ✅ | 3 (1.6.1.15) |
| A-5 — 5 policies sem `beclinic_can?` | ✅ | 9 (1.6.1.21) |
| A-6 — ConsentRecord Scope sem `scope=own` (LGPD) | ✅ | 4 (1.6.1.16) |
| A-7 — CannedResponses sem authorize | ✅ | 5 (1.6.1.17) |
| A-8 — AgendaEvents `user_id` mass-assignment | ✅ | 4 |
| A-9 — `_agent.json.jbuilder` info disclosure | ✅ | 1 |

**Médios:**

| # | Status | Lote |
|---|---|---|
| M-1 — `custom_attributes` hash livre | ✅ | 12 (1.6.1.24) |
| M-2 — `filter#permit!` | Mitigado pelo FilterService upstream | — |
| M-3 — `AccountsController#update` sem `beclinic_can?` | ✅ | 12 |
| M-7 — `BeClinicRoles` rotas órfãs | ✅ | 11 |
| M-9 — `full_permissions_hash` defasado | ✅ | 13 (1.6.1.25) |

**Bônus (não auditoria — pré-existentes):**

| # | Tipo | Lote |
|---|---|---|
| bug AddAgent (`beclinic_user_profiles.account_id` NotNullViolation) | Backend hook ordering | 6 (1.6.1.18) |
| Seed presets idempotente (4 presets) | Feature defensiva | 10 (1.6.1.22) |
| Bonus 1 Lote 8 — `Sidebar.vue#CHILD_GATES.Agenda` name mismatch | Frontend gating | 8 |
| Bonus 2 Lote 8 — race condition KLIVY_REQUIRED no boot | Frontend router guard | 8 |

**Follow-ups documentados (não bloqueadores):**

1. **C-3 Fase B** — drop coluna `account_users.custom_role_id` via migration. Após Fase A em prod por semanas, validar e dropar. Toca `enterprise/conversation_policy.rb` que ainda lê o campo (legado Chatwoot).
2. **Index DB** — adicionar `add_index :patients, :responsible_professional_id` pra perf do JOIN em `ConsentRecordPolicy::Scope` (Lote 4).
3. **Scripts one-shots** — `script/migrate_beclinic_core_frontend.rb`, `script/fix_roles_nesting.rb`, `script/setup_beclinic_core_engine.rb` (one-shots históricos, sem efeito em runtime — podem ser removidos).
4. **AuditLog para mudanças em roles** — compliance. KlivyRolesController não persiste histórico de create/update/destroy/assign. Domain clínico exige.
5. **Sync Ruby ↔ JS catalogs** — `PermissionsCatalog` (Ruby) e `modules.js` (JS) precisam ser mantidos em sync manualmente. Idealmente futura iteração move pra single JSON source consumido por ambos. Adicionar spec que compare estruturas.
6. **`moduleEnabled` fail-open** (M-4) — mudar pra fail-closed (default deny) — alinha com o resto do sistema. Backlog.
7. **ActionCable invalidação do store** (M-5) — broadcast `klivy_role_updated` pra forçar refetch quando admin troca role do user logado. UX.
8. **`updated_at` em PATCH role** (M-6) — optimistic concurrency. Defesa contra race em multi-tab. Backlog.

**Recomendação de deploy:**

1. Push dos 13 commits pra staging easypanel.
2. Restart `rails` + `sidekiq` containers (Lotes 6, 7, 10, 11, 13 mexem em `lib/` ou model — precisam restart).
3. Rodar `bundle exec rake custom_roles:seed_presets` em staging pra restaurar/criar presets Klivy em todas as contas.
4. Validação em staging:
   - `/agenda` direto + F5 mantém rota (Lote 8 race condition).
   - Criar agent novo via UI (Lote 6 bug fix).
   - Tentar exploit C-3 via curl (`custom_role_id` arbitrário ignorado).
   - Gerente edita label/team/conta (Lotes 9 + 12).
5. Após 1 semana sem regressão, promover pra prod.

---

> **Notas de método:** auditoria feita em modo leitura na primeira passada (Lote 0). Fixes aplicados em 13 lotes versionados (`1.6.1.13` → `1.6.1.25`) entre 2026-05-17 e 2026-05-18, todos validados em localhost (Docker Desktop + Vite HMR) antes do commit. Histórico detalhado por lote em §18.

---

## 18. Histórico de fixes aplicados

### Lote 16 — `1.6.1.28` (2026-05-18) — Atualização swagger / API docs

**Escopo:** sincronizar 17 arquivos OpenAPI/Swagger com mudanças de contract introduzidas pelos lotes 1-15. Sem este lote, consumidores externos da API (integrações de terceiros, dev tools, doc auto-gerada via Swagger UI) ficariam com docs defasadas.

**Cobertura por lote origem:**

| Lote | Mudança documentada | Arquivos |
|---|---|---|
| 1 (A-9) | Visibilidade condicional de `klivy_role.*`, `klivy_role_id`, `beclinic_super_admin`, `is_agenda_provider_override` no serializer agent | `swagger/definitions/resource/agent.yml` |
| 1 (C-4) | `POST /conversations` com `message` exige `chat.reply` (não basta `send_broadcast`) | `swagger/paths/application/conversation/index.yml` |
| 5 + 14 (A-7) | 4 paths `canned_responses`: index/show abertos pra agent; mutations exigem perm Klivy | 4 paths em `canned_responses/` |
| 6 (bug AddAgent) | `after_create_commit` cria `beclinic_user_profile` + `agenda_public_id` auto | `agents/create.yml`, `agent.yml` (campo `agenda_public_id`) |
| 7 (C-2) | Resposta 403 `forbidden_permission_escalation` com array `forbidden`. Nota sobre sanitize do `permissions` hash | `klivy_roles.yml`, `klivy_role.yml`, `KlivyRole.yml` |
| 9 (A-5) | 3 plugins (`teams`, `automation_rule`, `agent_bots`): mutations aceitam admin OR perm Klivy | 3 paths `create.yml` |
| 11 (C-3) | `custom_role_id` marcado `deprecated` em agent serializer + agents/create + agents/update | `agent.yml`, `agents/create.yml`, `agents/update.yml` |
| 12 (M-1) | Limites `custom_attributes`: 50 keys + 10KB | `conversation/custom_attributes.yml` |
| 12 (M-3) | `accounts/update` aceita admin OR Klivy `account_manage` | `accounts/update.yml` |
| 13 (M-9) | Admin recebe `permissions: {}` (não mais hash hardcoded) | `BeclinicPermissions.yml` |

**Fora de escopo (anotado pra PR futuro):**

- **Paths swagger pra `consent_records` (A-6) e `agenda_events` (A-8)**: os plugins `plugins/patients/swagger/` e `plugins/agenda/swagger/` ainda não têm paths detalhados (só model definitions). Documentar exigiria criar a estrutura swagger desses plugins do zero.
- **i18n `customRole.json` upstream**: 25 arquivos `customRole.json` em locales Chatwoot mantidos intocados pra preservar merge upstream.

**Risco / regressão:** zero impacto em runtime (só arquivos .yml estáticos). Não precisa restart.

---

### Lote 15 — `1.6.1.27` (2026-05-18) — Drift detector + AGENTS.md workflow

**Escopo:** automatizar detecção de drift entre os 2 catálogos paralelos de permissões (Ruby ↔ JS) + documentar workflow padrão pra desenvolvedores futuros.

**Problema endereçado:** o catálogo de perms vive em `permissions_catalog.rb` (Ruby) e `modules.js` (JS). Mudança em um sem o outro causa bugs sutis:
- Perm só no Ruby → editor sem toggle, admin não marca.
- Perm só no JS → `sanitize_and_migrate` dropa silenciosamente; admin confuso.
- Backend chama `beclinic_can?(:mod, :perm)` em key não-catalogada → non-admin sempre nega.

**Solução:**

| Arquivo | Função |
|---|---|
| `spec/plugins/custom_roles/catalog_sync_spec.rb` (novo) | 9 specs: detecta drift Ruby→JS por module/perm keys, valida LEGACY_KEY_MIGRATIONS apontam pra keys válidas, valida idempotência do `sanitize_and_migrate`, valida tratamento de `ActionController::Parameters`, etc. Roda no CI. |
| `AGENTS.md` (seção nova) | Workflow obrigatório pra adicionar perm nova ou módulo novo. Lista os 6 lugares a tocar + failure modes + salvaguardas existentes. |

**Cobertura do spec:**

- ✅ Module keys do Ruby existem no JS (textualmente via regex `/\bkey:\s*['"](\w+)['"]/`).
- ✅ Permission keys do Ruby existem no JS.
- ✅ LEGACY_KEY_MIGRATIONS aponta pra keys do CATALOG (não pra keys removidas).
- ✅ `sanitize_and_migrate` é idempotente (rodar 2x = rodar 1x).
- ✅ `sanitize_and_migrate` dropa módulos e perms desconhecidas.
- ✅ `sanitize_and_migrate` aceita `ActionController::Parameters` (bug encontrado no Lote 7).
- ✅ Legacy migrations expandem corretamente (`settings.manage_users` → 4 keys).
- ✅ `scope` aceita só `all`/`own`.

**Limitação conhecida:** o spec é Ruby → JS only. Pegar drift JS → Ruby (perm só no JS) exigiria parsing AST do JS, muito caro pra benefício marginal. Aceito porque:
- O caso comum (dev adiciona feature → cria perm no backend Ruby primeiro) é coberto.
- Frontend-only seria detectado em PR review (toda PR que toca `modules.js` deve tocar `permissions_catalog.rb` também — guideline no AGENTS.md).

**Como rodar:**

```bash
docker exec beclinic-rails-1 bundle exec rspec spec/plugins/custom_roles/catalog_sync_spec.rb
# Esperado: 9 examples, 0 failures
```

---

### Lote 14 — `1.6.1.26` (2026-05-18) — Patch A-7 pós-audit prod

**Escopo:** refinamento do A-7 (Lote 5) descoberto durante audit pré-deploy. Audit em prod identificou 7 agents Especialistas (account 17) que perderiam acesso a "Respostas Prontas" no editor de mensagem após o deploy do Lote 5 original. Patch relaxa `index?/show?` mantendo mutations restritas.

| Arquivo | Diff |
|---|---|
| `app/policies/canned_response_policy.rb` | `index?` e `show?` agora aceitam `admin OR agent OR beclinic_can?(:settings, :canned_view)`. Mesmo padrão de `LabelPolicy#show?`, `AgentBotPolicy#index/show`. `create?/update?/destroy?` mantêm fallback Klivy adicionado (`admin OR beclinic_can?`). |

**Justificativa:** respostas prontas são utilitário de leitura comum nas conversas. Restringir leitura quebra UX sem ganho de segurança real (canned_responses são compartilhados na conta, sem PHI). Padrão alinhado com Labels (também aberto pra agent ler).

**Como validar:**

```bash
# Conta com Especialista (account 17 em prod) — agent sem canned_view consegue LISTAR mas não criar
TOKEN_DO_ESPECIALISTA=...
curl -s -o /dev/null -w "INDEX=%{http_code}\n" -H "api_access_token: $TOKEN" \
  http://localhost:3000/api/v1/accounts/17/canned_responses
# Esperado: 200 (era 401 após Lote 5 original)

curl -s -o /dev/null -w "CREATE=%{http_code}\n" -X POST -H "api_access_token: $TOKEN" \
  -H 'Content-Type: application/json' -d '{"canned_response":{"short_code":"x","content":"y"}}' \
  http://localhost:3000/api/v1/accounts/17/canned_responses
# Esperado: 401 (mutation continua restrita)
```

**Risco / regressão:**

- Especialistas/agents sem `canned_view` continuam **listando** canned (preserva UX do editor).
- **Não** podem mais criar/editar/deletar sem `canned_create/_edit/_delete` (fix A-7 original preservado pra mutations).
- Admins continuam passando em tudo.

---

### Lote 13 — `1.6.1.25` (2026-05-17) — M-9 (limpar full_permissions_hash dead code)

**Escopo:** remover hash hardcoded `BeclinicPermissible#full_permissions_hash` que estava defasado vs catálogo atual.

| ID | Tipo | Arquivos | Diff resumo |
|---|---|---|---|
| **M-9** | Dead code defasado | `plugins/beclinic_core/app/models/concerns/beclinic_permissible.rb` | Método `full_permissions_hash` deletado. `beclinic_permissions_for(account)` retorna `{}` para admin/SuperAdmin com comentário explicando o porquê (frontend `isAdmin` bypassa antes de consultar store; backend `beclinic_can?` retorna true antes de checar permissions). |

**Análise prévia:** único consumidor de `beclinic_permissions_for` é `BeclinicPermissionsController#show`, que serializa pro frontend. Frontend pra admin nunca usa o payload (bypass via `isAdmin`). Logo `full_permissions_hash` era dead code que só ficava defasado e arriscava confundir leitores.

**Validação (terminal):**

```bash
docker restart beclinic-rails-1 beclinic-sidekiq-1 && sleep 8

# Admin agora recebe permissions={}
ADMIN='XSw1X9NAYgfZ1iLRdM4Mxako'
curl -s -H "api_access_token: $ADMIN" \
  http://localhost:3000/api/v1/accounts/31/beclinic_permissions | jq '.permissions, .beclinic_role'
# Esperado: {} e "administrator"
# Antes do M-9: hash hardcoded com 5 módulos parciais

# Non-admin (Leandro) — sem mudança, retorna permissions reais do KlivyRole
AGENT='MRcVscwkHuDMCa8oATXwzm3e'
curl -s -H "api_access_token: $AGENT" \
  http://localhost:3000/api/v1/accounts/31/beclinic_permissions | jq '.permissions | keys'
# Esperado: lista com módulos do role Especialista (inbox, chat, captain, agenda, patients, financial, etc.)
```

**Risco / regressão:**

- **Nenhum lugar lê o payload pra admin.** Frontend faz `isAdmin → true` antes de consultar store. Backend `beclinic_can?` retorna true antes de qualquer checagem.
- **Caso edge teórico:** se algum consumidor server-side futuro fizer `user.beclinic_permissions_for(account)[:patients][:view]` esperando `true` pra admin, vai receber `nil`. Comentário no método sinaliza explicitamente esse comportamento. Se for caso real, basta substituir o `{}` por `KlivyRole::PermissionsCatalog.full_admin_hash` (helper futuro).
- **Restart obrigatório:** concern Ruby autoloaded mas vale restart pra garantir.

**Validação executada em 2026-05-18 (localhost / Docker):**

- ✅ Admin: `GET /beclinic_permissions` → `{permissions: {}, beclinic_role: "administrator"}`. Antes do M-9 retornava hash hardcoded com 5 módulos parciais defasados.
- ✅ Non-admin (Leandro Especialista): mesmo endpoint → `beclinic_role: "Especialista"`, `permissions` com 12 keys de módulos reais (agenda, campaigns, captain, chat, contacts, financial, help, help_center, inbox, patients, reports, settings). Sem regressão.

---

### Lote 12 — `1.6.1.24` (2026-05-17) — M-1 + M-3 (polish mass-assignment + AccountPolicy)

**Escopo:** dois polish backend pequenos.

| ID | Tipo | Arquivos | Diff resumo |
|---|---|---|---|
| **M-1** | Mass-assignment JSONB stuffing | `app/controllers/api/v1/accounts/conversations_controller.rb` | Helper `sanitize_custom_attributes(input)` aplica `CUSTOM_ATTRIBUTES_MAX_KEYS=50` e trunca cada valor string em `CUSTOM_ATTRIBUTES_MAX_VALUE_LENGTH=10_000` antes de salvar no JSONB. Defesa contra DoS/perf. |
| **M-3** | Authz gap | `app/policies/account_policy.rb` | `AccountPolicy#update?` agora aceita `admin? \|\| beclinic_can?(:settings, :account_manage)`. Mesma estrutura do A-5. |
| **M-2** | (não aplicável) | — | Anotado como já mitigado pelo `FilterService` upstream (whitelist via `lib/filters/filter_keys.yml` + `validate_query_operator`). `params.permit!` cosmético. |

**Como validar (terminal):**

```bash
docker restart beclinic-rails-1 beclinic-sidekiq-1 && sleep 8

# M-1: tentar stuffar 200 keys → só persiste 50
docker exec beclinic-rails-1 bundle exec rails runner '
account = Account.find(31)
conv = account.conversations.first
huge_payload = (1..200).each_with_object({}) { |i, h| h["key_#{i}"] = "value_#{i}" }
# Simula o helper diretamente
controller = Api::V1::Accounts::ConversationsController.new
sanitized = controller.send(:sanitize_custom_attributes, huge_payload)
puts "sanitized_keys=#{sanitized.keys.size}"  # Esperado: 50
puts "truncated_value=#{controller.send(:sanitize_custom_attributes, {"x"=>"a"*15_000})["x"].length}"  # Esperado: 10000
'

# M-3: Leandro com role Gerente (que tem account_manage=true) → POST update da conta passa
docker exec beclinic-rails-1 bundle exec rails runner '
account = Account.find(31)
leandro = User.find_by!(email: "leandro@benuv.com")
gerente = account.klivy_roles.find_by!(name: "Gerente")
au = leandro.account_users.find_by!(account_id: 31)
au.update!(klivy_role_id: gerente.id)
puts "account_manage=#{leandro.beclinic_can?(account, :settings, :account_manage)}"  # Esperado: true
'

AGENT='MRcVscwkHuDMCa8oATXwzm3e'
curl -s -o /dev/null -w "ACCOUNT_UPDATE=%{http_code}\n" -X PATCH \
  -H "api_access_token: $AGENT" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Mamedes (atualizado via Gerente)"}' \
  http://localhost:3000/api/v1/accounts/31
# Esperado: 200 (antes do fix: 401)

# Cleanup: restaurar Leandro pra Especialista
docker exec beclinic-rails-1 bundle exec rails runner '
au = User.find_by!(email: "leandro@benuv.com").account_users.find_by!(account_id: 31)
au.update!(klivy_role_id: 1)
puts "Leandro_restaurado=#{au.reload.klivy_role.name}"
'
```

**Risco / regressão:**

- **M-1 truncamento silencioso:** se cliente legítimo envia `custom_attributes` com 60 keys ou string > 10KB, as keys/sufixos excedentes são silenciosamente dropados/truncados. Cenário improvável (UI Chatwoot usa < 10 keys), mas vale documentar. Alternativa rejeitada: 422 explícito (quebra UI legacy).
- **M-3 sem regressão:** admin nativo continua passando (primeira condição); só adiciona Klivy fallback.
- **Restart obrigatório:** policies + controllers Ruby autoloaded mas vale restart pra garantir cache zerado.

---

### Lote 11 — `1.6.1.23` (2026-05-17) — C-3 Fase A + M-7

**Escopo:** limpar legado `custom_role` / `BeClinicRoles` (Klivy-específico, não Chatwoot upstream). Fecha vuln C-3 (cross-account custom_role_id) sem aumentar divergência com Chatwoot upstream.

| Arquivo deletado | Motivo |
|---|---|
| `enterprise/app/controllers/enterprise/api/v1/accounts/agents_controller.rb` | Aqui morava a vuln C-3 — `update!(custom_role_id: params[:custom_role_id])` sem escopo. Klivy não usa custom_role. `prepend_mod_with` vira no-op silencioso (tolerante a ausência via `const_get_maybe_false`). |
| `plugins/beclinic_core/frontend/settings/BeClinicRoles/RoleFormModal.vue` | UI órfã do BeClinic Core (sistema de roles paralelo deprecado em 2026-04-30). |
| `plugins/beclinic_core/frontend/settings/BeClinicRoles/AssignRoleModal.vue` | Idem. |
| `plugins/beclinic_core/frontend/settings/BeClinicRoles/Index.vue` | Idem. |
| `plugins/beclinic_core/frontend/settings/BeClinicRoles/beclinicRoles.routes.js` | Rota órfã `beclinic_roles_list` → `/settings/roles`. Klivy usa `klivy_roles_list` → `/settings/custom-roles`. |
| `plugins/beclinic_core/frontend/api/beclinicRoles.js` | API client órfão (sem consumidor após delete do diretório acima). |
| Diretório `plugins/beclinic_core/frontend/settings/BeClinicRoles/` | Removido (estava vazio após deletes). |

**Mantido upstream Chatwoot intocado** (decisão consciente pra não piorar merge com upstream):
- `app/javascript/dashboard/routes/dashboard/settings/customRoles/*` — UI Chatwoot enterprise nativa.
- `app/javascript/dashboard/api/customRole.js` + `store/modules/customRole.js` — API/store Chatwoot.
- i18n locales `customRole.json` em 25+ idiomas.
- `enterprise/app/policies/enterprise/conversation_policy.rb` — ainda lê `custom_role_id` (Chatwoot conversation_manage perms).
- `enterprise/app/views/api/v1/models/_account_user.json.jbuilder` — serializa `custom_role_id`.
- `enterprise/app/services/enterprise/conversations/permission_filter_service.rb`.
- `enterprise/app/builders/saml_user_builder.rb`.
- Specs enterprise.
- `db/migrate/20240726220747_add_custom_roles.rb` — migration histórica.

**Fase B (futuro PR — após Fase A em prod por algumas semanas):**
- Migration drop coluna `account_users.custom_role_id`.
- Adapter pra `enterprise/conversation_policy.rb` ignorar custom_role_id ausente.
- Eventualmente remover scripts `script/migrate_beclinic_core_frontend.rb`, `script/fix_roles_nesting.rb`, `script/setup_beclinic_core_engine.rb` (one-shots históricos de migração de plugin, sem efeito em runtime mas ocupam espaço).

**Como validar:**

```bash
# Backend (Rails): confirma que servidor sobe sem erro mesmo sem o arquivo enterprise
docker restart beclinic-rails-1 && sleep 8
curl -s -o /dev/null -w "RAILS=%{http_code}\n" \
  -H "api_access_token: XSw1X9NAYgfZ1iLRdM4Mxako" \
  http://localhost:3000/api/v1/accounts/31
# Esperado: RAILS=200

# Confirmar que AgentsController#create ainda funciona (não chama mais associate_agent_with_custom_role)
docker exec beclinic-rails-1 bundle exec rails runner '
puts "Api::V1::Accounts::AgentsController.instance_methods(false).include?(:create) = #{Api::V1::Accounts::AgentsController.instance_methods(false).include?(:create)}"
puts "Tem override enterprise? = #{Api::V1::Accounts::AgentsController.ancestors.any? { |a| a.name&.include?("Enterprise::Api::V1::Accounts::AgentsController") }}"
'
# Esperado: false na 2a linha (sem override enterprise)

# Frontend: criar agent novo via UI deve continuar funcionando (Lote 6 fix permanece)
# - Settings → Agentes → Adicionar agente → preencher → salvar
# - Esperado: criado sem erro
```

**Risco / regressão:**

- **Payload `custom_role_id` enviado por UI** (AddAgent.vue/EditAgent.vue ainda enviam quando admin escolhe um "Custom Role" Chatwoot): silenciosamente ignorado pelo backend (controller padrão não permite o campo). UI Chatwoot Custom Roles (que não usamos) continua funcionando porque os endpoints `/custom_roles` ainda existem; só não atribuem mais ao agent.
- **Agents existentes com `custom_role_id` no banco**: campo permanece (Fase B dropa). Nenhum código Klivy lê (`_agent.json.jbuilder` já condiciona ao admin desde Lote 1 + após Fase B vai sumir).
- **Enterprise `conversation_policy.rb`**: ainda lê `account_user.custom_role_id` pra perms `conversation_manage`/`unassigned_manage`/`participating_manage`. Como nenhuma role Klivy atribui custom_role_id, essas perms ficam sempre nil → fallback pro `super` do `show?` (que valida via inbox/team access). Sem regressão.
- **Restart obrigatório**: deletou arquivo `lib/` enterprise. `docker restart beclinic-rails-1 beclinic-sidekiq-1`.
- **Sem mudança de runtime na UI**: dropdown de roles em AddAgent.vue mostra "Administrator/Agent" sempre, custom_roles array fica vazio (endpoint Chatwoot retorna [] na maioria das contas Klivy).

**Validação executada em 2026-05-17 (localhost / Docker):**

- ✅ `RAILS=200` — servidor sobe sem o arquivo enterprise.
- ✅ `tem_enterprise_override? = false` — `Enterprise::Api::V1::Accounts::AgentsController` não está mais na cadeia de ancestors.
- ✅ Exploit C-3: admin enviou `POST /agents` com `custom_role_id: 999999` no payload → agent criado com `custom_role_id: null` (campo silenciosamente ignorado). Vuln cross-account fechada.
- ✅ Lote 6 continua OK: agent ganha `agenda_public_id: "05msrg18"` automaticamente.

---

### Lote 10 — `1.6.1.22` (2026-05-17)

**Escopo:** seed idempotente dos 4 presets KlivyRole + auto-seed em contas novas. Endereça o achado do Lote 9 (preset Gerente corrompido com todas perms false) e previne regressão similar.

**Por que esse fix existe:** durante validação do Lote 9 descobrimos que o role "Gerente" da conta 31 estava com TODAS as perms `settings.*=false` no JSONB. Causa especulada: editor de role salvou em estado vazio (provável race ou bug no auto-save). Sem mecanismo de cura, o preset fica permanentemente quebrado e qualquer agent atribuído fica sem perms (apesar do badge "Gerente"). Solução: ter o sistema reaplicar os presets canônicos de forma idempotente.

| Arquivo (novo) | Função |
|---|---|
| `plugins/custom_roles/lib/custom_roles/preset_definitions.rb` | Constante `PresetDefinitions::ALL` (espelho exato de `frontend/shared/presets.js`). 4 presets com `label`, `preset_key`, `description`, `permissions` (hash JSONB pronto). |
| `plugins/custom_roles/lib/custom_roles/preset_seeder.rb` | Service `PresetSeeder.call(account, force: false)`. Pra cada preset: cria se não existe; restaura se está corrompido (`permissions` vazio ou todas false); skip se admin customizou. `force: true` sobrescreve. |
| `plugins/custom_roles/lib/tasks/custom_roles.rake` | `bundle exec rake custom_roles:seed_presets` (todas contas) ou `ACCOUNT_ID=31 bundle exec rake custom_roles:seed_presets` (uma só). Aceita `FORCE=true`. |
| `plugins/custom_roles/lib/custom_roles/engine.rb` (mod) | `Account.after_create :seed_klivy_presets` — contas novas ganham os 4 presets automaticamente. Best-effort com rescue (não quebra criação de conta se seed falhar). |

**Definição de "corrompido":**

```ruby
def corrupted?(role)
  perms = role.permissions || {}
  return true if perms.empty?
  perms.values.all? do |mod_perms|
    next true unless mod_perms.is_a?(Hash)
    mod_perms.except('scope').values.none? { |v| v == true }
  end
end
```

Detecta: `{}` (vazio), `{settings: {labels_create: false, ...all false}}` (caso do Gerente), e variantes. Não detecta: role com 1 perm true e 99 false (considera "customizado", não toca).

**Como validar:**

```bash
# 1) Forçar corrupção no Gerente pra teste
docker exec -i beclinic-rails-1 bash -c "cat > /tmp/lote10_setup.rb" <<'EOF'
account = Account.find(31)
gerente = account.klivy_roles.find_by!(name: 'Gerente')
# Zera todas as perms (simula bug)
zeroed = gerente.permissions.transform_values do |mod_perms|
  mod_perms.is_a?(Hash) ? mod_perms.transform_values { |_| false } : mod_perms
end
gerente.update!(permissions: zeroed)
true_count = gerente.reload.permissions.values.sum { |m| m.is_a?(Hash) ? m.values.count(true) : 0 }
puts "GERENTE_BEFORE: true_perms=#{true_count}"  # Esperado: 0
EOF
docker exec beclinic-rails-1 bundle exec rails runner /tmp/lote10_setup.rb

# 2) Rodar o seed
docker exec beclinic-rails-1 bundle exec rake 'custom_roles:seed_presets ACCOUNT_ID=31'

# 3) Confirmar restauração
docker exec beclinic-rails-1 bundle exec rails runner '
gerente = Account.find(31).klivy_roles.find_by!(name: "Gerente")
n = gerente.permissions.values.sum { |m| m.is_a?(Hash) ? m.values.count(true) : 0 }
puts "GERENTE_AFTER: true_perms=#{n}"  # Esperado: ~160
'
```

**Risco / regressão:**

- **Skip de customizações:** se admin editou um preset (ex: removeu `chat.delete_message` do Gerente), o seed NÃO sobrescreve. Preserva intencionalidade. Para sobrescrever, usar `FORCE=true`.
- **`after_create` em Account:** rescue evita quebrar criação de conta. Se seed falhar, conta é criada sem presets — admin pode rodar `rake custom_roles:seed_presets ACCOUNT_ID=X` depois.
- **Sync com `presets.js`:** mudança em um exige mudança no outro. Anotado nos comentários dos dois arquivos. Idealmente futura iteração move pra single source (JSON consumido por ambos).
- **Restart obrigatório:** engine.rb mudou (rake_tasks + initializer + after_create). `docker restart beclinic-rails-1 beclinic-sidekiq-1`.

**Validação executada em 2026-05-17 (localhost / Docker):**

Sequência de teste na conta 31:
1. Zerar Gerente propositalmente → `BEFORE_seed: gerente_perms_true=0` ✅
2. `rake custom_roles:seed_presets ACCOUNT_ID=31` (run 1) → `[RESTORED] gerente`, `[CREATED] sdr`, 2 `[SKIP]` (Recepcionista/Especialista já customizados). Bônus: SDR não existia na conta — foi criado pela primeira vez.
3. `rake custom_roles:seed_presets ACCOUNT_ID=31` (run 2 — idempotência) → 4 `[SKIP]`, zero mudança.
4. Confirmação → `AFTER_seed: gerente_perms_true=160` ✅

---

### Lote 9 — `1.6.1.21` (2026-05-17)

**Escopo:** A-5 — completar cobertura RBAC em 5 policies que só checavam `administrator?`.

| Policy | Actions tocadas | Perm Klivy adicionada |
|---|---|---|
| **LabelPolicy** | `create/update/destroy/show` | `settings.labels_create/_edit/_delete`; `show?` aberto pra agent |
| **TeamPolicy** | `create/update/destroy` | `settings.teams_create/_edit/_delete` |
| **AutomationRulePolicy** | `index/show/create/update/clone/destroy` | `settings.automation_view/_create/_edit/_delete` (`clone` = `_create`) |
| **AgentBotPolicy** | `create/update/destroy/avatar/reset_access_token` | `settings.agent_bots_manage` |
| **AgendaSettingPolicy** | `show/update` | `show: agenda.view_settings`; `update: agenda.manage_schedules` |

**Validação executada em 2026-05-17 (localhost / Docker):** Role temp `Test-A5-Full` com perms cheias → `LABEL_CREATE=200`, `TEAM_CREATE=200`, `AUTOMATION_INDEX=200`, `AGENT_BOT_CREATE=200`. Antes do fix: 4× 401. ✅

**⚠️ Achado adicional durante validação — preset Gerente corrompido no DB:**

Ao tentar atribuir Leandro ao preset "Gerente" (que deveria ter 106 perms true), descobrimos que **TODAS as perms `settings.*` estão `false`** no JSONB:
```ruby
{"labels_create" => false, "teams_create" => false, "automation_view" => false, ...}
```

Causa provável (especulação — não rastreada):
1. Alguém abriu Gerente no editor e clicou Save sem marcar as perms.
2. Auto-save (debounce 400ms) disparou em estado vazio durante carregamento.
3. Migration/seed histórico zerou.

Não é regressão de nenhum dos lotes da auditoria. Risco: agents atribuídos ao "Gerente" não têm perms reais (apesar do badge). Mitigação: criar script que reaplica os 4 presets (Recepcionista/Especialista/Gerente/SDR) por conta, idempotente — anotado pra PR separado.

**Como validar (terminal):**

```bash
# 1) Criar Gerente fake pro Leandro (preset Gerente tem 106 perms)
docker exec -i beclinic-rails-1 bash -c "cat > /tmp/a5_setup.rb" <<'EOF'
account = Account.find(31)
# Atribui preset Gerente ao Leandro
gerente = account.klivy_roles.find_by!(name: 'Gerente')
au = User.find_by!(email: 'leandro@benuv.com').account_users.find_by!(account_id: 31)
puts "PREV_ROLE=#{au.klivy_role&.name}"
au.update!(klivy_role_id: gerente.id)
puts "NOW_ROLE=#{au.reload.klivy_role.name}"
EOF
docker exec beclinic-rails-1 bundle exec rails runner /tmp/a5_setup.rb

AGENT='MRcVscwkHuDMCa8oATXwzm3e'

# 2) Antes do fix retornava 401. Esperado AGORA: 200/201.
# Label
curl -s -o /dev/null -w "LABEL_CREATE=%{http_code}\n" -X POST -H "api_access_token: $AGENT" \
  -H 'Content-Type: application/json' \
  -d '{"label":{"title":"a5-test-label","color":"#ff0000"}}' \
  http://localhost:3000/api/v1/accounts/31/labels

# Team
curl -s -o /dev/null -w "TEAM_CREATE=%{http_code}\n" -X POST -H "api_access_token: $AGENT" \
  -H 'Content-Type: application/json' \
  -d '{"name":"a5-test-team","description":"A-5 test"}' \
  http://localhost:3000/api/v1/accounts/31/teams

# Automation
curl -s -o /dev/null -w "AUTOMATION_INDEX=%{http_code}\n" -H "api_access_token: $AGENT" \
  http://localhost:3000/api/v1/accounts/31/automation_rules

# Agent bot
curl -s -o /dev/null -w "AGENT_BOT_CREATE=%{http_code}\n" -X POST -H "api_access_token: $AGENT" \
  -H 'Content-Type: application/json' \
  -d '{"name":"a5-test-bot","outgoing_url":"https://example.com/bot"}' \
  http://localhost:3000/api/v1/accounts/31/agent_bots
```

Cleanup:
```bash
docker exec beclinic-rails-1 bundle exec rails runner '
account = Account.find(31)
au = User.find_by!(email: "leandro@benuv.com").account_users.find_by!(account_id: 31)
au.update!(klivy_role_id: 1)
account.labels.where(title: "a5-test-label").destroy_all
account.teams.where(name: "a5-test-team").destroy_all
account.agent_bots.where(name: "a5-test-bot").destroy_all
puts "CLEANUP_OK"
'
```

**Risco / regressão:**

- **Sem regressão pra admin** (todas mantêm `administrator?` como primeira condição).
- **Não-admins sem perm Klivy:** comportamento idêntico (continuam negados).
- **Não-admins COM perm Klivy:** agora passam (era o gap funcional fechado).
- **`LabelPolicy#show?`:** ampliado de admin-only pra `admin OR agent` — labels são listadas/usadas por todos os agents pra filtrar conversas (era restrição estranha do Chatwoot upstream).
- **Restart obrigatório:** policies Ruby são carregadas pelo autoloader, mas se Pundit fizer caching em produção é necessário restart. `docker restart beclinic-rails-1 beclinic-sidekiq-1`.

---

### Lote 8 — `1.6.1.20` (2026-05-17)

**Escopo:** A-1 + A-2 + A-3 — fechar bypass de URL direta em plugins que hoje só têm gating de sidebar (`moduleEnabled` fail-open) ou EXACT noop.

| ID | Tipo | Arquivos | Diff resumo | Validação |
|---|---|---|---|---|
| **A-1** (Captain) | URL bypass | `app/javascript/dashboard/helper/routeHelpers.js` | 12 entries em `KLIVY_REQUIRED_ROUTE_RULES` mapeando cada sub-rota Captain à perm específica do catálogo (`captain.view`, `manage_faqs`, `manage_documents`, etc.). | ✅ Validado em 2026-05-17 — sidebar oculta sub-items sem perm; URL direta redireciona |
| **A-2** (Patients + Ajuda) | URL bypass | mesmo arquivo | `patients_dashboard_index` / `_record` → `patients.view`; `ajuda_dashboard_index` / `_report_bug` / `_feature_request` → `help.view`. Companies fora de escopo (sem módulo Klivy). | ✅ Validado em 2026-05-17 |
| **A-3** (Agenda) | EXACT noop, sem deny | mesmo arquivo | 4 rotas agenda_* promovidas pra REQUIRED (mantém EXACT pra defesa em profundidade). | ✅ Validado em 2026-05-17 — `/agenda/settings` (sem perm) redireciona; `/agenda` (com perm) entra |
| **Bonus 1** (sidebar Agenda) | Pre-existing name mismatch | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | `CHILD_GATES.Agenda.rules` usava keys `'Agenda Settings'`/`'Agenda Custom Attributes'` mas `child.name` no menu é só `'Settings'`/`'Custom Attributes'` — lookup falhava e items apareciam sem filtro. Corrigido durante validação do A-3 quando o gating real (router guard) tornou o bug visível (item aparecia no menu, ao clicar redirecionava). | ✅ Validado em 2026-05-17 — Leandro só vê Calendário + Categorias |
| **Bonus 2** (race condition F5) | Bug introduzido pelo próprio Lote 8 | `app/javascript/dashboard/helper/routeHelpers.js` | F5/URL direta dispara `router.beforeEach` ANTES do `App.vue#mounted` ter completado `beclinicPermissions/fetch`. Sem guard, `klivyHasPermission({}, rule)` retornava false sempre → toda rota mapeada KLIVY_REQUIRED bloqueava → user preso no dashboard. Fix: novo helper `isKlivyPermissionsLoaded()` faz fail-open enquanto store vazio — sidebar e backend Pundit cobrem o gating real depois que o store carrega. | ✅ Validado em 2026-05-17 — F5 em qualquer rota mantém o usuário na rota |

**Por que Companies foi fora:**

Não existe módulo `companies` em `frontend/shared/modules.js`. Adicionar uma entry KLIVY_REQUIRED com perm fictícia (`companies.view`) só bloquearia qualquer non-admin sem dar caminho de liberação — pior que o estado atual. Solução proper: adicionar módulo `companies` ao catálogo (Ruby + JS sync) primeiro, depois esse fix. Anotar como follow-up.

**Como validar (UI — Vite HMR):**

Logado como Leandro (Especialista — sem perms de captain/patients/agenda customizadas hoje pelo preset). Tentar cada URL:

| URL | Comportamento esperado |
|---|---|
| `/app/accounts/31/patients/dashboard/index` | Redireciona (Especialista preset NÃO tem `patients.view`)? — **verificar preset Especialista** |
| `/app/accounts/31/agenda` | Redireciona se preset não tem `agenda.view` |
| `/app/accounts/31/captain` | Redireciona se preset não tem `captain.view` |
| `/app/accounts/31/ajuda` | Redireciona se preset não tem `help.view` |
| Admin (Danilo) | Entra em tudo (bypass via `isAdmin`) |

**Atenção pra possível regressão:** Especialista preset (mais usado) **TEM** várias perms `patients.*` e `agenda.*`. Confirmar com debug do preset que `view` está marcado true. Caso contrário, validar com role temp `Test-A8` com 0 perms.

**Risco / regressão:**

- **Mudança esperada:** agents sem a perm respectiva no Klivy perdem acesso por URL às páginas mapeadas. Sidebar já escondia o item se `moduleEnabled` voltasse false.
- **Sem regressão para:** admin (bypass via `isAdmin` no router guard).
- **Cenário de quebra possível:** se algum role customizado em prod **dependia** do fail-open de `moduleEnabled` para ver Patients/Agenda sem ter explicitamente `*.view=true` no JSONB. Improvável — todos os 4 presets atuais marcam `patients.view`/`agenda.view` corretamente quando aplicável.
- **Sem necessidade de restart:** mudança puramente frontend; Vite HMR cobre.

---

### Lote 7 — `1.6.1.19` (2026-05-17)

**Escopo:** C-2 — defesa final contra privilege escalation no `KlivyRolesController`. Fecha o último vetor crítico de elevação (C-1 já fechou o front-end gating, C-2 fecha o backend).

| ID | Tipo | Arquivos | Diff resumo | Validação |
|---|---|---|---|---|
| **C-2** | Privilege escalation via mass-assignment de permissions JSONB | `plugins/custom_roles/app/models/klivy_role/permissions_catalog.rb` (novo) + `plugins/custom_roles/app/models/klivy_role.rb` + `plugins/custom_roles/app/controllers/api/v1/accounts/klivy_roles_controller.rb` | (a) Catálogo Ruby espelha `modules.js`. (b) Model: `before_validation :sanitize_permissions`. (c) Controller: `enforce_delegation_limit!` + `PrivilegeEscalationError → 403`. (d) **`sanitize_and_migrate` aceita `ActionController::Parameters`** via `to_unsafe_h` — sem esse cast a checagem ficava silenciosa (bug encontrado e fixado durante validação). | ✅ Validado em 2026-05-17 (localhost / Docker): role temp `Test-C2` com `roles_create + users_edit + chat.{view_all,reply}` (sem `delete_message`) → curl tentando delegar `chat.delete_message=true` → **403** + `forbidden:["chat.delete_message"]`. Curl com `chat.view_all` (perm que tem) → **201**. Admin sem regressão. |

**Por que 3 camadas (sanitize + delegation):**

- **Sanitize (model)** garante higiene do JSONB independente de quem chama. Mesmo um teste/seed/migration que setasse `permissions = { foo: { bar: true } }` em um KlivyRole resultaria em hash vazio após save.
- **Sanitize ANTES de `enforce_delegation_limit!`** no controller é importante: roda primeiro pra que keys legadas se expandam para keys novas que serão de fato avaliadas. Sem isso, requester com `manage_users` legado em si poderia delegar `users_view/_edit/etc.` sem ter as keys novas.
- **Delegation limit (controller)** bloqueia o vetor de escalation. Admin/SuperAdmin têm bypass via `beclinic_can?`/`beclinic_scope` que retornam true/'all' para eles.

**Casos cobertos:**

| Cenário | Esperado |
|---|---|
| Admin cria role com qualquer perm | OK (bypass) |
| Gerente cria role com perms que tem | OK |
| Gerente cria role com `chat.delete_message=true` (que tem) | OK |
| User com role customizada `roles_create + users_edit` mas SEM `chat.delete_message` → tenta delegar `chat.delete_message=true` | 403 + `forbidden: ["chat.delete_message"]` |
| User com `agenda.scope=own` tenta delegar `agenda.scope=all` | 403 + `forbidden: ["agenda.scope=all"]` |
| Payload com key inventada `{ foo: { bar: true } }` | Aceito (silenciosamente drop), role salva com `permissions={}` |
| Payload com key legada `settings.manage_users=true` (Gerente que tem `users_*`) | Aceito; salvo como `users_view/_invite/_edit/_remove=true` |

**Como validar (terminal):**

```bash
# Cria role temp limitada pra Leandro: roles_create + users_edit + chat.view_all
# (SEM chat.delete_message — propositadamente)
docker exec -i beclinic-rails-1 bash -c "cat > /tmp/c2_setup.rb" <<'EOF'
account = Account.find(31)
role = account.klivy_roles.find_or_create_by!(name: 'Test-C2') do |r|
  r.description = 'Validar C-2 — pode criar role mas não delega delete_message'
  r.permissions = {
    'settings' => { 'roles_view' => true, 'roles_create' => true, 'roles_edit' => true, 'users_edit' => true },
    'chat' => { 'view_all' => true, 'reply' => true }
  }
end
leandro = User.find_by!(email: 'leandro@benuv.com')
au = leandro.account_users.find_by!(account_id: 31)
puts "PREV_LEANDRO_ROLE_ID=#{au.klivy_role_id}"
au.update!(klivy_role_id: role.id)
puts "ROLE_ID=#{role.id}"
EOF
docker exec beclinic-rails-1 bundle exec rails runner /tmp/c2_setup.rb

AGENT='MRcVscwkHuDMCa8oATXwzm3e'

# 1) Leandro tenta criar role com chat.delete_message=true (não tem) → 403
curl -s -X POST -H "api_access_token: $AGENT" -H 'Content-Type: application/json' \
  -d '{"klivy_role":{"name":"Escalada","permissions":{"chat":{"delete_message":true}}}}' \
  http://localhost:3000/api/v1/accounts/31/klivy_roles
# Esperado: 403 {"error":"forbidden_permission_escalation","forbidden":["chat.delete_message"]}

# 2) Leandro cria role só com chat.view_all (tem) → 200
curl -s -X POST -H "api_access_token: $AGENT" -H 'Content-Type: application/json' \
  -d '{"klivy_role":{"name":"Limitada","permissions":{"chat":{"view_all":true}}}}' \
  http://localhost:3000/api/v1/accounts/31/klivy_roles | jq '{id, name, permissions}'
# Esperado: 200 com role criada

# 3) Sanitize: payload com key inventada → silenciosamente dropada
curl -s -X POST -H "api_access_token: $AGENT" -H 'Content-Type: application/json' \
  -d '{"klivy_role":{"name":"ComLixo","permissions":{"foo":{"bar":true},"chat":{"view_all":true}}}}' \
  http://localhost:3000/api/v1/accounts/31/klivy_roles | jq '{id, name, permissions}'
# Esperado: 200, permissions só tem chat.view_all (foo dropado)

# 4) Sanity admin: pode tudo
ADMIN='XSw1X9NAYgfZ1iLRdM4Mxako'
curl -s -X POST -H "api_access_token: $ADMIN" -H 'Content-Type: application/json' \
  -d '{"klivy_role":{"name":"AdminAll","permissions":{"chat":{"delete_message":true,"send_broadcast":true}}}}' \
  http://localhost:3000/api/v1/accounts/31/klivy_roles | jq '{id, name, permissions}'
# Esperado: 200, todas as perms aceitas

# Cleanup ao final:
docker exec beclinic-rails-1 bundle exec rails runner '
account = Account.find(31)
au = User.find_by!(email: "leandro@benuv.com").account_users.find_by!(account_id: 31)
au.update!(klivy_role_id: 1)
%w[Test-C2 Limitada ComLixo AdminAll].each do |n|
  r = account.klivy_roles.find_by(name: n)
  if r
    AccountUser.where(klivy_role_id: r.id).update_all(klivy_role_id: nil)
    r.destroy!
    puts "DELETED #{n}"
  end
end
'
```

**Risco / regressão:**

- **Roles legadas em prod com keys flat (`settings.manage_users` etc.)**: migradas automaticamente na próxima save (sem perda de perms). Comportamento idêntico ao do `LEGACY_KEY_MIGRATIONS` no frontend.
- **Roles com keys inventadas (lixo no JSONB)**: silenciosamente dropadas no próximo save. Aceitável — esse "lixo" não tinha efeito (nenhum código consumia).
- **Admin/SuperAdmin**: zero mudança — bypass total.
- **Gerente preset**: tem TODAS as perms `settings.*` + amplos perms de chat/patients/agenda → continua criando roles inclusive com perms estritas dele mesmo.
- **Roles customizadas no campo (caso raro hoje)**: se tiverem `roles_create + users_edit` mas perm clínica limitada, ficam impedidas de criar role com perms clínicas que não têm — comportamento DESEJADO (não pode delegar mais do que tem).
- **Cliente legado que envia payload sem ser pelo editor oficial**: keys desconhecidas são dropadas silenciosamente. Sem 422 — escolha consciente (resposta à pergunta do usuário no Lote 7).

---

### Lote 6 — `1.6.1.18` (2026-05-17) — bug AddAgent (pré-existente, não relacionado à auditoria)

**Escopo:** correção de bug que impedia criação de qualquer agente novo via UI. Descoberto durante diagnóstico do Lote 1 (A-9) — confirmou-se ser **pré-existente**, sem relação com nenhum fix da auditoria. Documentado aqui por ter sido encontrado no mesmo ciclo.

**Sintoma:** UI mostrava toast "Não foi possível conectar ao servidor Woot, por favor tente novamente mais tarde" ao tentar adicionar novo agente. Servidor retornava 500 com:

```
ActiveRecord::NotNullViolation: null value in column "account_id" of relation
"beclinic_user_profiles" violates not-null constraint
```

**Causa raiz:**

1. `AgentBuilder#perform` ([app/builders/agent_builder.rb:16-22](app/builders/agent_builder.rb#L16)) abre transaction; cria `User` PRIMEIRO, depois `AccountUser`.
2. `after_create :ensure_agenda_public_id` no User (definido em [plugins/agenda/lib/agenda/engine.rb:29](plugins/agenda/lib/agenda/engine.rb#L29)) dispara nesse instante.
3. O método chama `profile = beclinic_profile`. O association em [plugins/beclinic_core/lib/beclinic_core/engine.rb:34](plugins/beclinic_core/lib/beclinic_core/engine.rb#L34) é `has_one :beclinic_profile, autosave: true` e o getter (linha 36-38) faz `super || build_beclinic_profile` — anexa uma instância em memória ao user com `account_id=nil`.
4. O método tem early return se `profile.account_id.blank?` — mas isso só evita o `profile.save!` MANUAL.
5. O **`autosave: true`** força o profile a ser persistido junto com qualquer `User.save` subsequente. Ao final da transaction, `User.save` dispara INSERT em `beclinic_user_profiles` com `account_id=NULL` → constraint NOT NULL violada (migration `20260514100001_add_account_to_beclinic_user_profiles` torna a coluna NOT NULL).
6. Transaction rolla back → User não persistido, AccountUser não persistido → "Beatriz" (e qualquer outro tentativa) ficavam fantasmas no UI mas inexistentes no DB.

**Fix aplicado** ([plugins/agenda/lib/agenda/engine.rb](plugins/agenda/lib/agenda/engine.rb)):

1. **Early return ANTES de tocar `beclinic_profile`**: `return unless account_users.exists?`. Evita o `build_beclinic_profile` quando ainda não há AccountUser — sem instância em memória, nada pra autosave.
2. **Backstop em `AccountUser.after_create_commit`**: novo hook `ensure_user_agenda_public_id` que chama `user&.ensure_agenda_public_id` depois do commit do AccountUser. Garante que o profile é criado no momento certo do fluxo AgentBuilder.

| ID | Tipo | Arquivos | Diff resumo | Validação |
|---|---|---|---|---|
| **bug-AddAgent** | NotNullViolation em autosave | `plugins/agenda/lib/agenda/engine.rb` | `User#ensure_agenda_public_id` faz early return se `account_users.exists? == false`. Adicionado `AccountUser.after_create_commit :ensure_user_agenda_public_id` como backstop. | ✅ Validado em 2026-05-17 (localhost / Docker): após restart de `beclinic-rails-1` + `beclinic-sidekiq-1`, criação de `teste-bug2@benuv.com` via UI → `USER id=869 agenda_public_id=iu0wbwql profile_account_id=31 account_users=[[31,"agent"]]`. Beatriz (Gerente) também criada com sucesso |

**Risco / regressão:**

- **Sem regressão para:** fluxos onde User já tem AccountUser antes do `User.save` (ex.: Devise signup com nested attributes — não comum no Chatwoot atual).
- **Mudança esperada:** users criados sem AccountUser ficam SEM `beclinic_profile`/`agenda_public_id` até receberem o primeiro vínculo. Quando o AccountUser for criado, o backstop dispara automaticamente. Cenário improvável em prod mas tratado.
- **Restart obrigatório:** mudança em `lib/` de engine; Vite HMR não cobre. `docker restart beclinic-rails-1 beclinic-sidekiq-1` necessário.

---

### Lote 5 — `1.6.1.17` (2026-05-17)

**Escopo:** A-7 — `CannedResponsesController` sem nenhum gating de autorização.

| ID | Tipo | Arquivos | Diff resumo | Validação |
|---|---|---|---|---|
| **A-7** | Missing policy / Authorization gap | `app/policies/canned_response_policy.rb` (novo) + `app/controllers/api/v1/accounts/canned_responses_controller.rb` | Criada `CannedResponsePolicy` (5 actions + Scope) mapeada para `settings.canned_view/_create/_edit/_delete`. Controller ganhou `before_action :check_authorization` que invoca Pundit automaticamente. | ✅ Validado em 2026-05-17 (localhost / Docker): role temp `Test-A7` com só `canned_view` → ADMIN_INDEX=200, AGENT_INDEX=200, AGENT_CREATE=401, ADMIN_CREATE=200 |

**Como validar:**

```bash
# Setup: role temp só com canned_view, atribuir ao Leandro
docker exec -i beclinic-rails-1 bash -c "cat > /tmp/a7_setup.rb" <<'EOF'
account = Account.find(31)
role = account.klivy_roles.find_or_create_by!(name: 'Test-A7') do |r|
  r.description = 'Validar A-7 — só canned_view'
  r.permissions = { 'settings' => { 'canned_view' => true } }
end
leandro = User.find_by!(email: 'leandro@benuv.com')
au = leandro.account_users.find_by!(account_id: 31)
puts "PREV_ROLE_ID=#{au.klivy_role_id}"
au.update!(klivy_role_id: role.id)
puts "ROLE_ID=#{role.id}"
EOF
docker exec beclinic-rails-1 bundle exec rails runner /tmp/a7_setup.rb

# Testar
AGENT='MRcVscwkHuDMCa8oATXwzm3e'
ADMIN='XSw1X9NAYgfZ1iLRdM4Mxako'

# 1. Admin lista — esperado 200
curl -s -o /dev/null -w "ADMIN_INDEX=%{http_code}\n" -H "api_access_token: $ADMIN" \
  http://localhost:3000/api/v1/accounts/31/canned_responses

# 2. Leandro (só canned_view) lista — esperado 200
curl -s -o /dev/null -w "AGENT_INDEX=%{http_code}\n" -H "api_access_token: $AGENT" \
  http://localhost:3000/api/v1/accounts/31/canned_responses

# 3. Leandro tenta criar — esperado 401/403 (não tem canned_create)
curl -s -o /dev/null -w "AGENT_CREATE=%{http_code}\n" -X POST -H "api_access_token: $AGENT" \
  -H 'Content-Type: application/json' \
  -d '{"canned_response":{"short_code":"a7test","content":"test"}}' \
  http://localhost:3000/api/v1/accounts/31/canned_responses

# 4. Admin cria — esperado 200/201
curl -s -o /dev/null -w "ADMIN_CREATE=%{http_code}\n" -X POST -H "api_access_token: $ADMIN" \
  -H 'Content-Type: application/json' \
  -d '{"canned_response":{"short_code":"a7admin","content":"admin test"}}' \
  http://localhost:3000/api/v1/accounts/31/canned_responses
```

Cleanup posterior:
```bash
docker exec beclinic-rails-1 bundle exec rails runner '
account = Account.find(31)
au = User.find_by!(email: "leandro@benuv.com").account_users.find_by!(account_id: 31)
au.update!(klivy_role_id: 1)
test = account.klivy_roles.find_by(name: "Test-A7")
test&.destroy!
account.canned_responses.where(short_code: %w[a7admin]).destroy_all
puts "CLEANUP_OK"
'
```

---

### Lote 4 — `1.6.1.16` (2026-05-17)

**Escopo:** A-6 (vazamento de consents para profissional com `scope=own`) + A-8 (criação de evento de agenda em nome de outro profissional via `user_id` mass-assignment). Ambos backend, compliance LGPD/HIPAA.

| ID | Tipo | Arquivos | Diff resumo | Validação |
|---|---|---|---|---|
| **A-6** | PHI leak (LGPD) | `plugins/patients/app/controllers/api/v1/accounts/patients/consent_records_controller.rb` + `app/policies/consent_record_policy.rb` | Controller: `set_patient` agora usa `policy_scope(Current.account.patients).find(...)` — herda o filtro `scope=own` do `PatientPolicy::Scope`. Policy: `Scope.resolve` faz `joins(:patient).where(patients: { responsible_professional_id: user.id })` quando `scope=own` (defesa em profundidade). | ✅ Validado em 2026-05-17 (localhost / Docker): Leandro role temp `patients.scope=own` → GET `/patients/17/consents` (não é responsável) → 404; GET `/patients/16/consents` (é responsável) → 200 + 11 consents |
| **A-8** | Mass-assignment cross-professional | `plugins/agenda/app/controllers/api/v1/accounts/agenda_events_controller.rb` | Novo helper `clamp_user_id_for_own_scope(safe_params)`. Chamado em `create` e `update`. Quando `beclinic_scope(:agenda) == 'own'`, força `user_id = Current.user.id`. Admin/SuperAdmin (`scope=all`) e AgentBot (sem método) passam direto. | ✅ Validado em 2026-05-17 (localhost / Docker): Leandro role temp `agenda.scope=own` + POST `user_id:32` → evento criado com `user_id:33` (clamped); admin POST `user_id:32` → evento criado com `user_id:32` (preservado) |

**Por que dois pontos no A-6:**

Mesmo o `policy_scope` no controller cobrindo o entry point principal (`/patients/:id/consents`), corrigir só ali deixaria a `Scope.resolve` do policy ainda inconsistente para qualquer código futuro que chame `policy_scope(ConsentRecord)` direto. Defesa em profundidade.

**Risco / regressão:**

- **A-6 lado controller**: `policy_scope(Current.account.patients)` retorna a mesma coisa que `Current.account.patients` quando `scope=all`. Para `scope=own`, restringe a `responsible_professional_id = user.id`. Para admin/SuperAdmin, idem `scope=all`. **Único cenário onde muda:** non-admin com `patients` `scope=own` chamando consents de paciente que não é seu — vai retornar 404 em vez de vazar.
- **A-6 lado policy**: o `joins(:patient)` adiciona um JOIN simples; performance OK porque `consent_records.patient_id` é indexed e `patients.responsible_professional_id` também (asumido — convém validar). Sem `policy_scope(ConsentRecord)` no codebase ativo, é defensivo puro.
- **A-8**: o helper não modifica `user_id` para admin/SuperAdmin (cenário comum). Para non-admin `scope=own`, o `user_id` no payload é ignorado e substituído pelo próprio user. Cenário onde quebra: clínica usa um profissional "secretária" (`scope=own`) que cria eventos em nome do dentista — antes funcionava, agora não. **Solução nesse caso:** dar à secretária role com `scope=all` em agenda, ou criar role específica de recepção com `scope=all` mas perms restritas. Os 4 presets atuais (Recepcionista, Especialista, Gerente, SDR) — vale checar qual o `scope` padrão deles.

**Como validar:**

A-6 (terminal):
```bash
# 1) Encontrar um paciente que NÃO é do Leandro
docker exec beclinic-rails-1 bundle exec rails runner '
account = Account.find(31)
leandro = User.find_by!(email: "leandro@benuv.com")
not_mine = account.patients.where.not(responsible_professional_id: leandro.id).first
puts "PATIENT_NOT_MINE_ID=#{not_mine&.id}"
puts "PATIENT_NOT_MINE_RESP=#{not_mine&.responsible_professional_id}"
'

# 2) Garantir Leandro tem role com patients.scope=own + view_consents
#    (ver §18 Lote 4 setup mais abaixo)

# 3) Tentar listar consents do paciente que não é dele
curl -s -i -H "api_access_token: $AGENT_TOKEN" \
  http://localhost:3000/api/v1/accounts/31/patients/<PATIENT_NOT_MINE_ID>/consents
# Esperado: 404 com "Paciente não encontrado"
# Antes do fix: 200 vazando os consents
```

A-8 (terminal):
```bash
# Leandro com role agenda scope=own (Especialista preset já é). user_id=99 é outro user.
# Criar evento via API (precisa de contact_id, agenda_service_id válidos — adapt)
curl -s -X POST -H "api_access_token: $AGENT_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"agenda_event":{"title":"A-8 test","starts_at":"2026-05-20T10:00:00-03:00","ends_at":"2026-05-20T11:00:00-03:00","user_id":99}}' \
  http://localhost:3000/api/v1/accounts/31/agenda_events
# Esperado: 200 com evento criado, mas user_id no response = leandro.id (não 99)
# Antes do fix: criava com user_id=99
```

UI:
- Leandro abre prontuário de paciente sob seu cuidado → consents aparecem normalmente.
- Leandro digita URL de prontuário de paciente fora do seu cuidado → 404 ou redirect (depende de outras camadas).
- Leandro tenta arrastar/recriar evento na agenda → evento fica sob `leandro.user_id` mesmo se UI tentar setar outro.

---

### Lote 3 — `1.6.1.15` (2026-05-17)

**Escopo:** fix A-4 — fechar bypass de gating em 4 áreas administrativas (inbox, teams, integrations, assignment policy) que herdavam o mesmo padrão do C-1.

| ID | Tipo | Arquivo | Diff resumo | Validação |
|---|---|---|---|---|
| **A-4** | Bypass de router via prefix loose | `app/javascript/dashboard/helper/routeHelpers.js` | 7 entradas removidas de `KLIVY_PREFIX_ROUTE_RULES` (`settings_inbox`, `settings_inboxes`, `settings_teams`, `settings_applications`, `assignment_policy`, `agent_assignment_policy`, `agent_capacity_policy`). 21 EXACT rules adicionadas em `KLIVY_EXACT_ROUTE_RULES` cobrindo todas as rotas filhas com a perm coerente. Objeto `KLIVY_PREFIX_ROUTE_RULES` agora vazio. | ✅ Validado em 2026-05-17 (localhost / Docker + Vite HMR): Leandro (Especialista, todas perms settings=false) redirecionado em `/settings/inboxes/new`, `/teams/new`, `/integrations`, `/assignment-policy/assignment/create` |

**Por que cada perm escolhida:**

| Route name | Antes (prefix) | Agora (exact) | Justificativa |
|---|---|---|---|
| `settings_inbox_list` | `inboxes_view` | `inboxes_view` | Lista — leitura |
| `settings_inbox_show` | `inboxes_view` | `inboxes_view` | Tela de configuração: navegação livre, actions internas protegidas por `v-can` + `InboxPolicy#update?` |
| `settings_inbox_new` | `inboxes_view` ❌ | `inboxes_create` | Início do wizard de criação |
| `settings_inbox_finish` | `inboxes_view` ❌ | `inboxes_create` | Última etapa do wizard |
| `settings_inboxes_page_channel` | `inboxes_view` ❌ | `inboxes_create` | Seleção de canal no wizard |
| `settings_inboxes_add_agents` | `inboxes_view` ❌ | `inboxes_manage_agents` | Adição de agents ao inbox |
| `settings_teams_list` | `teams_view` | `teams_view` | Lista |
| `settings_teams_new/_finish/_add_agents` | `teams_view` ❌ | `teams_create` | Fluxo `/new/...` |
| `settings_teams_edit/_edit_members/_edit_finish` | `teams_view` ❌ | `teams_edit` | Fluxo `/edit/...` |
| `settings_applications` | `integrations_view` | `integrations_view` | Lista de integrações |
| `settings_applications_integration` | `integrations_view` | `integrations_view` | Página da integração (config interna usa `v-can`/backend) |
| `assignment_policy_index` | `users_view` | `users_view` | Index |
| `agent_assignment_policy_index/_capacity_index` | `users_view` | `users_view` | Index |
| `agent_assignment_policy_create/_edit, _capacity_create/_edit` | `users_view` ❌ | `users_edit` | Mutações exigem perm de edição |

**Risco / regressão:**

- **Mudança esperada:** non-admins com APENAS `*_view` perdem acesso por URL às telas de criação/edição (era brecha em todas as 4 áreas).
- **Sem regressão para:** admin (bypass via `isAdmin`); Gerente preset (tem todas as perms de inboxes/teams/integrations/users); presets sem perm específica já eram bloqueados pelo sidebar gate.
- **Sidebar não tocada:** `Sidebar.vue#CHILD_GATES.Settings` continua usando `*_view` para mostrar/ocultar itens — sem mudança visual.
- **Rotas `settings_integrations_slack/linear/notion/shopify/webhook/dashboard_apps`** não estavam no prefix antigo nem no novo conjunto EXACT — continuam apenas para admin (intencional; instalação OAuth/configuração de dashboard apps é admin-only).

**Como validar:**

UI (precisa front rodando):

| Cenário | URL | Esperado antes | Esperado agora |
|---|---|---|---|
| Admin | qualquer URL admin | OK | OK (sem mudança) |
| Especialista (sem `inboxes_create`) | `/settings/inboxes/new` | Entrava ❌ | Redireciona ✅ |
| Especialista | `/settings/inboxes/list` | Entrava | Entra (mas sidebar esconde — só URL direta) — atenção: Especialista não tem `inboxes_view` no preset, então redireciona |
| Especialista (sem `teams_create`) | `/settings/teams/new` | Entrava ❌ | Redireciona ✅ |
| Especialista (sem `teams_edit`) | `/settings/teams/:id/edit` | Entrava ❌ | Redireciona ✅ |
| Especialista (sem `integrations_view`) | `/settings/integrations` | Entrava | Redireciona (Especialista preset não tem) |
| Gerente (tem tudo) | qualquer rota acima | OK | OK |

Backend (terminal) — confirma estado de perms do Leandro:
```bash
docker exec beclinic-rails-1 bundle exec rails runner '
account = Account.find(31)
leandro = User.find_by!(email: "leandro@benuv.com")
%w[inboxes_view inboxes_create inboxes_manage_agents teams_view teams_create teams_edit integrations_view users_view users_edit].each do |p|
  puts "#{p}=#{leandro.beclinic_can?(account, :settings, p.to_sym)}"
end
'
# Esperado para Especialista: todas false (preset Especialista não toca settings/*)
```

---

### Lote 2 — `1.6.1.14` (2026-05-17)

**Escopo:** fix C-1 — fechar bypass de gating de UI/router para `/settings/custom-roles/new` e `/settings/custom-roles/:id/edit` via prefix loose.

| ID | Tipo | Arquivo | Diff resumo | Validação |
|---|---|---|---|---|
| **C-1** | Bypass de router via prefix loose | `app/javascript/dashboard/helper/routeHelpers.js` | Removida entry `klivy_roles` de `KLIVY_PREFIX_ROUTE_RULES`. Adicionadas 3 EXACT rules: `klivy_roles_list → roles_view`, `klivy_roles_new → roles_create`, `klivy_roles_edit → roles_edit`. Granularidade alinhada com o controller (`authorize_action!`). | ✅ Validado em 2026-05-17 (localhost / Docker + Vite HMR): admin entra em `/custom-roles/new`; Especialista (sem `roles_view`) redireciona em `/list`, `/new` e `/:id/edit` |

**Por que NÃO simplifiquei pra `klivy_roles_list` apenas (como o doc original sugeria):**

O backend `KlivyRolesController#authorize_action!` já libera `create` para `roles_create` e `update` para `roles_edit` — não é admin-only. Bloquear o front com base só em `roles_view` deixaria a UI inconsistente com o backend: um Gerente com `roles_create` clicaria em "Nova função" e seria redirecionado, mesmo tendo a perm. Manter as 3 perms permite que cada nível de role tenha exatamente a UI que pode usar. **A barreira definitiva contra privilege escalation continua sendo C-2** (whitelist do payload `permissions`), que ainda está pendente.

**Risco / regressão:**

- **Quebra esperada (intencional):** non-admin com APENAS `roles_view` que estiver acessando `/custom-roles/new` ou `/custom-roles/:id/edit` por URL favoritada — será redirecionado. Eles não deveriam estar lá (bug do prefix).
- **Sem regressão para:** admin (bypass via `isAdmin`), Gerente preset (tem `roles_create + roles_edit + roles_delete`), usuários sem nenhuma perm de roles (já eram bloqueados).
- **Sidebar não afetada:** `Sidebar.vue` usa `CHILD_GATES.Settings['Settings Custom Roles']: ['settings','roles_view']` — só esconde/mostra o item de menu, não afeta as 3 rotas internas.

**Como validar manualmente:**

Backend (terminal):
```bash
# Pegar token de um agent com roles_view=false (Especialista por padrão)
# E rodar uma chamada para a API — o front é só de gating, o backend já estava OK
docker exec beclinic-rails-1 bundle exec rails runner '
account = Account.find(31)
leandro = User.find_by!(email: "leandro@benuv.com")
au = leandro.account_users.find_by!(account_id: 31)
puts "AGENT_KLIVY_ROLE=#{au.klivy_role.name}"
puts "AGENT_HAS_roles_view=#{leandro.beclinic_can?(account, :settings, :roles_view)}"
puts "AGENT_HAS_roles_create=#{leandro.beclinic_can?(account, :settings, :roles_create)}"
puts "AGENT_HAS_roles_edit=#{leandro.beclinic_can?(account, :settings, :roles_edit)}"
'

# Esperado para Especialista (sem perm de roles): todas false
# Verificar via API que tentar criar role já retornava 403 antes do fix
curl -s -i -X POST -H "api_access_token: $AGENT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"klivy_role":{"name":"hack","permissions":{}}}' \
  http://localhost:3000/api/v1/accounts/31/klivy_roles
# Esperado: 403 {"error":"forbidden"} — confirma que backend já estava OK
```

UI (precisa do front buildado/rodando):
1. Login como Especialista (Leandro). Configurações → menu lateral: "Funções personalizadas" não deve aparecer (pois `roles_view=false`).
2. Mesmo Leandro: tentar URL direta `/app/accounts/31/settings/custom-roles/list` → deve redirecionar para dashboard.
3. Mesmo Leandro: tentar `/app/accounts/31/settings/custom-roles/new` → deve redirecionar.
4. Trocar pra admin → mesma URL → entra normalmente.
5. Criar role temporária "Test-C1-view" com `settings.roles_view=true` apenas (sem `roles_create/edit/delete`), atribuir a um agent de teste, logar como ele:
   - `/custom-roles/list` → entra.
   - `/custom-roles/new` → redireciona (era brecha; agora fechada).
   - `/custom-roles/:id/edit` → redireciona.
6. Reverter agent + deletar role temp.

---

### Lote 1 — `1.6.1.13` (2026-05-17)

**Escopo:** dois fixes cirúrgicos de baixo risco que não alteram comportamento legítimo.

| ID | Tipo | Arquivo | Diff resumo | Validação |
|---|---|---|---|---|
| **A-9** | Information disclosure | `app/views/api/v1/models/_agent.json.jbuilder` | Adicionado guard `viewer_can_see_role_internals` (admin OR `settings.users_view`). Esconde `custom_role_id`, `klivy_role_id`, `beclinic_super_admin`, `klivy_role.id`, `klivy_role.preset_key` de não-admins. Mantém `klivy_role.name` público porque o prontuário usa em qualquer agent com `patients.view`. | ✅ Validado em 2026-05-17 (localhost / Docker): admin vê os 5 campos, Especialista sem `users_view` vê só `klivy_role.name` |
| **C-4** | Bypass parcial de policy | `app/controllers/api/v1/accounts/conversations_controller.rb` | `authorize @conversation, :reply?` adicionado antes do `Messages::MessageBuilder.perform` dentro do `if params[:message].present?`. | ✅ Validado em 2026-05-17 (localhost / Docker): role Test-C4 (`send_broadcast=true + reply=false`) → 401 com mensagem; sem mensagem → 200; admin → 200 (bypass intacto) |

**Validação manual recomendada (terminal — sem build do front):**

```bash
# Pré-requisito: ter cookie de sessão de um admin e de um agent (Recepcionista) salvos
# em cookies_admin.txt e cookies_agent.txt. Substitua o accountId conforme necessário.

# A-9 — admin: TODOS os campos sensíveis devem aparecer
curl -s -b cookies_admin.txt http://localhost:3000/api/v1/accounts/31/agents \
  | jq '.[0] | {klivy_role, klivy_role_id, custom_role_id, beclinic_super_admin}'
# Esperado: { "klivy_role": { "name": "...", "id": <n>, "preset_key": "..." }, "klivy_role_id": <n>, "custom_role_id": <n|null>, "beclinic_super_admin": <bool> }

# A-9 — non-admin sem settings.users_view: campos sensíveis devem SUMIR
curl -s -b cookies_agent.txt http://localhost:3000/api/v1/accounts/31/agents \
  | jq '.[0] | {klivy_role, klivy_role_id, custom_role_id, beclinic_super_admin}'
# Esperado: { "klivy_role": { "name": "..." }, "klivy_role_id": null, "custom_role_id": null, "beclinic_super_admin": null }
# (jq retorna null para chaves ausentes; o payload real omite o campo)

# C-4 — tentar criar conversa com mensagem como user com reply=false (improvável com presets atuais
# mas pode ser simulado editando a role do agente para desligar chat.reply manualmente)
curl -s -X POST -b cookies_agent_no_reply.txt \
  -H 'Content-Type: application/json' \
  -d '{"inbox_id":1,"contact_id":1,"source_id":"abc","message":{"content":"oi"}}' \
  http://localhost:3000/api/v1/accounts/31/conversations
# Esperado: 401/403 com erro de Pundit; conversa NÃO criada (transaction rollback)
```

**Validação manual recomendada (UI):**

A-9:
1. Logar como admin → `Configurações → Agentes`. Badges com nome de role aparecem normalmente, sem regressão visual.
2. Trocar para usuário com role "Recepcionista" (ou qualquer KlivyRole sem `settings.users_view`) → abrir prontuário de qualquer paciente → o badge do profissional responsável continua aparecendo com o nome da role (ex.: "Especialista"). **Não pode** quebrar essa exibição.
3. Abrir DevTools → Network → recarregar página → inspecionar a chamada `GET /api/v1/accounts/<id>/agents`. No payload de um agent sem `users_view`, os campos `klivy_role_id`, `beclinic_super_admin`, `custom_role_id`, `klivy_role.id` e `klivy_role.preset_key` devem estar **ausentes**.

C-4:
1. Sem mexer em código, é difícil reproduzir o cenário (todos os presets têm `reply=true`). Para validar: criar role "Test C-4" com `chat.send_broadcast=true` e `chat.reply=false`, atribuir a um agent de teste, tentar criar uma conversa nova com mensagem inicial pelo composer — deve falhar com erro 403. Reverter a role após teste.
2. Sanity check com role normal (Recepcionista): criar conversa nova com mensagem inicial — deve funcionar como antes.

**Sem regressões esperadas em:**

- `professionalRoles.js#resolveAgentRoleLabel` (usa `klivy_role.name` que continua público).
- `ChangeResponsibleModal.vue`, `AuditLogsTable.vue` (idem).
- `Settings/Agents/Index.vue` (usuários que abrem essa tela têm `users_view` por definição do sidebar gating).
- `AssignRoleModal.vue` (usuários que atribuem role têm `users_edit` ⊇ `users_view`).
- Criação de conversa por admin/agent com `reply=true` (todos os presets).
- AgentBot criando conversas (`ConversationPolicy#reply?` aceita `agent_bot?`).
