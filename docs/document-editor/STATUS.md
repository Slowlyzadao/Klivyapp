# Document Editor — STATUS do projeto

> **Documento vivo.** Atualizado a cada sessão de trabalho. Use como ponto de verdade entre conversas: o que foi feito, o que está em andamento, o que parou pela metade, o que ficou pra depois.

**Última atualização**: 2026-05-28 (sessão 12 — **FASE 5 (PARTE 2 — sem HTTP Clicksign)** — wire-up dos botões "Enviar pra Assinatura" no DocumentsTab + ConsentsTab do paciente; `DownloadSignedPdfJob` genérico (agnostic de provider) conectado ao webhook controller. **72 RSpec verdes** (49 document_templates + 23 signatures). Clicksign HTTP real adiado a pedido do user pra "MUITO pra frente" — sistema funcional via MockProvider.)

---

## 0. Princípios de arquitetura (não negociáveis)

Esses princípios valem pra tudo nesse projeto. Não pode quebrar nem "só dessa vez".

1. **Arquitetura limpa, igual aos plugins existentes** (`telemed`, `patient_portal`, `patients`, `agenda`, `financial`).
   - Plugin novo isolado em `plugins/document_templates/`.
   - Engine Rails **sem** `isolate_namespace` (padrão Klivy — models no namespace global).
2. **Separação rígida por linguagem**:
   - CSS/SCSS → `.scss` (entry + partials em `styles/`, nunca inline)
   - Ruby → `.rb` (controllers, models, services, jobs em arquivos separados)
   - JS → `.js` (sem JS em template Vue ou misturado em outros arquivos)
   - Vue → `.vue` com `<script setup>` curto, lógica pesada extraída pra composables `.js`
3. **Sem "arquivos deuses"**. Arquivos pequenos, foco único, fácil manutenção.
   - Regra prática: se um `.vue` passa de ~200 linhas ou um service de ~150, quebrar em partes.
4. **Componentes reutilizáveis**. Botão, modal, card, input, badge, etc. — criados uma vez, usados em todo lugar.
   - Reusar `app/javascript/dashboard/components-next/` (Button, Modal, Icon, etc.) sempre que possível.
   - Só criar componente novo se não existir equivalente.
5. **Padrão de design consistente** com o resto do app.
   - Tokens SCSS de `plugins/patients/frontend/styles/_variables.scss` (cores, espaçamentos).
   - Dark mode via `rgb(var(--slate-N))`.
   - Lucide icons (`i-lucide-*`).

---

## 1. Visão geral da feature

**O que é**: nova aba **Documentos** no sidebar, com editor visual TipTap (estilo Google Docs), variáveis dinâmicas (`{{patient.full_name}}` vira chip), biblioteca Klivy de templates prontos, geração de PDF via Grover (Chromium headless). Os templates alimentam as áreas de Documentos e Consentimentos que já existem dentro de Pacientes.

**Documentação do plano**: 10 docs em `docs/document-editor/01-...` a `10-...md`. Ler [`README.md`](README.md) primeiro.

---

## 2. Stack confirmado (auditoria 2026-05-27)

| Camada | Tecnologia | Versão | Status |
|---|---|---|---|
| Backend | Rails Engine plugin | — | A criar |
| PDF | gem `grover` (Chromium headless) | ~> 2.0 | **Não instalado** |
| Validação JSON | manual ou `json-schema` | — | A definir |
| Frontend | Vue | 3.5.12 | ✅ Instalado |
| Store | **Pinia** 3.0.4 (decisão: usar Pinia, não Vuex, pra feature nova) | 3.0.4 | ✅ Instalado |
| Editor | TipTap 2 (`@tiptap/vue-3` + extensões) | ~> 2.5 | **Não instalado** |
| Popup variáveis | tippy.js | ~> 6.3 | **Não instalado** |
| PDF legado | gem `prawn` + `prawn-table` | — | ✅ Instalado (mantido como fallback) |

---

## 3. Decisões arquiteturais consolidadas (sessão 2026-05-27)

### 3.1 Store
- **Pinia** pra feature nova (não Vuex). Justificativa: Pinia já existe no projeto (3.0.4), é padrão moderno Vue 3, melhor DX.

### 3.2 Campos faltantes em User/Account
- Usar **`custom_attributes` JSONB** (não criar colunas dedicadas).
- Variáveis tipo `clinic.cnpj`, `professional.council_number` lêem de hash com fallback gracioso quando vazio.
- Zero migration adicional em `users` / `accounts`.

### 3.3 Ritmo
- **Sequencial**: Fase 0 → 1 → 2 → 3 → 4. Sem pular fase, sem PR gigante.

### 3.4 Ajustes do plano original (após auditoria do schema real)
| Plano original | Realidade | Ajuste |
|---|---|---|
| `Document.document_type` enum integer (0-10) | É **string** ('receita', 'atestado'...) | Usar string no `DocumentTemplate` também |
| `Patient.birth_date` | É `birthdate` | Catálogo de variáveis usa `patient.birthdate` |
| `Patient.address_*` colunas | É JSONB `address` | Resolver lê do hash |
| `Patient.responsible_*` | É JSONB `guardian` + `has_guardian` boolean | Resolver lê de `guardian` JSON |
| `User.council_number/specialty` colunas | ❌ Não existem | Lê de `user.custom_attributes` |
| `Account.cnpj/address` colunas | ❌ Não existem | Lê de `account.custom_attributes` e/ou `account.settings` |
| `ConsentRecord.pdf_hash` (novo) | Já existe `integrity_hash` | Reusar `integrity_hash` (não duplicar) |

---

## 4. Auditoria do código existente (achados 2026-05-27)

