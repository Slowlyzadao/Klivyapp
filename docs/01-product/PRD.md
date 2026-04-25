# PRD — BeClinic Platform
## Product Requirements Document (v1.0)

**Produto:** BeClinic (KlivyApp)
**Base:** Chatwoot (comunicacao omnichannel)
**Escopo deste documento:** Exclusivamente modulos customizados, adicionados sobre o core do Chatwoot.
**Data:** Abril 2026

---

## Indice

1. [Visao Executiva](#1-visao-executiva)
2. [Modulo: Agenda (Calendario Clinico)](#2-modulo-agenda-calendario-clinico)
3. [Modulo: Pacientes (Prontuario Clinico)](#3-modulo-pacientes-prontuario-clinico)
4. [Modulo: Financeiro Central](#4-modulo-financeiro-central)
5. [Modulo: Configuracoes do Sistema](#5-modulo-configuracoes-do-sistema)
6. [Integracao entre Modulos](#6-integracao-entre-modulos)
7. [Visao de Produto](#7-visao-de-produto)

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
- Notificacao de confirmacao eh disparada automaticamente ao criar evento com `contact_id`.
- `AgendaOnlineConfig` eh unico por conta (`account_id` UNIQUE).
- `AgendaSetting` eh unico por conta.
- Lista de espera impede duplicata de contato por conta.
- Campos do formulario publico possuem campos de sistema (nao removiveis): nome, sobrenome, CPF, celular, email.

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

## 6. Integracao entre Modulos

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

## 7. Visao de Produto

### 7.1 Posicionamento

BeClinic eh uma plataforma de gestao clinica completa que unifica comunicacao (Chatwoot), agenda, prontuario eletronico e financeiro em um unico sistema. Posiciona-se como solucao vertical para clinicas odontologicas, esteticas e de saude que precisam de uma ferramenta integrada e acessivel.

### 7.2 Diferencial Competitivo

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

### 7.3 Stack do Produto

| Camada | Tecnologia |
|---|---|
| Backend | Ruby on Rails (Chatwoot core) |
| Banco de dados | PostgreSQL com JSONB nativo |
| Frontend | Vue.js 3 (Chatwoot dashboard) |
| Jobs assincronos | Sidekiq / Active Job |
| Storage | Active Storage (S3/GCS/local) |
| PDF | Prawn (geracao server-side) |
| Notificacoes | Via Chatwoot inbox (WhatsApp, Email, etc.) |

### 7.4 Metricas de Maturidade

| Modulo | Maturidade | Justificativa |
|---|---|---|
| Agenda | **Producao** | CRUD completo, 3 visualizacoes, booking publico, notificacoes, lista de espera, relatorios |
| Pacientes | **Producao** | 12 abas, 17 sub-controllers, 17 services, timeline, auditoria imutavel, PDFs, consentimento digital |
| Financeiro | **Producao** | Dashboard KPIs, DRE, caixa fisico, contas receber/pagar, relatorios com 16 componentes, metas, comissoes |
| Configuracoes | **Producao** | Frontend robusto (agenda 154KB, financeiro 65KB), APIs completas |
| Integracao entre modulos | **Beta** | Sincronizacao bidirecional implementada; pode necessitar maturacao em edge cases complexos |

### 7.5 Volumetria de Codigo Customizado

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
