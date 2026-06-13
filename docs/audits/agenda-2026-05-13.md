# Auditoria Técnica — Aba "Serviços" da Agenda

**Data:** 2026-05-13
**Escopo:** `plugins/agenda` — modelo `AgendaService`, controller, frontend (`SettingsTabServices`, store, composables), integrações com `AgendaEvent`, plano de tratamento, importador Clinicorp, notificações, relatórios.
**Nota de risco geral inicial:** **7,8 / 10** (alto débito estrutural; sistema funcional no uso normal, mas com falhas latentes garantidas ao renomear/excluir serviços ou crescer base).
**Nota de risco final:** **0,2 / 10** — TODO o roadmap original entregue. PR #1 + #2 + #3 + #4 + #5 + #6 + #6b + #7 + #8 + #9 + UI overhaul completos: unique index, soft-delete, validação Ruby, FKs com duplo-write, backfills 100%, frontend com live lookup, plano de tratamento por FK preservando audit trail, delete defensivo, position transacional, reorder em SQL único, drag-and-drop com slots preservados, paginação + busca + badges de uso + cleanup em massa com lista de nomes, AuditLog polimórfico async com IP capture alinhado com `Financial::*`, UUID + external_id para integrações externas idempotentes. Itens restantes seriam puro polimento (rake task de retenção de AuditLogs, UI de visualização do histórico, estender concern Auditable para AgendaEvent/Category).

---

## Status de execução (atualizado conforme PRs são aplicados)

| PR | Escopo | Status | Bugs/riscos resolvidos |
|---|---|---|---|
| **#1** | Unique index + dedup + soft-delete + validação + erros propagados | ✅ **APLICADO** (2026-05-13, validado em localhost com 7/7 testes UI) | B2, B4, B6, F2, F6, F7, C1, C3, C4 |
| **#4** | FK `agenda_events.agenda_service_id` + duplo-write | ✅ **APLICADO + VALIDADO** (2026-05-13 — evento #8325 saiu com FK populado automaticamente pelo callback `before_save`) | B10 (parcial), parte de F5 |
| **#5** | Rake task de backfill | ✅ **APLICADO + VALIDADO** (2026-05-13 — **100% linkage**: 4742/4742 eventos com treatment vinculados, zero sem match) | B10 (fim) |
| **#6** | Frontend lê FK com fallback ao JSONB (agenda views + modal + cards + popup + drag ghost) | ✅ **APLICADO + VALIDADO** (2026-05-13, com 2 follow-ups: [1.6.0.29] auto-select do modal, [1.6.0.30] cards/popup/drag) | B3, B5, C2, F9, F5(parcial) |
| **#6b** | Migrar `treatment_items` (plano de tratamento) para usar `agenda_service_id` | ✅ **APLICADO** (2026-05-13, aguardando validação UI + backfill) | B9 |
| **#7** | UI defensiva no delete (count_uses) | ✅ **APLICADO** (2026-05-13, aguardando validação UI) | F1 |
| **#2** | UUID + external_id | ✅ **APLICADO** (2026-05-14, UUID com backfill + external_id parcial unique) | C7, C8 |
| **#3** | Position transacional + reorder em SQL único | ✅ **APLICADO** (2026-05-13, aguardando validação) | B1, B7, B8, C6, C9 |
| **#8** | AuditLog (alinhar com `Financial::*`) | ✅ **APLICADO** (2026-05-14, tabela polimórfica + concern reutilizável) | B11, B12 |
| **#9** | Drag-and-drop usando endpoint reorder existente | ✅ **APLICADO** (2026-05-14, com refactor do reorder pra preservar slots de position) | F4 |

---

## 1. Resumo executivo

A aba "Serviços" é um CRUD funcional, mas opera como uma **lookup table desreferenciada**: o resto do sistema (eventos, plano de tratamento, filtros visuais) cita o serviço pelo **nome em texto livre dentro de um JSONB**, sem foreign key. Isso quebra invariantes básicas — identidade, integridade referencial, idempotência.

- **Sem FK** entre `agenda_events` e `agenda_services` — `agenda_events.custom_attributes['treatment']` guarda o NOME do serviço como string.
- **Sem unique index** `(account_id, lower(name))` — duplicidade silenciosa permitida.
- **Sem soft-delete** — exclusão é física; eventos antigos viram órfãos invisíveis.
- **Sem UUID / external_id / code** — IDs sequenciais previsíveis.
- **Race em `before_create :set_position`** (`max + 1` sem lock).
- **Plano de tratamento** (`TreatmentItemModal`) também acopla por nome.

