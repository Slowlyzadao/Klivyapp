# Mega Update — 2026-04-26

> Pacote consolidado de mudanças desenvolvidas até 2026-04-26 sobre o KlivyApp (fork do Chatwoot). Cobre **dois plugins novos**, refatoração ampla do **RBAC**, evolução do módulo **Ajuda** (FAQ → dropdown + formulários de feedback), ajustes em **Agenda / Pacientes / Financeiro**, correção do **bridge WhatsApp**, e a desativação completa do antigo módulo `BeClinicRoles`.

---

## 1. Sumário executivo

| Categoria | Status | Observação |
|-----------|--------|-------------|
| **Plugins novos** | 2 | `custom_roles`, `migration` |
| **Plugin atualizado** | `ajuda` | dropdown + Reportar erro + Solicitar melhoria |
| **Plugins afetados** | `agenda`, `patients`, `financial`, `beclinic_core` | gating fino + ajustes UI |
| **Toques no core (Rails)** | Cirúrgicos | listados na §6 |
| **Toques no core (Vue)** | Médios | sidebar, permissões, route helpers |
| **Arquivos criados** | ≈ 50 | maioria dentro dos plugins novos |
| **Arquivos removidos** | 9 | módulo antigo `BeClinicRoles` + `customRoles/` legado |
| **Total de arquivos modificados/criados/removidos** | ~150 | — |
| **Mudanças runtime descartadas** | ✅ | `bridge.log`, `lid_map.json`, `sessions/` (gitignore) |

---

## 2. Plugin novo — `plugins/custom_roles/`

Sistema completo de **RBAC granular** atribuído **direto ao usuário** (`account_users.klivy_role_id`), substituindo as duas tentativas anteriores que ficaram órfãs (frontend antigo em `app/javascript/.../settings/customRoles/` e plugin de roles dentro de `beclinic_core`).

**Stack do plugin (engine isolado):**

```
plugins/custom_roles/
├── app/
│   ├── controllers/api/v1/accounts/klivy_roles_controller.rb
│   └── models/klivy_role.rb
├── db/migrate/
│   ├── 20260425220001_create_klivy_roles.rb
│   └── 20260425220002_add_klivy_role_id_to_account_users.rb
├── frontend/
│   ├── api/klivyRolesApi.js
│   ├── components/PermissionDenied.vue
│   ├── composables/
│   │   ├── useRoleEditor.js
│   │   ├── useRolesList.js
│   │   └── useSilentErrors.js
│   ├── features/
│   │   ├── role-assignment/
│   │   │   ├── AssignRoleButton.vue
│   │   │   ├── AssignRoleModal.vue
│   │   │   └── RoleOption.vue
│   │   ├── role-editor/
│   │   │   ├── RoleEditorIndex.vue
│   │   │   └── components/
│   │   │       ├── ModeTabs.vue
│   │   │       ├── ModuleSection.vue
│   │   │       ├── PermissionGroup.vue
│   │   │       ├── PermissionToggle.vue
│   │   │       ├── PresetPicker.vue
│   │   │       ├── RoleEditorHeader.vue
│   │   │       └── RoleIdentityForm.vue
│   │   └── roles-list/RolesListIndex.vue
│   ├── routes/routes.js
│   └── shared/{modules.js, presets.js}
└── lib/custom_roles/engine.rb
```

**Rotas frontend:** `/settings/custom-roles`, `/settings/custom-roles/new`, `/settings/custom-roles/:id/edit`

**Documentação completa:** [`docs/01-product/modules/funcoes-personalizadas.md`](../01-product/modules/funcoes-personalizadas.md) (também novo neste pacote).

### Pontos de integração (toques no core obrigatórios para o RBAC funcionar)

