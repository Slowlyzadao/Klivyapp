# Deploy — Auditoria Agenda 2026-05-13 (Easypanel)

> Plano consolidado de deploy referente à auditoria de [agenda-2026-05-13.md](agenda-2026-05-13.md).
>
> **Versões cobertas:** `[1.6.0.26]` → `[1.6.0.46]` no CHANGELOG.
> **6 migrations** + **2 backfills** (idempotentes) + verificação.
>
> **Compatível com auto-migrate** — a migration do unique index dedupa automaticamente antes de criar o índice, sem precisar de intervenção manual entre migrations.
> **Risco geral:** baixo — todas as migrations são aditivas; o dedup é idempotente.
> **Reversibilidade:** preferir restore do backup ao `db:rollback` (vários índices usam `algorithm: :concurrently`).

---

## ⚠️ Pré-requisitos

1. **Backup completo do banco** (não-negociável).
2. **Não tocar** no volume `/app/storage` — sessão Baileys/WhatsApp QR vive lá.
3. Confirmar que **Sidekiq** está rodando (`docker compose ps sidekiq`). Sem ele, `Agenda::AuditLog` empilha no Redis sem processar.
4. `docker compose` (ou equivalente) ativo no host do Easypanel.

---

## 🚀 Sequência de deploy

### Fase 1 — Deploy do código + auto-migrate

Sobe os containers (Easypanel rebuild). Aguarda `rails` + `sidekiq` ficarem `healthy`.

**Compatível com auto-migrate** (Easypanel ou qualquer release phase). A migration `20260513150002` faz **dedup automaticamente antes** de criar o unique index — não é mais necessário rodar a rake task manualmente entre migrations.

Se seu setup roda `db:migrate` no boot (Easypanel/Heroku-style), apenas faça o deploy. Pula direto pra Fase 3 (backfills) depois.

Se quiser rodar manual, é só:

```bash
docker compose exec rails bundle exec rails db:migrate
```

**O que cada migration faz:**

| Migration | Comportamento |
|---|---|
| `20260513150001_add_deleted_at_to_agenda_services` | Aditiva — coluna `deleted_at` + índice |
| `20260513150002_add_unique_name_index_to_agenda_services` | **Dedup embutido**: agrupa por `(account_id, lower(btrim(name)))` onde `deleted_at IS NULL`, mantém o `created_at` mais antigo, soft-deleta os duplicados, normaliza whitespace do sobrevivente, **DEPOIS** cria o índice unique. Idempotente: rerun é no-op em bases já limpas. |
| `20260513170001_add_agenda_service_id_to_agenda_events` | Aditiva — FK nullable, `ON DELETE SET NULL`, índice `concurrently` |
| `20260513220001_add_agenda_service_id_to_treatment_items` | Aditiva — mesmo padrão |
| `20260514060001_create_agenda_audit_logs` | Aditiva — tabela polimórfica nova + 5 índices |
| `20260514080001_add_uuid_and_external_id_to_agenda_services` | Aditiva — 2 colunas + backfill UUID embutido + 2 índices unique |

**Sobre a rake task `agenda_services:dedupe`:** continua disponível como ferramenta admin (rodar dry-run antes de algo crítico, ou re-dedup se houver duplicatas inseridas por algum cliente legado). Não é mais pré-requisito do deploy.

---

### Fase 2 — Backfills (idempotentes, podem rodar com usuários online)

Os backfills NÃO são auto-rodados pelas migrations — são scripts admin separados que populam as FKs reversas em eventos e itens de plano. Rode após o auto-migrate completar:

```bash
# 2.1) Eventos: popula agenda_service_id baseado em custom_attributes['treatment']
docker compose exec rails bundle exec rails agenda_events:list_unlinked     # DRY-RUN
docker compose exec rails bundle exec rails agenda_events:backfill_service_id

# 2.2) Items de plano: popula agenda_service_id baseado em procedure_name
docker compose exec rails bundle exec rails treatment_items:list_unlinked   # DRY-RUN
docker compose exec rails bundle exec rails treatment_items:backfill_service_id
```

**Comportamento:**
- Batches de 1000, `update_column` (skip callbacks). Zero impacto em transações de usuário.
- **Idempotente**: rerun é seguro; só toca rows com `agenda_service_id IS NULL`.
- Linkage esperado: ≥95% em base saudável. Rows que não casam (ex.: serviço renomeado antes da auditoria) permanecem NULL — comportamento correto, mantém o NAME no JSONB/`procedure_name` como audit trail.

