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

## Naming — Avoid Chatwoot Core Collisions (Beclinic standard)

All custom code identifiers use the **`Beclinic` / `beclinic_`** standard. This matches the existing engine `BeclinicCore`, table prefixes (`beclinic_profiles`, `beclinic_preset_roles`), and column prefixes (`beclinic_role`).

Legacy identifiers that still carry the brand name (e.g. `KlivyMailer`, `klivy_mailer.html.erb`) are not a pattern to extend — treat them as tech debt. Do not introduce new `Klivy`-named code; if you touch one of those files for an unrelated reason, leave the rename out of scope unless explicitly requested.

Concrete rules for new custom code:

- **Ruby modules/classes**:
  - Foundation/shared code lives under `BeclinicCore::*` (e.g. `BeclinicCore::AccountSetup`, `BeclinicCore::AccountProfile`).
  - Domain plugins keep their own top-level engine namespace matching the plugin folder (`Patients::*`, `Agenda::*`, `Billing::*`, `Financial::*`). Inside a plugin, scope further as needed (e.g. `Patients::Registration::Service`).
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

## CHANGELOG.md (Mandatory)

Every functional change (feat, fix, refactor with visible impact, behavior change) **must** add an entry to `CHANGELOG.md` before commit, following the pattern already established in the file:

- **Version `1.B.C.D`**: increment `D` for a bug/minor change; when `D` reaches 10, increment `C` and reset `D`; bump `B` only when a full module/project is completed.
- **ISO timestamp** with `-03:00` timezone in the entry header: `## [1.B.C.D] - YYYY-MM-DDTHH:MM:SS-03:00`.
- **Descriptive title** on the next line, as `###`.
- **Expected sections** when applicable: `**Problema:**`, `**Solução:**` (numbered if multiple fronts), and always at the end **`**Arquivos Modificados:**`** listing every touched file (relative path).
- Purely cosmetic changes (style, chore, manifest tweaks, asset rebuilds) **do not** require an entry — align with the recent `style:` / `chore:` commits in history.
- Add the entry at the **top** of the file, right below the "Estrutura de Versão" block.
