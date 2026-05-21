# PRD — Portal do Paciente (pacientes.klivy.app)
## Product Requirements Document (v1.1)

**Produto:** Portal do Paciente — extensão da Klivy (BeClinic)
**Base:** Klivy (Chatwoot fork) — reaproveita modelos `Patient`, `Contact`, `AgendaEvent`, `Installment`, `Document`, `ConsentRecord`, `Conversation`
**Escopo deste documento:** Aplicação web pública voltada ao paciente final, separada visualmente do sistema da clínica mas servida pelo mesmo backend.
**Companion:** [`patient-portal-fluxos.md`](./patient-portal-fluxos.md) — catálogo detalhado de fluxos e controles operacionais
**Data:** 2026-05-18 (v1.1) · 2026-05-17 (v1.0)
**Status:** Especificação técnica para início de desenvolvimento

### Changelog v1.0 → v1.1
- Incorporado modelo de configuração granular do companion de Fluxos (~80 controles em 7 categorias, antes 5 colunas).
- Adicionado conceito de **Modos de Operação** (presets) — MVP entrega "Autonomia Guiada"; demais presets na Fase 2.
- Adicionada **hierarquia de configuração**: Account → Profissional → Serviço → Procedimento → Tag de paciente.
- Modelo de dados expandido: `AppointmentRequest`, `DocumentRequest`, `PortalInvite`, `PatientNotificationPreference`, `ProfessionalPortalSetting`, `AgendaServiceSetting`, colunas novas em `Patient`, `ClinicalNote`, `Document`, `ConsentRecord`.
- Reescopo MVP/F2/F3 alinhado com Fluxos: pre-flight checks, recall, anamnese pré-consulta e revogação de consentimento entram no **MVP**; pagamento online, cobranças automáticas (no-show/late cancel), slot picker, NPS e validade de documentos entram na **Fase 2**; referral, dependentes, exames com delay e upload paciente permanecem **Fase 3**.
- Endpoints expandidos (\§15) e decisões em aberto consolidadas com F-1 a F-20 do companion (\§19).

---

## Índice

