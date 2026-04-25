> [!IMPORTANT]
> **Nota de Auditoria Arquitetural Atualizada:** 
> O texto a seguir contém a Especificação Histórica das Regras de Negócio deste módulo.
> Em nível sistêmico (código, frontend, backend e Banco de Dados), todas as estruturas listadas abaixo encontram-se 100% isoladas na Arquitetura Modular (Rails Engines), localizadas especificamente dentro do seu diretório `plugins/`. O modelo de banco de dados original do Chatwoot citado como destino de colunas no documento abaixo já foi refatorado utilizando Satélites DB Profiles (`beclinic_profiles`) visando prevenir colisões de migrações nativas do Chatwoot no longo prazo.
> Leia `02-architecture/system-architecture.md` para visualizar as ligações sistêmicas exatas em código. Tudo detalhado abaixo responde ao Produto e Usuário.

# Plano de Backend: Prontuário Eletrônico do Paciente (BeClinic)

> **Versão 2.2** — Atualizado em 2026-03-07 com status de implementação dos Blocos 1–3.

---

## 🚦 Status de Implementação (atualizado 2026-03-07)

| Bloco | Descrição | Status | Versão |
|-------|-----------|--------|--------|
| **Bloco 1** | Fundação de Dados (Patient, CriticalAlert, FormTemplate, PatientAuditLog, CashEntry) | ✅ **CONCLUÍDO** | v1.2.0.0 |
| **Bloco 2** | Módulo Clínico Core (Anamnese + Evolução Clínica) | ✅ **CONCLUÍDO** | v1.2.1.0 |
| **Bloco 3** | Plano de Tratamento + Itens + Sessões | ✅ **CONCLUÍDO** | v1.2.2.0 |
| **Bloco 4** | Financeiro do Paciente (FinancialEstimate + Transaction + Installment) | ✅ **CONCLUÍDO** | v1.2.3.0 |
| **Bloco 5** | Mídia, Documentos e Consentimentos (ExamMedia + Document + ConsentRecord) | ✅ **CONCLUÍDO** | v1.2.4.0 |
| **Bloco 6** | Agenda do Paciente + Timeline | ✅ **CONCLUÍDO** | v1.2.5.0 |
| **Bloco 7** | Auditoria + Permissões + Exportação PDF prontuário | ✅ **CONCLUÍDO** | v1.2.6.0 |

### O que foi feito no Bloco 1 e por quê:
- **5 migrations criadas** (`patients`, `critical_alerts`, `form_templates`, `patient_audit_logs`, `cash_entries`) — formam a espinha dorsal do prontuário.
- **`Patient`** é a entidade-mãe de todo o sistema. Usa JSONB para dados complexos (endereço, seguros, LGPD) sem sub-tabelas.
- **`CriticalAlert`** com severidades (low/medium/high) — alimenta o banner vermelho do prontuário visível para toda a equipe.
- **`FormTemplate`** global — templates de anamnese/evolução reutilizáveis por especialidade.
- **`PatientAuditLog`** imutável — callbacks Ruby bloqueiam UPDATE e DESTROY; cada acesso ao prontuário gera um log automático.
- **`CashEntry`** stub — "nivelar o terreno": o módulo financeiro do paciente (Bloco 4) vai injetar entradas aqui via baixa dupla, sem precisar refatorar a fundação.
- **Policies Pundit** para acesso controlado por perfil.
- **Endpoint estrela** `GET /summary` — payload consolidado para o dashboard do paciente.

### O que foi feito no Bloco 2 e por quê:
- **`Anamnesis`** com versionamento: cada `POST` cria nova linha numerada, nunca sobrescreve. Base legal exige histórico imutável.
- **`AnamnesisFinalizerService`**: ao finalizar a anamnese, varre alergias severas e contraindições → cria `CriticalAlert` automaticamente. Reduz erro humano.
- **`ClinicalNote`** com janela de 48h: draft editável → assinatura trava a nota com HTTP 403. Requisito jurídico para prontuários.
- **`ClinicalNoteSignerService`**: registra `signed_by_id`, `signed_at`, bloqueia edição futura.
- **`PatientTimelineEventJob`**: job central reutilizado por TODOS os módulos seguintes para registrar eventos cronológicos de forma assíncrona (não trava o request).

### O que foi feito no Bloco 3 e por quê:
- **`TreatmentPlan`** → entidade comercial-clínica central. Status: proposto → aprovado → em_execucao → concluido/cancelado.
- **`TreatmentItem`**: cada procedimento do plano com preço, sessões planejadas/realizadas e progresso calculado.
- **`SessionLog`**: sessão executada imutável. JSONB `products_used[]` preparado para módulo de Estoque futuro.
- **`TreatmentPlanApprover`**: aprova total ou parcialmente por `item_ids[]`. Trigger para geração automática do orçamento (Bloco 4).
- **`IncrementTreatmentSessionJob`**: incrementa `sessions_done` assincronamente → frontend recebe 201 imediato.
- **`UpdateTreatmentPlanStatusJob`**: recalcula status do plano (`concluido` quando todos os itens done).

