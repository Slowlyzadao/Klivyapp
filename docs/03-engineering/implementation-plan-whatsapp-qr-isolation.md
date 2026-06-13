# 🛠️ Plano de Implementação: Isolamento do Módulo WhatsApp QR

Este documento descreve o passo-a-passo técnico para mover a funcionalidade de **WhatsApp QR Code** (atualmente integrada ao core) para um diretório isolado em `plugins/whatsapp_qr`, seguindo a arquitetura de **Modular Monolith** do KlivyApp.

> **Status:** plano atualizado em `2026-05-07` após auditoria do estado atual do repo. Diferenças vs. versão anterior estão marcadas com **(novo)**.

---

## 1. Objetivos
- **Desacoplamento:** Garantir que o core do Chatwoot permaneça intocado para facilitar upgrades.
- **Organização:** Centralizar lógica de backend (Rails), frontend (Vue) e motor (Node.js) em um único diretório.
- **Padronização:** Seguir o modelo de Rails Engines já utilizado nos módulos `plugins/patients`, `plugins/financial`, `plugins/billing` e `plugins/migration`.

---

## 2. Levantamento de Arquivos Atuais

### 2.1. Backend Rails (a mover para o plugin)
- `app/services/whatsapp/providers/whatsapp_qr_service.rb` — 183 linhas. Service que envia mensagens para a Bridge.
- `app/services/whatsapp/incoming_message_qr_service.rb` — 402 linhas. **(novo)** Não estava listado na versão anterior do plano. Processa o payload recebido do webhook e cria mensagens no Chatwoot. **Tem que ir junto.**
- `app/controllers/webhooks/whatsapp_qr_controller.rb` — 47 linhas.

### 2.2. Modificações no core que precisam ser extraídas via `class_eval`
**(novo — esta seção foi expandida com a lista exata)**

`app/models/channel/whatsapp.rb` tem 8 pontos com lógica `whatsapp_qr` que devem ser injetadas pelo engine:
- `PROVIDERS = %w[default whatsapp_cloud whatsapp_qr].freeze` — constante congelada (ver risco em §4).
- `provider_service` — branch `elsif provider == 'whatsapp_qr'`.
- `validate_provider_config` — early-return se `whatsapp_qr`.
- `setup_webhooks` — early-return se `whatsapp_qr`.
- `perform_webhook_setup` — early-return se `whatsapp_qr`.
- `teardown_webhooks` — chama `disconnect_qr_bridge` se `whatsapp_qr`.
- `disconnect_qr_bridge` — método privado QR-only.
- `should_auto_setup_webhooks?` — early-return se `whatsapp_qr`.

`config/routes.rb:893` — `post 'webhooks/whatsapp_qr/:phone_number', to: 'webhooks/whatsapp_qr#process_payload'`. **(novo)** Decidir se vai para o engine ou fica no core (ver §3 Passo 3.4).

### 2.3. Frontend Vue (a mover)
- `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/WhatsappQR.vue` — 467 linhas. Tela de criação de inbox QR.
- `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/WhatsappQRStatus.vue` — 342 linhas. Painel de status (gera QR, mostra estado de conexão).

### 2.4. Consumidores do core (apenas atualizar import paths) **(novo)**
Não precisam ser movidos — só atualizar os imports/aliases:
- `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue:8` — `import WhatsappQR from './WhatsappQR.vue'`.
- `app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue:19` — `import WhatsappQRStatus from './channels/WhatsappQRStatus.vue'`.

Outros arquivos (`inboxMixin.js`, `dashboard/store/modules/inboxes.js`, `WhatsAppCampaignForm.vue`, `send_on_whatsapp_service.rb`, `oneoff_campaign_service.rb`, `message_window_service.rb`, `start_conversations_controller.rb`) só checam a string literal `'whatsapp_qr'`. Continuam onde estão.

