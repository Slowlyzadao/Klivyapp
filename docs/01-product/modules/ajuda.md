# Módulo Central de Ajuda (`plugins/ajuda`)

> [!IMPORTANT]
> **Nota de Auditoria Arquitetural:**
> Este módulo é um **Rails Engine isolado** em `plugins/ajuda/`. Todos os modelos novos vivem em namespaces próprios e o frontend é Vue 3 isolado em `plugins/ajuda/frontend/`. Toques no core do Chatwoot foram cirúrgicos e estão **explicitamente listados** na seção *Histórico evolutivo* — **nenhum arquivo do core foi reescrito ou teve lógica existente alterada**. Restrições do Administrate (gem do Super Admin) e do Zeitwerk (autoloader Ruby) obrigaram alguns controllers/dashboards a serem registrados na árvore `app/` do core, mas com lógica mínima — apenas o necessário para o gem reconhecer o recurso.

---

## 📌 Visão Geral

A **Central de Ajuda** é a área pública (logada) onde os usuários da KlivyApp consultam artigos, FAQs e tutoriais de uso do produto. Funciona como uma documentação contextual, com busca por título/categoria/conteúdo, navegação por categorias visuais e drawer de leitura.

Toda a curadoria (criação, edição, publicação de artigos e categorias) acontece num CMS embutido no **Super Admin** (`/super_admin/help_articles` e `/super_admin/help_categories`).

**Acesso do usuário:** Sidebar lateral → "Ajuda" (dropdown) → `/accounts/:id/ajuda`
**Acesso do admin:** `/super_admin/help_articles`, `/super_admin/help_categories`

A partir de 2026-04-26, o item **"Ajuda"** no sidebar virou **dropdown** com 3 filhos:

| Item | Rota | Descrição |
|------|------|-----------|
| 📖 Artigos | `/accounts/:id/ajuda` | FAQ original (intacta) |
| 🐛 Reportar um erro | `/accounts/:id/ajuda/reportar-erro` | Formulário de bug report |
| ✨ Solicitar melhoria | `/accounts/:id/ajuda/solicitar-melhoria` | Formulário de feature request |

---

## 🎯 Funcionalidades

### Para o usuário final
- 🔎 **Busca rápida** com atalho `⌘K` que pesquisa em título, descrição da categoria e conteúdo do corpo (HTML stripado)
- 🗂 **Navegação por categorias** via pills horizontais roláveis (drag-to-scroll) — seleciona uma categoria e vê apenas os artigos dela
- 📂 **Grade de categorias** com ícone customizável (SVG inline ou classe Lucide)
- ❓ **Seção de FAQ** com filtro por categoria (chips) e accordion animado
- 📖 **Drawer de leitura** com `Teleport` para body, suporte a embed de vídeo (YouTube/Vimeo) e seção "Próximos passos"
- 📺 **Modo leitura** que centraliza o drawer na tela em formato wide (botão maximize)
- 💬 **Botão "Iniciar conversa"** que aciona o widget nativo de chat do Chatwoot (`#cw-bubble-holder`)
- 🐛 **Reportar um erro** — formulário com nome/e-mail pré-preenchidos do usuário logado, descrição livre e até 5 anexos (JPG/PNG/MP4/PDF, 20MB cada)
- ✨ **Solicitar melhoria** — mesmo formulário com copy adaptada para sugestões de funcionalidade

### Para o super admin
- ✏️ **CRUD de artigos** com editor Quill.js (toolbar: H2/H3, bold/italic/underline/strike, listas, blockquote, code, link)
- 🔧 **Modo HTML bruto** (botão `</>` no toolbar) que alterna entre WYSIWYG e textarea para colar HTML diretamente
- 🎬 **Embed de vídeo** por URL (YouTube ou Vimeo) — renderizado como iframe 16:9 acima do corpo do artigo
- 📋 **Próximos passos** — campo texto livre, uma sugestão por linha, vira `<li>` no drawer
- 🗑 **Soft delete** — artigos excluídos vão para `deleted_at` e somem da listagem (não são apagados de fato)
- 🏷 **CRUD de categorias** com nome, slug, descrição, ícone (SVG bruto OU classe Lucide), ordem e flag `hidden`
- 👁 **Categoria oculta** — categoria com `hidden: true` some da grade pública mas continua acessível via busca (útil para "Outros" / catch-all)

