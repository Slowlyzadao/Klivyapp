# Internal Chat — Klivy plugin

Sistema de chat interno staff-only para clínicas. Substitui ferramentas externas (Slack, WhatsApp pessoal) com rooms, DMs, mentions, attachments, stickers customizados, e integração nativa com **Bea** (AI Agent) para notificações proativas.

## Arquitetura em 1 página

```
                ┌──────────────────────────────────────────┐
                │  Vue3 SPA — RoomList / RoomView / Mentions│
                └─────────────────┬────────────────────────┘
                                  │ Axios + ActionCable
                                  ▼
                ┌──────────────────────────────────────────┐
                │  Api::V1::Accounts::InternalChat::*       │
                │  Controllers (Pundit-gated)              │
                │  - RoomsController (CRUD + unread_summary)│
                │  - MessagesController (CRUD + favorite)  │
                │  - MembershipsController                 │
                │  - StickersController                    │
                │  - AttachmentsController, TypingController│
                └─────────────────┬────────────────────────┘
                                  │
                                  ▼
                ┌──────────────────────────────────────────┐
                │ Services / Jobs (multi-tenant scoped)    │
                │  - MessageDispatcher (cria msg + broadcast)│
                │  - BroadcastMessageJob (fan-out cable)   │
                │  - MentionExtractor (resolve @ → user_id) │
                │  - RoomCreator (DM/group + Bea)          │
                │  - SystemMessageBuilder (member_added etc)│
                │  - DataExporter (LGPD Art. 18)           │
                │  - PurgeUserDataJob (LGPD Art. 18)       │
                └──────────────────────────────────────────┘
```

## Componentes principais

| Componente | Responsabilidade |
|---|---|
| [Room](app/models/internal_chat/room.rb) | DM (kind=`direct`) ou Group (kind=`group`) — multi-tenant via account_id |
| [Membership](app/models/internal_chat/membership.rb) | Liga User/AiAgent ↔ Room. `.active` scope = `where(left_at: nil)` |
| [Message](app/models/internal_chat/message.rb) | Texto/sticker/anexo. Soft-delete (`deleted_at`) com purge de blobs |
| [Mention](app/models/internal_chat/mention.rb) | Notificação per-user. `account_id` denormalizado pra eficiência |
| [MessageDispatcher](app/services/internal_chat/message_dispatcher.rb) | Cria message + atualiza last_message_at + enfileira broadcast + mark-read-by-sender |
| [BroadcastMessageJob](app/jobs/internal_chat/broadcast_message_job.rb) | Fan-out via ActionCable pro pubsub_token de cada membro ativo |
| [Sticker](app/models/internal_chat/sticker.rb) | Custom upload (account scope) ou default Klivy (account_id NULL, visível global) |

## Domínio crítico

**Pundit policies obrigatórias em todo controller.** Cada policy:
1. Valida feature gate `internal_chat.view` (Klivy custom_roles) — fail-closed
2. Valida membership ativa quando aplicável — `.active.where(user_id: ...)`
3. Admin bypass de conta documentado e auditado (SEC-7 — log warn)

Ver [audit 2026-05-18](../../docs/audits/ai-agent-internal-chat-audit.md) seção 5 (Security/RBAC) para histórico.

## Integração com Bea (ai_agent)

- **Bea como membership AI**: `Membership` aceita `ai_agent_id` (mutuamente exclusivo com `user_id`)
- **Bea posta mensagens**: `MessageDispatcher.call(sender: bea, ...)` — `sender_ai_agent_id` setado, `sender_user_id` nil
- **Notificações de eventos**: `AiAgent::InternalNotifier::Dispatcher` posta como Bea no chat interno (templates configuráveis em `/ai_agent/templates`)

## Frontend

```
plugins/internal_chat/frontend/
├── components/         # 30+ componentes Vue3 SFC
│   ├── ChatShell.vue   # Root: sidebar + main panel
│   ├── RoomList.vue    # Lista de salas com search debounced
│   ├── RoomView.vue    # Sala aberta (header + thread + composer)
│   ├── MessageBubble.vue + messageBubbleParts/  # Decomposto FE-1
│   ├── GroupSettingsDrawer.vue + groupSettingsParts/  # Decomposto FE-2
│   └── ...
├── store/              # Vuex modules (cada um com reset action MT-14..19)
└── api/                # Axios wrappers
```

## Multi-tenancy invariants

| Recurso | Scope mechanism |
|---|---|
| Rooms | `belongs_to :account` |
| Messages | via `room.account_id` |
| Mentions | `account_id` denormalizado + validation `account_id == message.room.account_id` (MT-12) |
| StickerFavorite | `(user_id, sticker_id, account_id)` unique — same user em múltiplas contas tem favoritos próprios (MT-11) |
| Frontend Vuex stores | `reset` action em todos + watcher no ChatShell pra account-switch (MT-14..19) |
| ActionCable | `user.pubsub_token` é per-user (1 conta primária); payloads incluem `account_id` pra frontend filter |

## Testing

```bash
# Spec suite completa do plugin
docker compose exec rails bundle exec rspec plugins/internal_chat/spec

# Specs caracterizadores principais (BE-3, BE-4 do audit)
docker compose exec rails bundle exec rspec \
  plugins/internal_chat/spec/services/internal_chat/message_dispatcher_spec.rb \
  plugins/internal_chat/spec/jobs/internal_chat/broadcast_message_job_spec.rb
```

## Documentação

- [PRD chat interno](../../docs/01-product/modules/PRD-chat-interno.md) — produto, escopo, integrações
- [Audit técnico 2026-05-18](../../docs/audits/ai-agent-internal-chat-audit.md) — review enterprise
- [AGENTS.md → Multi-tenancy](../../AGENTS.md#multi-tenancy--toda-feature-roda-em-isolamento-por-account_id) — invariantes
