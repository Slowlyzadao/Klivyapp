# Funções Personalizadas (Custom Roles / RBAC granular)

> Implementação inicial: 2026-04-25
> Atualização 1 (gating fino da Agenda + Configurações + Atributos Personalizados): 2026-04-26
> Atualização 2 (catálogo agrupado + sub-permissões CRUD nas Configurações): 2026-04-26
> Atualização 3 (gating ponta-a-ponta de Caixas de Entrada — Pundit + auto-assign InboxMember): 2026-04-26
> Atualização 4 (gating do módulo `chat` — reply box, assignee, broadcast, message destroy): 2026-04-26
> Atualização 5 (sub-permissões do painel direito da conversa + ações do header do contato + cadeado em /contacts/:id): 2026-04-25
> Atualização 11 (auditoria completa de Settings + Custom Roles compartilhados por conta + admins intocáveis): 2026-04-25
> Plugin: `plugins/custom_roles/`
> Rotas: `/settings/custom-roles`

---

## 1. Visão geral

Sistema de **funções (roles) com permissões granulares por módulo** atribuídas
**direto ao usuário** (via `account_users.klivy_role_id`), independente de Time.
Substitui as duas tentativas anteriores que ficaram órfãs:

- `CustomRole` legacy do Chatwoot Enterprise (UI antiga em `/settings/custom-roles`).
- `BeClinicRoles` baseado em Times (UI nova em `/settings/roles`).

### Como funciona em uma frase

> Cada agente recebe uma `KlivyRole`. Cada role tem um hash `permissions` JSONB
> com **12 módulos × N sub-permissões**. O sidebar consulta `usePermissions().moduleEnabled(key)`
> e remove módulos inteiros do menu quando todas as sub-permissões deles estão `false`.
> Botões/ações dentro das telas são gated com `v-if="can(modulo, acao)"`.
> Tabs/páginas que recebem 401/403 do backend mostram um cadeado `<PermissionDenied />`
> em vez de toast de erro técnico.

### Catálogo agrupado (atualização 2)

A partir de 2026-04-26 o catálogo de módulos suporta **dois esquemas** mutualmente exclusivos:

- `permissions: Permission[]` — **flat**, comportamento original. Adequado para módulos pequenos (`inbox`, `chat`, `captain`, `contacts`, `reports`, `campaigns`, `help_center`, `help`, `patients`, `financial`).
- `groups: Group[]` — **agrupado**, com cada grupo tendo header próprio, contador `(N/M)` e botão "Marcar todos / Desmarcar todos". Adequado para módulos extensos (`agenda`, `settings`).

Cada `Group = { key, label, icon?, permissions: Permission[] }`. Independente do esquema, a chave de permissão final é flat dentro do hash JSONB — o backend continua armazenando `{ settings: { inboxes_view: true, ... } }` sem nesting. O agrupamento é puramente visual + de UX (toggle por grupo).

Helpers em `shared/modules.js`:
- `flattenPermissions(module)` — retorna a lista de Permissions independente do esquema.
- `groupPermissions(module, groupKey)` — só usado em UI agrupada.
- `moduleHasGroups(module)` — discriminador.
- `countActiveInGroup(perms, moduleKey, groupKey)` — para o "(2/4)" no header.
- `LEGACY_KEY_MIGRATIONS` (interno) — mapeia chaves antigas (`manage_inboxes`, `manage_users`, etc.) para as novas durante `normalizePermissions`. Roles antigas com `manage_inboxes: true` ganham automaticamente `inboxes_view/create/edit/delete/manage_agents: true` ao serem carregadas.

UI: `ModuleSection.vue` decide entre renderizar a lista flat ou delegar para múltiplos `PermissionGroup.vue`. Cada `PermissionGroup` é colapsável e tem o seu próprio "Marcar todos" — o usuário pode controlar gerência de Caixas de Entrada sem mexer em Etiquetas, por exemplo.

### Resolução de permissão (back e front)

Ordem de precedência (em `BeclinicPermissible#beclinic_can?`):

1. `SuperAdmin` (BeClinic) → bypass total
2. Chatwoot `administrator` na conta → bypass total
3. **Klivy Role atribuída ao `account_user`** → permissão consultada
4. Time com `beclinic_role: 'dono'` → bypass
5. Permissão do Time (legado, mantido por retrocompat)
6. Sem time → `false`

O endpoint `GET /api/v1/accounts/:id/beclinic_permissions` retorna o hash já
consolidado, então o frontend (`usePermissions`) é agnóstico à fonte.

---

## 2. Plugin novo: `plugins/custom_roles/`

### Backend Rails

| Arquivo | O que faz |
|---|---|
| `lib/custom_roles/engine.rb` | Rails Engine. Registra `db/migrate` do plugin via `initializer :append_custom_roles_migrations`. `to_prepare` injeta `Account has_many :klivy_roles` e `AccountUser belongs_to :klivy_role`. |
| `app/models/klivy_role.rb` | Model `KlivyRole`. Campos: `account_id`, `name`, `description`, `preset_key`, `permissions` (jsonb). Métodos `can?`, `module_enabled?`, `scope_for`. |
| `app/controllers/api/v1/accounts/klivy_roles_controller.rb` | CRUD + `POST /:id/assign` (atribui role a um user). Renderiza JSON inline (sem jbuilder). Autorização: só `administrator`. |
| `db/migrate/20260425220001_create_klivy_roles.rb` | Cria tabela `klivy_roles` com índice único `(account_id, name)`. |
| `db/migrate/20260425220002_add_klivy_role_id_to_account_users.rb` | Adiciona FK `klivy_role_id` em `account_users`. |

### Frontend (Vue 3 + Vite, Tailwind inline)

#### Compartilhado

| Arquivo | O que faz |
|---|---|
| `frontend/shared/modules.js` | **Catálogo central dos 12 módulos** e suas sub-permissões. Schema suporta `permissions[]` (flat) ou `groups[]` (agrupado, com sub-permissões CRUD por área). Helpers: `emptyPermissionsHash`, `normalizePermissions`, `countActivePermissions`, `countActiveInModule`, `countActiveInGroup`, `flattenPermissions`, `groupPermissions`, `moduleHasGroups`, `isModuleDisabled`. **Fonte de verdade** — toda UI de permissões consulta isso. |
| `frontend/shared/presets.js` | 4 presets prontos (Recepcionista, Especialista, Gerente, SDR/Comercial). Cada preset é um hash de permissões pré-configurado. **Gerente** atualizado em 2026-04-26 com as ~52 chaves novas do módulo `settings` (acesso CRUD total). |

#### API e composables

| Arquivo | O que faz |
|---|---|
| `frontend/api/klivyRolesApi.js` | HTTP client (axios) — `list`, `show`, `create`, `update`, `delete`, `assignToUser`. |
| `frontend/composables/useRolesList.js` | Estado da lista de roles (load, remove). |
| `frontend/composables/useRoleEditor.js` | Estado do editor (name, description, presetKey, permissions, save, applyPreset, togglePermission, setModuleEnabled, **setGroupEnabled** desde 2026-04-26). |
| `frontend/composables/useSilentErrors.js` | `useSilentErrors()` retorna `notifyError(msg, error)` que **silencia 401 e 403** e mostra `useAlert(msg)` só pra erros reais. |

#### Componentes reutilizáveis

| Arquivo | O que faz |
|---|---|
| `frontend/components/PermissionDenied.vue` | Componente "cadeado" reusável. Props: `title`, `message`, `compact`. Tailwind inline com tokens do projeto. |

#### Telas: lista de funções

| Arquivo | O que faz |
|---|---|
| `frontend/features/roles-list/RolesListIndex.vue` | Página em `/settings/custom-roles/list`. Usa `SettingsLayout` + `BaseSettingsHeader` (mesmo padrão de Settings → Agentes). Botão "Nova função", busca, lista de cards, ações editar/excluir (com confirmação 2-clicks). `onMounted(load); onActivated(load)` pra recarregar quando voltar do editor. |

#### Telas: editor de função

| Arquivo | O que faz |
|---|---|
| `frontend/features/role-editor/RoleEditorIndex.vue` | Página em `/settings/custom-roles/new` e `/:roleId/edit`. Usa `SettingsLayout`. Junta os componentes abaixo. |
| `frontend/features/role-editor/components/RoleEditorHeader.vue` | Header com botão "Funções" (voltar), título, contador "X permissões ativas", botão "Salvar função". |
| `frontend/features/role-editor/components/RoleIdentityForm.vue` | Inputs nome (max 80) e descrição (max 240) usando `Input` do projeto. |
| `frontend/features/role-editor/components/ModeTabs.vue` | Tabs "Perfis Prontos" / "Personalizado". |
| `frontend/features/role-editor/components/PresetPicker.vue` | Grid 2x2 dos 4 presets, cada um é um card clicável colorido. |
| `frontend/features/role-editor/components/ModuleSection.vue` | Acordeão de cada módulo: header com nome+contador, "Marcar todos / Desmarcar todos", chevron expand. Quando 0/N → badge "Oculto no menu" e visual pontilhado. **(2026-04-26)** Detecta esquema `groups` e delega pra `PermissionGroup.vue`. |
| `frontend/features/role-editor/components/PermissionGroup.vue` | **(novo, 2026-04-26)** Subseção agrupada dentro de um módulo. Header com nome+contador `(N/M)` + "Marcar todos / Desmarcar todos" próprio + colapsa lista. Indentação `pl-6` para diferenciar do nível módulo. |
| `frontend/features/role-editor/components/PermissionToggle.vue` | Linha individual: label + `Switch` do projeto. |

#### Telas: atribuir função a um usuário

| Arquivo | O que faz |
|---|---|
| `frontend/features/role-assignment/AssignRoleButton.vue` | Botão escudo (ícone `i-lucide-shield-plus`) + `woot-modal` embutido. Aparece na linha de cada agente. |
| `frontend/features/role-assignment/AssignRoleModal.vue` | Conteúdo do modal. Usa `woot-modal-header` padrão do projeto. Lista de roles com radio circle desenhado em CSS (sem `<input type="radio">` pra evitar bordas pretas do navegador). |
| `frontend/features/role-assignment/RoleOption.vue` | Linha de uma role no modal — botão clicável com radio + nome + descrição + pill de "X permissões". Selected: `border-n-brand bg-n-brand/5`. |

#### Roteamento

| Arquivo | O que faz |
|---|---|
| `frontend/routes/routes.js` | 3 rotas: `klivy_roles_list`, `klivy_roles_new`, `klivy_roles_edit`. Todas em `/settings/custom-roles/*` com `meta.permissions: ['administrator']`. Importado em [settings.routes.js](../../../app/javascript/dashboard/routes/dashboard/settings/settings.routes.js). |

---

## 3. Mudanças em arquivos do **core** (fora de `plugins/`)

### `config/routes.rb`
- **Adicionado** dentro de `namespace :api → :v1 → resources :accounts → scope :accounts`:
  ```ruby
  resources :klivy_roles, only: [:index, :create, :show, :update, :destroy] do
    member do
      post :assign
    end
  end
  ```
- Motivo: rotas Rails do plugin precisam estar registradas no roteador central (exceção automática conforme regra de plugins).

### `app/javascript/dashboard/composables/usePermissions.js`
- **Adicionado** método `moduleEnabled(moduleName)`:
  - Retorna `true` para admin / dono.
  - Caso contrário, varre `state.permissions[moduleName]` e retorna `true` se houver pelo menos uma sub-permissão `=== true` (ignorando a chave `scope`).
  - Se o módulo não existe no hash, retorna `true` (fail-open pra não esconder funcionalidade não mapeada).
- **Exportado** no objeto retornado pelo composable.
- Motivo: o sidebar precisa saber se um módulo inteiro está bloqueado pra removê-lo do menu.

### `app/javascript/dashboard/components-next/sidebar/provider.js` (2026-04-26)
- **Adicionado** helper `isChildAllowed(child)` no contexto compartilhado do
  sidebar. Combina o `isAllowed(child.to)` (Chatwoot RBAC nativo) com um novo
  flag `child.bypassPolicy`. Se `bypassPolicy === true`, ignora o `meta.permissions`
  da rota.
- **Motivo**: as rotas de Settings (Inboxes, Labels, Automations, Integrations,
  Audit Logs, Custom Roles, Billing etc.) têm `meta.permissions: ['administrator']`
  no core Chatwoot. Sem esse override, o sidebar filtrava 100% delas para
  qualquer usuário com role `agent` (que é o que usuários com Klivy Custom
  Role têm), independentemente de o catálogo Klivy `settings.*` estar marcado.
  Isso é o que fazia só "Macros" e "Respostas Prontas" aparecerem (essas
  duas rotas usam `[...ROLES, ...CONVERSATION_PERMISSIONS]` e portanto
  passam pra agentes).

### `app/javascript/dashboard/components-next/sidebar/SidebarGroup.vue`, `SidebarSubGroup.vue`, `SidebarCollapsedPopover.vue` (2026-04-26)
- **Trocado** `isAllowed(child.to)` por `isChildAllowed(child)` em todos os
  filtros e templates que decidem se um sub-item do menu aparece. Sem isso,
  o `bypassPolicy: true` setado em `Sidebar.vue` não teria efeito.

