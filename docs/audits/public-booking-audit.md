# Auditoria — Agendamento Público (Klivy)

- **Data:** 2026-05-14
- **Escopo:** Fluxo de agendamento online público (`/agenda/:public_id`) + visibilidade de serviços + deduplicação Contact/Patient + regras de disponibilidade + concorrência + segurança + performance.
- **Status:** Em correção (acompanhar checklist na seção 12).
- **URL pública auditada:** `http://localhost:3000/agenda/qtpzdaac`
- **Plugin principal:** `plugins/agenda`

---

## Confirmação de escopo

Quase todas as correções listadas são **exclusivas do agendamento público**. As exceções (com impacto colateral em outras áreas) estão marcadas explicitamente:

| Item | Escopo |
|---|---|
| 9.1, 9.3, 9.4, 9.5, 9.6, 9.8, 9.9, 9.10–9.15, 9.18–9.19 | ✅ Só agendamento público |
| 9.2 (EXCLUDE gist em `agenda_events`) | ⚠️ Tabela compartilhada — afeta também `AgendaEventsController` (admin) |
| 9.7 (vínculo serviço↔profissional) | ⚠️ Estrutural — exige UI nova em Configurações de Serviços |
| 9.16, 9.17 (índices/queries em `agenda_events`) | ⚠️ Beneficia todo leitor da agenda, não só o público |

---

## 0. Sumário executivo

| # | Severidade | Eixo | Achado |
|---|---|---|---|
| 1 | 🔴 Crítico | Regras | `book` revalida **só** `min_lead_time` e `future_limit`; ignora working_window, almoço, feriado e exceção que o `slots` aplica → bypass via curl |
| 2 | 🔴 Crítico | Concorrência | Sem transaction/lock/EXCLUDE gist. `.exists?` + `.create!` é TOCTOU → double-booking real |
| 3 | 🔴 Crítico | Integridade | Booking público cria `Contact` + `AgendaEvent` mas nunca cria `Patient` / `PatientAppointment` / `ContactInbox` — paciente fica órfão na UI |
| 4 | 🔴 Crítico | Tenancy | `@account = @user.accounts.first` — usuário com >1 conta pega a primeira, vazando agenda entre contas |
| 5 | 🟠 Alto | Serviço×Pro | Não há FK serviço→profissional. Endpoint `services` devolve todos da conta → paciente pode marcar serviço que esse profissional não oferece |
| 6 | 🟠 Alto | Segurança | Sem rate-limit por `public_id`, sem captcha/honeypot. CPF em plaintext em `AgendaEvent.description` — violação LGPD |
| 7 | 🟠 Alto | Dedup | Sem `ContactInboxWithContactBuilder`, sem transação isolada, sem retry em `RecordNotUnique`. CPF buscado em JSONB sem índice (full-scan) |
| 8 | 🟡 Médio | Regras | `book` não valida alinhamento ao grid (aceita `time=10:07`); não valida que `service.duration_minutes` cabe na janela do dia/almoço |
| 9 | 🟡 Médio | Performance | `slots` faz 1 query EXISTS por slot (~48/dia). 30 dias = ~1.440 queries. Sem batch endpoint |
| 10 | 🟡 Médio | UX | `event_id` não retornado ao paciente — sem rastreabilidade, sem cancelar/reagendar via link público |

---

## 1. Arquitetura atual

### Fluxo end-to-end

```
Usuário abre /agenda/qtpzdaac
        ↓
agenda_booking#show (HTML server-side, ERB + vanilla JS embarcado)
        ↓ fetch
GET  /public/api/v1/agenda/:public_id            → show(user, config)
GET  /public/api/v1/agenda/:public_id/services   → services[]
GET  /public/api/v1/agenda/:public_id/slots      → slots[]   (por dia, 1 req)
POST /public/api/v1/agenda/:public_id/book       → cria AgendaEvent
```

### Endpoints

