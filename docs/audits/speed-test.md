# Auditoria de Performance — Klivy

> Data: 2026-05-29 · Sintoma investigado: **login médio ~20s, constante desde o deploy**
> Servidor: 1 host **4 vCPU / 8 GB / 80 GB SSD** rodando 3 serviços (Postgres + Klivy + Redis) via EasyPanel
> Método: medição ao vivo no servidor (cgroup + waterfall do navegador) + auditoria multiagente do código (7 dimensões, 25 agentes, verificação adversarial)

---

## 🎯 Veredito (TL;DR)

**O problema NÃO é o servidor. É o frontend.**

As métricas ao vivo provam que a máquina está **ociosa e folgada** — e o Rails responde em **2,5 ms**. Os ~20s acontecem **no navegador**, baixando **~13 MB de JavaScript/CSS não comprimido** na tela de login, dominados por **um único chunk de 10,5 MB** que nem deveria estar ali.

| Causa | É a causa dos 20s? | Esforço do fix |
|---|---|---|
| **Chunk JS de 10,5 MB carregado no login** (sem code-splitting) | ✅ **SIM — principal** | Médio |
| **Assets servidos sem compressão** (gzip/brotli) | ✅ **SIM** | Baixo |
| **Sem CDN + Puma servindo tudo + 1 worker só** | ✅ **SIM** | Baixo/Médio |
| **Login carrega o app inteiro** (40 idiomas, Twilio, Sentry, store) | ✅ contribui | Médio |
| ~33 round-trips Redis seriais no render | ⚠️ contribui pouco | Médio |
| Postgres com defaults / jemalloc / YJIT / separar processos | ❌ **não** (otimização) | Vários |
| Contenção de CPU/RAM, swap, OOM | ❌ **refutado pela medição** | — |
| APM, R2/storage, Rack::Attack | ❌ **descartado com evidência** | — |

**Importante:** as variáveis que você colocou no `.env` (`WEB_CONCURRENCY=2`, `RAILS_MAX_THREADS=5`, `SIDEKIQ_CONCURRENCY=5`) **nunca chegaram ao servidor** — o container não lê o `.env` do repo (o EasyPanel injeta env pela aba própria). Por isso o Puma roda em **modo single (1 processo)** e você viu "não usa 100% dos cores".

---

## 🔬 As evidências

### 1. Métricas do servidor (medidas dentro do container `klivy`)

| Métrica | Valor medido | Leitura |
|---|---|---|
| CPUs visíveis (`nproc`) | 4 | vê os 4 núcleos |
| Limite de CPU (`cpu.max`) | **`max`** | **sem limite** |
| CPU throttling (`nr_throttled`) | **0** | **zero estrangulamento** |
| Limite de RAM (`memory.max`) | **`max`** | **sem limite** |
| RAM usada pelo container | ~1,73 GB | folgado |
| RAM livre no host | 4,0 GB | sobra |
| Load average | **0.04 / 0.09 / 0.08** | **máquina parada** |
| Disco | 29% (21/75 GB) | tranquilo |
| **TTFB do Rails (localhost)** | **2,5 ms** (`http=301`) | **backend voando** |
| `printenv WEB_CONCURRENCY` | *(vazio)* | env do `.env` **não aplicada** |

➡️ **Conclusão:** sem limite de CPU/RAM, sem throttle, sem swap, load ~zero e backend em 2,5 ms. **Não há contenção de recurso.** A lentidão é de **entrega/tamanho de payload**, não de capacidade.

### 2. Waterfall do navegador na tela de login (Chrome, Disable cache)

| Arquivo | Tamanho | Tempo |
|---|---|---|
| `login` (HTML) | 10,6 kB | 493 ms |
| `v3app-*.js` | 264 kB | 1,36 s |
| `v3app-*.css` | **1.154 kB** | 4,11 s |
| `_plugin-vue_export-helper-*.js` | 172 kB | 3,37 s |
| **`DashboardIcon-*.js`** | **10.600 kB** 🚨 | **6,36 s** |
| `Validators` / `utils.esm` / `index-*` (×10) | 85–176 kB cada | ~3 s cada |

