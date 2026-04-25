# Changelog — Leandro

---

## Versão 1.4.1 — 2026-04-25

**Autor:** Claude (instruído por Leandro Benuv)
**Escopo:** Plugin `assinatura` — limites por plano, checkout dinâmico vinculado a Asaas, fix do erro 500 do super_admin, retrabalho dos botões/ícones, endpoint público.
**Status final:** ✅ Validado em ambiente local — CRUD de planos e cupons funcionando, checkout dinâmico abrindo com nome/preço corretos do plano selecionado, fluxo de pagamento via Asaas preservado, cupons aplicáveis em cima do preço dinâmico do plano.

---

### Resumo geral

Continuação do plugin `assinatura` (v1.4.0). Três entregas funcionais e dois fixes de plataforma:

1. **Limites por plano** — 5 limites configuráveis por plano (agentes, inboxes, respostas IA, documentos IA, e-mails) salvos em coluna JSONB `limits`.
2. **Slug + checkout dinâmico** — cada plano ganha um `slug` único auto-gerado; o card mostra a URL pública de checkout (`/checkout.html?plan=<slug>`) com botão de copiar; `public/checkout.html` lê o slug e busca o plano via API pública nova, renderizando nome + preço corretos no resumo da assinatura. O fluxo Asaas (token Turnstile, dados de faturamento, cartão, endereço, criação de assinatura) **não foi tocado** — o `selected_plan` no payload final passou a ser dinâmico (`PLAN_SLUG`) em vez de `'standard'` hard-coded, o que basta para o backend Asaas reconhecer qual plano foi assinado.
3. **Cupons em cima do preço dinâmico** — o `applyCoupon()` do checkout passou a usar `PLAN_PRICE` mutável; cupons trial / percent / free_forever continuam funcionando em qualquer plano, não apenas no Standard.
4. **Fix erro 500 super_admin** — Zeitwerk não estava resolvendo `SubscriptionPlan` / `DiscountCoupon` quando referenciados de dentro do namespace `SuperAdmin::`.
5. **Fix botões/ícones invisíveis** — botões dos componentes Vue do plugin estavam virando retângulos azuis sem ícone.

---

### Mudanças no CORE do sistema (fora de `plugins/`)

> ⚠️ Estas são as únicas tocadas fora do plugin. Todas pequenas e estritamente necessárias para o plugin funcionar.

#### MODIFICADO — `app/controllers/super_admin/subscription_plans_controller.rb`

- Todas as referências a `SubscriptionPlan` foram prefixadas com `::` (`::SubscriptionPlan`) para forçar resolução no namespace global.
- **Por quê:** dentro do namespace `SuperAdmin::`, o Ruby tenta resolver primeiro `SuperAdmin::SubscriptionPlansController::SubscriptionPlan`, depois `SuperAdmin::SubscriptionPlan` e só então o root. Como o modelo está em outro autoload root (do plugin), o Zeitwerk dispara `NameError` antes de chegar no root via `const_missing`. O `::` pula o nesting e vai direto pro topo.
- `plan_params` foi estendido para aceitar `limits` (lê `params.dig(:subscription_plan, :limits)`, faz `to_unsafe_h`, `slice` nas 5 chaves permitidas, `transform_values { v.to_i }`, `compact`).

#### MODIFICADO — `app/controllers/super_admin/discount_coupons_controller.rb`

- Mesmo fix de `::DiscountCoupon` aplicado preventivamente. Sem isso o erro 500 voltaria assim que a página de Cupons fosse acessada.

#### MODIFICADO — `config/routes.rb`

- **Uma única linha adicionada**, dentro do namespace público existente (`namespace :public > namespace :api > namespace :v1`):
  ```ruby
  resources :subscription_plans, only: [:show], param: :slug
  ```
- Nenhuma rota existente foi alterada ou removida.

#### MODIFICADO — `db/migrate/20260425000001_create_subscription_plans.rb`

- Esta migration foi **criada por mim na v1.4.0**, mas durante a v1.4.1 ganhou duas colunas novas:
  ```ruby
  t.jsonb  :limits, null: false, default: {}
  t.string :slug
  add_index :subscription_plans, :slug, unique: true
  ```
- Como o banco do usuário ainda não tinha rodado a versão antiga, a migration foi editada in-place em vez de criar uma migration de `add_column` separada (decisão pragmática para ambiente de dev pré-deploy).

#### MODIFICADO — `public/checkout.html`

- **Antes:** plano "Standard" (R$ 397 → R$ 197) e `selected_plan: 'standard'` estavam hard-coded em ~12 lugares.
- **Agora:**
  - Adicionados IDs novos no resumo da sidebar: `#planNameLabel`, `#planPriceLabel`, `#totalAssinaturaValue`, `#planLoadError`.
  - O `payTodayBadge`, `payTodayOriginal` ganharam `display: none` por padrão (mostrados só quando há cupom).
  - Bloco `<script>` ganhou:
    - Variáveis mutáveis `let PLAN_PRICE`, `PLAN_NAME`, `PLAN_SLUG`, `PLAN_LOAD_ERROR`.
    - Função `formatBRLAt(value)` (separada da `formatBRL` antiga, evita colisão).
    - Função `renderPlanSummary()` que preenche todos os IDs com base nas variáveis.
    - Função `loadSelectedPlan()` (rodada no `DOMContentLoaded`):
      1. Lê `?plan=<slug>` da URL.
      2. Sem param: usa fallback "standard" + R$ 197 (legado).
      3. Com param: faz `fetch('/public/api/v1/subscription_plans/<slug>')`.
      4. 404: mostra banner `⚠️ Plano "<slug>" não existe ou está inativo.`
      5. Sucesso: atualiza `PLAN_PRICE`, `PLAN_NAME`, `PLAN_SLUG`.
  - `applyCoupon()`: removidos os `R$ 397,00` literais; o badge agora é mostrado/escondido via `display`; cálculos usam `PLAN_PRICE` dinâmico.
  - `removeCoupon()`: simplificado — só chama `renderPlanSummary()` em vez de re-hardcodar valores.
  - `payload.selected_plan = PLAN_SLUG` (antes: `'standard'`).
- **Não tocado:** Turnstile, integração Asaas, validações de CPF/CNPJ/CEP/cartão, modal de Termos, todos os 33+ artigos do TERMOS_USO_HTML, fluxo de steps (faturamento → endereço → cartão → revisão), API de submissão. O checkout é o mesmo fluxo, só ficou parametrizado por plano.

---

### Mudanças no PLUGIN `plugins/assinatura/`

#### CRIADO — `plugins/assinatura/app/controllers/public/api/v1/subscription_plans_controller.rb`

Endpoint público (sem autenticação) usado pelo `checkout.html`:

```
GET /public/api/v1/subscription_plans/:slug
→ 200 { id, slug, name, description, price_monthly, price_yearly, color, features, limits }
→ 404 { error: 'Plano não encontrado' } (slug inexistente ou plano inativo)
```

Implementado como `ActionController::API` (sem CSRF, sem layout) — apropriado para endpoint público.
Filtra por `SubscriptionPlan.active` para nunca expor planos desativados.

#### CRIADO — `plugins/assinatura/frontend/shared/AsIcon.vue`

Componente Vue único com 25 SVGs inline (estilo Lucide, traços de 2px). Cobre todos os ícones usados pelo plugin: `edit`, `trash`, `copy`, `check`, `close`, `add`, `loader`, `refresh`, `star`, `alert`, `tag`, `ticket`, `user`, `calendar`, `heart`, `robot`, `chart`, `code`, `plug`, `book`, `headset`, `shield`, `globe`, `user-add`, `checkbox`.

API: `<AsIcon name="edit" :size="16" />`. Substituiu as ~20 ocorrências de `<i class="icon-*">` que não renderizavam no super_admin (a fonte de ícones do dashboard não está carregada nesse contexto).

#### MODIFICADO — `plugins/assinatura/app/models/subscription_plan.rb`

- `before_validation :generate_slug` — gera slug a partir de `name.parameterize`, com sufixo numérico em colisão (`foda`, `foda-1`, `foda-2`, …).
- `validates :slug, presence: true, uniqueness: true`.
- `as_json` força `price_monthly` e `price_yearly` a `Float` (evita `BigDecimal` aparecer com aspas no JSON do checkout).

#### MODIFICADO — `plugins/assinatura/frontend/shared/constants.js`

- `PLAN_FEATURES`: ícones trocados de `icon-calendar-line`, `icon-heart-pulse-line`, etc. para nomes curtos resolvidos pelo `AsIcon` (`calendar`, `heart`, `robot`, …).
- Adicionada constante `PLAN_LIMITS` com os 5 limites + rótulos pt-BR.
- Adicionada função `getCheckoutUrl(plan)` → `${origin}/checkout.html?plan=${plan.slug || plan.id}`.