---

## 🏗 Arquitetura

### Stack
- **Backend:** Rails Engine (`plugins/ajuda/lib/ajuda/engine.rb`) + ActiveRecord + Administrate (Super Admin)
- **Frontend público:** Vue 3 (Composition API) com composables, componentes isolados e CSS scoped por feature
- **Frontend admin:** ERB + Quill.js (vanilla, sem framework)
- **API:** REST sob `/public/api/v1/help_articles` (sem autenticação) e `/super_admin/help_*` (admin only)

### Modelagem de domínio

```
HelpArticle (CMS)
  ├─ title:        string (obrigatório)
  ├─ body:         text (HTML)
  ├─ category:     string (slug; FK lógica para HelpCategory)
  ├─ status:       string ('draft' | 'published')
  ├─ video_url:    string (YouTube/Vimeo, opcional)
  ├─ next_steps:   text (uma sugestão por linha, opcional)
  ├─ position:     integer (ordem dentro da categoria)
  ├─ deleted_at:   datetime (soft delete)
  └─ timestamps

HelpCategory (CMS)
  ├─ name:        string (obrigatório)
  ├─ description: string
  ├─ slug:        string (único, usado como `help_articles.category`)
  ├─ icon_svg:    text (markup SVG opcional, prioritário)
  ├─ icon_class:  string (fallback Lucide tipo "i-lucide-bolt")
  ├─ position:    integer (ordem na grade)
  ├─ hidden:      boolean (default: false)
  └─ timestamps
```

> **Por que `category` é string e não FK:** Mantém compatibilidade com a categoria `outro` hardcoded no frontend e permite que artigos sigam funcionando mesmo se a tabela `help_categories` ainda não tiver sido migrada (graceful degradation via `rescue`).

---

## 📦 Estrutura de arquivos do plugin

```
plugins/ajuda/
├── lib/
│   └── ajuda/
│       └── engine.rb                              # Rails Engine (registro)
└── frontend/
    ├── routes/
    │   └── routes.js                              # Rota /accounts/:id/ajuda
    └── features/
        └── help/
            ├── HelpIndex.vue                      # Componente raiz da página pública
            ├── help.css                           # Folha de estilos (prefixo .hp-)
            ├── data/
            │   └── helpData.js                    # CATEGORIES_META + FAQS (fallback)
            ├── composables/
            │   └── useHelpData.js                 # Busca artigos + categorias da API
            └── components/
                ├── HelpSearchBar.vue              # Busca + dropdown + pills de categoria
                ├── HelpBanner.vue                 # Banner "Precisa de ajuda?" + botão chat
                ├── HelpCategoryGrid.vue           # Grade visual de categorias
                ├── HelpFaq.vue                    # FAQ accordion com filtro
                └── HelpArticleDrawer.vue          # Drawer lateral de leitura
```

### Arquivos no core (necessários, mínimos)

```
app/models/
  ├── help_article.rb                 # Model
  └── help_category.rb                # Model

app/dashboards/
  ├── help_article_dashboard.rb       # Administrate dashboard
  └── help_category_dashboard.rb      # Administrate dashboard

app/controllers/super_admin/
  ├── help_articles_controller.rb     # CRUD admin
  └── help_categories_controller.rb   # CRUD admin

app/controllers/public/api/v1/
  └── help_articles_controller.rb     # API pública

app/fields/
  └── rich_text_field.rb              # Custom Administrate field (Quill)

app/views/fields/rich_text_field/
  ├── _index.html.erb                 # Preview na listagem
  ├── _show.html.erb                  # Render seguro do HTML
  └── _form.html.erb                  # Editor Quill (toolbar customizada)

app/javascript/superadmin_pages/
  └── quill_editor.js                 # Bootstrap do Quill em todas páginas SuperAdmin

db/migrate/
  ├── 20260424100000_create_help_articles.rb
  ├── 20260425100001_add_next_steps_to_help_articles.rb
  └── 20260425200000_create_help_categories.rb
```

