# ADR 0003 — Read Receipts via `Membership.last_read_message_id`

**Status:** Accepted — 2026-05-19
**Plugin:** `internal_chat`
**Arquivos:** [membership.rb](../../plugins/internal_chat/app/models/internal_chat/membership.rb), [rooms_controller.rb#unread_summary](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/rooms_controller.rb), [message_dispatcher.rb#mark_read_by_sender!](../../plugins/internal_chat/app/services/internal_chat/message_dispatcher.rb)

## Contexto

Chat interno precisa rastrear "última mensagem lida por user" pra:

1. **Unread badge** (sidebar mostra "5 não lidas" por sala)
2. **Read receipts** (sender vê "✓✓ Lida" quando todos os outros membros leram)
3. **Marcar como lida** quando user abre a sala (`POST /rooms/:id/messages/:mid/mark_read`)
4. **Sender auto-mark-read** (RT-7) — mensagem que eu mando, eu já li

Padrão dominante na indústria (WhatsApp, Slack) é tabela dedicada `ReadReceipt(user_id, message_id, read_at)`. Pra grupos grandes com N×M mensagens, isso vira tabela gigante.

## Decisão

**Não criar tabela `ReadReceipt`. Usar apenas `Membership.last_read_message_id` como `BIGINT`.**

Invariantes:
- `last_read_message_id` é monotônico crescente — `mark_read` só atualiza se `new_id > current`
- "Não lidas pra mim" = `messages.where('id > ?', membership.last_read_message_id || 0)` na sala
- "Quem leu até X?" = `room.memberships.where('last_read_message_id >= ?', X).pluck(:user_id)`
- Read receipts no UI = `maxOthersRead = MAX(last_read_message_id) WHERE user_id != current_user_id`

## Consequências

### Positivas

- **1 row por user×room**, vs N rows por user×message — escala linearmente com participantes, não com volume
- **Update O(1)** (1 UPDATE simples por mark_read), vs INSERT explosivo
- **Sender auto-mark via MessageDispatcher** (RT-7, lote 26): após `message.save!`, dispatcher faz `membership.update_column(:last_read_message_id, message.id)` — single source of truth
- **Unread badges via 1 SQL com LEFT JOIN + GROUP BY** (PERF-2, lote 3.1): 100 salas → 1 query vs 101

### Negativas / trade-offs

- **Sem timestamp de leitura** por mensagem individual — não dá pra responder "às 14:32 você leu esta msg específica"
- **Pular mensagens não fica registrado** — se user marca msg #10 como lida (via mark_read explícito), msgs 1-9 também ficam marcadas implicitamente
- **Não suporta "anti-stalker mode"** (esconder read receipts) — toda leitura é visível pra sender via `maxOthersRead`. Aceitável pra chat interno staff (transparência > privacidade)

## Alternativas consideradas

| Opção | Por que NÃO |
|---|---|
| Tabela `ReadReceipt(user_id, message_id, read_at)` dedicada | Scala pior, dobra complexidade de queries, sem ganho real pra chat interno (grupos pequenos) |
| Bit flag em `Message.read_by` JSONB array | Mutação concorrente exige lock pessimist, audit log impossível, query lenta |
| Redis-only (sem persistência) | Read state perdido em restart, dashboard "5 não lidas" some |

## Migração futura

- Per-message timestamp `read_at` SE o produto pedir "às 14:32 você leu" — exige nova tabela
- Anti-stalker mode SE algum cliente pedir compliance específico — `BeclinicSetting.show_read_receipts: false` per-account, frontend só esconde, backend continua persistindo
- Bulk read receipts para mentions ("li 12 menções") — atualmente cada Mention tem `read_at` próprio (sim, EXISTE essa coluna em `Mention` — mas é só pra notificação badge, não leitura de mensagem)
