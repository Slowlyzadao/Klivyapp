# PRD — Chat Interno (Klivy)

> **Status:** v1.1 entregue (2026-05-09) · **Owner:** Leandro · **Doc pareado:** [chat-interno.md](chat-interno.md) (plano de ação) · **Bea-related:** [ai-agent-configuration-plan.md](../ai-agent-configuration-plan.md) (Apêndice F)
>
> Este PRD é a referência viva do que existe **hoje no código** do módulo Chat Interno. Cada arquivo, endpoint, evento e decisão está mapeado. Atualize aqui sempre que tocar no plugin.

---

## 1. Visão geral

Sistema de mensagens em tempo real entre profissionais de uma mesma conta Klivy (clínica), isolado em plugin (`plugins/internal_chat/`) e desacoplado do canal de atendimento ao cliente do core.

**Casos de uso:**
- Coordenação operacional na clínica (agenda, encaminhamento, recados rápidos)
- Comunicação direta dentista ↔ recepção, financeiro, administrativo
- Anúncios para todo o time (`@todos`)
- Terreno preparado para a Bea participar e ser mencionada (Sprint Bea-Chat futuro)

**Não é:**
- Atendimento a paciente (isso continua em `Conversation` do core)
- Substituto de email ou WhatsApp interno corporativo (não tem threads, search avançada, integrações externas)
- Canal regulado por LGPD do paciente (são dados profissionais, mas há purge/export pra LGPD do colaborador)

---

## 2. Métricas de tamanho (real, conferido em 2026-05-09)

| Métrica | Valor |
|---|---|
| Arquivos novos no plugin | **89** |
| LOC Ruby (backend) | ~2.335 |
| LOC Vue (frontend) | ~4.833 |
| LOC JS (api/store/composables/routes) | ~1.478 |
| LOC CSS | ~37 |
| Tabelas Postgres novas | **10** |
| Migrations | **12** |
| Models | **10** |
| Controllers | **7** |
| Services | **11** |
| Endpoints HTTP | **36** |
| Eventos ActionCable | **7** |
| Stores Vuex | **5** |
| Componentes Vue | **23** |
| Toques no core | **6 arquivos**, todos pré-aprovados no plano de ação |

---

## 3. Arquitetura — estrutura do plugin

Plugin isolado em `plugins/internal_chat/`, espelhando convenções dos plugins existentes (`agenda`, `ai_agent`, `financial`, `patients`). Arquitetura limpa: 1 arquivo = 1 responsabilidade, separação por extensão (`.rb`, `.vue`, `.js`, `.css`).

```
plugins/internal_chat/
├── lib/internal_chat/engine.rb           # Engine Rails + injeções no Account/User
├── config/routes.rb                       # vazio (rotas no core, ver §6.1)
├── db/migrate/                            # 12 migrations
│
├── app/
│   ├── models/internal_chat/              # 10 models
│   │   ├── room.rb
│   │   ├── membership.rb
│   │   ├── message.rb
│   │   ├── attachment.rb
│   │   ├── mention.rb
│   │   ├── read_receipt.rb                # reservada (não usada hoje)
│   │   ├── sticker.rb
│   │   ├── sticker_favorite.rb
│   │   ├── message_favorite.rb
│   │   └── message_reaction.rb
│   ├── controllers/api/v1/accounts/internal_chat/
│   │   ├── rooms_controller.rb
│   │   ├── messages_controller.rb
│   │   ├── memberships_controller.rb
│   │   ├── mentions_controller.rb
│   │   ├── typing_controller.rb
│   │   ├── attachments_controller.rb       # painel arquivos + download alpha-aware
│   │   └── stickers_controller.rb
│   ├── policies/internal_chat/
│   │   ├── room_policy.rb
│   │   ├── message_policy.rb
│   │   └── sticker_policy.rb
│   ├── services/internal_chat/             # 11 services (toda a lógica de negócio)
│   │   ├── room_creator.rb
│   │   ├── message_dispatcher.rb
│   │   ├── mention_extractor.rb
│   │   ├── system_message_builder.rb
│   │   ├── room_serializer.rb
│   │   ├── message_serializer.rb
│   │   ├── sticker_serializer.rb
│   │   ├── bea_resolver.rb
│   │   ├── telemetry.rb
│   │   ├── data_exporter.rb                # LGPD
│   │   └── image_webp_converter.rb         # WebP automático no upload
│   ├── jobs/internal_chat/
│   │   ├── broadcast_message_job.rb        # ActionCable fan-out
│   │   └── purge_user_data_job.rb          # LGPD
│   └── listeners/internal_chat/
│       └── ai_agent_mention_listener.rb    # stub — Sprint Bea-Chat
│
└── frontend/
    ├── routes/routes.js
    ├── api/                                 # 7 clientes axios
    │   ├── rooms.js
    │   ├── messages.js
    │   ├── memberships.js
    │   ├── mentions.js
    │   ├── typing.js
    │   ├── attachments.js
    │   └── stickers.js
    ├── store/                               # 5 modules Vuex
    │   ├── internalChatRooms.js
    │   ├── internalChatMessages.js
    │   ├── internalChatMentions.js
    │   ├── internalChatTyping.js
    │   └── internalChatStickers.js
    ├── composables/
    │   ├── useAudioRecorder.js
    │   ├── useMentionAutocomplete.js
    │   ├── useTypingIndicator.js
    │   └── stickerImageProcessor.js
    ├── components/                          # 23 componentes Vue
    │   ├── ChatShell.vue
    │   ├── RoomList.vue
    │   ├── RoomListItem.vue
    │   ├── RoomView.vue
    │   ├── EmptyState.vue
    │   ├── NewRoomModal.vue
    │   ├── GroupSettingsDrawer.vue          # redesenhado WhatsApp-style
    │   ├── MessageThread.vue
    │   ├── MessageBubble.vue
    │   ├── MessageComposer.vue
    │   ├── MessageAttachments.vue
    │   ├── AttachmentPreviewList.vue
    │   ├── AudioMessage.vue
    │   ├── AudioRecorder.vue
    │   ├── MentionPopover.vue
    │   ├── MentionsView.vue
    │   ├── ReplyPreview.vue
    │   ├── PresenceDot.vue
    │   ├── TypingIndicator.vue
    │   ├── FavoritesPanel.vue               # mensagens favoritas
    │   ├── FilesPanel.vue                   # painel de arquivos (mídia + docs)
    │   ├── StickerPicker.vue
    │   └── StickerCreatorModal.vue
    └── styles/
        └── internal-chat.css                # animações globais (não-scoped)
```

**Padrão de naming:**
- Backend Ruby: `InternalChat::Room`, `InternalChat::Membership`, etc. (namespace explícito via `isolate_namespace`).
- Tabelas: prefixo `internal_chat_*`.
- URLs API: `/api/v1/accounts/:account_id/internal_chat/...`.
- Stores Vuex: camelCase `internalChatRooms`, etc.
- Vue routes: kebab-case `/accounts/:accountId/internal-chat/rooms/:roomId`.
- Componentes Vue: PascalCase `RoomView.vue`.
- Composables: `useX.js`.

---

## 4. Backend — inventário detalhado

### 4.1. Engine ([lib/internal_chat/engine.rb](../../../plugins/internal_chat/lib/internal_chat/engine.rb))

