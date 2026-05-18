# Chat Interno — Plano de Ação

> Módulo de comunicação interna entre profissionais da clínica (dentistas, recepcionistas, financeiro, administrativo) integrado à plataforma Klivy. Convive lado a lado com os módulos existentes (Conversas, Agenda, Pacientes, Financeiro) e permite que a IA agêntica (Bea) também participe das conversas.
>
> **Status:** Sprints 1–8 concluídos (v1.0 entregue 2026-05-08) · **Owner:** Leandro

---

## 1. Objetivo

Permitir que **usuários internos** de uma mesma conta Klivy (clínica) conversem entre si em tempo real, com:

- **Mensagens 1:1** e **grupos** (com seleção de participantes).
- **Mensagens** de texto, imagem, áudio, vídeo e arquivo.
- **Menções** (`@usuário`) com badge dedicado no menu lateral (estilo WhatsApp).
- **Resposta a mensagem** (quote / reply).
- **Presença online** (online / ocupado / offline) e indicador "digitando…".
- **Leitura/recibo** (✓ enviado, ✓✓ entregue/lido).
- **Não-lidos** com contador no item de menu lateral.
- **IA agêntica (Bea)** como participante de primeira classe — pode mencionar e ser mencionada, deixando o terreno preparado para ações automáticas (ex.: atribuição de conversa) sem que essa lógica seja escopo desta entrega.

> ⚠️ **Inegociáveis:** arquitetura limpa em plugin isolado, separação por extensão (`.rb`, `.vue`, `.js`, `.css`), nunca alterar o core sem permissão explícita, reutilização máxima de componentes existentes.

---

## 2. Decisão de Arquitetura: novo plugin, modelos próprios

### 2.1. Por que não reaproveitar `Conversation` / `Message` do core

O sistema herdado de Chatwoot tem `Conversation` + `Message` + `Inbox` + `Channel::*` desenhados para **atendimento ao cliente**: cada `Conversation` exige `contact_id`, pertence a uma `Inbox` de canal externo (WhatsApp, Email, API…) e carrega um workflow de status (`open / pending / resolved / snoozed`), assignee, teams, labels, SLA. Empurrar mensagens internas entre profissionais nesse modelo:

- Polui semântica de relatórios (CSAT, SLA, contadores de conversa).
- Força um `Contact` fantasma por usuário (quebra lógica de pacientes).
- Mistura permissões de chat-com-paciente com chat-interno.
- Dificulta extensões futuras (presence rica, threads, reações).

### 2.2. Decisão

Criar um **plugin novo `internal_chat`** com modelos próprios, mas **reutilizando ao máximo** a infraestrutura compartilhada:

| Componente core reutilizado | Como |
|---|---|
| **ActionCable** ([app/channels/room_channel.rb](../../../app/channels/room_channel.rb)) | Novo evento `internal_chat.message.created` no mesmo `pubsub_token` por usuário. |
| **OnlineStatusTracker** ([lib/online_status_tracker.rb](../../../lib/online_status_tracker.rb)) | Reaproveitamos o set Redis já existente — usuários internos já são tracked. |
| **ActiveStorage** ([app/models/attachment.rb](../../../app/models/attachment.rb)) | Cópia do padrão (model próprio `InternalChat::Attachment`) para isolar. |
| **Pundit** | Policies dedicadas em `app/policies/internal_chat/`. |
| **Componentes Vue** (Avatar, Modal, Button, TextArea, Spinner) | Ver §6.4. |
| **Sidebar do plugin AI Agent** como referência de injeção | Ver §6.1. |

### 2.3. Estrutura do plugin (espelha `agenda` / `ai_agent`)