> **Por que esses arquivos estão no core e não no plugin:** O Zeitwerk (autoloader Rails) exige que cada namespace Ruby (`SuperAdmin::`, `Public::Api::V1::`) tenha **um único diretório raiz**. Como o core já define esses namespaces, registrar controllers no plugin quebraria o autoloader. O Administrate (gem do Super Admin) também espera dashboards em `app/dashboards/` para escanear recursos.

---

## 🔌 API

### Pública (sem autenticação)

| Método | Path | Descrição |
|---|---|---|
| `GET` | `/public/api/v1/help_articles` | Lista artigos publicados. Filtros: `?category=<slug>`, `?q=<termo>` |
| `GET` | `/public/api/v1/help_articles/:id` | Detalhe de um artigo |
| `GET` | `/public/api/v1/help_articles/categories` | Lista todas as categorias (com `icon_svg`, `hidden`, `position`) |

### Super Admin (autenticada)

| Método | Path | Descrição |
|---|---|---|
| `GET` / `POST` | `/super_admin/help_articles` | Lista / cria artigo |
| `GET` / `PATCH` / `DELETE` | `/super_admin/help_articles/:id` | Mostra / edita / soft-deleta |
| `GET` / `POST` | `/super_admin/help_categories` | Lista / cria categoria |
| `GET` / `PATCH` / `DELETE` | `/super_admin/help_categories/:id` | Mostra / edita / deleta |

### Resposta de exemplo (`GET /public/api/v1/help_articles`)

```json
[
  {
    "id": 12,
    "title": "Como agendar uma consulta",
    "body": "<p>Para agendar...</p>",
    "category": "agenda",
    "status": "published",
    "video_url": "https://www.youtube.com/watch?v=...",
    "next_steps": "Configurar lembretes\nDefinir duração padrão",
    "position": 0,
    "created_at": "...",
    "updated_at": "..."
  }
]
```

---

## ⚙️ Frontend — Detalhes técnicos

### `useHelpData.js` (composable)
- Faz duas requisições em paralelo via `Promise.all`: `/help_articles` + `/help_articles/categories`
- Se a API de categorias falhar, cai no fallback `CATEGORIES_META` de `helpData.js`
- Normaliza cada artigo: `{ id, title, body, category, videoUrl, nextSteps, ... }`
- Agrupa artigos por categoria e calcula contagem reativa via `computed`

### `HelpSearchBar.vue` (mais complexo)
- Atalho global `⌘K` / `Ctrl+K` para focar
- Pills horizontais com **drag-to-scroll** (threshold de 4px para distinguir click de drag)
- Pill ativa centralizada via `scrollTo({ behavior: 'smooth' })` calculado com `nextTick`
- Filtro de pills: digitar oculta pills que não têm artigos correspondentes
- Busca cross-field: título + nome da categoria + corpo (HTML stripado via `replace(/<[^>]*>/g, ' ')`)
- Detecção de clique fora do dropdown via `@click.outside`

### `HelpArticleDrawer.vue`
- Renderizado via `<Teleport to="body">` para z-index correto sobre o sidebar
- **Embed de vídeo:** regex pega ID de `youtube.com/watch?v=`, `youtu.be/` e `vimeo.com/<id>` e converte para URL embed
- **Próximos passos:** `next_steps.split('\n').filter(Boolean)` vira lista
- **Modo leitura:** botão maximize adiciona `.hp-drawer--expanded` que aplica `top: 4vh; right: 50%; transform: translateX(50%); width: min(860px, 82vw)` — centraliza e amplia tipografia

