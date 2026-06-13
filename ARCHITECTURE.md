# Arquitetura — Klivy

Documento de orientação técnica da plataforma. Para regras de contribuição detalhadas veja [AGENTS.md](AGENTS.md); para o resumo rápido veja [CLAUDE.md](CLAUDE.md).

---

## 1. Visão geral

**Klivy** é uma plataforma SaaS de gestão clínica (prontuário eletrônico, agenda, financeiro) construída como um **monólito modular** de Rails Engines sobre um fork do [Chatwoot](https://www.chatwoot.com/) (inbox omnichannel — WhatsApp, Instagram, Telegram).

Princípio central: **o core do Chatwoot nunca é editado fisicamente.** Toda feature de negócio vive como um *engine* isolado em `plugins/`, que estende o core por injeção de dependência no boot (`config.to_prepare`) e por tabelas-satélite, sem alterar arquivos OSS.

Dois termos que se cruzam o tempo todo:
- **Beclinic** — o padrão de *código*. Todos os identificadores customizados (classes, tabelas, colunas, componentes, rotas) usam `Beclinic`/`beclinic_`.
- **Klivy** — o nome de *marca* do produto. Aparece só em texto visível ao usuário (vindo de `BRAND_NAME` via `GlobalConfigService`), nunca em código.

---

## 2. Stack

| Camada | Tecnologia |
|---|---|
| Backend | Ruby 3.4.4 · Ruby on Rails 7.1 (modular monolith via Engines) |
| Jobs assíncronos | Sidekiq 7 (+ sidekiq-cron) sobre Redis |
| Banco de dados | PostgreSQL (`pg`, `pg_search`, `pgvector` para embeddings da IA) |
| Autenticação | Devise + `devise_token_auth` (tokens) + `devise-two-factor` (2FA) · JWT (LiveKit) |
| Autorização | Pundit (policies) + `KlivyRole` (RBAC custom do produto) |
| Frontend | Vue 3 (Composition API + `<script setup>`) · Vuex + Pinia · Vue Router |
| Build/assets | Vite (`vite-plugin-ruby`) · Tailwind CSS · SCSS modular (plugins) |
| Storage | Active Storage (anexos, exames, documentos) |
| Mensageria | Chatwoot core + bridge Node.js (Baileys/WhatsApp) |
| Tempo real | ActionCable (WebSocket) · LiveKit (telemedicina) |

Gerenciadores: **pnpm 10** (Node 24) e **bundler**.

---

## 3. Pastas principais

```
KlivyApp-main/
├── app/                      # Chatwoot OSS core — NÃO editar sem justificar impacto
│   ├── controllers/api/      #   API REST do core (base controllers, auth, account scoping)
│   ├── models/               #   Account, User, Contact, Conversation, Current...
│   ├── policies/             #   Pundit policies do core
│   ├── javascript/           #   Frontend: dashboard/, widget/, portal/, shared/, v3/
│   └── views/                #   jbuilder (respostas JSON), mailers, dashboard#index (SPA shell)
├── enterprise/               # Overlay Enterprise do Chatwoot (override/extensão do OSS)
├── plugins/                  # ★ TODO o código de negócio Klivy (engines isolados)
│   ├── beclinic_core/        #   Fundação: config, perfis-satélite, componentes UI compartilhados
│   ├── patients/             #   Prontuário eletrônico (EHR)
│   ├── agenda/               #   Calendário, agendamento público (booking), lista de espera
│   ├── financial/            #   Financeiro v2 (caixa, DRE, dashboards, gateways)
│   ├── billing/              #   Cobrança/assinatura
│   ├── custom_roles/         #   RBAC KlivyRole (catálogo de permissões)
│   ├── ai_agent/             #   Bea (agente de IA receptivo)
│   ├── internal_chat/ signatures/ telemed/ patient_portal/
│   ├── document_templates/ ajuda/ migration/
├── config/
│   ├── application.rb         #   Carrega os engines de plugins (linha ~59)
│   ├── routes.rb             #   Rotas core + algumas de plugin + mount de engines
│   └── initializers/
├── db/
│   ├── schema.rb             #   Schema consolidado (core + todos os plugins, single DB)
│   ├── migrate/             #   Migrations (core e plugins)
│   └── seeds.rb
├── lib/
│   └── whatsapp/             #   Bridge Node.js (Baileys) — server.js
├── spec/                     # RSpec (core + spec/plugins/, spec/enterprise/)
├── swagger/                  # OpenAPI 3.0 (core) — plugins têm swagger próprio
├── docs/                     # Produto, arquitetura, engenharia, IA, ADRs
└── dev-tools/                # Scripts de dev, seeds, bridge launcher
```

### Anatomia de um plugin (engine)

```
plugins/<engine>/
├── lib/<engine>/engine.rb    # Rails::Engine isolado; estende o core via config.to_prepare
├── lib/<engine>.rb           # require do engine
├── app/                      # controllers, models, policies, services, views (jbuilder)
├── frontend/                 # routes/, features/, api/, styles/, constants/ (Vue)
├── config/                   # routes.rb e locales/pt_BR.yml próprios (quando aplicável)
└── swagger/                  # contrato OpenAPI do plugin
```

Cada `engine.rb` declara `isolate_namespace` e injeta associações/callbacks nos modelos do core **sem editá-los**. Exemplo real ([plugins/patients/lib/patients/engine.rb](plugins/patients/lib/patients/engine.rb)):

```ruby
module Patients
  class Engine < ::Rails::Engine
    isolate_namespace Patients
    config.to_prepare do
      Account.class_eval { has_many :patients, dependent: :destroy }
      Contact.class_eval { has_one :patient, dependent: :nullify }
    end
  end
end
```

Os engines são auto-carregados em [config/application.rb:59](config/application.rb#L59):
```ruby
Dir[Rails.root.join('plugins/*/lib/*/engine.rb')].each { |f| require f }
```

---

## 4. Onde fica a API

API REST JSON, versionada, **toda escopada por conta** (multi-tenancy):

- **Core:** `app/controllers/api/v1/accounts/...` → `/api/v1/accounts/:account_id/...`
- **Plugin:** `plugins/<engine>/app/controllers/api/v1/accounts/...` → mesmo prefixo, mantendo o namespace do engine.
  Ex.: [plugins/patients/app/controllers/api/v1/accounts/patients_controller.rb](plugins/patients/app/controllers/api/v1/accounts/patients_controller.rb).
- **Público (sem auth de conta):** widget, portal do paciente (`pacientes.*`), booking de agenda (`/agenda/:public_id`), webhooks.
- **Super admin:** `/super_admin/...`.

Rotas vivem em [config/routes.rb](config/routes.rb) (core + parte dos plugins) e em `plugins/<engine>/config/routes.rb` para engines montados (PatientPortal, Billing, DocumentTemplates via `mount`).

Hierarquia de controllers (a cadeia que dá auth + tenancy de graça):

```
ApplicationController
└── Api::BaseController                      # autentica (token de acesso OU usuário)
    └── Api::V1::Accounts::BaseController    # resolve conta + valida membership + locale
        └── <Plugin>::...Controller          # ex.: PatientsController
```

Respostas são renderizadas via **jbuilder** (`app/views/**/*.json.jbuilder` / views do plugin).

---

## 5. Banco de dados

- **PostgreSQL único e compartilhado** por todos os engines — não há banco por plugin. O schema consolidado fica em [db/schema.rb](db/schema.rb) (core + plugins juntos).
- **Multi-tenancy lógica:** cada clínica é uma `Account`. Quase toda tabela de plugin tem `belongs_to :account` + índice em `account_id`. O isolamento é por *query scoping*, não por schema separado.
- **Convenções de tabela:**
  - `beclinic_*` → tabelas que pertencem ao `BeclinicCore` (ex.: `beclinic_profiles`).
  - nome do plugin → tabelas do plugin (`patients`, `agenda_*`, `financial_*`...).
  - colunas adicionadas a tabelas do core levam prefixo `beclinic_` (ex.: `beclinic_role` em `teams`).
- **Extensão higiênica do core:** em vez de adicionar colunas em tabelas do Chatwoot, usa-se **tabelas-satélite de perfil** (`beclinic_profiles` etc.).
- **Padrões de domínio:** soft delete via `deleted_at` (scopes `active`/`deleted`); dinheiro no Financeiro v2 sempre em **centavos `BIGINT`** (nunca float); idempotência via header `Idempotency-Key`.

---

## 6. Autenticação & autorização

**Autenticação (quem é você):**
- `devise_token_auth` monta as rotas em `/auth/*` (sign in/out, confirmações, senhas). Login devolve os headers de token.
- O cliente envia em cada request os headers **`access-token`, `client`, `uid`, `expiry`, `token-type`**, injetados no axios por [app/javascript/dashboard/helper/APIHelper.js](app/javascript/dashboard/helper/APIHelper.js).
- Integrações server-to-server usam `api_access_token` (header). Bots usam `AgentBot`. 2FA via `devise-two-factor`. JWT só para LiveKit.
- `Api::BaseController` decide: se há `api_access_token` → `authenticate_access_token!`; senão → `authenticate_user!` (Devise).

**Resolução de conta + tenancy (a qual clínica você tem acesso):**
`Api::V1::Accounts::BaseController` roda `before_action :current_account`, via `EnsureCurrentAccountHelper`:
1. `Account.find(params[:account_id])` e checa `account.active?`.
2. Valida que o `current_user` é membro: `account.account_users.find_by(user_id:)`. Se não for → `render_unauthorized`.
3. Seta `Current.account` e `Current.account_user` (objeto de request-scope, `CurrentAttributes`).

**Autorização (o que você pode fazer):** dois níveis combinados:
1. **Pundit** — `check_authorization` chama `authorize(Model)`; `policy_scope(Model)` filtra a query pelos registros visíveis. Policies recebem `pundit_user` = `{ user, account, account_user }`.
2. **KlivyRole (RBAC do produto)** — único sistema de permissões de negócio. Checa via `beclinic_can?(:modulo, :acao)` no backend e `usePermissions().can(...)` / `v-can` no frontend. Admin (`administrator? || beclinic_super_admin?`) faz bypass. O catálogo de permissões é mantido em **dois arquivos espelhados** (JS + Ruby) com `catalog_sync_spec` quebrando o CI em caso de drift — ver AGENTS.md → "RBAC Klivy".

---

## 7. Fluxo de uma requisição (front → banco)

Exemplo: listar pacientes na tela da clínica.

```
┌─ FRONTEND (Vue 3 SPA, servida por dashboard#index) ──────────────────────────┐
│ 1. Componente dispara action Vuex/Pinia                                       │
│ 2. Action chama a camada de API do plugin (frontend/api/) → ApiClient         │
│    (app/javascript/dashboard/api/ApiClient.js), accountScoped: true           │
│ 3. ApiClient monta a URL com o account_id da rota:                            │
│       GET /api/v1/accounts/42/patients                                        │
│    axios anexa headers de auth (access-token, client, uid, expiry)            │
└───────────────────────────────────────────────────────────────────────────────┘
                                   │ HTTP
                                   ▼
┌─ RAILS ───────────────────────────────────────────────────────────────────────┐
│ 4. Routing (config/routes.rb) → Api::V1::Accounts::PatientsController#index    │
│ 5. Api::BaseController: authenticate_user! (valida token devise_token_auth)    │
│ 6. Api::V1::Accounts::BaseController → EnsureCurrentAccountHelper:             │
│       • Account.find(42) + active?                                             │
│       • valida membership (account_users) do current_user  ← guard cross-tenant│
│       • Current.account / Current.account_user setados                         │
│    + SwitchLocale (locale da conta)                                            │
│ 7. Controller#index:                                                           │
│       • check_authorization → Pundit PatientPolicy                             │
│       • @patients = policy_scope(Patient).active.includes(...)  ← scope tenant │
│         (filtra por account; preloads evitam N+1; paginação Kaminari)          │
└───────────────────────────────────────────────────────────────────────────────┘
                                   │ ActiveRecord (SQL escopado por account_id)
                                   ▼
┌─ POSTGRES ────────────────────────────────────────────────────────────────────┐
│ 8. SELECT ... FROM patients WHERE account_id = 42 AND deleted_at IS NULL ...   │
└───────────────────────────────────────────────────────────────────────────────┘
                                   │ models (Patient belongs_to :account, soft delete)
                                   ▼
┌─ RESPOSTA ────────────────────────────────────────────────────────────────────┐
│ 9. View jbuilder serializa → JSON                                              │
│ 10. axios resolve a promise → store atualiza estado → componente re-renderiza  │
└───────────────────────────────────────────────────────────────────────────────┘
```

**Escritas** seguem o mesmo caminho até o passo 7, então delegam a lógica de negócio a um **service** (`*::Service`, padrão `self.call(...)`) — controllers ficam finos. Trabalho pesado (notificações WhatsApp/e-mail, PDFs, sync) vai para **jobs Sidekiq**, que **nunca assumem `Current.account`** — recebem `account_id` por argumento e refazem o fetch.

**Regra de ouro do fluxo:** toda query de plugin filtra por `account_id` (direto, via associação escopada, ou `policy_scope`). Vazamento cross-tenant é o bug mais crítico do produto.

---

## 8. Ambiente de desenvolvimento

Stack roda via `pnpm dev` (= `overmind start -f ./Procfile.dev`); se overmind faltar, sobe os serviços individualmente do [Procfile.dev](Procfile.dev):

| Serviço | Comando | Porta |
|---|---|---|
| Backend (Rails/Puma) | `bin/rails s -p 3000` | 3000 |
| Worker (Sidekiq) | `bundle exec sidekiq -C config/sidekiq.yml` | — |
| Frontend (Vite) | `bin/vite dev` | 3036 |
| WhatsApp bridge (Node/Baileys) | `./dev-tools/scripts/start_bridge.sh` | 3002 |

Comandos de teste/lint estão em [CLAUDE.md](CLAUDE.md#common-commands).

---

## 9. Para aprofundar

- [docs/02-architecture/system-architecture.md](docs/02-architecture/system-architecture.md) — arquitetura sistêmica detalhada.
- [docs/02-architecture/ai-agent-architecture.md](docs/02-architecture/ai-agent-architecture.md) — arquitetura da Bea (IA).
- [docs/03-engineering/rbac-custom-roles.md](docs/03-engineering/rbac-custom-roles.md) — RBAC KlivyRole a fundo.
- [AGENTS.md](AGENTS.md) — guia completo de contribuição e convenções obrigatórias.
```