#### MODIFICADO — `plugins/assinatura/frontend/features/plans/components/PlanCard.vue` (reescrito)

- Importa `AsIcon` e usa para todos os ícones.
- Botões de ação (Editar / Excluir): `type="button" class="reset-base plan-card__action-btn"` + ícone SVG + `<span class="plan-card__action-label">Editar</span>` (label visível, não só ícone).
- Nova seção "Limites" exibindo apenas as chaves preenchidas (formatadas com `Intl.NumberFormat('pt-BR')`).
- Footer mostra a URL do checkout truncada + botão de copiar (`navigator.clipboard.writeText`) com feedback "Copiado!" por 2s.

#### MODIFICADO — `plugins/assinatura/frontend/features/plans/components/PlanFormModal.vue`

- Importa `AsIcon`. Todos os `<i class="icon-*">` substituídos.
- Adicionado novo bloco "Limites do plano" (5 inputs numéricos em grid) com hint "Deixe em branco para ilimitado".
- Todos os 4 botões (close X, color swatches, Cancelar, Salvar) ganharam `reset-base`.

#### MODIFICADO — `plugins/assinatura/frontend/features/plans/components/PlanFeatureItem.vue` (reescrito)

- Importa `AsIcon`. Default `icon` mudou de `'icon-checkbox-line'` para `'checkbox'`.
- Botão ganhou `reset-base`.

#### MODIFICADO — `plugins/assinatura/frontend/features/plans/PlansIndex.vue`

- Importa `AsIcon`. Todos os `<i class="icon-*">` substituídos (botão "Novo Plano", loading, empty state, toast).
- Botões `Novo Plano` e `Criar primeiro plano` ganharam `reset-base`.

#### MODIFICADO — `plugins/assinatura/frontend/features/plans/composables/usePlanForm.js`

- `emptyForm()` ganhou campo `limits: {}`.
- `openEdit(plan)` faz `limits: { ...(plan.limits || {}) }` para edição não mutar o objeto original.
- Nova função `buildLimits()` que filtra valores vazios / zero / NaN antes de enviar ao backend.

#### MODIFICADO — `plugins/assinatura/frontend/features/coupons/CouponsIndex.vue`

- Importa `AsIcon`. Todos os `<i class="icon-*">` substituídos. Botões com `reset-base`.

#### MODIFICADO — `plugins/assinatura/frontend/features/coupons/components/CouponCard.vue`

- Importa `AsIcon`. Botões de ação ganharam `reset-base` + label de texto ("Editar" / "Excluir").

#### MODIFICADO — `plugins/assinatura/frontend/features/coupons/components/CouponFormModal.vue`

- Importa `AsIcon`. Todos os `<i class="icon-*">` substituídos. Botões com `reset-base`.

#### MODIFICADO — `plugins/assinatura/frontend/features/plans/plans.css`

- `.plan-card__action-btn` deixou de ser quadrado 28×28 sem borda e virou pill com altura 28px, padding horizontal, borda visível, label de texto inline. Variante `--danger` em tons de ruby.
- `.plan-card__copy-btn` ganhou borda + hover em iris.
- Adicionado `.plan-card__action-label` (line-height: 1).

---

### Arquivos EXCLUÍDOS

Nenhum. Nenhum arquivo foi removido nesta release.

---

### Mudanças no banco de dados

| Tabela | Mudança | Como |
|---|---|---|
| `subscription_plans` | + coluna `slug` (string, único) | Editado in-place na migration v1.4.0 (banco de dev ainda não havia rodado a versão antiga). |
| `subscription_plans` | + coluna `limits` (jsonb, default `{}`) | Mesmo. |
| `subscription_plans` | + index único em `slug` | Mesmo. |

Nenhuma tabela do core foi alterada. Nenhum dado foi destruído.

---

### Operacional / DevOps

- **Restart do Puma necessário** — toda Rails Engine descobre raízes de autoload (`app/controllers/`, `app/models/`, etc.) **uma única vez no boot**. Como o diretório `plugins/assinatura/app/controllers/` foi criado durante esta release, o Puma rodando em modo dev precisou ser reiniciado para registrar o autoload root e resolver `Public::Api::V1::SubscriptionPlansController`. Sem restart, a rota `/public/api/v1/subscription_plans/:slug` cai em `RoutingError` (HTTP 404).
- Em produção (Docker/CI), isso não é problema: o boot já vê todos os arquivos.

---

### Como testar (final)

1. Acesse `/super_admin/subscription_plans` — botões com ícone + label visíveis, URL de checkout copiável no footer de cada card.
2. Crie/edite um plano com nome arbitrário (ex: "Pro"). O slug é auto-gerado (`pro`).
3. Clique no botão de copiar URL → cole no navegador → abre `/checkout.html?plan=pro`.
4. O sumário da sidebar mostra "Plano Pro" + preço cadastrado, sem banner de erro.
5. Aplique um cupom (ex: `BEMVINDO`) → desconto incide sobre o preço dinâmico do plano.
6. Network tab: deve aparecer `GET /public/api/v1/subscription_plans/pro` → `200`.
7. Submeter o formulário → request POST para Asaas com `selected_plan: "pro"` no payload (verificável no Network tab).

---

## Versão 1.4.0 — 2026-04-25

**Autor:** Claude (instruído por Leandro Benuv)
**Escopo:** Plugin `assinatura` — Gerenciamento de Planos de Assinatura e Cupons de Desconto no Super Admin

---

### Resumo geral

Criação do plugin `assinatura`, que adiciona ao Super Admin duas áreas de gestão: (1) **Planos de Assinatura**, com CRUD completo via interface de cards visuais coloridos, seleção de cor, toggle de 12 recursos e preço mensal + anual; (2) **Cupons de Desconto**, com CRUD completo suportando três tipos (trial, desconto percentual, grátis para sempre), geração automática de código, controle de usos e data de expiração. Todo o frontend é em Vue 3 com componentes, composables, API JS e CSS separados por feature.

A arquitetura segue o padrão dos plugins existentes (`agenda`, `ajuda`). Por limitação do Zeitwerk (o autoloader do Rails não permite que dois diretórios diferentes sejam raiz do mesmo namespace), os controllers e dashboards do Administrate que precisam existir no namespace `SuperAdmin::` foram criados no core — exatamente como acontece com os controllers de `help_articles`, `help_categories` e `help_faqs` do plugin `ajuda`.

---

### Arquivos CRIADOS — Plugin `plugins/assinatura/`

#### `plugins/assinatura/lib/assinatura.rb` — CRIADO

Ponto de entrada do engine. Apenas: `require 'assinatura/engine'`.

---

#### `plugins/assinatura/lib/assinatura/engine.rb` — CRIADO

Engine Rails mínima. Sem `isolate_namespace` (para que modelos e classes coexistam no namespace global, compatível com Administrate).

```ruby
module Assinatura
  class Engine < ::Rails::Engine
    engine_name 'assinatura'
  end
end
```

Carregado automaticamente pelo glob `Dir[Rails.root.join('plugins/*/lib/*/engine.rb')]` em `config/application.rb`. Nenhum toque no core necessário para o carregamento.

---

#### `plugins/assinatura/app/models/subscription_plan.rb` — CRIADO

Model ActiveRecord para planos de assinatura.

**Tabela:** `subscription_plans`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `name` | string NOT NULL | Nome do plano |
| `description` | text | Descrição breve |
| `price_monthly` | decimal(10,2) NOT NULL | Preço mensal em R$ |
| `price_yearly` | decimal(10,2) nullable | Preço anual em R$ |
| `color` | string DEFAULT '#5B5BD6' | Cor do card |
| `features` | jsonb DEFAULT [] | Array de chaves de recursos incluídos |
| `active` | boolean DEFAULT true | Se o plano está ativo |
| `display_order` | integer DEFAULT 0 | Ordem de exibição na grade |

Validações: `name` presence, `price_monthly` presence + numericality ≥ 0, `display_order` numericality.
Scopes: `active`, `ordered` (por display_order, name).
Override de `as_json` para serializar decimais como float.

---

#### `plugins/assinatura/app/models/discount_coupon.rb` — CRIADO

Model ActiveRecord para cupons de desconto.

**Tabela:** `discount_coupons`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `code` | string NOT NULL UNIQUE | Código do cupom (salvo em maiúsculas) |
| `description` | string NOT NULL | Descrição do benefício |
| `kind` | string NOT NULL | `trial`, `percent` ou `free_forever` |
| `discount_percent` | integer nullable | Percentual de desconto (kind=percent) |
| `trial_days` | integer nullable | Dias de trial grátis (kind=trial) |
| `months_duration` | integer nullable | Duração em meses (kind=percent) |
| `active` | boolean DEFAULT true | Se o cupom está ativo |
| `max_uses` | integer nullable | Limite de usos (nil = ilimitado) |
| `current_uses` | integer DEFAULT 0 | Usos realizados |
| `expires_at` | datetime nullable | Data de expiração |

