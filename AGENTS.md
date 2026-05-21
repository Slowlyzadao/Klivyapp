# Chatwoot Development Guidelines

## Build / Test / Lint

- **Setup**: `bundle install && pnpm install`
- **Run Dev**: `pnpm dev` or `overmind start -f ./Procfile.dev`
- **Seed Local Test Data**: `bundle exec rails db:seed` (quickly populates minimal data for standard feature verification)
- **Seed Search Test Data**: `bundle exec rails search:setup_test_data` (bulk fixture generation for search/performance/manual load scenarios)
- **Seed Account Sample Data (richer test data)**: `Seeders::AccountSeeder` is available as an internal utility and is exposed through Super Admin `Accounts#seed`, but can be used directly in dev workflows too:
  - UI path: Super Admin → Accounts → Seed (enqueues `Internal::SeedAccountJob`).
  - CLI path: `bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.find(<id>))"` (or call `Seeders::AccountSeeder.new(account: Account.find(<id>)).perform!` directly).
- **Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix`
- **Lint Ruby**: `bundle exec rubocop -a`
- **Test JS**: `pnpm test` or `pnpm test:watch`
- **Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb`
- **Single Test**: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
- **Run Project**: `overmind start -f Procfile.dev`
- **Ruby Version**: Manage Ruby via `rbenv` and install the version listed in `.ruby-version` (e.g., `rbenv install $(cat .ruby-version)`)
- **rbenv setup**: Before running any `bundle` or `rspec` commands, init rbenv in your shell (`eval "$(rbenv init -)"`) so the correct Ruby/Bundler versions are used
- Always prefer `bundle exec` for Ruby CLI tasks (rspec, rake, rubocop, etc.)

## Code Style

- **Ruby**: Follow RuboCop rules (150 character max line length)
- **Vue/JS**: Use ESLint (Airbnb base + Vue 3 recommended)
- **Vue Components**: Use PascalCase
- **Events**: Use camelCase
- **I18n**: No bare strings in templates; use i18n
- **Error Handling**: Use custom exceptions (`lib/custom_exceptions/`)
- **Models**: Validate presence/uniqueness, add proper indexes
- **Type Safety**: Use PropTypes in Vue, strong params in Rails
- **Naming**: Use clear, descriptive names with consistent casing
- **Vue API**: Always use Composition API with `<script setup>` at the top

## Styling

- **Tailwind Only**:  
  - Do not write custom CSS  
  - Do not use scoped CSS  
  - Do not use inline styles  
  - Always use Tailwind utility classes  
- **Colors**: Refer to `tailwind.config.js` for color definitions

## General Guidelines

- MVP focus: Least code change, happy-path only
- No unnecessary defensive programming
- Ship the happy path first: limit guards/fallbacks to what production has proven necessary, then iterate
- Prefer minimal, readable code over elaborate abstractions; clarity beats cleverness
- Break down complex tasks into small, testable units
- Iterate after confirmation
- Avoid writing specs unless explicitly asked
- Remove dead/unreachable/unused code
- Don’t write multiple versions or backups for the same logic — pick the best approach and implement it
- Prefer `with_modified_env` (from spec helpers) over stubbing `ENV` directly in specs
- Specs in parallel/reloading environments: prefer comparing `error.class.name` over constant class equality when asserting raised errors

## Codex Worktree Workflow

- Use a separate git worktree + branch per task to keep changes isolated.
- Keep Codex-specific local setup under `.codex/` and use `Procfile.worktree` for worktree process orchestration.
- The setup workflow in `.codex/environments/environment.toml` should dynamically generate per-worktree DB/port values (Rails, Vite, Redis DB index) to avoid collisions.
- Start each worktree with its own Overmind socket/title so multiple instances can run at the same time.

## Commit Messages

- Prefer Conventional Commits: `type(scope): subject` (scope optional)
- Example: `feat(auth): add user authentication`
- Don't reference Claude in commit messages

## PR Description Format

- Start with a short, user-facing paragraph describing the product change.
- Add a `Closes` section with relevant issue links (GitHub, Linear, etc.).
- For feature PRs, add `How to test` from a product/UX standpoint.
- For bugfix PRs, use `How to reproduce` when helpful.
- Optionally add a `What changed` section for implementation highlights.
- Do not add a `How this was tested` section listing specs/commands.