```
plugins/internal_chat/
├── app/
│   ├── builders/internal_chat/             # MessageBuilder
│   ├── controllers/api/v1/accounts/internal_chat/
│   │   ├── rooms_controller.rb
│   │   ├── memberships_controller.rb
│   │   ├── messages_controller.rb
│   │   └── attachments_controller.rb
│   ├── jobs/internal_chat/
│   │   ├── broadcast_message_job.rb        # ActionCable broadcast assíncrono
│   │   └── notify_mentioned_users_job.rb
│   ├── listeners/internal_chat/
│   │   └── ai_agent_mention_listener.rb    # ouve mention p/ Bea (terreno)
│   ├── models/internal_chat/
│   │   ├── room.rb
│   │   ├── membership.rb
│   │   ├── message.rb
│   │   ├── mention.rb
│   │   ├── attachment.rb
│   │   └── read_receipt.rb
│   ├── policies/internal_chat/
│   │   ├── room_policy.rb
│   │   ├── membership_policy.rb
│   │   └── message_policy.rb
│   └── services/internal_chat/
│       ├── room_creator.rb
│       ├── message_dispatcher.rb
│       ├── mention_extractor.rb
│       └── presence_query.rb
├── config/
│   ├── locales/pt_BR.yml
│   └── routes.rb                            # vazio; rotas vão no core (ver §3.3)
├── db/migrate/
│   ├── YYYYMMDDHHMMSS_create_internal_chat_rooms.rb
│   ├── ..._create_internal_chat_memberships.rb
│   ├── ..._create_internal_chat_messages.rb
│   ├── ..._create_internal_chat_mentions.rb
│   ├── ..._create_internal_chat_attachments.rb
│   └── ..._create_internal_chat_read_receipts.rb
├── lib/
│   └── internal_chat/
│       └── engine.rb                        # injeções no Account/User
├── frontend/
│   ├── api/
│   │   ├── rooms.js
│   │   ├── messages.js
│   │   └── presence.js
│   ├── components/
│   │   ├── ChatLayout.vue                   # split panel: lista + thread
│   │   ├── RoomList.vue
│   │   ├── RoomListItem.vue
│   │   ├── MessageThread.vue
│   │   ├── MessageBubble.vue
│   │   ├── MessageComposer.vue
│   │   ├── MentionPopover.vue
│   │   ├── ReplyPreview.vue
│   │   ├── AttachmentUploader.vue
│   │   ├── AudioRecorder.vue
│   │   ├── PresenceDot.vue
│   │   ├── NewRoomModal.vue                 # criar 1:1 ou grupo
│   │   └── GroupSettingsDrawer.vue
│   ├── composables/
│   │   ├── useInternalChat.js
│   │   ├── useMessageDraft.js
│   │   ├── useMentionAutocomplete.js
│   │   └── useTypingIndicator.js
│   ├── store/
│   │   ├── internalChatRooms.js
│   │   ├── internalChatMessages.js
│   │   ├── internalChatMentions.js
│   │   └── internalChatPresence.js
│   ├── routes/
│   │   └── routes.js
│   ├── styles/
│   │   └── internal-chat.css                # animações globais (não-scoped)
│   └── utils/
│       └── mention-parser.js
└── swagger/
    ├── definitions/
    └── paths/
```

---

## 3. Backend

### 3.1. Modelos e schema

Convenção de tabelas: prefixo `internal_chat_` (igual a `agenda_*`, `ai_agent_*`).

#### `internal_chat_rooms`
| coluna | tipo | nota |
|---|---|---|
| `id` | bigint | PK |
| `account_id` | bigint | FK, escopo multi-tenant |
| `kind` | string | `direct` (1:1) ou `group` |
| `name` | string | nullable em direct (derivado dos membros) |
| `description` | text | grupos |
| `avatar_url` | string | grupos |
| `created_by_user_id` | bigint | FK users |
| `last_message_at` | datetime | denormalizado p/ ordenação |
| `archived_at` | datetime | soft-archive |
| `timestamps` | | |

Index: `(account_id, last_message_at desc)`, `(account_id, kind)`.

Para `direct`, garantimos unicidade de par via constraint sobre `internal_chat_memberships` (par hash). Service `RoomCreator` faz lookup → reusa room existente.

#### `internal_chat_memberships`
| coluna | tipo | nota |
|---|---|---|
| `id` | bigint | |
| `room_id` | bigint | FK |
| `user_id` | bigint | FK users (nullable se for IA — ver §3.2) |
| `ai_agent_id` | bigint | nullable (Bea / outras IAs no futuro) |
| `role` | string | `owner / admin / member` |
| `last_read_message_id` | bigint | p/ contagem de não-lidos |
| `muted_until` | datetime | |
| `joined_at` / `left_at` | datetime | |