### O que foi feito no Bloco 4 e por quê:
- **`FinancialEstimate`**, **`Transaction`** e **`Installment`**: modelos criados para sustentar todo o orçamentário. Calcula dinamicamente subtotais e os `totals` (com suporte a descontos percentuais ou reais).
- **`FinancialEstimateGenerator` (Service)**: O "cérebro" da venda. Acoplado para rodar *após* a aprovação em `TreatmentPlanApprover`. Cria o orçamento automaticamente para não deixar a secretária fazer dois steps manuais.
- **`InstallmentPayService` (Service)**: A Baixa Dupla. Quando executa `PATCH /pay` via controller, a magia acontece: muda o status da parcela do paciente E injeta autonomamente dinheiro dentro da tabela `cash_entries` (caixa principal), fechando o gap de arquitetura.
- **`charge_whatsapp` (Endpoint)**: Gera o payload cru para disparar notificação passiva via WhatsApp conectando aos módulos existentes.
- **`refund` (Endpoint)**: Gera lançamentos negativos para fechar o caixa corretamente em caso de estorno, não permitindo exclusão (`DELETE`) em itens já pagos mantendo o rastreamento via _Audit_.
- Integrado tudo na sub-rota `/api/v1/accounts/:account_id/patients/:patient_id/...` completando todo funil financeiro local.

### O que foi feito no Bloco 5 e por quê:
- **`ExamMedia`**: Gerenciamento de exames e fotos clínicas via Active Storage com suporte a `signed_url` de 15 minutos para privacidade absoluta, evitando URLs públicas. Também possui endpoint `compare` nativo para slider Antes/Depois no front.
- **`Document`**: Representa receitas, atestados e pedidos. Integrado nativamente a um serviço de emissão PDF (`PdfGenerator`) utilizando `Prawn` e a outro serviço (`DocumentWhatsappSender`) para repasse ao paciente, possuindo versionamento rígido.
- **`ConsentRecord`**: Segurança judiciária. Qualquer assinatura salva passa por uma digestão de base64 criando um `#integrity_hash` SHA-256 inquebrável no banco. Se os dados forem modificados no banco direto, o hash quebra. Opção de envio remoto via Token único habilitada.

### O que foi feito no Bloco 6 e por quê:
- **`PatientAppointment`**: Tabela central contendo todo o ciclo de vida do agendamento (Avaliação, Retorno, Procedimento), independente da tabela legada geral da clínica, mas podendo ligar ao `agenda_event_id` por foreign key. Adotado esquema rígido de status (agendado, chegado, concluído, falta, cancelado).
- **`PatientTimelineEvent` e `RecordTimelineEventJob`**: Criado ecossistema da Timeline purificada. O "evento" é materializado na tabela e no mesmo Job grava paralelamente de forma obrigatória no `PatientAuditLog` para tracking em background.
- **`AppointmentScheduler` e `AppointmentRescheduler` (Services)**: Services com bloqueios cross-module. Exemplo: A avaliação bloqueia agendar se o paciente estiver `overdue` financeiramente (Bloco 4). Também acionam o Job da Timeline automaticamente em caso de remarcação e criação.
- **Recall Sender**: Endpoint `POST /recall` com service próprio para construir o texto do lembrete de WhatsApp baseando-se no último procedimento feito e retornando o payload pronto para o chatwoot enviar por fora. Atualiza automaticamente a flag dinâmica `needs_recall` feita no Model do `Patient`.

---


## ✅ Decisões Arquiteturais Confirmadas (2026-03-07)

| Questão | Decisão | Razão |
|---------|---------|-------|
| **Auditoria** | Tabela própria **`patient_audit_logs`** | Mais controle, payload customizado, separado da gem `audited` existente |
| **PDF** | **Prawn** (100% Ruby, sem dependências externas) | Sem wkhtmltopdf/puppeteer, compila limpo no Docker, ótimo suporte a fontes e layout |
| **Caixa Geral** | Tabela stub **`cash_entries`** criada no Bloco 1 | "Nivelar o terreno" — dados financeiros são irreversíveis; quando o módulo Financeiro Mestre existir, apenas conectar via `source_id` polimórfico |

> **Schema `cash_entries` (stub):**
> ```ruby
> t.bigint  "account_id", null: false
> t.string  "entry_type", null: false    # income / expense / refund
> t.decimal "amount"
> t.string  "description"
> t.string  "source_type"               # "Transaction" (polimórfico)
> t.bigint  "source_id"
> t.string  "payment_method"            # pix / cartao / dinheiro / boleto
> t.date    "entry_date", null: false
> t.bigint  "patient_id"                # referência ao paciente
> t.bigint  "registered_by_id"
> t.jsonb   "metadata", default: {}     # dados extras para conexão futura
> t.datetime "deleted_at"
> t.timestamps
> ```

---

## 0. Arquitetura Geral

### 0.1 Convenção de Rotas

Todas as rotas seguem REST aninhado sob o paciente:

```
/api/v1/patients/:patient_id/<recurso>
```

Rotas de escopo global (Auditoria, Formulários) ficam em namespace próprio:

```
/api/v1/audit_logs
/api/v1/form_templates
```

### 0.2 Entidades do Banco (Tabelas Principais)