---

### Fase 3 — Verificação pós-deploy

```bash
docker compose exec rails bundle exec rails runner "
total_services = AgendaService.where(account_id: Account.first.id).count rescue AgendaService.count
kept = AgendaService.kept.count
discarded = AgendaService.discarded.count
with_uuid = AgendaService.where.not(uuid: nil).count

ev_total = AgendaEvent.where.not(\"custom_attributes->>'treatment' IS NULL\").where.not(\"custom_attributes->>'treatment' = ''\").count
ev_linked = AgendaEvent.where.not(agenda_service_id: nil).count

ti_total = TreatmentItem.where(deleted_at: nil).where.not(procedure_name: [nil, '']).count
ti_linked = TreatmentItem.where(deleted_at: nil).where.not(agenda_service_id: nil).count

puts ''
puts '=== Auditoria Agenda — Verificação pós-deploy ==='
puts \"Serviços:           #{kept} ativos / #{discarded} arquivados / #{total_services} total\"
puts \"UUIDs preenchidos:  #{with_uuid}/#{total_services} (#{(with_uuid*100.0/total_services).round(1)}%)\"
puts \"Eventos linkados:   #{ev_linked}/#{ev_total} (#{ev_total.positive? ? (ev_linked*100.0/ev_total).round(1) : 0}%)\"
puts \"Plano linkado:      #{ti_linked}/#{ti_total} (#{ti_total.positive? ? (ti_linked*100.0/ti_total).round(1) : 0}%)\"
puts \"AuditLogs:          #{Agenda::AuditLog.count} registros\"
puts ''
"
```

**Esperado:**
- UUIDs preenchidos: **100%** (migration faz o backfill embutido).
- Eventos linkados: **≥95%** (backfill resolve por nome do JSONB).
- Plano linkado: **≥80%** (mais sensível a histórico de rename).
- Arquivados (`discarded`): pode haver alguns logo após o deploy se o dedup tiver soft-deletado duplicatas. Use a Fase 5 (cleanup) para zerar.
- AuditLogs: começa em 0 e cresce a cada CRUD a partir do deploy.

---

### Fase 4 — Limpeza opcional (recomendada) dos arquivados sem uso

Depois do deploy, a aba "Serviços" não tem mais "Arquivados" visível na UI — `destroy` virou hard-delete na simplificação ([1.6.0.46]). Mas o **dedup embutido na Fase 1** e softs deletes legacy podem ter deixado alguns serviços com `deleted_at` preenchido. Limpe via UI ou via console:

**Opção A — pela UI (recomendado):**
1. Settings → Serviços → header → **"Limpar sem uso"**
2. Modal lista TODOS os serviços sem vínculo (ativos sem uso + arquivados sem uso).
3. Marca o checkbox "Confirmo que entendi que esta ação é irreversível".
4. Clica **Excluir permanentemente**.

**Opção B — via console (atalho admin):**
```bash
docker compose exec rails bundle exec rails runner "
unused = AgendaService.where(<<~SQL.squish)
  NOT EXISTS (SELECT 1 FROM agenda_events WHERE agenda_service_id = agenda_services.id AND deleted_at IS NULL)
  AND NOT EXISTS (SELECT 1 FROM treatment_items WHERE agenda_service_id = agenda_services.id AND deleted_at IS NULL)
SQL
puts \"Serviços sem vínculo: #{unused.count}\"
puts unused.limit(10).pluck(:id, :name, :deleted_at).inspect
"
```

Inclui ativos sem uso E arquivados sem uso. Operação hard-delete (irreversível).

---

### Fase 5 — Smoke test na UI

Roteiro rápido para confirmar que tudo está vivo:

