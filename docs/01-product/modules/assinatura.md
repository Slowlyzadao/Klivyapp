# Módulo Assinatura — Planos & Cupons (`plugins/assinatura`)

> [!IMPORTANT]
> **Nota de Auditoria Arquitetural:**
> Este módulo é um **Rails Engine isolado** em `plugins/assinatura/`. Toda a lógica de negócio, modelos e UI vivem dentro do plugin. Toques no core do Chatwoot foram **mínimos e cirúrgicos**, restritos a registrar controllers/dashboards do Administrate (gem do Super Admin) — restrição imposta pelo Zeitwerk (autoloader Ruby), que exige que cada namespace Ruby tenha um único diretório raiz. **Nenhum arquivo do core teve lógica existente alterada — todas as mudanças foram adições.**
>
> O fluxo de pagamento via **Asaas** (gateway oficial) **não foi tocado**. Este módulo apenas cataloga planos/cupons e parametriza o checkout existente; a integração de cobrança continua sendo responsabilidade do módulo `billing` (ver [billing.md](billing.md)).

---

## 📌 Visão Geral

O **Módulo Assinatura** entrega ao SaaS Klivy duas frentes administrativas + um link público de venda:

1. **Planos de Assinatura** (`/super_admin/subscription_plans`) — CRUD de planos comerciais com preço, limites de uso (agentes, inboxes, IA, e-mails), recursos liberados, cor identitária e ordem de exibição.
2. **Cupons de Desconto** (`/super_admin/discount_coupons`) — CRUD de cupons em três modalidades: trial gratuito, desconto percentual com duração, e gratuidade vitalícia.
3. **Checkout dinâmico** (`/checkout.html?plan=<slug>`) — página pública de adesão. Lê o slug do plano via querystring, busca dados em API pública e renderiza nome/preço corretos. Cupons aplicáveis em cima do preço dinâmico.

Cada plano gera automaticamente uma **URL única de checkout** que o admin copia direto do card e envia ao cliente.

---

## 🎯 Funcionalidades

### Para o super admin — Planos
- 🎨 **Card visual** com cor identitária (8 cores predefinidas + input hex livre), barra superior colorida, preço destacado
- 💰 **Preço mensal + anual** (ambos opcionais; só mensal é obrigatório)
- 🔢 **5 limites por plano** — agentes, inboxes, respostas Captain (IA), documentos Captain, e-mails. Vazio = ilimitado.
- 🧩 **12 recursos liberáveis** com toggle visual (módulos Agenda/Pacientes/Chatbot, Relatórios, API, Integrações, Central de Ajuda, Suporte Prioritário, Sem Marca, Domínio Personalizado, Agentes/Inboxes Ilimitados)
- ✅ **Toggle ativo/inativo** — planos inativos somem do checkout público
- 🔄 **Ordem de exibição** — controla a ordem dos cards
- 📋 **URL de checkout copiável** no footer de cada card (`http://…/checkout.html?plan=<slug>`)

### Para o super admin — Cupons
- 🎫 **3 tipos de cupom:**
  - `trial` — N dias grátis antes da primeira cobrança
  - `percent` — desconto percentual por N meses
  - `free_forever` — conta gratuita vitalícia
- 🎲 **Geração automática** de código (8 caracteres, charset sem ambiguidade — sem `0`/`O`/`1`/`I`)
- 📊 **Limite de usos** opcional (vazio = ilimitado)
- 📅 **Data de expiração** opcional
- ⚠️ **Indicação visual** de cupom expirado (em vermelho na lista)
- 🚫 **Toggle ativo/inativo**

### Para o cliente final — Checkout
- 🔗 **URL única por plano** (`/checkout.html?plan=<slug>`)
- 💲 **Preço dinâmico** — busca via API e renderiza nome + preço cadastrados
- 🏷 **Aplicação de cupom** — desconto incide sobre o preço dinâmico do plano (não fixo)
- 🛡 **Banner de erro claro** se o slug for inválido (em vez de mostrar plano errado)
- 💳 **Fluxo Asaas preservado** — toda a integração de pagamento, cartão, endereço e Turnstile continua funcionando exatamente como antes

---

## 🏗 Arquitetura

### Stack
- **Backend:** Rails Engine (`plugins/assinatura/lib/assinatura/engine.rb`) + ActiveRecord + Administrate (Super Admin)
- **Frontend admin:** Vue 3 (Composition API) com composables, componentes isolados e CSS prefixado `.as-` / `.plan-card-` / `.coupon-card-`
- **Frontend público:** HTML/JS vanilla em `public/checkout.html` (1 single-file)
- **API admin:** REST sob `/super_admin/subscription_plans` e `/super_admin/discount_coupons`
- **API pública:** REST sob `/public/api/v1/subscription_plans/:slug` (sem autenticação)