| Modelo               | Descrição                                                |
|----------------------|----------------------------------------------------------|
| `Patient`            | Mestre cadastral do paciente                             |
| `CriticalAlert`      | Alertas fixados (alergia, gestante, hipertenso…)        |
| `Anamnesis`          | Questionário clínico inicial, versionado                 |
| `ClinicalNote`       | Evolução por consulta (imutável após assinatura)         |
| `TreatmentPlan`      | Plano proposto (pai dos procedimentos)                   |
| `TreatmentItem`      | Procedimento individual dentro do plano                  |
| `SessionLog`         | Sessão executada (o que realmente aconteceu)             |
| `Appointment`        | Agendamento (passado, futuro, falta, cancelado)          |
| `ExamMedia`          | Arquivos: imagens, PDFs, DICOM, vídeos                   |
| `Document`           | Documentos gerados: receita, atestado, laudo, contrato   |
| `ConsentRecord`      | Termo de consentimento com tracking de assinatura        |
| `FinancialEstimate`  | Orçamento vinculado ao plano aprovado                    |
| `Transaction`        | Lançamento financeiro (entrada, parcela, reembolso)      |
| `Installment`        | Parcela de uma transação parcelada                       |
| `FormTemplate`       | Modelos de anamnese, evolução, consentimento             |
| `AuditLog`           | Registro imutável de toda ação no prontuário             |
| `PatientTimelineEvent` | Eventos consolidados para a Timeline visual            |

### 0.3 Regras de Negócio Cross-Módulo (Grafo de Dependências)

Este é o ponto mais crítico. Os módulos **não são ilhas** — eles se alimentam mutuamente:

```
Anamnese ──────────────────────► CriticalAlert (ex: alergia detectada)
                                        │
                                        ▼
                            Aba Geral / Banner de Alertas
                                        │
ConsentRecord (pendente) ───────────────┤
                                        ▼
                            Aba Consentimentos (alerta vermelho)

TreatmentPlan (aprovado) ──────────► FinancialEstimate (gerado automaticamente)
                                        │
                                        ▼
SessionLog (sessão realizada) ──► Transaction (parcela marcada como usada)
     │                            + Dedução de Estoque (se integrado)
     │
     └──────────────────────────► PatientTimelineEvent (entrada na Timeline)

ClinicalNote (assinada) ──────────► AuditLog (bloqueio de edição registrado)
     │
     └──────────────────────────► PatientTimelineEvent

Appointment (falta/no-show) ──────► needs_recall flag no Patient
                                        │
                                        ▼
                            Aba Agenda (banner laranja de retorno vencido)
```

---

## Aba 1: Geral (Dashboard do Paciente)

**Propósito:** Responder em segundos "quem é esse paciente?". Visão operacional rápida para toda a equipe.

### Endpoints

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/api/v1/patients/:id/summary` | Payload consolidado do dashboard |
| `PATCH` | `/api/v1/patients/:id/status` | Atualiza status do paciente |
| `POST` | `/api/v1/patients/:id/quick_action` | Atalhos rápidos (agendar, cobrar, iniciar atendimento) |

### Payload de Retorno (`GET summary`)

```json
{
  "id": 1,
  "name": "Maria Joaquina Santos",
  "avatar_url": "https://cdn.beclinic.com/...",
  "age": 34,
  "birthdate": "1990-05-18",
  "sex": "F",
  "phone": "+5511999990000",
  "whatsapp": "+5511999990000",
  "email": "maria@email.com",
  "document_cpf": "123.456.789-00",
  "insurance": { "type": "particular" },
  "origin": "indicacao",
  "unit": "Matriz SP",
  "responsible_professional": { "id": 3, "name": "Dra. Amanda" },
  "last_appointment": "2026-02-10",
  "next_appointment": "2026-04-10",
  "patient_status": "em_tratamento",
  "needs_recall": false,
  "critical_alerts": [
    { "type": "allergy", "label": "Alérgica a Lidocaína", "severity": "high" },
    { "type": "condition", "label": "Hipertensa", "severity": "medium" }
  ],
  "pinned_note": "Paciente ansiosa. Preferência por atendimento sem espera.",
  "active_treatment_summary": "Fios de PDO (3 sessões restantes de 5)",
  "financial_status": {
    "balance_due": 5000.00,
    "credit": 0.00,
    "status": "em_aberto"
  }
}
```

### Regras de Negócio

- `critical_alerts` é populado a partir de dois lugares: `CriticalAlert` fixados manualmente + campos da `Anamnesis` (`allergies`, `conditions`) que possuem flag `show_as_critical: true`.
- `patient_status` aceita os enums: `novo`, `em_avaliacao`, `em_tratamento`, `alta`, `inativo`, `faltoso`.
- `needs_recall` é calculado pelo banco: se `last_appointment` existe e não há `Appointment` futuro dentro da janela de retorno definida pelo último procedimento, a flag é `true`.
- **Botões de Ação Rápida** no frontend disparam rotas secundárias: `POST /appointments` (Agendar), `POST /transactions/charge` (Cobrar), `PATCH /clinical_notes/start` (Iniciar Atendimento).

---

## Aba 2: Cadastro (Ficha Administrativa)

**Propósito:** Dados administrativos completos e editáveis. Separado do clínico.

### Endpoints

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/api/v1/patients/:id` | Dados completos do paciente |
| `PATCH` | `/api/v1/patients/:id` | Atualização parcial (cadastro progressivo) |
| `GET` | `/api/v1/patients/:id/change_history` | Histórico de alterações do cadastro |

### Estrutura do Payload (`PATCH`)