- **Policies do core ajustadas** (`app/policies/*.rb`): `agent_bot_policy`, `automation_rule_policy`, `campaign_policy`, `contact_policy`, `conversation_policy`, `inbox_policy`, `label_policy`, `portal_policy`, `team_policy`, `user_policy`, `webhook_policy`, `report_policy`, `account_policy`, `article_policy`, `category_policy`, `hook_policy`, `assignment_policy_policy` — todas passaram a aceitar `klivy_role` como fonte de permissão além das roles padrão `administrator`/`agent` do Chatwoot.
- **Policies adicionadas:** `canned_response_policy.rb`, `custom_attribute_definition_policy.rb` (não existiam antes).
- **Controllers do core ajustados** para aplicar `authorize`: `agents_controller`, `campaigns_controller`, `canned_responses_controller`, `conversations_controller`, `conversations/assignments_controller`, `conversations/messages_controller`, `custom_attribute_definitions_controller`, `inboxes_controller`.
- **Composable Vue:** `app/javascript/dashboard/composables/usePermissions.js` ganhou suporte ao `klivy_role`.
- **Helpers Vue:** `app/javascript/dashboard/helper/routeHelpers.js` reorganizado para incluir gating por permissão granular.
- **Sidebar (`Sidebar.vue`)**: leitura grande (≈ 400 linhas) — adicionou `CHILD_GATES` por módulo (Agenda / Financial / Contacts / Reports / Settings) que escondem ou liberam itens conforme o `klivy_role`.

### Enterprise (também tocado)

- `enterprise/app/policies/{account_saml_settings_policy, agent_capacity_policy_policy, custom_role_policy, sla_policy_policy}.rb` — passam a respeitar `klivy_role`.
- `enterprise/app/controllers/api/v1/accounts/audit_logs_controller.rb` — autoriza via `klivy_role`.

### Migrações DB

```ruby
# 20260425220001_create_klivy_roles.rb
create_table :klivy_roles do |t|
  t.references :account, null: false, foreign_key: true
  t.string :name, null: false
  t.string :slug
  t.text :description
  t.json :permissions, default: {}
  t.timestamps
end

# 20260425220002_add_klivy_role_id_to_account_users.rb
add_reference :account_users, :klivy_role, foreign_key: { to_table: :klivy_roles }
```

(Refletido em `db/schema.rb`.)

### Removido (substituído por este plugin)

- ❌ `app/javascript/dashboard/routes/dashboard/settings/customRoles/Index.vue`
- ❌ `app/javascript/dashboard/routes/dashboard/settings/customRoles/component/CustomRoleModal.vue`
- ❌ `app/javascript/dashboard/routes/dashboard/settings/customRoles/component/CustomRolePaywall.vue`
- ❌ `app/javascript/dashboard/routes/dashboard/settings/customRoles/component/CustomRoleTableBody.vue`
- ❌ `app/javascript/dashboard/routes/dashboard/settings/customRoles/customRole.routes.js`
- ❌ `plugins/beclinic_core/frontend/api/beclinicRoles.js`
- ❌ `plugins/beclinic_core/frontend/settings/BeClinicRoles/AssignRoleModal.vue`
- ❌ `plugins/beclinic_core/frontend/settings/BeClinicRoles/Index.vue`
- ❌ `plugins/beclinic_core/frontend/settings/BeClinicRoles/RoleFormModal.vue`
- ❌ `plugins/beclinic_core/frontend/settings/BeClinicRoles/beclinicRoles.routes.js`

---

## 3. Plugin novo — `plugins/migration/`

Importador autônomo de dados **Clinicorp → Klivy**, executado pelo Super Admin. Recebe planilhas CSV e popula a conta com **pacientes, anamneses e agenda**. Processamento assíncrono via Sidekiq, idempotente quando possível, log estruturado em `MigrationRun#errors_log`.

**Stack do plugin (engine isolado):**

```
plugins/migration/
├── app/
│   ├── jobs/migration/process_csv_job.rb
│   ├── models/migration_run.rb
│   └── services/migration/
│       ├── clinicorp_agenda_importer.rb
│       └── clinicorp_patient_importer.rb
├── db/migrate/20260426023750_create_migration_runs.rb
├── frontend/features/migration/
│   ├── MigrationIndex.vue
│   ├── api/migrationApi.js
│   ├── components/
│   │   ├── MigrationRunDetail.vue
│   │   ├── MigrationRunsTable.vue
│   │   └── MigrationUploadForm.vue
│   └── migration.css
└── lib/migration/{engine.rb, migration.rb}
```

**Funcionalidades:**

- **Pacientes (+ anamnese opcional)** — aceita até 3 CSVs no mesmo upload (`Patient.csv` obrigatório, `PatientAnamnesis.csv` e `Anamnesis.csv` opcionais).
- **Agenda** — CSV único de eventos/appointments com inferência de status, criação automática de `AgendaService` por procedimento, mapeamento de "Categoria" como `AgendaCustomAttribute` do tipo `select`.
- Selector de "financeiro" reservado mas desabilitado (vem depois).