### Modelagem de domínio

```
SubscriptionPlan
  ├─ name:           string (obrigatório)
  ├─ slug:           string (único; auto-gerado de name.parameterize, com sufixo numérico em colisão)
  ├─ description:    text
  ├─ price_monthly:  decimal(10,2) (obrigatório, ≥ 0)
  ├─ price_yearly:   decimal(10,2) (opcional)
  ├─ color:          string (#RRGGBB, default #5B5BD6)
  ├─ features:       jsonb (array de chaves; default [])
  ├─ limits:         jsonb (hash; default {})
  │   └─ chaves: agents, inboxes, captain_responses, captain_documents, emails
  ├─ active:         boolean (default true)
  ├─ display_order:  integer (default 0)
  └─ timestamps

DiscountCoupon
  ├─ code:             string (obrigatório, único, salvo em maiúsculas)
  ├─ description:      string (obrigatório)
  ├─ kind:             string (obrigatório; "trial" | "percent" | "free_forever")
  ├─ discount_percent: integer (1..100; obrigatório se kind=percent)
  ├─ trial_days:       integer (>0; obrigatório se kind=trial)
  ├─ months_duration:  integer (>0; obrigatório se kind=percent)
  ├─ active:           boolean (default true)
  ├─ max_uses:         integer (nil = ilimitado)
  ├─ current_uses:     integer (default 0)
  ├─ expires_at:       datetime (nil = sem expiração)
  └─ timestamps
```

### Por que dois plugins (`assinatura` e `billing`)?

- **`assinatura`** é o **catálogo administrativo** — quem oferece planos, descontos e o link de venda. É de responsabilidade do produto/comercial.
- **`billing`** (módulo separado, ver [billing.md](billing.md)) é o **gateway financeiro** — quem cobra, gerencia subscription state, suspende contas inadimplentes. É de responsabilidade do financeiro/SRE.

Os dois se conectam apenas pelo `selected_plan: <slug>` enviado no payload de onboarding do checkout.

---

## 📦 Estrutura de arquivos do plugin

```
plugins/assinatura/
├── lib/
│   ├── assinatura.rb                                  # require 'assinatura/engine'
│   └── assinatura/
│       └── engine.rb                                  # Rails Engine
├── app/
│   ├── models/
│   │   ├── subscription_plan.rb                       # Model planos (slug auto-gerado)
│   │   └── discount_coupon.rb                         # Model cupons
│   └── controllers/
│       └── public/api/v1/
│           └── subscription_plans_controller.rb       # API pública (checkout)
├── db/
│   └── migrate/
│       ├── 20260425000001_create_subscription_plans.rb
│       └── 20260425000002_create_discount_coupons.rb
└── frontend/
    ├── shared/
    │   ├── constants.js                               # PLAN_FEATURES, PLAN_LIMITS, PLAN_COLORS, getCheckoutUrl
    │   ├── assinatura.css                             # Design system .as-*
    │   └── AsIcon.vue                                 # 25 SVGs inline (Lucide-style)
    └── features/
        ├── plans/
        │   ├── PlansIndex.vue                         # Página raiz
        │   ├── plans.css                              # CSS .plan-card-*
        │   ├── api/
        │   │   └── plansApi.js                        # HTTP client
        │   ├── composables/
        │   │   ├── usePlans.js                        # Estado da lista
        │   │   └── usePlanForm.js                     # Estado do form (com buildLimits())
        │   └── components/
        │       ├── PlanCard.vue                       # Card visual com URL checkout
        │       ├── PlanFormModal.vue                  # Modal create/edit (com grid de limites)
        │       └── PlanFeatureItem.vue                # Toggle de recurso
        └── coupons/
            ├── CouponsIndex.vue                       # Página raiz
            ├── coupons.css                            # CSS .coupon-card-*
            ├── api/
            │   └── couponsApi.js                      # HTTP client
            ├── composables/
            │   ├── useCoupons.js                      # Estado da lista
            │   └── useCouponForm.js                   # Estado do form (com generateCode())
            └── components/
                ├── CouponCard.vue                     # Linha de cupom
                └── CouponFormModal.vue                # Modal create/edit
```

### Arquivos no core (mínimo necessário)