```json
{
  "personal_info": {
    "name": "Maria Joaquina Santos",
    "birthdate": "1990-05-18",
    "sex": "F",
    "cpf": "123.456.789-00",
    "rg": "12.345.678-9"
  },
  "address": {
    "street": "Rua das Flores, 100",
    "city": "São Paulo",
    "state": "SP",
    "zip": "01234-567"
  },
  "contacts": [
    { "type": "phone", "value": "+5511999990000", "label": "Pessoal" },
    { "type": "email", "value": "maria@email.com" }
  ],
  "emergency_contact": {
    "name": "João Santos",
    "relationship": "Marido",
    "phone": "+5511888880000"
  },
  "legal_guardian": null,
  "insurance": { "provider": "Unimed", "plan": "Executivo", "card_number": "123456" },
  "billing_info": { "same_as_address": true },
  "contact_preferences": { "preferred_channel": "whatsapp", "best_time": "tarde" },
  "communication_opt_ins": { "sms": true, "email": false, "whatsapp": true },
  "lgpd_consent": { "accepted": true, "accepted_at": "2026-02-10T14:00:00Z" },
  "image_use_consent": { "accepted": true }
}
```

### Regras de Negócio

- **Cadastro progressivo:** `PATCH` deve funcionar com qualquer subconjunto de campos. Nenhum campo além de `name` e `phone` deve ser obrigatório no momento da criação inicial.
- **Validações graduais:** CPF obrigatório apenas quando `billing_info` for usado (geração de nota fiscal). Email obrigatório apenas se `communication_opt_ins.email = true`.
- **Histórico de Alterações:** Toda mutação no `Patient` deve persistir um registro em `AuditLog` com `{ field, old_value, new_value, changed_by, changed_at }`. O endpoint `GET /change_history` expõe essa leitura filtrada ao cadastro.

---

## Aba 3: Anamnese

**Propósito:** Questionário clínico estruturado, versionado. Base para alertas críticos automáticos.

### Endpoints

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/api/v1/patients/:id/anamnesis` | Retorna versão ativa |
| `GET` | `/api/v1/patients/:id/anamnesis/history` | Retorna todas as versões |
| `POST` | `/api/v1/patients/:id/anamnesis` | Cria nova versão (imutável ao finalizar) |
| `PATCH` | `/api/v1/patients/:id/anamnesis/:id/finalize` | Trava a versão como read-only |

### Estrutura de Campos

A anamnese é **estruturada**, não texto livre. Campos chave:

```json
{
  "template_id": 2,
  "specialty": "estetica_facial",
  "chief_complaint": "Linhas de expressão na testa e ao redor dos olhos",
  "medical_history": { "hypertension": true, "diabetes": false, "thyroid": false },
  "allergies": [
    { "substance": "Lidocaína", "reaction": "urticária", "severity": "high" }
  ],
  "current_medications": [
    { "name": "Losartana 50mg", "frequency": "1x/dia" }
  ],
  "surgical_history": "Apendicectomia em 2015",
  "family_history": "Mãe diabética",
  "pregnancy": { "pregnant": false, "breastfeeding": false },
  "relevant_habits": { "smoker": false, "alcohol": "social", "physical_activity": "regular" },
  "contraindications": [],
  "additional_notes": "Texto livre complementar da avaliação",
  "status": "draft"
}
```

### Regras de Negócio

- **Trigger de Alerta Crítico:** Ao finalizar (`PATCH finalize`), o backend varre o payload e para cada `allergy` com `severity: "high"` ou campo médico marcado como `true` (ex: `hypertension`), cria/atualiza registros na tabela `CriticalAlert` do paciente. Esses alertas aparecem automaticamente na Aba Geral.
- **Versionamento:** Nunca sobrescrever. `POST` sempre cria uma nova linha com `version_number` incrementado. A versão ativa é a mais recente com `status: "finalized"`.
- **Templates por especialidade (`template_id`):** O campo `specialty` direciona o frontend a carregar o `FormTemplate` adequado (ex: bateria de perguntas diferente para odontologia vs estética corporal).

---

## Aba 4: Evolução / Atendimento

**Propósito:** Registro cronológico legal do que aconteceu em cada consulta. Núcleo do prontuário clínico.

### Endpoints

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/api/v1/patients/:id/clinical_notes` | Lista todas as evoluções (timeline) |
| `GET` | `/api/v1/patients/:id/clinical_notes/:id` | Detalhe de uma evolução |
| `POST` | `/api/v1/patients/:id/clinical_notes` | Cria nova nota (draft) |
| `PATCH` | `/api/v1/patients/:id/clinical_notes/:id` | Edita rascunho (apenas status draft) |
| `PATCH` | `/api/v1/patients/:id/clinical_notes/:id/sign` | Assina e trava a evolução |
| `POST` | `/api/v1/patients/:id/clinical_notes/:id/addendum` | Cria adendo a uma nota já assinada |

### Estrutura

```json
{
  "appointment_id": 45,
  "professional_id": 3,
  "note_date": "2026-02-10T15:30:00Z",
  "template_id": 1,
  "complaint_of_day": "Leve sensibilidade na área tratada",
  "assessment": "Resultado satisfatório na testa. Área dos olhos com efeito parcial.",
  "conduct": "Reaplicação de 4U em canto externo OD. Orientada quanto ao período de ação.",
  "complications": null,
  "guidance_given": "Não deitar por 4h. Evitar atividade física intensa.",
  "return_recommended": "2026-05-10",
  "attachments": [12, 14],
  "status": "draft"
}
```

