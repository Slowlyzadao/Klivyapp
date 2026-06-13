# Internal Chat — Realtime & Integração Bea

Documentação da camada **realtime** (ActionCable) e da **integração com a Bea**
do plugin `internal_chat`. Cobre o que o OpenAPI/REST **não** documenta: o
modelo de transporte de eventos, o catálogo de eventos `cable` com seus
payloads, e os dois pipelines da Bea (resposta a `@beatriz` e notificações
internas proativas).

Para a visão geral do plugin (modelos, controllers REST, multi-tenancy), ver
[README.md](../README.md). Esta doc é complementar — assume o vocabulário de
lá (`Room`, `Membership`, `Message`, `Mention`, `MessageDispatcher`,
`BeaResolver`).

---

## 1. Modelo de transporte

O chat interno **não** tem channel ActionCable dedicado. Ele **reaproveita** o
canal genérico do core que cada usuário já assina no login.

### 1.1. Como funciona

- Todo `User` tem um `pubsub_token` único (concern `Pubsubable`,
  `app/models/concerns/pubsubable.rb`). Esse token é o **stream name** do
  ActionCable: o cliente faz `stream_from pubsub_token` ao conectar, e fica
  inscrito enquanto estiver logado.
- Os broadcasts do internal_chat são feitos **por usuário**, não por sala:
  ```ruby
  ActionCable.server.broadcast(user.pubsub_token, payload)
  ```
  Ou seja, o fan-out de uma mensagem de sala é traduzido em N broadcasts
  individuais (um para o token de cada membro ativo).
- Não há `InternalChatChannel` / `RoomChannel` próprio. O comentário no
  `BroadcastMessageJob` diz "reaproveita o RoomChannel existente" — isso se
  refere ao canal genérico do core que faz `stream_from pubsub_token`, não a um
  channel específico do plugin.

### 1.2. Por que por-usuário e não por-sala

- **Multi-tenancy**: `pubsub_token` é per-user (1 conta primária por usuário).
  Por isso **todo payload de evento carrega `account_id`** no `data` — o
  `ActionCableConnector` do frontend (core) filtra eventos por `account_id`
  antes de despachar para os handlers Vuex. Sem o `account_id`, um usuário em
  múltiplas contas receberia eventos cruzados.
- **Estado por-usuário**: vários eventos precisam de um payload **diferente por
  destinatário** (ex.: `is_favorited` e `by_me` em reações são estado
  per-user). O fan-out por-usuário permite serializar com `current_user: user`
  individualmente.

### 1.3. `UserBroadcaster` — o helper central de fan-out

`InternalChat::UserBroadcaster`
(`app/services/internal_chat/user_broadcaster.rb`) centraliza o pattern
repetido em controllers/jobs/services. Faz **1 SQL** (`User.where(id: ids)
.find_each`) + iteração + broadcast. Duas APIs:

| API | Quando usar |
|---|---|
| `UserBroadcaster.call(user_ids:, payload:)` | Payload **idêntico** para N users (ex.: `typing`, `read_receipt`, `room.deleted`). |
| `UserBroadcaster.each(user_ids:) { \|user\| ... }` | Payload **varia por user** (serializer com `current_user: user`) ou múltiplos broadcasts por user (ex.: `message.created` + `mention.created`). |

Opções:

- `isolate: true` — envolve cada entrega em `rescue StandardError` (logado como
  `warn`). Garante que a falha de **um** destinatário (token quebrado,
  ActionCable transient down, Redis blip) **não** derruba a entrega aos demais.
  Usado em room destroy / room.updated (padrão "RT-3"). Por padrão (`isolate:
  false`) os erros propagam (Sidekiq faz retry em jobs; controllers retornam
  500).
- `log_tag:` — prefixo do log de falha isolada.

Retorna a contagem de entregas bem-sucedidas (`delivered`).

### 1.4. Resiliência de enqueue