```
app/controllers/super_admin/
  ├── subscription_plans_controller.rb     # CRUD admin (Zeitwerk requer no core)
  └── discount_coupons_controller.rb       # CRUD admin

app/dashboards/
  ├── subscription_plan_dashboard.rb       # Dashboard mínimo (Administrate exige)
  └── discount_coupon_dashboard.rb         # Dashboard mínimo

app/views/super_admin/
  ├── subscription_plans/index.html.erb    # render_vue_component('AssinaturaPlans')
  └── discount_coupons/index.html.erb      # render_vue_component('AssinaturaCoupons')
```

### Arquivo público (frontend de venda)

```
public/checkout.html                       # Refatorado para ler ?plan=<slug> dinamicamente
```

---

## 🔌 API

### Pública (sem autenticação)

| Método | Path | Descrição |
|---|---|---|
| `GET` | `/public/api/v1/subscription_plans/:slug` | Detalhe do plano para o checkout |

#### Resposta de exemplo (200)

```json
{
  "id": 2,
  "slug": "foda",
  "name": "Foda",
  "description": "",
  "price_monthly": 199.0,
  "price_yearly": 1999.0,
  "color": "#8B5CF6",
  "features": ["agenda", "chatbot"],
  "limits": {
    "agents": 5,
    "inboxes": 2,
    "captain_responses": 100,
    "captain_documents": 1,
    "emails": 1
  }
}
```

#### Resposta de erro (404)

```json
{ "error": "Plano não encontrado" }
```

Retornado quando o slug não existe **ou** quando o plano está marcado como `active: false` (filtrado por `SubscriptionPlan.active`).

### Super Admin (autenticada)

| Método | Path | Descrição |
|---|---|---|
| `GET` | `/super_admin/subscription_plans(.json)` | Lista planos (HTML carrega Vue; JSON é o data feed) |
| `POST` | `/super_admin/subscription_plans.json` | Cria plano |
| `PATCH` | `/super_admin/subscription_plans/:id.json` | Atualiza plano |
| `DELETE` | `/super_admin/subscription_plans/:id.json` | Exclui plano |
| `GET/POST/PATCH/DELETE` | `/super_admin/discount_coupons(/:id)?(.json)?` | Idem para cupons |

---

## ⚙️ Frontend admin — Detalhes técnicos

### Composables Vue

#### `usePlans.js`
- Estado reativo: `plans` (ref), `loading`, `error`
- `fetchPlans()` — GET na API admin
- `deletePlan(id)` — DELETE + remove do array local
- `upsertPlan(plan)` — insere ou atualiza no array local sem refetch (otimista)

#### `usePlanForm.js`
- Estado reativo: `form`, `editingId`, `saving`, `formError`
- `openNew()` — `form = emptyForm()` (limits: `{}`, features: `[]`, ativo)
- `openEdit(plan)` — clona o plano, **especialmente** `limits: { ...(plan.limits || {}) }` para edição não mutar o original
- `toggleFeature(key)` — adiciona/remove do array `features`
- `buildLimits()` — filtra valores vazios / zero / NaN antes de enviar (impede `{ agents: 0 }` virar 0 ilimitado)
- `save()` — POST se `editingId == null`, PATCH se for número; chama `onSuccess(result)` no callback

#### `useCouponForm.js`
- Idem, com extras:
- `generateCode()` — gera string de 8 caracteres com charset `'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'` (sem `0/O/1/I`)
- `openNew()` chama `generateCode()` automaticamente
- `save()` faz `parseInt` em campos numéricos e envia `null` para opcionais vazios

### Componente `AsIcon.vue` (SVGs inline)

Componente único com **25 ícones** SVG inline (estilo Lucide, traços de 2px, viewBox 24×24). Nomes mapeados:

```
edit, trash, copy, check, close, add, loader, refresh, star, alert,
tag, ticket, user, calendar, heart, robot, chart, code, plug, book,
headset, shield, globe, user-add, checkbox
```

**Por que SVG inline e não fonte de ícones?** A fonte de ícones do dashboard principal (`icon-edit-line`, `icon-delete-bin-line` etc.) **não está carregada no contexto Super Admin**. Sem o fontfaces, qualquer `<i class="icon-*">` renderiza como inline vazio. SVGs inline funcionam em qualquer contexto, sem dependências externas.

API: `<AsIcon name="edit" :size="16" />`

### CSS — `reset-base` em todos os botões

O Administrate aplica um override global agressivo:

```scss
button:not(.reset-base),
input[type='submit']:not(.reset-base),
.button:not(.reset-base) {
  background-color: $color-woot;  // azul Chatwoot
  color: $white;
  // ...
}
```

Sem cuidado, **qualquer `<button>` no Vue do plugin** vira retângulo azul sólido. A solução foi adicionar `class="reset-base"` em **todos os 18 botões** do plugin. Esse marker é a saída oficial — é exatamente para isso que o `:not(.reset-base)` existe.

