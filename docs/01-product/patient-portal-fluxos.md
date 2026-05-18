# Portal do Paciente — Catálogo de Fluxos e Controles
## Companion ao PRD v1.0

**Documento:** Mapa de fluxos paciente ↔ clínica ↔ portal
**Companion:** `patient-portal-prd.md`
**Data:** 2026-05-17
**Objetivo:** Para CADA interação possível do paciente com a clínica via portal, apresentar:
1. O fluxo passo a passo
2. As **variantes** que a clínica pode escolher
3. Os pontos de **controle da clínica**
4. Os pontos de **controle do paciente**
5. Edge cases
6. Inspiração em concorrentes

---

## Índice

- [0. Princípios de Design](#0-principios)
- [1. Modos de Operação (Presets)](#1-modos)
- [2. Catálogo de Controles da Clínica](#2-controles)
- **A. Acesso e Identidade**
  - [A.1 Convite e primeiro acesso](#a1)
  - [A.2 Login recorrente](#a2)
  - [A.3 Multi-clínica](#a3)
  - [A.4 Suspensão/bloqueio de acesso](#a4)
- **B. Agendamento**
  - [B.1 Modos de agendamento (4 modos)](#b1)
  - [B.2 Primeira consulta vs retorno](#b2)
  - [B.3 Regras por profissional e por serviço](#b3)
  - [B.4 Lista de espera](#b4)
  - [B.5 Pré-requisitos para agendar](#b5)
- **C. Gestão da Consulta**
  - [C.1 Confirmação de presença](#c1)
  - [C.2 Reagendamento](#c2)
  - [C.3 Cancelamento](#c3)
  - [C.4 Política de no-show](#c4)
  - [C.5 Check-in](#c5)
- **D. Financeiro**
  - [D.1 Visualização de pendências](#d1)
  - [D.2 Pagamento de parcela existente](#d2)
  - [D.3 Pré-pagamento de consulta](#d3)
  - [D.4 Cobrança avulsa gerada pela clínica](#d4)
  - [D.5 Pacote/assinatura de tratamento](#d5)
  - [D.6 Reembolso e estorno](#d6)
  - [D.7 Bloqueio por inadimplência](#d7)
  - [D.8 Reembolso de convênio](#d8)
- **E. Documentos**
  - [E.1 Emissão pela clínica](#e1)
  - [E.2 Solicitação pelo paciente](#e2)
  - [E.3 Documentos com validade/expiração](#e3)
  - [E.4 Documentos com assinatura do paciente](#e4)
  - [E.5 Upload pelo paciente](#e5)
- **F. Comunicação**
  - [F.1 Mensagem geral](#f1)
  - [F.2 Mensagem dirigida](#f2)
  - [F.3 Templates rápidos](#f3)
  - [F.4 Auto-resposta e horário comercial](#f4)
  - [F.5 Triagem urgente](#f5)
- **G. Histórico Clínico**
  - [G.1 Níveis de visibilidade](#g1)
  - [G.2 Anamnese pré-consulta](#g2)
  - [G.3 Receitas e prescrições](#g3)
  - [G.4 Plano de tratamento](#g4)
  - [G.5 Exames e laudos](#g5)
- **H. Consentimentos**
  - [H.1 LGPD bloqueante](#h1)
  - [H.2 Por procedimento](#h2)
  - [H.3 Renovação periódica](#h3)
  - [H.4 Revogação](#h4)
  - [H.5 Menor de idade](#h5)
- **I. Perfil e Dados**
  - [I.1 Atualização cadastral](#i1)
  - [I.2 Dependentes](#i2)
  - [I.3 Export LGPD](#i3)
  - [I.4 Solicitação de exclusão](#i4)
- **J. Engajamento**
  - [J.1 Recall automático](#j1)
  - [J.2 NPS pós-consulta](#j2)
  - [J.3 Indicação](#j3)
- **K. Notificações**
  - [K.1 Canais](#k1)
  - [K.2 Preferências do paciente](#k2)
- [3. Matriz de Controle Clínica × Paciente](#3-matriz)
- [4. Inspirações de Concorrentes](#4-concorrentes)
- [5. Decisões em Aberto](#5-decisoes)

---

## 0. Princípios de Design <a id="0-principios"></a>

1. **Default-deny.** Nenhum controle "perigoso" (auto-agendamento, expor evolução, pagar com cartão) vem ligado por padrão. A clínica liga conscientemente.
2. **Configurável por camada.** Conta → Profissional → Serviço → Procedimento. Regra mais específica vence.
3. **Toda ação tem trilha.** Cada interação gera evento em `PatientPortalAccessLog` + `PatientTimelineEvent` quando aplicável.
4. **Paciente nunca surpreende a clínica.** Toda solicitação que altera agenda/financeiro passa pelo painel da clínica como tarefa.
5. **Clínica nunca surpreende o paciente.** Mudanças visíveis (cancelamento, cobrança, novo documento) disparam notificação.
6. **Vias de escape.** Para tudo que é automatizado, existe um botão "Falar com a clínica" — paciente nunca fica preso.
7. **Auto-serviço quando seguro, mediação quando importa.** Pagar uma parcela = seguro. Marcar primeira consulta = importa.

---

## 1. Modos de Operação (Presets) <a id="1-modos"></a>

Quatro presets que a clínica escolhe ao ativar o portal. Cada um é uma combinação de switches dos Controles (seção 2). Tudo pode ser customizado depois.

### 1.1 Modo Recepção Digital (conservador)

> *"O portal é uma janela, não uma porta."*

- Paciente **vê** tudo (agenda, parcelas, documentos), **não muda** quase nada.
- Todo agendamento, reagendamento, cancelamento vira **solicitação** que cai na fila da recepção.
- Pagamento online: opcional, sem efeito automático na agenda.
- Mensagens entram na inbox da clínica como qualquer outro canal.
- **Quem é:** clínicas tradicionais, especialidades sensíveis (psiquiatria, oncologia), consultórios solo.

### 1.2 Modo Autonomia Guiada (híbrido — *recomendado default*)

> *"Tarefas chatas são do paciente. Decisões médicas são da clínica."*

- Confirmar/cancelar consulta dentro de janela: livre.
- Reagendar/agendar primeira consulta: solicitação.
- Retornos: paciente pode agendar livremente em slots liberados pelo profissional.
- Pagar parcela: livre.
- Baixar documentos emitidos: livre.
- Pedir 2ª via, atestado retroativo: solicitação.
- **Quem é:** clínicas médias, multiprofissionais, odonto, fisio.

### 1.3 Modo Self-Service (liberal)

> *"Funciona como o Booking.com."*

- Agendamento direto em slots públicos para retornos e primeiras consultas.
- Reagendar/cancelar com regras de janela e cobrança automática quando aplicável.
- Pré-pagamento obrigatório no momento do booking para certos serviços.
- Paciente vê evolução clínica resumida.
- Anamnese obrigatória antes da consulta.
- **Quem é:** clínicas de estética, exames, telemedicina, cadeias.

### 1.4 Modo Concierge (premium)

> *"Cada paciente tem fluxo desenhado."*

- Tudo configurável por tag/segmento de paciente.
- VIPs têm regras diferentes (sem cobrança de cancelamento, slots premium, contato direto com profissional).
- Inadimplentes têm regras restritas.
- Convênios entram em fluxo separado de pré-autorização.
- **Quem é:** clínicas de alto ticket, medicina preventiva, casas de saúde.

### 1.5 Migração entre modos

A clínica pode trocar de modo a qualquer momento. Mudanças que **restringem** (ex: liberal → conservador) aplicam só a novas interações; agendamentos já feitos pelo paciente continuam válidos.

---

## 2. Catálogo de Controles da Clínica <a id="2-controles"></a>

Cada controle abaixo é um campo em `PatientPortalSetting` (por account) ou em um setting mais granular (`AgendaServiceSetting`, `ProfessionalPortalSetting`).

### 2.1 Agendamento

| Controle | Valores | Default | Onde aplica |
|---|---|---|---|
| `scheduling_mode` | `disabled` / `request_only` / `slot_picker` / `direct_booking` | `request_only` | Account; override por profissional/serviço |
| `first_visit_mode` | `request_only` / `direct_booking` | `request_only` | Account |
| `min_lead_time_hours` | número | 24 | Account/serviço |
| `max_future_days` | número | 60 | Account/serviço |
| `allow_same_day` | bool | false | Account/serviço |
| `slot_release_strategy` | `automatic` / `manual_windows` / `professional_opt_in` | `professional_opt_in` | Profissional |
| `block_if_overdue` | bool | true | Account |
| `block_if_pending_consent` | bool | true | Account |
| `require_anamnesis_before` | bool | false | Serviço |
| `require_prepayment` | bool / parcial | false | Serviço |
| `prepayment_percent` | 0–100 | 0 | Serviço |
| `max_active_appointments` | número | unlimited | Account |

### 2.2 Reagendamento e Cancelamento

| Controle | Valores | Default |
|---|---|---|
| `reschedule_mode` | `request_only` / `self_within_window` / `unlimited` | `self_within_window` |
| `reschedule_window_hours` | número | 24 |
| `max_reschedules_per_event` | número | 2 |
| `cancel_mode` | `request_only` / `self_within_window` / `self_unlimited` | `self_within_window` |
| `cancel_window_hours` | número | 24 |
| `late_cancel_fee` | valor / percent | 0 |
| `no_show_fee` | valor / percent | 0 |
| `no_show_auto_invoice` | bool | false |

### 2.3 Financeiro

| Controle | Valores | Default |
|---|---|---|
| `payment_methods` | array (pix/boleto/credit/debit) | [pix, boleto] |
| `installment_max` | 1–12 | 1 |
| `passes_fee_to_patient` | bool | false |
| `partial_payment_allowed` | bool | false |
| `early_payment_discount_percent` | 0–100 | 0 |
| `show_paid_history` | bool | true |
| `allow_self_refund_request` | bool | true |
| `block_portal_if_overdue_days` | número (0 = nunca) | 0 |
| `auto_charge_no_show` | bool | false |

### 2.4 Documentos

| Controle | Valores | Default |
|---|---|---|
| `document_types_exposed` | array | [atestado, encaminhamento, receita, recibo, plano_tratamento] |
| `allow_document_request` | bool | true |
| `requestable_document_types` | array | [atestado_2via, recibo_2via] |
| `allow_self_upload` | bool | false |
| `upload_categories` | array | [exame_externo, receita_externa] |
| `document_link_ttl_minutes` | número | 15 |
| `share_via_external_link` | bool | true |

### 2.5 Histórico Clínico

| Controle | Valores | Default |
|---|---|---|
| `clinical_visibility` | `none` / `summary` / `selected_fields` / `full` | `none` |
| `expose_clinical_note_fields` | array | [] |
| `expose_treatment_plan` | bool | false |
| `expose_session_logs` | bool | false |
| `expose_anamnesis_to_patient` | bool | false |
| `prescription_visibility` | `none` / `active_only` / `all` | `active_only` |

### 2.6 Comunicação

| Controle | Valores | Default |
|---|---|---|
| `messaging_enabled` | bool | true |
| `allow_direct_professional` | bool | false |
| `business_hours` | json | seg-sex 8-18 |
| `out_of_hours_template` | texto | "Recebemos sua mensagem, retornaremos no próximo dia útil." |
| `topic_routing` | json (tópico → fila) | financeiro→financeiro, etc |
| `urgent_keyword_alert` | array | [dor forte, urgência, sangue, ...] |
| `urgent_redirect_action` | `force_phone` / `dedicated_inbox` / `escalate` | `force_phone` |

### 2.7 Engajamento

| Controle | Valores | Default |
|---|---|---|
| `recall_enabled` | bool | true |
| `recall_after_months` | número | 6 |
| `nps_after_appointment` | bool | true |
| `nps_delay_hours` | número | 24 |
| `referral_program_enabled` | bool | false |
| `referral_reward_type` | desconto/dinheiro/sessão | desconto |

---

## A. Acesso e Identidade

### A.1 Convite e primeiro acesso <a id="a1"></a>

**Cenário:** Maria foi atendida pela primeira vez na Clínica X. A recepcionista quer dar acesso ao portal.

```
[Recepção cria Patient]
        │
        ▼
[Sistema verifica: phone/email ok?] ──── não ──► bloqueia "Preencha contato"
        │ sim
        ▼
[Recepção clica "Convidar para o portal"]
        │
        ▼
[Job envia mensagem via WhatsApp inbox da clínica:
 "Maria, a Clínica X criou seu acesso. Entre em pacientes.klivy.app"]
        │
        ▼
[Maria entra, faz login OTP, vê termo LGPD + termo Klivy]
        │
        ▼
[Aceita] ──► [Acesso liberado, primeira home carrega]
```

**Variantes:**
- **A.1.a Auto-convite:** ao criar `Patient`, dispara convite automaticamente (toggle `auto_invite_patient`).
- **A.1.b Convite explícito:** recepção dispara manualmente quando quiser.
- **A.1.c Booking público gera convite:** paciente que se agendou via link público recebe convite junto com a confirmação.
- **A.1.d Sem convite:** portal só funciona se a clínica habilitar paciente a paciente.

**Controles da clínica:**
- `auto_invite_on_create` (bool)
- `invite_message_template` (texto, com variáveis)
- `welcome_message_post_first_login` (texto)

**Controles do paciente:**
- Recusar termo → conta não é criada
- Pedir para não ser convidado de novo

**Edge cases:**
- Paciente sem telefone nem email: convite impossível, recepção precisa cadastrar primeiro.
- Paciente que apaga conta e volta: ao tentar logar, sistema reconhece e oferece reativar.

---

### A.2 Login recorrente <a id="a2"></a>

Já documentado no PRD §5.2. Resumo: OTP via WhatsApp ou email, JWT 7 dias com refresh silencioso.

**Variante notável:** "Lembrar este dispositivo" estende JWT para 30 dias com fingerprint do device. Toggle por clínica.

---

### A.3 Multi-clínica <a id="a3"></a>

**Cenário:** Carlos é atendido em duas clínicas Klivy (clínico geral e dermatologista). Mesmo telefone.

```
[Carlos digita telefone]
        │
        ▼
[Backend acha 2 Contacts em accounts diferentes]
        │
        ▼
[Envia OTP único]
        │
        ▼
[Carlos digita OTP]
        │
        ▼
[Portal mostra: "Em qual clínica você quer entrar?"]
   │                                                 │
   ▼                                                 ▼
[Clínica A — logo + nome]                  [Clínica B — logo + nome]
        │
        ▼
[JWT emitido com account_id da escolhida]
```

**Variantes:**
- **A.3.a Listagem simples:** mostra ambas, paciente escolhe.
- **A.3.b Última usada primeiro:** lembra a última e sugere.
- **A.3.c Switcher inline:** header sempre mostra clínica atual com dropdown para trocar (Fase 2).

**Edge cases:**
- 10+ clínicas (improvável mas possível): paginar a lista.
- Paciente sem nome em uma clínica (registro mal feito): exibir "Clínica X — paciente sem nome cadastrado".
- Clínica desativada no Klivy: oculta da lista.

---

### A.4 Suspensão/bloqueio de acesso <a id="a4"></a>

**Cenário:** Paciente assediou recepção, ou inadimplente crônico. Clínica quer bloquear acesso ao portal sem apagar dados.

```
[Recepção/admin abre o Patient]
        │
        ▼
[Aba "Portal" → "Suspender acesso"]
        │
        ▼
[Modal: motivo (obrigatório), data fim (opcional)]
        │
        ▼
[Patient.portal_status = suspended até X]
        │
        ▼
[Paciente tenta logar]
        │
        ▼
[Portal exibe: "Acesso temporariamente indisponível. Procure a recepção."]
```

**Variantes:**
- **A.4.a Suspensão temporária** (até data X).
- **A.4.b Suspensão permanente** (até reativação manual).
- **A.4.c Restrição parcial** (só visualização, sem mensagens nem agendamento).

**Controles da clínica:**
- Listar/auditar suspensões
- Razão obrigatória
- Notificar paciente do motivo (opcional)

**Controles do paciente:**
- Nenhum — bloqueio é unilateral da clínica.

---

## B. Agendamento

### B.1 Modos de agendamento <a id="b1"></a>

**Quatro modos**, escolhidos por account/profissional/serviço. Regra mais específica vence.

#### B.1.1 Modo `disabled`
Paciente não vê calendário. Botão "Agendar" leva direto pra mensagem na conversa.

#### B.1.2 Modo `request_only`
Paciente preenche formulário (serviço, profissional, 3 preferências de data/horário, observação). Cai numa fila de "Solicitações de agendamento" no painel da clínica. Recepção confirma ou propõe alternativa.

```
[Paciente preenche solicitação]
        │
        ▼
[AppointmentRequest criado, status=pending]
        │
        ▼
[Notificação para inbox "Recepção"]
        │
        ▼
[Recepção abre, clica "Confirmar com slot X"] ──► [AgendaEvent criado, paciente notificado]
                          │
                          └► [Clica "Propor outro horário"] ──► [Paciente recebe sugestão, aceita/recusa]
```

#### B.1.3 Modo `slot_picker` (recomendado — inspirado MyChart)
Profissional/recepção libera **janelas explícitas** no portal (ex: "tenho retornos disponíveis quartas 14h-18h"). Paciente vê só essas janelas e escolhe. Agendamento é direto (status `confirmed`), sem aprovação manual.

```
[Profissional configura "Janelas do portal"]
   - Dia da semana, horário, serviço permitido, máximo de agendamentos
        │
        ▼
[Paciente abre "Agendar"]
        │
        ▼
[Vê só os slots dessas janelas, dos próximos 60 dias]
        │
        ▼
[Escolhe, confirma] ──► [AgendaEvent direto status=confirmed]
        │
        ▼
[Janela tem slot a menos, próximo paciente vê só o que sobrou]
```

#### B.1.4 Modo `direct_booking`
Paciente vê **toda a agenda real** do profissional e escolhe qualquer slot vazio respeitando `AgendaSetting` (lead time, future limit). Risco maior, controle menor — usado em clínicas liberais.

**Quadro comparativo:**

| Modo | Esforço da clínica | Autonomia do paciente | Risco de erro |
|---|---|---|---|
| `disabled` | 0 (tudo manual) | Mínima | Mínimo |
| `request_only` | Alto (triagem) | Baixa | Mínimo |
| `slot_picker` | Médio (configurar janelas) | Média-alta | Baixo |
| `direct_booking` | Mínimo (uma vez) | Alta | Médio |

---

### B.2 Primeira consulta vs retorno <a id="b2"></a>

> **Insight de concorrentes:** Praticamente todos os portais distinguem isso. MyChart e Doctoralia tratam primeira consulta como request, retorno como direct.

**Lógica de detecção:** Paciente é "primeira consulta" para um profissional X se nunca teve `AgendaEvent.completed` com `user_id = X`.

**Controles da clínica:**

| Setting | Significado |
|---|---|
| `first_visit_mode = request_only` | Primeira sempre cai em fila |
| `first_visit_mode = slot_picker` | Permite, mas só em slots especiais |
| `first_visit_questionnaire` | Formulário extra obrigatório antes do request |
| `first_visit_requires_referral` | Exige número de encaminhamento |
| `first_visit_intake_form_id` | Vincula anamnese pré-consulta |

**Cenário:** Joana nunca foi atendida. Tenta marcar.

```
[Joana clica "Agendar"]
        │
        ▼
[Portal detecta: primeira consulta]
        │
        ▼
[Portal aplica first_visit_mode = request_only]
        │
        ▼
[Mostra formulário extra: motivo, encaminhamento, convênio, foto do documento]
        │
        ▼
[Cria AppointmentRequest com tag "primeira_consulta"]
        │
        ▼
[Cai na fila de triagem — clínica pode atribuir profissional adequado]
```

---

### B.3 Regras por profissional e por serviço <a id="b3"></a>

**Cenário:** Dr. Silva (psiquiatra) nunca aceita agendamento direto. Dra. Lima (clínico geral) aceita slot picker. Procedimento "botox" sempre pede pré-pagamento.

**Hierarquia de regras (mais específica vence):**

```
Account default
    │
    ▼
Profissional override
    │
    ▼
Serviço override
    │
    ▼
Procedimento override
    │
    ▼
Tag do paciente override (Concierge)
```

**Controles da clínica:**
- UI em "Configurações > Portal > Regras de agendamento"
- Tabela editável com colunas: escopo, modo, lead time, pré-pagamento, anamnese obrigatória
- Botão "Simular" para testar como o paciente verá

**Edge cases:**
- Conflito de regras: regra mais específica vence sem aviso.
- Profissional novo sem regras: herda da account.
- Serviço sem profissional: bloqueia agendamento.

---

### B.4 Lista de espera <a id="b4"></a>

`WaitingListEntry` já existe no Klivy. O portal expõe.

**Cenário:** Não há slot disponível em 60 dias. Pedro entra na lista.

```
[Pedro tenta agendar]
        │
        ▼
[Sem slot disponível]
        │
        ▼
[Portal: "Sem horários — quer entrar na lista de espera?"]
        │
        ▼
[Pedro escolhe período preferido (manhã/tarde/noite, dias)]
        │
        ▼
[WaitingListEntry criada]
        │
        ▼
[Clínica abre novo slot — Job notifica top da fila]
        │
        ▼
[Pedro recebe WhatsApp: "Vaga aberta DD/MM 14h. Aceita?"]
        │
        ▼
[Aceita em 30 min] ──► [Slot reservado pra ele] ──► [AgendaEvent criado]
[Não responde] ────► [Próximo da fila]
```

**Controles da clínica:**
- `waiting_list_enabled` (bool)
- `waiting_list_response_timeout_minutes` (default 30)
- `waiting_list_max_position_visible` (paciente vê "você é o 3º"? default sim)
- Ordem: FIFO, prioridade manual, ou tag (VIP primeiro)

**Controles do paciente:**
- Sair da lista
- Trocar preferência de período
- Ver posição

---

### B.5 Pré-requisitos para agendar <a id="b5"></a>

**Cenário:** A clínica exige (a) anamnese preenchida, (b) consentimento LGPD assinado, (c) sem parcela vencida. Senão, bloqueia o botão de agendar.

```
[Paciente clica "Agendar"]
        │
        ▼
[Pre-flight check]
   ├── consent ok? ─── não ──► "Antes, assine o termo de privacidade"
   ├── overdue? ────── sim ──► "Resolva parcelas vencidas. [Pagar agora]"
   ├── anamnesis ok? ── não ──► "Preencha sua anamnese para continuar"
   └── all ok ────────────────► Mostra calendário/formulário
```

**Controles da clínica:**

| Check | Setting |
|---|---|
| Consentimento LGPD | `block_if_pending_consent` |
| Parcela vencida | `block_if_overdue` + `block_overdue_days` |
| Anamnese | `require_anamnesis_before_scheduling` |
| Documentos pessoais | `require_id_upload_first_visit` |
| Convênio válido | `require_insurance_verification` (Fase 3) |
| Máximo de consultas abertas | `max_active_appointments` |

**Por que isso importa:** sem pre-flight, paciente agenda → no dia descobre que tá bloqueado → cancela na hora → no-show. Pre-flight previne.

---

## C. Gestão da Consulta

### C.1 Confirmação de presença <a id="c1"></a>

**Cenário:** Ana tem consulta amanhã 14h. Recebe lembrete pedindo confirmação.

```
[T-24h] [SendNotificationJob dispara via inbox WhatsApp da clínica]
        │
        ▼
[Mensagem: "Confirma sua consulta? [Sim] [Reagendar] [Cancelar]"]
        │
        ▼
[Ana clica "Sim" → abre portal autenticado por deep link]
        │
        ▼
[AgendaEvent.status: scheduled → confirmed]
        │
        ▼
[Timeline registra; clínica vê badge "Confirmado" na agenda]
```

**Variantes:**
- **C.1.a Confirmação implícita via mensagem:** paciente responde "sim" no WhatsApp; Bea ou regra atualiza status.
- **C.1.b Confirmação no portal:** card na home com botão.
- **C.1.c Auto-cancel se não confirmar:** clínica liga `auto_cancel_if_not_confirmed_hours_before = 6` → não confirmou em T-6h, vira `cancelled` automaticamente.
- **C.1.d Confirmação multi-step:** "Confirma?" → "Tem sintomas de gripe?" → confirmação só se passar.

**Controles da clínica:**
- `confirmation_required` (bool)
- `confirmation_window_hours_before` (default 24)
- `auto_cancel_if_not_confirmed_hours_before` (0 = nunca)
- `confirmation_questionnaire_id` (opcional)

---

### C.2 Reagendamento <a id="c2"></a>

```
[Paciente abre consulta] ──► [Botão "Reagendar"]
        │
        ▼
[Sistema checa reschedule_mode]
   │
   ├── request_only ──► [Abre conversa pré-preenchida]
   │
   ├── self_within_window:
   │     ├── dentro de window_hours? sim ──► [Mostra calendário/janelas]
   │     │                                            │
   │     │                                            ▼
   │     │                                   [Paciente escolhe novo slot]
   │     │                                            │
   │     │                                            ▼
   │     │                                   [AgendaEvent atualizado]
   │     └── fora? ──► [Mensagem "Reagendamento online indisponível, fale com a clínica"]
   │
   └── unlimited ──► [Calendário sempre liberado]
```

**Controles da clínica:**
- `reschedule_mode`
- `reschedule_window_hours`
- `max_reschedules_per_event` (após N, vira request_only)
- `reschedule_charge_outside_window` (cobrança automática)
- `reschedule_blocked_if_overdue`

**Cenário sensível:** paciente reagendou 3 vezes a mesma consulta. No 4º clique, sistema obriga request_only. Recepção decide.

**Edge cases:**
- Reagendamento para um slot que requer outro tipo de pré-pagamento → fluxo bifurca para cobrança.
- Reagendamento entre profissionais diferentes (caso o original não está disponível) → tratar como novo agendamento com transfer do histórico.

---

### C.3 Cancelamento <a id="c3"></a>

```
[Paciente clica "Cancelar consulta"]
        │
        ▼
[Modal: "Tem certeza? Motivo (opcional)"]
        │
        ▼
[Sistema checa cancel_mode + window]
   │
   ├── Dentro da window OU mode=self_unlimited:
   │     [AgendaEvent.status = cancelled, motivo registrado]
   │     [Slot volta para disponível]
   │     [Notifica clínica]
   │     [Se waiting list: oferece para o top]
   │
   ├── Fora da window E late_cancel_fee > 0:
   │     [Modal: "Cancelamento fora do prazo gera taxa de R$ X. Confirmar?"]
   │     [Confirma] ──► [Cria Transaction tipo "cancellation_fee", abre cobrança]
   │     [Recusa] ──► [Abre conversa com clínica]
   │
   └── cancel_mode=request_only:
         [Abre conversa pré-preenchida]
```

**Controles da clínica:**
- `cancel_mode`, `cancel_window_hours`
- `late_cancel_fee` (R$ ou %)
- `late_cancel_auto_invoice` (gera cobrança automática vs gera tarefa)
- `cancel_require_reason` (bool)
- `cancel_blocks_future_for_days` (após cancelar, bloqueia novo agendamento por N dias — coibir abusivos)

---

### C.4 Política de no-show <a id="c4"></a>

**Cenário:** Paciente não compareceu, sem aviso. Recepção marca `AgendaEvent.status = no_show`.

```
[Recepção marca no_show]
        │
        ▼
[Sistema aplica política]
   ├── no_show_auto_invoice = true:
   │     [Cria Transaction "no_show_fee", abre cobrança]
   │     [Notifica paciente]
   │
   ├── no_show_count >= threshold:
   │     [Patient.flag = chronic_no_show]
   │     [Agendamentos futuros viram request_only automaticamente]
   │
   └── always: timeline + audit log
```

**Controles da clínica:**
- `no_show_fee` (R$ ou % do serviço)
- `no_show_auto_invoice`
- `no_show_threshold_for_restriction` (ex: 3 no-shows em 90 dias)
- `no_show_restriction_action`: `request_only` / `block_portal` / `require_prepayment_next`
- `no_show_lift_after_days` (ex: 90 dias sem no-show, libera de novo)

**Controles do paciente:**
- Justificar no-show via conversa (clínica pode "perdoar" e reverter)

---

### C.5 Check-in <a id="c5"></a>

**Cenário:** Paciente chega à clínica. Recepção marca como `arrived`. Variante: paciente faz check-in pelo próprio celular.

```
[Paciente entra na clínica]
        │
        ├── Recepção marca "Chegou" no painel da agenda ──► AgendaEvent.status = arrived
        │
        └── [Variante portal] Paciente abre portal, vê "Sua consulta começa em 15 min — fazer check-in?"
                  │
                  ▼
              [Botão "Cheguei" — só aparece dentro de raio geográfico (opt-in) ou faixa de horário]
                  │
                  ▼
              [Status = arrived; recepção vê alerta]
```

**Controles da clínica:**
- `self_checkin_enabled` (bool)
- `self_checkin_geofence_meters` (0 = sem geofence)
- `self_checkin_time_window_minutes_before` (default 15)
- `self_checkin_qrcode_at_reception` (usa QR fixo na recepção em vez de geofence)

**Por que oferecer:** clínicas com muitos pacientes/dia (estética, exames) ganham operacionalmente. Clínicas pequenas, irrelevante.

---

## D. Financeiro

### D.1 Visualização de pendências <a id="d1"></a>

Cobertura básica detalhada no PRD §9. Pontos de controle:

**Controles da clínica:**
- `show_paid_history` (bool, default true)
- `show_treatment_estimates_with_open_balance` (bool — paciente vê o que ainda vai pagar do plano de tratamento?)
- `mask_amounts_for_minors` (bool — dependentes menores não veem valores)
- `consolidated_view_across_clinics` (default false — segurança: cada clínica é silo)

---

### D.2 Pagamento de parcela existente <a id="d2"></a>

```
[Maria abre "Financeiro" → vê 3 parcelas em aberto]
        │
        ▼
[Clica em uma → tela de detalhe + botão "Pagar agora"]
        │
        ▼
[Sistema oferece métodos habilitados: PIX, Boleto, Cartão]
        │
        ├── PIX:
        │   [Gateway gera cobrança] → [Portal exibe QR + copia/cola] → [Webhook confirma] → [Installment.status = paid]
        │
        ├── Boleto:
        │   [Gateway gera boleto] → [PDF + linha digitável] → [Webhook confirma quando pago]
        │
        └── Cartão:
            [Checkout transparente] → [Tokeniza, captura] → [Webhook] → [paid]
```

**Variantes:**
- **D.2.a Pagamento parcial** (se `partial_payment_allowed`): paciente escolhe quanto pagar; resto continua em aberto.
- **D.2.b Antecipar várias parcelas** com desconto: paciente seleciona, sistema aplica `early_payment_discount_percent`.
- **D.2.c Renegociar:** abre conversa com clínica.

**Controles da clínica:**
- Métodos habilitados
- `installment_max_for_self_payment` (paciente pode parcelar nova cobrança? max N x)
- `passes_fee_to_patient` (taxa de cartão repassa)
- Webhook handling robusto (idempotência)

---

### D.3 Pré-pagamento de consulta <a id="d3"></a>

**Cenário:** Serviço "botox" exige 50% pago para confirmar o agendamento.

```
[Paciente escolhe slot]
        │
        ▼
[Sistema detecta require_prepayment = true, prepayment_percent = 50]
        │
        ▼
[Antes de confirmar, abre tela de pagamento de R$ X]
        │
        ▼
[Webhook confirma] ──► [AgendaEvent confirmado]
                  └──► [Não confirmou em 15 min: slot liberado, agendamento descartado]
```

**Edge case crítico:** paciente paga mas webhook atrasa. Lógica: criar slot "soft-hold" por 15 min; ao confirmar webhook, vira `confirmed`; se expirar, libera slot mas Transaction fica criada pra estorno.

**Controles da clínica:**
- `require_prepayment` por serviço
- `prepayment_percent`
- `prepayment_timeout_minutes`
- `prepayment_refund_on_clinic_cancel` (clínica cancela, devolve automático)

---

### D.4 Cobrança avulsa gerada pela clínica <a id="d4"></a>

**Cenário:** Clínica termina consulta, faz orçamento de procedimento extra. Quer cobrar agora.

```
[Profissional gera FinancialEstimate na consulta]
        │
        ▼
[Marca "Enviar cobrança ao portal do paciente"]
        │
        ▼
[Job notifica: WhatsApp + push portal]
        │
        ▼
[Paciente abre, vê detalhamento + opções de pagamento]
        │
        ▼
[Paga ou recusa]
```

**Controles da clínica:**
- Template de mensagem de cobrança
- Prazo para pagamento (após X dias, marca como inadimplente)
- Aceitar contraproposta? (`allow_counter_offer` — paciente sugere valor/parcelamento)

---

### D.5 Pacote/assinatura de tratamento <a id="d5"></a>

**Cenário:** Tratamento de fisio 10 sessões. Paciente paga em 10x. Sistema controla saldo de sessões.

```
[Plano criado: 10 sessões a R$ 100, parceladas em 10x]
        │
        ▼
[Paciente vê no portal: "Plano de Fisioterapia — 0/10 sessões"]
        │
        ▼
[A cada sessão realizada (SessionLog): contador atualiza]
        │
        ▼
[Mensalmente: parcela vence; portal mostra status]
```

**Controles da clínica:**
- Auto-débito recorrente vs parcela manual
- O que acontece se paciente cancela antes de terminar — política de rescisão
- Pausa do plano (suspender débitos)

**Controles do paciente:**
- Solicitar pausa
- Solicitar cancelamento (gera tarefa para clínica processar)
- Ver saldo de sessões

---

### D.6 Reembolso e estorno <a id="d6"></a>

**Cenário:** Paciente pagou consulta antecipada, clínica cancelou.

```
[Clínica cancela] ──► [Sistema detecta pagamento associado] ──► [Aciona estorno automático ou tarefa manual]
        │
        ▼
[Estorno via gateway] ──► [Notifica paciente, atualiza Installment.status = refunded]
```

**Controles da clínica:**
- `auto_refund_on_clinic_cancel` (bool)
- `manual_review_threshold` (estornos acima de R$ X exigem aprovação)
- Política de reembolso por motivo: clínica cancelou (100%), paciente cancelou no prazo (100%), fora do prazo (parcial), no-show (0%)

**Controles do paciente:**
- Solicitar reembolso via conversa
- Acompanhar status do estorno

---

### D.7 Bloqueio por inadimplência <a id="d7"></a>

**Cenário:** Paciente tem 2 parcelas vencidas há 30+ dias.

```
[Job diário: scan_overdue_patients]
        │
        ▼
[Para cada Patient com overdue_count > threshold:]
   ├── Notifica paciente: "Você tem R$ X em atraso, regularize para continuar"
   ├── Bloqueia agendamento (se block_if_overdue = true)
   ├── Limita mensagens (só pode falar com financeiro)
   └── Após N dias adicionais: suspende portal completamente
```

**Controles da clínica:**
- `block_portal_if_overdue_days` (0 = nunca, 7/15/30/60)
- `overdue_restriction_level`: warn / limit_scheduling / limit_messaging_to_financial / full_block
- Auto-restaura após pagamento

---

### D.8 Reembolso de convênio <a id="d8"></a>

**Cenário (Fase 3):** Paciente pagou particular, vai pedir reembolso ao convênio. Precisa de nota fiscal + relatório.

```
[Paciente clica "Solicitar documentos para convênio" na parcela]
        │
        ▼
[Portal gera pacote: recibo + relatório médico + código TUSS + CID]
        │
        ▼
[Disponível para download]
```

**Controles da clínica:**
- `insurance_reimbursement_package_enabled`
- Templates por convênio
- Quem da clínica pode aprovar a inclusão de código CID em relatório

---

## E. Documentos

### E.1 Emissão pela clínica <a id="e1"></a>

```
[Profissional na consulta gera atestado (via módulo Pacientes)]
        │
        ▼
[Document criado com is_generated=true]
        │
        ▼
[Toggle "Disponibilizar no portal" — default conforme document_types_exposed]
        │
        ▼
[Job notifica paciente: "Novo documento disponível"]
        │
        ▼
[Paciente abre portal, baixa]
```

**Controles da clínica:**
- `document_types_exposed` — array de tipos liberados por default
- Por documento individual: switch "visível ao paciente" (override do default)
- `auto_send_via_whatsapp` (alternativo ao portal)

---

### E.2 Solicitação pelo paciente <a id="e2"></a>

**Cenário:** Paciente quer 2ª via de atestado de uma consulta passada.

```
[Paciente abre "Documentos" → "Solicitar documento"]
        │
        ▼
[Form: tipo, consulta de referência, justificativa]
        │
        ▼
[DocumentRequest criado, status=pending]
        │
        ▼
[Tarefa para fila "Documentos" da clínica]
        │
        ▼
[Profissional ou recepção gera e libera ou recusa]
        │
        ▼
[Paciente notificado do desfecho]
```

**Controles da clínica:**
- `requestable_document_types` (lista de tipos que aceitam request)
- `auto_approve_simple_requests` (ex: 2ª via de recibo automática)
- Quem da equipe pode aprovar: por profissional ou centralizado
- Prazo SLA (notifica clínica se ficou X dias sem resposta)

**Edge cases:**
- Pedido de atestado retroativo: clínica deve revisar com atenção (risco legal).
- Pedido de receita de medicamento controlado: bloqueado (precisa nova consulta).

---

### E.3 Documentos com validade/expiração <a id="e3"></a>

**Cenário:** Atestado válido por 30 dias. Após expirar, deixa de ter valor legal.

```
[Document criado com expires_at = +30 dias]
        │
        ▼
[Após expires_at: badge "Expirado", download bloqueado para fins legais]
        │
        ▼
[Paciente pode ver histórico mas não baixar mais]
```

**Controles da clínica:**
- Validade default por tipo de documento
- Override individual
- Pacientes podem pedir reemissão? `allow_reissue_expired_documents`

---

### E.4 Documentos com assinatura do paciente <a id="e4"></a>

**Cenário:** Termo de procedimento que paciente precisa assinar antes da consulta.

```
[Clínica anexa termo ao AgendaEvent]
        │
        ▼
[Notificação: "Assine antes da consulta"]
        │
        ▼
[Portal: modal com texto + assinatura digital touch]
        │
        ▼
[Assinou] ──► [ConsentRecord criado, hash, IP, UA]
                       │
                       ▼
            [Anexa ao prontuário]
```

**Controles da clínica:**
- Bloquear check-in/consulta se não assinado (`require_signed_consent_before_arrived`)
- Permitir assinatura no balcão como fallback

---

### E.5 Upload pelo paciente <a id="e5"></a>

**Cenário:** Paciente foi a outra clínica fazer exame de sangue. Quer subir o resultado.

```
[Paciente abre "Meus exames externos" → "Adicionar"]
        │
        ▼
[Upload PDF/imagem com categoria]
        │
        ▼
[ExamMedia criado com uploaded_by_patient=true, status=pending_review]
        │
        ▼
[Notifica profissional vinculado]
        │
        ▼
[Profissional valida, anexa ao prontuário ou rejeita]
```

**Controles da clínica:**
- `allow_self_upload` (default false)
- Categorias permitidas
- Tamanho máximo, formatos
- Quem revisa
- Auto-OCR para extração de dados (Fase 3)

---

## F. Comunicação

### F.1 Mensagem geral <a id="f1"></a>

Já documentado no PRD §12. Reuso de `Conversation` do Chatwoot, inbox dedicado por account.

---

### F.2 Mensagem dirigida <a id="f2"></a>

**Cenário:** Paciente quer falar diretamente com Dr. Silva (não com a recepção).

```
[Paciente: "Nova mensagem" → "Para quem?"]
        │
        ▼
[Lista: Recepção, Financeiro, Dr. Silva, Dra. Lima]
        │
        ▼
[Escolhe Dr. Silva]
        │
        ▼
[Conversation criada com assignee = Dr. Silva user_id]
```

**Controles da clínica:**
- `allow_direct_professional` (bool)
- Por profissional individual: opt-in (alguns aceitam, outros não)
- Limite de mensagens por paciente por dia
- Filtro de palavras-chave urgentes (escalação)
- Auto-resposta do profissional fora do horário

**Controles do paciente:**
- Escolher destinatário (limitado ao que clínica permite)
- Marcar como urgente (com confirmação "isto vai escalar a equipe — é mesmo urgente?")

---

### F.3 Templates rápidos <a id="f3"></a>

**Cenário:** Paciente quer pedir reagendamento, dúvida sobre exame, 2ª via de recibo. Em vez de digitar, escolhe template.

```
[Tela "Nova mensagem" → barra de quick actions]
   [Pedir reagendamento] [Dúvida financeira] [Pedir documento] [Outro]
        │
        ▼
[Escolhe, formulário pré-estruturado abre]
        │
        ▼
[Cria conversa já roteada para fila correta]
```

**Controles da clínica:**
- Templates ativos
- Roteamento por template → fila/inbox
- Variáveis suportadas (qual consulta, qual documento)

**Por que isso é bom para a clínica:** triagem automática reduz trabalho da recepção em 60-80% segundo o que vi em iClinic/Healthie.

---

### F.4 Auto-resposta e horário comercial <a id="f4"></a>

**Cenário:** Paciente manda mensagem 22h domingo.

```
[Mensagem recebida fora do business_hours]
        │
        ▼
[Sistema responde imediatamente: "Recebemos! Atendimento seg-sex 8h-18h. Retornaremos amanhã."]
        │
        ▼
[Se contém keyword urgente (dor, sangue, etc): adiciona "Em emergência, ligue 192"]
        │
        ▼
[Conversa fica marcada para topo da fila na próxima abertura]
```

**Controles da clínica:**
- `business_hours` (json por dia da semana)
- `out_of_hours_template`
- `holidays` (lista de feriados)
- `keyword_urgent_list`
- `urgent_action`: extra mensagem / sair / abrir conversa especial / acionar plantão

---

### F.5 Triagem urgente <a id="f5"></a>

**Cenário:** Paciente escreve "estou com dor forte no peito".

```
[Detector roda em onMessage]
        │
        ▼
[Match em keyword_urgent_list]
        │
        ▼
[Aplica urgent_action]
   ├── force_phone: "Por favor, ligue agora para (11) X. Em emergência, 192."
   ├── dedicated_inbox: roteia para inbox "Urgências"
   ├── escalate: cria conversa + notificação push para profissional/gestor de plantão
   └── always: marca conversa com SLA reduzido + flag visual
```

**Controles da clínica:**
- Lista de palavras-chave (editável)
- Múltiplos níveis (atenção, urgência, emergência)
- Por especialidade (lista diferente em psiquiatria, cardio, etc)

**Por que importa:** sem isso, um caso real de emergência pode ficar parado na fila como mensagem normal — risco médico e legal.

---

## G. Histórico Clínico

### G.1 Níveis de visibilidade <a id="g1"></a>

Cinco níveis empilháveis. Cada um é opt-in da clínica.

| Nível | O que paciente vê |
|---|---|
| `none` | Nada além das datas das consultas |
| `summary` | Resumo curto que profissional escreve "para o paciente" (campo separado `patient_visible_note`) |
| `selected_fields` | Campos específicos do `ClinicalNote` (ex: conduct sim, assessment não) |
| `full_signed` | Notas finalizadas e assinadas, integrais |
| `download_pdf` | Mesmo de full_signed + permite baixar PDF |

**Controles da clínica:**
- `clinical_visibility` global
- Override por profissional (ex: psiquiatra força `none`)
- Override por paciente (ex: paciente VIP tem `full_signed`)
- Para cada `ClinicalNote`: switch individual "visível ao paciente" (override)

**Decisão de design crítica:** O DEFAULT é `none`. A clínica liga consciente.

---

### G.2 Anamnese pré-consulta <a id="g2"></a>

**Cenário:** Antes da primeira consulta, paciente recebe formulário pra preencher de casa.

```
[Agendamento de primeira consulta]
        │
        ▼
[Se require_anamnesis_before = true, dispara]
        │
        ▼
[Paciente recebe link, abre portal]
        │
        ▼
[Formulário dinâmico baseado em FormTemplate da clínica/especialidade]
        │
        ▼
[Preenche, salva como Anamnesis draft]
        │
        ▼
[Profissional na consulta abre, complementa, finaliza]
```

**Variantes:**
- **G.2.a Bloqueia consulta se não preencher** (forçar)
- **G.2.b Opcional mas incentivado** (banner na home)
- **G.2.c Por procedimento** (ex: cirurgia exige histórico cirúrgico detalhado)
- **G.2.d Atualização periódica** (cada 12 meses, paciente revê)

**Controles da clínica:**
- Templates de anamnese (já existe `FormTemplate`)
- Quando dispara
- Obrigatório vs opcional
- Quem pode editar depois (paciente pode? só draft? nunca?)

---

### G.3 Receitas e prescrições <a id="g3"></a>

**Cenário:** Profissional emite receita digital pelo Memed (ou outro).

```
[Profissional emite via Memed]
        │
        ▼
[Memed integra com Klivy, anexa Document à consulta]
        │
        ▼
[Paciente vê em "Documentos" → "Receitas"]
        │
        ▼
[Download + opção "Apresentar na farmácia" (QR code)]
```

**Controles da clínica:**
- `prescription_visibility`: none / active_only / all_history
- Auto-arquivar prescrições expiradas
- Mostrar tarja (vermelha/preta/azul)? Privacidade vs informação

**Edge cases:**
- Medicamento controlado: prescrição tem prazo curto, lembrete de validade
- Receita perdida: paciente NÃO pode reemitir — só profissional

---

### G.4 Plano de tratamento <a id="g4"></a>

**Cenário:** Profissional criou plano de 10 sessões. Paciente acompanha progresso.

```
[Plano ativo]
        │
        ▼
[Paciente vê: itens, progresso, próxima sessão, valor]
        │
        ▼
[A cada sessão concluída: timeline atualiza]
        │
        ▼
[Plano concluído: convite para alta ou novo plano]
```

**Controles da clínica:**
- `expose_treatment_plan`
- Mostrar valores ou só sessões?
- Permitir paciente "aprovar" plano remotamente (assina TreatmentPlan)
- Notificar quando plano está perto de terminar

---

### G.5 Exames e laudos <a id="g5"></a>

**Cenário (Fase 3):** Clínica faz exames internos. Paciente acompanha resultado.

```
[Exame realizado]
        │
        ▼
[Profissional anexa resultado a ExamMedia]
        │
        ▼
[Toggle "Liberar imediato" OU "Aguardar profissional revisar"]
        │
        ▼
[Liberado: notifica + paciente baixa]
```

**Decisão crítica (inspirada em MyChart):** alguns resultados são liberados **com delay** — biópsia, oncologia — para não chocar paciente antes da consulta de devolutiva.

**Controles da clínica:**
- `exam_release_strategy`: immediate / delayed_X_days / requires_professional_review / never_via_portal
- Por categoria de exame
- Por paciente (sensibilidade individual)

---

## H. Consentimentos

### H.1 LGPD bloqueante <a id="h1"></a>

**Cenário:** Primeiro acesso. Sem aceite = sem entrada.

```
[Login completo]
        │
        ▼
[PatientPortalConsent não existe para a versão atual]
        │
        ▼
[Modal full-screen com texto, scroll obrigatório até o fim]
        │
        ▼
[Assinatura digital + checkbox]
        │
        ▼
[Aceita] ──► [Salva consent + libera navegação]
[Recusa] ──► [Logout + página "Sem aceite, sem portal"]
```

**Por que bloqueante:** sem LGPD, qualquer dado mostrado é violação. Não há meio termo.

---

### H.2 Por procedimento <a id="h2"></a>

```
[AgendaEvent agendado para procedimento "cirurgia menor"]
        │
        ▼
[Sistema detecta: procedimento exige termo específico]
        │
        ▼
[Cria ConsentRecord status=pending vinculado ao evento]
        │
        ▼
[Notifica paciente]
        │
        ▼
[Paciente assina no portal antes da consulta]
        │
        ▼
[Sem assinatura: dia da consulta, profissional vê alerta vermelho]
```

**Controles da clínica:**
- Catálogo de termos por procedimento/serviço
- Auto-disparo quando agenda esse procedimento
- Bloqueio de consulta se não assinado (opcional)

---

### H.3 Renovação periódica <a id="h3"></a>

**Cenário:** Termo de imagem vale 12 meses. Após expira, pede de novo.

```
[ConsentRecord expires_at = +12 meses]
        │
        ▼
[Job: scan_expiring_consents (daily)]
        │
        ▼
[T-30 dias: notifica paciente "Termo expira em breve, renove"]
        │
        ▼
[T-0: expira] ──► [Nova versão é cobrada na próxima ação que dependa]
```

**Controles da clínica:**
- TTL por tipo de termo
- Antecedência da notificação
- Bloqueio retroativo (uso de dados expirados) — risco regulatório

---

### H.4 Revogação <a id="h4"></a>

**Cenário:** Paciente decide revogar consentimento de uso de imagem.

```
[Paciente abre "Meus consentimentos" → escolhe um → "Revogar"]
        │
        ▼
[Modal: "Tem certeza? Implicações: [lista]"]
        │
        ▼
[Confirma]
        │
        ▼
[ConsentRecord.revoked_at = now, motivo registrado]
        │
        ▼
[Notifica clínica via inbox dedicado "Compliance"]
        │
        ▼
[Trilha de auditoria]
```

**Controles da clínica:**
- Revogação self-service vs precisa aprovação
- Termos não-revogáveis (LGPD básica não pode revogar e continuar usando)
- Notificação para qual fila

---

### H.5 Menor de idade <a id="h5"></a>

**Cenário (Fase 3):** Paciente Lucas (8 anos). Mãe (Joana) precisa assinar.

```
[Joana faz login no portal]
        │
        ▼
[Vê seletor: "Sua conta" OU "Lucas (dependente)"]
        │
        ▼
[Escolhe Lucas]
        │
        ▼
[JWT recarrega com acting_as_responsible=true, responsible_for=lucas_id]
        │
        ▼
[Todos os fluxos rodam no contexto de Lucas]
        │
        ▼
[Quando assina consentimento: registra Joana E Lucas, com vínculo legal]
```

**Controles da clínica:**
- Idade de corte (default 18)
- Idade mínima do paciente ter acesso próprio (default 16, com co-assinatura)
- Vínculo automático por endereço/CPF de pais? (risco — melhor manual)
- Documentação do vínculo (anexar termo de tutela?)

---

## I. Perfil e Dados

### I.1 Atualização cadastral <a id="i1"></a>

Já no PRD §13. Edição livre: telefone secundário, email secundário, endereço, avatar. Edição mediada: CPF, nome, data de nascimento (vira solicitação).

---

### I.2 Dependentes <a id="i2"></a>

Já no PRD §13. Detalhamento:

**Fluxo de vinculação:**

```
[Joana clica "Adicionar dependente"]
        │
        ▼
[Form: CPF do dependente, parentesco, anexar documento (RG/certidão)]
        │
        ▼
[PatientResponsibleLink criado, status=pending]
        │
        ▼
[Tarefa para clínica revisar]
        │
        ▼
[Clínica valida documento, aprova/rejeita]
        │
        ▼
[Aprovado: Joana vê Lucas no seletor]
```

**Controles da clínica:**
- Self-vinculação permitida vs apenas pela clínica
- Documento obrigatório
- Quem aprova
- Vínculo automático para menores cadastrados pelo mesmo `Contact` (mãe e filho no mesmo cadastro)

---

### I.3 Export LGPD <a id="i3"></a>

Já no PRD §17.3.

---

### I.4 Solicitação de exclusão <a id="i4"></a>

**Cenário:** Paciente quer ser esquecido.

```
[Paciente clica "Excluir meus dados"]
        │
        ▼
[Modal explicativo: "Prontuário deve ser preservado por 20 anos (CFM). Vamos anonimizar."]
        │
        ▼
[Confirma]
        │
        ▼
[Cria DeletionRequest, status=pending]
        │
        ▼
[Notifica DPO/admin da clínica]
        │
        ▼
[Admin processa em até 15 dias]
        │
        ▼
[Anonimização]: 
   - Patient.name → "Paciente removido"
   - CPF mantido cifrado (compliance financeira)
   - Contact apagado
   - Conversa apagada
   - Portal access revogado
   - Documentos clínicos preservados (anonimizados quando possível)
```

**Controles da clínica:**
- SLA de processamento
- Quem é o DPO
- Auto-anonimização vs revisão manual

---

## J. Engajamento

### J.1 Recall automático <a id="j1"></a>

Reaproveita `Patient.needs_recall` que já existe.

```
[Job diário: scan_needs_recall]
        │
        ▼
[Patient sem consulta há recall_after_months E status=ativo]
        │
        ▼
[needs_recall = true]
        │
        ▼
[Notifica paciente: "Faz 6 meses — vamos agendar uma consulta?"]
        │
        ▼
[CTA direto: abre fluxo de agendamento]
```

**Controles da clínica:**
- `recall_after_months` por serviço (limpeza = 6m, oftalmo = 12m, etc)
- Canal (portal/whatsapp/email)
- Template
- Frequência max (não encher o paciente)
- Excluir pacientes com status alta/arquivado

---

### J.2 NPS pós-consulta <a id="j2"></a>

```
[Consulta concluída] ──► [+ nps_delay_hours: dispara]
        │
        ▼
[Pergunta única: "De 0 a 10, recomenda a clínica?"]
        │
        ▼
[Resposta]:
   ├── 0-6 (detrator): "Sentimos muito. Quer contar mais?" → conversa para gerente
   ├── 7-8 (passivo): "Obrigado!"
   └── 9-10 (promotor): "Que ótimo! Quer indicar amigos? [Link]"
```

**Controles da clínica:**
- Quando perguntar (delay)
- Frequência (não perguntar a cada consulta — mensal? trimestral?)
- O que fazer com detratores (escalação automática)
- Avaliação pública? (default não — interno)

---

### J.3 Indicação <a id="j3"></a>

**Cenário:** Promotor NPS recebe link de indicação.

```
[Paciente: "Indicar amigos"]
        │
        ▼
[Gera link único com referral_code]
        │
        ▼
[Paciente compartilha]
        │
        ▼
[Amigo abre, agenda primeira consulta (via booking público)]
        │
        ▼
[Sistema vincula ReferralRecord]
        │
        ▼
[Após primeira consulta paga: indicador ganha recompensa]
```

**Controles da clínica:**
- Tipo de recompensa (desconto/dinheiro/sessão grátis)
- Requisitos (consulta paga, X dias depois)
- Limite por paciente
- Aprovação manual vs automática

---

## K. Notificações

### K.1 Canais <a id="k1"></a>

| Evento | Default canal | Alternativas |
|---|---|---|
| Login OTP | WhatsApp | Email |
| Confirmação de agendamento | WhatsApp | Push portal, Email |
| Lembrete T-24h | WhatsApp | Email |
| Mensagem da clínica respondida | Push portal | WhatsApp |
| Cobrança nova | Email + Push | WhatsApp |
| Documento novo | Push portal | WhatsApp, Email |
| NPS | WhatsApp | Email |

**Controles da clínica:**
- Habilitar/desabilitar cada evento
- Override de template
- Frequência máxima por dia (evitar spam)

---

### K.2 Preferências do paciente <a id="k2"></a>

**Cenário:** Paciente quer só email, nada de WhatsApp.

```
[Configurações → Notificações]
        │
        ▼
[Tabela: evento × canal × on/off]
        │
        ▼
[Paciente customiza]
```

**Limites:**
- Notificações de segurança (login suspeito, troca de senha) NUNCA desligáveis.
- Notificações regulatórias (consentimento expirando) NUNCA desligáveis.
- Lembrete T-24h: opt-out apenas se clínica permitir (alta no-show = clínica força).

---

## 3. Matriz de Controle Clínica × Paciente <a id="3-matriz"></a>

Resumo executivo de quem controla o quê.

| Ação | Clínica controla | Paciente faz |
|---|---|---|
| Existir no portal | Cadastrar Patient + enviar convite | Aceitar termo no 1º acesso |
| Logar | — | OTP, escolher clínica se multi |
| Ver agenda | Sempre permitido | Visualiza |
| Agendar 1ª consulta | Modo, formulário, pré-requisitos | Preenche, aguarda aprovação |
| Agendar retorno | Modo, slots liberados | Escolhe slot |
| Reagendar | Modo, janela, taxa | Reagenda ou solicita |
| Cancelar | Modo, janela, taxa | Cancela ou solicita |
| Confirmar presença | Obrigatoriedade, T- | Confirma |
| Faltar | Política de no-show, taxa | (faltou) |
| Ver parcela | Quais campos | Visualiza |
| Pagar | Métodos, taxas, parcelamento | Paga |
| Pedir reembolso | Política | Solicita |
| Ver documento | Quais tipos liberados | Baixa |
| Pedir documento | Quais tipos requestables | Solicita |
| Subir documento | Permite ou não | Faz upload |
| Mandar mensagem | Quem é destino, urgência | Manda |
| Ver evolução | Nível de visibilidade | Visualiza |
| Preencher anamnese | Quando exigir | Preenche |
| Aceitar consentimento | Quais termos | Assina |
| Revogar consentimento | Quais permitem | Revoga |
| Atualizar perfil | Quais campos livres | Atualiza |
| Adicionar dependente | Self vs aprovado | Solicita |
| Export LGPD | SLA | Solicita |
| Excluir conta | Política de anonimização | Solicita |
| Receber recall | Quando, canal | (recebe) |
| Responder NPS | Quando perguntar | Responde |
| Indicar amigos | Programa ativo, recompensa | Compartilha link |

---

## 4. Inspirações de Concorrentes <a id="4-concorrentes"></a>

### Epic MyChart (EUA — gold standard hospitalar)
- **Que copiei:** distinção "schedule directly" vs "request appointment"; release de exames com delay configurável; family proxy access; messaging com triagem urgente.
- **Que NÃO copiei:** complexidade absurda do menu — eles têm 30+ funcionalidades, vamos com as essenciais.

### Doctoralia / Zocdoc (booking marketplace)
- **Copiei:** UX limpa de seleção de slot; filtro por convênio; reviews públicos.
- **NÃO:** modelo de marketplace (Klivy é por clínica).

### iClinic / Doutorado (Brasil)
- **Copiei:** simplicidade do portal, foco em confirmação e financeiro; templates em PT-BR.
- **NÃO:** falta de configuração granular — clínica não tem o controle que a gente quer dar.

### SimplePractice (terapia/saúde mental)
- **Copiei:** consentimento por procedimento, sliding scale fees, "private notes" separadas de "patient-visible notes".
- **NÃO:** foco exclusivo em sessões individuais; nosso PRD precisa cobrir times.

### Healthie (practice management)
- **Copiei:** configurabilidade por profissional/serviço; assinaturas/pacotes; intake forms dinâmicos.
- **NÃO:** features fitness/wellness fora do escopo clínico.

### Mindbody (fitness/spa)
- **Copiei:** pacotes/créditos; auto-debit; check-in mobile.
- **NÃO:** marketplace e gamificação.

### Memed (receita digital BR)
- **Copiei:** integração para receita digital.
- **Considerar:** parceria/integração ao invés de construir do zero.

### Asaas / Pagar.me / Stripe
- **Para gateway:** Asaas tem cobertura ampla (PIX/boleto/cartão), API ok, taxas competitivas, foco BR. Recomendado.

---

## 5. Decisões em Aberto <a id="5-decisoes"></a>

Específicas de fluxos (complementam D-1 a D-7 do PRD):

| # | Decisão | Recomendação |
|---|---|---|
| F-1 | Default de `scheduling_mode` para 1ª consulta? | `request_only` (segurança) |
| F-2 | Default de `scheduling_mode` para retorno? | `slot_picker` (autonomia controlada) |
| F-3 | Cobrar no-show automaticamente? | **Não** por default (delicado legalmente; opt-in) |
| F-4 | Cobrar cancelamento tardio automaticamente? | **Não** por default (mesma razão) |
| F-5 | Permitir paciente mandar mensagem direto pro profissional? | **Não** por default (sobrecarrega quem cuida) |
| F-6 | Anamnese obrigatória antes da 1ª consulta? | **Sim** por default (intake form) |
| F-7 | Mostrar evolução clínica? | **Não** por default (opt-in por campo) |
| F-8 | Auto-aprovar pedido de 2ª via de recibo? | **Sim** (baixíssimo risco) |
| F-9 | Permitir upload de exames externos pelo paciente? | **Não** no MVP (Fase 3) |
| F-10 | Permitir self-vinculação de dependente? | **Não** — só pela clínica (Fase 3) |
| F-11 | Resultado de exame: liberar imediato ou aguardar revisão? | Configurável; default `requires_professional_review` |
| F-12 | Auto-block portal por inadimplência? | **Não** por default (paciente perde via para se comunicar) |
| F-13 | NPS público (review) ou interno? | Interno no MVP |
| F-14 | Pacote de tratamento: cancelamento gera estorno parcial automático? | **Não** — vira solicitação |
| F-15 | Permitir agendar para procedimento sem consulta prévia? | **Não** por default (segurança clínica) |
| F-16 | Lista de espera é FIFO ou priorizada? | FIFO no MVP |
| F-17 | Receita de medicamento controlado: reemissão self-service? | **Nunca** |
| F-18 | Mensagem urgente: força telefone, escala plantão ou abre fila? | Configurável por especialidade |
| F-19 | Termo de imagem expira em? | 12 meses default |
| F-20 | Recall padrão? | 6 meses para odonto/estética, 12 meses para médico |

---

**Fim do documento.**