### Regras de Negócio

- **Bloqueio após assinatura:** `status: "signed"` ativa uma guard no backend que retorna `HTTP 403` para qualquer `PATCH` ou `DELETE` na nota. A única saída é criar um `addendum`.
- **Janela de edição draft:** Configurável pela clínica (padrão: 48h). Após esse prazo, o sistema auto-assina ou bloqueia a edição, conforme regra da clínica.
- **Geração de evento na Timeline:** Toda nota criada dispara um job assíncrono que insere um `PatientTimelineEvent` do tipo `clinical_note`.
- **Vinculação ao Agendamento:** `appointment_id` obrigatório. Isso garante que toda evolução seja rastreável a uma consulta específica.

---

## Aba 5: Plano de Tratamento

**Propósito:** O que foi planejado pelo profissional e negociado comercialmente com o paciente.

### Endpoints

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/api/v1/patients/:id/treatment_plans` | Lista todos os planos |
| `POST` | `/api/v1/patients/:id/treatment_plans` | Cria novo plano |
| `PATCH` | `/api/v1/patients/:id/treatment_plans/:id/approve` | Paciente aprova o plano |
| `POST` | `/api/v1/patients/:id/treatment_plans/:id/items` | Adiciona item ao plano |
| `PATCH` | `/api/v1/patients/:id/treatment_plans/:id/items/:item_id` | Edita item (dente, região, qtd sessões) |
| `DELETE` | `/api/v1/patients/:id/treatment_plans/:id/items/:item_id` | Remove item do plano |

### Estrutura de um TreatmentItem

```json
{
  "procedure_code": "10101",
  "procedure_name": "Toxina Botulínica - Região Frontal",
  "region": "fronte",
  "tooth_number": null,
  "sessions_planned": 3,
  "sessions_done": 1,
  "unit_price": 800.00,
  "total_price": 2400.00,
  "priority": "high",
  "status": "approved",
  "clinical_justification": "Hiperatividade muscular com linhas de expressão estáticas",
  "estimated_start": "2026-02-10",
  "professional_id": 3
}
```

### Regras de Negócio

- **Status do Plano:** enum `proposto → aprovado (parcial / total) → em_execucao → concluido / cancelado`.
- **Trigger financeiro:** Ao `PATCH approve`, o backend dispara um `Service` que cria automaticamente um `FinancialEstimate` na tabela financeira com o valor total do plano e sugere parcelamento conforme configuração da clínica. O recepcionista só precisa confirmar.
- **Progresso de sessões:** `sessions_done` é incrementado automaticamente a cada `SessionLog` criado com `treatment_item_id` referenciando aquele item.

---

## Aba 6: Procedimentos / Sessões

**Propósito:** O que foi efetivamente executado. Registro operacional de cada sessão.

### Endpoints

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/api/v1/patients/:id/session_logs` | Lista sessões (filtrável por data, profissional, tipo) |
| `POST` | `/api/v1/patients/:id/session_logs` | Registra nova sessão executada |
| `GET` | `/api/v1/patients/:id/session_logs/:id` | Detalhe de uma sessão |

### Estrutura de SessionLog

```json
{
  "appointment_id": 45,
  "treatment_item_id": 12,
  "professional_id": 3,
  "procedure_name": "Toxina Botulínica - Frontal (Sessão 1/3)",
  "performed_at": "2026-02-10T15:00:00Z",
  "duration_minutes": 40,
  "areas_treated": ["frontal", "glabela"],
  "products_used": [
    {
      "product_id": 7,
      "product_name": "Botox 100U - Allergan",
      "batch_number": "LOT-2026-B44",
      "expiration_date": "2027-01-01",
      "quantity_used": 20
    }
  ],
  "complications": null,
  "result_observed": "Relaxamento muscular adequado. Sem intercorrências.",
  "post_procedure_guidance": "Evitar exercício por 24h. Não massagear a área.",
  "return_needed": true,
  "return_in_days": 90,
  "media_attachments": [18, 19]
}
```

### Regras de Negócio

- **Dedução de Estoque:** Se o módulo de Estoque estiver ativo, o `POST` dispara um job que desconta `quantity_used` do lote `batch_number` registrado. Lotes vencidos são bloqueados no frontend.
- **Incremento de Sessões no Plano:** Após criar o `SessionLog`, o backend atualiza `TreatmentItem.sessions_done += 1`. Se `sessions_done == sessions_planned`, o item muda para `status: "concluido"`.
- **Filtros:** `GET session_logs?procedure_type=toxina&professional_id=3&from=2026-01-01&to=2026-03-31`

---

## Aba 7: Exames e Imagens

**Propósito:** Galeria digitalizada de toda documentação visual e laboratorial.