### 2.5. Motor Node.js (Bridge — a mover)
Todo o conteúdo de `lib/whatsapp/` exceto `sessions/` (ver §4):
- `server.js` — 1658 linhas.
- `package.json`, `package-lock.json`.
- `Dockerfile`, `.dockerignore`.
- `whatsapp-bridge.service` (systemd unit).
- `env.docker`, `env.localhost`.
- `lid_map.json`, `channel_config.json` (estado runtime; ver §4).
- `test_fetch.mjs`, `test_send_audio_v2.mjs`.
- `bridge.log` é gerado em runtime — não mover.

### 2.6. Scripts e Procfile
- `dev-tools/scripts/start_bridge.sh` — boot da Bridge em dev.
- `dev-tools/scripts/install_bridge_service.sh` — **(novo)** instala o systemd `whatsapp-bridge.service` em VPS. Tem caminhos hard-coded que precisam ser regenerados.
- `dev-tools/scripts/register_qr.sh` — **(novo)** helper de registro/CLI.
- `Procfile.dev:5` — linha `whatsapp: ./dev-tools/scripts/start_bridge.sh`.

### 2.7. Loader de plugins (já existe — não precisa mudar) **(novo)**
`config/application.rb:59` já carrega automaticamente todo `plugins/*/lib/*/engine.rb`. Basta criar `plugins/whatsapp_qr/lib/whatsapp_qr/engine.rb` no padrão de `plugins/patients/lib/patients/engine.rb` e o Rails encontra sozinho.

---

## 3. Etapas da Implementação

### Passo 1: Criar a estrutura do plugin
```bash
mkdir -p plugins/whatsapp_qr/{lib/whatsapp_qr,app/services/whatsapp/providers,app/services/whatsapp,app/controllers/webhooks,frontend/components,engine,scripts}
```

Crie:
- `plugins/whatsapp_qr/lib/whatsapp_qr.rb` — `require 'whatsapp_qr/engine'`.
- `plugins/whatsapp_qr/lib/whatsapp_qr/engine.rb` — engine Rails (ver Passo 3).

Modelo a copiar: `plugins/patients/lib/patients.rb` + `plugins/patients/lib/patients/engine.rb`.

### Passo 2: Migrar o Motor Node.js (Bridge)
1. Mover `lib/whatsapp/*` (exceto `sessions/`, `bridge.log` e arquivos `.tmp`) para `plugins/whatsapp_qr/engine/`.
2. Mover `dev-tools/scripts/start_bridge.sh` → `plugins/whatsapp_qr/scripts/start_bridge.sh`. Atualizar `cd ./lib/whatsapp` para `cd ./plugins/whatsapp_qr/engine` dentro do script.
3. Mover `dev-tools/scripts/install_bridge_service.sh` e `register_qr.sh` para `plugins/whatsapp_qr/scripts/`. Regenerar paths.
4. **Sessões e estado runtime:**
   - **NÃO mover** `lib/whatsapp/sessions/` fisicamente. Em vez disso, parametrizar o caminho via env var `WHATSAPP_SESSIONS_DIR` no `server.js` (default: `./sessions` relativo ao engine).
   - Em produção (Easypanel) o volume `/app/storage` já está mapeado para `lib/whatsapp/sessions` — **remapear o volume** para o novo caminho do plugin OU manter `WHATSAPP_SESSIONS_DIR=/app/storage` apontando para o volume. **Sem isso, a sessão da inbox 13 some no redeploy.**
   - Idem para `lid_map.json` e `channel_config.json` — manter no diretório de sessões (volume persistente), não em `engine/`.
5. **Procfile.dev:**
   ```diff
   - whatsapp: ./dev-tools/scripts/start_bridge.sh
   + whatsapp: ./plugins/whatsapp_qr/scripts/start_bridge.sh
   ```
6. Atualizar `whatsapp-bridge.service` (`WorkingDirectory`, `ExecStart`) para apontar para o novo caminho.