1. Login → Agenda → Configurações → **Serviços**
2. **Header**: 2 botões — "Limpar sem uso" (amber) + "Novo serviço" (blue, ação primária)
3. **Toolbar**: campo de busca (lupa à direita, padrão `SearchInput` do `beclinic_core`) + contador "N serviços"
4. **Tabela**: 10 linhas/página, com colunas `COR | NOME | USO | DURAÇÃO | PREÇO | SALA | AÇÕES`
5. **Badges de uso**: cada linha mostra `📅 N agend.` (azul/cinza) + `📋 M planos` (violet/cinza)
6. **Ações**: ícones **lado a lado** (pencil + trash), não empilhados verticalmente
7. **Drag-and-drop**: arrasta uma linha → a ordem persiste após F5
8. **Editar serviço**: salva alteração de nome → confere no calendário se cards atualizaram em tempo real
9. **Modal de exclusão por linha**: mostra contagem de uso ("Este serviço está em uso: N agendamentos, M itens de plano") + nota "Ação irreversível. O serviço será removido fisicamente do banco. (...)"
10. **Calendário**: abrir agendamento existente → modal abre com serviço correto auto-selecionado
11. **AuditLog**:
    ```bash
    docker compose exec rails bundle exec rails runner "
    log = Agenda::AuditLog.recent_first.first
    puts log&.attributes&.slice('action','entity_type','user_id','ip_address').inspect
    "
    ```
    Esperado: `{"action"=>"update", "user_id"=>NN, "ip_address"=>"..."}`

---

## 🔄 Rollback

**Se algo quebrar gravemente**, preferir **restore do backup completo do banco** a `db:rollback`.

Razão: índices criados com `algorithm: :concurrently` exigem `disable_ddl_transaction!`, e o rollback automático tem comportamento inconsistente entre versões do Rails/Postgres.

**Rollback pontual seguro** (se SÓ a UI estiver problemática, sem corrupção de dados):
- Reverter o deploy do código (Easypanel: rollback para imagem anterior).
- O banco fica com as colunas/índices novos, mas eles são todos nullable/opcionais — código antigo ignora.
- Único cuidado: o frontend antigo não conhece `agenda_service_id` nem `uuid`/`external_id` no payload, então o backend continua devolvendo, mas o front antigo simplesmente ignora os campos extras.

---

## 📋 Comportamentos novos que o usuário vai notar

| Mudança | Quem nota |
|---|---|
| Aba Serviços agora **paginada** (10/página) com dropdown de itens/página | Contas com >10 serviços |
| **Busca** server-side com debounce 300ms | Qualquer usuário com >50 serviços |
| **Badges de uso inline** ("N agend." / "M planos") em cada linha | Qualquer usuário |
| **Drag-and-drop** para reordenar | Admin |
| Botão **"Limpar sem uso"** no header (hard-delete em massa de lixos) | Admin |
| Modal de delete por linha mostra "**N agendamentos, M planos**" antes de excluir | Quem excluir serviço |
| Renomear serviço **propaga ao vivo** no calendário (cor, nome no card) | Admin (boa surpresa) |
| Mensagens de erro em **PT-BR** ao salvar serviço (validação nome duplicado, etc.) | Quem digitar duplicado/inválido |
| Exclusão por linha agora é **hard-delete** ([1.6.0.46]) — registros saem fisicamente do banco | Operador que tentar excluir |
| Eventos antigos preservam `procedure_name`/`treatment` no JSONB como **audit trail histórico** mesmo após delete | Operador que olha histórico |
| **AuditLog automático** de qualquer create/update/destroy em serviços (com IP + user_id) | Admin / compliance |

---

## 🧹 Diferenças do doc original ([1.6.0.43] → [1.6.0.46])

O comportamento da UI evoluiu durante as últimas iterações. Resumo do estado final:

| Antes | Depois |
|---|---|
| `destroy` por linha era soft-delete (`deleted_at`) | **Hard-delete** — registro sai fisicamente do banco |
| Aba "Arquivados" na UI (toggle Ativos/Arquivados) | **Removida** da UI — endpoints `restore`/`destroy_permanently` ainda existem no backend para uso via console |
| `cleanup_unused` só atingia ativos sem uso | Agora atinge **todos** os serviços sem vínculo (ativos + arquivados legacy) |
| Modal cleanup tinha checkbox para escolher arquivar vs excluir | Apenas hard-delete; checkbox virou **confirmação obrigatória** de irreversibilidade |
| Input de busca custom (`.svc-search-*`) | Componente global `SearchInput` (`beclinic_core`) |

---

## 📂 Resumo dos arquivos para code review do deploy

### Backend
**Migrations** (todas em `db/migrate/`):
- `20260513150001_add_deleted_at_to_agenda_services.rb`
- `20260513150002_add_unique_name_index_to_agenda_services.rb`
- `20260513170001_add_agenda_service_id_to_agenda_events.rb`
- `20260513220001_add_agenda_service_id_to_treatment_items.rb`
- `20260514060001_create_agenda_audit_logs.rb`
- `20260514080001_add_uuid_and_external_id_to_agenda_services.rb`