### Schemas reais (db/schema.rb)
- **patients**: `name`, `phone`, `email`, `cpf`, `rg`, `birthdate`, `sex`, `social_name`, `marital_status`, JSONB (`address`, `contacts`, `emergency_contact`, `insurance`, `billing_info`, `lgpd_consent`, `guardian`), `has_guardian`, `responsible_professional_id`
- **users**: `name`, `display_name`, `email`, `availability`, JSONB (`ui_settings`, `custom_attributes`), `message_signature`. **Sem** colunas de conselho/especialidade.
- **accounts**: `name`, `domain`, `support_email`, JSONB (`limits`, `custom_attributes`, `internal_attributes`, `settings`). **Sem** colunas dedicadas pra CNPJ/endereço.
- **documents**: `patient_id`, `account_id`, `generated_by_id`, `form_template_id`, `document_type` (**string**), `status`, `title`, `version`, `is_generated`, `variables` JSONB, `file_name`, `mime_type`, `file_size`, `sent_at`, `signed_at`, `signed_by_id`, `deleted_at`. **Faltam** (a adicionar via migration): `document_template_id`, `rendered_html`, `pdf_hash`.
- **consent_records**: `patient_id`, `account_id`, `form_template_id`, `title`, `status`, `mode`, `signature_blob`, `integrity_hash`, `ip_address`, `device_info`, `signed_at`, `expires_after_days`, `expires_at`, `remote_token`, `body` (TEXT), `document_type` (string), `observations`. **Faltam** (a adicionar via migration): `document_template_id`, `rendered_html`.

### Plugin pattern (referência: `plugins/telemed/`)
- `lib/<plugin>.rb` (entry, require do engine)
- `lib/<plugin>/engine.rb` — **sem** `isolate_namespace`, só `to_prepare` pra injetar associações no core
- `config/routes.rb` — `<Plugin>::Engine.routes.draw do ... end`
- `app/models/`, `app/controllers/`, `app/services/`, `app/jobs/`, `app/policies/` — autoloadados pelo Rails
- `frontend/` — Vue + SCSS modular (estrutura igual `plugins/patients/frontend/`)
- Auto-carregamento em `config/application.rb:59`: `Dir[Rails.root.join('plugins/*/lib/*/engine.rb')].each { |f| require f }`
- Mount em `config/routes.rb` raiz: `mount <Plugin>::Engine, at: '/'`

### Vite alias relevante
- `@plugins` → `./plugins/` (definido em `vite.config.ts:110`)