### `HelpCategoryGrid.vue`
- `computed visibleCategories` filtra `c.hidden` (categoria oculta some da grade)
- `computed totalArticles` soma TODAS as categorias (incluindo ocultas)
- Renderiza `v-html="cat.iconSvg"` se houver SVG, fallback para `<span :class="cat.icon">` (Lucide)

---

## 🧩 Integrações

### Editor Quill.js (Super Admin)
- Pacote: `quill@2.0.3` (única dependência npm adicionada por este módulo)
- Bootstrap em `app/javascript/superadmin_pages/quill_editor.js`, importado em `entrypoints/superadmin.js`
- **Toolbar:** parágrafo/H2/H3, bold/italic/underline/strike, listas, blockquote, code-block, link, clean
- **Modo HTML:** botão `</>` adicionado manualmente após init — alterna entre Quill e `<textarea>` monospace
- **Sync com form:** a cada `text-change`, faz `quill.getSemanticHTML()` → `<input hidden>`. No submit do form, sync final para garantir nada perdido.

### Chat real do Chatwoot
- O botão "Iniciar conversa" do banner **não abre nada novo** — apenas dispara click no widget já presente:
  ```js
  document.querySelector('.woot-widget-bubble:not(.woot--close):not(.woot--hide)')?.click();
  ```

---

## 🚀 Como ativar / testar

```bash
# 1. Migrar
bin/rails db:migrate

# 2. Acessar painel admin
open http://localhost:3000/super_admin/help_categories  # criar categorias
open http://localhost:3000/super_admin/help_articles    # criar artigos

# 3. Acessar visão pública
open http://localhost:3000/app/accounts/1/ajuda
```

---

## 📜 Histórico evolutivo

> Cada versão lista **TODOS** os arquivos tocados, marcando se estão no **core** (`app/`, `config/`, `db/`, `package.json`) ou no **plugin** (`plugins/ajuda/`), e a ação realizada (Criado / Modificado / Reescrito / Excluído).

---

### v1.0.0 — 2026-04-24 — Criação do plugin

**Escopo:** Estrutura inicial do plugin `ajuda`, página pública de Central de Ajuda com busca, FAQs, drawer de artigos e integração com chat real do Chatwoot. Dados ainda mockados (sem CMS).

#### Arquivos CRIADOS — Plugin

| Arquivo | Descrição |
|---|---|
| `plugins/ajuda/frontend/routes/routes.js` | Rota `/accounts/:accountId/ajuda` → `HelpIndex.vue` |
| `plugins/ajuda/frontend/features/help/HelpIndex.vue` | Componente raiz; gerencia estado `drawerData`, `openArticle`, `openCategory`, `openChat` |
| `plugins/ajuda/frontend/features/help/help.css` | Folha de estilos (prefixo `hp-`) usando tokens `--slate-*`, `--color-woot-*`, `--blue-*` |
| `plugins/ajuda/frontend/features/help/data/helpData.js` | Dados mockados — 6 categorias + 7 FAQs |
| `plugins/ajuda/frontend/features/help/components/HelpSearchBar.vue` | Busca com `⌘K`, dropdown com highlight do termo, click-outside |
| `plugins/ajuda/frontend/features/help/components/HelpBanner.vue` | Banner com botão que aciona widget Chatwoot |
| `plugins/ajuda/frontend/features/help/components/HelpCategoryGrid.vue` | Grid 3 colunas de categorias |
| `plugins/ajuda/frontend/features/help/components/HelpFaq.vue` | FAQ accordion via `grid-template-rows: 0fr → 1fr` |
| `plugins/ajuda/frontend/features/help/components/HelpArticleDrawer.vue` | Drawer lateral via `Teleport`, lista + leitura, feedback "foi útil?" |

#### Arquivos MODIFICADOS — Core (4 toques mínimos)

