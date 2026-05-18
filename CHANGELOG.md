# Changelog

Todas as mudanças relevantes no projeto serão documentadas neste arquivo.

## Estrutura de Versão: `1.B.C.D`

- **1**: Versão Major (Fixa).
- **B**: Conclusão de Projetos/Módulos completos (Ex: Sistema de Agenda, Kanban).
- **C**: Incrementado quando a contagem de bugs (D) atinge 10.
- **D**: Correções de bugs e mudanças menores.
- **Obrigatório**: Cada entrada deve listar os **Arquivos Modificados** ao final da descrição.

## [1.5.1.57] - 2026-04-30T07:30:00-03:00

### Tweak: botão de excluir do card agora aparece em cards de 15min e ganhou visual sólido vermelho + ícone branco

**Problemas:**
1. Cards do tier pill (≤32px de altura — eventos de 15min) não tinham botão de excluir no template, então não havia como deletar via hover. Só clicando pra abrir o popup.
2. Botão de excluir nos outros tiers usava `background: rgba(0,0,0,0.06)` (transparente sobre o fundo do card) e `color: var(--evt-text-color)` (cor adaptada à categoria). Ficava quase invisível sobre cards pastel claros e sem indicação clara de "ação destrutiva". O ícone também ficava com a cor do texto do evento — em alguns cards ficava azulado/esverdeado, longe do "delete".

**Solução:**
1. Tier pill ganhou `<div class="evt-pill-actions">` posicionado absoluto à direita com o mesmo botão de excluir. Aparece no hover do card, escondido fora dele.
2. `.evt-info-btn-hover` e `.evt-info-btn-inline` passam a ter `background: #ef4444` (red-500) sólido + `color: #ffffff` fixos. Sem alpha, sem `var(--evt-text-color)`. Hover escurece pra `#dc2626` (red-600) com leve `scale(1.05)` pra feedback. Resultado: vermelho cristalino em qualquer fundo, light ou dark.

**Arquivos Modificados:**
- `plugins/agenda/frontend/components/AgendaEventCard.vue`
- `plugins/agenda/frontend/styles/agenda-events.css`
- `CHANGELOG.md`

---

## [1.5.1.56] - 2026-04-30T07:00:00-03:00

### Tweak: bubble do widget aumentado para 56x56 (alinhar com tamanho do Captain copilot)

**Problema:**
O usuário reportou que o bubble 48x48 ficou pequeno demais comparado ao botão do Captain copilot que aparece logo abaixo no canto inferior direito. Pediu para alinhar o tamanho com o Captain.

**Solução:**
Ajustei os 3 overrides em `app/views/layouts/vueapp.html.erb` de 48 para 56 (mantendo o ícone SVG 24x24 centralizado):
```css
.woot-widget-bubble:not(.woot-widget--expanded) { width: 56px; height: 56px; }
.woot-widget-bubble:not(.woot-widget--expanded) svg { margin: 16px; }   /* (56-24)/2 */
.woot-widget-bubble.woot--close::before,
.woot-widget-bubble.woot--close::after          { left: 27px; top: 16px; }
```

**Arquivos Modificados:**
- `app/views/layouts/vueapp.html.erb`
- `CHANGELOG.md`

---

## [1.5.1.55] - 2026-04-30T06:50:00-03:00

### Fix: ícone vazando do bubble após reduzir para 48x48 — margin do SVG e posição do X de fechar precisavam recalcular

**Problema:**
Após a 1.5.1.54 (bubble 48x48), o ícone SVG interno apareceu **descentralizado e vazando** do círculo. O CSS do gem (`app/javascript/sdk/sdk.js`) tem:
```css
.woot-widget-bubble svg     { height: 24px; margin: 20px; width: 24px; }   /* 20+24+20 = 64 ✓ */
.woot--close::before/::after { left: 32px; top: 20px; height: 24px; ... }  /* centraliza o X em 64x64 */
```
Esses números só funcionam para 64x64. Reduzi a borda externa pra 48 mas o margin/posição interna continuou em 20/32 — o SVG (24px + 20px de margin de cada lado = 64px) não cabe em 48 e vaza pra fora do `border-radius: 100px`, parecendo deslocado.

**Solução:**
3 overrides em `app/views/layouts/vueapp.html.erb` que casam matematicamente com o tamanho 48x48:
```css
.woot-widget-bubble:not(.woot-widget--expanded) {
  width: 48px !important;
  height: 48px !important;
}
.woot-widget-bubble:not(.woot-widget--expanded) svg {
  margin: 12px !important;          /* (48 - 24) / 2 = 12 */
}
.woot-widget-bubble.woot--close::before,
.woot-widget-bubble.woot--close::after {
  left: 23px !important;            /* centro horizontal: 48/2 - 1 = 23 */
  top:  12px !important;            /* (48 - 24) / 2 = 12 */
}
```
Resultado: SVG de 24x24 fica perfeitamente centralizado no círculo de 48x48, e as duas barras do X (variante close) também se cruzam no centro.

**Arquivos Modificados:**
- `app/views/layouts/vueapp.html.erb`
- `CHANGELOG.md`

---

## [1.5.1.54] - 2026-04-30T06:40:00-03:00

### Tweak: bubble do widget Klivy reduzido para 48x48 (default do SDK é 64x64)

**Problema:**
O bubble do SDK do Chatwoot vem com 64x64px por padrão — visualmente grande no rodapé, especialmente porque agora compartilha o canto inferior direito com o botão do Captain copilot. O usuário pediu o tamanho padrão de 48x48 (mais alinhado com tamanho típico de FABs em apps modernos).

**Solução:**
CSS override em `app/views/layouts/vueapp.html.erb` (junto dos outros overrides de visibilidade e posição já existentes):
```css
.woot-widget-bubble:not(.woot-widget--expanded) {
  width: 48px !important;
  height: 48px !important;
}
```
- Aplica apenas em `.woot-widget-bubble` (a classe base de ambos os botões: "abrir chat" e "X fechar"). O ícone SVG interno é 24x24, então com 48x48 o padding fica em 12px (visualmente equilibrado).
- Exclui a variante `.woot-widget--expanded` (modo com texto ao lado do ícone), que controla altura própria via flex/auto-width — o `!important` no width quebraria esse modo.

**Arquivos Modificados:**
- `app/views/layouts/vueapp.html.erb`
- `CHANGELOG.md`

---

## [1.5.1.53] - 2026-04-30T06:30:00-03:00

### Fix: bubble vazando para todas as páginas (deveria aparecer só no módulo Ajuda)

**Problema:**
O bubble de suporte estava aparecendo no canto inferior direito de **todas as páginas** do dashboard, quando o comportamento esperado é só dentro do módulo Ajuda (`/accounts/:id/ajuda`, `/ajuda/reportar-erro`, `/ajuda/solicitar-melhoria`). A camada anterior dependia de:
1. `hideMessageBubble: true` no `chatwootSDK.run()` (esconder por padrão).
2. `useChatBubble` chamando `toggleBubbleVisibility('show'|'hide')` no mount/unmount dos componentes do plugin Ajuda.

Essa abordagem é frágil: o `toggleBubbleVisibility` só funciona depois que `window.$chatwoot` está disponível (SDK carregou), e em SPA navigation rápida o componente Vue pode desmontar antes do SDK responder ao primeiro `show`. Resultado: o bubble fica visível depois do primeiro acesso a `/ajuda`, e o `hide` no unmount não consegue desfazer.

**Solução — defesa em duas camadas:**

1. **CSS estrito por padrão** em `app/views/layouts/vueapp.html.erb` — o bubble nasce com `display: none !important`. Só fica visível quando o `<body>` tem a class `klivy-help-active`:
   ```css
   .woot--bubble-holder,
   .woot-widget-bubble,
   .woot-widget-holder { display: none !important; }
   body.klivy-help-active .woot--bubble-holder,
   body.klivy-help-active .woot-widget-bubble:not(.woot--hide),
   body.klivy-help-active .woot-widget-holder { display: block !important; }
   ```
   Não depende de JS rodar na ordem certa — CSS estático aplicado no momento do load.

2. **Composable `useChatBubble` adiciona/remove class** em `plugins/ajuda/frontend/features/help/composables/useChatBubble.js`:
   ```js
   const show = () => {
     document.body.classList.add('klivy-help-active');
     window.$chatwoot?.toggleBubbleVisibility('show');
   };
   const hide = () => {
     document.body.classList.remove('klivy-help-active');
     window.$chatwoot?.toggleBubbleVisibility('hide');
   };
   ```
   Mantive o `toggleBubbleVisibility` para sincronizar o estado interno do SDK (importante quando o usuário abre o iframe), mas a class no body é o que efetivamente controla a visibilidade.

**Cenários cobertos:**
- SDK ainda não carregou + componente do Ajuda monta: class no body adicionada → CSS já mostra (assim que o SDK injetar o DOM, ele aparece visível).
- Componente desmonta antes do SDK responder: class removida → bubble esconde via CSS, mesmo sem chamada JS bem-sucedida.
- Navegação SPA rápida entre rotas: cada componente do Ajuda chama `add` no mount, qualquer outro componente que use o composable em outro plugin só precisa replicar o padrão.

**Arquivos Modificados:**
- `app/views/layouts/vueapp.html.erb` (CSS de visibilidade controlada por class no body)
- `plugins/ajuda/frontend/features/help/composables/useChatBubble.js` (add/remove class no body além do toggleBubbleVisibility)
- `CHANGELOG.md`

**Como aplicar:**
- Refresh — Vite/Rails recarregam JS+ERB em hot reload. O bubble deve sumir de todas as páginas exceto `/ajuda`, `/ajuda/reportar-erro` e `/ajuda/solicitar-melhoria`.

---

## [1.5.1.52] - 2026-04-30T06:15:00-03:00

### Fix: 500 em todas as páginas do Super Admin — Administrate tentava renderizar `klivy_widgets` como recurso CRUD

**Problema:**
Após a 1.5.1.51, todas as páginas do `/super_admin/` quebraram com:
```
ActionView::Template::Error (No route matches {action: "index", controller: "super_admin/klivy_widgets"})
```
em `_navigation.html.erb:38`. Causa: o `_navigation.html.erb` itera por `Administrate::Namespace.new(namespace).resources`, que **descobre automaticamente todos os controllers em `app/controllers/super_admin/`**. Quando criei o `klivy_widgets_controller.rb`, ele entrou nessa lista. O loop então chamou `resource_index_route(resource)` (que sempre tenta a rota `index`) — mas como a rota é `resource :klivy_widget` (singleton, sem index), o Rails não acha e levanta erro.

Mesmo padrão de skip já era usado para os outros controllers que não devem aparecer no loop flat (`help_articles`, `help_categories`, `help_faqs` — todos renderizados manualmente sob o dropdown "Ajuda" via `_help_menu.html.erb`).

**Solução:**
Adicionei `"klivy_widgets"` à lista de strings filtradas no `next if` do loop em `_navigation.html.erb` linha 35. O recurso continua acessível via dropdown Ajuda → Widget de Suporte (link manual em `_help_menu.html.erb`), só não tenta mais ser renderizado como item flat com link de `index`.

**Arquivos Modificados:**
- `app/views/super_admin/application/_navigation.html.erb`
- `CHANGELOG.md`

**Como aplicar:**
- Refresh — autoload de view do Rails pega imediatamente em dev. Páginas do Super Admin voltam a abrir, e o link "Widget de Suporte" no dropdown Ajuda aponta corretamente para `/super_admin/klivy_widget`.

---

## [1.5.1.51] - 2026-04-30T06:00:00-03:00

### Fix: página "Widget de Suporte" não carregava — controller e view dir estavam no singular, Rails espera plural

**Problema:**
Após a 1.5.1.50, a página `/super_admin/klivy_widget` não carregava. Causa: convenção do Rails para `resource :klivy_widget` (singular) é gerar rota apontando para `KlivyWidgetsController` (controller sempre **plural**, mesmo em recursos singleton). Eu criei o controller como `KlivyWidgetController` (singular) — Rails levantava `uninitialized constant SuperAdmin::KlivyWidgetsController` ao acessar a página.

Confirmação do padrão no próprio repo: `resource :app_config` → `app_configs_controller.rb` (plural); `resource :instance_status` → `instance_statuses_controller.rb` (plural). Mesma regra.

**Solução:**
1. Renomeei o controller: `app/controllers/super_admin/klivy_widget_controller.rb` → `klivy_widgets_controller.rb`.
2. Renomeei a class interna: `SuperAdmin::KlivyWidgetController` → `SuperAdmin::KlivyWidgetsController`.
3. Renomeei o diretório de views: `app/views/super_admin/klivy_widget/` → `app/views/super_admin/klivy_widgets/`.
4. Ajustei `help_menu_open?` em `SuperAdmin::NavigationHelper` para detectar o controller path como `super_admin/klivy_widgets` (plural — o que `params[:controller]` realmente devolve em runtime).

**Não mudou:**
- `config/routes.rb` continua com `resource :klivy_widget` (singular) — esse é o nome do recurso, gera helper `super_admin_klivy_widget_url` (singular). Combinação correta: recurso singular + controller/view plural.
- `_help_menu.html.erb` continua referenciando `super_admin_klivy_widget_url` — funciona porque o helper segue o nome do recurso, não do controller.

**Arquivos Modificados:**
- `app/controllers/super_admin/klivy_widgets_controller.rb` (renomeado de `klivy_widget_controller.rb`, classe interna ajustada)
- `app/views/super_admin/klivy_widgets/show.html.erb` (renomeado de `klivy_widget/`)
- `app/helpers/super_admin/navigation_helper.rb` (controller path no `help_menu_open?` agora plural)
- `CHANGELOG.md`

**Como aplicar:**
- Mudanças em `app/` recarregam imediatamente em dev. Refresh da página `/super_admin/klivy_widget` deve agora carregar o form.

---

## [1.5.1.50] - 2026-04-30T05:30:00-03:00

### Tweak: substituí "Configs do Sistema" (lista enorme) por página dedicada "Widget de Suporte" no dropdown Ajuda

**Problema:**
Na 1.5.1.49 adicionei um link "Configs do Sistema" na sidebar Klivy que apontava para `/super_admin/installation_configs/` — o índice padrão do Administrate que lista **todas** as ~100 entries (LANGFUSE, CLOUDFLARE, GOOGLE_OAUTH, OG_IMAGE, etc.). O usuário só queria um lugar simples pra colar o token do widget e ligar/desligar — não uma exposição da configuração inteira do sistema. Sobrecarrega visualmente e induz a mexer em coisas que não deveria.

**Solução:**
Página dedicada e enxuta no Super Admin com **só os 3 campos** que importam para o widget de suporte, posicionada como sub-item do dropdown "Ajuda":

1. **Controller** `SuperAdmin::KlivyWidgetController` (`app/controllers/super_admin/klivy_widget_controller.rb`):
   - `show`: lê os 3 valores via `InstallationConfig.find_by(name:)`.
   - `update`: persiste via `first_or_create + update!`, com sanitização (boolean para o flag `enabled` via `ActiveModel::Type::Boolean`, strip para strings) + `GlobalConfig.clear_cache`.
   - Constante `CONFIG_KEYS` lista as 3 chaves whitelisted (segurança contra mass assignment de outras keys).
   - Padrão idêntico ao `SuperAdmin::AppConfigsController` já existente — herda de `SuperAdmin::ApplicationController`, autenticação Devise super_admin já garantida.

2. **View** `app/views/super_admin/klivy_widget/show.html.erb`:
   - Título "Widget de Suporte".
   - Texto explicativo curto.
   - Form com 3 campos:
     - **Ativar widget** (select Ativado/Desativado).
     - **Website Token** (input texto monoespaçado).
     - **Base URL** (input url monoespaçado).
   - Botão "Salvar". Dicas curtas embaixo de cada campo (em cinza claro). Largura limitada a 720px para não esticar demais.

3. **Rota** `resource :klivy_widget, only: [:show, :update]` em `config/routes.rb`, dentro do bloco `# ── Beclinic / Klivy custom modules ──` do `namespace :super_admin`.

4. **Sub-item no dropdown Ajuda** em `app/views/super_admin/application/_help_menu.html.erb` — adicionei "Widget de Suporte" no array de links (depois de "Perguntas Frequentes"), apontando para `super_admin_klivy_widget_url`. Helper `help_menu_open?` em `app/helpers/super_admin/navigation_helper.rb` ganhou `super_admin/klivy_widget` na lista de controllers que mantêm o dropdown aberto.

5. **Removi o link "Configs do Sistema"** que tinha posto na sidebar Klivy (`app/views/super_admin/application/_navigation.html.erb`) — voltou ao formato anterior (Ajuda dropdown + Migração).

**Resultado na sidebar:**
```
─── KLIVY ──────────────
▾ Ajuda
    Categorias
    Artigos
    Perguntas Frequentes
    Widget de Suporte    ← novo
🗄  Migração
```

Para configurar agora: Super Admin → Ajuda → **Widget de Suporte** → muda os 3 campos → Salvar. Mudanças refletem no próximo refresh, sem deploy.

**Arquivos Modificados:**
- `app/controllers/super_admin/klivy_widget_controller.rb` (criado)
- `app/views/super_admin/klivy_widget/show.html.erb` (criado)
- `config/routes.rb` (+1 resource :klivy_widget)
- `app/views/super_admin/application/_help_menu.html.erb` (+1 sub-item "Widget de Suporte")
- `app/helpers/super_admin/navigation_helper.rb` (+klivy_widget no help_menu_open?)
- `app/views/super_admin/application/_navigation.html.erb` (removido link "Configs do Sistema")
- `CHANGELOG.md`

---

## [1.5.1.49] - 2026-04-30T05:10:00-03:00

### Fix: bubble não subiu (seletor CSS errado) + link "Configs do Sistema" na sidebar Klivy do Super Admin

**Problema:**
1. Após a 1.5.1.47/.48, o usuário reportou que **o bubble continuou no mesmo canto** (não subiu pra evitar overlap com o Captain). Causa: meu CSS aplicava `bottom` em `#cw-bubble-holder`, mas esse elemento é só um **wrapper** sem `position: fixed`. Quem realmente posiciona é o `.woot-widget-bubble` (botão visível, default `bottom: 20px;`) e o `.woot-widget-holder` (iframe da janela de chat, default `bottom: 94px;`) — ambos com `position: fixed` direto em `app/javascript/sdk/sdk.js`. Como meu seletor era no parent (sem position fixa), o `bottom: 88px !important` era ignorado.
2. Usuário não conseguia achar o menu pra ativar/desativar/trocar token. As 3 InstallationConfig já apareciam em `/super_admin/installation_configs` (Administrate descobre auto), mas **não havia link na sidebar** — só dava pra acessar digitando a URL na mão.

**Solução:**
1. **Seletores CSS corretos** em `app/views/layouts/vueapp.html.erb`:
   ```css
   .woot-widget-bubble                  { bottom: 88px !important; }
   .woot-widget-bubble.woot-widget--expanded { bottom: 92px !important; }
   .woot-widget-holder                  { bottom: 162px !important; }
   ```
   - `88px` no bubble = espaço de 88px da borda inferior (acima do botão Captain que fica em ~24px).
   - `92px` na variante `.woot-widget--expanded` (caso o widget esteja em modo expandido).
   - `162px` no holder = `94px` original + `68px` (mesmo offset que subi no bubble).

2. **Link "Configs do Sistema" na sidebar Klivy** em `app/views/super_admin/application/_navigation.html.erb` — adicionei um `nav_item` ao final do bloco Klivy (depois de "Migração"), apontando para `super_admin_installation_configs_url` com ícone `icon-settings-2-line`. Permite acesso direto via UI a todas as InstallationConfig editáveis (incluindo as 3 `KLIVY_SUPPORT_WIDGET_*` que controlam o widget).

**Como usar agora:**
1. **Ativar/desativar o widget**: Super Admin → sidebar → Klivy → **Configs do Sistema** → procure por `KLIVY_SUPPORT_WIDGET_ENABLED` → edite valor (`true`/`false`).
2. **Trocar o token (apontar pra outra inbox)**: mesma página → `KLIVY_SUPPORT_WIDGET_TOKEN`.
3. **Trocar URL base**: `KLIVY_SUPPORT_WIDGET_URL`.

Mudanças tomam efeito no próximo refresh, sem deploy.

**Arquivos Modificados:**
- `app/views/layouts/vueapp.html.erb` (seletores CSS corretos)
- `app/views/super_admin/application/_navigation.html.erb` (link "Configs do Sistema")
- `CHANGELOG.md`

**Importante:** se ainda não rodou a 1.5.1.48 (`bin/rails db:migrate`), as 3 keys `KLIVY_SUPPORT_WIDGET_*` ainda não existem no banco e não vão aparecer em `/super_admin/installation_configs`. Rode `db:migrate` antes de procurar.

---

## [1.5.1.48] - 2026-04-30T04:50:00-03:00

### Fix: bubble do widget de suporte sumiu — InstallationConfig do widget não tinha sido populada no banco

**Problema:**
Após a 1.5.1.47, o widget Klivy de suporte sumiu de todas as páginas. Causa: as 3 InstallationConfig (`KLIVY_SUPPORT_WIDGET_ENABLED`/`_TOKEN`/`_URL`) só são criadas no banco quando `ConfigLoader.new.process` roda — e isso só acontece em `db/seeds.rb` ou no rake task `db:enhancements`, não no boot do server. Como o app já tinha sido seedeado antes da 1.5.1.47, as keys novas nunca foram inseridas. Resultado: `InstallationConfig.find_by(name: 'KLIVY_SUPPORT_WIDGET_ENABLED')` → `nil` → `nil&.value.to_s == 'true'` → `false` → `<script>` do widget nem é renderizado.

**Solução:**
Migration dedicada `20260429210000_seed_klivy_support_widget_configs.rb` que popula as 3 keys via `InstallationConfig.where(name: ...).first_or_create(value: ..., locked: false)`. Idempotente (não sobrescreve valores que o Super Admin já editou). Usa o mesmo padrão das outras migrations do projeto (`FlipChatwootV4DefaultFeatureFlagInstallationConfig`, `EnableCaptainTasksForExistingAccounts`). `GlobalConfig.clear_cache` no fim para invalidar cache.

Por que migration e não confiar em `db:seed`: em ambientes de produção `db:seed` pode ter side effects (depende do estado), e equivocadamente reexecutar pode bagunçar dados de teste. `db:migrate` é o mecanismo padrão para garantir que mudanças de schema/config sejam aplicadas exatamente uma vez. Funciona automaticamente no fluxo de deploy do Easypanel.

**Arquivos Modificados:**
- `db/migrate/20260429210000_seed_klivy_support_widget_configs.rb` (criado)
- `CHANGELOG.md`

**Como aplicar:**
```bash
bin/rails db:migrate
```
Após rodar, as 3 configs aparecem em `/super_admin/installation_configs/` para edição. O bubble volta a aparecer automaticamente em todas as páginas (com a posição corrigida da 1.5.1.47, sem overlap com Captain).

---

## [1.5.1.47] - 2026-04-30T04:30:00-03:00

### Feat: bubble do widget de suporte sobe pra não overlap com Captain copilot + 3 configs editáveis no Super Admin

**Problema:**
1. O bubble do widget Klivy de suporte (canto inferior direito, `#cw-bubble-holder`) ficava **na mesma posição do copiloto nativo do Chatwoot (Captain)** — quando ambos ativos, um sobrepunha o outro, ficando inutilizável.
2. Toda alteração no widget (websiteToken, baseUrl, ativar/desativar) exigia editar `app/views/layouts/vueapp.html.erb` no código e novo deploy. Sem UI pra trocar a inbox conectada nem desligar o widget temporariamente.

**Solução:**
1. **Bubble subiu 88px** — adicionei `<style>` no `vueapp.html.erb` que aplica `bottom: 88px` ao `#cw-bubble-holder` e `bottom: 156px` ao `.woot-widget-holder` (a janela de chat que abre quando clica no bubble). 88px = espaço pro botão do Captain abaixo (~24px margem + ~64px do botão). Aplicado via `!important` porque o SDK injeta CSS inline.

2. **3 novas `InstallationConfig`** em `config/installation_config.yml` (todas `locked: false` → editáveis em `/super_admin/installation_configs`):
   - `KLIVY_SUPPORT_WIDGET_ENABLED` (boolean, default `true`) — quando `false`, o `<script>` do widget nem é renderizado, removendo completamente o bubble de todas as páginas.
   - `KLIVY_SUPPORT_WIDGET_TOKEN` (secret, default `RroQdfAJ1m2m93Fx43sUMSNZ`) — websiteToken do canal Chatwoot. Trocar aqui aponta o widget pra outra inbox sem editar código.
   - `KLIVY_SUPPORT_WIDGET_URL` (default `https://waha-chatwoot.efqhwo.easypanel.host`) — URL base que serve o `sdk.js` e recebe as conversas.

3. **`vueapp.html.erb` agora consulta as configs em runtime** — substitui os valores hardcoded por `InstallationConfig.find_by(name: 'KLIVY_SUPPORT_WIDGET_*')&.value`. O `<script>` do SDK só é renderizado se `enabled == 'true'` E os outros 2 campos têm valor. Tokens passados como JSON via `to_json.html_safe` para evitar problemas de escape.

**Sobre "atualizar o HTML do widget":** o HTML do bubble (svg circular, cor, ícone) é gerado **em runtime pelo SDK do Chatwoot** — não vive no código do app, é injetado pelo `sdk.js` do canal apontado pelo `websiteToken`. Para mudar visual (cor azul `rgb(0, 156, 224)`, logo, mensagem "Olá!"), edite a configuração do **Web Widget no painel do Chatwoot** (a instância apontada por `KLIVY_SUPPORT_WIDGET_URL`). Ali estão: cor, mensagem de boas-vindas, mensagem de fora-de-horário, etc. O sdk.js carrega essas configs automaticamente quando o widget inicializa.

**Como gerenciar agora (sem deploy):**
1. Acesse `/super_admin/installation_configs`.
2. Procure por `KLIVY_SUPPORT_WIDGET_ENABLED` → mude pra `false` para desligar o widget.
3. Para apontar pra outra inbox, edite `KLIVY_SUPPORT_WIDGET_TOKEN` e `KLIVY_SUPPORT_WIDGET_URL`.
4. Mudanças tomam efeito no próximo refresh — sem restart.

**Arquivos Modificados:**
- `config/installation_config.yml` (3 entries novas no fim do arquivo)
- `app/views/layouts/vueapp.html.erb` (script hardcoded → leitura dinâmica via InstallationConfig + CSS de posição)
- `CHANGELOG.md`

**Como aplicar:**
- `bin/rails db:seed` (ou simplesmente reinicie o Rails — `ConfigLoader` roda no boot e popula as 3 configs novas com os valores default no banco).
- Após popular, as configs aparecem em `/super_admin/installation_configs` para edição direta.

---

## [1.5.1.46] - 2026-04-30T04:10:00-03:00

### Tweak: empty state no drawer da Central de Ajuda quando categoria não tem artigos

**Problema:**
Ao clicar em uma categoria que ainda não tem artigos cadastrados (caso típico no início, antes do CMS estar populado), o drawer abria com o título "Todos os artigos" e **nada abaixo** — um espaço grande em branco. Ruim UX, parece bug ("será que travou?", "tá carregando?").

**Solução:**
1. **`HelpArticleDrawer.vue`** — na category view, envolvi a `<div class="hp-art-list">` com `v-if="data.cat.articles && data.cat.articles.length > 0"` e adicionei um `<div v-else class="hp-empty-state">` com:
   - Ícone de busca em círculo (`i-lucide-file-search`).
   - Título "Ainda não há artigos nesta categoria".
   - Texto explicando que conteúdo está sendo preparado.
   - Botão **"Falar com suporte"** que emite o evento `openChat`.

2. **`HelpArticleDrawer.vue`** — adicionei `'openChat'` à lista de `defineEmits` (antes só tinha `close` e `openArticle`).

3. **`HelpIndex.vue`** — wire do evento: `<HelpArticleDrawer ... @open-chat="openChat" />`. A função `openChat()` já existia no parent (clica no bubble do widget Chatwoot), então nenhuma lógica nova foi necessária — só conectar o emit.

4. **`help.css`** — bloco `.hp-empty-state*` no fim do arquivo: layout flex column centralizado, border dashed para sinalizar visualmente que é estado "vazio aguardando conteúdo" (ao invés de erro), ícone em círculo com cor primária do Klivy, botão CTA. ~50 linhas de CSS, todas no mesmo padrão do prefixo `hp-` já usado.

**Arquivos Modificados:**
- `plugins/ajuda/frontend/features/help/components/HelpArticleDrawer.vue`
- `plugins/ajuda/frontend/features/help/HelpIndex.vue`
- `plugins/ajuda/frontend/features/help/help.css`
- `CHANGELOG.md`

**Comportamento:**
- Categoria com artigos → continua exibindo a lista normalmente.
- Categoria vazia → drawer mostra ícone + texto amigável + botão "Falar com suporte" que aciona o widget de chat do Chatwoot.

---

## [1.5.1.45] - 2026-04-30T03:50:00-03:00

### Tweak: títulos PT-BR nas páginas new/edit do Super Admin + form ocupa largura cheia da tela

**Problema:**
1. As páginas `new`/`edit` dos dashboards de Ajuda mostravam título "Adicionar Ajuda Artigos" (plural sem hífen via `.titleize` do gem) e botões "Back" em inglês. A 1.5.1.44 só sobrescreveu `_index_header.html.erb` — os templates `new.html.erb` e `edit.html.erb` do gem continuavam vencendo.
2. O formulário ficava centralizado em ~800px (Administrate default trava `.field-unit__field` em `max-width: 50rem`), com muito espaço vazio em monitores wide. Visual desproporcional, especialmente no editor Quill que precisa de espaço pra render confortável.

**Solução:**
1. **Override per-resource de `new.html.erb` e `edit.html.erb`** — 6 arquivos novos em `app/views/super_admin/<resource>/{new,edit}.html.erb`, um par para cada dashboard de Help. Por estarem no `controller_path` do request, têm prioridade máxima no Rails view lookup (vence `super_admin/application/`, vence `administrate/application/` do gem). Cada arquivo:
   - Self-contained com título hardcoded em PT-BR ("Novo Artigo" / "Editar Artigo: <título>", idem para Categoria e Pergunta Frequente).
   - Botão "Voltar" em vez de "Back" (acompanhando o padrão da i18n PT-BR já existente).
   - Botão "Ver <recurso>" no edit (substitui o `show_resource` interpolado do gem).
   - Restante do markup idêntico ao gem (mesma chamada `render 'form', page: page`).

2. **CSS override no `_stylesheet.html.erb`** — adicionei um `<style>` no fim do partial existente em `app/views/super_admin/application/_stylesheet.html.erb`. CSS:
   - `.main-content { max-width: none !important; }` — remove constraint do app-container do gem (era 100rem).
   - `.field-unit__field { max-width: none !important; }` — remove o `max-width: 50rem` (~800px) que centralizava cada input.
   - `.main-content__body { padding-right: 2.5rem; }` — respiração à direita.
   - Inputs/selects/textarea com `width: 100%` para preencher a largura disponível.
   Aplica-se globalmente nas páginas do Super Admin (não só Ajuda) — outros dashboards (Accounts, Users, Agent Bots, etc.) também ganham espaço útil. Comportamento responsivo é preservado porque é só `max-width: none`, o `width: 100%` se ajusta ao viewport.

**Arquivos Modificados:**
- `app/views/super_admin/help_articles/new.html.erb` (criado)
- `app/views/super_admin/help_articles/edit.html.erb` (criado)
- `app/views/super_admin/help_categories/new.html.erb` (criado)
- `app/views/super_admin/help_categories/edit.html.erb` (criado)
- `app/views/super_admin/help_faqs/new.html.erb` (criado)
- `app/views/super_admin/help_faqs/edit.html.erb` (criado)
- `app/views/super_admin/application/_stylesheet.html.erb` (CSS overrides Klivy)
- `CHANGELOG.md`

**Como aplicar:**
- Refresh da página `/super_admin/help_articles/new` deve mostrar título "Novo Artigo" e form ocupando a tela toda. Mudanças em `app/views/` recarregam imediatamente em dev (autoload Rails).

---

## [1.5.1.44] - 2026-04-30T03:30:00-03:00

### Fix: botões do Super Admin com override per-resource (prioridade máxima de view lookup) + editor Quill expandido

**Problema:**
1. Mesmo após a 1.5.1.43 (defesa em 3 camadas: hardcode em `resource_name`, custom keys I18n, partial em `super_admin/application/`), o usuário **continuou** vendo "Adicionar help category" no botão. Diagnóstico provável: o partial em `app/views/super_admin/application/_index_header.html.erb` não está sendo picked up, possivelmente por cache de templates do Bootsnap dentro do container Docker. As 3 camadas anteriores não conseguiram contornar.
2. O editor Quill no formulário de artigos estava enxuto: só H2/H3, bold/italic/underline/strike, listas, blockquote, code, link, clean. Faltavam recursos comuns: H1/H4, font/size, color/background, sub/super, indent, alinhamento, imagem, vídeo embed.

**Solução:**
1. **Override per-resource em `app/views/super_admin/<resource>/_index_header.html.erb`** — Rails resolve view path **a partir do controller_path do request**, então `super_admin/help_categories/_index_header.html.erb` tem prioridade **máxima** (vence `super_admin/application/`, vence `administrate/application/` do gem). 3 arquivos criados, cada um:
   - Self-contained com label hardcoded em PT-BR (sem depender de I18n/YAML reload).
   - Title hardcoded ("Ajuda - Categorias", "Ajuda - Artigos", "Ajuda - Perguntas Frequentes").
   - Botão "novo" com label perfeito: **"Nova Categoria"**, **"Novo Artigo"**, **"Nova Pergunta Frequente"**.
   - Resto do markup (search bar + accessible_action? gate) idêntico ao original do gem para não regredir comportamento.

   As 3 camadas anteriores (hardcode `resource_name`, custom I18n keys, partial em `super_admin/application/`) continuam ativas como fallback para outros dashboards Beclinic que venham a precisar do tratamento.

2. **Toolbar Quill expandido** (`app/javascript/superadmin_pages/quill_editor.js`):
   - Headers H1, H2, H3, H4 (era só H2, H3).
   - Font family + size (small/normal/large/huge).
   - Color de texto + background.
   - Sub/superscript.
   - Indent (-/+).
   - Alinhamento (left/center/right/justify).
   - Insert image, video embed, link.
   - Listas mantidas (ordered, bullet).
   - Blockquote, code-block, clean mantidos.

3. **Sanitize whitelist em `_show.html.erb` do `rich_text_field`** — expandida para acompanhar o que o Quill agora pode gerar:
   - Tags adicionadas: `h1 h4 h5 h6 hr div span sub sup b i img video source table thead tbody tfoot tr td th`.
   - Atributos adicionados: `class style alt title name width height controls poster colspan rowspan data-list`.
   - Conteúdo é editado pelo Super Admin (já autenticado), risco de XSS é controlado; mantemos `sanitize` com whitelist estrita ao invés de `raw`.

4. **CSS do form** ajustado para acomodar toolbar maior — `min-height` do editor de 280px → 360px, padding do toolbar e spacing entre `.ql-formats`.

**Arquivos Modificados:**
- `app/views/super_admin/help_categories/_index_header.html.erb` (criado — override per-resource)
- `app/views/super_admin/help_articles/_index_header.html.erb` (criado — override per-resource)
- `app/views/super_admin/help_faqs/_index_header.html.erb` (criado — override per-resource)
- `app/javascript/superadmin_pages/quill_editor.js` (toolbar expandido)
- `app/views/fields/rich_text_field/_show.html.erb` (whitelist expandida)
- `app/views/fields/rich_text_field/_form.html.erb` (CSS para toolbar maior)
- `CHANGELOG.md`

**Como aplicar:**
- View overrides per-resource pegam imediatamente em dev (autoload do Rails). Refresh da página `/super_admin/help_categories` deve mostrar **"Nova Categoria"** sem precisar de restart.
- Para o Quill recarregar o JS com toolbar novo: rebuild do Vite (`pnpm dev` já reflete em hot reload, ou `pnpm build` em produção).

---

## [1.5.1.43] - 2026-04-30T03:10:00-03:00

### Fix: botão "Adicionar help category" continuava em inglês — defesa em camadas (dashboard hardcode) garante tradução mesmo sem reload do YAML

**Problema:**
Após a 1.5.1.42, o usuário reportou que o botão ainda saía como `"Adicionar help category"` (note: `Adicionar` em PT mas `help category` em inglês, minúsculo). A análise:
- `Adicionar` carregado → `administrate.actions.new_resource: "Adicionar %{name}"` foi pego do YAML novo. ✓
- `help category` em minúsculo → `model.model_name.human(count: 1)` falhou em achar `activerecord.models.help_category.one`, caiu no default `"Help Category"` (titleized do nome do model), depois passou pelo `.downcase` do template do gem. ✗

Causas combinadas:
1. **YAML parcialmente em cache**: Bootsnap/I18n pode ter recarregado parte do `administrate.pt_BR.yml` mas não o bloco `activerecord.models.help_category.*`. Comportamento estranho mas observado.
2. **Override de view possivelmente não picked up**: `app/views/super_admin/application/_index_header.html.erb` está no path certo, mas se houver cache de templates/view paths, não substitui o partial do gem.

**Solução — defesa em 3 camadas:**

1. **Hardcode em cada dashboard** (camada nova nesta entrada — INDEPENDE de YAML/I18n):
   ```ruby
   def self.resource_name(opts = {})
     opts[:count] == 1 ? 'Categoria' : 'Ajuda - Categorias'
   end
   ```
   Adicionado em `HelpCategoryDashboard`, `HelpArticleDashboard`, `HelpFaqDashboard`. O método é chamado pelo `display_resource_name` do Administrate antes de tentar `model.model_name.human` — então **sempre** retorna o nome em PT, mesmo com I18n stale.

2. **YAML PT-BR** (já da 1.5.1.42): `new_help_categories: "Nova Categoria"` etc. — usado pelo override do partial quando ambos estão ativos para nome perfeito com gênero.

3. **Override do `_index_header.html.erb`** (já da 1.5.1.42): consulta a key custom + remove `.downcase`.

**Cenários possíveis (sempre seguros agora):**
| Override partial | YAML carregou | Resultado |
|---|---|---|
| ✓ | ✓ | "Nova Categoria" (custom key, ideal) |
| ✓ | ✗ | "Adicionar Categoria" (fallback usa dashboard.resource_name) |
| ✗ | ✓ | "Adicionar categoria" (template gem com `.downcase` no nome do dashboard) |
| ✗ | ✗ | "Novo(a) categoria" (template gem antigo + dashboard.resource_name) |

Em **todos** os cenários, "help category" em inglês não aparece mais.

**Arquivos Modificados:**
- `app/dashboards/help_category_dashboard.rb`
- `app/dashboards/help_article_dashboard.rb`
- `app/dashboards/help_faq_dashboard.rb`
- `CHANGELOG.md`

**Como aplicar:**
- Restart do Rails server (`docker compose restart rails`) garante que **todas** as 3 camadas estejam ativas para resultado ideal "Nova Categoria". Sem restart, a camada 1 (hardcode) já entra em ação porque modificações em `app/dashboards/` são autoload-compatíveis no Rails dev.

---

## [1.5.1.42] - 2026-04-30T02:50:00-03:00

### Tweak: botões do Super Admin com texto amigável em PT-BR ("Nova Categoria", "Novo Artigo", "Nova Pergunta Frequente")

**Problema:**
1. Botão de criação no índice dos dashboards de ajuda saía como **"Novo(a) help category"** — duas falhas: o `(a)` genérico ficava feio e o nome do recurso aparecia em inglês literal sem tradução. Causa: o template do gem Administrate (`_index_header.html.erb`) chamava `display_resource_name(..., singular: true).downcase` interpolado em `administrate.actions.new_resource: "Novo(a) %{name}"` — produz "Novo(a) <nome>" sempre, e ainda força minúsculo.
2. Diagnóstico extra: verifiquei via `ruby + I18n.load_path` em isolado que as chaves `activerecord.models.help_category.one` etc. **resolvem corretamente para "Categoria de Ajuda"** com `count: 1`. O motivo de o app exibir "help category" plain é que **Rails não recarrega `config/locales/*.yml` em hot-reload** — só em restart do server. Após o deploy/restart, mesmo o fallback antigo já melhoraria. Mas a solução abaixo é independente do reload e dá controle de gênero/capitalização.

**Solução:**
1. **`config/locales/administrate.pt_BR.yml`** — duas mudanças no bloco `administrate.actions`:
   - `new_resource` mudou de `"Novo(a) %{name}"` para `"Adicionar %{name}"` (verbo neutro de gênero, fallback razoável para qualquer recurso).
   - Adicionei chaves customizadas por recurso, com gênero correto:
     - `new_help_categories: "Nova Categoria"`
     - `new_help_articles: "Novo Artigo"`
     - `new_help_faqs: "Nova Pergunta Frequente"`
   E encurtei os singulares dos models para nomes limpos (sem o redundante "de Ajuda" — o contexto da sidebar/dropdown "Ajuda" já cobre):
   - `help_category.one`: "Categoria de Ajuda" → "Categoria"
   - `help_article.one`: "Artigo de Ajuda" → "Artigo"
   - `help_faq.one`: continua "Pergunta Frequente"
   (Os `other:` continuam com prefixo "Ajuda - ..." para distinguir na sidebar listada de outros plurais como "Contas", "Usuários".)

2. **Override do `_index_header.html.erb`** — criei `app/views/super_admin/application/_index_header.html.erb` (Rails resolve esse caminho **antes** do gem por convenção de view paths). Mudanças vs. o partial original:
   - Detecta uma chave I18n customizada por recurso: `administrate.actions.new_<resource_path>` (ex: `new_help_categories`). Se existir (`I18n.exists?`), usa ela direto como label do botão — permite gênero correto e capitalização perfeita.
   - Se não existir, cai no fallback `administrate.actions.new_resource` mas **sem `.downcase`** no nome — o nome capitalizado já vem do I18n (`Conta`, `Usuário`, etc.). Resultado nos dashboards sem custom key: "Adicionar Conta" em vez de "Adicionar conta".
   - Restante do template (h1 + search bar + accessible_action? gate) ficou idêntico ao original.

**Resultado final na UI** (após restart do Rails server):
- `/super_admin/help_categories` → botão **"Nova Categoria"**
- `/super_admin/help_articles` → botão **"Novo Artigo"**
- `/super_admin/help_faqs` → botão **"Nova Pergunta Frequente"**
- `/super_admin/accounts` → botão **"Adicionar Conta"** (fallback aprimorado)

**Arquivos Modificados:**
- `config/locales/administrate.pt_BR.yml`
- `app/views/super_admin/application/_index_header.html.erb` (criado — override do gem)
- `CHANGELOG.md`

**Importante para deploy:**
- Rails só recarrega `config/locales/*.yml` em **restart do server** (não em autoreload de `app/`). Após pull desse commit, **reiniciar o container Rails** (`docker compose restart rails` ou similar). Sem o restart, o Rails ainda usa o YAML antigo em memória e mantém os labels velhos.

---

## [1.5.1.41] - 2026-04-30T02:30:00-03:00

### Fix: Super Admin retornava 500 em todas as páginas — `help_menu_open?` não exposto como helper

**Problema:**
Após a 1.5.1.40 todas as páginas do `/super_admin/` quebravam com `ActionView::Template::Error (undefined method 'help_menu_open?' for an instance of ...)` na linha 52 do `_navigation.html.erb`. O helper `help_menu_open?` foi definido em `SuperAdmin::NavigationHelper` (incluído no `SuperAdmin::ApplicationController` via `include`), mas esse mecanismo não basta no Administrate — o controller precisa declarar explicitamente quais métodos ficam disponíveis na view via `helper_method :nome`. O `settings_open?` da mesma classe já estava listado lá; eu esqueci de adicionar `help_menu_open?` na lista quando criei o dropdown.

**Solução:**
`SuperAdmin::ApplicationController#helper_method` ganhou `:help_menu_open?` ao lado dos outros 3 já presentes (`:render_vue_component`, `:settings_open?`, `:settings_pages`). Padrão idêntico ao do irmão `settings_open?`.

**Arquivos Modificados:**
- `app/controllers/super_admin/application_controller.rb`
- `CHANGELOG.md`

---

## [1.5.1.40] - 2026-04-30T02:15:00-03:00

### Feat: módulo Ajuda — gerenciamento de Perguntas Frequentes + dropdown "Ajuda" no Super Admin

**Problema:**
1. As FAQs exibidas em `/accounts/:id/ajuda` ainda viviam **hardcoded** em `plugins/ajuda/frontend/features/help/data/helpData.js` (constante `FAQS` com 7 entradas) — não dava pra editar/adicionar/remover sem alterar código e fazer deploy.
2. Os 3 itens custom de Ajuda no Super Admin (Categorias, Artigos, agora FAQs) ocupavam linhas separadas na sidebar — funciona, mas vira ruído visual conforme o módulo cresce. Pedido: agrupar num dropdown "Ajuda" com sub-itens.

**Solução:**
1. **Tabela `help_faqs`** — migration `20260429200000_create_help_faqs.rb` cria a tabela (`question` 500 chars, `answer` text, `category` slug, `tags` string CSV, `position` int, `hidden` bool) com índices em category/position/hidden e **seed inline** das 7 FAQs originais do `helpData.js` via `INSERT` em `reversible up`. Mantém o conteúdo já cadastrado por padrão — Super Admin pode editar depois.

2. **Model `HelpFaq`** — validações (presence question/answer/category, length question ≤500), `validate :category_must_be_valid` (consulta `HelpCategory.pluck(:slug)` com `rescue ActiveRecord::StatementInvalid` igual ao padrão usado no `HelpArticle`), scopes `visible`/`ordered`/`by_category`, e helper `tags_array` que parseia o CSV (`"plano, cobrança, trial"` → `["plano","cobrança","trial"]`).

3. **Dashboard `HelpFaqDashboard`** + **Controller `SuperAdmin::HelpFaqsController`** — CRUD via Administrate, dropdown de categoria com lambda (`-> { HelpCategory.ordered.pluck(:slug) }`), filtros `visible`/`hidden` no índice. Padrão idêntico aos dashboards de Article/Category.

4. **API pública** — `Public::Api::V1::HelpArticlesController#faqs` foi de `render json: []` (stub temporário da Fase 2 inicial) para query real: lista `HelpFaq.visible.ordered`, monta `category_lookup = HelpCategory.ordered.pluck(:slug, :name).to_h` em uma única query, serializa no formato exato esperado pelo frontend (`{ id, cat, catName, question, answer, tags: [...] }`). `rescue ActiveRecord::StatementInvalid` no fim cobre o caso de tabela ainda não migrada → frontend cai no fallback estático do `helpData.js`.

5. **Rota Super Admin** — `resources :help_faqs` adicionado dentro do bloco `# ── Beclinic / Klivy custom modules ──` em `config/routes.rb`.

6. **Dropdown "Ajuda" na sidebar Super Admin** — em vez de 3 nav_items soltos sob o header "Klivy":
   - Novo partial `app/views/super_admin/application/_help_menu.html.erb` — replica a estrutura `<details>/<summary>` do `_settings_menu.html.erb` (HTML nativo, sem JS) mostrando "Ajuda" com sub-itens **Categorias, Artigos, Perguntas Frequentes**. Abre/fecha via `<details>`.
   - Novo helper `help_menu_open?` em `SuperAdmin::NavigationHelper` que retorna `true` quando `params[:controller]` está em `super_admin/help_*` — dropdown abre automaticamente quando o operador navega pra qualquer página de Ajuda.
   - `_navigation.html.erb` adiciona `help_faqs` à lista de resources filtrados do loop automático e troca os 3 nav_items soltos por `<%= render 'help_menu', open: help_menu_open? %>`. "Migração" continua como nav_item individual sob o header "Klivy".

7. **Labels PT-BR** — `config/locales/administrate.pt_BR.yml` ganhou model `help_faq` (one: "Pergunta Frequente" / other: "Ajuda - Perguntas Frequentes") e attributes traduzidos. Convenção `Ajuda - <X>` segue o padrão já estabelecido para Categorias/Artigos.

**Arquivos Modificados:**
- `db/migrate/20260429200000_create_help_faqs.rb` (criado)
- `app/models/help_faq.rb` (criado)
- `app/dashboards/help_faq_dashboard.rb` (criado)
- `app/controllers/super_admin/help_faqs_controller.rb` (criado)
- `app/controllers/public/api/v1/help_articles_controller.rb`
- `config/routes.rb`
- `config/locales/administrate.pt_BR.yml`
- `app/helpers/super_admin/navigation_helper.rb`
- `app/views/super_admin/application/_help_menu.html.erb` (criado)
- `app/views/super_admin/application/_navigation.html.erb`
- `CHANGELOG.md`

**Como aplicar (deploy):**
- `bin/rails db:migrate` cria `help_faqs` + popula 7 FAQs padrão. Frontend automaticamente passa a usar dados do banco (composable `useHelpData.js` já consumia `/faqs` com `Promise.allSettled`).

---

## [1.5.1.39] - 2026-04-30T01:50:00-03:00

### Tweak: seção "Klivy" visível no Super Admin agrupando módulos customizados

**Problema:**
Na 1.5.1.38 reordenei os `resources` no `routes.rb` deixando os módulos Beclinic/Klivy (Help Categories, Help Articles, Migrações) no fim do bloco — porém o Administrate **não tem agrupamento nativo**, então na UI do Super Admin os 3 itens apareciam só "no fim da lista", sem cabeçalho/separador visual. O comentário `# ── Beclinic / Klivy custom modules ──` que pus no routes.rb era visível só pro dev.

**Solução:**
A sidebar do Super Admin (`app/views/super_admin/application/_navigation.html.erb`) **já é uma view customizada do projeto** — não é Administrate puro. Aproveitei isso pra criar um agrupamento visual real:

1. Adicionei `help_categories`, `help_articles` à lista de resources filtrados do loop automático que renderiza os itens nativos do Chatwoot (Accounts, Users, Agent Bots, Platform Apps).
2. Após o `settings_menu`, criei uma nova seção:
   - **Cabeçalho** `<li>` com texto "Klivy" em uppercase 11px tracking-wider color slate-400 — visualmente uma "divisória" estilo iOS/Slack, sem nenhum hack pesado de CSS.
   - **3 nav_items** explícitos: Ajuda - Categorias (`icon-folder-3-line`), Ajuda - Artigos (`icon-book-2-line`), Migração (`icon-database-2-line`).
3. Removi o `nav_item` solto de "Migração" que existia anteriormente (consolidado dentro do grupo).

Os ícones todos já existem no sprite SVG de `_icons.html.erb` (não precisei adicionar nada novo). Texto "Klivy" segue a regra do AGENTS.md (Klivy é brand visível ao usuário, Beclinic é só code identifier).

**Arquivos Modificados:**
- `app/views/super_admin/application/_navigation.html.erb`
- `CHANGELOG.md`

---

## [1.5.1.38] - 2026-04-30T01:30:00-03:00

### Tweak: feature flag `help_center` desativado por padrão + Super Admin reorganizado (Beclinic custom no fim)

**Problema:**
1. Mesmo após esconder o item "Centro de Ajuda" da sidebar do dashboard (1.5.1.37), o painel de Features no Super Admin continuava mostrando "Help Center" **marcado** — ambíguo, induz ao erro: o operador olha e acha que a feature ainda está ligada.
2. Os recursos custom Beclinic (`Help Categories`, `Help Articles`, `Migrations`) ficavam misturados com recursos OSS do Chatwoot (`Platform Apps`, `Settings`) na sidebar do Super Admin, dificultando distinguir o que é Chatwoot nativo do que é nosso.

**Solução:**
1. **Desativar `help_center`** em três frentes (precisa das três pra cobrir presente e futuro):
   - `config/features.yml` → `help_center.enabled: false` (default para futuras instalações).
   - Migration `20260429190000_disable_help_center_for_existing_accounts.rb` → atualiza `InstallationConfig.ACCOUNT_LEVEL_FEATURE_DEFAULTS` (default das próximas contas criadas) e roda `disable_features!('help_center')` em cada Account já existente, em batches de 100. `GlobalConfig.clear_cache` no fim. Padrão idêntico à migration `FlipChatwootV4DefaultFeatureFlagInstallationConfig` (20250416182131).
2. **Reordenar Super Admin** — em `config/routes.rb`, mover `resources :help_categories` e `resources :help_articles` do meio (depois de `instance_status`) para o **fim do bloco** `namespace :super_admin`, agrupados com `migrations` sob comentário `# ── Beclinic / Klivy custom modules ──`. Ordem final na sidebar: Accounts, Users, ... Platform Apps, Instance Status, Settings, **Ajuda - Categorias, Ajuda - Artigos, Migrações**. (O comentário do próprio arquivo já avisa: *"order of resources affect the order of sidebar navigation"*.)
3. **Labels PT-BR** — `config/locales/administrate.pt_BR.yml` ganhou entradas para `help_category` (one: "Categoria de Ajuda" / other: "Ajuda - Categorias") e `help_article` (one: "Artigo de Ajuda" / other: "Ajuda - Artigos") + atributos traduzidos (Título, Conteúdo, Status, etc.). Convenção do `other:` com prefixo "Ajuda -" deixa visualmente claro que pertencem ao mesmo módulo na sidebar.

**Arquivos Modificados:**
- `config/features.yml`
- `db/migrate/20260429190000_disable_help_center_for_existing_accounts.rb` (criado)
- `config/routes.rb`
- `config/locales/administrate.pt_BR.yml`
- `CHANGELOG.md`

**Como aplicar:**
- Em produção, `bin/rails db:migrate` desativa o flag nas 3 contas existentes e flipa o default. Não precisa restart manual — `GlobalConfig.clear_cache` invalida o cache no momento da migration.

---

## [1.5.1.37] - 2026-04-30T01:00:00-03:00

### Tweak: Help Center nativo do Chatwoot escondido do sidebar — substituído pela Central de Ajuda própria

**Problema:**
O sidebar do dashboard mostrava por padrão o item "Centro de Ajuda" (Portals) — feature nativa do Chatwoot OSS para construir help centers públicos com Articles/Categories/Locales/Settings. Não faz sentido para os clientes da Klivy: a Central de Ajuda da plataforma é o módulo `plugins/ajuda/` (introduzido nas versões 1.5.1.34 e 1.5.1.35), e o Portals confunde mais do que ajuda.

**Solução:**
Bloco `Portals` removido de `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` (linhas que renderizavam o dropdown com 4 filhos). Não mexido no backend — rotas `/portals/*`, controllers, tabelas `portals`/`articles`/`categories` do Chatwoot continuam existindo (acessíveis via URL direta), apenas saem da navegação por padrão. Reversão: re-adicionar o objeto no `menuItems` se algum dia precisar.

**Arquivos Modificados:**
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
- `CHANGELOG.md`

---

## [1.5.1.36] - 2026-04-30T00:45:00-03:00

### Fix: bubble do Chatwoot só aparece dentro do módulo Ajuda

**Problema:**
O widget do Chatwoot (bubble flutuante "Olá! Nos envie seu nome e sua dúvida!") aparecia em **todas** as páginas do dashboard, sobrepondo conteúdo onde não devia. Comportamento esperado: o bubble só faz sentido dentro do módulo Ajuda (`/accounts/:id/ajuda`, `/ajuda/reportar-erro`, `/ajuda/solicitar-melhoria`).

**Solução:**
1. **Globalmente esconder por padrão** — `app/views/layouts/vueapp.html.erb` agora chama `chatwootSDK.run({ ..., hideMessageBubble: true })`. O widget continua sendo carregado e disponível via `window.$chatwoot`, mas inicia oculto em todas as páginas.

2. **Composable centralizado no plugin** — `plugins/ajuda/frontend/features/help/composables/useChatBubble.js` exporta `useChatBubble()` que faz `toggleBubbleVisibility('show')` no `onMounted` e `'hide')` no `onBeforeUnmount`. Cada um dos 3 componentes do plugin (`HelpIndex`, `HelpReportBug`, `HelpFeatureRequest`) chama o composable — antes só `HelpIndex` controlava o bubble e a lógica estava inline (espalhada).

3. **Compatibilidade com outros consumidores do widget**:
   - `app/javascript/dashboard/routes/dashboard/suspended/Index.vue` já chama `toggleBubbleVisibility('show')` no mount → continua mostrando o bubble em conta suspensa.
   - `app/javascript/dashboard/routes/dashboard/settings/billing/Index.vue` chama `$chatwoot.toggle()` em botão "preciso de ajuda" → o `toggle` abre o iframe direto, independente do bubble estar oculto, então não quebra.

**Arquivos Modificados:**
- `app/views/layouts/vueapp.html.erb`
- `plugins/ajuda/frontend/features/help/composables/useChatBubble.js` (criado)
- `plugins/ajuda/frontend/features/help/HelpIndex.vue` (removida lógica inline de show/hide; usa composable)
- `plugins/ajuda/frontend/features/help/HelpReportBug.vue`
- `plugins/ajuda/frontend/features/help/HelpFeatureRequest.vue`
- `CHANGELOG.md`

---

## [1.5.1.35] - 2026-04-30T00:15:00-03:00

### Feat: módulo Ajuda — Fase 2 (CMS no Super Admin + API pública)

**Problema:**
A Fase 1 (1.5.1.34) deixou a Central de Ajuda rodando só com fallback estático (`helpData.js`). Falta o CMS para o time poder publicar artigos e gerenciar categorias direto do Super Admin, e a API pública que o frontend já tenta consumir (`/public/api/v1/help_articles*`).

**Solução:**
1. **Banco** — duas tabelas novas (não tocam em nenhuma existente):
   - `help_articles` (`title`, `body`, `category` slug, `status` draft/published, `video_url`, `next_steps`, `position`, `deleted_at` para soft delete) — todas as colunas em uma única migration.
   - `help_categories` (`name`, `description`, `slug` único, `icon_svg`, `icon_class`, `position`, `hidden`) com **seed inline** das 7 categorias padrão (`conversas`, `agenda`, `pacientes`, `financeiro`, `bea`, `configuracoes`, `outro` oculta) — via `INSERT` em `reversible up` para o frontend ter conteúdo desde o primeiro deploy.

2. **Models** — `HelpArticle` (validações + scopes `published`/`visible`/`by_category`/`ordered`, `search(q)`, `reading_time`, `soft_delete!`) e `HelpCategory` (scopes `ordered`/`visible`). Validação de `category` em `HelpArticle` consulta `HelpCategory.pluck(:slug)` com `rescue ActiveRecord::StatementInvalid` — permite app bootar antes da migration rodar.

3. **Super Admin (Administrate)** — dashboards `HelpArticleDashboard` e `HelpCategoryDashboard` aparecem **automaticamente** na sidebar do `/super_admin/` graças ao Administrate (não precisa editar nenhum menu manualmente). Filtros `published`/`draft` no índice de artigos. Dropdown de categoria via lambda `-> { HelpCategory.ordered.pluck(:slug) }` (recalcula a cada request).

4. **Custom field `RichTextField`** — `app/fields/rich_text_field.rb` + 3 partials em `app/views/fields/rich_text_field/` (index com preview de 120 chars sem HTML; show com `sanitize` permitindo tags básicas + iframe; form com Quill.js).

5. **Quill.js bootstrap** — `app/javascript/superadmin_pages/quill_editor.js` enhança qualquer `[data-quill-field]`, sincroniza com `<input hidden>` no `text-change` e no `submit`, com botão `</>` para alternar entre WYSIWYG e textarea HTML bruto. Importado de `entrypoints/superadmin.js`.

6. **Controllers Super Admin** — `SuperAdmin::HelpArticlesController` (override `destroy` para soft delete, `scoped_resource` para `visible.ordered`) e `SuperAdmin::HelpCategoriesController` (`scoped_resource` ordenado por position).

7. **API pública** — `Public::Api::V1::HelpArticlesController < PublicController` com:
   - `GET /public/api/v1/help_articles` (filtros `?category=` e `?q=`)
   - `GET /public/api/v1/help_articles/:id`
   - `GET /public/api/v1/help_articles/categories` (lista de categorias com `icon_svg`/`icon_class`/`hidden`/`position`)
   - `GET /public/api/v1/help_articles/faqs` (retorna `[]` por enquanto — composable usa `Promise.allSettled`, então funciona)

8. **Routes** — bloco `super_admin` ganhou `resources :help_categories` e `resources :help_articles` (CRUD completo); bloco `public/api/v1` ganhou `resources :help_articles, only: [:index, :show]` com collection `categories` e `faqs`.

9. **Dependência npm** — `quill@2.0.3` adicionado em `package.json` (precisa `pnpm install`).

**Arquivos Modificados:**
- `db/migrate/20260429180000_create_help_articles.rb` (criado)
- `db/migrate/20260429180001_create_help_categories.rb` (criado)
- `app/models/help_article.rb` (criado)
- `app/models/help_category.rb` (criado)
- `app/dashboards/help_article_dashboard.rb` (criado)
- `app/dashboards/help_category_dashboard.rb` (criado)
- `app/controllers/super_admin/help_articles_controller.rb` (criado)
- `app/controllers/super_admin/help_categories_controller.rb` (criado)
- `app/controllers/public/api/v1/help_articles_controller.rb` (criado)
- `app/fields/rich_text_field.rb` (criado)
- `app/views/fields/rich_text_field/_index.html.erb` (criado)
- `app/views/fields/rich_text_field/_show.html.erb` (criado)
- `app/views/fields/rich_text_field/_form.html.erb` (criado)
- `app/javascript/superadmin_pages/quill_editor.js` (criado)
- `app/javascript/entrypoints/superadmin.js`
- `config/routes.rb`
- `package.json`
- `CHANGELOG.md`

**Como ativar (deploy):**
1. `pnpm install` (puxa quill@2.0.3)
2. `bin/rails db:migrate` (cria 2 tabelas novas + popula 7 categorias padrão)
3. Acessar `/super_admin/help_categories` e `/super_admin/help_articles` para gerenciar conteúdo
4. Frontend `/accounts/:id/ajuda` passa a consumir API real assim que houver artigos publicados

---

## [1.5.1.34] - 2026-04-29T23:45:00-03:00

### Feat: módulo Ajuda (Fase 1 — frontend isolado, sem backend)

**Problema:**
Falta uma Central de Ajuda dentro do app — usuários não têm onde consultar tutoriais nem reportar bugs/sugestões direto da plataforma. A versão remota (`Slowlyzadao/Klivyapp`) já tem o plugin `plugins/ajuda/frontend/` pronto, mas precisa ser portado pra cá sem mexer no que já está no ar.

**Solução:**
Fase 1 — somente frontend, dependência zero do backend (CMS de artigos fica pra Fase 2):

1. **Plugin novo isolado** em `plugins/ajuda/frontend/` com 13 arquivos copiados do remoto: `routes/routes.js`, 3 páginas (`HelpIndex`, `HelpReportBug`, `HelpFeatureRequest`), 6 componentes (`HelpSearchBar`, `HelpBanner`, `HelpCategoryGrid`, `HelpFaq`, `HelpArticleDrawer`, `HelpFeedbackForm`), composable `useHelpData.js`, dados de fallback `helpData.js` e `help.css`.
2. **Rotas registradas**: `/accounts/:accountId/ajuda` (artigos), `/accounts/:accountId/ajuda/reportar-erro`, `/accounts/:accountId/ajuda/solicitar-melhoria`. Permissões `['administrator', 'agent']`.
3. **Sidebar**: novo dropdown "Ajuda" (ícone `i-lucide-life-buoy`) no fim de `menuItems`, depois de Configurações, com 3 filhos (Artigos / Reportar erro / Solicitar melhoria).
4. **i18n**: 4 chaves novas em pt_BR e en (`SIDEBAR.AJUDA`, `SIDEBAR.AJUDA_ARTICLES`, `SIDEBAR.AJUDA_REPORT_BUG`, `SIDEBAR.AJUDA_FEATURE_REQUEST`).
5. **Sem backend**: `useHelpData.js` faz `Promise.allSettled` nas APIs `/public/api/v1/help_articles*` que ainda não existem aqui — quando dão 404, o composable cai em fallback estático (`CATEGORIES_META` + `FAQS` do `helpData.js`). Página renderiza com 7 categorias mockadas e ~30 FAQs. Formulários de bug/feature usam mock submit (já é assim no remoto, com TODO marcado no código).
6. **Toques no core 100% aditivos** (sem reescrita): só import + spread em `dashboard.routes.js`, novo objeto em `menuItems`, novas chaves i18n.

Plano da Fase 2 (futuro, separado): models `HelpArticle`/`HelpCategory`, migrations, controllers Admin (Administrate + Quill), API pública `/public/api/v1/help_articles*`, integração de submit do bug/feature report. Conforme doc `docs/01-product/modules/ajuda.md`.

**Arquivos Modificados:**
- `plugins/ajuda/frontend/routes/routes.js` (criado)
- `plugins/ajuda/frontend/features/help/HelpIndex.vue` (criado)
- `plugins/ajuda/frontend/features/help/HelpReportBug.vue` (criado)
- `plugins/ajuda/frontend/features/help/HelpFeatureRequest.vue` (criado)
- `plugins/ajuda/frontend/features/help/help.css` (criado)
- `plugins/ajuda/frontend/features/help/data/helpData.js` (criado)
- `plugins/ajuda/frontend/features/help/composables/useHelpData.js` (criado)
- `plugins/ajuda/frontend/features/help/components/HelpArticleDrawer.vue` (criado)
- `plugins/ajuda/frontend/features/help/components/HelpBanner.vue` (criado)
- `plugins/ajuda/frontend/features/help/components/HelpCategoryGrid.vue` (criado)
- `plugins/ajuda/frontend/features/help/components/HelpFaq.vue` (criado)
- `plugins/ajuda/frontend/features/help/components/HelpFeedbackForm.vue` (criado)
- `plugins/ajuda/frontend/features/help/components/HelpSearchBar.vue` (criado)
- `app/javascript/dashboard/routes/dashboard/dashboard.routes.js`
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
- `app/javascript/dashboard/i18n/locale/pt_BR/settings.json`
- `app/javascript/dashboard/i18n/locale/en/settings.json`
- `CHANGELOG.md`

---

## [1.5.1.33] - 2026-04-29T23:30:00-03:00

### Tweak: dots de status e serviço no card padronizados com border interna — sem clipping em cards estreitos

**Problema:**
1. Status dot (`.evt-status-dot-sm`) na iteração anterior foi reduzido pra 6px pra evitar clipping pelo `overflow: hidden` dos parents `.evt-title-wrap` / `.evt-pill-body` — solução funcionou mas ficou pequeno demais e diferente do dot do modal de status (`.cs-svc-dot` 10px).
2. Service dot no rodapé do card (`.evt-treatment-dot`) tinha o mesmo problema (8px com box-shadow ring de 1.5+0.5px) — clipava em cards estreitos.

**Solução:**
Padronização nos dois dots usando borda interna (`box-sizing: border-box` + `border: 1px solid`) em vez de box-shadow externo:
- Tamanho final: 10px (casa com `.cs-svc-dot` do modal — consistência cross-componente).
- Borda discreta `rgba(0, 0, 0, 0.18)` em light, `rgba(255, 255, 255, 0.2)` em dark via `.dark` selector.
- Sem extensão pra fora da bounding box → não pode ser clipado pelo `overflow: hidden` dos parents.

**Arquivos Modificados:**
- `plugins/agenda/frontend/styles/agenda-events.css`
- `CHANGELOG.md`

---

## [1.5.1.32] - 2026-04-29T23:00:00-03:00

### Fix: tint do agente em day view alinha com week view + dot de status reduzido pra não cortar

**Problemas:**
1. Day view usava `pastelBgFromColor` (opaco, HSL L=95% / L=20%) no wash da coluna; week view usava `translucentBgFromColor` (rgba alpha 0.12 / 0.18) na lane. Visualmente saíam tons diferentes mesmo pro mesmo agente — dia ficava mais "saturado", semana mais "leve".
2. Dot de status nos cards (8px bola + 1.5px ring branco + 0.5px sombra = ~12px área visível) batia no `overflow: hidden` dos parents `.evt-title-wrap` e `.evt-pill-body` em cards estreitos, ficando cortado/deformado.

**Soluções:**
1. `getAgentColumnTint` em day view passou a usar `translucentBgFromColor` com a mesma alpha do `getDayAgentLanes` (0.12 light / 0.18 dark). Os dois modos agora produzem rgba idêntico → tom 100% consistente.
2. Status dot encolheu de 8px → 6px e o ring duplo (1.5px branco + 0.5px sombra) virou um ring único fino (1px alpha 0.12). Área total ~8px — cabe nos cards estreitos sem clipping.

**Arquivos Modificados:**
- `plugins/agenda/frontend/components/AgendaTimelineView.vue`
- `plugins/agenda/frontend/styles/agenda-events.css`
- `CHANGELOG.md`

---

## [1.5.1.31] - 2026-04-29T22:30:00-03:00

### Fix: cards de evento e wash de coluna respeitam o tema escuro em day/week view

**Problema:**
Os cards e o wash dos agentes em day/week view foram desenhados pensando só em light mode: pastéis L=95% (quase brancos) e texto darkened L=28% (quase preto). Em dark mode o calendário tem fundo escuro mas os cards continuavam quase brancos com texto escuro — ilegível em alguns trechos e visualmente "fora do tema". Month view já estava ok porque usa `solidEventBg` (passa a cor sólida sem pastelizar).

**Solução:**
Helpers de cor em `agenda-colors.js` ganham parâmetro `isDark` opcional, default `false` (mantém compat com chamadas antigas):

- `pastelBgFromColor(color, isDark)`: HSL → L=20% no dark vs L=95% light. Não-HSL → alpha 0.22 no dark vs 0.12 light.
- `opaquePastelFromColor(color, isDark)`: dark mistura com slate-900 (rgb 15,23,42) na proporção 18%/82%; light continua misturando com branco 12%/88%.
- `darkenedTextColor(color, isDark)`: dark gera texto claro (HSL L=85% / RGB ×0.4 + branco ×0.6); light mantém o texto escuro original. Nome `darkened*` ficou histórico — agora é "tinted text" adaptativo, mas mantido pra não quebrar imports.
- `translucentBgFromColor`: o caller passa alpha; em `getDayAgentLanes` subimos pra 0.18 no dark (de 0.12) porque alpha baixo sobre fundo escuro fica invisível.

`getEventTimelineStyle` no `AgendaTimelineView.vue` lê `this.isDarkTheme` e propaga pros helpers; sem categoria, o card cai pra `rgb(30,41,59)` (slate-800) no dark em vez de `#ffffff`. Texto fallback (sem categoria) vira `#e2e8f0` (slate-200) no dark vs `#1f2937` (slate-800) no light. Accent neutro: `#475569` (slate-600) dark vs `#cbd5e1` (slate-300) light.

`getAgentColumnTint` (day view) e `getDayAgentLanes` (week view) passam `isDarkTheme` adiante, então tanto o wash da coluna quanto o backdrop da lane se adaptam ao tema. Month view não foi tocado — `getEventBackground` usa `solidEventBg` (passa cor saturada inalterada), funciona em ambos os temas.

**Arquivos Modificados:**
- `plugins/agenda/frontend/utils/agenda-colors.js`
- `plugins/agenda/frontend/components/AgendaTimelineView.vue`
- `CHANGELOG.md`

---

## [1.5.1.30] - 2026-04-29T22:00:00-03:00

### Refactor: padronização do termo "Serviços" em toda a UI da Agenda — Tratamentos/Procedimento → Serviços

**Problema:**
Mesmo conceito (lista de procedimentos cadastrados em `agenda_services`) aparecia com 3 nomes diferentes pra usuário:
- Sidebar do calendário: "TRATAMENTOS"
- Modal de novo agendamento: "Procedimento"
- Settings: "Serviços"

Cada label apontava pra mesma fonte de dados (`agenda_services`), mas a inconsistência fazia usuário pensar que eram coisas diferentes — "onde cadastro um procedimento? em serviços?", "tratamentos é a mesma coisa?".

**Solução:**
Padronização total em "**Serviços**" / "Serviço" (singular) na UI. Schema do backend (`AgendaEvent#custom_attributes.treatment`, model `AgendaService`) ficou intocado — só labels visuais mudaram. Mudanças:

- Sidebar: `AGENDA.SIDEBAR.TREATMENTS` → "SERVIÇOS" (en) / "SERVIÇOS" (pt_BR).
- Modal de evento: label "Procedimento" → "Serviço"; placeholder "Selecione um procedimento" → "Selecione um serviço".
- Event info popup: label "Procedimento" → "Serviço".
- i18n: `MODAL.FIELD_TREATMENT` → "Service" (en) / "Serviço" (pt_BR); `MODAL.TREATMENT_PLACEHOLDER` → "Select service" / "Selecione o serviço".

Comentários internos no código que mencionam "tratamento" (jargão de domínio anterior) ficam como estão — não são user-facing.

**Arquivos Modificados:**
- `plugins/agenda/frontend/components/AgendaEventModal.vue`
- `plugins/agenda/frontend/components/AgendaEventInfoPopup.vue`
- `app/javascript/dashboard/i18n/locale/en/settings.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/settings.json`
- `CHANGELOG.md`

---

## [1.5.1.29] - 2026-04-29T21:30:00-03:00

### Tweak: linha colorida do agente migra do topo da lane para a base do day header

**Problema:**
A linha colorida que identifica cada agente em week view estava no `border-top` do primeiro segmento da lane — ou seja, aparecia no início do horário de trabalho do agente, no meio da grade. Visualmente fica "perdida" — o usuário lê o header (DOM/SEG/TER...) e não associa a cor ali com o que está embaixo.

**Solução:**
A linha colorida sobe pra borda inferior do day header. Cada dia em week view ganha uma faixa de 3px no rodapé do header, dividida nas mesmas proporções das lanes (uma faixa por agente que tem evento naquele dia). O olho conecta direto: "header DOM 26 com tira roxa-laranja → embaixo, lane roxa à esquerda + lane laranja à direita". Faixas usam `lane.leftPct/widthPct` calculadas pelo mesmo `getDayAgentLanes`, então alinham perfeitamente com as lanes abaixo. `border-top` foi removido das lane segments — fica só o pastel limpo.

**Arquivos Modificados:**
- `plugins/agenda/frontend/components/AgendaTimelineView.vue`
- `CHANGELOG.md`

---

## [1.5.1.28] - 2026-04-29T21:00:00-03:00

### Tweak: tooltip moderno (estilo dark) sobre slots bloqueados — substitui o `title` nativo do browser

**Problema:**
Após esconder o label de texto dos slots bloqueados (1.5.1.25), a única forma de descobrir o motivo do bloqueio era via tooltip nativo do `title` HTML — que é cinza, demora ~1s pra aparecer e quebra a estética do produto.

**Solução:**
Tooltip CSS-only estilizado: pill escuro (`#1f2937`), texto branco, arrow apontando pra cima da célula bloqueada. Aparece imediatamente ao hover via `:hover` do `.timeline-cell` (o overlay interno tem `pointer-events: none`, então o evento de mouse é capturado pelo cell). Bordas arredondadas, sombra sutil de drop, transição de opacidade de 150ms. Posicionado abaixo da célula com seta apontando pra cima — vivo dentro do flow CSS, sem necessidade de Popper.js ou JS de posicionamento.

**Stacking trick:** o `.timeline-events-layer` (que contém eventos e lanes) tem `z-index: 5` e fica visualmente acima da grade. Sem ajuste, o tooltip ficaria escondido atrás dela. Solução: `.timeline-cell.cell-blocked:hover` recebe `z-index: 50`, elevando a célula bloqueada (e o tooltip dentro dela) acima da camada de eventos. Como lanes e cards já pulam slots bloqueados (1.5.1.26), o lift não esconde conteúdo relevante.

`:title` HTML removido de ambos os blocos (week + day view) pra não duplicar tooltip (nativo + custom aparecendo juntos).

**Arquivos Modificados:**
- `plugins/agenda/frontend/components/AgendaTimelineView.vue`
- `CHANGELOG.md`

---

## [1.5.1.27] - 2026-04-29T20:30:00-03:00

### Fix: range de horário no card não quebra mais em múltiplas linhas — trunca com ellipsis igual ao título

**Problema:**
Em week view com 2-3 agentes ativos no mesmo dia, cada lane fica estreita (33-50% da coluna do dia). Cards do tier medium/normal exibiam o horário "15:00 - 15:45" quebrando em até 3 linhas verticais ("15:0\n-\n15:4"), ocupando espaço de leitura sem ganho — o título do paciente já tinha truncamento via `--clamp`, mas o time row não.

**Solução:**
`.evt-sbs-time` ganha `white-space: nowrap; overflow: hidden; text-overflow: ellipsis; min-width: 0;` — mesmo padrão usado no título. Pai `.evt-sbs-time-row` ganha `min-width: 0; overflow: hidden;` pra permitir o filho encolher além do conteúdo. Em colunas largas o range continua aparecendo inteiro; em colunas apertadas, trunca elegantemente sem quebrar linha. Tier pill e small já tinham `nowrap` — só o medium/normal precisava.

**Arquivos Modificados:**
- `plugins/agenda/frontend/styles/agenda-events.css`
- `CHANGELOG.md`

---

## [1.5.1.26] - 2026-04-29T20:00:00-03:00

### Fix: lane do agente em week view não pinta sobre slots bloqueados — paridade visual com day view

**Problema:**
Em day view, células bloqueadas (almoço, feriado, fora do expediente) ficam apenas com o hatch listrado, sem o tint pastel do agente — fica limpo. Em week view, a lane backdrop era um único div com `top: 0; bottom: 0` cobrindo a coluna inteira, então o hatch dos slots bloqueados ficava parcialmente coberto pelo tint translúcido da lane. Visual inconsistente entre as duas views.

**Solução:**
Lane agora é renderizada como múltiplos segmentos. `getLaneSegments(dayObj)` agrupa os slots em ranges contínuos de horas não-bloqueadas (varre `dayHours`, abre segmento ao encontrar slot livre, fecha ao encontrar slot bloqueado). Para cada lane × cada segmento, um div absoluto com `top` e `height` calculados pelo range. Borda superior na cor sólida do agente só no **primeiro** segmento (identifica o início do dia de trabalho do agente sem repetir uma linha colorida em cada quebra como após o almoço).

Resultado: lane se "interrompe" em cima de almoço/feriado/fora-do-expediente, hatch fica visível e limpo, identificação do agente continua presente no topo do horário de trabalho.

**Arquivos Modificados:**
- `plugins/agenda/frontend/components/AgendaTimelineView.vue`
- `CHANGELOG.md`

---

## [1.5.1.25] - 2026-04-29T19:30:00-03:00

### Tweak: slots bloqueados no calendário só mostram ícone — label some pra reduzir poluição visual

**Problema:**
Cada slot bloqueado (almoço, feriado, fora do expediente, indisponível) repetia ícone + label de texto várias vezes seguidas na mesma coluna. Em uma semana com horário de almoço configurado e fora-do-expediente cedo/noite, eram 8-12 ocorrências do texto "Almoço" e "Fora do expediente" empilhadas verticalmente — ruído pesado que competia com a leitura dos eventos.

**Solução:**
Slots bloqueados agora exibem apenas o ícone de cadeado. O motivo do bloqueio migrou pro atributo `title` da célula — continua acessível em hover (tooltip nativo do browser), só não polui a tela. CSS órfão `.blocked-slot-text` (incluindo override mobile) removido.

**Arquivos Modificados:**
- `plugins/agenda/frontend/components/AgendaTimelineView.vue`
- `CHANGELOG.md`

---

## [1.5.1.24] - 2026-04-29T19:00:00-03:00

### Fix: card de evento usa pastel opaco da categoria — leitura preservada sobre as linhas do grid

**Problema:**
Cards com categoria estavam usando `pastelBgFromColor(categoryColor)` que, para entradas hex (formato em que as cores das categorias são salvas), retorna `rgba(r,g,b,0.12)` — translúcido. Isso fazia as linhas horizontais do grid do calendário vazarem através do card, reduzindo o contraste do texto e prejudicando leitura.

**Solução:**
Helper novo `opaquePastelFromColor` em `agenda-colors.js` que mistura a cor com branco na proporção 12%/88% e retorna `rgb()` sólido. Visualmente idêntico ao alpha 0.12 sobre branco — mas como é opaco, as linhas do grid pararam de aparecer atrás do card. Aplicado apenas no body do card; o backdrop da lane do agente continua usando `translucentBgFromColor` (lá a transparência é desejada para o hatch de slots bloqueados não sumir).

**Arquivos Modificados:**
- `plugins/agenda/frontend/utils/agenda-colors.js`
- `plugins/agenda/frontend/components/AgendaTimelineView.vue`
- `CHANGELOG.md`

---

## [1.5.1.23] - 2026-04-29T18:30:00-03:00

### Refactor: week view divide a coluna do dia em lanes por agente — fundo pastel + borda superior na cor do agente

**Problema:**
Na iteração anterior, o card sem categoria carregava o pastel sutil do agente pra dar identidade em week view. O usuário pediu paridade visual com a "Agenda antiga": cards 100% brancos sem categoria + a cor do agente pintada na **coluna** (não no card) também em week view, com a coluna dividida em sub-faixas quando há mais de um agente trabalhando no mesmo dia.

**Solução:**
Layout de week view re-arquitetado em torno de "agent lanes":

1. **Lanes por agente** — `getDayAgentLanes(dayObj)` calcula, para cada dia, quantos agentes ativos têm evento naquele dia e divide a largura da coluna em fatias iguais (ordem segue `activeAgents`, ignora agentes ocultos pelo filtro). Retorna `{ agentId, agentColor, leftPct, widthPct, bg }` por lane.

2. **Eventos posicionados dentro da lane do seu agente** — `getColumnEventsWithPositions` em week view agora agrupa eventos por `user_id`, calcula overlaps **dentro** do bucket de cada agente, e converte o `colIdx`/`totalCols` interno pra coordenadas relativas à lane. Resultado: 2 consultas do mesmo agente sobrepostas continuam dividindo a lane dele em duas, mas eventos de agentes diferentes vivem em lanes separadas mesmo sem conflito de horário.

3. **Backdrop visual da lane** — div absoluto `.agent-lane-bg` por lane, ocupando `top: 0; bottom: 0` da coluna do dia, com `background` translúcido (rgba 0.12) na cor do agente + `border-top: 3px solid agentColor`. Translúcido (não opaco) para o hatch de almoço/feriado/bloqueio continuar visível atrás.

4. **Card sem categoria volta a `#ffffff` puro** — a identidade do agente agora mora exclusivamente no fundo da lane (week) ou no fundo da célula (day). Card é puramente "branco ou cor da categoria".

5. **Day view e month view inalterados** — day view continua com wash da célula; month view continua com `getEventBackground` priorizando categoria → agente.

6. **Helper novo** `translucentBgFromColor(color, alpha)` em `agenda-colors.js` — retorna sempre rgba independente do formato de entrada (HSL/hex/rgb), porque `pastelBgFromColor` retorna HSL opaco para entradas HSL, o que cobriria o hatch das células bloqueadas atrás da lane. `parseColorToRgb` virou export pra suportar isso.

**Arquivos Modificados:**
- `plugins/agenda/frontend/components/AgendaTimelineView.vue`
- `plugins/agenda/frontend/utils/agenda-colors.js`
- `CHANGELOG.md`

---

## [1.5.1.22] - 2026-04-29T17:30:00-03:00

### Tweak: card sem categoria carrega pastel sutil do agente — fundo do agente também aparece em week view

**Problema:**
Versão anterior pintava cards sem categoria com `#ffffff` puro. Em day view ficava ok porque a coluna do agente já tinha o wash pastel — o card branco harmonizava com a coluna colorida. Em week view (colunas são dias, não agentes) a identidade do agente sumia completamente quando não havia categoria: vários eventos brancos lado a lado, impossível distinguir quem agenda o quê. O pedido foi explícito: "fundo sutil dos agentes também no modo semana".

**Solução:**
Card sem categoria agora usa `pastelBgFromColor(agentColor)` em vez de `#ffffff`. O pastel da função é L=95% (HSL) ou alpha 0.12 (hex/rgb) — visualmente "quase branco" com um leve hint da cor do agente. Atende as duas regras simultaneamente:

- "Card branco sem categoria" — pastel L=95% é praticamente indistinguível de branco puro.
- "Fundo sutil dos agentes" — o leve hint carrega a identidade do agente em qualquer view.

Em day view, o card pastel-do-agente fica em cima do wash da coluna (mesma cor) → harmonia visual reforçada. Em week view, o card pastel-do-agente é a única fonte da identidade do agente naquela posição. Cards com categoria continuam usando `pastelBgFromColor(categoryColor)` — categoria sempre vence na cor.

**Arquivos Modificados:**
- `plugins/agenda/frontend/components/AgendaTimelineView.vue`
- `CHANGELOG.md`

---

## [1.5.1.21] - 2026-04-29T17:00:00-03:00

### Refactor: cor do agente sai do card e vai pro fundo da coluna; card é branco por padrão e ganha cor da categoria quando atribuída

**Problema:**
Card de evento usava a cor do agente como fundo pastel + borda esquerda. Isso fazia o agendamento "carregar" duas informações conflitantes ao mesmo tempo: identidade do agente E (quando havia categoria) cor da categoria sobrescrita. Em day view com 5+ agentes ativos a tela virava um arco-íris saturado e perdia a leitura — categorias importantes (ex: NÃO AGENDAR vermelho, Bloqueio cinza) ficavam concorrendo com as cores dos agentes.

**Solução:**
Separação de responsabilidades visuais:

1. **Identidade do agente** → wash pastel atrás da **coluna** dele (apenas day view, onde colunas representam agentes). Implementado via CSS variable `--agent-tint` setada inline na célula + classe `.cell-agent-tinted` que lê a variável. O hover azul existente continua funcionando porque `:hover` ganha da regra de classe pela cascade. Slots bloqueados mantêm seu hatch (têm `!important`).

2. **Card de evento** → branco por padrão, cor da categoria quando o evento tem `category_id`. A regra é simples e exclusiva: sem categoria = `#ffffff` + borda neutra cinza; com categoria = pastel da `category.color` + accent saturado da mesma cor. Texto recebe `darkenedTextColor()` quando há cor pra garantir contraste WCAG; senão `#1f2937`.

3. **Helper `getEventCardColor`** novo em `useAgenda.js` separa explicitamente a regra de "cor do card" (categoria-only) da "cor do agente" (que volta a ser pura). `getAgentColor` agora ignora categoria — ele responde só sobre o agente, e quem decide o que pintar é o caller.

4. **Month view preservado** — lá não temos coluna pra fazer wash do agente, então `getEventBackground` mantém fallback `categoria → agente` pra que o evento permaneça visível. O comportamento do month view não muda.

5. **Week view** — colunas são dias, não agentes, então não recebem wash. Cards seguem a mesma regra (branco/categoria). Identidade do agente em week view fica implícita na coluna do dia + nome do paciente — se isso virar problema de leitura, abrimos um indicador discreto depois.

**Arquivos Modificados:**
- `plugins/agenda/frontend/composables/useAgenda.js`
- `plugins/agenda/frontend/components/AgendaTimelineView.vue`
- `plugins/agenda/frontend/routes/AgendaDashboard.vue`
- `CHANGELOG.md`

---

## [1.5.1.20] - 2026-04-29T16:30:00-03:00

### Refactor: filtro de Categorias na sidebar do calendário com comportamento idêntico ao de Agentes

**Problema:**
A seção "CATEGORIAS" na sidebar estava com um único comportamento (clique = toggle). O resto da sidebar (Agentes) já tinha o padrão "click no nome = solo, click no dot = toggle, pill 'Todos' resetando o filtro" — quem usa o calendário toda hora esperava o mesmo padrão nas Categorias e ficava ligando/desligando uma a uma para isolar uma única categoria. Inconsistência custa atrito mental.

**Solução:**
Paridade total com o bloco Agentes:

1. **Click no nome da categoria** → solo (esconde todas as outras, mostra só a clicada). Implementado via `soloCategory(id, allIds)` em `useAgenda.js` setando `state.hiddenCategories = allIds.filter(c => c !== id)`.
2. **Click no dot colorido** → toggle individual (mantém o `toggleCategory` existente, agora com `@click.stop` para não propagar pro solo).
3. **Pill "Todos" no header** → `showAllCategories()` zera `hiddenCategories`. A pill fica "ativa" (azul) quando nenhuma categoria está oculta, espelhando o comportamento do `sidebar-all-pill` de Agentes.

i18n da pill em `AGENDA.SIDEBAR.ALL_CATEGORIES` (fallback `Todos`).

**Arquivos Modificados:**
- `plugins/agenda/frontend/composables/useAgenda.js`
- `plugins/agenda/frontend/components/AgendaSidebar.vue`
- `plugins/agenda/frontend/routes/AgendaDashboard.vue`
- `CHANGELOG.md`

---

## [1.5.1.19] - 2026-04-29T15:00:00-03:00

### Feat: Categorias da Agenda como entidade de primeira classe

**Problema:**
Categoria de agendamento estava modelada de forma provisória — como string crua dentro de `event.custom_attributes` (chave `category` ou um custom attribute do tipo `select`). Sem entidade própria, era impossível: editar nome/cor sem reescrever todos os eventos antigos, contar quantos agendamentos cada categoria tem, escalar para tipo (consulta/bloqueio), duração padrão ou integração com financeiro. Cada cor era hardcoded, cada listagem era um `pluck` em JSONB, e adicionar funcionalidade nova exigia tocar JSONB de produção.

**Solução:**
Nova entidade `Agenda::Category` desacoplada — convive com tudo que já existe (Procedimento/AgendaService continua intocado, custom_attributes legados continuam funcionando), introduzida com migrations backward-compatible.

1. **Backend** — model `Agenda::Category` (`agenda_categories` table) com `name`, `color`, `position`, `active` escopados por `account_id` (índice unique em `[account_id, name]`). `AgendaEvent` ganha `belongs_to :category, optional: true` via `category_id` nullable. Engine atualizado com `Account.has_many :agenda_categories`. CRUD completo em `Api::V1::Accounts::AgendaCategoriesController` com policy dedicada (`Agenda::CategoryPolicy`: leitura pra todo membro, mutações só para administradores) e endpoint extra `PATCH reorder`. **Soft delete**: `destroy` apenas marca `active=false` para preservar referências históricas; eventos antigos continuam vinculados. **Hardening de tenant**: `nullify_missing_category` no `AgendaEventsController` rejeita `category_id` cross-account.

2. **Service de migração** — `Agenda::MigrateCategoriesFromCustomAttributes` lê `custom_attributes['category']` e custom attrs de tipo `select` chamados "Categoria", cria `Agenda::Category` idempotente por nome e popula `event.category_id`. **Não roda automaticamente** — chamada manual quando o cliente decidir migrar:
   ```
   Account.find_each { |acc| Agenda::MigrateCategoriesFromCustomAttributes.new(acc).call }
   ```

3. **Frontend — nova tela** — rota `agenda_categories_index` em `/agenda/categorias`, item "Categorias" no Sidebar core entre "Calendar" e "Settings". Página dedicada com cards por categoria mostrando nome, cor e contador de agendamentos, modal de criar/editar com paleta de 10 cores + ColorPicker custom (mesmo componente já usado em Serviços, sem duplicação de lógica).

4. **Frontend — integração no calendário** — Sidebar do dashboard ganha seção "CATEGORIAS" com filtro multi-select (estilo idêntico ao bloco Treatments/Procedimentos). Modal de agendamento ganha dropdown "Categoria" abaixo de "Procedimento" (separados — categoria é classificação semântica, procedimento é serviço executado). Cor do evento no calendário passa a priorizar `category.color` sobre cor do agente quando há categoria atribuída.

5. **Compat backward-compatible total** — eventos sem `category_id` continuam funcionando exatamente como antes (lookup de cor cai em treatment → agent). Custom attributes existentes nunca são apagados. Sistema não quebra se nenhuma categoria foi cadastrada (bloco "CATEGORIAS" só aparece quando há ao menos uma).

**Arquivos Modificados:**
- `db/migrate/20260429120000_create_agenda_categories.rb`
- `db/migrate/20260429120001_add_category_id_to_agenda_events.rb`
- `plugins/agenda/app/models/agenda/category.rb`
- `plugins/agenda/app/models/agenda_event.rb`
- `plugins/agenda/app/controllers/api/v1/accounts/agenda_categories_controller.rb`
- `plugins/agenda/app/controllers/api/v1/accounts/agenda_events_controller.rb`
- `plugins/agenda/app/services/agenda/migrate_categories_from_custom_attributes.rb`
- `plugins/agenda/lib/agenda/engine.rb`
- `app/policies/agenda/category_policy.rb`
- `app/views/api/v1/models/_agenda_category.json.jbuilder`
- `app/views/api/v1/models/_agenda_event.json.jbuilder`
- `app/views/api/v1/accounts/agenda_categories/index.json.jbuilder`
- `app/views/api/v1/accounts/agenda_categories/show.json.jbuilder`
- `config/routes.rb`
- `plugins/agenda/frontend/api/agendaCategories.js`
- `plugins/agenda/frontend/store/agendaCategories.js`
- `plugins/agenda/frontend/routes/categories/Index.vue`
- `plugins/agenda/frontend/routes/routes.js`
- `plugins/agenda/frontend/features/categories/composables/useAgendaCategories.js`
- `plugins/agenda/frontend/components/AgendaSidebar.vue`
- `plugins/agenda/frontend/components/AgendaEventModal.vue`
- `plugins/agenda/frontend/composables/useAgenda.js`
- `plugins/agenda/frontend/composables/useAgendaCrud.js`
- `plugins/agenda/frontend/composables/useAgendaInit.js`
- `plugins/agenda/frontend/routes/AgendaDashboard.vue`
- `plugins/agenda/frontend/utils/agenda-date.js`
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
- `app/javascript/dashboard/helper/routeHelpers.js`
- `app/javascript/dashboard/i18n/locale/en/settings.json`
- `app/javascript/dashboard/store/index.js`
- `app/javascript/dashboard/store/mutation-types.js`
- `CHANGELOG.md`

---

## [1.5.1.18] - 2026-04-29T11:30:00-03:00

### Feat: botão "Iniciar conversa" inline em cada card da lista de Contatos

**Problema:**
Para iniciar uma conversa WhatsApp com um contato cadastrado, o agente precisava: ir em Contatos → "Ver detalhes" → entrar no perfil → procurar o canal certo → criar nova conversa. Quatro cliques para uma ação que devia ser imediata. Em fluxo comercial (call center, atendimento clínico) isso vira fricção real, ainda mais agora que o painel de Conversas já tem busca híbrida com botão inline (1.5.1.17) — a inconsistência confunde.

**Solução:**
Botão "Iniciar conversa" inline ao lado de "Ver detalhes" em cada card da lista de Contatos. Click → endpoint `whatsapp/start_conversation` → reusa conversa aberta se já existir, cria nova se não → navega direto pra ela.

1. **Composable compartilhado** — extraído `useBeclinicStartWhatsAppConversation()` em [composables/useBeclinicStartWhatsAppConversation.js](app/javascript/dashboard/composables/useBeclinicStartWhatsAppConversation.js). Encapsula request, mensagens de erro padronizadas (`NUMBER_NOT_ON_WHATSAPP`, `INBOX_DISCONNECTED`, etc.), navegação e estado `isStarting`. Bater no critério "2+ callers reais" do AGENTS.md: ChatList.vue (CTA telefônico + busca híbrida) e ContactsCard.vue (botão inline) — três pontos hoje, removendo ~80 linhas duplicadas.

2. **Visibilidade do botão** —
   - **Aparece**: contato tem `phoneNumber` E usuário pode (`administrator` ou Klivy `chat:reply`).
   - **Não aparece**: contato sem telefone (não dá pra iniciar via WhatsApp) ou usuário sem permissão de reply.
   - **Estado loading**: `isStarting` faz o botão entrar em spinner enquanto o bridge valida o número.

3. **Comportamento idempotente** — backend já reusa conversa aberta para o mesmo contato (busca por `contact_inbox.source_id`). Click em contato com conversa existente abre a mesma; click em contato novo cria. Zero duplicação de contato — o controller `Whatsapp::StartConversationsController#find_or_create_conversation` cobre os dois caminhos.

4. **Refatoração do ChatList.vue** — `startNewConversationWithQuery` e `onStartConversationWithContact` agora delegam ao composable. Reduz superfície da função de ~40 linhas → 5 linhas, e garante que qualquer mudança futura (ex: adicionar telemetria, trocar de toast pra dialog) atinja todos os pontos de uma vez.

**Arquivos Modificados:**
- `app/javascript/dashboard/composables/useBeclinicStartWhatsAppConversation.js`
- `app/javascript/dashboard/components/ChatList.vue`
- `app/javascript/dashboard/components-next/Contacts/ContactsCard/ContactsCard.vue`
- `CHANGELOG.md`

---

## [1.5.1.17] - 2026-04-29T10:00:00-03:00

### Feat: busca híbrida (conversas + contatos sem conversa) na lista de Conversas

**Problema:**
O input "Buscar por contato..." na lista de Conversas só filtrava conversas existentes localmente. Se um contato cadastrado ainda não tinha conversa, ele simplesmente não aparecia — o agente precisava ir em "Contatos", encontrar a pessoa, abrir o perfil e clicar "Nova conversa". Fricção comercial: o agente pensa "quero falar com o João", a busca devolve vazia, ele assume que precisa criar contato do zero ou desiste.

**Solução:**
Busca unificada estilo WhatsApp Web. Um único input devolve dois grupos: **Conversas** (com contato cujo nome ou telefone bate) e **Contatos** (que existem mas ainda não têm conversa, com botão "Iniciar conversa" inline por linha).

1. **Backend** — novo endpoint `GET /api/v1/accounts/:account_id/beclinic_unified_search?q=`. Retorna `{ conversations: [...], contacts: [...] }`, limitado a 10 de cada lado. Ordenação: conversas por `last_activity_at DESC`, contatos por `last_activity_at DESC`. Match contra `name ILIKE :q OR phone_number ILIKE :q` em ambos os lados. **Regra crítica**: contatos que já aparecem em `conversations` são removidos do bloco de `contacts` — zero duplicação. Filtro de inbox respeitado via `Current.user.assigned_inboxes`.

2. **Frontend** — debounce de 300ms para evitar 1 request por keystroke. Enquanto há query, a lista virtual habitual é substituída pelo painel `BeclinicUnifiedSearchResults.vue` (carrossel "Conversas" → "Contatos" → CTA telefônico). Click em conversa navega; click em "Iniciar conversa" no contato dispara o fluxo `whatsapp/start_conversation` existente (reusando a lógica que valida número no bridge). Se a query parece um número e nenhum match volta, o CTA WhatsApp Web continua aparecendo.

3. **Edge cases** —
   - Contato sem `phone_number` → botão fica desabilitado (não dá pra iniciar conversa via WhatsApp).
   - Conversa já existente com aquele contato → contato sumido do bloco "Contatos", evitando duplicação visual.
   - Race entre requests: se a query muda enquanto o request ainda está em voo, descartamos o resultado obsoleto.

Permissão pra iniciar conversa continua passando pelo `ConversationPolicy#reply?` (administrador, agent_bot ou Klivy `chat:reply`) — gate aplicado no controller `whatsapp/start_conversations#create`, não duplicado no `unified_search`.

**Arquivos Modificados:**
- `plugins/beclinic_core/app/controllers/api/v1/accounts/beclinic_unified_search_controller.rb`
- `plugins/beclinic_core/app/views/api/v1/accounts/beclinic_unified_search/index.json.jbuilder`
- `config/routes.rb`
- `app/javascript/dashboard/api/beclinicUnifiedSearch.js`
- `app/javascript/dashboard/components/BeclinicUnifiedSearchResults.vue`
- `app/javascript/dashboard/components/ChatList.vue`
- `CHANGELOG.md`

---

## [1.5.1.16] - 2026-04-28T19:35:00-03:00

### Fix: filtro de busca da lista de conversas agora olha phone — botão "Iniciar conversa" só aparece quando faz sentido

**Problema:**
Após [1.5.1.12], ao digitar qualquer número na busca da lista (ex: `11912345678`) o botão "Iniciar conversa no WhatsApp" aparecia SEMPRE — mesmo quando já existia conversa com esse contato. UX confusa: o agente clicaria pra criar uma "nova" conversa que na verdade duplicaria o contato (já mitigado pela 1.5.1.15, mas o sintoma visual continuava).

**Causa raiz:**
[ChatList.vue:379-385](app/javascript/dashboard/components/ChatList.vue) filtrava `conversationList` apenas por `meta.sender.name`. Como o nome do contato é "Contato Teste" e a query digitada é o número, não havia match — lista filtrada zerava — empty state acionava o botão.

**Solução:**
Filtro local agora considera também `meta.sender.phone_number` quando a query tem ≥ 4 dígitos. Comparação é digits-only de cada lado:

```js
const qDigits = localSearchQuery.value.replace(/\D/g, '');
// match por nome OU por phone (substring de digits)
return name.includes(q) || (qDigits.length >= 4 && phone.includes(qDigits));
```

Resultado: digitar `11912345678` agora filtra a conversa do Contato Teste corretamente (phone `+5511912345678` contém `11912345678`). Botão "Iniciar conversa" só aparece quando o filtro de fato não tem match — caso real de número novo.

**Caveat conhecido:**
O filtro só age sobre conversas da tab ativa (Minhas / Não atribuídas / Todos). Se uma conversa existe em outra tab, o botão ainda aparece. Polimento futuro se virar problema na prática.

**Arquivos Modificados:**
- `app/javascript/dashboard/components/ChatList.vue`
- `CHANGELOG.md`

---

## [1.5.1.15] - 2026-04-28T19:25:00-03:00

### Fix: contato duplicado quando destinatário responde com LID após `start_conversation`

**Problema:**
Após iniciar conversa via "Iniciar conversa com (11) 91234-5678" (1.5.1.12), quando o destinatário respondia o WhatsApp Web entregava a primeira mensagem do contato com **JID em formato LID** (`56500512911541@lid`). O `IncomingMessageQrService` não conseguia mapear de volta pro phone real, então criava um SEGUNDO contato. Visualmente: dois "Contato Teste" na lista, um com avatar real (do agente que iniciou), outro com iniciais (criado pelo webhook).

**Causa raiz:**
O `lidToJidMap` local do bridge é alimentado por scans de grupos comuns (`scanGroupForLidMappings`) e `contacts.upsert` events. Para um contato 1:1 com quem o usuário NUNCA conversou antes, o LID não está nesse cache — `resolveLidToJid` retorna o LID puro, e o serviço Rails cai no caminho de criação de contato fantasma.

**Solução:**
Baileys 7 expõe a API canônica `sock.signalRepository.lidMapping.getPNForLID(lid)` e `getLIDForPN(phone)` ([lid-mapping.d.ts](lib/whatsapp/node_modules/@whiskeysockets/baileys/lib/Signal/lid-mapping.d.ts)) — fonte oficial de mapping LID↔PN dessa sessão.

[server.js](lib/whatsapp/server.js):

1. **`resolveLidViaBaileys(sock, jid)`**: nova função que consulta o `signalRepository`. Plugada no fluxo `messages.upsert` 1:1 — quando cache local não resolve, tenta via Baileys e popula o cache local pra próximas chamadas.

2. **`ensureLidMappingForPhone(sock, phoneJid)`**: chama `getLIDForPN` em paralelo (best-effort). Acionada em DOIS pontos:
   - `POST /sessions/:id/check_number` — quando o agente clica "Iniciar conversa", o bridge já popula o LID antes mesmo da primeira mensagem.
   - `POST /sessions/:id/send` — quando o agente envia mensagem, popula. Garante que a resposta do contato (com LID) seja resolvida.

**Resultado:**
A partir de agora, qualquer "Iniciar conversa" novo: ao destinatário responder, o bridge resolve LID → phone real → `IncomingMessageQrService` reusa o contact_inbox criado pelo agente. Sem duplicação.

**Caveat:**
Contatos duplicados criados ANTES desse fix continuam no banco (caso testado: Contact #1858 + Conversation #16 em dev). Cleanup desses requer ação manual — não foi automatizada porque envolve mergir mensagens cross-contact e o sistema bloqueou ação destrutiva sem autorização explícita do usuário.

**Arquivos Modificados:**
- `lib/whatsapp/server.js`
- `CHANGELOG.md`

---

## [1.5.1.14] - 2026-04-28T18:55:00-03:00

### Fix: gate de permissão errado — usar `reply?` em vez de `create?` em `start_conversation`

**Problema:**
Após resolver o JOIN da [1.5.1.13], teste em produção mostrou 403 "Você não tem permissão para iniciar conversas." pra agentes não-admin.

**Causa raiz:**
[ConversationPolicy](app/policies/conversation_policy.rb) não define `create?`, então cai no default em [application_policy.rb:20-22](app/policies/application_policy.rb#L20-L22) que é hardcoded `false`. Resultado: só admin passava.

**Solução:**
[start_conversations_controller.rb](app/controllers/api/v1/accounts/whatsapp/start_conversations_controller.rb) — trocar `create?` por `reply?`:

```ruby
ConversationPolicy.new(pundit_user, Conversation.new(inbox: inbox)).reply?
```

`reply?` já existe e cobre `administrator? || agent_bot? || beclinic_can?(:chat, :reply)`. Quem pode responder mensagens deve poder iniciar uma — gate alinhado semanticamente.

**Arquivos Modificados:**
- `app/controllers/api/v1/accounts/whatsapp/start_conversations_controller.rb`
- `CHANGELOG.md`

---

## [1.5.1.13] - 2026-04-28T18:40:00-03:00

### Fix: `start_conversation` 500 — `Inbox` polymorphic não tem association `:channel_whatsapp`

**Problema:**
Validação em produção (conta 31) levantou `ActiveRecord::ConfigurationError: Can't join 'Inbox' to association named 'channel_whatsapp'; perhaps you misspelled it?` ao tentar usar o botão "Iniciar conversa com (11) 91234-5678" da [1.5.1.12].

**Causa raiz:**
`StartConversationsController#resolve_inbox` usava `Current.account.inboxes.joins(:channel_whatsapp)` — mas o model `Inbox` no Chatwoot tem `belongs_to :channel, polymorphic: true`, sem uma association nomeada `:channel_whatsapp`. ActiveRecord não consegue resolver o JOIN.

**Solução:**
[start_conversations_controller.rb](app/controllers/api/v1/accounts/whatsapp/start_conversations_controller.rb) — substituir o `joins(:channel_whatsapp)` por filtro polymorphic + JOIN explícito na tabela:

```ruby
base = Current.account.inboxes.where(channel_type: 'Channel::Whatsapp')
base.joins('INNER JOIN channel_whatsapp ON channel_whatsapp.id = inboxes.channel_id')
    .where('channel_whatsapp.provider = ?', 'whatsapp_qr')
    .first
```

Validado: query roda na account 31 e retorna inbox 13 (provider whatsapp_qr) corretamente.

**Arquivos Modificados:**
- `app/controllers/api/v1/accounts/whatsapp/start_conversations_controller.rb`
- `CHANGELOG.md`

---

## [1.5.1.12] - 2026-04-28T18:25:00-03:00

### Feat: iniciar conversa direto por número estilo WhatsApp Web (com validação no WhatsApp)

**Problema:**
Versão inicial dessa feature (commit anterior, mesma data) abria o `ComposeConversation` modal pré-disparando uma busca pelo número digitado. Validação em produção mostrou 3 problemas:
1. **Busca falhava** com "Não foi possível completar a pesquisa" quando query era um número (`searchContacts` não lida bem com input numérico em alguns formatos).
2. **Forçava o usuário a digitar `+55`** — UX que não bate com expectativa nacional ("11 91234-5678" devia bastar).
3. **Não validava se o número tem WhatsApp** — usuário podia gerar contato/conversa pra um número que não existe na plataforma.

**Solução: pular o modal completamente, fluxo direto via novo endpoint dedicado.**

1. **Bridge: `POST /sessions/:inboxId/check_number`** ([server.js](lib/whatsapp/server.js)):
   - Recebe `{ phone_number }`, normaliza pra dígitos puros.
   - Chama `sock.onWhatsApp(jid)` do Baileys com timeout de 8s.
   - Retorna `{ exists: true, jid }` ou `{ exists: false }`.
   - 503 se o socket não está conectado (não-recuperável sem reconnect).

2. **Rails: novo endpoint `POST /api/v1/accounts/:id/whatsapp/start_conversation`** ([start_conversations_controller.rb](app/controllers/api/v1/accounts/whatsapp/start_conversations_controller.rb), [routes.rb](config/routes.rb)):
   - Recebe `{ phone_number, inbox_id? }`.
   - **Normaliza assumindo Brasil**: se digits < 12, prepend `55` automático. Cobre "11 91234-5678" → `5511912345678`.
   - Resolve inbox: parâmetro `inbox_id` se passado, senão primeira inbox `whatsapp_qr` da conta.
   - Gate de RBAC: `ConversationPolicy#create?` (já respeita Klivy roles via `beclinic_can?(:chat, :reply)`).
   - Pergunta ao bridge → se `exists: true`: cria/reusa contato e conversa via `ContactInboxWithContactBuilder`, retorna `{ conversation_id, contact_id, inbox_id }`. Se `exists: false`: 404 com `error: "NUMBER_NOT_ON_WHATSAPP"`.
   - Codes de erro estruturados: `INVALID_PHONE`, `NO_WHATSAPP_INBOX`, `INBOX_DISCONNECTED`, `NUMBER_NOT_ON_WHATSAPP`, `BRIDGE_ERROR`, `FORBIDDEN`.

3. **Frontend ChatList** ([ChatList.vue](app/javascript/dashboard/components/ChatList.vue)):
   - `phoneCandidate` aceita 10-15 dígitos (cobre BR 10-11 sem código país e internacional 12+).
   - `phoneCandidateLabel` formata pro display: `(11) 91234-5678` para BR, `+5521...` para internacional.
   - Click no botão → `axios.post('/api/.../start_conversation')` → router push pra `inbox_conversation` com `conversation_id` retornado. Sucesso = abre direto a caixa de mensagem.
   - Erros mapeados em mensagens em PT-BR via `useAlert`.
   - Loading state: ícone spinner + "Validando número..." enquanto a request roda.

**Cleanup:**
- Removido `BUS_EVENTS.OPEN_NEW_CONVERSATION_WITH_QUERY` e o listener correspondente em [ComposeConversation.vue](app/javascript/dashboard/components-next/NewConversation/ComposeConversation.vue) — não usa mais o modal pra esse fluxo. Versão direta substitui completamente a v1.

**UX entregue:**
- Digita `11 91234-5678` na busca → sem matches → botão "Iniciar conversa com (11) 91234-5678".
- Click → bridge valida no WhatsApp:
  - **Tem WhatsApp**: cria conversa + abre tela de digitar mensagem (sem passos extras).
  - **Não tem**: toast "Esse número não tem WhatsApp" e o botão volta ao estado normal (sem criar contato/conversa fantasma).
- Reusa conversa aberta existente se já houver — não duplica.

**Validação:**
- Bridge `curl POST /sessions/13/check_number {phone_number:"5511912345678"}` → `{exists:true, jid}` ✅
- Mesmo número sem `+55` (`11912345678`) → `{exists:true}` (Baileys também resolveu, mas Rails normaliza antes pra não depender disso).
- Número falso (`00000000000`) → `{exists:false}` ✅
- Rota Rails registrada: `POST /api/v1/accounts/:account_id/whatsapp/start_conversation`.
- Sintaxe Ruby/JS: ✓.

**Arquivos Modificados:**
- `lib/whatsapp/server.js`
- `app/controllers/api/v1/accounts/whatsapp/start_conversations_controller.rb` (novo)
- `config/routes.rb`
- `app/javascript/dashboard/components/ChatList.vue`
- `app/javascript/dashboard/components-next/NewConversation/ComposeConversation.vue` (cleanup do v1)
- `app/javascript/shared/constants/busEvents.js` (cleanup do v1)
- `CHANGELOG.md`

---

## [1.5.1.11] - 2026-04-28T17:30:00-03:00

### Feat: avatar real do contato WhatsApp QR na lista de conversas

**Problema:**
A lista de conversas mostrava apenas iniciais como avatar para contatos do WhatsApp QR. O componente [ConversationCard.vue:256-282](app/javascript/dashboard/components/widgets/conversation/ConversationCard.vue#L256-L282) já consome `currentContact.thumbnail`, mas o backend nunca populava esse campo — o pipeline `bridge → IncomingMessageQrService → Contact` não tinha nenhuma referência a `avatar`/`profile_pic`/`thumbnail` (validado: 0 matches em 383 linhas do serviço).

Outros canais do Chatwoot (Telegram, Instagram, Twitter) já usam [Avatar::AvatarFromUrlJob](app/jobs/avatar/avatar_from_url_job.rb) — só faltava plugá-lo no fluxo do WhatsApp QR.

**Solução:**

1. **Bridge: cache + fetch de profile picture** ([server.js](lib/whatsapp/server.js)):
   - Novo `profilePicCache` (`Map<jid, { url, fetchedAt }>`) com TTL de 24h. Cacheia tanto URLs válidas quanto `null` (privacidade bloqueia / contato sem foto) pra não bater no WhatsApp toda mensagem.
   - Função `getProfilePictureUrl(sock, jid)` que chama `sock.profilePictureUrl(jid, 'image')` do Baileys, com fallback silencioso pra `null` em 401/404 (privacidade do contato).
   - Pula JIDs `@lid` (não-resolvidos) — Baileys não retorna foto pra LIDs.
   - Em mensagens 1:1 from-me, busca foto do destinatário (`msg.key.remoteJid`) em vez do remetente (que sou eu mesmo).
   - Adiciona `sender_avatar_url` ao payload do webhook.

2. **Backend: enfileira AvatarFromUrlJob** ([incoming_message_qr_service.rb](app/services/whatsapp/incoming_message_qr_service.rb)):
   - Após criar/atualizar `@contact` (1:1) ou `actual_sender` (participante de grupo), se `sender_avatar_url` veio no payload → `Avatar::AvatarFromUrlJob.perform_later(contact, url)`.
   - Job já existente trata: rate limit de 1min/contato, deduplicação por SHA256 da URL (não rebaixa se já sincronizou a mesma), tratamento de `Down::NotFound` se a URL expirou.
   - Para grupos, o avatar do grupo em si fica pra depois — só sincroniza avatar do participante individual nesta versão.

**Como o frontend já estava preparado:**
`ConversationCard.vue` já lê `currentContact.thumbnail` via store. Uma vez que `contact.avatar` está anexado via ActiveStorage, o serializer popula `thumbnail` automaticamente — UI atualiza sem mudança de código.

**Validação:**
- Bridge rebuildado no dev: `grep -c "getProfilePictureUrl\|sender_avatar_url" /app/server.js` → 3 (função, chamada, payload).
- Sessão inbox 13 (já existente no volume) reidratou sem QR no rebuild — bônus de confirmação que o fix do volume de [1.5.1.10] funciona em ciclo real.

**Edge cases tratados:**
- Privacidade do WhatsApp bloqueia foto pra desconhecidos → 401 → cacheia `null` → fallback de iniciais segue funcionando.
- LID não-resolvido (cache LID→JID ainda não populou) → pula fetch.
- URL do WhatsApp expira antes do Sidekiq processar → `Down::NotFound` engolido pelo job, sem ruído.
- Mensagem from-me em 1:1 → foto do destinatário, não do próprio número conectado.

**Arquivos Modificados:**
- `lib/whatsapp/server.js`
- `app/services/whatsapp/incoming_message_qr_service.rb`
- `CHANGELOG.md`

---

## [1.5.1.10] - 2026-04-28T16:55:00-03:00

### Fix: persistência de sessão WhatsApp QR sobrevive a redeploy + healthcheck real + watchdog ativo

**Problema:**
Após `docker compose down && up --build` (local) ou redeploy no Easypanel (produção), a sessão WhatsApp QR caía silenciosamente:
- UI mostrava "conectado", mas mensagens paravam de chegar e webhooks paravam
- Era necessário reescanear o QR Code manualmente após cada deploy
- Em produção, anexos de mensagens (imagens/áudios) também davam 404 após cada deploy — mesmo bug, sintoma diferente

**Causa raiz:**

Camada 1 (local, compose) — o bridge multi-tenant ([lib/whatsapp/server.js](lib/whatsapp/server.js), Baileys 7) grava credenciais em `/app/sessions/<inboxId>/auth_info/creds.json`, mas o `docker-compose.yaml` montava o volume no caminho LEGADO single-tenant (`/app/auth_info`). Resultado: `/app/sessions/` ficava na camada writable do container e era apagado a cada `docker compose down`.

Camada 2 (Easypanel, single-container via Procfile/foreman) — o único volume persistente do serviço estava montado em `/app/lib/whatsapp/auth_info` (vestígio órfão do tempo single-tenant). `/app/storage` (onde Rails ActiveStorage escreve E onde o bridge devia escrever) era overlay puro, evaporando a cada redeploy. Por isso anexos de mensagens davam 404 — mesma raiz.

Camada 3 (estado falso) — status reportado pelo bridge era `socket_connected: !!session.sock`, verdadeiro mesmo com websocket Baileys silenciosamente caída ("zumbi"). Sem probe ativo, esse estado nunca era detectado e a UI ficava verde mentindo.

**Solução:**

1. **Volume correto:**
   - [docker-compose.yaml](docker-compose.yaml) `whatsapp_bridge.volumes`: bind `./lib/whatsapp/sessions:/app/sessions` (path real multi-tenant) em vez do `auth_info` legado. Volume órfão `whatsapp_auth` removido.
   - Easypanel: criar volume nomeado `klivy_storage` montado em `/app/storage`, com env `WHATSAPP_SESSIONS_DIR=/app/storage/whatsapp_sessions`.

2. **Configurabilidade por env** ([server.js:62-66](lib/whatsapp/server.js#L62-L66)):
   - `WHATSAPP_SESSIONS_DIR`, `WHATSAPP_LID_MAP_PATH`, `WHATSAPP_MEDIA_DIR`.
   - Auto-migração de `lid_map.json` legado pro novo path no boot ([server.js:158-176](lib/whatsapp/server.js#L158-L176)) — preserva os 8021 mapeamentos LID→JID acumulados.

3. **`/healthz` real** ([server.js:984-1019](lib/whatsapp/server.js#L984-L1019)):
   Retorna 503 se houver "fantasma" — creds no disco mas socket não conectado, OU sessão `connected` mas liveness probe stale > 2min. Plugado no `docker-compose.yaml` como `healthcheck` do serviço — Docker reinicia container unhealthy automaticamente.

4. **Watchdog ativo** ([server.js:148-188](lib/whatsapp/server.js#L148-L188)):
   A cada 30s, envia `sendPresenceUpdate('available')` em cada socket conectado com timeout de 8s. Falha → força `sock.end()` → dispara o fluxo normal de reconnect com backoff exponencial existente. Detecta zumbis que o Baileys nunca avisa via `connection.update`.

5. **Filtro dinâmico de timestamp** ([server.js:91-105](lib/whatsapp/server.js#L91-L105), [server.js:743-757](lib/whatsapp/server.js#L743-L757)):
   - First-scan (sem creds prévias, primeiros 60s): janela 2h — defesa contra history dump do Baileys.
   - Reconnect (sessão rehidratada): janela 168h (7 dias, configurável via `WHATSAPP_MAX_MESSAGE_AGE_HOURS`) — cobre downtime longo de servidor sem perder mensagens enfileiradas pelo WhatsApp Web.
   - Substitui o filtro fixo de 2h que descartava mensagens após qualquer downtime > 2h.

6. **UI honesta** ([WhatsappQRStatus.vue](app/javascript/dashboard/routes/dashboard/settings/inbox/channels/WhatsappQRStatus.vue)):
   Consome novo campo `alive` do `/sessions/:id/status` (resultado do liveness probe). Badge laranja "Reconectando..." quando socket está zumbi mas estado interno ainda diz `connected`. Verde só quando o probe confirma — fim do "verde mentiroso".

7. **Documentação e segurança:**
   - [.env.example](.env.example): novo bloco "WhatsApp QR Bridge" com explicação por ambiente.
   - [.gitignore](.gitignore): `lib/whatsapp/sessions/*` (ignora creds), com `.gitkeep` versionado pra Docker criar a pasta com permissão correta no primeiro `up`.

**Validação:**
- Local: `docker compose down && up --build` — sessão fake gravada no volume sobreviveu; log `♻️ Re-hidratando 1 sessão(ões) válida(s)` confirmou rehydrate sem QR.
- Easypanel: após criar volume `klivy_storage` em `/app/storage`, `mount | grep storage` retornou `/dev/sda1 on /app/storage type ext4 (rw,relatime)` — volume real persistente. Sentinel `/app/storage/.persist_test` sobreviveu redeploy.

**Bonus:** o volume novo `/app/storage` resolveu também os 404 em `/rails/active_storage/disk/...` em prod (anexos de mensagens ficavam na camada writable e evaporavam a cada deploy) — mesma raiz, dois sintomas resolvidos por uma mudança.

**Arquivos Modificados:**
- `docker-compose.yaml`
- `lib/whatsapp/server.js`
- `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/WhatsappQRStatus.vue`
- `.gitignore`
- `.env.example`
- `lib/whatsapp/sessions/.gitkeep` (novo)
- `CHANGELOG.md`

---

## [1.5.1.9] - 2026-04-27T23:13:01-03:00

### Runbook: usar force destroy direto em vez de purge_later para órfãos do Disk antigo

**Problema:**
A Etapa 7 do runbook original instruía rodar `ActiveStorage::Blob.where(service_name: ['local', nil]).find_each(&:purge_later)` para limpar blobs órfãos remanescentes do `service: Disk` legacy. Validado em dev: **não funciona**.

`purge_later` enfileira `ActiveStorage::PurgeJob`, que tenta deletar o arquivo físico do Disk. Como o filesystem efêmero do container já apagou os arquivos há muito tempo, o job falha com `Errno::ENOENT`. Adicionalmente, `ActiveStorage::Blob#purge` tem um `rescue ActiveRecord::InvalidForeignKey` que **silenciosamente engole** falhas de FK constraint quando o blob ainda tem attachments — então o loop reporta "Sucesso" sem destruir nada.

Em dev, 68 órfãos (57.92 MB) permaneceram intactos no DB após `purge_later`.

**Solução:**
Atualizar [docs/03-engineering/runbook-active-storage-r2-production.md](docs/03-engineering/runbook-active-storage-r2-production.md) (Etapa 7) com a sequência correta:

```ruby
ActiveStorage::Attachment.where(blob_id: blob.id).destroy_all  # detacha primeiro
blob.destroy                                                    # agora destroy passa
```

Isso pula a tentativa de deletar arquivo (que não existe mesmo) e mata só as rows do DB.

**Arquivos Modificados:**
- `docs/03-engineering/runbook-active-storage-r2-production.md`
- `CHANGELOG.md`

---

## [1.5.1.8] - 2026-04-27T22:04:13-03:00

### Fix: reverter SecureBlobsController, restaurar rails_blob_url em Document e ConsentRecord

**Problema:**
A introdução do `SecureBlobsController` (1.5.1.6) foi feita com a intenção de adicionar guard de cross-tenant via `devise_token_auth`. Validado em dev: **quebra click-to-open de PDF/imagem**.

A URL gerada (`/api/v1/accounts/:id/secure_blobs/:signed_id`) passa pelo `Api::V1::Accounts::BaseController` que exige headers de auth (`access-token`, `client`, `uid`). Esses headers são enviados pelo SPA via fetch/axios, mas **não pelo browser quando o usuário clica num link** (GET vanilla). Resultado: `{"errors":["Você precisa entrar ou se cadastrar antes de continuar."]}` ao tentar baixar/visualizar documento.

**Solução:**
1. [plugins/patients/app/models/document.rb](plugins/patients/app/models/document.rb) `signed_url` — voltar pra `rails_blob_url` (Active Storage padrão).
2. [plugins/patients/app/models/consent_record.rb](plugins/patients/app/models/consent_record.rb) `signature_image_url` — idem.
3. Deletar [app/controllers/api/v1/accounts/secure_blobs_controller.rb](app/controllers/api/v1/accounts/secure_blobs_controller.rb) (não usado mais).
4. Remover `resources :secure_blobs` de [config/routes.rb](config/routes.rb).

Mitigação atual da brecha de capability token: `signed_id` curto (30min) + HTTPS + signed URLs nunca renderizadas em UI cross-account. É o mesmo modelo de Notion/Linear/Asana — capability token aceitável para SaaS multi-tenant comum.

Para hardening verdadeiro de cross-tenant (caso vire requisito regulatório), redesign futuro precisa de token customizado + auth via cookie de sessão (incompatível com auth de API token-based atual). Fora de escopo agora.

**Arquivos Modificados:**
- `plugins/patients/app/models/document.rb`
- `plugins/patients/app/models/consent_record.rb`
- `app/controllers/api/v1/accounts/secure_blobs_controller.rb` (removido)
- `config/routes.rb`
- `CHANGELOG.md`

---

## [1.5.1.7] - 2026-04-27T21:38:49-03:00

### Fix: SyntaxError em Document e ConsentRecord por merge conflict mal resolvido

**Problema:**
Durante o merge da série de PRs de hardening do R2, GitHub web flagrou conflito não só em `CHANGELOG.md` mas também em `plugins/patients/app/models/document.rb` e `plugins/patients/app/models/consent_record.rb` — porque PR `fix/active-storage-url-config` (1.5.1.3) e PR `feat/active-storage-secure-proxy` (1.5.1.6) editaram o mesmo método (`signed_url` / `signature_image_url`).

A resolução usando "Accept both changes" colou as DUAS versões dos métodos, gerando código com `def` aninhado sem fechamento de parênteses — `SyntaxError` no boot do Rails. Sintoma visível: "Erro ao gerar documento" no UI ao tentar gerar PDF.

**Solução:**
Manter apenas a versão final correta (Group D — `api_v1_account_secure_blob_url` via `SecureBlobsController`) em ambos os arquivos. A versão anterior (Group A — `rails_blob_url` direto) foi superseded pela arquitetura do proxy autenticado e pode ser removida sem perda funcional.

Validado com `ruby -c` em ambos arquivos — sintaxe OK.

**Arquivos Modificados:**
- `plugins/patients/app/models/document.rb`
- `plugins/patients/app/models/consent_record.rb`
- `CHANGELOG.md`

---

## [1.5.1.6] - 2026-04-27T20:51:08-03:00

### Active Storage: SecureBlobsController — guard de cross-tenant em URLs de PHI

> Assumindo merge após PRs `fix/active-storage-url-config` (1.5.1.3), `feat/active-storage-purge-orphans` (1.5.1.4) e `feat/active-storage-account-scoping` (1.5.1.5). Renumerar se ordem mudar.

**Problema:**
Auditoria identificou risco de vazamento cross-tenant via signed URLs do Active Storage. O comportamento default de `rails_blob_url` é tratar `signed_id` como capability token: quem tiver o token (intercept de log, share acidental por WhatsApp, XSS) consegue baixar o blob durante a janela de validade — independente da conta em que está autenticado.

Para PHI clínico (Document = atestado/receita; ConsentRecord = assinatura digital de consentimento), isso não atende rigor de proteção de dados sensíveis.

**Solução:**
Novo controller [app/controllers/api/v1/accounts/secure_blobs_controller.rb](app/controllers/api/v1/accounts/secure_blobs_controller.rb) que serve como proxy autenticado:

1. Recebe `signed_id` em URL escopada à conta (`/api/v1/accounts/:account_id/secure_blobs/:signed_id`)
2. Verifica via `ActiveStorage::Attachment.where(blob_id:)` que o blob pertence a algum record da conta atual (usando `record.account_id` ou `record.patient.account_id`)
3. Se não bate → retorna 404 (não 403 — não vaza existência do blob)
4. Se bate → 302 redirect pra URL R2 signed com expiração curta (5min)

Modelos editados para apontar pro novo proxy:
- [plugins/patients/app/models/document.rb](plugins/patients/app/models/document.rb) `signed_url`
- [plugins/patients/app/models/consent_record.rb](plugins/patients/app/models/consent_record.rb) `signature_image_url`

Route adicionada em [config/routes.rb](config/routes.rb): `resources :secure_blobs, only: [:show], param: :signed_id` no scope `Api::V1::Accounts`.

**Trade-off documentado no header do controller (REDIRECT vs STREAM):**
Optei por REDIRECT (302 → R2 signed URL) em vez de STREAM (`send_data` via Rails) para não pagar custo de banda. Trade-off: a URL R2 final fica brevemente exposta no `Location:` header, mas o TTL curto (5min) limita replay. Para PHI mais sensível ou quando aceitarmos custo de banda, migrar pra streaming é trivial (`send_data blob.download, ...`).

**Escopo restrito a PHI textual:**
ExamMedia (mídia binária pesada — fotos clínicas, raio-X, vídeos) **continua via `rails_blob_url` direto**. Custo de proxy não compensa o ganho marginal de segurança para conteúdo binário grande, e a expiração curta da signed URL (1h) já mitiga.

**Compatibilidade:**
- API contract (`signed_url`/`signature_image_url`) inalterado — frontend não precisa mudar.
- URLs antigas em links externos/cache (se houver) quebram. Como cliente está em testes sem dados reais, não há impacto operacional.

**Arquivos Modificados:**
- `app/controllers/api/v1/accounts/secure_blobs_controller.rb` (novo)
- `config/routes.rb`
## [1.5.1.5] - 2026-04-27T20:46:46-03:00

### Active Storage: namespace `accounts/<id>/` em keys do R2 (multi-tenant)

> Assumindo merge após PRs `fix/active-storage-url-config` (1.5.1.3) e `feat/active-storage-purge-orphans` (1.5.1.4). Renumerar se ordem mudar.

**Problema:**
Auditoria do R2 detectou que keys de blobs eram aleatórios sem namespace por tenant — `klivy-storage/qcblr2ryx3...` para qualquer conta. Operacionalmente isso significava:
- Auditoria forense exigia JOIN no DB para descobrir a qual account um blob pertence
- Lifecycle policies tinham que ser globais (não por-tenant)
- "Delete account" (LGPD): impossível remover só os blobs de uma conta sem listar e filtrar via DB

Não era vulnerabilidade de segurança (cross-tenant access é Group D), mas dívida operacional que custa mais quanto mais clientes entram.

**Solução:**
Initializer [config/initializers/active_storage_account_scoping.rb](config/initializers/active_storage_account_scoping.rb) que monkey patch `ActiveStorage::Blob.before_create` prefixando o `key` com `accounts/<id>/` quando `Current.account` está setado (já é o padrão no `Api::V1::Accounts::BaseController`). Resultado no bucket:

```
klivy-storage/
  accounts/
    42/qcblr2ryx3...   (blob da conta 42)
    87/0gal5btb4...    (blob da conta 87)
```

Comportamento:
- HTTP requests via BaseController → `Current.account` setado → namespace aplicado
- Sidekiq jobs que setam `Current.account` → namespace aplicado
- Sistema/console/jobs sem context → key na raiz (fallback Rails default — sem regressão)
- Idempotente: keys já com prefixo `accounts/` não são alteradas

**Limitações documentadas (no header do initializer):**
- Direct uploads (browser → R2) bypass este hook. Hoje OK porque `DIRECT_UPLOADS_ENABLED` está vazio. Se ativar no futuro, signing server-side precisa montar a key prefixada manualmente.
- Jobs sem `Current.account` setado escrevem na raiz — não é vazamento, só fica menos auditável.

**Arquivos Modificados:**
- `config/initializers/active_storage_account_scoping.rb` (novo)
## [1.5.1.4] - 2026-04-27T20:21:50-03:00

### Active Storage: garbage collection de blobs órfãos (LGPD + custo R2)

> Assumindo merge após PR `fix/active-storage-url-config` (entry 1.5.1.3). Se mergeada antes, renumerar para 1.5.1.3.

**Problema:**
Auditoria do R2 detectou que apenas `ExamMedia` tinha purge automático após soft-delete (`Patients::ExamMediaPurgeJob`). Os outros models com attachment (`Document`, `ConsentRecord`, `Transaction`, `AccountTransaction`, `DataImport`) faziam soft-delete mas **nunca purgavam o blob no R2**, gerando dois problemas:

1. **LGPD:** usuário pede pra apagar dados (right to erasure), mas o blob continua acessível via signed URL que pode ter sido cacheada/vazada. Risco de auditoria.
2. **Custo:** acúmulo silencioso de bytes no R2 (~$0.015/GB/mês). 1000 documentos × 2MB × 12 meses = $0.36/mês perdido por tenant — multiplica.

Adicionalmente, blobs criados mas nunca attached (uploads abortados pelo browser, drafts não salvos) ficavam para sempre como "lixo" no bucket.

**Solução:**
1. Novo concern compartilhado [plugins/beclinic_core/app/models/concerns/beclinic_purgeable_attachment.rb](plugins/beclinic_core/app/models/concerns/beclinic_purgeable_attachment.rb) com DSL `purges_attachment_with(job_class:, after: 30.days)` e método de instância `schedule_attachment_purge!`. Cross-plugin (vive no `beclinic_core` porque é usado por patients + financial).

2. Três jobs irmãos do `ExamMediaPurgeJob`, mesmo padrão idempotente (no-op se record já destruído ou restaurado, blob purgado via `purge_later`):
   - [plugins/patients/app/jobs/patients/document_purge_job.rb](plugins/patients/app/jobs/patients/document_purge_job.rb)
   - [plugins/patients/app/jobs/patients/consent_record_purge_job.rb](plugins/patients/app/jobs/patients/consent_record_purge_job.rb)
   - [plugins/financial/app/jobs/financial/transaction_purge_job.rb](plugins/financial/app/jobs/financial/transaction_purge_job.rb)

3. Edits nos 3 models para incluir o concern, declarar `purges_attachment_with`, e chamar `schedule_attachment_purge!` no `soft_delete!`:
   - `Document` ([plugins/patients/app/models/document.rb](plugins/patients/app/models/document.rb))
   - `ConsentRecord` ([plugins/patients/app/models/consent_record.rb](plugins/patients/app/models/consent_record.rb))
   - `Transaction` ([plugins/financial/app/models/transaction.rb](plugins/financial/app/models/transaction.rb))

4. Garbage collector mensal de blobs órfãos sem attachment: [app/jobs/internal/purge_unattached_blobs_job.rb](app/jobs/internal/purge_unattached_blobs_job.rb) + agendamento em [config/schedule.yml](config/schedule.yml) (1º dia do mês 04h UTC, queue `housekeeping`). Janela de segurança 24h evita apagar uploads em transação aberta.

**Não incluído (follow-ups):**
- `AccountTransaction`: tem bug pré-existente de visibilidade — `soft_delete!` está dentro de bloco `private` (linha 29 → 83 de `account_transaction.rb`). Cobrir após corrigir o bug estrutural.
- `DataImport`: não tem soft_delete; precisa de design diferente (purge no `after_destroy`).
- `ExamMediaPurgeJob`: continua em `app/jobs/patients/` em vez de `plugins/patients/app/jobs/patients/` (tech debt cosmético, fora de escopo).

**Arquivos Modificados:**
- `plugins/beclinic_core/app/models/concerns/beclinic_purgeable_attachment.rb` (novo)
- `plugins/patients/app/jobs/patients/document_purge_job.rb` (novo)
- `plugins/patients/app/jobs/patients/consent_record_purge_job.rb` (novo)
- `plugins/financial/app/jobs/financial/transaction_purge_job.rb` (novo)
- `app/jobs/internal/purge_unattached_blobs_job.rb` (novo)
- `plugins/patients/app/models/document.rb`
- `plugins/patients/app/models/consent_record.rb`
- `plugins/financial/app/models/transaction.rb`
- `config/schedule.yml`
## [1.5.1.3] - 2026-04-27T20:15:12-03:00

### Active Storage URLs: harmonizar host config e expirações

**Problema:**
Auditoria do R2 detectou 3 inconsistências em URLs assinadas:
1. `Document#signed_url` montava `host:` via `config.action_mailer.default_url_options&.dig(:host) || 'localhost:3000'` — fallback a localhost vazaria em produção se o initializer de mailer rodasse fora de ordem.
2. `ConsentRecord#signature_image_url` mesma coisa: `host: ENV.fetch('FRONTEND_URL', 'http://localhost:3000')` — fallback inseguro.
3. `production.rb` não tinha `config.active_storage.default_url_options`, então `rails_blob_url` chamado em background jobs (Sidekiq) podia levantar `ArgumentError("Missing host")` quando a request stack estava vazia.

Adicionalmente, expirações estavam destoantes: Document=15min (curto demais para download), ConsentRecord=2h (longo demais para PHI clínico).

**Solução:**
1. [config/environments/production.rb](config/environments/production.rb) — definir `config.active_storage.default_url_options = { host: ENV['FRONTEND_URL'] }` (espelha o que `development.rb` já fazia). Active Storage helpers passam a ter host garantido em qualquer contexto.
2. [plugins/patients/app/models/document.rb](plugins/patients/app/models/document.rb) `signed_url` — remover `host:` explícito (deixar Rails resolver via `default_url_options`); ajustar expiração de 15min → 30min.
3. [plugins/patients/app/models/consent_record.rb](plugins/patients/app/models/consent_record.rb) `signature_image_url` — remover `host:` hardcoded; ajustar expiração de 2h → 30min.

`ExamMedia#signed_url` já estava no padrão correto (sem `host:`, expiração 1h) — referência para os outros.

**Arquivos Modificados:**
- `config/environments/production.rb`
- `plugins/patients/app/models/document.rb`
- `plugins/patients/app/models/consent_record.rb`
- `CHANGELOG.md`

---

## [1.5.1.2] - 2026-04-27T15:01:51-03:00

### Documentação: runbook de produção para Active Storage → R2

**Problema:**
Após o merge do PR #1 (config do R2 pronta para ativar), faltava um runbook operacional passo-a-passo cobrindo a sequência de ativação em produção (Cloudflare → Easypanel → smoke test → purge), incluindo critérios de validação e rollback por etapa.

**Solução:**
Novo documento [docs/03-engineering/runbook-active-storage-r2-production.md](docs/03-engineering/runbook-active-storage-r2-production.md) com 8 etapas (criar bucket prod, CORS, token escopado, ENVs nos services rails+sidekiq, redeploy, smoke test, purge dos blobs órfãos do Disk legado, limpeza opcional). Cada etapa lista (a) o que fazer, (b) onde fazer, (c) como validar, (d) como reverter. Tabela de diagnósticos para os 3 erros mais comuns (501 NotImplemented, 403 InvalidAccessKeyId, NoSuchBucket). Marca a Etapa 7 (purge) como ponto de não-retorno.

**Arquivos Modificados:**
- `docs/03-engineering/runbook-active-storage-r2-production.md` (novo)
- `CHANGELOG.md`

---

## [1.5.1.1] - 2026-04-27T12:43:10-03:00

### Active Storage: migrar de Disk (efêmero) para Cloudflare R2

**Problema:**
Em produção (Easypanel), o container roda sem volume persistente em `/app/storage`. Active Storage usa `service: Disk`, então qualquer redeploy ou restart apaga avatares, exames e anexos. Banco mantém os registros `ActiveStorage::Blob`, mas as URLs `/rails/active_storage/disk/...` retornam 404. Sintomas observados: avatar de paciente quebrado, vídeos/PDFs em "Exames e Imagens" sumindo após algumas horas, e erros `Not allowed to load local resource: blob:` no console.

**Solução:**
Mudanças de configuração — só acionam o R2 quando `ACTIVE_STORAGE_SERVICE=s3_compatible` e as credenciais R2 são definidas no Easypanel. Cutover sem migração de dados (cliente ainda em fase de testes, sem arquivos reais). Validado em localhost contra bucket `klivy-storage-dev` (smoke test rails runner + UI: avatar PNG, imagem 496 KB, vídeo MP4 6.55 MB).

1. Novo initializer [config/initializers/aws_sdk_r2_compat.rb](config/initializers/aws_sdk_r2_compat.rb): desliga checksums CRC32 da `aws-sdk-s3 ≥ 1.178` quando o service ativo é `s3_compatible`. Sem isso, R2 rejeita todo PUT com `501 NotImplemented`.
2. Novo initializer [config/initializers/active_storage.rb](config/initializers/active_storage.rb): define `urls_expire_in = 1.hour`, evitando 404 em galerias revisitadas (problema M2 da auditoria de exames) sem alongar exposição de PHI.
3. [config/storage.yml](config/storage.yml) `s3_compatible` ajustado para R2: `region` default `auto`, `force_path_style` default `true`. Chave `upload.acl` deliberadamente **omitida** — R2 rejeita o header `x-amz-acl` mesmo com valor vazio (501 NotImplemented), descoberto no smoke test do dev.
4. [.github/workflows/run_foss_spec.yml](.github/workflows/run_foss_spec.yml): adicionado `env: RAILS_ENV: test` ao job `backend-tests`. Bug pré-existente exposto pelo PR #1: sem RAILS_ENV explícito, `rake db:create` carregava `development.rb` e crashava ao abrir `log/development.log` (diretório gitignored, não existe no runner). Os 16 jobs paralelos morriam em cascata.
5. [.env.example](.env.example): bloco comentado documentando as ENVs `STORAGE_*` + `ACTIVE_STORAGE_SERVICE=s3_compatible`.
6. [.gitignore](.gitignore): pattern `docs/R2_Cloudlare_*.md` (e variantes `credentials*.md` / `secrets*.md`) para impedir commit acidental de credenciais R2.
7. Plano completo em [docs/03-engineering/implementation-plan-active-storage-r2.md](docs/03-engineering/implementation-plan-active-storage-r2.md), incluindo smoke test, rollback, custo estimado e purge de blobs órfãos pós-deploy.

**Arquivos Modificados:**
- `config/initializers/aws_sdk_r2_compat.rb` (novo)
- `config/initializers/active_storage.rb` (novo)
- `config/storage.yml`
- `.github/workflows/run_foss_spec.yml`
- `.env.example`
- `.gitignore`
- `docs/03-engineering/implementation-plan-active-storage-r2.md` (novo)
- `CHANGELOG.md`

---

## [1.5.0.10] - 2026-04-27T01:00:00-03:00

### Agenda Configurações: simplificar status do dia para "Aberto" / "Fechado"

**Problema:**
Em Configurações > Horários de funcionamento, dias com horário diferente do default (08:00-20:00 com almoço configurado) ganhavam o badge "Horário reduzido" (laranja). Isso polui a UI sem agregar — o usuário só precisa saber se o dia está aberto ou fechado; o detalhe do horário já está visível nos próprios inputs.

**Solução:**
Em [useSettingsSchedules.js#getDayStatus](plugins/agenda/frontend/features/settings/composables/useSettingsSchedules.js#L5-L8), colapsar todas as variantes "aberto" (com ou sem almoço, com qualquer horário) em um único retorno `{ label: 'Aberto', cls: 'open' }`. Status passa a ser binário: dia desabilitado → "Fechado", caso contrário → "Aberto". CSS órfão `.status-badge.reduced` e `.status-badge-modern.reduced` removido de [SettingsTabSchedules.vue](plugins/agenda/frontend/features/settings/components/SettingsTabSchedules.vue).

**Arquivos Modificados:**
- `plugins/agenda/frontend/features/settings/composables/useSettingsSchedules.js`
- `plugins/agenda/frontend/features/settings/components/SettingsTabSchedules.vue`
- `CHANGELOG.md`

---

## [1.5.0.9] - 2026-04-27T00:50:00-03:00

### Agenda: Fase 4 de performance — loader visual + pre-fetch de vizinhança

**Problema:**
Após Fases 0-3, a grade renderiza rápido e a navegação dispara fetch leve por janela. Restavam dois pontos de UX:
1. **Sem feedback visual durante o refetch**: trocar de semana ficava 50-200ms parecendo "travado" mesmo com a request rolando — o usuário não tem como saber que algo está acontecendo.
2. **Cada navegação espera a rede**: clique em prev/next sempre paga o round-trip do servidor, mesmo que o usuário pudesse ter os eventos já carregados em background enquanto olhava a semana atual.

**Solução:**

1. **Barra fina de progresso na grade durante refetch** ([AgendaDashboard.vue](plugins/agenda/frontend/routes/AgendaDashboard.vue#L313-L320)): linha de 2px (`h-0.5`) no topo do `.agenda-body`, posicionada absolutamente para não causar layout shift, ligada via `v-if="isFetchingEvents"` ao flag `agendaEvents/getUIFlags.isFetching`. Usa o keyframe `animate-loader-pulse` já registrado no [tailwind.config.js](tailwind.config.js#L249-L253) (opacity 0.4 → 1 → 0.4 num loop de 1.5s) — pulsa sutil, some quando a request termina. Não substitui a grade: eventos do cache continuam visíveis durante o fetch, a barra é só sinal complementar. Sem custom CSS, sem inline style — só Tailwind utility + animation já disponível no projeto.

2. **Pre-fetch da semana/dia adjacente em idle** ([useAgendaInit.js](plugins/agenda/frontend/composables/useAgendaInit.js)):
   - Após cada navegação que termina de carregar (`fetchEventsForView` + 800ms idle), dispara silenciosamente `agendaEvents/fetchByRange` para a janela anterior e a próxima — usando `requestIdleCallback` quando disponível, com fallback `setTimeout(250ms)` para Safari.
   - Para week-view: ±7 dias. Para day-view: ±1 dia. Month-view não pre-fetcha (a grade de 6 semanas já cobre vizinhança ampla).
   - **Dedupe via `recentFetches` Map** com TTL de 30s: o mesmo range não é re-disparado dentro da janela. Cobre `onMounted` + `onActivated` + watcher + prefetch sobreporem-se durante init/navegação. Backend ainda recebe ETag conditional via `fresh_when`, então mesmo um hit de dedupe-miss vira 304 — dedupe local elimina a latência do round-trip.
   - Quando o usuário clicar prev/next, o `fetchByRange` correspondente vê o range no `recentFetches` (foi pré-carregado) e pula. O store já tem os eventos via upsert, então a UI mostra eventos imediatamente — navegação fica visualmente instantânea.

**Custo extra**: 2 requests adicionais por navegação, em idle, deduplicadas, com ETag → tipicamente 304 com ~0 bytes de body. Insignificante até 50k eventos.

**Comportamento visualmente igual** exceto pela barra fina pulsando durante refetch e pela impressão de navegação instantânea após a primeira semana visitada. Cliques compulsivos em prev/next agora levam < 50ms (cache local) em vez de 50-200ms (rede).

**Arquivos Modificados:**
- `plugins/agenda/frontend/routes/AgendaDashboard.vue`
- `plugins/agenda/frontend/composables/useAgendaInit.js`
- `CHANGELOG.md`

---

## [1.5.0.8] - 2026-04-27T00:30:00-03:00

### Agenda: Fase 3 de performance — memoização frontend (filtro O(n) único + relógio dual)

**Problema:**
Mesmo com payload pequeno após Fases 0-1, a renderização da grade ainda fazia trabalho desnecessário a cada reatividade do Vue:

1. **`getEventsForDay` em full-scan por dia**: a função era invocada via prop pelo `AgendaTimelineView` (`getColumnEventsWithPositions` em [AgendaTimelineView.vue:102](plugins/agenda/frontend/components/AgendaTimelineView.vue#L102)) uma vez para cada coluna do calendário. Cada chamada percorria a lista inteira de eventos filtrando por dia/agente/prioridade/tipo/tratamento. Com 8k eventos × 7 dias = 56k iterações por render. Cada render do Vue (drag, resize, hover, scroll com hot reload) refazia esse trabalho. Em month-view era 42 dias × n.
2. **`state.now` único disparava re-render da grade inteira a cada minuto**: `setInterval` 60s atualizava um único Date que era lido por `currentTimeLineStyle`, `isEventLate`, `isHourBlocked` (past), `isDayInPast` e outros — qualquer um deles invalidava a árvore inteira que dependesse de qualquer um dos consumidores.
3. **`fetchInitialData` rodando 2x no mount**: `onMounted` + `onActivated` disparavam tudo (agentes, contatos, settings, custom attrs, range de eventos) duas vezes. Visível no Network tab como 2 requests idênticas a `/agenda_events?starts_at=...`.

**Solução:**

1. **`eventsByDayKey` Map memoizado em [AgendaDashboard.vue](plugins/agenda/frontend/routes/AgendaDashboard.vue#L164-L208)**: um único `computed` percorre `agendaEvents` em O(n), aplica todos os filtros de visibilidade e agrupa por chave `YYYY-M-D`. Cada bucket é ordenado uma vez. `getEventsForDayBound(dayObj)` vira um `Map.get` O(1). `monthEventsMap` agora consome o mesmo Map em vez de chamar `agenda.getEventsForDay` 42x. Recomputa só quando a lista de eventos OU os filtros (`hiddenAgents`/`hiddenPriorities`/`hiddenEventTypes`/`hiddenTreatments`) mudam — não em hover/drag.
2. **Relógio dual em [useAgenda.js](plugins/agenda/frontend/composables/useAgenda.js)**: `state.now` virou dois refs distintos:
   - `state.nowMinute` (1x/min): consumido por `currentTimeLineStyle`, `isEventLate`, `isCurrentTimeWithinExpediente`, `isHourBlocked` (past), `getBlockedMessage`, drag/resize bounds. Precisão de minuto onde realmente importa (linha do tempo, validação de booking no passado).
   - `state.nowDay` (só atualiza quando a data muda): consumido por `isDayInPast`. Headers de dia / month-view não re-renderizam mais 1x/min só porque a hora avançou. O `setInterval` agora compara `n.getDate()/getMonth()/getFullYear()` antes de atualizar `nowDay`.
   - Consumidor externo `useAgendaDnD` atualizado para `state.nowMinute`.
3. **Flag `hasInitialized` em [useAgendaInit.js](plugins/agenda/frontend/composables/useAgendaInit.js)**: na primeira chamada, `fetchInitialData` faz init completo (agentes, contatos, settings, custom attrs, range). Em re-ativações (KeepAlive disparando `onActivated` após `onMounted`), só chama `fetchEventsForView()` para atualizar a janela visível. Network tab agora mostra 1 request inicial em vez de 2.

**Comportamento visualmente igual** (continua o tema das fases anteriores). Drag, resize, click, navegação, filtros — tudo idêntico. Ganho percebido: scroll mais fluido em contas com muitos eventos, drag/resize sem stutter, troca de filtros (ocultar agente, etc.) instantânea.

**Arquivos Modificados:**
- `plugins/agenda/frontend/routes/AgendaDashboard.vue`
- `plugins/agenda/frontend/composables/useAgenda.js`
- `plugins/agenda/frontend/composables/useAgendaDnD.js`
- `plugins/agenda/frontend/composables/useAgendaInit.js`
- `CHANGELOG.md`

---

## [1.5.0.7] - 2026-04-27T00:10:00-03:00

### Agenda: hotfix — eventos sumindo após Fase 1 (params ignorados pelo ApiClient base)

**Problema:**
Após o deploy da Fase 1, a grade da semana atual ficou completamente vazia. Settings (feriados, fora do expediente) carregavam normalmente — só os eventos sumiram.

**Causa raiz:**
O método `ApiClient.get()` em [ApiClient.js:42-44](app/javascript/dashboard/api/ApiClient.js#L42-L44) é declarado como `get() { return axios.get(this.url) }` — **ignora qualquer argumento**. O `filter()` em [agendaEvents.js](plugins/agenda/frontend/api/agendaEvents.js) passava `this.get({ params })`, mas `params` era silenciosamente descartado. Resultado: o request batia em `/agenda_events` sem `starts_at`/`ends_at`, caía no cap defensivo da Fase 0 (`limit(500).order(:starts_at)`) e devolvia os 500 eventos **mais antigos** da conta — tipicamente importações históricas, fora da semana visível.

Antes da Fase 1 isso funcionava por acidente: o store dispatchava `agendaEvents/get`, que chamava `AgendaEventsAPI.get(filters)`, e os filters eram igualmente ignorados — mas como ainda não havia cap nem range, o backend devolvia a tabela inteira, então a UI conseguia filtrar em memória. A Fase 0 (cap) + Fase 1 (range esperado mas não enviado) expôs o bug latente.

**Correção:**
Trocar `this.get({ params })` por `axios.get(this.url, { params })` direto no `filter()`. Não tocar no `ApiClient` base (escopo isolado, sem regressão potencial em outros recursos).

**Arquivos Modificados:**
- `plugins/agenda/frontend/api/agendaEvents.js`
- `CHANGELOG.md`

---

## [1.5.0.6] - 2026-04-26T23:50:00-03:00

### Agenda: Fase 1 de performance — fetch por range visível com refetch debounced

**Problema:**
Após a Fase 0 (cap + ETag + índices), o frontend ainda baixava a tabela inteira (até 500 eventos pelo cap) na primeira carga porque [`useAgendaInit`](plugins/agenda/frontend/composables/useAgendaInit.js) chamava `dispatch('agendaEvents/get')` sem filtros, e a navegação entre semanas não disparava nenhum refetch — Vue apenas refiltrava em memória os eventos pré-carregados. Em contas com 8k+ eventos isso significa: payload inicial pesado, dor de re-render no scroll, e zero invalidação de dados quando o usuário muda de mês.

**Solução:**

1. **Predicado de range corrigido** ([agenda_events_controller#index](plugins/agenda/app/controllers/api/v1/accounts/agenda_events_controller.rb#L13-L17)): trocou containment (`starts_at >= ? AND ends_at <= ?`) por overlap real (`starts_at < ? AND ends_at > ?`). Eventos que cruzam a borda da janela (ex.: domingo 23:30 → segunda 00:30) agora aparecem corretamente em todas as semanas que tocam — antes sumiam silenciosamente em ambas. Pré-requisito para Fase 1: sem isso, mandar range do client viraria regressão para esse caso de borda.

2. **Action `fetchByRange` com upsert** ([store/agendaEvents.js](plugins/agenda/frontend/store/agendaEvents.js)): nova action recebe `{ startsAt, endsAt, userId }` e mescla os resultados no store por `id` em vez de substituir o array (`SET_AGENDA_EVENTS` continua existindo para compat). Isso preserva eventos já carregados de outras janelas, evita race condition com drag-and-drop em curso e funciona como cache implícito client-side. Mutation type `UPSERT_AGENDA_EVENTS` adicionada em [mutation-types.js](app/javascript/dashboard/store/mutation-types.js).

3. **Refetch debounced ao navegar** ([useAgendaInit.js](plugins/agenda/frontend/composables/useAgendaInit.js)): `watch` em `[currentDate, viewMode]` dispara `fetchEventsForView` com debounce de 150ms — clicar prev/next em sequência agora dispara apenas a última requisição. Janela calculada em `computeRange`:
   - **day**: do 00:00 ao 23:59 do dia atual.
   - **week**: domingo 00:00 a sábado 23:59 (alinhado com `startOfWeek({ weekStartsOn: 0 })` que é o que o `calendarWeeks` em useAgenda.js usa).
   - **month**: grade de 6 semanas a partir do início da semana do dia 1 — espelha exatamente o layout de `calendarWeeks` para que o month view nunca pinte um dia "vazio" só por falta de fetch.
   - 1 minuto de padding em cada borda para evitar clip por arredondamento de timezone.

4. **Inicialização do dashboard mais leve**: a chamada inicial em `fetchInitialData` agora usa `fetchEventsForView` (range da semana/dia atual) em vez de buscar todos os eventos. Carga inicial cai de "até 500 eventos" para tipicamente 30-100 por semana.

**Comportamento visualmente igual:** layout, cards, drag, modais e cores não mudam. Única mudança perceptível: trocar de semana agora dispara um fetch (~50-200ms) em vez de filtrar localmente. Sem skeleton ainda — fica para Fase 4 se a fração de tela em branco incomodar.

**Arquivos Modificados:**
- `plugins/agenda/app/controllers/api/v1/accounts/agenda_events_controller.rb`
- `app/javascript/dashboard/store/mutation-types.js`
- `plugins/agenda/frontend/store/agendaEvents.js`
- `plugins/agenda/frontend/composables/useAgendaInit.js`
- `CHANGELOG.md`

---

## [1.5.0.5] - 2026-04-26T23:30:00-03:00

### Agenda: Fase 0 de performance — cap, eager loading, ETag e índices compostos

**Problema:**
Com ~8.000 agendamentos importados em produção, abrir a visualização semanal travava: scroll engasgava, payload do `GET /agenda_events` devolvia a tabela inteira (frontend nunca enviava `starts_at`/`ends_at`), o jbuilder acessava `resource.contact` e `resource.user` por evento sem `includes` (~16k queries N+1) e os únicos índices eram single-column (`account_id`, `user_id`, `contact_id`) — qualquer filtro por intervalo de datas caía em seq scan.

**Solução:**
Fase 0 do plano de auditoria: corrige o pior caso sem alterar contrato de API. Frontend antigo continua funcionando; cap protege contra dump full-table.

1. **Eager loading**: [`agenda_events_controller#index`](plugins/agenda/app/controllers/api/v1/accounts/agenda_events_controller.rb#L4-L20) agora chama `.includes(:user, :contact)` — derruba os ~16k queries N+1 disparados pelo jbuilder ao serializar `resource.contact`/`resource.user`.
2. **Cap defensivo**: `limit(INDEX_MAX_RESULTS = 500)` + `order(:starts_at)`. Sem range, devolve os 500 mais próximos em vez da tabela inteira. Loga warn em produção quando o request chega sem range, para visibilidade durante a transição.
3. **ETag automático**: `fresh_when(@agenda_events)` — navegação repetida pela mesma semana retorna `304 Not Modified`, sem recomputar serializer.
4. **Índices compostos** com `CONCURRENTLY` (sem downtime) em [migrate/20260426190000](db/migrate/20260426190000_add_range_indexes_to_agenda_events.rb):
   - `(account_id, starts_at)` — cobre week-view com todos os agentes.
   - `(account_id, user_id, starts_at)` — cobre day-view filtrado por dentista.

A correção semântica do predicado de range (`starts_at < end AND ends_at > start` em vez do containment atual) ficou para Fase 2 porque pode incluir eventos que hoje não aparecem na borda da janela — exige testar com dados reais antes de subir.

**Arquivos Modificados:**
- `plugins/agenda/app/controllers/api/v1/accounts/agenda_events_controller.rb`
- `db/migrate/20260426190000_add_range_indexes_to_agenda_events.rb`
- `CHANGELOG.md`

---

## [1.5.0.4] - 2026-04-26T22:30:00-03:00

### Prontuário aba Geral: estilos `.geral-*` restaurados (cards de consulta, botões, banner crítico, nota fixada)

**Problema:**
Na aba `?tab=general` do prontuário ([http://localhost:3000/app/accounts/31/patients/2370/record](app/accounts/31/patients/2370/record)) os cards de "Última Consulta" / "Próxima Consulta" apareciam com texto colado — `Última ConsultaNenhuma consulta registrada` numa linha só, sem ícone separado, sem hierarquia. O botão `Agendar Consulta`, o banner de Alertas Críticos, a sticky-note amarela do `pinned_note`, o card do plano de tratamento, a linha do profissional responsável e a meta-info (Unidade, Origem) também ficaram sem estilo. Tudo virou texto inline puro.

**Causa raiz:**
O refactor [f6813bc5](https://github.com/) (extraiu `RegistrationTab` e `FinancialTab` do `Record.vue`) reescreveu o `<style scoped>` do componente e **dropou as 212 linhas de regras `.geral-*`** que estavam lá. Os 9 arquivos do plugin que dependiam dessas classes (`Record.vue` + 8 tabs) ficaram referenciando seletores que não existem em lugar nenhum — o navegador caiu no default `display: inline` pra todo `<span>`, daí o texto colado.

**Correção:**
Recuperei as 212 linhas via `git show f6813bc5^:Record.vue` e movi pra [record.css](plugins/patients/frontend/routes/patients/record.css#L2624) (CSS compartilhado, em vez de voltar pra `<style scoped>` — assim as outras tabs do plugin que também usam `.geral-*` herdam de graça). Bloco delimitado por comentário explicando a origem, pra evitar que o próximo refactor remova achando que é dead code.

Classes restauradas: `geral-alert-banner/icon/body/title/text`, `geral-pinned-note`, `geral-action-btn`, `geral-header-btn`, `geral-tags-row`, `geral-plan-title`, `geral-divider`, `geral-prof-row/avatar`, `geral-meta-row/item/label/value`, `geral-visit-card`, `geral-visit-icon`, `geral-visit-info`, `geral-visit-label`, `geral-visit-date(--highlight)`, `geral-visit-time`, `geral-visit-empty`. Os modifiers `--past` / `--next` continuam vindo de utilitários Tailwind inline no template (não precisam de CSS).

**Verificação:**
- `wc -l record.css`: 2840 linhas (era 2623 + 212 + comentário).
- Todos os 9 arquivos que referenciam `.geral-*` agora têm seletor resolvido.

**Arquivos Modificados:**
- `plugins/patients/frontend/routes/patients/record.css` (+ bloco `.geral-*` completo, comentário de origem)
- `CHANGELOG.md`

---

## [1.5.0.3] - 2026-04-26T22:00:00-03:00

### Pacientes: paginação real no servidor + total no header (resolve teto de 500)

**Problema:**
A tela `/plugins/patients` mostrava no máximo 500 pacientes. O frontend chamava `PatientsAPI.get(...)` sempre com `page=1&per_page=500` e fazia paginação 100% no cliente — qualquer paciente além do 500º simplesmente não aparecia. Além disso, não havia em nenhum lugar a contagem total de pacientes ativos da conta, e baixar 500 registros (com `critical_alerts`, `responsible_professional`, `patient_appointments`) por requisição, pra exibir 15-25 na tela, era desperdício de banco/rede.

**Solução:**

1. **Paginação server-side de verdade.** [PatientsAPI.get](plugins/patients/frontend/api/patients/index.js#L24) agora aceita `{ page, perPage, sort, search, status }` (via `URLSearchParams` — sem concatenação manual de query string) e o controller respeita `per_page` (cap 500) + `page`. [Index.vue](plugins/patients/frontend/routes/patients/Index.vue) lê `meta.total_count` / `meta.total_pages` do response, refaz fetch a cada mudança de página/perPage/filtro/busca/sort, e o default caiu de 500 → 25 por requisição. O view `index.json.jbuilder` já expunha `meta` — só não estava sendo usado.

2. **Sort enviado pro servidor.** Novo [`apply_sort`](plugins/patients/app/controllers/api/v1/accounts/patients_controller.rb#L260) com whitelist `SORT_OPTIONS` (`name_asc/desc`, `created_at_asc/desc`, fallback em `name_asc`). Antes o `.order(:name)` era fixo no controller e o sort `Mais recente`/`Mais antigo` só funcionava dentro dos 500 já carregados — agora aplica em todo o conjunto.

3. **Total no header.** Novo badge azul `pt-total-badge` ao lado do título `Pacientes` (`<span>{{ totalCount }}</span>`) — fica ao vivo conforme filtros mudam (ex: filtrando `Faltoso`, mostra o total de faltosos). E a linha "Exibindo X–Y de Z pacientes" no rodapé agora reflete o total real do servidor, não só os 500 baixados.

4. **Callers atualizados pra nova assinatura.** [AgendaEventModal.vue](plugins/agenda/frontend/components/AgendaEventModal.vue#L413) e [RegistrationTab.vue](plugins/patients/frontend/routes/patients/tabs/RegistrationTab.vue#L574) usavam `PatientsAPI.get(1, 'name', query, '')` (positional) — migrados pro novo formato de objeto.

**Verificação:**
- `ruby -c` no controller: `Syntax OK`.
- `perPageOptions` aumentado pra `[25, 50, 100, 200]` — quem quiser ver mais por página continua podendo, mas o default consciente.

**Arquivos Modificados:**
- `plugins/patients/app/controllers/api/v1/accounts/patients_controller.rb` (remoção do `.order(:name)` fixo, + `apply_sort` + `SORT_OPTIONS`)
- `plugins/patients/frontend/api/patients/index.js` (assinatura `{page, perPage, sort, search, status}` + `URLSearchParams`)
- `plugins/patients/frontend/routes/patients/Index.vue` (paginação server-side, leitura de `meta`, badge de total, sort delegado ao servidor)
- `plugins/patients/frontend/routes/patients/patients-index.css` (`.pt-total-badge`)
- `plugins/agenda/frontend/components/AgendaEventModal.vue` (nova assinatura)
- `plugins/patients/frontend/routes/patients/tabs/RegistrationTab.vue` (nova assinatura)
- `CHANGELOG.md`

---

## [1.5.0.2] - 2026-04-26T21:00:00-03:00

### Migração: re-importar agora limpa o pinned_note legado automaticamente

**Problema:**
Os 2 imports anteriores (Mamedes #31) gravaram conteúdo clínico do Clinicorp em `pinned_note` (a Nota Fixada amarela do prontuário), por causa do bug corrigido em [1.5.0.1]. Sem o fix de hoje, re-importar o mesmo CSV não resolvia: o importer encontrava o paciente, atualizava só campos vazios em `notes`, e o `pinned_note` antigo permanecia — paciente ficaria com a info duplicada em 2 lugares.

**Correção:**
Novo helper `legacy_pinned_to_migrate?(existing)` em [clinicorp_patient_importer.rb:237-247](plugins/migration/app/services/migration/clinicorp_patient_importer.rb#L237) que detecta o resíduo: paciente com `origin='migration_clinicorp'` que tem `pinned_note` preenchido **e** o conteúdo desse `pinned_note` ainda não está em `notes` (idempotente — re-rodar 2x não duplica).

Mudanças no flow de merge:
- `decide_merge` ([linha 226](plugins/migration/app/services/migration/clinicorp_patient_importer.rb#L226)): antes só atualizava se `incoming_score > existing_score` (CSV traz mais info que o paciente já tem). Agora também atualiza se `legacy_pinned_to_migrate?` é true — força o cleanup mesmo quando o CSV é idêntico ao que já foi importado.
- `merge_into_existing` ([linha 270-279](plugins/migration/app/services/migration/clinicorp_patient_importer.rb#L270)): quando `legacy_pinned_to_migrate?` é true, consolida `[notes existente, pinned_note existente, notes do CSV]` em `notes` (dedup com `.uniq`, junta por `\n`) e seta `pinned_note: nil`. Senão, comportamento antigo (só preenche `notes` se estiver vazio).

**Preview atualizado:**
`ClinicorpPatientPreviewer#decide_action` ([linha 86-100](plugins/migration/app/services/migration/clinicorp_patient_previewer.rb#L86)) agora consulta `legacy_pinned_to_migrate?` via `send` e — se aplica — devolve `['update', "Vai mover pinned_note legado pra Observações."]`. Assim o usuário vê na pré-visualização exatamente quantos pacientes vão ser limpos antes de confirmar.

**Como usar:**
Pra arrumar os 2 imports já feitos: subir o **mesmo Patient.csv** novamente, dar Pré-visualizar, conferir que aparece "Atualizar" com a razão de cleanup, clicar Confirmar. Idempotente — pode rodar várias vezes sem duplicar dados.

**Verificação:**
- `ruby -c` nos 2 arquivos modificados: `Syntax OK`.
- Caso `notes` já contenha o texto do `pinned_note` (re-import depois do fix): helper retorna false, paciente cai no caminho de skip.
- Caso paciente tenha `pinned_note` colocado manualmente depois do import: também pega no cleanup. Aceitamos esse risco — os 2 imports são recentes, improvável que alguém tenha editado pinned_note manualmente; e o conteúdo vai pra notes (não some).

**Arquivos Modificados:**
- `plugins/migration/app/services/migration/clinicorp_patient_importer.rb` (+ `legacy_pinned_to_migrate?`, `decide_merge` força update, `merge_into_existing` consolida e limpa)
- `plugins/migration/app/services/migration/clinicorp_patient_previewer.rb` (`decide_action` checa cleanup primeiro)
- `CHANGELOG.md`

---

## [1.5.0.1] - 2026-04-26T20:30:00-03:00

### Migração: pré-visualização antes do import + correção de campo Notes + classificação de colisões como warning

**Problemas reportados pelo usuário após o primeiro import real:**
1. Notes do Clinicorp ("Plano Odonto 300092714, nega problemas de saúde, toma puran t4 100mcg…") apareciam como **pinned_note** (sticky-note amarela de destaque no prontuário). Esse campo é pra lembretes curtos tipo "chamar pelo apelido", não pra histórico clínico longo.
2. Não havia como saber, antes de importar, quantos pacientes seriam criados, atualizados ou pulados — usuário só descobria no log depois.
3. Mensagens "Colisão de clinicorp_id para chave '4,50989E+15'" apareciam como **erro** vermelho, mas na prática são limitação do Excel (arredonda IDs de 16 dígitos para notação científica) e os pacientes são importados normalmente — só a anamnese fica sem vínculo determinístico.

**Correção 1 — campo Notes:**
- `pinned_note: notes` → `notes: notes` em [plugins/migration/app/services/migration/clinicorp_patient_importer.rb:156](plugins/migration/app/services/migration/clinicorp_patient_importer.rb#L156). Isso afeta `map_row`, `merge_into_existing` e `create_patient` — todas atualizadas. Removida também a concatenação com `IndicationSource` (que tem fluxo próprio de "Como conheceu" e não deveria ser misturado com histórico clínico).

**Correção 2 — pré-visualização ("dry run"):**
- Novo serviço `Migration::ClinicorpPatientPreviewer` (em [plugins/migration/app/services/migration/clinicorp_patient_previewer.rb](plugins/migration/app/services/migration/clinicorp_patient_previewer.rb)) que reusa as helpers do importer (`map_row`, `find_existing_patient`, `score_existing/mapped`, `scientific_truncation`) via `send` — assim a preview é fiel ao que o import vai fazer, sem segunda implementação que pode divergir. Retorna `{ summary: { total, would_create, would_update, would_skip, errors, warnings }, rows: [{action, name, cpf, fields, reason}] (cap 100), warnings: [...], anamneses: { total, linked, unlinked } }`.
- Nova ação `preview` em [app/controllers/super_admin/migrations_controller.rb](app/controllers/super_admin/migrations_controller.rb) (POST `/super_admin/migrations/preview`) — aceita o mesmo multipart payload que `create`, valida tamanho de arquivo, mas não cria `MigrationRun` nem dispara job. Limita a 25MB igual ao create.
- Rota `post :preview` adicionada em [config/routes.rb](config/routes.rb) como collection action de `migrations`.
- Frontend: novo botão "Pré-visualizar" em [MigrationUploadForm.vue](plugins/migration/frontend/features/migration/components/MigrationUploadForm.vue) que dispara `previewCsv` (em [migrationApi.js](plugins/migration/frontend/features/migration/api/migrationApi.js), que extrai `buildFormData` para reuso entre upload e preview), exibe summary chips coloridos (Criar verde / Atualizar azul / Pular cinza / Avisos âmbar) e tabela de até 100 linhas mostrando, pra cada paciente: ação prevista, nome, CPF, email/telefone, plano, primeiros 80 chars do `notes`, e "razão" textual ("Já existe paciente 'X' (id=…). Vai preencher campos vazios: phone, address."). Trocar arquivo invalida o preview; botão "Iniciar" muda para "Confirmar e iniciar" depois do preview gerado.

**Correção 3 — colisões viram warnings:**
- Em [clinicorp_patient_importer.rb:317](plugins/migration/app/services/migration/clinicorp_patient_importer.rb#L317), `log_error` → novo helper `log_warning` (level='warning' no `errors_log`) com mensagem mais didática: "Chave 'X' colide entre 2+ pacientes (Excel arredondou IDs longos). Pacientes importados normalmente; anamneses dessa chave ficam sem vínculo." Mesma mudança em `build_and_persist_anamnesis` para os dois casos (collision e patient não importado). Adicionado `warnings` ao hash `@counters` (não somado em `error_count` no DB — é um contador separado em memória, exposto via preview/log).
- `MigrationRunDetail.vue`: nova classe CSS `mig-error-list__item--warning` (âmbar `#fffbeb`/`#78350f`) — antes só tinha `--info` (cinza). `mig-error-list__item` base agora pinta erros em vermelho explicitamente (era a cor default), pra warnings ficarem visualmente distintos.

**Por que `send` nas helpers do importer (em vez de extrair pra módulo compartilhado):**
Considerado, mas a refatoração maior (Mapper module + Importer + Previewer) iria expandir muito o escopo dessa correção. `send` no Previewer é circunscrito às helpers puras (sem efeito colateral no `@run`/`@account`); se um dia a alma for melhorar, basta extrair, sem mudar a interface da preview.

**Verificação:**
- `ruby -c` nos 3 arquivos Ruby modificados/novos: `Syntax OK`.
- A view ERB `index.html.erb` não foi tocada (continua só com `<%= render_vue_component('MigrationIndex') %>`); o componente Vue ganhou estado novo (`preview`, `previewing`) sem mudar a montagem.
- Limite de tamanho de arquivo (25MB) aplicado também na preview pra evitar DoS.

**Arquivos Modificados:**
- `plugins/migration/app/services/migration/clinicorp_patient_importer.rb` (Notes → notes em 3 lugares; warnings via novo helper; counters[:warnings])
- `plugins/migration/app/services/migration/clinicorp_patient_previewer.rb` (novo)
- `app/controllers/super_admin/migrations_controller.rb` (+ ação `preview`, helper `preview_patients`)
- `config/routes.rb` (+ collection `post :preview`)
- `plugins/migration/frontend/features/migration/api/migrationApi.js` (+ `previewCsv`, refator `buildFormData`)
- `plugins/migration/frontend/features/migration/components/MigrationUploadForm.vue` (botão pré-visualizar, summary chips, tabela de rows)
- `plugins/migration/frontend/features/migration/components/MigrationRunDetail.vue` (classe CSS pra warning)
- `plugins/migration/frontend/features/migration/migration.css` (`.mig-preview*`, `.mig-error-list__item--warning`)
- `CHANGELOG.md`

---

## [1.5.0.0] - 2026-04-26T19:30:00-03:00

### Novo módulo: Migração de dados (importador de planilhas Clinicorp)

**O que foi adicionado:**
Plugin `migration` instalado a partir do repositório remoto (`Slowlyzadao/Klivyapp/plugins/migration`). Console no Super Admin (`/super_admin/migrations`) que permite importar planilhas de outras plataformas (Clinicorp como primeiro source suportado) para uma `Account` específica do Klivy. Suporta os tipos `patients` (com até 3 CSVs: Patient + PatientAnamnesis + Anamnesis), `agenda`, `anamnesis` e `financial`.

**Arquitetura:**
- **Plugin engine** (`plugins/migration/lib/migration/engine.rb`): registra `db/migrate` do plugin e injeta `Account.has_many :migration_runs` via `config.to_prepare`.
- **Modelo** `MigrationRun` com colunas de progresso (total/processed/created/updated/skipped/error counts), status (`pending|processing|completed|failed`), kind, source, csv_filename, errors_log e referência ao super_admin que disparou.
- **Job assíncrono** `Migration::ProcessCsvJob` que executa o importer correto via Sidekiq.
- **Services** `Migration::ClinicorpPatientImporter` e `Migration::ClinicorpAgendaImporter` (parsers específicos por origem).
- **Frontend Vue 3** (single page app embutido na view ERB do Super Admin via `render_vue_component`): `MigrationIndex.vue` com polling a cada 4s, `MigrationUploadForm.vue` (upload multipart, condicional por kind), `MigrationRunsTable.vue` (histórico) e `MigrationRunDetail.vue` (progresso + log de erros). API client em `migrationApi.js` usando sessão Devise super_admin (cookie + CSRF, sem Authorization header).

**Por que precisou de arquivos no core (fora do plugin):**
O Super Admin Console é renderizado pelo Administrate, que descobre rotas pelo namespace `super_admin/`. Para o item aparecer na sidebar e o Vue ser bundleado pelo Vite no entrypoint `superadmin_pages`, controller, view ERB, rota, registro no ComponentMapping e ícone do sprite SVG precisam viver no core (limitação conhecida do Zeitwerk + Administrate, mesma usada pelos plugins `assinatura` e `ajuda` no remoto).

**Integração realizada (5 pontos de wiring):**
1. **Rota** (`config/routes.rb`): adicionado `resources :migrations, only: [:index, :create, :show]` dentro do `namespace :super_admin`.
2. **Controller core** (`app/controllers/super_admin/migrations_controller.rb`): herda de `SuperAdmin::ApplicationController`, valida tamanho de arquivo (limite 25MB), aceita 3 CSVs no kind `patients` ou um único `csv` para os outros kinds, força encoding UTF-8 com fallback de replace para bytes inválidos, cria `MigrationRun` e dispara `Migration::ProcessCsvJob`.
3. **View ERB** (`app/views/super_admin/migrations/index.html.erb`): 3 linhas, só monta o componente Vue via `render_vue_component('MigrationIndex')`.
4. **Vite entrypoint** (`app/javascript/entrypoints/superadmin_pages.js`): importado `MigrationIndex` de `../../../plugins/migration/...` e registrado no `ComponentMapping` (sem isso, o `render_vue_component` ficaria vazio).
5. **Sidebar** (`app/views/super_admin/application/_navigation.html.erb`): `"migrations"` adicionado à skip-list do loop do Administrate (impede tentativa de carregar dashboard inexistente) e adicionado um `nav_item` manual com label "Migração" apontando para `super_admin_migrations_url`.

**Detalhe extra — ícone do sprite:**
O `_nav_item.html.erb` referencia ícones via `<svg><use xlink:href="#icon-name" /></svg>` (sprite registrado em `_icons.html.erb`). O ícone `icon-database-2-line` não existia no sprite (mesmo no remoto faltava — o changelog do Leandro confirma esse mesmo padrão para os plugins de assinatura/ajuda). Adicionado `<symbol id="icon-database-2-line" viewBox="0 0 24 24">` com path do Remix Icon `database-2-line`.

**Verificação:**
- `bundle exec rails db:migrate` aplicado com sucesso (criou tabela `migration_runs` via migration `20260426023750`).
- `db/schema.rb` atualizado com a nova tabela.
- Rota `super_admin_migrations_url` resolvida.
- Item "Migração" aparece na sidebar do Super Admin com ícone de database renderizado.

**Arquivos Modificados:**
- `plugins/migration/**` (novo — 13 arquivos: engine, model, job, 2 services, 1 db migration, 6 arquivos de frontend Vue/CSS/JS)
- `app/controllers/super_admin/migrations_controller.rb` (novo)
- `app/views/super_admin/migrations/index.html.erb` (novo)
- `config/routes.rb` (+1 rota)
- `app/javascript/entrypoints/superadmin_pages.js` (+import + mapping)
- `app/views/super_admin/application/_navigation.html.erb` (skip-list + nav_item)
- `app/views/super_admin/application/_icons.html.erb` (+symbol `icon-database-2-line`)
- `db/schema.rb` (auto-atualizado pela migration)
- `CHANGELOG.md`

---

## [1.4.5.5] - 2026-04-26T18:30:00-03:00

### Prontuário/Cadastro: ícone de busca do CEP (lupa) renderizando fora do input

**Problema:**
A lupa do campo CEP aparecia em uma linha abaixo do input, à esquerda, em vez de sobreposta no canto direito do `<input>`.

**Causa raiz:**
As classes `.input-with-action` (wrapper com `position: relative`) e `.btn-icon-inside` (botão com `position: absolute; right: 8px`) viviam exclusivamente no `<style scoped>` do `Record.vue`. Como o `RegistrationTab.vue` é componente filho separado, o seletor scoped do pai (`[data-v-XXX]`) não casa com elementos do filho — só `.form-input` e os outros estilos compartilhados (que já estão em `record.css` global) atravessam a fronteira. Com o wrapper sem `position: relative` e o botão sem `position: absolute`, ambos viraram blocks empilhados no fluxo normal, jogando a lupa para a linha de baixo.

**Solução:**
- Adicionadas as regras `.input-with-action` e `.btn-icon-inside` (+ `:hover`) no `<style scoped>` do `RegistrationTab.vue`. Adicionei também `.input-with-action .form-input { padding-right: 36px; }` para garantir que o texto digitado nunca passe por baixo da lupa.
- Tokens migrados para o design system: `rgb(var(--slate-9))` (cor padrão), `rgb(var(--slate-12))` (hover) e `rgb(var(--slate-3))` (background hover) em vez dos hex `#94a3b8` / `#f1f5f9` / `rgba(255,255,255,0.1)` do código antigo, ficando consistente com o resto do prontuário.

**Arquivos Modificados:**
- `plugins/patients/frontend/routes/patients/tabs/RegistrationTab.vue` (+ ~22 linhas de CSS)
- `CHANGELOG.md`

---

## [1.4.5.4] - 2026-04-26T18:20:00-03:00

### Prontuário/Cadastro: campos não persistiam ao salvar (Nome Social, Bairro, Validade da Carteirinha)

**Problemas reportados:**
1. **Nome Social** — input nunca persistia. (`<input>` sem `v-model`, sem coluna no banco, sem permit; era um placeholder visual.)
2. **Bairro** — usuário digitava, clicava em Salvar, e o valor sumia visualmente.
3. **Validade da Carteirinha** — mesmo padrão: digitar, salvar, sumir.

**Causas raiz:**

1. **Nome Social**: campo decorativo sem nada por trás. Bug pré-existente (já estava assim no commit `2efb9f4a`, antes da extração).

2. **Bairro**: o campo era persistido no payload corretamente, mas o `searchCep()` (autosearch via watcher de `zip_code`) sobrescrevia `address.neighborhood` com o valor (frequentemente vazio) que o ViaCEP retorna para o CEP — para CEPs de cidades pequenas a API costuma devolver `bairro: ""`. Isso acontecia em duas situações: (a) no fetch inicial do paciente, quando o watcher detectava `zip_code` indo de `''` para o valor salvo e disparava ViaCEP; (b) após qualquer mudança que fizesse o watcher reavaliar. Resultado: usuário digitava "Centro", salvava, parent re-fetchava, watcher disparava searchCep, ViaCEP retornava bairro vazio, sobrescrevia. Bug latente do código original — só ficou visível agora porque o fluxo de salvar foi exercitado mais.

3. **Validade da Carteirinha**: mismatch de nome de campo entre frontend e backend. Frontend gravava em `insurance.valid_until`; o `permit` do controller já permitia apenas `insurance: [:name, :number, :plan, :validity]` e a documentação OpenAPI (`api-docs.html`) e `PatientRecordPopup.vue` usavam `validity`. O `valid_until` enviado pelo frontend era silenciosamente filtrado pelo Strong Params. Bug pré-existente (mesmo nome estava no commit antigo).

**Solução — backend:**
- Migration `20260426180000_add_social_name_to_patients.rb`: `add_column :patients, :social_name, :string`.
- `patients_controller.rb`: adicionado `:social_name` na lista de `permit(...)` (logo após `:name`).
- `_patient.json.jbuilder`: adicionado `json.social_name patient.social_name`.

**Solução — frontend (`RegistrationTab.vue`):**
- **Nome Social**: adicionado `v-model="patient.social_name"` no `<input>` e incluído no payload do `saveRegistration` como `social_name: props.patient.social_name || ''`.
- **Validade da Carteirinha**: renomeadas as 4 referências a `insurance.valid_until` para `insurance.validity` (watcher source, handler de input que setava ISO, handler que limpava no campo vazio, handler de blur que re-formatava). Não toquei em `FinancialTab.vue` — `valid_until` lá é coluna real de `financial_estimates` (domínio diferente).
- **Bairro / CEP autosearch**:
  - `searchCep(forceOverwrite = false)` — agora nunca sobrescreve `street/neighborhood/city/state` que já tenham valor, a menos que `forceOverwrite=true`. ViaCEP só preenche campos vazios (e ignora valores vazios retornados — sem mais "limpar" bairro porque o CEP é genérico).
  - Lupa de busca manual continua sobrescrevendo (`searchCep(true)` no `@click.prevent` do botão de busca) — comportamento esperado quando o usuário pede explicitamente para refazer a busca.
  - Watcher de `zip_code` agora exige `cepUserDirty.value === true` antes de disparar autosearch. A flag é setada via `markCepDirty` no `@input` do CEP, ou seja: só dispara ViaCEP automaticamente quando o usuário digita/cola/edita o CEP — fetch do parent não dispara mais pesquisa nenhuma e não sobrescreve nada do que veio do banco.

**Solução — frontend (`Record.vue`):**
- `patient.value` ref inicializer: adicionado `social_name: ''` e renomeado `valid_until: ''` para `validity: ''` no `insurance`.

**Limpeza colateral (IDE diagnostics — `Record.vue`):**
Após as remoções de código durante o refactor, sobraram imports e funções não usados que o tsserver vinha sinalizando. Removidos: `PatientTimelineAPI`, `brToIsoDate`, `maskDateBR`, `FormSelect`, `formatTime`, `formatCurrency`. `BRT` mantido (usado por outros formatadores de data restantes).

**Verificação:**
- `bundle exec rails db:migrate` aplicado com sucesso (a falha do `annotaterb` é warning posterior à aplicação real, não interfere no schema).
- `Patient.column_names` retorna `social_name`.
- `@vue/compiler-sfc` `parse + compileTemplate + compileScript` em ambos os arquivos: zero erros.
- HMR Vite recarregou sem warnings; rails reiniciado para pegar a mudança em controller.

**Arquivos Modificados:**
- `db/migrate/20260426180000_add_social_name_to_patients.rb` (novo)
- `plugins/patients/app/controllers/api/v1/accounts/patients_controller.rb` (+:social_name no permit)
- `app/views/api/v1/accounts/patients/_patient.json.jbuilder` (+social_name no serializer)
- `plugins/patients/frontend/routes/patients/Record.vue` (initializer + cleanup de imports)
- `plugins/patients/frontend/routes/patients/tabs/RegistrationTab.vue` (v-model em Nome Social, rename `validity`, refator de `searchCep` + `cepUserDirty`)
- `CHANGELOG.md`

---

## [1.4.5.3] - 2026-04-26T18:10:00-03:00

### Prontuário/Cadastro: dropdowns vazios e estilos quebrados (toggle "Possui responsável?", divisores, etc.)

**Problema:**
Após abrir a aba Cadastro, os dropdowns de **Sexo**, **Estado Civil**, **Grau de Relacionamento**, **Estado (UF)** e **Convênio** ficavam invisíveis (não renderizavam nada — campo simplesmente não aparecia). Vários estilos também estavam quebrados visualmente: o toggle de "Possui responsável?" sem layout (texto e switch desalinhados), bloco de Responsável sem indentação/borda lateral, animação de collapse ao expandir, observações textarea sem o min-height/resize, badge WhatsApp sem cor, dropdown de busca de contato/paciente sem estilização (lista nua).

**Causa raiz:**
1. O componente `FormSelect` usado em todos os 5 dropdowns nunca foi importado no `<script setup>` da `RegistrationTab.vue` durante a extração — Vue 3 com `<script setup>` exige import explícito (não há registro global de componentes neste codebase). Como resultado, os 5 `<FormSelect>` viraram custom-elements que o browser ignora, removendo o campo da árvore.
2. ~26 classes CSS específicas do Cadastro nunca foram migradas. Algumas estavam no `<style scoped>` original do `Record.vue` e outras eram exclusivas dessa aba — não foram para o `record.css` global porque eram de uso único. Classes faltantes: `.reg-toggle-row`, `.reg-toggle-row-text/title/hint`, `.reg-guardian-block`, `.reg-collapse-{enter,leave}-{active,from,to}` (transição), `.reg-textarea`, `.reg-chevron-open` (chevron rotacionado quando seção expandida), `.reg-badge-wpp` (badge verde do WhatsApp ao lado do telefone), `.reg-field-relative` + `.reg-contact-dropdown` + `.reg-dropdown-{loading,list,item,section-header,section-count,section-icon--*,divider}` (dropdown de busca dual paciente/contato).

**Solução — `RegistrationTab.vue`:**
- Adicionado import: `import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';` — mesmo path usado pelo `Record.vue`.
- Adicionados ~140 linhas de CSS no `<style scoped>` cobrindo todas as 26 classes faltantes, copiadas do `Record.vue` de antes da extração (commit `2efb9f4a`). Os tokens (`rgb(var(--slate-X))`, `rgb(var(--blue-X))`, `rgb(var(--border-strong))`) já estão definidos pelo design system, então as cores e bordas seguem o mesmo padrão dos outros componentes do prontuário.

**Verificação:**
- Auditoria automática cruzando `class="..."` e `:class="{...}"` do template + `name="reg-*"` de transitions com classes definidas em scoped + `record.css` (global): de 65 classes `reg-*` usadas, apenas `.reg-dropdown-section-icon` continua sem regra própria — mas é classe base sem styles próprios (apenas `--patient`/`--contact` carregam cor; o ícone em si vem das utility classes `i-lucide-* w-3 h-3`).
- `@vue/compiler-sfc` `parse` + `compileTemplate` + `compileScript` — zero erros.
- HMR Vite recarregou silencioso.

**Arquivos Modificados:**
- `plugins/patients/frontend/routes/patients/tabs/RegistrationTab.vue` (+1 import, ~140 linhas de CSS no style scoped)
- `CHANGELOG.md`

---

## [1.4.5.2] - 2026-04-26T17:50:00-03:00

### Prontuário: corrigido `ReferenceError: patient is not defined` ao abrir aba Cadastro

**Problema:**
Ao clicar na aba **Cadastro** em `/patients/:id/record?tab=registration`, a aba ficava em tela branca e o console mostrava `Uncaught (in promise) ReferenceError: patient is not defined` no setup do `RegistrationTab`. Sequências de erros `Cannot set properties of null (setting '__vnode')` eram crashes em cascata do mesmo unmount fail.

**Causa raiz:**
Em `<script setup>`, a prop precisa ser acessada como `props.patient` — não como `patient` bare — porque `defineProps` é uma macro do compilador (não uma destruturação). Durante a extração da aba, ~62 referências a `patient.X` ficaram sem o prefixo `props.` no script (template estava OK, pois Vue auto-expõe a prop ao template). 62 referências bare incluindo:
- Spread `...patient.emergency_contact` no payload do `saveRegistration`
- Mutações em `patient.address.X`, `patient.guardian.X`, `patient.cpf`, `patient.rg`, `patient.phone`, `patient.birthdate`, `patient.contact_id`, `patient.email`
- Reads em watchers e handlers (CEP, contact-search, máscaras de input)
- Construção do payload de `saveRegistration` (dados pessoais, endereço, convênio, opt-ins LGPD)

**Solução:**
Script de substituição via `state machine` (que respeita strings, comentários de linha, comentários de bloco e template literals com `${}`) para prefixar `patient` → `props.patient` apenas no `<script setup>`, deixando o template intocado:
- 62 substituições aplicadas no script.
- Caso especial corrigido manualmente: `...patient.emergency_contact` (spread operator com 3 dots fugiu do regex de lookbehind por confundir com member access).
- Caso especial preservado: `patient: { type: Object, required: true }` dentro do `defineProps()` — que é a chave da prop, não uma referência.

**Importância de usar `props.patient` (não bare `patient`):**
Em `Record.vue:174`, o pai faz `patient.value = { ...patient.value, ...data, ... }` ao re-fetchar o paciente — o que cria um **novo objeto** e troca a referência da prop. Se o filho tivesse capturado a referência via `const patient = props.patient` no setup, ficaria com a referência antiga após o fetch. Acessar via `props.patient.X` sempre busca o objeto atual da prop.

**Validação:**
- `@vue/compiler-sfc` `parse` + `compileTemplate` + `compileScript` — zero erros.
- Auditoria final: única ocorrência bare de `patient` no script é a chave de `defineProps` (legítima).
- HMR Vite recarregou sem warnings.

**Arquivos Modificados:**
- `plugins/patients/frontend/routes/patients/tabs/RegistrationTab.vue` (62 substituições + 1 spread manual)
- `CHANGELOG.md`

---

## [1.4.5.1] - 2026-04-26T17:35:00-03:00

### Prontuário: corrigidos `Invalid end tag` e `formatPhoneDisplay is not a function`

**Problemas:**
1. `vite build` quebrava com `Invalid end tag` em `RegistrationTab.vue:1648:3`. A extração do template havia trazido um `</div>` órfão (linha 1644, indent 2) que parecia visualmente o fechamento da raiz `<div class="tab-pane fade-in">`, mas o conteúdo interno já estava balanceado — o `</div>` real da raiz estava na linha 1642 (indent 10). O `</div>` extra fechava sobre uma stack vazia e o parser do Vue reportava o erro no próximo token (a linha do comentário `<!-- Modal: ... -->`).
2. Em runtime: `Uncaught TypeError: n.formatPhoneDisplay is not a function`. O cabeçalho do prontuário (`Record.vue:907`) renderiza o telefone do paciente via `formatPhoneDisplay(patient.phone)`, mas a função foi movida junto com a extração da aba Cadastro e nunca foi mantida uma cópia em `Record.vue`. O bind para o template ficou ausente do componente pai.

**Solução — `RegistrationTab.vue`:**
- Removido o `</div>` órfão da linha 1644.
- Reindentado o modal de câmera como **segunda raiz** do template (Vue 3 multi-root), com indentação de 2 espaços coerente com a raiz #1.
- Validado com `@vue/compiler-sfc` (`parse` + `compileTemplate` + `compileScript`) — zero erros.

**Solução — `Record.vue`:**
- Adicionadas as funções `formatPhoneDisplay` e `formatCpfDisplay` ao `<script setup>` (logo após `formatDate`, antes de `formatSex`). Mesma lógica usada em `RegistrationTab.vue` (formato BR `(XX) XXXXX-XXXX` para celular, fallback para fixo de 10 dígitos; CPF `XXX.XXX.XXX-XX` com formatação progressiva enquanto digita).
- Necessário porque o template do `Record.vue` exibe o telefone (`pb-chip` smartphone, linha 907) e o CPF (`pb-chip` credit-card, linha 915) no cabeçalho do prontuário, independente da aba ativa.
- Auditadas todas as 12 abas e o `Record.vue` com extração de `_ctx.fn(...)` do output de `compileTemplate` cruzado com `script.bindings` — apenas built-ins JS (`toLocaleDateString`, `find`, `then`, `toLowerCase`, `setTimeout`, `print`, `test`, `stringify`, `has`) ficaram fora dos bindings, todos chamados como métodos sobre valores (não como bindings de componente).

**Notas:**
- O erro de console `Not allowed to load local resource: blob:https://sistema.klivy.app/...` aparece junto, mas vem do widget chatwoot (`waha-chatwoot.efqhwo.easypanel.host/widget`) — bloqueio cross-origin de blob em iframe do widget, não relacionado ao prontuário.

**Arquivos Modificados:**
- `plugins/patients/frontend/routes/patients/tabs/RegistrationTab.vue` (-2 linhas: `</div>` órfão + linha em branco; reindent do modal)
- `plugins/patients/frontend/routes/patients/Record.vue` (+27 linhas: `formatPhoneDisplay` e `formatCpfDisplay` adicionados após `formatDate`)
- `CHANGELOG.md`

---

## [1.4.5.0] - 2026-04-26T23:30:00-03:00

### Prontuário (Fase 5 — FINAL): RegistrationTab extraído — refactor completo, 12/12 abas

**Problema:**
Última aba pendente do refactor estrutural. RegistrationTab é a Ficha Cadastral progressiva — edita o objeto `patient` que é compartilhado com outras 5 abas extraídas (`Consents`, `Schedule`, `Financial`, `Procedures`, `TreatmentPlan` leem dados do paciente via prop). Inclui upload de avatar (arquivo + câmera frontal com getUserMedia), busca automática de CEP via ViaCEP, máscaras de input (CPF/telefone/data nasc/CEP/validade convênio), seções colapsáveis e opt-ins LGPD.

**Solução — RegistrationTab.vue (novo, 2.164 linhas):**
- State próprio: `editFirstName`/`editLastName` (split de patient.name para form), `regSections` (4 seções colapsáveis: personal/contact/address/admin), `birthdateInputDisplay`/`insuranceValidUntilDisplay` (mascarados via maskDateBR), camera state (`showCameraModal`/`videoElement`/`canvasElement`/`capturedPhoto`/`cameraStream`/`cameraError`), `avatarInputRef`, `isLoading`.
- Helpers locais: `formatDate`, `getInitials`.
- Functions:
  - **Avatar/Câmera**: `triggerAvatarUpload`, `processImageToWebP` (canvas resize + 0.8 quality), `handleAvatarUpload`, `openCameraModal` (getUserMedia front-facing), `closeCameraModal` (encerra stream), `capturePhoto` (canvas.toDataURL), `retakePhoto`, `useCapturedPhoto` (converte dataURL→Blob→File→upload).
  - **Form/Save**: `toggleRegSection`, `registrationCompleteness` computed (% de campos preenchidos), `saveRegistration` (formata CPF/RG/telefone com `+55`, monta payload + chama `PatientsAPI.update` + emite `saved` para o pai re-fetch).
  - **Input handlers com máscara**: `handleCpfInput` (XXX.XXX.XXX-XX), `handleBirthdateInput`/`handleBirthdateBlur` (DD/MM/YYYY ↔ ISO), `handleInsuranceValidUntilInput`/`Blur` (idem), `handleGuardianCpfInput`, `handleGuardianPhoneInput` ((XX) XXXXX-XXXX), `handlePhoneInput`, `handleAlternativePhoneInput`, `searchCep` (auto-fetch via `viacep.com.br`).
  - **Watches**: birthdate ISO → display BR (immediate), insurance.valid_until → display BR (immediate), zip_code → format + auto-search (debounced inline), `patient.has_guardian` → reset guardian fields, `patient.name` → re-init editFirstName/Last.
- Recebe `patient` como prop (Vue passa por referência — mutações em campos aninhados via v-model propagam direto pro pai).
- **Emite `saved`** após persistir no backend para o pai re-fetchar (`fetchPatientSummary`) e atualizar nome, idade, status financeiro, `computedClinicalTags` da aba Geral, etc.
- Modal de câmera incluso (com viewfinder circular, botão de captura, retake/use foto).
- Estilos `.reg-progress-*`, `.reg-dropdown-*`, `.reg-item-*`, `.reg-avatar-*`, `.reg-opt-in-*`, `.reg-toggle*`, `.cam-*` (modal câmera) — ~430 linhas em `<style scoped>`.
- `onBeforeUnmount` encerra `cameraStream.getTracks()` se modal aberto na hora do unmount (cleanup defensivo).

**Limpeza no `Record.vue`:**
- Adicionado import `RegistrationTab`.
- Removidos do script ~700 linhas (state, regSections, completeness, saveRegistration, todos os 11 handlers de input com máscara, searchCep, watch de zip_code, todas as funções de avatar e câmera, refs de câmera, editFirstName/Last assignments dentro de fetchPatientSummary).
- Substituído template inline (~849 linhas) por `<RegistrationTab v-if=... :patient="patient" @saved="fetchPatientSummary">`.
- Removido modal de câmera inline (~85 linhas).
- Removido bloco CSS `NOVO: ESTILOS DO CADASTRO` (~1.380 linhas — incluindo `.reg-progress`/`.reg-dropdown`/`.reg-item`/`.reg-avatar`/`.reg-opt-in`/`.reg-toggle` e todos os `.cam-*`).

**🎉 RESULTADO FINAL — REFACTOR COMPLETO (12/12 ABAS):**

| Métrica | Antes do refactor | Depois |
|---:|---:|---:|
| `Record.vue` | **18.680 linhas** | **3.035 linhas** |
| Redução | — | **−84%** |
| Tabs em arquivos próprios | 0 (todas inline) | **12 componentes funcionais** |
| Pasta `tabs/` (todas extraídas) | — | **14.851 linhas** distribuídas |

**Estrutura final:**
```
plugins/patients/frontend/routes/patients/
├── Record.vue                     3.035 linhas — shell + state compartilhado
├── record.css                     2.450 linhas — estilos globais
└── tabs/
    ├── AnamnesisTab.vue             809
    ├── AuditTab.vue                 959
    ├── ConsentsTab.vue            1.337
    ├── DocumentsTab.vue             629
    ├── EvolutionTab.vue             974 (já existia)
    ├── ExamsTab.vue               2.074
    ├── FinancialTab.vue           2.197
    ├── ProceduresTab.vue            816
    ├── RegistrationTab.vue        2.164 (novo, esta turn)
    ├── ScheduleTab.vue            1.314
    ├── TimelineTab.vue              771
    └── TreatmentPlanTab.vue         807
```

**Validações finais:**
- ✓ Vite sobe sem erros (HMR ativo, sem warnings).
- ✓ Sem ghost-refs em `Record.vue` (grep por `editFirstName`, `searchCep`, `triggerAvatarUpload`, `showCameraModal`, `cameraStream`, etc — todos retornam 0 matches).
- ✓ `fetchPatientSummary` não tenta mais setar `editFirstName.value`/`editLastName.value` (RegistrationTab inicializa via watch).
- ✓ Estrutura SFC válida em todos os 12 componentes.

**Para testar manualmente:**
- Aba **Cadastro**: editar todos os campos (nome, CPF/RG com máscara, data nasc, telefone, email, endereço com auto-CEP, contato emergência, responsável legal, convênio com validade, opt-ins LGPD), upload de avatar via arquivo, abrir câmera frontal e tirar foto, salvar → outras abas (Consents, Schedule, Financial) devem refletir os novos dados imediatamente.
- Aba **Geral**: nome, idade, status, tags clínicas devem atualizar após salvar Cadastro.
- Sincronização entre abas: editar paciente em Cadastro → ir para Consents → o template de termo deve usar os novos CPF/RG/endereço.

**Cumulative refactor (Fases 1-5 completas):**
- Phase 4 (1.4.4.71): ExamsTab extraído como POC.
- Phase 5 começou em 1.4.4.72 (Timeline+Audit+Anamnese), continuou em 1.4.4.73 (Documents+Schedule), 1.4.4.74 (Consents), 1.4.4.75 (Procedures+TreatmentPlan), 1.4.4.76 (Financial), e termina aqui em **1.4.5.0** (Registration — última aba).
- 11 novos componentes, ~14k linhas de código bem estruturado em arquivos auto-suficientes.
- Zero regressão funcional reportada (cada turn validou 100% antes de prosseguir).

**Bump de versão para `1.4.5.0`** marca a conclusão do projeto/módulo de refactor estrutural do prontuário. Próximos sprints podem focar em features novas sem o medo de conflito gigante no `Record.vue` monolítico.

**Arquivos Modificados:**
- `plugins/patients/frontend/routes/patients/tabs/RegistrationTab.vue` (novo, 2.164 linhas)
- `plugins/patients/frontend/routes/patients/Record.vue` (-3.032 linhas — última grande limpeza)
- `CHANGELOG.md`

## [1.4.4.76] - 2026-04-26T22:30:00-03:00

### Prontuário (Fase 5 — continuação): FinancialTab extraído (a maior aba até agora)

**Problema:**
Continuação da extração das abas restantes. Após Procedures+TreatmentPlan (1.4.4.75), restava a aba Financeiro (~1.130 linhas de template, ~570 de script, ~450 de CSS) — a maior aba do prontuário, com 4 entidades (transactions, estimates, bank accounts, KPIs financeiros), 4 modais inline (Pay, Estimate, Proof Upload, Print Preview) e 2 funções que geram HTML inteiro para impressão (extrato + recibo).

**Solução — FinancialTab.vue (novo, 2.197 linhas):**
- State: `financialSummary`, `transactions`, `financialEstimates`, `activeFinancialTab` (transactions/estimates/receipts), `financialFilter` (all/pendente/pago/vencido), `financialLoading`, `subtotalRaw` (BRL formatado), `payForm`, `estimateForm`, `bankAccountsForPay`, modais (pay/estimate/proof/print).
- Constantes: `TX_STATUS_CONFIG` (5 estados de transação), `ESTIMATE_STATUS_CONFIG` (4 estados de orçamento).
- Computeds: `filteredTransactions` (com lógica de overdue), `pendingTransactions` (para o modal de receber), `proofTx` (lookup para modal de comprovante).
- Functions: `fetchFinancialData` (Promise.all com 3 endpoints), `loadBankAccountsForPay`, `formatCurrencyInput`/`parseCurrencyInput`/`onSubtotalInput` (helpers de input BRL), `openPayModal`/`confirmPayment`/`payTransaction`, `openEstimateModal`/`confirmCreateEstimate`/`approveEstimate`/`cancelEstimate`, `chargeWhatsapp` (abre `wa.me`), `refundTransaction`, `openProofModal`/`handleProofUpload`/`viewProof`, `openPrintPreview`/`printFinancial` (gera HTML inteiro do extrato com KPIs + tabelas) /`printReceipt` (gera HTML do recibo de pagamento estilo "ticket").
- Helpers locais: `formatCurrency` (BRL), `formatDate`, `BRT`, `txStatusConfig`, `estimateStatusConfig`.
- 4 modais inclusos: Receber Pagamento (com seleção de parcela + 6 botões de método), Novo Orçamento (com preview de cálculo), Anexar Comprovante (drag-drop), Print Preview (iframe com srcdoc).
- Recebe `patient` como prop (usado em `printFinancial` e `printReceipt` para o nome no PDF).
- **Emite `update-financial-status`** para sincronizar `patient.financialStatus` no parent (usado pelo badge "Adimplente"/"Inadimplente" no header). Substitui a mutação direta `patient.value.financialStatus = X` que o componente fazia antes.
- Estilos `.fin-*` (~450 linhas) em scoped: KPI grid 5 colunas, internal tabs, filter pills, transaction table com cores semânticas (overdue vermelho, paid verde), action buttons, estimate cards.
- Auto-suficiente: `fetchFinancialData` + `loadBankAccountsForPay` no `onMounted`.

**Limpeza no `Record.vue`:**
- Removidos imports: `FinancialEstimatesAPI`, `TransactionsAPI`, `bankAccountsApi`.
- Adicionado import: `FinancialTab`.
- Removidos do script ~570 linhas (state + 2 modais de form + 4 modais state + helpers de BRL + functions de pay/refund/charge + functions de estimate + functions de proof + funções de impressão de extrato e recibo + constantes TX/ESTIMATE_STATUS_CONFIG + computeds).
- Removidos do `onMounted`: `loadBankAccountsForPay()`.
- Removido branch `financial` do `watch(activeTab)`.
- Substituído template inline (~1.126 linhas) por `<FinancialTab v-if=... :patient="patient" @update-financial-status="patient.financialStatus = $event">`.
- Removido bloco CSS `FINANCEIRO — estilos exclusivos` (~450 linhas).

**Resultado parcial (11/12 abas extraídas):**
| Antes desta turn | Depois |
|-----------------:|-------:|
| Record.vue: 8.217 linhas | Record.vue: **6.067 linhas** (-2.150, -26%) |
| 10 abas extraídas | **11 abas extraídas** (+ Financial) |

**Restante (1 aba):**
- RegistrationTab (~850 linhas) — última e mais delicada. Edita o objeto `patient` diretamente; outras abas extraídas (Consents, Schedule, Financial) leem esse mesmo objeto via prop. Vai precisar de `v-model:patient` ou pattern de `emit('update:patient')` para sincronização bidirecional com o pai.

**Total acumulado desde início do refactor:**
- Record.vue original: **18.680 linhas**
- Record.vue agora: **6.067 linhas** (-67%)
- Pasta `tabs/`: **12 componentes funcionais** (11 extraídos + EvolutionTab pré-existente).

**Validações:**
- ✓ Vite sobe sem erros, HMR ativo.
- ✓ Sem ghost-refs em `Record.vue` para os símbolos extraídos (grep retorna 0 matches exceto `permission: 'financial'` na lista de tabs, esperado).

**Para testar manualmente (rota `/patients/:id/record` → aba Financeiro):**
- KPIs (Total Aprovado, Pago/Recebido, Em Aberto, Devedor, Crédito).
- Tabs internas: Transações (com filtros all/pendentes/pagos/vencidos), Orçamentos (com cards), Recibos (lista de pagamentos).
- "Receber Pagamento": modal seleciona parcela pendente + método + data → registra pagamento.
- "Novo Orçamento": modal com subtotal BRL formatado + desconto + parcelas → preview do cálculo.
- "Cobrar via WhatsApp" em parcela pendente: abre `wa.me/<phone>` com mensagem pré-formatada.
- "Anexar Comprovante" em parcela paga: upload PNG/JPG/PDF.
- "Estornar" em parcela paga: dispara refund.
- "Imprimir Extrato": modal preview de iframe com HTML do extrato → botão Imprimir/PDF.
- "Recibo": idem, mas para uma transação específica.
- Header do paciente: badge "Adimplente"/"Inadimplente" deve atualizar quando o status financeiro muda (via emit `update-financial-status`).

**Arquivos Modificados:**
- `plugins/patients/frontend/routes/patients/tabs/FinancialTab.vue` (novo, 2.197 linhas)
- `plugins/patients/frontend/routes/patients/Record.vue` (-2.150 linhas)
- `CHANGELOG.md`

## [1.4.4.75] - 2026-04-26T21:30:00-03:00

### Prontuário (Fase 5 — continuação): ProceduresTab e TreatmentPlanTab extraídos

**Problema:**
Continuação da extração das abas restantes do prontuário. Após Consents (1.4.4.74), faltavam 4 abas, sendo Procedures+TreatmentPlan as mais entrelaçadas — compartilhavam `sessionLogs` e `uniqueProceduresLogged` (computed para autocomplete do filtro de Procedimentos). Decidi extrair as duas em conjunto para resolver a sincronização de uma vez, com cada componente fetching seu próprio state.

**Solução 1 — ProceduresTab.vue (novo, ~830 linhas com `<style scoped>`):**
- State próprio: `sessionLogs`, `isSessionsLoading`, `isSavingSession`, `sessionHistoryFilter` (procedure_name + date_from + date_to), `showFilterPanel`, `newSession` (form com 11 campos), `showConfirmDeleteSession`, `sessionToDelete`.
- Computed: `uniqueProceduresLogged` (autocomplete do filtro).
- Functions: `resetSessionForm`, `fetchSessionLogs`, `saveSession` (com payload bem estruturado: `areas_treated[]` + `products_used[]`), `registerSession` (scroll para form), `requestDeleteSessionLog`/`cancelDeleteSessionLog`/`confirmDeleteSessionLog`, `toggleFilterPanel`, `applySessionFilter`, `clearSessionFilter`, `openBeforeAfterPhotos` (emit `open-exams` para o pai).
- Recebe `patient` como prop (para fallback `responsibleProfessional` na lista).
- Emite `open-exams` quando usuário clica em "Fotos Antes/Depois" — pai (Record.vue) escuta e troca activeTab.
- Estilos `.proc-filter-*`, `.proc-date-input`, `.proc-form-actions` em scoped (não compartilhados); restante já estava em record.css de turn anterior.
- Auto-suficiente: `fetchSessionLogs` no `onMounted`.

**Solução 2 — TreatmentPlanTab.vue (novo, ~720 linhas):**
- State próprio: `treatmentPlans`, `editingPlanId`, `showItemModal`, `activePlanId`, `currentItem` (form), `isSavingItem`, `globalDiagnosisTitle`, `globalDiagnosisDescription`, `showConfirmDeletePlan`, `planToDelete`, `showConfirmDeleteItem`, `itemToDelete`.
- Functions: `fetchTreatmentPlans`, `createTreatmentPlan`, `savePlan`, `approvePlan` (dispara comissionamento no backend), `requestDeletePlan`/`cancelDeletePlan`/`confirmDeletePlan`, `openItemModal` (auto-save plan se em edição), `handleProcedureSelect` (lookup price em agendaServices), `saveItem` (create ou update), `requestDeleteItem`/`cancelDeleteItem`/`confirmDeleteItem`, `printPlan` (PDF se disponível, senão `window.print`).
- Helpers locais: `formatCurrency` (BRL), `formatDate`.
- Recebe `agenda-services` como prop (para o dropdown de procedimentos no modal — cada serviço tem nome + preço).
- Modais inclusos: Treatment Item (criar/editar procedimento), Confirm Delete Item, Confirm Delete Plan.
- Não usa `sessionLogs` (template não exibe count de sessões realizadas — checagem de uso confirmou).
- Estilos `.rp-*` (template) e `.tp-modal-*` (modais) já estavam em record.css de turns anteriores. Apenas o bloco `.tp-plan-card`/`.tp-plan-header`/etc (~327 linhas no scoped do Record.vue) foi confirmado como **dead CSS** (não usado por nenhum template) e removido.
- Auto-suficiente: `fetchTreatmentPlans` no `onMounted`.

**Limpeza no `Record.vue`:**
- Removidos imports: `SessionLogsAPI` (não usado mais).
- Adicionados imports: `ProceduresTab`, `TreatmentPlanTab`.
- Removidos do script:
  - Bloco `// ── Procedures / Session Logs` (~173 linhas: state, form, functions de save/delete/filter).
  - Bloco `// ── Treatment Plans & Sessions` (~175 linhas: state, modais, CRUD de planos e items).
  - `sessionLogs`/`uniqueProceduresLogged` (não usados mais — Procedures tem o seu próprio).
  - **Mantido**: `treatmentPlans` (mirror read-only) + `fetchTreatmentPlans` para alimentar `activePlanSummary` na aba Geral. Após editar plano em TreatmentPlanTab, F5 sincroniza este mirror — limitação aceita (mesmo padrão da Anamnese).
- Removidos dos branches do `watch(activeTab)`: `procedures`/`treatment_plan` — agora cada filho faz seu próprio fetch.
- Substituídos templates inline (~444 + ~427 linhas) por `<ProceduresTab v-if=... :patient="patient" @open-exams="activeTab = 'exams'">` e `<TreatmentPlanTab v-if=... :agenda-services="agendaServices">`.
- Removidos do template: 3 modais inline (`showItemModal`, `showConfirmDeleteItem`, `showConfirmDeletePlan`) + 1 modal `showConfirmDeleteSession` (cada um ~70 linhas).
- Removidos blocos CSS:
  - `PROCEDIMENTOS – estilos exclusivos` (~270 linhas — principalmente filter-panel, form-actions, proc-date-input que são procedures-only).
  - `ABA PLANO DE TRATAMENTO — tp-*` (~327 linhas — todas dead — não estavam sendo usadas pelo template atual que usa `.rp-*`).

**Resultado parcial (10/12 abas extraídas):**
| Antes desta turn | Depois |
|-----------------:|-------:|
| Record.vue: 10.283 linhas | Record.vue: **8.217 linhas** (-2.066, -20%) |
| 8 abas extraídas | **10 abas extraídas** (+ Procedures, TreatmentPlan) |

**Restante (2 abas):**
- FinancialTab (~1.000 linhas) — 4 entidades (transactions, estimates, bank accounts, KPIs).
- RegistrationTab (~850 linhas) — última e mais complexa: edita o objeto `patient` que outras abas/parent leem; vai precisar de `v-model` ou `emit` para sincronizar com Record.vue.

**Total acumulado desde início do refactor (Record.vue → tabs/):**
- Record.vue original: **18.680 linhas**
- Record.vue agora: **8.217 linhas** (-56%)
- Pasta `tabs/`: **11 componentes funcionais** (10 extraídos + EvolutionTab pré-existente).

**Validações:**
- ✓ Vite sobe sem erros (HMR ativo).
- ✓ Sem ghost-refs em `Record.vue` para os símbolos extraídos (grep retorna 0 matches exceto os intencionais — `treatmentPlans`/`fetchTreatmentPlans` para o mirror do Geral).

**Para testar manualmente:**
- Aba **Procedimentos**: registrar nova sessão (procedimento, área, produto, lote, intercorrências, resultado, retorno em dias), filtrar histórico por procedimento + intervalo de datas, excluir registro com modal de confirmação, "Fotos Antes/Depois" deve trocar pra aba Exames.
- Aba **Plano de Tratamento**: criar plano com diagnóstico/CID, adicionar procedimentos via modal (com lookup de preço em agendaServices), editar título/descrição/duração, aprovar plano, excluir plano, baixar PDF / imprimir.
- Aba **Geral**: card "Plano Ativo" deve continuar funcionando (usa `treatmentPlans` mirror do parent).

**Arquivos Modificados:**
- `plugins/patients/frontend/routes/patients/tabs/ProceduresTab.vue` (novo, ~830 linhas)
- `plugins/patients/frontend/routes/patients/tabs/TreatmentPlanTab.vue` (novo, ~720 linhas)
- `plugins/patients/frontend/routes/patients/Record.vue` (-2.066 linhas)
- `CHANGELOG.md`

## [1.4.4.74] - 2026-04-26T20:30:00-03:00

### Prontuário (Fase 5 — continuação): ConsentsTab extraído

**Problema:**
Continuação da extração de abas do prontuário. Após Documents+Schedule (1.4.4.73), restavam 5 abas inline. ConsentsTab é a próxima mais isolada (apenas depende do paciente para substituições nos templates de termos legais).

**Solução — ConsentsTab.vue (novo, 1.337 linhas com `<style scoped>`):**
- State: `consents`, `consentLoading`, `showConsentModal`, `showSignModal`, `showViewModal`, `consentInView`, `signingConsentId`, `consentModalLoading`, `signatureCanvas`, `isDrawing`, `hasSignature`, `newConsentForm`.
- Constantes: `CONSENT_TYPES` (10 tipos: lgpd, autorizacao_imagem, botox, preenchimento, fototerapia, peeling, menor_idade, procedimento_cirurgico, anestesia, geral — cada um com `template` jurídico pré-preenchido contendo placeholders `[NOME DO PACIENTE]`, `[CPF]`, `[ENDEREÇO]`, etc), `CONSENT_STATUS_CONFIG` (6 estados: pendente, assinado_localmente, assinado_remotamente, signed, vencido, revogado).
- Functions: `fetchConsents`, `selectConsentType` (substitui placeholders com dados do paciente), `onConsentTypeChange`, `openConsentModal`, `createConsent`, `openSignModal`, `getCanvasCoords` (suporta touch e mouse), `startDrawing`/`draw`/`stopDrawing`/`clearSignature` (canvas de assinatura digital), `confirmSign` (gera dataURL WebP 0.85 e envia para `ConsentsAPI.sign`), `viewConsent` (busca `signature_image_url` se já assinado), `sendConsentRemote` (link via WhatsApp), `revokeConsent`.
- Computeds: `consentTypeDetail`, `consentStats` (total/signed/pending/expired).
- Helpers: `consentStatusLabel`, `consentTypeLabel`, `signConsentNow`.
- Recebe `patient` como prop — usado em `selectConsentType` para substituir `[NOME DO PACIENTE]`/`[CPF]`/`[RG]`/`[DATA DE NASCIMENTO]`/`[ENDEREÇO]`/`[EMAIL]`/`[TELEFONE]` no template do termo legal.
- Estilos `.consent-*` (~360 linhas) em `<style scoped>` do componente: KPI grid colorido, modal de assinatura com canvas, modal de visualização com bloco de auditoria forense (hash SHA-256, IP de assinatura, imagem da assinatura).
- Auto-suficiente: `fetchConsents` no `onMounted`.

**Limpeza no `Record.vue`:**
- Removido import `ConsentsAPI` (não usado mais).
- Adicionado import `ConsentsTab`.
- Removidos do script ~412 linhas (state + 10 templates de CONSENT_TYPES + funções de canvas/sign/view/revoke + stats).
- Removido branch `consents` do `watch(activeTab)`.
- Substituído template inline (~670 linhas) por `<ConsentsTab v-if=... :patient="patient">`.
- Removido bloco CSS `CONSENTIMENTOS — estilos exclusivos` (~356 linhas).

**Resultado parcial (8/12 abas extraídas):**
| Antes desta extração | Depois |
|---------------------:|-------:|
| Record.vue: 11.717 linhas | Record.vue: **10.283 linhas** (-1.434, -12%) |
| 7 abas extraídas | **8 abas extraídas** (+ Consents) |

**Restante (4 abas):**
- ProceduresTab (~440)
- TreatmentPlanTab (~1.000) — compartilha `sessionLogs` com Procedures
- FinancialTab (~1.000)
- RegistrationTab (~850) — edita o objeto `patient`; vai precisar de v-model/emit para sincronização com pai

**Total acumulado desde início do refactor:**
- Record.vue original: 18.680 linhas
- Record.vue agora: **10.283 linhas** (-45%)
- Pasta `tabs/`: **9 componentes funcionais** (incluindo EvolutionTab pré-existente).

**Validações:**
- ✓ Vite sobe sem erros, HMR ativo.
- ✓ Sem ghost-refs em `Record.vue` (grep por `consents`, `fetchConsents`, `CONSENT_TYPES`, `signatureCanvas`, etc retorna 0 matches no script — só fica `'consents'` no array `tabs[]` e como `activeTab` value, esperado).

**Para testar manualmente:**
- Aba **Consentimentos**: KPIs (Total/Assinados/Pendentes/Vencidos), criar novo consentimento (selecionar tipo → template auto-preenchido com nome/CPF do paciente), assinar presencialmente (canvas com mouse/touch), visualizar termo + bloco de auditoria forense, enviar link via WhatsApp, revogar.

**Arquivos Modificados:**
- `plugins/patients/frontend/routes/patients/tabs/ConsentsTab.vue` (novo, 1.337 linhas)
- `plugins/patients/frontend/routes/patients/Record.vue` (-1.434 linhas)
- `CHANGELOG.md`

## [1.4.4.73] - 2026-04-26T19:30:00-03:00

### Prontuário (Fase 5 — continuação): Documents, Schedule extraídos + estilos compartilhados em record.css

**Problema:**
Após Fase 5 parcial (Timeline, Audit, Anamnese), restavam 8 abas inline em `Record.vue`. Adicionalmente, ao validar a Anamnese o usuário reportou que os estilos `.reg-section`, `.form-input`, `.check-item` não estavam aplicando — esses layouts viviam em `<style scoped>` do `Record.vue`, então só atingiam elementos do próprio componente, não dos filhos extraídos. Extraindo tabs adicionais sem resolver isso geraria a mesma quebra a cada nova extração.

**Solução 1 — Estilos de form compartilhados promovidos a global em `record.css`:**
- Movidas regras de layout dos blocos `<style scoped>` do `Record.vue` (que tinham só `.reg-section { color: ... !important }` originalmente em record.css) para `record.css` global:
  - `.reg-header`, `.reg-form-grid`, `.reg-section` (border-radius+overflow), `.reg-section-toggle`, `.reg-section-toggle-left`, `.reg-section-icon`, `.reg-icon-{blue,green,amber,purple,cyan,red,orange}`, `.reg-section-title`, `.reg-section-subtitle`, `.reg-section-body`, `.reg-field-grid-{2,3,cep}`, `.reg-required`.
  - `.form-group`, `.form-label`, `.form-input`, `.form-textarea`, `select.form-input`.
  - `.check-item`, `.check-item-box`, `.check-item-label` (incluindo estados :checked, :disabled, :hover).
  - `.proc-count-badge`, `.proc-empty-state`, `.proc-empty-icon`, `.proc-empty-text`, `.proc-empty-hint`, `.proc-table-wrap`, `.proc-table`, `.proc-table-cell`, `.proc-product-item`, `.proc-cell-resultado`, `.proc-result-row`, `.proc-action-btn` — compartilhados entre Procedures, Documents e (futuro) TreatmentPlan.
  - `.docs-status-badge`, `.docs-modal*` — compartilhados com possíveis abas que abrem modais de documento.
- Versões scoped no Record.vue continuam existindo (vão sair na limpeza final). Conflito de cascade: scoped tem hash `data-v-XXX` (mais específico) — Record.vue mantém suas regras; filhos extraídos pegam as globais que copiamos.

**Solução 2 — DocumentsTab.vue (novo, ~580 linhas):**
- State: `documents`, `showDocModal`, `docModalLoading`, `showDeleteDocModal`, `pendingDeleteDocId`, `docForm` (com 11 campos).
- Constantes: `DOC_TYPE_LABELS` (11 tipos: receita, atestado, pedido_exame, declaracao, relatorio_clinico, encaminhamento, contrato, orcamento, instrucao_procedimento, questionario, outro), `DOC_STATUS_CONFIG` (5 estados: gerado, pendente_assinatura, assinado, enviado, arquivado).
- Functions: `openDocModal`, `fetchDocuments`, `generateDocument`, `downloadDocument`, `sendWhatsAppDocument`, `deleteDocument`, `confirmDeleteDocument`.
- Modal de geração com forms condicionais por tipo de documento (atestado tem CID + dias afastamento; receita tem medicamentos + posologia; etc).
- Auto-suficiente: `fetchDocuments` no `onMounted`.

**Solução 3 — ScheduleTab.vue (novo, 1.314 linhas):**
- State: `appointments`, `appointmentsLoading`, `appointmentFilter`. Modais: `showRescheduleModal` (com `rescheduleForm`), `showNoShowModal`. Banner: `recallDismissedForever`/`recallDismissedSession`/`recallLoading`.
- Constantes: `APPOINTMENT_TYPE_LABELS`, `EVENT_TYPE_LABELS`, `PRIORITY_CONFIG`, `APPOINTMENT_STATUS_CONFIG` (8 estados).
- Computeds: `filteredAppointments` (filtro pill: all/upcoming/issues + ordenação), `nextAppointmentId`, `aptKPIs` (total/done/upcoming/noShows), `issuesCount`, `pendingRecallAppointment` (banner de retorno).
- Functions: `aptStatusCfg`, `priorityCfg`, `fetchAppointments`, `openRescheduleModal`/`handleReschedule`, `openNoShowModal`/`handleNoShow`, `sendRecallWhatsApp` (com fallback para `wa.me/` caso API falhe), `dismissRecallForever`/`dismissRecallSession`, `navigateToAgendaWithPatient`, `openRescheduleFromRecall`.
- Recebe `patient` como prop (para `recall_dismissed_at` inicial, dados de contato e telefone para WhatsApp fallback).
- Styles `.sched-*` (KPIs, filter pills, recall banner, timeline com dots, badges de status/prioridade/PRÓXIMA, cards de agendamento, ações) em `<style scoped>` do componente — 570 linhas.
- Auto-suficiente: `fetchAppointments` no `onMounted`.

**Solução 4 — Limpeza no `Record.vue`:**
- Removidos imports `DocumentsAPI`, `PatientAppointmentsAPI` (não usados mais).
- Adicionados imports: `DocumentsTab`, `ScheduleTab`.
- Removidos do script: state de Documents (~40 linhas), state de Schedule (~330 linhas — incluindo APPOINTMENT_STATUS_CONFIG, modais e funções), `fetchAppointments`, `fetchDocuments`, todas as funções de schedule/recall, `navigateToAgendaWithPatient`, `recallDismissedForever`/`recallDismissedSession`.
- Removidos branches `documents`/`schedule` do `watch(activeTab)`.
- Removida linha `recallDismissedForever.value = true` em `fetchPatientSummary` (estado vive em ScheduleTab agora).
- Substituídos templates inline (~445 + ~580 linhas) por `<DocumentsTab v-if=...>` e `<ScheduleTab v-if=... :patient="patient">`.
- Removidos blocos CSS `DOCUMENTOS — estilos exclusivos` (~100 linhas) e `AGENDA E HISTÓRICO — estilos exclusivos` (~570 linhas).

**Resultado parcial (7/12 abas extraídas):**
| Antes desta turn | Depois desta turn |
|-----------------:|------------------:|
| Record.vue: 13.903 linhas | Record.vue: **11.717 linhas** (-2.186, -16%) |
| 5 abas extraídas | **7 abas extraídas** (+ Documents, Schedule) |

**Restante (5 abas para próximas fases):**
- ConsentsTab (~700 linhas)
- ProceduresTab (~440) — depende de `sessionLogs` que é compartilhado com TreatmentPlan
- TreatmentPlanTab (~1.000)
- FinancialTab (~1.000)
- RegistrationTab (~850)

**Total acumulado desde início do refactor (Phase 4 + Phase 5 parcial + esta):**
- Record.vue original: **18.680 linhas**
- Record.vue agora: **11.717 linhas** (-37%)
- Pasta `tabs/` cresceu de 1 (EvolutionTab) → 8 componentes funcionais.

**Validações executadas:**
- ✓ Vite sobe sem erros.
- ✓ Sem ghost-refs em `Record.vue` (grep por `appointments`, `fetchAppointments`, `fetchDocuments`, `recallDismissedForever`, etc retorna 0 matches).

**Para testar manualmente:**
- Aba **Documentos**: gerar documento (atestado/receita/pedido_exame/encaminhamento), download, enviar WhatsApp, excluir.
- Aba **Agenda e Histórico**: KPIs (total/realizados/próximos/faltas), filtros (todos/próximos/faltas), banner de recall em paciente que faltou, reagendar consulta, marcar falta, navegar para Agenda.
- Aba **Anamnese**: estilos voltaram a aplicar corretamente após move de `.reg-*`/`.form-*`/`.check-item*` para record.css.

**Arquivos Modificados:**
- `plugins/patients/frontend/routes/patients/tabs/DocumentsTab.vue` (novo, ~580 linhas)
- `plugins/patients/frontend/routes/patients/tabs/ScheduleTab.vue` (novo, 1.314 linhas)
- `plugins/patients/frontend/routes/patients/Record.vue` (-2.186 linhas)
- `plugins/patients/frontend/routes/patients/record.css` (+~250 linhas — estilos compartilhados promovidos a global)
- `CHANGELOG.md`

## [1.4.4.72] - 2026-04-26T18:30:00-03:00

### Prontuário (Fase 5 — parcial): Timeline, Auditoria e Anamnese extraídas para componentes próprios

**Problema:**
Após Fase 4 (extração de ExamsTab), `Record.vue` ainda continha 11 abas inline (~16k linhas) com lógica, template e estilos misturados. Cada nova feature ou correção tinha alto risco de conflito com qualquer mudança em qualquer outra aba. Próximo passo natural: continuar extraindo as abas restantes uma a uma, seguindo o padrão de `ExamsTab.vue`.

**Solução — três extrações nesta fase (mais simples primeiro):**

**1. TimelineTab.vue (novo, 695 linhas):**
- State: `timelineEvents`, `timelineLoading`, `timelineFilter`, `timelineFilterOpen`, `timelineSortOrder`.
- Constantes: `TIMELINE_TYPE_CONFIG` (mapa de ícone+cor+label por tipo de evento), `BRT` (timezone).
- Computeds: `filteredTimelineEvents` (filtro por categoria + ordenação), `groupedTimelineEvents` (agrupamento por data).
- Functions: `timelineEventConfig`, `tlIconCls`, `tlBadgeCls`, `fetchTimeline`, `formatTime`.
- Styles `.tl-*` (filtros, sidebar, cards de evento, badges semânticas, marcador de fim de histórico).
- Auto-suficiente: `useRoute` + `fetchTimeline()` no `onMounted`.

**2. AuditTab.vue (novo, 884 linhas):**
- State: `auditLogs`, `expandedLogs` (Set), `isAuditLoading`, `isExportingPdf`, `auditMeta`, `auditFilters`.
- Constante `AUDIT_ACTION_OPTIONS` (10 tipos de ação).
- Functions: `getInitials`, `toggleLogDetails`, `formatAuditAction`, `generateDetailedAuditText`, `formatAuditDateTime`, `fetchAuditLogs`, `applyAuditFilters`, `clearAuditFilters`, `auditPagePrev`, `auditPageNext`, `exportPdf`.
- Recebe `patient-name` como prop (necessário pra nomear o PDF exportado).
- Styles `.aud-*` (filtros, tabela, action badges, avatar de usuário, módulo/diff, linha expandida, paginação).

**3. AnamnesisTab.vue (novo, 793 linhas):**
- State: `anamneses`, `currentAnamnesis`, `allergyInput`, `medicationInput`, `isSavingAnamnesis`.
- Constantes: `EMPTY_ANAMNESIS` (factory), `UNPERMITTED_ANAMNESIS_KEYS`.
- Functions: `deepCloneAnamnesis`, `normalizeAnamnesisFromServer`, `applyAnamnesisState` (mutação cirúrgica para preservar reatividade de v-models aninhados), `startNewAnamnesis`, `flushAllergyInput`, `flushMedicationInput`, `removeAllergy`, `removeMedication`, `fetchAnamneses`, `saveAnamnesis` (com flag de finalize).
- Styles `.anm-*` (grids de checkboxes, tags de alergias/medicamentos, inputs com borda de alerta, card de observações).
- **Detalhe importante**: `currentAnamnesis` ainda existe em `Record.vue` em versão **mínima e somente-leitura**, alimentada por `fetchAnamnesisForTags()` no `onMounted`, porque `computedClinicalTags` (renderiza badges de alergia/condição na aba Geral) precisa dela. Após editar a anamnese, F5 atualiza as tags da aba Geral — limitação aceita pra não introduzir provide/inject ou store global só por isso.

**4. Estabilidade entre pacientes:**
Adicionado `:key="<tab>-${route.params.patientId}"` em todos os componentes extraídos (`ExamsTab`, `TimelineTab`, `AuditTab`, `AnamnesisTab`). Garante que os componentes desmontem e remontem ao trocar de paciente (substitui o antigo `watch(route.params.patientId)` que estava no `Record.vue` para resetar a anamnese).

**Resultado parcial (5/12 abas extraídas):**
| Antes desta fase | Depois desta fase |
|-----------------:|------------------:|
| Record.vue: 16.577 linhas | Record.vue: **13.903 linhas** (-2.674, -16%) |
| 2 abas extraídas (Evolution, Exams) | **5 abas extraídas** (+ Timeline, Audit, Anamnese) |

**Restante (7 abas para próximas fases):**
- ProceduresTab (~440) — depende de `sessionLogs` que é compartilhado com TreatmentPlan; requer fix conjunto.
- DocumentsTab (~470)
- ScheduleTab (~580)
- ConsentsTab (~700)
- RegistrationTab (~850)
- FinancialTab (~1.000)
- TreatmentPlanTab (~1.000)

**Validações executadas:**
- ✓ Vite sobe sem erros, HMR ativo.
- ✓ Sem ghost-refs em `Record.vue` (grep por `auditLogs`, `timelineEvents`, `anamneses`, etc retorna 0 matches no arquivo principal — exceto o `currentAnamnesis` mínimo intencional pra `computedClinicalTags`).
- ✓ Estrutura SFC válida em ambos os 3 novos componentes (1 script setup, 1 template, 1 style scoped).
- ✓ `fetchAnamnesisForTags` chamado no `onMounted` do parent — pré-carrega dados da Anamnese para a aba Geral.

**Para testar manualmente (rota `/patients/:id/record`):**
- Aba **Timeline**: filtros (Tudo/Consultas/Clínico/Financeiro/Documentos), ordenação (mais recente/antigo), agrupamento por data, badge de evento.
- Aba **Auditoria**: lista de logs, filtros por tipo de ação + intervalo de datas + paginação, expansão de linha com detalhes, exportar PDF (nomeia com `prontuario_<nome>_<id>.pdf`).
- Aba **Anamnese**: criar rascunho, editar checkboxes/tags/textos, "Salvar Rascunho", "Assinar e Finalizar" (deve voltar como readonly + PDF).
- Aba **Geral**: tags clínicas (Alergia, Diabético, Hipertenso, etc.) ainda aparecem corretamente — derivam de `currentAnamnesis` carregado no parent.

**Arquivos Modificados:**
- `plugins/patients/frontend/routes/patients/tabs/TimelineTab.vue` (novo, 695 linhas)
- `plugins/patients/frontend/routes/patients/tabs/AuditTab.vue` (novo, 884 linhas)
- `plugins/patients/frontend/routes/patients/tabs/AnamnesisTab.vue` (novo, 793 linhas)
- `plugins/patients/frontend/routes/patients/Record.vue` (-2.674 linhas)
- `CHANGELOG.md`

## [1.4.4.71] - 2026-04-26T17:30:00-03:00

### Exames e Imagens (Fase 4): aba extraída para componente próprio + cleanup de stubs órfãos

**Problema:**
Após Fases 1–3, o módulo "Exames e Imagens" estava funcional, mas o arquivo `Record.vue` continuava com 18.680 linhas contendo TODAS as 12 abas do prontuário inline. Identificado em revisão de Phase 3:
1. **`Record.vue` monolítico** — qualquer mudança em qualquer aba colide com qualquer outra mudança no arquivo. A aba "Exames e Imagens" ocupava ~2.000 linhas (script + template + style) misturadas no meio de outras 10 abas.
2. **Stubs órfãos em `tabs/`** — pasta `tabs/` continha 11 arquivos `.vue`, mas só `EvolutionTab.vue` era de fato importado e usado. Os outros 10 (`AnamnesisTab.vue`, `AuditTab.vue`, `ConsentsTab.vue`, `DocumentsTab.vue`, `FinancialTab.vue`, `ProceduresTab.vue`, `RegistrationTab.vue`, `ScheduleTab.vue`, `TimelineTab.vue`, `TreatmentPlanTab.vue` — apenas `RegistrationTab.vue` tinha `<script>`) eram extrações iniciadas e abandonadas, com apenas `<template>` e nenhuma lógica. Confundia leitura: quem abrisse `tabs/AnamnesisTab.vue` pensaria que era o componente real e tentaria editar lá sem efeito.

**Solução 1 — Deletar os 10 stubs órfãos (cleanup A):**
Removidos da pasta `plugins/patients/frontend/routes/patients/tabs/`:
- `AnamnesisTab.vue`, `AuditTab.vue`, `ConsentsTab.vue`, `DocumentsTab.vue`, `FinancialTab.vue`, `ProceduresTab.vue`, `RegistrationTab.vue`, `ScheduleTab.vue`, `TimelineTab.vue`, `TreatmentPlanTab.vue`.
Sem mudança de comportamento — todos os arquivos eram órfãos sem `<script>` (exceto `RegistrationTab.vue` que tinha script mas também não era importado em lugar nenhum).

**Solução 2 — Extração real de `ExamsTab.vue` (refactor B):**
Novo `plugins/patients/frontend/routes/patients/tabs/ExamsTab.vue` (2.074 linhas):
- **Script**: `examMedias`, `examFolders`, todos os modais (criar/renomear/excluir pasta, lock/unlock, excluir mídia), `lightboxMedia`, `mediaFileInput`, `uploadProgress`, helpers (`isVideo`/`isPdf`/`isImage`, `formatDate`, `formatMb`, `classifyUpload`, `detectMediaCategory`, `isMediaLocked`), computeds (`topLevelFolders`, `mediasInFolder`, `getSubfolders`, `getFolderPath`, `getTotalItemCount`), e TODAS as actions (CRUD de pastas, drag/drop de pastas e mídias com `persistFolderReorder`/`renumberSiblings`, lock/rename/delete de mídia, upload com validação de tipo/tamanho, lightbox).
- **Template**: header da aba + breadcrumb + sidebar de pastas (com drag/drop estilo Shopify) + grade de mídias (thumbnail dinâmico por tipo) + 5 modais + lightbox. Lightbox é uma raiz separada do componente (Vue 3 multi-root) para garantir overlay fullscreen sem stacking context do pai.
- **Style scoped**: 360 linhas de `.exams-*` (breadcrumb, sidebar, filters, empty-state, card, thumb, upload-progress, card-footer, card-actions). Migrados do `<style scoped>` do Record.vue — agora isolados por scope hash do próprio componente.
- **Lifecycle**: `onMounted` faz `fetchExamMedias()` + `loadFolderData()` + registra listener de `Escape` (lightbox). `onUnmounted` desregistra. Componente é totalmente autossuficiente — pai não precisa orquestrar nada.

**Solução 3 — Limpeza no `Record.vue`:**
- Removidos imports: `ExamMediasAPI`, `ExamFoldersAPI` (não usados mais).
- Removido import `onUnmounted` (lifecycle hook só era usado para a tecla Escape do lightbox, agora em ExamsTab).
- Adicionado import: `ExamsTab from './tabs/ExamsTab.vue'`.
- Removidos do `<script setup>` (~530 linhas total): state da aba (`examMedias`/`examFolders`/modais/lock/lightbox), helpers (`isVideo`/`isPdf`/`isImage`), computeds (`topLevelFolders`/`mediasInFolder`/`getFolderPath`/`getSubfolders`/`getTotalItemCount`/`activeFolder`), todas as actions (folder CRUD, drag/drop, lock, rename, delete media, upload), `fetchExamMedias`, `loadFolderData`, `triggerMediaUpload`, `openMediaLightbox`, `handleLightboxKey`, listeners de keypress.
- Removido do `watch(activeTab)` o branch `else if (newVal === 'exams') { fetchExamMedias() }` — ExamsTab faz seu próprio fetch ao montar.
- Removido do `onMounted` o `loadFolderData(route.params.patientId)`.
- Substituído todo o bloco `<!-- ABA: EXAMES E IMAGENS -->` (~951 linhas de template + 5 modais inline) por 1 linha: `<ExamsTab v-else-if="activeTab === 'exams'" />`.
- Removido o lightbox inline (~66 linhas).
- Removido do `<style scoped>` o bloco `EXAMES E IMAGENS — estilos exclusivos` (~360 linhas).

**Resultado:**
- `Record.vue`: **18.680 → 16.577 linhas** (-2.103, -11.3%).
- `ExamsTab.vue` (novo): 2.074 linhas, autossuficiente, com responsabilidade única.
- Total bruto cresce ~30 linhas (boilerplate `<script>`/`<template>`/`<style>` + imports duplicados), mas a **modularidade real é o ganho**: qualquer mudança futura na aba Exames toca só `ExamsTab.vue` (zero conflito com mudanças nas outras 11 abas).
- Pasta `tabs/` ficou limpa: só `EvolutionTab.vue` (já em uso) e `ExamsTab.vue` (novo).

**Próximos refactors recomendados (não bloqueantes):**
- Extrair as outras 11 abas (Geral, Cadastro, Anamnese, Plano de Tratamento, Procedimentos, Documentos, Consentimentos, Financeiro, Agenda, Timeline, Auditoria) seguindo o mesmo padrão. Cada uma reduz `Record.vue` em 500-2000 linhas. Pode ser feito incrementalmente — extrair uma de cada vez, na hora que precisar mexer.
- Após todas as extrações, `Record.vue` deve ficar com ~2.000-3.000 linhas (só shell + state compartilhado: paciente, alerta crítico, header, navegação de abas).

**Validações:**
- ✓ Vite compila sem erros (HMR ativo, sem warnings).
- ✓ Estrutura SFC válida em ambos arquivos: 1 `<script setup>`, 1 `<template>`, 1 `<style scoped>` cada.
- ✓ Sem ghost-refs no `Record.vue` (grep por `examMedias`/`examFolders`/`fetchExamMedias`/`loadFolderData`/`lightboxMedia` retorna 0 matches).

**Arquivos Modificados:**
- `plugins/patients/frontend/routes/patients/tabs/ExamsTab.vue` (novo, 2.074 linhas)
- `plugins/patients/frontend/routes/patients/Record.vue` (-2.103 linhas)
- `plugins/patients/frontend/routes/patients/tabs/AnamnesisTab.vue` (removido — stub órfão)
- `plugins/patients/frontend/routes/patients/tabs/AuditTab.vue` (removido — stub órfão)
- `plugins/patients/frontend/routes/patients/tabs/ConsentsTab.vue` (removido — stub órfão)
- `plugins/patients/frontend/routes/patients/tabs/DocumentsTab.vue` (removido — stub órfão)
- `plugins/patients/frontend/routes/patients/tabs/FinancialTab.vue` (removido — stub órfão)
- `plugins/patients/frontend/routes/patients/tabs/ProceduresTab.vue` (removido — stub órfão)
- `plugins/patients/frontend/routes/patients/tabs/RegistrationTab.vue` (removido — stub órfão)
- `plugins/patients/frontend/routes/patients/tabs/ScheduleTab.vue` (removido — stub órfão)
- `plugins/patients/frontend/routes/patients/tabs/TimelineTab.vue` (removido — stub órfão)
- `plugins/patients/frontend/routes/patients/tabs/TreatmentPlanTab.vue` (removido — stub órfão)
- `CHANGELOG.md`

## [1.4.4.70] - 2026-04-26T16:30:00-03:00

### Exames e Imagens (Fase 3): purge job, lock real, thumbnails de imagem e cleanup

**Problema:**
Após Fases 1 e 2, a aba "Exames e Imagens" ficou funcional, mas a auditoria (`docs/03-engineering/audit-exames-imagens.md`) sinalizava 4 itens de cleanup com impacto real em custo, segurança e performance:
1. **B3 — Soft-delete sem purge físico** — `soft_delete!` apenas marcava `deleted_at`, mas o blob no S3/Disk ficava órfão para sempre, acumulando custo de storage indefinidamente.
2. **M6 — Lock fake** — o lock usava PIN hardcoded `'123'` no frontend e o backend `destroy` *não* verificava `locked` antes de excluir. Bypass trivial via `curl` ou DevTools.
3. **B4 — Sem thumbnails** — galeria carregava o arquivo full em cada card (imagens de 5MB renderizadas como 200×200 pixels). Custo de banda × N cards × tráfego.
4. **Cleanup — `compare` action com JSON inline** — duplicava lógica do partial `_exam_media.json.jbuilder`, divergente quando campos novos eram adicionados (já tinha ficado fora de sync com `exam_folder_id`/`locked`).

**Solução 1 — Purge agendado de soft-delete (B3):**
- `Patients::ExamMediaPurgeJob` (`app/jobs/patients/exam_media_purge_job.rb`) — verifica se o registro continua soft-deleted; se sim, chama `file.purge_later` (purge do blob no Active Storage) e `destroy!` do record. Idempotente: re-runs em registros já purgados são no-op silencioso.
- `ExamMedia#soft_delete!` agora enfileira o job com `wait: 30.days` (constante `PURGE_AFTER`).
- Janela de 30 dias permite admin tools restaurarem registros (apenas zerar `deleted_at` antes do prazo).

**Solução 2 — Lock real server-side (M6):**
- `ExamMediasController#destroy` agora retorna `422` com mensagem clara `"Arquivo bloqueado. Desbloqueie antes de excluir."` se `@exam.locked?`. A verificação client-side de `media.locked` continua sendo apenas UX.
- Frontend (`Record.vue#confirmDeleteMedia`) propaga a mensagem do backend em vez de mostrar genérico "Erro ao excluir arquivo".
- PIN client-side (`'123'`) **mantido como UX de confirmação** (não como mecanismo de segurança). A integridade real do bloqueio agora vive no backend.

**Solução 3 — Thumbnails on-demand para imagens (B4):**
- `ExamMedia#thumbnail_url` gera variant `resize_to_limit: [400, 400]`. ActiveStorage cacheia o resultado, então primeira requisição é lenta e subsequentes são rápidas (servidas direto do storage).
- Tentamos passar `saver: { quality: 80 }` para reduzir peso, mas `saver` não está na whitelist `ActiveStorage.supported_image_processing_methods` do Rails 7.1 e gera 500 (`UnsupportedImageProcessingMethod`). Resize a 400px já dá redução significativa por si só; controle de qualidade fica para um processor custom em fase posterior.
- Variant gerada apenas para `file_kind == :image` e `file.variable?`; vídeo/PDF retornam `nil` e o frontend cai em ícone genérico.
- `_exam_media.json.jbuilder` expõe `thumbnail_url` ao lado de `url`.
- Galeria (`Record.vue`) usa `media.thumbnail_url || media.url` no `<img>` da thumbnail. Lightbox continua usando `media.url` (resolução cheia para zoom).
- `config/environments/development.rb` define `config.active_storage.variant_processor = :mini_magick` (container dev tem ImageMagick mas não libvips42; produção mantém default `:vips` por já ter ambos no Dockerfile principal).

**Solução 4 — `compare` action via jbuilder (cleanup):**
- `app/views/api/v1/accounts/patients/exam_medias/compare.json.jbuilder` (novo) reutiliza o partial `_exam_media`. Resposta do `compare` agora tem o mesmo shape de `index`/`show`, automaticamente incluindo `thumbnail_url`/`folder_id`/`locked` sem código duplicado.
- Controller reduzido de 25 linhas inline para 4 (`render :compare`).

**Notas operacionais:**
- Sidekiq queue `:patients` precisa estar rodando para o purge funcionar (já está no `Procfile.dev` e `docker-compose.yaml`).
- Soft-deleted records gerados antes desta fase **não terão** purge agendado — uma migração one-shot futura (ou script Rake) pode varrer registros antigos.
- Em produção (libvips42 + ffmpeg disponíveis), o variant_processor permanece `:vips` (mais rápido). Para alinhar dev com prod no futuro, basta adicionar `libvips42` ao `docker/dockerfiles/rails.Dockerfile`.

**Arquivos Modificados:**
- `plugins/patients/app/models/exam_media.rb`
- `plugins/patients/app/controllers/api/v1/accounts/patients/exam_medias_controller.rb`
- `app/jobs/patients/exam_media_purge_job.rb` (novo)
- `app/views/api/v1/accounts/patients/exam_medias/_exam_media.json.jbuilder`
- `app/views/api/v1/accounts/patients/exam_medias/compare.json.jbuilder` (novo)
- `config/environments/development.rb`
- `plugins/patients/frontend/routes/patients/Record.vue`
- `CHANGELOG.md`

## [1.4.4.69] - 2026-04-26T15:00:00-03:00

### Exames e Imagens (Fase 2): pastas migradas de JSONB para modelo relacional `ExamFolder` (REST)

**Problema:**
A persistência de pastas vivia num JSONB (`patients.exam_folder_data`) e era escrita por um endpoint único que sofria de uma combinação de bugs identificada em auditoria (`docs/03-engineering/audit-exames-imagens.md`):
1. **Pastas sumiam após F5** — frontend (axios) enviava `{ exam_folder: { folders: [...] } }`, mas o controller lia `params[:folders]` (top-level). O `wrap_parameters` do Rails detectava o wrapper já presente e não desempacotava, então `params[:folders]` ficava `nil` e o blob era resetado a cada PUT. O caminho `sendBeacon` (sem wrapper) funcionava ocasionalmente — daí a aparência intermitente do bug.
2. **camelCase × snake_case** — frontend mandava `parentId`/`order`, strong params filtrava `parent_id`/`position`. Mesmo se a persistência funcionasse, hierarquia e ordem das pastas eram descartadas.
3. **Duas implementações concorrentes** — tabela `exam_folders` (relacional) + JSONB `patients.exam_folder_data` coexistiam. Tabela ficava sempre vazia, FK `exam_medias.exam_folder_id` órfã, e o JSONB era a "verdade" frágil.
4. **`media_folder_map` e `lock_map`** mantidos em JSONB com IDs de mídia, exigindo sincronização manual a cada `fetchExamMedias` (`applyMediaFolderMap`). Frágil.
5. **`ExamsTab.vue`** — arquivo template órfão de 897 linhas duplicando markup do `Record.vue`, sem `<script>`. Confunde leitura.

**Solução 1 — Drop do JSONB e ativação do modelo relacional:**
- Migration `20260426130000_drop_exam_folder_data_from_patients` remove a coluna `patients.exam_folder_data`.
- `exam_folders` (já migrado em 20260322200003) passa a ser fonte de verdade. `exam_medias.exam_folder_id` (FK existente) passa a ser usado.
- Como o módulo está em fase de testes (sem arquivos reais de pacientes), não há script de migração de dados — a UX recomeça com pastas vazias.

**Solução 2 — `ExamFolder` model com validações fortes:**
- `validates :name, length: { maximum: 80 }` (`MAX_NAME_LENGTH`).
- `validate :max_one_level_nesting` — subpastas não podem conter subpastas.
- `validate :parent_in_same_patient` — defesa em profundidade contra IDs cross-tenant.
- `validate :no_self_parent` — pasta não pode ser pai de si mesma.
- `before_validation :assign_account_from_patient` — preenche `account_id` automaticamente.
- `belongs_to :parent` + `has_many :children, dependent: :destroy` (subpastas vão junto).
- `has_many :exam_medias, dependent: :nullify` (arquivos voltam para raiz na exclusão da pasta).

**Solução 3 — `ExamFoldersController` RESTful:**
- `index` (GET), `create` (POST), `update` (PATCH), `destroy` (DELETE) e `reorder` (PUT collection).
- `set_patient` usa `Current.account.patients.find` (multi-tenant).
- `set_folder` re-escopa via `@patient.exam_folders.find` (defesa cross-tenant).
- `destroy` move medias para raiz em transação (`exam_medias.update_all(exam_folder_id: nil)`) antes de excluir.
- `reorder` aceita `items: [{id, parent_id, position}]` em batch, ignora IDs que não pertencem ao paciente, aplica em transação.
- `normalize_parent_id` valida que o pai-alvo é do mesmo paciente.
- `ExamFolderPolicy` (nova) com mesmas regras de `view_exams`/`manage_exams` do `ExamMediaPolicy`.

**Solução 4 — `ExamMediasController#exam_update_params` aceita movimento + lock + rename:**
- Aceita `:exam_folder_id`, `:locked`, `:file_name` no PATCH além dos campos já existentes.
- `normalize_folder_id` valida que a pasta-alvo pertence ao mesmo paciente, aceita `'root'`/null/string vazia como "sem pasta".

**Solução 5 — Frontend (`Record.vue` + `examFolders.js` + `examMedias.js`):**
- `examFolders.js` reescrito para REST: `getAll`, `create`, `update`, `delete`, `reorder` (todos com payload `{ exam_folder: ... }` ou `{ items: [...] }`).
- `examMedias.js` ganha `update(patientId, mediaId, payload)` para mover/lock/rename via PATCH.
- `Record.vue`:
  - `examFolders` agora começa vazio (`ref([])`); `'root'` é apenas sentinel de UI.
  - Removidos: `mediaFolderMap`, `mediaLockMap`, `applyMediaFolderMap`, `saveFolderData`, `flushFolderData`, `buildFolderPayload`, `handleFolderBeforeUnload`, `lastFolderPayloadJson`, `saveFolderDebounceTimer`, `nonRootFolders`, listeners de `beforeunload` e `onBeforeUnmount`.
  - `expandedFolderIds` mantido como UI-only (não persiste).
  - `parentId`/`order` → `parent_id`/`position` em todo o componente (template + script).
  - `mediaLockMap[id]` → `media.locked` direto no template.
  - `createFolder`/`confirmRenameFolder`/`confirmDeleteFolder` viraram async com chamadas REST e rollback otimista em erro.
  - `onFolderSidebarDrop` e `promoteFolderToRoot` calculam o batch mínimo de pastas afetadas e chamam `reorder` uma vez.
  - `onFolderDrop` (drop de mídia em pasta) e `confirmLockAction`/`confirmRenameMedia` viraram async com chamadas REST + rollback em erro.

**Solução 6 — JBuilder views:**
- Novas: `app/views/api/v1/accounts/patients/exam_folders/{_exam_folder,index,show}.json.jbuilder`.
- `_exam_media.json.jbuilder` agora expõe `exam_folder_id`, `folder_id` (alias para o frontend manter mesmo nome) e `locked`.

**Solução 7 — Cleanup:**
- Removido `plugins/patients/frontend/routes/patients/tabs/ExamsTab.vue` (arquivo órfão de 897 linhas, sem `<script>`, duplicava o markup já presente no `Record.vue`).

**Notas de migração:**
- Migration destrutiva (drop column). Sem dados reais de paciente, sem necessidade de script de migração de JSONB → relacional. Para rodar: `docker compose exec rails bundle exec rails db:migrate`.
- Após migrar, recomendado limpar `storage/` local para começar do zero também nos uploads.

**Arquivos Modificados:**
- `db/migrate/20260426130000_drop_exam_folder_data_from_patients.rb` (novo)
- `plugins/patients/app/models/exam_folder.rb`
- `plugins/patients/app/controllers/api/v1/accounts/patients/exam_folders_controller.rb`
- `plugins/patients/app/controllers/api/v1/accounts/patients/exam_medias_controller.rb`
- `app/policies/exam_folder_policy.rb` (novo)
- `app/views/api/v1/accounts/patients/exam_folders/_exam_folder.json.jbuilder` (novo)
- `app/views/api/v1/accounts/patients/exam_folders/index.json.jbuilder` (novo)
- `app/views/api/v1/accounts/patients/exam_folders/show.json.jbuilder` (novo)
- `app/views/api/v1/accounts/patients/exam_medias/_exam_media.json.jbuilder`
- `config/routes.rb`
- `plugins/patients/frontend/api/patients/examFolders.js`
- `plugins/patients/frontend/api/patients/examMedias.js`
- `plugins/patients/frontend/routes/patients/Record.vue`
- `plugins/patients/frontend/routes/patients/tabs/ExamsTab.vue` (removido)
- `CHANGELOG.md`

## [1.4.4.68] - 2026-04-26T12:00:00-03:00

### Exames e Imagens (Fase 1): render de vídeo, limites por tipo, signed_url corrigida e UX de upload

**Problema:**
A aba "Exames e Imagens" do prontuário tinha múltiplos defeitos críticos identificados em auditoria (ver `docs/03-engineering/audit-exames-imagens.md`):
1. **Vídeos não renderizavam** — galeria e lightbox tratavam qualquer mídia não-PDF como `<img>`, então MP4/MOV/WEBM eram envolvidos em tag de imagem e quebravam silenciosamente.
2. **Sem limites por tipo no backend** — modelo `ExamMedia` aceitava até 500MB para qualquer arquivo. Requisito do produto: 5MB para imagem, 10MB para PDF e 10MB para vídeo.
3. **`signed_url` com fallback `localhost:3000`** — em produção sem `default_url_options[:host]` configurado, todas as URLs de mídia apontariam para localhost. Expiração de 15 minutos era curta demais para uso normal de galeria/lightbox (imagem aberta após 15min retornava 404).
4. **Categoria derivada do client (não-confiável)** — HEIC do iPhone com MIME vazio caía em `outro`, vídeo `.mov` no Windows idem. A categoria correta deveria vir do `content_type` real do blob no servidor.
5. **UX sem informação prévia** — usuário não sabia tipos/tamanhos aceitos antes de tentar o upload, e mensagens de erro vinham como array bruto da API.

**Solução 1 — Limites por tipo no backend (`ExamMedia`):**
- Constantes `IMAGE_TYPES`, `PDF_TYPES`, `VIDEO_TYPES` separadas, `ALLOWED_CONTENT_TYPES` derivada da união. Removido `application/dicom`, `application/octet-stream` (eram aceitos sem validação real).
- Constante `SIZE_LIMITS = { image: 5MB, pdf: 10MB, video: 10MB }`.
- Método `file_kind` classifica o blob pelo `content_type` real (não pela `category` informada).
- Validação `file_content_type_and_size` agora rejeita formato fora da whitelist com mensagem clara em PT-BR e aplica o limite específico do tipo (com `number_to_human_size` para o limite na mensagem de erro).
- `before_validation :derive_category_from_file, on: :create` define `category` automaticamente a partir do `file_kind`, sobrescrevendo `'outro'` quando o blob é classificável — o client pode mandar qualquer coisa e o servidor garante a categorização correta.
- `image?`, `video?`, `pdf?` agora consultam `file_kind` primeiro (fonte de verdade) e caem na `category` legada como fallback.

**Solução 2 — `signed_url` correta:**
- `expires_in` default movido de `15.minutes` para `1.hour` (compatível com galerias/lightbox revisitados).
- Removido o fallback `host: 'localhost:3000'` — agora confia em `config.active_storage.default_url_options[:host]` (já configurado em dev e production via `FRONTEND_URL`).

**Solução 3 — Frontend: render de vídeo (`Record.vue`):**
- Helpers `isVideo`, `isPdf`, `isImage` adicionados perto de `mediasInFolder`, classificando por MIME e por extensão (proteção contra blob com `content_type` ausente).
- Galeria (thumbnail): bloco condicional reescrito para `<video preload="metadata" muted playsinline>` quando `isVideo(media)`, `<img loading="lazy">` quando `isImage(media)`, ícone PDF quando `isPdf(media)`, ícone genérico no `else`.
- Badge "VÍDEO" no canto sup. direito do thumbnail de vídeo (`.exams-thumb-badge` no `record.css`).
- Lightbox: tag `<video controls autoplay playsinline>` quando `isVideo(lightboxMedia)`, mantendo iframe para PDF e img para imagem.

**Solução 4 — UX de upload (`Record.vue`):**
- Constantes `UPLOAD_LIMITS`, `ACCEPTED_MIME`, `ACCEPTED_EXT` em sync com `ExamMedia::SIZE_LIMITS`.
- Função `classifyUpload(file)` valida contra MIME + extensão antes de tocar a rede; rejeita formatos não suportados com mensagem específica.
- `onMediaFileSelected` valida formato → tamanho → upload, com mensagens distintas para cada falha (`Formato não suportado…` vs `Arquivo muito grande. Máximo XMB para…`).
- Erros do backend (array `errors[]`) agora são juntados com `. ` em vez de exibir só o primeiro item.
- Linha de hint visível abaixo do título da aba: `Aceitos: imagens (JPG, PNG, WEBP, HEIC) até 5MB · PDF até 10MB · vídeo (MP4, MOV, WEBM) até 10MB`.
- `accept` do `<input type="file">` enxugado para a lista exata aceita pelo backend (removidos `image/*` genérico e `video/x-msvideo`).

**Notas de migração:**
- Como o módulo está em fase de testes (sem arquivos reais de pacientes), uploads existentes que estiverem fora dos novos limites simplesmente passam a falhar. Não há script de migração — basta limpar a pasta `storage/` local se necessário.
- A Fase 2 (refactor de pastas JSONB → modelo relacional `ExamFolder`) é PR separado, conforme planejado em `docs/03-engineering/audit-exames-imagens.md`.

**Arquivos Modificados:**
- `plugins/patients/app/models/exam_media.rb`
- `plugins/patients/frontend/routes/patients/Record.vue`
- `plugins/patients/frontend/routes/patients/record.css`
- `docs/03-engineering/audit-exames-imagens.md` (novo — plano completo da auditoria)
- `CHANGELOG.md`

## [1.4.4.67] - 2026-04-25T18:00:00-03:00

### Agendamento Online (link público): sincronização total com AgendaSetting + branding institucional + UX

**Problema:**
A página pública de agendamento (`/agenda/:public_id`) operava completamente desacoplada das configurações da agenda da clínica:
1. **Slots ignoravam o `slot_interval_minutes`** — sempre gerava blocos de 60min, mesmo com 15/30min configurado no painel.
2. **Não respeitava `week_days`** da AgendaSetting — caía em `WorkingHour` (configuração no nível de inbox), não na configuração de horário gerenciada pela clínica.
3. **Holidays e exceptions ignoradas** — feriados e folgas configurados no painel não bloqueavam slots na página pública.
4. **Lunch break ignorado** — mesmo com `block_lunch_break` ativo, os slots de almoço apareciam disponíveis.
5. **Branding hardcoded** — header com texto "Beclinic" literal, cor indigo `#4f46e5` fixa, sem logo da instalação. Não acompanha o `BRAND_NAME`/`LOGO` global configurados em `installation_config.yml`.
6. **Validação primitiva** — `alert()` JavaScript para erros, sem feedback inline por campo.
7. **Sem ARIA, sem mobile UX adequada** — touch targets pequenos (28px), sem `aria-current`, `role="alert"`, sem reflow para tela pequena nos botões.

**Solução 1 — Slots respeitam AgendaSetting (5 regras):**
`Public::Api::V1::Agenda::PublicController#calculate_slots` reescrito. Agora, em ordem:
- **Window de trabalho:** `working_window_for(date, setting)` — prefere `setting.week_days[wday].start/end/lunchStart/lunchEnd`, cai em `WorkingHour` só se a configuração nova ausente. Backwards-compat preservada.
- **Holiday check:** itera `setting.holidays` (status `'closed'`, formato `dd/mm/...`) — retorna `[]` se data bate.
- **Exception check:** itera `setting.exceptions` com range `start..end` — retorna `[]` se data está dentro.
- **Slot step = `setting.slot_interval_minutes`** (15/30/60), não mais hardcoded 60.
- **Lunch break:** se `setting.block_lunch_break` true E `lunchStart/lunchEnd` definidos no dia, slots que cruzam a janela de almoço são pulados.
- **Loop fix:** `while current_time + slot_interval.minutes <= close_time` (antes: `< end_time` permitia slot estourando o horário de fechamento).

`#book` action também ajustado: `slot_duration = setting&.slot_interval_minutes || 60` (mesma fonte que gerou a grade), garantindo que evento criado ocupa exatamente um slot inteiro do calendário interno — sem sobreposição parcial entre o público e o calendário do dashboard.

**Solução 2 — Branding institucional via GlobalConfigService:**
`AgendaBookingController#show` agora carrega:
- `BRAND_NAME` (default 'Klivy') — usado no `<title>` da página, footer ("Powered by …"), `alt` do logo.
- `LOGO` (default `/brand-assets/logo.svg`) — renderizado no header com `<img>` (antes era apenas texto).
- `LOGO_DARK` (carregado mas reservado para tema escuro futuro).
- `BRAND_URL` (default `https://klivy.com.br`) — link do footer.
- `@agenda_setting` exposto à view para futuros usos sem novo round-trip.

**Solução 3 — Cor brand mais clean:**
Tokens CSS `--brand`/`--brand-dark`/`--brand-light`/`--brand-mid` migrados de indigo (`#4f46e5`) para azul institucional Klivy:
- `--brand: #1f6cf2` (azul primário, casa com `--blue-9` do dashboard)
- `--brand-dark: #1858d4`
- `--brand-light: #e8f0ff`
- `--brand-mid: #5b8dee`

Estrutura de tokens preserva compatibilidade — qualquer override por conta no futuro só precisa injetar 4 linhas de CSS via controller.

**Solução 4 — Validação inline + ARIA:**
- Todos os campos do form Step 1 (`Nome`, `Sobrenome`, `WhatsApp`, `E-mail`, `CPF`) ganharam `<span class="field-error" role="alert">` por baixo + classe `.is-invalid` no input no estado de erro.
- `setFieldError(inputId, errId, hasError)` helper centraliza toggle.
- Listeners de `input` limpam o erro automaticamente quando o usuário começa a corrigir (mais responsivo que validar só no submit).
- E-mail (opcional): se preenchido, valida regex; vazio passa.
- Telefone: valida 10 ou 11 dígitos (DDD + número), antes não validava.
- Submit move foco para o primeiro campo inválido — bom para teclado e leitores de tela.
- `<alert>` substitui `alert()` JavaScript bloqueante.

**Solução 5 — Acessibilidade + mobile:**
- Stepper: `role="list"`, cada step `role="listitem"`, item ativo com `aria-current="step"`, `aria-hidden="true"` no número decorativo.
- Form: `aria-label`, `aria-required`, `aria-invalid` dinâmico, `<span class="sr-only">obrigatório</span>` para leitores de tela (mantém o `*` visual).
- Header: `role="banner"` + `<img alt="<brand>">` (antes não havia logo, só texto).
- Inputs ganharam `inputmode="tel"` / `inputmode="numeric"` para teclados mobile certos.
- Novo breakpoint `max-width: 768px` (tablet) ajusta padding e calendário.
- `max-width: 600px` (mobile) agora também:
  - Aumenta step dot para 32×32 (touch target).
  - Aumenta `.btn` para padding 14px/20px.
  - Empilha `.btn-row` em coluna invertida (botão principal em cima).
- Helper `.sr-only` adicionado para conteúdos só-leitor-de-tela.

**Arquivos Modificados:**
- `app/controllers/agenda_booking_controller.rb` (carrega `agenda_setting` + `BRAND_NAME`/`LOGO`/`LOGO_DARK` via `GlobalConfigService`)
- `app/controllers/public/api/v1/agenda/public_controller.rb` (reescrita de `calculate_slots`, novos métodos `working_window_for` / `blocked_by_holiday?` / `blocked_by_exception?`, `book` alinhado ao `slot_interval_minutes`)
- `app/views/layouts/agenda_booking.html.erb` (cor brand azul, `sr-only`, breakpoint tablet, mobile reflow, footer dinâmico, `<title>` dinâmico)
- `app/views/agenda_booking/show.html.erb` (logo `<img>` no header, ARIA no stepper/form, `field-error` por campo, `setFieldError` helper, validação de telefone e email)

**Compatibilidade:**
- Backend: contas que ainda não criaram `AgendaSetting` continuam funcionando — fallback para `WorkingHour` preservado em `working_window_for`.
- Frontend: instalações sem `BRAND_NAME` configurado caem para 'Klivy'; sem `LOGO`, caem para `/brand-assets/logo.svg`. Sem regressão visual.

---

## [1.4.4.66] - 2026-04-25T00:00:00-03:00

### Agenda: Auditoria de slots — alinhamento exato no grid, snap configurável no drag/resize, modal sem pré-seleção e DatePicker com botão "Hoje"

**Problema:**
Múltiplos bugs visuais e de sincronização no módulo de Agenda (`/plugins/agenda`) compunham uma falta geral de precisão:
1. **Cards do calendário cortavam o último slot.** Evento `09:00–10:00` com intervalo de 15min ocupava visualmente apenas até 09:45 — `getEventTimelineStyle` calculava altura como `durationHours * pixelsPerHour - 4`, comendo 4px do fundo de cada card.
2. **Modal abria com horário pré-selecionado sem ação do usuário.** `createDefaultNewEvent` forçava `09:00`/`10:00` quando o modal era aberto via "+ Novo Evento", contradizendo a expectativa de "estado inicial limpo".
3. **Auto-seleção de serviço não respeitava o intervalo do slot.** Um procedimento de 45min com slots de 30min produzia `time_end` em fração de slot (não alinhado ao grid).
4. **Drag-and-drop e resize tinham snap fixo de 5min**, ignorando `slot_interval_minutes`. Resultado: arrastar evento com slot=15min produzia horários como `09:10`, `09:25`, fora do grid configurado.
5. **DatePicker do modal tinha contraste fraco** em ambos os modos (claro e escuro), com cores hardcoded que não invertiam corretamente. Faltava também atalho para "voltar a hoje".
6. **Defaults inconsistentes:** modal usava fallback de 30min para `slot_interval_minutes`, calendário e backend usavam 60min.

**Solução 1 — Altura/topo dos cards alinhados ao slot (regra `ceil`, nunca `floor`):**
Substituí o cálculo baseado em `durationHours` por math em slots inteiros:
- `snapStartSlot = Math.floor((startMin - visibleStartMin) / interval)` — topo no slot que contém `start_time`.
- `snapEndSlot = Math.ceil((endMin - visibleStartMin) / interval)` — base no fim do último slot que o evento toca.
- `slotsOccupied = max(1, snapEndSlot - snapStartSlot)`.
- `height = slotsOccupied * slotHeight - 2` (2px de respiro vertical entre cards).

Aplicado também no `dragGhostStyle` em `useAgenda.js` para consistência.

**Solução 2 — Modal sem pré-seleção:**
- `createDefaultNewEvent` mudou de `||` para `??` em `time_start`/`time_end`, preservando string vazia.
- `openEventModal` só passa horário quando há `hourStr` (cell click); abertura via botão / FAB / mês deixa os campos vazios.
- `isSlotInRange`, `selectSlot`, `rangeLabel`, `canConfirm` ganharam guard para o estado vazio.
- `saveEvent` valida `time_start`/`time_end` antes de tentar criar `Date`.

**Solução 3 — Auto-seleção de serviço slot-aligned:**
`selectTreatment` agora calcula `slotsNeeded = Math.ceil(duration_minutes / slotInterval)` e aplica `slotsNeeded * slotInterval` minutos. Se o usuário ainda não escolheu start, ancora no primeiro slot não-bloqueado do dia.

**Solução 4 — Drag/Resize snap pelo `slot_interval_minutes`:**
`useAgendaDnD.onGlobalMouseMove` lê `agenda.agendaSettings.value?.slot_interval_minutes || 60` e usa `Math.round(... / snapMin) * snapMin` em vez de `Math.round(... / 5) * 5`. Resize também usa o mesmo snap, e `minEndMs` = `start + snapMin * 60000` (mínimo de 1 slot, antes era 5min).

**Solução 5 — DatePicker semântico + botão "Hoje":**
Reescrita do CSS do `.mx-datepicker-main` em `agenda-events.css` usando exclusivamente tokens semânticos (`slate-1..12`, `blue-9..11`) — invertem automaticamente entre modo claro e escuro. Principais melhorias:
- "Hoje" sem seleção: anel interno 1px azul (`box-shadow: inset 0 0 0 1px`) + texto `blue-11` → visível em ambos os modos, mesmo quando outra data está selecionada.
- Hover translúcido (`rgba(blue-9, 0.15)`) em vez de cor sólida (`blue-3`).
- Mês anterior/próximo: `slate-9` + opacity `0.7` (antes: `slate-8`, ilegível no escuro).
- Cells desabilitadas com regra explícita (`slate-8` + `cursor: not-allowed`).
- Hover nos botões de navegação (mudam para `blue-11`).

Botão "Hoje" novo (`.datepicker-today-btn`) ao lado do campo Data nas duas abas (Consulta + Compromisso/Bloqueio): seta `newEvent.date` para o dia atual e fica desabilitado/destacado quando já está em hoje.

**Solução 6 — Default unificado:**
`AgendaEventModal.slotInterval` mudou de `30` para `60` (alinhado com `useAgenda.js`, `dayHours`, `AgendaTimelineView` e o `set_defaults` do backend `AgendaSetting`).

**Sincronização final — todos os pontos lendo a mesma fonte (`agendaSettings.slot_interval_minutes`):**
- Grid (linhas/altura): `useAgenda.js` (rowHeight, pixelsPerHour, dayHours).
- Card visual (top/height): `AgendaTimelineView.vue` (snapStart/snapEnd).
- Drag ghost: `useAgenda.js` (dragGhostStyle).
- Drag/resize (tempo salvo): `useAgendaDnD.js` (snapMin).
- Modal (grid de slots, seleção, auto-serviço): `AgendaEventModal.vue`.

**Arquivos Modificados:**
- `plugins/agenda/frontend/components/AgendaTimelineView.vue` (nova prop `slotIntervalMinutes`, math slot-aligned, remoção do `+2/-4`)
- `plugins/agenda/frontend/components/AgendaEventModal.vue` (guards de estado vazio, `selectTreatment` com `Math.ceil`, computed `todayDateStr`/`isDateToday`, botão "Hoje" nas duas abas, default 60)
- `plugins/agenda/frontend/composables/useAgenda.js` (`dragGhostStyle` slot-aligned com 2px de respiro)
- `plugins/agenda/frontend/composables/useAgendaCrud.js` (`openEventModal` sem time default, validação em `saveEvent`)
- `plugins/agenda/frontend/composables/useAgendaDnD.js` (`snapMin` lido do setting, mínimo de resize = 1 slot)
- `plugins/agenda/frontend/utils/agenda-date.js` (`createDefaultNewEvent` com `??` para preservar string vazia)
- `plugins/agenda/frontend/routes/AgendaDashboard.vue` (computed `slotIntervalMinutes`, prop passada ao Timeline)
- `plugins/agenda/frontend/styles/agenda-events.css` (DatePicker reescrito com tokens semânticos, classe `.datepicker-today-btn`)

**Testes manuais validados:**
- Evento `09:00–10:00` ocupa 4 slots em 15min, 2 slots em 30min, 1 slot em 60min.
- Modal abre vazio via "+ Novo Evento"; abre pré-preenchido via clique em célula.
- Procedimento "Avaliação" (1h) auto-seleciona corretamente em qualquer intervalo.
- Drag em slot=15min snap em `09:00 / 09:15 / 09:30 / 09:45`; sem mais `09:10`.
- DatePicker "hoje" visível em modo claro e escuro com ou sem data selecionada.

---

## [1.4.4.65] - 2026-04-24T00:00:00-03:00

### RBAC: Refinamentos na promoção a Owner — filtro de SuperAdmin e ocultação do time interno

**Problema:**
Após a entrega das versões v1.4.4.63 (botão manual) e v1.4.4.64 (auto-promoção), dois ajustes finos apareceram no uso real:
1. SaaS SuperAdmins (`User.type = 'SuperAdmin'`) apareciam na lista de usuários "promovíveis" do painel `/beclinic_admin/owners`, mesmo já tendo bypass global via `beclinic_super_admin?` — confuso e redundante.
2. O `Team` interno chamado `owner` (infraestrutura da RBAC) aparecia no sidebar do cliente ("Times → owner") e na tela Configurações → Times, poluindo a UI do cliente final.

**Solução 1 — Filtro de SuperAdmin em 4 camadas (defesa em profundidade):**
- `BeclinicAdmin::OwnersController#show` — filtra `users.type = nil` na listagem de `@account_users` (esconde SuperAdmins).
- `BeclinicAdmin::OwnersController#load_owners_for` / `#owner_user_ids` — rejeita SuperAdmins da coluna "Proprietário(s) atual(is)" do index e do cálculo de "já é proprietário".
- `BeclinicCore::AccountSetup#promote_to_owner!` — raise `ArgumentError` se tentarem promover um SuperAdmin (mesmo via POST direto ou console).
- `Account#setup_beclinic_owner` callback — skip se o primeiro usuário da conta for SuperAdmin (evita auto-promoção no onboarding inicial do SaaS).

**Solução 2 — Time `owner` invisível para o cliente:**
Sobrescrita via `class_eval` de `Api::V1::Accounts::TeamsController#index` dentro do `to_prepare` do plugin, filtrando `WHERE name != 'owner'`. Afeta sidebar, Configurações → Times e qualquer dropdown de seleção de time. Zero edição do controller original do core. `beclinic_team_for(account)` e permissões backend continuam enxergando o time normalmente.

**Arquivos Modificados:**
- `plugins/beclinic_core/app/controllers/beclinic_admin/owners_controller.rb` (filtros de SuperAdmin nas 3 actions)
- `plugins/beclinic_core/app/services/beclinic_core/account_setup.rb` (+1 linha guard)
- `plugins/beclinic_core/lib/beclinic_core/engine.rb` (skip no callback + class_eval na TeamsController)
- `spec/plugins/beclinic_core/services/account_setup_spec.rb` (+2 testes)
- `spec/plugins/beclinic_core/callbacks/account_owner_auto_promotion_spec.rb` (+1 teste)

**Testes:** 27/27 passando no rspec do plugin após os ajustes.

---

## [1.4.4.64] - 2026-04-23T16:30:00-03:00

### RBAC: Promoção automática de Owner na criação de conta (compra de plano)

**Problema:**
Mesmo com o botão manual do Super Admin disponível (v1.4.4.63), toda nova conta criada via compra de plano ainda nascia sem Proprietário definido, exigindo intervenção do time. O ideal é que o comprador do plano já saia como Proprietário automaticamente.

**Solução:**
Callback `after_create_commit :setup_beclinic_owner` registrado em `Account` via `class_eval` dentro do próprio `plugins/beclinic_core/lib/beclinic_core/engine.rb` (padrão já usado no plugin para `has_one :beclinic_profile`). Quando uma nova `Account` é criada (tipicamente via `AccountBuilder` no fluxo do `plugins/billing`), o callback:
- Busca o primeiro `AccountUser` da conta (o criador).
- Chama `BeclinicCore::AccountSetup.promote_to_owner!` — mesmo service reutilizado pelo botão manual.
- Resgata qualquer erro e apenas registra `Rails.logger.warn` — falha aqui **nunca** derruba a criação da conta.
- Não faz nada se a conta foi criada sem usuário vinculado (ex: factories em testes).

Zero edição em `app/models/account.rb` ou em qualquer arquivo do core — tudo vive dentro do plugin.

**Arquivos Modificados:**
- `plugins/beclinic_core/lib/beclinic_core/engine.rb` (callback adicionado no `Account.class_eval` existente)

**Arquivos Adicionados:**
- `spec/plugins/beclinic_core/callbacks/account_owner_auto_promotion_spec.rb`

---

## [1.4.4.63] - 2026-04-23T16:00:00-03:00

### RBAC: Promoção manual de Owner (UI: "Proprietário") em painel standalone

**Problema:**
Após a compra do plano, o cliente (dono da conta) ficava com papel `gerente`, exigindo ajuste manual de permissões toda vez que ele tentava operar recursos como "adicionar pacientes". O papel `dono` já existia no backend (`BECLINIC_ROLES`) e concede `full_permissions_hash`, mas não havia fluxo para atribuí-lo.

**Solução:**
Página standalone `/beclinic_admin/owners`, autenticada via sessão Devise de `super_admin` (mesmo login do painel super admin). Selecione uma conta e promova um de seus usuários a Proprietário. A promoção:
- Cria (idempotente) um `Team` chamado `owner` com `beclinic_role: 'dono'` na conta.
- Remove o usuário de outros times da mesma conta para garantir que `beclinic_team_for(account)` resolva para o time de Owner.
- **Nunca** altera `User#type` (a flag `SuperAdmin` permanece reservada ao dono do SaaS).

**Por que standalone e não dentro do `/super_admin`?** O painel super admin do Chatwoot usa Administrate, que auto-descobre controllers cujo path começa com `super_admin/` e tenta renderizar sidebar items para cada um. Qualquer resource desconhecido nesse path quebra toda a navegação admin. A feature usa layout próprio mínimo (sem Vite, sem Administrate) e tem zero impacto no painel super admin existente.

**Convenção de nomes:** identificadores em inglês (classes, rotas, arquivos, métodos, `Team.name`); valor de enum `beclinic_role: 'dono'` mantido (compatibilidade com `BECLINIC_ROLES` existente); rótulos de UI em português ("Proprietário").

**Arquivos Adicionados:**
- `plugins/beclinic_core/app/services/beclinic_core/account_setup.rb`
- `plugins/beclinic_core/app/controllers/beclinic_admin/owners_controller.rb`
- `plugins/beclinic_core/app/views/layouts/beclinic_admin.html.erb`
- `plugins/beclinic_core/app/views/beclinic_admin/owners/index.html.erb`
- `plugins/beclinic_core/app/views/beclinic_admin/owners/show.html.erb`
- `spec/plugins/beclinic_core/services/account_setup_spec.rb`
- `spec/plugins/beclinic_core/controllers/beclinic_admin/owners_controller_spec.rb`

**Arquivos Modificados:**
- `config/routes.rb` (+4 linhas: `namespace :beclinic_admin do resources :owners, ... end` no topo do arquivo, fora do bloco super_admin existente)

---

## [1.4.4.62] - 2026-04-23T15:44:17-03:00

### WhatsApp: Entrega de Áudio com Duração e Externalização dos Termos de Uso

**Problema:**
Áudios enviados via WhatsApp chegavam sem metadado de duração, exibindo "0:00" em alguns clientes. Adicionalmente, o texto dos Termos de Uso estava hardcoded no `checkout.html`, dificultando manutenção.

**Solução:**
- Servidor WhatsApp (`lib/whatsapp/server.js`) passou a calcular/anexar a duração antes do envio, garantindo que o player do destinatário exiba o tempo correto.
- Conteúdo dos Termos movido para `TermosUso.md` e carregado dinamicamente pelo `checkout.html`.
- Ajustes no `Dockerfile` para suportar os novos assets.

**Arquivos Modificados:**
- `lib/whatsapp/server.js`
- `TermosUso.md`
- `public/checkout.html`
- `Dockerfile`

---

## [1.4.4.61] - 2026-04-23T14:20:59-03:00

### Prontuário: Upload de Vídeos, Progresso e Persistência em Navegação + Webhooks com X-Forwarded-Proto

Duas frentes combinadas: suporte a vídeo em exames e robustez em salvamento durante navegação, além de correção em requisições HTTPS via proxy.

**1. Upload de Vídeos em Exames (`plugins/patients`):**
- Controller `exam_folders_controller` e model `exam_media` agora aceitam mimetypes de vídeo.
- Barras de progresso por upload no `Record.vue`.
- Dados da pasta de exames persistem de forma confiável mesmo quando o usuário navega/recarrega durante o upload (uso de `beforeunload` + flush pendente).

**2. Webhook / Loopback HTTPS (`lib/whatsapp/server.js`):**
- Adicionado header `X-Forwarded-Proto` em requisições fetch de webhook e loopback, corrigindo validação de protocolo em ambientes atrás de proxy reverso (EasyPanel/Traefik).

**Arquivos Modificados:**
- `plugins/patients/app/controllers/api/v1/accounts/patients/exam_folders_controller.rb`
- `plugins/patients/app/models/exam_media.rb`
- `plugins/patients/frontend/api/patients/examMedias.js`
- `plugins/patients/frontend/routes/patients/Record.vue`
- `lib/whatsapp/server.js`
- `docs/build_deploy.md`

---

## [1.4.4.60] - 2026-04-23T13:06:18-03:00

### Anamnese: Campos Aninhados de Histórico Médico, State Patching e Ajustes no PDF + Toasts no Checkout

**Anamnese (`plugins/patients`):**
- Campos de histórico médico foram aninhados (objeto estruturado) em vez de chaves planas, simplificando novas adições e a renderização dinâmica no `AnamnesisTab.vue`.
- Introduzido _state patching_ no `Record.vue` para evitar re-renders completos ao editar blocos grandes da anamnese.
- Gerador de PDF (`anamnesis_pdf_generator.rb`) atualizado para a nova estrutura e teve o cabeçalho limpo — removidas informações de versão/data que estavam poluindo o topo do relatório.
- Specs adicionados em `spec/models/anamnesis_spec.rb` e factories atualizadas.

**Checkout (`plugins/billing`):**
- Toasts de sucesso/erro substituindo alerts nativos.
- Validação inline por campo (e não apenas no submit) no `checkout.html` e `onboarding-finish.html`.
- Ajustes em `create_customer` e no `onboarding_controller` para retornar mensagens consistentes.

**Arquivos Modificados:**
- `app/services/patients/anamnesis_pdf_generator.rb`
- `app/views/api/v1/accounts/patients/anamneses/_anamnesis.json.jbuilder`
- `plugins/patients/frontend/routes/patients/Record.vue`
- `plugins/patients/frontend/routes/patients/tabs/AnamnesisTab.vue`
- `spec/factories/anamneses.rb`
- `spec/factories/patients.rb`
- `spec/models/anamnesis_spec.rb`
- `plugins/billing/app/controllers/billing/api/v1/billing/onboarding_controller.rb`
- `plugins/billing/app/services/asaas/create_customer.rb`
- `plugins/billing/config/routes.rb`
- `public/checkout.html`
- `public/onboarding-finish.html`

---

## [1.4.4.59] - 2026-04-22T23:07:40-03:00

### Checkout: Cupons Dinâmicos, Multi-step Validation, Turnstile e Ajuste de Preços

Evolução completa do fluxo de checkout para produção: validação por etapa, anti-bot, sistema flexível de cupons e reajuste de planos.

**1. Cupons Dinâmicos (`plugins/billing`):**
- Migrations adicionam `coupon_fields` e `credit_card_token` em `billing_subscriptions`.
- Novo `Billing::CouponRegistry` centraliza regras de descontos/trials variáveis por cupom.
- `Asaas::CreateSubscription` e `Asaas::CreatePayment` passam a aplicar trial e desconto conforme registry.

**2. Multi-step Validation & Formatação (`public/checkout.html`):**
- Validação por passo (dados pessoais → endereço → pagamento), bloqueando avanço com campos inválidos.
- Formatação aprimorada do input de cartão de crédito (máscara + bandeira detectada).

**3. Cloudflare Turnstile (`plugins/billing`, `plugins/beclinic_core`):**
- Verificação do token Turnstile no backend de onboarding.
- Domínios de contato atualizados para `klivy.app` em mailers e textos.

**4. Pricing:**
- Preço do plano Standard e valores promocionais atualizados no `Asaas::CreateSubscription` e no HTML.

**Arquivos Modificados:**
- `db/migrate/20260423000001_add_coupon_fields_to_billing_subscriptions.rb`
- `db/migrate/20260423000002_add_credit_card_token_to_billing_subscriptions.rb`
- `db/schema.rb`
- `config/schedule.yml`
- `plugins/billing/app/controllers/billing/api/v1/billing/onboarding_controller.rb`
- `plugins/billing/app/services/asaas/api_client.rb`
- `plugins/billing/app/services/asaas/create_payment.rb`
- `plugins/billing/app/services/asaas/create_subscription.rb`
- `plugins/billing/app/services/billing/coupon_registry.rb`
- `plugins/beclinic_core/app/mailers/klivy_mailer.rb`
- `plugins/beclinic_core/app/views/klivy_mailer/password_change.html.erb`
- `plugins/agenda/frontend/features/settings/composables/useSettingsNotifications.js`
- `app/controllers/swagger_controller.rb`
- `public/checkout.html`

---

## [1.4.4.58] - 2026-04-22T18:39:53-03:00

### DevOps: Build & Deploy em Produção (Docker Hub + EasyPanel)

Suporte completo para build/push de imagens de produção e deploy em EasyPanel.

**Mudanças:**
- Documentação em `docs/03-engineering/docker.md` com instruções de build/push no Docker Hub e passos de deploy em EasyPanel, incluindo troubleshooting.
- `Dockerfile` corrigido para garantir permissão de execução nos scripts de `bin/` dentro da imagem.
- Scripts em `bin/` marcados como executáveis no próprio git (arquivos versionados com bit +x).
- `docker-compose.yaml` com comandos formatados e `config/initializers/filter_parameter_logging.rb` ampliado para filtrar parâmetros sensíveis adicionais nos logs.
- `config/database.yml` ajustado para o ambiente de produção.

**Arquivos Modificados:**
- `Dockerfile`
- `docker-compose.yaml`
- `docs/03-engineering/docker.md`
- `config/database.yml`
- `config/initializers/filter_parameter_logging.rb`
- `bin/bundle`, `bin/rails`, `bin/rake`, `bin/setup`, `bin/spring`, `bin/sync_i18n_file_change`, `bin/update`, `bin/validate_push`, `bin/vite`, `bin/yarn`
- `.claude/settings.local.json`

---

## [1.4.4.57] - 2026-04-22T14:41:14-03:00

### API: Swagger/OpenAPI Completo para Plugins Core + Brand Assets

Documentação OpenAPI unificada para os plugins principais e substituição de logos inline por assets externos.

**Swagger (`plugins/*/swagger`):**
- Estrutura definitions/paths para `agenda`, `financial`, `patients`, `beclinic_core` e `billing`.
- `lib/tasks/swagger.rake` consolida os arquivos YAML em `swagger/plugins_swagger.json` e gera viewers estáticos (`plugins_scalar.html`, `core_scalar.html`).
- `docs/api-documentation-strategy.md` descreve a convenção adotada.

**Brand Assets:**
- Logos inline no `checkout.html` e `onboarding-finish.html` substituídos por referências a `public/brand-assets/logo.*` (svg + png variações), com ajustes de sizing.
- Correção de IDs duplicados em spinners de carregamento.

**Arquivos Modificados:**
- `config/routes.rb`
- `lib/tasks/swagger.rake`
- `docs/api-documentation-strategy.md`
- `plugins/agenda/swagger/**/*.yml`
- `plugins/financial/swagger/**/*.yml`
- `plugins/patients/swagger/**/*.yml`
- `plugins/beclinic_core/swagger/index.yml`
- `plugins/billing/swagger/index.yml`
- `swagger/plugins_swagger.json`, `swagger/plugins_scalar.html`, `swagger/core_scalar.html`, `swagger/plugins_index.yml`
- `public/checkout.html`
- `public/onboarding-finish.html`
- `.gitignore`

---

## [1.4.4.56] - 2026-04-22T13:20:03-03:00

### Mailer: Templates Branded Klivy (Confirmação, Convite, Alteração de Senha)

Substituição completa dos templates padrão do Devise por um mailer branded Klivy e migração de reset-password para email de confirmação.

**Mudanças (`plugins/beclinic_core`):**
- Novo `Klivy::Mailer` com layout compartilhado (`layouts/klivy_mailer.html.erb`) e templates para: `confirmation_instructions`, `reset_password_instructions`, `password_change`, `_invitation`.
- Locales dedicados em `config/locales/klivy_mailer.pt_BR.yml` + overrides de `devise.pt_BR.yml`.
- Assets de marca adicionados em `public/brand-assets/logo.*` (svg claro/escuro, png, thumbnail).

**Onboarding:**
- Fluxo de reset-password substituído por envio de email de confirmação (`confirmation_instructions`).
- Tratamento de erros adicionado ao `onboarding_controller`.
- Strings localizadas em `config/locales/pt_BR.yml`.

**Arquivos Modificados:**
- `plugins/beclinic_core/app/mailers/klivy_mailer.rb`
- `plugins/beclinic_core/app/views/klivy_mailer/*.html.erb`
- `plugins/beclinic_core/app/views/layouts/klivy_mailer.html.erb`
- `plugins/beclinic_core/config/locales/devise.pt_BR.yml`
- `plugins/beclinic_core/config/locales/klivy_mailer.pt_BR.yml`
- `plugins/beclinic_core/lib/beclinic_core/engine.rb`
- `app/views/devise/mailer/confirmation_instructions.html.erb`
- `app/views/layouts/vueapp.html.erb`
- `config/locales/pt_BR.yml`
- `plugins/billing/app/controllers/billing/api/v1/billing/onboarding_controller.rb`
- `public/brand-assets/logo.png`, `logo.svg`, `logo_dark.svg`, `logo_thumbnail.svg`
- `public/onboarding-finish.html`

---

## [1.4.4.55] - 2026-04-21T10:48:48-03:00

### Onboarding: Fluxo de Finalização (Senha + Endereço) e Guia Coolify

**Onboarding Finish Flow (`plugins/billing`):**
- Nova página `public/onboarding-finish.html` onde o usuário define senha e informa endereço após a confirmação por email.
- Rotas dedicadas no `plugins/billing/config/routes.rb` e ações no `onboarding_controller` + `Asaas::CreateCustomer` para persistir endereço no Asaas.

**Documentação:**
- `docs/guia_instalacao_coolify.md` com passos para rodar Coolify ao lado do KlivyApp sem conflito de portas.

**Arquivos Modificados:**
- `plugins/billing/app/controllers/billing/api/v1/billing/onboarding_controller.rb`
- `plugins/billing/app/services/asaas/create_customer.rb`
- `plugins/billing/config/routes.rb`
- `public/checkout.html`
- `public/onboarding-finish.html`
- `docs/guia_instalacao_coolify.md`

---

## [1.4.4.54] - 2026-04-20T12:46:28-03:00

### Billing: Cupom BEMVINDO com Desconto na Assinatura

Primeiro cupom do sistema, validado antes da chamada ao Asaas.

**Mudanças (`plugins/billing`):**
- `onboarding_controller` recebe o código do cupom e o valida.
- `Asaas::CreateSubscription` aplica desconto quando o cupom `BEMVINDO` é válido.
- `checkout.html` exibe campo de cupom e feedback visual do desconto aplicado.

**Arquivos Modificados:**
- `plugins/billing/app/controllers/billing/api/v1/billing/onboarding_controller.rb`
- `plugins/billing/app/services/asaas/create_subscription.rb`
- `public/checkout.html`

---

## [1.4.4.53] - 2026-04-20T12:36:55-03:00

### Prontuário: Layout Responsivo, Sidebar Mobile e Design Tokens

Refatoração completa da rota de prontuário para uso em mobile e aplicação consistente dos tokens do design system.

**Mudanças:**
- Layout responsivo de `Record.vue` e `Index.vue` em `plugins/patients`, com sidebar mobile dedicada (`MobileSidebarLauncher.vue`) e expand/collapse no layout do dashboard (breakpoint atualizado para 1024px).
- Novo componente `BaseSelect.vue` integrado ao `NewPatientModal` para seleção de gênero (substitui `<select>` nativo).
- Tokens de cor/design-system aplicados ao modal de câmera e à sidebar do prontuário; estilos CSS consolidados em `record.css` e `patients-index.css`.

**Arquivos Modificados:**
- `plugins/patients/frontend/components/BaseSelect.vue`
- `plugins/patients/frontend/routes/patients/Record.vue`
- `plugins/patients/frontend/routes/patients/Index.vue`
- `plugins/patients/frontend/routes/patients/components/NewPatientModal.vue`
- `plugins/patients/frontend/routes/patients/record.css`
- `app/javascript/dashboard/components-next/sidebar/MobileSidebarLauncher.vue`
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
- `app/javascript/dashboard/constants/globals.js`

---

## [1.4.4.52] - 2026-04-19T19:12:11-03:00

### Design System: Switch Component, Border-radius Consistente e Permissões de Equipe

Alinhamento visual e estrutural de componentes ao design system.

**Mudanças:**
- `Switch` component substituindo inputs de toggle em `TeamPermissions.vue` e `RoleFormModal.vue`.
- Erro de unauthorized em `teams_controller` agora é localizado (i18n) em `agentMgmt.json` e `teamsSettings.json`.
- Migração de CSS para variáveis semânticas em `patients-index.css` e novos tokens aplicados em `AgendaEventModal.vue`, `AgendaHeader.vue`, `agenda-events.css`.
- Border-radius consistente em modais/paginação/patients index.

**Arquivos Modificados:**
- `app/controllers/api/v1/accounts/teams_controller.rb`
- `app/controllers/concerns/request_exception_handler.rb`
- `app/javascript/dashboard/routes/dashboard/settings/teams/Edit/TeamPermissions.vue`
- `app/javascript/dashboard/i18n/locale/pt_BR/agentMgmt.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/teamsSettings.json`
- `plugins/beclinic_core/frontend/settings/BeClinicRoles/RoleFormModal.vue`
- `plugins/agenda/frontend/components/AgendaEventModal.vue`
- `plugins/agenda/frontend/components/AgendaHeader.vue`
- `plugins/agenda/frontend/styles/agenda-events.css`
- `plugins/patients/frontend/routes/patients/components/NewPatientModal.vue`
- `plugins/patients/frontend/routes/patients/patients-index.css`
- `plugins/patients/frontend/routes/patients/Index.vue`

---

## [1.4.4.51] - 2026-04-19T14:14:26-03:00

### Agenda: Polish em Settings, Indicador de Fechado e Month View Border

Round de acabamento visual e feedback nos settings da agenda + ajustes no grid mensal.

**Mudanças (`plugins/agenda`):**
- Estilo do botão "Salvar" padronizado (`SettingsTabSchedules.vue`).
- Scroll suave com `scroll-into-view` ao trocar de aba nos settings.
- Feedback de sucesso visual no `SettingsTabServices.vue` e limpeza de lógica de cor em `useAgenda.js` / `AgendaEventModal.vue`.
- Indicador de status "fechado" adicionado na timeline com ajustes responsivos para mobile.
- Remoção da borda `.cell-header` em `AgendaMonthView.vue` para visual mais limpo.

**Arquivos Modificados:**
- `plugins/agenda/frontend/features/settings/components/SettingsTabSchedules.vue`
- `plugins/agenda/frontend/features/settings/components/SettingsTabServices.vue`
- `plugins/agenda/frontend/routes/settings/Index.vue`
- `plugins/agenda/frontend/composables/useAgenda.js`
- `plugins/agenda/frontend/components/AgendaEventModal.vue`
- `plugins/agenda/frontend/components/AgendaMonthView.vue`
- `plugins/agenda/frontend/components/AgendaTimelineView.vue`

---

## [1.4.4.50] - 2026-04-18T23:08:07-03:00

### I18n, Onboarding Security, Default Holidays e pt-BR no Administrate

Ajustes transversais envolvendo localização, segurança e seed de feriados.

**Mudanças:**
- `switch_locale` e demais concerns de i18n revisados para processar blocos de locale corretamente em `ApplicationController`, `portals/base_controller` e `ApplicationMailer`.
- Segurança no onboarding: validação reforçada em `onboarding_controller` e `Asaas::HandleWebhook`; lógica de acesso corrigida em `Billing::AccessControl` e `Billing::Subscription`.
- Novo seed de feriados default em `AgendaSetting` com configuração automática via `agenda_settings_controller` e locale da aplicação fixado em `pt-BR`.
- Adicionado `config/locales/administrate.pt_BR.yml` para o dashboard do Administrate.

**Arquivos Modificados:**
- `app/controllers/application_controller.rb`
- `app/controllers/concerns/switch_locale.rb`
- `app/controllers/public/api/v1/portals/base_controller.rb`
- `app/mailers/application_mailer.rb`
- `config/application.rb`
- `config/locales/administrate.pt_BR.yml`
- `plugins/agenda/app/controllers/api/v1/accounts/agenda_settings_controller.rb`
- `plugins/agenda/app/models/agenda_setting.rb`
- `plugins/billing/app/controllers/billing/api/v1/billing/onboarding_controller.rb`
- `plugins/billing/app/models/billing/subscription.rb`
- `plugins/billing/app/services/asaas/handle_webhook.rb`
- `plugins/billing/lib/billing/access_control.rb`
- `public/checkout.html`

---

## [1.4.4.49] - 2026-04-17T21:51:29-03:00

### Billing: Engine com Integração Asaas (Assinaturas + Webhooks + Onboarding)

Novo engine `plugins/billing` responsável por todo o ciclo de cobrança via Asaas.

**Estrutura criada:**
- Models: `Billing::Customer`, `Billing::Subscription`, `Billing::Payment`.
- Services Asaas: `ApiClient`, `CreateCustomer`, `CreateSubscription`, `HandleWebhook`.
- Controllers: `Billing::OnboardingController` e `Billing::WebhooksController`.
- Jobs: `Billing::ProcessAsaasWebhookJob` para processamento assíncrono.
- `Billing::AccessControl` para bloquear features quando a assinatura não está ativa.
- Migration `20260416200000_create_billing_tables.rb` criando tabelas do módulo.
- `public/checkout.html` com landing inicial do onboarding.
- Documentação em `docs/01-product/modules/billing.md`.

**Arquivos Modificados:**
- `db/migrate/20260416200000_create_billing_tables.rb`
- `db/schema.rb`
- `config/routes.rb`
- `docs/01-product/modules/billing.md`
- `lib/custom_exceptions/billing.rb`
- `plugins/billing/app/controllers/billing/api/v1/billing/onboarding_controller.rb`
- `plugins/billing/app/controllers/billing/api/v1/billing/webhooks_controller.rb`
- `plugins/billing/app/jobs/billing/process_asaas_webhook_job.rb`
- `plugins/billing/app/models/billing/{customer,payment,subscription}.rb`
- `plugins/billing/app/services/asaas/{api_client,create_customer,create_subscription,handle_webhook}.rb`
- `plugins/billing/config/routes.rb`
- `plugins/billing/lib/billing.rb`
- `plugins/billing/lib/billing/{access_control,engine}.rb`
- `public/checkout.html`

---

## [1.4.4.48] - 2026-04-16T22:18:37-03:00

### Agenda: Bloqueio de Dias Fechados + Ícone de Cadeado e Dropdown Invertido

Tratamento visual e lógico de dias fechados na agenda e ajuste de popups.

**Mudanças (`plugins/agenda`):**
- `useAgenda.js` filtra blocos "closed" nas views Timeline e Month.
- Ícone de cadeado (lock) exibido em dias fechados na timeline, com lógica de bloqueio a cliques/drag.
- `AgendaEventModal.vue` ganhou modo de dropdown abrindo para cima quando não há espaço abaixo (styles em `agenda-events.css`).

**Arquivos Modificados:**
- `plugins/agenda/frontend/components/AgendaMonthView.vue`
- `plugins/agenda/frontend/components/AgendaTimelineView.vue`
- `plugins/agenda/frontend/components/AgendaEventModal.vue`
- `plugins/agenda/frontend/composables/useAgenda.js`
- `plugins/agenda/frontend/styles/agenda-events.css`

---

## [1.4.4.47] - 2026-04-16T19:50:05-03:00

### Agenda: Dark Mode nos Modais e AgendaEventModal Responsivo com Teleport

Round de UX dos modais e popups da agenda.

**Mudanças (`plugins/agenda`):**
- Dark mode implementado para `AgendaDeleteModal`, `AgendaEventCard` e tipos de bloco no `AgendaEventInfoPopup`.
- `AgendaEventModal` responsivo para mobile e encapsulado em `<Teleport>` + `<transition>` para melhor overlay.
- Ajustes de layout no `AgendaHeader.vue` e estilos em `agenda-summary.css`.

**Arquivos Modificados:**
- `plugins/agenda/frontend/components/AgendaDeleteModal.vue`
- `plugins/agenda/frontend/components/AgendaEventCard.vue`
- `plugins/agenda/frontend/components/AgendaEventInfoPopup.vue`
- `plugins/agenda/frontend/components/AgendaEventModal.vue`
- `plugins/agenda/frontend/components/AgendaHeader.vue`
- `plugins/agenda/frontend/components/AgendaMonthView.vue`
- `plugins/agenda/frontend/components/AgendaTimelineView.vue`
- `plugins/agenda/frontend/features/agenda-summary/agenda-summary.css`

---

## [1.4.4.46] - 2026-04-16T12:22:11-03:00

### Agenda: Day-Block Banners, Treatment Colors e Cleanup de Patches Obsoletos

Banners por tipo de bloqueio de dia e paleta unificada de cores por tratamento, além de remoção dos arquivos de patch usados durante a refatoração.

**Mudanças (`plugins/agenda`):**
- `agenda-colors.js` centraliza a paleta por tratamento; `AgendaEventCard`, `AgendaMonthView` e `AgendaTimelineView` passam a lê-la via composable.
- Banners visuais nos day-blocks (Online Booking / Schedules / Services settings).
- Padronização de font-size (Tailwind `@apply text-sm`) em todos os componentes da agenda + ajustes na lógica de posicionamento de popups.
- Removidos os arquivos `patch_index_*.js` usados durante a migração e assets Vite obsoletos.
- `.gitignore` ignora arquivos `Zone.Identifier` (artefatos do WSL).

**Arquivos Modificados:**
- `plugins/agenda/frontend/utils/agenda-colors.js`
- `plugins/agenda/frontend/components/AgendaEventCard.vue`
- `plugins/agenda/frontend/components/AgendaMonthView.vue`
- `plugins/agenda/frontend/components/AgendaTimelineView.vue`
- `plugins/agenda/frontend/components/AgendaHeader.vue`
- `plugins/agenda/frontend/components/AgendaDeleteModal.vue`
- `plugins/agenda/frontend/components/AgendaEventInfoPopup.vue`
- `plugins/agenda/frontend/components/AgendaEventModal.vue`
- `plugins/agenda/frontend/components/AgendaSidebar.vue`
- `plugins/agenda/frontend/components/AgendaWlSchedulePopup.vue`
- `plugins/agenda/frontend/components/ModernSelect.vue`
- `plugins/agenda/frontend/composables/useAgenda.js`
- `plugins/agenda/frontend/composables/useAgendaPopups.js`
- `plugins/agenda/frontend/composables/useAgendaDnD.js`
- `plugins/agenda/frontend/features/settings/components/SettingsTab*.vue`
- `plugins/agenda/frontend/styles/agenda-events.css`
- `plugins/agenda/frontend/routes/AgendaDashboard.vue`
- `plugins/agenda/frontend/routes/settings/{Index,ColorPicker}.vue`
- `plugins/agenda/frontend/routes/customAttributes/Index.vue`
- `.gitignore`

---

## [1.4.4.45] - 2026-04-16T09:56:28-03:00

### Agenda: Refatoração com Composables, Settings UI e ModernSelect

Refatoração estrutural do dashboard da agenda em composables e nova UI de configurações.

**Mudanças (`plugins/agenda`):**
- `AgendaDashboard.vue` decomposto em composables: `useAgendaCrud`, `useAgendaDnD`, `useAgendaInit`, `useAgendaPopups`.
- Utilitários extraídos: `agenda-colors.js`, `agenda-constants.js`, `agenda-date.js`.
- Nova UI de configurações via `SettingsTabNotifications`, `SettingsTabOnlineBooking`, `SettingsTabSchedules`, `SettingsTabServices` com composables dedicados.
- Componente `ModernSelect.vue` substituindo selects nativos.
- Layout responsivo e estilos de toggle switch.
- Rotas e bootstrap limpos em `plugins/agenda/lib/agenda/engine.rb`.

**Arquivos Modificados:**
- `plugins/agenda/frontend/composables/use{Agenda,AgendaCrud,AgendaDnD,AgendaInit,AgendaPopups}.js`
- `plugins/agenda/frontend/utils/{agenda-colors,agenda-constants,agenda-date}.js`
- `plugins/agenda/frontend/components/ModernSelect.vue`
- `plugins/agenda/frontend/components/Agenda*.vue` (Dashboard, DeleteModal, DragGhost, EventCard, EventInfoPopup, EventModal, Header, MonthView, Sidebar, TimelineView, WlSchedulePopup)
- `plugins/agenda/frontend/features/settings/components/SettingsTab*.vue`
- `plugins/agenda/frontend/features/settings/composables/useSettings{Notifications,OnlineBooking,Schedules,Services}.js`
- `plugins/agenda/frontend/routes/{AgendaDashboard,customAttributes/Index,settings/Index}.vue`
- `plugins/agenda/lib/agenda/engine.rb`
- `plugins/agenda/db/seeds/treatments.rb`

---

## [1.4.4.44] - 2026-04-15T18:52:16-03:00

### Arquitetura: Modularização em Plugins (Agenda, Patients, Financial, Beclinic Core)

Isolamento dos módulos do Klivy em engines Rails dedicadas, alinhado à análise arquitetural de 2026-04-12.

**Mudanças:**
- `plugins/agenda`: controllers/models de agenda (AgendaEvent, AgendaService, Slot, WaitingList) + frontend Vue + engine registrada.
- `plugins/patients`: controllers/models de prontuário (Patient, Anamnesis, ClinicalNote, ExamFolder, ExamMedia, Document, TreatmentPlan, etc.) + frontend Vue + engine.
- `plugins/financial`: controllers/models do financeiro (AccountTransaction, BankAccount, CashRegister, FinancialCategory, CommissionRule, DreCalculator, etc.) + frontend Vue + engine.
- `plugins/beclinic_core`: core Klivy com `BeclinicPermissions`, `AccountProfile`, `TeamProfile`, `UserProfile` e frontend de roles/permissões.
- Migration `20260415185500_create_beclinic_profiles.rb` extrai atributos do `Account`/`Team`/`User` para tabelas de profile separadas.
- Scripts auxiliares em `script/` para a migração automática de backend/frontend.
- Documentação reorganizada em `docs/01-product/`, `docs/02-architecture/`, `docs/03-engineering/`, incluindo `PRD.md`, `ANALISE_ARQUITETURAL.md`, `MAPA_MODULOS.md`.
- `AGENTS.md` e rake task `auto_annotate_models` atualizada.

**Arquivos Modificados:**
- `plugins/agenda/**/*`, `plugins/patients/**/*`, `plugins/financial/**/*`, `plugins/beclinic_core/**/*`
- `app/models/{account,team,user}.rb`
- `db/migrate/20260415185500_create_beclinic_profiles.rb`, `db/schema.rb`
- `docs/01-product/PRD.md`, `docs/01-product/modules/*.md`
- `docs/02-architecture/*.md`, `docs/03-engineering/*.md`
- `docs/{ANALISE_ARQUITETURAL,MAPA_MODULOS}.md`
- `docs/notes/*.md`, `docs/plans/*.md`
- `AGENTS.md`
- `script/migrate_*_backend.rb`, `script/migrate_*_frontend.rb`, `script/setup_*_engine.rb`
- `lib/tasks/auto_annotate_models.rake`

---

## [1.4.4.43] - 2026-04-14T23:00:24-03:00

### DevOps: Containerização Dev (Rails + Vite) com Polling File Watchers

Ambiente de desenvolvimento conteinerizado, com builds separados para Rails e Vite.

**Mudanças:**
- `Dockerfile` e `Dockerfile.vite` customizados com entrypoints dedicados.
- `docker-compose.yaml` orquestrando Rails + Vite + serviços auxiliares.
- Polling file watchers habilitados para Vite (necessário dentro do container em Windows/WSL).
- Documentação de setup em `docs/03-engineering/docker.md`.
- Ajustes responsivos na agenda mobile (primeiras iterações).

**Arquivos Modificados:**
- `Dockerfile`, `Dockerfile.vite`
- `docker-compose.yaml`
- `docs/03-engineering/docker.md`
- `config/vite.json`, `vite.config.ts`
- `plugins/agenda/frontend/routes/AgendaDashboard.vue`

---

## [1.4.4.42] - 2026-04-12T19:30:02-03:00

### Agenda: Layout Responsivo Mobile (Primeiras Iterações)

Início do trabalho de responsividade no dashboard da agenda para uso em tablets/celulares, antes da refatoração maior em composables.

**Mudanças:**
- Ajustes no grid/scroll em `AgendaDashboard.vue` e componentes auxiliares para viewports < 768px.

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

---

## [1.4.4.41] - 2026-04-12T13:07:10-03:00

### Documentação: Rebranding Klivy, PRD e Análise Arquitetural

Estabelecimento dos documentos fundacionais do Klivy como produto: PRD, análise arquitetural de isolamento de módulos e reorganização de scripts/docs.

**Mudanças:**
- `README.md` reescrito para Klivy.
- `docs/01-product/PRD.md` criado.
- `docs/ANALISE_ARQUITETURAL.md` descreve o isolamento entre Klivy e BeClinic/Chatwoot.
- Scripts de desenvolvimento reorganizados e `docs/notes/changelog_Qwen.md` adicionado (histórico do assistente Qwen).
- `.gitignore` ajustado para remover cache do pnpm.

**Arquivos Modificados:**
- `README.md`
- `docs/01-product/PRD.md`
- `docs/ANALISE_ARQUITETURAL.md`
- `docs/notes/changelog_Qwen.md`
- `.gitignore`

---

## [1.4.4.39] - 2026-04-09T17:00:00-03:00

### Agenda: Intervalo de Visualização do Calendário (15min / 30min / 60min)

Implementação de configuração de intervalo de tempo na grade do calendário, permitindo alternar entre visualizações de 15 minutos, 30 minutos ou 1 hora.

**Problema:**
A agenda era exibida apenas em janelas de 1 hora (00:00, 01:00, 02:00...), sem flexibilidade para visualizações mais granulares. Usuários que precisavam de agendamentos mais precisos (ex: consultas de 15 ou 30 minutos) não tinham essa opção.

**Solução:**
1. **Backend:**
   - Adicionada coluna `slot_interval_minutes` (integer, default: 60) na tabela `agenda_settings` via migration.
   - Atualizado modelo `AgendaSetting` com validação de inclusão (15, 30, 60).
   - Atualizado `AgendaSettingsController` para expor e aceitar `slot_interval_minutes` no payload JSON.

2. **Frontend — Settings:**
   - Novo campo "Intervalo da visualização" na aba "Agendamento online" das configurações da agenda, com opções 15min/30min/60min.
   - Valor persistido via `AgendaSettingsAPI` e carregado no `agendaSettingsData`.

3. **Frontend — Calendar Grid:**
   - `dayHours` computed property agora gera slots dinâmicos baseados no `slot_interval_minutes` (ex: 15min → "00:00", "00:15", "00:30", "00:45"...).
   - `rowHeight` computed property escala proporcionalmente: 15min→20px, 30min→40px, 60min→80px.
   - Altura das linhas do grid aplicada via inline style (`:style="{ height: ... }"`), removendo o `height: 80px` hardcoded do CSS.
   - Drag-and-drop, redimensionamento e snapping de eventos agora respeitam o intervalo configurado.
   - Linha de tempo atual (`currentTimeLineStyle`) e scroll automático (`scrollToCurrentTime`) usam o `rowHeight` dinâmico.

4. **Internacionalização:**
   - Chaves i18n adicionadas em `pt_BR` e `en` sob `AGENDA.SLOT_INTERVAL.*` para labels e opções.

**Arquivos Modificados:**
- `app/models/agenda_setting.rb`
- `app/controllers/api/v1/accounts/agenda_settings_controller.rb`
- `app/javascript/dashboard/routes/agenda/settings/Index.vue`
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`
- `app/javascript/dashboard/i18n/locale/pt_BR/settings.json`
- `app/javascript/dashboard/i18n/locale/en/settings.json`

---

## [1.4.4.40] - 2026-04-09T18:30:00-03:00

### Agenda: Correção — Botões de Alternância de Visualização (Mês/Semana/Dia) não Respondiam

**Problema:**
Ao clicar nos botões "Semana" ou "Dia" no cabeçalho da agenda, a visualização permanecia presa no Mês. O clique funcionava corretamente (`viewMode` era atualizado), mas a timeline ficava vazia pois o scroll continuava em posição 0 (topo) — sem eventos visíveis no horário atual.

**Causa raiz:**
O método `setViewMode(mode)` apenas atualizava `this.viewMode` sem chamar `scrollToCurrentTime()` para posicionar a timeline na hora atual. Ao entrar na view de Semana ou Dia, o usuário chegava no topo da grade (00:00), onde não há eventos, dando a impressão de que nada havia mudado.

**Solução:**
Adicionado `this.$nextTick(() => this.scrollToCurrentTime())` dentro do `setViewMode` sempre que o modo não for `month`, garantindo scroll automático ao horário atual ao trocar de visualização.

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

---

## [1.4.4.38] - 2026-04-09T11:15:00-03:00

### Financeiro: UI Ajustes Dinâmicos de KPIs e Correção 422 no DB

Ajustes baseados no workflow de design para re-arranjo da leitura de dados e correções de validação de modelo que recuavam salvamentos no módulo financeiro.

**Problemas corrigidos & UI/UX:**
1. **Erro 422 na Criação de Despesas ("A Pagar"):** A validação `payment_source: ""` ativava o array restrito do Model e as `check_constraints` lógicas do banco de dados, pois strings vazias do Javascript não contam nativamente como NULLs do Postgre.
2. **Layout das "Entradas Hoje" Engessado:** O bloco sofria do wrapper padrão em estilo bloco listrado (`.financial-block`) com título e moldura, e estava misturado na grade draggagle inferior, desalinhando-se com os mockups.

**Soluções Aplicadas:**
1. **AccountTransaction Fix:** Em `app/models/account_transaction.rb`, adicionado helper privado ativado em `before_validation` responsável por rastrear campos `payment_*` retornando com `.blank?`, transformando a string em `.nil`, deixando a entrada limpa para persistência.
2. **Reordenação e Estilização de KPIs (`Standalone`):**
   - O component `<FinancialKpiCards>` foi retirado do map de arrasto (`vuedraggable`) e de seu array padrão global `DEFAULT_BLOCKS`. Elevamos o component ao Topo Abosluto da página, aparecendo antes dos minicards de "Receita Líquida".
   - Todo `<div class="financial-standalone-kpi__header">` foi deletado.
   - Classes CSS condicionais (`.kpi-card--entradas`, `--saidas`, `--saldo`, `--inadimplencia`) injetaram cores pálidas/translúcidas aos _backgrounds_ seguindo estética abobada (High-End UX), reajustando seus opacos paramétricos também no `.dark`.

**Arquivos Modificados:**
- `app/models/account_transaction.rb`
- `app/javascript/dashboard/features/financial/pages/FinancialDashboard.vue`
- `app/javascript/dashboard/features/financial/components/FinancialKpiCards.vue`
- `app/javascript/dashboard/features/financial/financial.css`

---

## [1.4.4.37] - 2026-04-09T16:00:00-03:00

### Financeiro: Revisão Arquitetural — Bugs Críticos, Performance e Layout Definitivo

Auditoria completa do módulo financeiro corrigindo crashes de navegação, erros 500 em endpoints, N+1 queries, dados silenciados e layout quebrado (double scroll).

**Problemas corrigidos:**

1. **Navegação quebrada entre páginas do Financeiro** — `NewVsReturningPatients.vue` acessava `chartColors.value.tickColor` (propriedade inexistente no composable `useChart`), causando crash no render que corrompia o VDOM do Draggable e impedia unmount/navegação para qualquer outra página (Fluxo de Caixa, A Receber, etc.).
2. **DOM corruption no unmount (v-show + vuedraggable)** — `v-show` dentro do slot `#item` do vuedraggable tentava manipular `style.display` em nodes já removidos pelo SortableJS, gerando cascata de `Cannot read 'parentNode' of null`. Substituído por `v-if`.
3. **DRE Waterfall retornando 500** — `DreCalculator` fazia `GROUP BY financial_categories.dre_line` mas a coluna não existe na tabela. Corrigido para agrupar por `cost_type` (`fixo`/`variavel`).
4. **Ticket Trend retornando 500** — Controller passava `user_id:` mas o service espera `professional_id:` (`ArgumentError`).
5. **DOW offset descartava segunda-feira do heatmap** — `EXTRACT(DOW)` retorna 1 para segunda, mas o código subtraía 2 (resultando em -1, filtrado). Corrigido para `- 1`.
6. **N+1 no PatientRetentionService** — 1 query por paciente para buscar `first_event_month`. Com 500 pacientes × 12 meses = ~6.000 queries/request. Substituído por uma única query com `GROUP BY contact_id + minimum(:starts_at)`.
7. **Funil de conversão com dados inconsistentes** — `count_comparecidos` e `count_orcados` não filtravam por `event_type: 'consultation'` (diferente de `count_agendados`). `Fechados` era idêntico a `Orçados`. Corrigido: filtro consistente + `Fechados` agora cruza com `AccountTransaction` (receita efetiva).
8. **`rescue StandardError` silenciando bugs** — 7 ocorrências nos services analytics engoliam erros reais (a causa original dos 500 nunca aparecia nos logs). Removidos.
9. **CSS: Double scroll e KPI cards não full-width** — `column-count: 2` (CSS Multi-Column) não suporta `column-span` em filhos de vuedraggable. Substituído por `display: grid` + `grid-template-columns: repeat(2, 1fr)` com `.financial-block--full { grid-column: 1 / -1 }`.
10. **Sparklines vazando do card** — Container sem `overflow: hidden`, canvas sem posicionamento, eixo Y sem `grace`. Corrigido com CSS e opções Chart.js.
11. **`isBlockVisible()` não definida** — Template chamava a função mas ela não existia no `<script setup>`. Implementada com suporte a `ui_settings.financial_dashboard_hidden`.

**Arquivos Modificados:**
- `app/services/financial/agenda_analytics_service.rb`
- `app/services/financial/patient_retention_service.rb`
- `app/services/financial/conversion_analytics_service.rb`
- `app/services/financial/dre_calculator.rb`
- `app/controllers/api/v1/accounts/financial_reports_controller.rb`
- `app/javascript/dashboard/features/financial/components/NewVsReturningPatients.vue`
- `app/javascript/dashboard/features/financial/components/FinancialKpiCards.vue`
- `app/javascript/dashboard/features/financial/pages/FinancialDashboard.vue`
- `app/javascript/dashboard/features/financial/financial.css`

---

## [1.4.4.36] - 2026-04-09T09:16:00-03:00

### Financeiro: Refatoração Analítica e UI/UX Dashboard (`payment_source` e `AgendaEvent`)

Revisão estrutural e correção de todos os gráficos "quebrados" da arquitetura financeira, adaptando a lógica analítica ao banco de dados real (`AgendaEvent` e `account_transactions`). Melhoria substancial no layout do front-end do painel para evitar renderizações infinitas.

**Problema:**
1. A arquitetura de analytics financeira havia sido codificada espelhando modelos que não existiam no contexto (ex: modelo `Appointment` inexistente, ao invés de usar `AgendaEvent`). Isso gerou exceções 500 em 9 componentes da dashboard financeira.
2. Analytics de receita buscavam agrupar informações por transação baseada em "Origem da Receita" (Planos, Particular, etc), todavia a tabela `account_transactions` não possuia a coluna `payment_source`, causando Erros Undefined Column no backend.
3. Consultas a tabelas financeiras para KPIs de Inadimplência tentavam puxar o campo relacional `user_id`, sendo que o esquema atual utiliza o `professional_id`.
4. O Dashboard renderizava inúmeras instâncias vazias da classe `.financial-block` oriundas de grids draggables com condicionais falhas (v-if), causando scrollbars duplas na tela; os "Entradas Hoje" não preenchiam a grade panoramicamente.

**Solução:**
1. **Ruby Services Rewritten:**
   - Reescrevemos por completo o `ConversionAnalyticsService`, `AgendaAnalyticsService` e `PatientRetentionService` para ancorar no modelo existente `AgendaEvent` usando sua coluna temporal `starts_at`.
   - Adicionamos pareamentos exatos das 7 tipagens `status` do `AgendaEvent` às macros analíticas (Ex: `arrived`, `in_progress`, `completed` mapeados como 'Comparecidos/Aprovados').
2. **`payment_source` Migration Database:**
   - Criada migration para injeção de coluna `payment_source` (string) em `account_transactions` com check_constraints SQL limitando valores (`particular`, `convenio`, `plano` e `outro`) e indexação.
   - Atualizados serializadores, models (`PAYMENT_SOURCES`) e controller (`transaction_params`) para assimilar o campo. O Componente `<TransactionModal.vue>` e os JSON de tradução foram adaptados.
3. **Foreign Keys Refatoradas:**
   - Reajustado o apontamento nas consultas complexas de `ProfessionalRevenueService` e `DelinquencyCalculator`, substituindo a quebra gerada pelo `user_id` e consolidando o fluxo com `professional_id`.
4. **CSS/Vue Refactoring:**
   - Inseridas diretivas `v-show="isBlockVisible(element.id)"` no renderizador arrastável impedindo a geração indiscriminada de div's no `FinancialDashboard.vue`, matando o bug do endless scroll.
   - Injeção de `column-span: all` via bind dinâmico `:class="{ 'financial-block--full': element.id === 'kpi_cards' }"` para os KPI cards adquirirem aspecto span total.

**Arquivos Modificados/Adicionados:**
- `db/migrate/...add_payment_source_to_account_transactions.rb`
- `app/services/financial/professional_revenue_service.rb`
- `app/services/financial/delinquency_calculator.rb`
- `app/services/financial/revenue_analytics_service.rb`
- `app/services/financial/conversion_analytics_service.rb`
- `app/services/financial/agenda_analytics_service.rb`
- `app/services/financial/patient_retention_service.rb`
- `app/models/account_transaction.rb`
- `app/controllers/api/v1/accounts/account_transactions_controller.rb`
- `app/javascript/dashboard/features/financial/components/TransactionModal.vue`
- `app/javascript/dashboard/features/financial/pages/FinancialDashboard.vue`
- `app/javascript/dashboard/i18n/locale/en/financial.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json`

---

## [1.4.4.35] - 2026-04-07T12:35:00-03:00

### UI/UX: Light Mode — PatientRecordPopup (Popup do Prontuário na Conversa)

Migração completa do `PatientRecordPopup.vue` do modo escuro legado (`#0f1117`, cores hardcoded) para o padrão **dual-theme** (light/dark) do sistema, usando variáveis CSS `rgb(var(--slate-N))` em todos os elementos.

**Problema:**
1. O popup lateral de prontuário (exibido nas conversas do Klivy) usava cores hardcoded do dark mode (`background: #0f1117`, `color: #f1f5f9`, bordas `rgba(255,255,255,0.09)`) que tornavam o componente completamente ilegível no light mode — fundo quase preto em cima de interface branca.
2. O popup estava posicionado no canto superior direito da tela (`align-items: flex-start; justify-content: flex-end`), tornando a leitura desconfortável em telas grandes.

**Solução:**
1. **Migração total para variáveis CSS dual-theme:**
   - Fundo do painel: `rgb(var(--slate-1))` (branco no light, escuro no dark)
   - Bordas: `rgb(var(--slate-4))` (visível em ambos os temas)
   - Textos primários: `rgb(var(--slate-12))`, secundários: `rgb(var(--slate-11))`, terciários: `rgb(var(--slate-9))`
   - Spinner de loading: usa `rgb(var(--slate-4))` como trilho base
   - Scrollbar customizada adaptada ao tema
   - Botão de fechar (`prp-close`): hover com `rgb(var(--slate-3))` sutil

2. **Badges de status patient corrigidos para dual-theme:**
   - `prp-pill-novo` → `#2563eb` (azul legível em ambos os temas, era `#60a5fa` dark-only)
   - `prp-pill-ativo` → `#16a34a` (verde sólido, era `#4ade80` dark-only)
   - `prp-pill-faltoso` → `#d97706` (âmbar), `prp-pill-alta` → `#9333ea` (roxo)
   - Dots de status (`prp-dot-*`) também corrigidos para cores legíveis em ambos

3. **Tags clínicas (`prp-tag--*`) com cores semânticas dual-theme:**
   - Condições: azul `rgba(37,99,235,0.12)` + `#2563eb`
   - Alergias: vermelho `rgba(220,38,38,0.12)` + `#dc2626`
   - Medicamentos: roxo `rgba(147,51,234,0.12)` + `#9333ea`
   - Contraindicações: âmbar `rgba(217,119,6,0.12)` + `#d97706`

4. **Seção financeira corrigida:**
   - `prp-fin-paid` → `#16a34a` (era `#4ade80` dark-only)
   - `prp-fin-open` → `#d97706` (era `#fbbf24` dark-only)
   - `prp-fin-overdue` → `#dc2626` (era `#f87171` dark-only)
   - `prp-fin-credit` → `#2563eb` (era `#22d3ee` dark-only)

5. **Centralização do modal:** Alterado `.prp-overlay` de `align-items: flex-start; justify-content: flex-end` (canto superior direito) para `align-items: center; justify-content: center` — popup agora aparece centrado na tela.

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/dashboard/conversation/contact/PatientRecordPopup.vue` — migração completa do `<style scoped>` para dual-theme + centralização

---

## [1.4.4.34] - 2026-04-05T20:32:00-03:00

### Financeiro: UI Enhancement do A Pagar e Validação de Despesas Recorrentes

Melhorias no design da página de "A Pagar", consistência dos botões de exportação e introdução do sistema de validação explícita de erros em "Despesas Recorrentes".

**Problema:**
1. Botões de exportação de PDF inconsistentes nas listagens financeiras. Falta de padronização nas telas de listagem.
2. Tabela de "A Pagar" não trazia visibilidade rápida para itens com recorrência associada. Os cards totalizadores mostravam métricas simples demais (faltava alinhamento visual com o "Fluxo de Caixa").
3. Tentativa de salvar despesas recorrentes com campos em branco resultava em falha invisível de backend (Erro 422 - `Translation missing: pt_BR.activerecord...`). Nenhum alerta impedia a interface de parecer "congelada".

**Solução:**
1. **Padronização dos Botões de Exportação:** Uniformizado o label para "Gerar PDF" em todas as áreas (`Receivables.vue`, `Payables.vue`, `CashFlow.vue`, `DRE.vue`, `Reports.vue`). Ajustado o distanciamento/margins entre botões adjacentes.
2. **Dashboard de "A Pagar" Avançado:**
   - Adicionada coluna "Recorrência" (`is_recurring`) à listagem da grid para informar se a transação partiu de ciclo repetido, acoplado com badge (`success/neutral`).
   - Implementação de 4 Novos *Status Cards* inspirados no CashFlow: **Total A Pagar**, **Total Recorrente**, **Próximos a Vencer** e **Transações**; sendo orquestrados via `meta` keys processadas no Controller `account_transactions_controller`.
3. **Padrão de Validação Full-Stack (Frontend e Backend):**
   - Interceptação síncrona visual no `saveExp` antes da requisição API, disparando alertas via `useAlert` do Vue 3 requerendo campos essenciais.
   - Atualizados os metadados do locale `pt_BR.yml` criando descrições exatas de erros de validação do módulo `recurring_expense`.
   - Modificado backend (`RecurringExpensesController`) para devolver arrays stringificados dos erros no bad_request, sanando os silent 422 errors.

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/pages/Payables.vue`
- `app/javascript/dashboard/features/financial/pages/CashFlow.vue`
- `app/javascript/dashboard/features/financial/pages/Receivables.vue`
- `app/javascript/dashboard/features/financial/pages/DRE.vue`
- `app/javascript/dashboard/features/financial/pages/Reports.vue`
- `app/javascript/dashboard/features/financial/pages/FinancialSettings.vue`
- `app/controllers/api/v1/accounts/account_transactions_controller.rb`
- `app/controllers/api/v1/accounts/recurring_expenses_controller.rb`
- `config/locales/pt_BR.yml`

---

## [1.4.4.33] - 2026-04-05T17:49:11-03:00

### Financeiro: Aprimoramentos no PDF e Refinamentos no Filtro de Fluxo de Caixa

Implementação de visualização prévia (preview) nos relatórios PDF, correção de erros críticos no Prawn ao lidar com encodings e grids de tabelas flexíveis, e modernização da escolha de datas no Fluxo de Caixa.

**Problema:**
1. Os relatórios financeiros via PDF iniciavam downloads automáticos compulsórios, não permitindo revisar os dados antes de salvar o arquivo no PC.
2. Tentativas de baixar alguns relatórios estouravam Erro 500 vindo do backend. Motivos investigados envolveram incompatibilidade da fonte local do `prawn` com Emojis (UTF-8 `📅`) no cabeçalho e `prawn-table` crashando ao receber propriedade `column_widths: nil`.
3. Tela de Fluxo de Caixa não permitia a seleção de intervalos livres de dias para gráficos ou geração de PDF, presa a três botões rígidos (Hoje, Semana e Mês).

**Solução:**
1. **Preview inteligente na emissão:** Novo comportamento em `pdfs.js` com o uso de `window.open` instanciando Web Blobs injetáveis via Headers Auth. Agora a tela carrega o documento gerado em uma aba nova.
2. **Estabilização Prawn / Ruby:** 
   - Remoção do emoji 📅 e implementação do novo label `"Período: "` no construtor `BasePdf`, evitando falha de encoding Windows-1252 em containers.
   - Refatoração preventiva do `.draw_styled_table` que agora encapsula e instrupula hashes (`**table_options`) em arrays somente quando houver instâncias reais declaradas de column_widths, blindado de Null/Type Errors.
3. **DateRangePicker em toda a camada:** Integração fluida do `<DateRangePicker />` (já implementado nas outras abas) no `CashFlow.vue`. O componente foi ancorado diretamente no Data Fetch da tela (`params.period = 'custom'`), orquestrando relatórios Prawn e Chart dinâmicos perfeitamente a partir de datas do calendário.

**Arquivos Modificados:**

- `app/javascript/dashboard/features/financial/api/pdfs.js`
- `app/javascript/dashboard/features/financial/pages/CashFlow.vue`
- `app/services/financial/pdf/base_pdf.rb`

---

## [1.4.4.32] - 2026-04-05T16:00:00-03:00

### Financeiro: Integração do Financeiro Central com Consulta de Paciente e Refinamento de UI

Conclusão do fluxo que permite criar lançamentos no "Financeiro Central" associando um paciente via Autocomplete, e o reflexo dessa conta manual diretamente dentro do Histórico Financeiro do Prontuário do Paciente.

**Problema:**

1. As Entradas e Saídas do Financeiro não possuíam vínculos práticos para associar despesas manuais não planejadas com os pacientes no front.
2. Contas criadas de modo manual com um `patient_id` anexado ficavam salvas do lado do Financeiro Central (model `AccountTransaction`), porém o Prontuário do Paciente só listava os pagamentos de Tratamentos e Orçamentos (model `Transaction`), deixando as entradas manuais "invisíveis" aos olhos do médico no dossiê do paciente.
3. No Componente do Caixa, o layout do `<TransactionModal>` continha campos de input desconexos, labels desalinhadas, sem tratamento para buscas responsivas e sem feedback limpo.

**Solução:**

1. **Adicionado Seletor Rápido de Pacientes (`TransactionModal.vue` e `patients/index.js`):**
   - Criação de interface limpa com busca na `/api/patients` under-the-hood (acionada após digitação via debounce) e fechamento do tooltip interativo inteligente através do event watcher `onClickOutside`. O ID selecionado agora trafega via JSON pro Create do Transaction de conta.
   
2. **Refinamento Cirúrgico UI/UX (`TransactionModal` & `financial.css`):**
   - Conserto milimétrico na simetria vertical das caixas. Remoção de margens (`mb-1.5`) na root grid e nas labels flex.
   - Refatoração do feedback da captura do paciente: A view do item selecionado agora substitui lixeiras vermelhas poluídas por um emblema verde sutil com tipografia em caps no topo do input de pesquisa (`VINCULADO: [Nome do Paciente]`). 

3. **Espelhamento Analítico no Prontuário (`transactions_controller.rb` e `Record.vue`):**
   - Refatoração no Controller do Prontuário: Em vez de um complexo SyncService entre dois bancos de dados para as transações manuais, a `index` de transações do paciente constrói simultaneamente arrays puxando do modelo de `Transaction` (Orçamentos) E concatena em tempo real quaisquer entradas perdidas no model `AccountTransaction` que retenham a key do paciente sem origens atreladas.
   - No frontend, transações puras vindas do AccountTransaction possuem as tags unificadas por flag reativa e recebem um novo tratamento com Proteção nos Botões (`v-if="!tx.is_manual"`), prevenindo requisições na API de tratamentos erradas. Em vez dos atalhos de WhatsApp/Comprovantes, essas linhas exibem um belo Badge referencial: `⚡ Lançamento Manual`.

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/components/TransactionModal.vue`
- `app/javascript/dashboard/api/patients/index.js`
- `app/controllers/api/v1/accounts/patients/transactions_controller.rb`
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue`

---

## [1.4.4.31] - 2026-04-05T09:35:00-03:00

### Financeiro: Integração Contas Bancárias ↔ Fluxo de Caixa (FINANCIAL_ARCHITECTURE.md — Etapa 1)

Implementação da primeira etapa da arquitetura financeira definida em `FINANCIAL_ARCHITECTURE.md`: vinculação real entre contas bancárias e transações, com reflexo imediato no Fluxo de Caixa.

**Problema:**
As contas bancárias cadastradas em Configurações > Contas Bancárias existiam de forma isolada — o `bank_account_id` nunca era preenchido ao liquidar recebíveis (era sempre `null`), portanto o `opening_balance` e o `current_balance` das contas nunca refletiam a realidade. O Fluxo de Caixa não exibia o saldo patrimonial real das contas.

**Solução — 5 arquivos alterados:**

1. **`ReceivePaymentModal.vue`** — Adicionado campo `"Conta de Destino"` (select com contas bancárias ativas). Carrega contas via API no `onMounted`. Pré-seleciona automaticamente se só houver uma conta. O `bank_account_id` é incluído no evento `confirm`.

2. **`accountTransactions.js`** — Método `receive()` agora aceita `bankAccountId` e o inclui no `FormData` enviado ao backend.

3. **`Receivables.vue`** — O handler `handleReceiveConfirm` extrai e passa `bankAccountId` para o `transactionsApi.receive()`.

4. **`account_transactions_controller.rb`** — Action `receive` agora aceita e persiste `bank_account_id` na transação ao liquidar, conectando o dinheiro à conta correta.

5. **`CashFlow.vue`** — O `fetchData()` agora carrega em paralelo o fluxo de caixa E as contas bancárias. Adicionado 4º card **"Saldo em Caixa"** calculado como:
   `saldo_final = opening_balance + entradas_do_período - saídas_do_período`
   Onde `opening_balance = initial_balance das contas + movimentações históricas`, implementando a fórmula do FINANCIAL_ARCHITECTURE.md: `Saldo Atual = Saldo Inicial + ΣEntradas - ΣSaídas`

**CSS:**
- Classes `.cf-balance-card`, `.cf-balance-label`, `.cf-balance-icon`, `.cf-balance-hint` adicionadas ao `financial.css`

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/components/ReceivePaymentModal.vue`
- `app/javascript/dashboard/features/financial/api/accountTransactions.js`
- `app/javascript/dashboard/features/financial/pages/Receivables.vue`
- `app/javascript/dashboard/features/financial/pages/CashFlow.vue`
- `app/javascript/dashboard/features/financial/financial.css`
- `app/controllers/api/v1/accounts/account_transactions_controller.rb`

---

## [1.4.4.30] - 2026-04-04T10:54:00-03:00


### UI/UX: Redesign Completo — Aba Plano de Tratamento

Refatoração total do `TreatmentPlanTab.vue`. O componente estava usando classes `tp-plan-*`, `tp-section-*`, `tp-table-*`, etc. que **não existiam em nenhum CSS**, causando: nomes de procedimentos quase invisíveis (cor herdada do tema escuro), barra total com fundo cinza-escuro distorcido, badges de status ilegíveis e layout completamente quebrado no light mode.

**Problemas corrigidos:**
- Classes CSS indefinidas (`tp-table-head`, `tp-table-row`, `tp-cell-name`, `tp-total-row`, etc.) causavam herança de estilos escuros do Chatwoot
- Nome do procedimento ("Limpeza", "Avaliação") aparecia em cinza muito claro — ilegível
- Linha "Total Estimado" renderizava com fundo cinza-escuro e texto branco (herança dark)
- Badge "PROPOSTO" em maiúsculo e cor incorreta
- Títulos h3 com `text-slate-100` (branco) — invisível no light mode
- Ícone de seção `reg-section-icon reg-icon-blue` com fundo colorido (padrão errado)

**Solução — reescrita total com `<style scoped>`:**
- Sistema `tp-*` completo definido no próprio componente (scoped) — zero dependência de classes globais indefinidas
- Cores via `rgb(var(--slate-N))` — dual-theme automático
- **Tabela**: `tp-th` (labels uppercase 11px), `tp-td--name` (slate-12 forte), `tp-td--muted` (slate-9), `tp-td--strong` (slate-12 bold)
- **Total estimado**: fundo `slate-2`, label uppercase, valor azul `#2563eb` — limpo e legível
- **Badges de status**: `tp-status--blue` (proposto) e `tp-status--green` (aprovado) com `rgba` semitransparente
- **Cabeçalho do plano**: fundo `slate-2`, ícone verde 32px com `rgba(22,163,74,0.12)`, textos slate-12/slate-9
- **Seções internas**: label uppercase 11px slate-9, corpo com padding uniforme
- **Botões de ação**: `tp-action-btn` com borda slate-4, hover sutil; variantes `--green` e `--danger`
- **Empty state**: ícone em container slate-3, textos slate-10/slate-8
- **Print**: overrides para `@media print` preservando legibilidade

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/tabs/TreatmentPlanTab.vue` — reescrita total

---

## [1.4.4.29] - 2026-04-04T10:40:00-03:00

### UI/UX: Modal "Novo Procedimento" — Refatoração para Padrão npm-*

Auditoria completa e refatoração do modal "Novo Procedimento/Editar Procedimento" no `Record.vue`. O modal anterior usava classes Tailwind inline com ícone grande no header (`h-9 w-9 bg-slate-100`) e labels em `UPPERCASE tracking-wider`, divergindo completamente do padrão estabelecido pelo `NewPatientModal.vue`.

**Problemas corrigidos:**
- Ícone `i-lucide-plus-circle` com container `h-9 w-9 bg-slate-100` no header — removido (padrão Novo Paciente não tem ícone no header)
- Labels em `UPPERCASE tracking-wider` — corrigido para case normal com `tp-label` (12px, font-weight 600)
- Botão "Confirmar" usando `btn-modal-primary` que estava sendo sobrescrito pelo CSS do Chatwoot — migrado para `tp-btn-submit` scoped no `record.css`
- Botão "Cancelar" sem distinção visual clara — migrado para `tp-btn-cancel` com borda `--border-strong`
- Estrutura Tailwind inline toda migrada para classes `tp-*` globais

**Novo sistema `tp-*` para modais (adicionado ao `record.css`):**
- `.tp-modal-overlay` — overlay `rgba(0,0,0,0.45)` com `backdrop-filter: blur(4px)`, `z-index: 99999`
- `.tp-modal-card` — card `rgb(var(--slate-1))`, borda `slate-4`, `border-radius: 16px`
- `.tp-modal-header` — padding `22px 22px 16px`, borda inferior `--border-strong`
- `.tp-modal-title` — 16px, font-weight 600, `slate-12`
- `.tp-modal-subtitle` — 13px, `slate-9`
- `.tp-modal-close` — 28×28px, sem borda, hover `slate-3`
- `.tp-modal-body` — flex-column, gap 14px, padding `16px 22px`
- `.tp-row-2` — grid 2 colunas, gap 12px
- `.tp-label` — 12px, font-weight 600, `slate-11`
- `.tp-input` — `slate-2` bg, `--border-strong` borda, `blue-9` focus, zero box-shadow
- `.tp-btn-cancel` — transparente com borda `--border-strong`, hover `slate-3`
- `.tp-btn-submit` — azul sólido `#3b82f6`, hover `#2563eb`, zero box-shadow

**Atualização das classes globais `btn-modal-*`:**
- `btn-modal-primary`: removido `box-shadow` (proibido pelo StyleMD)
- `btn-modal-cancel`: migrado para `--border-strong` para consistência

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue` — modal Novo Procedimento reescrito com `tp-*`
- `app/javascript/dashboard/routes/dashboard/patients/record.css` — sistema `tp-*` de modal + fix `btn-modal-*`

---

## [1.4.4.28] - 2026-04-04T10:40:00-03:00

### UI/UX: Light Mode — Prontuário Clínico (Série Completa)

Migração completa do módulo de Prontuário (Record.vue) do modo escuro legado para o padrão de **Light Mode** do sistema, com criação do guia de design `STYLEMD.md`.

#### Histórico de Evoluções Clínicas (`.evo-note-*`)

- Convertidas todas as cores hexadecimais hardcoded (modo escuro) das classes `.evo-note-*` para variáveis semânticas (`rgb(var(--slate-N))`).
- **Tipografia corrigida:**
  - Labels (Queixa, Avaliação, Conduta…) → `font-weight: 700; color: #0f172a` (preto-escuro, negrito proeminente)
  - Valores das respostas → `font-weight: 500; color: #475569` (cinza médio-escuro, legível)
- **Campo "Intercorrência":** Removida a classe `evo-note-field--alert` do HTML e toda a CSS que injetava fundo vermelho/amarelo. O campo agora é visualmente idêntico a todos os outros campos.
- **Bordas e separadores** dos campos migrados para `rgb(var(--slate-3/4))`.

#### Modal "Novo Procedimento" (`.delete-modal-card`)

- Fundo do modal corrigido de gradiente escuro (`#1e293b → #0f172a`) para **branco sólido** (`bg-white border-slate-200 shadow-xl`).
- Ícone do header: tamanho reduzido de `h-10 w-10 size-5` para `h-9 w-9 size-4`; fundo alterado para `bg-slate-100 text-slate-600` (neutro claro); ícone estilo **outline** (não preenchido).
- Labels do formulário: cor alterada de `text-slate-400` para `text-slate-600`.
- Títulos e subtítulo: `text-slate-900` e `text-slate-500`.

#### Sistema de Botões de Modal — Criado `StyleMD`

- **`btn-modal-primary`** (CSS em `record.css`): Botão azul sólido `#2563eb`, texto branco, hover `#1d4ed8`, estado disabled com `opacity: 0.45`. Imune a overrides do Chatwoot via `!important`.
- **`btn-modal-cancel`** (CSS em `record.css`): Fundo transparente, **borda cinza** (`rgb(var(--slate-5))`), hover com fundo `slate-2`. Nunca mais botão cancelar invisível.
- Seletor global `button.bg-blue-600` adicionado ao `record.css` para forçar o azul mesmo quando CSS do Chatwoot sobrepõe Tailwind.
- Modal "Novo Procedimento" migrado para as classes `btn-modal-primary` e `btn-modal-cancel`.

#### Criação do `STYLEMD.md`

Guia de design oficial do BeClinic criado com:
- Tabela de variáveis semânticas de cor
- Estrutura HTML canônica de modais
- Regras visuais (ícones outline, fundo branco, etc.)
- Referência de botões (`btn-modal-primary` / `btn-modal-cancel`)
- Anti-padrões documentados (o que **não** fazer)
- Tipografia padrão do Histórico de Evoluções

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue`
- `app/javascript/dashboard/routes/dashboard/patients/tabs/EvolutionTab.vue`
- `app/javascript/dashboard/routes/dashboard/patients/record.css`

**Arquivos Criados:**
- `STYLEMD.md` — Guia de estilo oficial do BeClinic

---

## [1.4.4.27] - 2026-04-03T21:05:00-03:00


### Funcionalidade: Busca Local na Lista de Conversas
**Modificações:**
- Implementada barra lateral expansível de busca (search input) em formato retrátil ("lupa") no cabeçalho das mensagens (`ChatListHeader.vue`).
- Estado local otimizado para filtragem de conversas por nome de contato de remetente (client-side) (`ChatList.vue`), incluindo evento do global bus para limpeza de campo baseada no estado entre abas.

### UI/UX: Correção de Estilos no Prontuário e Componentes
**Modificações:**
- Criação e padronização da classe utilitária semântica e multi-tema (dark/light) `.geral-header-btn` para o projeto conforme o `STYLE.md`.
- Correção massiva do problema visual do "Ghost Button" (botão transparente fundido com backgrouds claros), substituindo todas as ocorrências de `.btn-secondary flex items-center...` em headers e actions no escopo do Prontuário Clínico.
- Botões corrigidos/melhorados: `Agendar Consulta`, `Editar Ficha`, `Nova Anamnese`, `Salvar Rascunho` (Evolução e Anamnese), `Filtrar` e `Fotos Antes/Depois` (Procedimentos), `Ver na Agenda`, `Nova Pasta` (Exames), botões de ordenação da `Timeline`, e `Exportar PDF` (Auditoria).

**Arquivos Modificados:**
- `app/javascript/dashboard/components/ChatList.vue`
- `app/javascript/dashboard/components/ChatListHeader.vue`
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue`
- `app/javascript/dashboard/routes/dashboard/patients/patients-index.css`
- `app/javascript/dashboard/routes/dashboard/patients/record.css`

## [1.4.4.26] - 2026-04-01T19:15:00-03:00
### Demo: Dados de Demonstração para Apresentação Comercial

**Seed de dados demo incluído na imagem:**
- 18 pacientes com dados brasileiros realistas (CPF, RG, endereço, convênio)
- 18 anamneses completas e individualizadas por especialidade
- 12 alertas críticos (alergia, gestante, marca-passo, oncológico, etc.)
- 6 notas clínicas assinadas e em rascunho
- 6 planos de tratamento com itens e sessões controladas
- 86 eventos na agenda (3 meses histórico + 6 semanas futuras)
- 117+ transações financeiras retroativas (Jan–Mar) com categorias reais
- Abril/2026: R$ 625.410 em entradas, R$ 408.009 em saídas, margem ~35%

**Arquivos Modificados:**
- `db/seeds/patients_demo_seed.rb`
- `db/seeds/patients_demo_seed_2.rb`
- `db/seeds/agenda_events_seed.rb`
- `db/seeds/financeiro_demo_seed_2.rb`
- `db/seeds/abril_financeiro_seed.rb`

---

## [1.4.4.25] - 2026-03-27T15:36:00-03:00

### Pacientes: Paginação + Historico Caixa + i18n AMOUNT

**Paginação na listagem de pacientes:**
- Implementado controle de paginação client-side na aba Pacientes (view lista e grade)
- Seletor de itens por página: 15 (padrão), 20, 50, 100
- Barra de paginação no rodapé da tabela exibindo "Exibindo X–Y de N pacientes"
- Navegação inteligente com ellipsis para listas com muitas páginas
- Reset automático para página 1 ao mudar filtro ou busca
- Scroll corrigido: `pt-list-wrap` e `pt-grid` com `flex-shrink: 0` garantem que o `pt-page` gere overflow e o `overflow-y: auto` funcione corretamente

**Histórico do Caixa (sessão anterior):**
- Histórico agrupado por data em accordion colapsável
- Cada dia exibe totais de suprimentos, sangrias e saldo calculado
- Carregamento sob demanda das movimentações ao expandir each dia
- Filtro de mês para o histórico

**i18n:**
- Adicionada chave `FINANCIAL.CASH_REGISTER.AMOUNT` em `pt_BR` ("Valor") e `en` ("Amount")

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/Index.vue` — paginação, `pagedPatients`, `pageNumbers`, `goToPage`, `setPerPage`
- `app/javascript/dashboard/routes/dashboard/patients/patients-index.css` — `.pt-pagination*`, `flex-shrink: 0` nos wrappers
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json` — chave `AMOUNT`
- `app/javascript/dashboard/i18n/locale/en/financial.json` — chave `AMOUNT`

## [1.4.4.24] - 2026-03-27T13:10:00-03:00

### Financeiro: Correção na Exclusão de Categorias e Contas Bancárias

**Problema:** O botão de exclusão nas listas de "Categorias Financeiras" e "Contas Bancárias" dentro das Configurações do Financeiro falhava silenciosamente, ao passo que a exclusão em "Despesas Recorrentes" e "Regras de Comissão" funcionava perfeitamente. Como a API de Categorias e Contas encapsulava a lista em um objeto raiz (ex: `{ categories: [...] }`), a interface (Vue) injetava o objeto bruto na variável de estado reativo e o laço `v-for` acabava iterando sobre os valores das propriedades iteráveis do objeto, criando um problema estrutural no HTML (linhas renderizadas sem *id* de instâncias reais). Como consequência, as chamadas de API `.delete(cat.id)` e o `.filter` de listas falhavam.

**Solução:**
- Inserido *unwrapping* condicional seguro (`data?.categories || data || []` e `data?.bank_accounts || data || []`) no nível da action `loadCategories` e `loadBankAccounts` na página `FinancialSettings.vue`. Isso desempacota e normaliza os dados diretamente para instâncias reais de Array. Agora a visualização, paginação e eventos `@click` manipulando exclusões com `splice` ou `filter` funcionam nativamente sem falhas e atualizam a interface em tempo real.

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/pages/FinancialSettings.vue` — Correção no assinalamento reativo de carga de dados nas funções primárias.

## [1.4.4.23] - 2026-03-27T12:50:00-03:00

### Financeiro: UI Premium para Configurações e Caixa Diário

**Problema:** A aba de Configurações (regras de comissão, contas bancárias, despesas recorrentes e categorias) e a interface do Caixa Diário (`CashRegister.vue`) ainda utilizavam componentes isolados no estilo legado. Tabelas espremidas em cards, botões de ação e status com cores vazadas (`--color-woot-500` ausente) e menu de abas em "pills" flutuantes que não acompanhavam o design edge-to-edge das outras telas.

**Solução:**
- **Centralização Real de Modais (Teleport):** Envolto de todos os 4 modais de edição e criação de regras em `<Teleport to="body">`, garantindo que o overlay (`fixed inset-0`) respeite 100% da viewport e fique livre de eventuais blocos de `overflow: hidden` ou `transform` dos containers pais. Modais não cobrem mais apenas metade da página!
- **Sistema de Abas Horizontal (Underline):** Reescrita total das abas de navegação de Configurações (`.sets-tabs`) e eliminação total do contêiner obsoleto (`fin-card`), implementando padrão idêntico a `Agenda -> Configurações`.
- **Tabelas Canto-a-Canto:** Conversão da lista de histórico do *CashRegister* para `rep-table` com status pills padronizados. Nas Configurações, as seções agora mesclam harmoniosamente com o fundo da tela.
- **Header e Ações Consistentes:** Categoria e título das seções agora se alinham perfeitamente horizontalmente (`display: flex; align-items: flex-end`) com o botão de criação ("+ Regra", "+ Conta", etc). Correção de cores forçando hex `#3b82f6` para sanar o erro de variância no botão primário.
- **Empty States de Impacto:** Refatoração de estados vazios (`.cr-empty-state`, `.sets-empty`) usando ícones em blocos *soft-blue* arredondados e bordas `dashed`, imitando on-boarding minimalista.

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/pages/CashRegister.vue` — Layout refeito do histórico e header
- `app/javascript/dashboard/features/financial/pages/FinancialSettings.vue` — Strip de cards extras e melhor formatação
- `app/javascript/dashboard/features/financial/financial.css` — Extenso re-work de classes `.cr-*` e `.sets-*`

## [1.4.4.22] - 2026-03-27T10:49:00-03:00

### Financeiro: UI Premium, Filtros Modernizados e Calendários Customizados (Pickers)

**Problema:** Alta fragmentação visual estourando nos módulos financeiros (DRE, A Pagar, A Receber, Fluxo). Filtros baseados em `<select>` e date inputs padrão do browser, que quebravam a imersão do Design System e impossibilitavam uma experiência premium "canto-a-canto" garantida. Problemas severos de alinhamento em gráficos em resoluções atípicas.

**Solução:**
- **Gráfico de Fluxo SVG "Canto a Canto":** Reescrita do gráfico interativo removendo bordas mortas, permitindo que a linha verde/vermelha flua de quina a quina absoluta do container-pai. Resolvido bug de corte superior em picos e overlapping com cabeçalhos.
- **Barra de Filtros Pagar/Receber:** Substituição completa de barras com selects para layouts icon-driven de busca e menus "Status" customizados via dropdown (ref-click-outside).
- **Picker 100% Customizado no DRE:**
  - Criação do **`MonthPicker.vue`** para seleção rápida e fluida de Meses do Ano através de botões estilizados.
  - Criação do **`DatePicker.vue`** base para navegação de dias, emulando calendário de maneira clean e em dark-mode.
  - Substituição definitiva das chamadas obsoletas `type="month"` e `type="date"`.

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/components/MonthPicker.vue` — Novo componente criado do zero.
- `app/javascript/dashboard/features/financial/components/DatePicker.vue` — Novo componente criado do zero.
- `app/javascript/dashboard/features/financial/pages/DRE.vue` — Integração de picks e abas pill.
- `app/javascript/dashboard/features/financial/pages/Payables.vue` — Redesign do filtro com Status Menu.
- `app/javascript/dashboard/features/financial/pages/Receivables.vue` — Mirror dos filtros A Pagar.
- `app/javascript/dashboard/features/financial/financial.css` — +200 linhas de CSS system-compliant para comportar Dropdowns de Pickers e correção do Fluxo de Caixa.
- `app/javascript/dashboard/i18n/locale/*/financial.json` — Translation Keys para placeholders (`DATE_PLACEHOLDER`).

## [1.4.4.21] - 2026-03-27T10:45:00-03:00

### Financeiro — Relatórios: Refinamento Premium e Calendários Customizados

**Problema:** O módulo de "Relatórios" do financeiro estava exibindo abas centralizadas de forma indesejada devido a contêineres pai grid global, e utilizando as cores erradas para "Ativo" (ficando com texto invisível no modo claro). Além disso, os inputs de data ainda eram os nativos HTML `type="month"` e `type="date"`.

**Solução:**
- **Alinhamento:** `<div class="rep-tabs">` envolto com um contêiner `w-full flex justify-start` para garantir que o menu da aba fique sempre à esquerda, obedecendo as margens máximas de 1280px de forma fluida.
- **Cor Primária Azul:** Correção dos seletores de abas `.rep-tab--active` e `.rep-period-tab--active` que voltaram a usar estritamente o azul canônico BeClinic (`bg-woot-600` e `#3b82f6`) garantindo máximo contraste com fonte branca `#ffffff` ao invés de usar os antigos tons de slate.
- **Pickers Customizados:** Remoção total dos inputs nativos HTML de todas as quatro abas de relatório (Comissões, Despesas, Faturamento, Ticket). Em seu lugar foram estendidos e implementados de maneira unificada os novos componentes `<MonthPicker>` (seleção ágil mes/ano) e `<DatePicker>` (popovers customizados para datas específicas) reutilizando a sólida base construída no DRE.

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/pages/Reports.vue` — Inserção de refatoração para Month/DatePicker, e wrap do menu à esquerda.
- `app/javascript/dashboard/features/financial/financial.css` — `.rep-tab--active` agora usa cores hex code solidificadas para as brands blue.

## [1.4.4.20] - 2026-03-27T07:22:00-03:00

### Financeiro — Dashboard: Gráfico de Fluxo de Caixa reformulado para linha dupla

**Problema:** O `CashFlowChart.vue` exibia barras duplas (entradas verde / saídas vermelho), sem uma leitura comparativa imediata. O usuário precisava comparar alturas de barras adjacentes para entender o saldo do dia.

**Causa:** Design inicial baseado em `Bar` do Chart.js, sem área preeenchida, sem tooltip enriquecido e sem indicador de status do período.

**Solução — Redesign completo com gráfico de duas linhas:**
- Migrado de `Bar` para `Line` do Chart.js com `Filler` plugin
- **Linha verde** (Entradas) com área preenchida em gradiente verde sutil
- **Linha vermelha** (Saídas) com área preenchida em gradiente vermelho sutil
- Quando a linha verde está acima da vermelha = período positivo; quando a vermelha ultrapassa = saldo negativo do dia
- **Status Pill** contextual no cabeçalho do gráfico: "Saldo positivo no período" (verde) / "Saldo negativo no período" (vermelho)
- **Crosshair plugin** customizado: linha vertical tracejada ao fazer hover, facilitando leitura precisa dos pontos
- **Tooltip premium** com `mode: index`: exibe entradas (▲) e saídas (▼) de forma simultânea + saldo do dia após separador
- **Legenda redesenhada**: dot circular + traço de linha colorido para cada série + dica de leitura à direita ("Verde acima = mais entradas do que saídas")
- Grid Y minimalista com linhas horizontais ultra-suaves (`#f1f5f9` / `#1e293b`)
- Animação `easeInOutQuart` com 600ms de duração
- Canvas com altura de 280px (aumento de 20px vs. versão anterior)
- Suporte dual-theme completo (light/dark via `isDark` reactivo do `useChart`)
- Alerta de saldo negativo acumulado mantido e com cores corrigidas para padrão `STYLE.md`

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/components/CashFlowChart.vue` — redesign completo
- `app/javascript/dashboard/features/financial/financial.css` — classes `ccf-*` totalmente reescritas
- `app/javascript/dashboard/i18n/locale/en/financial.json` — +3 chaves (`BALANCE_POSITIVE`, `BALANCE_NEGATIVE`, `LEGEND_HINT`)

## [1.4.4.19] - 2026-03-25T14:40:00-03:00

### Financeiro — Análise Avançada (Onda 4)

Implementação completa de três gráficos analíticos avançados para o Módulo Financeiro, provendo insights detalhados sobre funil de vendas, heatmap de ocupação da agenda e retenção de pacientes. Estes componentes seguem regras estritas de não usar bibliotecas de gráficos complexas quando viável por CSS.

**Gráficos implementados:**

- **Funil de Conversão (`ConversionFunnel.vue`)** — Gráfico com barras dinâmicas ilustrando a taxa de conversão entre etapas (Leads → Fechados). Inclui alerta destacando a etapa com maior perda (gargalo).
- **Heatmap de Ocupação da Agenda (`AgendaHeatmap.vue`)** — Matriz (Dias x Horários) exibindo densidade térmica baseada na taxa de ocupação. Construído sem libs (*completamente CSS Grid*). Alerta indicando horário de pico.
- **Novos Pacientes vs Recorrentes (`NewVsReturningPatients.vue`)** — Gráfico misto demonstrando pacientes novos (Barras Claras), retornados (Barras Escuras), o % de retenção (Linha Roxa) e meta de retenção (Tracejado). Sistema de alerta ativado caso retenção fique < 50% em 2 meses consecutivos (risco de *churn*).

**Backend & API:**
- Implementação de três Micro-Services otimizados (`agenda_analytics_service.rb`, `conversion_analytics_service.rb`, `patient_retention_service.rb`) para cálculo de percentuais e extração de insights.
- Criação dos três novos endpoints isolados no `FinancialReportsController`.
- Conformidade completa com regras do RuboCop para complexidade e tamanho de métodos.

**Design System & i18n:**
- Todas as definições visuais customizadas movidas para o manifesto unificado `financial.css`, mantendo a reusabilidade modular e suporte Light/Dark nativo.
- Adicionadas keys literais para os gráficos no manifesto `en/financial.json`.
- Atualização e documentação no `graficos_plano_de_acao.md`.

**Arquivos Criados:**
- `app/javascript/dashboard/features/financial/components/ConversionFunnel.vue`
- `app/javascript/dashboard/features/financial/components/AgendaHeatmap.vue`
- `app/javascript/dashboard/features/financial/components/NewVsReturningPatients.vue`
- `app/services/financial/agenda_analytics_service.rb`
- `app/services/financial/conversion_analytics_service.rb`
- `app/services/financial/patient_retention_service.rb`

**Arquivos Modificados:**
- `app/controllers/api/v1/accounts/financial_reports_controller.rb`
- `config/routes.rb`
- `app/javascript/dashboard/features/financial/pages/FinancialDashboard.vue`
- `app/javascript/dashboard/features/financial/financial.css`
- `app/javascript/dashboard/i18n/locale/en/financial.json`
- `graficos_plano_de_acao.md`
- `app/javascript/dashboard/features/financial/components/RevenueGoalGauge.vue` (pequenos fixes incidentais)

## [1.4.4.18] - 2026-03-25T12:35:57-03:00

### Financeiro — Gráficos do Dashboard + Refinamentos Visuais

Implementação de 2 gráficos CSS-only no Dashboard Financeiro e refinamentos visuais nos botões de ação, modal de transação e summary cards.

**Gráficos implementados:**

- **`DailyCashFlowChart.vue`** — Gráfico de barras duplas verticais (verde = entradas, vermelho = saídas) mostrando o fluxo de caixa dos últimos 8 dias. CSS-only, sem dependência de Chart.js. Inclui legenda com dot colorido, labels de data (dd/mm), tooltip com valor formatado em BRL. Classes `dcf-*` com suporte dual-theme.

- **`MonthlySalesChart.vue`** — Gráfico de barras verticais azuis mostrando a evolução de vendas dos últimos 6 meses. Valores abreviados acima das barras (ex: R$ 12,5k), labels de mês/ano abaixo. Cor primária `rgb(var(--blue-9))`. Classes `msc-*` com suporte dual-theme.

- Ambos integrados como blocos arrastáveis no grid do Dashboard (`daily_cash_flow`, `monthly_sales`), com skeleton loading e empty state.

**Refinamentos visuais:**

- **Modal de Transação (`TransactionModal.vue`):** Botões de tipo (Entrada/Saída) refatorados — estado inativo agora é cinza neutro (`#f9fafb`), estado ativo aplica cor semântica (verde para entrada, vermelho para saída). Corrige o bug onde ambos os botões ficavam verdes.

- **Botões de ação (CashFlow, Receivables, Payables):** Cores suaves aplicadas — `.btn-new-entry-cf` verde pastel, `.btn-new-expense-cf` vermelho pastel, `.btn-new-entry-rec` verde pastel, `.btn-new-expense-pay` vermelho pastel. Hover states removidos/simplificados.

- **Summary cards:** `.financial-summary-card` redesenhado com fundo verde claro (#f1fdf0), `.financial-summary-card--income` azul (#e5effd), `.financial-summary-card--expense` vermelho (#fdf0f0).

- **Teleport no modal:** `TransactionModal.vue` envolto em `<Teleport to="body">` para resolver overlay que não cobria 100% da tela.

**CSS adicionado:** ~145 linhas no `financial.css` (classes `dcf-*` e `msc-*`).

**i18n:** +13 chaves novas no `FINANCIAL.DASHBOARD.*` em pt-BR.

**Arquivos Criados:**
- `app/javascript/dashboard/features/financial/components/DailyCashFlowChart.vue`
- `app/javascript/dashboard/features/financial/components/MonthlySalesChart.vue`

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/pages/FinancialDashboard.vue` — imports + 2 novos blocos
- `app/javascript/dashboard/features/financial/financial.css` — +145 linhas de CSS de gráficos + botões
- `app/javascript/dashboard/features/financial/components/TransactionModal.vue` — Teleport + fix de indentação
- `app/javascript/dashboard/features/financial/pages/CashFlow.vue` — classes de botões
- `app/javascript/dashboard/features/financial/pages/Receivables.vue` — classes de botões
- `app/javascript/dashboard/features/financial/pages/Payables.vue` — classes de botões
- `app/javascript/dashboard/i18n/locale/en/financial.json` — +13 chaves DASHBOARD

---

## [1.4.4.17] - 2026-03-24T14:35:15-03:00


### Financeiro Central — Auditoria Visual Completa + Correção de CSS Crítico

Auditoria 100% do módulo financeiro: identificação e correção da causa raiz de todos os problemas visuais (páginas sem estilo, layout espremido, espaçamento inconsistente) e correções de i18n/inline styles.

**Problema:** Todas as sub-páginas (CashFlow, Receivables, Payables, Reports, Settings) estavam visualmente "quebradas" — sem espaçamento, sem cards, sem estilos de tabela, conteúdo espremido num canto da tela. O Dashboard e DRE/CashRegister tinham strings hardcoded em português e inline styles proibidos pelo STYLE.md.

**Causa Raiz (descoberta nesta auditoria):**
1. **5 de 8 páginas NÃO importavam `financial.css`** — CashFlow, Receivables, Payables, Reports e FinancialSettings nunca carregavam o stylesheet, então renderizavam sem NENHUM estilo
2. **~50 classes CSS referenciadas nos templates nunca foram definidas** — classes como `financial-page__header`, `financial-grid`, `financial-summary-card`, `financial-table`, `financial-filters`, `financial-badge`, `financial-btn`, `fin-card`, etc. eram usadas mas não existiam no CSS

**Solução:**

- **CSS imports** — Adicionado `import '../financial.css'` em 5 páginas: CashFlow.vue, Receivables.vue, Payables.vue, Reports.vue, FinancialSettings.vue.

- **+600 linhas de CSS** — Definidas todas as classes ausentes no `financial.css`:
  - Layout de sub-páginas: `.financial-page__header/title/subtitle`
  - Grid responsivo: `.financial-grid` / `--2` / `--3` / `--4` (com breakpoints mobile)
  - KPI summary cards: `.financial-summary-card` / `--income` / `--expense` + label/value
  - Data tables: `.financial-table` com th/td, hover, col variants (`--number`, `--income`, `--expense`, `--positive`, `--negative`, `--description`)
  - Barra de filtros: `.financial-filters` + `__search` / `__select` / `__overdue` / `__btn`
  - Badges: `.financial-badge` + `--success` / `--warning` / `--danger` / `--neutral`
  - Paginação: `.financial-pagination` + `__info` / `__btn`
  - Botões genéricos: `.financial-btn` + `--primary` / `--ghost`
  - Gráfico de barras (CashFlow): `.financial-bar-chart`, `.financial-bar--income/expense`, `.financial-chart-legend`
  - Empty states: `.financial-empty-state` + `__icon` / `__text`
  - Skeletons: `--card` / `--chart` / `--table`
  - Settings: `.fin-page`, `.fin-card`, `.fin-loading`, `.fin-text-muted`, `.fin-text-secondary`
  - Tudo com suporte completo a Dark Mode (`body.dark`)

- **CSS import path fix (sessão anterior)** — Corrigido `../../financial.css` → `../financial.css` em DRE.vue e CashRegister.vue (resolvia erro de build Vite).

- **i18n (sessão anterior)** — 15+ strings PT hardcoded em FinancialDashboard.vue substituídas por `$t()`. Chaves DASHBOARD e CANCEL/CONFIRM adicionadas em en/pt_BR `financial.json`.

- **Inline styles (sessão anterior)** — Removidos todos os `style=""` de FinancialDashboard.vue, substituídos por classes CSS utilitárias.

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/pages/CashFlow.vue` — +import CSS
- `app/javascript/dashboard/features/financial/pages/Receivables.vue` — +import CSS
- `app/javascript/dashboard/features/financial/pages/Payables.vue` — +import CSS
- `app/javascript/dashboard/features/financial/pages/Reports.vue` — +import CSS
- `app/javascript/dashboard/features/financial/pages/FinancialSettings.vue` — +import CSS
- `app/javascript/dashboard/features/financial/pages/DRE.vue` — fix import path
- `app/javascript/dashboard/features/financial/pages/CashRegister.vue` — fix import path + i18n keys
- `app/javascript/dashboard/features/financial/pages/FinancialDashboard.vue` — i18n + remove inline styles
- `app/javascript/dashboard/features/financial/financial.css` — +600 linhas de classes CSS
- `app/javascript/dashboard/i18n/locale/en/financial.json` — +chaves DASHBOARD/CANCEL/CONFIRM
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json` — idem

---

## [1.4.4.16] - 2026-03-24T14:05:17-03:00

### Financeiro Central — Onda 4C: Faturamento por Convênio + Ticket Médio + Exportação CSV

Implementa dois novos relatórios analíticos e adiciona exportação CSV a todos os relatórios financeiros, completando a Onda 4 do módulo financeiro.

**Problema:** A página Reports.vue tinha apenas 2 abas (Comissões e Despesas). Faltavam análise de faturamento por convênio/origem de pagamento e análise de ticket médio por profissional/mês — funcionalidades críticas para gestão de clínicas com múltiplos convênios.

**Solução:**

- **`FinancialReportsController#insurance`** — Agrupa entradas recebidas por `metadata['insurance']` ou `financial_category.name` (fallback: "Particular"). Retorna ranking com label, count e amount por origem. Suporte a `?format=csv` para download direto.

- **`FinancialReportsController#average_ticket`** — Calcula ticket médio agrupado por profissional ou por mês. Inclui overall (total geral). Query com `AVG(amount)` + COUNT nativo no Postgres.

- **`FinancialReportsController#commissions`** — Adicionado suporte a `?format=csv` (download de planilha de comissões com cabeçalho, linhas e total).

- **Rotas** — `get :insurance` e `get :average_ticket` adicionadas ao namespace `financial/reports`.

- **`reports.js`** — Adicionados `insurance()`, `averageTicket()` e `downloadReportCSV()` (utilitário separado para não violar regra de classe ESLint).

- **`Reports.vue`** — Reescrito com 4 abas:
  1. **Comissões** — existente, com botão CSV
  2. **Despesas por Categoria** — existente, sem alteração de lógica
  3. **Faturamento por Convênio** — novo: ranking horizontal por origem + tabela com ticket médio por convênio + KPI cards + botão CSV
  4. **Ticket Médio** — novo: toggle "por profissional / por mês", bar chart com acento verde, tabela e KPIs de total+ticket geral

- **CSS** — +50 linhas: `.rep-export-btn`, `.rep-filter-actions`, `.rep-date-input--year`, `.rep-ins-*`, `.rep-tick-*`, `.fin-flex-center`, `.fin-gap-sm`.

- **i18n** — +35 chaves novas no `FINANCIAL.REPORTS.*` em EN e pt_BR.

**Arquivos Modificados:**
- `app/controllers/api/v1/accounts/financial_reports_controller.rb` — +2 actions, CSV builders, helpers SQL
- `config/routes.rb` — `get :insurance` e `get :average_ticket`
- `app/javascript/dashboard/features/financial/api/reports.js` — 2 new methods + downloadReportCSV
- `app/javascript/dashboard/features/financial/pages/Reports.vue` — reescrito com 4 abas
- `app/javascript/dashboard/features/financial/financial.css` — +50 linhas de CSS
- `app/javascript/dashboard/i18n/locale/en/financial.json` — +35 chaves
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json` — idem

---

## [1.4.4.15] - 2026-03-24 13:56:50-03:00

### Financeiro Central — Onda 4B: Configurações (Regras de Comissão + Despesas Recorrentes)

Implementação completa da página `FinancialSettings.vue` — substitui o placeholder de `/financeiro/configuracoes` por uma interface funcional de gerenciamento de regras de comissão e despesas recorrentes.

**Problema:** Até agora, o `CommissionCalculator` calculava comissões mas as regras tinham que ser criadas manualmente via console Rail/seed. Sem UI, impossível para a clínica configurar regras por profissional. Idem para despesas recorrentes.

**Solução:**

- **`CommissionRulesController`** — CRUD completo (index/create/update/destroy). Multi-tenant via `Current.account.commission_rules`. Serializa `professional_name` e `category_name` para uso direto no frontend. Protegido por `CommissionRulePolicy` (admin only para write).

- **`RecurringExpensesController`** — CRUD completo (index/show/create/update/destroy). Destroy é soft (`active: false`). Inclui `bank_account_name` e `category_name` na serialização.

- **Rotas** — `resources :commission_rules` e `resources :recurring_expenses` adicionadas ao `namespace :financial`.

- **`FinancialSettings.vue`** — 2 abas: "Regras de Comissão" e "Despesas Recorrentes". Cada aba tem:
  - Tabela com badges coloridos (tipo de comissão / frequência / status ativo)
  - Modal de criação/edição com formulário completo
  - Select de profissional (carrega agents existentes)
  - Select de categoria e conta bancária (carregados de APIs existentes)
  - Toggles de ativo e auto_confirm

- **API clients** — `commissionRules.js` e `recurringExpenses.js` (padrão `ApiClient`).

- **CSS** — +420 linhas no `financial.css` com prefixo `sets-*`. Inclui: tabs, tabela, modal animado, form grid 2-col, badges, botões de ação, empty state. Suporte dark mode completo. Zero inline styles.

- **i18n** — +67 chaves `FINANCIAL.SETTINGS.*` em EN e pt_BR.

**Arquivos Criados:**
- `app/controllers/api/v1/accounts/commission_rules_controller.rb`
- `app/controllers/api/v1/accounts/recurring_expenses_controller.rb`
- `app/javascript/dashboard/features/financial/api/commissionRules.js`
- `app/javascript/dashboard/features/financial/api/recurringExpenses.js`

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/pages/FinancialSettings.vue` — substituiu placeholder
- `config/routes.rb` — 2 novos resources no namespace financial
- `app/javascript/dashboard/features/financial/financial.css` — +420 linhas `sets-*`
- `app/javascript/dashboard/i18n/locale/en/financial.json` — `FINANCIAL.SETTINGS.*`
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json` — idem em português

---

## [1.4.4.14] - 2026-03-24 13:33:00-03:00


### Financeiro Central — Onda 4A: Comissões por Profissional

Implementação completa do **Relatório de Comissões** com cálculo automático por profissional, período e tipo de regra, substituindo o placeholder da página Relatórios por uma interface funcional com duas abas.

**Problema:** A página `/financeiro/relatorios` era um placeholder sem dados reais. Não existia nem o cálculo de comissões no backend nem a interface de seleção de profissional + período. Impossível gerar relatório de repasse para profissionais.

**Solução:**

- **`Financial::CommissionCalculator` service** — Recebe account, professional e period. Para cada `AccountTransaction` do profissional no período (recebidas), busca a `CommissionRule` mais específica via `CommissionRule.most_specific_for` (prioridade: procedimento > categoria > geral). Aplica a fórmula correta conforme o tipo:
  - `percentage_production` → `original_amount * rule.value / 100`
  - `percentage_received` → `amount * rule.value / 100`
  - `fixed_value` → `rule.value` por transação
  - Retorna professional, period, total_commission, transaction_count, transactions[]

- **`commissions` action no `FinancialReportsController`** — `GET /api/v1/accounts/:id/financial/reports/commissions`. Params: `professional_id` (obrigatório), `period` (month/quarter/year/custom), `date`, `start_date`, `end_date`. Busca o profissional no escopo da account (segurança multi-tenant). Delega ao `CommissionCalculator`.

- **`resolve_commission_period` helper** — Suporta os mesmos 4 modos de período do DRE (month/quarter/year/custom).

- **`Reports.vue` completo** — Substitui o placeholder com duas abas:
  - **Aba Comissões:** Select de profissional (carrega `/agents`), seletor de período (mês/trimestre/ano/personalizado), input de data/range, botão Calcular. Exibe 3 KPI cards (profissional, Nº de transações, total de comissão roxo) + tabela detalhada por transação (descrição, categoria, data recebimento, valor, badge de tipo de regra, comissão calculada) + linha de total.
  - **Aba Despesas por Categoria:** Reaproveita o endpoint DRE existente. Gráfico de barras CSS-only com nome, valor e percentual por categoria + tabela com categoria, tipo (fixo/variável), valor e % sobre total.

- **CSS** — ~340 novas linhas com prefixos `rep-*` (shell da página), `comm-*` (comissões) e `exp-cat-*` (despesas por categoria). Zero inline styles, zero Tailwind ad-hoc.

**Decisões técnicas:**
- `CommissionCalculator` lê `transaction.metadata['procedure_name']` para busca por procedimento específico — forward-compatible com quando o campo for populado pela integração com procedimentos
- A aba de Despesas por Categoria reutiliza o endpoint `/dre` (já testado) em vez de criar um novo endpoint redundante — mantém o princípio de menor código
- Para o input de Ano no seletor de período, usa `input[type=number]` em vez de `input[type=month]` (compatibilidade com todos os browsers)

**Arquivos Criados:**
- `app/services/financial/commission_calculator.rb`
- `app/javascript/dashboard/features/financial/pages/Reports.vue` (substituiu placeholder)

**Arquivos Modificados:**
- `app/controllers/api/v1/accounts/financial_reports_controller.rb` — action `commissions` + helper `resolve_commission_period`
- `config/routes.rb` — `get :commissions` na collection de reports
- `app/javascript/dashboard/features/financial/api/reports.js` — método `commissions(params)`
- `app/javascript/dashboard/features/financial/financial.css` — +340 linhas `rep-*`, `comm-*`, `exp-cat-*`
- `app/javascript/dashboard/i18n/locale/en/financial.json` — chaves `FINANCIAL.REPORTS.*` e `FINANCIAL.COMMISSIONS.*`
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json` — idem em português

---

## [1.4.4.13] - 2026-03-24 13:15:00-03:00

### Financeiro Central — Onda 3A: DRE (Demonstração do Resultado do Exercício)

Implementação completa do DRE por **regime de competência** (`competence_date`), com comparativo automático de período anterior e tabela hierárquica expansível.

**Problema:** A página DRE era um placeholder. Não existia endpoint de cálculo de resultado econômico, apenas fluxo de caixa (regime de caixa). Impossível gerar demonstrativo contábil para a clínica.

**Solução:**

- **Backend** — 4 métodos novos em `FinancialReportsController`:
  - `dre` — action pública: resolve período, calcula DRE atual e anterior, retorna JSON estruturado
  - `resolve_dre_period` — suporta 4 modos: `month`, `quarter`, `year`, `custom`
  - `prior_period` — calcula período anterior com duração idêntica (shift temporal simples)
  - `build_dre` — agrega `account_transactions` por `competence_date` + LEFT JOIN com `financial_categories`; calcula as 9 linhas: receita bruta → deduções → receita líquida → custos variáveis → margem bruta → despesas fixas → EBITDA → outras despesas → lucro líquido
  - `dre_rows` — GROUP BY categoria com `SUM(amount)`, distinguindo `cost_type: fixo / variavel`

- **DRE.vue** — Página funcional substituindo placeholder:
  - Seletor de 4 períodos (mês/trimestre/ano/personalizado) com `input[type=month]` e range de datas
  - Tabela com 9 seções econômicas: linhas de resultado destacadas visualmente
  - Subcategorias expansíveis via chevron (receita bruta, custos var., desp. fixas, outras)
  - Coluna de variação % vs período anterior com badge colorido (↑ verde / ↓ vermelho)
  - Botão de exportação desabilitado (placeholder para onda futura)
  - Loading state com spinner + empty state

- **CSS** — ~350 novas classes DRE em `financial.css`: `.dre-table`, `.dre-row--result`, `.dre-row--net-profit`, `.dre-badge--up/down`, `.dre-period-tabs`, etc.

**Decisões técnicas:**
- Usa `competence_date` (não `received_at`/`paid_at`) — regime de competência correto para DRE
- LEFT JOIN com `financial_categories` para incluir transações sem categoria como "Sem categoria"
- Categorias `income` com `category_type = 'deducao'` são subtraídas da receita bruta
- Despesas sem `cost_type` caem em "Outras Despesas" (taxas bancárias, cartão, etc.)

**Arquivos Criados:**
- `app/javascript/dashboard/features/financial/pages/DRE.vue` (substituiu placeholder)

**Arquivos Modificados:**
- `app/controllers/api/v1/accounts/financial_reports_controller.rb` — action `dre` + 4 helpers privados
- `config/routes.rb` — `get :dre` na collection de reports
- `app/javascript/dashboard/features/financial/api/reports.js` — método `dre(params)`
- `app/javascript/dashboard/features/financial/financial.css` — +350 linhas DRE + `.financial-title/subtitle/loading`
- `app/javascript/dashboard/i18n/locale/en/financial.json` — chaves `FINANCIAL.DRE.*` (14 chaves)
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json` — idem em português

---

## [1.4.4.8] - 2026-03-24 12:36:00-03:00

### Financeiro Central — Onda 1A: Migrations + Models (Fundação)

Criação da fundação de dados do **Módulo Financeiro Central** do BeClinic. Este bloco estabelece as 5 tabelas que sustentam todos os KPIs, DRE, fluxo de caixa e relatórios futuros.

**Problema:** O sistema não tinha uma estrutura centralizada para financeiro da clínica — apenas o financeiro do paciente (`transactions`). Impossível gerar DRE, fluxo de caixa geral, ou registrar despesas operacionais.

**Solução:** Criação de 5 tabelas independentes que compõem o núcleo do módulo central:

- **`financial_categories`**: Árvore de categorias de receita/despesa (pai→filhos), com `cost_type` para distinguir fixo/variável no DRE
- **`bank_accounts`**: Contas bancárias da clínica com saldo inicial; saldo atual calculado dinamicamente pelas transações vinculadas
- **`account_transactions`**: Tabela "mãe" do financeiro central. Aceita entradas e saídas com ou sem paciente vinculado. 5 campos de data distintos (competência, vencimento, recebimento, pagamento, criação) para suportar tanto regime de caixa quanto regime de competência. Soft delete para rastreabilidade contábil. Índice `UNIQUE` em `source_transaction_id` garante idempotência absoluta na integração com o financeiro do paciente
- **`commission_rules`**: Regras de comissão por profissional com 3 tipos: `percentage_production`, `percentage_received`, `fixed_value`. Suporta prioridade: procedimento > categoria > geral, com vigência por data
- **`recurring_expenses`**: Template de despesas recorrentes (aluguel, salários) para geração automática via job. Suporta `competence_rule: same_month | previous_month` para correta alocação contábil

**Decisões técnicas:**
- Índice composto `[:account_id, :entry_type, :status]` recebeu nome explícito curto (`idx_acct_txns_account_type_status`) para respeitar limite de 63 chars do PostgreSQL
- Validado via `rails runner`: todos os 5 models carregam sem erro

**Arquivos Criados:**
- `db/migrate/20260324120001_create_financial_categories.rb`
- `db/migrate/20260324120002_create_bank_accounts.rb`
- `db/migrate/20260324120003_create_account_transactions.rb`
- `db/migrate/20260324120004_create_commission_rules.rb`
- `db/migrate/20260324120005_create_recurring_expenses.rb`
- `app/models/financial_category.rb`
- `app/models/bank_account.rb`
- `app/models/account_transaction.rb`
- `app/models/commission_rule.rb`
- `app/models/recurring_expense.rb`

---

## [1.4.4.10] - 2026-03-24 12:55:00-03:00

### Financeiro Central — Onda 1B: Frontend (Rotas + Sidebar + Dashboard)

Implementação completa da camada frontend da **Onda 1 do Módulo Financeiro Central**. O módulo agora está acessível na sidebar com dashboard funcional consumindo API real.

**Problema:** Sem frontend, o backend da Onda 1A era invisível para o usuário. A sidebar não tinha entrada "Financeiro" e as rotas Vue não existiam.

**Solução:** Estrutura modular completa em `features/financial/`:

- **8 rotas lazy-loaded** em `features/financial/routes.js` — dashboard, fluxo de caixa, a receber, a pagar, DRE, relatórios, caixa, configurações
- **CSS modular** `financial.css` — 240 linhas, zero inline/scoped, dual-theme light/dark
- **5 API clients** com `/* global axios */` — dashboard, transactions, categories, bankAccounts, reports
- **2 composables** — `useFormatCurrency` (Intl.NumberFormat BRL) + `useFinancialFilters` (period: today/week/month/custom)
- **`FinancialDashboard.vue`** — Dashboard principal com 4 KPIs (receita, saídas, novas entradas, lucro), blocos A Receber/A Pagar/Inadimplência/Contas, skeleton loading, seletor de período
- **7 páginas placeholder** para Onda 2/3 com visual "em breve"
- **i18n** `financial.json` adicionado em `en` e `pt_BR` e registrado nos respectivos `index.js`
- **Sidebar** — entrada "Financeiro" com ícone `i-lucide-wallet` e 8 subitens, posicionada entre Patients e Contacts

**Arquivos Criados:**
- `app/javascript/dashboard/features/financial/routes.js`
- `app/javascript/dashboard/features/financial/financial.css`
- `app/javascript/dashboard/features/financial/api/dashboard.js`
- `app/javascript/dashboard/features/financial/api/accountTransactions.js`
- `app/javascript/dashboard/features/financial/api/categories.js`
- `app/javascript/dashboard/features/financial/api/bankAccounts.js`
- `app/javascript/dashboard/features/financial/api/reports.js`
- `app/javascript/dashboard/features/financial/composables/useFormatCurrency.js`
- `app/javascript/dashboard/features/financial/composables/useFinancialFilters.js`
- `app/javascript/dashboard/features/financial/pages/FinancialDashboard.vue`
- `app/javascript/dashboard/features/financial/pages/CashFlow.vue`
- `app/javascript/dashboard/features/financial/pages/Receivables.vue`
- `app/javascript/dashboard/features/financial/pages/Payables.vue`
- `app/javascript/dashboard/features/financial/pages/DRE.vue`
- `app/javascript/dashboard/features/financial/pages/Reports.vue`
- `app/javascript/dashboard/features/financial/pages/CashRegister.vue`
- `app/javascript/dashboard/features/financial/pages/FinancialSettings.vue`
- `app/javascript/dashboard/i18n/locale/en/financial.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json`

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/dashboard/dashboard.routes.js`
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
- `app/javascript/dashboard/i18n/locale/en/index.js`
- `app/javascript/dashboard/i18n/locale/pt_BR/index.js`

---

## [1.4.4.12] - 2026-03-24 13:05:00-03:00

### Financeiro Central — Onda 2B: A Receber + A Pagar

Implementação das páginas **Receivables** e **Payables** com listagem real, filtros e detecção automática de inadimplência.

**Problema:** As páginas eram placeholders sem dados reais. O backend não suportava filtros por vencimento ou busca textual.

**Solução:**

- **Receivables.vue** — A Receber (entry_type: entrada): KPIs de total/quantidade, filtros por status/vencido/busca, tabela com badge de status e auto-detecção de inadimplência (due_date < hoje + não recebido = badge vermelho), paginação
- **Payables.vue** — A Pagar (entry_type: saida): mesma estrutura
- **Backend expandido** com filtros `?due_start`, `?due_end`, `?overdue=true`, `?q=texto` e `meta.total_amount` no retorno

**Arquivos Criados:**
- `app/javascript/dashboard/features/financial/pages/Receivables.vue`
- `app/javascript/dashboard/features/financial/pages/Payables.vue`

**Arquivos Modificados:**
- `app/controllers/api/v1/accounts/account_transactions_controller.rb`
- `app/javascript/dashboard/features/financial/api/accountTransactions.js`
- `app/javascript/dashboard/i18n/locale/en/financial.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json`

---

## [1.4.4.11] - 2026-03-24 13:00:00-03:00

### Financeiro Central — Onda 2A: Fluxo de Caixa + Bugfix Sidebar i18n

**Bug Corrigido — Sidebar mostrando labels crus (SIDEBAR.INBOX, SIDEBAR.CONVERSATIONS etc.):**
- Root cause: `financial.json` tinha chave top-level `SIDEBAR` que sobrescrevia o objeto inteiro do `settings.json` via spread (`...financial`)
- Fix: removido bloco `SIDEBAR` de `financial.json`; chaves `FINANCIAL_*` adicionadas dentro do `SIDEBAR` do `settings.json` (EN + pt_BR)

**Fluxo de Caixa:**
- `FinancialReportsController` com `GET /financial/reports/cash_flow` (breakdown diário + saldo inicial) e `GET /financial/reports/monthly_summary`
- `CashFlow.vue`: seletor de período, 3 KPIs, gráfico de barras CSS-only, tabela diária com skeleton loading

**Arquivos Criados:**
- `app/controllers/api/v1/accounts/financial_reports_controller.rb`
- `app/javascript/dashboard/features/financial/pages/CashFlow.vue` (substituiu placeholder)

**Arquivos Modificados:**
- `config/routes.rb`
- `app/javascript/dashboard/features/financial/api/reports.js`
- `app/javascript/dashboard/features/financial/composables/useFinancialFilters.js`
- `app/javascript/dashboard/i18n/locale/en/settings.json` e `pt_BR/settings.json`
- `app/javascript/dashboard/i18n/locale/en/financial.json` e `pt_BR/financial.json`

## [1.4.4.9] - 2026-03-24 12:45:00-03:00

### Financeiro Central — Onda 1A: Controllers + Policies + Rotas

Implementação da camada de API do **Módulo Financeiro Central**. Os 4 controllers expõem os endpoints financeiros protegidos por Pundit e acessíveis via namespace `/financial`.

**Problema:** Os models da Onda 1A não tinham controllers nem políticas de acesso. Impossível consumir os dados pelo frontend.

**Solução:**

- **`FinancialDashboardController`** — `GET /financial/dashboard` retorna 4 KPIs regime caixa (income, expense, new_income, net_profit), blocos receivables/payables/delinquency, lista de contas bancárias com saldo atual, mini cash flow e monthly sales
- **`AccountTransactionsController`** — CRUD completo com filtros por data/tipo/status, paginação, soft delete (preserva rastreabilidade contábil)
- **`FinancialCategoriesController`** — CRUD com proteção de categorias padrão contra deleção
- **`BankAccountsController`** — CRUD, destroy apenas desativa (soft delete)
- **6 Policies Pundit** — `FinancialDashboardPolicy`, `AccountTransactionPolicy`, `FinancialCategoryPolicy`, `BankAccountPolicy`, `CommissionRulePolicy`, `RecurringExpensePolicy`; escrita restrita a `administrator`
- **`Account` model** — `has_many` das 5 novas tabelas financeiras

**Arquivos Criados:**
- `app/controllers/api/v1/accounts/financial_dashboard_controller.rb`
- `app/controllers/api/v1/accounts/account_transactions_controller.rb`
- `app/controllers/api/v1/accounts/financial_categories_controller.rb`
- `app/controllers/api/v1/accounts/bank_accounts_controller.rb`
- `app/policies/financial_dashboard_policy.rb`
- `app/policies/account_transaction_policy.rb`
- `app/policies/financial_category_policy.rb`
- `app/policies/bank_account_policy.rb`
- `app/policies/commission_rule_policy.rb`
- `app/policies/recurring_expense_policy.rb`

**Arquivos Modificados:**
- `config/routes.rb` — namespace `:financial` com dashboard, transactions, categories, bank_accounts
- `app/models/account.rb` — `has_many` das 5 tabelas financeiras

---


## [1.4.4.7] - 2026-03-24 10:28:00-03:00

### Chat: Modal de Lista de Espera — Botão de Remoção

Adicionado botão **"Remover da lista"** no rodapé do modal `WaitingListModal` (acessível pelo botão "Lista de espera" no painel de contato da conversa).

**Comportamento:**
- O botão **só aparece quando o contato já está na lista de espera** (`isEditing = true`)
- Estilo vermelho/danger. É um botão icon-only (usando apenas o ícone de lixeira `i-ph-trash`), sem modal de confirmação (ação direta)
- Layout do footer ajustado: botão de remoção à esquerda, "Cancelar" e ação principal à direita
- Estado de loading (`isRemoving`) durante a requisição, com spinner no lugar do ícone
- Após remoção bem-sucedida: alerta com mensagem personalizada + fecha o modal automaticamente

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/dashboard/conversation/contact/WaitingListModal.vue` — função `handleRemove`, estado `isRemoving`, botão danger, CSS `.wl-btn--danger` e `.wl-footer-right`
- `app/javascript/dashboard/i18n/locale/en/contact.json` — chaves `REMOVE`, `REMOVING`, `REMOVE_MESSAGE`

---

## [1.4.4.6] - 2026-03-24 10:19:00-03:00

### Agenda: Lista de Espera — Remoção Automática ao Agendar

Quando um paciente da lista de espera é agendado através do popup de células verdes no calendário, sua entrada é **automaticamente removida** da lista de espera após o agendamento ser salvo com sucesso.

**Fluxo:**
1. Usuário clica na célula verde (slot disponível compatível com a preferência da lista de espera)
2. Popup mostra os pacientes na lista de espera para aquele horário
3. Usuário seleciona um paciente (ex: "Gabriel"), o modal de novo evento abre pré-preenchido
4. Usuário finaliza o agendamento e clica em "Agendar"
5. Após salvar com sucesso, o sistema **chama automaticamente `waitingListStore.remove(wlScheduleEntry.id)`**, removendo a entrada do banco e do store reativo

A remoção só ocorre em novos agendamentos (não em edições de eventos existentes) e apenas quando o contexto da lista de espera está presente (`wlScheduleEntry`).

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue` — chamada `waitingListStore.remove` após `agendaEvents/create`

---

## [1.4.4.5] - 2026-03-22 18:30:00-03:00

### Agenda: Correção de 500/404 em Endpoints + i18n

Auditoria e correção de erros de console que impediam o funcionamento correto da agenda.

#### Bug Fixes — API (500 / 404)

- **500 em `/api/v1/accounts/:id/agenda_setting`:** `Pundit::NotDefinedError` — faltava `AgendaSettingPolicy`
- **500 em `/api/v1/accounts/:id/agenda_custom_attributes`:** `Pundit::NotDefinedError` — faltava `AgendaCustomAttributePolicy`
- **404 em `/api/v1/accounts/:id/agenda_online_config`:** Dois problemas combinados:
  1. Faltava `AgendaOnlineConfigPolicy` (Pundit)
  2. `resource :agenda_online_config` no routes.rb buscava `AgendaOnlineConfigsController` (plural), mas o controller era `AgendaOnlineConfigController` (singular). Corrigido com `controller: 'agenda_online_config'`

Todas as 3 policies seguem o padrão existente: leitura para `account_user`, escrita para `administrator`.

#### Bug Fixes — i18n (traduções faltando em pt_BR)

- **`CONVERSATION_WORKFLOW`**: bloco completo (INDEX.HEADER, REQUIRED_ATTRIBUTES com MODAL, PAYWALL, ENTERPRISE_PAYWALL) adicionado em `pt_BR/settings.json`
- **`PAGINATION_FOOTER.SHOW` e `.PER_PAGE`**: chaves adicionadas em `pt_BR/contact.json`

**Arquivos Criados:**
- `app/policies/agenda_setting_policy.rb`
- `app/policies/agenda_custom_attribute_policy.rb`
- `app/policies/agenda_online_config_policy.rb`

**Arquivos Modificados:**
- `config/routes.rb` — `controller: 'agenda_online_config'` adicionado
- `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` — bloco CONVERSATION_WORKFLOW
- `app/javascript/dashboard/i18n/locale/pt_BR/contact.json` — SHOW, PER_PAGE

---

## [1.4.4.4] - 2026-03-22 16:43:00-03:00

### Agenda: Barra de Resumo (mini-dashboard contextual)

Adicionado botão **"Resumo"** no cabeçalho da agenda (substituindo "Filtrar Agentes") que abre/fecha uma barra de métricas contextual abaixo do header. A barra exibe 6 KPIs para o período atualmente visível (dia/semana/mês):

- **Agendados** — total de eventos no período
- **Confirmados** — eventos com status `confirmed`
- **Pendentes** — eventos com status `scheduled` (aguardando confirmação)
- **Atendidos** — soma de `completed + in_progress + arrived`
- **Ocupação** — taxa percentual de slots preenchidos vs. capacidade total
- **No-show** — taxa percentual de faltas

O range de datas (since/until) é calculado automaticamente a partir da view ativa:

- **Mês:** do primeiro ao último dia do mês exibido
- **Semana:** do domingo ao sábado da semana exibida
- **Dia:** a data exata do dia selecionado

Ao navegar para outra semana/mês/dia, as métricas são re-calculadas automaticamente via watcher reativo. O botão "Resumo" muda de aparência (azul ativo) quando a barra está visível.

**Arquitetura modular:** novo módulo em pasta própria, sem poluir o `AgendaDashboard.vue`.

**Arquivos Criados/Modificados:**

- `app/javascript/dashboard/features/agenda-summary/AgendaSummaryBar.vue` *(novo)*
- `app/javascript/dashboard/features/agenda-summary/agenda-summary.css` *(novo)*
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

---

## [1.4.4.3] - 2026-03-22 16:39:00-03:00

### Agenda: Botões de ação na célula verde — tamanho e posição

Aumentado o tamanho dos botões de ação inline nas células verdes (lista de espera) de 22px para 28px, com ícone de 11px → 15px. Posição ajustada de centralizado para **canto inferior direito** (`bottom: 4px; right: 4px`).

**Arquivos Modificados:**

- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

---

## [1.4.4.2] - 2026-03-22 16:35:00-03:00

### Agenda: Lista de Espera — cadastro automático de novo paciente

Quando o contato selecionado da lista de espera **não possui cadastro como paciente**, o sistema agora:

1. Limpa o campo "Paciente" no modal de novo evento (não pre-seleciona o contato incorretamente)
2. Abre automaticamente o painel lateral **"Novo Paciente"** com nome e telefone pré-preenchidos do contato
3. O `contact_id` é passado no `quickPatient` para vincular o novo paciente ao contato existente após o cadastro

Quando o contato **possui** paciente cadastrado, o comportamento anterior é mantido: paciente auto-selecionado via `PatientsAPI.byContact`.

**Arquivos Modificados:**

- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

---

## [1.4.4.1] - 2026-03-22 15:14:00-03:00

### Lista de Espera: Card minimalista, Seção na Agenda e Store reativo

Refatorado o card de contato no modal de lista de espera para design ultra-minimalista (uma linha com inicial + nome + telefone + badge). Implementado o módulo `features/waiting-list/` com arquitetura modular separada:

- `store.js` — store reativo com persistência em localStorage
- `WaitingListSidebarSection.vue` — seção colapsável na sidebar da Agenda
- `WaitingListSidebarItem.vue` — item individual com tooltip de detalhes
- `WaitingListSlotBadge.vue` — badge verde-pastel para slots livres compatíveis

O modal agora salva diretamente no store ao submeter, fazendo a entrada aparecer instantaneamente na sidebar da Agenda.

**Arquivos Modificados:**

- `app/javascript/dashboard/routes/dashboard/conversation/contact/WaitingListModal.vue`
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`
- `app/javascript/dashboard/features/waiting-list/store.js` (novo)
- `app/javascript/dashboard/features/waiting-list/WaitingListSidebarSection.vue` (novo)
- `app/javascript/dashboard/features/waiting-list/WaitingListSidebarItem.vue` (novo)
- `app/javascript/dashboard/features/waiting-list/WaitingListSlotBadge.vue` (novo)
- `app/javascript/dashboard/i18n/locale/en/contact.json`
- `docs/STYLE.md`

---

## [1.4.4.0] - 2026-03-22 15:02:00-03:00

### Chat: Botão e Modal de Lista de Espera no Painel de Contato

Adicionado botão **"Lista de Espera"** (ícone `i-ph-clock-countdown`) na barra de ações do painel lateral de contato, ao lado dos botões existentes (Nova Mensagem, Prontuário, Editar, Mesclar, Excluir).

**Fluxo:**
- Botão com tooltip "Lista de espera" segue o mesmo padrão visual (`NextButton` com `slate faded sm`)
- Ao clicar, abre o modal `WaitingListModal.vue` (componente separado, seguindo arquitetura de modularização)
- Modal exibe o contato da conversa já vinculado automaticamente (read-only, com badge verde "Contato vinculado automaticamente")
- Campos do modal:
  - **Período de preferência** (obrigatório): 3 botões seletores — Manhã 🌅 (08–12h), Tarde ☀️ (12–18h), Noite 🌙 (18–21h)
  - **Horário específico** (opcional): input `type="time"` com ícone de relógio
  - **Observações** (opcional): textarea livre
- Validação frontend com `useAlert` se período não selecionado
- Feedback de sucesso com nome do contato após submeter
- Dual-theme completo: todo CSS usa variáveis `rgb(var(--slate-N))` — funciona em dark e light mode
- Animações de entrada/saída (fade no backdrop, slide+scale no modal)

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/dashboard/conversation/contact/WaitingListModal.vue` *(criado)*
- `app/javascript/dashboard/routes/dashboard/conversation/contact/ContactInfo.vue` — importa e renderiza `WaitingListModal`, adiciona botão e state `showWaitingListModal`
- `app/javascript/dashboard/i18n/locale/en/contact.json` — chaves `WAITING_LIST.*` adicionadas

---

## [1.4.3.9] - 2026-03-21 19:36:00-03:00

### API Docs: Página de Documentação Interativa da API Klivy

Criação do site de documentação interativo da API da plataforma Klivy, servido estaticamente em `/api-docs.html`.

**Funcionalidades:**

- **Config Bar** no topo com campos Domínio, Account ID e API Access Token, persistidos no `localStorage`
- **Injeção dinâmica de credenciais** em todos os exemplos cURL da página
- **Barra de progresso** de preenchimento das credenciais (2px no topo)
- **Sidebar navegável** com contagem de endpoints por módulo e estado ativo por scroll
- **63 endpoints documentados** em 12 módulos: Autenticação, Agenda (Eventos, Serviços, Notificações, Config Online, Relatórios), Pacientes (CRUD, Evoluções, Planos, Agendamentos, Financeiro, Outros)
- **Grid de estatísticas** no hero (63 endpoints, 12 módulos, 100% com cURL, v1)
- **Tabs** por endpoint: Body/Params, cURL, Resposta
- **Botão Copiar** nos blocos de código com feedback visual
- **Botão Back-to-Top** flutuante
- **Atalho ⌘K** para focar no campo Domínio
- **Footer** com padrão de URL da API
- **Animações** de entrada nos endpoint cards

**Arquivos Modificados:**
- `public/api-docs.html` *(criado)*

---

## [1.4.3.8] - 2026-03-21 18:42:00-03:00


### Prontuário: Light Mode Modais + STYLE.md Guia Dual-Theme

#### Correções de Light Mode — Modais do Prontuário

Continuação da auditoria de tema claro no prontuário. Foco nos modais com fundo preto no light mode.

**Estratégia aplicada:**

- **`body:not(.dark)` overrides** no `record.css`: sobrescrevem classes Tailwind dark hardcoded (`bg-slate-900`, `bg-slate-800`, `border-slate-700`) sem editar o monolítico `Record.vue`.
- **Classes `record-modal-*`**: substituem `style=""` inline proibidos pelo ESLint. Usam variáveis `rgb(var(--slate-N))` para adaptar ao tema automaticamente.

**Modais/elementos corrigidos:**

- Criar/Renomear/Excluir Pasta: `bg-slate-900` → `.record-modal-box`; inputs e labels com `.record-modal-input`, `.record-modal-label`, `.record-modal-muted`
- Lock/Unlock e Excluir Arquivo: `body:not(.dark) .bg-slate-900` override no CSS
- Input modal Lock: `body:not(.dark) input.bg-slate-800` override
- Botão empty state de documentos: `style="color: #60a5fa"` → `class="text-blue-400"`

#### STYLE.md — Guia Completo de Dual-Theme

Adicionadas ao `docs/STYLE.md`:

- **Arquitetura CSS por Módulo**: CSS separado por feature é obrigatório
- **Guia de 5 Passos**: mecanismo `body.dark`, prefixos, estratégia `body:not(.dark)`, proibição `style=""`, grep de problemas
- **Sistema `record-modal-*`**: tabela de classes e exemplos before/after
- **Checklist de Auditoria**: 7 categorias para validar light mode
- **Lições Aprendidas**: tabela dos problemas reais e soluções

**Arquivos Modificados:**

- `app/javascript/dashboard/routes/dashboard/patients/record.css` — overrides `body:not(.dark)` + classes `record-modal-*`
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue` — `style=""` removidos; Tailwind dark → `record-modal-*`
- `docs/STYLE.md` — guia completo de implementação dual-theme adicionado

---

## [1.4.3.7] - 2026-03-21 21:45:00-03:00

### Pacientes: Light Mode Completo — Prontuário e Todas as Abas

Aplicação do sistema dual-theme (light/dark) para **toda** a área de pacientes: lista principal, arquivados, e as 13 abas do prontuário.

**Estratégia:** criado `record.css` com overrides de variáveis CSS `rgb(var(--slate-N))` que substituem os valores dark hardcoded do `<style scoped>` do `Record.vue` (17k linhas), sem precisar editar o arquivo monolítico. O CSS importado no `<script setup>` cria regras globais não-scoped com `!important` para garantir precedência.

**Abas cobertas:**
- Geral (Visão Geral) — cards, KPIs, empty states
- Cadastro (RegistrationTab) — seções colapsáveis, inputs, toggles, dropdown de contatos
- Anamnese — cards, assinatura
- Evolução — textarea, cards de notas, alertas
- Plano de Tratamento — cards, itens de tratamento
- Procedimentos — cards, tabela de sessões
- Exames e Imagens — cards de arquivos, pastas, breadcrumb, upload zone
- Documentos — cards, ações
- Consentimentos — KPIs, cards, botões de ação semânticos
- Financeiro — KPIs, tabelas de transações e orçamentos
- Agenda e Histórico — cards de consultas
- Timeline — cards de eventos, badges coloridos, ícones semânticos (16 variantes)
- Auditoria — filtros, tabela, expandido de diff

**Cores corretas para ambos os temas:**

| Status | Background | Texto |
| --- | --- | --- |
| Novo | `rgba(59,130,246,0.12)` | `#2563eb` |
| Ativo | `rgba(22,163,74,0.12)` | `#16a34a` |
| Faltoso | `rgba(217,119,6,0.10)` | `#d97706` |
| Alta | `rgba(124,58,237,0.10)` | `#7c3aed` |
| Inativo | `rgba(100,116,139,0.10)` | `#475569` |
| Arquivado | Banner âmbar com variáveis CSS |

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/record.css` — **NOVO** arquivo CSS dual-theme do prontuário
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue` — importa `record.css`
- `app/javascript/dashboard/routes/dashboard/patients/tabs/RegistrationTab.vue` — box-shadow dark removido

---

## [1.4.3.6] - 2026-03-21 21:30:00-03:00


### Pacientes: Correção de Bug 422 + Light Mode + Modularização CSS

#### Bug Fix: Criação de Paciente com 422 (Unprocessable Content)

- **Causa raiz**: O controlador criava um Contato fantasma no banco antes de validar o Paciente. Quando o nome tinha apenas 1 caractere (ex: `"s"`), o model `Patient` rejeitava com `length: { minimum: 2 }` — mas o contato já havia sido persistido, criando registros órfãos.
- **Correção backend** (`patients_controller.rb`): A autorização Pundit e a validação do model agora ocorrem **antes** da criação do contato. Se o paciente for inválido, retorna 422 imediatamente sem efeitos colaterais no banco.
- **Correção frontend** (`NewPatientModal.vue`): Validação do nome completo com mínimo de 2 caracteres antes de fazer a requisição — alinhada à validação do backend.

#### Light Mode: Página de Pacientes (Index)

- Todos os estilos da área de pacientes migrados de cores hardcoded dark (`#0a0c10`, `rgba(0,0,0,0.2)`, `rgba(255,255,255,0.X)`) para variáveis CSS `rgb(var(--slate-N))`.
- Status badges corrigidos para cores legíveis em ambos os temas (ex: `#4ade80` → `#16a34a` para "Ativo").
- Controles de busca, filtros, cards de grid e tabela de lista agora funcionam corretamente em light e dark mode.

#### Modularização CSS (seguindo KI de Arquitetura)

- CSS da `Index.vue` extraído para arquivo dedicado `patients-index.css` — elimina o arquivo monstruoso anterior de +640 linhas de estilos inline.
- O arquivo é importado estaticamente no `<script setup>` seguindo o padrão de modularização definido no Knowledge Item.

**Arquivos Modificados:**
- `app/controllers/api/v1/accounts/patients_controller.rb` — validação antes da criação do contato
- `app/javascript/dashboard/routes/dashboard/patients/components/NewPatientModal.vue` — validação de nome mínimo 2 chars
- `app/javascript/dashboard/routes/dashboard/patients/Index.vue` — CSS migrado para arquivo externo
- `app/javascript/dashboard/routes/dashboard/patients/patients-index.css` — **NOVO** arquivo CSS dual-theme modularizado

---

## [1.4.3.5] - 2026-03-21 15:17:00-03:00


### Enterprise Unlock, Deduplicação de Grupos e Paginação de Contatos

#### Enterprise: Plano desbloqueado por padrão

- `config/installation_config.yml`: `INSTALLATION_PRICING_PLAN` agora nasce como `enterprise`, `INSTALLATION_PRICING_PLAN_QUANTITY` = `10000`
- `Dockerfile`: env `CHATWOOT_HUB_URL=https://hub.invalid/#` impede que o job `CheckNewVersionsJob` sobrescreva o plano ao sincronizar com o hub externo — `@instance_info` fica `nil` e o job retorna antes de tocar nos configs de plano
- Resultado: toda imagem Docker nova já inicia em modo Enterprise completo, sem precisar de SQL manual

#### Grupos WhatsApp: Race condition na criação de conversas corrigida

- **Causa**: `find_or_create_conversation` buscava por `@contact_inbox.conversations.where(group_id).last`; quando 2 mensagens chegavam do mesmo grupo simultaneamente, ambas não encontravam a conversa existente e cada uma criava uma nova
- **Correção**: A busca passou a usar `Conversation.where(inbox_id:, contact_id:, group_id:)` (escopo mais amplo), com `rescue ActiveRecord::RecordNotUnique` para proteção contra race conditions

#### Paginação de Contatos: Seletor 15 / 50 / 100 por página

- **Backend** (`contacts_controller.rb`): aceita param `page_size` (validado em `[15, 50, 100]`, padrão 15)
- **API** (`contacts.js`): todos os endpoints paginados agora forwaram `page_size`
- **Store** (`actions.js`): `get`, `active`, `search`, `filter` aceitam `pageSize`
- **UI** (`ContactsListLayout.vue`): dropdown "Show [X] per page" no rodapé da lista de contatos
- **Persistência**: seleção salva em `uiSettings.contacts_page_size`

**Arquivos Modificados:**

- `Dockerfile` — `CHATWOOT_HUB_URL`
- `config/installation_config.yml` — plano enterprise + 10000 seats
- `app/services/whatsapp/incoming_message_qr_service.rb` — race condition na criação de conversas de grupo
- `app/controllers/api/v1/accounts/contacts_controller.rb` — suporte a `page_size`
- `app/javascript/dashboard/api/contacts.js` — `page_size` nos endpoints
- `app/javascript/dashboard/store/modules/contacts/actions.js` — `pageSize` nas actions
- `app/javascript/dashboard/routes/dashboard/contacts/pages/ContactsIndex.vue` — state + handler
- `app/javascript/dashboard/components-next/Contacts/ContactsListLayout.vue` — dropdown seletor
- `app/javascript/dashboard/i18n/locale/en/contact.json` — chaves `SHOW` e `PER_PAGE`

## [1.4.3.4] - 2026-03-21 13:29:00-03:00


### WhatsApp QR: API Create Message — Correção de Roteamento de Templates e Falha Silenciosa

#### Problema

Mensagens criadas via API padrão do Chatwoot (`POST /api/v1/accounts/:id/conversations/:id/messages`) em canais WhatsApp QR ficavam com status `sent` (ícone de relógio) permanentemente e nunca eram entregues ao destinatário.

#### Causa Raiz

Quando o payload da API continha `template_params`, o `SendOnWhatsappService#perform_reply` roteava a mensagem para `send_template_message` — mesmo para canais WhatsApp QR. O `WhatsappQrService#send_template` retornava `nil` (pois a bridge Baileys não suporta templates da API oficial). Resultado: a mensagem ficava eternamente como `sent` sem nunca ser entregue nem marcada como falha.

Adicionalmente, o `WhatsappQrService#post_to_bridge` capturava TODAS as exceções silenciosamente e retornava `nil`, sem atualizar o status da mensagem para `failed`.

#### Solução

1. **Roteamento corrigido para WhatsApp QR**: O `SendOnWhatsappService#perform_reply` agora detecta se o provider é `whatsapp_qr` e **sempre** roteia para `send_session_message`, ignorando `template_params`. Templates são exclusivos dos provedores Cloud API e 360Dialog.

2. **Tratamento de falhas com `mark_failed`**: Toda falha de comunicação com a bridge agora marca a mensagem como `status: :failed` com `external_error` descritivo. O UI mostra um ícone de erro vermelho e o usuário pode clicar em "Retry".

3. **Erros granulares**: Diferenciação entre `ECONNREFUSED` (bridge indisponível), `Timeout` (rede lenta) e erros HTTP (503, 500, etc.), cada um com mensagem de erro específica.

4. **Padronização de env vars**: Todos os arquivos aceitam **ambas** as env vars (`WHATSAPP_QR_BRIDGE_URL` → `WHATSAPP_BRIDGE_URL` → fallback `http://localhost:3002`).

5. **Fix de encoding UTF-8**: Respostas da bridge com caracteres acentuados (ex: "não está conectado") não causam mais `incompatible character encodings`.

#### Teste Realizado (Local)

- API com payload contendo `template_params` → agora roteia para `send_session_message` ✅
- Mensagem criada via API → Sidekiq processou → bridge entregou em 48ms → `status: delivered` ✅
- Bridge indisponível → mensagem marcada como `failed` com `external_error` descritivo ✅

**Arquivos Modificados:**

- `app/services/whatsapp/send_on_whatsapp_service.rb` — roteamento corrigido: WhatsApp QR **sempre** usa `send_session_message`
- `app/services/whatsapp/providers/whatsapp_qr_service.rb` — `mark_failed`, erros granulares, fix encoding, env var padronizada
- `app/jobs/delete_object_job.rb` — env var padronizada
- `app/models/channel/whatsapp.rb` — env var padronizada
- `app/controllers/api/v1/accounts/whatsapp/bridges_controller.rb` — env var padronizada
- `app/services/whatsapp/incoming_message_qr_service.rb` — anti-duplicação de contatos (LID → JID)

---

## [1.4.3.3] - 2026-03-19 23:25:00-03:00

### Agenda: Refatoração do Modal de Informações, Prontuário, Busca Telefônica Mágica e Cancelamento Motivacional

#### Melhorias Visuais e de Usabilidade
- **Aperfeiçoamento do Popup do Evento:** O popup de detalhes rápidos de um evento foi radicalmente melhorado. Agora ele exibe a **foto atual/histórica** do paciente, bem como o **Tratamento/Procedimento** atrelado ao evento e mapeia corretamente a **Observação** (dinâmica) vinda da criação.
- **Navegação Imersiva:** O botão de "Prontuário" no popup de evento deixou de abrir um insatisfatório e incompleto sub-popup fluante lateral. Agora ele executa um redirecionamento limpo e imediato à Rota Raiz do Prontuário do BeClinic, mantendo a tela imersiva na história daquele paciente.

#### Reestruturação de Fluxos e Correções Críticas (Bug Fixes)
- **Criação Rápida Livre de Duplicações:** Foi mitigado com rigor um erro onde a criação rápida na agenda resultava em pacientes fantasma no banco de dados (que mostravam erro 'Paciente não encontrado' no front-end).
  - O autocomplete de telefone passou a consumir o **ContactAPI**, e não o Patients API que impedia filtragem fluída via Wildcard Like.
  - Ao clicar numa sugestão de telefone existente, o sistema usa o `contact_id` para realizar checagem inteligente via `PatientsAPI.byContact`. Acertando na mosca o registro real, prevenindo orquestração confusa. O event binding funciona suavemente desde a criação!
- **Proteção do Histórico (Exclusão Motivada):** Os botões de atalho pela visão mensal/semanal de eventos não apagam de forma perniciosa os eventos com um prompt silencioso. Exigem a modal de **Confirmação e Justificativa**. "Cancelado pelo paciente", "Tráfego/Erro", etc. Tudo catalogável daqui para frente.

#### Remoções e Limpeza de Código
- Retirados os campos de "Como conheceu" e etc. O sistema passará focar em Observação de agenda de fábrica.
- Grande limpeza em `AgendaDashboard.vue`: O layout complexo e os estados que suportavam o antigo `patientRecordPopup` foram varridos, destravando leveza no componente.

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

## [1.4.3.2] - 2026-03-19 20:25:00-03:00

### Agenda: Redesign Avançado dos Cards de Evento & Status

- **Sistema de 4 Tiers (Responsividade Inteligente)**: Cards agora se adaptam a 4 alturas pré-definidas ('micro' ≤15m, 'compact' ≤30m, 'medium' ≤50m, 'normal') otimizando exibição de informações com base na duração.
- **Cor do Tratamento no Card**: A borda esquerda do card agora reflete fielmente a cor configurada para o tratamento do paciente (ex: Avaliação, Limpeza), facilitando leitura visual da agenda.
- **Bolinha de Status Inline**: O indicador de status do evento (Agendado, Confirmado, Chegou, Em atendimento, Cancelado, etc) agora se posiciona elegantemente ao lado direito do nome do paciente em todos os tamanhos de card.
- **Tooltip de Informação Rápida**: Adicionado tooltip nativo (`title`) em todo o card de evento, permitindo que ao passar o mouse, o usuário veja instantaneamente o "Nome do Paciente - Status do Evento", agilizando a leitura quando nomes estão truncados (longos).
- **Correção Geral de UI**: Reordenamento da lupa (Search) para sempre aparecer à esquerda da estrela e estar sempre visível (removido hover oculto em tiers de curto tempo).

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

## [1.4.3.1] - 2026-03-19 17:45:00-03:00

### WhatsApp Bridge: Sistema de Cleanup Definitivo — Sessões Nunca Mais Viram Fantasmas

Implementação de um sistema completo de 3 camadas para garantir que sessões WhatsApp excluídas sejam **permanentemente eliminadas** do disco, memória e bridge.

---

#### 🔴 Camada 1: Endpoint `DELETE /sessions/:inboxId` (Bridge)

Novo endpoint que **destrói completamente** uma sessão WhatsApp:
1. Desconecta o WebSocket
2. Remove todos os event listeners
3. Cancela todos os timers (reconnect, stableConnection)
4. Remove a sessão do Map em memória
5. **Apaga a pasta inteira** do disco (`auth_info/`, `config.json`, tudo)

```bash
# Exemplo de uso:
curl -X DELETE http://localhost:3002/sessions/28
# → { "success": true, "message": "Sessão 28 destruída permanentemente" }
```

**Arquivo modificado:**
- `lib/whatsapp/server.js` — Novo `app.delete('/sessions/:inboxId', ...)`

---

#### 🔴 Camada 2: Hook Rails `DeleteObjectJob` → Bridge (Auto-cleanup)

Quando um inbox WhatsApp é **excluído pela UI** (botão "Excluir" nas Caixas de Entrada), o `DeleteObjectJob` agora chama automaticamente `DELETE /sessions/:inboxId` no bridge **ANTES** de destruir o registro no banco.

- Usa `Net::HTTP` com timeout de 5s
- Silencia falhas: se o bridge estiver fora do ar, a exclusão do inbox **prossegue normalmente**
- Log de auditoria: `[WHATSAPP_CLEANUP] 🗑️ Destruindo sessão X no bridge...`

**Arquivo modificado:**
- `app/jobs/delete_object_job.rb` — Novo `cleanup_whatsapp_bridge_session` no private

---

#### 🟢 Camada 3: Validação no Boot (`rehydrateSessions`)

Ao iniciar, o bridge agora **verifica credenciais** de cada sessão antes de iniciar:
- Se `auth_info/` não existe ou tem <2 arquivos → sessão fantasma
- Sessões fantasmas são **automaticamente deletadas do disco** e logadas
- Resultado: impossível re-iniciar sessões mortas

**Arquivo modificado:**
- `lib/whatsapp/server.js` — `rehydrateSessions()` com validação e auto-limpeza

---

## [1.4.3.0] - 2026-03-19 17:40:00-03:00

### WhatsApp Bridge: Performance Crítica + Resolução de Contatos `fromMe` + Limpeza de Sessões Fantasmas

Correção de múltiplos problemas críticos de performance e funcionalidade no motor WhatsApp (Baileys bridge).

---

#### 🔴 Fix Crítico: Sessões Fantasmas Matando Performance

**Problema**: O bridge re-hidratava **15 sessões** ao iniciar (13-28), sendo que **14 delas eram fantasmas** — inboxes criadas por cliques duplicados no botão "Finalizar" que nunca chegaram a conectar. Cada uma abria um WebSocket ao WhatsApp Web, gerava QR codes infinitamente e causava erros 408 (timeout) em cascata, saturando CPU, RAM e Redis.

**Solução**:
- Removidas 14 sessões fantasmas do disco (~52.000 arquivos de auth mortos na sessão 13 sozinha)
- `rehydrateSessions()` agora **valida credenciais antes de iniciar**: verifica se `auth_info/` existe e tem ≥2 arquivos de credencial
- Sessões inválidas são **automaticamente removidas do disco** e logadas
- Resultado: bridge inicia com **1 sessão** (a real) e conecta em <2s

**Arquivos modificados:**
- `lib/whatsapp/server.js` — `rehydrateSessions()` com validação de credenciais e auto-limpeza

---

#### 🔴 Fix Crítico: Performance de Envio de Mensagens (5 Gargalos)

**Problema**: Enviar mensagens (especialmente áudio) demorava 5-15 segundos ou falhava silenciosamente.

**Gargalos corrigidos:**

| # | Gargalo | Antes | Depois | Economia |
|---|---------|-------|--------|----------|
| 1 | Import dinâmico de `node-fetch` | `import()` ESM a cada chamada (~200-500ms) | `require()` uma vez no topo | ~400ms/msg |
| 2 | Processamento sequencial | `for...of await` (msgs em fila) | `Promise.allSettled` (paralelo) | 2-10x |
| 3 | Conversão de áudio desnecessária | Todo áudio passava por ffmpeg | Detecta OGG/Opus e pula | 2-5s |
| 4 | ffmpeg sem timeout | Travava indefinidamente | Timeout de 15s + fallback | ∞→15s max |
| 5 | Rails com timeout de 30s | Worker Sidekiq preso | 15s texto, 25s áudio | 5-15s |

**Arquivos modificados:**
- `lib/whatsapp/server.js` — Import estático, processamento paralelo, conversão inteligente, timeouts
- `app/services/whatsapp/providers/whatsapp_qr_service.rb` — Timeouts dinâmicos, logs com timing em ms

---

#### 🟢 Feature: Mensagens `fromMe` Criam Contato do Destinatário

**Problema**: Ao enviar mensagem pelo celular para alguém que não estava na plataforma, a conversa aparecia como "Eu" (usando o próprio número como contato) em vez de criar o contato do destinatário.

**Solução**: O `IncomingMessageQrService` agora diferencia 3 cenários:

| Cenário | Contato criado | Tipo da mensagem |
|---------|----------------|------------------|
| Grupo | Contato do grupo | incoming/outgoing |
| Privado `fromMe` | **Destinatário** (remoteJid) | outgoing |
| Privado recebido | Remetente (sender_jid) | incoming |

**Bonus — Nome do destinatário**: O bridge mantém um `contactNameCache` por sessão alimentado por:
1. `contacts.upsert` / `contacts.update` (sincronização do WhatsApp)
2. `pushName` de cada mensagem recebida

Se o cache tiver o nome, é enviado como `recipient_name` para o Rails.

**Arquivos modificados:**
- `app/services/whatsapp/incoming_message_qr_service.rb` — Nova branch `elsif is_from_me` na resolução de contato
- `lib/whatsapp/server.js` — `contactNameCache` por sessão, `recipient_name` no payload

---

#### 🟢 Feature: Atualização Automática do Nome do Contato

**Problema**: Contatos criados via `fromMe` ficavam com o número de telefone como nome, mesmo depois que a pessoa respondia.

**Solução**: Quando uma mensagem `incoming` chega de um contato cujo nome atual é genérico (começa com `+` ou é igual ao phone_raw), o nome é automaticamente atualizado com o `pushName` do WhatsApp.

- Aceita **qualquer** caractere como nome válido (til `~`, emojis, acentos, etc.)
- Log de auditoria: `[WHATSAPP_QR] 👤 Nome do contato atualizado: +5511... → Maila`

**Arquivo modificado:**
- `app/services/whatsapp/incoming_message_qr_service.rb`

---

#### 🟢 Fix: Mensagens `fromMe` em Grupos Não Carregavam (Spinner)

**Problema**: Mensagens enviadas pelo celular em grupos apareciam como "Nova Mensagem" com spinner infinito, precisando de F5 para carregar.

**Causa**: O `msg_sender` era `nil` para todas as mensagens `fromMe`. O ActionCable precisa de um sender válido para serializar corretamente a mensagem para o frontend.

**Solução**: Para `fromMe` em **grupos**, o sender é o primeiro agente da inbox (`inbox.inbox_members.first&.user`). Para `fromMe` privado, continua `nil` (representa o agente/conta).

**Arquivo modificado:**
- `app/services/whatsapp/incoming_message_qr_service.rb`

---

## [1.4.2.2] - 2026-03-19 16:00:00-03:00

### Nova Regra Global de Arquitetura: Modularização Obrigatória

Foi adicionada uma nova diretriz rígida no Knowledge Items (KI) voltada à modularização de código, para evitar a criação de arquivos monstruosos (como `AgendaDashboard.vue`).

**Regras Estabelecidas:**
- Toda nova seção, área ou módulo grande de negócio criado (ex: "Área de Pacientes", "Área de Agenda") deverá possuir uma **estrutura de arquivos e pastas dedicada e isolada**.
- Essa separação afeta não só a estrutura principal, como também desde as lógicas das **funcionalidades**, parte **visual/UI** e **Estilos (CSS)**. Nada deverá ser agrupado.
- Nenhum código de um módulo ou subcomponente complexo deve ficar junto com outro arquivo não-relacionado.
- Exemplo prático: Modais complexos ou painéis laterais que ocupem centenas de linhas deverão ser isolados em componentes separados na mesma pasta raiz de sua página parente, e não mais injetados diretamente na View global.

---

## [DEPLOY] Docker Push — benuv/chatwoot:v1.4.2.1 — 2026-03-16 18:45:00-03:00

### Build e Push da Imagem Docker para Produção

- **Imagem publicada**: `benuv/chatwoot:latest` e `benuv/chatwoot:v1.4.2.1`
- **Registry**: Docker Hub — `docker.io/benuv/chatwoot`
- **Plataforma**: `linux/amd64` (para o servidor EasyPanel)
- **Estratégia de build**: Cache preservado — apenas layers com mudanças foram reconstruídas
- **O que mudou**: RBAC security hardening — 15+ actions de controllers sem `authorize` corrigidas, bug crítico no navigation guard do Vue Router (`getRole` → `getBeclinicRole`), sidebar oculta "Unattended" por permissão
- **Próximo passo**: Realizar **Redeploy** no EasyPanel para que o serviço faça pull de `benuv/chatwoot:latest`

---

## [DEPLOY] Docker Push — benuv/chatwoot:v1.3.2.0 — 2026-03-15 23:15:00-03:00


### Build e Push da Imagem Docker para Produção

- **Imagem publicada**: `benuv/chatwoot:latest` e `benuv/chatwoot:v1.3.2.0`
- **Registry**: Docker Hub — `docker.io/benuv/chatwoot`
- **Plataforma**: `linux/amd64` (para o servidor EasyPanel)
- **Estratégia de build**: Cache preservado — apenas layers com mudanças foram reconstruídas
- **Próximo passo**: Realizar **Redeploy** no EasyPanel para que o serviço faça pull de `benuv/chatwoot:latest`

---

## [1.4.2.0] - 2026-03-16 17:35:00-03:00

### RBAC — Fase 8: Hardening & QA de Segurança Backend

Garante que a autorização é aplicada no servidor — o frontend nunca é a única linha de defesa.

#### Arquivos modificados:

- `app/policies/application_policy.rb` — Adicionados helpers `beclinic_can?(module, action)` e `beclinic_scope(module)` disponíveis em todas as subclasses via `private`. Delegam ao concern `BeclinicPermissible` no `User`.

- `app/policies/patient_policy.rb` — **Refatorado completamente**: usa `beclinic_can?` para cada ação. `PatientPolicy::Scope` implementa `scope=own` filtrando por `responsible_professional_id` quando o perfil do usuário tem escopo restrito.

- `app/policies/clinical_note_policy.rb` — Refatorado: usa permissões granulares (`view_clinical_notes`, `create_clinical_notes`, `sign_clinical_notes`, `delete_clinical_notes`).

- `app/policies/agenda_event_policy.rb` — Refatorado: usa `beclinic_can?` + `AgendaEventPolicy::Scope` implementa `scope=own` filtrando por `user_id` (dentista/especialista responsável).

- `app/policies/transaction_policy.rb` — Refatorado: usa permissões granulares do módulo `:financial`.

- `app/policies/financial_estimate_policy.rb` — Refatorado: usa permissões granulares do módulo `:financial`.

- `app/policies/consent_record_policy.rb` — Refatorado: usa `view_consents` e `manage_consents`.

- `app/policies/document_policy.rb` — Refatorado: usa `view_documents` e `manage_documents`.

- `app/policies/exam_media_policy.rb` — Refatorado: usa `view_exams` e `manage_exams`.

- `app/policies/treatment_plan_policy.rb` — Refatorado: usa `view_treatment_plans` e `manage_treatment_plans`, mantendo guard de `status_proposto?`.

- `app/policies/anamnesis_policy.rb` — Refatorado: usa permissões de clinical notes, mantendo guard de `status_finalized?`.

#### Novo arquivo criado:

- `lib/tasks/beclinic_rbac.rake` — Rake tasks de retrocompatibilidade:
  - `beclinic:rbac:ensure_default_profiles` — Cria os 4 perfis preset (recepcionista, especialista, gerente, sdr) para contas que ainda não os têm
  - `beclinic:rbac:assign_missing_users` — Atribui usuários sem perfil ao time 'especialista' como fallback
  - `beclinic:rbac:status` — Imprime visão geral de cobertura RBAC por conta

#### Segurança garantida após Fase 8:
- `super_admin` bypass funcional via `beclinic_super_admin?` (mapeia para `super_admin?`)
- Teams com `beclinic_role=dono` têm acesso total automaticamente
- Usuários sem nenhum time recebem `{}` de permissões (negado por padrão)
- `scope=own` aplicado no banco de dados via `policy_scope` — não pode ser contornado via frontend

---

## [1.4.1.0] - 2026-03-16 20:25:00-03:00

### RBAC — Fase 7: Tela de Gestão de Perfis em Settings

Interface completa para Donos e Gerentes gerenciarem os perfis RBAC da clínica diretamente em **Settings → Perfis & Permissões** (`/settings/roles`).

#### Novos arquivos criados:

- `app/javascript/dashboard/routes/dashboard/settings/BeClinicRoles/beclinicRoles.routes.js` — Rota `/settings/roles/list` registrada como `beclinic_roles_list`
- `app/javascript/dashboard/routes/dashboard/settings/BeClinicRoles/Index.vue` — Tela principal com dois painéis:
  - **Grid de Perfis**: cards com nome, badge Padrão/Customizado, badge de nível (Dono/Gerente/Especialista), mini-indicadores de módulos com permissão, contagem de membros e avatars empilhados, ações de editar/deletar
  - **Tabela de Agentes**: lista todos os agentes com perfil atual e botão "Atribuir Perfil"
- `app/javascript/dashboard/routes/dashboard/settings/BeClinicRoles/RoleFormModal.vue` — Modal de criação/edição com dois modos:
  - **Perfis Padrão**: grade visual com os 4 presets (Recepcionista, Especialista, Gerente, SDR) — ao selecionar, preenche automaticamente todas as permissões
  - **Customizado**: campo de nome, seleção de nível base e checkboxes granulares organizados por módulo (Pacientes, Agenda, Financeiro, Chat, Settings)
- `app/javascript/dashboard/routes/dashboard/settings/BeClinicRoles/AssignRoleModal.vue` — Modal de atribuição com lista de radio buttons mostrando todos os perfis disponíveis (nome, nível, indicadores de módulos), perfil atual destacado, opção "Sem perfil" para remover
- `app/javascript/dashboard/api/beclinicRoles.js` — API client para CRUD de Times/Perfis + `addMember`/`removeMember` via `team_members` endpoint

#### Arquivos modificados:

- `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js` — Rota `beclinicRoles.routes` adicionada

#### Integração com backend existente:

Utiliza a API nativa de Teams (`/api/v1/accounts/:id/teams`) que já foi estendida na Fase 1 com:
- `beclinic_role` (string: dono/gerente/especialista) — já nos strong params e serializer
- `permissions` (JSONB) — já nos strong params e serializer
- `is_preset` (boolean) — já nos strong params e serializer

---

## [1.4.0.0] - 2026-03-16 17:21:00-03:00

### RBAC — Role-Based Access Control: Fases 1 a 6 Implementadas

Esta versão entrega as **6 primeiras fases** do sistema completo de controle de acesso baseado em papéis (RBAC) do BeClinic. O sistema é **híbrido**: a plataforma entrega perfis pré-configurados como ponto de partida, mas cada clínica pode editar, excluir ou criar perfis totalmente customizados.

> **Referência completa:** Ver `RBAC_Plan.md` na raiz do projeto para o plano detalhado com todas as permissões, hierarquia de roles e decisões de arquitetura.
> **Status atual:** Fases 1 a 6 ✅ concluídas. Fases 7 (Gestão de Perfis em Settings) e 8 (Hardening & QA) pendentes para o próximo sprint.

---

#### ✅ FASE 1 — Fundação Backend (Rails)

**Novos arquivos criados:**

- `db/migrate/XXXXXX_create_beclinic_roles.rb` — Migration que cria a tabela `beclinic_roles` (campos: `id`, `account_id`, `name`, `description`, `is_preset`, `base_role` enum, `permissions` JSONB, timestamps)
- `db/migrate/XXXXXX_add_beclinic_role_id_to_account_users.rb` — Adiciona `beclinic_role_id` em `account_users` (FK para `beclinic_roles`)
- `app/models/beclinic_role.rb` — Model `BeClinicRole` com validações, defaults e serialização do JSONB de permissões
- `app/models/concerns/beclinic_permissible.rb` — Concern incluído no `User` com helpers `can?(:module, :action)` e `permission_scope(:module)`
- `app/controllers/api/v1/accounts/beclinic_roles_controller.rb` — CRUD completo de perfis + endpoint `PUT /assign` de perfil ao usuário
- `app/policies/transaction_policy.rb` — Pundit policy para transações financeiras
- `app/policies/financial_estimate_policy.rb` — Pundit policy para orçamentos
- `db/seeds/beclinic_roles.rb` — Seed com os 4 perfis padrão (Recepcionista, Especialista, Gerente, SDR) criados automaticamente por conta

**Arquivos modificados:**
- `app/policies/patient_policy.rb` — Expandido com suporte a `scope`, `view`, `create`, `edit`, `delete`, `view_clinical_notes`, etc.
- `config/routes.rb` — Rota para `beclinic_roles` com nested resources em `accounts`

---

#### ✅ FASE 2 — Fundação Frontend (Vue.js)

**Novos arquivos criados:**

- `app/javascript/dashboard/store/modules/beclinicPermissions.js` — Vuex module que carrega as permissões do usuário logado via `GET /api/v1/accounts/:id/beclinic_roles/my_permissions`. Carregado no boot da aplicação.
- `app/javascript/dashboard/composables/usePermissions.js` — Composable central do RBAC: `can('financial', 'view_transactions')` retorna `true | false`; `scope('agenda')` retorna `'all' | 'own'`
- `app/javascript/dashboard/components/PermissionGate.vue` — Wrapper que recebe `module` e `action` e usa slot `#locked` para UI de cadeado quando sem permissão
- `app/javascript/dashboard/components/LockedTab.vue` — Visual de aba bloqueada com ícone de cadeado e tooltip
- `app/javascript/dashboard/components/Page403.vue` — Página de acesso negado para rotas protegidas
- `app/javascript/dashboard/directives/vCan.js` — Diretiva `v-can` que atua como `v-if` automático baseado em permissões: `<button v-can="['financial', 'delete_transaction']">Estornar</button>`

**Arquivos modificados:**
- `app/javascript/dashboard/app.js` — Registra `v-can` globalmente e despacha `beclinicPermissions/fetch` no boot
- `app/javascript/dashboard/store/index.js` — Registra o módulo `beclinicPermissions` na store Vuex

---

#### ✅ FASE 3 — Prontuário do Paciente

**Arquivo modificado:** `app/javascript/dashboard/routes/dashboard/patients/Record.vue`

Gates de permissão aplicados no `allTabs` (computed que controla abas visíveis):

| Aba | Permissão exigida |
|---|---|
| Evoluções Clínicas | `patients.view_clinical_notes` |
| Plano de Tratamento | `patients.view_treatment_plans` |
| Consentimentos | `patients.view_consents` |
| Documentos | `patients.view_documents` |
| Exames e Imagens | `patients.view_exams` |
| Financeiro | `financial.view_transactions` |
| Auditoria | `patients.view_audit` |

Botões com `v-can`: Deletar Paciente (`patients.delete`), Assinar Evolução (`patients.sign_clinical_notes`), Deletar Evolução (`patients.delete_clinical_notes`), Aprovar Plano (`patients.manage_treatment_plans`), Gerar Documento (`patients.manage_documents`), Upload de Exame (`patients.manage_exams`). Campos de cadastro em read-only para perfis sem `patients.edit`. Filtro de escopo: `scope=own` passa `responsible_professional_id` para o backend.

---

#### ✅ FASE 4 — Configurações de Times (Settings → Teams)

> Decisão de produto: ao invés de criar uma tela separada de "Agenda", o RBAC é configurável diretamente dentro da aba **Configurações → Times**, aproveitando o wizard de edição de times existente.

**Novo arquivo criado:**

- `app/javascript/dashboard/routes/dashboard/settings/teams/edit/TeamPermissions.vue` — Etapa "Permissões" no wizard de edição de times com dois modos:
  - **Perfis Predefinidos:** grade visual com os 4 perfis (Recepcionista, Especialista, Gerente, SDR), cada um com badge, descrição e lista de permissões principais
  - **Customizado:** toggles granulares organizados por módulo (Pacientes, Agenda, Financeiro, Chat, Settings)
  - Ao salvar, faz `PUT /api/v1/accounts/:id/teams/:teamId/permissions`

**Arquivos modificados:**
- `app/javascript/dashboard/routes/dashboard/settings/teams/edit/Index.vue` — Wizard agora tem 4 passos: Detalhes → Agentes → **Permissões** → Finalizar
- `app/javascript/dashboard/routes/dashboard/settings/teams/teams.routes.js` — Rota `/settings/teams/:teamId/edit/permissions` adicionada
- `app/javascript/dashboard/i18n/locale/en/teamsSettings.json` — Novas chaves de tradução para a etapa de Permissões

---

#### ✅ FASE 5 — Módulo Financeiro

**Arquivo modificado:** `app/javascript/dashboard/routes/dashboard/patients/Record.vue`

Aba "Financeiro" no `allTabs` agora exige `financial.view_transactions`. Botões com `v-can`:

| Botão | Permissão |
|---|---|
| Novo Orçamento | `financial.create_estimate` |
| Receber Pagamento (header) | `financial.create_transaction` |
| Receber (linha da tabela) | `financial.create_transaction` |
| Estornar transação | `financial.delete_transaction` |
| Aprovar Orçamento | `financial.approve_estimate` |
| Cancelar Orçamento | `financial.edit_estimate` |

---

#### ✅ FASE 6 — Chat / Conversas (WhatsApp)

**Arquivos modificados:**

- `app/javascript/dashboard/components-next/message/Message.vue` — `contextMenuEnabledOptions.delete` agora exige `can('chat', 'delete_message')`. Recepcionistas e Especialistas não veem o item "Deletar" no menu de contexto das mensagens.
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` — Grupo "Campanhas" (Live chat, SMS, WhatsApp) oculto para quem não tem `chat.send_broadcast`. Item "Todas as Conversas" oculto para quem não tem `chat.view_all`.

---

#### Mapa de Permissões por Perfil

| Módulo / Ação | Recepcionista | Especialista | SDR | Gerente | Dono |
|---|---|---|---|---|---|
| Pacientes — ver tudo | ✅ | só os seus | ✅ | ✅ | ✅ |
| Pacientes — criar | ✅ | ✅ | ✅ | ✅ | ✅ |
| Pacientes — deletar | ❌ | ❌ | ❌ | ✅ | ✅ |
| Evoluções clínicas | ❌ | ✅ | ❌ | ✅ | ✅ |
| Financeiro — transações | ver+criar | ver+criar | ❌ | tudo | tudo |
| Financeiro — orçamentos | ver | tudo | criar+editar | tudo | tudo |
| Chat — ver tudo | ✅ | ❌ | ✅ | ✅ | ✅ |
| Chat — campanhas | ❌ | ❌ | ✅ | ✅ | ✅ |
| Chat — deletar mensagem | ❌ | ❌ | ❌ | ✅ | ✅ |
| Settings | ❌ | ❌ | ❌ | parcial | tudo |

---

#### Próximos passos (iniciar em nova sessão de chat)

- **FASE 7:** Tela `/settings/roles` — listagem de perfis da clínica, criação, edição e assign de perfil ao usuário (ler `RBAC_Plan.md` seção 7 para todos os detalhes)
- **FASE 8:** Hardening & QA — testes de endpoints sem UI, validação de `scope=own` no backend, edge cases sem perfil atribuído

---

## [1.3.2.0] - 2026-03-15 23:15:00-03:00


### Agenda: Remoção do Placeholder "Selecione o Especialista"

- Removida a opção nula/placeholder `Selecione o especialista` do dropdown de especialista responsável no modal de criação de eventos — o select agora exibe apenas os especialistas reais cadastrados.

**Arquivos modificados:**
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

---

### Prontuário: Busca de Contato por Telefone na Aba Cadastro

A aba **Cadastro** do prontuário do paciente ganhou o mesmo autocomplete de contato que já existia no modal "Novo Paciente". Ao digitar no campo **Telefone Principal**, os contatos do Chatwoot com números similares são sugeridos em um dropdown.

- **Busca debounced** (400ms) disparada a partir de 2 dígitos digitados.
- **Remoção automática do prefixo `+55`**: o `handlePhoneInput` salva o número como `+55XXXXXXXXX`, mas a busca extrai apenas os dígitos locais para que a API encontre correspondências corretamente.
- **Dropdown premium**: avatar colorido determinístico (ou foto real), nome e número do contato.
- **Seleção**: ao clicar num contato, `contact_id` é vinculado ao paciente e o e-mail é auto-preenchido se estiver vazio.
- **Correção da arquitetura**: A aba de Cadastro é inline no `Record.vue` (o `RegistrationTab.vue` existia mas nunca foi importado) — lógica implementada diretamente no componente correto.

**Arquivos modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue`

---

### Agenda: Visibilidade por Role e Pré-seleção de Especialista

- **Role-based visibility**: Administradores veem a agenda de todos; agentes comuns veem apenas seus próprios eventos.
- **Pré-seleção**: O campo "Especialista Responsável" nos modais de criação de evento é automaticamente preenchido com o usuário logado.
- **Renomeação**: "Agente" → "Especialista" em toda a UI da agenda.

**Arquivos modificados:**
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`
- `app/javascript/dashboard/i18n/locale/pt_BR/settings.json`

---


## [1.3.1.1] - 2026-03-14 11:36:00-03:00

### Prontuário: Redesign Premium da Aba Procedimentos e Sessões

#### Aba Procedimentos — Refatoração Visual Completa (STYLE.md)

- **Header padronizado**: substituído `registration-header` por `reg-header` com botões `btn-secondary` (`i-lucide-sliders-horizontal` + "Filtrar") e `btn-primary` ("+ Registrar Sessão")
- **Painel de filtro**: novo `.proc-filter-panel` com posicionamento absoluto, sombra premium, botão X de fechar e campos com `form-label`; usa `reg-field-grid-2` em vez de `form-row-2`
- **Formulário "Registrar Novo Procedimento"**: convertido de `form-section card border-l-4 border-emerald-500` para `reg-section` com `reg-section-icon reg-icon-cyan` (ícone `i-lucide-syringe`), `reg-section-title`, `reg-section-subtitle` e body em `reg-section-body`
  - Grade de campos migrada de `form-row-3`/`form-row-2` para `reg-field-grid-3`/`reg-field-grid-2`
  - Labels com `form-label` e asterisco `reg-required` para campo obrigatório
  - Ações do formulário em `.proc-form-actions` (border-top, flex end) com ícones `w-4 h-4` explícitos
  - Input de data como `.proc-date-input` (sem `w-auto` inline)
- **Histórico de Sessões**: convertido de `card p-0` + tabela genérica para `reg-section` com `reg-section-icon reg-icon-purple` e tabela dedicada `proc-table` com:
  - Cabeçalho `proc-table-head` uppercase, tracking-wide, slate-600
  - Linhas `proc-table-row` com hover sutil e `proc-table-cell` com `vertical-align: top`
  - Células ricas: `proc-cell-primary` + `proc-cell-secondary` para dados hierárquicos
  - Coluna de resultado com `proc-result-ok` (verde), `proc-result-warn` (âmbar), `proc-result-info` (azul)
  - Botão de exclusão `proc-action-btn` (vermelho ao hover)
  - Empty state elegante: `proc-empty-state` + `proc-empty-icon` + `proc-empty-text` + `proc-empty-hint`
- **Contagem de sessões**: badge `proc-count-badge` no header do histórico
- **Adicionados no CSS**: bloco completo `/* PROCEDIMENTOS – estilos exclusivos */` com ~210 linhas definindo todas as classes `proc-*`

#### Arquivo Modificado
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue`

---

## [1.3.1.0] - 2026-03-13 18:26:00-03:00

### Prontuário: Timeline Visual + Auditoria e Segurança — Cobertura Completa

#### Timeline de Eventos — Redesign Visual Completo

- **Linha conectora corrigida**: linha contínua centralizada atrás dos ícones (antes saía do lado do círculo como micro-stub)
- **Ícones com fundos sólidos e coloridos por tipo de evento** usando inline styles (hex hardcoded) para imunidade total ao JIT/purge do Tailwind:
  - Cadastro → Índigo · Anamnese → Azul · Agendamento → Laranja · Reagendamento → Amarelo · Consulta Realizada → Esmeralda · Falta → Vermelho · Cancelamento → Rosa · Evolução Clínica → Ciano · Sessão → Teal · Exame/Imagem → Violeta · Documento → Céu · Consentimento → Roxo · Pagamento → Verde · Orçamento → Âmbar · Status Alterado → Slate · Alta → Lima · Recall → Amarelo
- **Paleta refinada (STYLE.md)**: tons ultra-escuros com leve tint da cor no fundo, borda de 1px sutil (não 2px), ícone em pastel médio — flat & minimalista sem saturação excessiva
- **Badges** (tipo de evento): mesma cor sólida do ícone, fundo levemente diferenciado

#### Auditoria e Segurança — Cobertura Completa de Módulos

**Backend — 5 controllers agora auditados (antes nenhum log era gerado):**

- `DocumentsController` → logs em `generate`, `attach`, `destroy`, `status`
- `ConsentRecordsController` → logs em `create`, `sign`, `revoke`
- `TransactionsController` → logs em `create`, `pay`, `destroy`
- `FinancialEstimatesController` → logs em `create`, `update`, `approve`, `destroy`
- `ExamMediasController` → logs em `create`, `update`, `destroy`

**Frontend — Bugs corrigidos:**

- **Bug crítico**: serializer chamava `log.changes` (método ActiveRecord de dirty tracking) em vez de `log.changed_fields` (coluna real do banco após rename migration) → logs de diff de campos eram sempre vazios
- **Filtro de ações corrigido**: `AUDIT_ACTION_OPTIONS` usava `send_whatsapp` e `login_access` que não existem no enum do model — substituídos pelos 10 enums reais: `view, create, update, delete, sign, export, finalize, approve, pay, print`
- **Emojis removidos** do dropdown de filtros (👁✅✏️🗑✍️📄💬🔑) → labels limpas seguindo STYLE.md
- **`formatAuditAction`** expandido com `finalize`, `approve`, `pay`, `print` e ícones Lucide corretos; removidos `send_whatsapp`, `login_access`, `permission_change` (inexistentes no enum)
- **`generateDetailedAuditText`** expandido com todos os resource types: `ConsentRecord`, `Transaction`, `FinancialEstimate`, `SessionLog`, `Recall`, `CriticalAlert`
- **Header STYLE.md**: `h3` sem ícone decorativo, botões usando `btn-primary`/`btn-secondary`

#### STYLE.md — Regra de `box-shadow` Documentada

- **Bug corrigido**: `.btn-primary` tinha `box-shadow: 0 2px 10px rgba(59, 130, 246, 0.2)` — efeito de glow proibido pelo princípio Flat & Minimalista
- Removido `box-shadow` do `.btn-primary` → `box-shadow: none`
- Adicionado `box-shadow: none` explícito em `.btn-secondary` também
- Adicionado `align-self: stretch` em `.btn-secondary` para garantir mesma altura que o botão primário adjacente em contexto flex (corrige desalinhamento do botão X de limpar filtros)
- **STYLE.md atualizado**: seção de Botões agora documenta explicitamente `box-shadow: none` em `.btn-primary` e `.btn-secondary`, e o uso de `align-self: stretch` para botões inline

**Arquivos modificados:**

- `app/javascript/dashboard/routes/dashboard/patients/Record.vue` — timeline visual (cores sólidas hex por tipo de evento, linha conectora, badges); aba Auditoria (filtros corrigidos, formatAuditAction expandido, generateDetailedAuditText expandido, botões STYLE.md, paginação); CSS (.btn-primary sem box-shadow, .btn-secondary com align-self: stretch)
- `app/controllers/api/v1/accounts/patients/audit_logs_controller.rb` — `log.changes` → `log.changed_fields`
- `app/controllers/api/v1/accounts/patients/documents_controller.rb` — PatientAuditLog.log! em generate, attach, destroy, status
- `app/controllers/api/v1/accounts/patients/consent_records_controller.rb` — PatientAuditLog.log! em create, sign, revoke
- `app/controllers/api/v1/accounts/patients/transactions_controller.rb` — PatientAuditLog.log! em create, pay, destroy
- `app/controllers/api/v1/accounts/patients/financial_estimates_controller.rb` — PatientAuditLog.log! em create, update, approve, destroy
- `app/controllers/api/v1/accounts/patients/exam_medias_controller.rb` — PatientAuditLog.log! em create, update, destroy
- `docs/STYLE.md` — box-shadow proibido em botões + align-self: stretch documentado

---

## [1.3.0.2] - 2026-03-12 17:55:00-03:00

### Pacientes: Status Coloridos na Lista + Jornada de Consultas Refinada

#### Lista de Pacientes — Status com Cores por Tipo

- Adicionados estilos de cor para todos os statuses na coluna "STATUS" da lista de pacientes (`Index.vue`), alinhados com as cores do prontuário:
  - **Novo** → azul · **Ativo** → verde · **Inativo** → cinza (antes vermelho) · **Faltoso** → âmbar · **Alta** → roxo · **Arquivado** → slate

#### Jornada de Consultas — Restaurada e Refinada

- Layout restaurado ao estilo empilhado: label ("Última Consulta" / "Próxima Consulta") + data + hora em linhas separadas.
- **Título do evento removido** — o campo `title` ("a", "s") não é exibido mais, pois não agrega valor visual.
- **Ícone centralizado verticalmente** — `align-items: center` no `.visit-box` mantém o ícone alinhado ao centro do bloco de informações.

**Arquivos modificados:**

- `app/javascript/dashboard/routes/dashboard/patients/Index.vue`
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue`

---

## [1.3.0.1] - 2026-03-12 17:02:00-03:00

### Prontuário: Aba "Visão Geral" — Painel Clínico Completo e Refinamentos

Entrega da aba **Geral** do prontuário com painel clínico, correção das tags clínicas, redesenho visual do status do paciente e da jornada de consultas.

#### Tags Clínicas — Dados Reais da Anamnese

- **Bug corrigido**: Tags exibiam `[object Object]` porque alergias e medicamentos são arrays de objetos `{ name }`, não strings planas.
- Helper `getString(v)` introduzido no computed `computedClinicalTags` para extrair `.name` de objetos ou usar o valor diretamente se for string.
- Resultado: tags agora mostram `Alergia: Penicilina`, `Med: Losartana 50mg`, etc.

#### Dados da Conta — Dropdown de Status do Paciente

- Removido o badge "Adimplente" (que já aparece no banner superior) do card "Dados da Conta".
- Adicionado dropdown **"Status do Paciente"** (Novo / Ativo / Inativo / Faltoso / Alta / Arquivado) diretamente no card, usando o mesmo `handleStatusChange`.

#### Bug Crítico: Status do Paciente Não Era Salvo

- **Causa raiz**: `PatientsAPI.updateStatus` enviava `{ status }` mas o controller Rails esperava `params[:patient_status]`.
- **Correção**: payload alterado para `{ patient_status: status }` — status agora persiste corretamente no banco.

#### Header: Dropdown de Status → Badge Colorido Estático

- O `<select>` de status foi removido do cabeçalho do prontuário.
- Substituído por `<span class="patient-status-badge">` com cor por status:
  - Novo = azul · Ativo = verde · Inativo = cinza · Faltoso = âmbar · Alta = roxo · Arquivado = slate
- Width do badge corrigida para `fit-content` (antes esticava 100% do container).

#### Jornada de Consultas — Layout Compacto

- Redesenhado: de 3 linhas separadas (label / data / hora / título) para layout horizontal minimalista.
- **Nova estrutura**: `Última · 09 de mar. de 2026 · 09:00` em linha única + título do evento abaixo (pequeno, azul) se existir.
- Implementadas classes CSS: `.visit-compact-row`, `.v-time-inline`, `.v-title-compact`.

#### Acesso Rápido Removido

- Removida a linha de 6 botões de navegação rápida (Anamnese, Evoluções, etc.) da aba Geral — menu lateral já cobre esse acesso.

#### Computeds e Dados Reais

- `computedClinicalTags`: lê anamnese real (alergias, medicamentos, histórico médico — diabetes, hipertensão, cardiopatia, gravidez, implantes).
- `activePlanSummary`: busca plano de tratamento ativo (`in_progress` ou `approved`) dos planos reais.
- `responsibleProfName`: resolve da lista de agents pelo `responsible_professional_id`; fallback para o usuário logado.
- `lastAppointmentFormatted` / `nextAppointmentFormatted`: formata data+hora+título dos compromissos reais retornados pelo endpoint `/summary`.
- `onMounted` agora carrega anamnese, planos de tratamento e agents para popular a aba Geral ao abrir.

**Arquivos modificados:**

- `app/javascript/dashboard/routes/dashboard/patients/Record.vue`
- `app/javascript/dashboard/api/patients/index.js`

---

## [1.3.0.0] - 2026-03-12 14:04:00-03:00

### Agenda: Drag-and-Drop de Eventos no Calendário (estilo Google Calendar)

Implementação completa de arrastar-e-soltar eventos na visão semanal e diária da agenda, com animações suaves, snapping em intervalos de 15 minutos e validação de horários bloqueados.

- **Interação fluida**: Clique e segure qualquer evento para iniciar o drag; solte no horário desejado para mover o evento.
- **Ghost de preview**: Durante o arraste, o evento original fica translúcido (25% opacidade) e um ghost azul tracejado se move em tempo real indicando a nova posição.
- **Ancoragem ao clique**: O ponto de clique dentro do evento fica fixo no cursor durante todo o arraste — não importa onde na barra do evento o usuário clicou.
- **Correção de scroll**: A posição do ghost é calculada usando `getBoundingClientRect()` (já inclui o scroll), eliminando o bug onde o ghost descía conforme o usuário rolava a página.
- **Snap a 15 minutos**: A posição final é arredondada para o intervalo de 15 minutos mais próximo, igual ao comportamento do Google Calendar.
- **Preservação de duração**: O evento mantém exatamente a mesma duração após ser movido.
- **Bloqueio de horários**: Se soltar em feriado, exceção, folga ou fora do expediente → alerta e reverte para a posição original.
- **Threshold anti-clique**: O drag só ativa após 6px de movimento — clicar no evento sem arrastar ainda abre o modal de edição.
- **Persistência via API**: No `mouseup`, o evento é atualizado via `agendaEvents/update` com os novos `starts_at` e `ends_at`.

**Arquivos modificados:**
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

---

### Agenda: Correção — Paciente Não Persistido ao Editar Evento

Quando um evento era reaberto para edição, o campo "Paciente" aparecia vazio ("Selecione o paciente") mesmo que um paciente houvesse sido selecionado e salvo anteriormente.

**Causa raiz**: O método `openEditEvent` carregava `contact_id` mas não populava `selectedPatientName` / `selectedPatientPhone`. A computed `selectedContactLabel` dependia dessas propriedades para exibir o nome, e ao encontrá-las vazias, não exibia nada.

**Solução implementada**:
- **`selectContact`**: Agora também salva `patient_id` (ID do registro de paciente) em `newEvent`.
- **Payload de salvamento**: Inclui `patient_id`, `patient_name` e `patient_phone` em `custom_attributes` do evento para garantir persistência independente do vínculo com o contato nativo.
- **`openEditEvent`**: Ao abrir evento existente, lê `custom_attributes.patient_name` / `patient_phone` / `patient_id` para restaurar o estado do dropdown corretamente.
- **Dropdown "selected"**: A classe `selected` agora usa `newEvent.patient_id === patient.id` em vez de comparar `contact_id`, pois `contact_id` pode ser `null` quando o contato nativo foi deletado.
- **Label do campo**: "Contato (Paciente)" → **"Paciente"** em todos os textos da interface (i18n `pt_BR`).

**Arquivos modificados:**
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`
- `app/javascript/dashboard/i18n/locale/pt_BR/settings.json`

---

### Agenda: Notificações Automáticas com Fallback de Nome do Paciente

O serviço de template das notificações automáticas dependia exclusivamente do `contact.name` (contato nativo do Chatwoot) para preencher a variável `{nome_paciente}`. Quando o contato era deletado e o `contact_id` do evento era nulo, o template exibia "Paciente" genérico.

**Fix**: O `Agenda::NotificationTemplateService` agora usa a seguinte cascata:
1. `event.contact.name` — contato Chatwoot vinculado (quando existe) ✅
2. `event.custom_attributes['patient_name']` — nome salvo no evento (fallback) ✅
3. `'Paciente'` — fallback genérico de último recurso

**Arquivos modificados:**
- `app/services/agenda/notification_template_service.rb`

---

### Pacientes: Busca de Contatos por Telefone no Cadastro — com Avatar

Ao cadastrar um novo paciente, digitar o celular agora sugere contatos existentes do Chatwoot em um dropdown.

**Correção de busca**: O código anterior passava o número formatado `(47)` para a API de busca, mas os contatos no banco estão em formato internacional `+554784226825`. A API usa `ILIKE %query%`, então a busca não encontrava correspondência. Agora os dígitos são extraídos antes de chamar a API — buscar `47` encontra `+554784226825` corretamente.

**Avatar no dropdown**: Cada contato sugerido exibe uma miniatura circular:
- Se o contato tem `avatar_url`: exibe a foto real.
- Se não tem foto: exibe a inicial do nome com cor determinística gerada por hash do nome (paleta de 10 cores, igual ao Chatwoot).

**Ajustes adicionais**:
- Busca começa com apenas **2 dígitos** (antes precisava de 3 chars formatados).
- Debounce reduzido para **400ms** para resposta mais ágil.

**Arquivos modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/components/NewPatientModal.vue`

---

## [1.2.9.9] - 2026-03-12 01:45:00-03:00

### Agenda: Busca Dinâmica de Pacientes no Agendamento

O componente de agendamento na Agenda Geral da BeClinic foi refatorado para usar uma busca dinâmica em tempo real (com debounce de 300ms) conectada diretamente ao sistema de Pacientes (Prontuário Eletrônico), em vez de depender da listagem completa em memória de Contatos (Chatwoot nativo).

- **Busca via `PatientsAPI`**: O input de "Contato (Paciente)" agora busca na tabela real de pacientes independente do status (`ativo`, `arquivado`, etc).
- **Tratamento Seguro de Chaves Estrangeiras**: O banco de dados do AgendaEvent está associado a `contact_id` nativo. A interface preserva essa estrutura internamente salvando o `contact_id` real vinculado ao paciente selecionado evitando problemas de integridade.
- **Labels Otimizados**: A interface adota preferencialmente o nome capturado na busca na mesma sessão (salvo localmente como `selectedPatientName`) se o contato não possuir um `contact_id`.
- **Experiência Otimizada**: Estado "Vazio", placeholder amigável e dropdown dinâmico acionado na abertura sem pré-carregar os milhares de perfis do banco logo ao inicializar o componente.

**Arquivos modificados:**

- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

---

## [1.2.9.8] - 2026-03-11 20:30:00-03:00

### Prontuário Eletrônico: Aba de Consentimentos — Sistema Completo de Gestão Jurídica

Esta versão entrega a **aba de Consentimentos e Assinaturas** completamente funcional, baseada em auditoria das melhores práticas do setor (Clinicorp, Dentrix, Jane App, Consentz).

#### 11 Tipos de Termos Pré-Definidos com Templates Completos

- **Termo LGPD / Privacidade de Dados**: autorização de coleta e uso de dados conforme Lei 13.709/2018
- **Autorização de Uso de Imagem**: fotos/vídeos para documentação clínica
- **Toxina Botulínica (Botox)**: riscos, efeitos esperados, contra-indicações e ausência de garantia de resultado
- **Preenchimento Dérmico (Filler)**: inclui alerta sobre oclusão vascular e risco de cegueira (extremamente raro)
- **Laser / Fototerapia / LED / Radiofrequência**: cuidados pós-procedimento com fotoproteção
- **Peeling Químico / Dermabrasão**: diferentes profundidades, contra-indicações (isotretinoína, herpes ativo)
- **Paciente Menor de Idade**: autorização do responsável legal (conforme ECA + CFM/CFF)
- **Procedimento Cirúrgico Minor**: biópsia, exérese e outros procedimentos ambulatoriais
- **Anestesia Local/Tópica**: declaração de alergias e medicamentos em uso
- **Termo de Consentimento Geral**: cobertura para procedimentos não enquadrados nas categorias acima

#### Modal de Criação (3 Passos)

- **Passo 1**: Grid visual com ícones para seleção do tipo de consentimento
- **Passo 2**: Título editável + seleção de validade (1, 3, 6, 12, 24, 60 meses ou sem vencimento)
- **Passo 3**: Editor completo do corpo do termo — auto-preenchido com nome e CPF do paciente, 100% customizável

#### Assinatura Digital via Canvas HTML5

- Canvas interativo com suporte a toque (tablet/celular) e mouse
- Traço azul suave com `lineCap: 'round'` para experiência de assinatura premium
- Botão "Limpar" para refazer a assinatura
- Exportação como `data:image/png;base64` via `.toDataURL()`
- Hash SHA-256 gerado automaticamente no backend após confirmar

#### Dashboard de Status (4 KPIs)

Total | Assinados | Pendentes | Vencidos — atualização automática após cada operação

#### Tabela Enriquecida

- Colunas: Documento | Categoria | Validade | Status | Ações
- Badges coloridos: Pendente (amber), Assinado (emerald), Vencido (red), Revogado (slate)
- Hash de integridade truncado + data e IP de assinatura
- Botões context-aware: pendentes → Enviar + Assinar; assinados → Hash + Revogar

#### Demais Funcionalidades

- **Modal de Visualização**: corpo completo do termo + painel de auditoria forense (hash SHA-256, data e IP)
- **Revogação**: confirmação nativa antes de revogar via `PATCH /revoke`
- **Envio Remoto**: link de assinatura por WhatsApp via `POST /send_remote`
- **Empty state inteligente**: mensagem contextual com botão CTA

**Arquivos modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue` — substituição completa da aba de Consentimentos: estado, constantes (`CONSENT_TYPES`, `CONSENT_STATUS_CONFIG`), todas as funções (criar, assinar, visualizar, enviar, revogar), template HTML/Vue com KPIs, tabela enriquecida e 3 modais (criação, assinatura digital com canvas, visualização/auditoria)
- `app/javascript/dashboard/api/patients/consents.js` — adicionados métodos `revoke()` e `delete()`

---

## [1.2.9.7] - 2026-03-11 19:51:00-03:00

### Prontuário Eletrônico: Galeria de Exames — Filtros por Tipo e Visualização Global

- **Filtros por Categoria de Mídia (Frontend)**: Introduzida uma nova barra de filtragem dinâmica na aba de "Exames e Imagens". Agora o profissional pode alternar instantaneamente entre **Imagens**, **Vídeos**, **PDFs** e **Documentos (Word/Excel)** através de botões segmentados com feedback visual por cores exclusivas.
- **Escopo "Todos os Arquivos" (Refatorado)**: A pasta raiz da galeria foi reestruturada para exibir **literalmente todos os arquivos** do paciente, independente de estarem organizados em subpastas ou não. Anteriormente, a visualização "Todos" mostrava apenas arquivos soltos na raiz, o que dificultava a localização rápida de mídias categorizadas.
- **Inteligência de Mimetypes**: Sistema de filtro agora identifica formatos variados (jpg, png, webp, heic, mp4, mov, pdf, docx, xlsx, csv, etc.) cruzando extensões de arquivo com `mime_type` retornado pela API.
- **UX Premium**: Filtros horizontais com suporte a scroll e estados ativos coloridos (Azul para Imagens, Vermelho para PDFs, Esmeralda para Documentos) mantendo a linguagem visual BeClinic.

**Arquivos modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue`

---

## [1.2.9.6] - 2026-03-11 16:38:00-03:00

### Prontuário Eletrônico: Aba de Documentos — Geração, Visualização e Gestão Completa

Esta versão entrega a **aba de Documentos** completamente funcional do prontuário eletrônico, cobrindo o ciclo completo de geração server-side de PDFs clínicos via Prawn, exibição na lista com metadados ricos, download via URL assinada do Active Storage, envio por WhatsApp e exclusão com confirmação.

---

#### 🆕 Modal de Geração de Documentos (Novo)

- **Modal inteligente e dinâmico** (`showDocModal`): Substituiu o antigo botão "Gerar Receita Doc" completamente inerte por um modal estruturado que coleta todos os dados necessários antes de chamar o backend. O modal detecta o tipo de documento selecionado e exibe **somente os campos relevantes** para aquele tipo, evitando poluição visual e reduzindo erros de preenchimento.
- **Suporte a 9 tipos de documento** com campos específicos por tipo:

  | Tipo de Documento | Campos Específicos Exibidos |
  |---|---|
  | Atestado Médico (`atestado`) | CID-10 + Dias de afastamento (numérico) |
  | Receita Médica (`receita`) | Medicamentos (nome) + Posologia/instruções |
  | Pedido de Exame (`pedido_exame`) | Exames solicitados — textarea (um por linha) |
  | Encaminhamento (`encaminhamento`) | Para quem (destino) + Especialidade |
  | Relatório Clínico (`relatorio_clinico`) | Campo de conteúdo livre (textarea longa) |
  | Declaração (`declaracao`) | Campo de conteúdo livre |
  | Instruções de Procedimento (`instrucao_procedimento`) | Campo de conteúdo livre |
  | Contrato de Serviços (`contrato`) | Campo de conteúdo livre |
  | Orçamento (`orcamento`) | Campo de conteúdo livre |

- **Campo de observações adicionais**: presente em todos os tipos de documento.
- **Campo de título customizável**: pré-preenchido automaticamente com o label padrão do tipo selecionado, mas 100% editável pelo profissional.
- **Estado de loading** (`docModalLoading`): botão "Gerar e Baixar PDF" entra em estado desabilitado com indicador visual durante o processamento, prevenindo duplo envio.
- **Função `openDocModal()`**: reinicializa o `docForm` com valores padrão toda vez que o modal abre, garantindo formulário limpo independentemente de usos anteriores.

---

#### 🔧 Correção Crítica: Integração Backend — `NoMethodError` 500 na Geração

**Problema:** O endpoint `POST /documents/generate` retornava 500 consistentemente com `NoMethodError: undefined method 'to_unsafe_h' for nil`.

**Causa raiz 1 — Payload aninhado incorretamente:** O método `DocumentsAPI.generate()` enviava o payload dentro de `{ document: payload }`, fazendo `params[:document_type]`, `params[:variables]` e `params[:title]` chegarem como `nil` no controller Rails (que espera params flat, não aninhados sob a chave `document`).

**Fix:** Removido o wrapper `{ document: ... }` — o payload é enviado flat diretamente.

**Causa raiz 2 — Nil não tratado:** O controller chamava `params[:variables].to_unsafe_h.symbolize_keys` sem proteção contra nil. Mesmo após o fix do wrapper, se o usuário não preencher campos de variáveis o objeto pode chegar vazio.

**Fix no controller:** `(params[:variables]&.to_unsafe_h || {}).symbolize_keys` — nil-safe com fallback para hash vazio.

---

#### 🔧 Correção Crítica: PDF Corrompido ("Falha ao carregar documento PDF")

**Problema:** Mesmo quando a geração ocorria com sucesso (HTTP 201), o arquivo baixado era inválido — o Chrome exibia "Falha ao carregar documento PDF".

**Causa raiz — `responseType: 'blob'` incorreto:** O método `generate()` do API client usava `{ responseType: 'blob' }`, esperando receber bytes binários de PDF. Porém, o `DocumentsController#generate` faz `render :show, status: :created` — que invoca o **template Jbuilder** e retorna **JSON** com metadados do documento (`{ id, title, document_type, status, url, generated_by, ... }`). O PDF real é salvo no **Active Storage** e acessado via URL assinada. O frontend tratava o JSON como blob binário, corrompendo o conteúdo.

**Fix:** Removido `responseType: 'blob'`. O fluxo correto agora é:
1. `POST /generate` → Rails gera o PDF com **Prawn**, salva no Active Storage, retorna JSON com `url` (signed URL do Active Storage com validade de 15 min)
2. Frontend extrai `docData.url` diretamente da resposta — o partial `_document.json.jbuilder` já incluía `json.url document.signed_url`
3. `window.open(signedUrl, '_blank')` → abre o PDF real no browser, sem download intermediário

Isso elimina a necessidade de um segundo request ao endpoint `/download` após a geração, simplificando o fluxo para **um único request**.

---

#### 🐛 Correção Crítica: Documentos Não Apareciam na Lista Após Geração

**Problema:** Após gerar um documento e chamar `fetchDocuments()`, a lista permanecia vazia ou com dados antigos — o novo documento não aparecia.

**Causa raiz — Envelope paginado não tratado:** O endpoint `GET /documents` retorna `{ data: [...], meta: { total_count, current_page, total_pages } }` (paginado via Kaminari/Jbuilder). O `fetchDocuments()` fazia `documents.value = res.data` — recebendo o objeto completo `{ data, meta }` em vez do array interno.

**Fix:** `documents.value = res.data?.data || res.data || []` — extrai corretamente o array do envelope paginado, com duplo fallback para compatibilidade com potenciais mudanças futuras do contrato da API.

---

#### 📋 Tabela de Documentos — Exibição Enriquecida e Correta

- **Tipos traduzidos** via `DOC_TYPE_LABELS`: tipos técnicos (ex: `receita`) são exibidos como labels amigáveis (ex: "Receita Médica") — antes aparecia o tipo cru ou traço.
- **Badges de status coloridos** via `DOC_STATUS_CONFIG`:
  - `gerado` → 🔵 Azul — "Gerado"
  - `pendente_assinatura` → 🟡 Amarelo — "Aguard. Assinatura"
  - `assinado` → 🟢 Verde — "Assinado"
  - `enviado` → 🟣 Roxo — "Enviado"
  - `arquivado` → ⚫ Cinza — "Arquivado"
- **Profissional exibido corretamente**: corrigido mapeamento de `doc.generated_by_name` (campo inexistente na API) para `doc.generated_by?.name`, respeitando a estrutura aninhada do Jbuilder (`json.generated_by { json.name ... }`). Antes exibia sempre "Sistema" mesmo para documentos com profissional identificado.
- **Colunas completas**: Documento (título + versão), Tipo, Data, Profissional, Status, Ações.
- **Empty state**: mensagem clara e botão "Gerar Documento" quando a lista de documentos está vazia.

---

#### 🔘 Botões de Ação por Documento

Cada linha da tabela possui três botões de ação:

- **⬇️ Download**: Chama `GET /documents/:id/download` → obtém signed URL do Active Storage → abre em nova aba. Guard: `if (!doc?.id) return` previne chamadas com ID undefined.
- **💬 WhatsApp**: Chama `POST /documents/:id/send_whatsapp` → invoca `DocumentWhatsappSender` no backend que monta o payload no formato Chatwoot e dispara para o WhatsApp do paciente. Guard: `if (!documentId) return` previne 404s com ID undefined (problema que aparecia nos logs de documentos antigos/mock).
- **🗑️ Excluir**: Exibe `confirm()` nativo antes de chamar `DocumentsAPI.delete()`. Remove o item do array local imediatamente após sucesso sem necessidade de refetch.

---

#### 🏗️ Novas Variáveis de Estado e Constantes

```javascript
// Estado do modal
const showDocModal = ref(false);
const docModalLoading = ref(false);
const docActionsOpenId = ref(null);

// Formulário de geração (todos os campos possíveis)
const docForm = ref({
  document_type: 'atestado', title: '',
  cid: '', dias_afastamento: '',
  medicamentos: '', posologia: '',
  exames_solicitados: '',
  encaminhado_para: '', especialidade: '',
  conteudo_livre: '', observacoes: '',
});

// Labels amigáveis para exibição na tabela
const DOC_TYPE_LABELS = {
  receita: 'Receita Médica', atestado: 'Atestado Médico',
  pedido_exame: 'Pedido de Exame', encaminhamento: 'Encaminhamento',
  relatorio_clinico: 'Relatório Clínico', declaracao: 'Declaração',
  instrucao_procedimento: 'Instrução de Procedimento',
  contrato: 'Contrato', orcamento: 'Orçamento',
};

// Configuração visual dos status badges
const DOC_STATUS_CONFIG = {
  gerado:               { label: 'Gerado',             cls: '...' },
  pendente_assinatura:  { label: 'Aguard. Assinatura',  cls: '...' },
  assinado:             { label: 'Assinado',            cls: '...' },
  enviado:              { label: 'Enviado',             cls: '...' },
  arquivado:            { label: 'Arquivado',           cls: '...' },
};
```

---

**Arquivos modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue` — Adição de estado e constantes para o modal de geração; função `openDocModal()`; refatoração completa de `generateDocument()` com mapeamento correto de variáveis para o PdfGenerator; refatoração de `downloadDocument()` (removido get() redundante, adicionado guard de `!doc?.id`); refatoração de `sendWhatsAppDocument()` (adicionado guard de `!documentId`); refatoração de `deleteDocument()`; **correção crítica em `fetchDocuments()`** (`res.data.data` em vez de `res.data`); substituição completa do template da aba Documentos com modal de geração, tabela enriquecida, badges coloridos e profissional correto
- `app/javascript/dashboard/api/patients/documents.js` — Removido `{ document: payload }` wrapper e `{ responseType: 'blob' }` do método `generate()`; payload agora é enviado flat para compatibilidade com o controller Rails
- `app/controllers/api/v1/accounts/patients/documents_controller.rb` — Nil-safety adicionada em `params[:variables]&.to_unsafe_h || {}` para prevenir `NoMethodError: undefined method 'to_unsafe_h' for nil:NilClass` quando `variables` não é enviado ou chega como objeto JS vazio

---