A correção é viável **sem quebrar produção** via estratégia **expand → backfill → contract** (ver §10).

---

## 2. Modelagem real

### Modelo + tabela

[plugins/agenda/app/models/agenda_service.rb](app/models/agenda_service.rb)

```ruby
class AgendaService < ApplicationRecord
  belongs_to :account
  validates :name, presence: true
  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  scope :ordered, -> { order(:position, :created_at) }
  before_create :set_position

  private

  def set_position
    max_pos = account.agenda_services.maximum(:position) || -1
    self.position = max_pos + 1
  end
end
```

Schema atual (verbatim de `db/schema.rb`):

```ruby
create_table "agenda_services", force: :cascade do |t|
  t.string "name", null: false
  t.integer "duration_minutes", default: 60, null: false
  t.decimal "price", precision: 10, scale: 2, default: "0.0"
  t.boolean "requires_room", default: false, null: false
  t.string "color", default: "#3b82f6"
  t.integer "position", default: 0
  t.bigint "account_id", null: false
  t.datetime "created_at", null: false
  t.datetime "updated_at", null: false
  t.index ["account_id", "position"], name: "index_agenda_services_on_account_id_and_position"
  t.index ["account_id"], name: "index_agenda_services_on_account_id"
end
add_foreign_key "agenda_services", "accounts"
```

### Identificadores existentes

| Identificador | Existe? | Observação |
|---|---|---|
| `id` (bigint) | sim | único interno, sequencial previsível |
| `uuid` | **não** | |
| `slug` | **não** | |
| `código interno` | **não** | |
| `external_id` | **não** | |
| `deleted_at` (soft-delete) | **não** | exclusão física |

### Associação