### `app/javascript/dashboard/helper/routeHelpers.js` (2026-04-26)
- **Adicionado** mapa `KLIVY_EXACT_ROUTE_RULES` + `KLIVY_PREFIX_ROUTE_RULES`
  + helpers `klivyRuleFor(routeName)` e `routeIsAccessibleByKlivy(route, klivyPermissions)`.
- **Modificado** `validateActiveAccountRoutes(to, user, klivyPermissions)`: depois
  da checagem nativa do Chatwoot (`routeIsAccessibleFor`), se ela falhar, faz
  fallback pelo Klivy. Se o catálogo Klivy permite a rota, libera; caso contrário
  redireciona como antes.
- **Modificado** `validateLoggedInRoutes(to, user, klivyPermissions)` pra
  encaminhar o terceiro argumento.
- **Por que**: o sidebar já mostrava os itens (via `bypassPolicy`), mas clicar
  redirecionava direto pro dashboard porque o **router guard** (`router.beforeEach`)
  ainda checava só o `meta.permissions` da rota contra o role nativo do Chatwoot.
  Esse fix faz o guard respeitar o catálogo Klivy quando a rota é mapeada.
- Mapeamento cobre rotas exatas (`agent_list`, `labels_list`, `automation_list`,
  `auditlogs_list`, `agenda_dashboard_index`, `agenda_settings_index`, etc.) e
  prefixos para grupos (`settings_teams`, `settings_inbox`, `settings_applications`,
  `klivy_roles`, `agent_assignment_policy`, etc.).

### `app/javascript/dashboard/routes/index.js` (2026-04-26)
- **Modificado** `validateAuthenticateRoutePermission` pra ler
  `store.getters['beclinicPermissions/getPermissions']` e passar como
  3º argumento de `validateLoggedInRoutes`. Sem isso, o helper recebia
  `undefined` e o fallback Klivy nunca disparava.

### `app/javascript/dashboard/components-next/sidebar/SidebarGroupLeaf.vue` (2026-04-26)
- **Adicionada** prop `bypassPolicy: Boolean` e computed `effectivePermissions`
  que retorna `[]` quando `bypassPolicy === true` — caso contrário usa
  `resolvePermissions(to)` normalmente.
- O `<Policy>` interno do leaf agora recebe `:permissions="effectivePermissions"`,
  então o `checkPermissions([])` resolve `true` (sem requisito) e o item
  renderiza.
- **Por que precisou**: o `SidebarGroupLeaf` tem um **segundo** `<Policy>`
  interno (independente do filtro do parent). Sem essa correção, o sub-item
  era liberado pelo `isChildAllowed` no parent mas o leaf bloqueava de novo
  pela política nativa — resultado: nada aparecia. Esse era o bug que fazia
  só Macros e Respostas Prontas (rotas com `[...ROLES]`) passarem mesmo com
  Klivy permissions ligadas.

### `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
- **Adicionado** mapa local `SIDEBAR_NAME_TO_MODULE` que mapeia nomes de itens do menu (`Inbox`, `Conversation`, `Captain`, `Agenda`, `Patients`, `Financial`, `Contacts`, `Companies`, `Reports`, `Campaigns`, `Portals`, `Settings`, `Ajuda`) aos `module_key` do catálogo.
- **Adicionado** `.filter()` no `menuItems` computed final: itens cujo módulo não está habilitado são removidos.
- **Item "Settings Custom Roles"** apontado para `klivy_roles_list` (era `custom_roles_list` da UI antiga) e `activeOn: ['klivy_roles_list', 'klivy_roles_new', 'klivy_roles_edit']`.
- **(2026-04-26)** Adicionado mapa `CHILD_GATES` com **dois modos** e helper `gateChildren`:
  - **Modo `filter`** (Agenda) — sub-item some se a permissão Klivy não passa.
    - `Agenda → Calendar` exige `agenda.view`
    - `Agenda → Settings` exige `agenda.view_settings`
    - `Agenda → Custom Attributes` exige `agenda.manage_custom_attributes`
  - **Modo `override`** (Settings) — sub-item ganha `bypassPolicy: true` quando a
    permissão Klivy passa, fazendo com que apareça mesmo quando o `meta.permissions`
    da rota seria `['administrator']`. Sem esse modo, todos os sub-itens de
    Settings (Inboxes, Labels, Integrations, Audit Logs, Custom Roles, Billing,
    etc.) ficariam ocultos para usuários com role nativo `agent`.
    - `Settings Agents`/`Teams`/`Custom Attributes`/`Sla`/`Agent Assignment` → `settings.manage_users`
    - `Settings Inboxes` → `settings.manage_inboxes`
    - `Settings Labels` → `settings.manage_labels`
    - `Settings Automation` / `Conversation Workflow` → `settings.manage_automation`
    - `Settings Macros` → `settings.manage_macros`
    - `Settings Canned Responses` → `settings.manage_canned`
    - `Settings Integrations` / `Settings Agent Bots` → `settings.manage_integrations`
    - `Settings Audit Logs` → `settings.view_audit`
    - `Settings Custom Roles` → `settings.manage_roles`
    - `Settings Account Settings` / `Settings Security` / `Settings Billing` → `settings.manage_billing`
- Motivo: ponto único de filtragem do menu por permissão, sem espalhar `v-if` por 12 lugares.

### `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js`
- **Trocado** `import customRoles from './customRoles/customRole.routes';` por `import customRoles from '@plugins/custom_roles/frontend/routes/routes';`
- **Removido** `import beclinicRoles from '@plugins/beclinic_core/frontend/settings/BeClinicRoles/beclinicRoles.routes.js';` e o `...beclinicRoles.routes` correspondente.
- Motivo: rota `/settings/custom-roles` agora aponta pra UI nova; rota duplicada `/settings/roles` (BeClinicRoles) desativada.

### `app/policies/inbox_policy.rb` (2026-04-26)
- **Modificado** todas as ações `create?`/`update?`/`destroy?`/`set_agent_bot?`/`avatar?`/`sync_templates?`/`campaigns?`/`health?` pra aceitar:
  `@account_user.administrator? || beclinic_can?(:settings, :inboxes_<action>)`.
- **Modificado** `Scope#resolve` pra retornar `account.inboxes` (todas) quando o usuário tem `settings.inboxes_view` Klivy. Sem isso, uma caixa criada por um custom-role sumia da lista (porque `user.assigned_inboxes` filtra por `InboxMember` pra não-admins) e o usuário não conseguia criar outra com o mesmo número (erro "phone number já está em uso").
- **Por que**: o frontend (sidebar + router + página + botão) já libera o acesso,
  mas `POST /api/v1/accounts/:id/inboxes` chama `authorize(Inbox)` (Pundit), e o
  `InboxPolicy#create?` antigo era estritamente `@account_user.administrator?` —
  então o backend devolvia 401 Unauthorized mesmo com a permissão Klivy ligada.
- O `beclinic_can?` (já presente em `ApplicationPolicy` como private helper
  delegando ao `BeclinicPermissible#beclinic_can?`) cobre o resto: super admin,
  admin nativo da conta, KlivyRole, fallback Time. Admins continuam passando pelo
  primeiro termo do OR; Klivy custom roles pelo segundo.
- **Padrão a replicar nas outras policies** (Macro, Label, Automation,
  CannedResponse, AgentBot, Sla, Workflow, etc.) quando estendermos o gating CRUD
  pra essas áreas.

### `app/policies/conversation_policy.rb` (2026-04-26 — Atualização 4)
- **Adicionados** métodos `reply?`, `assign?`, `transfer_inbox?`, `delete_message?`, `send_broadcast?`. Todos seguem o mesmo padrão `administrator? || beclinic_can?(:chat, :<action>)`. `agent_bot?` também passa em `reply?` e `assign?` (mantém comportamento original Chatwoot pra bots).
- **Por que**: o Chatwoot original não tinha policy methods pra essas ações — os controllers de `assign`, `message destroy`, `conversation create` rodavam livres ou com checks fraco. Adicionar os métodos é a base pra o Pundit `authorize` no controller funcionar.

### `app/controllers/api/v1/accounts/conversations/assignments_controller.rb` (2026-04-26)
- **Adicionado** `authorize @conversation, :assign?` no início do `create`. Bloqueia o backend se um agente sem `chat.assign_conversation` tentar atribuir agente/time via API direto.

### `app/controllers/api/v1/accounts/conversations/messages_controller.rb` (2026-04-26)
- **Adicionado** `authorize @conversation, :reply? unless api_token_request?` no `create` (ressalva pra api_access_token usado pelo BEA bot).
- **Adicionado** `authorize @conversation, :delete_message?` no `destroy`.

### `app/controllers/api/v1/accounts/conversations_controller.rb` (2026-04-26)
- **Adicionado** helper `allowed_to_create_conversation?` chamado no `create`. Permite criar nova conversa via composer apenas se o usuário é admin ou tem `chat.send_broadcast` ou `chat.reply` Klivy.

### `app/javascript/dashboard/components/widgets/conversation/MessagesView.vue` (2026-04-26)
- **Adicionado** `import { usePermissions }` + computed `canReply = can('chat', 'reply')`.
- **Trocado** o `<ReplyBox>` por bloco condicional: aparece se `canReply`, senão renderiza um banner com cadeado "Você não tem permissão para responder conversas." Layout responsivo Tailwind inline.

### `app/javascript/dashboard/routes/dashboard/conversation/ConversationAction.vue` (2026-04-26)
- **Adicionado** `import { usePermissions }` + computeds `canAssignConversation` e `canTransferInbox`.
- **`v-if="canAssignConversation"`** envolvendo as duas seções "Agente atribuído" e "Time atribuído" (dropdowns + self-assign). Usuário sem `chat.assign_conversation` perde os controles na sidebar direita da conversa.

### `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` (2026-04-26 — Atualização 4)
- **Gateado** o componente `<ComposeConversation>` (botão de pena ao lado da busca, abre o composer / nova conversa) por `can('chat', 'send_broadcast') || can('chat', 'reply')`. Sem nenhuma das duas, o botão somem.

### `plugins/custom_roles/frontend/shared/modules.js` (2026-04-25 — Atualização 5)
- **Refatorado** o módulo `chat` de `permissions[]` plano para `groups[]`, ficando organizado como **Conversas > Grupo > Permissão** no editor de funções:
  - Grupo `actions` (mantém o que já existia): `view_all`, `view_unassigned`, `view_mentions`, `reply`, `assign_conversation`, `transfer_inbox`, `delete_message`, `send_broadcast`.
  - Grupo `panel` (novo): `view_conversation_actions`, `use_macros`, `view_conversation_info`, `view_contact_attributes`, `view_contact_notes`, `view_previous_conversations`, `view_participants`. Cada permissão controla a visibilidade de uma das seções arrastáveis do painel direito da conversa.
  - Grupo `contact_header` (novo): `view_patient_record` (botão estetoscópio), `edit_contact` (botão lápis), `merge_contact` (botão de mesclar), `manage_waiting_list` (botão relógio) e `view_contact_profile` (link `i-lucide-external-link` ao lado do nome do contato + acesso direto à rota `/contacts/:id`).
- **Por que `chat` virou agrupado**: o catálogo cresceu de 8 → 20 sub-permissões. Sem grupos, o editor virava uma lista achatada confusa. Os grupos espelham a hierarquia visual do produto (ações da conversa vs painel direito vs ações sobre o contato).

### `plugins/custom_roles/frontend/shared/presets.js` (2026-04-25 — Atualização 5)
- **Recepcionista**: ganha as 7 sub-permissões de `panel` (todas `true`) + `edit_contact: true`, `manage_waiting_list: true`, e fica **sem** `view_patient_record`, `merge_contact` e `view_contact_profile`. Default conservador: vê todas as seções no painel da conversa, edita dados básicos do contato e gerencia lista de espera, mas não abre prontuário, mescla nem entra na página completa do contato.
- **Especialista**: ganha `panel` cheio + `view_patient_record: true` + `view_contact_profile: true` (precisa abrir o prontuário do paciente). Mantém `merge_contact: false`.
- **Gerente**: ganha tudo `true` (continua sendo o "admin custom").
- **SDR**: ganha `panel` cheio + `view_contact_profile: true` (precisa entrar na página do contato pra qualificar leads). Sem `view_patient_record`, sem `merge_contact`.

### `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue` (2026-04-25)
- **Adicionado** `import { usePermissions }` + `const { can } = usePermissions()`.
- **Cada `<div v-if="element.name === '<x>'">`** dentro do `<Draggable>` agora tem cláusula adicional `&& can('chat', '<perm>')`:
  - `conversation_actions` → `view_conversation_actions`
  - `conversation_participants` → `view_participants`
  - `conversation_info` → `view_conversation_info`
  - `contact_attributes` → `view_contact_attributes`
  - `previous_conversation` → `view_previous_conversations`
  - `macros` → `use_macros` (mantém também o `<woot-feature-toggle>` original)
  - `contact_notes` → `view_contact_notes`