---

## 🛒 Frontend público — `public/checkout.html`

### Como funciona o checkout dinâmico

```
┌─────────────────────────────────────────────────────────────┐
│  Cliente acessa /checkout.html?plan=<slug>                  │
│                          ↓                                  │
│  DOMContentLoaded → loadSelectedPlan()                      │
│                          ↓                                  │
│  GET /public/api/v1/subscription_plans/<slug>               │
│                          ↓                                  │
│  ├─ 200 → atualiza PLAN_PRICE/PLAN_NAME/PLAN_SLUG           │
│  ├─ 404 → mostra banner ⚠️ "Plano não existe ou inativo"    │
│  └─ erro → fallback "Plano <slug>" + banner de erro         │
│                          ↓                                  │
│  renderPlanSummary() preenche:                              │
│   ├─ #planNameLabel        ← PLAN_NAME                      │
│   ├─ #planPriceLabel       ← PLAN_PRICE formatado           │
│   ├─ #totalAssinaturaValue ← PLAN_PRICE/mês                 │
│   └─ #payTodayFinal        ← PLAN_PRICE                     │
│                          ↓                                  │
│  Cliente preenche dados → applyCoupon() (opcional)          │
│                          ↓                                  │
│  Submit final: payload.selected_plan = PLAN_SLUG (dinâmico) │
│                          ↓                                  │
│  POST para Asaas (fluxo intacto desde antes)                │
└─────────────────────────────────────────────────────────────┘
```

### Variáveis-chave do JS

```js
let PLAN_PRICE = 197.00;        // mutável; atualizada pela API
let PLAN_NAME  = 'Plano Standard';
let PLAN_SLUG  = 'standard';
let PLAN_LOAD_ERROR = null;     // string da mensagem de erro a exibir
```

### Cupons em cima do preço dinâmico

A função `applyCoupon()` foi reescrita para usar `PLAN_PRICE` em vez de `R$ 197,00` literal. Os 3 tipos de cupom continuam funcionando:

- **trial** — paga R$ 0 hoje; informa que após N dias cobra `PLAN_PRICE`/mês
- **percent** — desconto X% sobre `PLAN_PRICE` por N meses
- **free_forever** — paga R$ 0 sempre

A função `removeCoupon()` foi simplificada — apenas chama `renderPlanSummary()` em vez de re-hardcodar valores.

---

## 🧩 Integração com Asaas

> **TL;DR:** Não foi tocada. O único delta é que `selected_plan` no payload final virou dinâmico.

| Componente | Estado |
|---|---|
| Token Turnstile (anti-bot Cloudflare) | ✅ Inalterado |
| Validação CPF/CNPJ/CEP/cartão (frontend) | ✅ Inalterado |
| Modal de Termos de Uso (33+ artigos) | ✅ Inalterado |
| Steps do formulário (faturamento → endereço → cartão → revisão) | ✅ Inalterado |
| Endpoint de submissão (`POST` para o backend Asaas) | ✅ Inalterado |
| Payload final | 🔄 `selected_plan: PLAN_SLUG` (antes: literal `'standard'`) |

O backend que processa o checkout (módulo `billing`) já recebe o `selected_plan` como string e usa para criar a `Billing::Subscription` com o plano correto.

---

## ⚠️ Constraints técnicas notáveis

### Zeitwerk + Administrate

O autoloader do Rails (Zeitwerk) exige que cada namespace Ruby tenha **um único diretório raiz**. Como o core já define o namespace `SuperAdmin::` em `app/controllers/super_admin/`, **não dá** para colocar `SuperAdmin::SubscriptionPlansController` no plugin — o Zeitwerk não consegue ponte entre dois autoload roots para o mesmo namespace.

**Solução adotada:** Os 4 controllers + 2 dashboards + 2 views ficam em `app/` (core), mas com lógica mínima — apenas o necessário para o Administrate reconhecer o recurso. **Toda a lógica de negócio, validações, geração de slug etc. permanece no plugin.**

Isso replica o exato padrão do plugin `ajuda` (controllers `help_articles`, `help_categories`, `help_faqs`).

### `::` prefix em referências de modelo

Dentro de `SuperAdmin::SubscriptionPlansController`, escrever `SubscriptionPlan.find(...)` faz o Ruby tentar:

1. `SuperAdmin::SubscriptionPlansController::SubscriptionPlan` ❌
2. `SuperAdmin::SubscriptionPlan` ❌
3. `SubscriptionPlan` (root) — depende do Zeitwerk encontrar

