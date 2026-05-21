# Klivy

**Klivy** é uma plataforma SaaS completa de gestão clínica (prontuário, agenda, financeiro) construída de forma modular e integrada como uma extensão sobre a infraestrutura omnichannel do [Chatwoot](https://www.chatwoot.com/). Ele unifica toda a comunicação da sua clínica (WhatsApp, Instagram, Telegram) com os processos diários de atendimento e operação.

---

## 🚀 Visão Geral

A arquitetura do Klivy opera seguindo o princípio de **Modular Monolith** via Ruby on Rails Engines. Nossas features não tocam nos arquivos nativos da plataforma base. Os módulos são isolados, auto-contidos e interagem dinamicamente com o núcleo oferecendo um hub centralizado:

- Nenhuma funcionalidade ou arquivo core do Chatwoot é alterado fisicamente.
- Todos os módulos do negócio (Agenda, Pacientes, Financeiro, Permissões) vivem de forma autônoma na pasta `plugins/`.
- Uso de **Satélites DB Profiles** (`beclinic_profiles`) para estender tabelas de banco de dados nativas de forma higiênica.

## 🧩 Módulos Principais

### 1. 📅 Agenda (Calendário Clínico)
Sistema visual completo para gestão de tempo e ocupação da clínica.
- **Múltiplas Views:** Dia, Semana, Mês com Drag-and-Drop.
- **Agendamento Público (Booking):** Página com link único para auto-agendamento do paciente.
- **Lista de Espera:** Filtros por período de preferência (manhã, tarde, noite).
- **Notificações Automáticas:** Envios via WhatsApp e E-mail (Lembretes, Confirmações, Felicitações, Follow-up).
- **Serviços & Atributos Customizados:** Totalmente configurável.

### 2. 🗂️ Pacientes (Prontuário Clínico Eletrônico)
O coração operacional médico/odontológico do Klivy, com rastreabilidade total (LGPD) e 12 abas de registros.
- **Anamnese Versionada:** Histórico médico com proteção contra edições em documentos consolidados.
- **Evolução Clínica:** Notas e progressões, com recurso de assinatura por usuário.
- **Planos de Tratamento:** Acompanhamento desde a proposta até a execução e conclusão procedural.
- **Documentos & Exames:** Upload com permissões, armazenamento otimizado e templates flexíveis.
- **Consentimento Digital:** Assinatura remota com criptografia/hash de integridade (tablet ou web).
- **Timeline:** Histórico e consolidação de toda interação física, clínica e via mensageria do paciente na clínica.

### 3. 💰 Financeiro Central
Solução de gestão e caixa para suportar a complexidade de convênios e planos privados.
- **DRE:** Demonstrativo de Resultado simplificado entre regime por caixa ou competência.
- **Dashboard e Relatórios (Business Intelligence):** KPI's em tempo real de metas para a clínica (ticket médio, conversões, composição da receita, inadimplência e comissões de profissionais).
- **Caixa Físico:** Controle de sangria e suprimentos na recepção (PDV).
- **Despesas Recorrentes & Metas Mensais:** Monitoramento de metas cadastradas da clínica no Dashboard.
- **Sincronização Bidirecional:** Os recebimentos criados no Prontuário refletem diretamente e instantaneamente no Caixa Central.

### 4. ⚙️ Configurações do Sistema
Sessão isolada para adaptar o Klivy conforme a realidade do negócio estabelecido.
- Configurações operacionais (Regras de Lembretes, Horários do Profissional, Template Form).
- Roles e acessos restritivos de módulos e visualizações financeiras aos envolvidos (BeClinicRoles).

---

## 🛠️ Tech Stack

- **Backend:** Ruby on Rails, Active Job (Sidekiq)
- **Banco de Dados:** PostgreSQL
- **Frontend:** Vue.js 3
- **Armazenamento:** Active Storage
- **Mensageria/Omnichannel:** Baseado em Chatwoot Core.

---

## 📊 Estrutura de Diretórios (Modular Monolith)

Para aprofundamento técnico e sistêmico detalhado, consulte os documentos em `docs/02-architecture`.

- `plugins/agenda/` - Motor isolado contemplando rotas Vue responsivas (Mobile-first) e backend do Calendário.
- `plugins/patients/` - Motor do Prontuário Clínico (APIs, Serviços, Modelos associativos via Proxy).
- `plugins/financial/` - Motor Financeiro (Dashboards, Fluxo de Caixa Diário, e PDFs Nativos via Prawn).
- `plugins/beclinic_core/` - Motor Administrativo que gerencia Configurações e as abstrações de Bando de Dados satélites (`AccountProfile`, `TeamProfile`).
- `docs/` - Manuais de engenharia, especificações de produtos, planos técnicos e guias Padrão-Ouro de interface.

> *Klivy - Unificando a comunicação omnichannel com excelência na gestão clínica.*