- **Por que**: o `conversation_sidebar_items_order` (UI Settings) é compartilhado entre todos os usuários, então não dá pra remover items do array — alguns usuários veriam outros sumindo. A solução é manter a ordem global e gatear no template; a seção desativada some pro usuário que não tem permissão sem afetar quem tem.

### `app/javascript/dashboard/routes/dashboard/conversation/contact/ContactInfo.vue` (2026-04-25)
- **Adicionado** `import { usePermissions }` no `setup()` retornando `can`.
- **Computeds**: `canViewContactProfile`, `canViewPatientRecord`, `canEditContact`, `canMergeContact`, `canManageWaitingList`.
- **Template**:
  - `<a :href="contactProfileLink">` (a "caixinha com setinha" `i-lucide-external-link` ao lado do nome do contato) recebe `v-if="canViewContactProfile"`.
  - Os 4 `<NextButton>` da fileira de ações (estetoscópio, lápis, mesclar, lista de espera) recebem `v-if="canViewPatientRecord/canEditContact/canMergeContact/canManageWaitingList"` respectivamente.
- **Por que**: a fileira de ações antes só verificava `isAdmin` no botão de excluir. Com Custom Roles, cada ícone precisa de sua própria gate.

### `app/javascript/dashboard/components/ChatList.vue` (2026-04-25 — Atualização 5 fix)
- **Bug original**: as abas "Minhas / Não atribuídas / Todos" no topo da lista de conversas usavam `filterItemsByPermission(ASSIGNEE_TYPE_TAB_PERMISSIONS, userPermissions)`. O filtro só verifica os roles nativos do Chatwoot (`agent`, `administrator`) e ignora completamente o Klivy. Por isso, mesmo com `chat.view_unassigned = false`, a aba "Não atribuídas" continuava aparecendo porque o usuário tem role `agent`.
- **Adicionado** `import { usePermissions }` + `const { can } = usePermissions()` no setup.
- **Mapa local** `KLIVY_TAB_PERMISSIONS = { unassigned: 'view_unassigned', all: 'view_all' }`.
- **Encadeado** um `.filter()` extra após `filterItemsByPermission(...)`: pra cada tab que tem mapeamento Klivy, exige `can('chat', <perm>)`. A tab `me` ("Minhas") não tem mapeamento e passa direto.
- **Watcher** sobre `assigneeTabItems`: se o usuário estava ativo numa tab que sumiu (perdeu permissão em runtime), troca pra primeira tab visível. Sem isso, ele ficaria com `activeAssigneeTab = 'unassigned'` e a query de conversas continuaria carregando não-atribuídas mesmo com a tab oculta.

### Módulo `captain` (BEA) — gating sub-link a sub-link (2026-04-25 — Atualização 5 fix 4)
- **Renomeado** o label do módulo de "Bia (IA)" para "BEA (IA)" em [modules.js](plugins/custom_roles/frontend/shared/modules.js). Também os labels das permissões `view` e `manage_settings`.
- **Adicionadas** duas sub-permissões novas no catálogo: `manage_inboxes` (Gerenciar caixas de entrada) e `manage_tools` (Gerenciar ferramentas), pra cobrir os 2 sub-links da BEA que não tinham permissão correspondente.
- **Sidebar**: o array `children` do item "Captain" em `Sidebar.vue` foi convertido pra spreads condicionais — cada filho só entra se `can('captain', '<perm>')`. Quando todas as sub-permissões estão off, o item BEA fica visível mas sem filhos (o item pai some via regra geral "se um módulo tem 0 permissões ativas, esconde tudo" caso `view` também esteja off).
- **Router guards**: `KLIVY_REQUIRED_ROUTE_RULES` em `routeHelpers.js` ganhou 10 entradas — uma pra cada nome de rota da BEA. Sem a permissão correspondente, o `validateActiveAccountRoutes` redireciona pra `accounts/:accountId/forbidden` (Page403, com cadeado e mensagem) em vez do dashboard.
- **Mudança no comportamento de deny**: antes, faltar permissão Klivy redirecionava pro `defaultRedirectPage` (dashboard). Agora redireciona pra `/forbidden` em rotas listadas no `KLIVY_REQUIRED_ROUTE_RULES`. Mais explícito e dá feedback ao usuário (o cadeado).

### Remoção de `chat.transfer_inbox` (2026-04-25 — Atualização 5 fix 3)
- **Bug**: a permissão `transfer_inbox` estava no catálogo desde o desenho original (vinha do conceito de "Times" do Chatwoot), mas **não há nenhum botão / dropdown / endpoint** no codebase atual que execute "transferir conversa entre caixas de entrada". Era uma permissão órfã: o usuário ligava o switch e nada acontecia.
- **Removido**: a chave `transfer_inbox` saiu de:
  - `plugins/custom_roles/frontend/shared/modules.js` (grupo `chat.actions`)
  - `plugins/custom_roles/frontend/shared/presets.js` (Recepcionista e Gerente)
  - `app/javascript/dashboard/routes/dashboard/conversation/ConversationAction.vue` (computed `canTransferInbox`)
  - `app/policies/conversation_policy.rb` (método `transfer_inbox?`)
- **Quando reintroduzir**: caso surja a feature "transferir conversa entre inboxes" (mudar `conversation.inbox_id`), recriar a permissão e ligá-la ao botão correspondente.

### Mapeamento atual completo do módulo `chat`
Cada switch agora tem ponto de aplicação real na UI/backend:

**Grupo `actions` (7 permissões):**
| Permissão | Onde aparece |
|-----------|--------------|
| `view_all` | Aba "Todos" no `ChatList`, link "Todas as conversas" no Sidebar |
| `view_unassigned` | Aba "Não atribuídas" no `ChatList`, "Não atendidas" no Sidebar, guard de rota `/unattended/conversations` |
| `view_mentions` | Link "Menções" no Sidebar, guard de rota `/mentions/conversations` |
| `reply` | `<ReplyBox>` na conversa, botão "Resolver" e dropdown de status no header, status/priority/etiqueta no context menu da conversa e painel direito, bulk actions de status/etiqueta |
| `assign_conversation` | Dropdowns Agente / Time no painel direito, "Atribuir Agente" / "Atribuir time" no context menu, bulk actions de agente/time, autorização Pundit no `assignments_controller#create` |
| `delete_message` | Item "Excluir" no context menu da **mensagem** (botão direito sobre o balão), autorização Pundit no `messages_controller#destroy`. **Não confundir** com excluir conversa inteira (ainda gateada por `isAdmin` no card da lista). |
| `send_broadcast` | Botão "compose" (lápis) ao lado da busca no Sidebar, item "Campanhas" no Sidebar, autorização do `conversations_controller#create` |

**Grupo `panel` (7 permissões):** cada chave esconde uma seção no painel direito da conversa via `<Draggable>` em `ContactPanel.vue`. Seção "Ações da conversa" também aparece se `assign_conversation` OR `reply` estiver ativo.

**Grupo `contact_header` (6 permissões):** cada chave esconde um botão na fileira de ações da `ContactInfo.vue`. `view_contact_profile` adicionalmente bloqueia o acesso à rota `/contacts/:id` com cadeado. `delete_contact` controla o ícone de lixeira vermelha que era gateado por `isAdmin` (frontend) e agora também via `ContactPolicy#destroy?` (backend).

### `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue` (2026-04-25 — Atualização 5 fix 2)
- **Bug**: a seção "Ações da conversa" estava gateada **apenas** por `chat.view_conversation_actions`. Se o usuário tinha `chat.assign_conversation=true` mas `view_conversation_actions=false`, a seção sumia inteira, levando junto o dropdown de atribuir agente.
- **Fix**: a regra de visibilidade do `<div>` raiz da seção virou `view_conversation_actions OR assign_conversation OR reply`. A seção aparece se qualquer permissão filha estiver ativa. Dentro dela, cada dropdown continua gateado pela sua sub-permissão (Assignee/Team → `assign_conversation`; Priority/Labels → `reply`).
- **Semântica final**:
  - `view_conversation_actions=true` (sozinho) → seção visível, mas vazia (só o header).
  - `assign_conversation=true` → seção visível, dropdowns de agente e time visíveis.
  - `reply=true` → seção visível, Prioridade e Etiquetas visíveis.

### `app/javascript/dashboard/components/widgets/conversation/contextMenu/Index.vue` (2026-04-25 — Atualização 5 fix)
- **Bug original**: o context menu (botão direito sobre uma conversa na lista) mostrava todas as opções — Marcar resolvida, Deixar pendente, Adiar, Prioridade, Atribuir etiqueta, Atribuir Agente, Atribuir time — independente de permissão.
- **Adicionado** `import { usePermissions }` no setup, expondo `can`.
- **Computeds**: `canChangeStatus`, `canAssignPriority`, `canAssignLabel` (todos `can('chat', 'reply')`), `canAssignAgent`, `canAssignTeam` (`can('chat', 'assign_conversation')`).
- **Template**: cada bloco/item ganhou seu `v-if` correspondente. Mark as read/unread, Open in new tab e Copy link permanecem sem gate (não mutam dado da conversa). Delete continua gateado por `isAdmin` (já existia).

### `app/javascript/dashboard/components/widgets/conversation/conversationBulkActions/Index.vue` (2026-04-25 — Atualização 5 fix)
- **Bug original**: ao selecionar múltiplas conversas, a barra de ações exibia 4 botões (etiquetas, status, agente, time) sem checagem de permissão.
- **Adicionado** `setup() { return { can } }` + computeds `canBulkAssignLabel`, `canBulkChangeStatus` (`chat.reply`), `canBulkAssignAgent`, `canBulkAssignTeam` (`chat.assign_conversation`).
- **Template**: `v-if` em cada `<NextButton>` da `bulk-action__actions`.

### `app/javascript/dashboard/components/buttons/ResolveAction.vue` (2026-04-25 — Atualização 5 fix)
- **Bug original**: o botão "Resolver" (e dropdown com Snooze / Marcar como pendente) no topo direito da conversa aberta ficava sempre visível.
- **Adicionado** `import { usePermissions }` + `const canChangeStatus = computed(() => can('chat', 'reply'))`.
- **Template**: `v-if="canChangeStatus"` no `<div class="resolve-actions">` raiz, ocultando o botão inteiro (incluindo arrow-down e dropdown).

### `app/javascript/dashboard/routes/dashboard/conversation/ConversationAction.vue` (2026-04-25 — Atualização 5 fix)
- **Bug residual**: dentro do acordeão "Ações da conversa" (sidebar direita), Prioridade e Etiquetas continuavam editáveis para qualquer usuário com `view_conversation_actions=true`.
- **Adicionado** computed `canChangeStatus = can('chat', 'reply')`.
- **Template**: `v-if="canChangeStatus"` na seção Prioridade e na seção Conversation Labels.

### `app/javascript/dashboard/helper/routeHelpers.js` (2026-04-25 — Atualização 5 fix)
- **Bug original**: as rotas `conversation_mentions` e `conversation_unattended` declaram `meta.permissions: CONVERSATION_PERMISSIONS` (que inclui `agent`). O guard global `validateActiveAccountRoutes` só **adiciona** acesso via Klivy quando o Chatwoot nega — nunca **subtrai** acesso quando o Chatwoot libera. Resultado: usuário sem `chat.view_mentions` conseguia colar `/mentions/conversations` na URL e entrar normalmente.
- **Adicionado** mapa `KLIVY_REQUIRED_ROUTE_RULES`: rotas que precisam de uma sub-permissão Klivy específica mesmo quando o Chatwoot libera por role.
  ```js
  conversation_mentions:           ['chat', 'view_mentions'],
  conversation_through_mentions:   ['chat', 'view_mentions'],
  conversation_unattended:         ['chat', 'view_unassigned'],
  conversation_through_unattended: ['chat', 'view_unassigned'],
  ```
- **Bloco de enforcement** dentro de `validateActiveAccountRoutes`, antes do check positivo: se o usuário não é `administrator` nativo e a rota está no mapa, exige a permissão Klivy. Sem ela → `defaultRedirectPage`.
- **Por que admin nativo passa direto**: cliente Chatwoot puro não usa Klivy. Manter compatibilidade.

### `app/javascript/dashboard/routes/dashboard/contacts/pages/ContactManageView.vue` (2026-04-25)
- **Adicionado** `import { usePermissions }` + `import PermissionDenied from '@plugins/custom_roles/frontend/components/PermissionDenied.vue'`.
- **Computed** `canViewContactProfile = can('chat', 'view_contact_profile')`.
- **Template**: bloco `v-if="!canViewContactProfile"` renderiza `<PermissionDenied />` (cadeado) e o `v-else` renderiza o layout completo `<ContactsDetailsLayout>`.
- **Por que**: além de esconder o botão `i-lucide-external-link`, é preciso bloquear acesso direto via URL (`/app/accounts/1/contacts/544`). O navegador navega normalmente porque a rota tem `meta.permissions: ['administrator', 'agent', 'contact_manage']` (que cobre qualquer agente). O cadeado in-page é a defesa final.