`MessageDispatcher` persiste a mensagem **dentro de uma transação** e só
**depois** (fora da transação) enfileira `BroadcastMessageJob.perform_later`,
com `rescue` (BE-11): se a fila (Redis/Sidekiq) estiver fora, a mensagem **já
está gravada**; o broadcast falhar não pode dar rollback no save. O frontend
reconcilia via `fetch` ao reabrir a sala. Implicação para quem consome cable: a
entrega realtime é **best-effort**; a fonte de verdade é sempre o REST.

---

## 2. Catálogo de eventos

Todos os eventos têm o shape de envelope:

```jsonc
{ "event": "internal_chat.<nome>", "data": { ... } }
```

E todo `data` contém `account_id` (filtro de tenant no frontend). Os shapes de
`data` abaixo são derivados diretamente dos serializers/controllers — são a
verdade do código.

### 2.1. `internal_chat.message.created`

- **Quando dispara**: ao criar uma mensagem nova, via
  `BroadcastMessageJob` (enfileirado pelo `MessageDispatcher` após persistir).
  Vale para mensagens de humanos **e** da Bea (toda mensagem passa pelo
  dispatcher).
- **Quem recebe**: todos os membros **ativos** da sala (`memberships.active`,
  `left_at IS NULL`), incluindo o próprio sender. Membros AI (Bea) são
  ignorados no fan-out (`where.not(user_id: nil)`).
- **Payload** (`data`): o `MessageSerializer.as_json` completo:

```jsonc
{
  "id": 123,
  "account_id": 7,
  "room_id": 45,
  "sender": {
    "id": 9,                 // user.id OU sender_ai_agent_id (Bea)
    "name": "Maria Silva",   // ou "Beatriz · IA" para a Bea
    "avatar_url": "https://...",
    "is_ai": false           // true para a Bea
  },
  "content": "texto da mensagem",
  "content_type": "text",    // text | sticker | image | video | audio | file | system
  "content_attributes": { "in_reply_to": 100, "mentioned_user_ids": [3,5], ... },
  "in_reply_to": 100,        // id da msg citada (ou null)
  "in_reply_to_message": {   // snapshot da msg citada (ou null)
    "id": 100, "sender_name": "João", "content_type": "text",
    "content_preview": "...(140 chars)...", "deleted_at": null,
    "first_attachment_type": "image", "thumb_url": "https://..."
  },
  "mentioned_user_ids": [3, 5],
  "mentioned_ai_agent_ids": [12],
  "edited_at": null,
  "deleted_at": null,
  "created_at": "2026-05-30T12:00:00Z",
  "attachments": [
    { "id": 1, "file_type": "image", "file_name": "foto.webp",
      "content_type": "image/webp", "file_size": 12345,
      "file_url": "https://...", "thumb_url": "https://...",
      "download_url": "/api/v1/.../attachments/1/download" }
  ],
  "sticker": { "id": 4, "image_url": "https://...", "width": 320, "height": 320 }, // ou null
  "is_favorited": false,     // sempre false neste evento (sender perspective)
  "reactions": []            // [] na criação
}
```

> Nota: no `BroadcastMessageJob` o serializer é instanciado **sem**
> `current_user`, então `is_favorited` é `false` e `reactions[].by_me` é
> `false`. O estado per-user (favorito/by_me) só vem correto nos eventos
> `.updated` e nas leituras REST.

### 2.2. `internal_chat.mention.created`

- **Quando dispara**: junto com `message.created`, **dentro do mesmo loop** do
  `BroadcastMessageJob`, mas **apenas para os usuários mencionados** na
  mensagem (`message.mentions.pluck(:user_id)`). Um usuário mencionado recebe
  **dois** payloads: o `message.created` e, em seguida, o `mention.created`.
- **Quem recebe**: somente os `user_id` presentes em `internal_chat_mentions`
  para essa mensagem (e que sejam membros ativos da sala).
- **Side effect**: dispara `InternalChat::Telemetry.track('mention_received',
  ...)` por destinatário.
- **Payload** (`data`):

```jsonc
{
  "account_id": 7,
  "room_id": 45,
  "message_id": 123,
  "mentioned_at": "2026-05-30T12:00:00Z",
  "sender": { "id": 9, "name": "Maria Silva", "avatar_url": "...", "is_ai": false },
  "content_preview": "texto da mensagem (até 140 chars)"
}
```