### Endpoints

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/api/v1/patients/:id/exams` | Lista arquivos (filtrável por categoria) |
| `POST` | `/api/v1/patients/:id/exams` | Upload (multipart/form-data) |
| `PATCH` | `/api/v1/patients/:id/exams/:id` | Edita metadados (categoria, descrição) |
| `DELETE` | `/api/v1/patients/:id/exams/:id` | Exclusão lógica (soft delete) |
| `GET` | `/api/v1/patients/:id/exams/compare` | Retorna par de imagens para comparação before/after |

### Categorias Suportadas (enum)

`rx`, `tomografia`, `foto_clinica`, `antes_depois`, `intraoral`, `laudo`, `laboratorial`, `video`, `outro`

### Regras de Negócio

- **Armazenamento:** Arquivos vão para S3/GCS. O backend salva apenas a `storage_key` e devolve URLs assinadas com expiração de 15min para o frontend. Nunca expor URL pública permanente.
- **Vinculação contextual:** Cada arquivo pode ter `session_log_id` OU `appointment_id` opcionais. Isso permite o frontend mostrar "Fotos desta sessão" ao abrir o SessionLog.
- **Comparação Before/After:** `GET /exams/compare?left_id=5&right_id=12` — backend retorna as duas URLs assinadas. Frontend renderiza o slider side-by-side.
- **Vídeos:** Tamanho máximo configurável (padrão 100MB). Backend valida MIME type no upload.

---

## Aba 8: Documentos

**Propósito:** Gestão de documentos formais gerados ou anexados ao prontuário.

### Endpoints

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/api/v1/patients/:id/documents` | Lista documentos (filtrável por tipo, status) |
| `POST` | `/api/v1/patients/:id/documents/generate` | Gera PDF server-side a partir de template |
| `POST` | `/api/v1/patients/:id/documents/attach` | Anexa PDF externo (multipart) |
| `GET` | `/api/v1/patients/:id/documents/:id/download` | URL assinada para download/preview |
| `POST` | `/api/v1/patients/:id/documents/:id/send_whatsapp` | Envia documento pelo gateway WhatsApp |
| `PATCH` | `/api/v1/patients/:id/documents/:id/status` | Atualiza status (gerado → assinado → pendente) |

### Tipos de Documento (enum)

`receita`, `atestado`, `pedido_exame`, `declaracao`, `relatorio_clinico`, `encaminhamento`, `contrato`, `orcamento`, `instrucao_procedimento`, `questionario`, `outro`

### Regras de Negócio

- **Geração de PDF:** `POST /generate` recebe `{ template_id, variables }`. O backend preenche o template HTML com os dados do paciente/profissional e converte para PDF (PDFKit, WickedPDF ou Puppeteer headless). Salva o arquivo no storage e registra na tabela `Document`.
- **Versionamento:** Documentos nunca são sobrescritos. Cada regeneração cria uma nova linha com `version: 2, 3...`. O frontend exibe a versão mais recente por padrão.
- **Status:** enum `gerado → pendente_assinatura → assinado → enviado → arquivado`.

---

## Aba 9: Consentimentos e Assinaturas

**Propósito:** Gestão jurisdicional dos termos sensíveis com rastreabilidade legal completa.

### Endpoints

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/api/v1/patients/:id/consents` | Lista consentimentos com status |
| `POST` | `/api/v1/patients/:id/consents` | Cria novo requerimento de consentimento |
| `POST` | `/api/v1/patients/:id/consents/:id/sign` | Registra assinatura (local ou remota) |
| `POST` | `/api/v1/patients/:id/consents/:id/send_remote` | Envia link para o celular do paciente |
| `GET` | `/api/v1/patients/:id/consents/pending` | Retorna apenas pendências do dia |

### Payload de Assinatura (`POST sign`)

```json
{
  "mode": "local_tablet",
  "signature_blob": "data:image/png;base64,iVBORw0KGg...",
  "ip_address": "192.168.1.100",
  "device_info": "iPad Pro - Safari 17",
  "signed_at": "2026-03-07T14:30:00Z"
}
```

### Regras de Negócio

- **Hash de integridade:** Ao salvar a assinatura, o backend gera `SHA-256(patient_id + consent_id + signature_blob + signed_at)` e persiste o hash. Qualquer adulteração futura torna o hash inválido.
- **Alerta cross-módulo:** O endpoint `GET /summary` (Aba Geral) consulta `GET /consents/pending` e injeta os pendentes no payload como `{ urgent_consent_required: true }`. O frontend usa essa flag para exibir o alerta vermelho.
- **Expiração:** Consentimentos podem ter `expires_after_days` (ex: consentimento de Botox válido por 12 meses). Backend calcula automaticamente o status `vencido` ao retornar a listagem.
- **Status:** enum `pendente → assinado_localmente → assinado_remotamente → vencido → revogado`.

---

## Aba 10: Financeiro do Paciente

**Propósito:** Ciclo financeiro isolado do paciente — não o caixa geral da clínica.

### Endpoints

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/api/v1/patients/:id/financial_summary` | KPIs: total, pago, devedor, crédito |
| `GET` | `/api/v1/patients/:id/transactions` | Extrato completo de lançamentos |
| `POST` | `/api/v1/patients/:id/transactions` | Cria lançamento manual |
| `PATCH` | `/api/v1/patients/:id/transactions/:id/pay` | Baixa financeira de uma parcela |
| `POST` | `/api/v1/patients/:id/transactions/:id/charge_whatsapp` | Dispara cobrança pelo WhatsApp |
| `POST` | `/api/v1/patients/:id/transactions/:id/refund` | Registra reembolso |

### Payload `GET financial_summary`