#### Cenário de teste — Painel direito + página do contato
> Conta `Acme Inc`, usuário `kodakinhocry@gmail.com` (id=4), KlivyRole `Recepcionista` com `chat.view_contact_profile=false`, `chat.merge_contact=false`, `chat.view_patient_record=false`, `chat.view_conversation_info=false` e o resto `true`.

1. Abrir uma conversa qualquer.
2. **Painel direito** (acordeões): Ver "Ações da conversa", "Macros", "Atributos do contato", "Notas do contato", "Conversas anteriores", "Participantes". A seção "Informação da conversa" deve sumir.
3. **Header do contato** (no topo do painel): Ver o ícone lápis (editar) e relógio (lista de espera). Não ver estetoscópio (prontuário), nem `i-ph-arrows-merge` (mesclar), nem `i-lucide-external-link` (caixinha com seta).
4. **Acesso direto à página do contato**: colar `http://localhost:3000/app/accounts/1/contacts/544` no navegador. Deve aparecer o componente `<PermissionDenied />` com cadeado e mensagem "Você não tem permissão para abrir a página do contato.".
5. Liberar `view_contact_profile=true` no editor da função e salvar — o ícone external-link aparece e a página `/contacts/544` carrega normalmente.

### `app/controllers/api/v1/accounts/inboxes_controller.rb` (2026-04-26)
- **Adicionado** `InboxMember.find_or_create_by!(inbox: @inbox, user: Current.user) unless Current.account_user.administrator?` ao final do `create`.
- **Por que**: se um usuário não-admin (com `settings.inboxes_create` Klivy) cria
  uma caixa, é necessário auto-vincular ele como `InboxMember` pra que
  `assigned_inboxes` retorne a caixa em outras telas (Conversas, Dashboard etc.).
  Admins não precisam disso porque já enxergam todas as inboxes da conta.
- **Cadeia completa de visibilidade**: `inboxes_view` Klivy libera apenas a
  página de listagem das caixas (`InboxPolicy::Scope`). Pra um usuário **ver
  conversas** daquela caixa, `ConversationPolicy#inbox_access?` chama
  `user.inboxes` que filtra por `InboxMember`. Conclusão: `inboxes_view` Klivy
  sozinho não basta — precisa também ser InboxMember. O auto-assign no `create`
  resolve pro fluxo "usuário criou a caixa". Pra cenários onde um admin atribui
  uma caixa pré-existente a um usuário, a UI já tem o passo "Adicionar Agentes"
  no wizard — ele cria o `InboxMember` corretamente.
- **Backfill manual** (caso uma caixa criada antes do hot-reload do Rails
  pegar o auto-assign): `InboxMember.find_or_create_by!(inbox: Inbox.find(<id>), user: User.find(<id>))` via `bundle exec rails runner`.

### `app/javascript/dashboard/routes/dashboard/settings/inbox/Index.vue` (2026-04-26)
- **Adicionado** `import { usePermissions }` e computeds `canCreateInbox`,
  `canEditInbox`, `canDeleteInbox` que combinam `isAdmin` (Chatwoot) com
  `can('settings', 'inboxes_*')` (Klivy).
- **Trocado** `v-if="isAdmin"` por:
  - `v-if="canCreateInbox"` no botão "Configurar nova caixa de entrada" (header).
  - `v-if="canEditInbox"` no ícone de configurações por inbox.
  - `v-if="canDeleteInbox"` no ícone de lixeira por inbox.
- **Por que**: o botão estava amarrado só ao role nativo `administrator`. Mesmo
  com `settings.inboxes_create` ligado na função personalizada, um agente não
  via o botão. Esse é o **padrão de gating em camadas para páginas core**:
  primeira-camada Klivy + fallback nativo `isAdmin` (admins continuam vendo tudo).
  Replicar esse padrão nas próximas páginas (Labels, Macros, Canned, Automation
  etc.) é a forma de levar o controle CRUD pra todo settings.

### `app/javascript/dashboard/routes/dashboard/settings/agents/Index.vue`
- **Adicionado** `import AssignRoleButton from '@plugins/custom_roles/frontend/features/role-assignment/AssignRoleButton.vue';`
- **Adicionado** `<AssignRoleButton :user="agent" @assigned="store.dispatch('agents/get')" />` antes dos botões de Editar/Excluir em cada linha.
- Motivo: dar entrada visível para atribuir funções aos agentes.

---

## 4. Mudanças em plugins existentes

### `plugins/beclinic_core/app/models/concerns/beclinic_permissible.rb`
- **Adicionado** método `klivy_role_for(account)` — busca a `KlivyRole` atribuída via `account_users.klivy_role_id`.
- **Adicionado** método `beclinic_admin_in?(account)` — checa se é `administrator` Chatwoot.
- **Reescrito** `beclinic_can?` e `beclinic_scope` pra consultar **Klivy Role antes** do Time (ordem definida na seção 1).

### `plugins/beclinic_core/app/controllers/api/v1/accounts/beclinic_permissions_controller.rb`
- **Reescrito** `show` para retornar `permissions` consolidadas via `effective_permissions` (Klivy Role → fallback Time).
- **Adicionado** payload `klivy_role: { id, name, preset_key }` ao response.

### `plugins/agenda/` — gating completo do calendário, configurações e atributos (2026-04-26)

#### Novo composable: `plugins/agenda/frontend/composables/useAgendaPermissions.js`
- **Centraliza** todas as permissões de agenda em um lugar:
  `canCreate`, `canEdit`, `canCancel`, `canDrag`, `canManageBlocks`, `canManageNotifications`.