> O `sender` é o mesmo objeto do payload de `message.created` (reusado por
> referência: `message_payload[:data][:sender]`).

### 2.3. `internal_chat.message.updated`

- **Quando dispara**: em qualquer mutação de uma mensagem existente —
  `update` (edição de texto), `destroy` (soft-delete), `react`/`unreact`
  (reações). Centralizado em `MessagesController#broadcast_message_change`.
- **Quem recebe**: todos os membros **ativos** da sala (inclui o sender).
- **Payload** (`data`): o `MessageSerializer.as_json` completo (mesmo shape do
  `.created`), porém serializado **por destinatário** com `current_user: user`,
  então:
  - `is_favorited` reflete o estado **daquele** usuário;
  - `reactions[].by_me` reflete se **aquele** usuário reagiu.
  - Em soft-delete, `deleted_at` vem preenchido e `content` segue o estado
    pós-`soft_delete!`.

### 2.4. `internal_chat.typing`

- **Quando dispara**: `POST /rooms/:room_id/typing` com `{ active: true|false }`
  (`TypingController#create`). **Efêmero** — não persiste nada.
- **Quem recebe**: todos os outros membros ativos da sala (**self é removido**
  do fan-out).
- **Rate-limit**: **1 broadcast por usuário / sala / segundo**, e **somente**
  para `active=true`. A chave de cache é
  `internal_chat:typing_rate:<room_id>:<user_id>` (TTL 1s). Se o limite estiver
  ativo, o `start` é descartado (`204 No Content` sem broadcast).
  - `active=false` (stop) **sempre** passa — para a UX dos outros membros não
    ficar com "Fulano digitando…" infinito.
  - Se o Redis cair, o fallback é **broadcastar** (melhor ruído do que
    silêncio).
- **Payload** (`data`):

```jsonc
{
  "account_id": 7,
  "room_id": 45,
  "user_id": 9,
  "user_name": "Maria Silva",
  "active": true
}
```

### 2.5. `internal_chat.read_receipt.updated`

- **Quando dispara**: `POST /rooms/:room_id/read` (`MessagesController
  #mark_read`) quando o `last_read_message_id` da membership **avança**
  (mensagens só com id maior que o já lido).
- **Quem recebe**: outros membros ativos da sala (**self excluído**).
- **Debounce**: leading-edge, **2 segundos** por usuário/sala. Chave de cache
  `internal_chat:read_receipt_debounce:<room_id>:<user_id>` (TTL 2s). A
  primeira call dispara; as seguintes dentro da janela **só atualizam o DB**
  (`last_read_message_id` é canônico) sem broadcast. Outros membros veem o read
  receipt "atrasado em até 2s" — aceitável. Se o Redis cair, broadcasta sem
  rate-limit.
- **Payload** (`data`):

```jsonc
{
  "account_id": 7,
  "room_id": 45,
  "user_id": 9,
  "last_read_message_id": 123
}
```

### 2.6. `internal_chat.room.updated`

- **Quando dispara**: em mutações da sala que os clientes precisam refletir na
  listagem em tempo real:
  - Criação de sala/DM (`RoomCreator#broadcast_to_other_members`) — notifica os
    **outros** membros (o criador já tem a sala via resposta REST);
  - Avatar do grupo (`update_avatar` / `remove_avatar`);
  - Mudança de membership (add/remove/promover) via `MembershipsController`;
  - (Renomear/descrição geram `system message`, que já trafega como
    `message.created`.)
- **Quem recebe**: depende do call site:
  - `RoomsController#broadcast_room_update` e `MembershipsController`: todos os
    membros **ativos** (`memberships.active`);
  - `RoomCreator`: apenas os **outros** membros (exclui o criador).
- **Resiliência**: os call sites em `RoomsController` e `RoomCreator` usam
  `isolate: true` (RT-3); `MembershipsController#broadcast_room_update` **não**
  isola.
- **Payload** (`data`): o `RoomSerializer.as_json` completo. Serializado por
  destinatário (`current_user: user`) em `RoomCreator`; nos controllers é
  serializado com `Current.user`. Shape:

```jsonc
{
  "id": 45,
  "account_id": 7,
  "kind": "group",            // direct | group
  "name": "Recepção",         // display_name_for(current_user)
  "description": "...",
  "avatar_url": "https://...",
  "archived_at": null,
  "muted_until": null,        // do membership do current_user
  "last_message_at": "2026-05-30T12:00:00Z",
  "last_message": { ...MessageSerializer (sem current_user)... }, // ou null
  "unread_count": 3,          // do membership do current_user
  "members": [
    { "id": 1, "user_id": 9, "ai_agent_id": null, "role": "owner",
      "name": "Maria Silva", "avatar_url": "...", "is_ai": false,
      "last_read_message_id": 120 },
    { "id": 2, "user_id": null, "ai_agent_id": 12, "role": "member",
      "name": "Beatriz · IA", "avatar_url": null, "is_ai": true,
      "last_read_message_id": null }
  ],
  "created_by_user_id": 9,
  "created_at": "2026-05-29T08:00:00Z"
}
```

### 2.7. `internal_chat.room.deleted`

- **Quando dispara**: `DELETE /rooms/:id` (`RoomsController#destroy`). O
  broadcast é montado **antes** de destruir a sala (os ids de membros são
  coletados antes do `destroy!`) e enviado **depois** do `destroy!`.
- **Quem recebe**: **todos** os membros que já estiveram na sala (`where.not
  (user_id: nil)` — **não** filtra `.active`, para que quem já saiu também
  remova a sala fantasma da UI). Fan-out com `isolate: true`.
- **Payload** (`data`):

```jsonc
{ "account_id": 7, "room_id": 45 }
```

### 2.8. Resumo

| Evento | Origem | Destinatários | Self incluído? |
|---|---|---|---|
| `message.created` | `BroadcastMessageJob` | membros ativos | sim |
| `mention.created` | `BroadcastMessageJob` | só users mencionados | n/a |
| `message.updated` | `MessagesController` (edit/delete/react) | membros ativos | sim |
| `typing` | `TypingController` | outros membros ativos | **não** |
| `read_receipt.updated` | `MessagesController#mark_read` | outros membros ativos | **não** |
| `room.updated` | `RoomsController` / `MembershipsController` / `RoomCreator` | membros ativos (criação: só os outros) | varia |
| `room.deleted` | `RoomsController#destroy` | todos que já foram membros | sim |

---

## 3. Typing — detalhes

`internal_chat.typing` é **puramente efêmero**: nenhum estado é persistido. O
controller só faz broadcast + escreve a chave de rate-limit no cache.

- **Rate-limit server-side** (PERF-12): **1 broadcast / usuário / sala /
  segundo**, **só** para `active=true`. Motivação: em uma sala com 50 membros,
  uma rajada de `start` faria `50 × 49 = 2450` broadcasts/seg no pior caso. O
  frontend já tem debounce (~3s), mas o limite no servidor cobre races de
  keystroke duplicado.
- **`active=false` nunca é limitado** — o stop precisa chegar imediatamente.
- **Falha de cache** (Redis down): o controller faz `rescue` e ainda responde
  `204`; e o `typing_rate_limited?` retorna `false` no erro, então prefere
  broadcastar a silenciar.
- **Autorização** (`TypingPolicy`): exige feature gate `internal_chat.view`
  **e** membership ativa. **Sem** bypass de admin não-membro (diferente das
  outras policies) — um admin que não é membro não deve aparecer "digitando…"
  para os membros.

---

## 4. Integração Bea — Pipeline B (resposta a `@beatriz`)

Fluxo: alguém menciona **@beatriz** numa mensagem do chat interno → a Bea
responde postando uma **mensagem real** na sala (que por sua vez trafega como
`internal_chat.message.created` para todos).

### 4.1. Trilha do código

1. **`InternalChat::MessageDispatcher#persist_mentions`** — após persistir a
   mensagem e gravar as `Mention`s, chama
   `InternalChat::AiAgentMentionListener.call(message:, ai_agent_ids:)`.