## Project-Specific

- **Translations**:
  - Only update `en.yml` and `en.json`
  - Other languages are handled by the community
  - Backend i18n → `en.yml`, Frontend i18n → `en.json`
- **Frontend**:
  - Use `components-next/` for message bubbles (the rest is being deprecated)

## Ruby Best Practices

- Use compact `module/class` definitions; avoid nested styles

## Enterprise Edition Notes

- Chatwoot has an Enterprise overlay under `enterprise/` that extends/overrides OSS code.
- When you add or modify core functionality, always check for corresponding files in `enterprise/` and keep behavior compatible.
- Follow the Enterprise development practices documented here:
  - https://chatwoot.help/hc/handbook/articles/developing-enterprise-edition-features-38

Practical checklist for any change impacting core logic or public APIs
- Search for related files in both trees before editing (e.g., `rg -n "FooService|ControllerName|ModelName" app enterprise`).
- If adding new endpoints, services, or models, consider whether Enterprise needs:
  - An override (e.g., `enterprise/app/...`), or
  - An extension point (e.g., `prepend_mod_with`, hooks, configuration) to avoid hard forks.
- Avoid hardcoding instance- or plan-specific behavior in OSS; prefer configuration, feature flags, or extension points consumed by Enterprise.
- Keep request/response contracts stable across OSS and Enterprise; update both sets of routes/controllers when introducing new APIs.
- When renaming/moving shared code, mirror the change in `enterprise/` to prevent drift.
- Tests: Add Enterprise-specific specs under `spec/enterprise`, mirroring OSS spec layout where applicable.
- When modifying existing OSS features for Enterprise-only behavior, add an Enterprise module (via `prepend_mod_with`/`include_mod_with`) instead of editing OSS files directly—especially for policies, controllers, and services. For Enterprise-exclusive features, place code directly under `enterprise/`.

## Branding / White-labeling note

- For user-facing strings that currently contain "Chatwoot" but should adapt to branded/self-hosted installs, prefer applying `replaceInstallationName` from `shared/composables/useBranding` in the UI layer (for example tooltip and suggestion labels) instead of adding hardcoded brand-specific copy.

---

# Beclinic Custom Rules

> Project-specific rules layered on top of the Chatwoot OSS base. Anything in this section overrides or extends the Chatwoot guidelines above. **Beclinic** is the code/engine standard — all custom code identifiers use it. **Klivy** is only the end-product brand name; it appears exclusively in user-visible text (sourced from `BRAND_NAME` via `GlobalConfigService`) and never in new code identifiers, file names, classes, tables, columns, components, routes, or i18n keys.

## Change Scope (Isolation)

- **Develop in isolation by default**: only touch core (shared code, central models, base controllers, fundamental services, structural migrations) when strictly required by the task.
- Before editing a core file, ask: "Is there an extension point (module, hook, `enterprise/` override, decorator, dedicated plugin engine under `plugins/`) that solves this without changing core?" — if yes, use it.
- If a core change is unavoidable, **state the reason and the impact in the response** before applying it.
- Prefer creating new files / isolated modules over expanding existing core files.
- New custom feature work belongs in a dedicated engine under `plugins/` (`plugins/beclinic_core`, `plugins/agenda`, `plugins/patients`, `plugins/billing`, `plugins/financial`, etc.) or a new plugin engine — never mixed into generic Chatwoot OSS logic.

## Architecture & Code Quality

Apply these rules **before** writing any code, not after:

- **Think first**: before touching the keyboard, map the impact — which files/engines are affected, which existing patterns the change must respect, which integration points it crosses. Skip this only for trivial one-line fixes.
- **Read context first**: open the surrounding files (sibling controllers/services/components, the engine's `engine.rb`, related tests) to learn the established pattern. Match it instead of inventing a new one.
- **Check `plugins/` structure before creating a new module**: list `plugins/<engine>/app/`, `plugins/<engine>/lib/`, `plugins/<engine>/frontend/` and follow the same folder layout already in use. Do not invent parallel structures.
- **No hardcoded values**: route brand strings through `BRAND_NAME`/`GlobalConfigService`, environment values through `ENV`/Rails config, business constants through model constants or DB-backed settings, URLs through route helpers. Magic numbers in business logic must become named constants.
- **Separation of concerns**: controllers stay thin (params + auth + delegation); business logic lives in services (`*::Service`, `*::Action`, jobs); persistence and validations in models; presentation in components/serializers. Do not collapse layers.
- **No god files**: if a file grows past ~200 lines of real logic, or holds two unrelated responsibilities, split it. Prefer many small, single-purpose files over one large multi-purpose file.
- **Consistency with existing system**: naming (covered in the next section), folder organization, and data flow (params → service → model → response) must follow the patterns already present in the surrounding engine. When in doubt, copy the closest existing example.
- **Reuse vs. MVP — tiebreaker**: the General Guidelines above say "MVP focus, least code change". That stays in force for new code. Extract for reuse, add an extension point, or build an abstraction **only when 2+ real callers already exist**. Designing for hypothetical future callers is a violation, not a virtue. When the second caller appears, refactor then — not before.

## Reusable UI components — use these instead of inventing/native equivalents

When building Vue UI inside `plugins/`, ALWAYS prefer these shared components over native HTML or duplicated implementations. They live in `plugins/beclinic_core/frontend/components/` and exist precisely so we don't ship 12 different button styles or 8 tooltip variations.

| Use this | Instead of | Why |
|---|---|---|
| **`BeclinicButton`** | `<button class="...">`, `btn-primary` | Single source for variants (`solid`/`outline`/`faded`/`ghost`/`link`), colors, sizes, loading, icon. See its docstring for `variant` guide. |
| **`Tooltip`** | `title="..."` HTML attribute | Native `title` is browser-native, ugly, slow, doesn't survive in Teleport, breaks in screen readers. The `Tooltip` component renders via `<Teleport to="body">`, has consistent dark-pill style, animation, position-aware (`top`/`bottom`/`left`/`right`), and respects `delay`. |
| **`FormSelect`** | `<select>`, custom dropdowns | Search, clear, keyboard nav, consistent styling, dark-mode tokens. |
| **`Badge`** | `<span class="bg-... text-...">` | Semantic intent (`success`/`warning`/`danger`/`info`/`neutral`), color tokens, sizes, strikethrough mode. |
| **`Checkbox`** | `<input type="checkbox">` native | Native checkbox tem visual desencontrado entre browsers, ignora tema dark/light e o `accent-color` é inconsistente. O componente é `appearance-none` + checkmark SVG sobreposto, com hover/focus ring, disabled state e cores `--blue-9`/`--slate-7`. v-model + label/slot. |
| **`ConfirmDangerModal`** | `window.confirm`, inline modals | Modern modal with title/message/loading/cancel — replaces native `confirm()` (which composables shouldn't even call — separation of concerns). |

**Hard rules:**
- A new `<button title="...">` requires explicit user approval. Default action: wrap in `<Tooltip :label="...">`.
- A new `window.confirm` / `window.alert` / `window.prompt` is a code smell — use the appropriate modal component.
- Composables (`useXxx.js`) must NEVER call `window.confirm` or open modals — they're pure logic. UI lives in components.

**When extending an existing pattern:** if the shared component is missing a feature you need, extend the shared component (not your local copy). Two callers needing the same flag = it's a real requirement, not a one-off.

## Multi-tenancy — toda feature roda em isolamento por `account_id`

Klivy/Chatwoot é multi-tenant: cada clínica = uma `Account`. Quase todo modelo, endpoint, blob e cache de frontend é (ou deveria ser) scoped por `account_id`. Vazamento cross-tenant é um dos bugs mais caros de pegar em review e crítico em produção (clínica A enxerga dados da clínica B). As regras abaixo são **non-negotiable**.

**Regras de backend:**

1. **Toda query de modelo de plugin DEVE filtrar por `account_id`.** Nunca query global:
   - ❌ `Document.where(patient_id: x)` — pode retornar docs de outro tenant.
   - ✅ `Current.account.documents.where(...)`, `@patient.documents`, `policy_scope(Document)`.
2. **Rotas novas vão sob `/api/v1/accounts/:account_id/...`** (Chatwoot middleware seta `Current.account` e valida membership de `account_user` antes da action). Não criar endpoint global a menos que seja super_admin (`/super_admin/...`).
3. **Toda Policy DEVE checar `@account_user.present?`** para read e `administrator?` (ou role Beclinic mais estrita) para write.
4. **Modelos com `belongs_to :account`** devem validar presença e ter index em `account_id`. Tabelas plugin-novas: criar com `t.references :account, null: false, foreign_key: true`.
5. **Active Storage blobs servidos ao browser DEVEM passar pelo `SecureBlobsController`** ([plugins/patients/app/controllers/secure_blobs_controller.rb](plugins/patients/app/controllers/secure_blobs_controller.rb)) — token assinado carrega `account_id` + cross-tenant guard. Nunca expor `rails_blob_url` direto.
6. **Background jobs** não podem assumir `Current.account` — receber `account_id` como argumento e refetch.

**Regras de frontend:**

1. **Composables com cache em escopo de módulo** (`const profile = ref(...)` fora da função) DEVEM keyar por `accountId` ou invalidar quando `accountId` muda. Padrão: ler `accountId` do `useAccount()`, watchar, resetar state na mudança. Exemplo de referência: [`plugins/beclinic_core/frontend/composables/useClinicProfile.js`](plugins/beclinic_core/frontend/composables/useClinicProfile.js). O full reload do `SidebarAccountSwitcher` é safety net atual, **não garantia** — não dependa.
2. **URLs sempre via `useAccount()`**: usar `accountScopedUrl(...)` / `accountScopedRoute(...)` em vez de hardcodar `/app/accounts/X/...`.
3. **Vuex/store global**: getters tipo `getDocumentsList()` devem aceitar `accountId` ou ser invalidados em logout/account switch. Não popule store sem prefixo de account.

**Pre-merge checklist quando o diff toca tenant:**
- [ ] Toda query de plugin tem `account_id` no filtro (direto ou via association scoped)?
- [ ] Rota nova está sob `/api/v1/accounts/:account_id/...`?
- [ ] Policy nova checa `@account_user`?
- [ ] Cache de frontend (composable singleton) lida com troca de conta?
- [ ] Asset/blob servido via `SecureBlobsController` (não `rails_blob_url`)?
- [ ] Job em background recebe `account_id` por argumento?

## RBAC Klivy / Custom Roles — workflow ao adicionar perm em plugin

KlivyRole é o **único** sistema de permissões do produto (memory `rbac_klivy_only` — Times/TeamProfile/dono removidos em 2026‑04‑30). O catálogo de permissões vive em **2 lugares paralelos** que **precisam ser mantidos em sync** — o `catalog_sync_spec.rb` quebra o build se houver drift, mas o workflow padrão evita o problema:

| Catálogo | Função |
|---|---|
| [`plugins/custom_roles/frontend/shared/modules.js`](plugins/custom_roles/frontend/shared/modules.js) | Fonte da UI do editor de role + sidebar gating + router guards |
| [`plugins/custom_roles/app/models/klivy_role/permissions_catalog.rb`](plugins/custom_roles/app/models/klivy_role/permissions_catalog.rb) | Sanitize + delegation limit no backend + seed presets |

### Adicionar PERM nova em módulo existente

Exemplo: novo `patients.export_clinical_pdf`.

1. **JS** (`modules.js`): add `{ key: 'export_clinical_pdf', label: 'Exportar PDF' }` no array `permissions` do módulo `patients`.
2. **Ruby** (`permissions_catalog.rb`): add `'export_clinical_pdf'` no array `'patients'` do `CATALOG`.
3. **(Opcional) Presets**: se algum preset (Recepcionista/Especialista/Gerente/SDR) deve receber por padrão — espelhar em [`presets.js`](plugins/custom_roles/frontend/shared/presets.js) **E** [`preset_definitions.rb`](plugins/custom_roles/lib/custom_roles/preset_definitions.rb).
4. **Backend**: usar `beclinic_can?(:patients, :export_clinical_pdf)` em Policy/Controller.
5. **Frontend**: usar `usePermissions().can('patients', 'export_clinical_pdf')` ou `v-can="['patients','export_clinical_pdf']"`.
6. **(Se a feature tem rota nova com gating)**: add em `KLIVY_REQUIRED_ROUTE_RULES` em [`routeHelpers.js`](app/javascript/dashboard/helper/routeHelpers.js).

### Adicionar MÓDULO novo (plugin inteiro)

Exemplo: `plugins/prescriptions/`.

1. **JS**: nova entrada `{ key: 'prescriptions', label: 'Receituário', permissions: [...] }` em `MODULES` array.
2. **Ruby**: `'prescriptions' => %w[view create sign delete...]` no `CATALOG`.
3. **Presets**: espelhar (mesma regra do #3 acima).
4. **Sidebar** ([`Sidebar.vue`](app/javascript/dashboard/components-next/sidebar/Sidebar.vue)):
   - `SIDEBAR_NAME_TO_MODULE: { Prescriptions: 'prescriptions' }` (oculta item se módulo todo está desligado).
   - `CHILD_GATES.Prescriptions` se tem sub-items.
5. **Router guard**: `KLIVY_REQUIRED_ROUTE_RULES: { prescriptions_index: ['prescriptions', 'view'] }`.
6. **Backend/Frontend**: usar `beclinic_can?` / `usePermissions().can()` como acima.

### Failure modes se esquecer um dos catálogos

| Esquecimento | Sintoma |
|---|---|
| Perm só no Ruby, não no JS | Editor não tem o toggle pra essa perm — admin não consegue marcar. |
| Perm só no JS, não no Ruby | Admin marca true e salva → `sanitize_and_migrate` DROPA silenciosamente → ao recarregar, volta false. **Confusão UX.** |
| Backend usa `beclinic_can?` em perm que não está no catálogo | Admin passa (bypass), non-admin nunca consegue. Feature "broken pra non-admin". |

### Salvaguardas existentes

- **`spec/plugins/custom_roles/catalog_sync_spec.rb`** — falha o build se houver drift Ruby → JS. Roda no CI.
- **`LEGACY_KEY_MIGRATIONS`** (em ambos catálogos) — renomeação de perm é segura: mapear antiga → nova lá e o sistema migra automaticamente em todo save.
- **`sanitize_and_migrate`** no model — protege JSONB de payload arbitrário (auditoria C-2). Roda em `before_validation` de toda save de `KlivyRole`.
- **`enforce_delegation_limit!`** no controller — non-admin não delega perm que ele próprio não tem (auditoria C-2).
- **Admin bypass** total — `administrator? || beclinic_super_admin?` curto-circuita tudo. Drift nunca afeta admin.

### Quem usa o catálogo

- **Model**: `KlivyRole#before_validation :sanitize_permissions`.
- **Controller**: `KlivyRolesController#enforce_delegation_limit!` + `create/update` que chamam `sanitize_and_migrate`.
- **Seed**: `CustomRoles::PresetSeeder` (auto em `Account.after_create` + via `rake custom_roles:seed_presets`).
- **Sidebar / router**: gating frontend.
- **Cada policy/controller**: via `beclinic_can?(:mod, :perm)`.

## API docs (Swagger / OpenAPI) — mantém em sync ao tocar controller/policy

Klivy/Chatwoot publica especificação OpenAPI 3.0 em `swagger/swagger.json` + `swagger/plugins_swagger.json` (consumida por Swagger UI, geradores de cliente como `openapi-generator-cli`, e por integrações de terceiros que leem o contract). Os arquivos `.yml` em `swagger/paths/`, `swagger/definitions/` e `plugins/*/swagger/` são a fonte — sempre que mudar o contract de um endpoint, atualize o yml correspondente **no mesmo PR**.

**Quando atualizar:**

- Alteração em `app/controllers/api/**` ou `plugins/*/app/controllers/api/**` que muda:
  - Códigos de resposta possíveis (novo 401, 403, 422, 404...).
  - Estrutura do body de resposta (campos novos, removidos, renomeados, mudaram de tipo).
  - Estrutura do body de request (novo campo no `permit`, validação nova).
  - Authorization (qual perm é exigida — admin, Klivy `mod.action`, etc.).
- Alteração em policy (`app/policies/**`) que muda quem passa em qual action.
- Alteração em serializer/jbuilder/`json.partial!` que muda o JSON retornado.
- Visibilidade condicional de campo (ex.: campo só aparece pra admin).
- Deprecação de campo/endpoint legado.

**Onde editar:**

| Mudou… | Atualize… |
|---|---|
| Resposta de endpoint Chatwoot core | `swagger/paths/application/<resource>/<action>.yml` |
| Schema de modelo/resource Chatwoot core | `swagger/definitions/resource/<name>.yml` |
| Endpoint de plugin Klivy (ex.: `klivy_roles`, `beclinic_permissions`) | `plugins/<plugin>/swagger/paths/<resource>.yml` + `plugins/<plugin>/swagger/definitions/<Model>.yml` |
| Plugin novo sem swagger ainda | Criar `plugins/<plugin>/swagger/{paths,definitions,common.yml,index.yml}` (espelhar estrutura de `plugins/custom_roles/swagger/` ou `plugins/beclinic_core/swagger/`) |

**Checklist pre-merge quando o diff toca API:**

- [ ] Códigos de resposta no swagger refletem o controller (todos 200/201/401/403/422/404 documentados)?
- [ ] Campos novos do response aparecem no schema da resource (`swagger/definitions/resource/*.yml`)?
- [ ] Campos com visibilidade condicional (ex.: A-9 — só admin vê) têm `description` explicando a regra? (OpenAPI 3.0 não tem syntax nativa pra "condicional por role", documenta por description.)
- [ ] Authorization mudou (admin → admin || Klivy perm)? `description` reflete?
- [ ] Campo deprecated tem `deprecated: true` + nota explicando a substituição?
- [ ] Limites novos (rate, size) documentados (ex.: M-1 — 50 keys + 10KB)?
- [ ] Plugin novo? Estrutura swagger própria criada?

**Anti-patterns:**

- ❌ Atualizar o controller numa PR e o swagger em outra "depois" — depois nunca chega (audit pegou 17 arquivos defasados de uma vez, ver `CHANGELOG.md` entrada `1.6.1.28`).
- ❌ Adicionar campo no `_agent.json.jbuilder` sem atualizar `swagger/definitions/resource/agent.yml`.
- ❌ Mudar Pundit policy de admin-only pra "admin OR Klivy perm" sem refletir na `description` do swagger.

**Notas pra agentes IA/LLMs que tocam o codebase:**

Se você edita um controller ou policy em `app/controllers/api/**` ou `app/policies/**`, **sempre verifique se há swagger correspondente em `swagger/paths/application/<resource>/` e atualize no mesmo diff**. Mesma regra pra plugins (`plugins/*/swagger/`). Se não houver swagger pra esse endpoint ainda (gap conhecido), pelo menos anote no CHANGELOG ("TODO: criar swagger pra endpoint X").

## Naming — Avoid Chatwoot Core Collisions (Beclinic standard)

All custom code identifiers use the **`Beclinic` / `beclinic_`** standard. This matches the existing engine `BeclinicCore`, table prefixes (`beclinic_profiles`, `beclinic_preset_roles`), and column prefixes (`beclinic_role`).

Legacy identifiers that still carry the brand name (e.g. `KlivyMailer`, `klivy_mailer.html.erb`) are not a pattern to extend — treat them as tech debt. Do not introduce new `Klivy`-named code; if you touch one of those files for an unrelated reason, leave the rename out of scope unless explicitly requested.

Concrete rules for new custom code:

- **Ruby modules/classes**:
  - Foundation/shared code lives under `BeclinicCore::*` (e.g. `BeclinicCore::AccountSetup`, `BeclinicCore::AccountProfile`).
  - Domain plugins keep their own top-level engine namespace matching the plugin folder (`Patients::*`, `Agenda::*`, `Billing::*`, `Financial::*`). Inside a plugin, scope further as needed (e.g. `Patients::Registration::Service`).
  - **Financial module v2** (canon [`docs/01-product/modules/financeiro-funcionamento.md`](docs/01-product/modules/financeiro-funcionamento.md)): all new code MUST use `Financial::*` namespace with tables `financial_*`. Inherit from `Financial::ApplicationRecord` (gives `SoftDeletable`, `Auditable`, `Stamped`, `MoneyAttribute` for free). Money values stored as `BIGINT` cents — never decimal/float. Idempotency via `Financial::IdempotentAction` concern + header `Idempotency-Key`. Payment gateway access via `Financial::Gateways.adapter_for(account)` (Manual or Asaas). Legacy v1 models (`Transaction`, `AccountTransaction`, `Installment` global, `FinancialEstimate`) **foram removidos em 2026-05-11** (Fase A da depreciação); tabelas v1 (`transactions`, `account_transactions`, `installments`, `financial_estimates`) ainda existem no banco mas serão dropadas em Fase B. See [CHANGELOG 1.6.0.1](CHANGELOG.md#16012026-05-07T220000-0300) for the full rewrite rationale.
  - Never define a top-level constant that could shadow a Chatwoot OSS or Enterprise constant — when in doubt, wrap under the engine namespace.
- **Controllers/routes**: keep new endpoints under their plugin engine's namespace (`Patients::Api::V1::*`, `Agenda::Api::V1::*`) or a dedicated `Beclinic`-scoped namespace for cross-plugin admin (`BeclinicAdmin::*` is already in use — see `spec/plugins/beclinic_core/controllers/beclinic_admin/`). Avoid attaching new routes directly to `Api::V1::Accounts::*` unless extending an existing Chatwoot resource.
- **Database tables**: prefix custom tables with `beclinic_` only when they belong to `BeclinicCore` (e.g. `beclinic_profiles`, `beclinic_preset_roles`). Plugin-owned tables follow the plugin name (`patients`, `agenda_settings`, `billing_invoices`, etc.) — match the engine that owns them.
- **Columns added to Chatwoot core tables**: prefix with `beclinic_` to mark them as ours (e.g. `beclinic_role` on `teams`). Never repurpose an existing Chatwoot column.
- **Vue components**: prefix with `Beclinic` (e.g. `BeclinicPatientForm.vue`, `BeclinicAgendaSlot.vue`) when the component is generic/shared. Plugin-scoped components live under that plugin's frontend folder (`plugins/patients/frontend/...`) and may use the plugin name as prefix (`PatientRecord.vue`).
- **JS/TS modules and composables**: prefix shared utilities with `beclinic` / `useBeclinic` (e.g. `beclinicDateMask.js`, `useBeclinicAgenda.js`). Plugin-scoped utilities can use the plugin name.
- **i18n keys**: nest custom strings under a `BECLINIC.*` root in `en.json` / `en.yml` to keep them separate from upstream Chatwoot keys.
- **CSS classes / design tokens**: prefix utility classes with `bcl-`. Brand color tokens stay as the existing `--brand*` set in `tailwind.config.js` (these are brand-neutral semantic tokens, not code-identifier).
- **Pre-creation check**: before naming a new file/class/route/table/column/i18n key, run a search across `app/`, `enterprise/`, and `plugins/` (e.g. `rg -n "ClassName|table_name|route_path"`) to confirm no upstream or sibling-plugin identifier already uses the name. If a collision exists, namespace it under `Beclinic` (or the owning plugin engine) instead of overloading the existing one.
- **Renames**: never rename a Chatwoot core identifier to avoid a collision — namespace the new Beclinic code instead.

## Plugin Styles (SCSS por padrão)

A seção "Styling — Tailwind Only" da base Chatwoot acima continua valendo para componentes pequenos do core (botões, layouts genéricos). **Para plugins Beclinic com domínios complexos** (prontuário, dashboard financeiro, agenda) que precisam de classes semânticas, overrides dual-theme (`rgb(var(--slate-N))`) e variantes BEM, o padrão é **SCSS modular** seguindo a estrutura adotada em [plugins/patients/frontend/styles/](plugins/patients/frontend/styles/) (versão de referência).

**Padrão para arquivos de estilo novos em plugin:**

- Nunca criar `.css` puro em `plugins/<engine>/frontend/`. Sempre `.scss`.
- Estrutura recomendada (espelha [plugins/patients/frontend/styles/](plugins/patients/frontend/styles/)):
  ```
  plugins/<engine>/frontend/styles/
    _variables.scss        # tokens hardcoded compartilhados ($brand-*, $whatsapp-green, etc.)
    <entry>.scss           # entry com @use de cada partial em ordem de cascata
    <entry>/
      _layout.scss
      _<dominio>.scss      # um partial por domínio/tab/feature
      ...
  ```
- Tokens hardcoded usados em **3+ ocorrências** devem virar variável em `_variables.scss`. Cores únicas/raras ficam inline.
- Cada partial declara `@use "../variables" as *;` no topo se usar tokens.
- Custom properties (`rgb(var(--slate-N))`) continuam sendo a fonte da verdade do dual-theme — variáveis SCSS são apenas atalhos para cores hardcoded semânticas.
- `<style scoped>` em `.vue` só para regras locais ao próprio arquivo (wrapper raiz, modifiers, `@media print`). Estilos compartilhados entre componente pai + filhos extraídos vão no `.scss` global do plugin.

**Quando Tailwind utility ainda é a melhor escolha:**

- Componentes pequenos isolados sem repetição de padrão (botão único, espaçamento ad-hoc).
- Layouts genéricos de página (`grid grid-cols-X gap-Y`).
- Estados simples com `class="..."` direto no template.

**Quando SCSS modular é a melhor escolha (override do "Tailwind Only"):**

- Mais de ~5 classes semânticas relacionadas (ex: `.fin-kpi-card`, `.fin-kpi-card--green`, `.fin-kpi-icon`, `.fin-kpi-label`, `.fin-kpi-value`).
- Necessidade de override dual-theme com `!important` em token específico.
- Variantes BEM com mais de 2-3 modifiers.
- Animações `@keyframes` reutilizadas entre componentes.
- `@media print`/`@media (max-width)` afetando múltiplos elementos do plugin.

**Plugins legacy** ([plugins/financial](plugins/financial/), [plugins/agenda](plugins/agenda/), [plugins/migration](plugins/migration/), [plugins/ajuda](plugins/ajuda/)) ainda têm `.css` puro — não migrar oportunisticamente, só quando o arquivo for tocado por outro motivo de tamanho equivalente. **Para código novo nesses plugins, ainda assim usar `.scss`** com a estrutura acima.

**Sem `<style scoped>` novo em `.vue` de plugin** — extrair para partial em `styles/<area>/_<componente>.scss`, importar via `@use` no entry do plugin (ex.: [plugins/patients/frontend/styles/tabs.scss](plugins/patients/frontend/styles/tabs.scss) carrega 10 partials de tabs do prontuário). `<style scoped>` só para wrapper raiz / modifiers / `@media print` que afetam exclusivamente o template do próprio arquivo.

Uma checagem `pre-commit` bloqueia adição de novos `.css` em `plugins/` (whitelist dos legacy existentes). Para bypassar em caso excepcional, justificar no PR — não usar `--no-verify` silenciosamente.

## CHANGELOG.md (Mandatory)

Every functional change (feat, fix, refactor with visible impact, behavior change) **must** add an entry to `CHANGELOG.md` before commit, following the pattern already established in the file:

- **Version `1.B.C.D`**: increment `D` for a bug/minor change; when `D` reaches 10, increment `C` and reset `D`; bump `B` only when a full module/project is completed.
- **ISO timestamp** with `-03:00` timezone in the entry header: `## [1.B.C.D] - YYYY-MM-DDTHH:MM:SS-03:00`.
- **Descriptive title** on the next line, as `###`.
- **Expected sections** when applicable: `**Problema:**`, `**Solução:**` (numbered if multiple fronts), and always at the end **`**Arquivos Modificados:**`** listing every touched file (relative path).
- Purely cosmetic changes (style, chore, manifest tweaks, asset rebuilds) **do not** require an entry — align with the recent `style:` / `chore:` commits in history.
- Add the entry at the **top** of the file, right below the "Estrutura de Versão" block.