➡️ **~13 MB de JS/CSS up-front**, sem compressão, servidos por um Puma de **1 worker** sobre poucas conexões → serializa → ~20s.

### 3. Waterfall pós-login (dashboard) — **prova definitiva de compressão ZERO**

Carregamento completo após autenticar:

| Métrica | Valor |
|---|---|
| Requests | **98** |
| **Transferred** | **23,7 MB** |
| **Resources** | **23,7 MB** |
| DOMContentLoaded | 6,11 s |
| Load | 6,13 s |
| **Finish** | **12,30 s** |
| `DashboardIcon-*.js` (de novo!) | **10.600 kB** / 4,82 s |

➡️ **`Transferred` == `Resources` (23,7 MB = 23,7 MB).** Com gzip/brotli ligado, o "transferred" (bytes comprimidos na rede) seria **3–5× menor** que o "resources" (tamanho real). Serem **idênticos** é prova matemática de que **nada está sendo comprimido** — confirma a Causa-raiz #2 sem margem de dúvida.

➡️ O chunk `DashboardIcon` de **10,6 MB** aparece **também aqui** — ele pesa tanto no login quanto no dashboard. Sozinho é ~45% dos 23,7 MB.

➡️ Observações menores no boot: `GET .../limits` retorna **404** (`account.js:18`) e `sdk.js` é bloqueado por ORB — ruído, não causam lentidão, mas valem uma limpada.

---

## 🔴 Causa-raiz #1 — Chunk "catch-all" de 10,5 MB no login

**O que é:** o entrypoint do login ([app/javascript/entrypoints/v3app.js](app/javascript/entrypoints/v3app.js)) importa estaticamente um componente de ícones global, e o Rollup, **sem nenhuma estratégia de chunking**, despeja num único arquivo `DashboardIcon-*.js` (10,5 MB) coisas que o login nunca usa: **`@twilio/voice-sdk`** (telefonia), **`@sentry/*`** e **a store inteira do dashboard**.

> ⚠️ Correção de um mito: os ícones (`dashboard-icons.json`) são só **114 KB**. O peso de 10,5 MB **não são os ícones** — é o vendor `@twilio/voice-sdk` + Sentry + store que caíram nesse chunk porque **não existe `manualChunks` no `vite.config.ts`**. Logo, "lazy-load só dos ícones" **não resolve**.