```json
{
  "total_approved": 12500.00,
  "total_paid": 7500.00,
  "total_overdue": 2500.00,
  "total_open": 2500.00,
  "credit_balance": 0.00,
  "overall_status": "em_aberto",
  "next_due_date": "2026-04-10",
  "next_due_amount": 2500.00
}
```

### Regras de Negócio

- **Geração automática de orçamento:** Aprovação do `TreatmentPlan` dispara `Service::FinancialEstimateGenerator` que cria o `FinancialEstimate` e parcelas sugeridas. Recepcionista confirma sem redigitar nada.
- **Baixa financeira dupla:** `PATCH /pay` fecha a `Transaction` do paciente E injeta uma entrada positiva no `CashEntry` geral da clínica (Financeiro Mestre). Garante consistência dos dois módulos.
- **Bloqueio por inadimplência (opcional):** Se o paciente tiver `overdue > 0` e a clínica tiver a regra ativa, o sistema pode bloquear a marcação de novos agendamentos (retorna `HTTP 422` com `reason: "patient_overdue"`).
- **Reembolsos:** `POST /refund` cria uma `Transaction` de tipo `reembolso` com valor negativo e atualiza `credit_balance`.

---

## Aba 11: Agenda e Histórico de Consultas

**Propósito:** Linha do tempo operacional de todos os agendamentos do paciente.

### Endpoints

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/api/v1/patients/:id/appointments` | Lista agendamentos (com filtros) |
| `POST` | `/api/v1/patients/:id/appointments` | Cria novo agendamento |
| `PATCH` | `/api/v1/patients/:id/appointments/:id/reschedule` | Reagenda |
| `PATCH` | `/api/v1/patients/:id/appointments/:id/cancel` | Cancela |
| `PATCH` | `/api/v1/patients/:id/appointments/:id/no_show` | Marca como falta |
| `POST` | `/api/v1/patients/:id/recall` | Dispara lembrete de retorno via WhatsApp |

### Filtros suportados

`?status=scheduled,done,no_show,canceled,rescheduled&from=2026-01-01&to=2026-12-31`

### Regras de Negócio

- **Flag `needs_recall`:** Calculada no banco via query: `SELECT * FROM appointments WHERE patient_id = X AND status = 'done' ORDER BY date DESC LIMIT 1` → se a data do último atendimento + janela_de_retorno_do_procedimento < HOJE e não existe `appointment` futuro → `needs_recall = true`.
- **Marcação de falta:** `PATCH /no_show` incrementa `Patient.no_show_count`. Se `no_show_count >= 3` (configurável), o status do paciente muda para `faltoso`.
- **Tipo de consulta:** enum `avaliacao`, `retorno`, `procedimento`, `revisao`, `emergencia`.
- **Integração Timeline:** Toda mutação de status em um `Appointment` (marcado, cancelado, falta) insere um `PatientTimelineEvent`.

---

## Aba 12: Timeline

**Propósito:** Visão cronológica consolidada de toda a jornada do paciente. Leitura única, sem edição.

### Endpoints

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/api/v1/patients/:id/timeline` | Lista todos os eventos em ordem cronológica |

### Payload

```json
{
  "events": [
    {
      "id": 1,
      "type": "cadastro",
      "label": "Paciente cadastrada no sistema",
      "actor": "Recepção (Maria)",
      "occurred_at": "2026-01-15T09:00:00Z",
      "reference_id": null,
      "reference_type": null
    },
    {
      "id": 2,
      "type": "appointment_done",
      "label": "Consulta realizada: Avaliação + Sessão #1",
      "actor": "Dra. Amanda",
      "occurred_at": "2026-02-10T15:00:00Z",
      "reference_id": 45,
      "reference_type": "Appointment"
    },
    {
      "id": 3,
      "type": "payment",
      "label": "Pagamento recebido: R$ 5.000,00 (PIX)",
      "actor": "Recepção",
      "occurred_at": "2026-02-10T16:00:00Z",
      "reference_id": 12,
      "reference_type": "Transaction"
    }
  ]
}
```

### Tipos de Evento Mapeados

| type | Origem |
|------|--------|
| `cadastro` | Criação do Patient |
| `anamnesis_filled` | Finalização da Anamnese |
| `appointment_scheduled` | Novo Appointment |
| `appointment_done` | Appointment marcado como concluído |
| `appointment_no_show` | Falta registrada |
| `appointment_canceled` | Cancelamento |
| `clinical_note` | ClinicalNote criada/assinada |
| `session_performed` | SessionLog criado |
| `exam_uploaded` | ExamMedia adicionado |
| `document_generated` | Document gerado |
| `consent_signed` | ConsentRecord assinado |
| `payment` | Transaction de pagamento |
| `refund` | Transaction de reembolso |
| `status_changed` | Mudança em Patient.status |
| `discharge` | Alta do paciente |

### Regras de Negócio

- **Geração de eventos:** Todo módulo do sistema, ao criar ou mudar estado de um registro relevante, dispara um job assíncrono (`PatientTimelineEventJob`) que insere o evento. O dado não é calculado em tempo real — é materializado.
- **`reference_id / reference_type`:** Permite ao frontend exibir um botão "Ver detalhe" que abre diretamente o recurso correspondente na aba correta (ex: clicou no evento `clinical_note` → abre Aba 4 na nota específica).
- **Filtros opcionais:** `?type=payment,appointment_done&from=2026-01-01`