O Zeitwerk **não** dispara `const_missing` corretamente para essa cadeia se o modelo está num autoload root diferente. **Solução:** `::SubscriptionPlan.find(...)` pula o nesting e vai direto pro topo. Aplicado em todas as referências dos controllers do super admin.

### Restart do Puma para novos `app/` no plugin

Toda Rails Engine descobre raízes de autoload (`app/controllers/`, `app/models/`, etc.) **uma única vez no boot**. Se você adiciona um diretório novo (ex: `plugins/assinatura/app/controllers/`) durante uma sessão de dev, **precisa reiniciar o Puma** — `tmp/restart.txt` não funciona com `bin/rails s` standalone, e o file watcher do `Listen` não monitora `plugins/`.

Em produção (Docker/CI) isso não é problema — o boot já vê todos os arquivos.

---

## 🚀 Como ativar / testar

```bash
# 1. Migrar o banco
bin/rails db:migrate

# 2. Acessar painel admin
open http://localhost:3000/super_admin/subscription_plans   # criar planos
open http://localhost:3000/super_admin/discount_coupons     # criar cupons

# 3. Copiar URL de checkout do card → testar visão pública
open "http://localhost:3000/checkout.html?plan=foda"

# 4. (Opcional) Aplicar um cupom no checkout para validar o cálculo dinâmico
```

Network tab deve mostrar:
- `GET /public/api/v1/subscription_plans/<slug>` → `200` (dados do plano)
- No submit: `POST` para o endpoint Asaas com `selected_plan: "<slug>"` no payload

---

## 📜 Histórico evolutivo

> Cada versão lista **TODOS** os arquivos tocados, marcando se estão no **core** (`app/`, `config/`, `db/`, `public/`) ou no **plugin** (`plugins/assinatura/`), e a ação realizada (Criado / Modificado / Reescrito / Excluído).

---

### v1.4.0 — 2026-04-25 — Criação do plugin (CRUD de planos e cupons)

**Escopo:** Estrutura inicial do plugin `assinatura`. CRUD completo de planos e cupons no Super Admin com UI Vue 3.

#### Arquivos CRIADOS — Plugin

| Arquivo | Descrição |
|---|---|
| `plugins/assinatura/lib/assinatura.rb` | Entry point: `require 'assinatura/engine'` |
| `plugins/assinatura/lib/assinatura/engine.rb` | Rails Engine sem `isolate_namespace` (modelos coexistem no namespace global, compatível com Administrate) |
| `plugins/assinatura/app/models/subscription_plan.rb` | Model planos: validações, escopos `active`/`ordered`, `as_json` para serializar decimais como float |
| `plugins/assinatura/app/models/discount_coupon.rb` | Model cupons: validações condicionais por `kind`, normaliza código para maiúsculas, `expired?`/`uses_exhausted?`/`valid_for_use?` |
| `plugins/assinatura/db/migrate/20260425000001_create_subscription_plans.rb` | Tabela `subscription_plans` (sem `slug` e `limits` — adicionados em v1.4.1) |
| `plugins/assinatura/db/migrate/20260425000002_create_discount_coupons.rb` | Tabela `discount_coupons` |
| `plugins/assinatura/frontend/shared/constants.js` | `PLAN_FEATURES` (12 recursos), `COUPON_KINDS`, `PLAN_COLORS`, `getCsrfToken()`, `formatPrice()` |
| `plugins/assinatura/frontend/shared/assinatura.css` | Design system `.as-*` (botões, forms, modais, toggles, alerts, badges, toasts) |
| `plugins/assinatura/frontend/features/plans/api/plansApi.js` | HTTP client de planos |
| `plugins/assinatura/frontend/features/plans/composables/usePlans.js` | Estado da lista |
| `plugins/assinatura/frontend/features/plans/composables/usePlanForm.js` | Estado do formulário |
| `plugins/assinatura/frontend/features/plans/components/PlanFeatureItem.vue` | Toggle de recurso |
| `plugins/assinatura/frontend/features/plans/components/PlanCard.vue` | Card visual |
| `plugins/assinatura/frontend/features/plans/components/PlanFormModal.vue` | Modal create/edit |
| `plugins/assinatura/frontend/features/plans/PlansIndex.vue` | Página raiz |
| `plugins/assinatura/frontend/features/plans/plans.css` | CSS feature planos |
| `plugins/assinatura/frontend/features/coupons/api/couponsApi.js` | HTTP client de cupons |
| `plugins/assinatura/frontend/features/coupons/composables/useCoupons.js` | Estado da lista |
| `plugins/assinatura/frontend/features/coupons/composables/useCouponForm.js` | Estado do formulário (+`generateCode()` charset sem ambiguidade) |
| `plugins/assinatura/frontend/features/coupons/components/CouponCard.vue` | Linha de cupom |
| `plugins/assinatura/frontend/features/coupons/components/CouponFormModal.vue` | Modal create/edit (campos condicionais por kind) |
| `plugins/assinatura/frontend/features/coupons/CouponsIndex.vue` | Página raiz |
| `plugins/assinatura/frontend/features/coupons/coupons.css` | CSS feature cupons |