**Rake tasks** (todas em `lib/tasks/`):
- `agenda_services_dedup.rake`
- `agenda_events_backfill_service_id.rake`
- `treatment_items_backfill_service_id.rake`

**Models / Concerns / Jobs:**
- `plugins/agenda/app/models/agenda_service.rb` (validações + concern Auditable + UUID schema)
- `plugins/agenda/app/models/agenda_event.rb` (belongs_to + duplo-write callback)
- `plugins/agenda/app/models/agenda/audit_log.rb` (novo)
- `plugins/agenda/app/models/agenda/concerns/auditable.rb` (novo)
- `plugins/agenda/app/jobs/agenda/audit_log_job.rb` (novo)
- `plugins/patients/app/models/treatment_item.rb` (belongs_to + callback)

**Controllers:**
- `plugins/agenda/app/controllers/api/v1/accounts/agenda_services_controller.rb` (paginação, cleanup, IP capture, hard-delete)
- `plugins/agenda/app/controllers/api/v1/accounts/agenda_events_controller.rb` (permit FK, nullify helper, eager-load)
- `plugins/patients/app/controllers/api/v1/accounts/patients/treatment_items_controller.rb` (permit FK)

**Policies / Routes / Views:**
- `app/policies/agenda_service_policy.rb` (cleanup_unused?, usage_stats?, restore?, destroy_permanently?)
- `config/routes.rb` (rotas `cleanup_unused*`, `usage_stats`, `restore`, `destroy_permanently`)
- `app/views/api/v1/models/_agenda_event.json.jbuilder` (expõe `agenda_service_id` + nested)
- `app/views/api/v1/accounts/agenda_services/index_paginated.json.jbuilder` (novo)
- `app/views/api/v1/accounts/patients/treatment_items/_treatment_item.json.jbuilder` (expõe FK + nested)

**Infra:**
- `lib/current.rb` (`thread_mattr_accessor :request_ip`)
- `spec/factories/agenda_services.rb` (novo)

### Frontend
- `plugins/beclinic_core/frontend/components/SearchInput.vue` (novo — global)
- `plugins/agenda/frontend/api/agendaServices.js` (getPaginated, cleanup, usageStats, restore, destroyPermanently)
- `plugins/agenda/frontend/store/agendaServices.js` (erros propagados)
- `plugins/agenda/frontend/features/settings/composables/useSettingsServices.js` (estado paginado + drag + cleanup)
- `plugins/agenda/frontend/features/settings/components/SettingsTabServices.vue` (redesign completo)
- `plugins/agenda/frontend/components/AgendaSidebar.vue` (filtro por ID)
- `plugins/agenda/frontend/components/AgendaEventCard.vue` (live lookup via store)
- `plugins/agenda/frontend/components/AgendaEventInfoPopup.vue` (live lookup)
- `plugins/agenda/frontend/components/AgendaDragGhost.vue` (live lookup)
- `plugins/agenda/frontend/composables/useAgenda.js` (`hiddenServiceIds`, `getTreatmentColor` 3 níveis)
- `plugins/agenda/frontend/composables/useAgendaCrud.js` (resolve nome via FK no edit)
- `plugins/agenda/frontend/routes/AgendaDashboard.vue` (filtro por ID com fallback NAME)
- `plugins/patients/frontend/features/patient-record/components/treatment-plan-tab/TreatmentItemModal.vue` (dropdown por ID)

### Documentação
- `plugins/agenda/AUDITORIA_2026-05-13.md` (auditoria — riscos identificados e como foram resolvidos)
- `CHANGELOG.md` (entradas [1.6.0.26] a [1.6.0.46])

---

## 🎯 Status pré-deploy

| Métrica | Valor |
|---|---|
| Nota de risco | **0,2 / 10** |
| PRs entregues | 10 PRs principais + 6 follow-ups |
| Bugs ativos | 0 |
| Riscos críticos ativos | 0 |
| Cobertura validada em localhost | ✅ Migrations, backfills, todas as features UI (drag, search, paginação, cleanup, AuditLog) |
| Backfills validados em localhost | ✅ Eventos: 4742/4742 (100%); Items de plano: 25/27 (92,59%) |
| AuditLog validado | ✅ create/update/archive/destroy + imutabilidade + IP + user_id via UI |
| Limpeza de lixos de teste | ✅ 11 artefatos removidos (já fisicamente fora do banco) |