### Sidebar
- Arquivo: `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
- Entrada vai entre **Teleconsulta** (linha ~596) e **Patients** (linha ~602)
- Precisa registrar em `SIDEBAR_NAME_TO_MODULE` (linha ~230) — provável módulo: `'patients'` (ou criar `'documents'` se permissão for separada)
- i18n keys vivem em `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` (chave `SIDEBAR.*` está espalhada — verificar qual arquivo)

### PDF generators existentes (a integrar, não duplicar)
- `plugins/patients/app/services/patients/pdf_generator.rb` (central — **modificar** na Fase 3)
- `record_pdf_generator.rb`, `treatment_plan_pdf_generator.rb`, `anamnesis_pdf_generator.rb` (intocados)

---

## 5. Roadmap por fases

| Fase | Status | Notas |
|---|---|---|
| **0** — Preparação | ✅ Concluída | Gemfile + package.json + plugin boilerplate + sidebar stub + Grover PDF smoke test |
| **1** — Fundação (MVP base) — backend | ✅ Concluída | 4 migrations, 2 models + concern, engine to_prepare, catálogo (55 vars), formatters, readers, resolver, 3 controllers, 2 serializers, 2 policies, routes |
| **1** — Fundação — frontend | ✅ Concluída | 3 API clients, Pinia store, composable de variáveis, 7 componentes de lista, 3 modais, 6 componentes de editor TipTap + extensão + suggestion + node view, 11 SCSS partials, i18n PT/EN expandido, 2 rotas Vue, **vite build OK** |
| **2** — Catálogo Klivy | ✅ Concluída | DSL Builder + 10 clínicos + 12 consentimentos = **22 templates Klivy globais** seedados. LibrarySeeder idempotente (re-run skipped=22). Rake task `document_templates:seed_klivy_library` + `:list_klivy`. E2E validado: Atestado Klivy → clone pra account → PDF 44KB salvo. |
| **3** — Integração paciente | ✅ Concluída | Renderer (JSON→HTML), layout ERB, PdfGenerator (Grover), integração Patients::PdfGenerator (delega quando template_id presente, senão Prawn legado), modal com dropdown "Modelo". E2E validado: template→render→Grover→Document salvo com pdf_hash, rendered_html, file PDF anexado |
| **4** — Polimento + QA | ✅ Concluída | Dockerfile com chromium+fontes+libs · menu ⋮ (Duplicar/Arquivar/Reativar/Excluir) · autosave com retry exponencial (2s/5s/10s) + botão "Tentar novamente" + dirty guard (beforeRouteLeave + beforeunload) · atalhos Cmd+S e Cmd+/ · lazy-load do editor (chunk 409KB separado) · dark mode WYSIWYG (paper sempre branco + chip com cores fixas) · sanitização anti-XSS de links (rejeita javascript:/data:) · **49 RSpec verdes** (model, Catalog, Renderer) |
| 5 — Clicksign (parte 1: fundação) | ✅ Concluída | Plugin `signatures/` novo. Model `SignatureRequest` polimórfico (signable: Document/ConsentRecord) com máquina de estados 8 status (pending→sent→viewed→signed→completed + cancelled/failed/expired). Provider abstract + MockProvider (dev/test) + skeleton ClicksignProvider (TODO próxima sessão: HTTP real). Creator, controller (CRUD + cancel/resend/refresh_status), webhook receiver com validação HMAC, UI completa (modal + status card). 23 RSpec verdes. |
| 5 — Signatures (parte 2: UI + job) | ✅ Concluída | Botão "Enviar pra Assinatura" no `DocumentsTable.vue` (ícone pen-line) + handler/modal no `DocumentsTab.vue`. Botão "Assinatura digital" no `ConsentsTable.vue` (apenas pra consents pendentes) + handler/modal no `ConsentsTab.vue` com pre-fill do paciente. `DownloadSignedPdfJob` genérico (qualquer provider que implemente `download_signed_pdf` funciona) conectado ao webhook quando recebe `envelope.completed` — baixa PDF, calcula SHA-256, substitui file attachment, marca completed. Idempotente. Broadcast ActionCable pro frontend. |
| 5 — Clicksign HTTP real | ⏸️ Adiado | A pedido do user — "MUITO pra frente". Skeleton `ClicksignProvider` mantido com 5 métodos `NotImplementedError` e TODOs apontando docs Clicksign v3. Sistema funcional via `MockProvider` em dev. |
| 6+ — IA (geração/LGPD review/autofill) | ⚪ Futuro | Reusa client Anthropic do telemed |

**Legenda**: ✅ Concluída · 🟡 Em andamento · 🔴 Bloqueada · ⚪ Pendente · ⏸️ Parada (com motivo)

---

## 6. Fase 0 — Preparação

**Objetivo**: instalar dependências e criar boilerplate sem nada visível pro usuário final.

### Tarefas

- [x] Adicionar gem `grover` ao Gemfile *(linhas 217-220, com comentário explicativo)*
- [x] Adicionar dependências TipTap + tippy.js ao `package.json` *(15 pacotes `@tiptap/*` em ordem alfabética + `tippy.js`)*
- [x] Criar estrutura `plugins/document_templates/`:
  - [x] `lib/document_templates.rb` (entry, só require do engine)
  - [x] `lib/document_templates/engine.rb` (Rails::Engine, sem isolate_namespace — padrão Klivy)
  - [x] `config/routes.rb` (esqueleto pronto com namespace `/api/v1/accounts/:id/`, rotas reais comentadas pra Fase 1)
  - [x] `app/models/`, `app/controllers/api/v1/accounts/`, `app/services/document_templates/`, `app/jobs/document_templates/`, `app/policies/`, `app/serializers/` (todos com `.keep`)
  - [x] `frontend/` completo: `routes/documents/`, `components/{index,editor/extensions,modals}/`, `composables/`, `stores/`, `api/`, `styles/{index,editor,modals}/`, `i18n/`
- [x] Adicionar `mount DocumentTemplates::Engine, at: '/'` em `config/routes.rb` raiz *(linha 19, após telemed)*
- [x] Adicionar entrada "Documentos" no `Sidebar.vue` *(após Patients — alimenta área do paciente, ícone `i-lucide-file-text`)*
- [x] Adicionar `Documents: 'patients'` em `SIDEBAR_NAME_TO_MODULE` *(reusa permissão patients — Fase 1 pode separar)*
- [x] Adicionar i18n keys: `SIDEBAR.DOCUMENTS` em pt_BR/en `settings.json` + namespace `DOCUMENT_TEMPLATES.*` em `plugins/document_templates/frontend/i18n/{pt_BR,en}.json`
- [x] Registrar i18n do plugin em `app/javascript/dashboard/i18n/locale/{pt_BR,en}/index.js`
- [x] Criar rota stub `documents_dashboard_index` com componente `DocumentsIndex.vue` mostrando `EmptyPlaceholder` "Em construção"
- [x] Registrar rota no `dashboard.routes.js`
- [x] SCSS modular: `document-templates.scss` (entry), `_variables.scss` (tokens locais), `index/_index.scss`, `index/_empty-placeholder.scss`
- [x] Sintaxe validada: `ruby -c` em todos os `.rb`, JSON válido em todos os i18n
- [x] `bundle install` rodado — **gem `grover 1.2.10` instalada** (versão `~> 2.0` do plano não existia; ajustado pra `~> 1.2` no Gemfile)
- [x] `pnpm install` rodado — TipTap 2.27.2 (15 pacotes) + tippy.js 6.3.7 instalados
- [x] **Puppeteer adicionado ao `package.json`** (`^23.10.4` → instalou 23.11.1) — Grover depende dele
- [x] **Chromium baixado localmente** via `node node_modules/puppeteer/install.mjs` → `~/.cache/puppeteer/chrome/mac_arm-131.0.6778.204` (post-install do pnpm é skipped por default — precisou rodar manual)
- [x] **Smoke test backend OK**:
  - `DocumentTemplates::Engine` carrega no boot do Rails ✅
  - `Grover::VERSION` retorna `"1.2.10"` ✅
  - **Grover gerou PDF real**: 8055 bytes, `PDF document, version 1.4, 1 pages` em `/tmp/grover_smoke_test.pdf` ✅
- [ ] **PENDENTE — Smoke test frontend** (precisa user rodar e abrir no browser):
  - `overmind start` ou `bin/vite dev` + `bin/rails s` em terminais separados
  - Abrir `/app/accounts/<id>/documents` → deve ver placeholder "Editor de documentos em construção"
- [ ] **PENDENTE — Dockerfile/Coolify** (não bloqueia Fase 1, bloqueia Fase 3 em prod):
  - Adicionar `chromium` + `fonts-freefont-ttf`, `fonts-liberation`, libs (libnss3, libatk-bridge2.0-0, etc.)
  - ENV: `PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true` + `PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium`

### Em andamento agora
- _(nada — Fase 0 100% concluída no backend; só falta user fazer smoke visual do frontend se quiser)_

### Bloqueios / aberto
- **Frontend smoke test visual**: requer servidor dev rodando (eu não navego no browser).
- **Chromium em produção (Dockerfile)**: pendente, prazo até Fase 3.
- **Decisão futura (Fase 1)**: ao adicionar permissão `documents` separada, atualizar `SIDEBAR_NAME_TO_MODULE` (hoje reusa `patients`).
- **Warning ambiental** (não-crítico): node 25.7.0 instalado mas pnpm avisa que prefere 24.x; puppeteer 23.11.1 marcado como "deprecated < 24.15.0". Funciona, mas considerar upgrade depois.

---

## 7. Fase 1 — Backend ✅ concluído

### Migrations rodadas (timestamp 20260527000001..04)
- `CreateDocumentTemplateFolders` — pasta organizadora (suporta hierarquia, MVP usa só raiz)
- `CreateDocumentTemplates` — tabela central (account NULL = Klivy global; document_type string)
- `AddTemplateRefToDocuments` — adicionou `document_template_id`, `rendered_html`, `pdf_hash`
- `AddTemplateRefToConsentRecords` — adicionou `document_template_id`, `rendered_html` (reusa `integrity_hash` existente)

### Models
- `DocumentTemplate` — 22 tipos clínicos+consentimento, source (klivy/clinic/cloned), validação de imutabilidade do content_json (sem `<script>`/`<iframe>`, max 500KB), bump_version só em update, sync archived_at automático
- `DocumentTemplateFolder` — hierarquia opcional, validação cross-account
- `DocumentTemplateExtension` (concern) — injetado em `Document` e `ConsentRecord` via `engine.to_prepare`. Adiciona FK + scopes `from_template`/`legacy_pdf` + helper `generated_from_template?` + validação `rendered_html_immutability` em update

### Catálogo de variáveis (55 totais, 4 categorias)
- `DocumentTemplates::Variable` (struct)
- `Variables::PatientDefinitions::LIST` (23 vars) — adaptado pra schema real (`birthdate`, JSONB address/guardian)
- `Variables::ClinicDefinitions::LIST` (12 vars) — lê de `custom_attributes` + `settings`
- `Variables::ProfessionalDefinitions::LIST` (9 vars) — lê de `user.custom_attributes`
- `Variables::DateDefinitions::LIST` (11 vars) — usa I18n pt_BR
- `Catalog` (módulo singleton) — `all`, `find(key)`, `for_frontend`, `grouped_for_frontend`, lazy-load

### Resolver + Formatters
- `Formatters` (módulo) — CPF, CNPJ, phone, CEP, date_short, date_long, age, currency, uppercase, image_tag. Defensivo: blank → blank, tipo errado → valor original
- `Readers::PatientReader`, `ClinicReader`, `ProfessionalReader`, `DateReader` (cada um em arquivo próprio — sem arquivo deus)
- `Resolver` — orquestra catalog + reader + formatter. API: `resolve(key, fallback: nil)` e `resolve_all`. Fallback global `'_______'`, override via atributo do template

### Controllers + Serializers + Policies + Routes
- `DocumentTemplatesController` — index (filtros: document_type, folder_id, family, include_archived, only), show, create, update, destroy (soft archive), duplicate, clone_to_account, archive, unarchive, variables, klivy_library
- `DocumentTemplateFoldersController` — CRUD básico
- `DocumentTemplateSerializer` — compact (sem content_json) + full (com content)
- `DocumentTemplateFolderSerializer` — inclui templates_count
- `DocumentTemplatePolicy` — admin escreve, agent lê; Klivy é read-only; Scope filtra `for_account`
- `DocumentTemplateFolderPolicy` — mesma lógica
- 19 routes registradas (validado com `bin/rails routes`)

### Smoke tests passados
- 4 migrations rodaram limpas
- `Catalog.all.size == 55`, 4 categorias
- Resolver: CPF formatado, idade calculada, datas em pt_BR, fallback
- Model: criação, validação de document_type inválido, bump_version (v=1 no create, v=2 no update), serializer compacto + full
- Policy: index/show/update true pra admin

## 8. Fase 1 — Frontend ✅ concluído

### API clients (3)
- `frontend/api/documentTemplates.js` — list, klivyLibrary, show, create, update, destroy, duplicate, cloneToAccount, archive, unarchive
- `frontend/api/documentTemplateFolders.js` — CRUD
- `frontend/api/documentTemplateVariables.js` — fetch catálogo

### Pinia store + composable
- `frontend/stores/documentTemplates.js` — gerencia templates/klivy/folders/variables com loading flags individuais. Actions assíncronas com error propagation, cache do catálogo de variáveis.
- `frontend/composables/useVariableCatalog.js` — wrapper ergonômico com search, agrupamento por categoria, autoload no mount.

### Componentes da lista (`components/index/`)
- `DocumentsHeader.vue` — busca + filtro de tipo + botões "Biblioteca Klivy" e "Novo template"
- `FolderSidebar.vue` + `FolderItem.vue` — sidebar interno com lista de pastas
- `TemplateCard.vue` — card reutilizável (variant: 'owned' | 'klivy'), badges de source, menu ⋮
- `TemplateGrid.vue` — grid responsivo + estado vazio + loading
- `KlivyLibrarySection.vue` — seção horizontal de modelos Klivy no topo
- `EmptyPlaceholder.vue` — componente reutilizável de estado vazio

### Modais (`components/modals/`)
- `BaseModal.vue` — shell de modal próprio (backdrop + ESC + Teleport, 15 linhas)
- `NewFolderModal.vue` — formulário de nova pasta
- `NewTemplateModal.vue` — nome + tipo + pasta opcional; cria com content_json vazio + abre editor

### Editor TipTap (`components/editor/`)
- `TipTapEditor.vue` — wrapper do `@tiptap/vue-3` com StarterKit + 11 extensões (Underline, TextAlign, TextStyle, Color, FontFamily, Link, Table, TableRow, TableCell, TableHeader, Placeholder, CharacterCount) + extensão custom de variável + suggestion. Expõe `insertVariable()` via `defineExpose`.
- `EditorToolbar.vue` + `EditorToolbarButton.vue` — 6 grupos (histórico, formatação inline, headings, listas, alinhamento, inserções). Estado active sincronizado com TipTap.
- `EditorSidebar.vue` — abas "Configurações" (nome, tipo, pasta, papel, orientação) e "Variáveis" (catálogo com busca, click insere)
- `PaperContainer.vue` — canvas A4 simulado com tamanhos/orientações
- `VariableNodeView.vue` — chip não-editável renderizado no editor (ícone + label)
- `VariablePickerMenu.vue` — menu de variáveis com busca + navegação por teclado, usado tanto na sidebar quanto no popover "/"
- `extensions/VariableExtension.js` — Node TipTap `variable` (atom inline, atributos key/label/fallback/format)
- `extensions/VariableSuggestion.js` — config do suggestion ("/" trigger + tippy popup + insert command)
- `extensions/VariableSuggestionExtension.js` — Extension TipTap que registra o Suggestion como ProseMirror plugin

### Rotas + i18n
- `routes/routes.js` — 2 rotas: `documents_dashboard_index` (todos), `documents_dashboard_edit` (só admin)
- `i18n/pt_BR.json` + `i18n/en.json` — namespace `DOCUMENT_TEMPLATES.*` com ~50 strings

### SCSS (11 partials + entry + variables)
- `_variables.scss` (tokens locais), `document-templates.scss` (entry)
- index/: `_index`, `_empty-placeholder`, `_documents-header`, `_folder-sidebar`, `_folder-item`, `_template-card`, `_template-grid`, `_klivy-library-section`
- editor/: `_editor`, `_toolbar`, `_variable-node`, `_paper-container`, `_picker-menu`, `_sidebar`, `_editor-page`
- modals/: `_base-modal`, `_form-stack`

### Validação
- `bin/vite build` passou: ✓ built in 35.56s, 4062 módulos transformados, 57 referências aos arquivos do plugin
- TipTap + 15 extensões + suggestion + tippy.js + puppeteer todos resolvidos no bundle
- Adicionado `@tiptap/core` ao package.json (era peer-dep que pnpm não resolvia transitivamente)

---

## 8. Histórico de sessões

### 2026-05-27 — Sessão inicial (parte 1)
- ✅ Lidos os 10 documentos do plano
- ✅ Auditoria do schema real e stack (Vue 3.5.12, Pinia 3.0.4, Vuex 4.1, Prawn instalado, **Grover ausente**, **TipTap ausente**)
- ✅ Decisões: Pinia / custom_attributes JSONB / sequencial
- ✅ Mapeamento divergências entre plano e schema real
- ✅ Padrão de plugin Klivy identificado (`plugins/telemed/` como referência)
- ✅ Criado este STATUS.md + memórias persistentes (`feedback-clean-architecture`, `project-document-editor`)

### 2026-05-27 — Sessão inicial (parte 2)
- ✅ Fase 0 boilerplate completo (ver seção 6)
- ✅ Arquivos criados (16 novos):
  - `plugins/document_templates/lib/document_templates.rb`
  - `plugins/document_templates/lib/document_templates/engine.rb`
  - `plugins/document_templates/config/routes.rb`
  - `plugins/document_templates/frontend/routes/routes.js`
  - `plugins/document_templates/frontend/routes/documents/DocumentsIndex.vue`
  - `plugins/document_templates/frontend/components/index/EmptyPlaceholder.vue`
  - `plugins/document_templates/frontend/i18n/{pt_BR,en}.json`
  - `plugins/document_templates/frontend/styles/document-templates.scss`
  - `plugins/document_templates/frontend/styles/_variables.scss`
  - `plugins/document_templates/frontend/styles/index/_index.scss`
  - `plugins/document_templates/frontend/styles/index/_empty-placeholder.scss`
  - 15 `.keep` em pastas vazias
- ✅ Arquivos editados (6):
  - `Gemfile` (+gem grover)
  - `package.json` (+15 pkgs TipTap + tippy.js)
  - `config/routes.rb` (mount engine)
  - `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` (import + spread)
  - `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` (item + mapping)
  - `app/javascript/dashboard/i18n/locale/pt_BR/index.js` + `en/index.js` (registra i18n do plugin)
  - `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` + `en/settings.json` (`SIDEBAR.DOCUMENTS`)
- ✅ Sintaxe validada (ruby -c + JSON parse)

### 2026-05-28 — Sessão 12 — Fase 5 parte 2 (sem HTTP Clicksign)
- 🐛 **Bug ambiental do servidor** (similar à sessão 6): puma rodando desde sessão 7 não conhecia `Signatures::Engine`. Foreman não conseguia subir por causa do livekit/livekit-egress (porta UDP 7882 + container Docker zumbi). Resolução: matar todos os processos (foreman, sidekiq, livekit, whatsapp, vite, docker container `klivy-livekit-egress`) e subir `bin/rails server` direto sem foreman. Documentado em STATUS pra próximas vezes.
- ✅ **Wire-up `DocumentsTab.vue`** (cliente):
  - `DocumentsTable.vue` ganhou emit `sign` + botão Pen-line (azul) ao lado do WhatsApp.
  - `DocumentsTab.vue` importa `SendForSignatureModal`, mantém ref `signingDoc`, handler `openSignModal`, modal renderiza com `signable-type="Document"`.
  - i18n PT/EN: `PATIENT_DOCUMENTS.TABLE.SIGN_TITLE`.
- ✅ **Wire-up `ConsentsTab.vue`** (cliente):
  - `ConsentsTable.vue` ganhou emit `send-for-signature` + botão "Assinatura digital" só pra consents `pendente` (paralelo ao SignatureModal local existente).
  - `ConsentsTab.vue` importa `SendForSignatureModal`, ref `remoteSigningConsent`, handler `openRemoteSignModal`. Modal renderizado com `signable-type="ConsentRecord"` + `default-signer` pre-fill do `patient` prop.
  - i18n PT/EN: `PATIENT_CONSENTS.TABLE.SIGN_REMOTE` + `SIGN_REMOTE_TITLE`.
- ✅ **`Signatures::DownloadSignedPdfJob`** (genérico, agnostic de provider):
  - Triggered por `envelope.completed` no `Webhooks::ClicksignController`.
  - Pipeline: carrega request → resolve provider → baixa PDF via `provider.download_signed_pdf` → calcula SHA-256 → substitui `file` attachment do Document (ou só atualiza hash em ConsentRecord) → `mark_completed!` → broadcast ActionCable.
  - Idempotente: já-completed = return early. Webhook duplicado seguro.
  - Retry com backoff em `ProviderError`/`StandardError`.
- ✅ **E2E via runner** validou pipeline completa: Document → SignatureRequest → mark_signed! → DownloadSignedPdfJob.perform → completed, signed_pdf_hash populado, file substituído, audit_log com 5 entries, idempotência (re-run não muda completed_at).
- ✅ Build `bin/vite build` em 31.81s. **72 RSpec verdes** (49 doc_templates + 23 signatures).

### 2026-05-27 — Sessão 11 — Fase 5 (Clicksign) parte 1: fundação
- ✅ **Plugin novo `plugins/signatures/`** (padrão Klivy — engine sem isolate_namespace, mounted em `config/routes.rb`).
- ✅ **Migration 20260527000005**: tabela `signature_requests` com signable polimórfico (Document/ConsentRecord), provider, external_id, signing_url, 8 status, signer info, timeline (sent_at/viewed_at/signed_at/completed_at/cancelled_at/expires_at), audit_log JSONB, original_pdf_hash + signed_pdf_hash. Index único parcial em `(provider, external_id)` pra detectar webhooks duplicados.
- ✅ **Model `SignatureRequest`** com máquina de estados manual (sem state_machine gem): `mark_sent!`, `mark_viewed!`, `mark_signed!`, `mark_completed!`, `mark_cancelled!`, `mark_failed!`, `mark_expired!`. Cada transição valida estado de origem + persiste timestamp + append no audit_log. `append_audit!` pra eventos sem transição.
- ✅ **Provider abstrato + 2 implementações**:
  - `Signatures::Provider` (interface: `create_envelope`, `cancel_envelope`, `resend_envelope`, `fetch_status`, `download_signed_pdf`).
  - `Providers::MockProvider` (dev/test — gera `mock_<hex>` IDs, simula tudo).
  - `Providers::ClicksignProvider` (skeleton com TODOs claros — implementação HTTP fica pra próxima sessão quando user passar `CLICKSIGN_API_TOKEN`).
  - `ProviderResolver` (resolve por nome ou ENV `SIGNATURES_PROVIDER`, default por env).
- ✅ **`Signatures::RequestCreator`** orquestra: extrai PDF do signable (file attachment ou re-render do rendered_html), cria SignatureRequest local, chama provider.create_envelope, transita pra `sent` com external_id+signing_url. Calcula original_pdf_hash SHA-256.
- ✅ **Controller `Api::V1::Accounts::SignatureRequestsController`** com index/show/create/cancel/resend/refresh_status + serializer + policy.
- ✅ **Webhook receiver `Webhooks::ClicksignController`**: parse de eventos (envelope.opened/signed/completed/cancelled/refused), HMAC validation com `CLICKSIGN_WEBHOOK_SECRET`, dispatch pras transições corretas. Idempotente quando envelope desconhecido.
- ✅ **UI completa**: API client (axios), composable `useSignatureRequests`, `SendForSignatureModal.vue` (form pra criar) + `SignatureStatusCard.vue` (timeline visual + ações Cancelar/Reenviar/Atualizar), SCSS modular. i18n PT/EN com namespace `SIGNATURES.*` registrado nos loaders centrais.
- ✅ **23 RSpec verdes** (model: validações + máquina de estados + scopes; mock provider: shape do retorno).
- ✅ **E2E via runner**: Document → SignatureRequest com MockProvider → transições sequenciais → audit_log com 5 entries → guardrail de transição inválida rejeitando.
- ✅ `bin/vite build` passou em 42.33s.

### Pendente pra próxima sessão (Fase 5 parte 2)
- 🔌 ClicksignProvider HTTP real (5 métodos com TODO no código apontam pras docs Clicksign v3)
- 🔌 ClicksignController webhook HMAC validation (placeholder OK pra dev; produção precisa do `CLICKSIGN_WEBHOOK_SECRET`)
- 🪛 `DownloadSignedPdfJob` — quando `envelope.completed` chega, baixa o PDF assinado do Clicksign e anexa ao Document/ConsentRecord original
- 🎯 Wire-up do `<SendForSignatureModal>` em `DocumentsTab.vue` e `ConsentsTab.vue` (botão "Enviar pra assinatura")
- 📱 Portal Paciente — exibir documentos pendentes de assinatura, abrir signing_url

### 2026-05-27 — Sessão 10 — Polimentos finais (caminho consent + drag-and-drop)
- ✅ **Caminho dedicado pra consent via template**:
  - `DocumentTemplates::ConsentRecordBuilder` — orquestra criação de `ConsentRecord` + render HTML/PDF via Renderer/Grover. Valida que template é `consent?`. ConsentRecord reusa `integrity_hash` no lugar de `pdf_hash` (não duplica coluna).
  - `PdfGenerator#attach_to_record` ajustado pra construir `attrs` hash dinamicamente (não passar `pdf_hash:` pra records que não têm a coluna — `assign_attributes(pdf_hash: nil)` dava `UnknownAttributeError` em ConsentRecord).
  - `consent_records_controller#create` agora desvia pra `create_from_template` quando `document_template_id` vier no payload. Sem o param, fluxo legado intocado.
  - `NewConsentForm.vue` ganhou dropdown "Modelo" (fetch automático no troca de tipo, lista templates próprios + Klivy globais). Quando template escolhido, textarea de `body` esconde e mostra aviso explicando que o conteúdo vem renderizado. i18n PT/EN expandido (`PATIENT_CONSENTS.FORM.TEMPLATE_*` × 6 chaves cada).
  - E2E validado: Klivy LGPD → clone → ConsentRecordBuilder → ConsentRecord persistido com `document_template_id`, `rendered_html=4527 bytes`, `integrity_hash`, `body=nil`, `status='pendente'`. PDF de 58KB salvo. Sanity do Document path: continua funcionando (`pdf_hash` ainda popula).
- ✅ **Drag-and-drop pastas** (HTML5 nativo, sem dependência extra):
  - `TemplateCard` ganhou `draggable="true"` (só pra owned, não Klivy) e `dragstart` que coloca `template.id` em `application/x-doc-template-id`.
  - `FolderItem` aceita `dragover`/`dragleave`/`drop` — destaque visual `--drop-target` (outline dashed azul + background) durante hover.
  - `FolderSidebar` propaga `drop-template` pro pai E aceita drop direto na entrada "Todos" (folderId=null = move pra raiz).
  - `DocumentsIndex.handleDropTemplate` chama `store.updateTemplate(id, { folder_id })` com early-return se já está no destino. Toast `MOVED` na conclusão.
- ✅ `bin/vite build` passou em 32.94s. `bundle exec rspec spec/plugins/document_templates/` → **49 examples, 0 failures**.

### 2026-05-27 — Sessão 9 — Fase 4 (Polimento + QA) completa
- ✅ **4.1 Dockerfile** atualizado pra prod: `PUPPETEER_SKIP_DOWNLOAD` no pre-builder + chromium/fontes/libs (fonts-liberation, fonts-freefont-ttf, fonts-noto-color-emoji, libnss3, libatk, libdrm2, libxkbcommon0, libxcomposite1, libxdamage1, libxfixes3, libxrandr2, libgbm1, libpango, libcairo2, libasound2) + `PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium` no stage final
- ✅ **4.2 Menu contextual ⋮**: `TemplateContextMenu.vue` (Duplicar/Arquivar/Reativar/Excluir com confirm), Teleport pra body, click-outside + ESC. Wire-up no `DocumentsIndex.vue` com 4 handlers async + 4 mensagens de i18n
- ✅ **4.3 Estados de erro do editor**: autosave com retry exponencial (delays 2s/5s/10s, max 3 tentativas), botão "Tentar novamente" inline no header, alerta após esgotar retries, `dirty` ref que bloqueia `onBeforeRouteLeave` + `beforeunload` quando há mudanças não salvas, `saveNow` aceita `{ manual: true }` pra pular o retry automático
- ✅ **4.4 Atalho Cmd+/ + Lazy-load**: Cmd/Ctrl+/ insere "/" no editor (ativa o suggestion popover do Notion-style). `TemplateEditor` virou rota lazy (`() => import(...)`) — Vite gerou chunk separado de **409KB JS + 12KB CSS** (gzip 131KB+2KB) que só carrega quando o user abre o editor
- ✅ **4.5 Dark mode**: paper container e ProseMirror agora usam cores fixas (`#1a1a1a`, `#0f0f0f`, `#dbeafe`, `#1d4ed8`) porque o conteúdo é WYSIWYG do PDF — sempre fundo branco mesmo em dark mode da clínica. Resto do UI continua usando custom props dual-mode
- ✅ **4.6 Specs RSpec**: 3 arquivos em `spec/plugins/document_templates/` (model, Catalog, Renderer). **49 examples, 0 failures**. Cobre: validações estruturais + consistência account/source, scopes (klivy, for_account, clinical, consents), callbacks (bump_version só em update, archived_at sync), Catalog (find/find!, categorias, for_frontend), Renderer (walk, marks, variable resolution, fallback, XSS escape, links inseguros descartados)
- 🔒 **Hardening de segurança extra (descoberto via spec)**: Renderer agora descarta links com schema `javascript:`/`data:`/`vbscript:`. Whitelist: `http`, `https`, `mailto`, `tel` + paths relativos (`/`, `#`).

### 2026-05-27 — Sessão 8 — Fase 2 (Catálogo Klivy) completa
- ✅ DSL `Seeds::Builder` (`doc`, `paragraph`, `heading`, `text`, `bold`, `italic`, `variable`, `bullet_list`, `signature_block`, etc.) — montagem de JSON ProseMirror em Ruby legível
- ✅ `Seeds::ClinicalTemplates` (10 modelos): Atestado, Receita, Pedido de Exame, Declaração, Relatório Clínico, Encaminhamento, Contrato Estético, Orçamento, Instruções Pós-Procedimento, Questionário de Admissão
- ✅ `Seeds::ConsentTemplates` (12 modelos): Geral, LGPD, Imagem, Toxina Botulínica, Preenchimento Dérmico, Laser, Fototerapia LED, Peeling Químico, Dermoabrasão, Paciente Menor, Cirurgia Menor, Anestesia Local — usando helper `procedure_consent` pra deduplicar estrutura comum
- ✅ `Seeds::LibrarySeeder` idempotente (find_or_initialize_by + comparação estrutural deep-equal de hashes; primeira tentativa usou `.to_json` que dava falso positivo em re-runs)
- ✅ Rake task `document_templates:seed_klivy_library` + `:list_klivy` registradas via `rake_tasks do load ... end` no engine
- ✅ Seed rodou: `created=22, updated=0, skipped=0` na primeira; `skipped=22` na segunda (idempotência confirmada)
- ✅ Guardrail no `PdfGenerator#build_document_record`: templates de consentimento exigem `save_to:` (ConsentRecord, schema diferente). Sem isso, levanta `ArgumentError` claro
- ✅ E2E final: Atestado Klivy → clone com `source='cloned', source_template_id` → PDF de 44KB salvo no Document com FK+rendered_html+pdf_hash

### 2026-05-27 — Sessão 7 — Fase 3 (Integração paciente) completa
- ✅ `DocumentTemplates::Renderer` — walk recursivo em JSON ProseMirror, 14 tipos de nó (doc, paragraph, heading, listas, blockquote, codeBlock, hr, br, text, variable, table+row+cell+header, image). Marks: bold/italic/underline/strike/code/link/textStyle. Escape HTML em todos os textos. CSS values sanitizados.
- ✅ `app/views/document_templates/pdf_layout.html.erb` — layout completo (header com logo+endereço+CNPJ da clínica, footer com profissional+conselho+timestamp, CSS inline pra A4)
- ✅ `DocumentTemplates::PdfGenerator` — orquestra Resolver + Renderer + Grover. Calcula SHA-256. Anexa PDF via Active Storage + persiste rendered_html + pdf_hash. Result struct compatível com legacy.
- ✅ `Patients::PdfGenerator` modificado: novo param `document_template_id`. Quando presente, `delegate_to_template_engine` chama o novo gerador. Sem o param, Prawn legado intocado. Compatibilidade reversa total.
- ✅ Controller `Api::V1::Accounts::Patients::DocumentsController#generate` repassa `document_template_id` do params pro service.
- ✅ Modal Vue `GenerateDocumentModal.vue`: import do `documentTemplatesApi`, ref `availableTemplates`, watch no `document_type` que faz Promise.all de templates da clínica + Klivy library, novo `<FormSelect>` "Modelo" que só aparece se há templates (`v-if="hasTemplates"`).
- ✅ i18n PT/EN: `PATIENT_DOCUMENTS.MODAL.TEMPLATE_*` (5 chaves novas em cada idioma).
- ✅ `blankDocForm()` ganhou `document_template_id: null`.
- ✅ **E2E smoke test**: template criado no banco → Patients::PdfGenerator com template_id → delega pro DocumentTemplates::PdfGenerator → Renderer → Grover → Document salvo com FK, hash, HTML, file PDF anexado. Path legado (sem template_id) também testado: Prawn ainda funciona.
- ✅ `bin/vite build` passou em 30.98s.

### 2026-05-27 — Sessão 6 — Debug rotas + tela funcional no browser
- 🐛 **Bug 1 (pré-existente)**: servidor puma rodando desde antes do plugin existir; em dev, Rails recarrega `routes.rb` mas NÃO recarrega `config/application.rb` (onde o `require 'document_templates/engine'` vive). Servidor não conhecia a constante → mount falhava silenciosamente → todas as rotas após o mount paravam de carregar. **Fix**: matar puma duro (SIGTERM/-9), limpar bootsnap se necessário, restart com `foreman start -f ./Procfile.dev`. SIGUSR2 não basta — bootsnap mantém o cache de application.rb.
- 🐛 **Bug 2 (meu erro)**: usei `scope module: 'api'` no `plugins/document_templates/config/routes.rb` quando deveria ser `namespace :api`. As 22 rotas eram registradas em `/v1/...` em vez de `/api/v1/...`. Telemed usa `namespace :api`. **Fix**: trocado em [plugins/document_templates/config/routes.rb:6](plugins/document_templates/config/routes.rb#L6). Para o futuro: `scope module` = só module Ruby, `namespace` = path + module.
- ✅ Após fix, todas as rotas API retornam 401 (auth missing — igual ao telemed): `/api/v1/accounts/:id/document_templates`, `/document_templates/variables`, `/document_templates/folders` etc.
- ✅ `/app/accounts/1/documents` retorna 200 e Vue Router renderiza a tela placeholder.

### 2026-05-27 — Sessão 5 — Fase 1 frontend completa
- ✅ User pediu pra fazer tudo de uma vez
- ✅ Criados 50 arquivos no frontend do plugin (API clients, store, composables, componentes da lista, modais, editor TipTap completo, SCSS, i18n)
- ✅ Padrão Pinia seguido (não Vuex), espelhando `plugins/patient_portal/frontend/store/documents.js`
- ✅ Padrão de API client (extends ApiClient com `accountScoped: true`) espelhando telemed
- ✅ Componentes pequenos, focados, com SCSS partials separados — princípio "sem arquivo deus" mantido
- ✅ Editor TipTap com extensão custom `variable` (atom inline, JSON ProseMirror estável) + suggestion plugin `/` + node view Vue
- ✅ Bug do build: `@tiptap/core` faltando no package.json (pnpm strict não permite peer-deps transitivas) → adicionado → build passou
- ✅ `bin/vite build` passou: 4062 módulos, 57 referências aos arquivos novos, ✓ built in 35.56s

### 2026-05-27 — Sessão 4 — Fase 1 backend completa
- ✅ 4 migrations criadas e rodadas (db:migrate sem erro)
- ✅ Models criados: DocumentTemplate (217 linhas, validações completas), DocumentTemplateFolder, concern DocumentTemplateExtension
- ✅ Engine atualizado com `to_prepare` (injeta has_many em Account, include do concern em Document/ConsentRecord)
- ✅ Catálogo dividido em 4 arquivos por categoria (princípio "sem arquivo deus") + Catalog agregador
- ✅ Formatters extraídos pra arquivo próprio
- ✅ Readers (Patient/Clinic/Professional/Date) em arquivos separados
- ✅ Resolver orquestrando catalog + reader + formatter
- ✅ 2 controllers + 2 serializers + 2 policies criados
- ✅ Routes do plugin com 19 endpoints
- ✅ Bug do bump_version no create corrigido (era v=2, agora v=1)
- ✅ Locale `:'pt-BR'` corrigido pra `:'pt_BR'` (padrão do projeto)
- ✅ Smoke test end-to-end: model CRUD, serializer compact+full, policy, validação rejeitando type inválido, formatters retornando valores corretos

### 2026-05-27 — Sessão inicial (parte 3) — installs + smoke test backend
- ✅ User autorizou autonomia total no terminal (memória `feedback-full-autonomy` salva)
- ✅ Detectado **pnpm** (lockfile `pnpm-lock.yaml`) — não yarn
- ✅ `bundle install` falhou inicialmente (grover ~> 2.0 não existe) → corrigido pra `~> 1.2` → grover 1.2.10 instalado
- ✅ `pnpm install` instalou TipTap (15 pkgs @ 2.27.2) + tippy.js 6.3.7
- ✅ Smoke test inicial do Grover falhou: `Cannot find module 'puppeteer'` → adicionado `puppeteer ^23.10.4` ao package.json
- ✅ Chromium não baixou automático (pnpm ignora build scripts por default) → rodado `node node_modules/puppeteer/install.mjs` manualmente → Chrome 131 baixado em `~/.cache/puppeteer/`
- ✅ **Smoke test final OK**: `Grover.new('<h1>Test</h1>').to_pdf` gerou PDF v1.4 de 8055 bytes em `/tmp/grover_smoke_test.pdf`

---

## 9. Como testar o que já está pronto

### Backend — via `bin/rails runner`
```ruby
# Catálogo de variáveis
DocumentTemplates::Catalog.all.size                        # => 55
DocumentTemplates::Catalog.categories                      # => 4 categorias
DocumentTemplates::Catalog.find('patient.cpf').label       # => "CPF"

# CRUD de Folder + Template
folder = DocumentTemplateFolder.create!(account: Account.first, name: 'Estética', position: 0)
tpl = DocumentTemplate.create!(account: Account.first, folder: folder, created_by_user: User.first,
  name: 'Atestado Padrão', document_type: 'atestado', source: 'clinic', status: 'active',
  content_json: { 'type' => 'doc', 'content' => [{'type'=>'paragraph'}] })
DocumentTemplateSerializer.new(tpl).as_json(include_content: true)

# Resolver (variável → valor real)
resolver = DocumentTemplates::Resolver.new(patient: Patient.first, clinic: Account.first, professional: User.first)
resolver.resolve('patient.full_name')
resolver.resolve('date.today_long')
```

### Backend — via API (curl)
Servidor precisa estar rodando (`overmind start` ou `bin/rails s`). Substituir `<ID>` e `<TOKEN>`:
```bash
# Catálogo de variáveis
curl http://localhost:3000/api/v1/accounts/<ID>/document_templates/variables \
  -H "api_access_token: <TOKEN>" | jq

# Listar templates
curl http://localhost:3000/api/v1/accounts/<ID>/document_templates | jq

# Biblioteca Klivy
curl http://localhost:3000/api/v1/accounts/<ID>/document_templates/klivy_library | jq

# Criar template
curl -X POST http://localhost:3000/api/v1/accounts/<ID>/document_templates \
  -H "Content-Type: application/json" -H "api_access_token: <TOKEN>" \
  -d '{"document_template":{"name":"Teste","document_type":"atestado","content_json":{"type":"doc","content":[]}}}'
```

## 10. Coisas a NÃO esquecer

- **Imutabilidade**: `Document.rendered_html` nunca pode ser atualizado depois de criado (LGPD + integridade).
- **Hash SHA-256**: calcular sempre, mesmo antes da Clicksign entrar.
- **Catálogo de variáveis em código** (PORO), não em banco. Versionado via git.
- **Templates Klivy** têm `account_id: NULL` e `source: 'klivy'`. Clínica clica "Usar" → clona.
- **Versionamento congelado**: editar template depois NÃO altera documentos gerados.
- **Permissões MVP**: só `administrator` mexe em templates. `agent` só usa.
- **Pinia**, não Vuex (decisão dessa feature).
- **`document_type` como string**, não enum integer.
- **Plugin sem `isolate_namespace`** (padrão Klivy).

---

## 11. Próxima sessão — onde retomar

Se você abrir uma nova conversa sobre esse projeto:

1. Ler este `STATUS.md` primeiro.
2. Verificar a fase ativa (seção 5).
3. Olhar as tarefas em andamento e bloqueios da fase atual.
4. Continuar de onde a seção "Em andamento agora" indicar.
