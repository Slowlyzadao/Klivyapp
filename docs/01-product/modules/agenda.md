> [!IMPORTANT]
> **Nota de Auditoria Arquitetural Atualizada:** 
> O texto a seguir contém a Especificação Histórica das Regras de Negócio deste módulo.
> Em nível sistêmico (código, frontend, backend e Banco de Dados), todas as estruturas listadas abaixo encontram-se 100% isoladas na Arquitetura Modular (Rails Engines), localizadas especificamente dentro do seu diretório `plugins/`. O modelo de banco de dados original do Chatwoot citado como destino de colunas no documento abaixo já foi refatorado utilizando Satélites DB Profiles (`beclinic_profiles`) visando prevenir colisões de migrações nativas do Chatwoot no longo prazo.
> Leia `02-architecture/system-architecture.md` para visualizar as ligações sistêmicas exatas em código. Tudo detalhado abaixo responde ao Produto e Usuário.

# Plano de Ação - Módulo de Agenda (Calendar)

## 1. Visão Geral

Implementação de um sistema de agenda completo dentro do Chatwoot, com foco em clínicas (Beclinic), permitindo o gerenciamento de consultas, bloqueios e compromissos de forma integrada.

## 2. Requisitos de Design (Chatwoot Standard)

- **Identidade Visual**: Utilizar as cores e tipografia oficiais do Chatwoot.
- **Temas**: Suporte completo a Dark Mode e Light Mode (com troca automática baseada no sistema).
- **Navegação**: Sidebar lateral com filtros e mini calendário.
- **Micro-interações**: Feedback visual ao arrastar eventos e transições suaves entre visualizações.

## 3. Funcionalidades Core (API Própria)

Desenvolvimento de uma API robusta para suportar:

- **Agendamento**: Criação de novos eventos vinculados a Contatos (Pacientes).
- **Reagendamento**: Suporte a drag-and-drop no frontend com atualização via API.
- **Cancelamento/Exclusão**: Gestão de status do evento com logs de auditoria.
- **Edição Detalhada**: Alteração de todos os metadados do evento.
- **Visualização Flexível**: Alternar entre visualizações de **Mês**, **Semana** e **Dia**.

## 4. Gerenciamento de Dados (Campos do Evento)

- **Paciente (MVP)**: Vínculo obrigatório com `Contact` do Chatwoot. Atualmente, o modelo de Contatos servirá como base para os pacientes.
- **Evolução para Módulo de Pacientes**: Em uma fase futura, será implementado um módulo dedicado de **Pacientes** para substituir/estender o uso de Contatos, permitindo:
  - Upload de arquivos e PDFs (exames, prontuários).
  - Vínculo avançado entre contatos e fichas clínicas.
  - Histórico clínico estruturado.
- **Responsável**: Vínculo obrigatório com `User` (Agente/Profissional).
- **Metadados**:
  - **Prioridade**: Urgente, Alta, Média, Baixa.
  - **Tipo de Evento**: Consulta, Bloqueio de Agenda, Compromisso.
  - **Tratamento**: Lista específica para Beclinic (veja Seção 6).
  - **Status do Agendamento**: Pendente, Confirmado, Cancelado, Compareceu, Não Compareceu.
  - **Horário**: Data/Hora de início e fim.
  - **Observações**: Campo de texto para detalhes clínicos ou lembretes.

## 5. Filtros e Sidebar

- **Mini Calendário**: Navegação rápida por data (clicar em um dia muda a visão principal).
- **Filtro de Profissionais (Agentes)**: Seleção individualizada com cores para cada agente.
- **Filtros de Status**: Por Prioridade, Tipo de Evento e Tratamento.
- **Busca**: Filtrar agentes/profissionais por nome na sidebar.

## 6. Lista de Tratamentos (Contexto Beclinic)

**Diretriz Visual:** Os emojis abaixo são APENAS para referência no plano. No desenvolvimento da interface, TODOS OS EMOJIS SERÃO SUBSTITUÍDOS POR ÍCONES SVG MINIMALISTAS seguindo o mesmo estilo dos ícones nativos do Chatwoot (traços finos, sem preenchimento colorido).

1. [Ícone] Avaliação
2. [Ícone] Reavaliação
3. [Ícone] Profilaxia (limpeza)
4. [Ícone] Restauração
5. [Ícone] Dente quebrado / urgência
6. [Ícone] Endodontia (canal)
7. [Ícone] Extração
8. [Ícone] Clareamento
9. [Ícone] Implante dental
10. [Ícone] Prótese fixa
11. [Ícone] Prótese removível
12. [Ícone] Protocolo sobre implante
13. [Ícone] Prova de prótese
14. [Ícone] Entrega de prótese