Constraint: exatamente um de `user_id` ou `ai_agent_id` preenchido. Unique `(room_id, user_id)` e `(room_id, ai_agent_id)`.

#### `internal_chat_messages`
| coluna | tipo | nota |
|---|---|---|
| `id` | bigint | |
| `room_id` | bigint | FK |
| `sender_user_id` | bigint | FK users (nullable) |
| `sender_ai_agent_id` | bigint | nullable |
| `content` | text | |
| `content_type` | string | `text / image / audio / video / file / system` |
| `content_attributes` | jsonb | `{ in_reply_to: <message_id>, mentions: [user_id...], duration_ms, … }` |
| `edited_at` | datetime | |
| `deleted_at` | datetime | soft-delete (mantém placeholder na thread) |
| `timestamps` | | |

Index: `(room_id, created_at desc)`, GIN em `content_attributes`.

#### `internal_chat_mentions`
| coluna | tipo |
|---|---|
| `message_id` | bigint FK |
| `user_id` | bigint FK |
| `read_at` | datetime |

Unique `(message_id, user_id)`. Driver dos badges no menu (`@`).

#### `internal_chat_attachments`
Espelha [app/models/attachment.rb](../../../app/models/attachment.rb): `message_id`, `file_type` (`image / audio / video / file`), metadados JSONB, `has_one_attached :file` (ActiveStorage). Limite 15 anexos por mensagem (mesmo do core).

#### `internal_chat_read_receipts`
| coluna | tipo |
|---|---|
| `message_id` | bigint FK |
| `user_id` | bigint FK |
| `read_at` | datetime |

Atualizado em batch quando o usuário rola/abre a conversa.

### 3.2. Engine e injeções no core

[`plugins/internal_chat/lib/internal_chat/engine.rb`](../../../plugins/internal_chat/lib/internal_chat/engine.rb) seguirá padrão de [agenda/engine.rb](../../../plugins/agenda/lib/agenda/engine.rb):

```ruby
module InternalChat
  class Engine < Rails::Engine
    isolate_namespace InternalChat

    config.to_prepare do
      Account.class_eval do
        has_many :internal_chat_rooms, class_name: 'InternalChat::Room', dependent: :destroy_async
      end

      User.class_eval do
        has_many :internal_chat_memberships, class_name: 'InternalChat::Membership', dependent: :destroy_async
        has_many :internal_chat_rooms, through: :internal_chat_memberships, source: :room
      end

      # Bea (AiAgent) também participa
      AiAgent::Setting.class_eval do
        has_many :internal_chat_memberships, class_name: 'InternalChat::Membership',
                 foreign_key: :ai_agent_id, dependent: :destroy_async
      end if defined?(AiAgent::Setting)
    end
  end
end
```

Carregamento automático (já existente no core): `config/application.rb` faz `Dir[Rails.root.join('plugins/*/lib/*/engine.rb')].each { |f| require f }`.

### 3.3. Rotas (no `config/routes.rb` do core — convenção observada)

Como agenda/ai_agent já registram rotas no `config/routes.rb` raiz (engines não isolam rotas), seguiremos o mesmo padrão. **Esta é a única edição mínima de core**, e o usuário deve aprovar antes da execução:

```ruby
namespace :api do
  namespace :v1 do
    resources :accounts, only: [] do
      namespace :internal_chat do
        resources :rooms do
          resources :memberships, only: [:index, :create, :destroy]
          resources :messages do
            resources :attachments, only: [:index, :create, :destroy]
            member { post :react }
          end
          collection { get :unread_summary }
        end
        resources :presence, only: [:index]
        resources :mentions, only: [:index]
      end
    end
  end
end
```

URLs resultantes: `/api/v1/accounts/:account_id/internal_chat/rooms`, `…/rooms/:id/messages`, etc.

### 3.4. Serviços