### Pontos de integração com o core (Super Admin / Administrate)

São pontos **intencionais** porque a feature vive dentro do Administrate (gem do core), e o Zeitwerk (autoloader) força o registro nessas localizações:

- **Novo:** `app/controllers/super_admin/migrations_controller.rb`
- **Novo:** `app/views/super_admin/migrations/` (template Administrate)
- **Modificado:** `app/views/super_admin/application/_navigation.html.erb` (link "Migrações" no menu admin)
- **Modificado:** `config/routes.rb` (mounta o engine em `/super_admin/migrations`)
- **Modificado:** `app/javascript/entrypoints/superadmin_pages.js` (registro do JS do upload form)

**Documentação completa:** [`docs/01-product/modules/migracao.md`](../01-product/modules/migracao.md) (também novo).

---

## 4. Plugin atualizado — `plugins/ajuda/`

Reorganização do menu lateral e adição de dois formulários de feedback.

### Antes
- Item "Ajuda" no sidebar como link direto (leaf) → `/accounts/:id/ajuda` (FAQ).

### Depois
- Item "Ajuda" virou **dropdown** com 3 filhos:
  - **Artigos** → FAQ (rota existente, intacta).
  - **Reportar um erro** → `/accounts/:id/ajuda/reportar-erro` (novo).
  - **Solicitar melhoria** → `/accounts/:id/ajuda/solicitar-melhoria` (novo).

### Formulário de feedback (compartilhado)

Componente único [`HelpFeedbackForm.vue`](../../plugins/ajuda/frontend/features/help/components/HelpFeedbackForm.vue) com prop `mode="bug" | "feature"`:

- **Nome e e-mail** pré-preenchidos via `useMapGetter('getCurrentUser')` (`available_name` + `email`), **editáveis**.
- **Textarea** de descrição (label/placeholder mudam conforme `mode`).
- **Anexos**: até **5 arquivos**, **20MB cada**, formatos **JPG / JPEG / PNG / MP4 / PDF** (validado por MIME + extensão).
- **Estado de sucesso** com card teal + opção "Enviar outra".
- Submit **mockado** (`setTimeout`) — pronto para conectar endpoint real (provável `multipart/form-data`).

### Arquivos novos / alterados (Ajuda)