1. [Visão Executiva](#1-visao-executiva)
2. [Problema e Oportunidade](#2-problema-e-oportunidade)
3. [Personas](#3-personas)
4. [Escopo (MVP, Fase 2, Fase 3) + Modos de Operação](#4-escopo)
5. [Módulo: Autenticação, Convite e Suspensão](#5-modulo-autenticacao)
6. [Módulo: Home (Painel do Paciente)](#6-modulo-home)
7. [Módulo: Agendamentos (modos, pre-flight, AppointmentRequest)](#7-modulo-agendamentos)
8. [Módulo: Evolução / Histórico Clínico + Anamnese](#8-modulo-evolucao)
9. [Módulo: Financeiro do Paciente](#9-modulo-financeiro)
10. [Módulo: Documentos + DocumentRequest](#10-modulo-documentos)
11. [Módulo: Consentimentos (LGPD) + Revogação](#11-modulo-consentimentos)
12. [Módulo: Comunicação + Templates de Roteamento + Triagem Urgente](#12-modulo-comunicacao)
13. [Módulo: Perfil e Dependentes](#13-modulo-perfil)
13bis. [Módulo: Engajamento (Recall, NPS, Referral)](#13bis-engajamento)
13ter. [Módulo: Notificações](#13ter-notificacoes)
14. [Arquitetura Técnica + Hierarquia de Configuração + Presets](#14-arquitetura)
15. [Endpoints API](#15-endpoints)
16. [Modelo de Dados (novas tabelas e colunas)](#16-modelo-de-dados)
17. [Segurança, Privacidade e LGPD](#17-seguranca-lgpd)
18. [Roadmap por Sprint](#18-roadmap)
19. [Riscos, Premissas e Decisões em Aberto](#19-riscos)
20. [Anexo: Sugestões Adicionais do Claude](#20-sugestoes-claude)

---

## 1. Visão Executiva

O **Portal do Paciente** é uma aplicação web acessível em `pacientes.klivy.app` que dá ao paciente final autonomia para acompanhar seus agendamentos, evolução clínica, situação financeira, documentos emitidos e se comunicar com a clínica que o atende. O sistema é servido pelo mesmo backend Rails da Klivy (sistema.klivy.app), em um namespace novo (`/api/v1/patient_portal/`), com autenticação isolada e um SPA dedicado.

A arquitetura **reaproveita os modelos existentes** (`Patient`, `AgendaEvent`, `Installment`, `Document`, `ConsentRecord`, `ClinicalNote`, `Conversation`) e introduz apenas a camada de autenticação, configuração granular e auditoria específica do portal. Multi-tenancy é resolvida via `Account` (cada clínica = uma account) e o paciente identifica sua clínica automaticamente pelo `Contact` vinculado ao seu telefone/email no momento do login.

### 1.1 Princípios de produto

1. **Default-deny.** Nenhum controle "perigoso" (auto-agendamento, expor evolução, pagar com cartão) vem ligado por padrão. A clínica liga conscientemente.
2. **Configurável por camada.** Account → Profissional → Serviço → Procedimento → Tag de paciente. Regra mais específica vence.
3. **Toda ação tem trilha.** Cada interação gera evento em `PatientPortalAccessLog` + `PatientTimelineEvent` quando aplicável.
4. **Paciente nunca surpreende a clínica.** Toda solicitação que altera agenda/financeiro passa pelo painel da clínica como tarefa.
5. **Clínica nunca surpreende o paciente.** Mudanças visíveis (cancelamento, cobrança, novo documento) disparam notificação.
6. **Vias de escape.** Para tudo que é automatizado, existe um botão "Falar com a clínica".
7. **Auto-serviço quando seguro, mediação quando importa.** Pagar uma parcela = seguro. Marcar primeira consulta = importa.

### 1.2 Fasamento

- **MVP (Sprint A-E):** Autonomia Guiada como preset único. Visualização (agenda/financeiro/documentos), solicitação de agendamento (`request_only`), confirmação/cancelamento de consulta dentro de janela, pre-flight checks, recall, anamnese pré-consulta, mensageria com triagem urgente, revogação de consentimento.
- **Fase 2 (Sprint F-H):** Pagamento online (Asaas), cobranças automáticas opt-in (no-show fee, late cancel fee, pré-pagamento), demais presets (Recepção Digital / Self-Service / Concierge), `slot_picker` e `direct_booking`, NPS, validade de documentos, switcher inline de clínica, mensagem dirigida a profissional.
- **Fase 3 (Sprint I+):** Dependentes/menores, programa de indicação (referral), upload de exames externos pelo paciente, exames com release strategy, self-checkin, reembolso de convênio.

---

## 2. Problema e Oportunidade

### 2.1 Problema

Hoje todo contato do paciente com a clínica passa pela recepção: confirmar horário, descobrir quanto deve, pegar atestado, mandar uma dúvida pro doutor. Isso gera:

- **Sobrecarga operacional** na recepção para tarefas repetitivas (envio de boleto, confirmação, repasse de documento).
- **Atrito do paciente** que precisa ligar/mandar WhatsApp no horário comercial pra cada solicitação.
- **Faltas e inadimplência evitáveis** quando o paciente esquece o horário ou desconhece a parcela em aberto.
- **Documentos perdidos** (atestado, encaminhamento) que precisam ser reenviados manualmente.
- **Conformidade LGPD frágil**: consentimentos coletados no papel ou WhatsApp, sem trilha auditável.

### 2.2 Oportunidade

Mover essas interações para um portal self-service:
- Libera tempo da recepção.
- Reduz no-show através de lembretes e confirmação digital.
- Acelera o pagamento (paciente vê parcela e paga sem precisar pedir boleto).
- Centraliza documentos com download seguro e auditado.
- Coleta consentimentos com assinatura digital versionada (já existe `ConsentRecord` com `remote_token`).
- Posiciona a Klivy como produto **completo** para o paciente, não só para o dono da clínica.

---

## 3. Personas

| Persona | Descrição | Necessidades principais |
|---|---|---|
| **Paciente adulto** | Maior de idade, atendido por uma clínica | Ver agenda, pagar parcela, baixar atestado, falar com a clínica |
| **Responsável legal** | Adulto que gerencia o atendimento de um menor de idade ou tutelado | Acessar a conta do dependente, assinar consentimentos pelo menor, pagar |
| **Paciente menor (≥13 anos)** | Adolescente que pode ter acesso limitado de visualização | Ver agenda e mensagens, sem acesso a financeiro ou consentimentos |
| **Paciente multi-clínica** | Atendido em mais de uma clínica que usa Klivy | Alternar entre clínicas no mesmo login |

---

## 4. Escopo

A divisão MVP/Fase 2/Fase 3 reflete as decisões de produto da v1.1 (ver Changelog). MVP entrega o preset **"Autonomia Guiada"** como modo único — visualização + solicitações + auto-serviço seguro. Cobrança automática e demais presets ficam para Fase 2.

### 4.1 MVP (Sprint A–E)

**Identidade e onboarding:**
- Login com OTP (e-mail ou WhatsApp).
- Convite de paciente pela clínica (auto ou manual) com `PortalInvite`.
- Seleção de clínica quando o paciente existe em múltiplas accounts.
- Aceite digital de Termo de Uso + Política de Privacidade (LGPD) bloqueante no primeiro acesso.
- Suspensão/bloqueio de paciente pela clínica (com motivo e janela).

**Home e visualização:**
- Cards de próximas consultas, parcelas em aberto, mensagens não lidas, consentimentos pendentes, recall.
- Banner bloqueante para consentimento LGPD pendente.

**Agendamento (modo `request_only` apenas — Autonomia Guiada):**
- Lista de agendamentos (futuros e passados) com detalhe.
- Botão "Confirmar presença".
- Botão "Solicitar reagendamento" e "Solicitar cancelamento" → cria `AppointmentRequest`.
- **Pre-flight checks**: bloqueia "Agendar" se há consentimento pendente, parcela vencida (configurável) ou anamnese não preenchida.
- Distinção 1ª consulta vs retorno (com formulário extra na primeira).
- Cancelamento self-service dentro da janela configurada (sem cobrança automática no MVP).

**Financeiro (somente leitura):**
- Resumo: total em aberto, total pago no ano, próxima parcela.
- Lista de parcelas com status (aberto, pago, em atraso).
- Detalhe da parcela e histórico de pagamentos.
- Download de recibo (PDF) para parcelas pagas.

**Documentos:**
- Lista de documentos com filtro por tipo, download via signed URL (TTL 15 min).
- Solicitação de documento pelo paciente (`DocumentRequest` — ex: 2ª via de recibo, atestado retroativo).
- Compartilhamento via link público de uso único.

**Consentimentos:**
- Lista (pendentes + assinados) com aceite digital touch + IP + UA.
- **Revogação self-service** com notificação para inbox "Compliance" da clínica.
- Termos por procedimento (vinculados a `AgendaEvent`).

**Comunicação:**
- Caixa de entrada reaproveitando `Conversation` do Chatwoot em inbox tipo `api` dedicado por account.
- Templates rápidos pré-preenchidos com roteamento por fila ("Pedir reagendamento" → Recepção, "Dúvida financeira" → Financeiro).
- Auto-resposta fora de `business_hours`.
- **Triagem urgente**: keyword matching com ação configurável (padrão `force_phone`).

**Anamnese pré-consulta:**
- Formulário dinâmico baseado em `FormTemplate` existente, disparado no agendamento (configurável).

**Engajamento:**
- **Recall automático** reaproveitando `Patient.needs_recall` (notificação + CTA agendar).

**Perfil:**
- Visualizar dados cadastrais; atualizar telefone secundário, e-mail secundário, endereço, foto.
- Solicitação de correção de campos sensíveis (CPF, nome, data nasc) via conversa.
- Export de dados (LGPD).
- Solicitação de exclusão (anonimização, preserva prontuário 20 anos).

**Notificações:**
- Matriz padrão (login OTP via WhatsApp, lembretes T-24h, novo documento, etc.).
- Preferências do paciente (canais por evento), respeitando notificações não-desligáveis (segurança, regulatórias).

### 4.2 Fase 2 (Sprint F–H)

**Pagamento e cobrança:**
- Pagamento online via gateway (recomendação: Asaas — PIX/boleto/cartão).
- Cobranças automáticas opt-in: `no_show_fee`, `late_cancel_fee`, pré-pagamento por serviço.
- Pagamento parcial, antecipação com desconto, renegociação.
- Reembolso/estorno automático quando clínica cancela.
- Bloqueio progressivo por inadimplência (`warn` → `limit_scheduling` → `limit_messaging_to_financial` → `full_block`).

**Agendamento avançado:**
- Modos `slot_picker` e `direct_booking` para retornos.
- Lista de espera (`WaitingListEntry`) com top-da-fila notificado em vagas.
- Múltiplos reagendamentos com limite (`max_reschedules_per_event`).

**Demais presets:**
- "Recepção Digital", "Self-Service" e "Concierge" disponíveis com switch único.

**Documentos:**
- Validade (`expires_at`) e badge "Expirado".
- Documentos com assinatura do paciente vinculados a `AgendaEvent`.

**Consentimentos:**
- Renovação periódica automática (`expires_at` + job de aviso).

**Comunicação:**
- Mensagem dirigida a profissional específico (opt-in por profissional).
- Anexar arquivos (≤ 10 MB).
- Indicador de "lida" pela clínica.

**Engajamento:**
- NPS pós-consulta com roteamento detrator/passivo/promotor.

**Multi-clínica:**
- Switcher inline no header (sem relogar).

### 4.3 Fase 3 (Sprint I+)

- Dependentes / gestão de menores pelo responsável (`PatientResponsibleLink`).
- Programa de indicação (referral) com `ReferralRecord` + `referral_code`.
- Upload de exames externos pelo paciente (`ExamMedia` com `uploaded_by_patient`).
- Release strategy para resultados de exames (immediate / delayed / requires_review).
- Self-checkin (geofence ou QR code na recepção).
- Reembolso de convênio (pacote: recibo + relatório médico + TUSS + CID).
- Telemedicina (link da consulta, se a clínica oferecer).
- Avaliação pública / reviews da clínica.

### 4.4 Fora de Escopo

- App nativo iOS/Android (web responsive resolve).
- Prescrição médica digital com assinatura ICP-Brasil (paciente só visualiza).
- Marketplace entre clínicas.
- Sincronização consolidada multi-clínica (cada clínica é silo — princípio de segurança).

### 4.5 Modos de Operação (Presets)

Para reduzir tempo de configuração, o portal oferece **presets** que ativam combinações pré-definidas dos controles de `PatientPortalSetting` (ver \§14.7 e companion de Fluxos \§2). A clínica pode customizar livremente depois.

| Preset | Quando entra | Resumo |
|---|---|---|
| **Autonomia Guiada** (default) | MVP | Confirmar/cancelar dentro de janela: livre. Reagendar/agendar primeira consulta: solicitação. Retornos: paciente agenda em slots liberados pelo profissional. Pagar parcela: livre. Documentos emitidos: livre. Visualização clínica: opt-in. |
| **Recepção Digital** (conservador) | Fase 2 | Paciente vê tudo, muda quase nada. Todo agendamento/reagendamento/cancelamento vira solicitação que cai na fila da recepção. Para clínicas tradicionais e especialidades sensíveis (psiquiatria, oncologia). |
| **Self-Service** (liberal) | Fase 2 | Agendamento direto em slots públicos para retornos E primeiras consultas. Reagendar/cancelar com cobrança automática quando aplicável. Pré-pagamento obrigatório por serviço. Anamnese obrigatória. Para estética, exames, telemedicina, cadeias. |
| **Concierge** (premium) | Fase 2 | Tudo configurável por tag/segmento. VIPs sem cobrança de cancelamento; inadimplentes restritos; convênios com fluxo de pré-autorização. Para alto ticket. |

**Migração entre modos:** mudanças que **restringem** (ex: liberal → conservador) aplicam só a novas interações; agendamentos já feitos pelo paciente continuam válidos.

> **Decisão de produto (v1.1):** MVP oferece apenas "Autonomia Guiada" como preset selecionado por default na ativação. Os switches granulares já existem desde a Sprint A, permitindo customização. Outros presets (Recepção/Self-Service/Concierge) aparecem na UI a partir da Fase 2.

---

## 5. Módulo: Autenticação e Identificação <a id="5-modulo-autenticacao"></a>

### 5.1 Visão Geral

Login passwordless via OTP de 6 dígitos enviado por e-mail ou WhatsApp. Não há cadastro: o paciente só consegue entrar se já existe um `Contact` (e portanto um `Patient`) vinculado ao seu telefone/email em alguma clínica Klivy.

### 5.2 Fluxo de Login

1. Paciente acessa `pacientes.klivy.app`.
2. Informa telefone (com DDI) ou e-mail.
3. Backend procura `Contact` por `phone_number` ou `email` em qualquer `Account`.
4. Se encontrado em pelo menos uma account, gera OTP de 6 dígitos com TTL de 10 min, persiste hash em `patient_portal_otps` e envia:
   - **E-mail:** via ActionMailer (já configurado).
   - **WhatsApp:** via inbox dedicado da Klivy (não da clínica — explicado na seção 17).
5. Paciente digita o OTP no portal.
6. Backend valida e:
   - **1 account:** loga direto, emite JWT com `patient_portal_user_id` e `current_account_id`.
   - **N accounts:** retorna lista de clínicas com nome/logo; paciente escolhe; JWT é emitido para a account escolhida.
7. JWT vale 7 dias. Refresh silencioso enquanto a sessão estiver ativa.

### 5.3 Primeiro Acesso

- No primeiro login do paciente, exibe modal de aceite do **Termo de Uso do Portal** + **Política de Privacidade**.
- Sem aceite, nenhum dado é exibido.
- Aceite é persistido em `patient_portal_consents` com versão do termo, IP, user-agent e timestamp.

### 5.4 Regras de Negócio

- Não há autocadastro. Se o paciente não tem `Contact` em nenhuma clínica, o portal exibe "Não encontramos seu cadastro. Procure a clínica para se cadastrar."
- Telefone deve estar no formato E.164 (+5511999999999). Backend normaliza antes de buscar.
- Máximo de 5 OTPs por 24h por destinatário (anti-flood).
- OTP é invalidado após uso, expiração ou 3 tentativas erradas.
- Troca de e-mail/telefone só pode ser feita pela clínica (no sistema, módulo Pacientes). Paciente solicita pela conversa.

### 5.5 Edge Cases

- Paciente com mesmo telefone em 5 clínicas: lista de seleção paginada.
- Paciente troca de número: precisa avisar a clínica (não há fluxo de auto-update no MVP).
- Tentativa de login com Contact sem `Patient` vinculado: trata como inexistente (o portal só atende quem está no módulo Pacientes).

### 5.6 Convite e Ativação (Fluxos A.1)

Antes do paciente poder fazer login, a clínica precisa habilitar o acesso. O modelo `PortalInvite` rastreia esse processo.

**Fluxos suportados (MVP):**

| Variante | Quando |
|---|---|
| **A.1.a Auto-convite** | Ao criar `Patient`, dispara convite automaticamente. Toggle `auto_invite_on_create` em `PatientPortalSetting`. |
| **A.1.b Convite explícito** | Recepção dispara manualmente quando quiser (botão "Convidar para o portal" no perfil do paciente). |
| **A.1.c Booking público gera convite** | Paciente que se agendou via link público recebe convite junto com a confirmação. |
| **A.1.d Sem convite** | Portal não funciona para o paciente até a clínica habilitar — paciente que tentar login vê "Procure a clínica para se cadastrar". |

**Fluxo:**
```
[Recepção/Sistema cria PortalInvite]
        │
        ▼
[Job envia mensagem via inbox WhatsApp da clínica:
 "Maria, a Clínica X criou seu acesso. Entre em pacientes.klivy.app"]
        │
        ▼
[Paciente entra, faz login OTP, vê termo LGPD]
        │
        ▼
[Aceita] ──► [PortalInvite.accepted_at = now] ──► [Home carrega]
```

**Controles da clínica:**
- `auto_invite_on_create` (bool, default false)
- `invite_message_template` (texto com variáveis: `{patient_name}`, `{clinic_name}`)
- `welcome_message_post_first_login` (texto)

**Edge cases:**
- Paciente sem telefone nem email: convite impossível, recepção precisa cadastrar primeiro.
- Paciente que solicitou exclusão e volta: ao tentar logar, sistema reconhece e oferece reativar (cria nova `PortalInvite`).

### 5.7 Suspensão e Bloqueio (Fluxos A.4)

Clínica pode suspender acesso do paciente sem apagar dados (assédio, inadimplência crônica, etc.).

**Modelagem:** Adiciona-se `portal_status` em `Patient`:
- `active` (default) — acesso normal
- `suspended_temporary` — bloqueio até `portal_suspended_until`
- `suspended_permanent` — bloqueio até reativação manual
- `restricted` — apenas visualização (sem mensagens nem agendamento)

**Fluxo:**
- UI no painel do paciente (aba "Portal" → "Suspender acesso"): motivo obrigatório, data fim opcional.
- Login bloqueado retorna: "Acesso temporariamente indisponível. Procure a recepção."
- Auditado em `PatientPortalAccessLog` como `suspension_change`.

**Controles da clínica:**
- Razão obrigatória ao suspender (campo `suspension_reason`)
- Notificar paciente do motivo (opcional)
- Listar/auditar suspensões ativas

---

## 6. Módulo: Home (Painel do Paciente) <a id="6-modulo-home"></a>

### 6.1 Visão Geral

Tela inicial pós-login, formato dashboard com cards resumo e CTAs principais.

### 6.2 Componentes

| Componente | Conteúdo |
|---|---|
| Header | Logo da clínica selecionada, nome do paciente, avatar, seletor de clínica (se multi), menu |
| Próxima consulta | Data, hora, profissional, serviço, botão "Confirmar presença" e "Pedir reagendamento" |
| Pendências financeiras | Total em aberto, parcela mais próxima do vencimento, CTA "Ver financeiro" |
| Mensagens | Última mensagem da clínica, contador de não lidas, CTA "Abrir conversa" |
| Documentos recentes | Últimos 3 documentos emitidos com link de download |
| Consentimentos pendentes | Banner destacado se houver consentimento aguardando assinatura |
| Recall (opcional) | Banner "Faz X meses desde seu último atendimento — agendar agora?" se `Patient.needs_recall = true` |

### 6.3 Regras

- Card desaparece se não há conteúdo (ex: sem próxima consulta, sem pendência).
- Consentimentos pendentes bloqueiam navegação se forem do tipo `blocking` (ex: LGPD obrigatório).

---

## 7. Módulo: Agendamentos <a id="7-modulo-agendamentos"></a>

### 7.1 Visão Geral

Lista cronológica de `AgendaEvent` onde `contact_id` corresponde ao paciente logado, dentro da account ativa. **Quatro modos de operação** suportados pelo sistema; **MVP entrega apenas `request_only`** (Autonomia Guiada). Os demais entram na Fase 2.

### 7.2 Modos de Agendamento

| Modo | Quando | Comportamento |
|---|---|---|
| `disabled` | F2 | Paciente não vê calendário. Botão "Agendar" leva direto a mensagem na conversa. |
| `request_only` | **MVP** | Paciente preenche solicitação (serviço, profissional, 3 preferências de horário, observação). Cai em fila no painel da clínica como `AppointmentRequest`. Recepção confirma com slot ou propõe alternativa. |
| `slot_picker` | F2 | Profissional libera janelas explícitas; paciente vê só essas e escolhe. Agendamento direto (status `confirmed`). |
| `direct_booking` | F2 | Paciente vê toda a agenda real e escolhe qualquer slot vazio respeitando `AgendaSetting`. |

Configuração: `scheduling_mode` em `PatientPortalSetting` (default `request_only`). Override por profissional via `ProfessionalPortalSetting.scheduling_mode_override` ou por serviço via `AgendaServiceSetting.scheduling_mode_override`. Regra mais específica vence.

### 7.3 AppointmentRequest (entidade MVP)

Modelo novo que materializa a fila de solicitações:

| Campo | Tipo | Notas |
|---|---|---|
| `account_id` | bigint | Multi-tenancy |
| `patient_id` | bigint | FK |
| `agenda_service_id` | bigint nullable | Serviço solicitado |
| `professional_user_id` | bigint nullable | Profissional preferido |
| `preferred_slots` | jsonb | Lista de até 3 preferências `{date, period}` |
| `purpose` | enum | `new_appointment` / `reschedule` / `cancellation` |
| `original_event_id` | bigint nullable | Quando é reagendamento/cancelamento |
| `notes` | text | Observação do paciente |
| `status` | enum | `pending` / `confirmed` / `proposed` / `rejected` / `cancelled` |
| `resolved_at` | datetime nullable | Quando recepção fechou |
| `resolved_by_user_id` | bigint nullable | Quem resolveu |
| `resolved_agenda_event_id` | bigint nullable | Evento criado quando confirmou |
| `is_first_visit` | boolean | Calculado no momento da criação |

### 7.4 Distinção 1ª consulta vs retorno (MVP)

**Detecção:** paciente é "primeira consulta" para profissional X se nunca teve `AgendaEvent.completed` com `user_id = X` ou para a especialidade.

**Comportamento no MVP (`request_only`):**
- Primeira consulta: formulário extra obrigatório (motivo, encaminhamento, convênio, foto do documento).
- Retorno: formulário simples.
- Tag `is_first_visit = true` em `AppointmentRequest`.

**Settings relacionados (catálogo completo na \§14.7):**
- `first_visit_mode` (`request_only` / `slot_picker` na F2)
- `first_visit_questionnaire` (form_template_id)
- `first_visit_requires_referral` (bool)
- `first_visit_intake_form_id` (vincula anamnese pré-consulta)

### 7.5 Pre-flight Checks (MVP)

Antes de abrir o calendário/formulário de agendamento, sistema valida:

```
[Paciente clica "Agendar"]
        │
        ▼
[Pre-flight]
   ├── consent ok? ─── não ──► "Antes, assine o termo de privacidade"
   ├── overdue? ────── sim ──► "Resolva parcelas vencidas. [Pagar agora]"
   ├── anamnesis ok? ── não ──► "Preencha sua anamnese para continuar"
   ├── max ativas? ─── sim ──► "Você já tem N consultas em aberto"
   └── all ok ──────────────► Mostra fluxo de agendamento
```

**Settings:**
- `block_if_pending_consent` (default true)
- `block_if_overdue` + `block_overdue_days` (default false; F2 ativa cobrança)
- `require_anamnesis_before_scheduling` (default false)
- `max_active_appointments` (default unlimited)

### 7.6 Funcionalidades — MVP

| Funcionalidade | Descrição |
|---|---|
| Lista futura | Eventos com `starts_at >= now`, ordem ascendente |
| Lista passada | Eventos `< now`, ordem descendente, paginada |
| Detalhe do evento | Data, hora, duração, profissional, serviço, status, observações públicas |
| Confirmar presença | Botão para eventos com status `scheduled`; muda para `confirmed` e registra timeline |
| Solicitar reagendamento | Cria `AppointmentRequest` com `purpose=reschedule` |
| Solicitar cancelamento | Se dentro da `cancel_window_hours`, cancela direto; fora, cria `AppointmentRequest` com `purpose=cancellation` |
| Filtros | Por profissional, por status |

### 7.7 Funcionalidades — Fase 2

- Modos `slot_picker` e `direct_booking`.
- Reagendamento self-service dentro de janela (`reschedule_window_hours`).
- Limite `max_reschedules_per_event` (após N, vira `request_only`).
- Lista de espera (`WaitingListEntry`) exposta no portal com top-da-fila notificado.
- Cobrança automática (`late_cancel_fee`, `no_show_fee`) — ver \§9.
- Pré-pagamento por serviço (`require_prepayment`).

### 7.8 Funcionalidades — Fase 3

- Self-checkin com geofence ou QR code (`self_checkin_enabled`).
- Confirmação multi-step (questionário de sintomas pré-consulta).

### 7.9 Regras de Negócio

- Paciente só vê eventos onde `contact_id = current_contact.id` no account ativo.
- Status `pending_confirmation` (Bea aguardando humano) **não aparece** para o paciente.
- Eventos com `cancelled` aparecem na lista passada com badge.
- Observações marcadas como `internal` no `AgendaEvent` **nunca** são expostas (ver coluna `notes_internal` separada — \§16).
- Pacientes flagados como `chronic_no_show` têm agendamentos forçados a `request_only` mesmo em modos liberais (Fase 2).

### 7.10 Integrações

- Confirmar presença dispara o mesmo callback que a confirmação interna (timeline + notificação opcional).
- `AppointmentRequest` criado dispara evento para inbox configurado em `appointment_request_inbox_id`.
- Cancelamento dentro da janela libera o slot E oferece para top da `WaitingListEntry` (F2).

---

## 8. Módulo: Evolução / Histórico Clínico <a id="8-modulo-evolucao"></a>

### 8.1 Visão Geral

Linha do tempo do que aconteceu nos atendimentos do paciente, com **5 níveis de visibilidade configuráveis** pela clínica. **Default `none`** (princípio default-deny — clínica liga conscientemente).

### 8.2 Níveis de Visibilidade Clínica

| Nível | O que paciente vê | Quando entra |
|---|---|---|
| `none` | Nada além das datas das consultas | MVP (default) |
| `summary` | Resumo curto escrito pelo profissional "para o paciente" — campo separado `patient_visible_note` em `ClinicalNote` | MVP |
| `selected_fields` | Campos específicos do `ClinicalNote` (ex: `conduct` sim, `assessment` não) — array `expose_clinical_note_fields` | MVP |
| `full_signed` | Notas finalizadas e assinadas, integrais | F2 |
| `download_pdf` | Mesmo de `full_signed` + permite baixar PDF | F2 |

**Setting:** `clinical_visibility` em `PatientPortalSetting`. Override em `ProfessionalPortalSetting.clinical_visibility_override` (ex: psiquiatra força `none`) ou por paciente via tag (Concierge, F2).

### 8.3 Anamnese Pré-consulta (MVP)

`FormTemplate` já existe no Klivy. O portal expõe formulário dinâmico antes da consulta.

```
[Agendamento de primeira consulta]
        │
        ▼
[Se require_anamnesis_before = true]
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

**Settings:**
- `require_anamnesis_before_scheduling` (bool, default false — clínica liga)
- `anamnesis_form_template_id` (FK em FormTemplate)
- `anamnesis_blocks_scheduling` (bool — se true, pre-flight bloqueia agendamento sem preencher)
- `anamnesis_update_period_months` (F2 — pedir revisão periódica)

### 8.4 Funcionalidades

| Funcionalidade | Descrição | Fase |
|---|---|---|
| Timeline de consultas | Cards com data, profissional, resumo público (se nível ≥ `summary`) | MVP |
| Plano de tratamento | `TreatmentPlan` ativo: itens, progresso, status — toggle `expose_treatment_plan` | MVP |
| Sessões realizadas | Lista de `SessionLog` com data e procedimento — toggle `expose_session_logs` | MVP |
| Resumo de evolução | Campos selecionados por clínica (`selected_fields`) | MVP |
| Download PDF evolução | `download_pdf` permitido | F2 |
| Exames com release strategy | `immediate` / `delayed_X_days` / `requires_professional_review` / `never_via_portal` | F3 |

### 8.5 Regras de Negócio

- **Apenas notas `signed_at IS NOT NULL`** são expostas. Rascunhos nunca.
- Campos com flag `private = true` no `ClinicalNote` nunca são expostos (default `private = true` — opt-in explícito por campo).
- Cada acesso a `ClinicalNote` gera entrada em `PatientPortalAccessLog`.
- Receita de medicamento controlado: paciente NÃO pode reemitir — só profissional.

### 8.6 Decisões fechadas e em aberto

- **D-1 (fechada):** Default `none` (opt-in da clínica).
- **D-2 (fechada):** Download PDF na Fase 2 (não MVP).
- **D-8 (aberta):** Anamnese revogável pelo paciente após assinada? (recomendo não — versionada como `ConsentRecord`)

---

## 9. Módulo: Financeiro do Paciente <a id="9-modulo-financeiro"></a>

### 9.1 Visão Geral

Visão completa das obrigações financeiras do paciente naquela clínica. **MVP é somente leitura**; pagamento online e cobranças automáticas (no-show fee, late cancel fee, pré-pagamento) entram na **Fase 2**.

### 9.2 Funcionalidades — MVP

| Funcionalidade | Descrição |
|---|---|
| Resumo | Total em aberto, total pago no ano, próxima parcela |
| Lista de parcelas | `Installment` agrupadas por `FinancialEstimate` / `Transaction` |
| Status visual | Em aberto, pago, em atraso (com dias de atraso) |
| Detalhe da parcela | Valor, vencimento, método previsto, descrição (procedimento/serviço) |
| Histórico de pagamentos | Lista de parcelas pagas com data |
| Download de recibo | PDF gerado por parcela paga |
| Renegociação | Botão "Falar sobre essa parcela" → cria conversa pré-preenchida com fila Financeiro |

### 9.3 Funcionalidades — Fase 2

**Pagamento online (gateway recomendado: Asaas):**
- **PIX:** QR code + copia/cola; webhook confirma `Installment.status = paid`.
- **Boleto:** gera, mostra linha digitável; webhook confirma quando pago.
- **Cartão:** checkout transparente, tokenização, captura imediata.
- **Pagamento parcial** (`partial_payment_allowed`): paciente escolhe quanto pagar.
- **Antecipação:** quitar várias parcelas com desconto (`early_payment_discount_percent`).

**Cobranças automáticas (opt-in por clínica):**
- **Pré-pagamento** por serviço (`require_prepayment` + `prepayment_percent`): soft-hold de slot por `prepayment_timeout_minutes`; webhook confirma → AgendaEvent vira `confirmed`.
- **Late cancel fee** (`late_cancel_fee` + `late_cancel_auto_invoice`): cancelamento fora da janela gera `Transaction` tipo `cancellation_fee`.
- **No-show fee** (`no_show_fee` + `no_show_auto_invoice`): no-show marcado pela recepção gera cobrança.
- **Reembolso automático** quando clínica cancela (`auto_refund_on_clinic_cancel`).

**Cobrança avulsa pela clínica (D.4 dos Fluxos):**
- Profissional gera `FinancialEstimate` na consulta e marca "Enviar ao portal".
- Paciente recebe notificação e abre tela com detalhamento + opções de pagamento.
- Opcional: `allow_counter_offer` (paciente sugere valor/parcelamento → solicitação).

**Pacote/assinatura de tratamento (D.5 dos Fluxos):**
- Visualização de `TreatmentPlan` com saldo de sessões (já cobre em \§8 — toggle `expose_treatment_plan`).
- Auto-débito recorrente vs parcela manual (configurável).
- Paciente solicita pausa ou cancelamento (gera tarefa para clínica).

**Bloqueio progressivo por inadimplência (D.7 dos Fluxos):**
- Setting `overdue_restriction_level`: `warn` / `limit_scheduling` / `limit_messaging_to_financial` / `full_block`.
- Setting `block_portal_if_overdue_days` (0 = nunca; ex: 30 dias = full_block após 30 dias de atraso).
- Auto-restaura após pagamento.

### 9.4 Funcionalidades — Fase 3

- **Reembolso de convênio:** pacote automático (recibo + relatório médico + TUSS + CID) — exige aprovação de quem pode incluir CID em relatório.

### 9.5 Regras de Negócio

- Paciente vê apenas suas próprias parcelas (`Installment.transaction.patient_id = current_patient.id`).
- Parcelas de transações com `transaction_type = expense` (despesa da clínica) nunca aparecem.
- Atraso é calculado em tempo real (`due_date < today AND status = pending`).
- Recibo só fica disponível após `status = paid` E `paid_at IS NOT NULL`.
- **Idempotência de webhook:** payments gateway deve passar pelo `Financial::IdempotencyKey` (modelo já existe no projeto).
- Soft-hold de slot expira em `prepayment_timeout_minutes` (default 15). Se webhook chega depois, `Transaction` fica criada e entra fluxo de estorno automático.

### 9.6 Decisões fechadas e em aberto

- **D-3 (recomendação):** Gateway = **Asaas** (cobertura PIX/boleto/cartão BR, taxas competitivas, API ok).
- **D-4 (aberta):** Repasse de taxa de cartão (`passes_fee_to_patient`) — default `false`; clínica liga se quiser.
- **F-3, F-4 (fechadas para MVP):** Cobrança automática de no-show e late cancel é **opt-in da clínica**, default `false` (delicado legalmente). Disponível na F2.

---

## 10. Módulo: Documentos <a id="10-modulo-documentos"></a>

### 10.1 Visão Geral

Repositório de PDFs emitidos pela clínica para o paciente: atestados, encaminhamentos, receitas, laudos, anamnese, plano de tratamento. Inclui **solicitação de 2ª via** (`DocumentRequest`) já no MVP.

### 10.2 Funcionalidades — MVP

| Funcionalidade | Descrição |
|---|---|
| Lista de documentos | `Document` filtrado por `patient_id` e `status = active`, agrupado por tipo |
| Filtros | Por tipo (`document_type`), por intervalo de data |
| Download | Link assinado com TTL `document_link_ttl_minutes` (default 15) para `ActiveStorage::Blob` |
| Compartilhamento | Botão "Enviar para WhatsApp/Email" gera link público de uso único com TTL configurável (`share_via_external_link`) |
| Preview inline | PDF aberto no navegador antes de baixar |
| **Solicitação 2ª via** | `DocumentRequest` — paciente pede 2ª via de recibo, atestado retroativo, etc. |

### 10.3 DocumentRequest (entidade MVP)

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
[Profissional ou recepção aprova/rejeita]
        │
        ▼
[Paciente notificado; documento aparece na lista]
```

**Settings:**
- `allow_document_request` (bool, default true)
- `requestable_document_types` (array, default `[atestado_2via, recibo_2via]`)
- `auto_approve_simple_requests` (default true — 2ª via de recibo é auto-aprovada)
- `document_request_sla_hours` (notifica clínica se não respondido em X horas)

**Edge cases:**
- Atestado retroativo: revisão obrigatória (risco legal).
- Receita de medicamento controlado: bloqueado (precisa nova consulta).

### 10.4 Funcionalidades — Fase 2

- **Validade/expiração** (`expires_at` em `Document`): badge "Expirado", download bloqueado para fins legais após expirar; histórico permanece visível.
- **Documentos com assinatura do paciente** vinculados a `AgendaEvent`: termos de procedimento que paciente precisa assinar antes da consulta. Bloqueio opcional de check-in se não assinado (`require_signed_consent_before_arrived`).

### 10.5 Funcionalidades — Fase 3

- **Upload pelo paciente** (`allow_self_upload`): foto de exame externo, receita de outro médico → `ExamMedia` com `uploaded_by_patient = true`, status `pending_review`.
- **Auto-OCR** para extração de dados.

### 10.6 Regras de Negócio

- Documentos com `is_generated = true` E `status = active` aparecem.
- Documentos com flag `internal = true` (uso interno) nunca aparecem.
- Documentos com `visible_in_portal = false` (override individual) ocultos mesmo se tipo está em `document_types_exposed`.
- Cada download gera registro em `PatientPortalAccessLog` com `resource_type = 'Document'`, `resource_id`.
- Links assinados expiram em `document_link_ttl_minutes` (default 15) e são single-use por padrão.

---

## 11. Módulo: Consentimentos (LGPD) <a id="11-modulo-consentimentos"></a>

### 11.1 Visão Geral

Reaproveita o `ConsentRecord` existente, que já tem suporte a assinatura remota via `remote_token`. O portal substitui o fluxo atual de enviar link de assinatura por WhatsApp.

### 11.2 Funcionalidades — MVP

| Funcionalidade | Descrição |
|---|---|
| Lista de consentimentos | Pendentes (topo) e assinados (histórico) |
| Aceite digital | Modal full-screen com texto, scroll obrigatório até o fim, assinatura via touch/mouse, captura de IP+UA |
| Re-assinatura | Quando clínica publica nova versão, dispara aceite obrigatório |
| Download | PDF do consentimento assinado com hash de integridade |
| Recusa | Paciente pode recusar consentimento opcional; obrigatórios bloqueiam uso do portal |
| **Revogação self-service** | Paciente revoga consentimento opcional; sistema notifica inbox "Compliance" da clínica |
| Auto-disparo por procedimento | Agendamento de procedimento que exige termo específico cria `ConsentRecord` pending vinculado ao evento |

### 11.3 Funcionalidades — Fase 2

- **Renovação periódica automática:** termo com `expires_at` (ex: termo de imagem vale 12 meses); job `scan_expiring_consents` notifica T-30 dias antes; após expirar, nova versão é cobrada na próxima ação que dependa.

### 11.4 Tipos de Consentimento Suportados

| Tipo | Origem | Obrigatório | TTL default |
|---|---|---|---|
| Termo de uso do portal | Klivy | Sim (1ª vez) | Imutável (re-assina se mudar) |
| Política de Privacidade (LGPD) | Klivy | Sim (1ª vez) | Imutável |
| Termo de tratamento de dados sensíveis | Cada clínica | Sim | 12 meses (F2) |
| Consentimento por procedimento | Cada clínica | Conforme procedimento | Por evento |
| Termo de imagem | Cada clínica | Opcional | 12 meses (F2) |
| Termo para menor (assinado por responsável) | Cada clínica | Quando aplicável | F3 |

### 11.5 Revogação (MVP)

```
[Paciente abre "Meus consentimentos" → "Revogar"]
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
[Notifica clínica via inbox "Compliance" (ou recepção se não houver)]
        │
        ▼
[Trilha de auditoria em PatientPortalAccessLog]
```

**Settings:**
- `compliance_inbox_id` (FK em inbox; fallback `recepção`)
- `revocable_consent_types` (array — quais termos podem ser revogados pelo paciente)
- **Termos não-revogáveis:** LGPD básica não pode ser revogada e continuar usando portal — revogar = solicitar exclusão (\§13).

### 11.6 Regras de Negócio

- Consentimento bloqueante (`mode = required`) sem assinatura impede navegação.
- Versão do consentimento é imutável após primeira assinatura por qualquer paciente.
- Hash de integridade (`integrity_hash`) já é calculado pelo modelo existente.
- Para menores (F3): o JWT precisa carregar `acting_as_responsible: true` E `responsible_for_patient_id`. Auditoria registra os dois sujeitos.
- Auto-disparo por procedimento: criação de `AgendaEvent` para procedimento com termo associado cria `ConsentRecord` status `pending` vinculado.

### 11.7 Edge Cases

- Paciente já assinou no consultório (papel): clínica marca `ConsentRecord` como `signed_offline` e portal não pede de novo.
- Paciente recusa LGPD obrigatório: portal oferece "Falar com a clínica" e bloqueia acesso ao conteúdo clínico.
- Sem assinatura de termo de procedimento: dia da consulta, profissional vê alerta vermelho no painel. Opt-in `require_signed_consent_before_arrived` bloqueia check-in.

---

## 12. Módulo: Comunicação com a Clínica <a id="12-modulo-comunicacao"></a>

### 12.1 Visão Geral

**Reaproveita o `Conversation` do Chatwoot**. A clínica já tem inbox(es) no painel; o portal cria/escreve em uma conversa associada ao `Contact` do paciente em um inbox específico do tipo `api` (Patient Portal Inbox), gerado automaticamente no primeiro uso.

Do lado da clínica, a mensagem do paciente aparece exatamente como qualquer outra conversa, com a tag "Portal do Paciente" e acessível em `/app/accounts/:id/conversations`.

### 12.2 Funcionalidades — MVP

| Funcionalidade | Descrição |
|---|---|
| Caixa de entrada | Lista de conversas do paciente naquela clínica |
| Nova mensagem (geral) | Botão para iniciar conversa (texto livre, sem destinatário específico) |
| Histórico | Threading completo da conversa |
| Notificação de não lidas | Contador na home e badge no menu |
| **Templates com roteamento** | Templates rápidos pré-formatados → cada um roteia para fila/inbox específico (ver \§12.3) |
| **Auto-resposta fora de horário** | Sistema responde imediatamente fora de `business_hours` |
| **Triagem urgente** | Keyword matching com ação configurável (default `force_phone`) |

### 12.3 Templates com Roteamento (MVP)

Tela "Nova mensagem" exibe barra de quick actions. Cada template é configurável pela clínica:

| Template padrão | Roteamento padrão |
|---|---|
| Pedir reagendamento | Inbox "Recepção" |
| Dúvida financeira / boleto | Inbox "Financeiro" |
| Pedir 2ª via de documento | Cria `DocumentRequest` (não conversa) |
| Cancelar consulta | Inbox "Recepção" |
| Outro / texto livre | Inbox geral do portal |

**Settings:**
- `message_templates` (jsonb, array de objetos `{key, label, body_template, target_inbox_id, target_team_id, variables}`)
- `default_inbox_id` (FK para inbox geral)

**Por que isso é bom:** triagem automática reduz trabalho da recepção 60-80% (referência: iClinic, Healthie).

### 12.4 Business Hours e Auto-resposta (MVP)

```
[Mensagem recebida fora do business_hours]
        │
        ▼
[Sistema responde imediatamente: "Recebemos! Atendimento seg-sex 8h-18h. Retornaremos amanhã."]
        │
        ▼
[Se contém keyword urgente: adiciona "Em emergência, ligue 192"]
        │
        ▼
[Conversa marcada para topo da fila na próxima abertura]
```

**Settings:**
- `business_hours` (jsonb por dia da semana)
- `out_of_hours_template` (texto)
- `holidays` (array de datas)
- `auto_reply_no_agent_available_template`

### 12.5 Triagem Urgente (MVP)

```
[Detector roda em onMessage]
        │
        ▼
[Match em keyword_urgent_list (ex: "dor forte", "sangue", "emergência")]
        │
        ▼
[Aplica urgent_action]
   ├── force_phone (DEFAULT MVP): responde "Por favor, ligue agora para (11) X. Em emergência, 192."
   ├── dedicated_inbox: roteia para inbox "Urgências"
   ├── escalate: cria conversa + notificação push para profissional de plantão
   └── always: marca conversa com SLA reduzido + flag visual
```

**Settings:**
- `urgent_keyword_list` (array de strings, editável; default lista PT-BR sensível)
- `urgent_action` (`force_phone` / `dedicated_inbox` / `escalate`, default `force_phone`)
- `urgent_inbox_id` (quando `dedicated_inbox`)
- `urgent_escalate_user_ids` (array, quando `escalate`)
- Lista pode variar por especialidade (Fase 2 — override por profissional/serviço).

> **Por que importa:** sem isso, um caso real de emergência pode ficar parado na fila como mensagem normal — risco médico e legal.

### 12.6 Funcionalidades — Fase 2

- **Mensagem dirigida a profissional específico** (`allow_direct_professional`): paciente escolhe destinatário; cria `Conversation.assignee_id`.
- Opt-in por profissional individual em `ProfessionalPortalSetting.accepts_direct_messages`.
- Anexar arquivos (imagem, PDF) com limite de 10 MB.
- Indicador de "lida" da clínica (`Message.status`).
- Limite de mensagens por paciente por dia (anti-spam).

### 12.7 Regras de Negócio

- Inbox dedicado por account: `Patient Portal — :clinic_name`, tipo `api`, **auto-criado no primeiro uso** do portal pela clínica.
- Mensagens do paciente entram com `message_type = incoming`.
- Atribuição de agente segue regra padrão do Chatwoot (round-robin, etc.) **ou** roteamento do template (`target_inbox_id`).
- Conversas ficam **fora** das métricas SLA da clínica por padrão (opt-in via setting `count_in_sla_metrics`).
- Paciente nunca vê mensagens com `private = true` (notas internas entre agentes).

### 12.8 Edge Cases

- Clínica sem nenhum agente disponível: paciente vê auto-reply "Recebemos sua mensagem, retornaremos em até X horas".
- Conversa muito antiga sem resposta da clínica: portal exibe alerta para o paciente reabrir.
- Keyword urgente em template já roteado (ex: "Pedir reagendamento" + "dor forte"): triagem urgente prevalece sobre roteamento por template.

---

## 13. Módulo: Perfil e Dependentes <a id="13-modulo-perfil"></a>

### 13.1 Funcionalidades — MVP (Perfil)

| Funcionalidade | Descrição |
|---|---|
| Visualizar dados | Nome, CPF, telefone, e-mail, data de nascimento, endereço |
| Atualizar limitado | Telefone secundário, e-mail secundário, endereço, foto |
| Solicitar correção | Para CPF/data de nasc — abre conversa com a clínica (não auto-edita) |
| Exportar dados (LGPD) | Botão "Baixar meus dados" gera JSON + PDF com tudo que a clínica tem |
| Solicitar exclusão (LGPD) | Botão envia solicitação formal — clínica processa em até 15 dias |

### 13.2 Funcionalidades — Fase 3 (Dependentes)

| Funcionalidade | Descrição |
|---|---|
| Vincular dependente | Responsável solicita vínculo informando CPF do dependente, parentesco, anexa documento (RG/certidão) → `PatientResponsibleLink` status `pending`; clínica aprova |
| Alternar contexto | Após login, escolhe se navega como ele mesmo ou como o dependente |
| Assinar pelo menor | Consentimentos do dependente exigem JWT com `acting_as_responsible` |
| Auditoria dupla | Toda ação no contexto do dependente registra responsável + dependente |

### 13.3 Regras de Negócio

- Edição de campos sensíveis (CPF, nome legal, data nasc) **nunca** é direta — sempre via solicitação.
- Endereço é livre para edição porque já tem precedente no formulário público de booking.
- Exclusão de dados não é apagamento real — é anonimização (`PatientAnonymizationService` — modelo `Financial::LgpdRequest` já existe, ampliar). Anonimização:
  - `Patient.name` → "Paciente removido"
  - CPF mantido cifrado (compliance financeira)
  - `Contact` apagado
  - Conversas apagadas
  - Portal access revogado
  - Documentos clínicos preservados (CFM exige 20 anos para prontuário)
- Vínculo de dependente exige documento legal (`PatientResponsibleLink.legal_doc_attachment`) — clínica revisa antes de aprovar.

---

## 13bis. Módulo: Engajamento <a id="13bis-engajamento"></a>

### 13bis.1 Recall Automático (MVP)

Reaproveita `Patient.needs_recall` (campo a adicionar — atualmente não existe na coluna do `Patient`).

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
[Notifica paciente via canal preferido]: "Faz 6 meses — vamos agendar uma consulta?"
        │
        ▼
[CTA direto: abre fluxo de agendamento]
```

**Settings:**
- `recall_enabled` (bool, default true)
- `recall_after_months` por serviço (default 6 odonto/estética, 12 médico)
- `recall_channel` (`portal_push` / `whatsapp` / `email` — default `whatsapp`)
- `recall_template` (texto com variáveis)
- `recall_max_per_year` (default 2 — não encher o paciente)
- Excluir pacientes com `status=alta` ou `arquivado`.

### 13bis.2 NPS Pós-consulta (Fase 2)

```
[AgendaEvent.status = completed] ──► [+ nps_delay_hours: dispara]
        │
        ▼
[Pergunta única: "De 0 a 10, recomenda a clínica?"]
        │
        ▼
[Resposta]:
   ├── 0-6 (detrator): "Sentimos muito. Quer contar mais?" → conversa para gerente/admin
   ├── 7-8 (passivo): "Obrigado!"
   └── 9-10 (promotor): "Que ótimo!" (F3: link de indicação)
```

**Settings (F2):**
- `nps_enabled` (default false)
- `nps_delay_hours` (default 24)
- `nps_frequency_max_per_quarter` (default 1 — não perguntar a cada consulta)
- `nps_detractor_escalation_user_ids`
- `nps_public_review` (default false — interno)

### 13bis.3 Indicação / Referral (Fase 3)

```
[Promotor NPS recebe link de indicação OU paciente abre "Indicar amigos"]
        │
        ▼
[Gera link único com referral_code]
        │
        ▼
[Amigo abre, agenda primeira consulta (via booking público)]
        │
        ▼
[ReferralRecord criado com indicador_patient_id + amigo_contact_id]
        │
        ▼
[Após primeira consulta paga: indicador ganha recompensa]
```

**Settings (F3):**
- `referral_program_enabled`
- `referral_reward_type` (`discount` / `cash` / `free_session`)
- `referral_reward_amount`
- `referral_requires_paid_appointment` (default true)
- `referral_max_per_patient` (default 10)
- `referral_auto_approve` vs aprovação manual

---

## 13ter. Módulo: Notificações <a id="13ter-notificacoes"></a>

### 13ter.1 Matriz de Canais (MVP)

| Evento | Default canal | Alternativas | Desligável? |
|---|---|---|---|
| Login OTP | WhatsApp | Email | **Nunca** (segurança) |
| Convite inicial | WhatsApp | Email | Não (1ª vez) |
| Confirmação de agendamento | WhatsApp | Push portal, Email | Sim |
| Lembrete T-24h | WhatsApp | Email | Condicional (clínica força se alto no-show) |
| Mensagem da clínica respondida | Push portal | WhatsApp | Sim |
| Cobrança nova | Email + Push | WhatsApp | Sim |
| Documento novo | Push portal | WhatsApp, Email | Sim |
| Consentimento expirando (F2) | Email | WhatsApp, Push | **Nunca** (regulatório) |
| NPS (F2) | WhatsApp | Email | Sim |
| Recall | WhatsApp | Push, Email | Sim |

### 13ter.2 Preferências do Paciente (MVP)

Tabela em "Configurações → Notificações": evento × canal × on/off.

**Modelo `PatientNotificationPreference`:**

| Campo | Tipo |
|---|---|
| `patient_id` | bigint |
| `account_id` | bigint |
| `event_type` | enum (`appointment_reminder`, `new_document`, ...) |
| `channel` | enum (`whatsapp`, `email`, `portal_push`) |
| `enabled` | boolean |

**Settings da clínica:**
- `notification_events_enabled` (matriz de eventos × habilitado pela clínica — paciente só configura o que clínica habilitou)
- `notification_max_per_day_per_patient` (default 5 — anti-spam)
- `notification_templates` (override por evento)

### 13ter.3 Limites

- Notificações de **segurança** (login OTP, suspensão) NUNCA desligáveis.
- Notificações **regulatórias** (consentimento expirando, exclusão LGPD processada) NUNCA desligáveis.
- Lembrete T-24h: opt-out apenas se clínica permitir (`allow_reminder_optout`).

---

## 14. Arquitetura Técnica <a id="14-arquitetura"></a>

### 14.1 Topologia

```
┌──────────────────────────────────┐
│  sistema.klivy.app               │  → SPA dono da clínica (atual)
└──────────────────────────────────┘
                  │
                  ▼
┌──────────────────────────────────┐
│  Rails (Klivy / Chatwoot)        │
│  ├─ /api/v1/**                   │  → admin (atual)
│  ├─ /api/v1/patient_portal/**    │  → NOVO namespace
│  └─ /super_admin/**              │  → admin Klivy (atual)
└──────────────────────────────────┘
                  ▲
                  │
┌──────────────────────────────────┐
│  pacientes.klivy.app             │  → NOVO SPA (Vue 3 + Tailwind)
└──────────────────────────────────┘
```

- **Mesmo container Rails, mesmo banco, mesmo Sidekiq, mesmo deploy.**
- O SPA do paciente pode rodar no mesmo Rails (entry separado no Webpacker/Vite) ou como app frontend independente em `patient-portal/` que faz build estático servido por Caddy/Nginx.
- Recomendação: **SPA no mesmo repo, entry separado**, evita duplicar pipeline de build.

### 14.2 Estrutura de Pastas (Plugin)

Seguindo a regra arquitetural do Klivy ("nenhuma funcionalidade ou arquivo core do Chatwoot é alterado fisicamente"), o portal vive como plugin novo `plugins/patient_portal/` no mesmo padrão dos plugins existentes (`agenda`, `patients`, `financial`, `beclinic_core`):

```
plugins/patient_portal/
  app/
    controllers/
      api/v1/patient_portal/
        base_controller.rb
        auth_controller.rb
        appointments_controller.rb
        appointment_requests_controller.rb
        installments_controller.rb
        documents_controller.rb
        document_requests_controller.rb
        consents_controller.rb
        conversations_controller.rb
        profile_controller.rb
        notification_preferences_controller.rb
        home_controller.rb
        evolution_controller.rb
    models/
      portal_invite.rb
      patient_portal_otp.rb
      patient_portal_session.rb
      patient_portal_consent.rb
      patient_portal_access_log.rb
      patient_portal_setting.rb
      professional_portal_setting.rb
      appointment_request.rb
      document_request.rb
      patient_notification_preference.rb
      # F3:
      patient_responsible_link.rb
      referral_record.rb
    services/
      patient_portal/
        otp_dispatcher.rb
        authenticator.rb
        config_resolver.rb              # hierarquia Account → Prof → Serviço → Procedimento → Tag
        pre_flight_checker.rb
        document_signed_url_generator.rb
        urgent_message_detector.rb
        recall_scanner.rb
        installment_payment_gateway.rb  # Fase 2
        nps_dispatcher.rb               # Fase 2
    policies/
      patient_portal/
        appointment_policy.rb
        installment_policy.rb
        document_policy.rb
        ...
    serializers/
      patient_portal/
        ...
    jobs/
      patient_portal/
        scan_needs_recall_job.rb
        scan_expiring_consents_job.rb   # F2
        process_appointment_request_job.rb
        send_invite_job.rb
  frontend/
    javascript/
      patient_portal/                    # SPA Vue 3 separado
        entry.js
        App.vue
        router/
        store/
        components/
        pages/
  db/
    migrate/
      ...
  config/
    routes.rb                            # mounted from plugins/patient_portal/engine.rb
```

> **Aderência ao padrão Klivy:** o plugin segue a mesma convenção dos engines existentes — todas as tabelas com prefixo do domínio (`portal_*`, `patient_portal_*`), modelos próprios, namespace de controllers. **Não toca em nenhum arquivo do core Chatwoot.**

### 14.3 Backend — Camadas

| Camada | Responsabilidade |
|---|---|
| `Api::V1::PatientPortal::BaseController` | Autenticação JWT, escopo de `current_patient`, `current_account`, rate limit |
| Controllers REST | Magros — só orquestram serializers e services |
| Services | Lógica de negócio (envio de OTP, geração de link assinado, pagamento) |
| Models | Apenas leitura nos modelos clínicos/financeiros existentes; escrita só em novas tabelas `patient_portal_*` |
| Pundit Policies | Toda query passa por policy: `PatientPortal::AppointmentPolicy`, etc. Garante isolamento por `patient_id` e `account_id` |

### 14.4 Frontend — Stack

- Vue 3 + Composition API (mesmo da Klivy).
- Tailwind com os mesmos tokens (`n-slate-*`, `woot-*`).
- Vue Router em modo history.
- Pinia para estado (mais leve que Vuex; pode ser Vuex se preferir uniformidade com o app principal).
- Axios com interceptor que injeta JWT e renova ao receber 401.

### 14.5 Reaproveitamento do Core

| Item | Reaproveita | Como |
|---|---|---|
| Identidade do paciente | `Contact` (Chatwoot) | Busca por phone/email; resolve `Patient` via `Patient.contact_id` |
| Mensageria | `Conversation` + `Message` + inbox tipo `api` | Cria inbox dedicado por account; toda mensagem usa o pipeline normal |
| Documentos | `Document` + Active Storage | Signed URL com TTL via `ActiveStorage::Blob.signed_id` |
| Consentimentos | `ConsentRecord.remote_token` | Já tem fluxo de assinatura remota; só substitui canal de entrega |
| Agenda | `AgendaEvent` | Read-only no MVP; reaproveita callbacks de status |
| Lista de espera | `WaitingListEntry` (existe em `plugins/agenda`) | Expõe no portal; top-da-fila notificado em vagas (F2) |
| Financeiro | `Installment` / `Transaction` / `FinancialEstimate` | Read-only no MVP; Fase 2 chama gateway e atualiza status |
| Idempotência de pagamento | `Financial::IdempotencyKey` (existe) | Garante webhook idempotente |
| Mailers | ActionMailer existente | Reaproveita layout |
| Auditoria | `PatientAuditLog` existente + novo `PatientPortalAccessLog` | Novos tipos: `portal_login`, `portal_view`, `portal_download`, `portal_sign`, `portal_message`, `portal_suspension_change` |
| Anonimização LGPD | `Financial::LgpdRequest` (existe) | Ampliar para cobrir solicitação via portal |
| Formulários | `FormTemplate` (existe) | Anamnese pré-consulta no MVP |

### 14.6 Hierarquia de Configuração

Conforme princípio de produto §1.1 (item 2: "Configurável por camada"), toda regra do portal segue a hierarquia abaixo. **Regra mais específica vence**.

```
Account default                  ← PatientPortalSetting (uma linha por account)
    │
    ▼
Profissional override            ← ProfessionalPortalSetting (uma linha por user_id × account_id)
    │
    ▼
Serviço override                 ← AgendaServiceSetting (estende serviço; já parcialmente existe)
    │
    ▼
Procedimento override            ← campos jsonb em AgendaService.procedures (F2)
    │
    ▼
Tag do paciente override         ← PatientTagSetting (F2 — Concierge)
```

**Serviço resolver:**

```ruby
# Pseudocódigo de PatientPortal::ConfigResolver
def resolve(setting_key, patient:, professional: nil, service: nil, procedure: nil)
  # Tag do paciente (F2)
  tag_value = patient.portal_tags.flat_map(&:settings).find { ... }
  return tag_value if tag_value.present?

  # Procedimento (F2)
  return procedure.portal_overrides[setting_key] if procedure&.portal_overrides&.key?(setting_key)

  # Serviço
  return service.portal_setting[setting_key] if service&.portal_setting&.key?(setting_key)

  # Profissional
  prof_setting = ProfessionalPortalSetting.find_by(user: professional, account: account)
  return prof_setting[setting_key] if prof_setting&.[](setting_key).present?

  # Account default
  account.patient_portal_setting[setting_key]
end
```

UI: "Configurações > Portal > Regras". Tabela editável com colunas: escopo, modo, lead time, pré-pagamento, anamnese obrigatória. Botão "Simular" para testar como o paciente verá (importante para evitar surpresas — F2).

### 14.7 Catálogo de Settings (resumo)

Para evitar duplicação, o **catálogo completo de ~80 controles** está no companion [`patient-portal-fluxos.md`](./patient-portal-fluxos.md#2-controles) seção 2. Os settings são agrupados em 7 categorias persistidas em `PatientPortalSetting` (jsonb por categoria):

| Categoria | Exemplos chave | Onde nos Fluxos |
|---|---|---|
| Agendamento | `scheduling_mode`, `first_visit_mode`, `min_lead_time_hours`, `block_if_pending_consent`, `require_anamnesis_before` | \§2.1 |
| Reagendamento/Cancelamento | `reschedule_mode`, `reschedule_window_hours`, `cancel_window_hours`, `late_cancel_fee` (F2) | \§2.2 |
| Financeiro | `payment_methods`, `installment_max`, `block_portal_if_overdue_days`, `auto_charge_no_show` | \§2.3 |
| Documentos | `document_types_exposed`, `allow_document_request`, `requestable_document_types`, `document_link_ttl_minutes` | \§2.4 |
| Histórico Clínico | `clinical_visibility`, `expose_clinical_note_fields`, `expose_treatment_plan`, `prescription_visibility` | \§2.5 |
| Comunicação | `messaging_enabled`, `allow_direct_professional`, `business_hours`, `urgent_action` | \§2.6 |
| Engajamento | `recall_enabled`, `recall_after_months`, `nps_after_appointment`, `referral_program_enabled` | \§2.7 |

### 14.8 Presets (UI de ativação)

Ao ativar o portal, a clínica escolhe um preset (\§4.5) que pré-carrega valores nas 7 categorias. Implementação:

- `PatientPortalSetting` tem coluna `active_preset` (`autonomy_guided` / `reception_digital` / `self_service` / `concierge` / `custom`).
- Service `PatientPortal::PresetApplier` carrega o conjunto de defaults do preset e mescla com customizações já feitas pela clínica.
- MVP exibe apenas "Autonomia Guiada". F2 expõe os outros 3.

### 14.9 Multi-tenancy

- JWT carrega `account_id` definido no momento do login (após escolha de clínica, se houver).
- Toda query no backend usa `current_account.contacts` / `current_account.patients` — nunca `Patient.all`.
- Trocar de clínica = relogar com nova seleção (não há "switcher" em runtime no MVP; Fase 2 traz switcher inline no header).

---

## 15. Endpoints API <a id="15-endpoints"></a>

### 15.1 Autenticação

| Método | Path | Descrição |
|---|---|---|
| POST | `/api/v1/patient_portal/auth/request_otp` | `{ identifier: phone or email, channel: "whatsapp"\|"email" }` → envia OTP |
| POST | `/api/v1/patient_portal/auth/verify_otp` | `{ identifier, otp }` → retorna lista de accounts e token temporário |
| POST | `/api/v1/patient_portal/auth/select_account` | `{ account_id, temp_token }` → emite JWT definitivo |
| POST | `/api/v1/patient_portal/auth/logout` | Invalida JWT |
| GET  | `/api/v1/patient_portal/auth/me` | Sessão atual + dados básicos do paciente |

### 15.2 Recursos

| Método | Path | Descrição |
|---|---|---|
**Home:**
| Método | Path | Fase |
|---|---|---|
| GET  | `/api/v1/patient_portal/home` | MVP |

**Agendamentos:**
| Método | Path | Fase |
|---|---|---|
| GET  | `/api/v1/patient_portal/appointments?status=&from=&to=` | MVP |
| GET  | `/api/v1/patient_portal/appointments/:id` | MVP |
| POST | `/api/v1/patient_portal/appointments/:id/confirm` | MVP |
| POST | `/api/v1/patient_portal/appointments/:id/cancel` | MVP (dentro da janela) |
| POST | `/api/v1/patient_portal/appointment_requests` | MVP — cria solicitação (`new_appointment`/`reschedule`/`cancellation`) |
| GET  | `/api/v1/patient_portal/appointment_requests` | MVP |
| GET  | `/api/v1/patient_portal/appointment_requests/:id` | MVP |
| GET  | `/api/v1/patient_portal/scheduling/preflight` | MVP — devolve `{ blocked: false, reasons: [] }` antes do paciente abrir o form |
| GET  | `/api/v1/patient_portal/scheduling/slots?service_id=&user_id=&from=&to=` | F2 — `slot_picker`/`direct_booking` |
| POST | `/api/v1/patient_portal/appointments` | F2 — booking direto |
| GET  | `/api/v1/patient_portal/waiting_list` | F2 |
| POST | `/api/v1/patient_portal/waiting_list` | F2 |
| DELETE | `/api/v1/patient_portal/waiting_list/:id` | F2 |
| POST | `/api/v1/patient_portal/appointments/:id/checkin` | F3 |

**Financeiro:**
| Método | Path | Fase |
|---|---|---|
| GET  | `/api/v1/patient_portal/financial/summary` | MVP |
| GET  | `/api/v1/patient_portal/financial/installments?status=` | MVP |
| GET  | `/api/v1/patient_portal/financial/installments/:id` | MVP |
| GET  | `/api/v1/patient_portal/financial/installments/:id/receipt` | MVP — URL assinada do PDF |
| POST | `/api/v1/patient_portal/financial/installments/:id/pay` | F2 — inicia pagamento |
| POST | `/api/v1/patient_portal/financial/installments/bulk_pay` | F2 — antecipação |
| POST | `/api/v1/patient_portal/financial/payment_webhook` | F2 — gateway → Klivy (com idempotência) |
| POST | `/api/v1/patient_portal/financial/installments/:id/refund_request` | F2 |
| GET  | `/api/v1/patient_portal/financial/treatment_plans/:id` | MVP — saldo do pacote |
| GET  | `/api/v1/patient_portal/financial/insurance_package/:installment_id` | F3 — recibo+relatório+TUSS+CID |

**Documentos:**
| Método | Path | Fase |
|---|---|---|
| GET  | `/api/v1/patient_portal/documents?type=` | MVP |
| GET  | `/api/v1/patient_portal/documents/:id/download` | MVP — redireciona signed URL |
| POST | `/api/v1/patient_portal/documents/:id/share_link` | MVP — gera link público de uso único |
| POST | `/api/v1/patient_portal/document_requests` | MVP — solicitação de 2ª via |
| GET  | `/api/v1/patient_portal/document_requests` | MVP |
| POST | `/api/v1/patient_portal/documents/upload` | F3 — `ExamMedia` com `uploaded_by_patient` |

**Consentimentos:**
| Método | Path | Fase |
|---|---|---|
| GET  | `/api/v1/patient_portal/consents?status=pending` | MVP |
| GET  | `/api/v1/patient_portal/consents/:id` | MVP |
| POST | `/api/v1/patient_portal/consents/:id/sign` | MVP |
| POST | `/api/v1/patient_portal/consents/:id/revoke` | MVP |

**Conversas / Mensagens:**
| Método | Path | Fase |
|---|---|---|
| GET  | `/api/v1/patient_portal/conversations` | MVP |
| POST | `/api/v1/patient_portal/conversations` | MVP — payload `{ template_key?, target_inbox_id?, body }` |
| GET  | `/api/v1/patient_portal/conversations/:id/messages` | MVP |
| POST | `/api/v1/patient_portal/conversations/:id/messages` | MVP |
| GET  | `/api/v1/patient_portal/message_templates` | MVP — templates configurados pela clínica |
| POST | `/api/v1/patient_portal/conversations/:id/messages/upload` | F2 — anexo (≤10MB) |

**Evolução / Histórico Clínico:**
| Método | Path | Fase |
|---|---|---|
| GET  | `/api/v1/patient_portal/evolution` | MVP — timeline (respeita `clinical_visibility`) |
| GET  | `/api/v1/patient_portal/evolution/clinical_notes/:id` | MVP |
| GET  | `/api/v1/patient_portal/evolution/clinical_notes/:id/pdf` | F2 — `download_pdf` |
| GET  | `/api/v1/patient_portal/evolution/treatment_plans` | MVP |
| GET  | `/api/v1/patient_portal/evolution/prescriptions` | MVP |
| GET  | `/api/v1/patient_portal/evolution/exams` | F3 |

**Anamnese:**
| Método | Path | Fase |
|---|---|---|
| GET  | `/api/v1/patient_portal/anamnesis/template` | MVP |
| GET  | `/api/v1/patient_portal/anamnesis` | MVP — retorna draft atual |
| PATCH | `/api/v1/patient_portal/anamnesis` | MVP — save draft |
| POST | `/api/v1/patient_portal/anamnesis/submit` | MVP — finaliza (ou submit ao agendar) |

**Perfil e LGPD:**
| Método | Path | Fase |
|---|---|---|
| GET  | `/api/v1/patient_portal/profile` | MVP |
| PATCH | `/api/v1/patient_portal/profile` | MVP |
| POST | `/api/v1/patient_portal/profile/export` | MVP |
| POST | `/api/v1/patient_portal/profile/deletion_request` | MVP |
| GET  | `/api/v1/patient_portal/profile/dependents` | F3 |
| POST | `/api/v1/patient_portal/profile/dependents` | F3 |

**Notificações:**
| Método | Path | Fase |
|---|---|---|
| GET  | `/api/v1/patient_portal/notifications/preferences` | MVP |
| PATCH | `/api/v1/patient_portal/notifications/preferences` | MVP |

**Engajamento:**
| Método | Path | Fase |
|---|---|---|
| POST | `/api/v1/patient_portal/recall/dismiss` | MVP — paciente fecha banner do recall |
| POST | `/api/v1/patient_portal/nps` | F2 — `{ score, comment }` |
| POST | `/api/v1/patient_portal/referrals` | F3 — gera código |
| GET  | `/api/v1/patient_portal/referrals` | F3 — histórico de indicações |

### 15.3 Endpoints administrativos (clínica)

Estes endpoints **não** ficam no namespace `/patient_portal/` e sim no namespace admin existente. Listados aqui pra completude:

| Método | Path | Fase |
|---|---|---|
| POST | `/api/v1/accounts/:id/portal_invites` | MVP — convidar paciente |
| POST | `/api/v1/accounts/:id/patients/:patient_id/portal_suspension` | MVP — suspender/restringir |
| GET  | `/api/v1/accounts/:id/appointment_requests?status=` | MVP — fila para recepção |
| POST | `/api/v1/accounts/:id/appointment_requests/:id/confirm` | MVP |
| POST | `/api/v1/accounts/:id/appointment_requests/:id/propose` | MVP |
| POST | `/api/v1/accounts/:id/appointment_requests/:id/reject` | MVP |
| GET  | `/api/v1/accounts/:id/document_requests` | MVP |
| POST | `/api/v1/accounts/:id/document_requests/:id/approve` | MVP |
| GET/PATCH | `/api/v1/accounts/:id/patient_portal_setting` | MVP |
| POST | `/api/v1/accounts/:id/patient_portal_setting/apply_preset` | MVP — aplica `autonomy_guided` no MVP, demais na F2 |

### 15.4 Convenções

- Todas as respostas no padrão `{ data, meta, errors }`.
- Paginação por cursor (`?after=`, `?limit=20`).
- Rate limit: 60 req/min por JWT, 5 req/min em endpoints de auth, **20 req/min** em endpoints de criação (`POST /appointment_requests`, `POST /document_requests`, `POST /conversations`) para evitar spam.
- Idempotency-Key header obrigatório em endpoints de pagamento (F2) e criação de solicitações duplicáveis.

---

## 16. Modelo de Dados <a id="16-modelo-de-dados"></a>

### 16.1 Novas tabelas — MVP

| Entidade | Campos principais | Notas |
|---|---|---|
| `PortalInvite` | `account_id`, `patient_id`, `channel` (whatsapp/email), `token`, `expires_at`, `sent_at`, `accepted_at`, `invited_by_user_id` (nullable se auto) | `auto_invite_on_create` cria automaticamente |
| `PatientPortalOtp` | `identifier` (phone/email normalizado), `code_digest`, `expires_at`, `used_at`, `attempts`, `ip` | TTL 10 min, máx 3 tentativas |
| `PatientPortalSession` | `patient_id`, `account_id`, `jwt_jti`, `expires_at`, `last_seen_at`, `ip`, `user_agent`, `device_fingerprint` (nullable, "lembrar dispositivo") | TTL 7 dias (30 dias se lembrar) |
| `PatientPortalConsent` | `patient_id`, `term_type` (`portal_terms`/`lgpd`), `term_version`, `accepted_at`, `ip`, `user_agent`, `signature_blob_id` | Termo Klivy (não confundir com `ConsentRecord` por procedimento) |
| `PatientPortalAccessLog` | `patient_id`, `account_id`, `action` (`login`/`view`/`download`/`sign`/`revoke`/`message`/`suspension_change`/`...`), `resource_type`, `resource_id`, `ip`, `user_agent`, `at`, `metadata` (jsonb) | LGPD obrigatório |
| `PatientPortalSetting` | `account_id` (UNIQUE), `active_preset` enum, `scheduling` jsonb, `rescheduling` jsonb, `financial` jsonb, `documents` jsonb, `clinical` jsonb, `messaging` jsonb, `engagement` jsonb, `invite` jsonb, `business_hours` jsonb, `notification_events_enabled` jsonb | Catálogo completo em [Fluxos §2](./patient-portal-fluxos.md#2-controles); cada chave é um campo dentro do jsonb da categoria |
| `ProfessionalPortalSetting` | `account_id`, `user_id` (UNIQUE com account_id), `overrides` jsonb (chaves dos settings sobrescritas) | Hierarquia de config — \§14.6 |
| `AgendaServiceSetting` | `agenda_service_id` (UNIQUE), `overrides` jsonb | Estende `AgendaService` (verificar se já existe parcialmente) |
| `AppointmentRequest` | `account_id`, `patient_id`, `agenda_service_id` (nullable), `professional_user_id` (nullable), `preferred_slots` jsonb, `purpose` enum, `original_event_id` (nullable), `notes`, `status` enum, `is_first_visit`, `resolved_at`, `resolved_by_user_id`, `resolved_agenda_event_id` | Fila no painel |
| `DocumentRequest` | `account_id`, `patient_id`, `document_type`, `reference_agenda_event_id` (nullable), `reason`, `status` enum, `resolved_at`, `resolved_by_user_id`, `created_document_id` | Solicitação 2ª via, atestado retroativo |
| `PatientNotificationPreference` | `patient_id`, `account_id`, `event_type` enum, `channel` enum, `enabled` boolean | Matriz de preferências |
| `MessageTemplate` (ou jsonb em setting) | `key`, `label`, `body_template`, `target_inbox_id` (nullable), `target_team_id` (nullable), `variables` array, `active` | Templates rápidos do MVP |

### 16.2 Novas tabelas — Fase 2

| Entidade | Campos principais |
|---|---|
| `Payment` | `account_id`, `installment_id`, `gateway`, `gateway_charge_id`, `method`, `amount`, `status`, `paid_at`, `refunded_at`, `idempotency_key` |
| `PaymentWebhookEvent` | `gateway`, `payload` jsonb, `received_at`, `processed_at`, `idempotency_key` |
| `RefundRequest` | `account_id`, `payment_id`, `reason`, `requested_by_patient`, `amount`, `status`, `resolved_at` |
| `NpsResponse` | `patient_id`, `account_id`, `agenda_event_id`, `score` (0-10), `comment`, `created_at` |
| `WaitingListEntry` | **(já existe em `plugins/agenda`)** — adicionar coluna `portal_visible` boolean e `portal_response_token` |

### 16.3 Novas tabelas — Fase 3

| Entidade | Campos principais |
|---|---|
| `PatientResponsibleLink` | `responsible_patient_id`, `dependent_patient_id`, `relationship_type`, `legal_doc_attachment_id`, `requested_at`, `approved_at`, `approved_by_user_id`, `account_id`, `status` |
| `ReferralRecord` | `account_id`, `referrer_patient_id`, `referral_code` (unique), `referred_contact_id` (nullable até converter), `referred_at`, `converted_at`, `reward_status`, `reward_amount` |
| `ExamMedia` upload paciente | Adicionar colunas `uploaded_by_patient` boolean, `review_status`, `reviewed_by_user_id`, `reviewed_at` em `ExamMedia` existente |
| `CheckinEvent` | `agenda_event_id`, `patient_id`, `method` (`self`/`reception`), `geofence_lat`/`lng` (nullable), `qr_token` (nullable), `at` |

### 16.4 Colunas adicionadas em modelos existentes

| Tabela | Coluna | Tipo | Default | Fase | Propósito |
|---|---|---|---|---|---|
| `patients` | `portal_status` | enum | `active` | MVP | `active`/`suspended_temporary`/`suspended_permanent`/`restricted` |
| `patients` | `portal_suspended_until` | datetime | null | MVP | Janela de suspensão temporária |
| `patients` | `portal_suspension_reason` | text | null | MVP | Auditoria |
| `patients` | `needs_recall` | boolean | false | MVP | Recall scanner liga |
| `patients` | `last_recall_at` | datetime | null | MVP | Anti-spam de recall |
| `patients` | `chronic_no_show` | boolean | false | F2 | Restrição automática |
| `patients` | `no_show_count_90d` | integer | 0 | F2 | Métrica derivada |
| `documents` | `internal` | boolean | false | MVP | Esconder do paciente |
| `documents` | `visible_in_portal` | boolean | null | MVP | Override individual (null = segue setting) |
| `documents` | `expires_at` | datetime | null | F2 | Validade |
| `clinical_notes` | `private` | boolean | true | MVP | Default fechado |
| `clinical_notes` | `patient_visible_note` | text | null | MVP | Resumo "para o paciente" (nível `summary`) |
| `clinical_notes` | `signed_at` | datetime | null | (já existe?) | Só notas assinadas são expostas |
| `agenda_events` | `notes_internal` | text | null | MVP | Separar notas internas das públicas |
| `agenda_events` | `prepayment_status` | enum | null | F2 | `pending`/`paid`/`expired` |
| `agenda_events` | `confirmation_required_by` | datetime | null | MVP | Auto-cancel se não confirmar |
| `consent_records` | `expires_at` | datetime | null | F2 | Renovação periódica |
| `consent_records` | `revoked_at` | datetime | null | MVP | Revogação self-service |
| `consent_records` | `revocation_reason` | text | null | MVP | Auditoria |
| `agenda_services` | `portal_setting` | jsonb | `{}` | MVP | Override por serviço |

### 16.5 Inboxes auto-criados

Ao primeiro uso do portal pela clínica, sistema cria automaticamente:

| Inbox | Tipo | Quando |
|---|---|---|
| "Patient Portal — :clinic_name" | `api` | MVP — recebe todas as mensagens iniciadas no portal sem template |
| "Compliance" | `api` ou inbox existente da clínica | MVP — recebe notificações de revogação de consentimento (fallback: inbox padrão) |
| "Urgências" | `api` | MVP — quando `urgent_action=dedicated_inbox` |
| "Recepção" / "Financeiro" / "Documentos" | (já existem ou criar via setup) | MVP — destinos dos templates de roteamento |

---

## 17. Segurança, Privacidade e LGPD <a id="17-seguranca-lgpd"></a>

### 17.1 Princípios

- **Default-deny:** nada do prontuário aparece sem opt-in explícito da clínica em `PatientPortalSetting`.
- **Least privilege:** JWT carrega só o necessário; toda query escopa por `current_patient` e `current_account`.
- **Auditoria total:** cada acesso a dado sensível grava em `PatientPortalAccessLog`.
- **Sem cadastro espontâneo:** paciente só entra se já existe no sistema.

### 17.2 OTP por WhatsApp — Decisão Importante

**Problema:** Se o OTP for enviado pelo inbox WhatsApp da clínica, o paciente recebe a mensagem antes de escolher a clínica, e clínicas com mesmo Contact podem competir pelo envio.

**Recomendação:** Klivy mantém um **WhatsApp Business Account próprio** (`+55 11 ... — Klivy Pacientes`) usado **exclusivamente** para OTP do portal. Não pertence a nenhuma clínica.

**Alternativa:** SMS via Twilio/Zenvia. Mais caro mas neutro.

### 17.3 LGPD

| Direito | Como atendemos |
|---|---|
| Acesso | Tela de "Meus Dados" + export JSON+PDF |
| Correção | Pedido via conversa (auto-edição em campos sensíveis é risco) |
| Exclusão | Anonimização (preserva prontuário 20 anos por exigência CFM) |
| Portabilidade | Export estruturado |
| Consentimento | Versionado, com hash, IP, UA, assinatura |
| Revogação | Botão "Revogar consentimento" — clínica é notificada |

### 17.4 Segurança Aplicação

- HTTPS obrigatório (HSTS).
- Cookies `SameSite=Lax`, `Secure`.
- CSP estrita no SPA.
- Signed URLs de Active Storage com TTL curto (15 min).
- Rate limit por IP e por identifier no endpoint de OTP.
- Captcha invisível (hCaptcha) após 3 tentativas falhas.
- Logs de segurança para alertar tentativas de força bruta.

---

## 18. Roadmap por Sprint <a id="18-roadmap"></a>

Cada sprint = 1 semana. Times podem paralelizar backend e frontend. Roadmap atualizado para v1.1 refletindo escopo MVP/F2/F3 reconciliado com Fluxos.

### Fase MVP (Sprint A–E)

| Sprint | Backend | Frontend | Marcos |
|---|---|---|---|
| **A** | Infra: subdomínio + DNS + plugin `plugins/patient_portal/` + namespace `/api/v1/patient_portal/` + `BaseController` + JWT + Pundit base. Modelos: `PatientPortalOtp`, `PatientPortalSession`, `PortalInvite`, `PatientPortalSetting` (schema + jsonb categorias), `ProfessionalPortalSetting`, `ConfigResolver` service. Endpoints `auth/*` + `home`. Admin: endpoint de convite + suspensão (`portal_status` em Patient). | SPA scaffold Vue 3 + Tailwind + router + Pinia + Axios interceptor + tela de login OTP + tela de seleção de clínica. | Login funcional end-to-end. |
| **B** | `PatientPortalConsent` (termo Klivy) + `PatientPortalAccessLog`. Endpoint de aceite de termo. Pre-flight checker básico. Settings UI no painel da clínica (preset "Autonomia Guiada"). Inbox auto-criação. | Modal LGPD bloqueante (1ª vez) + home shell + cards (skeleton) + suspensão UI. | Primeiro paciente entra e vê home vazia. |
| **C** | Agendamentos: GET lista/detalhe, POST confirm/cancel (dentro da janela), `AppointmentRequest` CRUD (paciente cria, recepção resolve). Pre-flight completo. Distinção 1ª vs retorno. Documentos: GET lista/download + signed URL + `DocumentRequest`. | Tela "Minhas consultas" + detalhe + modal confirmar/cancelar/solicitar. Tela "Documentos" + filtros + preview PDF + solicitar 2ª via. Painel clínica: fila de `AppointmentRequest` e `DocumentRequest`. | Paciente solicita reagendamento, recepção responde. |
| **D** | Financeiro (leitura): summary, lista de parcelas, detalhe, recibo PDF. Consentimentos: lista, sign, **revoke** (notifica "Compliance"), auto-disparo por procedimento. Anamnese pré-consulta (reuso FormTemplate) + bloqueio opcional. Recall scanner (job diário). | Tela financeiro + recibo download. Tela consentimentos (assinatura touch). Tela anamnese (formulário dinâmico). Banner recall na home. | Beta fechado com 2–3 clínicas começa. |
| **E** | Comunicação: integra `Conversation` + inbox auto-criado, templates rápidos com roteamento, business_hours + auto-resposta, triagem urgente (keyword + `force_phone` default). `PatientNotificationPreference` + matriz. | Tela de mensagens + composer com quick actions + indicador de não lidas. Tela "Preferências de notificação". | MVP fechado para go-live. |

### Fase 2 (Sprint F–H)

| Sprint | Backend | Frontend | Marcos |
|---|---|---|---|
| **F** | Pagamento online (Asaas): `Payment`, webhook handler com idempotência, PIX/boleto/cartão. Pré-pagamento por serviço (soft-hold 15min). Reembolso automático em clínica cancela. | Tela "Pagar parcela" + checkout PIX/boleto/cartão. Fluxo pré-pagamento. Tela "Status do reembolso". | Primeiro PIX pago via portal. |
| **G** | Cobranças automáticas opt-in: `late_cancel_fee`, `no_show_fee`. Bloqueio progressivo por inadimplência. NPS pós-consulta + roteamento detrator. Modos `slot_picker` + `direct_booking`. `WaitingListEntry` exposto + notificação top-da-fila. Validade de documentos (`expires_at`). Renovação periódica de consentimento. | Slot picker + calendar UI. Lista de espera. NPS prompt. Badge "Expirado" em documentos. | Presets adicionais disponíveis (Recepção Digital, Self-Service, Concierge) com UI de switch. |
| **H** | Switcher inline multi-clínica. Mensagem dirigida a profissional (`allow_direct_professional` + opt-in profissional). Anexos em mensagens. Indicador "lida". Cobrança avulsa pela clínica (`FinancialEstimate` → portal). | Header com switcher de clínica. Composer com seletor de destinatário + anexos. | Fase 2 fechada. |

### Fase 3 (Sprint I+)

| Sprint | Entrega |
|---|---|
| **I** | Dependentes/menores: `PatientResponsibleLink`, fluxo de vínculo + aprovação, JWT com `acting_as_responsible`, auditoria dupla. |
| **J** | Programa de indicação: `ReferralRecord` + `referral_code` + tracking de conversão + recompensas. |
| **K** | Upload de exames externos pelo paciente (`ExamMedia.uploaded_by_patient`) + revisão da clínica. Self-checkin (geofence/QR). |
| **L** | Reembolso de convênio (pacote: recibo + relatório + TUSS + CID). Exames com release strategy. |
| **M+** | Telemedicina, reviews públicos, otimizações.

---

## 19. Riscos, Premissas e Decisões em Aberto <a id="19-riscos"></a>

### 19.1 Riscos

| Risco | Mitigação |
|---|---|
| Vazamento de prontuário por falha de escopo | Pundit em 100% dos endpoints + testes de integração que tentam acessar dado de outro paciente |
| Confusão de paciente em múltiplas clínicas | Seletor explícito, JWT escopado, header sempre mostra clínica atual |
| Custo de WhatsApp/SMS para OTP | Limite anti-flood + fallback e-mail |
| Clínica não quer expor evolução | Default-deny + opt-in por campo em `PatientPortalSetting` |
| Inadimplência: paciente vê dívida e some | Cobranças seguem fluxo atual da clínica; portal é canal adicional, não único |
| Tráfego e disponibilidade impactando o sistema da clínica | Mesma infra é OK no início; monitorar e separar Sidekiq queues se necessário |

### 19.2 Premissas

- Toda clínica que ativar o portal já usa o módulo Pacientes (não faz sentido sem `Patient`).
- Gateway de pagamento será **um único** no MVP+Fase 2 (Asaas recomendado).
- Stack Vue 3 + Tailwind reaproveitada — não introduzimos React/Next.
- Deploy continua via Coolify, mesmo Dockerfile (apenas novo SPA buildado no mesmo pipeline).

### 19.3 Decisões Tomadas na v1.1

| # | Decisão | Resolução |
|---|---|---|
| **D-1** | Evolução clínica visível por padrão? | **Fechado:** default `none`, opt-in da clínica em 5 níveis (\§8.2). |
| **D-2** | PDF de evolução assinado disponível ao paciente? | **Fechado:** sim, nível `download_pdf` na Fase 2. |
| **D-3** | Gateway de pagamento? | **Recomendação:** Asaas. (Aberta para validação final com financeiro/diretoria.) |
| **F-1** | Default de `scheduling_mode` para 1ª consulta? | **Fechado:** `request_only` (segurança). |
| **F-2** | Default de `scheduling_mode` para retorno? | **Fechado para MVP:** `request_only` (MVP só entrega Autonomia Guiada). Fase 2 default vira `slot_picker`. |
| **F-3** | Cobrar no-show automaticamente? | **Fechado:** Não por default — opt-in clínica. F2. |
| **F-4** | Cobrar cancelamento tardio automaticamente? | **Fechado:** Não por default — opt-in. F2. |
| **F-5** | Mensagem direta a profissional? | **Fechado:** Não no MVP. Opt-in F2 com opt-in por profissional. |
| **F-6** | Anamnese obrigatória antes da 1ª consulta? | **Fechado:** **Sim** por default no MVP (clínica pode desligar). |
| **F-7** | Mostrar evolução clínica? | **Fechado:** Default `none` (opt-in por campo). |
| **F-8** | Auto-aprovar pedido de 2ª via de recibo? | **Fechado:** Sim por default (baixo risco). |
| **F-9** | Upload de exames externos pelo paciente? | **Fechado:** F3. |
| **F-10** | Self-vinculação de dependente? | **Fechado:** F3, com aprovação manual da clínica. |
| **F-11** | Resultado de exame: imediato ou aguardar revisão? | **Fechado:** Configurável, default `requires_professional_review`. F3. |
| **F-12** | Auto-block portal por inadimplência? | **Fechado:** Não por default. F2 com bloqueio progressivo opt-in. |
| **F-13** | NPS público ou interno? | **Fechado:** Interno no MVP/F2. F3 pode trazer público. |
| **F-15** | Agendar procedimento sem consulta prévia? | **Fechado:** Não por default (segurança clínica). |
| **F-16** | Lista de espera: FIFO ou priorizada? | **Fechado:** FIFO no MVP. F2 traz priorização opcional. |
| **F-17** | Receita de medicamento controlado: reemissão self-service? | **Fechado:** Nunca (segurança regulatória). |
| **F-18** | Mensagem urgente: força telefone, escala plantão ou abre fila? | **Fechado:** Configurável; default MVP = `force_phone`. |
| **F-19** | Termo de imagem expira em? | **Fechado:** 12 meses default (F2). |
| **F-20** | Recall padrão? | **Fechado:** 6 meses odonto/estética, 12 meses médico. Por serviço. |

### 19.4 Decisões em Aberto

| # | Decisão | Notas |
|---|---|---|
| **D-4** | Taxa do gateway repassa ao paciente? (`passes_fee_to_patient`) | Default proposto: `false`. Cada clínica decide. Validar com 3 clínicas-beta antes de F2. |
| **D-5** | WhatsApp Business próprio da Klivy para OTP ou SMS via terceiro (Twilio/Zenvia)? | Recomendação: WhatsApp Business próprio (custo menor + UX). Decisão executiva pendente. |
| **D-6** | Portal é ativável por clínica (toggle em `InstallationConfig` por account) ou universal? | Recomendação: ativável (módulo opt-in). Decisão de pricing/comercial. |
| **D-7** | Quem custeia infra extra — embutido no plano da clínica ou módulo pago à parte? | Decisão comercial. Não bloqueia desenvolvimento técnico. |
| **D-8** | Anamnese revogável pelo paciente após assinada? | Recomendação: não (versionar como `ConsentRecord`). |
| **F-14** | Pacote de tratamento: cancelamento gera estorno parcial automático? | Recomendação: vira solicitação (Fluxos D.5). Decisão de pricing/jurídico. |
| **D-9** (novo) | Soft-launch: quais 2–3 clínicas-beta no fim da Sprint D? | Definir até início da Sprint A. |
| **D-10** (novo) | Domínio único `pacientes.klivy.app` ou subdomínio por clínica? | Recomendação: domínio único + path por account (mais simples; consistente com sistema.klivy.app). |

---

## 21. Status de Execução <a id="21-status"></a>

Tracking sprint a sprint. **Atualizar ao final de cada sprint** com: status, escopo entregue, arquivos novos, modificações no core (sim/não) e link para visualizar.

### Sprint A — Infra + Auth OTP ✅ **CONCLUÍDA** (2026-05-18)

**Marco:** Login OTP end-to-end (paciente entra na home após receber código por e-mail).

**Status:** Concluída. Pronto para testar.

**Como visualizar:**
- **Portal do Paciente (SPA):** http://pacientes.lvh.me:3000/login
- **API admin (clínica):** http://localhost:3000/app/accounts/:id/settings/patient_portal (UI vem na Sprint B)
- **Inspeção das migrations:** rodar `bundle exec rails db:migrate`
- **OTP em dev:** aparece no log do `backend` (foreman), prefixado por `=== [PatientPortal OTP] ===`

**O que foi entregue:**

| Camada | Itens |
|---|---|
| Plugin | `plugins/patient_portal/` criado seguindo padrão dos plugins existentes (agenda/patients/financial). Engine isolada (`PatientPortal::Engine`) com `to_prepare` injetando `has_many/has_one` em `Account`, `Patient`, `User` — **sem editar nenhum arquivo do core**. |
| Migrations (7) | `patient_portal_settings`, `professional_portal_settings`, `portal_invites`, `patient_portal_otps`, `patient_portal_sessions`, `patient_portal_access_logs`, colunas `portal_status` / `portal_suspended_until` / `portal_suspension_reason` / `needs_recall` / `last_recall_at` em `patients`. |
| Modelos | `PatientPortalSetting`, `ProfessionalPortalSetting`, `PortalInvite` (com `token` único + TTL 30d + `accept!`), `PatientPortalOtp` (TTL 10min + bcrypt + anti-flood), `PatientPortalSession` (jti único + revoke + touch_last_seen), `PatientPortalAccessLog` (com `log!` idempotente). |
| Services | `PatientPortal::JwtEncoder` (HS256), `IdentifierNormalizer` (E.164/email), `OtpDispatcher` (email via ActionMailer + log dev), `ContactFinder` (cross-account), `Authenticator` (request_otp / verify_otp / select_account), `ConfigResolver` (hierarquia Account→Profissional, stubs F2 pra Serviço→Procedimento→Tag), `PresetApplier` (preset `autonomy_guided` completo). |
| Mailer | `PatientPortal::OtpMailer` + views HTML e texto. |
| Controllers API paciente | `Api::V1::PatientPortal::BaseController` (JWT auth), `AuthController` (5 endpoints: request_otp/verify_otp/select_account/logout/me), `HomeController` (payload agregado skeleton). |
| Controllers admin clínica | `Api::V1::Accounts::PatientPortal::BaseController` (gate `ensure_admin!`), `InvitesController` (CRUD), `SettingsController` (show/update/apply_preset), `Api::V1::Accounts::Patients::PatientPortal::PortalSuspensionsController` (suspender/restaurar). |
| Roteamento | `plugins/patient_portal/config/routes.rb` com 3 grupos: SPA via `constraints(subdomain: /^pacientes.../)`, API paciente em `/api/v1/patient_portal/*`, API admin em `/api/v1/accounts/:id/patient_portal/*`. |
| View HTML | `app/views/patient_portal_pages/index.html.erb` (shell mínimo + `vite_javascript_tag 'patient_portal'`). |
| Entry Vite | `app/javascript/entrypoints/patient_portal.js` (stub que importa `plugins/patient_portal/frontend/main.js` — único arquivo fora de plugins, segue padrão dos outros entries como `survey.js`, `superadmin.js`). |
| SPA Vue 3 | `plugins/patient_portal/frontend/` com `main.js`, `App.vue`, `router/`, `store/auth.js` (Pinia), `api/http.js` + `auth.js`, `styles/app.css`. |
| Componentes reutilizáveis | `BaseButton`, `BaseInput`, `BaseCard`, `AuthLayout`, `OtpInput` (6 dígitos com paste + autofocus + backspace). |
| Páginas | `LoginPage` (email/WhatsApp toggle — WhatsApp em breve), `OtpVerifyPage` (com mask de identifier), `AccountSelectPage` (multi-clínica), `HomePage` (skeleton com cards para sprints futuras). |

**Modificações no core (mínimas):**

| Arquivo do core | Mudança | Justificativa |
|---|---|---|
| `config/routes.rb` | +1 linha: `mount PatientPortal::Engine, at: '/'` | Mesmo padrão que `Billing::Engine` já usa (linha 1204). Não muda nada existente. |
| `app/javascript/entrypoints/patient_portal.js` | Arquivo novo (stub re-export) | Vite Ruby exige entry pack aqui. Stub apenas importa do plugin — toda a lógica fica em `plugins/`. Padrão dos outros entries (`survey.js`, `superadmin.js`, etc.). |

**Setup em localhost:**
1. Rodar migrations: `bundle exec rails db:migrate`
2. Reiniciar foreman (já rodando): `lsof -ti :3000 | xargs kill` + `foreman start -f Procfile.dev.local &`
3. Acessar **http://pacientes.lvh.me:3000/login**
4. Digitar e-mail de um paciente existente (ou criar um com `bundle exec rails c`)
5. Código OTP aparece no log do foreman (canal `backend`)
6. Digitar código → escolher clínica (se multi) → cair na Home

**Decisões resolvidas durante a Sprint A:**
- URL local: `pacientes.lvh.me:3000` (lvh.me aponta para 127.0.0.1, mimica produção).
- OTP: e-mail via ActionMailer + log no Rails console em dev.
- D-10 (subdomínio único): provisoriamente sim — todas as clínicas via mesmo host, `account_id` carregado no JWT após seleção.

**Ainda em aberto:**
- D-5 (WhatsApp Business próprio Klivy vs SMS) — não bloqueia avanço.
- UI admin (cliente da clínica) para gerenciar settings + presets + invites + suspensão — vira primeira tarefa da **Sprint B**.

**Hotfixes pós-merge:**

| Data | Arquivos | Resumo |
|---|---|---|
| 2026-05-18 | `services/patient_portal/patient_finder.rb` (novo, substitui `contact_finder.rb`), `services/patient_portal/authenticator.rb`, `controllers/api/v1/patient_portal/auth_controller.rb` | **Busca de paciente:** Klivy grava e-mail/telefone em `Patient.email`/`Patient.phone` (cadastro clínico), mas `Contact.email`/`Contact.phone_number` (Chatwoot) costuma vir vazio. `PatientFinder` agora consulta os dois lugares e retorna a união. `auth/me` e `select_account` serializam `email`/`phone` priorizando `Patient.*` com fallback no `Contact.*`. |

---

### Sprint B — SPA shell mobile + Termo LGPD + páginas-âncora ✅ **CONCLUÍDA** (2026-05-18)

**Marco:** App de paciente com cara de aplicativo nativo — header, bottom navigation, 5 abas, termo LGPD bloqueante na primeira sessão, sistema de notificações (stub estruturado).

**Como visualizar:**
- **Portal:** http://pacientes.lvh.me:3000/ — após login OTP, primeiro acesso mostra o termo LGPD bloqueante; depois cai na home com hero card + acessos rápidos + resumo + bottom nav (Início / Consultas / Saúde / Financeiro / Mais).
- **Notificações:** ícone de sino no header (com badge se houver não lidas) → `/notifications`.
- **Logout:** aba "Mais" → "Sair da conta".

**Decisão de produto da Sprint B:** o objetivo desta sprint deixou de ser "UI admin no painel da clínica" (que foi reescalonado para Sprint B' / paralelo) e passou a ser **shell mobile completo do paciente**, em resposta ao feedback do usuário (2026-05-18). UI admin para gerenciar settings/presets/invites/suspensão segue como pendente — pode ser feita em paralelo com Sprint C ou após Sprint E.

**O que foi entregue:**

| Camada | Itens |
|---|---|
| Migrations (1) | `patient_portal_consents` (term_type/version/accepted_at/revoked_at + IP/UA + unique index) — termo Klivy versus ConsentRecord clínico do plugin Pacientes |
| Modelos (1) | `PatientPortalConsent` com `accept!` helper e constante `CURRENT_TERM_VERSION` |
| Endpoints API paciente (4 novos) | `POST /consents/portal_terms/accept`, `POST /consents/lgpd/accept`, `GET /notifications` (stub), `POST /notifications/mark_all_read` |
| `/auth/me` + `/auth/select_account` ampliados | Retornam `consent: { required, term_version }` para o SPA decidir gate de termo |
| Sistema de ícones | `BaseIcon.vue` + 20 ícones SVG inline (Home/Calendar/Heart/Wallet/Grid/Bell/Chevron×2/User/Document/Shield/Check/Close/Logout/Message/Gift/Clock/Pill/Sparkle/Info). Sem dependência externa de iconify. |
| Componentes base | `Avatar` (com initials + cor derivada do nome), `Badge` (5 variants), `EmptyState`, `ListItem` (interativo), `PageHeader` (com back), `AppHeader` (saudação + sino), `BottomNav` (5 abas com router-link + active state), `AppShell` (layout principal — vira "moldura mobile" centralizada em desktop ≥720px) |
| Páginas novas (6) | `ConsentTermsPage` (modal full-screen bloqueante, scroll-to-enable + IP/UA registrado), `AppointmentsPage` (tabs Futuras/Histórico + EmptyState), `HealthPage` (3 cards Evolução/Plano/Prescrições), `FinancialPage` (summary + EmptyStates), `MorePage` (avatar grande + seções Conta/Comunicação/Privacidade + sair), `NotificationsPage` (lista + mark-all + EmptyState) |
| HomePage refatorada | Hero card com gradiente azul→índigo + saudação dinâmica · grid 3x2 de acessos rápidos com cores por categoria · banner de recall condicional · stats grid (em aberto/documentos/mensagens) |
| Auth pages polidas | `AuthLayout` ganhou pill de marca com ponto pulsante + sombras refinadas + radial-gradient sutil |
| Stores Pinia | `notifications` (fetch + markAllRead + unreadCount), `auth` ampliada com `consent` state e `acceptPortalTerms()` + chamada automática de `/me` após `selectAccount` para carregar consent flag |
| Router | Guards atualizados — `requiresAuth` + `needsPortalConsent` redireciona pra `/consent` enquanto não aceitar; `skipConsentGate` na própria rota de consent |
| Transições | Fade-up entre rotas (180ms) — sensação de app nativo |

**Modificações no core:** Nenhuma (continua apenas as 2 linhas tocadas na Sprint A — `config/routes.rb` mount e `app/javascript/entrypoints/patient_portal.js` stub).

**Total de arquivos do plugin tocados na Sprint B:**
- 4 backend (1 migration + 1 modelo + 2 controllers + atualizações em routes e auth_controller)
- ~40 frontend (20 ícones + 7 componentes base + 6 páginas novas + 2 páginas atualizadas + 2 stores + 2 APIs + router + App.vue + estilos)

**Setup adicional (já feito):**
- Migration `20260518000008` aplicada
- Variável `LETTER_OPENER=true` no `.env` (hotfix anterior — abre e-mails de OTP no navegador)

**Sprint C bate a porta com:** lista real de `AgendaEvent` na AppointmentsPage, detalhe de evento, botão "Confirmar presença", `AppointmentRequest` (solicitação de reagendamento), pre-flight checks, lista real de `Document` + `DocumentRequest`. Sprint C alimenta o que hoje é EmptyState.

---

---

### Sprint C — Agendamentos + Documentos ✅ **CONCLUÍDA** (2026-05-18)

**Versão entregue:** v0.3 (Sprint C)
**Branch:** `main` (commits incrementais)
**URL local para testes (`David Feliciano` / paciente 47):**
- http://pacientes.lvh.me:3000/login — login (já testado em Sprints A e B)
- http://pacientes.lvh.me:3000/ — Home agora renderiza `next_appointment` real quando existe
- http://pacientes.lvh.me:3000/appointments — lista real (Futuras + Histórico) + tag de pedidos pendentes
- http://pacientes.lvh.me:3000/appointments/new — solicitação de agendamento com preflight (consent/financeiro/anamnese)
- http://pacientes.lvh.me:3000/appointments/76 — detalhe da consulta com "Confirmar presença" e "Cancelar" (regras de janela)
- http://pacientes.lvh.me:3000/health — lista real de `Document` (filtrada por `documents.document_types_exposed`) + tag de pedidos pendentes
- http://pacientes.lvh.me:3000/health/document-request — solicitação de 2ª via / novo documento

**Decisão de produto:** mantemos o padrão "default-deny clínico" — só `assinado`/`enviado` ficam visíveis para o paciente, e o filtro de tipos vem do setting da clínica (`documents.document_types_exposed`). Cancelamento online segue a janela do `rescheduling.cancel_window_hours` (24h por padrão).

**Decisão técnica importante:**
- O download de documento NÃO reusa `SecureBlobsController` do core (que exige sessão Devise). Em vez disso, criamos `GET /api/v1/patient_portal/documents/:id/download` que autentica via JWT do paciente e faz `send_data` direto. Para MVP é OK (arquivos pequenos); quando crescer, plugamos URL S3 com TTL curto.
- AgendaEvent usa `contact_id` (não `patient_id`). Toda a query do paciente passa por `Patient.contact_id` no `PatientPortal::AppointmentVisibility` service — único lugar com essa lógica.

**Backend novo (todos arquivos sob `plugins/patient_portal/`, zero modificação no core):**

| Tipo | Arquivo |
|------|---------|
| Migration | `db/migrate/20260518000009_create_portal_appointment_requests.rb` — fila de pedidos do paciente |
| Migration | `db/migrate/20260518000010_create_portal_document_requests.rb` — pedidos de 2ª via |
| Model | `app/models/portal_appointment_request.rb` |
| Model | `app/models/portal_document_request.rb` |
| Service | `app/services/patient_portal/appointment_visibility.rb` — query escopo do paciente |
| Service | `app/services/patient_portal/document_visibility.rb` — filtro por tipo exposto + status |
| Service | `app/services/patient_portal/preflight_checker.rb` — 3 checks (consent/financeiro/anamnese) |
| Controller | `appointments_controller.rb` — list/show/confirm/cancel |
| Controller | `appointment_requests_controller.rb` — list/create/destroy |
| Controller | `documents_controller.rb` — list/show/download (stream via JWT) |
| Controller | `document_requests_controller.rb` — list/create/destroy |
| Controller | `preflight_controller.rb` — GET preflight/appointment |
| Atualizado | `home_controller.rb` — popula `next_appointment` + `documents_recent` reais |
| Routes | `config/routes.rb` — 11 rotas novas |

**Endpoints adicionados (todos autenticam via JWT do paciente):**

| Método | Path | Função |
|--------|------|--------|
| GET    | `/api/v1/patient_portal/appointments` | lista futuras + passadas (filtra por `contact_id`) |
| GET    | `/api/v1/patient_portal/appointments/:id` | detalhe |
| POST   | `/api/v1/patient_portal/appointments/:id/confirm` | `scheduled` → `confirmed` |
| POST   | `/api/v1/patient_portal/appointments/:id/cancel` | soft-delete com `cancelamento_paciente`, respeita `cancel_window_hours` |
| GET    | `/api/v1/patient_portal/appointment_requests` | meus pedidos |
| POST   | `/api/v1/patient_portal/appointment_requests` | novo pedido (até 3 sugestões de horário) |
| DELETE | `/api/v1/patient_portal/appointment_requests/:id` | cancela pedido pendente |
| GET    | `/api/v1/patient_portal/documents` | docs visíveis (`assinado`/`enviado`, tipos expostos) |
| GET    | `/api/v1/patient_portal/documents/:id` | detalhe |
| GET    | `/api/v1/patient_portal/documents/:id/download` | streaming do arquivo |
| GET    | `/api/v1/patient_portal/document_requests` | meus pedidos de 2ª via |
| POST   | `/api/v1/patient_portal/document_requests` | novo pedido |
| DELETE | `/api/v1/patient_portal/document_requests/:id` | cancela pedido pendente |
| GET    | `/api/v1/patient_portal/preflight/appointment` | consultivo: posso agendar? |

**Frontend novo (`plugins/patient_portal/frontend/`):**

| Tipo | Arquivos |
|------|---------|
| API clients | `api/appointments.js`, `api/appointment_requests.js`, `api/documents.js`, `api/document_requests.js`, `api/preflight.js` |
| Stores Pinia | `store/appointments.js`, `store/documents.js` |
| Components | `AppointmentCard.vue`, `AppointmentStatusBadge.vue`, `DocumentCard.vue`, `PreflightBanner.vue` |
| Utils | `utils/format.js` — formatadores de data/hora/moeda compartilhados |
| Pages novas | `AppointmentDetailPage.vue`, `NewAppointmentPage.vue`, `DocumentRequestPage.vue` |
| Pages refatoradas | `AppointmentsPage.vue` (lista real + tab Futuras/Histórico + pedidos pendentes), `HealthPage.vue` (lista real de documentos + pedidos pendentes), `HomePage.vue` (hero com `next_appointment` real e CTA) |
| Router | +3 rotas novas (`/appointments/new`, `/appointments/:id`, `/health/document-request`) |
| BaseButton | +2 variantes (`danger`, `ghost-danger`) |

**Modificações no core:** Nenhuma (continua apenas as 2 linhas tocadas na Sprint A — `config/routes.rb` mount e `app/javascript/entrypoints/patient_portal.js` stub).

**Total de arquivos do plugin tocados na Sprint C:**
- 13 backend (2 migrations + 2 modelos + 3 services + 5 controllers + 1 atualização em `home_controller` + atualizações em `routes.rb`)
- 15 frontend (5 APIs + 2 stores + 4 components + 1 utils + 3 pages novas + 3 pages refatoradas + router + BaseButton)

**Setup adicional (já feito):**
- Migrations `20260518000009` e `20260518000010` aplicadas
- Frontend roda em hot-reload (Vite) — nenhum rebuild manual necessário

**E2E backend smoke test (com JWT do paciente 47):**
- ✅ `GET /appointments` retorna o evento histórico em `past` (status `scheduled`, `can_confirm: false` porque já passou)
- ✅ `GET /documents` retorna `[]` (paciente não tem documentos `assinado`/`enviado` ainda)
- ✅ `GET /preflight/appointment` retorna `can_schedule: false` com `consent.status: 'blocked'` (paciente não aceitou termo)
- ✅ `POST /appointment_requests` com 2 sugestões cria pedido `status: 'pending'`
- ✅ `POST /document_requests` com `document_type: 'atestado'` cria pedido `status: 'pending'`

**Sprint D bate a porta com:** Financeiro read-only (lista de `Financial::Installment` por paciente), Anamnese (visualização do paciente, opt-in), `ConsentRecord` clínico por procedimento (PRD §11), Recall ativo (notificação push/email/SMS quando atinge `recall_after_months`). Sprint D vai alimentar o card "Financeiro" da home e a página `/financial`.

---

### Sprint D — Financeiro (read) + Consentimentos + Anamnese + Recall ✅ **CONCLUÍDA** (2026-05-18)

**Versão entregue:** v0.4 (Sprint D)
**Branch:** `main` (commits incrementais)

**URL local para testes (paciente David Feliciano · id 47):**
- http://pacientes.lvh.me:3000/ — home com card real de financeiro, alertas para termos pendentes/vencidos, recall com "Depois" e "Agendar"
- http://pacientes.lvh.me:3000/financial — lista real de parcelas com tabs "Em aberto · Pagas · Todas", summary com valor vencido em destaque
- http://pacientes.lvh.me:3000/financial/installments/:id — detalhe da parcela com botão "Ver comprovante" (quando anexado)
- http://pacientes.lvh.me:3000/consent-records — lista de termos clínicos (pendentes + histórico assinado)
- http://pacientes.lvh.me:3000/consent-records/:id — visualização + signature pad (canvas) + checkbox "Li e concordo"
- http://pacientes.lvh.me:3000/health — agora exibe banner de termos pendentes em destaque + seção de anamneses (quando setting habilitado)
- http://pacientes.lvh.me:3000/health/anamnesis/:id — anamnese estruturada (queixa, alergias com severidade, medicações, histórico)

**Decisões de produto importantes:**

1. **Read-only no MVP.** Financeiro é puramente visualização — pagamento online (PIX, boleto, cartão) entra na Sprint F. A motivação é desacoplar regulamentação fiscal/PCI-DSS do release atual.

2. **Visualização de anamnese é opt-in.** Default `clinical.expose_anamnesis_to_patient = false`. Algumas especialidades (psicologia, psiquiatria) nunca devem expor — a clínica habilita por escolha consciente. Quando false, a página simplesmente não mostra a seção (não é um erro).

3. **ConsentRecord assinatura remota via JWT.** Reutilizamos `sign_remotely!` do core (que estava pensado para link em e-mail/SMS) com canal = portal JWT. Resultado equivalente do ponto de vista jurídico (paciente autenticado + signature_blob + IP + user_agent + integrity_hash SHA-256). O `remote_token` clássico é ignorado neste fluxo porque o JWT já carrega a identidade do paciente.

4. **Recall dismissable.** Banner na home com 2 ações: "Depois" (zera `needs_recall` + carimba `last_recall_at`) e "Agendar" (registra `recall_schedule` intent + redireciona para `/appointments/new`). Métrica de conversão de recall vai sair do `PatientPortalAccessLog` direto.

**Decisões técnicas:**

1. **`render_not_found` sanitizado.** ActiveRecord::RecordNotFound carrega a query SQL completa na message. Patcheamos `base_controller#render_not_found` para devolver "Recurso não encontrado." quando a fonte é AR — evita vazamento de schema (LGPD §17.1).

2. **Comprovante via streaming JWT.** Mesmo padrão da Sprint C para documentos: `send_data` direto, autenticado via JWT, NÃO usa `SecureBlobsController` do core (que exige Devise).

3. **Setting fallback liberal.** Quando `patient_portal_setting` não existe na account, `DocumentVisibility` e `FinancialSummary` aplicam defaults razoáveis (libera todos os tipos, mostra histórico). Isso facilita onboarding — clínica não precisa configurar nada antes do paciente ver o portal.

**Backend novo (todos arquivos sob `plugins/patient_portal/`, zero modificação no core):**

| Tipo | Arquivo |
|------|---------|
| Service | `app/services/patient_portal/financial_summary.rb` — totais + lista por scope |
| Service | `app/services/patient_portal/consent_record_visibility.rb` — pending/signed |
| Service | `app/services/patient_portal/anamnesis_visibility.rb` — opt-in via setting |
| Controller | `financial_controller.rb` — summary + installments + proof streaming |
| Controller | `consent_records_controller.rb` — list + show + sign (POST) |
| Controller | `anamneses_controller.rb` — list (com exposed flag) + show |
| Controller | `recall_controller.rb` — dismiss + schedule_intent |
| Atualizado | `home_controller.rb` — `financial_summary`, `pending_consents_count`, `consent_pending_blocking` reais |
| Atualizado | `base_controller.rb` — sanitiza `RecordNotFound.message` (não vaza SQL) |
| Routes | `config/routes.rb` — 11 rotas novas Sprint D |

**Endpoints adicionados (todos autenticam via JWT do paciente):**

| Método | Path | Função |
|--------|------|--------|
| GET    | `/api/v1/patient_portal/financial/summary` | totais + next_due |
| GET    | `/api/v1/patient_portal/financial/installments?scope=open\|paid\|all` | lista |
| GET    | `/api/v1/patient_portal/financial/installments/:id` | detalhe |
| GET    | `/api/v1/patient_portal/financial/installments/:id/proof` | comprovante (stream) |
| GET    | `/api/v1/patient_portal/consent_records` | pending + signed |
| GET    | `/api/v1/patient_portal/consent_records/:id` | detalhe com body |
| POST   | `/api/v1/patient_portal/consent_records/:id/sign` | assina (signature_blob) |
| GET    | `/api/v1/patient_portal/anamneses` | lista (com exposed flag) |
| GET    | `/api/v1/patient_portal/anamneses/:id` | detalhe |
| POST   | `/api/v1/patient_portal/recall/dismiss` | "lembre depois" |
| POST   | `/api/v1/patient_portal/recall/schedule_intent` | métrica de clique |

**Frontend novo (`plugins/patient_portal/frontend/`):**

| Tipo | Arquivos |
|------|---------|
| API clients | `api/financial.js`, `api/consent_records.js`, `api/anamneses.js`, `api/recall.js` |
| Stores Pinia | `store/financial.js`, `store/consent_records.js`, `store/anamneses.js` |
| Components | `SignaturePad.vue` (canvas com touch/mouse + clear + emit dataURL), `InstallmentCard.vue` |
| Pages novas | `InstallmentDetailPage.vue`, `ConsentRecordsPage.vue`, `ConsentSignPage.vue`, `AnamnesisDetailPage.vue` |
| Pages refatoradas | `FinancialPage.vue` (lista real + tabs + summary danger), `HealthPage.vue` (banner termos + seção anamnese), `HomePage.vue` (financial real + alertas + recall dismiss + 6 quick access) |
| Router | +4 rotas (`/financial/installments/:id`, `/consent-records`, `/consent-records/:id`, `/health/anamnesis/:id`) |

**Modificações no core:** Nenhuma (continua apenas as 2 linhas tocadas na Sprint A).

**Total de arquivos do plugin tocados na Sprint D:**
- 10 backend (3 services + 4 controllers + 1 atualização em `home_controller` + 1 em `base_controller` + atualização de `routes.rb`)
- 16 frontend (4 APIs + 3 stores + 2 components novos + 4 pages novas + 3 pages refatoradas + router)

**E2E test (validações reais com seed data):**

| Cenário | Resultado |
|---------|-----------|
| Seed: paciente 47, 3 installments (R$300 recebido, R$300 vencido, R$300 a vencer), 1 ConsentRecord pendente, 1 Anamnesis finalized, `needs_recall=true` | ✅ Setup OK |
| `GET /home` retorna `financial_summary.overdue_amount_cents=30000`, `recall_due=true`, `pending_consents_count=1` | ✅ |
| `GET /financial/summary` retorna `next_due` apontando para parcela vencida (#2) | ✅ |
| `GET /financial/installments?scope=open` retorna 2 itens (vencido + pendente, não traz recebido) | ✅ |
| `GET /consent_records` retorna 1 pending, 0 signed | ✅ |
| `POST /consent_records/:id/sign` com signature PNG base64 move para `signed`, mode=`remote_link`, signature_method=`remote` | ✅ |
| Re-assinatura no mesmo ID retorna `Este termo já foi assinado.` | ✅ |
| `POST /sign` sem `signature_blob` retorna `Assinatura ausente.` | ✅ |
| `GET /anamneses` retorna `exposed=true` (setting habilitado) com 1 item | ✅ |
| `POST /recall/dismiss` zera `needs_recall` no Patient; próximo `/home` retorna `recall_due=false` | ✅ |
| **Cross-patient isolation:** JWT do paciente 47 tentando acessar installment #4 (outro paciente, mesma account) → 404 com mensagem sanitizada (sem SQL) | ✅ |
| **Audit trail:** `PatientPortalAccessLog` registra `sign`, `dismiss`, com `metadata` correto | ✅ |

**Setup adicional (já feito):**
- Migration: nenhuma nova (reusamos `Financial::Installment`, `ConsentRecord`, `Anamnesis` do core)
- Setting: `clinical.expose_anamnesis_to_patient` habilitado no seed (default é false; clínica decide)

**Sprint E bate a porta com:** Mensagens (reuso de `Conversation` do Chatwoot via `inbox_id` dedicado por clínica), Triagem urgente (keywords + redirect para telefone), Notificações reais (saem do stub), `/more` page completa (perfil, configurações, sobre, exportar dados LGPD), recibo digital pós-pagamento.

---

### Sprint E — Comunicação + Triagem Urgente + Notificações + Perfil ✅ **CONCLUÍDA** (2026-05-18)

**Versão entregue:** v0.5 (Sprint E)
**Branch:** `main`

**URLs locais para testes (paciente David Feliciano · id 47):**
- http://pacientes.lvh.me:3000/messages — conversa com a clínica (chat com bolhas) + triagem urgente
- http://pacientes.lvh.me:3000/notifications — lista real com ícones por tipo, tap pra marcar lido
- http://pacientes.lvh.me:3000/profile — formulário editável (nome, email, telefone, data nasc, sexo, endereço)
- http://pacientes.lvh.me:3000/more — agora com rotas funcionais + ação "Exportar meus dados" (LGPD)

**Decisões de produto importantes:**

1. **Mensagens reaproveitam o Chatwoot.** Em vez de criar um sistema paralelo de mensageria, criamos um `Channel::Api` por Account (marcado com `additional_attributes.source = 'patient_portal'`) e usamos os modelos nativos `Inbox`, `Conversation`, `Message`. A recepção responde no painel Chatwoot existente — a resposta aparece automaticamente no portal sem qualquer código extra. Decisão S18 do anexo de sugestões.

2. **Triagem urgente é UX, não bloqueio.** Quando o paciente envia mensagem com keywords da `messaging.urgent_keyword_list` (default: urgência, urgente, emergência, sangramento, desmaio, dor forte, febre alta, convulsão), o front consulta `/messages/triage` *antes* de enviar e mostra modal "isso é uma urgência? ligue agora" com botão `tel:`. Se o paciente confirmar "enviar mesmo assim", a mensagem é gravada com `additional_attributes.urgent: true` (visível no painel da clínica como tag).

3. **Notificações in-app, push fica em F2.** Modelo `PatientPortalNotification` com 11 tipos (`appointment_confirmed`, `document_ready`, `consent_pending`, `recall`, `message_received`, `financial_charge`, `financial_overdue`, etc.). `NotificationDispatcher` é o ponto único — qualquer fluxo (Sprint C/D em diante) chama `dispatch(account:, patient:, kind:, title:, body:)`. Push real (web push / FCM) entra em outra sprint quando o tráfego justificar.

4. **LGPD export em JSON self-service.** MVP retorna um JSON com tudo que o paciente JÁ VÊ no portal (perfil, agendamentos, parcelas, documentos, consentimentos, access_logs recentes). PDF formatado + envio por email entram em F2. Não esquece direito de acesso (LGPD Art. 18 §1º).

5. **Perfil com whitelist explícita.** Paciente edita apenas: `name`, `email`, `phone`, `birthdate`, `sex`, `address` (jsonb), `contact_preferences` (jsonb). NÃO edita `patient_status`, `responsible_professional_id`, `needs_recall`, `contact_id`, `custom_attributes` — controle da clínica. Mudanças de `email`/`phone` espelham automaticamente no Contact (mantém OTP funcionando).

**Decisões técnicas:**

1. **`MessagingBridge` lida com `find_or_create` em 3 níveis** — Channel::Api → Inbox → ContactInbox → Conversation. É idempotente: se já existem, reusa; se não, cria. Permite que a 1ª mensagem do paciente "ligue" todo o pipeline sem dependência de setup manual da clínica.

2. **Conversation aberta por paciente.** Mantemos uma conversation `open|pending|snoozed` por vez por paciente, evitando criar threads novas a cada mensagem. Se a recepção resolver, próxima mensagem reabre.

3. **Triage previewer.** O endpoint `POST /messages/triage` é puramente consultivo (não cria nada) — usado pelo front pra decidir se mostra o modal antes do envio. Reduz round-trips.

**Backend novo (todos sob `plugins/patient_portal/`, zero modificação no core):**

| Tipo | Arquivo |
|------|---------|
| Migration | `db/migrate/20260518000011_create_patient_portal_notifications.rb` |
| Model | `app/models/patient_portal_notification.rb` |
| Service | `app/services/patient_portal/notification_dispatcher.rb` — ponto único pra criar notifs |
| Service | `app/services/patient_portal/messaging_bridge.rb` — find_or_create de Inbox+Conversation Chatwoot |
| Service | `app/services/patient_portal/urgent_triage.rb` — detecção case-insensitive sem acentos |
| Controller | `messages_controller.rb` — list / create / triage |
| Controller | `profile_controller.rb` — show / update com sync Contact |
| Controller | `lgpd_exports_controller.rb` — export JSON self-service |
| Atualizado | `notifications_controller.rb` — migrou de stub pra modelo real |
| Atualizado | `home_controller.rb` — `unread_messages_count` agora reflete notifs reais |
| Routes | `config/routes.rb` — 8 rotas novas Sprint E |

**Endpoints adicionados (todos JWT-autenticados):**

| Método | Path | Função |
|--------|------|--------|
| GET    | `/api/v1/patient_portal/notifications` | lista + unread_count |
| POST   | `/api/v1/patient_portal/notifications/mark_all_read` | marca todas |
| POST   | `/api/v1/patient_portal/notifications/:id/mark_read` | marca uma |
| GET    | `/api/v1/patient_portal/messages` | conversa atual + lista |
| POST   | `/api/v1/patient_portal/messages` | envia mensagem |
| POST   | `/api/v1/patient_portal/messages/triage` | "é urgente?" (consultivo) |
| GET    | `/api/v1/patient_portal/profile` | dados editáveis |
| PATCH  | `/api/v1/patient_portal/profile` | atualiza (whitelist) |
| POST   | `/api/v1/patient_portal/lgpd/exports` | gera JSON LGPD |

**Frontend novo (`plugins/patient_portal/frontend/`):**

| Tipo | Arquivos |
|------|---------|
| API clients | `api/messages.js`, `api/profile.js` + extensão de `api/notifications.js` |
| Stores Pinia | `store/messages.js`, `store/profile.js` + extensão de `store/notifications.js` (markRead) |
| Components | `UrgentTriageModal.vue` — modal full-screen com CTA `tel:` |
| Pages novas | `MessagesPage.vue` (chat com bolhas + composer + scroll-to-bottom), `ProfilePage.vue` (form com Card cards) |
| Pages refatoradas | `NotificationsPage.vue` (ícones por kind + tap-to-read + navegação), `MorePage.vue` (rotas reais + ação LGPD export que baixa JSON) |
| Router | +2 rotas (`/messages`, `/profile`) |

**Modificações no core:** Nenhuma.

**Total de arquivos do plugin tocados na Sprint E:**
- 11 backend (1 migration + 1 modelo + 3 services + 3 controllers + 2 atualizações + routes)
- 14 frontend (2 APIs novas + extensão de 1 + 2 stores + extensão de 1 + 1 component + 2 pages novas + 2 refatoradas + router)

**E2E test (10 cenários validados via tunnel HTTPS):**

| # | Cenário | Resultado |
|---|---------|-----------|
| 1 | `NotificationDispatcher` cria 3 notifs (confirmation/document/overdue) | ✅ 3 criadas |
| 2 | `GET /notifications` retorna `unread_count=3` + 3 items | ✅ |
| 3 | `POST /notifications/:id/mark_read` reduz `unread_count` para 2 | ✅ |
| 4 | `POST /messages` com texto neutro retorna `urgent=false` | ✅ |
| 5 | `POST /messages` com "dor forte aqui, é urgência" retorna `urgent=true, keywords=[urgência, dor forte]` | ✅ |
| 6 | `GET /messages` lista as 2 mensagens, 1 marcada com `urgent` no `additional_attributes` | ✅ |
| 7 | `PATCH /profile` atualiza nome + endereço (jsonb) | ✅ |
| 8 | `POST /lgpd/exports` retorna JSON com 7 access_logs + 1 anamnese + 3 installments | ✅ |
| 9 | `GET /home` reflete `unread_messages_count=2`, `financial_summary.overdue=R$300`, `pending_consents_count=1` | ✅ |
| 10 | `POST /messages/triage` consultivo (não cria mensagem) com "emergência" retorna `urgent=true` | ✅ |

**Cloudflare Tunnel + iPhone:** Validamos toda a Sprint E via `https://*.trycloudflare.com` no iPhone (após hotfix do `apiBaseUrl` em `index.html.erb` — antes lia `ENV['FRONTEND_URL']` que tinha `0.0.0.0:3000` quebrando mobile).

**Setup adicional (já feito):**
- Migration `20260518000011` aplicada
- Gems `letter_opener_web` instalada e mountada em `/letter_opener` (dev only)
- Rota `/portal-diag` adicionada (HTML puro pra debug mobile)

**Sprint F bate a porta com:** pagamento online (PIX QR, boleto, cartão) integrando gateway via Sprint F do Financial — paciente paga direto no portal. Push notifications (web push + iOS APNs via FCM). UI admin do painel da clínica para gerenciar settings/presets/invites/suspensão (até hoje só via endpoint, sem tela).

---

### Sprint F — Pagamento online + Testes ✅ **CONCLUÍDA** (2026-05-18)

**Versão entregue:** v0.6 (Sprint F)
**Escopo ajustado:** focamos em pagamento + testes; push web + admin UI **adiados para Sprint G** (push tem caveats no iOS Safari < 16.4 e admin UI é seu próprio universo no dashboard Vue do Klivy).

**URLs locais (paciente David Feliciano · id 47):**
- http://pacientes.lvh.me:3000/financial — lista de parcelas com botão "Pagar online" no detalhe
- http://pacientes.lvh.me:3000/financial/installments/:id — detalhe com CTA "💳 Pagar online"
- http://pacientes.lvh.me:3000/financial/installments/:id/pay — escolha de método + QR PIX/Boleto + polling

**Decisões de produto importantes:**

1. **MockGateway por default em dev.** A clínica não precisa de credencial Asaas para o paciente experimentar o fluxo. Em produção, `Gateway.for(account:)` escolhe `AsaasGateway` automaticamente se a clínica configurou `Financial::GatewaySetting`. Botão "🧪 Simular pagamento (DEV)" aparece apenas para `gateway=mock` e em `Rails.env.development?` — produção retorna 403.

2. **PortalPayment é camada de tracking — não substitui Financial::Installment.** Cada parcela pode ter várias tentativas (PIX expira, paciente troca pra boleto, depois cartão). Cada tentativa é um `PortalPayment`; só uma vira `paid`. Quando isso acontece, `PaymentReceiptIssuer` marca a `Financial::Installment` como recebida.

3. **Recibo digital auto-gerado.** Quando o pagamento confirma, criamos um `Document` (tipo `orcamento` — não há "recibo" no enum core; MVP usa esse) com `variables.portal_payment_id` apontando para a tentativa. Idempotente: chamadas repetidas não duplicam.

4. **State machine no front.** Uma única `PaymentPage` que renderiza diferente conforme o status: `(sem payment)` → escolha de método; `awaiting_payment + pix` → QR canvas + copia-cola + countdown; `awaiting_payment + boleto` → linha digitável + PDF link; `paid` → success hero verde; `expired/failed/cancelled` → CTA "tentar de novo". Sem múltiplas rotas.

**Decisões técnicas:**

1. **Gateway interface plugável.** `PatientPortal::Payment::Gateway` define o contrato; `MockGateway` e `AsaasGateway` (stub) implementam. Adicionar Stripe/MercadoPago/Pagar.me = nova subclass + atualizar factory. **Webhooks** já existentes no plugin financial podem ser estendidos para chamar `PaymentReceiptIssuer` quando reconciliação confirma o `gateway_payment_id`.

2. **Polling no front em vez de WebSocket.** Front re-checa `GET /payments/:id` a cada 4s enquanto `awaiting_payment`. Mais simples; quando push notifications subirem (Sprint G), substitui por evento real-time.

**Backend novo (todos sob `plugins/patient_portal/`, zero modificação no core):**

| Tipo | Arquivo |
|------|---------|
| Migration | `db/migrate/20260518000012_create_portal_payments.rb` |
| Model | `app/models/portal_payment.rb` — state machine + scopes |
| Service | `app/services/patient_portal/payment/gateway.rb` — interface abstrata + factory |
| Service | `app/services/patient_portal/payment/mock_gateway.rb` — implementação dev/CI |
| Service | `app/services/patient_portal/payment/asaas_gateway.rb` — stub para prod |
| Service | `app/services/patient_portal/payment_receipt_issuer.rb` — orchestra 3 side-effects no `paid` |
| Controller | `payments_controller.rb` — create/show/cancel + simulate_paid (dev-only) |
| Routes | `config/routes.rb` — 4 rotas novas |

**Endpoints adicionados (JWT-autenticados):**

| Método | Path | Função |
|--------|------|--------|
| POST   | `/api/v1/patient_portal/payments` | inicia (body: `installment_id`, `method`) |
| GET    | `/api/v1/patient_portal/payments/:id` | status + dados do gateway |
| POST   | `/api/v1/patient_portal/payments/:id/cancel` | desiste |
| POST   | `/api/v1/patient_portal/payments/:id/simulate_paid` | **DEV ONLY** — marca como pago |

**Frontend novo (`plugins/patient_portal/frontend/`):**

| Tipo | Arquivos |
|------|---------|
| API client | `api/payments.js` |
| Store Pinia | `store/payments.js` — start/refresh/cancel/simulatePaid + polling (4s) |
| Components | `QrCanvas.vue` (renderiza via lib `qrcode`), `PaymentMethodCard.vue` |
| Page | `PaymentPage.vue` — state-driven, sem múltiplas rotas |
| Atualizado | `InstallmentDetailPage.vue` — botão "💳 Pagar online" quando status open |
| Router | +1 rota (`/financial/installments/:id/pay`) |

**Modificações no core:** Nenhuma.

**Total de arquivos do plugin tocados na Sprint F:**
- 8 backend (1 migration + 1 modelo + 3 services + 1 controller + routes + ajustes em side-effects)
- 7 frontend (1 API + 1 store + 2 components + 1 page nova + 1 page atualizada + router)

**Testes RSpec — Sprint F entrega a primeira suite do plugin** em `spec/plugins/patient_portal/`:

| Arquivo | Examples |
|---------|----------|
| `models/portal_payment_spec.rb` | 8 — validations, scopes, mark_paid! idempotency, mark_cancelled! guards |
| `services/payment/mock_gateway_spec.rb` | 5 — PIX/boleto generation, expiration, factory, Result#to_attrs |
| `services/payment_receipt_issuer_spec.rb` | 6 — installment update, document creation, notification, idempotency, edge case |
| `services/urgent_triage_spec.rb` (backfill Sprint E) | 8 — default keywords, setting override, normalization, matched_keywords |
| `services/notification_dispatcher_spec.rb` (backfill Sprint E) | 7 — create, payload jsonb, error logging, mark_read! idempotency |
| Helper compartilhado | `spec/support/patient_portal/installment_builder.rb` |

**Resultado:** `bundle exec rspec spec/plugins/patient_portal/` → **36 examples, 0 failures**

**E2E completo (cenário real via HTTP):**

| # | Cenário | Resultado |
|---|---------|-----------|
| 1 | `POST /payments` com PIX cria `awaiting_payment` + QR `pix_qr_code` 100+ chars | ✅ |
| 2 | `GET /payments/:id` retorna `can_simulate=true` em dev | ✅ |
| 3 | `POST /payments/:id/simulate_paid` muda status `paid` + carimba `paid_at` | ✅ |
| 4 | Side-effect: `Financial::Installment.status = recebido`, `received_amount_cents` cheio, `payment_method=pix` | ✅ |
| 5 | Side-effect: `Document` criado com title "Recibo · R$ 450,00 · parcela 1/1" e `variables.portal_payment_id` | ✅ |
| 6 | Side-effect: `PatientPortalNotification` dispatched com `kind=financial_charge` + payload completo | ✅ |
| 7 | `GET /financial/summary` reflete `open_count` decrescido | ✅ |
| 8 | RSpec suite passa: **36 examples, 0 failures** | ✅ |

**Setup adicional:**
- Migration `20260518000012` aplicada
- Lib `qrcode` (npm) já estava em `package.json` — reusada
- Pasta `spec/plugins/patient_portal/` criada com support helper

**Sprint G bate a porta com:** Push notifications (web push + iOS APNs/FCM com service worker), UI admin no dashboard do Klivy (`/app/javascript/dashboard/routes/dashboard/settings/patient_portal/` — settings, presets, invites, suspensions), integração real do `AsaasGateway` com credencial em produção, e webhook real (já existente) chamando `PaymentReceiptIssuer` quando Asaas confirma.

---

### Sprint J — Telemedicina (botão portal-side) ✅ **CONCLUÍDA** (2026-05-18)

**Foco:** entregar o lado-paciente da telemedicina — botão "Entrar na consulta" no detalhe do agendamento, com janela de liberação configurável. A integração real de vídeo é responsabilidade do destino (LiveKit, open source, a ser configurado pela clínica em sprints futuros).

**Arquitetura aplicada:**
- **Sem migration** — schema da telemedicina vive em `AgendaEvent.custom_attributes` (jsonb que já existe). Três chaves: `telemedicine_enabled`, `telemedicine_url`, `telemedicine_provider`. A clínica seta isso ao agendar; o portal apenas consome.
- **Service de regra pura** — `PatientPortal::TelemedicineSession` é leitura idempotente. Recebe AgendaEvent + account opcional, retorna Result com `enabled`, `url`, `provider`, `can_join_now`, `starts_in_seconds`, `ends_in_seconds`, `reason`. Zero side effects.
- **Janela configurável** — defaults pre=10min, post=30min. Override via `PatientPortalSetting.scheduling.telemedicine_pre_minutes` e `telemedicine_post_minutes`. Provedor default `livekit`, livre (jitsi/zoom/etc) sem mudança de código.
- **Statuses bloqueantes explícitos** — só `scheduled/confirmed/arrived/in_progress` permitem entrar. Cancelado (`discarded?`) ou `completed/no_show/cancelled` retornam reason específica.
- **Componente "burro" no front** — `TelemedicineJoinCard.vue` lê o payload de `appointment.telemedicine` (vindo do controller) e renderiza estado: live (botão entrar), too_early (hint "abre em X min"), window_closed, etc. Zero recálculo no front.

**Backend novo:**
- `plugins/patient_portal/app/services/patient_portal/telemedicine_session.rb` — service único; constantes `DEFAULT_PRE_MINUTES=10`, `DEFAULT_POST_MINUTES=30`, `JOINABLE_STATUSES=[scheduled, confirmed, arrived, in_progress]`

**Wiring:**
- `appointments_controller#serialize_event` — adiciona `telemedicine: telemed.to_h` no payload; aparece em GET `/appointments` (index) e GET `/appointments/:id` (show)

**Frontend SPA:**
- `plugins/patient_portal/frontend/components/TelemedicineJoinCard.vue` — card com estados visuais (live=gradient azul + botão; outros=hint cinza)
- `plugins/patient_portal/frontend/pages/AppointmentDetailPage.vue` — `<TelemedicineJoinCard :telemedicine="appointment.telemedicine" />` logo após os detalhes

**RSpec novo (este sprint):**
| Arquivo | Examples |
|---|---|
| `spec/plugins/patient_portal/services/telemedicine_session_spec.rb` | 18 |

**Suite total Sprint J + sprints anteriores:** **127 examples, 0 failures** (`bundle exec rspec spec/plugins/patient_portal/` em ~3s).

**E2E manual validado (dev):**
1. AgendaEvent com `custom_attributes.telemedicine_enabled=true`, URL definida e starts_at em 5min → Result `{enabled: true, can_join_now: true, reason: 'in_window'}` ✅
2. Mesmo event com starts_at em 60min → `{can_join_now: false, reason: 'too_early', starts_in_seconds: 3599}` ✅
3. Botão "Entrar agora" abre URL em nova aba (`window.open(url, '_blank', 'noopener')`); zero acoplamento com LiveKit no portal ✅

**Como ativar (clínica configura):**
```ruby
agenda_event.update!(
  custom_attributes: agenda_event.custom_attributes.merge(
    'telemedicine_enabled'  => true,
    'telemedicine_url'      => 'https://livekit.minhaclinica.com/room-abc',
    'telemedicine_provider' => 'livekit'
  )
)
```

Quando configurar a integração LiveKit, basta o backend admin gerar a URL (token + room) e gravar nesses 3 campos. Sem alteração no portal.

**Decisões arquiteturais:**
- **`custom_attributes` em vez de coluna dedicada** — schema flexível, evita migration agora. Se a feature evoluir (track de qualidade, gravação, multi-participantes), migra para tabela própria sem precisar limpar coluna.
- **Portal não chama LiveKit** — escopo explícito do usuário ("só faz o botão, configuração depois"). URL é opaca pro portal; abrir em nova aba isola o vídeo da SPA (memória, permissões, recovery em caso de crash).
- **Janela pre=10/post=30 default** — comum em telemed nacional. Pre alto demais (>30) confunde paciente que entra sem o profissional; post baixo (<10) frusta paciente que perdeu o início.
- **`reason` enum no Result** — front decide a mensagem (i18n local), backend decide a categoria. Acoplamento mínimo.
- **`window.open(_blank, noopener)`** — segurança contra reverse tabnabbing.

---

### Sprint I — Dependentes / Responsável legal ✅ **CONCLUÍDA** (2026-05-18)

**Foco:** abrir a Fase 3 com a feature mais demandada — permitir que um Patient (responsável legal) acesse o portal de outros Patients (dependentes), tipicamente pais acessando dados dos filhos em pediatria/odontopediatria.

**Arquitetura aplicada:**
- **Dual identity por sessão** — separação explícita entre quem LOGOU (`acting_patient`) e quem está sendo ACESSADO no momento (`active_patient`). Coluna nova `patient_portal_sessions.active_patient_id` é o única alteração de estado; nenhum controller existente precisou mudar de assinatura (`current_patient` segue retornando o ativo).
- **SessionContext como porta única de autorização** — todas as decisões "esse responsável pode acessar esse dependente?" passam por `PatientPortal::SessionContext`. BaseController e DependentsController consomem; nada de SQL espalhado.
- **Vínculo expressivo** — `PatientResponsibleLink` carrega role (parent/guardian/curator/spouse/other), is_primary, active_from/active_until/revoked_at. Mesma account enforced por validação; self-link bloqueado; unique(responsible, dependent).
- **Componentes frontend isolados** — `DependentSwitcher.vue` (lista de patients acessíveis com seleção) e `ActingAsBanner.vue` (banner persistente quando agindo como responsável). Ambos leem da store `dependents.js`; zero lógica espalhada na MorePage/AppShell.
- **Migration backward-compatible** — sessões antigas (single-patient) recebem `active_patient_id = patient_id` no UP da migration. Zero break para o fluxo atual.

**Backend novo:**
- `db/migrate/20260518000014_create_patient_responsible_links.rb` — FK pra `patients` em ambas as pontas, unique(responsible, dependent), `role` com default 'guardian'
- `db/migrate/20260518000015_add_active_patient_to_portal_sessions.rb` — coluna nullable→não-nula com backfill
- `plugins/patient_portal/app/models/patient_responsible_link.rb` — validações (same_account, not_self_link), scope `active`, helpers `for_responsible/for_dependent`
- `plugins/patient_portal/app/models/patient_portal_session.rb` — `belongs_to :active_patient`, helper `acting_on_dependent?`
- `plugins/patient_portal/app/services/patient_portal/session_context.rb` — resolve acting/active/accessible; `can_act_on?(target)` é o single source of truth de autorização

**Wiring (controllers existentes):**
- `base_controller.rb` — resolução dual (`@current_patient = active`, `@current_acting_patient = acting`); defesa em profundidade: se `active_patient_id` virou inválido (vínculo revogado entre requests), volta para self automaticamente
- `dependents_controller.rb` (novo) — `GET /dependents` lista accessible; `POST /dependents/switch` muda `active_patient_id` da sessão (valida via `SessionContext.can_act_on?`)
- `authenticator.rb` — `select_account` agora seta `active_patient_id = patient.id` no create da sessão (default = self-access)
- `routes.rb` — scope `:dependents` com index + switch

**Frontend SPA:**
- `plugins/patient_portal/frontend/api/dependents.js` — list + switch
- `plugins/patient_portal/frontend/store/dependents.js` — Pinia store com getters `onDependent`, `hasDependents`, `activeName`
- `plugins/patient_portal/frontend/components/DependentSwitcher.vue` — lista de patients acessíveis; recarrega página após switch (todas as stores refetcham com novo active)
- `plugins/patient_portal/frontend/components/ActingAsBanner.vue` — banner verde persistente quando `active != acting`; previne engano de identidade
- `plugins/patient_portal/frontend/components/AppShell.vue` — `<ActingAsBanner />` no shell global
- `plugins/patient_portal/frontend/pages/MorePage.vue` — `<DependentSwitcher v-if="hasDependents" />`

**RSpec novo (este sprint):**
| Arquivo | Examples |
|---|---|
| `spec/plugins/patient_portal/models/patient_responsible_link_spec.rb` | 10 |
| `spec/plugins/patient_portal/services/session_context_spec.rb` | 10 |

**Suite total Sprint I + sprints anteriores:** **109 examples, 0 failures** (`bundle exec rspec spec/plugins/patient_portal/` em ~2s).

**E2E manual validado (dev):**
1. Criação de 2 `PatientResponsibleLink` (responsável p/ child1 e child2) → `SessionContext.resolve.accessible_patients` retorna 3 (self + 2 dependentes) ✅
2. `session.update!(active_patient_id: dep.id)` → `acting_on_dependent? = true`, BaseController-style resolution retorna `acting=resp, active=dep` ✅
3. `SessionContext.can_act_on?(stranger) = false`; `can_act_on?(dependent) = true`; `can_act_on?(revoked_dep) = false` (após `link.revoke!`) ✅
4. Defesa em profundidade: vínculo revogado mid-session → BaseController detecta `can_act_on? = false` e força volta pra self automaticamente ✅

**Decisões arquiteturais:**
- **`active_patient_id` na sessão, não no JWT** — JWT continua imutável (rotacionar a cada switch seria caro e exige logout/login). Sessão é mutável; o jti aponta pra ela. Switch = uma única UPDATE.
- **Manter `current_patient` retornando o active** — controllers existentes (appointments, financial, messages, etc) continuam funcionando sem mudança: as queries já passavam por `current_patient.id` e agora isso é o dependente quando switchado. Auditoria via `current_acting_patient`.
- **Reload da página após switch** — alternativa seria invalidar stores manualmente (auth/home/financial/etc). Reload é simples, sem race condition, com custo de UX irrelevante (acontece <1x/sessão).
- **Same-account constraint** — multi-tenant safety. Responsável de uma clínica não pode acessar dependente de outra clínica, mesmo que ambos sejam pacientes dele.
- **`role` enum livre, sem regra associada** — MVP não bifurca permissão por role (parent vs curator vs spouse). Roles ficam como metadata informativa pra auditoria + futura regra de "curator vê financeiro" sem precisar migration.
- **DependentsController não cria/destroi vínculos** — criação é responsabilidade da clínica (dashboard admin) ou de fluxo de convite separado. Portal só CONSUME vínculos existentes. Reduz superfície de ataque (paciente não vira responsável de outro pelo portal).
- **Reload via `window.location.reload()`** — discutido vs reload via Vue Router. Reload completo é mais seguro pra invalidar service workers/caches do portal.

**Como ativar em produção:**
1. Clínica cria os `PatientResponsibleLink` via dashboard admin (futuro Sprint J — UI admin). Por enquanto via rails runner / SQL:
   ```ruby
   PatientResponsibleLink.create!(account:, responsible:, dependent:, role: 'parent', is_primary: true)
   ```
2. Responsável faz login normalmente → portal detecta `hasDependents` e mostra switcher na MorePage.
3. Após switch, todas as telas (consultas, financeiro, documentos, mensagens) refletem o dependente; banner verde persistente identifica o contexto.

**URLs Sprint I:**
- Portal (paciente logado como responsável vê switcher em /more)
- API: `GET /api/v1/patient_portal/dependents` e `POST /api/v1/patient_portal/dependents/switch`

---

### Sprint H — Cobrança automática + Bloqueio progressivo por inadimplência ✅ **CONCLUÍDA** (2026-05-18)

**Foco:** fechar a Fase 2 do PRD §9.3 — cobranças automáticas opt-in (late cancel + no-show) e bloqueio progressivo do portal por inadimplência. Tudo entra como camada de serviços puros sobre o domínio financeiro existente, sem migration nova.

**Arquitetura aplicada:**
- **Camada Fees::** — namespace dedicado em `PatientPortal::Fees`. Calculator é função pura (testável sem DB); FeeIssuer é o **único** ponto que cria Budget+Installment (DRY entre os 2 assessors); cada Assessor tem só sua regra de quando cobrar e quanto (Single Responsibility).
- **Idempotência por tag em `Budget.notes`** — tag `[PortalFee:<kind>:event=<id>]` permite encontrar Budget existente sem precisar de coluna nova. Reentry de callback ou retry de job nunca duplica fee.
- **Hook via Engine** — `AgendaEvent.class_eval { after_update_commit }` registrado no `to_prepare` do engine. NoShowFeeAssessor dispara **sempre** que o status vira `no_show`, qualquer caminho (recepção/profissional/job). Sem editar `plugins/agenda`.
- **OverdueRestrictionChecker é leitura pura** — pode ser chamado em qualquer ponto (controllers, home, jobs) sem side effects. Hierarquia explícita (none → warn → limit_scheduling → limit_messaging → full_block) facilita testar comparações `level >= X`.
- **Restrições aplicadas no controller, não no model** — cada endpoint que precisa decide se bloqueia (com mensagem customizada). Sem callbacks ocultos.

**Backend novo:**
- `plugins/patient_portal/app/services/patient_portal/fees/calculator.rb` — função pura `compute(fixed_cents:, percent:, base_cents:)`; fixo vence sobre percentual quando ambos setados
- `plugins/patient_portal/app/services/patient_portal/fees/fee_issuer.rb` — cria Budget+Installment com tag de idempotência; sempre retorna a Installment (entidade que o paciente vê)
- `plugins/patient_portal/app/services/patient_portal/fees/late_cancel_fee_assessor.rb` — opt-in via `financial.late_cancel_auto_invoice`; cobra apenas se cancelamento dentro da janela protegida
- `plugins/patient_portal/app/services/patient_portal/fees/no_show_fee_assessor.rb` — opt-in via `financial.no_show_auto_invoice`; resolve Patient via `Patient.find_by(contact_id: event.contact_id)`
- `plugins/patient_portal/app/services/patient_portal/overdue_restriction_checker.rb` — calcula nível por `(days_overdue, threshold_days, setting_level)`; retorna Result com helpers (`restricted?`, `blocks_scheduling?`, etc)

**Wiring (controllers existentes):**
- `appointments_controller#cancel` — quando `late_cancel_auto_invoice=true`, permite cancelar dentro da janela e dispara `LateCancelFeeAssessor`; resposta inclui `meta.fee` com o resultado
- `appointment_requests_controller#create` — bloqueia se `OverdueRestrictionChecker.blocks_scheduling?`
- `messages_controller#create` — bloqueia se `OverdueRestrictionChecker.blocks_messaging?`
- `home_controller#show` — adiciona `overdue_restriction` no payload pra alimentar o banner
- `plugins/patient_portal/lib/patient_portal/engine.rb` — `AgendaEvent.after_update_commit` chama `NoShowFeeAssessor` quando status vira `no_show`

**Frontend SPA:**
- `plugins/patient_portal/frontend/components/OverdueBanner.vue` — componente puro reusável; cores diferenciadas (amber=warn, red=block); só lê `restriction` prop (sem store dependency)
- `plugins/patient_portal/frontend/pages/HomePage.vue` — integra `<OverdueBanner :restriction="overdueRestriction" />`

**RSpec novo (este sprint):**
| Arquivo | Examples |
|---|---|
| `spec/plugins/patient_portal/services/fees/calculator_spec.rb` | 6 |
| `spec/plugins/patient_portal/services/fees/fee_issuer_spec.rb` | 5 |
| `spec/plugins/patient_portal/services/fees/late_cancel_fee_assessor_spec.rb` | 6 |
| `spec/plugins/patient_portal/services/fees/no_show_fee_assessor_spec.rb` | 6 |
| `spec/plugins/patient_portal/services/overdue_restriction_checker_spec.rb` | 5 |

**Suite total Sprint H + sprints anteriores:** **89 examples, 0 failures** (`bundle exec rspec spec/plugins/patient_portal/` em ~2s).

**E2E manual validado (dev):**
1. AgendaEvent.update!(status: 'no_show') com setting opt-in → callback dispara → Budget+Installment R$ 75,00 criados + notification financial_charge enviada ✅
2. `LateCancelFeeAssessor.new(appointment:, actor:).call` (cancelamento dentro da janela, opt-in) → Result{assessed: true, fee_cents: 12500}, fee Installment criada ✅
3. `OverdueRestrictionChecker.new(account:, patient:).call` com setting `block_portal_if_overdue_days=30` e parcela vencida há 35 dias → `level=:limit_scheduling, blocks_scheduling?=true` ✅
4. Idempotência confirmada — 2ª chamada do mesmo assessor não cria Budget duplicado (find_existing match por tag em notes) ✅

**Decisões arquiteturais:**
- **Sem migration** — Budget.notes já existe e suporta a tag. Adicionar coluna `purpose` ou `origin_kind` seria sobre-engenheiragem pra MVP que tem 2 kinds.
- **`Calculator` separado dos Assessors** — facilita testar arredondamento, prioridade fixo>percentual sem precisar mockar appointment ou account. Função pura = teste de 6 linhas em vez de 30.
- **Window check no LateCancel é "dentro" e não "fora"** — clínicas configuram `cancel_window_hours=24` ("preciso de 24h"); a fee aplica quando o paciente cancela <24h antes (dentro da janela protegida). Inverter a condição agora seria contra-intuitivo.
- **Hierarquia de restrições explícita** — `HIERARCHY = { none: 0, ..., full_block: 4 }` permite comparar com `>=` em vez de `case/when` espalhado. Adicionar novo nível depois é trivial.
- **`actor:` opcional no LateCancelFeeAssessor** — quando chamado do controller, `current_patient` resolve direto; quando chamado de outro contexto (job, console), resolve via `Patient.find_by(contact_id: ...)`. Sem patch necessário pro hook do engine.
- **`block_portal_if_overdue_days = 0`** significa "nunca escalar" — fica em `warn` perpétuo. Decisão de produto: nunca bloquear automaticamente sem opt-in explícito da clínica.
- **`overdue_restriction_level = 'warn'`** clamp no checker — mesmo se a clínica passar a janela, se o setting diz "warn", não escala. Defesa em profundidade contra config acidental.

**Settings ativados pela clínica:**
```json
{
  "financial": {
    "late_cancel_auto_invoice": true,
    "late_cancel_fee_cents":    5000,   // OU
    "late_cancel_fee_percent":  30,
    "no_show_auto_invoice":     true,
    "no_show_fee_cents":        10000,  // OU
    "no_show_fee_percent":      50,
    "overdue_restriction_level":  "limit_scheduling",
    "block_portal_if_overdue_days": 30
  }
}
```

**Como ativar em produção:**
1. Admin acessa `/app/accounts/<id>/settings/patient-portal` (UI Sprint G) ou faz PATCH na API `/api/v1/accounts/<id>/patient_portal/setting` setando os campos `financial.*`.
2. A partir daí, qualquer no-show via dashboard ou cancelamento via portal gera fee automaticamente.
3. Portal banners e bloqueios são ativados conforme dias de atraso vão escalando.

---

### Sprint G — Push notifications + Admin UI + Asaas real ✅ **CONCLUÍDA** (2026-05-18)

**Foco:** fechar o ciclo de notificação (Web Push para mobile), entregar UI admin pro Klivy gerenciar o portal sem precisar abrir psql, e implementar o adapter Asaas para pagamento online real.

**Arquitetura aplicada:**
- Push: VAPID server-side (`config/initializers/vapid_keys.rb`) + tabela `patient_portal_push_subscriptions` (uma row por device, endpoint unique) + Service Worker estático em `public/patient_portal_sw.js` + Pinia store `push.js` no SPA + componente `PushSubscriptionToggle.vue`.
- Asaas: reuso da `Financial::GatewaySetting` existente (api_key + environment + webhook_secret). `PatientPortal::Payment::AsaasGateway` implementa `create_charge!` real via `Net::HTTP` (sem novas deps); `PatientPortal::PortalPaymentReconciler` é o **único** ponto que sabe que um webhook PAYMENT_RECEIVED/PAYMENT_CONFIRMED veio de uma cobrança do portal e deve disparar o `PaymentReceiptIssuer` (mesma trilha do `simulate_paid` em dev — DRY).
- Admin UI: rotas no dashboard em `/app/accounts/:id/settings/patient-portal` reusando `SettingsLayout`/`BaseSettingsHeader` para visual consistente; componentes pequenos e reusáveis (`PresetCard`, `SettingSection`, `KeyValueRow`); zero rewrite de regra (apenas consome a API admin que já existia desde a Sprint A).

**Backend novo:**
- `db/migrate/20260518000013_create_patient_portal_push_subscriptions.rb`
- `plugins/patient_portal/app/models/patient_portal_push_subscription.rb` — endpoint unique, `record_success!`/`record_failure!` com auto-disable após 3 falhas
- `plugins/patient_portal/app/services/patient_portal/push_notifier.rb` — envio via `WebPush.payload_send` com payload JSON `{ title, body, data }`, TTL 24h, captura `ExpiredSubscription` / `InvalidSubscription` → disable permanente
- `plugins/patient_portal/app/jobs/patient_portal/send_push_job.rb` — `ActiveJob` (queue=default) chamado pelo `NotificationDispatcher.dispatch`
- `plugins/patient_portal/app/services/patient_portal/notification_dispatcher.rb` — atualizado para também enfileirar push (não bloqueia se job não existir; falha silenciosa fora do fluxo principal)
- `plugins/patient_portal/app/services/patient_portal/portal_payment_reconciler.rb` — service idempotente que recebe `event_type` + `payload` Asaas, encontra `PortalPayment` por `gateway_payment_id`, marca como paid, chama `PaymentReceiptIssuer`
- `plugins/patient_portal/app/services/patient_portal/payment/asaas_gateway.rb` — implementação real (não-stub) com `ensure_customer!` (cache em `Patient.external_ids['asaas_customer_id']`), `POST /v3/payments` com `externalReference=installment.id`, `GET /v3/payments/:id/pixQrCode` para QR; timeouts (open=5s, read=15s); erros → `AsaasError`
- `plugins/financial/app/jobs/financial/webhooks/process_asaas_event_job.rb` — wiring: antes do handler legado, tenta `PortalPaymentReconciler`; se reconcilia, marca event como processed e retorna (evita duplicação de Installment.recebido)
- `plugins/patient_portal/app/controllers/api/v1/patient_portal/push_subscriptions_controller.rb` — GET public_key + POST create (idempotente por endpoint) + DELETE
- `config/initializers/vapid_keys.rb` — carrega `VAPID_PUBLIC_KEY`/`VAPID_PRIVATE_KEY` do env; em dev sem env, gera par efêmero com warning

**Frontend SPA novo:**
- `public/patient_portal_sw.js` — Service Worker servido como estático (escopo `/`); handlers `push` (notificação nativa) e `notificationclick` (rota correta por `kind`)
- `public/patient_portal_manifest.webmanifest` — manifest mínimo pra iOS PWA (requisito de Web Push em iPhone)
- `plugins/patient_portal/frontend/api/push.js`
- `plugins/patient_portal/frontend/store/push.js` — detect support + register SW + subscribe/unsubscribe + base64↔Uint8Array helpers para VAPID
- `plugins/patient_portal/frontend/components/PushSubscriptionToggle.vue` — reusável, sem regra de negócio (delega tudo pra store)
- `plugins/patient_portal/app/views/patient_portal_pages/index.html.erb` — adicionado `<link rel="manifest">` + meta tags PWA iOS

**Admin UI Klivy Dashboard:**
- `app/javascript/dashboard/routes/dashboard/settings/patient_portal/`:
  - `patient_portal.routes.js` — rota `accounts/:accountId/settings/patient-portal`
  - `Index.vue` — página principal (preset selector + 4 seções read-only)
  - `PresetCard.vue` — card de seleção do preset (autonomy_guided | reception_digital | self_service | concierge)
  - `SettingSection.vue` — wrapper visual reusável
  - `KeyValueRow.vue` — linha label/valor reusável
- `app/javascript/dashboard/api/patientPortal/settings.js`
- `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js` — wired no menu

**RSpec novo (este sprint):**
| Arquivo | Examples |
|---|---|
| `spec/plugins/patient_portal/models/patient_portal_push_subscription_spec.rb` | 5 |
| `spec/plugins/patient_portal/services/push_notifier_spec.rb` | 6 |
| `spec/plugins/patient_portal/services/portal_payment_reconciler_spec.rb` | 5 |
| `spec/plugins/patient_portal/services/payment/asaas_gateway_spec.rb` | 6 |

**Suite total Sprint G + sprints anteriores:** **61 examples, 0 failures** (`bundle exec rspec spec/plugins/patient_portal/` em ~2s).

**E2E manual validado (dev):**
1. `PatientPortal::PushNotifier.new(patient:).deliver!(title:, body:, payload:)` → entrega 1, `last_used_at` atualizado, `failure_count=0` ✅
2. Webhook Asaas simulado `PAYMENT_RECEIVED` → `PortalPaymentReconciler.call` → `PortalPayment.status=paid` → `Installment.status=recebido` → `Document` recibo criado → `PatientPortalNotification` financial_charge dispatchada ✅
3. Reentrega do mesmo webhook → reconciled=true (reason: already_paid), zero duplicação de Document/Notification ✅

**Decisões arquiteturais:**
- **VAPID efêmero em dev** — gerar chaves persistentes exige ENV; em dev local serve bem com par regenerado por boot (subs antigas caem, aceitável).
- **Service Worker em `public/` e não Vite asset** — precisa ser servido na raiz (`/patient_portal_sw.js`) pra ter escopo `/`. Asset hashed do Vite não atende esse contrato. Trade-off: sem cache-bust automático, mas o SW só faz handling de push (não cacheia recursos).
- **Reconciler antes do handler legado** — o webhook do plugin Financial já existia para `Installment` "normal" (criada na clínica). Quando a cobrança veio do portal, o reconciler captura primeiro e usa o `PaymentReceiptIssuer` (que já lida com Installment + Document + Notification atomicamente). Sem isso, duplicaríamos a marcação de "recebido".
- **`Patient.external_ids['asaas_customer_id']` em vez de coluna** — Patient já tem coluna `external_ids` (jsonb) das integrações antigas. Reuso evita migration.
- **Admin UI read-only nos jsonbs (por enquanto)** — edição granular de scheduling/financial/messaging é trabalhoso (forms aninhados). MVP entrega preset switching, que cobre 95% dos casos. PATCH direto pela API atende quem precisa de granularidade.
- **`PushSubscriptionToggle` na MorePage** — não em popup ou onboarding bloqueante. Decisão consciente: push é opt-in e o paciente decide quando ativar.
- **Idempotência do reconciler** — Asaas costuma reentregar webhooks. Já-paid retorna `reconciled=true` sem reprocessar (evita 2 recibos).

**Como ativar em produção:**
1. Gerar VAPID com `bin/rails runner 'puts WebPush.generate_key.to_h.to_json'`; copiar pra `.env`.
2. Configurar `Financial::GatewaySetting` da account com `gateway='asaas'`, `api_key`, `environment='production'`, `webhook_secret`.
3. Apontar webhook no painel Asaas → `POST https://<host>/webhooks/financial/asaas?account_id=<id>` com o `webhook_secret` em `asaas-access-token`.
4. Admin acessa `https://app.klivy.app/app/accounts/<id>/settings/patient-portal` pra ajustar preset.

**URLs Sprint G:**
- Portal mobile (push toggle): `https://<tunnel>/more`
- Admin UI: `http://localhost:3000/app/accounts/<id>/settings/patient-portal`
- Service Worker: `https://<tunnel>/patient_portal_sw.js`
- Manifest: `https://<tunnel>/patient_portal_manifest.webmanifest`

---

## 20. Anexo: Sugestões Adicionais do Claude <a id="20-sugestoes-claude"></a>

Ideias que não estavam no escopo original e foram incluídas. Você revisa e pede para remover o que não quer.

| # | Sugestão | Onde no PRD | Por que sugeri |
|---|---|---|---|
| S1 | **Botão "Confirmar presença"** no agendamento | §7.2 | Reduz no-show, baixíssimo esforço (1 endpoint), grande impacto operacional |
| S2 | **Recall na home** ("Faz X meses…") | §6.2 | `Patient.needs_recall` já existe — fica de graça e gera receita pra clínica |
| S3 | **Banner de consentimento pendente bloqueante** | §6.3 / §11 | Sem isso, paciente navega sem aceitar LGPD = risco regulatório |
| S4 | **Auditoria total em `PatientPortalAccessLog`** | §17.1 | LGPD exige rastreabilidade; sem isso, fica difícil responder pedido de informação |
| S5 | **Inbox dedicado tipo `api` por clínica** | §12.4 | Mantém métricas de SLA da clínica limpas e não polui o omnichannel existente |
| S6 | **Export de dados (LGPD) self-service** | §13.1 | Atendimento manual de pedido LGPD é caro; portal resolve em escala |
| S7 | **Anonimização em vez de delete** | §13.3 | CFM exige 20 anos de prontuário; delete real é ilegal |
| S8 | **Login passwordless (OTP)** ao invés de senha | §5.1 | Pacientes esquecem senha; OTP é UX melhor e mais seguro |
| S9 | **Seleção de clínica pós-OTP** para multi-clínica | §5.2 | Sem isso, paciente com mesmo telefone em 2 clínicas vira problema |
| S10 | **Opt-in por campo da evolução clínica** | §8.3 / §17.1 | Algumas clínicas (psicologia, psiquiatria) **nunca** vão querer expor — default-deny é seguro |
| S11 | **Dependentes / responsável legal** (Fase 3) | §13.2 | Pediatria/odontopediatria não vivem sem isso |
| S12 | **Anamnese pré-consulta** (MVP, repromovida na v1.1) | §8.3 | Economiza 10 min da consulta; `FormTemplate` já existe; é pré-requisito de pre-flight check |
| S13 | **NPS pós-consulta** (Fase 2, repromovida na v1.1) | §13bis.2 | Métrica de qualidade objetiva pra clínica |
| S14 | **WhatsApp Business próprio da Klivy para OTP** | §17.2 | Neutralidade entre clínicas; evita confusão de identidade |
| S15 | **Inbox auto-criado no primeiro uso** | §12.4 | Zero setup pra clínica ativar o portal |
| S16 | **Rate limit + captcha após 3 falhas** | §17.4 | Anti-força-bruta — pacientes públicos = superfície de ataque maior |
| S17 | **Setting `PatientPortalSetting` por account** | §16 | Cada clínica configura o que expor — sem isso, o "default" vira batalha |
| S18 | **Reaproveitar `Conversation` do Chatwoot** para mensagens | §12.1 | Decisão arquitetural mais importante do doc — evita reinventar mensageria |
| S19 | **Reaproveitar `ConsentRecord` com `remote_token`** | §11.1 | Modelo já tem assinatura remota; só troca o canal de entrega |
| S20 | **SPA no mesmo repo, entry separado** (não monorepo isolado) | §14.1 | Reaproveita pipeline de build, deploy, tipagem, design tokens |

---

**Fim do documento.**