- **`InternalChat::RoomCreator`** — cria/encontra `direct` ou cria `group`, idempotente.
- **`InternalChat::MessageDispatcher`** — orquestra: persiste `Message` → extrai menções → cria attachments → enfileira `BroadcastMessageJob` e `NotifyMentionedUsersJob` → atualiza `last_message_at` da room.
- **`InternalChat::MentionExtractor`** — parseia `@user-id` ou `@bea` no conteúdo (formato canônico: `<mention data-user-id="42">@João</mention>` no rich text, ou tokens em texto puro).
- **`InternalChat::PresenceQuery`** — wrapper sobre `OnlineStatusTracker.get_available_users(account_id)` filtrando para membros das salas do usuário corrente.

### 3.5. Real-time (ActionCable)

Reaproveitar `RoomChannel` existente. Dois eventos novos no payload broadcast:

```ruby
# em InternalChat::BroadcastMessageJob
recipients = message.room.memberships.where.not(user_id: nil).pluck(:user_id)
User.where(id: recipients).find_each do |user|
  ActionCable.server.broadcast(
    user.pubsub_token,
    {
      event: 'internal_chat.message.created',
      data: InternalChat::MessageSerializer.new(message).serializable_hash,
    },
  )
end
```

Eventos:

| Evento | Quando |
|---|---|
| `internal_chat.message.created` | nova mensagem |
| `internal_chat.message.updated` | edição/soft-delete |
| `internal_chat.mention.created` | menção (driver do badge `@`) |
| `internal_chat.read_receipt.updated` | recibo de leitura |
| `internal_chat.typing` | indicador "digitando" (broadcast leve, não persistido) |
| `internal_chat.room.updated` | mudança de membro/nome do grupo |

`presence.update` (que já existe) é reaproveitado para online/offline.

### 3.6. Permissões (Pundit + RBAC Klivy)

Convenção observada (ver `feedback_clean_architecture` e `project_rbac_settings_audit`):