2. **`InternalChat::AiAgentMentionListener`**
   (`plugins/internal_chat/app/listeners/internal_chat/ai_agent_mention_listener.rb`)
   — filtra antes de despachar:
   - retorna se não há `ai_agent_ids` mencionados;
   - **loop guard**: retorna se `message.sender_ai_agent_id` está presente (Bea
     nunca responde a IA);
   - resolve a Bea da conta (`BeaResolver.for_account`) e exige que ela esteja
     entre os mencionados;
   - exige que `::AiAgent::InternalChat::RespondJob` esteja definido (plugin
     `ai_agent` carregado);
   - enfileira `RespondJob.perform_later(message.id, account_id:
     message.room.account_id)`. O `account_id` é passado para o job validar
     tenant (defesa cross-tenant contra job forjado).
   - Todo o método é envolvido em `rescue` — falha do listener não quebra o
     envio da mensagem.

3. **`AiAgent::InternalChat::RespondJob`**
   (`plugins/ai_agent/app/jobs/ai_agent/internal_chat/respond_job.rb`) — roda
   **async** no Sidekiq (`queue_as :default`) para não bloquear o
   `MessageDispatcher` com a latência da LLM (1–3s). Delega para o `Responder`.

4. **`AiAgent::InternalChat::Responder`**
   (`plugins/ai_agent/app/services/ai_agent/internal_chat/responder.rb`) —
   orquestra a resposta:
   - **Guards de segurança**: ignora `content_type == 'system'`; valida
     `account_id` esperado vs. real (cross-tenant); re-resolve a Bea; **loop
     guard** (não responde se `sender_ai_agent_id` presente); confirma que a
     mensagem **de fato** menciona a Bea lendo de
     `internal_chat_mentions` (fonte de verdade, não de `content_attributes` —
     cobre menção implícita por reply a msg de IA).
   - **Rate-limit** (`AiAgent::InternalChat::RateLimiter`): se estourou e é o
     **primeiro** bloqueio, posta uma nota de limite; caso contrário,
     silencioso.
   - **Geração**: monta histórico (últimas 10 msgs visíveis não-system da sala,
     cronológico), prompt (`SystemPrompt` + histórico + msg citada + msg
     atual), chama `RubyLLM.chat` com `Toolset` **read-only** (sem book/cancel),
     propaga o user invocador para os tools privilegiados (SEC-12).
   - **Postagem**: posta a resposta via
     `InternalChat::MessageDispatcher.call(room:, sender: bea, content:,
     content_attributes: { 'in_reply_to' => original.id, 'pipeline' =>
     'internal_chat_response' })`. Por ser uma mensagem real, o dispatcher
     dispara o `BroadcastMessageJob` normal → todos recebem
     `message.created`.
   - **Erro**: em exception, posta uma resposta de erro amigável (pipeline
     `internal_chat_error`).

### 4.2. Pontos importantes

- A resposta da Bea é uma **mensagem normal** (`sender_ai_agent_id` setado,
  `sender_user_id` nil). Não há evento cable especial para "Bea respondeu" — é
  `message.created` como qualquer outra.
- A Bea **não conta como unread** para o mencionador: o `unread_summary` filtra
  `msg.sender_user_id != membership.user_id`, e mensagens da Bea têm
  `sender_user_id` NULL (comportamento histórico intencional).
- `content_attributes['pipeline']` distingue a origem:
  `internal_chat_response` (resposta normal), `internal_chat_rate_limit`,
  `internal_chat_error`.

---

## 5. Integração Bea — Notificações internas proativas

Pipeline separado do anterior: a Bea posta **notificações de eventos do
sistema** (agendamento pendente, no-show, tom ofensivo, emergência clínica,
falha de cobrança, etc.) na sala/DM configurada pela clínica.

### 5.1. Trilha do código

1. **Notifiers especializados** (`AiAgent::InternalNotifier::*Alert`, em
   `plugins/ai_agent/app/services/ai_agent/internal_notifier/`) — cada um só
   decide **quando** disparar e **passa as vars** do template. Ex.:
   `AppointmentPendingConfirmation`, `OffensiveToneAlert`, `EmergencyAlert`,
   `PatientDebtAlert`, `RefundRequestAlert`, `RepeatedFailuresAlert`,
   `AppointmentNoShow`, `AppointmentCancelled`, `AppointmentBookingFailed`.

