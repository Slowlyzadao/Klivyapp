# PRD — Portal do Paciente (pacientes.klivy.app)
## Product Requirements Document (v1.0)

**Produto:** Portal do Paciente — extensão da Klivy (BeClinic)
**Base:** Klivy (Chatwoot fork) — reaproveita modelos `Patient`, `Contact`, `AgendaEvent`, `Installment`, `Document`, `ConsentRecord`, `Conversation`
**Escopo deste documento:** Aplicação web pública voltada ao paciente final, separada visualmente do sistema da clínica mas servida pelo mesmo backend.
**Data:** 2026-05-17
**Status:** Discovery — aguardando aprovação para detalhamento técnico de cada módulo.

---

## Índice

1. [Visão Executiva](#1-visao-executiva)
2. [Problema e Oportunidade](#2-problema-e-oportunidade)
3. [Personas](#3-personas)
4. [Escopo (MVP, Fase 2, Fase 3)](#4-escopo)
5. [Módulo: Autenticação e Identificação](#5-modulo-autenticacao)
6. [Módulo: Home (Painel do Paciente)](#6-modulo-home)
7. [Módulo: Agendamentos](#7-modulo-agendamentos)
8. [Módulo: Evolução / Histórico Clínico](#8-modulo-evolucao)
9. [Módulo: Financeiro do Paciente](#9-modulo-financeiro)
10. [Módulo: Documentos](#10-modulo-documentos)
11. [Módulo: Consentimentos (LGPD)](#11-modulo-consentimentos)
12. [Módulo: Comunicação com a Clínica](#12-modulo-comunicacao)
13. [Módulo: Perfil e Dependentes](#13-modulo-perfil)
14. [Arquitetura Técnica](#14-arquitetura)
15. [Endpoints API](#15-endpoints)
16. [Modelo de Dados (novas tabelas)](#16-modelo-de-dados)
17. [Segurança, Privacidade e LGPD](#17-seguranca-lgpd)
18. [Roadmap por Sprint](#18-roadmap)
19. [Riscos, Premissas e Decisões em Aberto](#19-riscos)
20. [Anexo: Sugestões Adicionais do Claude](#20-sugestoes-claude)

---

## 1. Visão Executiva

O **Portal do Paciente** é uma aplicação web acessível em `pacientes.klivy.app` que dá ao paciente final autonomia para acompanhar seus agendamentos, evolução clínica, situação financeira, documentos emitidos e se comunicar com a clínica que o atende. O sistema é servido pelo mesmo backend Rails da Klivy (sistema.klivy.app), em um namespace novo (`/api/v1/patient_portal/`), com autenticação isolada e um SPA dedicado.

A arquitetura **reaproveita os modelos existentes** (`Patient`, `AgendaEvent`, `Installment`, `Document`, `ConsentRecord`, `ClinicalNote`, `Conversation`) e introduz apenas a camada de autenticação e auditoria específica do portal. Multi-tenancy é resolvida via `Account` (cada clínica = uma account) e o paciente identifica sua clínica automaticamente pelo `Contact` vinculado ao seu telefone/email no momento do login.

A entrega é faseada: o MVP cobre visualização (agenda, financeiro, documentos, mensagens) e o pagamento online + auto-agendamento ficam para a Fase 2.

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

### 4.1 MVP (Sprint A–D)

- Login com OTP (e-mail ou WhatsApp).
- Seleção de clínica quando o paciente existe em múltiplas accounts.
- Home com cards de próximas consultas, parcelas em aberto e mensagens não lidas.
- Lista de agendamentos (futuros e passados) com detalhe e botão "Confirmar presença".
- Lista de parcelas: aberto, pago, em atraso (somente visualização).
- Lista de documentos com download (atestado, encaminhamento, receita, anamnese, plano).
- Aceite digital de consentimentos pendentes (LGPD, termos por procedimento).
- Conversa com a clínica reaproveitando `Conversation` do Chatwoot (sem distinguir profissional ainda).
- Perfil: visualizar e atualizar dados cadastrais e foto.

### 4.2 Fase 2 (Sprint E–G)

- Pagamento online (PIX, boleto, cartão) — depende de gateway integrado (Asaas/Pagar.me/Stripe).
- Auto-agendamento dentro do portal (paciente autenticado, sem passar pelo link público).
- Reagendamento e cancelamento com regras configuráveis pela clínica.
- Direcionar mensagens a um profissional específico (não só "a clínica").
- Anexar arquivos na conversa (foto de exame, receita externa).

### 4.3 Fase 3 (Sprint H+)

- Dependentes / gestão de menores pelo responsável.
- Preenchimento de anamnese e questionários pré-consulta.
- Avaliação NPS pós-consulta.
- Upload de exames externos pelo paciente.
- Indicação de amigos (referral).
- Telemedicina (link da consulta, se a clínica oferecer).

### 4.4 Fora de Escopo

- App nativo iOS/Android (decisão: web responsive resolve por enquanto).
- Prescrição médica digital com assinatura ICP-Brasil (paciente apenas visualiza, não emite).
- Marketplace entre clínicas.

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

Lista cronológica de `AgendaEvent` onde `contact_id` corresponde ao paciente logado, dentro da account ativa.

### 7.2 Funcionalidades — MVP

| Funcionalidade | Descrição |
|---|---|
| Lista futura | Eventos com `starts_at >= now`, ordem ascendente |
| Lista passada | Eventos `< now`, ordem descendente, paginada |
| Detalhe do evento | Data, hora, duração, profissional, serviço, status, observações públicas |
| Confirmar presença | Botão para eventos com status `scheduled`; muda para `confirmed` e registra timeline |
| Pedir reagendamento | Abre conversa pré-preenchida na clínica ("Gostaria de reagendar a consulta de DD/MM") |
| Filtros | Por profissional, por status |

### 7.3 Funcionalidades — Fase 2

- **Auto-reagendamento:** paciente escolhe novo horário disponível dentro das regras de `AgendaSetting` e `AgendaOnlineConfig` (lead time, future limit).
- **Auto-cancelamento:** com janela mínima configurável (ex: cancelar até 24h antes).

### 7.4 Regras de Negócio

- Paciente só vê eventos onde `contact_id = current_contact.id`.
- Status `pending_confirmation` (Bea aguardando humano) **não aparece** para o paciente.
- Eventos com status `cancelled` aparecem na lista passada com badge específico.
- Observações marcadas como `internal` no `AgendaEvent` **nunca** são expostas.

### 7.5 Integrações

- Confirmar presença dispara o mesmo callback que a confirmação interna (timeline + notificação opcional).
- Pedido de reagendamento cria uma `Message` na `Conversation` do paciente com a clínica.

---

## 8. Módulo: Evolução / Histórico Clínico <a id="8-modulo-evolucao"></a>

### 8.1 Visão Geral

Linha do tempo do que aconteceu nos atendimentos do paciente, com nível de detalhe controlado pela clínica.

### 8.2 Funcionalidades

| Funcionalidade | Descrição |
|---|---|
| Timeline de consultas | Cada `ClinicalNote` finalizada vira um card: data, profissional, resumo público |
| Plano de tratamento | Visualização de `TreatmentPlan` ativo: itens, progresso (sessões realizadas/planejadas), status |
| Sessões realizadas | Lista de `SessionLog` com data e procedimento |
| Resumo de evolução | Campos selecionados por clínica para exposição (ex: `conduct`, mas não `assessment` interno) |

### 8.3 Regras de Negócio

- **Apenas notas `signed_at IS NOT NULL`** são expostas. Rascunhos nunca.
- Cada clínica configura em `PatientPortalSettings` quais campos do `ClinicalNote` ficam visíveis ao paciente (default: nada → opt-in explícito).
- Campos com flag `private = true` no `ClinicalNote` nunca são expostos.
- Acesso é auditado em `patient_portal_access_logs`.

### 8.4 Decisões em Aberto

- **D-1:** Mostrar evolução por padrão ou exigir opt-in da clínica?
- **D-2:** Permitir paciente baixar PDF da evolução assinada?

---

## 9. Módulo: Financeiro do Paciente <a id="9-modulo-financeiro"></a>

### 9.1 Visão Geral

Visão completa das obrigações financeiras do paciente naquela clínica.

### 9.2 Funcionalidades — MVP

| Funcionalidade | Descrição |
|---|---|
| Resumo | Total em aberto, total pago no ano, próxima parcela |
| Lista de parcelas | `Installment` agrupadas por `FinancialEstimate` / `Transaction` |
| Status visual | Em aberto, pago, em atraso (com dias de atraso) |
| Detalhe da parcela | Valor, vencimento, método previsto, descrição (procedimento/serviço) |
| Histórico de pagamentos | Lista de parcelas pagas com data |
| Download de recibo | PDF gerado por parcela paga |

### 9.3 Funcionalidades — Fase 2

- **Pagamento online:** PIX (QR code + copia/cola), boleto (gera, mostra linha digitável), cartão (checkout transparente).
- **Comprovante automático:** ao confirmar pagamento, gera recibo e marca parcela como `paid` no Klivy.
- **Antecipação de parcelas:** quitar várias de uma vez com possível desconto configurável.

### 9.4 Regras de Negócio

- Paciente vê apenas suas próprias parcelas (`Installment.transaction.patient_id = current_patient.id`).
- Parcelas de transações com `transaction_type = expense` (despesa da clínica) nunca aparecem.
- Atraso é calculado em tempo real (`due_date < today AND status = pending`).
- Recibo só fica disponível após `status = paid` E `paid_at IS NOT NULL`.

### 9.5 Decisões em Aberto

- **D-3:** Qual gateway de pagamento? (Asaas tem boa cobertura para clínicas; Pagar.me/Stripe para cartão; Mercado Pago para PIX simples). Recomendo **Asaas** como default.
- **D-4:** Repasse de taxa: clínica absorve ou paciente paga?

---

## 10. Módulo: Documentos <a id="10-modulo-documentos"></a>

### 10.1 Visão Geral

Repositório de PDFs emitidos pela clínica para o paciente: atestados, encaminhamentos, receitas, laudos, anamnese, plano de tratamento.

### 10.2 Funcionalidades — MVP

| Funcionalidade | Descrição |
|---|---|
| Lista de documentos | `Document` filtrado por `patient_id` e `status = active`, agrupado por tipo |
| Filtros | Por tipo (`document_type`), por intervalo de data |
| Download | Link assinado com TTL de 15 min para `ActiveStorage::Blob` |
| Compartilhamento | Botão "Enviar para WhatsApp/Email" gera link público de uso único com TTL configurável |
| Preview inline | PDF aberto no navegador antes de baixar |

### 10.3 Funcionalidades — Fase 3

- Upload pelo paciente (foto de exame externo, receita de outro médico). Vai para `ExamMedia` com flag `uploaded_by_patient = true` e fica em revisão da clínica.

### 10.4 Regras de Negócio

- Documentos com `is_generated = true` E `status = active` aparecem.
- Documentos com flag `internal = true` (uso interno) nunca aparecem.
- Cada download gera registro em `patient_portal_access_logs` com `resource = Document/:id`.
- Links assinados expiram em 15 min e são single-use.

---

## 11. Módulo: Consentimentos (LGPD) <a id="11-modulo-consentimentos"></a>

### 11.1 Visão Geral

Reaproveita o `ConsentRecord` existente, que já tem suporte a assinatura remota via `remote_token`. O portal substitui o fluxo atual de enviar link de assinatura por WhatsApp.

### 11.2 Funcionalidades

| Funcionalidade | Descrição |
|---|---|
| Lista de consentimentos | Pendentes (topo) e assinados (histórico) |
| Aceite digital | Modal com texto completo, checkbox de leitura, assinatura via touch/mouse, captura de IP+UA |
| Re-assinatura | Quando clínica publica nova versão, dispara aceite obrigatório |
| Download | PDF do consentimento assinado com hash de integridade |
| Recusa | Paciente pode recusar consentimento opcional; obrigatórios bloqueiam uso do portal |

### 11.3 Tipos de Consentimento Suportados

| Tipo | Origem | Obrigatório |
|---|---|---|
| Termo de uso do portal | Klivy | Sim (1ª vez) |
| Política de Privacidade (LGPD) | Klivy | Sim (1ª vez) |
| Termo de tratamento de dados sensíveis | Cada clínica | Sim |
| Consentimento por procedimento | Cada clínica | Conforme procedimento |
| Termo de imagem | Cada clínica | Opcional |
| Termo para menor (assinado por responsável) | Cada clínica | Quando aplicável |

### 11.4 Regras de Negócio

- Consentimento bloqueante (`mode = required`) sem assinatura impede navegação.
- Versão do consentimento é imutável após primeira assinatura por qualquer paciente.
- Hash de integridade (`integrity_hash`) já é calculado pelo modelo existente.
- Para menores: o JWT precisa carregar `acting_as_responsible: true` E `responsible_for_patient_id`. Auditoria registra os dois sujeitos.

### 11.5 Edge Cases

- Paciente já assinou no consultório (papel): clínica marca `ConsentRecord` como `signed_offline` e portal não pede de novo.
- Paciente recusa LGPD obrigatório: portal oferece "Falar com a clínica" e bloqueia acesso ao conteúdo clínico.

---

## 12. Módulo: Comunicação com a Clínica <a id="12-modulo-comunicacao"></a>

### 12.1 Visão Geral

**Reaproveita o `Conversation` do Chatwoot**. A clínica já tem inbox(es) no painel; o portal cria/escreve em uma conversa associada ao `Contact` do paciente em um inbox específico do tipo `api` (Patient Portal Inbox), gerado automaticamente no primeiro uso.

Do lado da clínica, a mensagem do paciente aparece exatamente como qualquer outra conversa, com a tag "Portal do Paciente" e acessível em `/app/accounts/:id/conversations`.

### 12.2 Funcionalidades — MVP

| Funcionalidade | Descrição |
|---|---|
| Caixa de entrada | Lista de conversas do paciente naquela clínica |
| Nova mensagem | Botão para iniciar conversa (texto livre, sem destinatário específico) |
| Histórico | Threading completo da conversa |
| Notificação de não lidas | Contador na home e badge no menu |
| Anexar texto pré-preenchido | Botão "Pedir reagendamento" / "Dúvida sobre boleto" insere template |

### 12.3 Funcionalidades — Fase 2

- Selecionar profissional ao iniciar conversa (cria atribuição automática no Chatwoot).
- Anexar arquivos (imagem, PDF) com limite de 10 MB.
- Indicador de "lida" da clínica (`Message.status`).

### 12.4 Regras de Negócio

- Inbox dedicado por account: `Patient Portal — :clinic_name`, tipo `api`, criado no primeiro uso.
- Mensagens do paciente entram com `message_type = incoming`.
- Atribuição de agente segue regra padrão do Chatwoot (round-robin, etc.).
- Conversas ficam **fora** das métricas SLA da clínica por padrão (opt-in).
- Paciente nunca vê mensagens `private = true` (notas internas entre agentes).

### 12.5 Edge Cases

- Clínica sem nenhum agente disponível: paciente vê resposta automática "Recebemos sua mensagem, retornaremos em até X horas".
- Conversa muito antiga sem resposta da clínica: portal exibe alerta para o paciente reabrir.

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
| Vincular dependente | Responsável solicita vínculo informando CPF do dependente; clínica aprova |
| Alternar contexto | Após login, escolhe se navega como ele mesmo ou como o dependente |
| Assinar pelo menor | Consentimentos do dependente exigem JWT com `acting_as_responsible` |
| Auditoria dupla | Toda ação no contexto do dependente registra responsável + dependente |

### 13.3 Regras de Negócio

- Edição de campos sensíveis (CPF, nome legal, data nasc) **nunca** é direta — sempre via solicitação.
- Endereço é livre para edição porque já tem precedente no formulário público de booking.
- Exclusão de dados não é apagamento real — é anonimização (`PatientAnonymizationService` a ser criado), preservando registros financeiros e clínicos por obrigação legal (CFM exige 20 anos para prontuário).

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

Seguindo a regra de arquitetura do projeto (sem editar core):

```
enterprise/
  app/
    controllers/
      api/v1/patient_portal/
        base_controller.rb
        auth_controller.rb
        appointments_controller.rb
        installments_controller.rb
        documents_controller.rb
        consents_controller.rb
        conversations_controller.rb
        profile_controller.rb
    models/
      patient_portal_user.rb
      patient_portal_otp.rb
      patient_portal_consent.rb
      patient_portal_access_log.rb
      patient_portal_setting.rb
    services/
      patient_portal/
        otp_dispatcher.rb
        authenticator.rb
        document_signed_url_generator.rb
        installment_payment_gateway.rb   # Fase 2
    serializers/
      patient_portal/
        appointment_serializer.rb
        installment_serializer.rb
        ...
    javascript/
      patient_portal/                    # SPA Vue 3
        entry.js
        App.vue
        router/
        store/
        components/
        pages/
```

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

### 14.5 Multi-tenancy

- JWT carrega `account_id` definido no momento do login (após escolha de clínica, se houver).
- Toda query no backend usa `current_account.contacts` / `current_account.patients` — nunca `Patient.all`.
- Trocar de clínica = relogar com nova seleção (não há "switcher" em runtime no MVP; Fase 2 pode trazer).

### 14.6 Reaproveitamento do Core

| Item | Reaproveita | Como |
|---|---|---|
| Identidade do paciente | `Contact` (Chatwoot) | Busca por phone/email; resolve `Patient` via `Patient.contact_id` |
| Mensageria | `Conversation` + `Message` + inbox tipo `api` | Cria inbox dedicado por account; toda mensagem usa o pipeline normal |
| Documentos | `Document` + Active Storage | Signed URL com TTL via `ActiveStorage::Blob.signed_id` |
| Consentimentos | `ConsentRecord.remote_token` | Já tem fluxo de assinatura remota; só substitui canal de entrega |
| Agenda | `AgendaEvent` | Read-only no MVP; reaproveita callbacks de status |
| Financeiro | `Installment` / `Transaction` | Read-only no MVP; Fase 2 chama gateway e atualiza status |
| Mailers | ActionMailer existente | Reaproveita layout |
| Auditoria | `PatientAuditLog` existente | Novos tipos: `portal_login`, `portal_view`, `portal_download` |

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
| GET  | `/api/v1/patient_portal/home` | Payload agregado para o dashboard inicial |
| GET  | `/api/v1/patient_portal/appointments?status=&from=&to=` | Lista de agendamentos |
| GET  | `/api/v1/patient_portal/appointments/:id` | Detalhe |
| POST | `/api/v1/patient_portal/appointments/:id/confirm` | Confirmar presença |
| POST | `/api/v1/patient_portal/appointments/:id/request_reschedule` | Cria mensagem na conversa |
| GET  | `/api/v1/patient_portal/financial/summary` | Totais |
| GET  | `/api/v1/patient_portal/financial/installments?status=` | Lista de parcelas |
| GET  | `/api/v1/patient_portal/financial/installments/:id` | Detalhe |
| POST | `/api/v1/patient_portal/financial/installments/:id/pay` | **Fase 2** — inicia pagamento |
| GET  | `/api/v1/patient_portal/financial/installments/:id/receipt` | URL assinada do PDF |
| GET  | `/api/v1/patient_portal/documents?type=` | Lista |
| GET  | `/api/v1/patient_portal/documents/:id/download` | Redireciona p/ signed URL (15 min) |
| GET  | `/api/v1/patient_portal/consents?status=pending` | Lista |
| POST | `/api/v1/patient_portal/consents/:id/sign` | `{ signature_data, accepted_at }` |
| GET  | `/api/v1/patient_portal/conversations` | Lista |
| POST | `/api/v1/patient_portal/conversations` | Cria conversa nova |
| GET  | `/api/v1/patient_portal/conversations/:id/messages` | Histórico |
| POST | `/api/v1/patient_portal/conversations/:id/messages` | Nova mensagem |
| GET  | `/api/v1/patient_portal/profile` | Dados cadastrais |
| PATCH | `/api/v1/patient_portal/profile` | Atualizar campos permitidos |
| POST | `/api/v1/patient_portal/profile/export` | **LGPD** — dispara job de exportação |
| POST | `/api/v1/patient_portal/profile/deletion_request` | **LGPD** — solicita exclusão |
| GET  | `/api/v1/patient_portal/evolution` | Timeline clínica (se habilitada) |

### 15.3 Convenções

- Todas as respostas no padrão `{ data, meta, errors }`.
- Paginação por cursor (`?after=`, `?limit=20`).
- Rate limit: 60 req/min por JWT, 5 req/min em endpoints de auth.

---

## 16. Modelo de Dados (novas tabelas) <a id="16-modelo-de-dados"></a>

| Entidade | Campos principais |
|---|---|
| `PatientPortalOtp` | identifier (phone/email), code_digest, expires_at, used_at, attempts, account_scope (nullable) |
| `PatientPortalSession` | patient_id, account_id, jwt_jti, expires_at, last_seen_at, ip, user_agent |
| `PatientPortalConsent` | patient_id, term_type, term_version, accepted_at, ip, user_agent, signature_blob |
| `PatientPortalAccessLog` | patient_id, account_id, action (login/view/download/sign/message), resource_type, resource_id, ip, ua, at |
| `PatientPortalSetting` | account_id (UNIQUE), expose_clinical_notes, expose_treatment_plan, expose_session_logs, auto_reply_template, whatsapp_inbox_id |
| `PatientResponsibleLink` | responsible_patient_id, dependent_patient_id, approved_at, approved_by_user_id, account_id |

Modelos existentes que **ganham flag ou coluna**:

| Tabela | Coluna adicionada | Propósito |
|---|---|---|
| `documents` | `internal:boolean` (default false) | Esconder do paciente |
| `clinical_notes` | `private:boolean` (default true) | Default fechado; clínica abre explicitamente |
| `agenda_events` | `notes_internal:text` (separado de `notes`) | Manter notas internas seguras |

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

Cada sprint = 1 semana. Times podem paralelizar backend e frontend.

| Sprint | Entrega |
|---|---|
| **A** | Infra: subdomínio + DNS + namespace `/api/v1/patient_portal/` + base controller + JWT + Pundit base. Modelos `PatientPortalOtp`, `PatientPortalSession`. Endpoint de OTP funcional. |
| **B** | SPA scaffold + login + seleção de clínica + termo inicial. Tela de home vazia. |
| **C** | Módulos Agendamentos e Documentos (leitura + download). |
| **D** | Módulos Financeiro (leitura) e Consentimentos. Auditoria. Beta fechado com 2–3 clínicas. |
| **E** | Módulo Comunicação (reuso de `Conversation`). Notificações de não lidas. |
| **F** | Pagamento online — Asaas (PIX + boleto + cartão). |
| **G** | Auto-agendamento e reagendamento. |
| **H** | Dependentes/menores + anamnese pré-consulta. |
| **I** | NPS + indicação + upload de exames externos. |

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

### 19.3 Decisões em Aberto

- **D-1:** Evolução clínica visível por padrão? (recomendo **não** — opt-in)
- **D-2:** PDF de evolução assinado disponível ao paciente?
- **D-3:** Gateway de pagamento (recomendo Asaas)
- **D-4:** Taxa do gateway é repassada ao paciente?
- **D-5:** WhatsApp Business próprio da Klivy para OTP ou SMS via terceiro?
- **D-6:** Portal é ativável por clínica (toggle em `InstallationConfig` por account) ou universal?
- **D-7:** Quem custeia a infra extra do portal — embutido no plano da clínica ou módulo pago à parte?

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
| S12 | **Anamnese pré-consulta** (Fase 3) | §4.3 | Economiza 10 min da consulta; o módulo já tem `Anamnesis` versionada |
| S13 | **NPS pós-consulta** (Fase 3) | §4.3 | Métrica de qualidade objetiva pra clínica |
| S14 | **WhatsApp Business próprio da Klivy para OTP** | §17.2 | Neutralidade entre clínicas; evita confusão de identidade |
| S15 | **Inbox auto-criado no primeiro uso** | §12.4 | Zero setup pra clínica ativar o portal |
| S16 | **Rate limit + captcha após 3 falhas** | §17.4 | Anti-força-bruta — pacientes públicos = superfície de ataque maior |
| S17 | **Setting `PatientPortalSetting` por account** | §16 | Cada clínica configura o que expor — sem isso, o "default" vira batalha |
| S18 | **Reaproveitar `Conversation` do Chatwoot** para mensagens | §12.1 | Decisão arquitetural mais importante do doc — evita reinventar mensageria |
| S19 | **Reaproveitar `ConsentRecord` com `remote_token`** | §11.1 | Modelo já tem assinatura remota; só troca o canal de entrega |
| S20 | **SPA no mesmo repo, entry separado** (não monorepo isolado) | §14.1 | Reaproveita pipeline de build, deploy, tipagem, design tokens |

---

**Fim do documento.**