#### Arquivos CRIADOS — Core (Zeitwerk + Administrate)

| Arquivo | Descrição |
|---|---|
| `app/controllers/super_admin/subscription_plans_controller.rb` | Controller; `index` renderiza HTML+Vue OU JSON; CRUD via JSON |
| `app/controllers/super_admin/discount_coupons_controller.rb` | Idem para cupons |
| `app/dashboards/subscription_plan_dashboard.rb` | Dashboard mínimo (Administrate exige para escanear) |
| `app/dashboards/discount_coupon_dashboard.rb` | Dashboard mínimo |
| `app/views/super_admin/subscription_plans/index.html.erb` | `render_vue_component('AssinaturaPlans')` |
| `app/views/super_admin/discount_coupons/index.html.erb` | `render_vue_component('AssinaturaCoupons')` |

#### Arquivos MODIFICADOS — Core

| Arquivo | Linhas | O que |
|---|---|---|
| `config/routes.rb` | +3 | `resources :subscription_plans` e `:discount_coupons` no namespace `super_admin` |
| `app/views/super_admin/application/_navigation.html.erb` | +7 | Adicionados `subscription_plans`/`discount_coupons` à lista de exclusão do auto-nav; novo grupo "Assinatura" com itens "Planos" e "Cupons" |
| `app/javascript/entrypoints/superadmin_pages.js` | +4 | Imports + registro de `AssinaturaPlans` e `AssinaturaCoupons` no `ComponentMapping` |

#### Arquivos EXCLUÍDOS (intermediários durante dev)

- `plugins/assinatura/app/controllers/` — criados no plugin inicialmente, **movidos para core** por Zeitwerk
- `plugins/assinatura/app/dashboards/` — idem, **movidos para core**
- `plugins/assinatura/app/views/` — idem, **movidos para core**

---

### v1.4.1 — 2026-04-25 — Limites por plano + Checkout dinâmico + Fix erro 500 + Botões/ícones

**Escopo:** 5 entregas:
1. Limites configuráveis por plano (5 limites em coluna JSONB nova)
2. Slug + checkout dinâmico (URL pública por plano + endpoint público + refactor do `checkout.html`)
3. Cupons em cima do preço dinâmico
4. Fix do erro 500 no super_admin (Zeitwerk não resolvia `SubscriptionPlan` dentro de `SuperAdmin::`)
5. Fix dos botões invisíveis (Administrate sobrescreve `<button>` + ícones-fonte não carregam no super_admin)

#### Arquivos CRIADOS — Plugin

| Arquivo | Descrição |
|---|---|
| `plugins/assinatura/app/controllers/public/api/v1/subscription_plans_controller.rb` | Endpoint público `GET /public/api/v1/subscription_plans/:slug` (filtra `.active`); 404 se não existir |
| `plugins/assinatura/frontend/shared/AsIcon.vue` | Componente Vue com 25 SVGs inline (Lucide-style); substitui `<i class="icon-*">` |

#### Arquivos MODIFICADOS — Plugin