---

## Aba 13: Formulários / Modelos

**Propósito:** Biblioteca de templates que padroniza e agiliza a operação clínica.

### Endpoints

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/api/v1/form_templates` | Lista templates disponíveis (global) |
| `GET` | `/api/v1/form_templates/:id` | Detalhe e estrutura de fields do template |
| `POST` | `/api/v1/form_templates` | Cria novo template (admin) |
| `PATCH` | `/api/v1/form_templates/:id` | Edita template |
| `DELETE` | `/api/v1/form_templates/:id` | Desativa template |

### Tipos de Template

| type | Usado em |
|------|----------|
| `anamnesis` | Aba Anamnese — campos estruturados por especialidade |
| `clinical_note` | Aba Evolução — modelo de nota por tipo de consulta |
| `consent` | Aba Consentimentos — texto do termo |
| `document` | Aba Documentos — layout de receita, atestado |
| `quick_phrase` | Campo de texto de qualquer aba — atalhos de texto |
| `pre_procedure_instruction` | Aba Documentos — orientações antes do procedimento |
| `post_procedure_instruction` | Aba Documentos — orientações após o procedimento |

### Regras de Negócio

- **Controle de acesso:** Apenas perfis `admin` e `supervisor` podem criar/editar templates. Profissionais clínicos só lêem.
- **Especialidades:** Templates têm `specialty` (ex: `odontologia`, `estetica_facial`, `dermatologia`, `clinica_geral`). O frontend filtra templates compatíveis com a especialidade do profissional logado.
- **Versionamento:** Toda edição cria nova versão do template. Registros criados com versões antigas mantêm referência à versão usada na época.

---

## Aba 14: Auditoria e Permissões

**Propósito:** Rastreabilidade total do prontuário. Proteção legal e compliance.

### Endpoints

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/api/v1/patients/:id/audit_logs` | Histórico de acessos e alterações no prontuário |
| `GET` | `/api/v1/audit_logs` | Log global (apenas admin) |
| `GET` | `/api/v1/patients/:id/audit_logs/export` | Exporta prontuário completo em PDF |

### Estrutura do AuditLog

```json
{
  "id": 981,
  "patient_id": 1,
  "actor_id": 5,
  "actor_name": "Dra. Amanda",
  "actor_role": "professional",
  "action": "view",
  "resource_type": "ClinicalNote",
  "resource_id": 33,
  "changes": null,
  "old_value": null,
  "new_value": null,
  "ip_address": "192.168.1.50",
  "occurred_at": "2026-03-07T14:00:00Z"
}
```

### Ações Rastreadas (enum de `action`)

`view`, `create`, `update`, `delete`, `sign`, `export`, `send_whatsapp`, `login_access`, `permission_change`

### Regras de Negócio

- **Inserção automática:** O `AuditLog` **nunca** é criado manualmente pelo código de negócio. Ele é inserido via callbacks (after_action, after_save, after_destroy) ou middleware centralizado. Isso garante que nenhuma operação passe sem registro.
- **Imutabilidade absoluta:** A tabela `audit_logs` não tem `UPDATE` e nem `DELETE` permitidos via aplicação. Acesso direto ao banco por admin do sistema é o único caminho para correção — e mesmo assim deve ser registrado.
- **Exclusões lógicas:** Nenhum registro clínico é deletado fisicamente. Todos usam `soft_delete` (`deleted_at`). O AuditLog registra o `delete` e o `actor` responsável.
- **Controle de permissões por perfil:**

| Perfil | Pode ver | Pode editar |
|--------|----------|-------------|
| `recepcionista` | Cadastro, Agenda, Financeiro | Cadastro, Agenda |
| `professional` | Tudo exceto Auditoria | Clínico + seus registros |
| `supervisor` | Tudo | Tudo exceto Auditoria |
| `admin` | Tudo | Tudo |

- **Exportação do prontuário:** `GET /export` gera um PDF compilado com todos os dados clínicos, exames, consentimentos e evolução do paciente, com capa de identificação e assinatura da clínica. Útil para transferência de paciente ou solicitação judicial.
- **Log de acesso à ficha:** Toda vez que qualquer usuário abre o prontuário de um paciente (`GET /summary`), um `AuditLog` com `action: "view"` é inserido automaticamente via middleware.

---

## Resumo: Mapa de Dependências por Módulo

| Módulo | Alimenta | Depende de |
|--------|----------|------------|
| Cadastro | — | — |
| Anamnese | CriticalAlert → Geral | FormTemplate |
| Evolução | Timeline, AuditLog | Appointment, FormTemplate |
| Plano de Tratamento | FinancialEstimate, TreatmentItem | Procedure (tabela de preços) |
| Sessões | TreatmentItem.sessions_done, Estoque, Timeline | TreatmentItem, Product |
| Exames | Timeline | SessionLog (opcional) |
| Documentos | — | FormTemplate |
| Consentimentos | CriticalAlert (flag pendente) → Geral | FormTemplate |
| Financeiro | CashEntry (Financeiro Mestre) | TreatmentPlan |
| Agenda | needs_recall → Geral, Timeline | — |
| Timeline | — | Todos os módulos (read-only) |
| Formulários | Todos os módulos que usam templates | — |
| Auditoria | — | Todos os módulos (listener passivo) |