- Expõe `guard(action, fn)` — executa `fn` se o usuário tem `agenda.<action>`,
  caso contrário dispara `useAlert` em PT-BR ("Você não tem permissão para criar
  eventos.", "…editar eventos.", "…cancelar eventos.", "…reorganizar eventos.").
- Usado pelo `AgendaDashboard.vue` pra envelopar as funções vindas dos
  composables `useAgendaCrud`, `useAgendaDnD` e `useAgendaPopups` antes de
  expor pro template.

#### `plugins/agenda/frontend/routes/AgendaDashboard.vue`
- **Adicionado** `import { useAgendaPermissions } from '../composables/useAgendaPermissions.js';`
- **Wrapping** das ações sensíveis com `guard(...)`:
  - `openEventModal` → exige `create_event`
  - `openEditEvent` → exige `edit_event`
  - `deleteEvent` / `quickDeleteEvent` → exigem `cancel_event`
  - `initDrag` → exige `drag_and_drop`
  - `initResize` → exige `edit_event`
  - `updateEventStatus` (mudança de status na popup) → exige `edit_event`
  - `openWlScheduleForCell` (clique em célula com waiting list) → exige `create_event`
- **`handleCellClick`** retorna cedo com toast "Você não tem permissão para criar eventos." se `!canCreate`.
- **Props passadas pra componentes filhos** (controlam visibilidade de UI):
  - `<AgendaHeader :can-create="canCreate" />`
  - `<AgendaMonthView :can-create="canCreate" />`
  - `<AgendaTimelineView :can-create :can-cancel :can-drag :can-edit />`
  - `<AgendaEventModal :can-cancel="canCancel" />`
  - `<AgendaEventInfoPopup :can-edit="canEdit" />`
- **`v-if="canCreate"`** na FAB mobile.

#### Componentes da agenda atualizados

| Componente | O que foi gated |
|---|---|
| `components/AgendaHeader.vue` | Botão "Novo Evento" desktop só aparece com `canCreate`. |
| `components/AgendaMonthView.vue` | Botão `+` da célula e clique no dia inteiro respeitam `canCreate` (handler retorna cedo se falso). |
| `components/AgendaTimelineView.vue` | Encaminha props `can-cancel/can-drag/can-edit` para cada `<AgendaEventCard>`. |
| `components/AgendaEventCard.vue` | 4 botões de lixeira (`canCancel`), handle de resize (`canEdit`), `mousedown-drag` agora passa por método `onMousedownDrag` que retorna se `!canDrag`. |
| `components/AgendaEventInfoPopup.vue` | Seção "Atualizar Status" e botão "Editar" só aparecem com `canEdit`. Footer fica oculto se nada vai aparecer. |
| `components/AgendaEventModal.vue` | Botão "Excluir" no rodapé só aparece se `canCancel && isEditing`. Layout do footer se ajusta sozinho (`justify-end` quando não há excluir). |

#### `plugins/agenda/frontend/routes/settings/Index.vue` — gating por aba
- **Adicionado** `import { usePermissions }` e `import PermissionDenied`.
- **Computeds** por aba: `canViewSettings`, `canManageSchedules`, `canViewNotifications`, `canManageNotifications`, `canManageOnlineBooking`, `canManageServices`.
- **Tabs** agora são um `computed(() => allTabs.filter(tab => tab.allowed.value))` — abas sem permissão somem.
- `watch(tabs)` recalibra `activeTab` quando a aba ativa some (ex.: admin desliga
  permissão dela em outra sessão).
- Template:
  - `<PermissionDenied />` se `!canViewSettings` (cadeado "Configurações da agenda restritas").
  - `<PermissionDenied />` se tem `view_settings` mas nenhuma `manage_*` ("Sem permissões disponíveis").
  - Caso contrário renderiza o tab bar filtrado e o conteúdo da aba ativa.

| Aba | Permissão exigida |
|---|---|
| Horários | `manage_schedules` |
| Notificações automáticas | `view_notifications` ou `manage_notifications` |
| Agendamento online | `manage_online_booking` |
| Serviços | `manage_services` |

#### `plugins/agenda/frontend/routes/customAttributes/Index.vue`
- **Adicionado** `import PermissionDenied` e `import { usePermissions }`.
- Bloco `setup()` retornando `can`; `computed.canManage` = `can('agenda', 'manage_custom_attributes')`.
- Template envelopado: `<PermissionDenied v-if="!canManage" />` antes do `<template v-else>` que segura todo o CRUD.

### `plugins/custom_roles/frontend/shared/modules.js` (2026-04-26)
- **Atualização 1**: expandido o módulo `agenda` de 8 para 13 sub-permissões
  (`view_settings`, `manage_schedules`, `manage_online_booking`,
  `manage_services`, `manage_custom_attributes` novas;
  `view_notifications`/`manage_notifications` já existiam).
- **Atualização 2**: schema do catálogo passou a suportar dois esquemas
  mutualmente exclusivos por módulo — `permissions: Permission[]` (flat,
  módulos pequenos) e `groups: Group[]` (agrupado, módulos extensos).
  - `agenda` reorganizada nos 4 grupos: Calendário, Configurações da agenda,
    Notificações automáticas, Atributos personalizados (chaves preservadas).
  - `settings` reescrita do zero em **17 grupos** com sub-permissões CRUD por
    área (Conta, Agentes, Times, Caixas de entrada, Etiquetas, Atributos,
    Automação, Robôs, Macros, Respostas prontas, Integrações, Auditoria,
    Funções, SLA, Fluxo, Segurança, Cobrança). Total: ~52 chaves novas.
- **Helpers novos**: `flattenPermissions`, `groupPermissions`, `moduleHasGroups`,
  `countActiveInGroup`.
- **Migração automática**: `LEGACY_KEY_MIGRATIONS` traduz chaves antigas
  (`manage_inboxes`, `manage_users`, etc.) pras novas dentro de
  `normalizePermissions`. Roles salvas no schema antigo carregam
  preservando intenção sem quebrar.

### `plugins/custom_roles/frontend/shared/presets.js` (2026-04-26)
- **Atualização 1**: preset Gerente ganhou as 5 novas permissões da agenda.
- **Atualização 2**: preset Gerente reescrito com as ~52 chaves novas do
  módulo `settings` (acesso total a toda configuração). Recepcionista,
  Especialista e SDR mantidos sem acesso a configurações por padrão.

### `plugins/patients/frontend/routes/patients/Index.vue`
- **Adicionado** `import { usePermissions } from 'dashboard/composables/usePermissions';` e `const { can } = usePermissions();`.
- **Gating** com `v-if`:
  - Botão "Novo Paciente" desktop e FAB mobile → `can('patients', 'create')`
  - Ícone lixeira (arquivar) na linha → `can('patients', 'delete')`
  - Botão "Restaurar paciente" na vista Arquivados → `can('patients', 'delete')`

### `plugins/patients/frontend/routes/patients/Record.vue`
- **Adicionado** imports:
  - `import { useSilentErrors } from '@plugins/custom_roles/frontend/composables/useSilentErrors';`
  - `import PermissionDenied from '@plugins/custom_roles/frontend/components/PermissionDenied.vue';`
  - `const notifyError = useSilentErrors();`
- **Substituído** em 6 catches `useAlert('Erro ao carregar X.')` por `notifyError('Erro ao carregar X.', error)`:
  - `fetchTreatmentPlans`
  - `fetchSessionLogs`
  - fetch financial (transações + estimates)
  - `fetchAppointments`
  - `fetchTimeline`
  - `fetchAuditLogs`
  - (corrigido também `} catch {` para `} catch (error) {` no `fetchTimeline` que faltava o binding)
- **Gating** dos 5 botões do header do prontuário:

  | Botão | Permissão |
  |---|---|
  | Agendar | `agenda.create_event` |
  | Anexar arquivo | `patients.manage_exams` |
  | Gerar documento | `patients.manage_documents` |
  | Cobrar (+ divisor) | `financial.create_transaction` |
  | Iniciar atendimento | `patients.create_clinical_notes` |

- **Enriquecido** o catálogo `allTabs` com `permission` em todas as tabs (antes só `financial` e `audit` tinham). O computed `tabs` filtra automaticamente.
- **Adicionado** computed `currentTabAllowed` — verifica se `activeTab` está em `tabs.value`.
- **Adicionado** no template `<div v-if="!currentTabAllowed"><PermissionDenied /></div>` antes da cadeia de tab panes (primeiro tab pane virou `v-else-if`). Quando alguém entra via URL com `?tab=financial` sem permissão, vê o cadeado em vez do conteúdo bloqueado.

---

### Atualização 6 — Anamnese, Exames, Financeiro do Paciente vs Financeiro Global (2026-04-25)

#### Catálogo: novas keys em `patients`
Em `plugins/custom_roles/frontend/shared/modules.js`, o módulo `patients` ganhou:
- `view_anamnesis` / `manage_anamnesis` — separadas de `*_clinical_notes` (Anamnese é um questionário, Evolução é nota clínica)
- `view_financial` / `manage_financial` — financeiro **do prontuário**, totalmente desacoplado do módulo `financial` global

#### `plugins/patients/frontend/routes/patients/Record.vue`
Novos computeds:
```js
const canEditPatient = computed(() => can('patients', 'edit'));
const canCreateClinicalNotes = computed(() => can('patients', 'create_clinical_notes'));
const canSignClinicalNotes = computed(() => can('patients', 'sign_clinical_notes'));
const canDeleteClinicalNotes = computed(() => can('patients', 'delete_clinical_notes'));
const canManageAnamnesis = computed(() => can('patients', 'manage_anamnesis'));
const canManageExams = computed(() => can('patients', 'manage_exams'));
const canViewPatientFinancial = computed(() => can('patients', 'view_financial'));
const canManagePatientFinancial = computed(() => can('patients', 'manage_financial'));
```

Padrão de bloqueio das abas: banner de cadeado + `:inert="!perm"` + `:class="{ 'opacity-60': !perm }"` no wrapper do form. `inert` desabilita nativamente todos os inputs/textareas/selects/buttons + cliques em divs (incl. toggles WhatsApp/E-mail/LGPD).

| Aba do prontuário | Permissão de visualização | Permissão de edição/save |
|---|---|---|
| Cadastro | `patients.view` | `patients.edit` |
| Anamnese | `patients.view_anamnesis` | `patients.manage_anamnesis` |
| Evolução | `patients.view_clinical_notes` | `patients.create_clinical_notes` (criar/editar rascunho), `patients.sign_clinical_notes` (assinar), `patients.delete_clinical_notes` (excluir) |
| Exames e Imagens | `patients.view_exams` | `patients.manage_exams` |
| Financeiro | `patients.view_financial` (antes era `financial.view_dashboard`) | `patients.manage_financial` (antes era spread em `create_estimate/create_transaction/...`) |

Mensagens específicas no save (early-return + tradução de 401/403):
- "Você não tem permissão para editar cadastro de pacientes"
- "Você não tem permissão para editar anamnese"
- "Você não tem permissão para criar evoluções"
- "Você não tem permissão para assinar evoluções"
- "Você não tem permissão para excluir evoluções"

Botão "Cobrar" no header do prontuário e todos os 6 `v-can="['financial', ...]"` da aba Financeiro foram trocados para `canManagePatientFinancial`.

#### `plugins/patients/frontend/routes/patients/tabs/EvolutionTab.vue`
Recebe perms via props (`canCreate`, `canSign`, `canDelete`, `noCreateMsg`). Form-card com `:inert="!canCreate"`. "Salvar Rascunho" agora `v-if="canCreate"` (antes não tinha gate nenhum — Salvar Rascunho era o bug visível pelo usuário). Edit/Delete na timeline gateados por `canCreate`/`canDelete`.

#### Backend: policies de Anamnesis e financeiro do paciente
- `app/policies/anamnesis_policy.rb` — index/show usam `view_anamnesis`; create/update/destroy usam `manage_anamnesis`. Antes herdavam `view_clinical_notes` / `create_clinical_notes` / `delete_clinical_notes`, o que misturava Anamnese com Evolução.
- `plugins/patients/app/controllers/api/v1/accounts/patients/financial_estimates_controller.rb` e `transactions_controller.rb` — substituídas as chamadas `authorize` (que iam contra `FinancialEstimatePolicy` / `TransactionPolicy` global e bloqueavam quem só tinha `patients.manage_financial`) por `before_action :ensure_view_patient_financial!` / `:ensure_manage_patient_financial!` que checam `Current.user.beclinic_can?(Current.account, :patients, :view_financial)` e `:manage_financial`. Resposta 403 com mensagem específica em PT-BR.
- `plugins/patients/app/controllers/api/v1/accounts/patients/exam_folders_controller.rb` — antes não tinha autorização nenhuma. Adicionados `before_action :ensure_view_exams!` (index) e `:ensure_manage_exams!` (update).

---

### Atualização 7 — Financeiro global gateado fim a fim (2026-04-25)

A primeira screenshot do usuário mostrava o sidebar listando Fluxo de Caixa, A Receber, A Pagar, DRE, Relatórios, Caixa, Configurações mesmo com só `view_dashboard` ligado. Causa raiz: as policies referenciavam `:view_transactions` (key inexistente no catálogo), o sidebar não filtrava children, e as rotas não tinham deny-rule.

#### `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
Em `CHILD_GATES`, adicionado `Financial` em modo `'filter'`:
```js
Financial: {
  mode: 'filter',
  rules: {
    'Financial Dashboard': ['financial', 'view_dashboard'],
    'Cash Flow': ['financial', 'view_cashflow'],
    Receivables: ['financial', 'view_receivables'],
    Payables: ['financial', 'view_payables'],
    DRE: ['financial', 'view_dre'],
    'Financial Reports': ['financial', 'view_reports'],
    'Cash Register': ['financial', 'view_cash_register'],
    'Financial Settings': ['financial', 'manage_settings'],
  },
},
```

Adicionado um `.filter()` final no `menuItems` computed que dropa o grupo pai inteiro se todos os children sumiram (modo `filter`). Isso resolve "se desmarquei todas as sub-perms, o grupo Financeiro continuava aparecendo vazio".

#### `app/javascript/dashboard/helper/routeHelpers.js`
8 rotas adicionadas em `KLIVY_REQUIRED_ROUTE_RULES` (deny — redireciona pra `/forbidden` se faltar a perm):
- `financial_dashboard_index` → `[financial, view_dashboard]`
- `financial_cash_flow` → `[financial, view_cashflow]`
- `financial_receivables` → `[financial, view_receivables]`
- `financial_payables` → `[financial, view_payables]`
- `financial_dre` → `[financial, view_dre]`
- `financial_reports` → `[financial, view_reports]`
- `financial_cash_register` → `[financial, view_cash_register]`
- `financial_settings` → `[financial, manage_settings]`

**Importante:** essas rotas têm `meta: { permissions: [...ROLES] }` no `routes.js` do plugin (qualquer role do Chatwoot passa). Sem a deny-rule explícita, o Klivy nunca bloquearia o acesso direto via URL. As rotas continuam com `[...ROLES]` para compatibilidade — o gate de verdade é o Klivy.

#### Bug das policies referenciando `:view_transactions` (key inexistente)
8 policies estavam quebradas — qualquer não-admin Klivy retornava 401/403 em todo o financeiro. Corrigidas:

| Policy | Mudança |
|---|---|
| `account_transaction_policy.rb` | `index?`/`show?` agora aceitam **qualquer** das 7 view-perms financeiras (constante `FINANCIAL_VIEW_PERMS`); `update?` corrigido pra `edit_transaction` (era `create_transaction`) |
| `transaction_policy.rb` | Mesma lógica; `approve?` agora usa `approve_estimate` (era `view_cashflow`); `cancel?` usa `edit_transaction` |
| `financial_estimate_policy.rb` | Usa `manage_estimates` em create/update/cancel/destroy (antes referenciava `create_estimate`/`edit_estimate`/`delete_estimate` que não existem) |
| `bank_account_policy.rb` | index com qualquer view-perm; CRUD exige `manage_settings` (antes hard-coded `administrator?`) |
| `cash_register_policy.rb` | index usa `view_cash_register`; create/update usa `create_transaction`; destroy usa `delete_transaction` |
| `commission_rule_policy.rb` | index com `view_reports OR manage_settings`; CRUD com `manage_settings` |
| `financial_category_policy.rb` | index com qualquer view-perm; CRUD com `manage_settings` |
| `financial_dashboard_policy.rb` | `show?` usa `view_dashboard` |
| `financial_goal_policy.rb` | `show?` com `view_dashboard`, `update?` com `manage_settings` |
| `recurring_expense_policy.rb` | index com `view_payables OR manage_settings`; CRUD com `manage_settings` |

#### Gating das ações in-page
Cada página recebeu `import { usePermissions }` + computeds e `v-if`:

| Página | Botões gateados | Permissão |
|---|---|---|
| `Receivables.vue` | "Nova Entrada" header, "Receber" linha | `create_transaction` |
| `Receivables.vue` | "Editar" linha | `edit_transaction` |
| `Receivables.vue` | "Gerar PDF", "CSV" | `export_data` |
| `Payables.vue` | "Nova Despesa" header, "Pagar" linha | `create_transaction` |
| `Payables.vue` | "Editar" linha | `edit_transaction` |
| `Payables.vue` | "Gerar PDF", "CSV" | `export_data` |
| `CashFlow.vue` | "Nova Entrada", "Nova Despesa" | `create_transaction` |
| `CashFlow.vue` | "Gerar PDF", "CSV" | `export_data` |
| `DRE.vue` | "Gerar PDF", "CSV" | `export_data` |
| `Reports.vue` | 6 botões de export (Comissões, Despesas, Convênio, Ticket Médio — PDF e CSV) | `export_data` |
| `CashRegister.vue` | "Abrir Caixa" + grupo de ações (Suprimento/Sangria/Fechar) | `create_transaction` |

`FinancialSettings.vue` não precisou de gating interno — todas as ações exigem `manage_settings`, que já é a perm da página inteira (gate de rota). Quem chega na página tem permissão, ponto final.

---

### Atualização 8 — Contatos gateado fim a fim (2026-04-25)

Mesma auditoria sistemática feita no Financeiro, agora no módulo `contacts`. O bug que motivou a auditoria: usuário ligou `contacts.delete` mas o botão de excluir não aparecia — estava preso em `<Policy :permissions="['administrator']">` (Chatwoot nativo) em vez de checar a perm Klivy.

#### `app/policies/contact_policy.rb`
Antes a policy era basicamente toda `def x?; true; end`. Agora bate no catálogo:

| Action | Perm Klivy |
|---|---|
| `index?` / `show?` / `search?` / `filter?` / `contactable_inboxes?` | `contacts.view_all` |
| `active?` | `contacts.view_active OR view_all` |
| `create?` | `contacts.create` |
| `update?` / `avatar?` / `destroy_custom_attributes?` | `contacts.edit` |
| `destroy?` | `contacts.delete OR chat.delete_contact` (mantém compatibilidade com o botão "Excluir contato" do painel da conversa) |
| `import?` / `export?` | `contacts.import_export` |

`beclinic_can?` já bypassa admins nativos e donos automaticamente, então o admin continua passando direto.

#### `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
Adicionado `Contacts` em `CHILD_GATES`:
```js
Contacts: {
  mode: 'filter',
  rules: {
    'All Contacts': ['contacts', 'view_all'],
    Active: ['contacts', 'view_active'],
    Segments: ['contacts', 'manage_segments'],
    'Tagged With': ['contacts', 'manage_tags'],
  },
},
```

Se o usuário desligar todas as 4 perms de visualização, o grupo "Contatos" inteiro some do sidebar (graças ao `.filter()` que dropa pais vazios em modo `filter`).

#### `app/javascript/dashboard/helper/routeHelpers.js`
4 rotas adicionadas em `KLIVY_REQUIRED_ROUTE_RULES`:
- `contacts_dashboard_index` → `[contacts, view_all]`
- `contacts_dashboard_active` → `[contacts, view_active]`
- `contacts_dashboard_segments_index` → `[contacts, manage_segments]`
- `contacts_dashboard_labels_index` → `[contacts, manage_tags]`

#### Gating dos botões nas telas

| Componente | Botão | Perm Klivy | Antes |
|---|---|---|---|
| `ContactsBulkActionBar.vue` | "Excluir contatos" (bulk) | `contacts.delete` | `<Policy administrator>` |
| `ContactsBulkActionBar.vue` | "Atribuir rótulo" (bulk) | `contacts.manage_tags` | sem gate |
| `ContactDeleteSection.vue` | "Excluir contato" (na lista expandida) | `contacts.delete` | `<Policy administrator>` |
| `ContactDetails.vue` | Botão "Atualizar" (form) | `contacts.edit` | sem gate |
| `ContactDetails.vue` | Seção "Excluir contato" inteira (página de detalhes) | `contacts.delete` | `<Policy administrator>` |
| `ContactsCard.vue` | Botão "Atualizar" (formulário inline) | `contacts.edit` | sem gate |
| `ContactsDetailsLayout.vue` | "Bloquear/Desbloquear contato" | `contacts.edit` | sem gate |
| `ContactMoreActions.vue` | Item "Adicionar contato" (menu ⋮) | `contacts.create` | sem gate |
| `ContactMoreActions.vue` | Items "Importar/Exportar" (menu ⋮) | `contacts.import_export` | sem gate |
| `ContactMoreActions.vue` | Botão `⋮` inteiro | só aparece se algum item passa | sempre visível |
| `ContactHeader.vue` | "Salvar segmento" (filtros ativos) | `contacts.manage_segments` | sem gate |
| `ContactHeader.vue` | "Excluir segmento" | `contacts.manage_segments` | sem gate |
| `ContactEmptyState.vue` | "Adicionar primeiro contato" (empty state) | `contacts.create` | sem gate |

Removidos os 3 imports/usos de `Policy from 'dashboard/components/policy.vue'` em `ContactsBulkActionBar.vue`, `ContactDeleteSection.vue` e `ContactDetails.vue`.

Resultado: ligando `contacts.delete` aparece o lixo bulk + o botão "Excluir contato" na página de detalhes; ligando `contacts.create` aparece o "Adicionar contato"; ligando `contacts.import_export` aparece "Importar/Exportar". Sem nenhuma perm marcada, o módulo Contatos some do sidebar. Direct URL access bate em `/forbidden`.

---

### Atualização 9 — Relatórios gateado fim a fim (2026-04-25)

Sub-perms do módulo `reports` (já existiam no catálogo) — `view_overview`, `view_conversation`, `view_agent`, `view_label`, `view_inbox`, `view_team`, `view_csat`, `view_sla`, `view_bot`, `view_agenda` — não estavam ligadas a nenhuma camada (sidebar, route guard ou backend). Resultado: ligar uma perm individual não fazia nada.

#### `app/policies/report_policy.rb`
Antes:
```rb
def view?
  @account_user.administrator?
end
```
Agora:
```rb
REPORT_VIEW_PERMS = %i[view_overview view_conversation view_agent view_label
                       view_inbox view_team view_csat view_sla view_bot
                       view_agenda].freeze

def view?
  return true if @account_user.administrator?
  REPORT_VIEW_PERMS.any? { |perm| beclinic_can?(:reports, perm) }
end
```

A view? é compartilhada por todos os endpoints (`reports_controller.rb`, `live_reports_controller.rb`, `summary_reports_controller.rb` — todos chamam `authorize :report, :view?`). Qualquer perm de view passa o gate API; a aba específica é restringida pelo router/sidebar. O Enterprise extension (`report_manage`) continua funcionando via `super`.

#### `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
Adicionado `Reports` em `CHILD_GATES`:
```js
Reports: {
  mode: 'filter',
  rules: {
    'Report Overview': ['reports', 'view_overview'],
    'Report Conversation': ['reports', 'view_conversation'],
    'Reports Agent': ['reports', 'view_agent'],
    'Reports Label': ['reports', 'view_label'],
    'Reports Inbox': ['reports', 'view_inbox'],
    'Reports Team': ['reports', 'view_team'],
    'Reports CSAT': ['reports', 'view_csat'],
    'Reports SLA': ['reports', 'view_sla'],
    'Reports Bot': ['reports', 'view_bot'],
    'Reports Agenda': ['reports', 'view_agenda'],
  },
},
```

Os 4 sub-itens dinâmicos (Por agente / etiqueta / caixa / time) vinham de `reportRoutes.value` (spread `...reportRoutes.value`); como o `name` de cada item bate com a chave do CHILD_GATES, o filtro pega corretamente.

Quando todas as 10 perms estão off, o grupo "Relatórios" desaparece (graças ao `.filter()` que dropa pais vazios em modo `filter`).

#### `app/javascript/dashboard/helper/routeHelpers.js`
14 rotas em `KLIVY_REQUIRED_ROUTE_RULES`:
- `account_overview_reports` → `[reports, view_overview]`
- `conversation_reports` → `[reports, view_conversation]`
- `agent_reports_index` / `agent_reports_show` → `[reports, view_agent]`
- `label_reports_index` / `label_reports_show` → `[reports, view_label]`
- `inbox_reports_index` / `inbox_reports_show` → `[reports, view_inbox]`
- `team_reports_index` / `team_reports_show` → `[reports, view_team]`
- `csat_reports` → `[reports, view_csat]`
- `sla_reports` → `[reports, view_sla]`
- `bot_reports` → `[reports, view_bot]`
- `agenda_reports` → `[reports, view_agenda]`

Reload em `/reports/labels_overview` sem `view_label` cai em `/forbidden`.

#### Botões dentro das páginas
As páginas de Relatórios são **read-only** (gráficos + KPIs). Não há botões de criar/editar/excluir gateáveis. Exports/downloads também não existem como botões nessas páginas (downloads são só nos relatórios financeiros, que vivem em outro módulo). Por isso esta atualização é só de visibilidade — não há gate "fino" pra adicionar dentro das páginas.

Resultado: o admin/dono continua vendo tudo. Para um Klivy não-admin, ligar `view_csat` faz aparecer só "CSAT" no submenu; ligar todos faz aparecer todos os 10 itens; desligar todos faz o grupo "Relatórios" sumir do menu. Direct URL bate em `/forbidden`.

#### Bug do `bypassPolicy` no modo `filter` (descoberto durante teste)

Inicialmente os Relatórios não apareciam para usuário com a perm Klivy ligada. Causa raiz: o `gateChildren` em modo `filter` apenas dropava children sem perm; mas os children que passavam ainda iam pra `isChildAllowed` em `provider.js` que checa `meta.permissions` do Chatwoot. Como rotas de Reports têm `meta.permissions: ['administrator', 'report_manage']`, qualquer não-admin era bloqueado mesmo passando o gate Klivy.

**Fix:** o `gateChildren` agora também marca `bypassPolicy: true` em filhos liberados pelo Klivy em modo `filter` (antes só fazia isso em `override`). Isso pula a checagem do `meta.permissions` do Chatwoot. Aplicado universalmente — beneficia também Financial, Contacts e qualquer futuro grupo que use modo `filter`.

**Adição complementar:** rotas de Reports também adicionadas em `KLIVY_EXACT_ROUTE_RULES` (allow list) — sem isso, mesmo o sidebar mostrando o link, clicar nele cairia no router guard que checa `meta.permissions = ['administrator', 'report_manage']` e redirecionaria.

Financial e Contacts não precisam dessa adição porque suas rotas têm `meta.permissions = [...ROLES]` (Financial) ou `['administrator', 'agent', 'contact_manage']` (Contacts) — qualquer agent passa o check do Chatwoot, então só o deny rule do Klivy basta. Reports é único em ter `meta` admin-only.

---

### Atualização 10 — Campanhas gateado fim a fim (2026-04-25)

Mesmo padrão de Reports + um bug extra: o grupo Campanhas inteiro estava preso atrás de `can('chat', 'send_broadcast')` no spread condicional do sidebar — ativar `campaigns.view` não fazia nada porque a perm certa nem era checada.

#### Sidebar — spread condicional removido
Antes:
```js
...(can('chat', 'send_broadcast') ? [{ name: 'Campaigns', children: [...] }] : []),
```
O grupo Campanhas só aparecia se o usuário tivesse `chat.send_broadcast` (perm de outro módulo!). Substituído pelo grupo direto, agora gateado por `moduleEnabled('campaigns')` + CHILD_GATES.

Adicionado `Campaigns` em `CHILD_GATES`:
```js
Campaigns: {
  mode: 'filter',
  rules: {
    'Live chat': ['campaigns', 'view'],
    SMS: ['campaigns', 'view'],
    WhatsApp: ['campaigns', 'view'],
  },
},
```

As 3 sub-abas usam a **mesma key** `view` (não `manage_*`), porque o usuário com `view` pode listar campanhas dos 3 canais. Os `manage_*` específicos gateiam só as ações de criar/editar/excluir dentro de cada página.

#### Route guards
- **Allow rules** em `KLIVY_EXACT_ROUTE_RULES` (rotas têm `meta.permissions: ['administrator']`):
  ```
  campaigns_livechat_index, campaigns_sms_index, campaigns_whatsapp_index,
  campaigns_ongoing_index, campaigns_one_off_index → ['campaigns', 'view']
  ```
- **Deny rules** em `KLIVY_REQUIRED_ROUTE_RULES` — mesmas 5 rotas → bloqueia /forbidden se faltar `view`.

#### Backend — `app/policies/campaign_policy.rb`
Antes era admin-only em todas as 5 actions. Agora:
- `index?` / `show?` → `campaigns.view`
- `create?` / `update?` / `destroy?` → checa o `inbox_type` da campanha:
  - `'Website'` → `manage_live_chat`
  - `'Sms'` ou `'Twilio SMS'` → `manage_sms`
  - `'Whatsapp'` → `manage_whatsapp`

Quando o controller passa a classe `Campaign` (sem instância — caso do `create` no Pundit do Chatwoot), aceita se o usuário tem qualquer um dos 3 `manage_*`.

`app/controllers/api/v1/accounts/campaigns_controller.rb` mudado: substituído o `before_action :check_authorization` (que sempre passava `Campaign` classe) por `:check_authorization_for_campaign` que passa `@campaign` quando disponível, permitindo a policy checar o canal específico.

#### Gating das ações in-page

| Componente | Botão | Perm |
|---|---|---|
| `CampaignLayout.vue` | "Nova campanha" header | nova prop `canCreate` |
| `CampaignCard.vue` | Botão lápis (edit, só LiveChat) | nova prop `canEdit` |
| `CampaignCard.vue` | Botão lixo (delete) | nova prop `canDelete` |
| `LiveChatCampaignsPage.vue` | passa `manage_live_chat` em todas as 3 props | — |
| `SMSCampaignsPage.vue` | passa `manage_sms` em todas as 3 props | — |
| `WhatsAppCampaignsPage.vue` | passa `manage_whatsapp` em todas as 3 props | — |

Resultado: ligando só `view`, o usuário vê todas as campanhas dos 3 canais mas não cria/edita/exclui nada. Ligando `view + manage_sms`, só pode mexer em campanhas SMS. Ligando os 3 manage_* + view, mexe em tudo.

---

### Atualização 11 — Auditoria completa de Settings + Custom Roles compartilhados + admins intocáveis (2026-04-25)

Três trabalhos consolidados nesta rodada:

1. **Auditoria completa das ~14 páginas de Settings** — gating granular botão a botão em cada `Index.vue`. Antes só `*_view` era gated (pela sidebar); botões internos de CRUD ficavam visíveis pra qualquer agent independente da role. Ex.: a aba Agentes tinha "Adicionar Agente", lápis editar e lixeira **sempre visíveis** mesmo com `users_invite/edit/remove = false` no editor de função.
2. **Custom Roles compartilhados por conta** — `KlivyRolesController` retornava 403 pra qualquer não-admin; agentes Klivy com `roles_view = true` viam "Nenhuma função criada" mesmo a conta tendo várias.
3. **Admins/donos intocáveis** — proteção em camada dupla (frontend + backend) pra que `users_remove` nunca consiga deletar um administrador ou super admin Klivy, independente de quem clica.

#### Sidebar — `CHILD_GATES.Settings` mudado para `mode: 'filter'`

`app/javascript/dashboard/components-next/sidebar/Sidebar.vue:962-984` —
antes `mode: 'override'`, agora `mode: 'filter'`. Causa raiz: as rotas `macros_wrapper` e `canned_list` têm `meta.permissions: [...ROLES, ...CONVERSATION_PERMISSIONS]` (agent-accessible nativamente), então quando o Klivy negava no modo `override`, caía no fallback do Chatwoot e o item vazava. No modo `filter`, Klivy é a única fonte de verdade e o item é dropado direto.

#### UI granular — padrão `canX = isAdmin || can('settings', 'x_action')`

Aplicado em todas as páginas listadas abaixo. Quando o botão está num componente filho compartilhado, o pai passa as flags como props `:can-edit`/`:can-delete` (default `true` pra não quebrar usos existentes).

| Página | Arquivo | Botões gated |
|---|---|---|
| Agentes | `settings/agents/Index.vue` | "Adicionar Agente" → `users_invite`; lápis editar + AssignRoleButton → `users_edit`; lixeira → `users_remove` (com regra extra de admins intocáveis — ver abaixo) |
| Times | `settings/teams/Index.vue` | "Novo Time" → `teams_create`; engrenagem editar → `teams_edit`; lixeira → `teams_delete` |
| Etiquetas | `settings/labels/Index.vue` | "Adicionar" → `labels_create`; lápis → `labels_edit`; lixeira → `labels_delete` |
| Atributos | `settings/attributes/Index.vue` + `components-next/ConversationWorkflow/AttributeListItem.vue` (props `canEdit`, `canDelete`) | "Adicionar" → `custom_attributes_create`; lápis → `custom_attributes_edit`; lixeira → `custom_attributes_delete` |
| Automação | `settings/automation/Index.vue` + `AutomationRuleRow.vue` (props `canEdit`, `canDelete`) | "Adicionar" → `automation_create`; lápis + clone + toggle status → `automation_edit`; lixeira → `automation_delete` |
| Robôs | `settings/agentBots/Index.vue` | "Adicionar" + lápis + lixeira → `agent_bots_manage` |
| Macros | `settings/macros/Index.vue` + `MacrosTableRow.vue` (props `canEdit`, `canDelete`) | "Nova macro" → `macros_create`; lápis → `macros_edit`; lixeira → `macros_delete` |
| Respostas prontas | `settings/canned/Index.vue` | "Adicionar" → `canned_create`; lápis → `canned_edit`; lixeira → `canned_delete` |
| SLA | `settings/sla/Index.vue` (Options API — `setup()` block) | "Adicionar" → `sla_create`; lixeira → `sla_delete` |
| Integrações | `settings/integrations/IntegrationItem.vue` | botão "Configurar" → `integrations_manage` |
| Conta | `settings/account/Index.vue` (Options API — `setup()` block) | botão "Salvar" → `account_manage` |
| Cobrança | `settings/billing/Index.vue` | "Comprar créditos" + "Upgrade" → `billing_manage` |
| Funções personalizadas | `plugins/custom_roles/frontend/features/roles-list/RolesListIndex.vue` | "Nova função" → `roles_create`; card clicável + lápis → `roles_edit`; lixeira → `roles_delete` |

Caixas de entrada já tinha gates granulares (atualização 3) e não foi tocado.

#### Custom Roles compartilhados por conta — `KlivyRolesController` refeito

`plugins/custom_roles/app/controllers/api/v1/accounts/klivy_roles_controller.rb` —
removido `before_action :authorize_admin!` (que mandava 403 pra todo não-admin) e substituído por `authorize_action!` que respeita perms granulares por action:

```ruby
def authorize_action!
  return if Current.account_user&.administrator?

  permitted = case action_name.to_sym
              when :index, :show then beclinic_can_view_roles?
              when :create  then beclinic_can?(:settings, :roles_create)
              when :update  then beclinic_can?(:settings, :roles_edit)
              when :destroy then beclinic_can?(:settings, :roles_delete)
              when :assign  then beclinic_can?(:settings, :users_edit)
              end

  render json: { error: 'forbidden' }, status: :forbidden unless permitted
end

def beclinic_can_view_roles?
  beclinic_can?(:settings, :roles_view) ||
    beclinic_can?(:settings, :users_edit)
end

def beclinic_can?(mod, action)
  return false unless Current.user && Current.account
  Current.user.beclinic_can?(Current.account, mod, action)
end
```

**Por que `users_edit` libera index/show:** o `AssignRoleButton` na lista de Agentes precisa carregar a lista de roles disponíveis pra montar o modal de atribuição. Sem isso, agente com `users_edit` mas sem `roles_view` ficaria sem dropdown.

**Action `assign`** (atribuir role a um agente) gated por `users_edit` — porque a operação modifica `account_users.klivy_role_id`, que conceitualmente é editar o agente.

A query continua `Current.account.klivy_roles.order(:name)` — escopo natural por conta, sem filtro por owner/criador. Isso garante que **todos os agentes da conta** com permissão veem a mesma lista (admins criam, demais consomem).

#### Admins/donos intocáveis — frontend

`app/javascript/dashboard/routes/dashboard/settings/agents/Index.vue:88-97` —
`showDeleteAction` reescrito:

```js
const showDeleteAction = agent => {
  if (currentUserId.value === agent.id) return false;        // não deleta a si mesmo
  if (agent.role === 'administrator') return false;          // admin Chatwoot
  if (agent.beclinic_super_admin) return false;              // dono Klivy
  return true;
};
```

A regra original do Chatwoot ("não deleta o último admin verificado", baseada em contagem) foi removida e substituída pela regra mais ampla acima — qualquer admin é intocável, sem depender de contagem.

#### Admins/donos intocáveis — backend

`app/controllers/api/v1/accounts/agents_controller.rb` —
adicionado `before_action :prevent_admin_removal, only: [:destroy]`:

```ruby
def prevent_admin_removal
  return unless @agent

  is_admin_target = @agent.current_account_user&.administrator?
  is_owner_target = @agent.respond_to?(:beclinic_super_admin?) && @agent.beclinic_super_admin?
  return unless is_admin_target || is_owner_target

  render json: { error: 'Administradores e donos não podem ser removidos.' }, status: :forbidden
end
```

Fecha contorno via curl/Postman/extensão — mesmo um admin atacante (ou um agent com `users_remove` que descobriu o ID via API) não consegue deletar um admin pela API direta. Pra remover um admin, é preciso primeiro **rebaixá-lo** pelo editor de agente (operação que exige `users_edit` e modifica `account_users.role` em vez de `destroy`).

#### Frontend `RolesListIndex.vue` — gating dos próprios botões de role

`plugins/custom_roles/frontend/features/roles-list/RolesListIndex.vue` —
adicionados `canCreateRole` (`roles_create`), `canEditRole` (`roles_edit`), `canDeleteRole` (`roles_delete`). Aplicados em:

- `v-if="canCreateRole"` no botão "Nova função"
- `:disabled="!canEditRole"` no card clicável que abre o editor + `@click="canEditRole && goEdit(role.id)"`
- `v-if="canEditRole"` no ícone lápis
- `v-if="canDeleteRole"` no ícone lixeira (com confirmação dupla mantida)

Resultado: agente com `roles_view` apenas vê a lista das funções da conta sem botões de ação. Agente com `roles_view + roles_create` vê "Nova função" mas não consegue editar as existentes. Etc.

#### Como testar

1. **Custom Roles compartilhados:**
   - Logue como admin (John), crie uma função "Especialista" com algumas perms.
   - Em "Atribuir Função", aplique a função a um agente comum (Gustavo).
   - Logue como Gustavo. Em Configurações → Funções Personalizadas, ele deve ver a função "Especialista" criada pelo John (antes via lista vazia).
2. **UI granular Settings:**
   - Crie role com **só** `users_view` ligado em Agentes. Atribua ao Gustavo.
   - Em Settings → Agentes, Gustavo vê os 2 agentes mas **sem** botões "Adicionar", lápis ou lixeira.
   - Ative `users_invite` na role → "Adicionar Agente" aparece.
   - Ative `users_edit` → lápis e botão de Atribuir função aparecem.
   - Ative `users_remove` → lixeira aparece (mas só em agentes não-admin; ver abaixo).
3. **Admins intocáveis:**
   - Mesmo com `users_remove = true`, Gustavo nunca vê lixeira no agente John (admin Super Admin).
   - Tentar `DELETE /api/v1/accounts/1/agents/<john_id>` via curl com o token do Gustavo retorna 403 com `{"error":"Administradores e donos não podem ser removidos."}`.

---

## 5. Arquivos removidos

UI antiga e UI paralela órfãs após a substituição:

```
app/javascript/dashboard/routes/dashboard/settings/customRoles/Index.vue
app/javascript/dashboard/routes/dashboard/settings/customRoles/component/CustomRoleModal.vue
app/javascript/dashboard/routes/dashboard/settings/customRoles/component/CustomRolePaywall.vue
app/javascript/dashboard/routes/dashboard/settings/customRoles/component/CustomRoleTableBody.vue
app/javascript/dashboard/routes/dashboard/settings/customRoles/customRole.routes.js
plugins/beclinic_core/frontend/api/beclinicRoles.js
plugins/beclinic_core/frontend/settings/BeClinicRoles/AssignRoleModal.vue
plugins/beclinic_core/frontend/settings/BeClinicRoles/Index.vue
plugins/beclinic_core/frontend/settings/BeClinicRoles/RoleFormModal.vue
plugins/beclinic_core/frontend/settings/BeClinicRoles/beclinicRoles.routes.js
```

> Nota: o **store Vuex** legado `app/javascript/dashboard/store/modules/customRole.js`
> e referências em `agents/AddAgent.vue`/`EditAgent.vue` ao `custom_role_id`
> antigo do Chatwoot **foram mantidos**. Eles são ortogonais ao `klivy_role` e
> podem ser limpos numa próxima rodada.

---

## 6. Banco de dados

### Tabelas

```sql
CREATE TABLE klivy_roles (
  id           bigserial PRIMARY KEY,
  account_id   bigint NOT NULL REFERENCES accounts(id),
  name         varchar(80) NOT NULL,
  description  varchar(240),
  preset_key   varchar(40),
  permissions  jsonb NOT NULL DEFAULT '{}',
  created_at   timestamp NOT NULL,
  updated_at   timestamp NOT NULL
);
CREATE UNIQUE INDEX index_klivy_roles_on_account_and_name
  ON klivy_roles(account_id, name);
```

### Coluna nova em tabela existente

```sql
ALTER TABLE account_users
  ADD COLUMN klivy_role_id bigint REFERENCES klivy_roles(id);
CREATE INDEX index_account_users_on_klivy_role_id
  ON account_users(klivy_role_id);
```

### Aplicação

```bash
bundle exec rails db:migrate
# == 20260425220001 CreateKlivyRoles: migrated
# == 20260425220002 AddKlivyRoleIdToAccountUsers: migrated
```

> O hook `annotaterb` falhou após as migrations com erro pré-existente no
> projeto (`TypeError: no implicit conversion of Hash into String` em algum
> YAML serializado). **Não bloqueia as migrations** e não tem relação com este
> trabalho — investigar separadamente.

---

## 7. Catálogo de módulos (`plugins/custom_roles/frontend/shared/modules.js`)

12 módulos × N sub-permissões. Cada `module.key` corresponde ao primeiro
argumento de `can(modulo, acao)` e ao `SIDEBAR_NAME_TO_MODULE` do sidebar.

| Módulo | Sub-permissões |
|---|---|
| `inbox` | view, mark_read |
| `chat` | view_all, view_unassigned, view_mentions, reply, assign_conversation, transfer_inbox, delete_message, send_broadcast |
| `captain` | view, manage_faqs, manage_documents, manage_scenarios, use_playground, manage_settings |
| `agenda` | **(agrupado)** Calendário: view, create_event, edit_event, cancel_event, drag_and_drop, manage_blocks · Configurações: view_settings, manage_schedules, manage_online_booking, manage_services · Notificações: view_notifications, manage_notifications · Atributos: manage_custom_attributes |
| `patients` | view, create, edit, delete, view_clinical_notes, create_clinical_notes, sign_clinical_notes, delete_clinical_notes, view_treatment_plans, manage_treatment_plans, view_consents, manage_consents, view_documents, manage_documents, view_exams, manage_exams, view_audit, view_timeline |
| `financial` | view_dashboard, view_cashflow, view_receivables, view_payables, view_dre, view_reports, view_cash_register, create_transaction, edit_transaction, delete_transaction, manage_estimates, approve_estimate, export_data, manage_settings |
| `contacts` | view_all, view_active, create, edit, delete, manage_segments, manage_tags, import_export |
| `reports` | view_overview, view_conversation, view_agent, view_label, view_inbox, view_team, view_csat, view_sla, view_bot, view_agenda |
| `campaigns` | view, manage_live_chat, manage_sms, manage_whatsapp |
| `help_center` | view, manage_articles, manage_categories, manage_portals |
| `settings` | **(agrupado, CRUD por área)** Conta: account_view, account_manage · Agentes: users_view, users_invite, users_edit, users_remove · Times: teams_view, teams_create, teams_edit, teams_delete · Caixas de entrada: inboxes_view, inboxes_create, inboxes_edit, inboxes_delete, inboxes_manage_agents · Etiquetas: labels_view, labels_create, labels_edit, labels_delete · Atributos personalizados: custom_attributes_view, custom_attributes_create, custom_attributes_edit, custom_attributes_delete · Automação: automation_view, automation_create, automation_edit, automation_delete · Robôs: agent_bots_view, agent_bots_manage · Macros: macros_view, macros_create, macros_edit, macros_delete · Respostas prontas: canned_view, canned_create, canned_edit, canned_delete · Integrações: integrations_view, integrations_manage · Auditoria: audit_view · Funções personalizadas: roles_view, roles_create, roles_edit, roles_delete · SLA: sla_view, sla_create, sla_edit, sla_delete · Fluxo de conversa: workflow_view, workflow_manage · Segurança: security_view, security_manage · Cobrança: billing_view, billing_manage |
| `help` | view |

---

## 8. Como testar

1. Acessar **Settings → Funções Personalizadas**
2. Clicar **Nova função** → escolher preset "Recepcionista" → desligar o módulo "Financeiro" inteiro (toggle pai) → salvar
3. **Settings → Agentes** → clicar no escudo de um agente → atribuir a função
4. Logar como esse agente:
   - Item "Financeiro" some do menu lateral
   - Tela do prontuário: tab "Financeiro" some, botão "Cobrar" some
   - Acessar URL direta `?tab=financial` mostra `<PermissionDenied />` (cadeado), sem toast de erro

### Cenário Recepcionista (gating fino da Agenda)

Editar a função "Recepcionista" e marcar **só** `view`, `view_notifications` e
`drag_and_drop` no módulo Agenda. Logar e abrir `/agenda`:

- Botão "Novo Evento" (header desktop) e FAB mobile **somem**.
- Botão `+` em cada célula do mês **some**.
- Clicar em dia vazio dispara toast "Você não tem permissão para criar eventos." — modal não abre.
- Cards de evento: **sem** ícone de lixeira, **sem** handle de resize.
- Arrastar evento para outro horário **funciona** (drag_and_drop ligado).
- Clicar em evento abre a popup, mas **sem** botão "Editar" e **sem** painel "Atualizar Status" — só "Prontuário".
- Acessar `/agenda/settings` → cadeado "Configurações da agenda restritas".
- Acessar `/agenda/custom_attributes` → cadeado "Atributos personalizados restritos".
- Sidebar: dentro de Agenda, só aparece o item "Calendar" (Settings e Custom Attributes somem).

### Cenário Configurações parciais

Função com `view_settings: true` e **só** `manage_schedules: true`:

- Sidebar: aparece "Settings" dentro da Agenda.
- Página de configurações: só a aba "Horários" aparece. As outras 3 (Notificações, Agendamento online, Serviços) somem.
- Tentar acessar `/agenda/custom_attributes` → cadeado.

### Cenário Conversas restritas (atualização 4)

Função personalizada com módulo `chat` configurado **só** com `view_all: true`
(todo o resto desligado: reply, assign, transfer, delete, broadcast, mentions,
unassigned). Recarregar a aba e abrir uma conversa:

- Lista de conversas carrega normalmente (3 itens — `view_all` libera).
- A aba "Não atribuídas" e "Menções" **somem** (já gateadas em rodada anterior).
- Botão **pena/composer ao lado da busca** (nova conversa / broadcast) **some**
  da sidebar topo.
- Painel direito ("Ações da conversa"): **sem** dropdown "Agente atribuído",
  **sem** dropdown "Time atribuído". "Prioridade" e "Etiquetas" continuam.
- **Reply box no rodapé** é trocado por um banner cinza com cadeado
  "Você não tem permissão para responder conversas."
- **Menu de contexto** numa mensagem (clique direito): **sem** opção "Excluir mensagem".

Backend (defesa em profundidade):
- `POST /conversations/:id/assignments` → 401 (Pundit `assign?`).
- `POST /conversations/:id/messages` → 401 (Pundit `reply?`).
- `DELETE /conversations/:id/messages/:mid` → 401 (Pundit `delete_message?`).
- `POST /conversations` → 401 (helper `allowed_to_create_conversation?`).

Pra confirmar via console:

```ruby
ctx = {
  user: User.find_by(email: 'recepcionista@example.com'),
  account: Account.find(1),
  account_user: AccountUser.find_by(user_id: ..., account_id: 1)
}
pol = ConversationPolicy.new(ctx, Conversation.find(...))
pol.show?           # true   (view_all)
pol.reply?          # false
pol.assign?         # false
pol.delete_message? # false
pol.send_broadcast? # false
```

### Cenário Caixas de Entrada ponta-a-ponta (atualização 3)

Função personalizada com **apenas** `settings.inboxes_view + inboxes_create +
inboxes_edit + inboxes_delete + inboxes_manage_agents` ligados (todo o resto
desligado). Logar como esse usuário (que tem role nativo Chatwoot `agent`):

- Sidebar Configurações: só **Caixas de Entrada** aparece (e Macros + Respostas
  Prontas, que sempre aparecem por terem rotas com `[...ROLES]`).
- `/settings/inboxes/list` carrega normalmente (router guard libera via
  `KLIVY_PREFIX_ROUTE_RULES`).
- Botão "Configurar nova caixa de entrada" aparece (gating Klivy no `Index.vue`).
- Clicar → escolher canal → criar inbox → adicionar agentes → finalizar:
  - O `POST /api/v1/accounts/:id/inboxes` passa pela `InboxPolicy#create?` que
    aceita `inboxes_create`.
  - O controller auto-vincula o usuário criador como `InboxMember`.
  - A inbox aparece na lista (Scope retorna `account.inboxes` quando há `inboxes_view`).
- Clicar no ícone de configurações da inbox → página abre, edits funcionam (`update?` aceita `inboxes_edit`).
- Clicar na lixeira → confirmação → exclui (`destroy?` aceita `inboxes_delete`).
- **Conversas dessa inbox** aparecem em `/conversations` (sidebar "Conversas →
  Todos") porque o usuário é `InboxMember` via auto-assign. Se a caixa foi
  criada **antes** do auto-assign entrar em vigor (ex.: durante o
  desenvolvimento, com hot-reload incompleto), as conversas vão chegar no DB
  mas ficar invisíveis na UI até alguém criar o `InboxMember`. Sintoma:
  `bundle exec rails runner 'puts Inbox.find(X).inbox_members.count'` retorna 0.
  Fix: backfill manual ou re-criação da caixa.

Reiniciar o Rails (Foreman/puma) é obrigatório após cada mudança em policy/controller.

---

## 9. Padrões usados (regras de codificação)

- **Plugin isolado** em `plugins/custom_roles/`. Toda lógica nova mora aqui exceto onde tocar o core foi inevitável (5 arquivos, listados na seção 3).
- **1 arquivo = 1 responsabilidade**. Componentes Vue ≤ ~150 linhas.
- **Tailwind inline** com tokens do projeto (`bg-n-slate-*`, `text-n-slate-*`, `border-n-weak`, `bg-n-brand`, `bg-woot-*`, `bg-n-ruby-*`, `text-heading-*`, `text-body-*`). **Não usar** `var(--color-...)` em CSS files — esses tokens não existem no projeto e renderizam transparente.
- **Componentes reusados do projeto**:
  - `dashboard/components-next/button/Button.vue`
  - `dashboard/components-next/input/Input.vue`
  - `dashboard/components-next/switch/Switch.vue`
  - `dashboard/routes/dashboard/settings/SettingsLayout.vue`
  - `dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue`
  - `woot-modal` + `woot-modal-header` (globais)
- **Erros de permissão silenciados** via `useSilentErrors` — nunca mostrar toast de erro técnico quando o backend retorna 401/403 numa chamada gated.
- **Plugin migrations registradas via initializer no engine** (não jogadas em `db/migrate/` central).
- **Composable `useXxxPermissions` por plugin** — quando um plugin tem várias
  ações sensíveis, criar um composable só pra centralizar (`canCreate`,
  `canEdit`, ...) e expor `guard(action, fn)`. Padrão estabelecido em
  `plugins/agenda/frontend/composables/useAgendaPermissions.js` e replicável
  para os próximos plugins.
- **Gating em camadas**: hide visual (props `can*` nos componentes) **+**
  guard funcional (handlers retornam cedo com `useAlert` em PT-BR). Defesa em
  profundidade contra cliques em UI fora do esperado.

### Padrão canônico das 5 camadas (estabelecido pelas Caixas de Entrada — atualização 3)

Para qualquer área core do Chatwoot que queira virar Klivy-aware, o conjunto
mínimo de mudanças é:

1. **Frontend gating** (`SettingsXxx/Index.vue` ou similar): trocar `v-if="isAdmin"`
   por computeds `canCreateXxx/canEditXxx/canDeleteXxx` combinando `isAdmin`
   nativo com `can('settings', 'xxx_action')` Klivy. Usuário não-admin com a
   permissão ligada vê os botões.
2. **Sidebar `CHILD_GATES`** (mode `override`): mapear o nome do item de menu
   pra `[modulo, acao]` Klivy. Sem isso, o item nunca aparece pra agentes
   nativos porque a rota tem `meta.permissions: ['administrator']`.
3. **Router rule** em `routeHelpers.js` (`KLIVY_EXACT_ROUTE_RULES` ou
   `KLIVY_PREFIX_ROUTE_RULES`): mapear o nome da rota pra `[modulo, acao]`
   Klivy. Sem isso, clicar no item redireciona pro dashboard via `defaultRedirectPage`.
4. **Pundit policy**: trocar `@account_user.administrator?` por
   `@account_user.administrator? || beclinic_can?(:settings, :xxx_action)`
   em cada ação relevante (`create?`, `update?`, `destroy?`, etc.). Sem isso,
   o backend devolve 401 mesmo com tudo liberado no front. Cobrir também
   o `Scope#resolve` se a área filtra registros por usuário (ex.: Inbox).
5. **Auto-assign creator** (controller): se a área tem o conceito de "membros"
   (Inbox → InboxMember, Team → TeamMember), o `create` deve auto-vincular
   o usuário não-admin que acabou de criar — senão ele perde o acesso ao
   próprio recurso porque os filtros `assigned_*` o excluem. **Lembrete**:
   permissão Klivy `xxx_view` libera só a tela do recurso em si; recursos
   filhos (ex.: Conversas dentro de uma Inbox) usam relação `Member` própria
   do Chatwoot e ignoram a permissão Klivy. Por isso o auto-assign é a ponte.

Implementação canônica disponível em:
- Frontend: `app/javascript/dashboard/routes/dashboard/settings/inbox/Index.vue`
- Sidebar: `Sidebar.vue` → `CHILD_GATES.Settings`
- Router: `app/javascript/dashboard/helper/routeHelpers.js`
- Policy: `app/policies/inbox_policy.rb`
- Auto-assign: `app/controllers/api/v1/accounts/inboxes_controller.rb#create`

---

## 10. Pendências conhecidas

Não foram feitas nesta rodada:

1. **Pass de `v-if can()` nas tabs internas do prontuário** — botões dentro de
   `EvolutionTab.vue`, `TreatmentPlanTab.vue`, `DocumentsTab.vue`,
   `ConsentsTab.vue`, `ExamsTab.vue`, `AuditTab.vue`, `RegistrationTab.vue`.
   O catálogo já cobre todas as ações (`patients.create_clinical_notes`,
   `sign_clinical_notes`, `manage_treatment_plans`, etc); falta aplicar nos
   templates.
2. **Pass nos outros plugins** (financial, contacts, campaigns, help_center) —
   botões de criar/editar/excluir dentro deles ainda aparecem independente de
   permissão. **Agenda já foi feita** (calendário + configurações + atributos
   personalizados). **Caixas de Entrada (settings/inbox/Index.vue + InboxPolicy)**
   já foi feita ponta-a-ponta:
   - **Frontend**: `usePermissions().can('settings', 'inboxes_*')` no `Index.vue`
     (botões "Configurar nova", "Editar", "Excluir").
   - **Backend**: `InboxPolicy` com `@account_user.administrator? || beclinic_can?(:settings, :inboxes_*)`.

   As demais páginas internas de Configurações (Etiquetas, Macros, Respostas
   Prontas, Automação, Robôs, Times, Agentes, etc.) seguem o **mesmo padrão**:
   - Frontend: importar `usePermissions`, criar computeds `canCreateXxx/canEditXxx/canDeleteXxx`
     e trocar os `v-if="isAdmin"` por essas computeds.
   - Backend: editar a Policy correspondente (`MacroPolicy`, `LabelPolicy`,
     `AutomationRulePolicy`, `CannedResponsePolicy`, `SlaPolicyPolicy`, etc.)
     trocando `@account_user.administrator?` por
     `@account_user.administrator? || beclinic_can?(:settings, :<group>_<action>)`.
3. **Tabs internas das configurações da agenda** — dentro das abas que o
   usuário **pode** ver, todos os toggles/inputs/botões ainda funcionam
   livremente. A regra atual é binária: se você vê a aba, você gerencia.
   Caso seja preciso um modo "read-only", precisaria adicionar um prop
   `readOnly` em cada `SettingsTab*.vue` e desabilitar inputs.
4. **Router guard global para módulos não-Settings** — para rotas das
   Configurações e Agenda já existe fallback Klivy em `routeHelpers.js`
   (ver seção 3). Para outros módulos (financial, contacts, campaigns,
   reports, help_center) o fallback não está mapeado: alguém que cola
   `/financial` no navegador ainda chega na página se for `administrator`
   nativo, e é redirecionado se não for. Adicionar entradas no
   `KLIVY_EXACT_ROUTE_RULES`/`KLIVY_PREFIX_ROUTE_RULES` cobre os próximos
   plugins quando entrarem no escopo.
5. **Remoção do `customRole` Vuex legado** e referências no formulário de
   agente — pode ser feito quando o time confirmar que a feature flag
   `custom_roles` do Chatwoot Enterprise não é mais usada.
6. **`annotaterb` quebrado** em `db:migrate` — pré-existente, sem relação.
   Investigar a column serializada que está com YAML inválido.

---

## 11. Anexos

- Endpoint da API: `GET|POST|PATCH|DELETE /api/v1/accounts/:account_id/klivy_roles[/:id]`
- Endpoint extra: `POST /api/v1/accounts/:account_id/klivy_roles/:id/assign` body `{ user_id: 42 }`
- Endpoint de leitura consolidada: `GET /api/v1/accounts/:account_id/beclinic_permissions`
  retorna `{ beclinic_role, permissions, team, klivy_role }`.