| Arquivo | Tipo | Descrição |
|---------|------|-----------|
| `plugins/ajuda/frontend/features/help/components/HelpFeedbackForm.vue` | ✨ novo | Form compartilhado bug/feature |
| `plugins/ajuda/frontend/features/help/HelpReportBug.vue` | ✨ novo | Página "Reportar um erro" |
| `plugins/ajuda/frontend/features/help/HelpFeatureRequest.vue` | ✨ novo | Página "Solicitar uma melhoria" |
| `plugins/ajuda/frontend/features/help/help.css` | ✏️ alterado | +264 linhas no fim — estilos `.hp-form-*` |
| `plugins/ajuda/frontend/routes/routes.js` | ✏️ alterado | +2 rotas: `ajuda_report_bug`, `ajuda_feature_request` |
| `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | ✏️ alterado | Item "Ajuda" virou dropdown com 3 filhos |

**Tokens de design respeitados:** `slate-*`, `blue-*`, `ruby-*` (vermelho), `teal-*` (verde) — todos do `_next-colors.scss` existente.

**Documentação:** [`docs/01-product/modules/ajuda.md`](../01-product/modules/ajuda.md) atualizado com a nova seção do dropdown.

---

## 5. Outros plugins atualizados

### `plugins/agenda/`
- **Novo:** `frontend/composables/useAgendaPermissions.js` — hook centralizado que lê `klivy_role.permissions.agenda.*`.
- **Atualizados:** `AgendaEventCard.vue`, `AgendaEventInfoPopup.vue`, `AgendaEventModal.vue`, `AgendaHeader.vue`, `AgendaMonthView.vue`, `AgendaTimelineView.vue`, `AgendaDashboard.vue`, `customAttributes/Index.vue`, `settings/Index.vue` — agora consultam `useAgendaPermissions` para esconder ações conforme a role.

### `plugins/patients/`
- **Backend** — `patients_controller`, `patients/exam_folders_controller`, `patients/financial_estimates_controller`, `patients/transactions_controller`: gating via `klivy_role`.
- **Frontend** — `Index.vue`, `Record.vue` (≈ +350 linhas), `tabs/EvolutionTab.vue`, `api/patients/index.js`: ajustes UI + permissões.

### `plugins/financial/`
- Páginas atualizadas com gating: `CashFlow.vue`, `CashRegister.vue`, `DRE.vue`, `Payables.vue`, `Receivables.vue`, `Reports.vue`.

### `plugins/beclinic_core/`
- `app/controllers/api/v1/accounts/beclinic_permissions_controller.rb` — limpeza, agora delega ao `klivy_role`.
- `app/models/concerns/beclinic_permissible.rb` — refatorado.
- Toda a pasta `frontend/settings/BeClinicRoles/` foi **removida** (substituída por `plugins/custom_roles/`).

---

## 6. Toques cirúrgicos no core (lista exaustiva)

Todos os toques no core são **autorizados** e estão listados aqui para auditoria. Nenhum arquivo do core teve lógica reescrita — apenas integração com o RBAC novo.

### Backend Rails (`app/`)

**Controllers:**
- `app/controllers/api/v1/accounts/agents_controller.rb`
- `app/controllers/api/v1/accounts/campaigns_controller.rb`
- `app/controllers/api/v1/accounts/canned_responses_controller.rb`
- `app/controllers/api/v1/accounts/conversations/assignments_controller.rb`
- `app/controllers/api/v1/accounts/conversations/messages_controller.rb`
- `app/controllers/api/v1/accounts/conversations_controller.rb`
- `app/controllers/api/v1/accounts/custom_attribute_definitions_controller.rb`
- `app/controllers/api/v1/accounts/inboxes_controller.rb`
- ✨ `app/controllers/super_admin/migrations_controller.rb` (novo, exige a integração Administrate)

**Policies (todas tocadas para suportar `klivy_role`):**
- `account_policy.rb`, `account_transaction_policy.rb`, `agent_bot_policy.rb`, `anamnesis_policy.rb`, `article_policy.rb`, `assignment_policy_policy.rb`, `automation_rule_policy.rb`, `bank_account_policy.rb`, `campaign_policy.rb`, `cash_register_policy.rb`, `category_policy.rb`, `commission_rule_policy.rb`, `contact_policy.rb`, `conversation_policy.rb`, `financial_category_policy.rb`, `financial_dashboard_policy.rb`, `financial_estimate_policy.rb`, `financial_goal_policy.rb`, `hook_policy.rb`, `inbox_policy.rb`, `label_policy.rb`, `portal_policy.rb`, `recurring_expense_policy.rb`, `report_policy.rb`, `team_policy.rb`, `transaction_policy.rb`, `user_policy.rb`, `webhook_policy.rb`
- ✨ `canned_response_policy.rb` (novo)
- ✨ `custom_attribute_definition_policy.rb` (novo)

**Views Super Admin:**
- `app/views/super_admin/application/_navigation.html.erb` — link "Migrações"
- ✨ `app/views/super_admin/migrations/` (novo, templates Administrate)

**Config:**
- `config/routes.rb` — mounta engine de migration
- `db/schema.rb` — tabelas `klivy_roles`, `migration_runs`, coluna `klivy_role_id` em `account_users`

### Enterprise (`enterprise/`)
- `enterprise/app/controllers/api/v1/accounts/audit_logs_controller.rb`
- `enterprise/app/policies/{account_saml_settings_policy, agent_capacity_policy_policy, custom_role_policy, sla_policy_policy}.rb`

### Frontend Vue (core)

**Sidebar e navegação:**
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` — adicionou `CHILD_GATES`, item "Ajuda" virou dropdown
- `app/javascript/dashboard/components-next/sidebar/SidebarCollapsedPopover.vue`
- `app/javascript/dashboard/components-next/sidebar/SidebarGroup.vue`
- `app/javascript/dashboard/components-next/sidebar/SidebarGroupLeaf.vue`
- `app/javascript/dashboard/components-next/sidebar/SidebarSubGroup.vue`
- `app/javascript/dashboard/components-next/sidebar/provider.js`