Validações condicionais por `kind`. `before_save` normaliza o código para maiúsculas.
Métodos: `expired?`, `uses_exhausted?`, `valid_for_use?`.

---

#### `plugins/assinatura/db/migrate/20260425000001_create_subscription_plans.rb` — CRIADO

Migration que cria a tabela `subscription_plans`. Índices em `active` e `display_order`.

---

#### `plugins/assinatura/db/migrate/20260425000002_create_discount_coupons.rb` — CRIADO

Migration que cria a tabela `discount_coupons`. Índices únicos em `code`, e índices em `kind` e `active`.

---

#### `plugins/assinatura/frontend/shared/constants.js` — CRIADO

Constantes compartilhadas entre as duas features:

- `PLAN_FEATURES` — array de 12 recursos que podem ser incluídos num plano (agenda, pacientes, chatbot, relatórios, API, integrações, central de ajuda, suporte prioritário, sem marca Klivy, domínio personalizado, agentes ilimitados, inboxes ilimitadas)
- `COUPON_KINDS` — array com os 3 tipos de cupom e seus labels em PT-BR
- `PLAN_COLORS` — 8 cores predefinidas para os cards
- `getCsrfToken()` — helper que lê o meta-tag CSRF do Rails
- `formatPrice(value)` — formata número como BRL (Intl.NumberFormat)

---

#### `plugins/assinatura/frontend/shared/assinatura.css` — CRIADO

Design system compartilhado entre Plans e Coupons. Usa os tokens de cor CSS do projeto (`rgb(var(--slate-*))`, `rgb(var(--iris-*))`, `rgb(var(--ruby-*))` etc).

Classes definidas: `.as-page`, `.as-page__header`, `.as-page__title`, `.as-btn` (variantes: `--primary`, `--ghost`, `--danger`, `--sm`), `.as-form-grid`, `.as-field`, `.as-label`, `.as-input`, `.as-textarea`, `.as-select`, `.as-toggle` (switch), `.as-color-picker`, `.as-color-swatch`, `.as-features-grid`, `.as-modal-backdrop`, `.as-modal`, `.as-alert`, `.as-loading`, `.as-empty`, `.as-toast`, `.as-badge` (variantes por kind), `.as-spin`.

---

#### `plugins/assinatura/frontend/features/plans/api/plansApi.js` — CRIADO

Cliente HTTP para a API de planos. Singleton com métodos: `list()`, `create(data)`, `update(id, data)`, `destroy(id)`. Usa `fetch` nativo, envia CSRF token nos métodos de mutação. URL base: `/super_admin/subscription_plans.json`.

---

#### `plugins/assinatura/frontend/features/plans/composables/usePlans.js` — CRIADO

Composable Vue que gerencia o estado da lista de planos: `plans` (ref), `loading`, `error`. Métodos: `fetchPlans()`, `deletePlan(id)`, `upsertPlan(plan)` (faz insert ou update local sem refetch).

---

#### `plugins/assinatura/frontend/features/plans/composables/usePlanForm.js` — CRIADO

Composable Vue que gerencia o estado do formulário de criação/edição de planos: `form` (reactive), `editingId`, `saving`, `formError`. Métodos: `openNew()`, `openEdit(plan)`, `toggleFeature(key)`, `save()`. O `save()` determina automaticamente se é POST ou PATCH pelo `editingId`. Chama `onSuccess(result)` ao salvar.

---

#### `plugins/assinatura/frontend/features/plans/components/PlanFeatureItem.vue` — CRIADO

Botão toggle para um recurso do plano. Props: `featureKey`, `label`, `icon`, `checked`. Emite `toggle`. Visual muda entre estado checked (fundo iris-3, borda iris-7) e unchecked.

---

#### `plugins/assinatura/frontend/features/plans/components/PlanCard.vue` — CRIADO

Card de exibição de um plano. Mostra: barra de cor no topo, nome, descrição, preço mensal formatado, preço anual (se preenchido), lista de recursos ativos com ícone, badge "Inativo" (se `active: false`), ordem de exibição. Botões de editar e excluir. A cor do card vem de `--plan-color` (CSS custom property).

---

#### `plugins/assinatura/frontend/features/plans/components/PlanFormModal.vue` — CRIADO

Modal de criação/edição de planos. Campos: nome, descrição, preço mensal, preço anual, ordem, toggle ativo, color picker (8 cores predefinidas + input texto), grid 2 colunas de `PlanFeatureItem` para os 12 recursos. Emite `save`, `close`, `toggle-feature`.

---

#### `plugins/assinatura/frontend/features/plans/PlansIndex.vue` — CRIADO

Componente raiz da página de planos. Monta `usePlans` e `usePlanForm`. Exibe: header com título + botão "Novo Plano", estado de loading/erro/lista vazia/grid de cards. Grid usa `auto-fill` com mínimo de 300px por coluna. Toast de sucesso/erro fixo no canto inferior direito. Confirmação nativa (`window.confirm`) antes de excluir.

---

#### `plugins/assinatura/frontend/features/plans/plans.css` — CRIADO

CSS da feature de planos. Classes: `.plans-grid`, `.plan-card` (hover com shadow + translateY), `.plan-card__header`, `.plan-card__color-bar`, `.plan-card__badge`, `.plan-card__actions`, `.plan-card__body`, `.plan-card__name`, `.plan-card__pricing`, `.plan-card__features`, `.plan-feature-item` (estado checked/unchecked).

---

#### `plugins/assinatura/frontend/features/coupons/api/couponsApi.js` — CRIADO

Idêntico ao `plansApi.js` mas para cupons. URL base: `/super_admin/discount_coupons.json`.

---

#### `plugins/assinatura/frontend/features/coupons/composables/useCoupons.js` — CRIADO

Idêntico ao `usePlans.js` mas para cupons. `upsertCoupon` faz `unshift` (novo cupom aparece no topo).

---

#### `plugins/assinatura/frontend/features/coupons/composables/useCouponForm.js` — CRIADO

Composable de formulário de cupons. Inclui `generateCode()` que gera um código aleatório de 8 caracteres (charset sem ambiguidade: sem 0/O/1/I). `openNew()` já gera um código automaticamente. `save()` converte campos numéricos com `parseInt` e envia `null` para campos opcionais vazios.

---

#### `plugins/assinatura/frontend/features/coupons/components/CouponCard.vue` — CRIADO

Linha de exibição de um cupom em formato de tabela. Colunas: código (monospace), badge do tipo + resumo do benefício, usos e validade (com indicação "Expirado" em vermelho), botões de ação. `opacity: 0.6` se inativo.

---

#### `plugins/assinatura/frontend/features/coupons/components/CouponFormModal.vue` — CRIADO

Modal de criação/edição de cupons. Campos condicionais por tipo:
- `trial`: input de dias
- `percent`: inputs de percentual e duração em meses
- `free_forever`: badge informativo (sem campos extras)

Campos opcionais comuns: max_uses, expires_at (date picker), toggle ativo. Botão de gerar código automático ao lado do input de código.

---

#### `plugins/assinatura/frontend/features/coupons/CouponsIndex.vue` — CRIADO

Componente raiz da página de cupons. Layout em lista (não grid), com cabeçalho de colunas. Mesmo padrão de loading/erro/vazio/toast que `PlansIndex.vue`.

---

#### `plugins/assinatura/frontend/features/coupons/coupons.css` — CRIADO

CSS da feature de cupons. Classes: `.coupons-list`, `.coupon-card` (grid de 4 colunas: 220px + 1fr + 1fr + auto), `.coupons-header-row`, `.coupon-card__code` (monospace), `.coupon-card__expiry--expired`, `.as-input-group`, `.as-section-divider`, `.coupon-free-badge`.

---

### Arquivos CRIADOS — Core (necessário por limitação do Zeitwerk/Administrate)

> **Por que no core:** O Zeitwerk exige que cada namespace Ruby seja "owned" por um único diretório raiz. Como `SuperAdmin::` já é definido pelo core em `app/controllers/super_admin/`, adicionar controllers com esse namespace num plugin quebra o autoloader. O mesmo vale para os dashboards do Administrate (classes top-level que precisam ser encontradas pelo autoloader global). Este é exatamente o mesmo padrão dos controllers `help_articles`, `help_categories`, `help_faqs` do plugin `ajuda`.

---

#### `app/controllers/super_admin/subscription_plans_controller.rb` — CRIADO (core)

Controller do super admin para planos. Herda de `SuperAdmin::ApplicationController`. Override das actions `index` (responde HTML renderizando Vue OU JSON para o frontend Vue), `create`, `update`, `destroy`. Não usa o sistema de scaffolding do Administrate — apenas autenticação via `authenticate_super_admin!` herdada.

---

#### `app/controllers/super_admin/discount_coupons_controller.rb` — CRIADO (core)

Idêntico ao controller de planos, para cupons.