- [public_controller.rb:4-18](../../app/controllers/public/api/v1/agenda/public_controller.rb#L4-L18) — `show`
- [public_controller.rb:24-35](../../app/controllers/public/api/v1/agenda/public_controller.rb#L24-L35) — `services`
- [public_controller.rb:37-44](../../app/controllers/public/api/v1/agenda/public_controller.rb#L37-L44) — `slots`
- [public_controller.rb:46-173](../../app/controllers/public/api/v1/agenda/public_controller.rb#L46-L173) — `book`
- Rotas: [config/routes.rb:1013-1018](../../config/routes.rb#L1013-L1018)

### Models / tabelas envolvidas

- `AgendaService` (soft-delete, `kept`/`ordered`, advisory lock em `position`) — [plugins/agenda/app/models/agenda_service.rb](../../plugins/agenda/app/models/agenda_service.rb)
- `AgendaEvent` (soft-delete, callbacks de timeline + `assign_patient_responsible_if_missing`) — [plugins/agenda/app/models/agenda_event.rb](../../plugins/agenda/app/models/agenda_event.rb)
- `AgendaOnlineConfig` (1:1 por account) — [plugins/agenda/app/models/agenda_online_config.rb](../../plugins/agenda/app/models/agenda_online_config.rb)
- `AgendaSetting` (1:1 por account, `week_days`/`holidays`/`exceptions` em JSONB) — [plugins/agenda/app/models/agenda_setting.rb](../../plugins/agenda/app/models/agenda_setting.rb)
- `BeclinicCore::UserProfile.agenda_public_id` (unique) — [plugins/beclinic_core/app/models/beclinic_core/user_profile.rb](../../plugins/beclinic_core/app/models/beclinic_core/user_profile.rb)
- `Contact` (UNIQUE per-account em `email`, `phone_number`, `identifier`)
- `Patient` (FK `contact_id` optional) — [plugins/patients/app/models/patient.rb](../../plugins/patients/app/models/patient.rb)
- `PatientAppointment` (FK `agenda_event_id` optional) — [plugins/patients/app/models/patient_appointment.rb](../../plugins/patients/app/models/patient_appointment.rb)

### Builders / actions que o controller **deveria** usar e não usa

- `ContactInboxWithContactBuilder` — [app/builders/contact_inbox_with_contact_builder.rb](../../app/builders/contact_inbox_with_contact_builder.rb) (dedup com retry em `RecordNotUnique`, transação isolada, cria `ContactInbox`)
- `ContactIdentifyAction` / `ContactMergeAction` — [app/actions/contact_identify_action.rb](../../app/actions/contact_identify_action.rb)

---

## 2. Eixo 1 — Visibilidade de serviços

### Achados

- ✅ `services` filtra `kept` (soft-delete respeitado) — [public_controller.rb:25](../../app/controllers/public/api/v1/agenda/public_controller.rb#L25)
- ✅ `services` escopa por `@account` — sem vazamento entre clínicas
- ❌ **Não existe flag de visibilidade pública** (`public_visible`/`online_bookable`). Todo serviço `kept` aparece — clínica não tem como ter serviço "interno-only"
- ❌ **Não existe vínculo serviço → profissional** (sem `agenda_service_users`). Link `/agenda/qtpzdaac` (Dr. A) mostra serviços que só Dr. B faz. `book` não valida combinação
- ⚠️ Endpoint `services` **não verifica `agenda_online_config.enabled`** — clínica desliga booking, mas catálogo continua exposto. Vazamento de pricing/duração mesmo com agendamento desligado
- ✅ Frontend re-fetcha slots ao trocar serviço, cache `date|service_id` correto — [app/views/agenda_booking/show.html.erb](../../app/views/agenda_booking/show.html.erb) (L446–L536)
- ✅ Sem localStorage/Pinia → sem estado stale entre sessões

### Risco

- **Médio** em multi-profissional (paciente pode escolher serviço "errado" para aquele profissional, criando inconsistência `agenda_service_id` ≠ `user_id`)
- **Baixo** em vazamento (catálogo de serviços/preços é semipúblico mesmo)

---

## 3. Eixo 2 — Deduplicação de contatos/pacientes

### Lógica atual ([public_controller.rb:109-135](../../app/controllers/public/api/v1/agenda/public_controller.rb#L109-L135))

1. Normaliza `phone` (`.gsub(/\D/,'')`), `cpf` (idem), `email.presence`
2. Busca por: CPF → phone (`+55…`) → email (todos com guard `.present?`)
3. Se não achar e `allow_new_patients=true`, cria `Contact` direto

### Cenários

| # | Cenário | Resultado hoje | Risco |
|---|---|---|---|
| A | Mesmo telefone, formatos diferentes | Match (ambos normalizados a `+5511…`) | ✅ Baixo |
| B | Mesmo CPF, pontuação diferente | Match (normalização nos 2 lados) | ✅ Baixo |
| C | Email vazio em ambos | `if email.present?` protege contra `find_by(email: nil)` | ✅ OK |
| D | Mesmo telefone, **nome diferente** | Reutiliza contato; **NÃO atualiza** nome/email stale | 🟡 Médio |
| E | Contact existe sem Patient (legado Clinicorp) | `AgendaEvent` criado; **Patient nunca criado** | 🔴 Alto |
| F | Contact existe sem ContactInbox | `AgendaEvent` criado, **ContactInbox nunca criado** → contato órfão na UI de Conversas | 🔴 Alto |
| G | 2 requests simultâneos com novo paciente | Ambos passam no `find_by`; só 1 vence pelo UNIQUE; o outro **explode em 500** ("Erro interno") | 🔴 Alto |
| H | CPF buscado por JSONB | `custom_attributes->>'cpf' = ?` sem índice → **full-table scan** | 🟡 Médio |

### Gap arquitetural

- ❌ Não usa `ContactInboxWithContactBuilder` (que já tem transação isolada + retry em `RecordNotUnique` + cria `ContactInbox`)
- ❌ Sem hook `Contact created → Patient.find_or_create_by(contact_id:)`. `AgendaEvent.assign_patient_responsible_if_missing` ([agenda_event.rb:264-273](../../plugins/agenda/app/models/agenda_event.rb#L264-L273)) só roda se Patient JÁ existe
- ❌ Sem criação automática de `PatientAppointment` quando `AgendaEvent` é criado pelo fluxo público → aba "Meus Agendamentos" do paciente fica **vazia**
- ❌ Sem normalização de DDI dinâmico (hardcoded `+55`)
- ❌ Sem validador CPF (módulo 11) — aceita `00000000000`
- ❌ Sem índice em `contacts.custom_attributes->>'cpf'`

---

## 4. Eixo 3 — Regras de agenda

### Comparação `slots` vs `book`

| Regra | `slots` valida? | `book` valida? | Bypass? |
|---|---|---|---|
| `enabled` (`agenda_online_config`) | ❌ (não checa) | ✅ L47 | — |
| `min_lead_time_minutes` | ✅ L228–L229 | ✅ L82–L87 | — |
| `future_limit_days` | ✅ L208–L209 | ✅ L89–L94 | — |
| `working_window` (dia/horário) | ✅ L273–L300 | ❌ | 🔴 sim — POST `time=03:00` em domingo cria evento |
| `block_lunch_break` | ✅ L250–L254 | ❌ | 🔴 sim |
| `blocked_by_holiday` | ✅ L302–L308 | ❌ | 🔴 sim — POST em 25/12 |
| `blocked_by_exception` (folgas) | ✅ L310–L319 | ❌ | 🔴 sim — POST durante recesso |
| Alinhamento ao grid (`time.min % slot_interval`) | implícito | ❌ | 🟡 sim — POST `time=10:07` |
| `service.duration_minutes` cabe no expediente | ✅ L241 | ❌ | 🟡 sim — serviço de 60min começando 19:30 |
| Serviço pertence à conta | — | ✅ `fetch_service` L188–L191 | — |
| Serviço pertence ao profissional | ❌ (não existe FK) | ❌ | 🟠 sim |

### Timezone

- ✅ `config.time_zone = 'Brasilia'` em [config/application.rb](../../config/application.rb), `Time.use_zone('America/Sao_Paulo')` no controller
- ✅ Brasil sem horário de verão desde 2019 → sem off-by-one
- ⚠️ `starts_at`/`ends_at` são `datetime` (não `timestamptz`). Atual config funciona; migrações futuras precisam de cuidado

### Profissionais e serviços

- ❌ Sem tabela de vínculo. `agenda_setting` é por **account**, não por user → 5 profissionais com horários diferentes precisam compartilhar 1 configuração
- ❌ Nenhum endpoint pra bloqueios ad-hoc (`agenda_blocks`) — só `exceptions` em JSONB editado por admin

---

## 5. Eixo 4 — Concorrência e integridade

### Pontos de falha

- ❌ `book` não está em `transaction do … end`
- ❌ Sem `lock!`/`with_lock`/`SELECT FOR UPDATE`
- ❌ Sem advisory lock (existe um em `AgendaService.set_position` mas não em `AgendaEvent`)
- ❌ Sem `EXCLUDE USING gist` com `tstzrange` em `agenda_events`
- ❌ Sem unique index em `(account_id, user_id, starts_at, ends_at) WHERE deleted_at IS NULL`

### Cenário comprovado de double-booking

```
t=0  req1.exists? → false (slot livre)
t=1  req2.exists? → false (req1 ainda não commitou)
t=2  req1.create! → ok [10:00-10:30]
t=3  req2.create! → ok [10:15-10:45]   ← OVERLAP. Banco aceita.
```

Frontend de cada paciente recebe 201, mas a agenda da clínica fica corrompida.

### Integridade de dados após booking público

- Contact criado mas **sem `ContactInbox`** → não aparece na inbox do Chatwoot, nenhum canal mensageiro pode responder
- **`Patient` nunca criado** → aba Pacientes mostra Contact "fantasma", prontuário vazio, timeline incompleta
- **`PatientAppointment` nunca criado** → "Meus Agendamentos" do paciente fica em branco mesmo após booking sucedido
- `AgendaEvent.custom_attributes['treatment']` grava nome do serviço para legado — duplo-write OK, mas fragiliza se o serviço for renomeado depois

---

## 6. Eixo 5 — Segurança

- 🔴 **CPF em plaintext em `description` do AgendaEvent** ([public_controller.rb:153](../../app/controllers/public/api/v1/agenda/public_controller.rb#L153)): `"Agendamento realizado online. CPF: #{cpf}. Telefone: #{phone}."`. Aparece em logs, exports e em qualquer view da agenda — **violação LGPD**
- 🔴 **Multi-tenancy frágil**: `@account = @user.accounts.first` ([L179](../../app/controllers/public/api/v1/agenda/public_controller.rb#L179)). Padrão do projeto exige scoping explícito (`feedback_multi_tenant.md`)
- 🟠 **Sem rate limit em `/slots` e `/book`** — Rack::Attack global (3000/min/IP) é praticamente inexistente
- 🟠 **Sem captcha/honeypot** — booking público é alvo trivial de spam
- 🟠 **`public_id` 8 chars** (entropia ~41 bits, base alfanumérica) — não é segredo, mas sem rate limit vira vetor de enumeração
- 🟡 **Sem idempotency key** — double-click ou retry de rede cria 2 contatos (ou 2 eventos, dependendo do estado)
- 🟡 **`patient&.to_unsafe_h`** ([L54](../../app/controllers/public/api/v1/agenda/public_controller.rb#L54)) ignora strong params
- 🟡 **`rescue StandardError`** ([L170-L172](../../app/controllers/public/api/v1/agenda/public_controller.rb#L170-L172)) engole erros silenciosamente
- ✅ XSS protegido no frontend pela função `esc()` na ERB

---

## 7. Eixo 6 — Performance

| Item | Status | Detalhe |
|---|---|---|
| `services` map em memória | ✅ | sem N+1 |
| `slots` por dia | ⚠️ | 1× EXISTS por slot. 12h × slot=15min = 48 queries/dia |
| 30 dias de calendário | ❌ | ~1.440 queries — gargalo em clínica cheia |
| CPF lookup JSONB | ❌ | full-scan, sem índice |
| Sem batch `/slots/range` | ❌ | frontend faz 1 req por dia ao navegar |
| Indexes em `agenda_events` | ⚠️ | tem `(account_id, user_id, starts_at)` mas não considera `deleted_at` |

---

## 8. Eixo 7 — UX e consistência

- ✅ Step 1/2/3 com loading, máscaras CPF/telefone, escapement HTML, ARIA, `prefers-reduced-motion`, responsivo
- ✅ Cache de slots por `date|service_id` invalidado ao trocar serviço
- ✅ Botão "Confirmar" disabled durante submit
- ⚠️ Sem indicação de fuso na UI — paciente em Manaus pode achar que é horário local
- ❌ Step 4 (sucesso) não mostra `event_id` — sem rastreabilidade, sem link de cancelamento/reagendamento
- ❌ Validação de CPF é só "11 dígitos" — aceita `11111111111`
- ⚠️ Mensagem genérica "Erro interno" do `rescue StandardError` confunde em casos recuperáveis

---

## 9. Correções priorizadas

Cada item lista: **causa raiz · solução mínima · solução ideal · risco de regressão · arquivos**.

### P0 — Críticos

#### 9.1 `book` não revalida regras de disponibilidade ✅ **APLICADO (2026-05-14)**
- **Escopo:** ✅ Só agendamento público
- **Causa:** `book` confiava que o frontend já filtrou; só revalidava lead-time e future-limit
- **Estratégia aplicada (mínima):** após os fast-paths de `min_lead` e `future_limit` (mantidos por terem mensagem de erro específica e melhor UX), o `book` chama `calculate_slots(starts_at.to_date, service: service)` e exige que `requested_time = starts_at.strftime('%H:%M')` esteja na lista. Essa única validação cobre, de uma vez, **todas** as regras que antes só rodavam no `slots`:
  - working_window (dia/horário aberto)
  - block_lunch_break
  - blocked_by_holiday
  - blocked_by_exception (folgas/recesso)
  - alinhamento ao grid (slot_interval_minutes) — fecha também **9.10**
  - serviço cuja duração não cabe no expediente
  - conflito com outro evento já marcado (substitui o `.exists?` antigo)
- **Arquivos:** [public_controller.rb#L105-L124](../../app/controllers/public/api/v1/agenda/public_controller.rb#L105-L124)
- **Plano futuro (ideal):** extrair `Agenda::Availability::Checker` (service object) usado por `slots` e `book` — hoje a duplicação é trivial (1 chamada de método), mas vale quando aparecer um 3º consumidor (ex.: API de admin).
- **Teste manual (executado 2026-05-14, todos os 5 cenários passaram em local):**
  1. POST com `date=2026-05-17 time=10:00` (domingo fechado) → **409** ✅
  2. POST com `date=2026-05-15 time=03:00` (fora do expediente) → **409** ✅
  3. POST com `date=2026-05-15 time=10:07` (grid `slot_interval=15`) → **409** ✅
  4. POST com `date=2026-05-15 time=12:30` (almoço bloqueado) → **409** ✅
  5. POST com `date=2026-05-15 time=10:00` (válido) → **201 created**, `event_id=8327` ✅

#### 9.2 Race condition em `book` ✅ **APLICADO (2026-05-14, Estratégia A — advisory lock)**
- **Escopo:** ✅ Só agendamento público (admin não tocado nesta PR)
- **Causa:** TOCTOU entre revalidação `calculate_slots` (9.1) e `agenda_events.create!`. Dois POSTs concorrentes para o mesmo slot ambos passavam na revalidação e criavam eventos sobrepostos.
- **Estratégia escolhida (A — advisory lock):** dentro da transação do `book`, antes da revalidação, executa `SELECT pg_advisory_xact_lock(hashtext('agenda_event_book'), <user_id>)`. Bookings concorrentes **para o mesmo profissional** são serializados (o 2º espera o 1º commitar/rollar). Outros profissionais não são afetados. Lock é liberado automaticamente no commit/rollback da transação (`_xact_`).
- **Reorganização exigida:** a revalidação `calculate_slots` foi **movida para dentro** da transação, depois do lock — antes ficava fora, criando uma janela TOCTOU que o lock por si só não fecharia. Mesma transação também envelopa Contact resolution, ContactInbox, Patient, AgendaEvent e PatientAppointment — tudo-ou-nada.
- **Arquivo:** [public_controller.rb#L130-L220](../../app/controllers/public/api/v1/agenda/public_controller.rb#L130-L220)
- **Por que NÃO `EXCLUDE USING gist`:** investigação 2026-05-14 mostrou **1.294 pares de overlap `consultation × consultation`** apenas em `user_id=36` (10 users com overlap, total ~5.000 pares). PostgreSQL não aceita `EXCLUDE NOT VALID`, então a constraint física quebraria criação até limpeza completa — risco alto, decisão manual sobre quais dos 1.294 manter. **Adiada** para item separado de qualidade de dados (§11).
- **Limitação conhecida:** o lock fecha o race no fluxo público. Outros caminhos de criação (admin `AgendaEventsController`, importação Clinicorp, scripts ad-hoc) **continuam vulneráveis** — uma migration futura aplicando advisory lock também nesses caminhos (ou trigger BEFORE INSERT/UPDATE no banco) fecha o último vetor.
- **Teste manual (executado 2026-05-14):** 2 POSTs concorrentes para o mesmo slot `2026-05-15 16:00`:
  - PIDs `73141` e `73142` disparados simultaneamente em background, sincronizados via `wait`
  - Output: `code=201` + `code=409` (um de cada) ✅
  - `event_id=8332` criado (único)
  - Query `AgendaEvent.kept.where(account_id: 31, user_id: 33, starts_at: 2026-05-15 16:00)` → `events_at_16h=1` ✅
  - Sem o lock, ambos os curls retornariam 201 (double-booking).

#### 9.3 Booking público não cria Patient/ContactInbox/PatientAppointment ✅ **APLICADO (2026-05-14)**
- **Escopo:** ✅ Só agendamento público
- **Causa:** Controller montava `Contact` + `AgendaEvent` direto, deixando o paciente "fantasma" na UI da clínica (sem prontuário, sem Conversas, sem "Meus Agendamentos").
- **Estratégia aplicada:** envolve criação numa `ActiveRecord::Base.transaction` com 4 etapas:
  1. **ContactInbox** via `ContactInboxBuilder.new(contact:, inbox: @account.inboxes.first).perform` ([public_controller.rb#L307-L324](../../app/controllers/public/api/v1/agenda/public_controller.rb#L307-L324)). Reusa o builder do core (gera source_id por channel_type, idempotente, retry em RecordNotUnique). Em conta com WhatsApp QR, vincula source_id = phone sem `+` → paciente aparece em Caixa de Entrada e pode receber mensagem. Conta sem inbox: log warn, **não falha** o booking (estado pré-9.3 preservado para esse caso de borda).
  2. **Patient** via `ensure_patient_for` ([public_controller.rb#L334-L358](../../app/controllers/public/api/v1/agenda/public_controller.rb#L334-L358)) — `find_by(account_id, contact_id)` + merge não-destrutivo (preenche só campos vazios; nome nunca sobrescrito); se novo, `responsible_professional_id = @user.id` e `patient_status = 'novo'`. Retorna `[patient, was_just_created]`.
  3. **AgendaEvent** (já existente).
  4. **PatientAppointment** — `appointment_type = 'avaliacao'` se Patient era novo, `'retorno'` se já existia; `status='scheduled'`; vincula `agenda_event_id` e `professional_id=@user.id`.
- **Compatibilidade com callback existente:** `AgendaEvent.assign_patient_responsible_if_missing` ([agenda_event.rb#L264-L273](../../plugins/agenda/app/models/agenda_event.rb#L264-L273)) continua funcionando — Patient novo já vem com responsible setado, callback é no-op; Patient antigo sem responsible continua sendo compensado.
- **Plano futuro (ideal):** quando 9.7 (vínculo serviço↔profissional) entrar, extrair tudo para `Agenda::PublicBookingService`.
- **Teste manual (executado 2026-05-14):**
  - POST paciente novo → `event_id=8330`, `contact_id=2868`, `patient_id=2503` (`status=novo`, `responsible_professional_id=33`), `patient_appointment_id=1` (**primeiro do sistema** — confirma que antes da 9.3 a tabela nunca era populada pelo booking público), `appointment_type=avaliacao`, `contact_inbox_id=803` (`inbox_id=13`, `source_id="5511955554444"`) ✅
  - POST 2 mesmo paciente → 2 PatientAppointments, **1** ContactInbox, **1** Patient (idempotência via Builder + `find_by`) ✅

#### 9.4 Multi-tenant: `@user.accounts.first` ✅ **APLICADO (2026-05-14, Opção A — estrutural)**
- **Escopo:** ✅ Só agendamento público (mas adiciona coluna em tabela compartilhada `beclinic_user_profiles`)
- **Causa:** Code assumia que user só pertence a 1 account
- **Estratégia aplicada (A):** `beclinic_user_profiles.account_id` é a fonte única de verdade para qual conta o link público representa. Cada profile vira par (user, account); user em N contas terá N profiles com N `agenda_public_id` distintos.
- **Arquivos alterados:**
  - **Migration:** [db/migrate/20260514100001_add_account_to_beclinic_user_profiles.rb](../../db/migrate/20260514100001_add_account_to_beclinic_user_profiles.rb) — `add_reference :account`, backfill via `account_users` (preserva escolha atual `.first`), `DELETE` profiles órfãos, `NOT NULL`, unique index `(user_id, account_id)`.
  - **Model:** [plugins/beclinic_core/app/models/beclinic_core/user_profile.rb](../../plugins/beclinic_core/app/models/beclinic_core/user_profile.rb) — `belongs_to :account`.
  - **Callback:** [plugins/agenda/lib/agenda/engine.rb](../../plugins/agenda/lib/agenda/engine.rb) — `ensure_agenda_public_id` agora seta `account_id` antes de salvar; adia silenciosamente se o user ainda não tem `account_users` (raríssimo, recuperável).
  - **Controllers:**
    - [app/controllers/public/api/v1/agenda/public_controller.rb#L195-L204](../../app/controllers/public/api/v1/agenda/public_controller.rb#L195-L204) — busca `BeclinicCore::UserProfile.find_by!(agenda_public_id:)` e deriva `@user`/`@account` do profile.
    - [app/controllers/agenda_booking_controller.rb#L7-L13](../../app/controllers/agenda_booking_controller.rb#L7-L13) — mesma mudança no fluxo HTML.
- **Risco:** Médio. Backfill **preserva comportamento atual** (mesma escolha de `.first`); regressão só ocorreria se algum user em produção tivesse profile com `account_id` que **não** bate com `account_users.first` — caso teórico que requer ação manual após deploy.
- **Teste manual:**
  1. Rodar `rails db:migrate` em staging com dados reais (ou snapshot de prod). Migration deve concluir sem erro; conferir `SELECT COUNT(*) FROM beclinic_user_profiles WHERE account_id IS NULL` = 0.
  2. Abrir um link público `/agenda/:public_id` válido → deve carregar normalmente.
  3. Criar um novo user via fluxo normal (signup/AccountBuilder) → callback `ensure_agenda_public_id` deve criar profile com `account_id` correto; `BeclinicCore::UserProfile.last.account_id` não pode ser nulo.
  4. Rollback (`rails db:rollback`) deve funcionar — `down` reverte `add_reference`.

### P1 — Altos

#### 9.5 Endpoint `services` não respeita `enabled` ✅ **APLICADO (2026-05-14)**
- **Escopo:** ✅ Só agendamento público
- **Mínima:** `return render json: { services: [] }, status: :forbidden unless @account.agenda_online_config&.enabled` no topo do método
- **Aplicado em:** [public_controller.rb:24-43](../../app/controllers/public/api/v1/agenda/public_controller.rb#L24-L43) — gate retorna `403 {error: 'Online booking is disabled'}` antes de qualquer leitura de catálogo.
- **Teste manual:** desligar `agenda_online_config.enabled` no admin → `GET /public/api/v1/agenda/:public_id/services` deve responder 403.

#### 9.6 LGPD: CPF em `description` ✅ **APLICADO (2026-05-14)**
- **Escopo:** ✅ Só agendamento público
- **Mínima:** Mover CPF para `custom_attributes` do evento; remover de `description`
- **Arquivos:** [public_controller.rb:137-167](../../app/controllers/public/api/v1/agenda/public_controller.rb#L137-L167)
- **Aplicado:** `description` agora é apenas `"Agendamento realizado online."` (+ observações se houver). CPF/telefone permanecem onde devem estar (`Contact.phone_number`, `Contact.custom_attributes['cpf']`). `AgendaEvent.custom_attributes` recebe `{ source: 'public_booking', treatment: <nome se houver>, observations: <se houver> }` — estruturado para serializer mascarar e LGPD exportar/excluir.
- **Teste manual (executado 2026-05-14, AgendaEvent #8327):**
  - `description = "Agendamento realizado online."` ✅ (sem CPF, sem telefone)
  - `custom_attributes = {"source" => "public_booking"}` ✅
  - `contact.phone_number = "+5511923652248"` ✅ (telefone preservado no Contact, onde deve estar)
  - `contact.custom_attributes["cpf"] = nil` ⚠️ — *não é regressão da 9.6*; é manifestação dos itens **9.8 + 9.15**.
- **Achado colateral grave (2026-05-14):** o teste 5 expôs cenário D do §3 com impacto **maior do que estimado**. Contact #1876 (`name: "Leandro L. | Klivy"`, criado 29/04/2026) foi reusado por telefone; o evento ficou com `title: "Consulta – Teste OK"` mas `contact.name: "Leandro L. | Klivy"`. **A clínica vê título de um paciente e dados de outro.** Promover **9.8 + 9.15** de P1/P2 para próxima PR prioritária — não é estética, é vinculação errada de agendamento.

#### 9.7 Serviço sem vínculo a profissional ✅ **APLICADO (2026-05-14, backend-only)**
- **Escopo:** ⚠️ Estrutural — backend nesta PR, UI fica para próxima
- **Estratégia aplicada:** tabela de junção `agenda_service_users (agenda_service_id, user_id)` + associations + filtro/validação nos endpoints públicos com **fallback de compat**: serviço sem nenhum vínculo (estado pré-9.7 ou clínica que não configurou) continua acessível a todos os profissionais. Com 1+ vínculos, só os listados.
- **Arquivos:**
  - **Migration:** [db/migrate/20260514100003_create_agenda_service_users.rb](../../db/migrate/20260514100003_create_agenda_service_users.rb) — tabela + unique index `(agenda_service_id, user_id)`.
  - **Model:** [plugins/agenda/app/models/agenda_service_user.rb](../../plugins/agenda/app/models/agenda_service_user.rb) (novo).
  - **AgendaService:** [plugins/agenda/app/models/agenda_service.rb](../../plugins/agenda/app/models/agenda_service.rb) — `has_many :agenda_service_users` + `has_many :professionals, through:` + helper `offered_by?(user_id)` com fallback de compat.
  - **User:** [plugins/agenda/lib/agenda/engine.rb](../../plugins/agenda/lib/agenda/engine.rb) — `class_eval` adiciona `has_many :agenda_services, through:`.
  - **public_controller:** [app/controllers/public/api/v1/agenda/public_controller.rb](../../app/controllers/public/api/v1/agenda/public_controller.rb) — `services_for_current_user` filtra via `LEFT JOIN` numa query; `fetch_service` retorna `nil` (fail-soft com log warn) se serviço não é oferecido pelo profissional do link, caindo no fluxo legado em vez de bloquear o booking.
- **Pendência:** UI no admin (Configurações → Serviços) com seletor de profissionais por serviço. Sem ela, a feature existe mas só é ativada manualmente via console (`AgendaServiceUser.create!(...)`). PR separada.
- **Teste manual (executado 2026-05-14):**
  - Setup: conta 31 com 14 users, 2.048 serviços `kept`, link público `qtpzdaac` aponta para user 33.
  - Sem vínculos: GET `/services` → 2.048 serviços (compat preservada) ✅
  - Vinculado `svc_id=11 ("Avaliação")` ao `user_id=32` (NÃO o do link): GET `/services` pelo link → **2.047** serviços (id=11 excluído, primeiro item agora é id=13). Diferença de exatamente 1 ✅
  - POST `/book` com `service_id` vinculado a outro profissional → log `"Service rejected"` + evento criado com `agenda_service_id=nil` (fail-soft funcionou).

#### 9.8 Dedup robusta ✅ **APLICADO (2026-05-14)**
- **Escopo:** ✅ Só agendamento público (+ 1 índice em `contacts` que beneficia qualquer consumidor que filtre por CPF)
- **Estratégia aplicada (mínima):** método privado `resolve_or_create_contact` em [public_controller.rb#L232-L268](../../app/controllers/public/api/v1/agenda/public_controller.rb#L232-L268) envolve lookup + create em `ActiveRecord::Base.transaction(requires_new: true)`; `rescue ActiveRecord::RecordNotUnique` faz retry uma vez (cobre 2 requests simultâneos criando o mesmo Contact pelo telefone — o 2º antes explodia 500, agora cai no lookup e reusa).
- **Índice:** migration [db/migrate/20260514100002_add_cpf_index_to_contacts.rb](../../db/migrate/20260514100002_add_cpf_index_to_contacts.rb) cria `index_contacts_on_custom_attrs_cpf` em `(custom_attributes->>'cpf') WHERE custom_attributes ? 'cpf'`. Usa `CREATE INDEX CONCURRENTLY` para não travar writes em produção (`disable_ddl_transaction!`).
- **Plano futuro (ideal):** migrar para `ContactInboxWithContactBuilder` quando 9.3 entrar (que vai criar `ContactInbox` também). Hoje seria escopo grande demais.
- **Teste manual:** simular 2 POSTs simultâneos via `xargs -P 2`:
  ```bash
  for i in 1 2; do
    curl -s -X POST http://localhost:3000/public/api/v1/agenda/qtpzdaac/book \
      -H 'Content-Type: application/json' \
      -d '{"date":"2026-05-15","time":"14:00","patient":{"first_name":"Novo","last_name":"Race","phone":"11999998888","cpf":"99999999999"}}' &
  done; wait
  ```
  Esperado: 1 retorna `201`, o outro retorna `409` (slot já reservado). **Nenhum** deve retornar `500`.
- **Teste manual executado 2026-05-14:**
  - Migration `CONCURRENTLY` rodou em 19ms, `indice_cpf_existe: true` ✅
  - POST com paciente novo (CPF `11122233344`) → `event_id=8328` ✅
  - POST 2 com mesmo telefone mas `name="Outro Nome"` e `cpf="99988877766"` → `event_id=8329` (reusou Contact) ✅
  - `contact.name="Paciente Novo"` (não sobrescreveu) ✅
  - `contact.custom_attributes["cpf"]="11122233344"` (CPF divergente ignorado) ✅
  - CPF mismatch logado em `Rails.logger.warn` (sem PII no log) ✅

#### 9.9 Rate limit em `/book` e `/slots` ✅ **APLICADO (2026-05-14)**
- **Escopo:** ✅ Só agendamento público
- **Arquivo:** [config/initializers/rack_attack.rb#L237-L266](../../config/initializers/rack_attack.rb#L237-L266)
- **Throttles aplicados** (todos ENV-tunáveis no padrão do projeto):
  - `agenda_public/book/ip` — 10 POSTs/hora por IP (`RATE_LIMIT_AGENDA_PUBLIC_BOOK_IP`)
  - `agenda_public/book/public_id` — 30 POSTs/hora por `public_id` (defesa contra IPs rotativos mirando 1 profissional)
  - `agenda_public/slots/ip` — 120 GETs/hora por IP
  - `agenda_public/slots/public_id` — 600 GETs/hora por `public_id`
- **Atenção:** Rack::Attack está **desligado por padrão em dev/test** (linha 267 do arquivo: `Rails.env.production? ? … : false`). Para testar localmente, exportar `ENABLE_RACK_ATTACK=true` e setar `Rack::Attack.enabled = true` no `console`/spec.
- **Teste manual em produção:** 11 POSTs seguidos para `/book` do mesmo IP → o 11º responde `429 Too Many Requests`.

### P2 — Médios

- **9.10** Alinhamento ao grid no `book` — ✅ **APLICADO (2026-05-14)** junto com 9.1 (coberto pela revalidação via `calculate_slots`)
- **9.11** Retornar `event_id` no JSON de sucesso; permitir lookup `GET /public/api/v1/agenda/:public_id/events/:id` com token assinado — ✅ só público
- **9.12** Validar CPF (módulo 11) backend — ✅ **APLICADO + TESTADO (2026-05-14)**. Método privado `valid_cpf?` em [public_controller.rb](../../app/controllers/public/api/v1/agenda/public_controller.rb) (algoritmo oficial Receita Federal: rejeita comprimento ≠ 11, todos dígitos iguais, DV1/DV2 que não fecham). Gate no topo do `book` — se `cpf` veio e é inválido, responde **422** antes de qualquer query. CPF continua opcional (front decide obrigatoriedade via `agenda_online_config.form_fields`). **Testes:** `00000000000`/`11111111111`/`12345678900` → 422; `11144477735` (válido) → 201; vazio → 201.
- **9.11** Cancelar agendamento via link com token assinado — ✅ **APLICADO (2026-05-15)**. POST `/public/api/v1/agenda/:public_id/book` agora retorna `cancel_token` (HMAC via `Rails.application.message_verifier(:agenda_public_booking)`, não-falsificável). Dois novos endpoints: `GET /public/api/v1/agenda/booking/:token` (mostra detalhes do agendamento + flag `cancellable`) e `POST .../booking/:token/cancel` (paciente cancela, status vira `cancelled`, registra `cancelled_via_public_link_at` em `custom_attributes`). Regras hard-coded em `cancellation_block_reason`: já cancelado é no-op (idempotente, 200), `completed`/`no_show`/`arrived`/`in_progress` retorna 422, dentro do `min_lead_time_minutes` ou no passado retorna 422 com mensagem específica. **Step 4** da UI ([show.html.erb](../../app/views/agenda_booking/show.html.erb)) ganha botão "Cancelar este agendamento" + confirmação + feedback de sucesso/erro.

- **9.13** Endpoint batch `/slots_range?from=…&to=…` — ✅ **APLICADO + TESTADO (2026-05-15)**. Novo endpoint público em [public_controller.rb](../../app/controllers/public/api/v1/agenda/public_controller.rb#slots_range) que aceita `from`/`to` (YYYY-MM-DD) e devolve `{ slots: { "YYYY-MM-DD" => [...] } }`. Limite de range = 60 dias (alinhado com `future_limit_days` default). Otimização: busca todos os AgendaEvents do range numa única query (`events_cache`) e passa para `calculate_slots`, que aceita o cache opcional e filtra em memória por dia. Resultado: 30 dias = **1 query** no banco em vez de 30. Rota registrada em [config/routes.rb](../../config/routes.rb). **Testes:** range 7 dias (sex 9 slots, sáb 16, dom 0 fechado, seg-qui 44 cada) ✅; com `service_id` reduz slots conforme duração ✅; ranges inválidos (invertido / >60d / data malformada) retornam 400 com mensagem clara.
- **9.14** Substituir `rescue StandardError` por `rescue` específico + reporter — ✅ **APLICADO (2026-05-14)**. Rescue chain agora separa: `RecordInvalid` (422), `RecordNotUnique` (409 — chega aqui significa bug no retry de 9.8), `StatementInvalid`/`PG::Error` (503), `ParameterMissing` (422), e fallback `StandardError` com `Rails.error.report(e, context: …)` para Sentry/Honeybadger via Rails 7.1 Error Reporter (no-op se nenhum reporter configurado). Todas as branches loggam `account_id` + `public_id` (sem PII).
- **9.15** Atualizar Contact existente — ✅ **APLICADO (2026-05-14)** junto com 9.8 (merge não-destrutivo em `merge_contact_with_form_data` em [public_controller.rb#L278-L305](../../app/controllers/public/api/v1/agenda/public_controller.rb#L278-L305); só preenche campos vazios, CPF divergente vira warning sem overwrite, mudanças logadas em `Rails.logger`)

### P3 — Performance/UX

- **9.16** Índice parcial em `agenda_events` — ✅ **APLICADO (2026-05-14)**. Migration [db/migrate/20260514100004_add_partial_index_on_agenda_events_kept.rb](../../db/migrate/20260514100004_add_partial_index_on_agenda_events_kept.rb) cria `index_agenda_events_kept_on_account_user_starts_at` em `(account_id, user_id, starts_at) WHERE deleted_at IS NULL`. Usa `CREATE INDEX CONCURRENTLY` + `disable_ddl_transaction!`. Beneficia: `calculate_slots` (público), `AgendaEventsController#index` com filtro de range, qualquer leitura de agenda por profissional+período.
- **9.17** Calcular slots com 1 query do dia — ✅ **APLICADO + TESTADO (2026-05-14)**. `calculate_slots` em [public_controller.rb#L557-L606](../../app/controllers/public/api/v1/agenda/public_controller.rb#L557-L606) agora faz um único `pluck(:starts_at, :ends_at)` dos eventos com overlap na janela [open_time, close_time] do dia e checa interseção em memória. Antes: ~48 queries EXISTS por dia (1 por slot, grade de 15min). Agora: **1 query por dia**, independente do tamanho do grid. Usa o índice parcial criado em 9.16. **Teste 2026-05-14:** GET `/slots?date=2026-05-15` retornou 21 slots corretamente excluindo os já ocupados (pulou 14:00 onde havia evento prévio); dia vazio (22/05) devolveu lista completa.
- **9.18** Mostrar fuso na UI — ✅ **APLICADO (2026-05-14)**. Texto `"Horários no fuso de Brasília (UTC−3)"` abaixo do header de slots em [app/views/agenda_booking/show.html.erb](../../app/views/agenda_booking/show.html.erb) com estilo discreto `.slots-timezone` em [app/views/layouts/agenda_booking.html.erb](../../app/views/layouts/agenda_booking.html.erb). Evita confusão para pacientes em Manaus/Acre/Fernando de Noronha.
- **9.19** Honeypot field invisível anti-bot — ✅ **APLICADO + TESTADO (2026-05-14)**. Input `#f-website` no form (Step 1) com CSS `.hp-field` off-screen (`position:absolute; left:-10000px`) — não `display:none` porque bots detectam e pulam. `aria-hidden`, `tabindex=-1`, `autocomplete=off`. JS envia o valor como `website` no payload. Backend rejeita silenciosamente se vier preenchido, devolvendo `201` falso para o bot e logando `[AgendaBooking] Honeypot triggered`. Complementa o rate-limit de 9.9 (volume). **Teste:** POST com `website` preenchido → 201 falso, `AgendaEvent.count` inalterado (antes=8321, depois=8321), log presente.

---

## 10. Plano de PRs sugerido

| PR | Itens | Escopo | Risco |
|---|---|---|---|
| **PR-1 — Segurança+integridade cirúrgica** | 9.4, 9.5, 9.6 | público | baixo |
| **PR-2 — Regras revalidadas no book** | 9.1, 9.10 | público | baixo |
| **PR-3 — Race condition** | 9.2 | tabela compartilhada | médio (migration + impacto admin) |
| **PR-4 — Integridade de dados pós-booking** | 9.3 | público | médio (depende de Inbox padrão) |
| **PR-5 — Serviço↔profissional** | 9.7 | estrutural + UI | médio |
| **PR-6 — Hardening do endpoint** | 9.8, 9.9, 9.12, 9.14, 9.19 | público | baixo |
| **PR-7 — Performance + UX** | 9.11, 9.13, 9.15, 9.16, 9.17, 9.18 | público + leitura geral | baixo |

---

## 10.1 Decisões de produto registradas

- **"A clínica define" mostra mais slots que serviços específicos** — comportamento intencional. Quando o paciente não escolhe serviço, `event_duration` cai no `slot_interval_minutes` da agenda (ex: 15min). Quando escolhe um serviço de 60min, slots precisam encaixar uma janela de 60min consecutiva (mais restritivo). Esse cenário pode ocasionalmente fazer o paciente reservar um slot inviável para o serviço que a clínica vai marcar — **aceito como trade-off** em favor de mais flexibilidade. Decisão revisitar quando: (a) clínica reportar conflitos com frequência, ou (b) `agenda_online_config` ganhar um campo `default_appointment_duration_minutes` (proposta C avaliada em 2026-05-15 e descartada).

## 11. Pendências e perguntas em aberto

- [x] ~~Existe `Inbox` padrão por conta para o canal "agenda público"?~~ Resolvido na 9.3 (2026-05-14): usa `@account.inboxes.first` (WhatsApp QR na realidade do Klivy); conta sem inbox: log warn e booking continua.
- [x] ~~Há overlaps históricos em `agenda_events`?~~ Investigado 2026-05-14: **sim, ~5.000 pares**, concentrados em 10 users (user_id=36 com 1.294 pares **`consultation × consultation`**). Indica bug histórico de double-booking (provavelmente import Clinicorp + race conditions pré-9.2). EXCLUDE gist adiado; criar task separada de **qualidade de dados** para categorizar e limpar.
- [ ] **Nova pendência (qualidade de dados):** auditar/limpar os ~5.000 overlaps históricos de `consultation × consultation` em `agenda_events`. Sugestão: extrair CSV por profissional para revisão da clínica → soft-delete dos duplicados confirmados → re-tentar `EXCLUDE USING gist` numa PR futura.
- [ ] **Estender lock 9.2 para `AgendaEventsController` (admin)** — hoje só o fluxo público está protegido contra race. PR pequena.
- [x] **PR-H: Paleta de cores do `STATUS_CONFIGS` realinhada com referência externa** ✅ **APLICADO (2026-05-15)** — antes `confirmed` e `completed` eram ambos verdes, `arrived` era amarelo e `in_progress` era azul, causando ambiguidade visual. Realinhamento:
  - [agenda-constants.js](../../plugins/agenda/frontend/utils/agenda-constants.js):
    - `confirmed` verde → **amarelo** (`#f59e0b`)
    - `arrived` amarelo → **laranja** (`#f97316`)
    - `in_progress` azul → **teal** (`#14b8a6`)
    - `completed` mantém verde escuro (#16a34a)
    - Demais status mantidos
  - [AgendaSummaryBar.vue](../../plugins/agenda/frontend/features/agenda-summary/AgendaSummaryBar.vue) — card "Confirmados" troca cor verde → amber, acompanhando `STATUS_CONFIGS.confirmed`.

- [x] **PR-G: Realinhar labels e cores do `AgendaSummaryBar` com `STATUS_CONFIGS`** ✅ **APLICADO (2026-05-15)** — os 4 primeiros cards do resumo no topo do calendário usavam labels e cores divergentes do sidebar de status, causando confusão (mesmo termo, conceitos diferentes). Mudanças:
  - [AgendaSummaryBar.vue](../../plugins/agenda/frontend/features/agenda-summary/AgendaSummaryBar.vue):
    - Card "Agendados" (que era `cur.total`) → renomeado para **"Total"** — não confunde com o status `scheduled`.
    - Card "Pendentes" (que era `cur.unconfirmed = status='scheduled'`) → renomeado para **"Agendados"** + cor cinza, alinhando com a label e cor de `STATUS_CONFIGS.scheduled` no sidebar.
    - Card "Confirmados" → cor azul mudou para **verde**, alinhando com `STATUS_CONFIGS.confirmed`.
    - Card "Atendidos" → fonte mudou de `cur.attended` (combo `completed+in_progress+arrived`) para `cur.completed` (só `status='completed'`), alinhando com o filtro do sidebar.
  - [agenda-summary.scss](../../plugins/agenda/frontend/features/agenda-summary/agenda-summary.scss) — adicionada classe `.agsum-val--slate` (não existia).

- [x] **PR-F: Distinção visual de eventos cancelados nos cards do calendário** ✅ **APLICADO (2026-05-15)** — eventos com `status='cancelled'` eram renderizados igual aos ativos (mesma cor, mesmo tamanho, sem indicação visual). Após a PR-D criar 320 cancelados, a clínica precisava distinguir visualmente. Mudanças:
  - [AgendaEventCard.vue](../../plugins/agenda/frontend/components/AgendaEventCard.vue) — classe `evt-cancelled` aplicada quando `status === 'cancelled'` (mesmo padrão de `evt-no-show`).
  - [_event-card.scss](../../plugins/agenda/frontend/styles/agenda-events/_event-card.scss) — strikethrough + opacity 0.55, hover restaura opacity 0.85 para leitura. Cor de base preservada (vem do tratamento/categoria).
  - Padrão alinhado com Google Calendar / Outlook.

- [x] **PR-UX-3: ContactInbox manual + PatientAppointment para histórico Clinicorp** ✅ **APLICADO + TESTADO (2026-05-15)**
  - **Reversão parcial PR-3:** `ensure_contact_inbox` removido do booking público em [public_controller.rb](../../app/controllers/public/api/v1/agenda/public_controller.rb). Decisão de produto: criar ContactInbox automaticamente poluía `/conversations` com pacientes que talvez nem tenham WhatsApp no número informado. Fluxo agora: clínica busca o número manualmente em `/contacts` ou via WhatsApp web e inicia a conversa só quando for relevante.
  - **Importer corrigido:** [clinicorp_agenda_importer.rb](../../plugins/migration/app/services/migration/clinicorp_agenda_importer.rb) ganhou `ensure_patient_appointment` + `determine_appointment_type` + `APPT_STATUS_MAP`. Futuras importações Clinicorp já criam PatientAppointment vinculado.
  - **Rake task de backfill:** [lib/tasks/agenda_clinicorp_backfill_appointments.rake](../../lib/tasks/agenda_clinicorp_backfill_appointments.rake) — `agenda_clinicorp:backfill_appointments_preview[<account_id>]` e `:backfill_appointments_apply`. Backfilla ~7.189 PatientAppointments (eventos kept) para a conta 31 com regras:
    - **A2**: primeiro evento cronológico por paciente = `avaliacao`; restante = `retorno`. Ordenação em batch por `starts_at`, então o resultado fica correto mesmo se CSV original não veio cronológico.
    - **B1**: pula soft-deletados (1.098 eventos com `Deleted=X` no Clinicorp). Prontuário do paciente fica enxuto, sem consultas que a própria clínica apagou.
    - **Status map**: scheduled/confirmed/arrived/in_progress → `scheduled`; completed → `done`; no_show → `no_show`; cancelled → `canceled`.
    - **Idempotente** via lookup por `agenda_event_id`.
  - **Resultado em produção (account_id=31):** 7.189 PatientAppointments criados em 1 execução (1.665 `avaliacao` + 5.524 `retorno`). Status: 6.582 `scheduled` + 320 `canceled` + 175 `no_show` + 112 `done`. Pacientes Clinicorp passam a ter histórico de consultas populado no prontuário. Validação: paciente Fernando Pereira da Silva (id=21) agora tem 5 PatientAppointments visíveis na aba "Meus Agendamentos".

- [x] **PR-E: Cancelado no filtro do sidebar + badge de contagem** ✅ **APLICADO + TESTADO (2026-05-15)** — após reconciliação Clinicorp (PR-D) gerou 320 eventos `cancelled` na agenda, mas o filtro lateral em [AgendaSidebar.vue](../../plugins/agenda/frontend/components/AgendaSidebar.vue) não listava esse status (havia sido omitido de `STATUS_OPTIONS` quando não havia cancelados). Mudanças:
  - [agenda-constants.js](../../plugins/agenda/frontend/utils/agenda-constants.js) — adicionado `{ key: 'cancelled', label: 'Cancelado' }` em `STATUS_OPTIONS`.
  - [AgendaSidebar.vue](../../plugins/agenda/frontend/components/AgendaSidebar.vue) — nova prop `statusCounts` + render `SidebarCountBadge` ao lado do label, padrão idêntico ao já existente para `eventTypeCounts`.
  - [AgendaDashboard.vue](../../plugins/agenda/frontend/routes/AgendaDashboard.vue) — computed `statusCounts` (agrupa `agendaEvents` por status, O(n)) + passa como prop.
  - **Decisão de UX (2026-05-15):** badge mostra contagem do **range visível/cache** (não do total da conta) — padrão alinhado com `eventTypeCounts` existente e com comportamento típico de filtros de calendário (Google/Outlook). Total absoluto da conta acessível via relatórios futuros, não via badge do filtro.
- [ ] **UI da 9.7** — seletor de profissionais por serviço em Configurações → Serviços. Backend já suporta (`agenda_service_users`); falta UI para a clínica ativar a restrição.
- [x] **Reconciliação Clinicorp — Canceled/Deleted/STATUS_MAP (PR-D)** ✅ **APLICADO + TESTADO (2026-05-15)** — análise comparativa entre XLSX e banco (conta 31) revelou 4 bugs históricos no `clinicorp_agenda_importer.rb`:
  1. `truthy?` não aceitava `"X"` (notação do XLSX Clinicorp) → 346 com `Canceled=X` e 1.143 com `Deleted=X` foram importados como agendamentos normais.
  2. `Canceled` e `Deleted` tratados como sinônimos (ambos → `status='cancelled'`), perdendo a distinção (Canceled visível no calendário com label vs Deleted some).
  3. `STATUS_MAP` sem CHECKOUT/IN_SESSION/LATE → 118 eventos com status incorreto.
  4. `find_or_create_contact` só buscava por nome → 199+ falhas com `Phone number já está em uso` quando o mesmo paciente aparecia com variações de nome no XLSX (espaço/acento/case).
  - **Parte 1 — Importer corrigido** ([clinicorp_agenda_importer.rb](../../plugins/migration/app/services/migration/clinicorp_agenda_importer.rb)): `truthy?` aceita `"x"`; STATUS_MAP completo; Canceled e Deleted aplicados separados (status=cancelled vs soft-delete); `find_or_create_contact` agora também busca por `phone_number` como fallback.
  - **Parte 2 — Rake task de reconciliação** ([lib/tasks/agenda_clinicorp_reconcile.rake](../../lib/tasks/agenda_clinicorp_reconcile.rake)): `agenda_clinicorp:reconcile_canceled_deleted[<account_id>,<csv_path>,<apply>]` lê o XLSX/CSV, busca AgendaEvents pelo `external_id` e aplica retroativamente: `Canceled=X` → status=cancelled; `Deleted=X` → soft-delete; CHECKOUT/IN_SESSION/LATE → status corrigido. Idempotente via flag `clinicorp_reconciled_at`. Bump `updated_at` (evita ETag stale, lição aprendida da PR-C).
  - **Decisão de produto:** aceitar perda dos 444 eventos que falharam na importação histórica (todos identificados como duplicatas de pacientes existentes). Re-importação seletiva descartada — ROI baixo.
  - **Resultado em produção (account_id=31):** 1.533 eventos reconciliados — 1.098 soft-deletados (Deleted=X), 320 marcados como cancelled (Canceled=X), 115 com status corrigido (112 CHECKOUT→completed, 2 IN_SESSION→in_progress, 1 LATE→arrived). 70 linhas do XLSX não foram encontradas no banco (entre os 444 erros do import original). Kept passou de 8.287 para 7.189. Distribuição final: confirmed 5.444 / scheduled 1.104 / cancelled 320 / no_show 175 / completed 112 / arrived 32 / in_progress 2. Diferença para o outro sistema (7.602): 413 (próximo dos 444+14 perdidos no import original). **Comportamento do calendário batendo com a referência externa.**

- [x] **Limpeza do catálogo de serviços (PR-A + PR-B + PR-C)** ✅ **APLICADO + TESTADO (2026-05-15)** — investigação: dos 2.048 serviços `kept` na conta 31, **apenas 2** tinham vínculo clínico real (`treatment_items > 0`): id=11 "Avaliação" (19 items) e id=13 "Limpeza Profunda" (6 items). Os outros 2.046 eram resíduo da importação Clinicorp, onde cada valor único de `Procedures` virava `AgendaService` por bug em [clinicorp_agenda_importer.rb#L135-L136](../../plugins/migration/app/services/migration/clinicorp_agenda_importer.rb#L135-L136). Solução em 3 etapas:
  - **PR-A** ([lib/tasks/agenda_services_catalog_audit.rake](../../lib/tasks/agenda_services_catalog_audit.rake)) — rake task `agenda_services:catalog_audit[<account_id>]` gera CSV de auditoria (read-only, sem alterar banco). Classificação heurística por `name` + flag de proteção `treatment_items > 0`.
  - **PR-B** ([clinicorp_agenda_importer.rb](../../plugins/migration/app/services/migration/clinicorp_agenda_importer.rb)) — importações **futuras** da Clinicorp: `Procedures` → `description` do evento; `Notes` → custom attribute "Notas (Clinicorp)" (tipo textarea, criado idempotentemente); NÃO cria mais `AgendaService`. Catálogo fica sob controle exclusivo da clínica via UI.
  - **PR-C** ([lib/tasks/agenda_clinicorp_backfill.rake](../../lib/tasks/agenda_clinicorp_backfill.rake)) — rake task `agenda_clinicorp:backfill_preview[<account_id>]` (dry-run) e `:backfill_apply[<account_id>]` (apply). Para AgendaEvents com `custom_attributes["source"]="clinicorp"`: move `description` (Notes antigo) → custom attribute "Notas (Clinicorp)"; copia `agenda_service.name` (Procedures antigo) → `description`; zera `agenda_service_id` (exceto se aponta para service protegido). Soft-delete dos services não-protegidos. Idempotente via flag `clinicorp_backfilled_at` em `custom_attributes`.
  - **Resultado em produção (account_id=31):** 8.287 eventos backfillados, 2.045 services arquivados (`AgendaService.kept` foi de 2.048 → 2), custom attribute "Notas (Clinicorp)" id=15 criado. Validação: AgendaEvent #111 antes tinha `description="SEM CUSTOS - PACIENTE MARIA"` + `service.name="avaliação implante"`; depois tem `description="avaliação implante"` + `attr_15="SEM CUSTOS - PACIENTE MARIA"`. Endpoint público `/services` agora retorna apenas Avaliação + Limpeza Profunda.
- [ ] Definir formato de identificador único de booking (UUID? token assinado?) para retornar ao paciente e suportar cancel/reagendamento (PR-7).
- [ ] LGPD: revisar quais outros campos sensíveis (telefone, email) estão em `description` ou em logs de outros fluxos.

---

## 12. Checklist de progresso

Marcar conforme cada item for aplicado/mergeado.

### P0 — Críticos
- [x] **9.1 — `book` revalida regras (working_window/lunch/holiday/exception/grid)** (aplicado 2026-05-14)
- [x] **9.2 — Race condition em `book`** (aplicado 2026-05-14, advisory lock; EXCLUDE gist adiado por overlaps históricos)
- [x] **9.3 — Booking público cria Patient/ContactInbox/PatientAppointment** (aplicado 2026-05-14)
- [x] **9.4 — Multi-tenant `@user.accounts.first`** (aplicado 2026-05-14, Opção A — estrutural)

### P1 — Altos
- [x] **9.5 — Gate `services` por `enabled`** (aplicado 2026-05-14)
- [x] **9.6 — CPF fora de `description` (LGPD)** (aplicado 2026-05-14)
- [x] **9.7 — Vínculo serviço↔profissional** (backend aplicado 2026-05-14; UI pendente)
- [x] **9.8 — Dedup robusta (transação + retry + índice CPF)** (aplicado 2026-05-14)
- [x] **9.9 — Rate limit em `/book` e `/slots`** (aplicado 2026-05-14)

### P2 — Médios
- [x] **9.10 — Alinhamento ao grid no `book`** (aplicado 2026-05-14, junto com 9.1)
- [x] **9.11 — Cancelar agendamento via link público com token assinado** (aplicado 2026-05-15)
- [x] **9.12 — Validação CPF módulo 11 no backend** (aplicado 2026-05-14)
- [ ] 9.13 — Endpoint batch `/slots?from=…&to=…`
- [x] **9.14 — `rescue StandardError` específico + tracker** (aplicado 2026-05-14)
- [x] **9.15 — Atualizar Contact existente com auditoria** (aplicado 2026-05-14, junto com 9.8)

### P3 — Performance/UX
- [x] **9.16 — Índice parcial em `agenda_events`** (aplicado 2026-05-14)
- [x] **9.17 — Calcular slots com 1 query do dia** (aplicado 2026-05-14)
- [x] **9.18 — Mostrar fuso na UI** (aplicado 2026-05-14)
- [x] **9.19 — Honeypot na ERB** (aplicado 2026-05-14)