| Arquivo | Linhas | O que |
|---|---|---|
| `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` | +2 | Import de `ajudaRoutes` + spread no array `children` |
| `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | +7 | Novo objeto no array `menuItems` (item "Ajuda" abaixo de Configurações) |
| `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` | +1 | Chave `SIDEBAR.AJUDA: "Ajuda"` |
| `app/javascript/dashboard/i18n/locale/en/settings.json` | +1 | Chave `SIDEBAR.AJUDA: "Help"` |

#### Arquivos EXCLUÍDOS

- `plugins/ajuda/frontend/features/help/components/HelpChatPanel.vue` — chat simulado criado inicialmente, **deletado** quando Leandro pediu integração com widget real do Chatwoot.

---

### v1.1.0 — 2026-04-24 — CMS no Super Admin + API pública

**Escopo:** Saída dos dados mockados; criação de CRUD de artigos no Super Admin com editor rich text, API pública sem autenticação, e frontend dinâmico via composable.

#### Arquivos CRIADOS — Core (CMS)

| Arquivo | Descrição |
|---|---|
| `db/migrate/20260424100000_create_help_articles.rb` | Tabela `help_articles` (`title`, `body`, `category`, `status`, `video_url`, `position`, `deleted_at`, timestamps + índices) |
| `app/models/help_article.rb` | Model com escopos `published`, `by_category`, `visible`, `ordered`; método `search(query)`, `reading_time`, `soft_delete!` |
| `app/fields/rich_text_field.rb` | `RichTextField < Administrate::Field::Base` (preview texto puro na listagem) |
| `app/views/fields/rich_text_field/_index.html.erb` | Listagem: 120 chars sem HTML |
| `app/views/fields/rich_text_field/_show.html.erb` | Detalhe: render do HTML |
| `app/views/fields/rich_text_field/_form.html.erb` | Form: editor rich text vanilla JS (toolbar manual, `execCommand`) — **substituído por Quill na v1.3.0** |
| `app/dashboards/help_article_dashboard.rb` | Dashboard Administrate com filtros `published`/`draft` |
| `app/controllers/super_admin/help_articles_controller.rb` | CRUD admin; override `destroy` para soft delete |
| `app/controllers/public/api/v1/help_articles_controller.rb` | API pública com filtros `?category=`, `?q=` |

#### Arquivos MODIFICADOS — Core

| Arquivo | O que |
|---|---|
| `config/routes.rb` | +2 blocos: `resources :help_articles` em `super_admin` e em `public/api/v1` |

#### Arquivos CRIADOS — Plugin

| Arquivo | Descrição |
|---|---|
| `plugins/ajuda/frontend/features/help/composables/useHelpData.js` | Busca em `GET /public/api/v1/help_articles`, agrupa por categoria, fallback para `CATEGORIES_META` em erro de rede |

#### Arquivos MODIFICADOS — Plugin

| Arquivo | O que |
|---|---|
| `plugins/ajuda/frontend/features/help/data/helpData.js` | Renomeado `CATEGORIES` → `CATEGORIES_META`; mantido alias para retrocompatibilidade; corpos viram HTML string |
| `plugins/ajuda/frontend/features/help/HelpIndex.vue` | Passa a usar `useHelpData`; `categories`/`faqs` viram props |
| `plugins/ajuda/frontend/features/help/components/HelpCategoryGrid.vue` | Aceita `categories` como prop |
| `plugins/ajuda/frontend/features/help/components/HelpFaq.vue` | Aceita `categories`/`faqs` como props |
| `plugins/ajuda/frontend/features/help/components/HelpSearchBar.vue` | Aceita `categories` como prop |
| `plugins/ajuda/frontend/features/help/components/HelpArticleDrawer.vue` | Renderiza `body` como HTML string OU array de parágrafos (fallback) |
| `plugins/ajuda/frontend/features/help/help.css` | Adicionado `.hp-art-body` para HTML da API (p, h2, h3, ul, blockquote, iframe, links) |

---

### v1.2.0 — 2026-04-25 — Editor: vídeo embed + próximos passos + modo HTML + reading mode

**Escopo:** Refinamentos no drawer e no editor. Embed de vídeo no drawer, campo "Próximos passos" editável, modo HTML bruto no editor, modo leitura centralizado.

#### Arquivos CRIADOS — Core

| Arquivo | Descrição |
|---|---|
| `db/migrate/20260425100001_add_next_steps_to_help_articles.rb` | `add_column :help_articles, :next_steps, :text` |

#### Arquivos MODIFICADOS — Core

| Arquivo | O que |
|---|---|
| `app/dashboards/help_article_dashboard.rb` | +`next_steps: Field::Text` no `ATTRIBUTE_TYPES`, em `SHOW_PAGE_ATTRIBUTES` e `FORM_ATTRIBUTES`; +`video_url` no form |
| `app/controllers/super_admin/help_articles_controller.rb` | +`:next_steps` no `resource_params` permit list |
| `app/controllers/public/api/v1/help_articles_controller.rb` | +`next_steps: article.next_steps.to_s` no método `serialize` |
| `app/views/fields/rich_text_field/_form.html.erb` | Botão `</>` na toolbar para alternar entre WYSIWYG e textarea de HTML bruto |

#### Arquivos MODIFICADOS — Plugin

| Arquivo | O que |
|---|---|
| `plugins/ajuda/frontend/features/help/composables/useHelpData.js` | +`nextSteps: art.next_steps ?? ''` em `normalizeArticle` |
| `plugins/ajuda/frontend/features/help/components/HelpArticleDrawer.vue` | **Reescrito.** Removido callout "Dica"; +embed de vídeo (regex YouTube/Vimeo → iframe 16:9); +seção "Próximos passos" dinâmica (split `\n`); +modo leitura (`hp-drawer--expanded`) |
| `plugins/ajuda/frontend/features/help/components/HelpCategoryGrid.vue` | `totalArticles` envolto em `computed()` (era atribuição direta — recalculava antes da API responder) |
| `plugins/ajuda/frontend/features/help/data/helpData.js` | +`{ id: 'outro', name: 'Outros', ... }` no `CATEGORIES_META` (artigos com `category: 'outro'` eram descartados sem isso) |
| `plugins/ajuda/frontend/features/help/components/HelpSearchBar.vue` | Busca passa a incluir corpo do artigo (HTML stripado) além do título |
| `plugins/ajuda/frontend/features/help/help.css` | +`.hp-art-video`, `.hp-drawer-expand-btn`, `.hp-drawer--expanded` (modo leitura), transição suave |

---

### v1.3.0 — 2026-04-25 — Categorias dinâmicas + UX de busca redesenhada + Quill.js

**Escopo:** Categorias passam a ser gerenciadas no banco; barra de busca ganha pills de categoria com drag-to-scroll; editor antigo (`execCommand`) substituído por Quill.js.

#### Arquivos CRIADOS — Core

| Arquivo | Descrição |
|---|---|
| `db/migrate/20260425200000_create_help_categories.rb` | Tabela `help_categories` (`name`, `description`, `slug` único, `icon_svg`, `icon_class`, `position`, `hidden`); seed automático com as 7 categorias padrão |
| `app/models/help_category.rb` | Model com escopos `ordered`, `visible`; validações `name`/`slug` presence, `slug` uniqueness |
| `app/dashboards/help_category_dashboard.rb` | Dashboard Administrate (campos: nome, descrição, slug, icon_class Lucide, icon_svg textarea, position, hidden toggle) |
| `app/controllers/super_admin/help_categories_controller.rb` | CRUD admin (override `scoped_resource` para ordenar por position) |
| `app/javascript/superadmin_pages/quill_editor.js` | Bootstrap do Quill em `.ha-quill-wrap`; suporte a HTML mode; sync com `<input hidden>` no `text-change` e no `submit` |

#### Arquivos MODIFICADOS — Core

| Arquivo | O que |
|---|---|
| `app/models/help_article.rb` | Validação `validates :category, inclusion: { in: CATEGORIES }` substituída por `validate :category_must_be_valid` que consulta `HelpCategory.pluck(:slug)` (com `rescue` para fallback à constante hardcoded) |
| `app/dashboards/help_article_dashboard.rb` | Dropdown de categoria virou lambda `-> { HelpCategory.ordered.pluck(:slug) }` (antes era avaliado uma vez no boot); +`video_url` no form |
| `app/controllers/public/api/v1/help_articles_controller.rb` | +action `categories` (`GET /help_articles/categories`) que retorna lista com `id`, `name`, `description`, `icon_svg`, `icon_class`, `hidden`, `position` |
| `config/routes.rb` | +1 linha em `super_admin` (`resources :help_categories`) e +bloco `collection { get :categories }` em `help_articles` |
| `app/javascript/entrypoints/superadmin.js` | +1 import: `'../superadmin_pages/quill_editor.js'` (Quill ativo em todas as páginas SuperAdmin) |
| `package.json` / `pnpm-lock.yaml` | +`quill@2.0.3` |
| `app/views/fields/rich_text_field/_form.html.erb` | **Reescrito.** Antes: DIV contenteditable + toolbar manual + `execCommand`. Depois: HTML mínimo (`.ha-quill-wrap` + `.ha-quill-editor` + textarea HTML mode + input hidden) que o Quill enhance no `DOMContentLoaded`. CSS inline mantido para auto-contenção. Compatibilidade retroativa via `dangerouslyPasteHTML` |

#### Arquivos MODIFICADOS — Plugin

| Arquivo | O que |
|---|---|
| `plugins/ajuda/frontend/features/help/data/helpData.js` | +`hidden: true` na entrada `outro` (consistência com banco) |
| `plugins/ajuda/frontend/features/help/composables/useHelpData.js` | **Reescrito.** Duas fetches paralelas (`Promise.all`); usa categorias do banco se disponíveis (com `iconSvg` e `hidden`); fallback para `CATEGORIES_META` em erro |
| `plugins/ajuda/frontend/features/help/components/HelpCategoryGrid.vue` | **Reescrito.** Filtra `c.hidden` na grade; total inclui categorias ocultas; suporte a `v-html="cat.iconSvg"` |
| `plugins/ajuda/frontend/features/help/components/HelpSearchBar.vue` | **Reescrito** (múltiplas iterações). Pills horizontais roláveis sempre visíveis; pills filtram por query; pill ativa centraliza com smooth scroll; drag-to-scroll com threshold 4px; Escape deseleciona |
| `plugins/ajuda/frontend/features/help/help.css` | +~110 linhas: pills (`.hp-browse-pills`, `.hp-browse-pill[--active]`), lista de artigos da categoria (`.hp-cat-art-list` com `max-height: 290px`), rótulo de navegação (`.hp-results-label--nav`, `.hp-back-btn`), suporte a SVG inline (`.hp-cat-svg-icon svg`, `.hp-browse-pill-svg svg`) |

---

## 🧮 Auditoria final — todos os arquivos do módulo

### Plugin (`plugins/ajuda/`) — 100% isolado, nenhum risco para o core

| Arquivo | Versão criado | Estado atual |
|---|---|---|
| `lib/ajuda/engine.rb` | v1.0.0 | Estável |
| `frontend/routes/routes.js` | v1.0.0 | Estável |
| `frontend/features/help/HelpIndex.vue` | v1.0.0 | Modificado em v1.1.0 |
| `frontend/features/help/help.css` | v1.0.0 | Modificado em v1.1.0, v1.2.0, v1.3.0 |
| `frontend/features/help/data/helpData.js` | v1.0.0 | Modificado em v1.1.0, v1.2.0, v1.3.0 |
| `frontend/features/help/composables/useHelpData.js` | v1.1.0 | Reescrito em v1.3.0 |
| `frontend/features/help/components/HelpSearchBar.vue` | v1.0.0 | Reescrito em v1.3.0 |
| `frontend/features/help/components/HelpBanner.vue` | v1.0.0 | Estável |
| `frontend/features/help/components/HelpCategoryGrid.vue` | v1.0.0 | Reescrito em v1.3.0 |
| `frontend/features/help/components/HelpFaq.vue` | v1.0.0 | Modificado em v1.1.0 |
| `frontend/features/help/components/HelpArticleDrawer.vue` | v1.0.0 | Reescrito em v1.2.0 |

**Excluídos:** `HelpChatPanel.vue` (v1.0.0).

### Core — toques cirúrgicos

| Arquivo | Tipo | Quando | Justificativa |
|---|---|---|---|
| `db/migrate/20260424100000_create_help_articles.rb` | Criado | v1.1.0 | Migration nova (não toca tabelas existentes) |
| `db/migrate/20260425100001_add_next_steps_to_help_articles.rb` | Criado | v1.2.0 | Migration nova |
| `db/migrate/20260425200000_create_help_categories.rb` | Criado | v1.3.0 | Migration nova |
| `app/models/help_article.rb` | Criado | v1.1.0 | Model novo (sem relação com models do core) |
| `app/models/help_category.rb` | Criado | v1.3.0 | Model novo |
| `app/fields/rich_text_field.rb` | Criado | v1.1.0 | Custom field do Administrate |
| `app/views/fields/rich_text_field/_index.html.erb` | Criado | v1.1.0 | Partial do custom field |
| `app/views/fields/rich_text_field/_show.html.erb` | Criado | v1.1.0 | Partial do custom field |
| `app/views/fields/rich_text_field/_form.html.erb` | Criado v1.1.0 / Reescrito v1.3.0 | Editor rich text (Quill após v1.3.0) |
| `app/dashboards/help_article_dashboard.rb` | Criado | v1.1.0 | Dashboard Administrate |
| `app/dashboards/help_category_dashboard.rb` | Criado | v1.3.0 | Dashboard Administrate |
| `app/controllers/super_admin/help_articles_controller.rb` | Criado | v1.1.0 | CRUD admin (Zeitwerk requer no core) |
| `app/controllers/super_admin/help_categories_controller.rb` | Criado | v1.3.0 | CRUD admin |
| `app/controllers/public/api/v1/help_articles_controller.rb` | Criado | v1.1.0 | API pública |
| `app/javascript/superadmin_pages/quill_editor.js` | Criado | v1.3.0 | Bootstrap Quill |
| `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` | Modificado (+2 linhas) | v1.0.0 | Registro da rota do plugin |
| `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | Modificado (+7 linhas) | v1.0.0 | Item "Ajuda" no menu |
| `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` | Modificado (+1 linha) | v1.0.0 | i18n pt-BR |
| `app/javascript/dashboard/i18n/locale/en/settings.json` | Modificado (+1 linha) | v1.0.0 | i18n en |
| `app/javascript/entrypoints/superadmin.js` | Modificado (+1 linha) | v1.3.0 | Import do Quill bootstrap |
| `config/routes.rb` | Modificado (+5 linhas, distribuídas) | v1.1.0, v1.3.0 | Rotas admin + API pública |
| `package.json` / `pnpm-lock.yaml` | Modificado | v1.3.0 | +`quill@2.0.3` |

### Resumo numérico

- **Arquivos criados no plugin:** 11 (inclui 1 deletado)
- **Arquivos criados no core:** 17
- **Arquivos modificados no core:** 7 (todas adições — nenhuma reescrita destrutiva)
- **Dependências npm adicionadas:** 1 (`quill`)
- **Tabelas novas no banco:** 2 (`help_articles`, `help_categories`)
- **Tabelas do core alteradas:** 0

---

## 🔗 Referências

- Plugin: [`plugins/ajuda/`](../../../plugins/ajuda/)
- Migrations: [`db/migrate/20260424100000_*`](../../../db/migrate/), [`db/migrate/20260425100001_*`](../../../db/migrate/), [`db/migrate/20260425200000_*`](../../../db/migrate/)
- Bootstrap Quill: [`app/javascript/superadmin_pages/quill_editor.js`](../../../app/javascript/superadmin_pages/quill_editor.js)
- Changelog detalhado: [`changelog.leandro.md`](../../../changelog.leandro.md) — versões 1.0.0 → 1.3.0