---

#### `app/dashboards/subscription_plan_dashboard.rb` — CRIADO (core)

Dashboard mínimo do Administrate para `SubscriptionPlan`. Necessário para que o `Administrate::Namespace.resources` não quebre ao escanear as rotas do super admin. Não é usado para renderização real (a UI é o Vue component).

---

#### `app/dashboards/discount_coupon_dashboard.rb` — CRIADO (core)

Idêntico, para `DiscountCoupon`.

---

#### `app/views/super_admin/subscription_plans/index.html.erb` — CRIADO (core)

```erb
<% content_for(:title) { 'Planos de Assinatura' } %>
<%= render_vue_component('AssinaturaPlans') %>
```

Necessário no core porque o resolvedor de views do Administrate procura templates em `super_admin/[controller]/` e faz fallback para `super_admin/application/index.html.erb` antes de verificar os paths do engine.

---

#### `app/views/super_admin/discount_coupons/index.html.erb` — CRIADO (core)

```erb
<% content_for(:title) { 'Cupons de Desconto' } %>
<%= render_vue_component('AssinaturaCoupons') %>
```

Mesmo motivo.

---

### Arquivos MODIFICADOS — Core

#### `config/routes.rb` — MODIFICADO (+3 linhas)

Dentro do `namespace :super_admin`, após as rotas de `help_faqs`:

```ruby
# Planos de Assinatura e Cupons de Desconto — gerenciados via plugin assinatura
resources :subscription_plans, only: [:index, :create, :update, :destroy]
resources :discount_coupons,   only: [:index, :create, :update, :destroy]
```

Nenhuma rota existente foi alterada.

---

#### `app/views/super_admin/application/_navigation.html.erb` — MODIFICADO (+7 linhas)

**Alteração 1** — adicionados `"subscription_plans"` e `"discount_coupons"` à lista de exclusão do auto-nav do Administrate:

```erb
<% next if ["account_users", ..., "help_articles", "help_categories", "help_faqs",
            "subscription_plans", "discount_coupons"].include?(resource.resource) %>
```

**Alteração 2** — adicionado grupo de navegação "Assinatura" após o grupo "Central de Ajuda":

```erb
<%= render 'nav_group',
      icon:  'icon-price-tag-3-line',
      label: 'Assinatura',
      items: [
        { icon: 'icon-stack-line',    url: super_admin_subscription_plans_url, label: 'Planos' },
        { icon: 'icon-coupon-3-line', url: super_admin_discount_coupons_url,   label: 'Cupons' },
      ] %>
```

---

#### `app/javascript/entrypoints/superadmin_pages.js` — MODIFICADO (+4 linhas)

Registrados os dois novos componentes Vue no `ComponentMapping`:

```js
import AssinaturaPlans   from '../../../plugins/assinatura/frontend/features/plans/PlansIndex.vue';
import AssinaturaCoupons from '../../../plugins/assinatura/frontend/features/coupons/CouponsIndex.vue';

const ComponentMapping = {
  // ... existentes ...
  AssinaturaPlans:   AssinaturaPlans,
  AssinaturaCoupons: AssinaturaCoupons,
};
```

---

### Arquivos EXCLUÍDOS (durante desenvolvimento — intermediários)

Durante o desenvolvimento, controllers, dashboards e views foram criados inicialmente dentro do plugin (`plugins/assinatura/app/`) e depois movidos para o core por conta das limitações do Zeitwerk e do Administrate. As cópias do plugin foram removidas:

- `plugins/assinatura/app/controllers/` — removido (movido para core)
- `plugins/assinatura/app/dashboards/` — removido (movido para core)
- `plugins/assinatura/app/views/` — removido (movido para core)

---

### Tabela completa de arquivos — Versão 1.4.0

| Arquivo | Core? | Ação | Motivo |
|---------|-------|------|--------|
| `plugins/assinatura/lib/assinatura.rb` | Não | Criado | Entry point do engine |
| `plugins/assinatura/lib/assinatura/engine.rb` | Não | Criado | Engine Rails |
| `plugins/assinatura/app/models/subscription_plan.rb` | Não | Criado | Model de planos |
| `plugins/assinatura/app/models/discount_coupon.rb` | Não | Criado | Model de cupons |
| `plugins/assinatura/db/migrate/20260425000001_create_subscription_plans.rb` | Não | Criado | Tabela de planos |
| `plugins/assinatura/db/migrate/20260425000002_create_discount_coupons.rb` | Não | Criado | Tabela de cupons |
| `plugins/assinatura/frontend/shared/constants.js` | Não | Criado | Constantes, helpers, cores |
| `plugins/assinatura/frontend/shared/assinatura.css` | Não | Criado | Design system compartilhado |
| `plugins/assinatura/frontend/features/plans/api/plansApi.js` | Não | Criado | HTTP client de planos |
| `plugins/assinatura/frontend/features/plans/composables/usePlans.js` | Não | Criado | Estado da lista de planos |
| `plugins/assinatura/frontend/features/plans/composables/usePlanForm.js` | Não | Criado | Estado do formulário de plano |
| `plugins/assinatura/frontend/features/plans/components/PlanFeatureItem.vue` | Não | Criado | Toggle de recurso |
| `plugins/assinatura/frontend/features/plans/components/PlanCard.vue` | Não | Criado | Card visual de plano |
| `plugins/assinatura/frontend/features/plans/components/PlanFormModal.vue` | Não | Criado | Modal create/edit plano |
| `plugins/assinatura/frontend/features/plans/PlansIndex.vue` | Não | Criado | Página raiz de planos |
| `plugins/assinatura/frontend/features/plans/plans.css` | Não | Criado | CSS da feature de planos |
| `plugins/assinatura/frontend/features/coupons/api/couponsApi.js` | Não | Criado | HTTP client de cupons |
| `plugins/assinatura/frontend/features/coupons/composables/useCoupons.js` | Não | Criado | Estado da lista de cupons |
| `plugins/assinatura/frontend/features/coupons/composables/useCouponForm.js` | Não | Criado | Estado do formulário de cupom |
| `plugins/assinatura/frontend/features/coupons/components/CouponCard.vue` | Não | Criado | Linha de cupom na lista |
| `plugins/assinatura/frontend/features/coupons/components/CouponFormModal.vue` | Não | Criado | Modal create/edit cupom |
| `plugins/assinatura/frontend/features/coupons/CouponsIndex.vue` | Não | Criado | Página raiz de cupons |
| `plugins/assinatura/frontend/features/coupons/coupons.css` | Não | Criado | CSS da feature de cupons |
| `app/controllers/super_admin/subscription_plans_controller.rb` | **Sim** | Criado | Zeitwerk: namespace SuperAdmin no core |
| `app/controllers/super_admin/discount_coupons_controller.rb` | **Sim** | Criado | Zeitwerk: namespace SuperAdmin no core |
| `app/dashboards/subscription_plan_dashboard.rb` | **Sim** | Criado | Administrate: dashboard requerido |
| `app/dashboards/discount_coupon_dashboard.rb` | **Sim** | Criado | Administrate: dashboard requerido |
| `app/views/super_admin/subscription_plans/index.html.erb` | **Sim** | Criado | View resolver Administrate |
| `app/views/super_admin/discount_coupons/index.html.erb` | **Sim** | Criado | View resolver Administrate |
| `config/routes.rb` | **Sim** | +3 linhas | Rotas no namespace super_admin |
| `app/views/super_admin/application/_navigation.html.erb` | **Sim** | +7 linhas | Exclusion list + nav group |
| `app/javascript/entrypoints/superadmin_pages.js` | **Sim** | +4 linhas | Registro dos Vue components |

**Total: 23 arquivos criados no plugin + 6 arquivos criados no core + 3 arquivos modificados no core**

---

### Como ativar

```bash
rails db:migrate
```

Acessar `/super_admin/subscription_plans` e `/super_admin/discount_coupons`.

---

## Versão 1.3.0 — 2026-04-25

**Autor:** Claude (instruído por Leandro Benuv)
**Escopo:** Categorias dinâmicas no banco + redesign completo da UX de busca + substituição do editor por Quill.js

---

### Resumo geral

Esta versão finaliza o sistema de Central de Ajuda com três frentes: (1) categorias passam a ser gerenciadas pelo Super Admin, com suporte a ícone SVG customizado e flag `hidden`; (2) a barra de busca ganha um modo de navegação por categorias com pills horizontais roláveis, drag-to-scroll e filtragem dinâmica; (3) o editor de texto do Super Admin é substituído pelo Quill.js (mesma engine do `@vueup/vue-quill` pedido pelo Leandro).

---

### Backend

#### `db/migrate/20260425200000_create_help_categories.rb` — CRIADO

**Por quê:** Categorias eram hardcoded no frontend. O pedido era permitir criar categorias novas no Super Admin com ícone SVG e controle de visibilidade.