### Passo 3: Migrar Lógica de Backend (Ruby)
1. Mover `app/services/whatsapp/providers/whatsapp_qr_service.rb` → `plugins/whatsapp_qr/app/services/whatsapp/providers/whatsapp_qr_service.rb`.
2. Mover `app/services/whatsapp/incoming_message_qr_service.rb` → `plugins/whatsapp_qr/app/services/whatsapp/incoming_message_qr_service.rb`. **(novo)**
3. Mover `app/controllers/webhooks/whatsapp_qr_controller.rb` → `plugins/whatsapp_qr/app/controllers/webhooks/whatsapp_qr_controller.rb`.
4. **Decisão de rota** — duas opções:
   - **(A) Mais simples:** manter `config/routes.rb:893` no core. Mudança = zero.
   - **(B) Puro:** remover do core e adicionar `routes.draw` no `engine.rb`:
     ```ruby
     initializer 'whatsapp_qr.routes', after: :add_routing_paths do |app|
       app.routes.append do
         post 'webhooks/whatsapp_qr/:phone_number', to: 'webhooks/whatsapp_qr#process_payload'
       end
     end
     ```
   Recomendado: **(A)**, porque o webhook é um endpoint público que outros plugins/serviços podem acabar referenciando.
5. **Engine.rb** — injetar a lógica `whatsapp_qr` em `Channel::Whatsapp` via `class_eval`, seguindo o padrão de `plugins/patients/lib/patients/engine.rb` (com guard `unless method_defined?`):
   ```ruby
   require 'rails/engine'

   module WhatsappQr
     class Engine < ::Rails::Engine
       isolate_namespace WhatsappQr

       config.to_prepare do
         Channel::Whatsapp.class_eval do
           # provider_service, validate_provider_config, setup_webhooks,
           # perform_webhook_setup, teardown_webhooks, disconnect_qr_bridge,
           # should_auto_setup_webhooks? — todos com guards `method_defined?`
           # para sobreviver ao hot-reload em dev.
         end
       end
     end
   end
   ```
6. **`PROVIDERS` constante** — **(novo, importante)** não tente `class_eval` em const congelada. Estratégia recomendada: **manter `'whatsapp_qr'` no array `PROVIDERS` do core** (1 string isolada não polui upgrade do Chatwoot), e mover só a lógica de despacho. Alternativa pura: `remove_const(:PROVIDERS)` + `const_set` no `to_prepare`, mas adiciona fragilidade.
7. Garantir que os paths de autoload do plugin estão registrados — o loader em `config/application.rb:59` já cobre `lib/`, mas `app/services/`, `app/controllers/` etc. dependem do Rails Engine pegar isso pelo `isolate_namespace`. Validar com `bin/rails runner 'p Whatsapp::Providers::WhatsappQrService'`.

### Passo 4: Migrar a Interface (Vue.js)
1. Mover os dois `.vue` para `plugins/whatsapp_qr/frontend/components/`.
2. **Configuração do Vite** — adicionar alias em `vite.config.ts` (próximo de `@plugins`):
   ```typescript
   '@whatsapp_qr': path.resolve(__dirname, 'plugins/whatsapp_qr/frontend'),
   ```