- **Módulo Klivy:** `internal_chat` (entrada nova em `SIDEBAR_NAME_TO_MODULE` da [Sidebar.vue](../../../app/javascript/dashboard/components-next/sidebar/Sidebar.vue#L230)).
- **Capacidades por role** (sugestão inicial — admin habilita por role):
  - `internal_chat:view` — ver e enviar em DMs e grupos onde é membro.
  - `internal_chat:create_group` — criar grupos.
  - `internal_chat:manage_group` — adicionar/remover membros, renomear (só donos/admins do grupo + admins da conta).
  - `internal_chat:delete_any_message` — moderação (admin da conta).
- **Policies em [`plugins/internal_chat/app/policies/internal_chat/`](../../../plugins/internal_chat/app/policies/internal_chat/)**: `RoomPolicy` (member-of check), `MessagePolicy` (sender-only para edit/delete + override admin), `MembershipPolicy`.

---

## 4. Frontend

### 4.1. Stack (segue a do projeto)

- **Vue 3 + Composition API + `<script setup>`**.
- **Vuex** (não Pinia ainda — convenção).
- **Tailwind inline** com tokens `n-slate-*`, `n-brand`, `woot-*` (ver `feedback_styling`). Nada de `var(--color-...)` que não exista.
- **Vite alias** `@plugins` já configurado.

### 4.2. Rotas Vue

```js
// plugins/internal_chat/frontend/routes/routes.js
export const routes = [
  {
    path: 'internal-chat',
    component: ChatShell,
    meta: { permissions: ['administrator', 'agent'] },
    children: [
      { path: '', name: 'internal_chat_home', component: EmptyState },
      { path: 'rooms/:roomId', name: 'internal_chat_room', component: RoomView, props: true },
      { path: 'mentions', name: 'internal_chat_mentions', component: MentionsView },
    ],
  },
];
```

Importadas em [dashboard.routes.js](../../../app/javascript/dashboard/routes/dashboard/dashboard.routes.js) (mesma forma que agenda/financial).

### 4.3. Stores Vuex (namespaced)

- `internalChatRooms` — lista de salas, ordenadas por `last_message_at`, com unread count e last preview.
- `internalChatMessages` — paginação por room (cursor `before_id`), cache com `Map(roomId → messages[])`.
- `internalChatMentions` — lista plana de menções não lidas (driver do badge `@` no menu).
- `internalChatPresence` — estende a presença que já existe; getter `isUserOnline(userId)`.

Cada store registra seus listeners em `actionCable.js` via composable `useInternalChat()` montado no `App.vue` (ou no `ChatShell` para evitar tocar o core — ver §6.1).

### 4.4. Componentes principais

| Componente | Responsabilidade |
|---|---|
| `ChatShell.vue` | layout 2 colunas: `RoomList` + `<router-view/>`. |
| `RoomList.vue` | lista de salas + busca + botão "Nova conversa/grupo". |
| `RoomListItem.vue` | linha com avatar, nome, último preview, badge não-lidos, dot de presença. |
| `MessageThread.vue` | lista virtualizada (recyclerView) de `MessageBubble`, scroll-to-bottom on new, agrupamento por dia. |
| `MessageBubble.vue` | balão estilo WhatsApp; props: `message`, `isOwn`, `showAvatar`, `replyTarget`. Renderiza menções com `<a>` clicável. |
| `MessageComposer.vue` | textarea + botão anexo + gravação áudio + emoji + reply preview + autocomplete de menção. |
| `MentionPopover.vue` | flutua acima do composer ao digitar `@`, lista membros + Bea. |
| `ReplyPreview.vue` | mostra mensagem citada acima do input (e dentro do bubble). |
| `AttachmentUploader.vue` | drag & drop + preview thumbnails antes do send. |
| `AudioRecorder.vue` | MediaRecorder API → blob → upload (formato `audio/webm`). |
| `PresenceDot.vue` | bolinha verde/amarela/cinza. |
| `NewRoomModal.vue` | escolher 1:1 (selecionar 1 user) ou grupo (selecionar N + nome). |
| `GroupSettingsDrawer.vue` | gerir membros, renomear, sair, arquivar. |

### 4.5. Reuso de componentes core

| Necessidade | Componente core a reutilizar |
|---|---|
| Botão | [`shared/components/Button.vue`](../../../app/javascript/shared/components/Button.vue) |
| Modal | [`dashboard/components/Modal.vue`](../../../app/javascript/dashboard/components/Modal.vue) |
| Avatar | [`dashboard/components-next/avatar/Avatar.vue`](../../../app/javascript/dashboard/components-next/avatar/Avatar.vue) |
| Textarea | [`shared/components/TextArea.vue`](../../../app/javascript/shared/components/TextArea.vue) |
| Spinner | [`shared/components/Spinner.vue`](../../../app/javascript/shared/components/Spinner.vue) |

Componentes do composer de conversa (`ReplyTo`, anexos) **não** são reutilizados diretamente — a UI do core é fortemente acoplada a `Conversation/Message`. Replicamos o look-and-feel, não os componentes.

### 4.6. UX-chave

- **Atalhos:** `Ctrl/Cmd+K` abre seletor de salas (já há padrão em CommandBar do core); `Esc` cancela reply; `Shift+Enter` quebra linha; `Enter` envia.
- **Scroll behavior:** ao abrir room, scroll no bottom; ao receber mensagem nova com scroll fora do bottom, mostrar "↓ N novas mensagens".
- **Notificações:** Web Notification API (já presente no core para conversas) — replicar quando aba está em background.
- **Mobile:** Sidebar already collapsa; o painel de chat ocupa full-width em telas `< md`.

### 4.7. i18n

`plugins/internal_chat/config/locales/pt_BR.yml` para textos backend (erros, mailers se houver). No frontend, seguindo a convenção observada nos plugins existentes, **strings em PT-BR diretas** nos componentes (sem vue-i18n por enquanto), exceto labels reaproveitados que já existem em `app/javascript/dashboard/i18n/locale/pt_BR/`.

---

## 5. Sidebar — integração visual

### 5.1. Item de menu lateral

Adicionar entrada em [`Sidebar.vue` linhas ~230 e ~373](../../../app/javascript/dashboard/components-next/sidebar/Sidebar.vue#L230) — **edição mínima de core, requer aprovação**:

```js
// SIDEBAR_NAME_TO_MODULE
InternalChat: 'internal_chat',
```

```js
// menuItems (posição: entre Conversation e Captain/Bea)
{
  name: 'InternalChat',
  label: t('SIDEBAR.INTERNAL_CHAT'),
  icon: 'i-lucide-messages-square',
  to: accountScopedRoute('internal_chat_home'),
  activeOn: ['internal_chat_home', 'internal_chat_room', 'internal_chat_mentions'],
  getterKeys: {
    count: 'internalChatRooms/getTotalUnread',
    badge: 'internalChatMentions/hasUnreadMentions', // boolean → renderiza ícone @
  },
},
```

### 5.2. Badge de menção (`@`)

`SidebarGroupLeaf.vue` já suporta `count`. Para o **ícone `@`** (estilo WhatsApp), precisaremos estender `getterKeys` com `badge` boolean OU passar slot custom. Decisão: adicionar prop opcional `mentionBadge` ao componente `SidebarGroupLeaf` — um pequeno tweak de core também sujeito a aprovação. Ao clicar, navegar para `/internal-chat/mentions`, view dedicada listando todas as menções não lidas, agrupadas por sala, com botão "Ir para mensagem" que pula para o anchor `message-<id>`.

---

## 6. Pontos de toque no core (e nada além disso)

Resumo único do que precisa ser editado no core, **com aprovação prévia**:

1. **`config/routes.rb`** — adicionar bloco `namespace :internal_chat` (§3.3). Padrão já existente para agenda/ai_agent.
2. **`app/javascript/dashboard/routes/dashboard/dashboard.routes.js`** — espalhar `internalChatRoutes` (padrão já existente).
3. **`app/javascript/dashboard/store/index.js`** — registrar 4 modules Vuex (padrão já existente).
4. **`app/javascript/dashboard/components-next/sidebar/Sidebar.vue`** — adicionar entry em `SIDEBAR_NAME_TO_MODULE` e `menuItems` (§5.1).
5. **`app/javascript/dashboard/helper/actionCable.js`** — registrar 5 novos event handlers (`internal_chat.*`). Alternativa mais limpa: composable `useInternalChat()` que se auto-inscreve no `cable.consumer` exposto pelo módulo, **sem editar `actionCable.js`**. Preferência: alternativa B (zero core edit).
6. **`SidebarGroupLeaf.vue`** — prop opcional `mentionBadge` (§5.2). Pequeno; aprovar.

Tudo o resto vive em `plugins/internal_chat/`.

---

## 7. IA agêntica (Bea) — terreno preparado, **sem implementar comportamento**

Esta entrega **não** inclui automações da Bea (atribuir conversa, agendar, etc.). Apenas garante que o modelo de dados e as filas suportam:

- **Bea como sender:** `internal_chat_messages.sender_ai_agent_id` populado quando a Bea fala. UI renderiza com avatar especial e label "Bea · IA". Configuração da persona/comportamento da Bea continua no `InstallationConfig['CAPTAIN_BEA_SYSTEM_PROMPT']` via `/super_admin/bea`, conforme `feedback_bea_system_prompt`.
- **Bea como mencionada:** `@bea` no composer aciona `mentions` com `ai_agent_id` ao invés de `user_id`. Listener `InternalChat::AiAgentMentionListener` (vazio por enquanto, só log) ouvirá o evento e, em entregas futuras, despachará para o pipeline existente em `plugins/ai_agent/app/services/ai_agent/chat_service.rb`.
- **Bea entra/sai de salas:** `Membership` com `ai_agent_id`. Por padrão, a Bea só entra em salas onde for explicitamente convidada.

> Quando o comportamento for implementado, a referência será `docs/01-product/ai-agent-configuration-plan.md` (decisões D-13 a D-23). Esta entrega só prepara contratos.

---

## 8. Segurança e privacidade

- **Multi-tenant:** todos os queries com `account_id` no escopo. `Current.account` na controller base já existe.
- **Member-of guard:** `RoomPolicy#show?` exige membership ativa; `MessagePolicy` herda.
- **Anexos:** validação MIME + tamanho (40 MB, igual ao core), antivírus quando configurado (mesmo pipeline que `Attachment` core já usa, se ativo).
- **Soft delete:** mensagens deletadas viram placeholder ("Mensagem apagada"); admin de conta pode hard-delete via job.
- **Auditoria:** se `audit-trail` (Paper Trail) já estiver habilitado para `Account/User`, **não** versionar `internal_chat_messages` por padrão (volume + privacidade); apenas `Room` e `Membership`.
- **LGPD:** export per-user e delete-on-request no `db_purge` job que já existe — adicionar shoulds para tabelas novas.

---

## 9. Performance e escala

- **Paginação** de mensagens com cursor `before_id` (índice `(room_id, created_at desc)`).
- **N+1**: `MessageSerializer` precarrega `sender`, `attachments`, `mentions`.
- **Broadcast em job** (`BroadcastMessageJob`) — nunca síncrono.
- **Read receipts em batch** — debounce frontend de 1s, payload `[{ message_id: ..., }]`.
- **`last_message_at` denormalizado** em `Room` evita `MAX(created_at)` na listagem.
- **Typing indicator** não persistido (Redis pubsub TTL 5s).

---

## 10. Telemetria

Eventos para analytics existente:
- `internal_chat.room.created` (`kind`).
- `internal_chat.message.sent` (`content_type`, `has_mentions`, `is_reply`).
- `internal_chat.mention.received`.
- `internal_chat.attachment.uploaded` (`file_type`, `size_kb`).

---

## 11. Plano de entrega — sprints

> Tamanho de cada PR: **máx 3 arquivos modificados no core + N arquivos novos no plugin**. Inegociável (`feedback_clean_architecture`).

### ✅ Sprint 1 — Esqueleto e mensagens 1:1 de texto (MVP) — concluído 2026-05-08
- [ ] Engine `internal_chat` + migrations (`rooms`, `memberships`, `messages`, `read_receipts`).
- [ ] Models, policies, controllers `RoomsController#index/show/create`, `MessagesController#index/create`.
- [ ] Service `RoomCreator`, `MessageDispatcher` (sem attachments ainda).
- [ ] `BroadcastMessageJob` + handler frontend (composable, **sem tocar `actionCable.js`**).
- [ ] Stores `internalChatRooms` + `internalChatMessages`.
- [ ] Componentes: `ChatShell`, `RoomList`, `RoomListItem`, `MessageThread`, `MessageBubble`, `MessageComposer` (texto puro).
- [ ] Item de menu lateral + permissão `internal_chat:view`.
- [ ] Testes RSpec (models + policies + controllers) e Vitest (stores).

### ✅ Sprint 2 — Grupos e gestão de membros — concluído 2026-05-08
- [ ] `RoomCreator` para `kind=group`.
- [ ] `MembershipsController` + `NewRoomModal` + `GroupSettingsDrawer`.
- [ ] Permissão `internal_chat:create_group` e `manage_group`.
- [ ] Mensagens de sistema (`content_type=system`): "Fulano entrou", "renomeou para X".

### ✅ Sprint 3 — Anexos (imagem/vídeo/arquivo) — concluído 2026-05-08
- [ ] `internal_chat_attachments` + `AttachmentsController`.
- [ ] `AttachmentUploader` (drag & drop, multi-upload, preview).
- [ ] Renderização em `MessageBubble` (lightbox p/ imagem, player nativo p/ vídeo).
- [ ] Validação tamanho/MIME.

### ✅ Sprint 4 — Áudio e gravação — concluído 2026-05-08
- [ ] `AudioRecorder` (MediaRecorder API).
- [ ] Player com waveform leve (sem libs pesadas — `<audio controls>` por enquanto).

### ✅ Sprint 5 — Menções, reply e mentions view — concluído 2026-05-08
- [ ] `internal_chat_mentions` + `MentionExtractor`.
- [ ] `MentionPopover` + parser no composer.
- [ ] Reply via `content_attributes.in_reply_to` + `ReplyPreview`.
- [ ] Badge `@` no menu (com tweak em `SidebarGroupLeaf`).
- [ ] View `/internal-chat/mentions`.

### ✅ Sprint 6 — Presença, leitura, typing — concluído 2026-05-08 (notificações Web ficaram para follow-up)
- [ ] `PresenceQuery` + `PresenceDot` em `RoomListItem` e header da sala.
- [ ] Recibo de leitura (✓✓), incluindo broadcast `read_receipt.updated`.
- [ ] Indicador "digitando…" (broadcast efêmero).
- [ ] Notificações Web (background).
- [ ] Mute por sala, arquivar.

### ✅ Sprint 7 — Bea como participante (terreno, sem comportamento) — concluído 2026-05-08
- [ ] `Membership.ai_agent_id` + `sender_ai_agent_id`.
- [ ] Renderização especial no bubble.
- [ ] `@bea` no autocomplete + `AiAgentMentionListener` (no-op com log).
- [ ] Documentação em `docs/01-product/ai-agent-configuration-plan.md` apontando para o evento.

### ✅ Sprint 8 — Hardening — concluído 2026-05-08 (E2E e perf real ficaram para follow-up)
- [ ] LGPD: export/delete jobs.
- [ ] Telemetria.
- [ ] E2E (Cypress / Playwright) cobrindo fluxos chave.
- [ ] Auditoria de performance (1k mensagens em sala, 50 salas, 10 usuários online).

---

## 12. Riscos e mitigações

| Risco | Mitigação |
|---|---|
| Volume de broadcast satura ActionCable em contas grandes | Broadcast por room (não por usuário) quando viável; coalescer typing events |
| Anexos grandes estourando ActiveStorage | Limites, presigned URLs S3 quando configurado |
| Mensagens fora-de-ordem em rede instável | `client_id` UUID por mensagem + dedupe no store |
| Bea spamar canal interno no futuro | Rate limit por `ai_agent_id` (já existe pattern em `ai_agent/llm/`) |
| Drift de UX vs. WhatsApp (expectativa do usuário) | Revisão de UX por sprint contra checklist de paridade no §1 |

---

## 13. Fora de escopo desta entrega

- Reações com emoji (👍, ❤️, …) — backlog.
- Threads (reply em árvore) — só reply 1-nível por enquanto.
- Mensagens efêmeras / autodestrutivas.
- Chamadas de voz/vídeo.
- Comportamento ativo da Bea no chat (atribuição automática etc.) — só preparação de modelo.
- Integração com Conversas externas (encaminhar mensagem do paciente para o chat interno).

---

## 14. Follow-ups pós-v1 (entregues separadamente)

- **Notificações Web** quando aba está em background — mexe com `onMessageCreated` do core. Implementação curta mas merece PR isolado.
- **E2E (Cypress/Playwright)** cobrindo: criar DM, criar grupo, mandar texto, mandar anexo, mencionar, responder, mute, archive, leitura ✓✓.
- **RSpec backend** para `MessageDispatcher`, `RoomCreator`, `MentionExtractor`, `BroadcastMessageJob` — esqueleto preparado mas o ambiente RSpec do Chatwoot precisa de wiring extra para autoload de `plugins/internal_chat/spec/`.
- **Performance benchmark** com seed de 1k mensagens × 50 salas × 10 usuários online — validar paginação, broadcast cost, presence interval.
- **Reações com emoji** (👍❤️) — backlog priorizado.
- **Threads aninhadas** (reply em árvore) — hoje só 1 nível.
- **Comportamento ativo da Bea** (atribuir conversa, agendar) — ver Apêndice F do `ai-agent-configuration-plan.md`.

---

## 15. Aprovações necessárias antes de codar (histórico)

1. ✅ Aprovação do **plano** (este documento).
2. ⏳ Aprovação dos **6 pontos de toque no core** listados em §6.
3. ⏳ Aprovação do **nome do módulo** Klivy (`internal_chat`) e das **capacidades RBAC** (§3.6).
4. ⏳ Aprovação da decisão de **modelos próprios** (não reusar `Conversation/Message`) — §2.

Após aprovação, executo Sprint 1 fim-a-fim (migrations, restart Rails, validação visual) e devolvo para teste no browser.