**O que cria:** Tabela `help_categories` com os campos:

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `name` | string NOT NULL | Nome exibido |
| `description` | string | Descrição curta |
| `slug` | string UNIQUE | Chave usada em `help_articles.category` |
| `icon_svg` | text | SVG markup do ícone customizado |
| `icon_class` | string | Classe Lucide (ex: `i-lucide-bolt`) |
| `position` | integer DEFAULT 0 | Ordem de exibição |
| `hidden` | boolean DEFAULT false | Oculta da grade principal se true |

**Seed automático:** As 7 categorias padrão são inseridas via `execute` SQL durante a própria migration. A categoria `outro` recebe `hidden: true` e `position: 99`. Isso garante que artigos existentes não percam sua categoria.

**Não mexe no core:** Cria uma tabela nova e independente. Nenhuma tabela existente do Chatwoot é alterada.

---

#### `app/models/help_category.rb` — CRIADO

**Por quê:** Necessário para o ActiveRecord acessar `help_categories`.

```ruby
class HelpCategory < ApplicationRecord
  validates :name, :slug, presence: true
  validates :slug, uniqueness: true
  scope :ordered, -> { order(:position, :name) }
  scope :visible, -> { where(hidden: false) }
end
```

Não é do core Chatwoot.

---

#### `app/models/help_article.rb` — MODIFICADO

**Por quê:** A validação `validates :category, inclusion: { in: CATEGORIES }` usava uma lista hardcoded. Com categorias dinâmicas, uma nova categoria criada no admin seria invalidada.

**Alteração:** Substituída por validação dinâmica que consulta o banco:

```ruby
validate :category_must_be_valid

def category_must_be_valid
  valid_slugs = HelpCategory.pluck(:slug)
rescue StandardError
  valid_slugs = CATEGORIES   # fallback se tabela não existir ainda
ensure
  errors.add(:category, 'não é uma categoria válida') unless (valid_slugs || CATEGORIES).include?(category.to_s)
end
```

O `rescue` garante retrocompatibilidade se alguém rodar o código antes de migrar.

Não é do core Chatwoot.

---

#### `app/dashboards/help_article_dashboard.rb` — MODIFICADO

**Duas alterações:**

**1. Dropdown de categoria dinâmico (lambda):**
```ruby
# ANTES — avaliado uma única vez no boot do Rails:
collection: (HelpCategory.ordered.pluck(:slug) rescue HelpArticle::CATEGORIES),

# DEPOIS — reavaliado em cada request:
collection: -> { HelpCategory.ordered.pluck(:slug) rescue HelpArticle::CATEGORIES },
```
Com lambda, criar uma nova categoria no admin aparece imediatamente no dropdown de artigos sem reiniciar o servidor.

**2. Exposição de `video_url` no form:**
Adicionado `video_url` a `FORM_ATTRIBUTES`.

---

#### `app/dashboards/help_category_dashboard.rb` — CRIADO

**Por quê:** O Administrate exige um dashboard file para cada model gerenciado.

**Campos disponíveis no formulário:** `name`, `description`, `slug`, `icon_class` (Lucide), `icon_svg` (textarea para SVG bruto), `position`, `hidden` (boolean toggle).

**Como usar o `icon_svg`:** Cole o conteúdo completo da tag `<svg>...</svg>` do ícone. O frontend aplica cor e tamanho automaticamente via CSS (`fill: currentColor`).

---

#### `app/controllers/super_admin/help_categories_controller.rb` — CRIADO

**Por quê:** Necessário para o Administrate gerenciar o CRUD de `HelpCategory`.

Herda de `SuperAdmin::ApplicationController`. Override de `scoped_resource` para ordenar por posição. `resource_params` permite: `name, description, slug, icon_class, icon_svg, position, hidden`.

**Acesso:** `/super_admin/help_categories`

---

#### `app/controllers/public/api/v1/help_articles_controller.rb` — MODIFICADO

**Adicionada a action `categories`:**

```ruby
def categories
  render json: HelpCategory.ordered.map { |c| serialize_category(c) }
rescue StandardError
  render json: []
end
```

**URL:** `GET /public/api/v1/help_articles/categories` (sem autenticação)

**Retorna:** array com `id` (slug), `name`, `description`, `icon_svg`, `icon_class`, `hidden`, `position`.

O `rescue StandardError` garante que a rota nunca retorne 500 (retorna `[]` se a tabela não existir).

---

#### `config/routes.rb` — MODIFICADO (core Chatwoot)

**Duas adições cirúrgicas:**

```ruby
# Dentro do namespace super_admin (~linha 898):
resources :help_categories, only: [:index, :new, :create, :show, :edit, :update, :destroy]

# Dentro do namespace public/api/v1 (~linha 794):
resources :help_articles, only: [:index, :show] do
  collection do
    get :categories
  end
end
```

Nenhuma rota existente foi alterada.

---

### Frontend (plugin `ajuda`)

#### `plugins/ajuda/frontend/features/help/data/helpData.js` — MODIFICADO

Adicionado `hidden: true` à entrada `outro` do `CATEGORIES_META`. Garante que o fallback estático se comporte igual ao dado do banco quando a API não responde.

---

#### `plugins/ajuda/frontend/features/help/composables/useHelpData.js` — REESCRITO

**Por quê:** Passou a buscar categorias do banco além dos artigos, para pegar `icon_svg`, `hidden` e `position`.

**Principais mudanças:**
- Duas fetches em paralelo com `Promise.all`: `/help_articles` e `/help_articles/categories`
- Se a API de categorias responder, usa esses dados (com `iconSvg` e `hidden`)
- Fallback para `CATEGORIES_META` se a API falhar ou retornar vazio
- Cada categoria normalizada recebe: `id`, `name`, `description`, `icon`, `iconSvg`, `hidden`, `articles`, `count`

---

#### `plugins/ajuda/frontend/features/help/components/HelpCategoryGrid.vue` — REESCRITO

**Mudanças:**

**1. Filtragem de categorias ocultas:**
```js
const visibleCategories = computed(() => props.categories.filter(c => !c.hidden));
```
A grade exibe apenas categorias com `hidden: false`. A categoria "Outros" some da grade mas continua acessível via busca.

**2. Contador inclui todas as categorias:**
```js
const totalArticles = computed(() =>
  props.categories.reduce(...)  // ALL, não só visibleCategories
);
```
Artigos da categoria "Outros" somam ao total mesmo sem aparecer na grade.

**3. Suporte a ícone SVG:**
```html
<span v-if="cat.iconSvg" v-html="cat.iconSvg" />
<span v-else :class="cat.icon" />
```

---

#### `plugins/ajuda/frontend/features/help/components/HelpSearchBar.vue` — REESCRITO (múltiplas iterações)

Esta foi a alteração mais iterativa. Estado final:

**Estrutura do dropdown (sempre que `focused = true`):**
```
┌─────────────────────────────────────────┐
│ EXPLORAR POR CATEGORIA                  │
│ [pill] [pill] [pill] [pill] → scroll →  │
├─────────────────────────────────────────┤
│ (se query digitado)                     │
│   N resultados                          │
│   [artigo] [artigo] ...                 │
│ (se categoria selecionada, sem query)   │
│   NOME DA CATEGORIA · N artigos         │
│   [artigo] [artigo] ...                 │
└─────────────────────────────────────────┘
```

**Comportamento das pills:**
- Pills NUNCA somem enquanto o dropdown estiver aberto
- Clicar em uma pill: destaca em azul (`.hp-browse-pill--active`), centraliza a pill no scroll via `scrollTo({ behavior: 'smooth' })` usando `nextTick`, exibe artigos da categoria abaixo
- Clicar na mesma pill novamente: deseleciona
- Digitar filtra as pills para mostrar apenas categorias com artigos que mencionam o termo
- Escape: deseleciona categoria → fecha dropdown

**Drag-to-scroll:**
```js
// Threshold de 4px evita disparar scroll em clicks normais
if (Math.abs(delta) > 4) {
  drag.moved = true;
  drag.el.scrollLeft = drag.scrollLeft - delta;
}
```
Cursor muda para `grabbing` durante arrasto.

**Centralização da pill selecionada:**
```js
async function scrollPillToCenter(catId) {
  await nextTick();
  const btn = container.querySelector(`[data-cat-id="${catId}"]`);
  container.scrollTo({
    left: btn.offsetLeft - container.offsetWidth / 2 + btn.offsetWidth / 2,
    behavior: 'smooth',
  });
}
```

---

#### `plugins/ajuda/frontend/features/help/help.css` — MODIFICADO (múltiplas adições)

**Adições desta versão:**