- `isolate_namespace InternalChat`
- `engine_name 'internal_chat'`
- Initializer `:append_internal_chat_migrations` registra `db/migrate/` do plugin no host (Rails autoload picks up).
- `config.to_prepare`:
  - `Account.class_eval` → `has_many :internal_chat_rooms, class_name: 'InternalChat::Room', dependent: :destroy_async`
  - `User.class_eval` → `has_many :internal_chat_memberships`, `has_many :internal_chat_rooms, through: :memberships`, `has_many :internal_chat_messages, foreign_key: :sender_user_id, dependent: :nullify`

### 4.2. Models

| Model | Tabela | Responsabilidade |
|---|---|---|
| `InternalChat::Room` | `internal_chat_rooms` | DM ou grupo. Belongs to account. Has many memberships, messages. Scopes: `not_archived`, `recent` (ordena por `last_message_at` qualificado, ou `created_at` como fallback). |
| `InternalChat::Membership` | `internal_chat_memberships` | Liga User OU AiAgent a Room. **XOR check constraint** garante exatamente um. Roles: `owner / admin / member`. Tem `last_read_message_id`, `muted_until`, `joined_at`, `left_at`. Validate `:exactly_one_member`. |
| `InternalChat::Message` | `internal_chat_messages` | Texto, anexos, system messages, figurinhas. `content_type ∈ {text, image, audio, video, file, system, sticker}`. JSONB `content_attributes` armazena `in_reply_to`, `mentioned_user_ids`, `mentioned_ai_agent_ids`, `system_event`, `quoted_message` (snapshot pra reply privado cross-room), `sticker_id`. `has_many :favorites, :reactions, dependent: :destroy`. Validação `content_or_attachments_present` é skip-if-deleted (pra suportar soft-delete). |
| `InternalChat::Attachment` | `internal_chat_attachments` | `has_one_attached :file` (ActiveStorage). `file_type ∈ {image, audio, video, file}`. Limite 40 MB. Aceita audio/*, image/*, video/* + lista de docs (csv, pdf, zip, doc, xls, etc). `inverse_of: :attachments` na message — sem isso a validação `belongs_to :message` falha durante autosave da message pai. |
| `InternalChat::Mention` | `internal_chat_mentions` | XOR `user_id` ou `ai_agent_id`. Scopes `unread`, `for_user`, `for_ai_agent`, `recent`. Driver do badge `@` no menu lateral e na lista de salas. |
| `InternalChat::ReadReceipt` | `internal_chat_read_receipts` | Reservado para futuro detalhamento por mensagem. **Hoje não é usada** — read tracking é via `Membership.last_read_message_id`. Tabela existe pra evolução granular. |
| `InternalChat::Sticker` | `internal_chat_stickers` | Figurinha custom. `account_id` nullable (defaults globais). Categorias livres. `has_one_attached :image`. Usada via mensagem `content_type=sticker` + `content_attributes.sticker_id`. |
| `InternalChat::StickerFavorite` | `internal_chat_sticker_favorites` | Estrela em figurinha (atalho na picker). Unique `(user_id, sticker_id)`. |
| `InternalChat::MessageFavorite` | `internal_chat_message_favorites` | Mensagem favoritada por usuário. Unique `(user_id, message_id)`. Drives painel "Favoritos" por sala. |
| `InternalChat::MessageReaction` | `internal_chat_message_reactions` | Reação emoji por usuário (1 por usuário por mensagem — WhatsApp-style). Unique `(user_id, message_id)`. Emojis canônicos: 👍 ❤️ 😂 😮 😢 🙏. |

### 4.3. Controllers (todos extendem `Api::V1::Accounts::BaseController` do core)

| Controller | Actions | Notas |
|---|---|---|
| `RoomsController` | `index`, `show`, `create`, `update`, `destroy`, `unread_summary`, `archive`, `unarchive`, `mute`, `unmute`, `update_avatar`, `remove_avatar` | `before_action :authorize_action` chama Pundit com `@room` ou classe (escolha automática). Index usa subquery em vez de `joins+distinct` pra evitar conflito Postgres com `ORDER BY COALESCE(...)`. |
| `MessagesController` | `index`, `create`, `update`, `destroy`, `mark_read`, `favorite`, `unfavorite`, `favorites`, `react`, `unreact` | Index pré-busca mensagens citadas em batch (`replied_cache`) para evitar N+1. Pré-carrega `:reactions` e passa `Current.user`/`favorited_ids` ao serializer. Edit/delete restritos ao próprio sender (ou admin da conta). `mark_read` é idempotente (skip se já lido até essa msg) e dispara broadcast `read_receipt.updated`. `react` é toggle (1 por user). `parsed_content_attributes` aceita JSON em FormData (multipart upload mantém `content_attributes`). |
| `MembershipsController` | `index`, `create`, `update`, `destroy` | `create` aceita `{ user_id }` ou `{ add_bea: true }` (atalho que resolve via `BeaResolver`). System message é emitida em todas as mudanças. |
| `MentionsController` | `index`, `mark_read`, `unread_count` | Filtro `?status=unread\|all`. `mark_read` pode aceitar `message_ids[]` ou marcar todas. Drives badge `@` por sala. |
| `TypingController` | `create` (efêmero) | Body `{ active: true \| false }`. Broadcast `typing` para todos os outros membros. Não persiste. |
| `AttachmentsController` | `index`, `download` | `index?type=media\|documents` filtra por `file_type IN (image,video)` ou `file`. `download` member action: WebP → converte e `send_data` em PNG (com alpha) ou JPG (sem alpha) via heurística `MiniMagick::Tool::Identify -format %A`; outros formatos → redirect para `file_url`. |
| `StickersController` | `index`, `create`, `destroy`, `favorite`, `unfavorite` | Lista figurinhas globais + da conta + favoritas do usuário. `create` aceita upload + categoria. `favorite` é toggle. |

### 4.4. Policies (Pundit)

| Policy | Métodos |
|---|---|
| `RoomPolicy` | `index?`, `show?`, `create?`, `update?`, `destroy?`, `unread_summary?`, `archive?`, `unarchive?`, `mute?`, `unmute?`, `update_avatar?`, `remove_avatar?`. Lógica baseada em membership ativa + role (`owner`/`admin`) + `account_user.administrator?` para bypass admin da conta. |
| `MessagePolicy` | `index?`, `create?`, `update?`, `destroy?`, `favorite?`, `react?`. `member?` checa room membership. `own_message?` para edit/delete. Favorite/react liberado para qualquer membro ativo. |
| `StickerPolicy` | `index?`, `create?`, `destroy?`, `favorite?`. Globals (`account_id IS NULL`) só lidos. Custom da conta: criar/deletar liberado para qualquer agent autenticado. Favorite por usuário. |

### 4.5. Services

| Service | Responsabilidade |
|---|---|
| `RoomCreator` | Idempotente em DM (lookup duplo via JOIN+GROUP+HAVING). Cria grupo ou DM. **Broadcast `internal_chat.room.updated` para os outros membros logo após o create** (sem isso DM nova não chega na lista do receiver). Emite telemetria `room_created`. |
| `MessageDispatcher` | Persiste msg + anexos, atualiza `last_message_at`, persiste mentions (humano e IA), invoca `AiAgentMentionListener`, enfileira `BroadcastMessageJob`, emite telemetria. |
| `MentionExtractor` | Lê `content_attributes['mentioned_user_ids']` e `'mentioned_ai_agent_ids']`. Filtra por membership ativa (anti-spam). Retorna struct `Result(user_ids, ai_agent_ids)`. |
| `SystemMessageBuilder` | Gera mensagens de sistema (`content_type=system`). Eventos: `member_added`, `member_removed`, `member_left`, `role_changed`, `renamed`, `description_changed`, `avatar_changed`. |
| `RoomSerializer` | Inclui `account_id` (filtro do cable!), `members`, `last_message`, `unread_count`, `muted_until`, `archived_at`, `avatar_url`. |
| `MessageSerializer` | Inclui `account_id`, `sender` (`is_ai` flag), `attachments` com `download_url`, `mentioned_user_ids/ai_agent_ids`, `in_reply_to_message` inline com `thumb_url` (sticker ou primeira imagem), `is_favorited`, `reactions: [{emoji, count, by_me, user_ids}]` (sorted by count desc). Aceita `current_user:`, `favorited_ids:`, `replied_cache:` (N+1 fix). |
| `StickerSerializer` | Stick assets (URL via ActiveStorage), categoria, `is_favorite_for(user)`. |
| `BeaResolver` | Acha a `Captain::Assistant` chamada "Beatriz" da conta. Constante `DISPLAY_LABEL = 'Beatriz · IA'`. |
| `Telemetry` | 6 eventos válidos: `room_created`, `message_sent`, `mention_received`, `attachment_uploaded`, `room_archived`, `room_muted`. Hoje só `Rails.logger.info` JSON; futuramente plug analytics. |
| `DataExporter` | LGPD Art. 18 — retorna `{ user_id, exported_at, rooms[], messages[], mentions_received[] }`. |
| `ImageWebpConverter` | Converte upload em WebP (quality 82) antes de persistir. Skip `image/webp` e `image/gif`. Falha → fallback ao original. Reduz ~70% no tamanho de imagens. Requer `imagemagick` no host. |

### 4.6. Jobs

| Job | Trigger | Responsabilidade |
|---|---|---|
| `BroadcastMessageJob` | `perform_later` no `MessageDispatcher` | Fan-out: para cada membro humano da sala, faz `ActionCable.server.broadcast(user.pubsub_token, message_payload)` com payload **serializado por usuário** (cada um recebe seu próprio `is_favorited`/`reactions.by_me`). Se a msg tem mention pra esse user, manda também `mention_payload`. |
| `PurgeUserDataJob` | LGPD opt-in (não automatizado ainda) | Soft-delete msgs do user, encerra memberships, deleta mentions. Idempotente. |

### 4.7. Listener

| Listener | Status |
|---|---|
| `AiAgentMentionListener` | **STUB** — Sprint 7 plantou o terreno. Hoje só `Rails.logger.info`. Quando Sprint Bea-Chat ativar, este é o ponto de integração: trocar log por `AiAgent::InternalChatRespondJob.perform_later`. |

---

## 5. Schema — tabelas Postgres

### `internal_chat_rooms`
| Coluna | Tipo | Notas |
|---|---|---|
| `id` | bigint PK | |
| `account_id` | bigint FK → `accounts(id)` ON DELETE CASCADE | indexed |
| `kind` | string | `direct \| group` |
| `name` | string | nullable em DM |
| `description` | text | grupos |
| `avatar_url` | string | grupos (legacy column; avatares novos via `has_one_attached :avatar`) |
| `created_by_user_id` | bigint | indexed |
| `last_message_at` | datetime | indexed `(account_id, last_message_at desc)` |
| `archived_at` | datetime | soft-archive |
| `created_at` / `updated_at` | datetime | |

### `internal_chat_memberships`
| Coluna | Tipo | Notas |
|---|---|---|
| `room_id` | bigint FK → rooms ON DELETE CASCADE | |
| `user_id` | bigint nullable | unique parcial `(room_id, user_id) WHERE user_id IS NOT NULL` |
| `ai_agent_id` | bigint nullable | unique parcial `(room_id, ai_agent_id) WHERE ai_agent_id IS NOT NULL` |
| `role` | string | `owner \| admin \| member` |
| `last_read_message_id` | bigint nullable | drives `unread_count` e ✓✓ |
| `muted_until` | datetime nullable | |
| `joined_at` | datetime NOT NULL | |
| `left_at` | datetime nullable | soft-leave |
| **CHECK** | `internal_chat_memberships_member_check` | `(user_id IS NOT NULL AND ai_agent_id IS NULL) OR (user_id IS NULL AND ai_agent_id IS NOT NULL)` |

### `internal_chat_messages`
| Coluna | Tipo | Notas |
|---|---|---|
| `room_id` | bigint FK ON DELETE CASCADE | |
| `sender_user_id` | bigint nullable | |
| `sender_ai_agent_id` | bigint nullable | |
| `content` | text | nullable em system msgs e anexo-only |
| `content_type` | string | `text \| image \| audio \| video \| file \| system \| sticker` |
| `content_attributes` | jsonb default `{}` | GIN index. Chaves usadas: `in_reply_to`, `mentioned_user_ids`, `mentioned_ai_agent_ids`, `system_event`, `actor_id`, `target_id`, `payload`, `quoted_message` (snapshot reply privado cross-room), `sticker_id` |
| `edited_at` | datetime nullable | |
| `deleted_at` | datetime nullable | soft-delete |
| **Index** | `(room_id, created_at desc)` | paginação |

### `internal_chat_attachments`
| Coluna | Tipo | Notas |
|---|---|---|
| `message_id` | bigint FK ON DELETE CASCADE | |
| `file_type` | string | `image \| audio \| video \| file` |
| `file_name` | string | |
| `content_type` | string | MIME (após `ImageWebpConverter`, imagens viram `image/webp`) |
| `file_size` | bigint | bytes |
| `meta` | jsonb default `{}` | reservado |
| `file` | ActiveStorage attachment | URL via `url_for`; download convertido para JPG/PNG via `AttachmentsController#download` |

### `internal_chat_mentions`
| Coluna | Tipo | Notas |
|---|---|---|
| `message_id` | bigint FK ON DELETE CASCADE | unique `(message_id, user_id)`, unique `(message_id, ai_agent_id)` |
| `user_id` | bigint nullable | indexed `(account_id, user_id, read_at)` |
| `ai_agent_id` | bigint nullable | indexed `(account_id, ai_agent_id, read_at)` |
| `account_id` | bigint NOT NULL | |
| `read_at` | datetime nullable | |
| **CHECK** | `internal_chat_mentions_target_check` | XOR de user_id e ai_agent_id |

### `internal_chat_read_receipts`
Existente mas **não usada hoje** (read tracking via `Membership.last_read_message_id`). Pronta para evolução granular.

### `internal_chat_stickers`
| Coluna | Tipo | Notas |
|---|---|---|
| `account_id` | bigint nullable | NULL = sticker global pré-instalado |
| `created_by_user_id` | bigint nullable | quem criou (custom) |
| `name` | string | label opcional |
| `category` | string | grupo livre (memes, comemorativas, etc) |
| `image` | ActiveStorage attachment | PNG/WebP recortado |

### `internal_chat_sticker_favorites`
| Coluna | Tipo | Notas |
|---|---|---|
| `user_id` | bigint NOT NULL | unique `(user_id, sticker_id)` |
| `sticker_id` | bigint FK ON DELETE CASCADE | |

### `internal_chat_message_favorites`
| Coluna | Tipo | Notas |
|---|---|---|
| `user_id` | bigint NOT NULL | unique `(user_id, message_id)` |
| `message_id` | bigint FK ON DELETE CASCADE | |
| `room_id` | bigint indexed | drives painel "Favoritos" por sala |
| `account_id` | bigint indexed | scoping multi-tenant |

### `internal_chat_message_reactions`
| Coluna | Tipo | Notas |
|---|---|---|
| `user_id` | bigint NOT NULL | unique `(user_id, message_id)` (1 reação por user por mensagem — WhatsApp-style) |
| `message_id` | bigint FK ON DELETE CASCADE | |
| `emoji` | string | livre, mas UI propõe 6 canônicos |

---

## 6. Mudanças no core (6 arquivos, todos pré-aprovados)

> Toda alteração no core foi mínima e segue exceções do `feedback_clean_architecture` (rotas, store registry, sidebar entry).

### 6.1. `config/routes.rb` (~linhas 121-168)

Adicionado bloco `namespace :internal_chat do` dentro do escopo `resources :accounts do scope module: :accounts do`. Define todos os 36 endpoints sob `/api/v1/accounts/:account_id/internal_chat/...`. **Decisão técnica:** usar `namespace` em vez de `scope :path, module:` para evitar bug Rails de path nesting com `resources :accounts only:`.

### 6.2. `app/javascript/dashboard/store/index.js`

Importa e registra **5 modules Vuex namespaced**:
```js
import internalChatRooms from '@plugins/internal_chat/frontend/store/internalChatRooms';
import internalChatMessages from '@plugins/internal_chat/frontend/store/internalChatMessages';
import internalChatMentions from '@plugins/internal_chat/frontend/store/internalChatMentions';
import internalChatTyping from '@plugins/internal_chat/frontend/store/internalChatTyping';
import internalChatStickers from '@plugins/internal_chat/frontend/store/internalChatStickers';
// modules: { ..., internalChatRooms, internalChatMessages, internalChatMentions, internalChatTyping, internalChatStickers }
```

### 6.3. `app/javascript/dashboard/routes/dashboard/dashboard.routes.js`

Importa rotas Vue do plugin e espalha no `children`:
```js
import { routes as internalChatRoutes } from '@plugins/internal_chat/frontend/routes/routes';
// children: [..., ...internalChatRoutes]
```

### 6.4. `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`

Duas adições:
1. **`SIDEBAR_NAME_TO_MODULE` (~linha 233):** `InternalChat: 'internal_chat'` — registra o módulo Klivy para gating RBAC (fail-open por padrão; granular pode ser adicionado depois).
2. **`menuItems` (~linha 477):** entrada nova entre Conversation e Captain:
   ```js
   {
     name: 'InternalChat',
     label: 'Chat interno',
     icon: 'i-lucide-messages-square',
     to: accountScopedRoute('internal_chat_home'),
     activeOn: ['internal_chat_home', 'internal_chat_room'],
     getterKeys: {
       count: 'internalChatRooms/getTotalUnread',
       badge: 'internalChatMentions/hasUnreadMentions',
     },
   }
   ```
   `count` mostra contador de não-lidos. `badge` (boolean) ativa a bolinha brand sobre o ícone quando há menção não lida — driver do indicador estilo WhatsApp.

### 6.5. `app/javascript/dashboard/helper/actionCable.js`

7 entries em `this.events` + 7 handlers no `ActionCableConnector`:
```js
'internal_chat.message.created': this.onInternalChatMessageCreated,
'internal_chat.message.updated': this.onInternalChatMessageUpdated,
'internal_chat.room.updated':    this.onInternalChatRoomUpdated,
'internal_chat.room.deleted':    this.onInternalChatRoomDeleted,
'internal_chat.mention.created': this.onInternalChatMentionCreated,
'internal_chat.read_receipt.updated': this.onInternalChatReadReceiptUpdated,
'internal_chat.typing':          this.onInternalChatTyping,
```

`onInternalChatMessageCreated` faz **3 ações** (não só dispatch):
1. `internalChatMessages/receiveFromCable`
2. Se sender ≠ usuário atual → `internalChatRooms/bumpUnread` (drives badge numérico na lista)
3. Defensive: se a sala não está em `records` → `internalChatRooms/show` (recupera DMs novas que perderam o `room.updated`)

**Crítico:** o filtro `isAValidEvent` do core compara `data.account_id === currentAccountId`, então TODO payload do plugin precisa incluir `account_id`. Enforced em todos os 7 broadcast points (ver §8).

### 6.6. `SidebarGroupLeaf.vue`

Prop opcional `mentionBadge` para renderizar bolinha brand `@` sobre o ícone quando `getterKeys.badge` é truthy. Pequeno, isolado.

---

## 7. Endpoints HTTP

Todos sob `/api/v1/accounts/:account_id/internal_chat/`:

### Rooms (11)
| Método | Path | Action | Auth |
|---|---|---|---|
| GET | `/rooms` | list (excluindo arquivadas) | qualquer membro |
| GET | `/rooms/unread_summary` | `{ data: { roomId: count }, total }` | qualquer member |
| POST | `/rooms` | create DM (idempotente) ou grupo + broadcast room.updated | qualquer user logado |
| GET | `/rooms/:id` | show | member |
| PATCH | `/rooms/:id` | update name/description (system msg auto) | owner/admin/account-admin |
| DELETE | `/rooms/:id` | destroy | creator/account-admin |
| PATCH | `/rooms/:id/archive` | soft-archive | owner/admin |
| PATCH | `/rooms/:id/unarchive` | revert | owner/admin |
| PATCH | `/rooms/:id/mute` | body `{ mute_until }` ou indefinido (~100 anos) | self |
| DELETE | `/rooms/:id/mute` | unmute | self |
| PATCH | `/rooms/:id/avatar` | upload avatar do grupo | owner/admin |
| DELETE | `/rooms/:id/avatar` | remover avatar | owner/admin |

### Messages (10)
| Método | Path | Action |
|---|---|---|
| GET | `/rooms/:room_id/messages?before_id&limit` | paginação cursor (limit 30 default, max 100) |
| POST | `/rooms/:room_id/messages` | aceita JSON ou multipart (anexos passam por `ImageWebpConverter`); retorna 201 + serialized |
| PATCH | `/rooms/:room_id/messages/:id` | edit (sender-only) |
| DELETE | `/rooms/:room_id/messages/:id` | soft-delete (sender ou account-admin) |
| POST | `/rooms/:room_id/messages/mark_read` | body `{ message_id }` |
| GET | `/rooms/:room_id/messages/favorites` | mensagens favoritadas pelo user nesta sala |
| POST | `/rooms/:room_id/messages/:id/favorite` | favoritar |
| DELETE | `/rooms/:room_id/messages/:id/favorite` | desfavoritar |
| POST | `/rooms/:room_id/messages/:id/react` | body `{ emoji }` (toggle 1-por-user) |
| DELETE | `/rooms/:room_id/messages/:id/react` | remover reação |

### Memberships (4)
| Método | Path | Action |
|---|---|---|
| GET | `/rooms/:room_id/memberships` | list |
| POST | `/rooms/:room_id/memberships` | body `{ membership: { user_id }}` ou `{ add_bea: true }` |
| PATCH | `/rooms/:room_id/memberships/:id` | change role |
| DELETE | `/rooms/:room_id/memberships/:id` | leave/kick |

### Attachments (2)
| Método | Path | Action |
|---|---|---|
| GET | `/rooms/:room_id/attachments?type=media\|documents` | listar arquivos da sala (drives FilesPanel) |
| GET | `/rooms/:room_id/attachments/:id/download` | download — converte WebP em JPG/PNG (alpha-aware) |

### Typing (1)
| Método | Path | Action |
|---|---|---|
| POST | `/rooms/:room_id/typing` | body `{ active }` (efêmero, broadcast pelos outros, 204 No Content) |

### Mentions (3)
| Método | Path | Action |
|---|---|---|
| GET | `/mentions?status=unread\|all&limit` | list pra o user atual |
| GET | `/mentions/unread_count` | `{ count }` |
| POST | `/mentions/mark_read` | body `{ message_ids: [..] }` ou vazio (todas) |

### Stickers (5)
| Método | Path | Action |
|---|---|---|
| GET | `/stickers` | lista global + da conta + favoritas (com flag `is_favorite`) |
| POST | `/stickers` | upload nova figurinha (multipart) |
| DELETE | `/stickers/:id` | remover (criador ou admin) |
| POST | `/stickers/:id/favorite` | favoritar |
| DELETE | `/stickers/:id/favorite` | desfavoritar |

**Total: 36 endpoints.**

---

## 8. Eventos ActionCable

Broadcast via `ActionCable.server.broadcast(user.pubsub_token, payload)`. **Todo payload inclui `account_id` no `data`** (filtro do `isAValidEvent` core).

| Evento | Quando | Payload `data` |
|---|---|---|
| `internal_chat.message.created` | nova msg (após Sidekiq processar `BroadcastMessageJob`) | `{ account_id, id, room_id, sender, content, content_type, content_attributes, in_reply_to_message, mentioned_user_ids, mentioned_ai_agent_ids, attachments, is_favorited, reactions, created_at, ... }` (serializado por usuário) |
| `internal_chat.message.updated` | edit/soft-delete/favorite/reaction | mesmo payload |
| `internal_chat.room.updated` | rename/add/remove member/avatar/criação de DM ou grupo | `RoomSerializer.as_json` (inclui `account_id`, `members`, `last_message`, etc) |
| `internal_chat.room.deleted` | room destruída | `{ account_id, room_id }` |
| `internal_chat.mention.created` | mention humana enfileirada com a msg | `{ account_id, room_id, message_id, mentioned_at, sender, content_preview }` |
| `internal_chat.read_receipt.updated` | user marca msg como lida | `{ account_id, room_id, user_id, last_read_message_id }` |
| `internal_chat.typing` | composer keystroke (POST /typing) | `{ account_id, room_id, user_id, user_name, active }` |

---

## 9. Frontend — fluxo de dados

```
[Usuário digita]
   ↓
MessageComposer.vue
   - useMentionAutocomplete (popover @)
   - useTypingIndicator (debounce keystroke)
   - validateAndAdd files (40 MB, 10 max)
   - StickerPicker (figurinhas + favoritas)
   - replyTarget._is_snapshot → content_attributes.quoted_message (cross-room)
   ↓
store.dispatch('internalChatMessages/send')
   ↓
api/messages.js → POST /messages (JSON ou multipart)
   ↓
[Backend: ImageWebpConverter → MessageDispatcher → BroadcastMessageJob]
   ↓
[Sidekiq processa job] → ActionCable.broadcast(token_de_cada_membro)
   ↓
[Redis pub/sub canal chatwoot_development_action_cable:<token>]
   ↓
[Puma com WebSocket aberto recebe e empurra pro browser]
   ↓
ActionCableConnector.onReceived → isAValidEvent(account_id check)
   ↓
events['internal_chat.message.created'](data)
   ↓
   ├─ store.dispatch('internalChatMessages/receiveFromCable')
   ├─ if sender ≠ self: store.dispatch('internalChatRooms/bumpUnread')
   └─ if !known_room: store.dispatch('internalChatRooms/show') ← defensive
   ↓
[Reactivity Vue] → MessageBubble.vue renderiza
```

### 9.1. Stores Vuex

| Store | Estado-chave | Getters/Actions principais |
|---|---|---|
| `internalChatRooms` | `records[]`, `unreadSummary`, `uiFlags` | `getAllRooms`, `getRoomById`, `getTotalUnread`, `getUnreadByRoom`, `getMaxOthersRead(roomId, userId)` (drives ✓✓), action `bumpUnread` (incrementa contador local sem refetch) |
| `internalChatMessages` | `byRoom: { roomId: [msgs] }`, `endOfHistory`, `pendingPrivateReply`, `uiFlags` | `getMessagesForRoom`, `isEndOfHistory`. Actions: `send`, `toggleFavorite`, `fetchFavorites`, `toggleReaction` (`applyMyReaction` pure helper), `preparePrivateReply` (snapshot via `buildQuoteSnapshot`), `consumePendingPrivateReply`, `clearPendingPrivateReply` |
| `internalChatMentions` | `records[]`, `unreadCount` | `getAll`, `getUnreadCount`, `hasUnreadMentions`, **`getUnreadCountByRoom(roomId)`** (drives badge `@` por sala) |
| `internalChatTyping` | `byRoom: { roomId: { userId: { name, expiresAt } } }` | `getTypersForRoom` (filtra expirados) |
| `internalChatStickers` | `records[]`, `favorites[]`, `uiFlags` | `getAll`, `getFavorites`, `getByCategory`. Actions: `fetch`, `create`, `destroy`, `toggleFavorite` |

### 9.2. Componentes-chave

| Componente | Responsabilidade |
|---|---|
| `ChatShell.vue` | Layout 2 colunas, header com botão "Nova" e badge `@`, monta NewRoomModal sob demanda. |
| `RoomList.vue` + `RoomListItem.vue` | Lista com busca, preview da última msg, contador, dot de presença, menu contextual com mute/archive. **Badge `@` ao lado do contador numérico** quando há menções não lidas. |
| `RoomView.vue` | Header com presença + botão settings, MessageThread, TypingIndicator, MessageComposer, GroupSettingsDrawer. DM star button abre FavoritesPanel. Consome `pendingPrivateReply` no load. |
| `MessageThread.vue` | Lista virtualizada (virtual scroll nativa), agrupamento por dia, scroll-to-bottom on new, jump-to-message com flash highlight. |
| `MessageBubble.vue` | Render por content_type (system = pílula central, normal = balão, sticker = imagem solta). **Chevron-on-hover** abre dropdown com Responder, Responder no particular, Conversar com [nome], Reagir (emoji row), Favoritar, Editar, Apagar. Reactions row no menu + badges abaixo da mensagem (fundo branco puro). Reply embed clicável (com thumb_url), attachments, ✓/✓✓, badge IA pra Bea, menções destacadas. Snapshot reply via `quotedSnapshot` computed. |
| `MessageAttachments.vue` | Render por tipo. Detecção de mp4 audio-only via `loadedmetadata` (videoHeight === 0) → AudioMessage. Video lightbox WhatsApp-style (white backdrop) com Avatar + nome + download/X. Usa `download_url \|\| file_url`. |
| `AudioMessage.vue` | Layout 2 linhas: `[avatar \| play \| waveform]` + tempo indentado. |
| `MessageComposer.vue` | Textarea auto-grow, drag-and-drop, file picker, AudioRecorder, MentionPopover, StickerPicker, ReplyPreview. Roteia replyTarget snapshot vs id. |
| `NewRoomModal.vue` | Aba DM ou Grupo, busca de membros, multi-select. |
| `GroupSettingsDrawer.vue` | **Redesenhado WhatsApp-style.** Hero (avatar 120px + nome inline-edit + descrição), quick links (Arquivos, Favoritos, Mídia), members list inline com badges ADMIN/CRIADOR, danger zone Sair/Excluir. Sub-views `files` e `favorites` com botão back. |
| `MentionsView.vue` | Filtro Não lidas/Todas, click leva pra mensagem original. |
| `MentionPopover.vue` | Renderiza humanos, Bea (badge IA), e item especial **Todos** (quando grupo com 2+ humanos). |
| `FavoritesPanel.vue` | Lista mensagens favoritadas da sala (DM e grupo) + botão desfavoritar. |
| `FilesPanel.vue` | Sub-tabs Imagens/Vídeos × Documentos. Grid 3 cols com thumbs lazy. Lightbox white-backdrop com img/video/iframe (PDF). |
| `ReplyPreview.vue` | Texto + nome + thumbnail 40×40 quando há sticker/imagem (`thumb_url`). |
| `StickerPicker.vue` | Painel deslizante com tabs Recentes/Favoritas/Categorias + busca + criar nova. |
| `StickerCreatorModal.vue` | Upload imagem → `stickerImageProcessor` (crop + remove background opcional) → POST. |

### 9.3. Composables

- **`useMentionAutocomplete.js`** — detecta `@<termo>` no caret; gerencia query, highlightedIndex, sets de `insertedUserIds` / `insertedAiAgentIds` / `insertedAll` flag. `collectInsertedIds()` valida quais ainda persistem no texto antes do envio (apaga `@João` → id é descartado). `@todos` expande para todos os humanos da sala no envio.
- **`useTypingIndicator.js`** — debounce: 1ª keystroke envia `active=true`, renova a cada 4s, envia `active=false` após 3s sem teclas ou no envio/unmount.
- **`useAudioRecorder.js`** — wrapper sobre MediaRecorder API. Detecta melhor mimeType por navegador (Chrome/Firefox: webm/opus, Safari: mp4). Cleanup automático no unmount. Limite hard 5 min.
- **`stickerImageProcessor.js`** — pré-processamento de figurinhas no client (resize, crop quadrado, opcional remoção de fundo).

---

## 10. Permissões e segurança

### 10.1. Camadas
1. **Multi-tenant**: todas queries começam em `Current.account.internal_chat_rooms` ou `InternalChat::X.where(account_id: Current.account.id)`. Vazamento entre contas é impossível.
2. **Membership guard**: `RoomPolicy#show?` exige membership ativa (`left_at IS NULL`). `MessagePolicy` herda.
3. **Role guard**: gestão de grupo (rename, add/remove member, avatar) só `owner` ou `admin` (ou bypass `account_user.administrator?`).
4. **Auto-saída**: usuário sempre pode `DELETE /memberships/:self_id` independente do role.
5. **Edit/delete de mensagem**: só sender (ou bypass admin).
6. **Reactions/Favorites**: qualquer membro ativo da sala.

### 10.2. Validações de segurança
- Anexos: 40 MB max, MIME whitelist (image/*, audio/*, video/*, lista de docs do core).
- Imagens: convertidas para WebP automaticamente no upload (`ImageWebpConverter`); download volta a JPG/PNG via heurística de canal alpha.
- Mentions: `MentionExtractor` filtra usuários e Bea para apenas membros ativos da sala (anti-spam, anti-tagged-out-of-room).
- Soft-delete preserva `deleted_at` (mensagens apagadas viram placeholder "Mensagem apagada").
- Hard-delete só via admin da conta (DELETE /rooms ou DELETE /messages com bypass).
- Stickers: validação MIME (image/*) e tamanho. Globais (`account_id IS NULL`) são read-only.

### 10.3. RBAC Klivy
- Módulo registrado em `SIDEBAR_NAME_TO_MODULE`: `InternalChat: 'internal_chat'`.
- Hoje fail-open (qualquer agent autenticado vê o item de menu). Granular vai ser adicionado quando houver capacidades específicas (ex: `internal_chat:create_group`).

### 10.4. LGPD
- **Export** (Art. 18 portabilidade): `InternalChat::DataExporter.call(user:)` retorna hash JSON-serializável com rooms, messages, mentions recebidas. Plug em endpoint admin futuro.
- **Purge** (Art. 18 apagamento): `InternalChat::PurgeUserDataJob.perform_later(user_id)`. Soft-deleta msgs (preserva coerência dos grupos), encerra memberships, deleta mentions. Idempotente.
- **Ainda não automatizado**: hook quando `User` é destruído. Adicionar quando houver fluxo de remoção de colaborador.

---

## 11. Telemetria

Service centralizado: `InternalChat::Telemetry.track(event, payload)`. Hoje só `Rails.logger.info` JSON com prefixo `[InternalChat::Telemetry]`. Plug analytics depois sem mexer call sites.

| Evento | Disparado em | Payload |
|---|---|---|
| `room_created` | `RoomCreator#create_direct/_group` | `account_id, room_id, kind, members` |
| `message_sent` | `MessageDispatcher#call` | `account_id, room_id, message_id, content_type, has_mentions, is_reply, attachments` |
| `mention_received` | `BroadcastMessageJob` (por user mencionado) | `account_id, room_id, message_id, user_id` |
| `attachment_uploaded` | `MessageDispatcher#call` (1 por anexo) | `account_id, room_id, file_type, size_kb` |
| `room_archived` | `RoomsController#archive` | `account_id, room_id` |
| `room_muted` | `RoomsController#mute` | `account_id, room_id, user_id` |

---

## 12. Bugs reais corrigidos durante desenvolvimento

> Documento aqui para que ninguém repita quando estender o módulo.

| # | Sintoma | Causa raiz | Fix |
|---|---|---|---|
| 1 | POST mensagem com anexo retornava 422 ("Attachments é inválido") | `belongs_to :message` rodava validação antes da Message ter id, durante autosave | `inverse_of: :attachments` em ambos os lados + `autosave: true` explícito no `has_many` |
| 2 | GET /rooms 500 — `PG::AmbiguousColumn: created_at` | Scope `recent` não qualificava a tabela; JOIN com memberships causava ambiguidade | Qualificar com `internal_chat_rooms.last_message_at`/`internal_chat_rooms.created_at` no `Arel.sql` |
| 3 | GET /rooms 500 — `PG::InvalidColumnReference: DISTINCT + ORDER BY COALESCE(...)` | Postgres rejeita `DISTINCT` com `ORDER BY` de expressão fora do SELECT | Trocar `joins+distinct` por subquery `where(id: Membership.pluck(:room_id))` |
| 4 | GET /rooms/:id 500 — NoMethodError em `RoomPolicy#show?` | `check_authorization(InternalChat::Room)` passava a CLASSE; `show?` precisa do registro pra checar membership | `authorize_action` que escolhe `@room` ou classe conforme action |
| 5 | NoMethodError pra `archive?`, `unarchive?`, `mute?`, `unmute?` no Pundit | Métodos não definidos na policy | Adicionados |
| 6 | Soft-delete e LGPD purge falhavam com "mensagem precisa de conteúdo ou anexo" | Validação `content_or_attachments_present` rodava em update mesmo quando setando `deleted_at` + `content: nil` | `unless: :deleted_at?` |
| 7 | **Real-time não funcionava** — mensagens não chegavam pro outro user, ✓✓ não atualizava | **Dois bugs combinados:** (a) Sidekiq travado com 0 workers e 85+ jobs entupidos; (b) payload do cable sem `account_id`, filtro `isAValidEvent` do core descartava | Restart Sidekiq + adicionar `account_id` em todos os 5 payloads de cable |
| 8 | Routes URL `/internal_chat/accounts/:account_id/...` em vez de `/accounts/.../internal_chat/...` | `scope :path, module:` reposiciona path na frente em alguns nestings | Trocar por `namespace :internal_chat` |
| 9 | Imagens não carregavam (broken icon) após adicionar WebP | `MiniMagick::Error: You must have ImageMagick or GraphicsMagick installed` | `brew install imagemagick`; `Attachment#thumb_url` rescue StandardError; `<img>` fallback com `@error` |
| 10 | mp4 audio-only renderizava `<video>` 300×150 vazio | Element `<video>` tem default size para audio-only; sem heurística no client | `loadedmetadata` handler detecta `videoHeight === 0` → switch para `AudioMessage` |
| 11 | Waveform desalinhado com botão play | Flex items-center centralizava coluna inteira (waveform+time) | Restructurar para `flex flex-col`: row1 `[avatar \| play \| waveform]`, row2 `<p>` time com `pl-[100px]` |
| 12 | FormData com `content_attributes` JSON-stringified perdia chaves | Rails parseia FormData direto, não decodifica JSON | Helper `parsed_content_attributes` no controller que tenta `JSON.parse` se for string |
| 13 | DM nova não chegava no receiver | `RoomCreator` não broadcastava `room.updated` para outros membros — receiver tinha o cable mas room nunca entrava em `records` | Adicionar `broadcast_to_other_members` em `create_direct` e `create_group` + defensive `internalChatRooms/show` no `onInternalChatMessageCreated` |

---

## 13. Como testar

### 13.1. Suíte E2E automatizada (legacy /tmp/)

Dois scripts em `/tmp/` (do desenvolvimento original):
- `e2e_internal_chat.rb` — 48 asserts cobrindo services (criação de salas, mensagens, mentions, reply, anexos, áudio, read receipts, memberships, system messages, Bea, mute, archive, telemetria, LGPD, N+1 cache, validações XOR).
- `e2e_http.rb` — 32 asserts cobrindo controllers + routing + auth (todos os endpoints, permissões, edit cross-user negado).

```bash
bundle exec rails runner /tmp/e2e_internal_chat.rb   # → PASS: 48 / FAIL: 0
bundle exec rails runner /tmp/e2e_http.rb            # → PASS: 32 / FAIL: 0
```

> **Nota:** scripts cobrem o escopo v1.0. Features pós-v1.0 (favoritos, reações, stickers, reply privado, painel arquivos, WebP) ainda não têm cobertura E2E formal — testes manuais documentados em §13.4.

### 13.2. Smoke test real-time

WebSocket cliente programático conectado ao cable + dispara mensagem via runner → confirma evento `internal_chat.message.created` chega ao cliente em <1s. Comando documentado no histórico de troubleshooting.

### 13.3. Dependências de runtime
- **Sidekiq deve estar rodando** processando a fila `default`. Sem isso, broadcasts nunca saem (BroadcastMessageJob fica enfileirado).
- **Redis disponível** — usado por ActionCable adapter (`config/cable.yml` → `redis`) e por Sidekiq.
- **Puma com cable mounted** (default no Chatwoot).
- **ImageMagick instalado no host** — necessário para `ImageWebpConverter` e `AttachmentsController#download` (alpha detection).

### 13.4. Testar manualmente no browser
1. Login com 2 usuários em abas separadas.
2. Item "Chat interno" entre Conversas e BEA no menu lateral.
3. Botão lápis → Nova conversa (DM ou Grupo).
4. Composer:
   - Texto + Enter envia
   - `@` abre popover (humanos + "Todos" + Bea se membro)
   - Drag-and-drop arquivo → imagens viram WebP no servidor
   - Mic → grava → preview → envia
   - Botão sticker → picker com favoritas, categorias, criar nova
5. Mensagem chega na outra aba em real-time, ✓ vira ✓✓ quando lida; lista de salas mostra contador 1, 2, …, 99+.
6. Hover na msg → chevron → menu Responder / Responder no particular / Reagir / Favoritar / Editar / Apagar.
7. Reagir abre row de 6 emojis; reaction badge aparece abaixo da msg (fundo branco).
8. "Responder no particular" navega pra DM com a pessoa e pré-preenche o composer com o quote snapshot.
9. Engrenagem do header (em grupo) → drawer WhatsApp-style → quick links Arquivos / Favoritos.
10. Item `@` no header da sidebar → vista de menções; badge `@` na lista de salas quando há menção pendente.

---

## 14. O que NÃO está implementado (registro)

Funcionalidades **fora de escopo da v1.1** com motivo:

| Feature | Por quê | Onde retomar |
|---|---|---|
| **Notificações Web** (Browser Notification API quando aba está em background) | Mexe com `onMessageCreated` do core, não estava no escopo aprovado. | PR isolado, ~50 linhas. |
| **Bea notificar grupo Recepção** (Pipeline A — agendamento pendente confirmação) | Spec definida em Apêndice F (D-25). Templated, não-LLM. Aguarda Sprint Bea-Chat 1. | Apêndice F.2 do `ai-agent-configuration-plan.md` |
| **Bea responder quando mencionada** (Pipeline B — `@beatriz` no chat interno) | Spec definida em Apêndice F (D-24). LLM com prompt enxuto. Aguarda Sprint Bea-Chat 2. Listener stub já existe. | Apêndice F.3 do `ai-agent-configuration-plan.md` |
| **Threads aninhadas** (reply em árvore) | Hoje só 1 nível de reply. Suficiente pro caso de uso. | Backlog. |
| **Mensagens efêmeras / autodestrutivas** | Não solicitado. | — |
| **Chamadas de voz/vídeo** | Fora do escopo de mensageria. | — |
| **Search dentro do chat** (full-text) | Backlog. PostgreSQL tem GIN index nas colunas certas. | — |
| **RSpec backend** | Ambiente de specs do Chatwoot precisa de wiring extra para autoload de `plugins/internal_chat/spec/`. Suíte E2E em `/tmp/` cobre v1.0; v1.1 só manual. | Habilitar quando for fazer CI. |
| **E2E Cypress/Playwright** | Backend coberto v1.0; UI testes manuais no momento. | Backlog. |
| **Performance benchmark** com 1k msgs × 50 salas × 10 online | Indices certos foram criados; benchmark formal não rodado. | Antes de deploy em produção com >100 colaboradores. |
| **Granularidade RBAC** (`internal_chat:create_group`, etc) | Hoje fail-open. Adicionar quando admin pedir limitação. | — |
| **Notificação push mobile** | Sem app mobile nativo Klivy ainda. | — |

> **Itens removidos desta lista** (entregues na v1.1): reações com emoji, figurinhas, favoritar mensagem, painel de arquivos, reply privado cross-room, conversão WebP automática.

---

## 15. Decisões arquiteturais (por que assim e não de outro jeito)

### 15.1. Modelos próprios vs reuso de `Conversation`/`Message` do core
**Decisão:** modelos próprios.
**Trade-off considerado:** `Conversation`+`Message` do core têm toda a infra (broadcast, attachments, mentions). Reusar pareceria barato.
**Por quê não:** `Conversation` exige `contact_id` e participa de status workflow (`open/resolved/...`), SLA, CSAT, assignee. Forçaria `Contact` fantasma por user e poluiria relatórios. Custo de divergência futura > custo de duplicar 6 modelos.

### 15.2. Broadcast pelo `pubsub_token` do user (não por `room_id`)
**Decisão:** fan-out N broadcasts (1 por membro humano).
**Trade-off considerado:** stream `room_<id>` único e cliente subscrever por sala visitada.
**Por quê fan-out:** o cliente precisa receber updates de TODAS as suas salas (badge unread, lista) sem subscribe explícito. O `pubsub_token` do user é universal e já existe pro core. Custo: N publishes em vez de 1, mas N tipicamente <10. Permite ainda **payload por usuário** (cada um vê seu próprio `is_favorited`, `reactions.by_me`).

### 15.3. `account_id` em todo payload
**Decisão:** obrigatório em `data` de todo evento `internal_chat.*`.
**Por quê:** o `ActionCableConnector` do core tem filtro `isAValidEvent(data) → data.account_id === currentAccountId`. Sem isso, eventos do plugin são silenciosamente descartados. **Aprendido na dor** (bug #7).

### 15.4. Sem ActionCable channel customizado
**Decisão:** reusar `RoomChannel` do core.
**Por quê:** o `RoomChannel` já faz `stream_from pubsub_token` no subscribe. Criar channel próprio dobraria conexões WebSocket por usuário sem ganho. Trade-off: dependência implícita do core; documentada aqui.

### 15.5. ActiveStorage própria (não usar `Attachment` do core)
**Decisão:** model `InternalChat::Attachment` separado.
**Por quê:** `Attachment` do core tem `belongs_to :message` apontando pra `Message` do core. Reuso causaria mistura de namespaces e quebraria o isolamento do plugin. Custo: 1 model + 1 migration extras. Vale.

### 15.6. Bea como `Captain::Assistant` (não criar entidade nova)
**Decisão:** `BeaResolver.for_account` resolve `Captain::Assistant.find_by(name: 'Beatriz')`.
**Por quê:** Bea já existe no core como Assistant pré-instalada. Criar uma `AiAgent::Persona` paralela duplicaria estado e ficaria fora de sincronia.

### 15.7. Mention de IA em tabela compartilhada
**Decisão:** `internal_chat_mentions` com XOR `user_id` ou `ai_agent_id`.
**Trade-off considerado:** tabela separada `internal_chat_ai_mentions`.
**Por quê compartilhada:** mentions têm shape idêntico (message + recipient + read_at). Tabela separada custaria duplicar índices, controllers, scopes. XOR check garante consistência.

### 15.8. Sidekiq pra broadcast (vs síncrono no controller)
**Decisão:** `BroadcastMessageJob.perform_later`.
**Trade-off considerado:** `ActionCable.broadcast` direto no controller (síncrono).
**Por quê async:** N publishes podem custar 50-200ms para grupos grandes; bloquear a request do sender é UX ruim. Custo: dependência do Sidekiq estar rodando (ver bug #7 — aprendizado).

### 15.9. Reply privado via snapshot (não via `in_reply_to` cross-room)
**Decisão:** "Responder no particular" copia um snapshot do conteúdo da mensagem original em `content_attributes.quoted_message` na mensagem nova (em outra sala/DM).
**Trade-off considerado:** estender `in_reply_to` para aceitar `message_id` de outra sala.
**Por quê snapshot:** o serializer e a UI assumem que `in_reply_to` aponta pra uma msg da MESMA sala (`replied_cache` é por room). Cross-room exigiria expansão da query/serializer + permission check de leak (e se a pessoa não é membro da sala original?). Snapshot resolve sem novo modelo de permissão, é resiliente a delete da original e é como o WhatsApp faz forward com quote.

### 15.10. WebP automático no upload
**Decisão:** `ImageWebpConverter` chamado antes de criar a `InternalChat::Attachment`.
**Trade-off considerado:** servir WebP só no get (mantendo JPG/PNG no storage) ou conversão lazy.
**Por quê eager + storage WebP:** reduz custo de storage em ~70% e CDN/bandwidth. Heurística no `download` reverte (PNG se alpha, JPG se não), atendendo a expectativa do usuário de baixar formato "normal". Skip de WebP/GIF preserva animações e formatos que não convertem bem.

### 15.11. 1 reação por usuário por mensagem (não múltiplas)
**Decisão:** unique `(user_id, message_id)` em `message_reactions`.
**Trade-off considerado:** Slack-style permitir várias reações por user.
**Por quê WhatsApp-style:** padrão visual do produto é WhatsApp. Reações múltiplas geram complexidade de UI (stack vs row, contador por emoji × user). Toggle simples com 1 ativo por user é suficiente e mais legível.

---

## 16. Versão e governança

- **Versão atual:** 1.1 (entregue 2026-05-09)
- **v1.0:** entregue 2026-05-08 — Sprints 1–8 do plano original
- **v1.1:** entregue 2026-05-09 — features WhatsApp-style:
  - Reações com emoji (👍 ❤️ 😂 😮 😢 🙏)
  - Favoritar mensagem + painel Favoritos por sala
  - Figurinhas (stickers globais e custom + favoritas)
  - Reply privado cross-room (via snapshot)
  - Painel de Arquivos (mídia + documentos) com lightbox
  - Conversão WebP automática + download alpha-aware (JPG/PNG)
  - GroupSettingsDrawer redesenhado WhatsApp-style
  - Badge `@` na lista de salas
  - Avatar de grupo
  - Fix delivery em DM nova (broadcast `room.updated` pós-create)
- **Sprints concluídos:** 1–8 (v1.0) + entrega contínua v1.1
- **Doc pareado:** [docs/01-product/modules/chat-interno.md](chat-interno.md) (plano original)
- **Doc Bea integration:** [docs/01-product/ai-agent-configuration-plan.md](../ai-agent-configuration-plan.md) Apêndice F
- **Próxima revisão:** quando ativar Bea-Chat, implementar item da §14, ou iniciar v1.2.

Toda mudança neste módulo dispara update em:
- Este PRD (sempre)
- `chat-interno.md` se mudar plano
- PRD principal (`docs/01-product/PRD.md`) se afetar comportamento visível
- `ai-agent-configuration-plan.md` Apêndice F se mexer em Bea-Chat