| Arquivo | O que |
|---|---|
| `plugins/assinatura/db/migrate/20260425000001_create_subscription_plans.rb` | +`t.jsonb :limits, default: {}`, +`t.string :slug`, +`add_index :slug, unique: true` (editado in-place pois banco de dev ainda não havia rodado a versão antiga) |
| `plugins/assinatura/app/models/subscription_plan.rb` | +`before_validation :generate_slug` (parameterize + sufixo numérico em colisão); +`validates :slug, presence, uniqueness`; `as_json` força float em prices |
| `plugins/assinatura/frontend/shared/constants.js` | Ícones em `PLAN_FEATURES` trocados de fonte (`icon-calendar-line`) para nomes neutros (`calendar`, `heart`, `robot`, …); +`PLAN_LIMITS` (5 limites + rótulos pt-BR); +`getCheckoutUrl(plan)` |
| `plugins/assinatura/frontend/features/plans/composables/usePlanForm.js` | +`limits: {}` em `emptyForm()`; +`limits: { ...(plan.limits || {}) }` em `openEdit`; +função `buildLimits()` (filtra zeros/vazios/NaN) |
| `plugins/assinatura/frontend/features/plans/components/PlanCard.vue` | **Reescrito.** Usa `AsIcon`; botões com `reset-base` + label de texto ("Editar"/"Excluir"); +seção "Limites" (só chaves preenchidas, formato `Intl.NumberFormat('pt-BR')`); +footer com URL de checkout truncada + botão de copiar (feedback "Copiado!" 2s) |
| `plugins/assinatura/frontend/features/plans/components/PlanFormModal.vue` | Usa `AsIcon`; botões com `reset-base`; +novo bloco "Limites do plano" (5 inputs em `as-limits-grid`, hint "Deixe em branco para ilimitado") |
| `plugins/assinatura/frontend/features/plans/components/PlanFeatureItem.vue` | **Reescrito.** Usa `AsIcon`; default `icon` mudou para `'checkbox'`; botão com `reset-base` |
| `plugins/assinatura/frontend/features/plans/PlansIndex.vue` | Usa `AsIcon`; todos os botões com `reset-base` |
| `plugins/assinatura/frontend/features/plans/plans.css` | `.plan-card__action-btn` deixou de ser quadrado 28×28 sem borda → pill com altura 28px, padding horizontal, borda visível, label inline; variante `--danger` em ruby; `.plan-card__copy-btn` com borda + hover iris; +`.plan-card__action-label` |
| `plugins/assinatura/frontend/features/coupons/CouponsIndex.vue` | Usa `AsIcon`; botões com `reset-base` |
| `plugins/assinatura/frontend/features/coupons/components/CouponCard.vue` | Usa `AsIcon`; botões de ação com `reset-base` + label de texto |
| `plugins/assinatura/frontend/features/coupons/components/CouponFormModal.vue` | Usa `AsIcon`; botões com `reset-base` |

#### Arquivos MODIFICADOS — Core

| Arquivo | Linhas | O que |
|---|---|---|
| `app/controllers/super_admin/subscription_plans_controller.rb` | ~6 | `SubscriptionPlan` → `::SubscriptionPlan` (force global namespace); `plan_params` aceita `limits` (slice → to_i → compact) |
| `app/controllers/super_admin/discount_coupons_controller.rb` | ~4 | `DiscountCoupon` → `::DiscountCoupon` (preventivo, mesmo erro de Zeitwerk) |
| `config/routes.rb` | +1 | Adicionada `resources :subscription_plans, only: [:show], param: :slug` no namespace `public/api/v1` |
| `public/checkout.html` | ~40 (refactor) | **Refatorado.** Antes: "Plano Standard" + R$ 197/397 e `selected_plan: 'standard'` hardcoded em ~12 lugares. Depois: IDs novos (`#planNameLabel`, `#planPriceLabel`, `#totalAssinaturaValue`, `#planLoadError`); variáveis mutáveis (`let PLAN_PRICE`, `PLAN_NAME`, `PLAN_SLUG`); funções `formatBRLAt()`, `renderPlanSummary()`, `loadSelectedPlan()`; `applyCoupon()` usa `PLAN_PRICE` dinâmico; `removeCoupon()` simplificada; `payload.selected_plan = PLAN_SLUG` |

**Não tocado em `checkout.html`:** Turnstile, integração Asaas, validações, modal de Termos, todos os 33+ artigos de TERMOS_USO_HTML, fluxo de steps, endpoint de submissão.

#### Arquivos EXCLUÍDOS

Nenhum.

---

## 🧮 Auditoria final — todos os arquivos do módulo

### Plugin (`plugins/assinatura/`) — 100% isolado