```css
/* Pills horizontais roláveis */
.hp-browse-pills { display: flex; flex-wrap: nowrap; overflow-x: auto;
                   scrollbar-width: none; cursor: grab; user-select: none; }
.hp-browse-pills::-webkit-scrollbar { display: none; }
.hp-browse-pill { border: 1.5px solid slate-5; border-radius: 20px;
                  white-space: nowrap; flex-shrink: 0; }
.hp-browse-pill--active { background: blue-3; border-color: blue-7; font-weight: 600; }
.hp-browse-pill:hover { background: blue-3; border-color: blue-6; }

/* Lista de artigos da categoria (com scroll máx ~5 itens) */
.hp-cat-art-list { max-height: 290px; overflow-y: auto; }

/* Rótulo de navegação */
.hp-results-label--nav { display: flex; align-items: center; gap: 6px; }
.hp-back-btn { width: 20px; height: 20px; border-radius: 5px; ... }
.hp-label-meta { color: slate-9; font-weight: 400; }

/* SVG inline nas categorias */
.hp-cat-svg-icon svg { width: 18px; height: 18px; fill: currentColor; }
.hp-browse-pill-svg svg { width: 13px; height: 13px; fill: currentColor; }
```

---

### Editor de texto — Substituição por Quill.js

#### Contexto