3. **Atualizar imports nos consumidores:** **(novo)**
   - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue:8` →
     `import WhatsappQR from '@whatsapp_qr/components/WhatsappQR.vue';`
   - `app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue:19` →
     `import WhatsappQRStatus from '@whatsapp_qr/components/WhatsappQRStatus.vue';`
4. Não há rotas de Vue Router específicas do QR — todo o fluxo está dentro de `Settings.vue`/`Whatsapp.vue`. Não precisa de `router.addRoute`.

### Passo 5: Limpeza e Validação
1. **Limpar o core:** remover do `Channel::Whatsapp` original todos os blocos `whatsapp_qr` (exceto a string em `PROVIDERS`, conforme decisão em §3.6). O resultado deve ser equivalente a um `git checkout` do upstream do Chatwoot, exceto pela linha do `PROVIDERS`.
2. **Smoke test:**
   - `overmind start` (ou `Procfile.dev`) — verificar que o processo `whatsapp:` sobe e ouve em `:3002`.
   - `bin/rails runner 'p Whatsapp::IncomingMessageQrService'` — autoload OK.
   - Abrir `/app/accounts/<id>/settings/inboxes/<inbox_qr_id>` — `WhatsappQRStatus` renderiza, QR aparece.
   - Enviar mensagem de teste de/para o número placeholder `(11) 92365-2248`.
   - Validar logs: tag `[WHATSAPP_QR]` no log Rails + `bridge.log` no diretório do engine.
3. **Validar persistência:** restartar a Bridge sem rescanear QR — sessão deve sobreviver (volume Easypanel).

---

## 4. Riscos e Mitigações

| Risco | Impacto | Mitigação |
| :--- | :--- | :--- |
| **Perder sessão WhatsApp da inbox 13 (prod)** | Usuários precisam re-escanear QR; histórico de envio/recebimento interrompe. | Antes do redeploy, copiar `sessions/13/auth_info` para o novo destino e **remapear o volume Easypanel `/app/storage`** ou setar `WHATSAPP_SESSIONS_DIR` para o caminho atual do volume. Ver memória `project_easypanel_volume_whatsapp.md`. |
| Constante `PROVIDERS` congelada | `class_eval` puro falha; tentativa de `freeze`/`remove_const` em hot-reload bagunça. | **Manter `'whatsapp_qr'` no array do core.** É 1 string e não impacta merge com upstream. |
| Erro de autoload do Engine | Falha ao iniciar Rails. | Garantir `plugins/whatsapp_qr/lib/whatsapp_qr.rb` + `engine.rb` no padrão `patients`. Loader em `config/application.rb:59` já cobre. |
| Webhook quebrar | Mensagens recebidas não chegam ao Chatwoot. | A Bridge usa `${CHATWOOT_BASE_URL}/webhooks/whatsapp_qr/...`. Manter rota no `config/routes.rb` (opção A do Passo 3.4) elimina o risco. |
| `class_eval` reaplicado em hot-reload | `NoMethodError` ou stack overflow em `super`. | Usar guard `unless method_defined?(:method_name_orig)` antes de `alias_method`, como em `plugins/patients/lib/patients/engine.rb:14`. |
| Build frontend não acha componente | `Whatsapp.vue` ou `Settings.vue` quebra após remover arquivo. | Adicionar alias `@whatsapp_qr` no Vite **antes** de mover os arquivos; rodar `bin/vite build` localmente. |
| `whatsapp-bridge.service` (systemd) com path antigo | Bridge não sobe em VPS após deploy. | Reinstalar via `install_bridge_service.sh` regenerado, ou editar `WorkingDirectory`/`ExecStart` na unit. |
| Multi-tenancy | Bridge mistura sessões entre accounts. | Bridge já isola por `inbox_id` (cada inbox pertence a 1 account). Manter — não regredir. Ver memória `feedback_multi_tenant.md`. |

---

## 5. Checklist de PR

- [ ] `plugins/whatsapp_qr/lib/whatsapp_qr/engine.rb` criado e segue padrão `patients`.
- [ ] Todos os arquivos da §2.1, §2.3, §2.5, §2.6 movidos.
- [ ] `Channel::Whatsapp` core: removidos blocos QR; `PROVIDERS` mantém a string.
- [ ] `config/routes.rb` mantém a rota (decisão A) ou engine injeta (decisão B).
- [ ] `vite.config.ts` tem alias `@whatsapp_qr`.
- [ ] 2 imports em `Whatsapp.vue` e `Settings.vue` atualizados.
- [ ] `Procfile.dev` atualizado.
- [ ] `whatsapp-bridge.service` regenerado para novo path.
- [ ] Volume Easypanel remapeado **antes** do deploy de prod.
- [ ] Smoke test: gera QR, envia, recebe, restart sem perder sessão.
- [ ] Entrada no `CHANGELOG.md` com versão bumped.