## 7. Integrações Clínicas e Funcionalidades Extra

Para maximizar o valor para clínicas, adicionaremos:

- **Lembretes Automáticos via WhatsApp**: Integração com as campanhas ou automações do Chatwoot para avisar o paciente 24h antes.
- **Ficha Clínica Rápida**: Botão no evento da agenda que abre diretamente o perfil do contato no Chatwoot para ver histórico de conversas e notas.
- **Fluxo de Confirmação**: Paciente responde "SIM" no WhatsApp e o status na agenda muda automaticamente para "Confirmado".
- **Gestão de Financeiro Simplificada**: Campo opcional de "Valor do Procedimento" e "Status de Pagamento" (Pago/Pendente).
- **Lista de Espera**: Funcionalidade para marcar pacientes que desejam ser avisados em caso de desistência em datas específicas.
- **Recorrência de Tratamentos**: Possibilidade de agendar múltiplas sessões (ex: 4 sessões de canal) de uma só vez.

## 8. Relatórios e Insights (Dashboard)

- **Taxa de Ocupação**: % de horários preenchidos vs total disponível por profissional.
- **Relatório de No-Show**: Identificar pacientes que faltam com frequência.
- **Ranking de Tratamentos**: Quais procedimentos são mais realizados.

## 9. Arquitetura de Dados e Evolução

Para garantir uma entrega rápida e valor imediato, seguiremos uma estratégia de duas fases:

### Fase 1: MVP com Contatos do Chatwoot

- Utilizaremos o modelo `Contact` nativo para representar os pacientes.
- Aproveitaremos os `custom_attributes` para dados clínicos básicos (ex: data de nascimento, CPF).
- Foco total na lógica de agendamento e visualização.

### Fase 2: Módulo Dedicado de Pacientes

- Criação de uma entidade `Patient` independente.
- Integração com Active Storage para gestão de PDFs e documentos clínicos.
- Migração transparente dos dados da Fase 1 para a nova estrutura.

## 10. Próximos Passos (Workflow)

1. [x] **Backend**: Criar Migration para `agenda_events` (vinculando `account_id`, `contact_id` e `user_id`).
2. [x] **Backend**: Desenvolver o Model `AgendaEvent` com validações de choque de horário.
3. [x] **Backend**: Criar API Controller para os endpoints CRUD.
4. [x] **Frontend**: Criar a View `/app/accounts/:id/calendar` no layout do Chatwoot.
5. [x] **Frontend**: Integrar visualização de calendário (Grid responsiva customizada baseada no Chatwoot Design).
6. [x] **Frontend**: Desenvolver Sidebar de filtros e Modais de criação com buscas de Contatos e Agentes (React-Select style).
7. [x] **Frontend**: Completar a edição e deleção de eventos ao clicar num evento existente (Visualização de Detalhes).
8. [x] **Integração**: Conectar o filtro da Sidebar para aplicar formatação e filtragem local na store Vuex.
9. [ ] **Integração**: Implementar worker de automação para notificações e lembretes de WhatsApp.

## 11. Configurações da Agenda (Settings)

Um painel administrativo para configurar o comportamento padrão do calendário para a clínica inteira.

### 11.1 Abas de Configuração

1. **Horários**: Configuração dos horários de funcionamento, pausas, feriados e dias de folga.
2. **Notificações automáticas**: Templates e regras de lembretes e confirmações via WhatsApp.
3. **Agendamento online**: Links e portal para o paciente agendar por conta própria (Fase 2).
4. **Serviços e tipos**: Gerenciamento profundo dos tratamentos, durações padrão, e cores.
5. **Profissionais**: Configuração de horários específicos por médico/dentista.

### 11.2 Horários de Funcionamento (Implementação Atual)

- **Horários Padrão**: Tabela com Segunda a Domingo, permitindo habilitar/desabilitar cada dia.
  - Horário de Abertura (`09:00`)
  - Horário de Fechamento (`18:00`)
  - Intervalo de Almoço (Ex: `12:00` às `13:00`)
  - Status Visual: Aberto, Fechado, Horário Reduzido.