**Permissões e roteamento:**
- `app/javascript/dashboard/composables/usePermissions.js` — suporte a `klivy_role`
- `app/javascript/dashboard/helper/routeHelpers.js` — gating por permissão granular
- `app/javascript/dashboard/helper/portalHelper.js`
- `app/javascript/dashboard/routes/index.js`

**Páginas de Settings (paywall + gating):**
- `settings/account/Index.vue`, `agentBots/Index.vue`, `agents/Index.vue`, `attributes/Index.vue`, `automation/{Index, AutomationRuleRow}.vue`, `billing/Index.vue`, `canned/Index.vue`, `inbox/Index.vue`, `integrations/IntegrationItem.vue`, `labels/Index.vue`, `macros/{Index, MacrosTableRow}.vue`, `sla/Index.vue`, `teams/Index.vue`, `settings.routes.js`

**Outras páginas core afetadas pelo gating:**
- Campaigns: `CampaignCard.vue`, `CampaignLayout.vue`, `CampaignList.vue`, `LiveChatCampaignsPage.vue`, `SMSCampaignsPage.vue`, `WhatsAppCampaignsPage.vue`
- Contacts: `ContactDeleteSection.vue`, `ContactsCard.vue`, `ContactsDetailsLayout.vue`, `ContactHeader.vue`, `ContactMoreActions.vue`, `ContactEmptyState.vue`, `ContactDetails.vue`, `ContactsBulkActionBar.vue`, `ContactManageView.vue`, `ContactInfo.vue`
- Conversations: `ChatList.vue`, `ResolveAction.vue`, `MessagesView.vue`, `contextMenu/Index.vue`, `conversationBulkActions/Index.vue`, `ContactPanel.vue`, `ConversationAction.vue`
- Help Center (do core): `helpcenter/pages/PortalsIndexPage.vue`
- Conversation Workflow: `AttributeListItem.vue`
- Dialog: `Dialog.vue`

---

## 7. Bridge WhatsApp

- `lib/whatsapp/server.js` — removeu `require('node-fetch')`. Em Node 18+ (projeto roda Node 25), o `fetch` global já está disponível e o `node-fetch@v3` retornava o ESM namespace, quebrando todos os webhooks em silêncio.

### Runtime descartado da versão (gitignore atualizado)
- ❌ `lib/whatsapp/bridge.log` (untracked + ignored)
- ❌ `lib/whatsapp/lid_map.json` (untracked + ignored)
- ❌ `lib/whatsapp/sessions/` (já era untracked — agora ignorado explicitamente)
- ❌ `lib/whatsapp/in_*.tmp` (ignorado)
- ❌ `lib/whatsapp/channel_config.json` (ignorado para futuro)

---

## 8. Documentação

Novos docs criados ou atualizados:

- ✨ `docs/01-product/modules/funcoes-personalizadas.md` (novo) — RBAC granular completo
- ✨ `docs/01-product/modules/migracao.md` (novo) — importador Clinicorp
- ✏️ `docs/01-product/modules/ajuda.md` (atualizado) — nova seção "Reportar erro / Solicitar melhoria"
- ✨ `docs/04-changelog/2026-04-26-mega-update.md` (este arquivo)

---

## 9. Como aplicar este pacote em outra máquina

```bash
git pull origin main
bundle install
pnpm install
bin/rails db:migrate          # cria klivy_roles, migration_runs, klivy_role_id
pnpm overmind start           # ou: bin/dev
```

Migrações que entram com este commit:
1. `20260425220001_create_klivy_roles.rb`
2. `20260425220002_add_klivy_role_id_to_account_users.rb`
3. `20260426023750_create_migration_runs.rb`

---

## 10. Resumo das regras seguidas

- ✅ Nenhum arquivo do core teve **lógica existente reescrita** — apenas pontos de integração explicitados.
- ✅ Funcionalidades novas vivem **isoladas em plugins** (`custom_roles`, `migration`, `ajuda`).
- ✅ Padrão visual respeitado (tokens `slate/blue/ruby/teal` + classes `hp-*`).
- ✅ Klivy tratada como substantivo **feminino** em toda copy ("a Klivy", nunca "o Klivy").
- ✅ Runtime / logs / sessões removidos do tracking via `.gitignore`.
- ✅ Test files locais (`test_fetch.mjs`, `test_send_audio_v2.mjs`, `env.localhost`) **não** foram tocados — permanecem como estavam (já estavam no histórico antes deste pacote).