2. **`AiAgent::InternalNotifier::Dispatcher`** (`.call`/`.dispatch`) — helper
   genérico. Para cada notificação:
   - resolve o destino via `Router`;
   - dedupe por `notifier_key` (não repete a mesma notificação na sala —
     checa `content_attributes ->> 'notifier_key'`);
   - renderiza o corpo (`TemplateRenderer` + `EventCatalog.default_body_for`);
   - posta como Bea via `InternalChat::MessageDispatcher`, com
     `content_attributes` contendo `mentioned_user_ids` (membros humanos
     ativos), `mentioned_all`, `notifier_key` e `event_key`.
   - Todo o método é `rescue`-protegido (falha de notificação não propaga).

3. **`AiAgent::InternalNotifier::Router`** — dado `account` + `event_key`,
   resolve **qual `InternalChat::Room`** a Bea usa, conforme o
   `InternalNotificationTemplate` configurado pela clínica. Três tipos de
   destino:
   - `'room'` → posta na sala configurada (validada ainda existir);
   - `'user'` → posta numa **DM 1:1 idempotente** entre Bea e o user
     (`find_or_create_bea_dm` — reusa a DM `direct` existente ou cria com os 2
     membros);
   - `'disabled'` (ou template ausente) → retorna `nil`, **não dispara** (sem
     auto-magia: clínica que não configurou template não recebe nada).
   - Se o destino aponta para sala/user inexistente, loga `warn` e **não**
     envia.

### 5.2. Ponto importante

Assim como no Pipeline B, a notificação é uma **mensagem real** postada pelo
`MessageDispatcher` → trafega como `internal_chat.message.created` (e, por
causa dos `mentioned_user_ids`, gera `internal_chat.mention.created` para os
membros). Não há evento cable dedicado a notificações.

---

## 6. Nota RBAC — `internal_chat.manage_memberships` NÃO é enforced

A permissão de catálogo `internal_chat.manage_memberships` **existe** no
catálogo Klivy (`plugins/custom_roles/app/models/klivy_role/
permissions_catalog.rb`), mas **não é enforced** em runtime.

O gate real de gestão de membros é por **room role**: `MembershipPolicy`
autoriza add/remove/promote apenas para quem tem `role IN ('owner', 'admin')`
**na própria sala** (`room_manager?`), com bypass de admin de conta. A
permissão de catálogo é um **extension point não-ativado** — conceder
`manage_memberships` a um `KlivyRole` **não** habilita gestão de membros hoje.

> Implicação para docs/expectativas: não prometa que conceder
> `internal_chat.manage_memberships` dá poder sobre membros. Quando o ciclo de
> role granular for ativado, a policy passará a exigir
> `beclinic_can?(:internal_chat, :manage_memberships)` **além** do room role
> (ver docstring em `membership_policy.rb`).

Relacionado: `TypingPolicy` também é uma exceção ao padrão — **não** tem bypass
de admin não-membro (intencional, seção 3).

---

## Referências

- [README do plugin](../README.md) — visão geral, modelos, multi-tenancy.
- `app/jobs/internal_chat/broadcast_message_job.rb` — fan-out de
  `message.created` + `mention.created`.
- `app/services/internal_chat/user_broadcaster.rb` — helper de fan-out.
- `app/controllers/api/v1/accounts/internal_chat/{typing,messages,rooms,memberships}_controller.rb`
  — origens dos eventos cable.
- `app/listeners/internal_chat/ai_agent_mention_listener.rb` — entrada do
  Pipeline B.
- `plugins/ai_agent/app/jobs/ai_agent/internal_chat/respond_job.rb` +
  `plugins/ai_agent/app/services/ai_agent/internal_chat/responder.rb` —
  resposta da Bea.
- `plugins/ai_agent/app/services/ai_agent/internal_notifier/{dispatcher,router}.rb`
  — notificações internas.