- **Feriados**: Lista lateral fixa ou dinâmica dos principais feriados do ano (com opção de "Estaremos aberto" ou "Estaremos fechado").
- **Exceções e Folgas**: Cards para adicionar períodos customizados de ausência coletiva (Congressos, Férias Coletivas, Manutenções, etc). Possui Data Início, Data Fim e Categoria.
# Plano de Ação - Agendamento Online (Beclinic)

## 1. Visão Geral
O agendamento online permite que pacientes (novos ou existentes) agendem consultas de forma autônoma através de um link público. O sistema deve gerenciar a disponibilidade do profissional, validar os dados do paciente e criar automaticamente o registro na agenda e no cadastro de contatos.

## 2. Estrutura de Banco de Dados

### 2.1 Extensão do Modelo `User` (Agente/Profissional)
Adicionar um identificador único para o link público:
- `agenda_public_id`: string (UUID ou Hash aleatório de 6-10 caracteres). Deve ser único e indexado.

### 2.2 Nova Tabela: `agenda_online_configs`
Armazena as regras globais de agendamento da conta:
- `account_id`: bigint (references accounts)
- `enabled`: boolean (default: true)
- `allow_new_patients`: boolean (default: true)
- `require_whatsapp_verification`: boolean (default: false)
- `require_email_verification`: boolean (default: false)
- `min_lead_time_minutes`: integer (default: 180) - Antecedência mínima.
- `future_limit_days`: integer (default: 60) - Limite de dias à frente.
- `form_fields`: jsonb - Lista de campos personalizados do formulário.

## 3. Estrutura do Link Público
O link terá o formato:
`https://beclinic.com.br/agendar/:account_slug/:professional_name/:agenda_public_id`
*Nota: O `account_slug` e `professional_name` são estéticos, a busca real é feita pelo `agenda_public_id`.*

## 4. Funcionalidades do Backend

### 4.1 API Administrativa (`Agenda::OnlineConfigsController`)
- **GET /api/v1/accounts/:id/agenda_online_configs**: Retorna as configurações e campos.
- **PATCH /api/v1/accounts/:id/agenda_online_configs**: Atualiza regras e campos.

### 4.2 API Pública de Agendamento (`Agenda::PublicController`)
- **GET /agenda/public/:public_id/slots**:
    - Calcula slots disponíveis para os próximos `future_limit_days`.
    - Respeita `WorkingHours` (Expediente e Almoço).
    - Respeita `AgendaEvents` já marcados.
    - Aplica `min_lead_time_minutes` a partir do `now()`.
- **GET /agenda/public/:public_id/form**: Retorna os campos obrigatórios e personalizados.
- **POST /agenda/public/:public_id/book**:
    - Valida dados do formulário.
    - Busca ou Criar `Contact` (Cadastro do Paciente).
    - Cria `AgendaEvent` com status `confirmed` ou `pending` (dependendo da verificação).

## 5. Interface Frontend (Agenda Settings)

### 5.1 Aba "Agendamento Online"
- **Card "Link de Agendamento"**:
    - Dropdown para selecionar o profissional.
    - Input readonly com o link gerado e botão "Copiar link".
- **Card "Regras de Funcionamento"**:
    - Checkboxes para regras de acesso (novos pacientes, verificações).
    - Inputs numéricos para limites de tempo (antecedência e limite futuro).
- **Card "Formulário de Agendamento"**:
    - Tabela com campos obrigatórios: Nome, Sobrenome, CPF, Celular, E-mail.
    - Toggle para marcar como obrigatório (nos campos permitidos).
    - Botão "Novo campo" para adicionar campos extras.

## 6. Fluxo do Paciente (Página Pública)
1. **Seleção de Horário**: Exibição de calendário com slots livres.
2. **Preenchimento de Dados**: Formulário gerado dinamicamente com validação de CPF e Celular.
3. **Verificação (Opcional)**: Envio de código via WhatsApp/E-mail.
4. **Confirmação**: Exibição de voucher/detalhes e opção de adicionar ao calendário.

## 7. Próximos Passos (Checklist)

1. [ ] **Migration**: Criar `agenda_online_configs` e adicionar `agenda_public_id` ao `users`.
2. [ ] **Backend**: Implementar o Service de cálculo de slots disponíveis (`Agenda::AvailableSlotsService`).
3. [ ] **Backend**: Implementar Controller administrativo e API pública.
4. [ ] **Frontend**: Desenvolver a aba de Agendamento Online no `AgendaSettings/Index.vue`.
5. [ ] **Frontend**: Criar a página pública de agendamento (lightweight app).
6. [ ] **Integração**: Trigger para criar contato automaticamente e enviar mensagem de confirmação inicial.