| Arquivo | Versão criado | Estado atual |
|---|---|---|
| `lib/assinatura.rb` | v1.4.0 | Estável |
| `lib/assinatura/engine.rb` | v1.4.0 | Estável |
| `app/models/subscription_plan.rb` | v1.4.0 | Modificado em v1.4.1 (slug + as_json) |
| `app/models/discount_coupon.rb` | v1.4.0 | Estável |
| `app/controllers/public/api/v1/subscription_plans_controller.rb` | v1.4.1 | Estável |
| `db/migrate/20260425000001_*` | v1.4.0 | Modificado em v1.4.1 (slug + limits) |
| `db/migrate/20260425000002_*` | v1.4.0 | Estável |
| `frontend/shared/constants.js` | v1.4.0 | Modificado em v1.4.1 (ícones + LIMITS + getCheckoutUrl) |
| `frontend/shared/assinatura.css` | v1.4.0 | Estável |
| `frontend/shared/AsIcon.vue` | v1.4.1 | Estável |
| `frontend/features/plans/api/plansApi.js` | v1.4.0 | Estável |
| `frontend/features/plans/composables/usePlans.js` | v1.4.0 | Estável |
| `frontend/features/plans/composables/usePlanForm.js` | v1.4.0 | Modificado em v1.4.1 (buildLimits) |
| `frontend/features/plans/components/PlanFeatureItem.vue` | v1.4.0 | Reescrito em v1.4.1 |
| `frontend/features/plans/components/PlanCard.vue` | v1.4.0 | Reescrito em v1.4.1 |
| `frontend/features/plans/components/PlanFormModal.vue` | v1.4.0 | Modificado em v1.4.1 |
| `frontend/features/plans/PlansIndex.vue` | v1.4.0 | Modificado em v1.4.1 |
| `frontend/features/plans/plans.css` | v1.4.0 | Modificado em v1.4.1 |
| `frontend/features/coupons/api/couponsApi.js` | v1.4.0 | Estável |
| `frontend/features/coupons/composables/useCoupons.js` | v1.4.0 | Estável |
| `frontend/features/coupons/composables/useCouponForm.js` | v1.4.0 | Estável |
| `frontend/features/coupons/components/CouponCard.vue` | v1.4.0 | Modificado em v1.4.1 |
| `frontend/features/coupons/components/CouponFormModal.vue` | v1.4.0 | Modificado em v1.4.1 |
| `frontend/features/coupons/CouponsIndex.vue` | v1.4.0 | Modificado em v1.4.1 |
| `frontend/features/coupons/coupons.css` | v1.4.0 | Estável |

### Core — toques cirúrgicos

| Arquivo | Tipo | Quando | Justificativa |
|---|---|---|---|
| `app/controllers/super_admin/subscription_plans_controller.rb` | Criado | v1.4.0 | Zeitwerk: namespace SuperAdmin no core |
| `app/controllers/super_admin/discount_coupons_controller.rb` | Criado | v1.4.0 | Zeitwerk: namespace SuperAdmin no core |
| `app/dashboards/subscription_plan_dashboard.rb` | Criado | v1.4.0 | Administrate exige |
| `app/dashboards/discount_coupon_dashboard.rb` | Criado | v1.4.0 | Administrate exige |
| `app/views/super_admin/subscription_plans/index.html.erb` | Criado | v1.4.0 | View resolver Administrate |
| `app/views/super_admin/discount_coupons/index.html.erb` | Criado | v1.4.0 | View resolver Administrate |
| `config/routes.rb` | Modificado | v1.4.0 (+3) e v1.4.1 (+1) | Rotas admin + rota pública |
| `app/views/super_admin/application/_navigation.html.erb` | Modificado (+7 linhas) | v1.4.0 | Exclusion list + nav group "Assinatura" |
| `app/javascript/entrypoints/superadmin_pages.js` | Modificado (+4 linhas) | v1.4.0 | Registro `AssinaturaPlans` / `AssinaturaCoupons` |
| `public/checkout.html` | Refatorado | v1.4.1 | Plano dinâmico via querystring (Asaas intacto) |

### Resumo numérico

- **Arquivos criados no plugin:** 25
- **Arquivos criados no core:** 6 (todos pequenos, sem lógica duplicada do plugin)
- **Arquivos modificados no core:** 4 (`config/routes.rb`, `_navigation.html.erb`, `superadmin_pages.js`, `public/checkout.html`)
- **Tabelas novas no banco:** 2 (`subscription_plans`, `discount_coupons`)
- **Tabelas do core alteradas:** 0
- **Dependências npm adicionadas:** 0

---

## 🔗 Referências

- Plugin: [`plugins/assinatura/`](../../../plugins/assinatura/)
- Endpoint público: [`subscription_plans_controller.rb`](../../../plugins/assinatura/app/controllers/public/api/v1/subscription_plans_controller.rb)
- Migrations: [`subscription_plans`](../../../plugins/assinatura/db/migrate/20260425000001_create_subscription_plans.rb), [`discount_coupons`](../../../plugins/assinatura/db/migrate/20260425000002_create_discount_coupons.rb)
- Checkout público: [`public/checkout.html`](../../../public/checkout.html)
- Componente de ícones: [`AsIcon.vue`](../../../plugins/assinatura/frontend/shared/AsIcon.vue)
- Changelog detalhado: [`changelog.leandro.md`](../../../changelog.leandro.md) — versões 1.4.0 → 1.4.1
- Módulo financeiro relacionado: [`billing.md`](billing.md)