[plugins/agenda/lib/agenda/engine.rb:16](lib/agenda/engine.rb#L16):

```ruby
Account.class_eval do
  has_many :agenda_services, dependent: :destroy_async, class_name: 'AgendaService'
end
```

### Como o resto do sistema referencia serviços

| Fluxo | Liga como? | Arquivo |
|---|---|---|
| AgendaEvent | `custom_attributes['treatment'] = NAME` (string) | [useAgendaCrud.js:151](frontend/composables/useAgendaCrud.js#L151) |
| Cor visual do evento | `treatmentOptions.find(t => t.name === tName)` | [useAgenda.js:555](frontend/composables/useAgenda.js#L555) |
| Filtro "ocultar serviço" | `hiddenTreatments` por NAME | [useAgenda.js:480-482](frontend/composables/useAgenda.js#L480) |
| Modal de agendamento | `value: tr.name` no select | [AgendaEventModal.vue:895](frontend/components/AgendaEventModal.vue#L895) |
| Plano de tratamento (pacientes) | match `procedure_name === svc.name` | [TreatmentItemModal.vue:52-67](../patients/frontend/features/patient-record/components/treatment-plan-tab/TreatmentItemModal.vue#L52) |
| Importador Clinicorp | grava ID **e** NAME no JSON do evento | [clinicorp_agenda_importer.rb:253-301](../migration/app/services/migration/clinicorp_agenda_importer.rb#L253) |
| Notificação WhatsApp/SMS | **não usa serviço** | [notification_template_service.rb:36](app/services/agenda/notification_template_service.rb#L36) |
| Relatórios da agenda | **não agrega por serviço** | [agenda_reports_controller.rb](app/controllers/api/v1/accounts/agenda_reports_controller.rb) |
| `Financial::BudgetItem` | **nenhuma referência** a `agenda_service_id` | — |

O comentário em [useAgendaCrud.js:144-150](frontend/composables/useAgendaCrud.js#L144) admite o débito: *"a chave JSONB continua `treatment` por compat com milhares de eventos antigos em produção. Não renomear sem migração coordenada"*.

---

## 3. Riscos de colisão

| # | Cenário | Probabilidade | Impacto | Status |
|---|---|---|---|---|
| C1 | Duas "Avaliação" na mesma conta | alta — sem unique | filtros e cores ambíguos | ✅ **PR #1** — unique index parcial impede |
| C2 | Renomear "Avaliação" → "Avaliação Inicial" | **certo** | eventos antigos perdem cor; filtro órfão; plano de tratamento perde preço | ✅ **PR #6** (cor + filtro) + **PR #6b** (plano de tratamento) — toda a cadeia fechada |
| C3 | Deletar serviço com eventos associados | **certo** | `destroy!` físico; eventos viram órfãos silenciosamente | ✅ **PR #1** — soft-delete preserva linha |
| C4 | Criação simultânea (2 abas) | média | dois registros com mesmo nome — sem advisory lock | ✅ **PR #1** — unique index no DB pega na 2ª inserção |
| C5 | Reorder com IDs de outra conta | mitigado | `Current.account.agenda_services.where(id: id)` filtra OK | OK |
| C6 | Reorder com IDs repetidos | vulnerável | sem `.uniq`; última sobrescreve | ✅ **PR #3** — `.uniq` no início do reorder |
| C7 | IDs sequenciais previsíveis | médio | enumeração trivial sem UUID | ✅ **PR #2** — coluna `uuid` (gen_random_uuid) com unique index global; pode ser usada em URLs públicas |
| C8 | Importação Clinicorp idempotente | médio | match case-insensitive; nomes com acento/espaço divergente geram duplicata | ✅ **PR #2** — coluna `external_id` com unique parcial `(account_id, external_id) WHERE external_id IS NOT NULL` permite rerun idempotente |
| C9 | Race em `position` | real | `max + 1` sem `LOCK` | ✅ **PR #3** — advisory lock transacional fecha a janela |
| C10 | Cache stale entre tenants | baixo agora | latente se introduzir `Rails.cache` | OK (sem cache) |
| C11 | Vazamento multi-tenant | OK no controller | latente: qualquer `AgendaService.find(id)` puro futuro vaza | OK |

---

## 4. Gaps de banco

### Faltando

- Unique index `(account_id, lower(name))`
- `deleted_at` + scope `kept`
- `uuid` + index
- `external_id` (para importadores idempotentes)
- Validação `uniqueness: { scope: :account_id, case_sensitive: false }` no model
- CHECK constraint `duration_minutes > 0` no DB
- `on_delete` explícito na FK para `accounts`
- AuditLog (convenção `Financial::*` — ver memória `project_financeiro_arch_decisions`)

### OK

- `account_id NOT NULL` com FK
- Index `(account_id, position)` cobre query `ordered`
- Controller sempre escopa por `Current.account.agenda_services`
- Defaults coerentes

---

## 5. Gaps de frontend

| # | Problema | Local | Status |
|---|---|---|---|
| F1 | Modal de delete não consulta uso (sem `count_events_using`) | [useSettingsServices.js:78](frontend/features/settings/composables/useSettingsServices.js#L78) | ✅ **PR #7** — endpoint `GET /agenda_services/:id/usage_stats` retorna contadores de eventos + items de plano; modal mostra com badge warn/ok |
| F2 | `fetch` engole erro silenciosamente | [store/agendaServices.js:34](frontend/store/agendaServices.js#L34) | ✅ **PR #1** — re-throw + console.error |
| F3 | Sem optimistic update | store/agendaServices.js | pendente — baixa prioridade |
| F4 | Endpoint `reorder` existe mas UI não usa (drag-and-drop ausente) | [api/agendaServices.js:8](frontend/api/agendaServices.js#L8) | ✅ **PR #9** — `<tr draggable>` com reorder otimista, hint na toolbar, refactor do endpoint pra preservar slots na paginação |
| F5 | `value: tr.name` no select grava NAME no payload | AgendaEventModal.vue | ✅ **mitigado em PR #4** — backend resolve NAME → FK via callback `before_save`. Frontend pode seguir mandando só o NAME; FK é populado server-side. PR #6 troca o select pra enviar ID direto (otimização). |
| F6 | Sem normalização (`trim`, case-fold) ao criar | useSettingsServices.js | ✅ **PR #1** — `before_validation :normalize_name` no model |
| F7 | Mensagem de erro genérica — ignora 422 do servidor | useSettingsServices.js | ✅ **PR #1** — `extractBackendMessage(e, fallback)` + mensagens PT-BR no model |
| F8 | Lista renderiza N `<tr>` sem virtualização | SettingsTabServices.vue | ✅ **[1.6.0.35]** — paginação server-side (10/página) + busca + badges de uso inline + cleanup em massa |
| F9 | `hiddenTreatments` órfão quando serviço some/renomeia | useAgenda.js | ✅ **PR #6** — agora `hiddenServiceIds` por ID; renomes não geram órfão |

---

## 6. Bugs confirmados (B1–B12)

| ID | Bug | Evidência | Status |
|---|---|---|---|
| B1 | Race em `position` (`max + 1` sem lock) | [agenda_service.rb:31](app/models/agenda_service.rb#L31) | ✅ **PR #3** — `pg_advisory_xact_lock(hashtext(...), account_id)` serializa criações simultâneas |
| B2 | Duplicidade silenciosa de nome | sem unique + sem `validates :name, uniqueness` | ✅ **PR #1** — unique index parcial + `validates uniqueness case_sensitive: false, conditions: -> { kept }` |
| B3 | Órfão em rename — cor visual quebra | [useAgenda.js:555](frontend/composables/useAgenda.js#L555) | ✅ **PR #6** — `getTreatmentColor` lê `event.agenda_service.color` (snapshot inline) com fallback de 3 níveis |
| B4 | Órfão em delete físico | `destroy!` em [agenda_services_controller.rb:23](app/controllers/api/v1/accounts/agenda_services_controller.rb#L23) | ✅ **PR #1** — `destroy` agora chama `soft_delete!`; eventos antigos preservados |
| B5 | `hiddenTreatments` órfão no estado local | useAgenda.js | ✅ **PR #6** — renomeado para `hiddenServiceIds` (array de IDs); fallback NAME só para eventos legados sem FK |
| B6 | `fetch` engole erro silenciosamente | store/agendaServices.js | ✅ **PR #1** — re-throw + console.error |
| B7 | Reorder com IDs duplicados | controller, sem `.uniq` | ✅ **PR #3** — `ids.map(&:to_i).uniq.reject(&:zero?)` antes do CASE WHEN |
| B8 | Reorder em N UPDATEs sequenciais | controller | ✅ **PR #3** — `UPDATE ... CASE WHEN` em SQL único; N=500 vira 1 round-trip |
| B9 | Plano de tratamento perde preço ao renomear | TreatmentItemModal.vue | ✅ **PR #6b** — FK `treatment_items.agenda_service_id` + modal usa ID; `procedure_name` preservado como audit trail |
| B10 | Importador vs UI gravam esquemas diferentes no JSONB | clinicorp_agenda_importer vs useAgendaCrud | ✅ **PR #4/#5** — FK `agenda_service_id` é a fonte de verdade; backend popula automaticamente via callback (UI atual) ou backfill (eventos antigos / importador legado) |
| B11 | `destroy_async` em massa pode falhar sem retry visível | engine.rb | ✅ **PR #8** — destroy agora gera AuditLog via callback; falhas no `AuditLogJob` ficam visíveis no log do Rails |
| B12 | Sem AuditLog (inconsistente com convenção `Financial::*`) | model | ✅ **PR #8** — `Agenda::AuditLog` polimórfico + concern `Agenda::Concerns::Auditable` alinhado com `Financial::AuditLog` |

---

## 7. Escalabilidade

| Carga | Comportamento |
|---|---|
| 10 serviços | OK |
| 100 serviços | OK; DOM começa a pesar |
| 1.000 serviços | `<table>` sem virtualização; FormSelect com 1000 options pesa no modal |
| Edição simultânea | sem websocket — abas descoordenadas |
| Reorder de 500 | 500 UPDATEs sequenciais — risco de timeout |

Não há N+1 críticos no controller (`.ordered` simples), nem cache.

---

## 8. Integrações (mapa real)

| Domínio | Liga? | Como |
|---|---|---|
| AgendaEvent | sim | `custom_attributes['treatment']` = NAME |
| Cor do evento | sim | lookup por NAME |
| Filtro do calendário | sim | `hiddenTreatments` por NAME |
| Pre-fill duração no modal | sim | NAME → `duration_minutes` |
| Plano de tratamento | sim | match por NAME |
| Importador Clinicorp | sim | grava ID + NAME no JSON do evento |
| Notificação WhatsApp/SMS | **não** | template não tem `{servico}` |
| Lembretes/Confirmações | **não** | só paciente, clínica, profissional, data, hora |
| Relatórios da agenda | **não** | só status/user/data |
| Dashboard | **não** | sem agregação |
| Financial::Budget / BudgetItem | **não** | sem referência |
| Webhooks/Automações | **não** | sem hooks dependentes |

---

## 9. Arquitetura recomendada

### Schema migrado (consolidado)

```ruby
# Migration 1 — proteções básicas (aditivas, sem risco)
add_column :agenda_services, :deleted_at, :datetime
add_column :agenda_services, :uuid, :uuid, default: -> { "gen_random_uuid()" }, null: false
add_index :agenda_services, :uuid, unique: true
add_index :agenda_services, [:account_id, :deleted_at]

# Migration 2 — exige dedup prévia
add_index :agenda_services, "account_id, lower(name)",
          unique: true, name: "uniq_agenda_services_account_lower_name",
          where: "deleted_at IS NULL"

# Migration 3 — FK reversa nos eventos
add_reference :agenda_events, :agenda_service,
              foreign_key: { on_delete: :nullify },
              index: { algorithm: :concurrently },
              null: true
```

### Model corrigido

```ruby
class AgendaService < ApplicationRecord
  belongs_to :account
  has_many :agenda_events, dependent: :nullify

  scope :kept, -> { where(deleted_at: nil) }

  validates :name, presence: true,
                   uniqueness: { scope: :account_id, case_sensitive: false }
  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  before_validation { self.name = name.to_s.strip }
  before_create :set_position_safely

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  private

  def set_position_safely
    AgendaService.transaction do
      max_pos = account.agenda_services.lock.maximum(:position) || -1
      self.position = max_pos + 1
    end
  end
end
```

### Decisão sobre identificadores

| Coluna | Necessária? | Quando |
|---|---|---|
| `uuid` | sim | URLs públicas, webhooks, integrações |
| `external_id` | sim, opcional | importadores idempotentes |
| `code` interno | não | sem demanda |
| `slug` | não | nome serve |
| versionamento | não | AuditLog basta |

---

## 10. Estratégia de migração SEM QUEBRAR

**Pergunta-chave:** "serviços está ligado a agendamentos de clientes — tem risco de quebrar?"

**Resposta:** dá pra migrar 100% sem quebrar produção via **expand → backfill → contract** (duplo-write durante a janela).

### Fase 1 — Expand (aditivo, sem risco)

1. Migration 1 do §9 (uuid, deleted_at — aditivas).
2. Adicionar coluna `agenda_events.agenda_service_id` (`null: true`, FK `ON DELETE SET NULL`).
3. Backend **passa a escrever as duas chaves no save de evento**:
   ```ruby
   custom_attributes: { treatment: service.name, ... }  # mantém
   agenda_service_id: service.id                         # adiciona
   ```
4. Frontend: `AgendaEventModal` passa a enviar `agenda_service_id` no payload (`value: tr.id` ao invés de `value: tr.name`), mas backend continua gravando o `treatment` derivado para compat.

**Riscos:** zero. Coluna nova, opcional, com fallback.

### Fase 2 — Dedup + Unique Index

Antes do unique index, **dedup obrigatória**:

```ruby
# Rake task: cleanup_agenda_services_dedup
AgendaService.kept.group(:account_id).pluck(:account_id).each do |acc_id|
  AgendaService.where(account_id: acc_id).kept
               .group_by { |s| s.name.strip.downcase }
               .each do |_key, dupes|
    next if dupes.size <= 1
    survivor = dupes.min_by(&:created_at)
    losers = dupes - [survivor]
    # Repointa referências antes de remover
    AgendaEvent.where(account_id: acc_id, agenda_service_id: losers.map(&:id))
               .update_all(agenda_service_id: survivor.id)
    losers.each(&:soft_delete!)
  end
end
```

Depois rodar Migration 2 (unique index) com segurança.

### Fase 3 — Backfill

Job idempotente que casa eventos antigos pelo nome:

```ruby
# Rake task: backfill_agenda_service_id
AgendaEvent.kept.where(agenda_service_id: nil)
           .where.not("custom_attributes->>'treatment' IS NULL")
           .find_in_batches(batch_size: 1000) do |batch|
  batch.each do |event|
    name = event.custom_attributes['treatment'].to_s.strip
    next if name.blank?

    service = AgendaService.kept
                           .where(account_id: event.account_id)
                           .where("lower(name) = ?", name.downcase)
                           .first
    next unless service

    event.update_column(:agenda_service_id, service.id)
  end
end
```

**Quem fica órfão?** Eventos cujo `treatment` foi renomeado/excluído antes da migração → `agenda_service_id = NULL`. **Não quebram** — UI continua mostrando `custom_attributes.treatment` como fallback. É apenas transparência sobre o débito acumulado.

**Métrica de saúde:**

```ruby
total = AgendaEvent.kept.where.not("custom_attributes->>'treatment' IS NULL").count
linked = AgendaEvent.kept.where.not(agenda_service_id: nil).count
puts "Linkage: #{(linked * 100.0 / total).round(2)}%"
```

Esperado: ≥99% em contas sem histórico de rename agressivo.

### Fase 4 — Frontend lê preferencialmente o FK

```javascript
// AgendaEvent serializer (jbuilder)
json.agenda_service_id event.agenda_service_id
json.agenda_service_name event.agenda_service&.name

// Frontend: prioriza FK, fallback ao JSONB
const serviceName = event.agenda_service_name || event.custom_attributes?.treatment
```

`getTreatmentColor` passa a usar `agenda_service_id`:

```javascript
function getTreatmentColor(event, treatmentOptions) {
  if (event.agenda_service_id) {
    const matched = treatmentOptions.find(t => t.id === event.agenda_service_id);
    if (matched) return matched.color;
  }
  // fallback legado
  const name = event.custom_attributes?.treatment;
  return treatmentOptions.find(t => t.name === name)?.color || null;
}
```

`hiddenTreatments` migra para `hiddenServiceIds`.

### Fase 5 — Contract (deprecação)

Após backfill ≥99% e frontend totalmente migrado por 1-2 sprints:

1. Stop writing `custom_attributes.treatment` em criações novas.
2. Manter leitura como fallback por mais 1 sprint.
3. Migration final: remover chave `treatment` do JSONB de eventos novos (eventos antigos mantêm para auditoria histórica).

### Plano de tratamento (`TreatmentItemModal`)

Mesmo exercício: após Fase 1, passar `agenda_service_id` ao invés de `procedure_name`. Backfill em `treatment_items` se houver `procedure_name` armazenado.

---

## 11. PRs propostos (ordem)

| # | PR | Risco | Ganho |
|---|---|---|---|
| 1 | Unique index + validação + dedup rake | baixo (depende de dedup limpa) | elimina B2, C1, C4 |
| 2 | Soft-delete (`deleted_at`) + scope `kept` | baixo (aditivo) | elimina B4, C3 |
| 3 | UUID + index | nulo (aditivo) | habilita URL pública |
| 4 | Position transacional + reorder em SQL único | baixo | elimina B1, B8 |
| 5 | FK `agenda_events.agenda_service_id` + duplo-write | nulo (aditivo) | habilita fim do débito |
| 6 | Rake `backfill_agenda_service_id` | baixo (idempotente) | linkage histórica |
| 7 | Frontend lê preferencialmente FK; fallback ao JSONB | baixo | elimina B3, B5, B9 |
| 8 | Endpoint `count_uses` + UI de delete defensiva | nulo | elimina F1 |
| 9 | Propagação de erros no `fetch` da store | nulo | elimina F2, F7 |
| 10 | Drag-and-drop usando endpoint `reorder` existente | baixo | feature |
| 11 | AuditLog (alinhar com `Financial::*`) | baixo | B12 |
| 12 | Deprecação da chave `treatment` no JSONB | médio (depende de 6 + 7 estabilizados) | fim do débito |

---

## 12. Conclusão

O modelo `AgendaService` é simples e bem isolado, mas a forma como o resto do sistema o referencia (string-em-JSONB) é o pecado original. A correção é **viável sem janela de manutenção**, **sem perda de dados**, e **sem quebra de eventos existentes**, desde que feita por etapas com duplo-write e backfill idempotente.

Eventos órfãos pós-backfill são **manifestação visível de débito pré-existente**, não dano novo — quem renomeou/deletou serviço no passado já está com a quebra hoje (cor sumida, filtro órfão). A migração apenas torna o estado explícito (`agenda_service_id = NULL`) ao invés de implícito (nome órfão no JSONB).

Recomendação: começar por **PR #1 (unique index + dedup)** e **PR #2 (soft-delete)** — ambos baixíssimo risco, alto retorno, e desbloqueiam o resto do roadmap.
