# PRD — BeClinic Platform
## Product Requirements Document (v1.1)

**Produto:** BeClinic (KlivyApp)
**Base:** Chatwoot (comunicacao omnichannel)
**Escopo deste documento:** Exclusivamente modulos customizados, adicionados sobre o core do Chatwoot.
**Data:** Maio 2026 (atualizado 2026-05-07)

---

## Indice

1. [Visao Executiva](#1-visao-executiva)
2. [Modulo: Agenda (Calendario Clinico)](#2-modulo-agenda-calendario-clinico)
3. [Modulo: Pacientes (Prontuario Clinico)](#3-modulo-pacientes-prontuario-clinico)
4. [Modulo: Financeiro Central](#4-modulo-financeiro-central)
5. [Modulo: Configuracoes do Sistema](#5-modulo-configuracoes-do-sistema)
6. [Modulo: Bea (Assistente Virtual com IA)](#6-modulo-bea-assistente-virtual-com-ia)
7. [Integracao entre Modulos](#7-integracao-entre-modulos)
8. [Visao de Produto](#8-visao-de-produto)
9. [Mudanças no Core (auditoria)](#9-mudanças-no-core-registro-de-auditoria)

---

## 1. Visao Executiva

BeClinic eh uma plataforma SaaS de gestao clinica construida como extensao plugavel sobre a infraestrutura do Chatwoot. O sistema adiciona quatro verticais fundamentais para operacao de clinicas: agendamento de consultas, prontuario eletronico do paciente, gestao financeira completa e configuracoes especializadas. Todos os modulos operam de forma isolada do core de comunicacao, sem alterar funcionalidades nativas.

A arquitetura segue o principio de composicao: cada modulo eh auto-contido (models, controllers, services, jobs, frontend) e se relaciona com os demais atraves de chaves estrangeiras e servicos de sincronizacao explicitos.

---

## 2. Modulo: Agenda (Calendario Clinico)

### 2.1 Visao Geral

Sistema de agendamento visual com calendario interativo que opera como produto independente dentro da plataforma. Oferece visualizacoes por mes, semana e dia, agendamento publico via link compartilhavel, lista de espera, regras de notificacao configuráveis e atributos customizados.

### 2.2 Problema que Resolve

Clinicas dependem de agendas em papel, planilhas ou ferramentas desconectadas do sistema de comunicacao e prontuario. Isso causa faltas nao gerenciadas, notificacoes manuais, dupla entrada de dados e ausencia de visibilidade operacional.

### 2.3 Publico-Alvo

- **Recepcionistas:** Criam, movem e cancelam eventos no calendario.
- **Profissionais de saude:** Visualizam sua agenda diaria, confirmam atendimentos.
- **Gestores:** Acompanham metricas de ocupacao, faltas e produtividade.
- **Pacientes (externo):** Realizam auto-agendamento via link publico.

### 2.4 Funcionalidades Principais

| Funcionalidade | Descricao |
|---|---|
| Calendario visual | Visualizacoes mes, semana e dia com drag-and-drop |
| Eventos de agenda | CRUD completo com status: scheduled, confirmed, arrived, in_progress, completed, cancelled, no_show |
| Tipos de evento | Suporte a appointment (padrao) e extensivel |
| Servicos da clinica | Catalogo de servicos com duracao, preco e cor |
| Atributos customizados | Campos extras (text, textarea, select, date, phone, cpf, rg) configuráveis por conta |
| Notificacoes automaticas | Regras configuráveis: reminder, confirmation, followup, birthday, custom |
| Log de notificacoes | Registro de envio (sent, failed, skipped) por evento e regra |
| Agendamento online | Pagina publica por profissional com link unico (agenda_public_id) |
| Lista de espera | Entradas por contato com periodo preferido (manha, tarde, noite) |
| Template de mensagem | Mensagens com variaveis para envio via WhatsApp/inbox |
| Configuracoes de horario | Dias da semana, intervalos de slot (15/30/60 min), almoço |
| Relatorios de agenda | Endpoint dedicado com analytics de agendamentos |

### 2.5 Fluxos do Usuario

**Agendamento interno:**
1. Recepcionista acessa a agenda (rota `/accounts/:id/agenda`).
2. Seleciona data e horario no calendario.
3. Preenche titulo, paciente (contact), profissional, servico e atributos customizados.
4. Evento eh criado com status `scheduled`.
5. Callbacks disparam notificacoes de confirmacao automaticamente.
6. No dia, status evolui: confirmed -> arrived -> in_progress -> completed.
7. Caso falta, marca como `no_show`.

**Agendamento publico:**
1. Gestor configura `AgendaOnlineConfig` (habilitado, tempo minimo, limite futuro, campos do formulario).
2. Link publico eh gerado: `/booking/:public_id`.
3. Paciente acessa, preenche o formulario (nome, sobrenome, CPF, celular, email, observacoes).
4. Evento eh criado no calendario do profissional.

**Notificacoes:**
1. Gestor configura regras em `AgendaNotificationRule` (tipo, offset em horas, template, inboxes).
2. `Agenda::NotificationDispatcherJob` avalia regras de lembrete periodicamente.
3. `Agenda::SendNotificationJob` monta a mensagem, substitui variaveis e envia via Chatwoot inbox.

### 2.6 Regras de Negocio

- `ends_at` deve ser posterior a `starts_at`.
- Slot interval aceita apenas 15, 30 ou 60 minutos.
- Regras do tipo `reminder` exigem `trigger_offset_hours`.
- Notificacao de confirmacao eh disparada automaticamente ao criar evento com `contact_id` — exceto quando `status == 'pending_confirmation'` (Bea/IA), caso em que a notificacao fica retida ate humano aprovar.
- `AgendaOnlineConfig` eh unico por conta (`account_id` UNIQUE).
- `AgendaSetting` eh unico por conta.
- Lista de espera impede duplicata de contato por conta.
- Campos do formulario publico possuem campos de sistema (nao removiveis): nome, sobrenome, CPF, celular, email.
- Status do `AgendaEvent` aceita: `pending_confirmation`, `scheduled`, `confirmed`, `arrived`, `in_progress`, `completed`, `cancelled`, `no_show`. `pending_confirmation` eh reservado a eventos criados pela Bea (IA) que aguardam validacao humana — quando o status muda para `scheduled` ou `confirmed`, as notificacoes ao paciente sao disparadas (callback `approved_after_pending?`).

### 2.7 Modelo de Dados

| Entidade | Descricao |
|---|---|
| `AgendaEvent` | Evento central: titulo, datas, status, tipo, contact_id, user_id, custom_attributes (JSONB) |
| `AgendaService` | Catalogo: nome, duracao, preco, cor, posicao |
| `AgendaSetting` | Config por conta: dias da semana (JSONB), slot_interval_minutes |
| `AgendaOnlineConfig` | Config booking publico: enabled, min_lead_time, future_limit_days, form_fields (JSONB) |
| `AgendaNotificationRule` | Regras: title, rule_type, trigger_offset_hours, message_template, inboxes (JSONB), enabled |
| `AgendaNotificationLog` | Registro de envio: event_id, rule_id, sent_at, status, error_message |
| `AgendaCustomAttribute` | Campos extras: name, field_type, position |
| `WaitingListEntry` | Lista de espera: contact_id, period, account_id |

### 2.8 Integracoes

- **Pacientes:** `AgendaEvent.contact_id` vincula ao `Contact`, que se conecta ao `Patient.contact_id`. Mudancas de status do evento geram registros na `PatientTimeline`.
- **Prontuario Clinico:** `ClinicalNote.appointment_id` e `SessionLog.appointment_id` vinculam evolucoes e sessoes ao evento da agenda.
- **Chatwoot Inboxes:** Notificacoes sao enviadas atraves dos inboxes configurados nas regras.

### 2.9 Edge Cases

- Evento sem `contact_id`: nao dispara notificacoes nem timeline (bloqueios lanche, reuniao).
- Profissional sem conta: `AgendaBookingController` retorna `not_found`.
- `AgendaOnlineConfig` desabilitado: pagina publica exibe mensagem de indisponibilidade.
- Falha no envio de notificacao: registra `AgendaNotificationLog` com status `failed` e `error_message`.
- Regra de notificacao desabilitada: scope `enabled` a exclui automaticamente.

### 2.10 Estado Atual

- Calendario visual com tres visualizacoes: **implementado** (AgendaDashboard.vue — 195KB).
- CRUD de eventos via API: **implementado**.
- Servicos, settings, custom attributes: **implementados**.
- Regras de notificacao e log: **implementados**.
- Agendamento publico (booking): **implementado** (controller + layout dedicado).
- Lista de espera: **implementada** (model + controller + feature frontend).
- Relatorios de agenda: **implementados** (controller com 9.4KB de logica).
- Configuracoes de agenda: **implementadas** (frontend 154KB).

---

## 3. Modulo: Pacientes (Prontuario Clinico)

### 3.1 Visao Geral

Prontuario eletronico completo com 12 abas de registro clinico, timeline automatizada, auditoria imutavel (LGPD) e integracao bidirecional com agenda e financeiro. Funciona como hub central do paciente na plataforma.

### 3.2 Problema que Resolve

Clinicas gerenciam prontuarios em fichas de papel ou sistemas isolados sem integracao com comunicacao, agenda ou financeiro. Informacoes criticas (alergias, contraindicacoes) se perdem entre profissionais. Nao ha rastreabilidade de acesso nem conformidade regulatoria.

### 3.3 Publico-Alvo

- **Profissionais de saude:** Registram anamneses, evolucoes, planos de tratamento, sessoes e exames.
- **Recepcionistas:** Cadastram e atualizam dados do paciente, gerenciam agendamentos.
- **Gestores:** Monitoram metricas (recall, faltas, inadimplencia) e auditam acessos.

### 3.4 Funcionalidades Principais

#### Bloco 1 — Cadastro e Alertas

| Funcionalidade | Descricao |
|---|---|
| CRUD de pacientes | Nome, CPF, email, telefone, data de nascimento, sexo, estado civil, endereco (JSONB), responsavel, contato de emergencia, avatar |
| Status do paciente | novo, ativo, inativo, faltoso, alta, arquivado |
| Soft delete | Exclusao logica (deleted_at) preservando historico |
| Busca | Por nome, email, CPF |
| Alertas criticos | Alergias, condicoes, medicamentos, contraindicacoes (severidade: high, medium, low) |
| Recall automatico | Flag `needs_recall` calculada: sem agendamento futuro apos ultima consulta concluida |
| Vinculo com Contact | `contact_id` conecta ao sistema de comunicacao do Chatwoot |

#### Bloco 2 — Anamnese

| Funcionalidade | Descricao |
|---|---|
| Anamnese versionada | Cada anamnese incrementa `version_number` automaticamente |
| Campos estruturados | Queixa principal, historico medico (JSONB), alergias (JSONB), medicamentos (JSONB), historico cirurgico, historico familiar, gestacao (JSONB), habitos, contraindicacoes (JSONB), notas adicionais |
| Status | draft -> finalized (imutavel apos finalizacao) |
| Extracao de alertas | `AnamnesisAlertExtractorJob` cria CriticalAlerts a partir de alergias de alta severidade |
| Geracao de PDF | `Patients::AnamnesisPdfGenerator` gera PDF anexado via Active Storage |
| Templates | Vinculo opcional com `FormTemplate` de tipo anamnesis |

#### Bloco 3 — Evolucao Clinica

| Funcionalidade | Descricao |
|---|---|
| Notas clinicas | Queixa do dia, avaliacao, conduta, complicacoes, orientacoes, retorno recomendado |
| Assinatura digital | `sign!` congela o registro com `signed_at`, `signed_by` |
| Janela de edicao | Draft editavel por `clinical_note_draft_hours` (padrao 48h) |
| Vinculo com agenda | `appointment_id` liga ao evento da agenda |
| Templates | Vinculo opcional com `FormTemplate` de tipo clinical_note |

#### Bloco 4 — Plano de Tratamento

| Funcionalidade | Descricao |
|---|---|
| Plano de tratamento | Status: proposto -> aprovado -> em_execucao -> concluido / cancelado |
| Itens do plano | Procedimento, dente/regiao, quantidade de sessoes, preco unitario, prioridade (baixa, media, alta, urgente) |
| Progresso automatico | `sessions_done` incrementa via `SessionLog`; status do item evolui automaticamente |
| Aprovacao | `TreatmentPlanApprover` registra aprovacao com ator e timestamp |
| PDF | `TreatmentPlanPdfGenerator` gera documento para o paciente |

#### Bloco 5 — Sessoes Clinicas

| Funcionalidade | Descricao |
|---|---|
| Log de sessao | Data, duracao, observacoes, procedimento, profissional |
| Vinculo com tratamento | Sessao pode incrementar `treatment_item.sessions_done` via `IncrementTreatmentSessionJob` |
| Status do plano | `UpdateTreatmentPlanStatusJob` recalcula status do plano apos cada sessao |
| Retorno | Flag `return_needed` e `return_in_days` |

#### Bloco 6 — Financeiro do Paciente

| Funcionalidade | Descricao |
|---|---|
| Orcamentos | Subtotal, desconto (% ou fixo), total, parcelas, metodo de pagamento |
| Transacoes | Receita, despesa, reembolso (status: pendente, pago, vencido, cancelado, reembolsado) |
| Parcelas | Geradas automaticamente a partir do orcamento (`generate_transactions!`) |
| Sincronizacao central | `TransactionSyncService` replica transacoes do paciente no financeiro central (`AccountTransaction`) |

#### Bloco 7 — Exames e Midia

| Funcionalidade | Descricao |
|---|---|
| Upload de exames | Categorias: rx, tomografia, foto_clinica, antes_depois, intraoral, laudo, laboratorial, video, outro |
| Limite | 500MB por arquivo |
| Tipos aceitos | JPEG, PNG, GIF, WebP, HEIC, PDF, MP4, MOV, AVI, WebM, DICOM |
| Pastas | `ExamFolder` para organizacao |
| URLs assinadas | Expiracao de 15 minutos (nunca URL publica) |
| Lock | Campo `locked` impede edicao |

#### Bloco 8 — Documentos Clinicos

| Funcionalidade | Descricao |
|---|---|
| Tipos | receita, atestado, pedido_exame, declaracao, relatorio_clinico, encaminhamento, contrato, orcamento, instrucao_procedimento, questionario, outro |
| Versionamento | `version` incrementa automaticamente por tipo + titulo |
| Geracao server-side | `is_generated` indica se foi gerado pelo sistema |
| Status | gerado, pendente_assinatura, assinado, enviado, arquivado |
| Envio WhatsApp | `DocumentWhatsappSender` envia documento via conversa do Chatwoot |

#### Bloco 9 — Consentimentos

| Funcionalidade | Descricao |
|---|---|
| Assinatura local (tablet) | Captura assinatura digital via canvas, grava `signature_blob` |
| Assinatura remota (link) | Gera `remote_token` com expiração de 48h |
| Integridade | Hash SHA-256 do paciente + ID + blob + timestamp |
| Status | pendente, assinado_localmente, assinado_remotamente, vencido, revogado |
| Validade | `expires_after_days` calcula `expires_at` automaticamente |
| Verificacao | `integrity_valid?` valida hash armazenado |

#### Bloco 10 — Agendamentos do Paciente

| Funcionalidade | Descricao |
|---|---|
| Tipos | avaliacao, retorno, procedimento, revisao, emergencia |
| Status | scheduled, confirmed, arrived, in_progress, done, no_show, canceled, rescheduled |
| Falta automatica | `mark_no_show!` incrementa `no_show_count`; ao atingir 3 faltas, paciente vira `faltoso` |
| Recall | Flag `recall_sent` para controle de reengajamento |
| Vinculo agenda | `agenda_event_id` conecta ao calendario central |

#### Bloco 11 — Timeline

| Funcionalidade | Descricao |
|---|---|
| Eventos automaticos | cadastro, anamnesis_filled, appointment_scheduled/done/no_show/canceled, clinical_note, session_performed, exam_uploaded, document_generated, consent_signed, payment, refund, status_changed, discharge, recall_sent |
| Actor tracking | Nome e ID do profissional responsavel |
| Metadata | JSONB com contexto detalhado por tipo de evento |
| Reference tracking | Polimórfico (reference_type + reference_id) para navegacao direta |

#### Bloco 12 — Auditoria

| Funcionalidade | Descricao |
|---|---|
| Log imutavel | Nao permite UPDATE nem DESTROY (LGPD + CFM) |
| Acoes | view, create, update, delete, sign, export, finalize, approve, pay, print |
| Snapshot | Registra ator (nome, role), recurso alterado, campos modificados, IP |
| Conformidade | Atende requisitos de rastreabilidade da LGPD e resolucoes do CFM |

### 3.5 Fluxos do Usuario

**Cadastro de paciente:**
1. Recepcionista acessa `/accounts/:id/patients`.
2. Clica em "Novo Paciente".
3. Preenche dados pessoais (nome obrigatorio, CPF formatado com 11 digitos).
4. Paciente criado com status `novo`.
5. Opcionalmente vincula a um Contact existente do Chatwoot (`contact_id`).

**Prontuario completo:**
1. Clica no paciente na listagem -> abre `/patients/:id/record`.
2. Navega entre 12 abas: Cadastro, Anamnese, Evolucao, Plano de Tratamento, Procedimentos, Financeiro, Exames, Documentos, Consentimentos, Agenda, Timeline, Auditoria.
3. Cada acao (criar, editar, assinar, finalizar) gera registros na Timeline e Auditoria.

**Fluxo clinico tipico:**
1. Paciente chega -> status do agendamento muda para `arrived`.
2. Profissional abre prontuario -> registra evolucao clinica.
3. Registra sessao vinculada ao plano de tratamento.
4. Sessions_done incrementa automaticamente no item do tratamento.
5. Se item completou sessoes planejadas -> status muda para `concluido`.
6. Upload de fotos/exames pos-procedimento.
7. Gera documento (receita, atestado) e envia via WhatsApp.

### 3.6 Regras de Negocio

- CPF: formato exclusivo 11 digitos numericos; strip automatico de caracteres nao numericos.
- Anamnese finalizada: imutavel — `before_update` aborta se status era `finalized`.
- Evolucao assinada: imutavel — nao permite update nem delete.
- Janela de edicao draft: configuravel por conta (`clinical_note_draft_hours`), padrao 48h.
- Plano de tratamento: total calculado como soma de `treatment_items.total_price`.
- Item de tratamento: `sessions_done` nao pode exceder `sessions_planned`.
- Consentimento assinado: token remoto eh invalidado apos uso.
- Paciente com 3+ faltas (`no_show_count >= 3`): status automatico para `faltoso`.
- Recall: calculado automaticamente — paciente precisa de recall se tem ultima consulta concluida mas nenhum agendamento futuro.
- Audit log: execucao da operacao `FrozenError` em tentativas de update/destroy.

### 3.7 Modelo de Dados

| Entidade | Campos Principais |
|---|---|
| `Patient` | name, cpf, email, phone, birthdate, sex, marital_status, patient_status, address (JSONB), contact_id, needs_recall, no_show_count, avatar |
| `CriticalAlert` | alert_type, severity, title, description, patient_id, active |
| `Anamnesis` | version_number, chief_complaint, medical_history (JSONB), allergies (JSONB), status |
| `ClinicalNote` | note_date, complaint_of_day, assessment, conduct, status, signed_at, signed_by |
| `TreatmentPlan` | status, professional_id, approved_by, estimated_duration |
| `TreatmentItem` | procedure_name, tooth_region, sessions_planned, sessions_done, unit_price, priority |
| `SessionLog` | performed_at, duration_minutes, observations, procedure_name, return_needed |
| `FinancialEstimate` | subtotal, discount_type, discount_value, total, installments_count, status |
| `Transaction` | transaction_type, amount, payment_method, status, due_date, installment_number |
| `Installment` | number, amount, status, due_date, payment_method |
| `ExamMedia` | category, file (Active Storage), mime_type, file_size, locked |
| `ExamFolder` | name, patient_id |
| `Document` | document_type, title, version, status, file (Active Storage), is_generated |
| `ConsentRecord` | title, body, status, mode, signature_blob, integrity_hash, remote_token, expires_at |
| `PatientAppointment` | appointment_type, status, scheduled_at, duration_minutes, recall_sent |
| `PatientTimelineEvent` | event_type, label, actor_name, metadata (JSONB), occurred_at |
| `PatientAuditLog` | action, actor_name, actor_role, resource (polimorfic), changed_fields (JSONB), ip_address |
| `FormTemplate` | name, template_type, specialty, fields (JSONB), is_global |

### 3.8 Integracoes

- **Agenda:** `PatientAppointment.agenda_event_id` vincula ao calendario. Mudancas de status do `AgendaEvent` geram timeline no paciente.
- **Financeiro Central:** `TransactionSyncService` cria `AccountTransaction` no financeiro central quando transacao do paciente eh criada ou paga.
- **Comunicacao (Chatwoot):** `Patient.contact_id` vincula ao Contact. `DocumentWhatsappSender` envia documentos via conversa.

### 3.9 Edge Cases

- Paciente sem contact_id: nao recebe notificacoes automaticas da agenda.
- Anamnese com alergia de alta severidade: extrai alerta critico automaticamente via job assincrono.
- Evolucao fora da janela de edicao: nao permite mais edicao nem assinatura.
- Consentimento remoto com token expirado: `sign_remotely!` levanta erro.
- Transacao parcelada: orcamento gera N transacoes com ajuste de centavos na ultima parcela.
- Upload DICOM: aceito pelo sistema (application/dicom, image/dicom).
- Paciente com status `alta` ou `arquivado`: recall nao eh calculado.

### 3.10 Estado Atual

- Listagem de pacientes com busca: **implementado** (Index.vue — 23KB).
- Prontuario com 12 abas: **implementado** (Record.vue — 561KB).
- Todas as abas com frontend completo: **implementado** (16KB-37KB cada).
- API completa: **implementada** (17 sub-controllers em `patients/`).
- Services: **implementados** (17 servicos dedicados).
- Jobs assincronos: **implementados** (5 jobs para timeline, tratamento, alertas).
- Geracao de PDFs: **implementada** (anamnese, prontuario, plano de tratamento).
- Envio de documentos via WhatsApp: **implementado**.
- Consentimento com assinatura digital (local + remoto): **implementado**.
- Auditoria imutavel: **implementada**.

---

## 4. Modulo: Financeiro Central

### 4.1 Visao Geral

Sistema de gestao financeira com dashboard de KPIs, fluxo de caixa, contas a receber e a pagar, DRE (Demonstracao do Resultado do Exercicio), controle de caixa fisico, despesas recorrentes, comissoes de profissionais, categorias financeiras, contas bancarias e relatorios analiticos. Opera com regime de caixa e competencia.

### 4.2 Problema que Resolve

Clinicas perdem visibilidade financeira por usarem planilhas ou controles manuais. Nao ha separacao entre receitas, custos fixos e variaveis. Inadimplencia nao eh rastreada. Nao existe projecao de fluxo de caixa, DRE nem calculo de comissoes automatizado.

### 4.3 Publico-Alvo

- **Gestores/Proprietarios:** Dashboards de KPIs, DRE, metas de receita, relatorios.
- **Financeiro/Administrativo:** Contas a receber/pagar, caixa, categorias, despesas recorrentes.
- **Profissionais de saude:** Visualizacao de comissoes sobre producao/recebimento.

### 4.4 Funcionalidades Principais

#### Dashboard Financeiro

| Funcionalidade | Descricao |
|---|---|
| KPIs em tempo real | Entradas de hoje (com variacao vs ontem), saidas de hoje, saldo consolidado das contas, inadimplencia total |
| Sparklines | Graficos mini de 8 dias: entradas, saidas, saldo acumulado, inadimplencia |
| Resumo de recebiveis | Vencidos, a vencer, vencem hoje |
| Resumo de pagaveis | Vencidos, a vencer, vencem hoje |
| Resumo de inadimplencia | Total vencido + quantidade de pacientes inadimplentes |
| Saldo de contas bancarias | Saldo corrente de cada conta ativa |
| Mini fluxo de caixa | Ultimos 8 dias: entradas, saidas, saldo |
| Vendas mensais | Ultimos 6 meses de receita |
| Despesas por categoria | Grafico de pizza com despesas pagas por categoria |
| Receita por convenio | Agrupamento por seguradora/convenio |
| Ticket medio | Total recebido / numero de transacoes |
| Meta de receita | Gauge com meta mensal configurada por conta |

#### Fluxo de Caixa

| Funcionalidade | Descricao |
|---|---|
| Grafico temporal | Entradas vs saidas vs saldo ao longo do periodo |
| Projecao de fluxo | `CashFlowProjectionService`: projeta recebiveis e pagaveis futuros |
| Filtros | Periodo customizado, tipo de entrada |

#### Contas a Receber

| Funcionalidade | Descricao |
|---|---|
| Listagem de entradas | Filtro por status: pendente, recebido, parcial, cancelado |
| Baixa de pagamento | Modal dedicado (`ReceivePaymentModal.vue` — 18KB) |
| Recebiveis por semana | Grafico semanal de vencimentos |

#### Contas a Pagar

| Funcionalidade | Descricao |
|---|---|
| Listagem de saidas | Filtro por status, categoria, vencimento |
| Registro de pagamento | Formulario de baixa com metodo e data |

#### DRE — Demonstracao do Resultado

| Funcionalidade | Descricao |
|---|---|
| Calculo completo | Receita bruta -> deducoes -> receita liquida -> custos assistenciais -> margem bruta -> custos fixos -> marketing -> desp. financeiras -> impostos -> resultado liquido |
| Regime duplo | Caixa (received_at/paid_at) ou competencia (competence_date) |
| Waterfall chart | Visualizacao em cascata com base/topo para cada linha |
| Percentuais | Cada linha expressa como % da receita bruta |

#### Caixa Fisico (Cash Register)

| Funcionalidade | Descricao |
|---|---|
| Abertura de caixa | Operador, data, saldo de abertura |
| Suplementos/Sangrias | Entradas e retiradas durante o turno |
| Fechamento | Saldo declarado vs calculado, apuracao de diferenca |
| Status | open -> closed |

#### Despesas Recorrentes

| Funcionalidade | Descricao |
|---|---|
| CRUD | Descricao, valor, frequencia (mensal, semanal, quinzenal, trimestral, anual), dia de vencimento |
| Geracao automatica | `ProcessRecurringExpensesJob` cria `AccountTransaction` automaticamente |
| Regra de competencia | `same_month` ou `previous_month` |
| Metodo de pagamento | Dinheiro, PIX, cartao credito/debito, boleto, transferencia, cheque |

#### Comissoes

| Funcionalidade | Descricao |
|---|---|
| Regras por profissional | Percentual sobre producao, percentual sobre recebimento, ou valor fixo |
| Hierarquia de regras | Procedimento especifico > categoria > regra geral |
| Periodo de vigencia | valid_from / valid_until |
| Calculo | `CommissionCalculator` aplica regra mais especifica |

#### Categorias Financeiras

| Funcionalidade | Descricao |
|---|---|
| Hierarquia pai-filho | Categoria -> subcategorias |
| Tipos | income (receita) ou expense (despesa) |
| Custo fixo/variavel | Usado pelo DRE para classificacao |
| Categorias padrao | Seed com categorias pre-configuradas |

#### Contas Bancarias

| Funcionalidade | Descricao |
|---|---|
| CRUD | Nome, banco, tipo (corrente, poupanca, caixa), saldo inicial |
| Saldo corrente | Calculado: saldo_inicial + entradas_recebidas - saidas_pagas |
| Vinculo com transacoes | Cada transacao pode ser associada a uma conta |

#### Relatorios

| Funcionalidade | Descricao |
|---|---|
| Pagina dedicada | Reports.vue (45KB) com multiplos graficos |
| Componentes analiticos | Revenue composition, expense by category, delinquency aging, delinquency by professional, delinquency trend, average ticket trend, conversion funnel, new vs returning patients, revenue by professional, fixed vs variable costs, agenda heatmap, cash flow projection, DRE waterfall, receivables by week, revenue goal gauge |
| Exportacao PDF | `FinancialPdfsController` gera relatorios em PDF |

### 4.5 Fluxos do Usuario

**Visualizacao financeira:**
1. Gestor acessa `/accounts/:id/financial`.
2. Dashboard exibe KPIs, sparklines, resumos.
3. Filtra por periodo (hoje, semana, mes, customizado).

**Registro de transacao central:**
1. Acessa Contas a Receber ou Contas a Pagar.
2. Cria nova transacao (entrada ou saida).
3. Preenche: valor, status, categoria, conta bancaria, metodo de pagamento, fonte de pagamento, paciente, profissional.
4. Transacao aparece no fluxo de caixa e dashboards.

**Sincronizacao paciente -> central:**
1. Orcamento eh aprovado no prontuario do paciente.
2. `generate_transactions!` cria N transacoes no modulo Pacientes.
3. `TransactionSyncService.on_created` cria `AccountTransaction` correspondente no financeiro central.
4. Quando paciente paga, `TransactionSyncService.on_paid` atualiza central.
5. Sync reverso: quando central marca como recebido, `sync_back_to_patient_transaction` atualiza transacao do paciente.

**Fechamento de caixa:**
1. Operador abre caixa (data, saldo inicial).
2. Registra suplementos/sangrias ao longo do dia.
3. No fim do turno, informa saldo declarado.
4. Sistema calcula diferenca (declarado vs calculado).
5. Fecha o caixa.

### 4.6 Regras de Negocio

- `AccountTransaction.amount`: obrigatoriamente maior que zero.
- Entry types: `entrada` (receita) ou `saida` (despesa).
- Statuses: `pendente`, `recebido` (entradas), `pago` (saidas), `cancelado`, `parcial`.
- Origins: `manual`, `orcamento`, `procedimento`, `recorrente`.
- Payment sources: `particular`, `convenio`, `plano`, `outro`.
- Soft delete via `deleted_at` em todas as entidades.
- DRE classifica despesas como fixas ou variaveis via `FinancialCategory.cost_type`.
- Comissao: regra mais especifica vence (procedimento > categoria > geral).
- Despesa recorrente: `due_day` ajustado para o ultimo dia do mes quando mes nao tem o dia (ex: 31 em fevereiro).
- Saldo de conta bancaria: saldo_inicial + SUM(entradas_recebidas) — SUM(saidas_pagas).
- Meta de receita: mensal, configurada via `Account.financial_goals`.

### 4.7 Modelo de Dados

| Entidade | Campos Principais |
|---|---|
| `AccountTransaction` | entry_type, amount, status, origin, payment_method, payment_source, due_date, received_at, paid_at, competence_date, bank_account_id, financial_category_id, patient_id, professional_id, source_transaction_id, recurring_expense_id, estorno_de_id |
| `FinancialCategory` | name, category_type (income/expense), cost_type (fixo/variavel), parent_id, position, color, is_default |
| `BankAccount` | name, bank_name, account_type, initial_balance, active |
| `CashRegister` | register_date, operator_id, opening_balance, status, declared_balance, supplements, withdrawals, cash_in, cash_out |
| `CashRegisterEntry` | cash_register_id, entry_type (supplement/withdrawal/note), amount, payment_method |
| `CommissionRule` | professional_id, commission_type, value, procedure_name, financial_category_id, valid_from, valid_until, active |
| `RecurringExpense` | description, amount, frequency, due_day, competence_rule, start_date, end_date, payment_method, bank_account_id, financial_category_id, active, last_generated_at |

### 4.8 Integracoes

- **Pacientes:** Transacoes do paciente (`Transaction`) sao sincronizadas bidireccionalmente com `AccountTransaction` via `TransactionSyncService`.
- **Agenda:** `Financial::AgendaAnalyticsService` gera metricas cruzadas agenda-financeiro. Agenda heatmap no dashboard de relatorios.
- **Profissionais:** Comissoes calculadas por profissional. Receita por profissional nos relatorios.

### 4.9 Edge Cases

- Estorno: `estorno_de_id` vincula AccountTransaction revertida.
- Transacao parcial: status `parcial` indica pagamento incompleto.
- Despesa recorrente inativa: nao gera novas transacoes.
- Despesa recorrente com end_date passado: `active` se mantem mas nao gera.
- Conta bancaria com saldo negativo: permitido (saldo calculado, nao validado).
- Comissao sem regra aplicavel: retorna `nil`.
- Categoria financeira excluida: transacoes vinculadas tem FK `nullified`.

### 4.10 Estado Atual

- Dashboard com KPIs e sparklines: **implementado** (FinancialDashboard.vue — 44KB).
- Fluxo de caixa com projecao: **implementado** (CashFlow.vue — 26KB).
- Contas a receber: **implementado** (Receivables.vue — 17KB).
- Contas a pagar: **implementado** (Payables.vue — 14KB).
- DRE com waterfall: **implementado** (DRE.vue — 16KB).
- Caixa fisico: **implementado** (CashRegister.vue — 34KB).
- Relatorios com 16 componentes analiticos: **implementado** (Reports.vue — 45KB).
- Configuracoes financeiras: **implementado** (FinancialSettings.vue — 65KB).
- Backend completo: **implementado** (controllers: financial_dashboard, financial_reports 19KB, account_transactions 9KB, bank_accounts, cash_registers 5KB, commission_rules, financial_categories, recurring_expenses, financial_goals, financial_pdfs).
- Services dedicados: **implementados** (15 servicos + 1 subdir de PDF).
- Jobs: **implementado** (1 job de despesas recorrentes).
- Exportacao PDF: **implementada**.

---

## 5. Modulo: Configuracoes do Sistema

### 5.1 Visao Geral

Conjunto de configuracoes especificas do dominio clinico que estendem as configuracoes nativas do Chatwoot. Abrange configuracoes de agenda, financeiro, roles personalizados e templates de formularios.

### 5.2 Problema que Resolve

Cada clinica tem regras operacionais distintas: horarios, intervalos de consulta, templates de documentos, regras de notificacao, categorias financeiras. O sistema precisa ser parametrizavel sem exigir desenvolvimento.

### 5.3 Publico-Alvo

- **Administradores da clinica:** Configuram horarios, servicos, notificacoes, categorias financeiras.

### 5.4 Funcionalidades Principais

| Area | Configuracoes |
|---|---|
| Agenda — Horarios | Dias da semana habilitados, horario de inicio/fim, intervalo de almoco, slot_interval_minutes (15/30/60) |
| Agenda — Servicos | Catalogo de servicos com nome, duracao, preco, cor |
| Agenda — Atributos customizados | Campos extras para eventos: text, textarea, select, date, phone, cpf, rg |
| Agenda — Notificacoes | Regras de reminder/confirmation/followup/birthday/custom com template e offset |
| Agenda — Online | Habilitar/desabilitar booking, tempo minimo de antecedencia, limite futuro em dias, campos do formulario |
| Financeiro — Categorias | Hierarquia de categorias de receita/despesa com cost_type |
| Financeiro — Contas bancarias | Cadastro de contas com saldo inicial |
| Financeiro — Despesas recorrentes | Configuracao de despesas automaticas |
| Financeiro — Comissoes | Regras de comissao por profissional |
| Financeiro — Metas | Meta de receita mensal |
| Prontuario — Templates | Templates de anamnese, evolucao, consentimento, documento, recibo com campos configuráveis (JSONB) |
| Prontuario — Janela de edicao | `clinical_note_draft_hours` configura tempo de edicao de evolucoes |
| Controle de acesso — Roles | Permissoes customizadas por modulo (BeClinicRoles) |

### 5.5 Fluxos do Usuario

**Configuracao da agenda:**
1. Administrador acessa `/accounts/:id/agenda/settings`.
2. Configura dias de atendimento, horarios, intervalos de slot.
3. Cadastra servicos oferecidos.
4. Define regras de notificacao.
5. Habilita/configura agendamento online.

**Configuracao financeira:**
1. Acessa `/accounts/:id/financial/settings`.
2. Cadastra categorias (receitas e despesas) com hierarquia.
3. Configura contas bancarias.
4. Define despesas recorrentes.
5. Configura regras de comissao por profissional.
6. Define meta mensal de receita.

### 5.6 Modelo de Dados

Reutiliza as entidades ja documentadas nos modulos de Agenda e Financeiro:
- `AgendaSetting` (1 por conta)
- `AgendaOnlineConfig` (1 por conta)
- `AgendaService` (N por conta)
- `AgendaCustomAttribute` (N por conta)
- `AgendaNotificationRule` (N por conta)
- `FinancialCategory` (N por conta, hierarquica)
- `BankAccount` (N por conta)
- `RecurringExpense` (N por conta)
- `CommissionRule` (N por conta/profissional)
- `FormTemplate` (N por conta, globais ou locais)

### 5.7 Estado Atual

- Configuracoes de agenda (frontend 154KB): **implementado**.
- Configuracoes financeiras (frontend 65KB): **implementado**.
- Templates de formularios: **implementados** (CRUD via API + FormTemplate model).
- Roles customizados (BeClinicRoles): **implementado** (frontend + API).
- Todas as APIs de configuracao: **implementadas**.

---

## 6. Modulo: Bea (Assistente Virtual com IA)

> Plano detalhado e roadmap completo em [`ai-agent-configuration-plan.md`](ai-agent-configuration-plan.md). Esta seção captura a visão funcional de produto.

### 6.1 Visao Geral

Bea (Beatriz) é a assistente virtual da Klivy que atende pacientes via WhatsApp em linguagem natural PT-BR. Roda como agente único multi-tool sobre o stack Chatwoot+Klivy: ouve mensagens (texto, áudio, imagem, vídeo), consulta bases de conhecimento e dados estruturados (agenda, pacientes, financeiro), executa ações reversíveis (book, reschedule, cancel — sempre como reserva pendente que humano valida), classifica emergências antes de qualquer LLM e escala para humano nos casos certos. Plugin auto-contido em [`plugins/ai_agent/`](../../plugins/ai_agent/), com 5 mudanças no core devidamente registradas em §8.

### 6.2 Problema que Resolve

Clínicas brasileiras (odontológicas, estéticas, psicológicas) recebem alto volume de WhatsApp 24/7 com perguntas repetitivas (horário, preço, agendamento, remarcação). Recepção fica saturada nos picos, paciente espera horas pra resposta simples, no-show alto por falta de confirmação proativa. Bea resolve atendimento de primeira linha (~80% das interações típicas) sem terceirizar diagnóstico clínico nem escapar de exigências CFM 2.454/2026 e LGPD.

### 6.3 Publico-Alvo

- **Paciente**: WhatsApp como canal único, sem instalar app, atendimento 24/7.
- **Recepção/clínica**: vê reservas pendentes da Bea na agenda (badge laranja), valida em 1 clique. Notas internas privadas com contexto rico do que paciente disse + classificação automática (emergência, receita, foto clínica, etc).
- **Médico responsável técnico**: identificado em cada conta (CFM 2.454/2026), nome+CRM/CRO injetado no system prompt da Bea pra responder corretamente quando paciente pergunta quem é o(a) responsável.
- **Super admin Klivy**: liga/desliga Bea por conta, escolhe persona (odonto / estética / bem-estar), define teto de tokens/mês, sobe PDFs pra RAG, vê dashboard de uso e custo.

### 6.4 Funcionalidades Principais

**Núcleo conversacional:**
- Datetime context per-turn (PT-BR: "amanhã" → 07/05; clinic open/closed agora; feriados próximos).
- Memória cross-conversation 24h por contato (paciente reabre conversa nova, Bea ainda lembra).
- State machine determinística pra confirmações curtas ("Sim", "Ok") sem precisar do LLM.
- Active service intent: paciente em fluxo de "remoção de pontos" continua nele mesmo se LLM tentar voltar pra serviço anterior bem-sucedido.
- Pre-LLM short-circuits: emergência clínica (SAMU 192), ideação suicida (CVV 188), opt-out de recall.

**Ações na agenda (Sprint B*):**
- Tools: `clinic_info` (catálogo + horário + serviços por profissional), `search_available_slots` (HABTM Service↔User), `book_appointment`, `reschedule_appointment`, `cancel_appointment`, `list_appointments`.
- Toda criação/remarcação entra como `pending_confirmation` (badge laranja "Aguardando confirmação"). Notificação ao paciente só sai quando humano valida.
- Critique determinístico antes de book/reschedule: bloqueia data passada, fora do horário, profissional que não realiza o serviço, duração absurda.

**Multimodal:**
- Voice notes (PTT WhatsApp) → transcrição via Whisper PT-BR, persistida em `Message.content`.
- Imagem classificada via OpenAI Vision em 5 categorias (receita, foto clínica, exame, documento, outro) + vídeo. Sempre escala humano com nota interna específica. **Bea não interpreta clinicamente** (CFM).

**Compliance:**
- Tool `erasure_request` (LGPD art. 18 VI): registra `AuditLog` + nota privada + responde paciente com prazo 15 dias úteis. Não apaga automaticamente (D-23: humano que decide o que pode ser apagado vs retido por CFM 1.821/2007).
- Médico responsável técnico identificável (CFM 2.454/2026) configurado por conta no super admin.
- Validator pós-LLM bloqueia diagnóstico, prescrição, garantia.
- Sentinel pós-LLM em high-stakes (toggle `CAPTAIN_BEA_SENTINEL_ENABLED`): LLM-as-judge leve audita resposta antes de enviar e marca verdict no Trace.

**Recall proativo (Sprint G):**
- Cron diário 14h SP busca pacientes dormentes ≥6 meses sem agendamento futuro, manda 1 mensagem com opt-out claro.
- "NÃO" do paciente em até 7 dias após recall → opt-out automático determinístico (sem LLM), respeitado eternamente em runs futuros.

**Memória semantic (Sprint D):**
- Cron noturno 4h SP destila histórico do paciente (últimas 30 entries + 30 mensagens) num perfil compacto: `preferred_time_of_day`, `preferred_professional`, `frequent_services`, `tone`, `health_notes`, `summary`. Merge preserva keys manuais (`recall_opt_out`, etc).

**Follow-ups configuráveis (Sprint G2 + G2.1):**
- UI dedicada na sidebar BEA → Follow-ups (`/accounts/:id/ai_agent/follow_ups`). Clínica cria N regras configuráveis com cards visuais por tipo de gatilho (calendário/check/X/sem-resposta/raio).
- 5 triggers: `pre_appointment` (N antes do horário), `post_appointment` (N depois), `no_show` (N após faltar), `no_response` (paciente parado há N), `custom` (apenas via API externa).
- Offset com unidade selecionável: **segundos / minutos / horas** (limites: 1–14400s, 1–2880min, 1–720h). Cron roda a cada 1min com janela ±1min — suporta tanto disparos rápidos pra teste quanto agendamentos com lead time de dias.
- Filtro de origem (`applies_to`): "Em qualquer agendamento" (default), "Apenas se a Bea agendou", "Apenas se um humano agendou". Permite que automações pré-existentes do agendamento manual coexistam sem dupla notificação.
- Mensagem gerada agênticamente pela Bea via LLM leve (Gemini 3 Flash Preview / GPT-4.1-mini) usando o `context_brief` que a clínica escreve em linguagem natural. Tom herdado do CAPTAIN_BEA_SYSTEM_PROMPT (PT-BR profissional, sem gíria, ≤3 frases).
- Cap por paciente/consulta (`max_per_target`) anti-flood. Idempotência forte via UNIQUE no banco em `(rule_id, contact_id, agenda_event_id, target_at)`.
- Auditoria completa por disparo em `FollowUpExecution` (status: pending/sent/skipped/failed + `skip_reason` legível).

### 6.5 Regras de Negocio

- Toda criação ou remarcação pela Bea entra como `pending_confirmation` — humano valida antes de virar `scheduled`/`confirmed`. Decisão D-16 do plano.
- `cancel_appointment` é exceção: paciente cancelando o próprio compromisso é direito do paciente, executa direto.
- Emergência (regex PT-BR de risco-vida) e ideação suicida são classificadas **antes** do LLM ver — Mount Sinai 2026 mostrou 52% de undertriage em LLMs. Templates fixos com SAMU 192 / CVV 188.
- Tools high-stakes (book/reschedule/cancel/clinic_info/financial_status/erasure_request) podem disparar Sentinel quando habilitado; resposta atual é registrada com tag `sentinel:ok|reproved:<reason>` em `Trace.guardrail_violations` (modo telemetria — não regenera).
- Vocabulário obrigatório no system prompt: "reserva pendente / a clínica vai confirmar" em vez de "agendada / agendamento feito" — paciente não recebe mensagem com falsa certeza enquanto humano não validou.
- Recall não auto-executa em paciente com agendamento futuro ativo nem em quem fez opt-out. Cooldown 90 dias entre recalls.
- Memória semantic (cron Sprint D) só sobrescreve as 6 keys do Distiller. Keys manuais (`recall_opt_out`, `last_recall_at`, `_distiller_at`) sempre preservadas.
- **Follow-ups configuráveis** (Sprint G2): cada `FollowUpRule` é validada em criação (`trigger_type ∈ TRIGGER_TYPES`, `offset_unit ∈ {seconds, minutes, hours}`, `applies_to ∈ {both, ai_agent, manual}`). `offset_seconds = offset_value × seconds_per_unit` é a fonte canônica usada pelo CandidateFinder.
- **`applies_to` filter (Sprint G2.1)**: aplicado SOMENTE em triggers que envolvem AgendaEvent (`pre_appointment`, `post_appointment`, `no_show`). Em `no_response` e `custom` o filtro é ignorado pelo CandidateFinder e o campo fica oculto na UI.
- **`AgendaEvent.source`** é setado em UM único ponto por origem: Bea via `book_appointment_tool` (`'ai_agent'`), recepção via API REST padrão (`'manual'` via default), auto-agendamento público (`'public_booking'`), importação Clinicorp (`'manual'` por default; pode ser ajustado pra `'import'` se necessário). Nenhuma heurística — é seteado no create.
- **Bea reativa cancelamento recente** em vez de criar duplicata: se paciente cancela e logo pede pra remarcar no mesmo horário (≤60min após cancel), `book_appointment_tool` reativa o evento cancelled (status volta a `pending_confirmation`) ao invés de criar uma 2ª linha no calendário.
- **Idempotência de Follow-up disparado**: UNIQUE constraint em `(rule_id, contact_id, agenda_event_id, target_at)` no banco. Cron rodar duas vezes seguidas, retry de Sidekiq, click duplo de operador → todos caem no mesmo registro `FollowUpExecution`, sem duplicação.
- **Mensagem proativa não agenda nada**: `MessageGenerator` (Sprint G2) chama LLM SEM tools registradas. A mensagem que a Bea envia em follow-up é só texto — não pode book, reschedule ou cancel automático. Modificações na agenda continuam exigindo conversa explícita iniciada pelo paciente.

### 6.6 Modelo de Dados

| Entidade | Descricao |
|---|---|
| `AiAgent::AccountSetting` | Config por conta: `enabled`, `chat_model`, `monthly_token_budget`, `persona_id`, `system_prompt_prefix`, `enabled_tools` (jsonb), `responsible_physician_id` (FK User), `responsible_physician_council` (CRM/CRO/CRP/COREN), `responsible_physician_crm` ("123456/SP") |
| `AiAgent::GlobalSetting` | Provider (gemini/openai), modelos default, tetos globais |
| `AiAgent::PersonaTemplate` | 3 personas builtin (odonto / estética / bem-estar) + custom |
| `AiAgent::ToolDefinition` | Catálogo de tools registráveis (`erasure_request`, `book_appointment`, `clinic_info`, etc) |
| `AiAgent::Document` + `ParentChunk` + `ChildChunk` | RAG hierárquico com pgvector |
| `AiAgent::Trace` | 1 row por turno: model, provider, latência, tokens, custo, sentiment, escalation_reason, guardrail_violations (jsonb), short_circuited |
| `AiAgent::ConversationState` | working_memory (jsonb): pending_offer, last_completed, active_service, recent_listed_appointment_id |
| `AiAgent::PatientMemory` | Por contact: preferences (jsonb), history (jsonb capped 50), last_consolidated_at |
| `AiAgent::UsageCounter` | Tokens/custo por conta/mês |
| `AiAgent::AuditLog` | Append-only de mudanças globais/por conta + LGPD erasure_request |
| `AgendaServiceUser` | HABTM `User <-> AgendaService` (Sprint B1.5 — multi-doutor por especialidade) |
| `AiAgent::FollowUpRule` (Sprint G2) | Por conta: `name`, `trigger_type`, `offset_hours` (valor) + `offset_unit` (`seconds`/`minutes`/`hours`), `context_brief` (texto livre que vira prompt), `max_per_target`, `applies_to` (`both`/`ai_agent`/`manual`), `enabled`, `position`, `status_filter` (jsonb opcional). |
| `AiAgent::FollowUpExecution` (Sprint G2) | Audit + idempotência: 1 row por disparo. `rule_id`, `contact_id`, `conversation_id`, `agenda_event_id`, `target_at`, `sent_at`, `status` (`pending`/`sent`/`skipped`/`failed`), `skip_reason`, `message_id`. UNIQUE em `(rule_id, contact_id, agenda_event_id, target_at)`. |
| `AgendaEvent.source` (Sprint G2.1) | Coluna nova em `agenda_events` (string, default `'manual'`, NOT NULL). Valores: `'manual'` (recepção), `'ai_agent'` (Bea), `'public_booking'` (auto-agendamento online), `'import'` (Clinicorp/CSV). Usado pelo filtro `applies_to` dos Follow-ups. |

### 6.7 Integracoes

- **Chatwoot Messages**: `MessageListener` escuta `after_create_commit` em mensagens incoming. Filtros: bot habilitado, inbox ligado a Beatriz, conversa não escalada, sem assignee humano. Aceita mensagens com attachment mesmo sem content (áudio/imagem puros).
- **Agenda**: `AgendaEvent` ganhou status `pending_confirmation`. Notificações de confirmação ficam seguradas até humano aprovar (callback `approved_after_pending?` dispara WhatsApp).
- **Pacientes**: `Patient` resolvido via `Contact.contact_id` em todas as tools. Histórico clínico (alergias, condições) pode ser consultado via `patient_lookup`.
- **Financeiro**: `financial_status` tool retorna situação atual (saldo, parcelas vencidas) sem expor valores comprometedores.
- **Whisper API** (OpenAI): voice notes transcritas em PT-BR.
- **Vision API** (OpenAI `gpt-4o-mini`): imagem classificada em 5 categorias.
- **Sidekiq::Cron::Job**: 3 crons — `ProactiveOutreachJob` (diário 14h SP), `ConsolidatePatientMemoryJob` (diário 4h SP) e `FollowUpDispatcherJob` (a cada 1min). Todos registrados via initializer no engine, sem tocar `config/schedule.yml` do core.
- **AgendaEvent.source**: Bea `'ai_agent'` (single point in `book_appointment_tool`), recepção `'manual'` (default da migration), auto-agendamento `'public_booking'` (set em `Public::Api::V1::Agenda::PublicController`). Usado pelo CandidateFinder pra filtrar regras por origem.
- **RubyLLM 1.9.2 + Gemini 3 Flash Preview**: monkey-patch no plugin (`AiAgent::GeminiThoughtSignaturePatch`) captura e reinjeta `thoughtSignature` em function calls, permitindo usar o Gemini 3 com tools mesmo enquanto o gem oficial não suporta. Idempotente em reload — initializer aplica uma vez por boot.

### 6.8 Edge Cases

- Paciente fora da janela WhatsApp 24h: recall pode falhar — em produção exige WhatsApp Business template aprovado (Sprint G2 futura).
- Paciente sem `Contact` vinculado (inbox sem identificação): tools que precisam de `contact_id` retornam erro descritivo, Bea direciona "preciso da sua identificação primeiro".
- LLM tenta book com profissional que não realiza o serviço: Critique reprova antes de executar, retorna erro estruturado (`critique_failed: true`) e Bea pergunta o que falta.
- LLM alucina e tenta voltar pra serviço anterior bem-sucedido após paciente pedir outro: hard override em `wrap_tool_for_state_capture` sobrescreve `service_id` baseado em `active_service`.
- API LLM down: `with_provider_fallback` tenta OpenAI fallback, depois retry no mesmo modelo após backoff.
- Whisper/Vision indisponível: fallback determinístico ao paciente ("Não consegui ouvir" / "Recebi sua imagem, equipe vai avaliar"), sempre escala humano.
- Mensagem repetida 5x (loop): `EscalationRules` escala humano com reason `user_loop`.
- **Follow-up sem conversa aberta**: paciente nunca interagiu via WhatsApp → não tem `Conversation` ativa. `SendFollowUpJob` marca `FollowUpExecution.status='skipped'` com `skip_reason='no_open_conversation'`. Não cria conversa do zero (exigiria WhatsApp Business template aprovado pela Meta — fora do escopo G2/G2.1, fica pra Sprint G3).
- **Follow-up sem `contact_id`**: AgendaEvent criado como bloqueio interno (lanche, reunião) não dispara — CandidateFinder filtra `where.not(contact_id: nil)`.
- **Follow-up "reagendar sem cancelar antes"**: paciente cancela e logo pede pra remarcar mesmo horário. `book_appointment_tool` reativa o cancelado em vez de criar duplicata, evitando 2 cards no calendário.
- **`a gente` no PT-BR informal**: paciente diz "a gente consegue reagendar?" — NÃO escala humano. Regex de pedido explícito de humano (`EXPLICIT_HUMAN_REQUEST` em `EscalationRules`) ignora "a gente" isolado, exige verbo + complemento de transferência.
- **MessageGenerator no Sidekiq**: workers podem rodar antes do initializer carregar a key Gemini/OpenAI. Solução: `Llm::Config.initialize!` é chamado idempotentemente no início de `MessageGenerator#call` — sem custo nas chamadas seguintes.

### 6.9 Estado Atual (2026-05-07)

- **16 sprints concluídas e ativas em produção**: A, B1, B1.5, B2, B3, C, D, E, F MVP, F2, G MVP, **G2** (motor de Follow-ups configurável), **G2.1** (filtro `applies_to` Bea/humano/ambos), I, M, S.
- **Provider LLM principal**: Gemini 3 Flash Preview (`gemini-3-flash-preview`) via `CAPTAIN_GEMINI_MODEL`. OpenAI (`gpt-4.1-mini`) configurado como fallback automático em `with_provider_fallback`. Pricing tabelado em USD oficial Google ($0.50 in / $3.00 out por 1M tokens — output inclui thinking tokens).
- **Sentinel ligado** em modo telemetria (`CAPTAIN_BEA_SENTINEL_ENABLED=true`).
- **Crons ativos** registrados no Sidekiq::Cron::Job: `ProactiveOutreachJob` (recall, 14h SP), `ConsolidatePatientMemoryJob` (memória semantic, 4h SP), `FollowUpDispatcherJob` (a cada 1min).
- **Dashboard super admin** com 8 KPIs: deflection, custo, escaladas, tokens, latency p95, sentiment distribution.
- **Polimentos de qualidade entregues em 2026-05-07** (não-sprint, mas ativos):
  - **Tom da Bea humanizado**: `CAPTAIN_BEA_SYSTEM_PROMPT` reescrito com **Regra do Espelho** (reconhece o pedido do paciente antes de oferecer alternativa), 4 few-shots de rejeição empática, anti-monotonia (variar abertura), zero gíria/regionalismo (lista de 13 expressões proibidas: "pô", "tô", "rola", "deu ruim", "tipo", etc).
  - **Tool `search_available_slots`** retorna `gap_context` quando o horário pedido pelo paciente difere do disponível (`after_closing` / `before_opening` / `closed_day` / `lunch_break` / `time_unavailable`). O `note_for_bea` instrui o LLM a fazer espelho empático ("Entendi que 18h seria melhor, mas a clínica fecha 17h..." em vez de listar horários direto).
  - **`book_appointment_tool` reativa cancelados recentes**: se há um AgendaEvent cancelled do mesmo paciente/horário/profissional nas últimas 60min, reativa em vez de criar duplicata.
  - **Memory cross-conversation 24h**: usa `.reorder('messages.created_at DESC, messages.id DESC')` + `.to_a.reverse` pra contornar `Message.default_scope { order(created_at: :asc) }` que silenciosamente sobrescrevia a ordem; sem isso, LLM recebia histórico em ordem inversa.
  - **Audio race**: `AudioTranscriber` rescues `ActiveStorage::FileNotFoundError`, retry 3× com sleep 1s, retorna `:file_not_ready` sentinel; `ChatResponseJob` reenfileira com `wait: 5.seconds`, máx 3 tentativas (~24s total). Cobre o caso onde WhatsApp commitou Message antes do upload do blob terminar.
  - **`gemini-3-flash-preview` com tools**: monkey-patch `AiAgent::GeminiThoughtSignaturePatch` em RubyLLM 1.9.2 captura `thoughtSignature` da response e reinjeta nas próximas requests, satisfazendo o requisito do Gemini 3 sem esperar release oficial do gem.
  - **Pricing corrigido**: tabela tinha preço de Gemini 1.5 Flash mascarado de 2.5 (subestimando custo em ~6×). Atualizada com preços oficiais 2026 + lookup smart por prefixo (modelos com sufixo `-preview-09-2026` resolvem corretamente). USD/BRL atualizado pra 5.5.
- **Pendentes opcionais (não bloqueiam piloto)**:
  - **G3** (extensões de Follow-up): cadastro de WhatsApp Business templates aprovados pela Meta, criação de conversa nova quando paciente não tem inbox aberta, A/B testing de variações de `context_brief`, dashboard de "follow-ups disparados na semana".
  - **H** (qualidade): A/B testing de personas + regen no Sentinel quando reprovar (hoje só telemetria) + LLM-as-judge async em sample 10% dos turnos.

---

## 7. Integracao entre Modulos

### 6.1 Diagrama de Dependencias

```
┌──────────────────────────────────────────────────────────┐
│                    COMUNICACAO (Chatwoot)                 │
│              [Contacts] [Inboxes] [Conversations]        │
└──────────┬───────────────────┬───────────────────────────┘
           │                   │
     contact_id           inbox (notif.)
           │                   │
┌──────────▼──────────┐  ┌─────▼──────────────────────────┐
│      PACIENTES      │  │           AGENDA                │
│   [Patient]         │  │   [AgendaEvent]                 │
│   [ClinicalNote]    │◄─┤   [AgendaService]               │
│   [TreatmentPlan]   │  │   [WaitingListEntry]            │
│   [Transaction]     │  │   [NotificationRule/Log]         │
│   [ConsentRecord]   │  └────────────────────────────────┘
│   [ExamMedia]       │
│   [Document]        │
│   [Timeline]        │
│   [AuditLog]        │
└──────────┬──────────┘
           │
   TransactionSyncService
      (bidirecional)
           │
┌──────────▼──────────┐
│    FINANCEIRO        │
│  [AccountTransaction]│
│  [FinancialCategory] │
│  [BankAccount]       │
│  [CashRegister]      │
│  [CommissionRule]     │
│  [RecurringExpense]   │
└─────────────────────┘
```

### 6.2 Conexoes Especificas

| Origem | Destino | Mecanismo |
|---|---|---|
| Agenda -> Pacientes | `AgendaEvent.contact_id` resolve para `Patient.contact_id` | Timeline do paciente registra eventos de agenda |
| Agenda -> Pacientes | `PatientAppointment.agenda_event_id` | Vinculo direto de agendamento |
| Agenda -> Prontuario | `ClinicalNote.appointment_id` / `SessionLog.appointment_id` | Evolucoes e sessoes conectadas ao evento |
| Pacientes -> Financeiro | `TransactionSyncService.on_created/on_paid/on_cancelled` | Cria/atualiza AccountTransaction |
| Financeiro -> Pacientes | `AccountTransaction.sync_back_to_patient_transaction` | Callback reverso quando central marca como recebido |
| Pacientes -> Comunicacao | `Patient.contact_id` -> Chatwoot Contact | Permite envio de documentos e notificacoes |
| Agenda -> Comunicacao | `AgendaNotificationRule.inboxes` | Notificacoes enviadas via inboxes do Chatwoot |
| Financeiro -> Agenda | `Financial::AgendaAnalyticsService` | Metricas cruzadas nos relatorios |
| Prontuario -> Comunicacao | `DocumentWhatsappSender` | Envia documentos clinicos via conversa |

### 6.3 Fluxo Integrado Completo

1. **Paciente agenda online** -> cria `AgendaEvent`.
2. **Notificacao de confirmacao** -> envia via WhatsApp (Chatwoot inbox).
3. **Lembrete 24h antes** -> `NotificationDispatcherJob` verifica e envia.
4. **Paciente chega na clinica** -> recepcionista marca `arrived`.
5. **Evolucao clinica** -> profissional registra `ClinicalNote` vinculada ao evento.
6. **Sessao realizada** -> `SessionLog` incrementa progresso do `TreatmentPlan`.
7. **Orcamento gerado** -> `FinancialEstimate` com parcelas.
8. **Transacoes criadas** -> sincronizadas para `AccountTransaction` no financeiro central.
9. **Pagamento recebido** -> financeiro central marca como recebido -> sync reverso atualiza prontuario.
10. **Documento gerado** -> receita/atestado enviado via WhatsApp.
11. **Timeline** -> todos os eventos acima sao registrados automaticamente.
12. **Auditoria** -> cada acao eh logada de forma imutavel.

---

## 8. Visao de Produto

### 8.1 Posicionamento

BeClinic eh uma plataforma de gestao clinica completa que unifica comunicacao (Chatwoot), agenda, prontuario eletronico e financeiro em um unico sistema. Posiciona-se como solucao vertical para clinicas odontologicas, esteticas e de saude que precisam de uma ferramenta integrada e acessivel.

### 8.2 Diferencial Competitivo

| Diferencial | Descricao |
|---|---|
| Comunicacao nativa | WhatsApp, Instagram, Telegram e outros canais integrados via Chatwoot — nenhum concorrente de gestao clinica oferece isso nativamente |
| Prontuario conectado | Documentos enviados diretamente via WhatsApp. Agendamentos geram notificacoes automaticas via canal de comunicacao real do paciente |
| Financeiro bidirecional | Transacoes do paciente sincronizam automaticamente com o financeiro central e vice-versa |
| DRE automatizado | Poucos softwares clinicos oferecem DRE com regime de caixa e competencia |
| Consentimento digital | Assinatura local (tablet) e remota (link) com verificacao de integridade SHA-256 |
| Auditoria LGPD | Logs imutaveis que atendem regulamentacao brasileira |
| Agendamento online | Booking publico sem necessidade de app externo |
| Timeline automatizada | 15 tipos de eventos registrados automaticamente |

### 8.3 Stack do Produto

| Camada | Tecnologia |
|---|---|
| Backend | Ruby on Rails (Chatwoot core) |
| Banco de dados | PostgreSQL com JSONB nativo |
| Frontend | Vue.js 3 (Chatwoot dashboard) |
| Jobs assincronos | Sidekiq / Active Job |
| Storage | Active Storage (S3/GCS/local) |
| PDF | Prawn (geracao server-side) |
| Notificacoes | Via Chatwoot inbox (WhatsApp, Email, etc.) |

### 8.4 Metricas de Maturidade

| Modulo | Maturidade | Justificativa |
|---|---|---|
| Agenda | **Producao** | CRUD completo, 3 visualizacoes, booking publico, notificacoes, lista de espera, relatorios |
| Pacientes | **Producao** | 12 abas, 17 sub-controllers, 17 services, timeline, auditoria imutavel, PDFs, consentimento digital |
| Financeiro | **Producao** | Dashboard KPIs, DRE, caixa fisico, contas receber/pagar, relatorios com 16 componentes, metas, comissoes |
| Configuracoes | **Producao** | Frontend robusto (agenda 154KB, financeiro 65KB), APIs completas |
| Integracao entre modulos | **Beta** | Sincronizacao bidirecional implementada; pode necessitar maturacao em edge cases complexos |

### 8.5 Volumetria de Codigo Customizado

| Area | Metrica |
|---|---|
| Models customizados | 30 entidades |
| Controllers customizados | 25+ controllers (incluindo 17 sub-controllers de pacientes) |
| Services especializados | 33 services (17 pacientes + 15 financeiro + 1 agenda) |
| Jobs assincronos | 8 jobs (5 pacientes + 2 agenda + 1 financeiro) |
| Migrations customizadas | 54 migrations (a partir de 2026-02-24) |
| Frontend pages | 22 paginas/views |
| Frontend components | 50+ componentes dedicados |
| API endpoints frontend | 25 modulos de API |
| CSS customizado | 230KB+ (patients 86KB, financial 143KB) |

---

*Documento gerado a partir de analise direta do codigo-fonte, estrutura de pastas, models, controllers, services, jobs, migrations, rotas frontend, stores, APIs e componentes Vue.*

---

## 9. Mudanças no Core (registro de auditoria)

Esta seção registra **todas as edições** feitas em arquivos do core do Chatwoot necessárias para suportar features da Klivy. Toda entrada aqui foi explicitamente aprovada antes de codar e está espelhada no documento da feature correspondente.

| Data | Arquivo | Feature/Sprint | Justificativa | Aprovação |
|---|---|---|---|---|
| 2026-05-06 | [`app/javascript/dashboard/routes/dashboard/settings/agents/EditAgent.vue`](../../app/javascript/dashboard/routes/dashboard/settings/agents/EditAgent.vue) | Bea Sprint B1.5a (multi-doutor specialties) | Vue não tem hook de extensão como Rails. Pra adicionar campo "Serviços oferecidos" no modal de Editar Agente, é necessário editar o arquivo. Backend (controller + models) fica em plugin via prepend. | ✅ Leandro, 2026-05-06 |
| 2026-05-06 | [`app/views/api/v1/models/_agent.json.jbuilder`](../../app/views/api/v1/models/_agent.json.jbuilder) | Bea Sprint B1.5b (multi-doutor specialties) | jbuilder não tem prepend. 1 linha adicionada (`json.agenda_service_ids`) pra trazer os IDs no GET /agents, evitando 2 fetches no front. Arquivo já tinha customizações Klivy (`agenda_public_id`, `klivy_role`, `beclinic_super_admin`). | ✅ Leandro, 2026-05-06 |
| 2026-05-06 | [`app/views/super_admin/accounts/bea.html.erb`](../../app/views/super_admin/accounts/bea.html.erb) | Bea Sprint E (LGPD + CFM 2.454/2026) | Fieldset "Responsável técnico" com select de User + Conselho (CRM/CRO/CRP/COREN) + número/UF. Arquivo já era Klivy (criado na fase de implementação da Bea). | ✅ pré-aprovado (arquivo Klivy) |
| 2026-05-06 | [`app/controllers/super_admin/accounts_controller.rb`](../../app/controllers/super_admin/accounts_controller.rb) | Bea Sprint E (LGPD + CFM 2.454/2026) | `bea_setting_params` ganhou 3 campos no permit (`responsible_physician_id`, `responsible_physician_council`, `responsible_physician_crm`) + normalização uppercase do conselho antes do save. Arquivo já tinha customizações Klivy (`bea`, `update_bea`, `bea_setting_params` adicionados anteriormente); manutenção da customização existente. | ✅ Leandro, 2026-05-06 (autonomia delegada) |
| 2026-05-07 | [`config/routes.rb`](../../config/routes.rb) | Bea Sprint G2 (follow-ups configuráveis) | 1 bloco `resources :ai_agent_follow_up_rules` apontando pra controller no plugin (`/ai_agent/api/v1/accounts/follow_up_rules`). Mesmo padrão já em uso em `ai_agent_documents`. | ✅ Leandro, 2026-05-07 |
| 2026-05-07 | [`app/javascript/dashboard/store/index.js`](../../app/javascript/dashboard/store/index.js) | Bea Sprint G2 (follow-ups configuráveis) | 1 import + 1 registro no `modules: { ... }` do Vuex via `@plugins/ai_agent/frontend/store/aiAgentFollowUpRules`. Vue não tem hook de extensão; mesmo padrão já em uso pra `agendaNotificationRules`, `agendaServices`, etc. | ✅ Leandro, 2026-05-07 |
| 2026-05-07 | [`app/javascript/dashboard/routes/dashboard/dashboard.routes.js`](../../app/javascript/dashboard/routes/dashboard/dashboard.routes.js) | Bea Sprint G2 (follow-ups configuráveis) | 1 import + 1 spread `...aiAgentRoutes` via `@plugins/ai_agent/frontend/routes/routes`. Mesmo padrão já em uso pra `agendaRoutes`, `patientRoutes`, etc. | ✅ Leandro, 2026-05-07 |
| 2026-05-07 | [`app/javascript/dashboard/components-next/sidebar/Sidebar.vue`](../../app/javascript/dashboard/components-next/sidebar/Sidebar.vue) | Bea Sprint G2 (follow-ups configuráveis) | Item "Follow-ups" adicionado nos children do menu BEA, apontando pra rota Vue `ai_agent_follow_ups_index`; entrada `FollowUps: ['captain', 'manage_settings']` no permission gate. Vue não tem hook de extensão (precedente B1.5a). | ✅ Leandro, 2026-05-07 |
| 2026-05-07 | [`app/controllers/public/api/v1/agenda/public_controller.rb`](../../app/controllers/public/api/v1/agenda/public_controller.rb) | Bea Sprint G2.1 (filtro `applies_to`) | 1 linha: `source: 'public_booking'` no `agenda_events.create!` do auto-agendamento online. Permite que Follow-ups distinga origem do evento (Bea / humano / booking público) sem heurística. | ✅ Leandro, 2026-05-07 |
| 2026-05-07 | [`db/migrate/20260507110000_add_source_to_agenda_events.rb`](../../db/migrate/20260507110000_add_source_to_agenda_events.rb) | Bea Sprint G2.1 (filtro `applies_to`) | Migration root (tecnicamente core do projeto): adiciona `source` em `agenda_events` (string, default `'manual'`, NOT NULL) + índice `(account_id, source)`. Eventos antigos ficam como `'manual'` automaticamente — sem backfill manual. | ✅ Leandro, 2026-05-07 |
| 2026-05-07 | [`db/migrate/20260507180000_add_default_category_to_agenda_services.rb`](../../db/migrate/20260507180000_add_default_category_to_agenda_services.rb) | Bea — categoria default por serviço | Migration root: adiciona `default_category_id` (FK pra `agenda_categories`, nullify on delete) em `agenda_services`. Permite que cada serviço tenha categoria padrão sugerida — Bea usa pra preencher `AgendaEvent.category_id` ao agendar; recepção também (pode trocar manualmente). Substitui o mapeamento por nome (que era frágil). | ✅ Leandro, 2026-05-07 |
| 2026-05-07 | [`app/views/api/v1/models/_agenda_service.json.jbuilder`](../../app/views/api/v1/models/_agenda_service.json.jbuilder) | Bea — categoria default por serviço | jbuilder partial sem hook de extensão. 1 linha (`json.default_category_id`) pra trazer o campo no GET /agenda_services. Mesmo padrão do `_agent.json.jbuilder` (Sprint B1.5b). | ✅ Leandro, 2026-05-07 |

**Sprints sem core change registradas como auditoria de transparência:**

| Sprint | Resumo | Onde mexeu | Core change? |
|---|---|---|---|
| Bea Sprint A (datetime injection) | Per-turn datetime context, holiday calendar | `plugins/ai_agent/` (novo) | ❌ Não |
| Bea Sprint B1 (search_available_slots) | Tool de busca de slots vagos | `plugins/ai_agent/tools/` (novo) | ❌ Não |
| Bea Sprint B2 (reschedule + cancel) | Tools de remarcação e cancelamento | `plugins/ai_agent/tools/` (novo) | ❌ Não |
| Bea Sprint M (memória cross-conversation 24h) | Histórico do paciente entre conversas | `plugins/ai_agent/memory/` (novo), `plugins/ai_agent/jobs/` (edit) | ❌ Não |
| Bea Sprint S (state machine determinística) | Confirmação curta + active_service intent | `plugins/ai_agent/state_machine/` (novo), `plugins/ai_agent/services/chat_service.rb` (edit) | ❌ Não |
| Bea Sprint C (emergency layer) | Detector de emergência clínica/suicida (SAMU 192 / CVV 188) antes do LLM | `plugins/ai_agent/emergency/` (novo), `plugins/ai_agent/services/chat_service.rb` (edit) | ❌ Não |
| Bea Sprint B3 (pending_confirmation + Reflection) | Eventos da Bea entram como reserva pendente; Critique determinístico antes de book/reschedule; UI badge laranja "Aguardando confirmação" | `plugins/agenda/app/models/agenda_event.rb` (edit), `plugins/ai_agent/tools/book_*.rb` e `reschedule_*.rb` (edit), `plugins/ai_agent/humanization/critique.rb` (novo), `plugins/ai_agent/services/chat_service.rb` (edit), `plugins/agenda/frontend/utils/agenda-constants.js` (edit) | ❌ Não |
| Bea Sprint G2 (motor de follow-ups) | 2 migrations (`follow_up_rules`, `follow_up_executions`), 2 models (`FollowUpRule`, `FollowUpExecution`), 2 services (`CandidateFinder`, `MessageGenerator`), 2 jobs (`FollowUpDispatcherJob` cron 1min, `SendFollowUpJob`), 1 controller REST (`FollowUpRulesController`), 1 página Vue (`Index.vue` com modal completo), 1 store Vuex, 1 API client, edit em `engine.rb` (cron). | ⚠️ Sim (4 core edits — sidebar, store, dashboard.routes, config/routes — registrados acima) |
| Bea Sprint G2.1 (filtro `applies_to` por origem) | Migration `add_applies_to_to_follow_up_rules.rb`, edit em `FollowUpRule` model (constantes + helper `agenda_source_filter`), edit em `CandidateFinder` (`filter_by_source`), edit em `book_appointment_tool` (set `source: 'ai_agent'`), edit em `Index.vue` (radio cards "Aplicar quando" + badge no card). | ⚠️ Sim (3 core edits — public_controller.rb 1 linha, migration db/migrate root, plugins/agenda/agenda_event.rb — registrados acima) |

**Procedimento padrão:**
1. Justificativa por escrito antes de editar.
2. Aprovação explícita do Leandro.
3. Entrada nesta tabela.
4. Update no doc da feature (`docs/01-product/ai-agent-configuration-plan.md` §11 ou equivalente).
5. Update no changelog quando commit for feito.