O editor anterior usava `contenteditable` + `document.execCommand()` (API depreciada e com comportamento inconsistente entre navegadores). O Leandro pediu para substituir pelo `@vueup/vue-quill` (https://vueup.github.io/). Como o Super Admin é Rails + ERB (não Vue), foi usado o Quill.js diretamente — a engine subjacente, com resultado idêntico.

---

#### `package.json` + `pnpm-lock.yaml` — MODIFICADO (core)

```bash
pnpm add quill
# Versão instalada: quill@2.0.3
```

Quill é a única nova dependência de produção adicionada ao projeto.

---

#### `app/javascript/superadmin_pages/quill_editor.js` — CRIADO

**O que faz:**
1. Importa `Quill` de `quill` e o CSS do tema Snow de `quill/dist/quill.snow.css`
2. No `DOMContentLoaded`, inicializa um editor Quill em cada `.ha-quill-wrap` encontrado
3. Carrega HTML existente via `quill.clipboard.dangerouslyPasteHTML(initialHTML)`
4. Sincroniza com `<input hidden>` a cada `text-change` via `quill.getSemanticHTML()`
5. Adiciona manualmente um botão `</>` ao toolbar para modo HTML bruto
6. No `submit` do form, faz sync final garantindo que nenhuma edição se perca

**Toolbar configurada:**
- `[{ header: [2, 3, false] }]` — parágrafo, H2, H3
- `['bold', 'italic', 'underline', 'strike']`
- `[{ list: 'ordered' }, { list: 'bullet' }]`
- `['blockquote', 'code-block']`
- `['link']`
- `['clean']`
- `</>` — botão customizado adicionado após init para modo HTML

**Modo HTML bruto:**
```js
if (htmlMode) {
  htmlTextarea.value = quill.getSemanticHTML();
  quillContainer.style.display = 'none';
  htmlTextarea.style.display = 'block';
} else {
  quill.clipboard.dangerouslyPasteHTML(htmlTextarea.value);
  htmlTextarea.style.display = 'none';
  quillContainer.style.display = '';
}
```

---

#### `app/javascript/entrypoints/superadmin.js` — MODIFICADO (core)

```js
import '../dashboard/assets/scss/super_admin/index.scss';
import '../superadmin_pages/quill_editor.js';  // ← ADICIONADO
```

Este entry point é carregado em **todas** as páginas do Super Admin via `vite_javascript_tag 'superadmin'` no layout. Ao importar aqui, o Quill fica ativo em qualquer página com `RichTextField`.

---

#### `app/views/fields/rich_text_field/_form.html.erb` — REESCRITO

**Antes:** DIV contenteditable com toolbar manual (vanilla JS) e `document.execCommand()`.

**Depois:** HTML mínimo que o Quill.js enhance no `DOMContentLoaded`:

```erb
<div class="ha-quill-wrap" data-field-name="<%= field.attribute %>">
  <div class="ha-quill-editor"></div>
  <textarea class="ha-quill-html-textarea" style="display:none;"></textarea>
  <%= f.hidden_field field.attribute, class: 'ha-quill-hidden', value: field.data.to_s %>
</div>
```

**CSS inline incluído no template** (sem arquivo separado para auto-contenção):
- Sobrescreve estilos Snow para combinar com o design do admin (borda arredondada, cor do toolbar, placeholder)
- `.ql-html-toggle` — botão customizado estilizado
- `.ha-quill-html-textarea` — monospace, fundo cinza suave

**Compatibilidade retroativa:** HTML existente nos artigos (`<p>`, `<h2>`, `<ul>` etc) é carregado corretamente via `dangerouslyPasteHTML`. O `getSemanticHTML()` salva HTML equivalente. Nenhuma migração de dados necessária.

---

### Tabela de todos os arquivos desta versão (1.3.0)

| Arquivo | Core? | Ação | Impacto no Core |
|---------|-------|------|----------------|
| `db/migrate/20260425200000_create_help_categories.rb` | Não | Criado | Nenhum |
| `app/models/help_category.rb` | Não | Criado | Nenhum |
| `app/models/help_article.rb` | Não | Modificado | Nenhum |
| `app/dashboards/help_article_dashboard.rb` | Não | Modificado | Nenhum |
| `app/dashboards/help_category_dashboard.rb` | Não | Criado | Nenhum |
| `app/controllers/super_admin/help_articles_controller.rb` | Não | Modificado | Nenhum |
| `app/controllers/super_admin/help_categories_controller.rb` | Não | Criado | Nenhum |
| `app/controllers/public/api/v1/help_articles_controller.rb` | Não | Modificado | Nenhum |
| `config/routes.rb` | **Sim** | +4 linhas | Nenhum (só adição) |
| `app/javascript/entrypoints/superadmin.js` | **Sim** | +1 linha import | Nenhum |
| `app/javascript/superadmin_pages/quill_editor.js` | Não | Criado | Nenhum |
| `app/views/fields/rich_text_field/_form.html.erb` | Não | Reescrito | Nenhum |
| `package.json` / `pnpm-lock.yaml` | **Sim** | +quill@2.0.3 | Nenhum |
| `plugins/ajuda/frontend/features/help/composables/useHelpData.js` | Não | Reescrito | Nenhum |
| `plugins/ajuda/frontend/features/help/data/helpData.js` | Não | +`hidden: true` | Nenhum |
| `plugins/ajuda/frontend/features/help/components/HelpCategoryGrid.vue` | Não | Reescrito | Nenhum |
| `plugins/ajuda/frontend/features/help/components/HelpSearchBar.vue` | Não | Reescrito | Nenhum |
| `plugins/ajuda/frontend/features/help/help.css` | Não | +~110 linhas | Nenhum |

---

## Versão 1.2.0 — 2026-04-25

**Autor:** Claude (instruído por Leandro Benuv)
**Escopo:** Editor de artigos — vídeo embed, próximos passos, modo HTML, expand mode + correções de reatividade

---

### Resumo geral

Refinamentos no drawer de artigos e no editor do Super Admin. Corrigido bug de reatividade no contador de artigos. Adicionados: embed de vídeo YouTube/Vimeo no drawer, campo "Próximos passos" editável no Super Admin, modo HTML bruto no editor, e botão de "modo leitura" que centraliza o drawer na tela.

---

### Backend

#### `db/migrate/20260425100001_add_next_steps_to_help_articles.rb` — CRIADO

```ruby
class AddNextStepsToHelpArticles < ActiveRecord::Migration[7.0]
  def change
    add_column :help_articles, :next_steps, :text
  end
end
```

**Por quê:** O drawer exibia "Próximos passos" como texto estático. Para torná-lo editável, foi preciso adicionar a coluna no banco.

---

#### `app/dashboards/help_article_dashboard.rb` — MODIFICADO

- Adicionado `next_steps: Field::Text` ao `ATTRIBUTE_TYPES`
- Adicionado `next_steps` a `SHOW_PAGE_ATTRIBUTES` e `FORM_ATTRIBUTES` (entre `body` e `category`)
- Adicionado `video_url` a `FORM_ATTRIBUTES`

---

#### `app/controllers/super_admin/help_articles_controller.rb` — MODIFICADO

Adicionado `:next_steps` ao `resource_params` permit list. Sem isso, o campo era bloqueado pelo Strong Parameters do Rails e nunca salvo.

---

#### `app/controllers/public/api/v1/help_articles_controller.rb` — MODIFICADO

Adicionado `next_steps: article.next_steps.to_s` ao método `serialize`. Sem isso, o frontend não recebia o valor.

---

### Frontend

#### `plugins/ajuda/frontend/features/help/composables/useHelpData.js` — MODIFICADO

Adicionado `nextSteps: art.next_steps ?? ''` à função `normalizeArticle`. Sem isso, o campo chegaria como `undefined` nos componentes.

---

#### `plugins/ajuda/frontend/features/help/components/HelpArticleDrawer.vue` — REESCRITO

**4 funcionalidades adicionadas:**

**1. Remoção do callout "Dica" (bloco com dica sobre ⌘K):**
Estava hardcoded no template. Removido completamente.

**2. Embed de vídeo:**
```js
const videoEmbedUrl = computed(() => {
  const url = props.data?.art?.videoUrl;
  if (!url) return null;
  const yt = url.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/)([^&\s]+)/);
  const vi = url.match(/vimeo\.com\/(\d+)/);
  if (yt) return `https://www.youtube.com/embed/${yt[1]}`;
  if (vi) return `https://player.vimeo.com/video/${vi[1]}`;
  return null;
});
```
Renderiza `<iframe>` com aspect-ratio 16/9 acima do corpo do artigo.

**3. "Próximos passos" dinâmico:**
```js
const nextStepsList = computed(() => {
  const raw = props.data?.art?.nextSteps ?? '';
  return raw.split('\n').map(s => s.trim()).filter(Boolean);
});
```
Cada linha do campo `next_steps` vira um `<li>`. A seção só aparece se houver itens.

**4. Modo leitura (expand):**
Botão `i-lucide-maximize-2` no cabeçalho. Ao clicar, adiciona `.hp-drawer--expanded` ao `<aside>`. Reseta via `watch` ao trocar de artigo.

---

#### `plugins/ajuda/frontend/features/help/components/HelpCategoryGrid.vue` — MODIFICADO

`totalArticles` estava como atribuição direta (avaliada uma vez no setup, antes da API responder). Envolvido em `computed()` para recalcular reativamente.

---

#### `plugins/ajuda/frontend/features/help/data/helpData.js` — MODIFICADO

Adicionada entrada `{ id: 'outro', name: 'Outros', ... }` ao `CATEGORIES_META`. Sem isso, artigos com `category: 'outro'` eram descartados silenciosamente pelo composable (que faz `grouped[cat.id]` e só considera IDs presentes no array).

---

#### `plugins/ajuda/frontend/features/help/components/HelpSearchBar.vue` — MODIFICADO

Busca passou a incluir o corpo do artigo além do título:

```js
const bodyText = (art.body ?? '').replace(/<[^>]*>/g, ' ').toLowerCase();
if (art.title.toLowerCase().includes(q) || cat.name.toLowerCase().includes(q) || bodyText.includes(q)) {
```

O `.replace(/<[^>]*>/g, ' ')` remove tags HTML antes de buscar para evitar falsos positivos (ex: buscar "p" não retorna todos os artigos por causa da tag `<p>`).

---

#### `app/views/fields/rich_text_field/_form.html.erb` — MODIFICADO

Adicionado botão `</>` na toolbar que alterna entre editor visual e textarea de HTML bruto:
- Ao ativar: o `innerHTML` do editor é copiado para a textarea; o editor é ocultado
- Ao desativar: o conteúdo da textarea é copiado de volta para o editor
- Outros botões ficam desabilitados no modo HTML (`if (htmlMode) return`)

---

#### `plugins/ajuda/frontend/features/help/help.css` — MODIFICADO

**Adições da versão 1.2.0:**
```css
/* Embed de vídeo no drawer */
.hp-art-video { margin: 16px 0; border-radius: 10px; overflow: hidden; }
.hp-art-video iframe { width: 100%; aspect-ratio: 16/9; display: block; border: 0; }

/* Botão de expandir no cabeçalho */
.hp-drawer-expand-btn { ... }

/* Modo leitura centralizado */
.hp-drawer--expanded {
  top: 4vh !important;
  right: 50% !important;
  transform: translateX(50%) !important;
  width: min(860px, 82vw) !important;
  height: 92vh !important;
  border-radius: 18px !important;
  box-shadow: 0 24px 80px rgba(0,0,0,0.22) !important;
}
.hp-drawer--expanded .hp-drawer-body { padding: 36px 56px 80px; }
.hp-drawer--expanded .hp-drawer-body h1 { font-size: 28px; }
.hp-drawer--expanded .hp-art-body { font-size: 15.5px; line-height: 1.8; }

/* Transição suave entre compacto e expandido */
.hp-drawer { transition: width 300ms, top 300ms, height 300ms, right 300ms, ... }
```

---

### Tabela de todos os arquivos desta versão (1.2.0)

| Arquivo | Core? | Ação |
|---------|-------|------|
| `db/migrate/20260425100001_add_next_steps_to_help_articles.rb` | Não | Criado |
| `app/dashboards/help_article_dashboard.rb` | Não | Modificado |
| `app/controllers/super_admin/help_articles_controller.rb` | Não | Modificado |
| `app/controllers/public/api/v1/help_articles_controller.rb` | Não | Modificado |
| `plugins/ajuda/frontend/features/help/composables/useHelpData.js` | Não | Modificado |
| `plugins/ajuda/frontend/features/help/components/HelpArticleDrawer.vue` | Não | Reescrito |
| `plugins/ajuda/frontend/features/help/components/HelpCategoryGrid.vue` | Não | Modificado |
| `plugins/ajuda/frontend/features/help/data/helpData.js` | Não | Modificado |
| `plugins/ajuda/frontend/features/help/components/HelpSearchBar.vue` | Não | Modificado |
| `app/views/fields/rich_text_field/_form.html.erb` | Não | Modificado |
| `plugins/ajuda/frontend/features/help/help.css` | Não | Modificado |

---

## Versão 1.1.0

**Data:** 2026-04-24
**Autor:** Claude (instruído por Leandro Benuv)
**Escopo:** CMS de artigos no Super Admin + API pública + frontend dinâmico

---

## Resumo geral

Criação de um sistema completo de gestão de artigos de ajuda integrado ao Super Admin. O super administrador agora pode criar, editar e excluir artigos com editor rich text diretamente no painel `/super_admin/help_articles`. Ao publicar um artigo, ele aparece automaticamente na Central de Ajuda para todos os usuários do sistema via API pública.

---

## Arquivos CRIADOS — Backend

### Novos arquivos (não modificam nada existente)

| Arquivo | Descrição |
|---|---|
| `db/migrate/20260424100000_create_help_articles.rb` | Migration que cria a tabela `help_articles` com campos: `title`, `body` (HTML), `category`, `status`, `video_url`, `position`, `deleted_at` (soft delete), timestamps. Índices em `category`, `status`, `deleted_at` e `[status, category]` |
| `app/models/help_article.rb` | Model ActiveRecord com validações, escopos (`published`, `by_category`, `visible`, `ordered`), método `search(query)` por título e corpo, `reading_time` e `soft_delete!` |
| `app/fields/rich_text_field.rb` | Campo customizado do Administrate (`RichTextField < Administrate::Field::Base`). Exibe preview em texto puro na listagem |
| `app/views/fields/rich_text_field/_index.html.erb` | Partial de listagem: mostra os primeiros 120 chars sem HTML |
| `app/views/fields/rich_text_field/_show.html.erb` | Partial de detalhe: renderiza o HTML do corpo com segurança |
| `app/views/fields/rich_text_field/_form.html.erb` | Partial de formulário: editor rich text com toolbar vanilla JS (negrito, itálico, H2, H3, lista, destaque, vídeo YouTube/Vimeo, link). Sem dependências npm. Sincroniza com `<input hidden>` via `execCommand` |
| `app/dashboards/help_article_dashboard.rb` | Dashboard Administrate com `ATTRIBUTE_TYPES`, `COLLECTION_ATTRIBUTES`, `SHOW_PAGE_ATTRIBUTES`, `FORM_ATTRIBUTES` e filtros `published`/`draft` |
| `app/controllers/super_admin/help_articles_controller.rb` | Controller do Super Admin. Herda de `SuperAdmin::ApplicationController`. Scoped para não mostrar deletados. Override do `destroy` para usar soft delete |
| `app/controllers/public/api/v1/help_articles_controller.rb` | API pública (sem autenticação). Herda de `PublicController`. Endpoints: `GET /public/api/v1/help_articles` (com filtros `?category=` e `?q=`) e `GET /public/api/v1/help_articles/:id` |

---

## Arquivos MODIFICADOS — Core do sistema

### 1. `config/routes.rb`

**Modificação 1** — dentro do `namespace :super_admin`:
```ruby
# Artigos da Central de Ajuda — gerenciados via plugin ajuda
resources :help_articles, only: [:index, :new, :create, :show, :edit, :update, :destroy]
```

**Modificação 2** — dentro de `namespace :public > :api > :v1`:
```ruby
# API pública dos artigos da Central de Ajuda (sem autenticação)
resources :help_articles, only: [:index, :show]
```

**Impacto:** Apenas adição de rotas. Nenhuma rota existente foi alterada.

---

## Arquivos MODIFICADOS — Frontend (plugin)

| Arquivo | O que mudou |
|---|---|
| `plugins/ajuda/frontend/features/help/data/helpData.js` | Exporta `CATEGORIES_META` (sem artigos dinâmicos, com fallback estático). Mantém alias `CATEGORIES` para retrocompatibilidade. Corpos dos artigos migrados para HTML string |
| `plugins/ajuda/frontend/features/help/HelpIndex.vue` | Passa a usar o composable `useHelpData`. Passa `categories` e `faqs` como props para os componentes filhos |
| `plugins/ajuda/frontend/features/help/components/HelpCategoryGrid.vue` | Aceita `categories` como prop em vez de importar diretamente |
| `plugins/ajuda/frontend/features/help/components/HelpFaq.vue` | Aceita `categories` e `faqs` como props |
| `plugins/ajuda/frontend/features/help/components/HelpSearchBar.vue` | Aceita `categories` como prop |
| `plugins/ajuda/frontend/features/help/components/HelpArticleDrawer.vue` | Renderiza `body` como HTML string (API) ou array de parágrafos (fallback estático) |
| `plugins/ajuda/frontend/features/help/help.css` | Adicionados estilos `.hp-art-body` para renderização do HTML vindo da API (p, h2, h3, ul, blockquote, iframe, links) |

---

## Arquivos CRIADOS — Frontend (plugin)

| Arquivo | Descrição |
|---|---|
| `plugins/ajuda/frontend/features/help/composables/useHelpData.js` | Composable Vue que busca artigos em `GET /public/api/v1/help_articles`, agrupa por categoria e faz merge com `CATEGORIES_META`. Em caso de erro de rede, mantém os dados estáticos como fallback sem quebrar a UI |

---

## Estrutura final de arquivos do plugin

```
plugins/
└── ajuda/
    └── frontend/
        ├── routes/
        │   └── routes.js
        └── features/
            └── help/
                ├── HelpIndex.vue
                ├── help.css
                ├── data/
                │   └── helpData.js
                ├── composables/
                │   └── useHelpData.js          ← NOVO
                └── components/
                    ├── HelpSearchBar.vue
                    ├── HelpBanner.vue
                    ├── HelpCategoryGrid.vue
                    ├── HelpFaq.vue
                    └── HelpArticleDrawer.vue
```

---

## Como usar

1. Rodar a migration: `rails db:migrate`
2. Acessar `/super_admin/help_articles`
3. Criar artigo, escolher categoria (conversas/agenda/pacientes/financeiro/bea/configuracoes/outro), escrever com o editor rich text, definir status `published`
4. O artigo aparece automaticamente na Central de Ajuda em `/accounts/:id/ajuda`

---

## Versão 1.0.0

**Data:** 2026-04-24
**Autor:** Claude (instruído por Leandro Benuv)
**Escopo:** Criação do plugin `ajuda` — Central de Ajuda da KlivyApp

---

## Resumo geral

Foi criado um novo plugin chamado `ajuda`, seguindo a mesma arquitetura dos plugins existentes (`agenda`, `financial`, `patients`, etc.). O plugin adiciona uma página de Central de Ajuda acessível pelo menu lateral do sistema, com busca de artigos, categorias, FAQ, drawer de artigos e integração com o chat real do Chatwoot.

---

## Arquivos CRIADOS (novos — dentro do plugin)

Todos os arquivos abaixo foram criados do zero dentro da pasta `/plugins/ajuda/`, que não existia antes.

| Arquivo | Descrição |
|---|---|
| `plugins/ajuda/frontend/routes/routes.js` | Define a rota `/accounts/:accountId/ajuda` apontando para `HelpIndex.vue` |
| `plugins/ajuda/frontend/features/help/HelpIndex.vue` | Componente raiz da página. Gerencia estado global: `drawerData`, função `openArticle`, `openCategory` e `openChat` |
| `plugins/ajuda/frontend/features/help/help.css` | Folha de estilos completa do módulo. Usa prefixo `hp-` para evitar colisão com estilos globais. Usa tokens de design do sistema (`rgb(var(--slate-*))`, `var(--color-woot-500)`, `rgb(var(--blue-*))`) |
| `plugins/ajuda/frontend/features/help/data/helpData.js` | Dados mockados: exporta `CATEGORIES` (6 categorias com artigos) e `FAQS` (7 perguntas frequentes com resposta, categoria e tags) |
| `plugins/ajuda/frontend/features/help/components/HelpSearchBar.vue` | Barra de busca com atalho `⌘K`, dropdown de resultados com highlight do termo pesquisado, detecção de clique fora para fechar |
| `plugins/ajuda/frontend/features/help/components/HelpBanner.vue` | Banner "Precisa de ajuda? Fale com o nosso time agora." com botão que abre o chat real do Chatwoot |
| `plugins/ajuda/frontend/features/help/components/HelpCategoryGrid.vue` | Grid 3 colunas com as categorias de artigos. Emite `openCategory` ao clicar |
| `plugins/ajuda/frontend/features/help/components/HelpFaq.vue` | Seção de perguntas frequentes com filtro por categoria (chips) e accordion animado via CSS grid (`grid-template-rows: 0fr → 1fr`) |
| `plugins/ajuda/frontend/features/help/components/HelpArticleDrawer.vue` | Drawer lateral (via `<Teleport to="body">`) com duas views: lista de artigos por categoria e leitura de artigo com feedback "foi útil?" |

> **Nota:** O arquivo `HelpChatPanel.vue` foi criado inicialmente como um chat simulado e posteriormente **deletado** a pedido do Leandro, substituído pela integração com o widget real do Chatwoot.

---

## Arquivos MODIFICADOS fora do plugin (código do sistema)

Foram feitas alterações mínimas e cirúrgicas em 4 arquivos do core do sistema para registrar o novo plugin. Nenhuma lógica existente foi alterada — apenas adições.

### 1. `app/javascript/dashboard/routes/dashboard/dashboard.routes.js`

**O que foi modificado:** Adicionadas 2 linhas — import das rotas do plugin e spread no array `children`.

```js
// Linha adicionada no topo (imports)
import { routes as ajudaRoutes } from '@plugins/ajuda/frontend/routes/routes';

// Linha adicionada dentro do array children das rotas
...ajudaRoutes,
```

**Impacto:** Nenhum efeito sobre rotas existentes. Apenas registra a nova rota `/ajuda`.

---

### 2. `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`

**O que foi modificado:** Adicionado 1 objeto no array `menuItems` (computed), após o bloco de "Configurações".

```js
{
  name: 'Ajuda',
  icon: 'i-lucide-circle-help',
  label: t('SIDEBAR.AJUDA', 'Ajuda'),
  to: accountScopedRoute('ajuda_dashboard_index'),
  activeOn: ['ajuda_dashboard_index'],
},
```

**Impacto:** Aparece um novo item "Ajuda" no menu lateral, abaixo de "Configurações". Nenhum item existente foi alterado.

---

### 3. `app/javascript/dashboard/i18n/locale/pt_BR/settings.json`

**O que foi modificado:** Adicionada 1 chave dentro do objeto `SIDEBAR`.

```json
"AJUDA": "Ajuda"
```

**Impacto:** Apenas tradução do novo item de menu. Nenhuma chave existente foi tocada.

---

### 4. `app/javascript/dashboard/i18n/locale/en/settings.json`

**O que foi modificado:** Adicionada 1 chave dentro do objeto `SIDEBAR`.

```json
"AJUDA": "Help"
```

**Impacto:** Idem ao arquivo pt_BR — apenas tradução do novo item de menu.

---

## Integração com o chat real (Chatwoot)

O botão "Iniciar conversa" no banner **não abre nenhum componente próprio**. Ele aciona o widget nativo do Chatwoot já presente no sistema via:

```js
function openChat() {
  const bubble = document.querySelector('.woot-widget-bubble:not(.woot--close):not(.woot--hide)');
  bubble?.click();
}
```

O widget Chatwoot (`#cw-bubble-holder`) já está renderizado na página pelo sistema. Este código apenas simula um clique no botão dele.

---

## Estrutura final de arquivos do plugin

```
plugins/
└── ajuda/
    └── frontend/
        ├── routes/
        │   └── routes.js
        └── features/
            └── help/
                ├── HelpIndex.vue
                ├── help.css
                ├── data/
                │   └── helpData.js
                └── components/
                    ├── HelpSearchBar.vue
                    ├── HelpBanner.vue
                    ├── HelpCategoryGrid.vue
                    ├── HelpFaq.vue
                    └── HelpArticleDrawer.vue
```

---

## Convenções seguidas

- Prefixo `hp-` em todas as classes CSS para não colidir com estilos globais
- Tokens de design do sistema (`--slate-*`, `--color-woot-*`, `--blue-*`) em vez de cores hardcoded
- Arquitetura de componentes isolados com responsabilidade única
- Dados mockados em arquivo separado (`helpData.js`) prontos para substituição por chamadas de API
- `<Teleport to="body">` nos overlays para garantir z-index correto acima do sidebar