**Evidência:**
- [vite.config.ts](vite.config.ts) → `build.rollupOptions.output` **não define `manualChunks`** (só mexe em `inlineDynamicImports`/`lib` no modo SDK).
- [app/javascript/entrypoints/v3app.js:13](app/javascript/entrypoints/v3app.js#L13) `import FluentIcon from 'shared/components/FluentIcon/DashboardIcon.vue'` + linha 34 `app.component('fluent-icon', FluentIcon)` (registro global).
- [app/javascript/shared/components/FluentIcon/DashboardIcon.vue:3](app/javascript/shared/components/FluentIcon/DashboardIcon.vue#L3) `import icons from './dashboard-icons.json'` (estático).
- Build local: `public/vite/assets/DashboardIcon-*.js` = **10.552.736 bytes**.

**Correção (em ordem de impacto):**

1. **Definir `manualChunks` no [vite.config.ts](vite.config.ts)** para quebrar o catch-all e isolar vendors pesados:
   ```ts
   build: {
     sourcemap: false, // não publicar .js.map de 2,5 MB em prod
     rollupOptions: {
       output: {
         // ...config existente (isLibraryMode etc.)...
         manualChunks(id) {
           if (id.includes('@twilio/voice-sdk')) return 'twilio';
           if (id.includes('@sentry')) return 'sentry';
           if (id.includes('/i18n/locale/')) {
             const m = id.match(/i18n\/locale\/([^/]+)/);
             return m ? `locale-${m[1]}` : 'locale-misc';
           }
         },
       },
     },
   },
   ```
2. **Garantir que `@twilio/voice-sdk` seja import dinâmico** (`import()` / `defineAsyncComponent`) no ponto onde a telefonia é usada — ele **nunca** deve estar no grafo estático do login.
3. **Não registrar `FluentIcon` globalmente no `v3app`** se o login usa poucos ícones (registrar só no entrypoint `dashboard`).
4. **Validar:** `bin/vite build` e conferir no `public/vite/.vite/manifest.json` que o maior chunk do `v3app` caiu para a casa de **centenas de KB** e que `@twilio/voice-sdk` saiu do grafo up-front.

---

## 🔴 Causa-raiz #2 — Assets servidos **sem compressão**

**O que é:** não há `Rack::Deflater`, não há `.gz`/`.br` pré-gerados, não há brotli num proxy. O Puma (`ActionDispatch::Static`) entrega os bytes **crus**. Os 10,5 MB virariam **~2,8 MB com gzip** (3,7× menos).

**Evidência:**
- [config/environments/production.rb:23](config/environments/production.rb#L23) `public_file_server.enabled` = `RAILS_SERVE_STATIC_FILES` (true) — e o Static **não comprime**.
- Zero ocorrências de `Rack::Deflater`/`Rack::Brotli` em `config/`; `public/vite/assets/*.gz` e `*.br` = **0 arquivos**.

**Correção (1 linha, alto retorno):**

1. **Imediato** — em [config/environments/production.rb](config/environments/production.rb), no bloco de config:
   ```ruby
   config.middleware.use Rack::Deflater
   ```
   (já vem com o Rails; comprime HTML/JSON **e** os estáticos do Static). Derruba 10,5 MB → ~2,8 MB on-the-fly.
2. **Melhor** — pré-comprimir no build com `vite-plugin-compression2` (gera `.br`/`.gz`) **e** servir via proxy/Cloudflare com `brotli_static`/`gzip_static` (comprime 1× e cacheia, sem CPU no Puma a cada request).

---

## 🔴 Causa-raiz #3 — Sem CDN + Puma single servindo todos os assets

**O que é:** `ASSET_CDN_HOST` está **vazio** e `RAILS_SERVE_STATIC_FILES=true`, então **o próprio Puma serve cada chunk**. Pior: como `WEB_CONCURRENCY` não foi aplicada no servidor, o Puma roda em **modo single (1 worker, 5 threads)** — cada chunk ocupa uma thread, e o navegador ainda limita ~6 conexões por host (HTTP/1.1) → tudo serializa.

**Evidência:**
- [config/puma.rb:28](config/puma.rb#L28) `workers ENV.fetch('WEB_CONCURRENCY', 0)` → sem a env, **0 workers = single mode**.
- `printenv` no container: `WEB_CONCURRENCY`/`RAILS_MAX_THREADS`/`SIDEKIQ_CONCURRENCY` **vazias** (o `.env` do repo não é lido pelo container).
- [config/environments/production.rb:37](config/environments/production.rb#L37) só usa `asset_host` se `ASSET_CDN_HOST` existir — hoje não existe.

**Correção:**

1. **Aplicar as env vars no lugar certo** — na aba **Environment do EasyPanel** (não no `.env`!):
   - `WEB_CONCURRENCY=3` (host tem 4 vCPU ociosos; deixa 1 pro resto) → resolve o "não usa 100% dos cores"
   - `RAILS_MAX_THREADS=5`
   - `SIDEKIQ_CONCURRENCY=3`
2. **Pôr a Cloudflare na frente** (proxy laranja) **ou** um nginx servindo `/vite/` e `/packs/` com cache imutável. Depois pode setar `RAILS_SERVE_STATIC_FILES=false` e tirar 100% dos assets do Puma.
3. Acrescentar `immutable` ao Cache-Control em [config/environments/production.rb:24-26](config/environments/production.rb#L24-L26): `'public, max-age=31536000, immutable'` (os assets já têm fingerprint).

---

## 🟠 Causa-raiz #4 — Login carrega o app inteiro (não é enxuto)

[app/javascript/entrypoints/v3app.js:4](app/javascript/entrypoints/v3app.js#L4) faz `import i18nMessages from 'dashboard/i18n'`, que importa **~40 locales** estaticamente — a clínica usa 1. Some-se Sentry + Twilio + store. O CSS do `v3app` sozinho já é **1,13 MB**.

**Correção:** carregar **só `en` + o locale do usuário** (`window.chatwootConfig.selectedLocale`, já exposto em [vueapp.html.erb](app/views/layouts/vueapp.html.erb)) via `import()` dinâmico antes do `mount`, e combinar com o `manualChunks` por locale do #1.

---

## 🟡 Backend — contribui um pouco (corrigir depois do frontend)

### B1. ~33 round-trips Redis **seriais** por render da SPA
[app/controllers/dashboard_controller.rb:30](app/controllers/dashboard_controller.rb#L30) (`set_global_config`) + [lib/global_config.rb:11-13](lib/global_config.rb#L11-L13) fazem **um `GET` Redis por chave, em loop, sem pipeline** (~33 GETs por carregamento, inclusive no login). Redis é local (~1ms cada), então é ~33ms — não é o vilão dos 20s, mas é desperdício fácil de eliminar.
**Fix:** reescrever `GlobalConfig.get` para um único `pipelined` (→ 1 round-trip). Snippet completo no apêndice.

### B2. `FRONTEND_URL` pode estar como `0.0.0.0:3000`
No `.env` está `FRONTEND_URL=http://0.0.0.0:3000`. Se esse valor estiver no servidor, [dashboard_controller.rb:34](app/controllers/dashboard_controller.rb#L34) (`render_hc_if_custom_domain`) faz um `Portal.find_by(custom_domain:)` **em todo render** (o host real nunca bate `0.0.0.0`), e os redirects/url_options de auth ficam errados.
**Fix:** setar `FRONTEND_URL=https://<seu-domínio-real>` no EasyPanel. **Verifique:** `docker exec klivy printenv FRONTEND_URL`.

### B3. N+1 de `klivy_role` no `/agents` (pós-login)
[app/controllers/api/v1/accounts/agents_controller.rb:102](app/controllers/api/v1/accounts/agents_controller.rb#L102) não faz preload de `klivy_role` → 1 query por agente.
**Fix:** `.includes({ account_users: :klivy_role }, { avatar_attachment: [:blob] })`.

### B4. Log em INFO a cada request autenticada
[app/controllers/application_controller.rb:33](app/controllers/application_controller.rb#L33) loga `[ensure_session_cookie]` em INFO e reescreve o cookie em toda response. **Fix:** baixar para `debug`.

---

## ⚪ Otimizações secundárias — **boas práticas, mas NÃO resolvem os 20s**

> Faça depois. A medição ao vivo mostra que nenhuma delas é o gargalo atual (CPU ociosa, sem swap, sem throttle). São robustez/economia.

| Item | Por que vale | Onde |
|---|---|---|
| **Postgres com defaults** (shared_buffers 128MB) | tunar p/ host de 8GB compartilhado | `docker-compose`/painel: `-c shared_buffers=512MB -c effective_cache_size=2GB -c work_mem=8MB -c max_connections=50`, `shm_size: 512m` |
| **jemalloc + `MALLOC_ARENA_MAX=2` em runtime** | reduz RSS do Ruby (hoje só existe no build) | Dockerfile stage final: `ENV MALLOC_ARENA_MAX=2` + `libjemalloc2` |
| **YJIT desligado** (Ruby 3.4) | -15–30% CPU/request, de graça | `ENV RUBY_YJIT_ENABLE=1` |
| **Separar processos** (Puma+Sidekiq+Node no mesmo container) | isolamento (não há contenção hoje, mas é arquitetura correta) | 3 serviços no EasyPanel a partir da mesma imagem |
| **bootsnap apagado no build** (`rm tmp/cache`) | boot/restart mais frio | não apagar `tmp/cache/bootsnap` no [Dockerfile](Dockerfile) |
| **Redis único sem `maxmemory`** | evitar rejeição de escrita sob pressão | `maxmemory` + policy no serviço redis |
| **`gem 'hiredis-client'`** ausente | parsing Redis em C (menos CPU) | Gemfile |
| **Cron IMAP a cada 1min** | se não usa IMAP, desligar | [config/schedule.yml](config/schedule.yml) |
| **Variante de imagem inline** (`thumb_url`) | 1ª abertura de conversa com mídia trava | fixar `config.active_storage.variant_processor = :vips` + pré-gerar |
| **Logs Docker json-file sem limite** | risco de encher disco | `max-size=10m, max-file=3` no painel |

---

## ✅ O que foi **descartado** (com evidência)

- **Contenção de CPU / swap / OOM / limite apertado** → refutado: `cpu.max=max`, `nr_throttled=0`, `memory.max=max`, 4 GB livres, load 0.04.
- **Modo dev em produção** → `RAILS_ENV=production` confirmado; `eager_load`/`cache_classes` corretos.
- **APM (NewRelic/Datadog/Scout/Sentry/Elastic)** → todos *require-gated* por ENV ausentes; **nenhum agente ativo**.
- **R2/ActiveStorage** → modo **redirect** (não proxy); o login **não toca o R2**; avatares são eager-loaded (sem N+1).
- **Rack::Attack como gargalo** → estáticos nem chegam nele; throttle é ~1 comando Redis barato.

---

## 🗺️ Plano de ação (na ordem)

| Fase | Ação | Impacto esperado no login | Esforço |
|---|---|---|---|
| **0** | Env vars no **EasyPanel** (`WEB_CONCURRENCY=3`, `SIDEKIQ_CONCURRENCY=3`) + corrigir `FRONTEND_URL` | usa os 4 cores; tira query por render | 5 min |
| **1** | **Compressão** (`Rack::Deflater` ou vite-plugin-compression + brotli) | **~20s → ~6–8s** | Baixo |
| **2** | **`manualChunks`** + Twilio/Sentry dinâmicos + i18n por locale | **→ ~2–4s** | Médio |
| **3** | **Cloudflare/CDN** na frente de `/vite` `/packs` + `immutable`; depois `RAILS_SERVE_STATIC_FILES=false` | repeat-load quase instantâneo | Médio |
| **4** | Backend: pipeline dos 33 GETs Redis, N+1 `klivy_role`, log→debug | -100ms a -1s server-side | Médio |
| **5** | Secundárias (Postgres, jemalloc, YJIT, separar processos, etc.) | robustez/economia | Vários |

### Como validar cada fase
- **Rede:** `curl -s -o /dev/null -w '%{size_download} %{time_total}\n' -H 'Accept-Encoding: br,gzip' https://<dominio>/vite/assets/<chunk>.js` → o tamanho transferido deve cair ~3–4×.
- **Bundle:** após `bin/vite build`, conferir no `public/vite/.vite/manifest.json` que o maior chunk do `v3app` está abaixo de ~2 MB e sem `@twilio`.
- **Navegador:** repetir a waterfall (Disable cache) — "Finish" deve despencar.
- **Servidor (regra de ouro):** se após a Fase 1+2 o login não cair, **não era o que você achava** — mas a evidência aqui é forte de que cai.

---

## 📎 Apêndice — snippet do pipeline do GlobalConfig (B1)

```ruby
# lib/global_config.rb — substituir o loop de GETs por 1 round-trip
def get(*args)
  config_keys = args.flatten
  cache_keys  = config_keys.map { |k| "#{VERSION}:#{KEY_PREFIX}:#{k}" }
  cached = $alfred.with { |conn| conn.pipelined { |p| cache_keys.each { |ck| p.get(ck) } } }
  config = {}
  config_keys.each_with_index do |config_key, i|
    raw = cached[i]
    if raw.blank?
      raw = { value: db_fallback(config_key) }.to_json
      $alfred.with { |conn| conn.set(cache_keys[i], raw, ex: DEFAULT_EXPIRY) }
    end
    config[config_key] = JSON.parse(raw)['value']
  end
  typecast_config(config)
  config.with_indifferent_access
end
```

---

*Auditoria gerada com workflow multiagente (7 dimensões · verificação adversarial) cruzado com medições ao vivo do servidor. Onde o código estático sugeria "contenção de CPU", a medição mandou: o gargalo é entrega de assets, não capacidade.*
