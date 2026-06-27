# Self-Service Meta Apps Per-Account — Implementation Plan

> **Status:** Proposta arquitetural (não implementada)
> **Autor:** Auditoria + plano técnico — 2026-05-26
> **Escopo:** Habilitar cada `Account` a configurar sua própria App Meta (Facebook + Messenger + Instagram) sem depender do `super_admin`, com isolamento real multi-tenant e zero regressão para instalações atuais.
> **Modelo confirmado:** Coexistência com fallback global (`CredentialResolver`) — Account com `BeclinicMetaApp` própria usa a app dela; Account sem MetaApp cai no `InstallationConfig` global do super_admin.

---

## Índice

1. [Contexto e Objetivo](#1-contexto-e-objetivo)
2. [Como Funciona Hoje](#2-como-funciona-hoje-config-global-do-super_admin)
3. [Modelo de Coexistência (decisão arquitetural)](#3-modelo-de-coexistência-decisão-arquitetural)
4. [Auditoria Arquitetural Completa](#4-auditoria-arquitetural-completa)
5. [Diagnóstico dos Problemas Atuais](#5-diagnóstico-dos-problemas-atuais)
6. [Riscos Encontrados](#6-riscos-encontrados)
7. [Arquitetura Proposta](#7-arquitetura-proposta)
8. [Modelo de Dados](#8-modelo-de-dados)
9. [Estrutura do Plugin `social_channels`](#9-estrutura-do-plugin-social_channels)
10. [Fluxo Backend Completo](#10-fluxo-backend-completo)
11. [Fluxo Frontend Completo](#11-fluxo-frontend-completo)
12. [Estratégia Multi-Tenant](#12-estratégia-multi-tenant)
13. [Estratégia de Webhook](#13-estratégia-de-webhook)
14. [Estratégia RBAC](#14-estratégia-rbac)
15. [Plano de Implementação por Fase](#15-plano-de-implementação-por-fase)
16. [Estratégia Anti-Regressão](#16-estratégia-anti-regressão)
17. [Plano de Testes](#17-plano-de-testes)
18. [Checklist de Produção](#18-checklist-de-produção)
19. [Anexos](#19-anexos)

---

## 1. Contexto e Objetivo

### 1.1 Contexto

Klivy roda sobre uma base Chatwoot altamente customizada com arquitetura modular baseada em Rails Engines (`plugins/*`). O produto é multi-tenant: cada clínica = uma `Account`. Praticamente todo modelo, endpoint, blob e cache de frontend é (ou deveria ser) scoped por `account_id` ([AGENTS.md](../../AGENTS.md) seção "Multi-tenancy").

Chatwoot já suporta nativamente os canais Facebook Messenger, Instagram Direct e Facebook Page com Instagram vinculado. Porém **toda configuração de App Meta (App ID, App Secret, Verify Token) é global**, configurada em `/super_admin/app_config?config=facebook|instagram` e armazenada em `InstallationConfig`. Todas as N clínicas dividem **a mesma App Meta**.

### 1.2 Objetivo

Cada `Account` deve poder:

- Configurar sua própria App Meta (App ID + App Secret + Verify Token + API Version) sem intervenção do super_admin
- Conectar Facebook Pages, Messenger e Instagram Business usando suas credenciais
- Ter consent screen com nome da clínica (não "Klivy")
- Ter rate limit, suspensão e auditoria Meta isolados
- Continuar funcionando se não configurar nada (fallback global compatível com hoje)

### 1.3 Requisitos não-funcionais

| Requisito | Como atende |
|---|---|
| Multi-tenant real (sem vazamento cross-account) | Toda query/policy/cache scoped por `account_id`; webhook resolve via `page_id → Channel → Account → MetaApp` |
| Segurança | `app_secret` e `verify_token` criptografados (Active Record Encryption); serializer nunca expõe `app_secret`; signature timing-safe |
| Sem regressão | Fallback para `InstallationConfig` global preserva comportamento de instalações atuais |
| Compat Chatwoot | Sem fork de gem `facebook-messenger`; usa hooks `to_prepare` para substituir provider |
| Escalável SaaS | Lookup webhook O(1) via índice unique determinístico em `verify_token` |
| Modular | 100% do código novo em `plugins/social_channels/`; 2 micro-overrides via `prepend_mod_with` |
| RBAC | Perms novas `settings.meta_apps_view/manage` no catálogo Klivy |

---

## 2. Como Funciona Hoje (config global do super_admin)

### 2.1 Caminho técnico

1. Super_admin abre `/super_admin/app_config?config=facebook` e salva `FB_APP_ID`/`FB_APP_SECRET`/`FB_VERIFY_TOKEN`.
2. `SuperAdmin::AppConfigsController#create` faz upsert em `InstallationConfig` ([app/controllers/super_admin/app_configs_controller.rb:17-31](../../app/controllers/super_admin/app_configs_controller.rb#L17-L31)) e dispara `after_commit :clear_cache` que invalida Redis (`V1:GLOBAL_CONFIG:*`).
3. Quando QUALQUER usuário de QUALQUER Account abre o dashboard, `DashboardController#app_config` lê `GlobalConfigService.load('FB_APP_ID', '')` e injeta no HTML servido como `window.chatwootConfig.fbAppId` ([app/controllers/dashboard_controller.rb:74-77](../../app/controllers/dashboard_controller.rb#L74-L77), [app/views/layouts/vueapp.html.erb:38](../../app/views/layouts/vueapp.html.erb#L38)).
4. `ChannelItem.vue` ativa o card Facebook quando `window.chatwootConfig?.fbAppId` está presente ([app/javascript/dashboard/components/widgets/ChannelItem.vue:18-49](../../app/javascript/dashboard/components/widgets/ChannelItem.vue#L18-L49)).
5. Clínica clica "Conectar Facebook" → `Facebook.vue` chama `FB.init({ appId: window.chatwootConfig.fbAppId, ... })` com a app do super_admin.
6. OAuth flow termina em `CallbacksController#register_facebook_page` que persiste tokens per-channel mas usa `GlobalConfigService.load('FB_APP_ID', 'FB_APP_SECRET')` para long-lived exchange ([app/controllers/api/v1/accounts/callbacks_controller.rb:96-101](../../app/controllers/api/v1/accounts/callbacks_controller.rb#L96-L101)).
7. Webhooks chegam em `/bot` (gem `facebook-messenger`), validados contra `FB_APP_SECRET` global pelo `ChatwootFbProvider` ([config/initializers/facebook_messenger.rb:1-20](../../config/initializers/facebook_messenger.rb#L1-L20)).

### 2.2 Conclusão da precedência atual

| Aspecto | Estado atual |
|---|---|
| Quem habilita o card Facebook/Instagram | Super_admin no painel global → vale pra TODAS as Accounts |
| Quem aparece no consent Meta | "Klivy" (app do super_admin) — não o nome da clínica |
| Dono da relação Meta-Developer | Klivy (super_admin) — clínica não precisa ter conta Meta Developer |
| Rate limit Meta | Compartilhado entre todas as clínicas (1 bucket único) |
| Se Meta suspende a app | Todas as N clínicas perdem integração simultaneamente |
| Tokens de page/IG | Per-channel (não é problema arquitetural) |
| App Secret / Verify Token / App ID | Único globalmente — vazamento afeta todas |
| Self-service real | Inexistente — clínica não controla nada da app Meta |

**Em uma frase:** "Multi-tenant na superfície, single-tenant na infraestrutura Meta."

---

## 3. Modelo de Coexistência (decisão arquitetural)

### 3.1 Princípio

Toda leitura de credencial Meta passa por um único service `SocialChannels::CredentialResolver`. Ele aplica precedência:

```
resolve(account, provider) =
  BeclinicMetaApp.for(account, provider: provider)  # 1º: app da própria Account
  || InstallationConfig (global do super_admin)     # 2º: fallback compatível com hoje
```

### 3.2 Matriz de comportamento

| Account configurou MetaApp? | Super_admin configurou global? | O que acontece |
|---|---|---|
| Sim | Sim | Account usa app própria (per-account). Global é ignorado pra essa Account. |
| Sim | Não | Account usa app própria. |
| Não | Sim | Account usa app global do super_admin (= comportamento de hoje). |
| Não | Não | Cards FB/IG ficam desabilitados (= comportamento de hoje quando super_admin não configurou). |

### 3.3 Implicações por persona

| Persona | Pode fazer | Como |
|---|---|---|
| `super_admin` Klivy | Configurar app global "padrão Klivy" (modo trial ou fallback permanente) | `/super_admin/app_config?config=facebook|instagram` (mantido como está) |
| `administrator` da clínica | Configurar app própria da clínica | `/app/accounts/:id/settings/integrations/meta-apps` (novo) |
| User com `settings.meta_apps_view` | Ver status das apps configuradas (sem expor `app_secret`) | Mesma página, modo read-only |
| User sem perm | Não vê página; mas pode criar Inbox FB/IG se gate de Inbox permitir e a Account tem app configurada (global ou própria) | — |

### 3.4 Variações rejeitadas

| Modelo | Por que rejeitado |
|---|---|
| Per-account obrigatório (sem fallback) | Quebra clínicas que dependem da app global hoje; exige migração big-bang; viola requisito "Sem regressão" |
| Híbrido com toggle de expiração de fallback | Complexidade adicional não justificada na MVP; pode ser adicionado depois (Fase 8+) sem refatoração estrutural |
| URL de webhook per-tenant (`/webhooks/social/facebook/:account_id`) | Funciona porém duplica entropia (cada clínica já tem app própria com URL própria configurada por ela); URL fixa por instalação reduz superfície de erro de digitação no painel Meta |

---

## 4. Auditoria Arquitetural Completa

### 4.1 Estado atual da integração Meta

| Camada | Arquivo | Multi-tenant? |
|---|---|---|
| Channel FB model | [app/models/channel/facebook_page.rb:20-68](../../app/models/channel/facebook_page.rb#L20-L68) | Sim (per-channel) |
| Channel IG Direct model | [app/models/channel/instagram.rb](../../app/models/channel/instagram.rb) | Parcial (`instagram_id` UNIQUE global) |
| OAuth FB entry | [app/controllers/api/v1/accounts/callbacks_controller.rb:96-101](../../app/controllers/api/v1/accounts/callbacks_controller.rb#L96-L101) | Não (app global) |
| OAuth IG entry | [app/controllers/concerns/instagram_concern.rb:20-26](../../app/controllers/concerns/instagram_concern.rb#L20-L26) | Não (app global) |
| Webhook FB (gem) | [config/initializers/facebook_messenger.rb:1-20](../../config/initializers/facebook_messenger.rb#L1-L20) | Não (verify+secret globais) |
| Webhook IG | `app/controllers/webhooks/instagram_controller.rb:39-40` | Não (verify global) |
| Page→Token lookup | [config/initializers/facebook_messenger.rb:11-13](../../config/initializers/facebook_messenger.rb#L11-L13) | **Bug:** `.last` sem `account_id` |
| Frontend gate cards | [app/javascript/dashboard/components/widgets/ChannelItem.vue:18-49](../../app/javascript/dashboard/components/widgets/ChannelItem.vue#L18-L49) | Não (lê global do dashboard) |
| FB SDK init | `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Facebook.vue:124-129` | Não (app global) |
| Super_admin panel | `app/controllers/super_admin/app_configs_controller.rb:42-48` | Único pro tenant inteiro |

### 4.2 Pontos de leitura de config global (centralização-alvo)

| Config | Arquivo:linha | Uso |
|---|---|---|
| `FB_APP_ID` | `dashboard_controller.rb:74` | Frontend init |
| `FB_APP_ID` | `callbacks_controller.rb:97` | OAuth long-lived exchange |
| `FB_APP_ID` | `message_parser.rb:64` | Echo detection |
| `FB_APP_SECRET` | `facebook_messenger.rb:8` | Webhook signature |
| `FB_APP_SECRET` | `callbacks_controller.rb:97` | OAuth exchange |
| `FB_APP_SECRET` | `send_on_instagram_service.rb` (legacy via FB Page) | appsecret_proof |
| `FB_VERIFY_TOKEN` | `facebook_messenger.rb:4` | Webhook verify |
| `IG_VERIFY_TOKEN` | `instagram_controller.rb:39` | Webhook verify (legacy via FB Page) |
| `INSTAGRAM_VERIFY_TOKEN` | `instagram_controller.rb:40` | Webhook verify (direto) |
| `INSTAGRAM_APP_ID` | `instagram_concern.rb:21` | OAuth client |
| `INSTAGRAM_APP_SECRET` | `instagram_concern.rb:24` | OAuth client + JWT sign |
| `FACEBOOK_API_VERSION` | `dashboard_controller.rb:77` | Frontend SDK version |
| `INSTAGRAM_API_VERSION` | `message_text.rb`, `channel/instagram.rb:48` | API calls |

**Meta:** após Fase 3, **zero leitura direta** desses keys fora de `SocialChannels::CredentialResolver`. CI check via `grep` no PR.

### 4.3 RBAC e plugins relevantes

- Catálogo único em duas faces sincronizadas pelo CI ([plugins/custom_roles/frontend/shared/modules.js](../../plugins/custom_roles/frontend/shared/modules.js), [plugins/custom_roles/app/models/klivy_role/permissions_catalog.rb](../../plugins/custom_roles/app/models/klivy_role/permissions_catalog.rb)).
- API canônica: `beclinic_can?(:module, :perm)` no backend; `usePermissions().can(...)` + `v-can` no frontend.
- Padrão de plugin: `plugins/beclinic_core/` (foundation), `plugins/billing/`, `plugins/financial/`, `plugins/patients/`, `plugins/agenda/` (domain plugins com engine + frontend + swagger + migrations).
- Active Record Encryption: configurado em [config/initializers/active_record_encryption.rb](../../config/initializers/active_record_encryption.rb). Modelos que usam: `Channel::FacebookPage`, `Channel::Instagram`, `Channel::Email`, `Channel::Line`, `Channel::TikTok`, `Channel::Telegram`, `Channel::TwitterProfile`, `Channel::TwilioSMS`, `Integrations::Hook`, `User` (MFA), `Financial::AgentProfile`, `Financial::GatewaySetting`.

### 4.4 Padrão de referência mais próximo

`Channel::Whatsapp` ([app/models/channel/whatsapp.rb:1-98](../../app/models/channel/whatsapp.rb#L1-L98)) é o blueprint canônico de credenciais per-tenant em Channel: guarda em `provider_config` JSONB e gera `webhook_verify_token` único via `before_validation`. Limitação: é **per-channel** (1 token por número WhatsApp), e queremos **per-account** (1 App Meta cobre N pages/IG). Adaptamos o padrão movendo para `BeclinicMetaApp` com `(account_id, provider)` UNIQUE.

---

## 5. Diagnóstico dos Problemas Atuais

| # | Problema | Severidade | Impacto |
|---|---|---|---|
| 1 | `FB_APP_*`/`INSTAGRAM_APP_*` globais via `InstallationConfig` — todas as accounts compartilham 1 App Meta | Bloqueador | Inviabiliza self-service SaaS; clínica depende de Klivy ter app aprovada |
| 2 | `ChatwootFbProvider.access_token_for(page_id)` resolve `.last` sem `account_id` ([facebook_messenger.rb:12](../../config/initializers/facebook_messenger.rb#L12)) | Bug latente | Se 2 accounts conectarem mesma page_id (raro em prod, comum em dev/agency apps), webhook entrega ao Channel errado |
| 3 | Frontend dispara FB SDK com `window.chatwootConfig.fbAppId` global | Alto | Mesmo após desbloquear UI, OAuth abre com app errada → clínica autoriza dados pro app errado |
| 4 | `instagram_concern.rb` força `INSTAGRAM_APP_ID/SECRET` globais em todas operações OAuth/refresh | Alto | Não dá pra trocar app sem reset global |
| 5 | `MetaTokenVerifyConcern` compara verify_token contra constante global única | Alto | Cada Account precisa do MESMO verify_token na sua app Meta — conflito conceitual |
| 6 | OAuth state token IG é JWT assinado com `INSTAGRAM_APP_SECRET` global | Médio | Trocar app secret global mata todas authorizações em vôo |
| 7 | `Channel::Instagram.instagram_id` validates uniqueness global (sem scope `:account_id`) | Médio | Bloqueia 2 accounts com mesmo IG ID (improvável em prod, mas restritivo) |
| 8 | Logs do `register_facebook_page` imprimem `user_access_token` e `page_access_token` em `Rails.logger.debug` ([callbacks_controller.rb:25-29](../../app/controllers/api/v1/accounts/callbacks_controller.rb#L25-L29)) | Alto (segurança) | Vazamento de tokens para Sentry/console se nível debug ativo |

---

## 6. Riscos Encontrados

### 6.1 Multi-tenant

- **Cross-tenant token leakage** se `page_id → channel` continuar usando `.last` (problema 2). Mitigação: fix no provider override + warn em duplicações.
- **Cross-tenant verify_token leakage** mantendo verify_token global. Mitigação: per-tenant com 256-bit entropy + index unique determinístico.
- **State token JWT** assinado com secret global. Mitigação: usar `meta_app.app_secret` da Account específica.

### 6.2 Segurança

- App Secret em texto claro no `InstallationConfig.value`. Mitigação: novo modelo `BeclinicMetaApp` usa `encrypts :app_secret` (não-determinístico).
- Logs imprimem tokens (problema 8). Mitigação: rebaixar a `:trace` ou sanitizar — corrigido na Fase 5.
- `serializable_value` de `InstallationConfig` pode ser exposta em endpoint `/auth/config`. Mitigação: auditar whitelist antes de migrar valores.

### 6.3 Regressão

- Clínicas atuais dependem do App global. Mitigação: fallback no `CredentialResolver`.
- Gem `facebook-messenger` resolve provider em boot. Mitigação: usar `Rails.application.reloader.to_prepare` no engine do plugin.

### 6.4 Operacional

- Cada Account precisa criar app Meta própria (onboarding pesado). Mitigação: documentação + helper visual + fallback global pra trial.
- Token refresh do Instagram é lazy ([app/services/instagram/refresh_oauth_token_service.rb](../../app/services/instagram/refresh_oauth_token_service.rb)). Mitigação: job periódico `InstagramRefreshAllJob` (Fase 7).
- Painel Meta da clínica precisa colar URL + verify_token (UX pode confundir). Mitigação: helper `MetaWebhookHelper.vue` com copy-to-clipboard.

---

## 7. Arquitetura Proposta

### 7.1 Visão de alto nível

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            FRONTEND (Vue 3)                              │
│                                                                          │
│  ┌──────────────────────┐    ┌────────────────────────────────────────┐ │
│  │ MetaAppsSettings.vue │    │ ChannelItem.vue (existente, adaptado)  │ │
│  │ (página nova)        │    │   isActive = enabledFeatures.X         │ │
│  │   CRUD + helper      │    │            && (perAccount || global)   │ │
│  │   visual webhook     │    │            via useMetaApps()           │ │
│  └──────────┬───────────┘    └────────────┬───────────────────────────┘ │
│             │                              │                             │
│             │  useMetaApps()               │                             │
│             │  composable                  │                             │
│             ▼                              ▼                             │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  metaAppsAPI.js → /api/v1/accounts/:id/meta_apps                 │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────┬───────────────────────────────────┘
                                       │
┌──────────────────────────────────────┼───────────────────────────────────┐
│                              BACKEND │                                    │
│                                       │                                    │
│  ┌──────────────────────────────────▼───────────────────────────────┐   │
│  │  Api::V1::Accounts::SocialChannels::MetaAppsController            │   │
│  │  (CRUD + verify_connection)                                       │   │
│  └──────────────────────────────────┬───────────────────────────────┘   │
│                                       │                                    │
│  ┌──────────────────────────────────▼───────────────────────────────┐   │
│  │              BeclinicMetaApp (model + encryption)                 │   │
│  │  (account_id, provider, app_id, app_secret, verify_token, ...)   │   │
│  └──────────────────────────────────┬───────────────────────────────┘   │
│                                       │                                    │
│  ┌────────────────────────────────────▼──────────────────────────────┐  │
│  │           SocialChannels::CredentialResolver (único entry)        │  │
│  │       resolve(account, provider) → struct {app_id, secret, ...}   │  │
│  │       Precedência: BeclinicMetaApp → InstallationConfig (fallback)│  │
│  └────────────────────────────────────┬──────────────────────────────┘  │
│                                       │                                    │
│       ┌───────────────────────────────┼───────────────────────────────┐  │
│       ▼                               ▼                               ▼  │
│  ┌──────────┐              ┌────────────────────┐         ┌──────────┐ │
│  │ OAuth    │              │ MultiTenantFb      │         │ Webhook  │ │
│  │ Services │              │ Provider           │         │ Ctrls    │ │
│  │ (FB+IG)  │              │ (override)         │         │ (social) │ │
│  └──────────┘              └────────────────────┘         └──────────┘ │
└──────────────────────────────────────────────────────────────────────────┘
```

### 7.2 Componentes novos

| Componente | Responsabilidade | Caminho |
|---|---|---|
| `BeclinicMetaApp` | AR model + encryption | `plugins/social_channels/app/models/beclinic_meta_app.rb` |
| `CredentialResolver` | Resolve credenciais (MetaApp → global fallback) | `plugins/social_channels/app/services/social_channels/credential_resolver.rb` |
| `FacebookOauth` | Long-lived exchange + page list (substitui código de `callbacks_controller`) | `plugins/social_channels/app/services/social_channels/facebook_oauth.rb` |
| `InstagramOauth` | Authorize URL + token exchange (substitui `instagram_concern`) | `plugins/social_channels/app/services/social_channels/instagram_oauth.rb` |
| `SignatureVerifier` | X-Hub-Signature-256 timing-safe | `plugins/social_channels/app/services/social_channels/signature_verifier.rb` |
| `MultiTenantFbProvider` | Override do `ChatwootFbProvider` | `plugins/social_channels/app/overrides/social_channels/overrides/multi_tenant_fb_provider.rb` |
| `MetaAppsController` | CRUD per-account | `plugins/social_channels/app/controllers/api/v1/accounts/social_channels/meta_apps_controller.rb` |
| `FacebookOauthController` | Substitui parte de `callbacks_controller` | `plugins/social_channels/app/controllers/api/v1/accounts/social_channels/facebook_oauth_controller.rb` |
| `Webhooks::SocialChannels::FacebookController` | Webhook URL nova (`/webhooks/social/facebook`) | `plugins/social_channels/app/controllers/webhooks/social_channels/facebook_controller.rb` |
| `Webhooks::SocialChannels::InstagramController` | Webhook URL nova (`/webhooks/social/instagram`) | `plugins/social_channels/app/controllers/webhooks/social_channels/instagram_controller.rb` |
| `BeclinicMetaAppPolicy` | Pundit + `beclinic_can?` | `plugins/social_channels/app/policies/beclinic_meta_app_policy.rb` |
| `InstagramRefreshAllJob` | Refresh proativo IG tokens | `plugins/social_channels/app/jobs/social_channels/instagram_refresh_all_job.rb` |
| `useMetaApps` composable | Cache frontend keyed por accountId | `plugins/social_channels/frontend/composables/useMetaApps.js` |
| `MetaAppsSettings.vue` | Página de settings | `plugins/social_channels/frontend/pages/MetaAppsSettings.vue` |
| `MetaAppForm.vue` | Form CRUD modal | `plugins/social_channels/frontend/components/MetaAppForm.vue` |
| `MetaWebhookHelper.vue` | Helper visual (URL + token copy) | `plugins/social_channels/frontend/components/MetaWebhookHelper.vue` |

### 7.3 Componentes existentes modificados

| Componente | Mudança | Justificativa |
|---|---|---|
| `ChatwootFbProvider` | Substituído por `MultiTenantFbProvider` via `Rails.application.reloader.to_prepare` | Único ponto onde gem `facebook-messenger` resolve credenciais |
| `callbacks_controller.rb` | `long_lived_token` passa por `SocialChannels::FacebookOauth` (mantém shim com fallback global) | Centraliza leitura de credenciais |
| `instagram_concern.rb` | Métodos `client_id`/`client_secret` recebem `account:` via parâmetro; fallback global mantido | Per-account OAuth |
| `Instagram::AuthorizationsController` | `prepend_mod_with` injeta resolução de MetaApp; state JWT assinado com `meta_app.app_secret` | Per-account state token |
| `Instagram::CallbacksController` | Decodifica state com `meta_app.app_secret`; usa MetaApp em token exchange | Per-account callback |
| `RefreshOauthTokenService` | Recebe `account`/`meta_app` em vez de ler GlobalConfig | Per-account refresh |
| `Facebook::SendOnInstagramService` (legacy) | `appsecret_proof` usa `CredentialResolver.call(...).app_secret` | Per-account signature |
| `ChannelItem.vue` | `hasFbConfigured` lê `useMetaApps().facebookAppId || window.chatwootConfig?.fbAppId` | Desbloqueio per-account com fallback |
| `Facebook.vue` (settings/inbox/channels) | `FB.init` usa `useMetaApps().facebookAppId || global` | OAuth com app correta |
| `plugins/custom_roles/frontend/shared/modules.js` | Adiciona `meta_apps_view`/`meta_apps_manage` no módulo `settings` | RBAC |
| `plugins/custom_roles/app/models/klivy_role/permissions_catalog.rb` | Adiciona perms novas no `CATALOG['settings']` | RBAC (sync com JS) |
| `Sidebar.vue` (settings) | Item novo "Integrações → Meta Apps" com `CHILD_GATES` | Navegação |
| `routeHelpers.js` | `KLIVY_REQUIRED_ROUTE_RULES` para nova rota | Route guard |

---

## 8. Modelo de Dados

### 8.1 Migration

`plugins/social_channels/db/migrate/2026XXXXXXXXXX_create_beclinic_meta_apps.rb`:

```ruby
class CreateBeclinicMetaApps < ActiveRecord::Migration[7.0]
  def change
    create_table :beclinic_meta_apps do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string  :provider, null: false                # "facebook" | "instagram"
      t.string  :app_id, null: false                  # Público; vai pro frontend
      t.string  :app_secret, null: false              # Encrypted (não-determinístico)
      t.string  :verify_token, null: false            # Encrypted (determinístico — webhook lookup)
      t.string  :api_version, null: false             # ex: "v18.0" (FB), "v22.0" (IG)
      t.boolean :enabled, null: false, default: true
      t.boolean :human_agent_enabled, null: false, default: false
      t.datetime :last_verified_at                    # Último handshake bem-sucedido
      t.jsonb   :metadata, null: false, default: {}   # Extensões futuras
      t.timestamps
    end

    add_index :beclinic_meta_apps, [:account_id, :provider], unique: true,
              name: 'idx_meta_apps_on_account_and_provider'
    add_index :beclinic_meta_apps, :verify_token, unique: true,
              name: 'idx_meta_apps_on_verify_token'
    add_index :beclinic_meta_apps, [:provider, :enabled],
              name: 'idx_meta_apps_on_provider_enabled'
  end
end
```

### 8.2 Model

`plugins/social_channels/app/models/beclinic_meta_app.rb`:

```ruby
# == Schema Information
#
# Table name: beclinic_meta_apps
#
#  id                  :bigint           not null, primary key
#  account_id          :bigint           not null
#  provider            :string           not null
#  app_id              :string           not null
#  app_secret          :string           not null    # encrypted
#  verify_token        :string           not null    # encrypted (deterministic)
#  api_version         :string           not null
#  enabled             :boolean          default: true, not null
#  human_agent_enabled :boolean          default: false, not null
#  last_verified_at    :datetime
#  metadata            :jsonb            default: {}, not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#

class BeclinicMetaApp < ApplicationRecord
  PROVIDERS = %w[facebook instagram].freeze
  DEFAULT_API_VERSIONS = { 'facebook' => 'v18.0', 'instagram' => 'v22.0' }.freeze

  self.table_name = 'beclinic_meta_apps'

  belongs_to :account

  if Chatwoot.encryption_configured?
    encrypts :app_secret
    encrypts :verify_token, deterministic: true
  end

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :provider, uniqueness: { scope: :account_id }
  validates :app_id, presence: true
  validates :app_secret, presence: true
  validates :api_version, presence: true, format: { with: /\Av\d+\.\d+\z/, message: 'must look like "vXX.X"' }

  before_validation :assign_verify_token
  before_validation :assign_api_version

  scope :facebook, -> { where(provider: 'facebook') }
  scope :instagram, -> { where(provider: 'instagram') }
  scope :enabled, -> { where(enabled: true) }

  def self.for(account, provider:)
    return nil if account.blank?

    enabled.where(account_id: account.id, provider: provider).first
  end

  def self.find_by_verify_token(token)
    return nil if token.blank?

    enabled.where(verify_token: token).first
  end

  def mark_verified!
    update!(last_verified_at: Time.current)
  end

  private

  def assign_verify_token
    self.verify_token ||= SecureRandom.hex(32)  # 256-bit entropy
  end

  def assign_api_version
    self.api_version ||= DEFAULT_API_VERSIONS[provider]
  end
end
```

### 8.3 Justificativa do schema

| Coluna | Decisão | Razão |
|---|---|---|
| `app_id` | Não criptografado | Vai pro frontend (público no consent screen Meta); índice futuro pra debug |
| `app_secret` | Encrypted não-determinístico | Nunca precisa de lookup; máxima entropia no ciphertext |
| `verify_token` | Encrypted determinístico | Webhook GET precisa fazer lookup; index unique funciona com deterministic encryption |
| `api_version` | String NOT NULL | Permite override por app (Meta lança versões novas; algumas clínicas podem ficar em version antiga) |
| `enabled` | Boolean default true | Permite "pausar" app sem deletar (manter histórico) |
| `human_agent_enabled` | Boolean | Equivale aos `ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT`/`ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT` globais hoje |
| `last_verified_at` | Datetime nullable | Alerta visual se >7 dias (token possivelmente quebrado) |
| `metadata` | JSONB default `{}` | Espaço pra rate-limit hints, business_account_id cacheado, etc. |
| `(account_id, provider)` UNIQUE | Constraint | 1 app por provider por account |
| `verify_token` UNIQUE | Constraint | Webhook routing depende de unicidade |

---

## 9. Estrutura do Plugin `social_channels`

```
plugins/social_channels/
├── lib/
│   └── social_channels/
│       ├── engine.rb                          # isolate_namespace, migrations, to_prepare overrides
│       └── version.rb
├── app/
│   ├── models/
│   │   └── beclinic_meta_app.rb
│   ├── controllers/
│   │   ├── api/v1/accounts/social_channels/
│   │   │   ├── meta_apps_controller.rb         # CRUD + verify_connection
│   │   │   └── facebook_oauth_controller.rb    # exchange + register_page
│   │   └── webhooks/social_channels/
│   │       ├── facebook_controller.rb          # /webhooks/social/facebook
│   │       └── instagram_controller.rb         # /webhooks/social/instagram
│   ├── services/
│   │   └── social_channels/
│   │       ├── credential_resolver.rb          # ÚNICO ponto de leitura de credenciais
│   │       ├── facebook_oauth.rb               # long_lived_token, fetch_pages
│   │       ├── instagram_oauth.rb              # authorize URL, exchange, refresh
│   │       ├── signature_verifier.rb           # X-Hub-Signature-256 timing-safe
│   │       └── webhook_dispatcher.rb           # find MetaApp by verify_token ou page_id
│   ├── jobs/
│   │   └── social_channels/
│   │       └── instagram_refresh_all_job.rb    # Cron diário
│   ├── policies/
│   │   └── beclinic_meta_app_policy.rb         # beclinic_can?(:settings, :meta_apps_*)
│   ├── overrides/
│   │   └── social_channels/
│   │       └── overrides/
│   │           ├── multi_tenant_fb_provider.rb # Substitui ChatwootFbProvider
│   │           ├── instagram_authorizations_controller_override.rb
│   │           ├── instagram_callbacks_controller_override.rb
│   │           └── meta_token_verify_concern_override.rb
│   └── views/
│       └── api/v1/accounts/social_channels/
│           ├── meta_apps/
│           │   ├── _meta_app.json.jbuilder     # Serializer (NUNCA expõe app_secret)
│           │   ├── index.json.jbuilder
│           │   └── show.json.jbuilder
│           └── facebook_oauth/
│               ├── exchange.json.jbuilder
│               └── register_page.json.jbuilder
├── config/
│   └── routes.rb                               # /webhooks/social/* + CRUD /meta_apps
├── db/
│   ├── migrate/
│   │   └── 2026XXXXXXXXXX_create_beclinic_meta_apps.rb
│   └── seeds/
│       └── README.md                           # Sem seed: app é per-account, criada pela clínica
├── swagger/
│   ├── common.yml
│   ├── index.yml
│   ├── paths/
│   │   └── social_channels/
│   │       ├── meta_apps.yml
│   │       └── facebook_oauth.yml
│   └── definitions/
│       └── beclinic_meta_app.yml
├── frontend/
│   ├── api/
│   │   └── metaAppsAPI.js
│   ├── routes/
│   │   └── index.js                            # injeta rota /settings/.../meta-apps
│   ├── pages/
│   │   └── MetaAppsSettings.vue
│   ├── components/
│   │   ├── MetaAppForm.vue
│   │   ├── MetaAppCard.vue
│   │   └── MetaWebhookHelper.vue
│   ├── composables/
│   │   └── useMetaApps.js
│   ├── styles/
│   │   ├── _variables.scss
│   │   └── meta-apps.scss
│   └── i18n/
│       └── pt_BR.json
├── spec/
│   ├── models/
│   │   └── beclinic_meta_app_spec.rb
│   ├── services/
│   │   └── social_channels/
│   │       ├── credential_resolver_spec.rb
│   │       ├── facebook_oauth_spec.rb
│   │       ├── instagram_oauth_spec.rb
│   │       └── signature_verifier_spec.rb
│   ├── controllers/
│   │   ├── api/v1/accounts/social_channels/
│   │   │   ├── meta_apps_controller_spec.rb
│   │   │   └── facebook_oauth_controller_spec.rb
│   │   └── webhooks/social_channels/
│   │       ├── facebook_controller_spec.rb
│   │       └── instagram_controller_spec.rb
│   ├── policies/
│   │   └── beclinic_meta_app_policy_spec.rb
│   ├── jobs/
│   │   └── instagram_refresh_all_job_spec.rb
│   ├── overrides/
│   │   └── multi_tenant_fb_provider_spec.rb
│   ├── multi_tenant/
│   │   └── isolation_spec.rb                   # Cross-tenant assertions
│   └── factories/
│       └── beclinic_meta_apps.rb
├── README.md
└── CHANGELOG.md
```

---

## 10. Fluxo Backend Completo

### 10.1 Engine boot

`plugins/social_channels/lib/social_channels/engine.rb`:

```ruby
module SocialChannels
  class Engine < ::Rails::Engine
    isolate_namespace SocialChannels

    initializer :append_social_channels_migrations do |app|
      app.config.paths['db/migrate'] << root.join('db/migrate').to_s
      ActiveRecord::Migrator.migrations_paths << root.join('db/migrate').to_s
    end

    config.to_prepare do
      # 1) Substituir provider da gem facebook-messenger
      require 'social_channels/overrides/multi_tenant_fb_provider'
      Facebook::Messenger.configure do |config|
        config.provider = SocialChannels::Overrides::MultiTenantFbProvider.new
      end

      # 2) Adicionar associação em Account
      unless Account.method_defined?(:beclinic_meta_apps)
        Account.has_many :beclinic_meta_apps, dependent: :destroy_async
      end

      # 3) Prepend overrides em controllers do core
      Api::V1::Accounts::Instagram::AuthorizationsController.prepend(
        SocialChannels::Overrides::InstagramAuthorizationsControllerOverride
      )
      Instagram::CallbacksController.prepend(
        SocialChannels::Overrides::InstagramCallbacksControllerOverride
      )
    end
  end
end
```

### 10.2 CredentialResolver (único ponto de leitura)

`plugins/social_channels/app/services/social_channels/credential_resolver.rb`:

```ruby
module SocialChannels
  class CredentialResolver
    PROVIDER_GLOBAL_KEYS = {
      'facebook' => {
        app_id: 'FB_APP_ID',
        app_secret: 'FB_APP_SECRET',
        verify_token: 'FB_VERIFY_TOKEN',
        api_version: 'FACEBOOK_API_VERSION'
      },
      'instagram' => {
        app_id: 'INSTAGRAM_APP_ID',
        app_secret: 'INSTAGRAM_APP_SECRET',
        verify_token: 'INSTAGRAM_VERIFY_TOKEN',
        api_version: 'INSTAGRAM_API_VERSION'
      }
    }.freeze

    Resolved = Struct.new(
      :app_id, :app_secret, :verify_token, :api_version, :source, :meta_app,
      keyword_init: true
    ) do
      def configured?
        app_id.present? && app_secret.present?
      end

      def from_meta_app?
        source == :meta_app
      end

      def from_global?
        source == :global
      end
    end

    def self.call(account:, provider:)
      new(account, provider.to_s).call
    end

    def initialize(account, provider)
      @account = account
      @provider = provider
    end

    def call
      meta_app = BeclinicMetaApp.for(@account, provider: @provider)
      meta_app.present? ? from_meta_app(meta_app) : from_global
    end

    private

    def from_meta_app(app)
      Resolved.new(
        app_id: app.app_id,
        app_secret: app.app_secret,
        verify_token: app.verify_token,
        api_version: app.api_version,
        source: :meta_app,
        meta_app: app
      )
    end

    def from_global
      keys = PROVIDER_GLOBAL_KEYS.fetch(@provider)
      Resolved.new(
        app_id: GlobalConfigService.load(keys[:app_id], ''),
        app_secret: GlobalConfigService.load(keys[:app_secret], ''),
        verify_token: GlobalConfigService.load(keys[:verify_token], ''),
        api_version: GlobalConfigService.load(keys[:api_version], default_api_version),
        source: :global,
        meta_app: nil
      )
    end

    def default_api_version
      BeclinicMetaApp::DEFAULT_API_VERSIONS[@provider]
    end
  end
end
```

### 10.3 MultiTenantFbProvider (override)

`plugins/social_channels/app/overrides/social_channels/overrides/multi_tenant_fb_provider.rb`:

```ruby
module SocialChannels
  module Overrides
    class MultiTenantFbProvider < Facebook::Messenger::Configuration::Providers::Base
      def valid_verify_token?(verify_token)
        return true if BeclinicMetaApp.find_by_verify_token(verify_token).present?

        global = GlobalConfigService.load('FB_VERIFY_TOKEN', '')
        global.present? && ActiveSupport::SecurityUtils.secure_compare(global, verify_token.to_s)
      end

      def app_secret_for(page_id)
        channel = resolve_channel(page_id)
        return GlobalConfigService.load('FB_APP_SECRET', '') unless channel

        resolved = CredentialResolver.call(account: channel.account, provider: 'facebook')
        resolved.app_secret.presence || GlobalConfigService.load('FB_APP_SECRET', '')
      end

      def access_token_for(page_id)
        channel = resolve_channel(page_id)
        return nil unless channel

        channel.page_access_token
      end

      private

      def bot
        Chatwoot::Bot
      end

      # Fix do bug original: ordering determinístico + warn em duplicação
      def resolve_channel(page_id)
        channels = Channel::FacebookPage.includes(:account)
                                        .where(page_id: page_id)
                                        .order(:account_id)
                                        .limit(2)
                                        .to_a
        if channels.size > 1
          Rails.logger.warn "[SocialChannels] page_id=#{page_id} mapeia para " \
                            "#{channels.size} channels em accounts diferentes. " \
                            "Selecionando account_id=#{channels.first.account_id}."
        end
        channels.first
      end
    end
  end
end
```

### 10.4 OAuth Facebook (per-account)

`plugins/social_channels/app/services/social_channels/facebook_oauth.rb`:

```ruby
module SocialChannels
  class FacebookOauth
    def self.long_lived_token(meta_app:, short_lived:)
      koala = Koala::Facebook::OAuth.new(meta_app.app_id, meta_app.app_secret)
      result = koala.exchange_access_token_info(short_lived)
      result['access_token']
    rescue Koala::Facebook::APIError => e
      Rails.logger.error "[SocialChannels::FacebookOauth] exchange failed: #{e.message}"
      raise
    end

    def self.fetch_pages(user_access_token)
      api = Koala::Facebook::API.new(user_access_token)
      pages = []
      result = api.get_connections('me', 'accounts')
      pages.concat(result)
      while result.respond_to?(:next_page) && (next_page = result.next_page)
        result = next_page
        pages.concat(result)
      end
      pages
    end

    def self.attach_instagram_id(channel, meta_app:)
      api = Koala::Facebook::API.new(channel.page_access_token)
      response = api.get_connections('me', '', { fields: 'instagram_business_account' })
      return if response['instagram_business_account'].blank?

      channel.update!(instagram_id: response['instagram_business_account']['id'])
    rescue StandardError => e
      Rails.logger.error "[SocialChannels::FacebookOauth] attach_instagram_id failed: #{e.message}"
    end
  end
end
```

### 10.5 Controller CRUD MetaApps

`plugins/social_channels/app/controllers/api/v1/accounts/social_channels/meta_apps_controller.rb`:

```ruby
class Api::V1::Accounts::SocialChannels::MetaAppsController < Api::V1::Accounts::BaseController
  before_action :fetch_meta_app, only: [:show, :update, :destroy, :verify_connection]
  before_action :authorize_view!, only: [:index, :show]
  before_action :authorize_manage!, only: [:create, :update, :destroy, :verify_connection]

  def index
    @meta_apps = Current.account.beclinic_meta_apps.order(:provider)
  end

  def show
    # @meta_app set by fetch_meta_app
  end

  def create
    @meta_app = Current.account.beclinic_meta_apps.create!(meta_app_params)
    render :show, status: :created
  end

  def update
    @meta_app.update!(meta_app_params.compact)
    render :show
  end

  def destroy
    @meta_app.destroy!
    head :no_content
  end

  def verify_connection
    response = SocialChannels::FacebookOauth.verify_app_credentials(@meta_app) if @meta_app.provider == 'facebook'
    response ||= SocialChannels::InstagramOauth.verify_app_credentials(@meta_app)
    @meta_app.mark_verified! if response[:ok]
    render json: response
  end

  private

  def fetch_meta_app
    @meta_app = Current.account.beclinic_meta_apps.find(params[:id])
  end

  def meta_app_params
    params.require(:meta_app).permit(
      :provider, :app_id, :app_secret, :api_version, :enabled, :human_agent_enabled
    )
  end

  def authorize_view!
    head :forbidden unless Current.user.beclinic_can?(Current.account, :settings, :meta_apps_view)
  end

  def authorize_manage!
    head :forbidden unless Current.user.beclinic_can?(Current.account, :settings, :meta_apps_manage)
  end
end
```

### 10.6 Serializer (jbuilder)

`plugins/social_channels/app/views/api/v1/accounts/social_channels/meta_apps/_meta_app.json.jbuilder`:

```ruby
json.id meta_app.id
json.provider meta_app.provider
json.app_id meta_app.app_id
# app_secret NUNCA exposto. Front mostra "••••••••" e POST de update envia novo valor.
json.app_secret_set meta_app.app_secret.present?
json.api_version meta_app.api_version
json.enabled meta_app.enabled
json.human_agent_enabled meta_app.human_agent_enabled
json.last_verified_at meta_app.last_verified_at
json.webhook_url Rails.application.routes.url_helpers.send(
  "webhooks_social_#{meta_app.provider}_url",
  host: ENV.fetch('FRONTEND_URL', nil)
)
# verify_token só para users com meta_apps_manage (admin)
if Current.user&.beclinic_can?(Current.account, :settings, :meta_apps_manage)
  json.verify_token meta_app.verify_token
end
json.created_at meta_app.created_at
json.updated_at meta_app.updated_at
```

### 10.7 Webhook Controllers

`plugins/social_channels/app/controllers/webhooks/social_channels/facebook_controller.rb`:

```ruby
class Webhooks::SocialChannels::FacebookController < ApplicationController
  skip_before_action :verify_authenticity_token

  def verify
    token = params['hub.verify_token'].to_s
    return head :unauthorized if token.blank?
    return head :unauthorized unless params['hub.mode'] == 'subscribe'

    if BeclinicMetaApp.find_by_verify_token(token)
      render plain: params['hub.challenge']
    elsif fallback_global_match?(token)
      render plain: params['hub.challenge']
    else
      head :unauthorized
    end
  end

  def receive
    body = request.raw_post
    signature = request.headers['X-Hub-Signature-256'].to_s

    # 1) Identifica MetaApp dona pelo primeiro entry
    parsed = JSON.parse(body) rescue {}
    page_id = parsed.dig('entry', 0, 'id')
    channel = Channel::FacebookPage.includes(:account).find_by(page_id: page_id)

    # 2) Resolve credenciais (per-account ou global fallback)
    resolved = if channel
                 SocialChannels::CredentialResolver.call(account: channel.account, provider: 'facebook')
               else
                 SocialChannels::CredentialResolver.send(:new, nil, 'facebook').send(:from_global)
               end

    # 3) Valida assinatura
    unless SocialChannels::SignatureVerifier.valid?(
      payload: body, signature: signature, app_secret: resolved.app_secret
    )
      Rails.logger.warn "[SocialChannels::FacebookWebhook] invalid signature page_id=#{page_id}"
      return head :unauthorized
    end

    # 4) Delega processamento ao job existente (não muda parser/builder)
    Webhooks::FacebookEventsJob.perform_later(body)
    head :ok
  end

  private

  def fallback_global_match?(token)
    global = GlobalConfigService.load('FB_VERIFY_TOKEN', '')
    global.present? && ActiveSupport::SecurityUtils.secure_compare(global, token)
  end
end
```

`plugins/social_channels/app/controllers/webhooks/social_channels/instagram_controller.rb` segue padrão idêntico, com:
- `parsed.dig('entry', 0, 'id')` retorna `instagram_business_account_id`
- Channel resolvido via `Channel::Instagram.find_by(instagram_id:)` + fallback `Channel::FacebookPage.find_by(instagram_id:)`
- Enfileira `Webhooks::InstagramEventsJob`

### 10.8 Rotas

`plugins/social_channels/config/routes.rb`:

```ruby
Rails.application.routes.draw do
  scope module: 'api' do
    namespace :v1 do
      resources :accounts, only: [] do
        namespace :social_channels do
          resources :meta_apps, only: [:index, :show, :create, :update, :destroy] do
            member do
              post :verify_connection
            end
          end
          resource :facebook_oauth, only: [], controller: 'facebook_oauth' do
            post :exchange
            post :register_page
          end
        end
      end
    end
  end

  namespace :webhooks do
    scope :social, module: 'social_channels' do
      get  :facebook,  to: 'facebook#verify'
      post :facebook,  to: 'facebook#receive'
      get  :instagram, to: 'instagram#verify'
      post :instagram, to: 'instagram#receive'
    end
  end
end
```

### 10.9 Job de refresh Instagram

`plugins/social_channels/app/jobs/social_channels/instagram_refresh_all_job.rb`:

```ruby
module SocialChannels
  class InstagramRefreshAllJob < ApplicationJob
    queue_as :low

    def perform
      Channel::Instagram.includes(:account).find_each do |channel|
        next if channel.expires_at.nil? || channel.expires_at > 10.days.from_now

        SocialChannels::InstagramOauth.refresh!(channel: channel)
      rescue StandardError => e
        Rails.logger.error "[SocialChannels::InstagramRefreshAllJob] " \
                           "channel=#{channel.id} account=#{channel.account_id}: #{e.message}"
      end
    end
  end
end
```

Cron em `config/schedule.yml`:
```yaml
instagram_refresh_all:
  cron: "0 3 * * *"            # 03:00 diário
  class: "SocialChannels::InstagramRefreshAllJob"
  queue: "low"
```

### 10.10 Policy

`plugins/social_channels/app/policies/beclinic_meta_app_policy.rb`:

```ruby
class BeclinicMetaAppPolicy < ApplicationPolicy
  def index?
    user.beclinic_can?(@account, :settings, :meta_apps_view)
  end

  def show?
    index?
  end

  def create?
    user.beclinic_can?(@account, :settings, :meta_apps_manage)
  end

  def update?
    create?
  end

  def destroy?
    create?
  end

  def verify_connection?
    create?
  end
end
```

---

## 11. Fluxo Frontend Completo

### 11.1 Composable `useMetaApps`

`plugins/social_channels/frontend/composables/useMetaApps.js`:

```javascript
import { ref, watch, computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import MetaAppsAPI from '@plugins/social_channels/frontend/api/metaAppsAPI';

const cache = new Map(); // accountId → { facebook, instagram, loadedAt }
const CACHE_TTL = 5 * 60 * 1000; // 5min

export function useMetaApps() {
  const { accountId } = useAccount();
  const facebook = ref(null);
  const instagram = ref(null);
  const loading = ref(false);

  const load = async (id, { force = false } = {}) => {
    if (!id) return;

    const cached = cache.get(id);
    if (!force && cached && Date.now() - cached.loadedAt < CACHE_TTL) {
      facebook.value = cached.facebook;
      instagram.value = cached.instagram;
      return;
    }

    loading.value = true;
    try {
      const { data } = await MetaAppsAPI.list();
      facebook.value = data.find(a => a.provider === 'facebook') || null;
      instagram.value = data.find(a => a.provider === 'instagram') || null;
      cache.set(id, {
        facebook: facebook.value,
        instagram: instagram.value,
        loadedAt: Date.now(),
      });
    } finally {
      loading.value = false;
    }
  };

  watch(
    accountId,
    (id) => {
      facebook.value = null;
      instagram.value = null;
      load(id);
    },
    { immediate: true }
  );

  return {
    facebookApp: computed(() => facebook.value),
    instagramApp: computed(() => instagram.value),
    facebookAppId: computed(() => facebook.value?.app_id),
    instagramAppId: computed(() => instagram.value?.app_id),
    facebookApiVersion: computed(() => facebook.value?.api_version),
    instagramApiVersion: computed(() => instagram.value?.api_version),
    loading,
    reload: () => load(accountId.value, { force: true }),
  };
}
```

### 11.2 API client

`plugins/social_channels/frontend/api/metaAppsAPI.js`:

```javascript
import ApiClient from 'dashboard/api/ApiClient';

class MetaAppsAPI extends ApiClient {
  constructor() {
    super('social_channels/meta_apps', { accountScoped: true });
  }

  verifyConnection(id) {
    return axios.post(`${this.url}/${id}/verify_connection`);
  }
}

export default new MetaAppsAPI();
```

### 11.3 Página de settings

`plugins/social_channels/frontend/pages/MetaAppsSettings.vue` (esqueleto):

```vue
<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMetaApps } from '../composables/useMetaApps';
import { usePermissions } from 'dashboard/composables/usePermissions';
import MetaAppCard from '../components/MetaAppCard.vue';
import MetaAppForm from '../components/MetaAppForm.vue';

const { t } = useI18n();
const { facebookApp, instagramApp, reload } = useMetaApps();
const { can } = usePermissions();

const editingProvider = ref(null);
const showForm = computed({
  get: () => editingProvider.value !== null,
  set: (v) => { if (!v) editingProvider.value = null; },
});

const canManage = computed(() => can('settings', 'meta_apps_manage'));

const openForm = (provider) => {
  if (!canManage.value) return;
  editingProvider.value = provider;
};

const onSaved = async () => {
  await reload();
  editingProvider.value = null;
};
</script>

<template>
  <div class="meta-apps-settings">
    <header class="page-header">
      <h1>{{ t('SOCIAL_CHANNELS.META_APPS.TITLE') }}</h1>
      <p>{{ t('SOCIAL_CHANNELS.META_APPS.DESCRIPTION') }}</p>
    </header>

    <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
      <MetaAppCard
        provider="facebook"
        :app="facebookApp"
        :can-manage="canManage"
        @edit="openForm('facebook')"
      />
      <MetaAppCard
        provider="instagram"
        :app="instagramApp"
        :can-manage="canManage"
        @edit="openForm('instagram')"
      />
    </div>

    <MetaAppForm
      v-if="showForm"
      :provider="editingProvider"
      :existing-app="editingProvider === 'facebook' ? facebookApp : instagramApp"
      @saved="onSaved"
      @close="editingProvider = null"
    />
  </div>
</template>
```

### 11.4 Helper visual de webhook

`plugins/social_channels/frontend/components/MetaWebhookHelper.vue` (esqueleto):

```vue
<script setup>
import { ref, computed } from 'vue';
import { useClipboard } from '@vueuse/core';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/BeclinicButton.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';

const props = defineProps({
  webhookUrl: { type: String, required: true },
  verifyToken: { type: String, required: true },
  provider: { type: String, required: true },
});

const { copy, copied } = useClipboard();

const requiredFields = computed(() => {
  if (props.provider === 'facebook') {
    return ['messages', 'message_deliveries', 'message_echoes', 'message_reads', 'standby', 'messaging_handovers'];
  }
  return ['messages', 'message_reactions', 'messaging_postbacks'];
});
</script>

<template>
  <div class="webhook-helper">
    <h3>{{ $t('SOCIAL_CHANNELS.WEBHOOK_HELPER.TITLE') }}</h3>
    <ol>
      <li>
        {{ $t('SOCIAL_CHANNELS.WEBHOOK_HELPER.STEP_URL') }}
        <div class="flex gap-2">
          <input :value="webhookUrl" readonly class="flex-1" />
          <Tooltip :label="copied ? $t('COMMON.COPIED') : $t('COMMON.COPY')">
            <BeclinicButton icon="i-lucide-copy" variant="ghost" @click="copy(webhookUrl)" />
          </Tooltip>
        </div>
      </li>
      <li>
        {{ $t('SOCIAL_CHANNELS.WEBHOOK_HELPER.STEP_VERIFY_TOKEN') }}
        <div class="flex gap-2">
          <input :value="verifyToken" readonly class="flex-1 font-mono text-sm" />
          <Tooltip :label="copied ? $t('COMMON.COPIED') : $t('COMMON.COPY')">
            <BeclinicButton icon="i-lucide-copy" variant="ghost" @click="copy(verifyToken)" />
          </Tooltip>
        </div>
      </li>
      <li>
        {{ $t('SOCIAL_CHANNELS.WEBHOOK_HELPER.STEP_FIELDS') }}
        <ul class="list-disc ml-4 text-sm">
          <li v-for="field in requiredFields" :key="field">
            <code>{{ field }}</code>
          </li>
        </ul>
      </li>
    </ol>
  </div>
</template>
```

### 11.5 Adaptação do `ChannelItem.vue`

Edit em [app/javascript/dashboard/components/widgets/ChannelItem.vue:18-49](../../app/javascript/dashboard/components/widgets/ChannelItem.vue#L18-L49):

```vue
<script setup>
import { computed } from 'vue';
import ChannelSelector from '../ChannelSelector.vue';
import { useMetaApps } from '@plugins/social_channels/frontend/composables/useMetaApps';

const props = defineProps({
  channel: { type: Object, required: true },
  enabledFeatures: { type: Object, required: true },
});

const emit = defineEmits(['channelItemClick']);

const { facebookAppId, instagramAppId } = useMetaApps();

const hasFbConfigured = computed(() => {
  return facebookAppId.value || window.chatwootConfig?.fbAppId;
});

const hasInstagramConfigured = computed(() => {
  return instagramAppId.value || window.chatwootConfig?.instagramAppId;
});

const hasTiktokConfigured = computed(() => {
  return window.chatwootConfig?.tiktokAppId;
});

const isActive = computed(() => {
  const { key } = props.channel;
  if (Object.keys(props.enabledFeatures).length === 0) return false;
  if (key === 'website') return props.enabledFeatures.channel_website;
  if (key === 'facebook') return props.enabledFeatures.channel_facebook && hasFbConfigured.value;
  if (key === 'email') return props.enabledFeatures.channel_email;
  if (key === 'instagram') return props.enabledFeatures.channel_instagram && hasInstagramConfigured.value;
  if (key === 'tiktok') return props.enabledFeatures.channel_tiktok && hasTiktokConfigured.value;
  if (key === 'voice') return props.enabledFeatures.channel_voice;
  return ['website', 'twilio', 'api', 'whatsapp', 'sms', 'telegram', 'line', 'instagram', 'tiktok', 'voice'].includes(key);
});

// ... resto inalterado
</script>
```

### 11.6 Adaptação do `Facebook.vue`

Edit em `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Facebook.vue` (linha 124-129):

```javascript
import { useMetaApps } from '@plugins/social_channels/frontend/composables/useMetaApps';

const { facebookAppId, facebookApiVersion } = useMetaApps();

const runFBInit = () => {
  const appId = facebookAppId.value || window.chatwootConfig.fbAppId;
  const version = facebookApiVersion.value || window.chatwootConfig.fbApiVersion;
  if (!appId) {
    // Modal "Configure Meta App in Settings first"
    return;
  }
  window.FB.init({ appId, xfbml: true, version, status: true });
};
```

### 11.7 Sidebar de settings

Edit em [app/javascript/dashboard/components-next/sidebar/Sidebar.vue](../../app/javascript/dashboard/components-next/sidebar/Sidebar.vue):

- Adicionar item `Settings Integrations Meta Apps` na seção Configurações → Integrações.
- Adicionar em `CHILD_GATES`:
  ```js
  'Settings Integrations Meta Apps': ['settings', 'meta_apps_view'],
  ```

Edit em [app/javascript/dashboard/helper/routeHelpers.js](../../app/javascript/dashboard/helper/routeHelpers.js):
```js
KLIVY_REQUIRED_ROUTE_RULES = {
  // ...
  settings_integrations_meta_apps_index: ['settings', 'meta_apps_view'],
};
```

---

## 12. Estratégia Multi-Tenant

### 12.1 Touchpoints de resolução

| Touchpoint | Resolução | Garantia |
|---|---|---|
| OAuth start (FE) | `useMetaApps()` keyed por `accountId`, watch em mudança | Cache invalida no account switch |
| OAuth exchange (BE) | `Current.account` + `BeclinicMetaApp.for(account, provider:)` | Pundit guard via `BeclinicMetaAppPolicy` |
| Webhook GET verify | `BeclinicMetaApp.find_by_verify_token` (deterministic encryption) | Verify tokens 256-bit; colisão prática impossível |
| Webhook POST FB | `page_id → Channel::FacebookPage → account → MetaApp` | Validação de assinatura com `MetaApp.app_secret` daquela account |
| Webhook POST IG | `instagram_id → Channel → account → MetaApp` | Idem; também fix do uniqueness scope (Fase 5) |
| Send outbound | `channel.page_access_token`/`channel.access_token` (per-channel) + `MetaApp.app_secret` para appsecret_proof | Resolução via Account dona do channel |
| Token refresh (IG) | Job recebe `account_id` (não `Current.account`) e refaz com MetaApp daquela account | Padrão multi-tenant de jobs do [AGENTS.md](../../AGENTS.md) |

### 12.2 Bloqueio cross-tenant (checklist)

- [x] Toda query passa por `for(account, provider:)` ou `Current.account.beclinic_meta_apps`.
- [x] Rotas CRUD sob `/api/v1/accounts/:account_id/...`.
- [x] Policy checa `@account_user.present?` + perm específica via `beclinic_can?`.
- [x] Tabela tem `t.references :account, null: false, foreign_key: true`.
- [x] Cache frontend keyed por `accountId` + watch em mudança.
- [x] Webhook lookup nunca usa `.last` sem ordering determinístico.
- [x] Job de refresh recebe `account_id` por argumento.
- [x] Verify_token único globalmente (index unique) — evita colisão de webhook routing.
- [x] State JWT (IG OAuth) assinado com `meta_app.app_secret` da Account específica.

### 12.3 Fix do uniqueness do Instagram

Adicionar migration na Fase 5:

```ruby
class FixInstagramIdUniqueness < ActiveRecord::Migration[7.0]
  def change
    remove_index :channel_instagram, :instagram_id if index_exists?(:channel_instagram, :instagram_id, unique: true)
    add_index :channel_instagram, [:instagram_id, :account_id], unique: true,
              name: 'idx_channel_instagram_on_instagram_id_and_account'
  end
end
```

E atualizar `Channel::Instagram`:
```ruby
validates :instagram_id, uniqueness: { scope: :account_id }
```

---

## 13. Estratégia de Webhook

### 13.1 URL fixa, verify_token único por tenant

**Decisão:** URL fixa por instalação (`https://<host>/webhooks/social/{facebook|instagram}`). Cada Account configura na Meta dela essa URL **e o verify_token que geramos pra ela**. Quando Meta faz handshake GET, o índice `verify_token UNIQUE` (deterministic encryption) localiza a MetaApp dona em O(1) → responde `hub.challenge`.

**Entropia:** `SecureRandom.hex(32)` = 256-bit. Colisão entre N tokens tem probabilidade `≈ N²/2^257` — totalmente desprezível.

**Alternativa rejeitada:** URL per-tenant (`/webhooks/social/facebook/:account_id`). Funciona mas duplica entropia (cada tenant já tem app própria com URL fixa por instalação) e aumenta superfície de erro de digitação no painel Meta.

### 13.2 Validação de assinatura POST

Meta envia `X-Hub-Signature-256: sha256=<hmac>`. Algoritmo: `HMAC-SHA256(app_secret, raw_body)`.

```ruby
module SocialChannels
  class SignatureVerifier
    def self.valid?(payload:, signature:, app_secret:)
      return false if signature.blank? || app_secret.blank?

      expected = 'sha256=' + OpenSSL::HMAC.hexdigest('sha256', app_secret, payload)
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end
  end
end
```

**Cuidado crítico:** `request.raw_post` deve ser lido ANTES de qualquer parser tocar. Confirme `skip_before_action :verify_authenticity_token` no controller.

### 13.3 Fix do bug `.last` (problema #2)

Implementado no `MultiTenantFbProvider#resolve_channel` (§10.3). Log de warn quando houver >1 resultado pra observabilidade.

### 13.4 Coexistência com `/bot` legacy

**Não removemos** `mount Facebook::Messenger::Server, at: 'bot'` ([config/routes.rb:1166](../../config/routes.rb#L1166)). Accounts antigas que ainda apontam pra `/bot` continuam funcionando — o `MultiTenantFbProvider` resolve credenciais corretas via MetaApp da Account. URL nova `/webhooks/social/facebook` é introduzida pra novas Accounts e documentação oficial. **Migração de URL no painel Meta é opcional**, recomendada mas não obrigatória.

### 13.5 Fluxo completo de webhook (diagrama)

```
┌────────────────────────────────────────────────────────────────┐
│              Meta servers POST /webhooks/social/facebook       │
│              Header X-Hub-Signature-256: sha256=<hmac>         │
│              Body: { entry: [{ id: page_id, messaging: [...] }]│
└─────────────────────────────┬──────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│  Webhooks::SocialChannels::FacebookController#receive          │
│  1. body = request.raw_post                                    │
│  2. signature = request.headers['X-Hub-Signature-256']         │
│  3. page_id = JSON.parse(body).dig('entry', 0, 'id')           │
└─────────────────────────────┬──────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│  channel = Channel::FacebookPage.includes(:account)            │
│                                   .find_by(page_id: page_id)   │
└─────────────────────────────┬──────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│  resolved = CredentialResolver.call(                           │
│    account: channel&.account, provider: 'facebook'             │
│  )                                                             │
│  # source = :meta_app se Account tem MetaApp                   │
│  # source = :global se não tem (fallback InstallationConfig)   │
└─────────────────────────────┬──────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│  if SignatureVerifier.valid?(                                  │
│      payload: body,                                            │
│      signature: signature,                                     │
│      app_secret: resolved.app_secret                           │
│    )                                                           │
│    → Webhooks::FacebookEventsJob.perform_later(body)           │
│    → head :ok                                                  │
│  else                                                          │
│    → head :unauthorized                                        │
│  end                                                           │
└────────────────────────────────────────────────────────────────┘
```

---

## 14. Estratégia RBAC

### 14.1 Catálogo (perms novas)

**Frontend** ([plugins/custom_roles/frontend/shared/modules.js](../../plugins/custom_roles/frontend/shared/modules.js)) — dentro do módulo `settings`:

```javascript
{
  key: 'settings',
  label: 'Configurações',
  permissions: [
    // ... perms existentes ...
    { key: 'meta_apps_view',   label: 'Visualizar integrações Meta' },
    { key: 'meta_apps_manage', label: 'Gerenciar integrações Meta (Facebook/Instagram)' },
  ],
}
```

**Backend** ([plugins/custom_roles/app/models/klivy_role/permissions_catalog.rb](../../plugins/custom_roles/app/models/klivy_role/permissions_catalog.rb)) — array `'settings'` do `CATALOG`:

```ruby
'settings' => %w[
  # ... perms existentes ...
  meta_apps_view
  meta_apps_manage
]
```

**Spec sync** ([spec/plugins/custom_roles/catalog_sync_spec.rb](../../spec/plugins/custom_roles/catalog_sync_spec.rb)) garante consistência — CI quebra se esquecer um dos lados.

### 14.2 Presets (espelhar em ambos)

| Preset | `meta_apps_view` | `meta_apps_manage` |
|---|---|---|
| Recepcionista | ❌ | ❌ |
| Especialista | ❌ | ❌ |
| Gerente | ✅ | ✅ |
| SDR | ❌ | ❌ |

(Administrator tem bypass total via `beclinic_can?` admin check.)

### 14.3 Sidebar + router guard

- `Sidebar.vue`: item novo `Settings Integrations Meta Apps` com `CHILD_GATES: ['settings', 'meta_apps_view']`.
- `routeHelpers.js`: `KLIVY_REQUIRED_ROUTE_RULES.settings_integrations_meta_apps_index = ['settings', 'meta_apps_view']`.

### 14.4 Aplicação backend/frontend

- **Backend Policy**: `BeclinicMetaAppPolicy` usa `beclinic_can?(:settings, :meta_apps_*)`.
- **Backend Controller**: `before_action :authorize_view!` / `:authorize_manage!`.
- **Frontend componente**: `v-can="['settings', 'meta_apps_manage']"` no botão "Salvar" e em ações de edit/delete.
- **Frontend composable**: `usePermissions().can('settings', 'meta_apps_view')` para esconder página.
- **Serializer**: campo `verify_token` só renderiza se `Current.user.beclinic_can?(... :meta_apps_manage)`.

### 14.5 Quem pode criar Inbox FB/IG depois disso?

Mantemos o gate atual de Inbox (`settings.inboxes_create` + role `administrator`). Mas o **destravamento dos cards FB/IG** passa a depender da existência de uma `BeclinicMetaApp` válida OU do fallback global.

| Cenário | Resultado |
|---|---|
| Account sem MetaApp, sem InstallationConfig global | Cards desativados (igual hoje) |
| Account sem MetaApp, com InstallationConfig global preenchida | Cards ativos (compat com instalações single-tenant) |
| Account com MetaApp própria | Cards ativos, OAuth usa app da Account |
| User sem `settings.meta_apps_manage` | Não vê página de Meta Apps, mas pode criar Inbox se Account tem MetaApp (ou global) configurada |

---

## 15. Plano de Implementação por Fase

Cada fase é **mergeable independente** com feature flag `social_channels:meta_apps_v1` (via `Features` existente do Chatwoot) protegendo o frontend. Backend é gradual e não invasivo.

### 15.1 Tabela de fases

| Fase | Escopo | Duração | Risco | Reversível? |
|---|---|---|---|---|
| **F1** | Criar plugin `social_channels` (engine vazio, migration `beclinic_meta_apps`, modelo + encryption + specs unitários) | 1d | Baixo | ✅ Drop table |
| **F2** | RBAC: perms novas em `custom_roles` (modules.js + catalog.rb + presets) | 0.5d | Baixo | ✅ Remover entradas |
| **F3** | `CredentialResolver` + refator dos pontos de leitura de config global pra passar por ele, mantendo fallback global | 2d | Médio | ✅ Revert PR |
| **F4** | `MultiTenantFbProvider` (override) substituindo `ChatwootFbProvider`; fix do `.last`; spec de webhook multi-tenant | 2d | Alto | ✅ Restaurar provider original |
| **F5** | Backend CRUD `MetaAppsController` + OAuth controllers refatorados (FB exchange + IG authorize/callback usando MetaApp); `verify_connection` endpoint; sanitização de logs; fix do uniqueness IG | 3d | Médio | ✅ Endpoints novos não removem existentes |
| **F6** | Frontend: composable `useMetaApps`, página `MetaAppsSettings.vue`, helpers, sidebar entry, gate em `ChannelItem.vue` (com fallback pra global) | 3d | Médio | ✅ Feature flag desliga UI |
| **F7** | Job `InstagramRefreshAllJob` agendado em `config/schedule.yml` (1x/dia) percorrendo MetaApps ativas; observability + audit log | 1d | Baixo | ✅ Desativar cron |

**Total estimado:** 12.5 dias úteis (≈ 2.5 semanas) de engenharia focada + 1-2 semanas de beta antes do rollout geral.

### 15.2 Ordem cirúrgica

```
F1 ┐
   ├─→ F3 ─→ F4 ─→ Smoke staging com 1 MetaApp real
F2 ┘             ↓
                F5 ─→ F6 ─→ Beta 2-3 clínicas opt-in
                  ↓
                F7
```

### 15.3 Critérios de saída por fase

| Fase | Critério "done" |
|---|---|
| F1 | `BeclinicMetaApp.create!(...)` funciona; `app_secret` criptografado no DB (bytes binários, não plaintext); `find_by_verify_token` retorna correto; CHANGELOG.md atualizado |
| F2 | `catalog_sync_spec.rb` passa; perms aparecem no editor de role; admin pode marcar/desmarcar |
| F3 | `grep -rn "GlobalConfigService.load.*FB_APP\|INSTAGRAM_APP" app/ enterprise/` retorna **só** `credential_resolver.rb`; specs existentes de FB/IG passam |
| F4 | Spec `multi_tenant/isolation_spec.rb` verde com 2 accounts e mesmo page_id em factories; webhook cross-tenant rejeita signature |
| F5 | Clínica de teste consegue criar `BeclinicMetaApp` via API; `verify_connection` retorna OK; logs não contêm tokens em texto plano |
| F6 | Beta clínica consegue conectar FB Page do zero (sem super_admin tocar nada) usando app própria; consent screen mostra nome da clínica |
| F7 | Job roda em ambiente de staging; tokens próximos de expirar são refrescados; specs de idempotência verdes |

---

## 16. Estratégia Anti-Regressão

### 16.1 Feature flag

`social_channels:meta_apps_v1` (per-account via tabela `Features` existente do Chatwoot). Backend respeita SEMPRE o resolver (fallback global), frontend só mostra UI/composable se flag ligada. Toggle instantâneo sem restart.

### 16.2 Fallback global durante migração

Toda leitura passa por `CredentialResolver` que primeiro tenta MetaApp da Account, depois `InstallationConfig` global. Resultado: **clínicas que não configurarem nada continuam usando app do super_admin**. Migração é opt-in clínica-por-clínica.

### 16.3 Smoke tests pós-deploy (manual + dashboard de health)

- [ ] Account legacy (sem MetaApp) consegue receber mensagem FB → testa fallback global.
- [ ] Account migrada (com MetaApp) consegue receber mensagem FB → testa per-account.
- [ ] Webhook GET verify responde 401 pra token inválido.
- [ ] Webhook POST com assinatura inválida → 401.
- [ ] Webhook POST cross-tenant (page de account A com signature de account B) → 401.
- [ ] OAuth FB completo em <1min sem erro.
- [ ] OAuth IG completo em <1min sem erro.
- [ ] Frontend: card FB/IG aparece habilitado pra Account com MetaApp; desabilitado sem ambos.
- [ ] Frontend: `useMetaApps` invalida cache ao trocar de Account (verificar com 2 accounts em browser).

### 16.4 Rollout gradual

```
Semana 0  → F1-F2 prod (silencioso, sem UI exposta)
Semana 1  → F3-F4 prod + monitorar Sentry/logs (sem usuários impactados — fallback global ativo)
Semana 2  → F5 prod + endpoints disponíveis (sem UI ainda)
Semana 3  → F6 prod com flag OFF (UI build deployed mas escondida)
Semana 4  → Flag ON pra 1 clínica beta (interna Klivy)
Semana 5  → Flag ON pra 5 clínicas beta
Semana 6+ → Rollout geral
```

### 16.5 Pontos de não-quebra

- `Channel::FacebookPage`, `Channel::Instagram` schemas **não mudam** (exceto fix de uniqueness IG na F5, que é apenas relaxa restrição).
- `Channel::Whatsapp` **não é tocado**.
- `Webhooks::FacebookEventsJob` / `Webhooks::InstagramEventsJob` (parsers) **não são tocados**.
- `Facebook::SendOnFacebookService` / `Instagram::SendOnInstagramService` mudam apenas no cálculo de `appsecret_proof` (1 linha cada).
- `super_admin/app_config` continua funcional pra demais configs e como fallback.
- URL `/bot` legacy continua funcionando.

### 16.6 Auditoria por commit

Cada PR de fase precisa:
- Spec `multi_tenant/isolation_spec.rb` verde (criado na F1, ampliado em cada fase).
- Specs existentes de webhook FB/IG **integralmente** verdes — zero quebra tolerada.
- Swagger atualizado (regra AGENTS.md API docs).
- Entrada no `CHANGELOG.md` (regra obrigatória AGENTS.md).
- `grep` de tokens em logs (CI quebra se `Rails.logger.debug.*token` aparecer em diff).

---

## 17. Plano de Testes

### 17.1 Backend

| Camada | Arquivo | Cobertura mínima |
|---|---|---|
| Model | `spec/models/beclinic_meta_app_spec.rb` | Encryption funciona; verify_token gerado automaticamente; uniqueness `(account, provider)`; `for(account, provider:)`; `find_by_verify_token` (deterministic) |
| Service | `spec/services/social_channels/credential_resolver_spec.rb` | Resolve via MetaApp; fallback global quando MetaApp ausente; struct retorna `source: :meta_app` ou `:global`; nil-safe quando ambos vazios |
| Service | `spec/services/social_channels/signature_verifier_spec.rb` | HMAC válido; rejeita signature errada; rejeita app_secret vazio; constant-time compare |
| Service | `spec/services/social_channels/facebook_oauth_spec.rb` | Long-lived exchange usa app_id/secret do MetaApp; lista pages; verify_app_credentials retorna ok/error |
| Service | `spec/services/social_channels/instagram_oauth_spec.rb` | Authorize URL contém app_id correto; state JWT decodificado retorna meta_app_id correto |
| Controller | `spec/controllers/api/v1/accounts/social_channels/meta_apps_controller_spec.rb` | CRUD com perms; serializer NUNCA expõe `app_secret`; `verify_token` só pra `meta_apps_manage`; cross-account 404 |
| Controller | `spec/controllers/api/v1/accounts/social_channels/facebook_oauth_controller_spec.rb` | Exchange retorna pages; register_page cria channel + inbox; sem MetaApp → 422 |
| Webhook | `spec/controllers/webhooks/social_channels/facebook_controller_spec.rb` | GET verify match → 200 challenge; mismatch → 401; POST signature ok → enqueue job; signature ruim → 401; fallback global pra GET sem MetaApp |
| Webhook | `spec/controllers/webhooks/social_channels/instagram_controller_spec.rb` | Idem |
| Override | `spec/overrides/multi_tenant_fb_provider_spec.rb` | `app_secret_for(page_id)` resolve per-account; fallback global; warn em duplicação |
| Policy | `spec/policies/beclinic_meta_app_policy_spec.rb` | view requer perm; manage requer perm; admin bypass; non-admin sem perm → false |
| Job | `spec/jobs/social_channels/instagram_refresh_all_job_spec.rb` | Idempotente (não refresca tokens válidos); recebe account via channel; loga erros sem stack overflow |

### 17.2 Multi-tenant isolation (crítico)

`spec/plugins/social_channels/multi_tenant/isolation_spec.rb`:

```ruby
RSpec.describe 'Meta Apps multi-tenant isolation' do
  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }
  let!(:app_a) { create(:beclinic_meta_app, account: account_a, provider: 'facebook', app_secret: 'secret-A') }
  let!(:app_b) { create(:beclinic_meta_app, account: account_b, provider: 'facebook', app_secret: 'secret-B') }

  it 'never resolves account B credentials when scoped to account A' do
    expect(
      SocialChannels::CredentialResolver.call(account: account_a, provider: 'facebook').app_secret
    ).to eq('secret-A')
    expect(
      SocialChannels::CredentialResolver.call(account: account_b, provider: 'facebook').app_secret
    ).to eq('secret-B')
  end

  it 'rejects webhook signed with another account secret' do
    create(:channel_facebook_page, account: account_a, page_id: 'page-1')
    payload = { entry: [{ id: 'page-1', messaging: [...] }] }.to_json
    bad_signature = 'sha256=' + OpenSSL::HMAC.hexdigest('sha256', 'secret-B', payload)

    post '/webhooks/social/facebook',
         params: payload,
         headers: { 'X-Hub-Signature-256' => bad_signature, 'Content-Type' => 'application/json' }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'admin of account A cannot read MetaApp of account B' do
    sign_in_as_admin(account_a)
    get "/api/v1/accounts/#{account_b.id}/meta_apps"
    expect(response).to have_http_status(:not_found)
  end

  it 'serializer never exposes app_secret' do
    sign_in_as_admin(account_a)
    get "/api/v1/accounts/#{account_a.id}/meta_apps/#{app_a.id}"
    expect(response.parsed_body).not_to include('app_secret')
    expect(response.body).not_to include('secret-A')
  end

  it 'serializer hides verify_token from non-manage users' do
    user = create(:user, account: account_a)
    create(:klivy_role, account: account_a, permissions: { 'settings' => { 'meta_apps_view' => true } })
    sign_in_as(user)
    get "/api/v1/accounts/#{account_a.id}/meta_apps/#{app_a.id}"
    expect(response.parsed_body).not_to include('verify_token')
  end

  it 'GET verify webhook routes to correct MetaApp by verify_token' do
    get '/webhooks/social/facebook', params: {
      'hub.mode' => 'subscribe',
      'hub.verify_token' => app_a.verify_token,
      'hub.challenge' => 'challenge-123'
    }
    expect(response.body).to eq('challenge-123')

    get '/webhooks/social/facebook', params: {
      'hub.mode' => 'subscribe',
      'hub.verify_token' => 'wrong-token',
      'hub.challenge' => 'challenge-123'
    }
    expect(response).to have_http_status(:unauthorized)
  end
end
```

### 17.3 Frontend

| Camada | Arquivo | Cobertura |
|---|---|---|
| Composable | `spec/javascript/composables/useMetaApps.spec.js` | Cache keyed por accountId; invalida em account switch; reload force-refetch; TTL respeitado |
| Component | `spec/javascript/components/MetaAppForm.spec.js` | Validação local; submit POST; mostra erros 422; mascara app_secret existente |
| Component | `spec/javascript/components/ChannelItem.spec.js` | Card FB ativo com MetaApp; com global fallback; desabilitado sem ambos |
| Component | `spec/javascript/components/MetaWebhookHelper.spec.js` | Mostra URL correta; verify_token copy-to-clipboard funciona |

### 17.4 E2E (Cypress, se disponível)

- `/settings/integrations/meta-apps` carrega; admin cria MetaApp; helper mostra webhook URL; "Testar Conexão" funciona com mock.
- Navegação para `/settings/inboxes/new` mostra cards FB/IG habilitados após MetaApp criada.

---

## 18. Checklist de Produção

### 18.1 Segurança

- [ ] `app_secret` criptografado em repouso (`encrypts :app_secret`).
- [ ] `verify_token` criptografado (deterministic) — só lookup, nunca exposto a non-admin.
- [ ] Serializer **nunca** retorna `app_secret`.
- [ ] Logs sanitizados: rebaixar/remover `Rails.logger.debug` de [callbacks_controller.rb:25-29](../../app/controllers/api/v1/accounts/callbacks_controller.rb#L25-L29).
- [ ] State JWT (IG OAuth) assinado com `meta_app.app_secret` da Account específica.
- [ ] Validação X-Hub-Signature-256 com `ActiveSupport::SecurityUtils.secure_compare` (timing-safe).
- [ ] Rate-limit no endpoint `verify_connection` (1 req/min/account) pra evitar abuse.
- [ ] CSP + CSRF: webhooks isentos via `skip_before_action :verify_authenticity_token` (padrão Chatwoot).
- [ ] Active Record Encryption keys configuradas em produção ([config/initializers/active_record_encryption.rb](../../config/initializers/active_record_encryption.rb)).

### 18.2 Multi-tenancy

- [ ] Toda query passa por `for(account, provider:)` ou `policy_scope`.
- [ ] Rotas CRUD sob `/api/v1/accounts/:account_id/...`.
- [ ] Composables frontend keyed por `accountId` com watch.
- [ ] Webhook lookup nunca usa `.last` sem ordering determinístico.
- [ ] Spec `multi_tenant/isolation_spec.rb` verde.

### 18.3 Observabilidade

- [ ] Métrica: `social_channels.webhook.received{provider, status}` (Prometheus / Rails::Instrumentation).
- [ ] Métrica: `social_channels.webhook.signature_failed{provider}` (alerta se >0 sustentado).
- [ ] Métrica: `social_channels.oauth.completed{provider, account}`.
- [ ] Log estruturado: prefix `[SocialChannels]` + `account_id` + `provider` em todos os eventos.
- [ ] Sentry breadcrumb: page_id / instagram_id em webhook errors (sem expor tokens).
- [ ] `last_verified_at` exibido na UI; alerta visual se >7 dias.

### 18.4 Compliance e dados

- [ ] LGPD: `app_secret` faz parte do export/delete do tenant (`dependent: :destroy_async` no Account → beclinic_meta_apps).
- [ ] Audit log: criação/edição/remoção de MetaApp registrada via mecanismo de audit existente do Klivy.
- [ ] Documentação interna: runbook de "como conectar Meta App" pra time de suporte.
- [ ] Documentação user-facing: passo a passo de "como criar app na Meta Developers" pra clínica.

### 18.5 Operacional

- [ ] Job `InstagramRefreshAllJob` agendado, com idempotência.
- [ ] Migration `beclinic_meta_apps` testada em DB com volume real (poucos milhares de accounts → trivial).
- [ ] Feature flag `social_channels:meta_apps_v1` configurada e testada (on/off sem restart).
- [ ] Swagger atualizado (`plugins/social_channels/swagger/paths/meta_apps.yml` + definitions).
- [ ] CHANGELOG.md atualizado a cada PR de fase (regra AGENTS.md).
- [ ] Procfile / Docker Compose: nenhuma mudança necessária (sem novos services).
- [ ] Restart do container `sidekiq-1` após F7 (novo job).

### 18.6 Regressão

- [ ] Suite completa de webhooks Chatwoot original passa (não-quebra dos fluxos legacy).
- [ ] Clínicas em produção sem MetaApp continuam recebendo mensagens (fallback global).
- [ ] Rollback plan: revert do PR F4 restaura provider original; PRs F5-F7 deixam só features novas sem impactar legacy.

---

## 19. Anexos

### 19.1 Padrão de service entry (AGENTS.md ARCH-13)

Todos os services seguem `.call`:

```ruby
class SocialChannels::CredentialResolver
  def self.call(account:, provider:)
    new(account, provider).call
  end

  def call
    # ...
  end
end
```

### 19.2 Exemplo de CHANGELOG.md (esperado em F1)

```markdown
## [1.X.Y.Z] - 2026-XX-XXTHH:MM:SS-03:00

### feat(social_channels): Plugin de Meta Apps per-account - F1 (modelo + encryption)

**Problema:**
Configuração de Facebook/Instagram App ID/Secret/Verify Token vive em `InstallationConfig`
global do super_admin — todas as N clínicas compartilham a mesma App Meta. Sem isolamento
multi-tenant real, sem self-service.

**Solução:**
1. Criado plugin novo `plugins/social_channels/` com engine isolado.
2. Modelo `BeclinicMetaApp` (tabela `beclinic_meta_apps`) com:
   - Colunas `account_id`, `provider`, `app_id`, `app_secret`, `verify_token`,
     `api_version`, `enabled`, `human_agent_enabled`, `last_verified_at`, `metadata`.
   - Encryption: `app_secret` não-determinístico, `verify_token` determinístico (lookup).
   - Validação: `(account_id, provider)` UNIQUE; verify_token gerado SecureRandom.hex(32).
3. Specs de model + factory.

**Arquivos Modificados:**
- plugins/social_channels/lib/social_channels/engine.rb (novo)
- plugins/social_channels/lib/social_channels/version.rb (novo)
- plugins/social_channels/app/models/beclinic_meta_app.rb (novo)
- plugins/social_channels/db/migrate/2026XXXXXXXXXX_create_beclinic_meta_apps.rb (novo)
- plugins/social_channels/spec/models/beclinic_meta_app_spec.rb (novo)
- plugins/social_channels/spec/factories/beclinic_meta_apps.rb (novo)
- config/application.rb (registra plugin)
- CHANGELOG.md
```

### 19.3 Swagger de exemplo (meta_apps.yml)

```yaml
/api/v1/accounts/{account_id}/social_channels/meta_apps:
  get:
    tags: [Social Channels]
    operationId: listMetaApps
    summary: List configured Meta Apps for this account
    description: |
      Returns Facebook and Instagram MetaApp configurations for the current account.
      Requires `settings.meta_apps_view` permission. `verify_token` field only included
      for users with `settings.meta_apps_manage`. `app_secret` NEVER returned.
    parameters:
      - $ref: '#/parameters/account_id'
    responses:
      '200':
        description: List of MetaApps
        schema:
          type: array
          items:
            $ref: '#/definitions/BeclinicMetaApp'
      '401': { description: Unauthorized }
      '403': { description: Forbidden — missing settings.meta_apps_view }
  post:
    tags: [Social Channels]
    operationId: createMetaApp
    summary: Create a new Meta App for this account
    description: |
      Creates a `BeclinicMetaApp`. Requires `settings.meta_apps_manage`.
      Only one MetaApp per `(account, provider)` allowed (returns 422 on conflict).
    parameters:
      - $ref: '#/parameters/account_id'
      - in: body
        name: meta_app
        required: true
        schema:
          $ref: '#/definitions/BeclinicMetaAppCreate'
    responses:
      '201':
        description: Created
        schema: { $ref: '#/definitions/BeclinicMetaApp' }
      '403': { description: Forbidden — missing settings.meta_apps_manage }
      '422': { description: Validation error (provider already exists for account) }
```

### 19.4 Referências de código (file:line)

**Hoje (problemas a resolver):**
- [config/initializers/facebook_messenger.rb:1-20](../../config/initializers/facebook_messenger.rb#L1-L20) — `ChatwootFbProvider` global
- [app/controllers/api/v1/accounts/callbacks_controller.rb:96-101](../../app/controllers/api/v1/accounts/callbacks_controller.rb#L96-L101) — `long_lived_token` com globals
- [app/controllers/concerns/instagram_concern.rb:20-26](../../app/controllers/concerns/instagram_concern.rb#L20-L26) — `client_id`/`client_secret` globais
- [app/javascript/dashboard/components/widgets/ChannelItem.vue:18-49](../../app/javascript/dashboard/components/widgets/ChannelItem.vue#L18-L49) — gate frontend global
- [app/controllers/dashboard_controller.rb:74-77](../../app/controllers/dashboard_controller.rb#L74-L77) — exposição de globals pro frontend

**Padrões de referência:**
- [app/models/channel/whatsapp.rb:1-98](../../app/models/channel/whatsapp.rb#L1-L98) — credenciais per-channel via `provider_config` JSONB
- [app/models/channel/facebook_page.rb:25-28](../../app/models/channel/facebook_page.rb#L25-L28) — `encrypts` com guard de configuração
- [plugins/financial/lib/financial/engine.rb](../../plugins/financial/lib/financial/engine.rb) — padrão de engine isolado
- [plugins/custom_roles/lib/custom_roles/engine.rb](../../plugins/custom_roles/lib/custom_roles/engine.rb) — padrão de seed via `config.to_prepare`

**Convenções obrigatórias:**
- [AGENTS.md](../../AGENTS.md) seção "Multi-tenancy" — regras non-negotiable
- [AGENTS.md](../../AGENTS.md) seção "RBAC Klivy" — sincronização de catálogos
- [AGENTS.md](../../AGENTS.md) seção "Service Entry Methods" — padrão `.call`
- [AGENTS.md](../../AGENTS.md) seção "API docs" — swagger no mesmo PR
- [AGENTS.md](../../AGENTS.md) seção "Naming" — `Beclinic` prefix para shared
- [AGENTS.md](../../AGENTS.md) seção "CHANGELOG.md" — entrada por funcional change

### 19.5 Glossário

| Termo | Definição |
|---|---|
| **Account** | Tenant/clínica no Klivy (1 row em `accounts` table) |
| **MetaApp** | Configuração de uma app Meta (Facebook ou Instagram) per-account (`BeclinicMetaApp`) |
| **Provider** | "facebook" ou "instagram" — qual canal Meta a MetaApp configura |
| **App ID** | Identificador público da app Meta (vai pro consent screen) |
| **App Secret** | Credencial sensível usada pra OAuth exchange e webhook signature |
| **Verify Token** | Token usado no handshake GET do webhook Meta (`hub.verify_token`) |
| **Long-lived Token** | Token de acesso de longa duração (FB ~60 dias; IG renovável) |
| **Page Token** | Token específico de uma Facebook Page, usado pra enviar mensagens |
| **Instagram Business Account ID** | ID Meta da conta Instagram vinculada a uma Page (ou direto) |
| **CredentialResolver** | Service único que resolve credenciais (MetaApp → global fallback) |
| **Fallback Global** | Comportamento atual onde super_admin configura 1 app pra todas as clínicas |

---

## Resumo executivo

| Pergunta | Resposta |
|---|---|
| **Onde construir?** | Plugin novo `plugins/social_channels` (modelo `BeclinicMetaApp` + services + override do provider FB + controllers + frontend) |
| **Como armazenar?** | Tabela `beclinic_meta_apps` com `(account_id, provider)` UNIQUE; `app_secret` encrypted, `verify_token` encrypted determinístico (lookup) |
| **Como rotear webhook multi-tenant?** | URL fixa por instalação; GET verifica `verify_token` único per-account (256-bit); POST resolve `page_id → Channel → Account → MetaApp` |
| **Como não quebrar nada?** | `CredentialResolver` com precedência `MetaApp → InstallationConfig global`; feature flag pro frontend; rollout em 7 fases mergeables |
| **Como destravar os cards FB/IG?** | Composable `useMetaApps` no `ChannelItem.vue` substitui `window.chatwootConfig.fbAppId` por resolução per-account com fallback global |
| **RBAC?** | 2 perms novas sob `settings`: `meta_apps_view` e `meta_apps_manage`; espelhadas em modules.js + permissions_catalog.rb + presets |
| **Bug crítico colateral?** | `ChatwootFbProvider.access_token_for(page_id).last` corrigido para ordering determinístico + warn em duplicação |
| **Risco maior?** | Webhook signature multi-tenant — mitigado por specs `multi_tenant/isolation_spec.rb` e smoke tests pós-deploy |
| **Esforço estimado?** | 7 fases × 1-3 dias cada = **2-4 semanas** de engenharia focada (1 dev sênior backend + 1 frontend), com beta de mais 1-2 semanas |

**Próximo passo concreto:** se aprovar a direção, abrimos por F1 (plugin + model + migration + specs unitários) — entrega isolada, zero risco, valida o esqueleto antes de tocar provider de webhook.
