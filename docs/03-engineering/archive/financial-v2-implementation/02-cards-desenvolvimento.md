# Cards de desenvolvimento — Financeiro Klivy/Salus

> 33 cards organizados em 10 fases sequenciais. Cada card detalha o que implementar, como funciona, com o que conversa, modelo de dados, critérios de aceite e notas técnicas.
>
> Cada `ID` (F-01 a F-33) é único e referenciável nas dependências.

## Legenda

**Prioridade**

- 🔴 **Crítica** — bloqueia operação, deve ser feito antes de subir
- 🟠 **Alta** — importante, tem workaround temporário aceitável
- 🟡 **Média** — polimento, melhora a experiência mas não bloqueia
- 🟢 **Baixa** — nice-to-have

**Tamanho**

- **P** — 1-2 dias
- **M** — 3-5 dias
- **G** — 1-2 sprints (uma sprint a uma sprint e meia)
- **GG** — 2+ sprints (mais de duas semanas)

## Sumário

**Fase 1 — Fundação técnica**

- `F-01` [Modelo de dados financeiro core](#f-01-modelo-de-dados-financeiro-core)
- `F-02` [Sistema de auditoria (AuditLog)](#f-02-sistema-de-auditoria-auditlog)
- `F-03` [Permissões com 5 perfis (RBAC)](#f-03-permissões-com-5-perfis-rbac)
- `F-04` [Wizard de configuração inicial obrigatório](#f-04-wizard-de-configuração-inicial-obrigatório)

**Fase 2 — Configurações**

- `F-05` [Cadastros base — Categorias e Contas Bancárias](#f-05-cadastros-base-—-categorias-e-contas-bancárias)
- `F-06` [Regras de Comissão por profissional](#f-06-regras-de-comissão-por-profissional)
- `F-07` [Despesas Recorrentes e Metas](#f-07-despesas-recorrentes-e-metas)

**Fase 3 — Importação Clinicorp**

- `F-08` [Importador de cadastros (Profissionais, Templates, Pacientes)](#f-08-importador-de-cadastros-profissionais-templates-pacientes)
- `F-09` [Importador de histórico clínico](#f-09-importador-de-histórico-clínico)
- `F-10` [Importador financeiro (Budgets, PaymentHeader, PaymentItem)](#f-10-importador-financeiro-budgets-paymentheader-paymentitem)
- `F-11` [Painel de importação (monitoramento, dry-run, desfazer)](#f-11-painel-de-importação-monitoramento-dry-run-desfazer)

**Fase 4 — Núcleo paciente**

- `F-12` [Plano de Tratamento clínico no prontuário](#f-12-plano-de-tratamento-clínico-no-prontuário)
- `F-13` [Aba Financeiro do paciente (consolidada)](#f-13-aba-financeiro-do-paciente-consolidada)
- `F-14` [Lançamento personalizado (entrada + parcelas variadas)](#f-14-lançamento-personalizado-entrada-+-parcelas-variadas)
- `F-15` [Crédito do paciente e status adimplente/inadimplente](#f-15-crédito-do-paciente-e-status-adimplenteinadimplente)

**Fase 5 — A Receber**

- `F-16` [Tela A Receber (lista, filtros, cards)](#f-16-tela-a-receber-lista-filtros-cards)
- `F-17` [Modal Receber Pagamento (sub-fluxos)](#f-17-modal-receber-pagamento-sub-fluxos)
- `F-18` [Baixa parcial em Dinheiro/PIX/Boleto (BUG-01)](#f-18-baixa-parcial-em-dinheiropixboleto-bug-01)
- `F-19` [Estorno de pagamento](#f-19-estorno-de-pagamento)

**Fase 6 — A Pagar e recorrentes**

- `F-20` [Tela A Pagar e cadastro de despesas](#f-20-tela-a-pagar-e-cadastro-de-despesas)
- `F-21` [Pagamento de despesa e estorno](#f-21-pagamento-de-despesa-e-estorno)
- `F-22` [Cron de despesas recorrentes](#f-22-cron-de-despesas-recorrentes)

**Fase 7 — Fluxo + Caixa físico**

- `F-23` [Tela Fluxo de Caixa](#f-23-tela-fluxo-de-caixa)
- `F-24` [Caixa físico (sessão diária — abertura, sangria, suprimento, fechamento)](#f-24-caixa-físico-sessão-diária-—-abertura-sangria-suprimento-fechamento)
- `F-25` [Lançamentos manuais avulsos (Nova Entrada e Nova Saída)](#f-25-lançamentos-manuais-avulsos-nova-entrada-e-nova-saída)

**Fase 8 — DRE e Dashboard**

- `F-26` [DRE (estrutura, cálculos, drill-down)](#f-26-dre-estrutura-cálculos-drill-down)
- `F-27` [Dashboard financeiro](#f-27-dashboard-financeiro)
- `F-28` [Reclassificação em massa e correções de bugs visuais](#f-28-reclassificação-em-massa-e-correções-de-bugs-visuais)

**Fase 9 — Relatórios**

- `F-29` [Relatório de Comissões](#f-29-relatório-de-comissões)
- `F-30` [Outros relatórios (Despesas por Categoria, Convênio, Ticket Médio)](#f-30-outros-relatórios-despesas-por-categoria-convênio-ticket-médio)

**Fase 10 — Auditoria + LGPD**

- `F-31` [Aba Auditoria por entidade e tela global de logs](#f-31-aba-auditoria-por-entidade-e-tela-global-de-logs)
- `F-32` [Backup automático diário](#f-32-backup-automático-diário)
- `F-33` [Exportação para contador e LGPD (anonimização)](#f-33-exportação-para-contador-e-lgpd-anonimização)

---


## FASE 1 — Fundação técnica

*Modelo de dados, auditoria e permissões. Pré-requisito de todo o resto.*


### `F-01` Modelo de dados financeiro core

**Prioridade:** 🔴 Crítica · 
**Tamanho:** G · 
**Depende de:** `Sem dependências`


**Descrição**

Criar todas as tabelas e relações que sustentam o módulo financeiro. Sem isso nada funciona. É a base de toda a aplicação.


**Como funciona**

Migrations criam as 17 entidades core: Patient, Dentist, Category, BankAccount, CommissionRule, RecurringExpense, RevenueGoal, Budget, Installment, PaymentReceipt, Expense, FinancialEntry, CommissionEntry, CashRegister, CashMovement, AuditLog, PatientCredit. Cada uma com soft delete (deletedAt, deletedBy), timestamps de auditoria (createdAt, createdBy, updatedAt, updatedBy) e foreign keys com ON DELETE RESTRICT. Valores monetários em BIGINT (centavos), nunca float.


**Conversa com**

Base para TODOS os módulos. Toda funcionalidade futura vai ler/escrever essas tabelas.


**Dados / configurações**

17 entidades. Índices em (PatientId), (DentistId), (BankAccountId, dueDate), (status, dueDate). Seed inicial: 1 conta 'Caixa físico', 1 categoria 'Sem categoria' default, 1 perfil ADMIN.


**Critérios de aceite**

- Migrations rodam sem erro em base zerada e em base com dados de teste
- Foreign keys com ON DELETE RESTRICT impedem deletar paciente que tem parcela vinculada
- Constraints de unicidade impedem duplicação (CPF de paciente, externalId Clinicorp)
- Valores monetários sempre em centavos (BIGINT)
- Seed inicial cria entidades default necessárias


> 💡 **Nota técnica:** Considerar particionamento por mês na AuditLog após 12 meses de operação.


### `F-02` Sistema de auditoria (AuditLog)

**Prioridade:** 🔴 Crítica · 
**Tamanho:** M · 
**Depende de:** `F-01`


**Descrição**

Registrar automaticamente toda escrita em entidades financeiras para rastreabilidade total. Permite saber quem fez o quê, quando e o que mudou.


**Como funciona**

Implementar via interceptor/middleware do ORM, sem chamada explícita em cada serviço. Cada CREATE/UPDATE/DELETE em entidade financeira gera 1 linha em AuditLog: id, entityType, entityId, action (CREATE|UPDATE|DELETE|RESTORE|DENIED), userId, ip, userAgent, before (JSONB), after (JSONB), createdAt.


**Conversa com**

Todo módulo financeiro escreve. Aba 'Histórico' de cada entidade lê. Tela global /admin/audit-logs lê.


**Dados / configurações**

Tabela AuditLog. Campos before e after em JSONB para flexibilidade.


**Critérios de aceite**

- Cada CREATE/UPDATE/DELETE em entidade financeira gera 1 linha automaticamente
- Tentativa de ação sem permissão também gera log (action='DENIED')
- Aba 'Histórico de alterações' acessível a partir de qualquer entidade financeira
- ADMIN e AUDITOR conseguem exportar logs em CSV por período
- Insert no AuditLog não bloqueia transação principal


> 💡 **Nota técnica:** Volume cresce rápido. Considerar particionamento mensal e arquivamento de logs com 5+ anos.


### `F-03` Permissões com 5 perfis (RBAC)

**Prioridade:** 🔴 Crítica · 
**Tamanho:** M · 
**Depende de:** `F-01`


**Descrição**

Controle de acesso por perfis. Define quem pode fazer o quê. Permissão modular — cada clínica configura conforme política interna.


**Como funciona**

Cinco perfis: RECEPCAO (lança avulsa, baixa parcela, abre/fecha caixa; NÃO estorna nem vê DRE); DENTIST (vê própria comissão, cria PT); GERENTE (tudo de RECEPCAO + estornar, ver DRE, configurar); ADMIN (tudo, único que altera regra de comissão); AUDITOR (somente leitura). Decorator @RequireRole(['ADMIN','GERENTE']) bloqueia 403 antes de executar.


**Conversa com**

Todos os endpoints. Frontend usa pra esconder botões. Backend usa pra bloquear ações.


**Dados / configurações**

Tabelas User, Role, UserRole. Um usuário pode ter mais de 1 perfil.


**Critérios de aceite**

- Decorator @RequireRole no backend bloqueia 403 antes de executar
- Frontend esconde botões/links de ações que o usuário não pode fazer
- Tela de gestão de usuários permite ADMIN atribuir/remover perfis
- Usuário pode ter múltiplos perfis (ex: dentista que também é admin)
- Tentativa de ação sem permissão gera log AuditLog action='DENIED'


> 💡 **Nota técnica:** Operações sensíveis (estorno, exclusão, reabertura de caixa) exigem confirmação dupla com texto a digitar.


### `F-04` Wizard de configuração inicial obrigatório

**Prioridade:** 🔴 Crítica · 
**Tamanho:** M · 
**Depende de:** `F-01, F-03`


**Descrição**

Quando o ADMIN entra pela primeira vez no módulo financeiro, abre wizard que força configurar o mínimo viável antes de liberar o módulo. Resolve o BUG-04 (DRE em 'Sem categoria') na raiz.


**Como funciona**

Wizard com 5 passos: (1) Criar pelo menos 1 categoria de cada tipo (Receita, Despesa Fixa, Custo Variável, Outra Despesa). (2) Cadastrar pelo menos 1 conta bancária + caixa físico. (3) Cadastrar regra de comissão para cada profissional ativo (skip se a clínica não usa). (4) Cadastrar pelo menos 1 despesa recorrente (skip permitido). (5) Cadastrar meta de receita (skip permitido). Pode ser pausado e retomado — estado salvo em UserPreferences.


**Conversa com**

Bloqueia acesso ao restante do módulo financeiro até completar passos obrigatórios. Cria dados em Categorias, Contas, Comissões, Recorrentes, Metas.


**Dados / configurações**

UserPreferences (estado do wizard). Categorias, Contas, Comissões, Recorrentes, Metas (criadas pelo wizard).


**Critérios de aceite**

- Wizard aparece automaticamente para ADMIN no primeiro acesso ao módulo financeiro
- Bloqueia acesso ao módulo até passos obrigatórios completos
- Pode ser pausado e retomado de onde parou
- Ao concluir, libera o módulo e fica oculto
- Pode ser reaberto via Configurações → Reabrir wizard


> 💡 **Nota técnica:** Crítico para evitar o cenário atual onde tudo cai em 'Sem categoria'. Se o wizard não for obrigatório, o BUG volta.


---


## FASE 2 — Configurações

*Cinco abas que sustentam o resto do módulo. Sem isso, lançamentos caem em 'Sem categoria'.*


### `F-05` Cadastros base — Categorias e Contas Bancárias

**Prioridade:** 🟠 Alta · 
**Tamanho:** M · 
**Depende de:** `F-01, F-03`


**Descrição**

Duas abas de configuração que são pré-requisito de todo lançamento. Categorias definem onde aparece no DRE. Contas definem onde o dinheiro está.


**Como funciona**

ABA CATEGORIAS: CRUD com nome, tipo (RECEITA / DESPESA_FIXA / CUSTO_VARIAVEL / OUTRA_DESPESA), ativa/inativa. Não permite duas iguais do mesmo tipo. Não permite excluir com lançamentos vinculados — oferece migrar primeiro. Categoria 'Sem categoria' não pode ser excluída nem renomeada. ABA CONTAS BANCÁRIAS: CRUD com tipos CHECKING, SAVINGS, CASH (caixa físico), CARD_RECEIVABLE (a receber de maquininha). Saldo inicial só editável na criação. Saldo atual sempre calculado. Tela de transferência entre contas gera 2 lançamentos TRANSFER (saída na origem, entrada no destino) que NÃO somam no DRE.


**Conversa com**

Categorias: usadas em DRE (agrupamento), A Pagar e Fluxo (seleção). Contas: usadas em todos os lançamentos. Caixa físico (type=CASH) é uma BankAccount com particularidade da sessão diária.


**Dados / configurações**

Tabelas Category (id, name, type, active), BankAccount (id, name, type, initialBalance). Saldo atual = initialBalance + Σ entradas − Σ saídas.


**Critérios de aceite**

- CRUD completo das duas: criar, listar, editar, ativar/desativar
- Categoria com lançamentos vinculados não pode ser excluída — oferece migrar
- Contas exibem saldo atual em tempo real
- Transferência entre contas gera 2 lançamentos TRANSFER neutros no DRE
- Não permite excluir conta com saldo ≠ 0 — sugere transferir saldo antes
- Permissão: leitura todos, escrita GERENTE/ADMIN


> 💡 **Nota técnica:** Casos de teste CT-CC-01 a CT-CC-05 da Auditoria Financeira.


### `F-06` Regras de Comissão por profissional

**Prioridade:** 🟠 Alta · 
**Tamanho:** M · 
**Depende de:** `F-01, F-08 (Importação Dentist)`


**Descrição**

Define como a comissão é calculada para cada profissional. Por padrão sobre RECEBIDO (não orçado). Suporta % fixo geral, por procedimento, por especialidade.


**Como funciona**

Para cada Dentist ativo, cadastrar 1+ regras com vigência (validFrom, validTo). Regra mais recente vigente na data do recebimento é a aplicada. Mudança de regra NÃO altera comissões já calculadas — afeta apenas recebimentos futuros. Histórico preservado para auditoria. Opção 'Descontar MDR antes do cálculo' reduz base pela taxa de cartão antes de aplicar o %.


**Conversa com**

Recebimento de pagamento (calcula automaticamente ao confirmar). Relatório → Comissões. Aba Auditoria.


**Dados / configurações**

Tabela CommissionRule (id, dentistId, kind, percent, validFrom, validTo, deductMDR). Histórico em CommissionEntry.


**Critérios de aceite**

- Cadastrar 1+ regras por profissional com vigência
- Regra vigente na data do recebimento é a aplicada (mesmo que regra atual seja diferente)
- Mudança de regra NÃO recalcula comissões antigas
- Comissão sempre sobre RECEBIDO (não orçado) — caso CT-COM-05 da auditoria
- Opção MDR descontado funciona corretamente
- Permissão: apenas ADMIN


> 💡 **Nota técnica:** Comissão histórica da Clinicorp não migra (clínica deve recalcular conforme acordo).


### `F-07` Despesas Recorrentes e Metas

**Prioridade:** 🟡 Média · 
**Tamanho:** M · 
**Depende de:** `F-01, F-05`


**Descrição**

Duas configurações finais. Recorrentes geram automaticamente em A Pagar mensalmente (aluguel, sistema, internet). Metas alimentam o gauge do Dashboard.


**Como funciona**

DESPESAS RECORRENTES: cadastro com nome, categoria padrão, conta padrão, valor (fixo ou variável), dia do mês, recorrência (mensal/bimestral/trimestral/anual), vigência (start/end opcional). Editar valor afeta apenas competências futuras. Inativar não exclui despesas geradas. METAS: três metas independentes (mensal, trimestral, anual). Editar retroativamente recalcula gauge. Quando meta=0, Dashboard oculta gauge e mostra CTA.


**Conversa com**

Recorrentes: alimentam A Pagar via cron (F-22). Metas: alimentam Dashboard (F-27).


**Dados / configurações**

Tabela RecurringExpense (id, name, categoryId, accountId, amount, dayOfMonth, frequency, validFrom, validTo). Tabela RevenueGoal (id, type, amount, period).


**Critérios de aceite**

- CRUD completo das duas
- Editar valor da recorrente afeta APENAS competências futuras
- Inativar recorrente NÃO exclui despesas já geradas
- Editar meta retroativamente recalcula gauge
- Meta=0 oculta gauge no Dashboard


> 💡 **Nota técnica:** Cron de geração das recorrentes está no F-22. Aqui é só o cadastro.


---


## FASE 3 — Importação Clinicorp

*Quatro importadores em ordem específica. Idempotentes, com painel de monitoramento e desfazer.*


### `F-08` Importador de cadastros (Profissionais, Templates, Pacientes)

**Prioridade:** 🔴 Crítica · 
**Tamanho:** G · 
**Depende de:** `F-01`


**Descrição**

Importa Dentist.xlsx (9 profissionais, 8 ativos), AnamnesisQuestions.xlsx (44 perguntas em 3 templates) e Patient.xlsx (2.559 pacientes, 2.407 ativos). Primeiro passo da migração — sem isso, todos os outros importam órfãos.


**Como funciona**

Roda em ordem: (1) Dentist primeiro — Type=DENTIST vira perfil DENTIST do RBAC, Deleted=X vira soft delete. (2) AnamnesisQuestions — cada TemplateId vira AnamnesisTemplate, cada linha vira AnamnesisQuestion, preserva Seq. (3) Patient — mapear 42 campos, detectar duplicatas por CPF antes de importar (gerar relatório para ADMIN), Active=X vira ativo, Deleted=X soft-deleted. Cada importação aceita arquivo XLSX, pre-valida colunas obrigatórias, roda em background com job assíncrono, retorna relatório (total, importadas, ignoradas com motivo, com erro com linha).


**Conversa com**

Pré-requisito de tudo. Anamnesis, Appointments, Budgets, Payments referenciam essas entidades.


**Dados / configurações**

Mapeamento Dentist: Name, CRO, Email, OtherDocumentId (CPF), MobilePhone, BirthDate, Sex, Active, Deleted, id (Clinicorp) → guardar como externalId. Patient: 42 campos relevantes. AnamnesisQuestions: TemplateId, QuestionType (YES_NO/DESC/OPTIONS), Options (JSON), Seq.


**Critérios de aceite**

- Dentist: 8 ativos importados (Daniele, Aline, Gustavo, Guilherme, Maria Luisa, Giovana, Ironete, Cláudia)
- AnamnesisQuestions: 3 templates visíveis em Configurações → Anamnese, perguntas em ordem
- Patient: 2.407 ativos visíveis em Pacientes
- Detector de duplicatas por CPF gera relatório de revisão para ADMIN
- Idempotente: rodar 2x não duplica registros (uso de externalId como chave)
- Relatório de importação: total processado, importado, ignorado com motivo, erro com linha


> 💡 **Nota técnica:** Idempotência via header Idempotency-Key (UUID v4). Mesma chave devolve mesma resposta.


### `F-09` Importador de histórico clínico

**Prioridade:** 🟠 Alta · 
**Tamanho:** G · 
**Depende de:** `F-08`


**Descrição**

Importa Anamnesis.xlsx (30 cabeçalhos), PatientAnamnesis.xlsx (600 respostas), Appointment.xlsx (8.745 agendamentos jul/2023 a jan/2027, 346 cancelados) e TreatmentOperation.xlsx (9.638 procedimentos clínicos, 9.635 executados).


**Como funciona**

Roda em ordem: (1) Anamnesis cabeçalho (liga via Patient_PersonId). (2) PatientAnamnesis respostas (liga via AnamnesisId e TemplateId). (3) Appointment (preserva Status: CONFIRMED, MISSED, CHECKOUT, ARRIVED, IN_SESSION, LATE, CANCELED). (4) TreatmentOperation (Deleted=X não importa; ATENÇÃO: 9.637 estão com DentistId vazio — confirmar com Clinicorp se há outra exportação antes de prosseguir).


**Conversa com**

Anamnese alimenta aba Anamnese do prontuário. Appointment alimenta agenda. TreatmentOperation alimenta evolução do prontuário.


**Dados / configurações**

Anamnesis (30 cabeçalhos com CurrentAnamnesis=X). PatientAnamnesis (600 respostas). Appointment (date, fromTime, toTime, PatientId, DentistId, Status, Notes). TreatmentOperation (Amount, ProcedureCondition, Type, Tooth, Surface, ExecutedDate).


**Critérios de aceite**

- 30 anamneses cabeçalho importadas, vinculadas aos pacientes corretos
- 600 respostas importadas, conferíveis em 3 pacientes-amostra
- 8.745 agendamentos visíveis na agenda (filtrar mês de jul/2023 retorna eventos)
- 346 cancelados aparecem como CANCELED (não somem)
- Procedimentos clínicos sem DentistId importam vinculados apenas ao Patient com aviso
- Relatório lista quais pacientes têm procedimentos sem profissional vinculado


> 💡 **Nota técnica:** BLOQUEADOR: validar com Clinicorp se há campos preenchidos em outra exportação para TreatmentOperation.


### `F-10` Importador financeiro (Budgets, PaymentHeader, PaymentItem)

**Prioridade:** 🔴 Crítica · 
**Tamanho:** G · 
**Depende de:** `F-08, F-05`


**Descrição**

Importa os 34 orçamentos abertos (≤ R$ 24.650,83), 1.766 cobranças (PaymentHeader) e 2.216 parcelas ativas (PaymentItem). Total histórico: R$ 537.794,90 lançado, R$ 445.025,75 recebido. Saldo a receber: R$ 92.769,15.


**Como funciona**

Roda em ordem: (1) Budgets vira Orçamento no Klivy (NÃO Plano de Tratamento, pois Clinicorp não tem PT clínico — todos importam como Orçamento). (2) PaymentHeader vira cabeçalho de cobrança. (3) PaymentItem vira Installment com mapeamento Type → forma de pagamento Klivy: OTHER 1.167 (51%) → Dinheiro por padrão (revisar PIX depois), CREDIT_CARD_EXTERNAL 717 (31%), DEBIT_CARD_EXTERNAL 331 (15%), BOLETO_INTERNAL 38 (2%), CREDIT_CARD_INTERNAL 30 (1%). Cada PaymentHeader com IsPartialPayment=X (34 casos tipo Manuele) entra em fila de revisão manual.


**Conversa com**

Alimenta A Receber, Financeiro do Paciente, Fluxo de Caixa, DRE.


**Dados / configurações**

Budgets.xlsx → Budget. PaymentHeader.xlsx → PaymentReceipt. PaymentItem.xlsx → Installment. BookEntry.xlsx NÃO importa (duplicaria).


**Critérios de aceite**

- 34 orçamentos visíveis no Klivy como Orçamento (não como PT)
- 1.766 cobranças importadas
- 2.216 parcelas com status correto (PENDING/RECEIVED/CANCELED)
- OTHER mapeia para Dinheiro por padrão
- 34 pagamentos parciais (IsPartialPayment=X) entram em fila de revisão
- BookEntry NÃO importa (apenas arquiva como referência)
- Total recebido e total a receber batem com a Clinicorp (R$ 445k recebido, R$ 92k a receber)


> 💡 **Nota técnica:** Após importar, ADMIN deve usar tela de Reclassificação em massa para corrigir OTHER → PIX nos casos relevantes (geralmente valor > R$ 200).


### `F-11` Painel de importação (monitoramento, dry-run, desfazer)

**Status:** ❌ **OUT-OF-SCOPE** (decisão Mamedes, 2026-05-11) — importação permanece exclusivamente no painel `/super_admin/migrations`, acessível só pelo time Klivy/Beclinic. A clínica não tem motivo operacional pra re-importar Clinicorp depois do go-live, então uma tela ADMIN dedicada seria over-engineering. Manter em super_admin centraliza risco e simplifica auditoria.

**Prioridade:** 🟠 Alta · 
**Tamanho:** M · 
**Depende de:** `F-08, F-09, F-10`


**Descrição**

Tela única em Configurações → Importação Clinicorp para o ADMIN gerenciar todo o processo de migração. Mostra status de cada importador, permite dry-run, refazer e desfazer.


**Como funciona**

Tela com cards para cada importador (Cadastros, Clínico, Financeiro). Cada card mostra: status (não iniciado / em andamento / concluído / com erro), última execução, total de registros, log do último relatório. Botões: Upload XLSX, Dry-run (simula sem salvar), Executar, Desfazer. Histórico de execuções em tabela embaixo. Cada importação gera ImportBatch com ID único — desfazer reverte usando esse ID.


**Conversa com**

Lê AuditLog para mostrar histórico. Aciona os 3 importadores (F-08, F-09, F-10).


**Dados / configurações**

Tabela ImportBatch (id, kind, status, totalRows, importedRows, errorRows, startedAt, finishedAt, userId, reportJson). Cada registro importado guarda batchId para permitir desfazer.


**Critérios de aceite**

- Painel mostra status de cada importador em tempo real
- Dry-run simula a importação e mostra o relatório sem salvar nada
- Desfazer reverte uma importação específica via batchId
- Histórico mostra todas as importações com link para o relatório completo
- Apenas ADMIN tem acesso
- Importação grande (Pacientes, PaymentItem) roda em background sem travar a UI


> 💡 **Nota técnica:** Período de paralelo recomendado: manter Clinicorp em modo leitura por 60 dias pós go-live.


---


## FASE 4 — Núcleo paciente

*PT clínico, aba Financeiro consolidada, lançamento personalizado e crédito do paciente.*


### `F-12` Plano de Tratamento clínico no prontuário

**Prioridade:** 🔴 Crítica · 
**Tamanho:** G · 
**Depende de:** `F-01, F-08`


**Descrição**

Aba Plano de Tratamento dentro do prontuário do paciente. Profissional (ou quem tiver permissão) cria PT com procedimentos e valores. Ao aprovar, gera as parcelas em A Receber automaticamente. Cobre cerca de 90% das receitas da clínica.


**Como funciona**

Botão 'Novo Plano' abre tela de criação. Adiciona procedimentos linha a linha (dente, face, tipo, condição, profissional executor, valor padrão da tabela ou valor manual). Soma total no rodapé. Ao salvar, fica em status DRAFT. Botão 'Aprovar' abre modal de parcelamento: número de parcelas, vencimento inicial, forma de pagamento. Modo simples (todas iguais) ou modo personalizado (parcelas com condições diferentes — ver F-14). Ao confirmar aprovação, gera N Installments em A Receber, status do PT vira APPROVED. Em IN_PROGRESS conforme procedimentos vão sendo executados. Em COMPLETED quando todos executados.


**Conversa com**

Gera parcelas em A Receber (F-16). Aparece na aba Financeiro do paciente (F-13) com link 'Visualizar Plano de Tratamento'. Procedimentos executados aparecem na evolução. Comissão calculada conforme regra do executor (F-06).


**Dados / configurações**

Tabela TreatmentPlan (id, patientId, status, totalAmount, createdBy, approvedBy, approvedAt). Tabela TreatmentPlanItem (id, treatmentPlanId, dentistId, procedure, tooth, surface, amount, executedAt).


**Critérios de aceite**

- Profissional consegue criar PT, adicionar procedimentos, salvar como DRAFT
- Permissão modular para aprovação: clínica define quem aprova (recepção, dentista ou financeiro)
- Aprovar gera as parcelas com a configuração escolhida (simples ou personalizada)
- PT aprovado pode ser editado APENAS por GERENTE/ADMIN com motivo (resolve BUG-02)
- Procedimentos executados aparecem na aba Evolução com data e profissional
- Status do PT atualiza automaticamente conforme execução


> 💡 **Nota técnica:** BUG-02 da auditoria: hoje PT aprovado não pode ser editado nem excluído. Resolver com permissão escalonada.


### `F-13` Aba Financeiro do paciente (consolidada)

**Prioridade:** 🔴 Crítica · 
**Tamanho:** G · 
**Depende de:** `F-01, F-12`


**Descrição**

Aba reformulada — substitui as 4 sub-abas atuais (Transações, Orçamentos, Plano de Tratamento, Recibos) por uma tabela única consolidada inspirada na Clinicorp. Todo lançamento do paciente em uma só visão.


**Como funciona**

Cards superiores (5): Total Aprovado, Pago/Recebido, Em Aberto, Devedor (Vencido), Crédito. Botões topo: Novo Orçamento, Adicionar Lançamento, Adicionar Mensalidades, Receber Pagamento (permissão modular por botão). Filtros: Todos / Pendentes / Pagos / Vencidos / Estornados. Tabela única com colunas: Data, Descrição + Origem (link clicável para PT/Orçamento), Valor, Saldo, Forma, Parcelas (bolinhas numeradas indicando status — azul preenchida = paga, contorno cinza = pendente, contorno vermelho = vencida), Ações (menu ⋮). Footer mostra saldo a pagar total.


**Conversa com**

Espelho do A Receber filtrado pelo paciente (F-16). Origem de cada linha linka para o PT (F-12) ou Orçamento. Crédito do paciente (F-15). Receber pagamento (F-17).


**Dados / configurações**

View consolidada de Installments + Expenses + Lançamentos avulsos do paciente. Não cria entidade nova — é apenas visualização.


**Critérios de aceite**

- Tabela única substitui as 4 sub-abas atuais
- Coluna 'Origem' tem link clicável que abre o PT/Orçamento de origem em drawer
- Bolinhas das parcelas indicam status visualmente (paga/pendente/vencida)
- Botão 'Cobrar' do header do paciente vira atalho para esta aba
- Filtros funcionam corretamente
- Permissão modular por botão (clínica decide quem vê quais)


> 💡 **Nota técnica:** Inspiração visual: print da Clinicorp Financeiro do paciente. Estética: paleta Klivy, sem replicar cores antigas.


### `F-14` Lançamento personalizado (entrada + parcelas variadas)

**Prioridade:** 🔴 Crítica · 
**Tamanho:** M · 
**Depende de:** `F-13`


**Descrição**

Resolve em uma feature só dois casos importantes: (1) paciente que dá entrada e depois parcela com valores diferentes, (2) caso da Manuele (BUG-01) onde paciente paga valor diferente do combinado para uma parcela.


**Como funciona**

Modal 'Adicionar Lançamento' tem dois modos: Modo Simples (90% dos casos) — valor único, N parcelas iguais, vencimentos sequenciais, forma única. Modo Personalizado (toggle 'parcelas com condições diferentes') — abre lista editável onde cada linha tem valor próprio, vencimento próprio e forma própria. Permite adicionar entrada explícita + parcelas. Validação: soma das linhas deve bater com valor total. Cada linha vira uma Installment independente no banco.


**Conversa com**

Cria Installments em A Receber. Disponível tanto no modal de aprovação de PT (F-12) quanto no modal Adicionar Lançamento da aba Financeiro do paciente (F-13).


**Dados / configurações**

Mesma tabela Installment do F-01, sem mudanças estruturais. Apenas a UI permite criar parcelas heterogêneas.


**Critérios de aceite**

- Modo Simples gera N parcelas iguais a partir de valor + vencimento + N
- Modo Personalizado permite definir valor, data e forma de cada parcela individual
- Validação: soma das linhas tem que bater com valor total
- Permite adicionar uma 'entrada' (parcela 0) e parcelas seguintes
- Cada parcela criada em modo personalizado é independente no banco
- Disponível no modal de aprovação de PT e no Adicionar Lançamento avulso


> 💡 **Nota técnica:** Forma 'Múltiplas' já existe na Clinicorp — Klivy precisa ter equivalente. Resolve BUG-01 e o caso Manuele em uma feature só.


### `F-15` Crédito do paciente e status adimplente/inadimplente

**Prioridade:** 🟠 Alta · 
**Tamanho:** M · 
**Depende de:** `F-01, F-13`


**Descrição**

PatientCredit é o saldo a favor do paciente. Vem de estorno sem devolução, pré-pagamento, ou pagamento maior que a parcela. Pode abater parcela futura ou ser sacado em dinheiro. Status do paciente (Adimplente/Inadimplente) calculado automaticamente.


**Como funciona**

Toda vez que estorno gera devolução em crédito (F-19), PatientCredit aumenta. Toda vez que recebimento usa crédito como forma, PatientCredit diminui. Toda vez que paciente paga mais que a parcela, diferença vira crédito. Saque do crédito gera SAÍDA na conta. Status: Adimplente se não tem parcela vencida, Inadimplente se tem 1+ vencida. Badge no header do paciente atualiza em tempo real.


**Conversa com**

Card 'Crédito' na aba Financeiro do paciente (F-13). Modal Receber Pagamento (F-17) oferece usar crédito. Estorno (F-19) oferece converter em crédito. Header do paciente mostra badge.


**Dados / configurações**

Tabela PatientCredit (id, patientId, balance, lastUpdate). Tabela CreditMovement (id, patientCreditId, kind: ADD/USE/WITHDRAW, amount, sourceEntityType, sourceEntityId, createdAt).


**Critérios de aceite**

- PatientCredit incrementa em estornos com devolução em crédito
- Receber Pagamento permite usar crédito como forma de pagamento
- Saque do crédito gera SAÍDA registrada no Fluxo
- Pagamento maior que parcela oferece diferença como crédito
- Badge Adimplente/Inadimplente atualiza em tempo real
- Histórico de movimentos do crédito acessível


> 💡 **Nota técnica:** Crédito do paciente já existe no Klivy atual (mostrado nos prints). Aqui é integração completa com fluxos de estorno e recebimento.


---


## FASE 5 — A Receber

*Tela A Receber, recebimento, baixa parcial (BUG-01) e estorno.*


### `F-16` Tela A Receber (lista, filtros, cards)

**Prioridade:** 🔴 Crítica · 
**Tamanho:** G · 
**Depende de:** `F-01, F-12`


**Descrição**

Lista global de tudo a receber e tudo já recebido. Coração do dia a dia da recepção. Equivale ao print do Klivy atual de A Receber.


**Como funciona**

Cards superiores (4): Total a Receber, Recebido, Vencido, Transações — calculados em tempo real conforme filtro de período. Tabela: Descrição (paciente + parcela), Valor, Vencimento, Recebido em, Forma, Status, Ações. Ordenação clicável em cada coluna. Filtros: descrição (busca), período, status (Pendente/Recebido/Vencido/Estornado/Cancelado), forma de pagamento. Ações por linha: Editar parcela (se PENDING), Receber pagamento, Estornar (se RECEIVED), Visualizar PT/Orçamento de origem. Botões topo: Nova Entrada (atalho lançamento avulso), Gerar PDF (extrato do período).


**Conversa com**

Espelho de Installments. Ações abrem modais (F-17 receber, F-19 estornar). Origem clicável vai pra PT/Orçamento.


**Dados / configurações**

Lê tabela Installment com joins em Patient, TreatmentPlan/Budget, Category.


**Critérios de aceite**

- Cards calculam corretamente conforme filtro de período
- Tabela mostra todas as parcelas com status correto
- Filtros funcionam combinados (data + status + forma)
- Cada linha tem link para o PT/Orçamento de origem
- Performance: lista com 2.216 parcelas (volume Clinicorp) carrega em <2s com paginação
- Permissão: leitura todos com acesso ao financeiro, ações conforme F-03


> 💡 **Nota técnica:** Depois da migração, vai ter 2.216 parcelas + as novas. Paginar ou virtualizar a tabela.


### `F-17` Modal Receber Pagamento (sub-fluxos)

**Prioridade:** 🔴 Crítica · 
**Tamanho:** G · 
**Depende de:** `F-16, F-15`


**Descrição**

Modal central que confirma o recebimento. Tem dois sub-fluxos: baixar parcela existente OU receber valor avulso (sem parcela vinculada).


**Como funciona**

Sub-fluxo 1 (parcela existente): selecionar parcela(s) a baixar, escolher forma de pagamento, valor (pré-preenchido com o da parcela), data efetiva, conta destino. Calcula juros e multa automaticamente se vencida (F-19 trata juros). Permite usar crédito do paciente (F-15) total ou parcial. Sub-fluxo 2 (avulso): valor, forma, data, conta — vira receita avulsa OU crédito do paciente conforme escolha. Após confirmar: cria FinancialEntry (ENTRADA) na conta, atualiza saldo, atualiza status da parcela (PENDING → RECEIVED), calcula CommissionEntry para o profissional, gera PaymentReceipt opcional, dispara webhook se configurado.


**Conversa com**

Atualiza Installment, BankAccount (saldo), FinancialEntry (Fluxo), CommissionEntry, PaymentReceipt. Dispara recálculo de status do paciente.


**Dados / configurações**

Operação atômica em transação de banco — se qualquer passo falhar, desfaz tudo.


**Critérios de aceite**

- Sub-fluxo parcela existente funciona (parcela vai pra RECEIVED, saldo conta atualiza)
- Sub-fluxo avulso funciona (vira receita ou crédito conforme escolha)
- Juros e multa calculados automaticamente em parcela vencida
- Crédito do paciente pode ser usado total ou parcialmente
- Operação atômica: falha em comissão desfaz baixa da parcela
- Idempotente: duplo clique não duplica recebimento


> 💡 **Nota técnica:** Endpoint receberá header Idempotency-Key obrigatório. Sem ele, retornar 400.


### `F-18` Baixa parcial em Dinheiro/PIX/Boleto (BUG-01)

**Prioridade:** 🔴 Crítica · 
**Tamanho:** M · 
**Depende de:** `F-17`


**Descrição**

BUG CRÍTICO da auditoria: hoje o sistema não permite baixar valor diferente da parcela em Dinheiro/PIX/Boleto (caso Manuele — combinado R$ 306, paga R$ 276, sistema trava). Esse card desbloqueia.


**Como funciona**

Modal Receber Pagamento aceita valor menor que o total da parcela. Quando valor pago < valor da parcela, sistema oferece: (a) deixar diferença como saldo a receber (parcela continua PENDING com novo valor remanescente), (b) cancelar a diferença (parcela vai pra RECEIVED com valor parcial registrado, diferença vira write-off categorizado), (c) usar lançamento personalizado (F-14) e criar 2 parcelas no lugar da original.


**Conversa com**

Estende F-17. Se opção (b), cria FinancialEntry de write-off com categoria 'Desconto Concedido'.


**Dados / configurações**

Adiciona campo originalAmount em Installment (preserva valor original quando baixa parcial). Categoria 'Desconto Concedido' deve estar no seed (F-05).


**Critérios de aceite**

- Caso Manuele resolvido: parcela R$ 306, paga R$ 276 com 3 opções
- Opção 'deixar saldo' atualiza valor da parcela e mantém como PENDING
- Opção 'cancelar diferença' gera write-off categorizado
- Opção 'parcelar diferença' usa modo personalizado (F-14)
- Funciona em Dinheiro, PIX, Boleto e Múltiplas (não só cartão)
- Caso de teste CT-AR-03 da auditoria


> 💡 **Nota técnica:** Casos de teste CT-AR-03 e CT-AR-04 da Auditoria Financeira. Bug número 1 da clínica hoje.


### `F-19` Estorno de pagamento

**Prioridade:** 🟠 Alta · 
**Tamanho:** M · 
**Depende de:** `F-17, F-15`


**Descrição**

Cancela um recebimento confirmado. Reverte tudo em cadeia. Operação delicada que precisa permissão GERENTE/ADMIN e exige confirmação dupla.


**Como funciona**

Botão Estornar na linha da parcela RECEIVED abre modal: motivo do estorno (obrigatório), opção (devolver dinheiro AGORA OU converter em crédito do paciente). Ao confirmar: parcela volta para PENDING, BankAccount perde valor (saída), gera FinancialEntry de saída no DRE com cashDate=hoje (não retroativo), reverte CommissionEntry do profissional, recalcula status do paciente (Adimplente/Inadimplente). Tudo em transação atômica.


**Conversa com**

Atualiza Installment, BankAccount, FinancialEntry, CommissionEntry, PatientCredit (se opção crédito). AuditLog registra com motivo.


**Dados / configurações**

Sem nova entidade. Adiciona campo reversedAt, reversedBy e reversedReason em PaymentReceipt e Installment.


**Critérios de aceite**

- Permissão GERENTE/ADMIN obrigatória (RECEPCAO não vê o botão)
- Confirmação dupla com motivo obrigatório
- Parcela volta a PENDING com histórico do estorno preservado
- Saída lançada no Fluxo do dia atual (não retroativa)
- Comissão revertida automaticamente
- Opção 'converter em crédito' incrementa PatientCredit ao invés de gerar saída
- Operação atômica — falha em qualquer passo desfaz tudo


> 💡 **Nota técnica:** Casos CT-EST-01 a CT-EST-04 da Auditoria. Categoria 'Devoluções' deve estar no seed.


---


## FASE 6 — A Pagar e recorrentes

*Tela A Pagar, pagamento de despesa e cron das recorrentes.*


### `F-20` Tela A Pagar e cadastro de despesas

**Prioridade:** 🟠 Alta · 
**Tamanho:** M · 
**Depende de:** `F-01, F-05`


**Descrição**

Espelho de A Receber para o lado de saídas. Recepção/financeiro lança despesas avulsas (aluguel, fornecedor, salário, etc) para pagamento futuro.


**Como funciona**

Cards (4): Total a Pagar, Total Recorrente, Próximos a Vencer (3 dias), Transações. Tabela: Descrição, Categoria, Vencimento, Valor, Conta, Status, Ações. Filtros: descrição, período, categoria, conta, status, 'Apenas vencidos'. Botão Nova Despesa abre modal: descrição, categoria, fornecedor (texto livre), valor, vencimento, conta de saída prevista, número de parcelas (se for parcelado), anexo opcional. Status inicial PENDING. Ações por linha: Editar (se PENDING), Pagar, Estornar (se PAID), Excluir (se PENDING).


**Conversa com**

Recebe despesas das Recorrentes (F-22). Disparo de pagamento (F-21). Categorias e Contas (F-05).


**Dados / configurações**

Tabela Expense (id, description, categoryId, supplierName, amount, dueDate, accountId, status, attachmentUrl, paidAt, paidBy).


**Critérios de aceite**

- Cards calculam corretamente
- Tabela mostra despesas com status correto
- Filtros funcionam combinados
- Anexo de comprovante (PDF/imagem) funciona
- Edição só em status PENDING
- Permissão: criar e pagar RECEPCAO/GERENTE/ADMIN, estornar GERENTE/ADMIN, excluir paga apenas ADMIN


> 💡 **Nota técnica:** Hoje a tela está vazia (print). Implementar do zero.


### `F-21` Pagamento de despesa e estorno

**Prioridade:** 🟠 Alta · 
**Tamanho:** M · 
**Depende de:** `F-20`


**Descrição**

Modal de pagamento e operação de estorno para despesas.


**Como funciona**

Botão Pagar abre modal: confirmar valor, data efetiva, conta de saída, anexo opcional do comprovante. Ao confirmar: cria FinancialEntry (SAÍDA) na conta, atualiza saldo, status da Expense vira PAID. Botão Estornar (em despesa PAID): motivo obrigatório, gera ENTRADA no Fluxo do dia atual (devolução), Expense volta a PENDING, atualiza saldo da conta. Operação atômica.


**Conversa com**

Atualiza Expense, BankAccount, FinancialEntry. AuditLog registra.


**Dados / configurações**

Sem nova entidade. Adiciona reversedAt, reversedBy, reversedReason em Expense.


**Critérios de aceite**

- Pagamento gera SAÍDA correta no Fluxo e atualiza saldo
- Estorno gera ENTRADA no dia atual (não retroativa)
- Permissão: pagar RECEPCAO/GERENTE/ADMIN, estornar GERENTE/ADMIN
- Pagamento parcial: oferece dividir despesa em 2 (paga + nova pendente com diferença)
- Confirmação dupla com motivo no estorno
- Operação atômica


> 💡 **Nota técnica:** Pagamento parcial é caso 'inverso' do BUG-01 — pode reusar lógica do F-18 adaptada.


### `F-22` Cron de despesas recorrentes

**Prioridade:** 🟡 Média · 
**Tamanho:** M · 
**Depende de:** `F-07, F-20`


**Descrição**

Job que roda diariamente e gera as despesas em A Pagar conforme as RecurringExpenses cadastradas. Cobre aluguel, sistema, internet, plano de telefonia, contador.


**Como funciona**

Cron roda às 00:01 todo dia. Para cada RecurringExpense ativa: gera as Expenses para os próximos 35 dias (1 mês adiantado para o usuário ver no A Pagar com antecedência). É idempotente: se já existe Expense para aquela competência, NÃO cria de novo. Edição de valor da recorrente afeta APENAS competências futuras — anteriores ficam preservadas. Inativar não exclui despesas existentes.


**Conversa com**

Lê RecurringExpense (F-07). Cria Expense em A Pagar (F-20).


**Dados / configurações**

Sem entidade nova. Job/cron job no scheduler do backend. Adiciona campo recurringExpenseId em Expense para rastreabilidade.


**Critérios de aceite**

- Cron roda diariamente sem intervenção manual
- Gera Expenses para próximos 35 dias
- Idempotente: rodar 2x não duplica
- Editar valor da recorrente afeta apenas futuras
- Inativar recorrente não exclui as já geradas
- Logs do cron acessíveis para ADMIN


> 💡 **Nota técnica:** Considerar usar bull/bullmq ou similar. Alertar ADMIN se cron falhar 2 dias seguidos.


---


## FASE 7 — Fluxo + Caixa físico

*Tela Fluxo de Caixa, sessão de caixa físico e lançamentos manuais.*


### `F-23` Tela Fluxo de Caixa

**Prioridade:** 🟠 Alta · 
**Tamanho:** G · 
**Depende de:** `F-01, F-17, F-21`


**Descrição**

Visão pelo regime caixa (o que entrou e saiu da conta). Fotografia do dinheiro real do período. Resolve BUG-06 da auditoria (nomenclatura confusa de saldos).


**Como funciona**

Cards (4): Total Entradas, Total Saídas, Resultado do Período (entradas − saídas, varia com filtro), Saldo Disponível Hoje (saldo atual de TODAS as contas, instantâneo, NÃO varia com filtro). Gráfico: linha dupla verde (entradas) + vermelha (saídas) por dia do período. Tabela detalhamento por dia: Data, Entradas, Saídas, Saldo cumulativo. Clicar em dia abre drawer com transações daquele dia. Botões: Nova Entrada, Nova Saída (atalho — cria Expense PAID em uma operação), Gerar PDF.


**Conversa com**

Lê de FinancialEntry com cashDate dentro do período. Não escreve direto (apenas via Nova Entrada/Saída que criam FinancialEntry).


**Dados / configurações**

View materializada ou query agregada de FinancialEntry. Cuidar da performance: indexar (cashDate, accountId).


**Critérios de aceite**

- BUG-06 resolvido: nomes 'Resultado do Período' e 'Saldo Disponível Hoje' (não 'Saldo Líquido' e 'Saldo em Caixa')
- Cards calculam corretamente com filtro de período
- Gráfico de linha mostra entradas e saídas por dia
- Drill-down por dia funciona
- Lançamento retroativo permitido com aviso
- Bloqueado se data cai em caixa fechado — exige reabrir


> 💡 **Nota técnica:** Casos de teste CT-FC-01 e CT-FC-02 da auditoria.


### `F-24` Caixa físico (sessão diária — abertura, sangria, suprimento, fechamento)

**Prioridade:** 🟠 Alta · 
**Tamanho:** G · 
**Depende de:** `F-01, F-23`


**Descrição**

Rastreia especificamente o dinheiro em espécie. Caixa físico é uma BankAccount type=CASH com particularidade: tem sessão diária (abertura → fechamento) com controle de quebra.


**Como funciona**

ABERTURA: recepcionista digita saldo inicial em dinheiro. Cria CashRegister status=OPEN. Apenas 1 caixa aberto por dia. SANGRIA: tirar dinheiro do caixa para depositar em conta bancária. Movimento neutro no DRE. SUPRIMENTO: inverso, banco → caixa físico (troco). FECHAMENTO: recepcionista conta o dinheiro. Sistema mostra esperado (abertura + entradas − saídas − sangrias + suprimentos). Diferença = Quebra de Caixa: falta vai pra Outras Despesas, sobra vai pra Outras Receitas. REABERTURA: permitida para GERENTE/ADMIN com motivo obrigatório. BLOQUEIO: lançamento em dinheiro com data em caixa fechado retorna erro pedindo reabrir antes.


**Conversa com**

Recebe entradas em dinheiro de F-17. Recebe saídas em dinheiro de F-21. Cria FinancialEntries em F-23. Quebra de caixa cria FinancialEntry em categoria Outras Despesas/Receitas.


**Dados / configurações**

Tabela CashRegister (id, openedAt, openedBy, openingBalance, closedAt, closedBy, expectedBalance, countedBalance, difference, status). Tabela CashMovement (id, cashRegisterId, kind: SANGRIA/SUPRIMENTO/QUEBRA, amount, accountId, createdBy, createdAt).


**Critérios de aceite**

- Apenas 1 caixa aberto por dia
- Sangria e suprimento são movimentos TRANSFER — neutros no DRE
- Fechamento calcula esperado e oferece registrar quebra
- Quebra de caixa categorizada em Outras Despesas/Receitas
- Reabertura exige permissão e motivo
- Bloqueia lançamento em dinheiro com data em caixa fechado
- Aba Histórico lista sessões anteriores


> 💡 **Nota técnica:** Categorias 'Quebra de Caixa' (despesa) e 'Sobra de Caixa' (receita) devem estar no seed.


### `F-25` Lançamentos manuais avulsos (Nova Entrada e Nova Saída)

**Prioridade:** 🟡 Média · 
**Tamanho:** P · 
**Depende de:** `F-23`


**Descrição**

Atalhos para registrar entrada ou saída avulsa direto no Fluxo de Caixa, sem passar por A Receber ou A Pagar. Útil para situações fora do fluxo normal.


**Como funciona**

Botão Nova Entrada: descrição, valor, conta destino, categoria de receita, data efetiva, opção de vincular paciente. Cria FinancialEntry direto. Botão Nova Saída: similar, mas cria Expense PAID em uma operação só (atalho — pula etapa A Pagar). Vinculação a paciente é opcional — se vincular, aparece também na aba Financeiro do paciente.


**Conversa com**

Cria FinancialEntry / Expense. Se vinculado a paciente, aparece em F-13.


**Dados / configurações**

Mesmas tabelas de F-17 e F-21. Sem nova entidade.


**Critérios de aceite**

- Nova Entrada cria FinancialEntry com categoria escolhida
- Nova Saída cria Expense PAID em uma operação
- Vinculação opcional a paciente funciona
- Permissão: RECEPCAO/GERENTE/ADMIN
- Lançamentos aparecem no Fluxo de Caixa imediatamente


> 💡 **Nota técnica:** Casos de uso: venda balcão sem cadastro, recebimento de juros, devolução de imposto.


---


## FASE 8 — DRE e Dashboard

*Telas de visualização. Apenas leitura. Resolve BUGs visuais (BUG-03, BUG-04, BUG-05).*


### `F-26` DRE (estrutura, cálculos, drill-down)

**Prioridade:** 🟠 Alta · 
**Tamanho:** G · 
**Depende de:** `F-01, F-05`


**Descrição**

Demonstração do Resultado do Exercício. Visão pelo regime competência. Receita aparece quando foi gerada (orçamento aprovado), despesa quando incorrida — independente de quando o dinheiro mudou de mãos.


**Como funciona**

Estrutura hierárquica: Receita Bruta → Deduções → Receita Líquida → Custos Variáveis → Margem Bruta → Despesas Fixas → EBITDA → Outras Despesas → Lucro Líquido. Toggle de período: Mês / Trimestre / Ano / Personalizado. Comparativo período anterior na mesma tabela (Período Atual, Período Anterior, Var %). Var % corrigida: quando base anterior é zero/muito pequena mostra 'Novo' em verde; quando atual zerou e anterior tinha valor, 'Zerou' em vermelho (resolve BUG-03). Drill-down: linha agregadora expande mostrando categorias; categoria abre lista de lançamentos; lançamento vai pra origem. Banner amarelo no topo se há lançamentos em 'Sem categoria' — link direto para reclassificação em massa (resolve BUG-04). Botão Gerar PDF.


**Conversa com**

Apenas leitura. Lê de FinancialEntry com competenceDate dentro do período.


**Dados / configurações**

Query agregada com GROUP BY categoria. Performance crítica: índice em (competenceDate, categoryId).


**Critérios de aceite**

- Estrutura hierárquica completa com cálculos corretos
- Var % corrigida (BUG-03): mostra 'Novo'/'Zerou' ao invés de % absurda como 1713%
- Banner 'Sem categoria' (BUG-04) com link para reclassificação
- Drill-down funciona em 3 níveis (linha → categoria → lançamento)
- Toggle de período funciona corretamente
- PDF formato amigável para contador
- Permissão: GERENTE/ADMIN/AUDITOR (RECEPCAO não vê)


> 💡 **Nota técnica:** BUGs CT-DRE-01 a CT-DRE-05 da Auditoria.


### `F-27` Dashboard financeiro

**Prioridade:** 🟠 Alta · 
**Tamanho:** G · 
**Depende de:** `F-23, F-26, F-07`


**Descrição**

Tela inicial do módulo financeiro. Visão executiva do dia. Onde o gestor olha primeiro de manhã.


**Como funciona**

Cards superiores (4): Entradas Hoje, Saídas Hoje, Saldo do Dia, Inadimplência Total — sempre do dia atual independente do toggle. Cards inferiores (5): Receita Líquida, Saídas, Novas Entradas, Lucro Líquido, Ticket Médio — respondem ao toggle de período (Hoje/Semana/Mês). Blocos resumo: A Receber e A Pagar lado a lado (Vencidos, A vencer, Vencem hoje). Link 'Ver todos' leva à aba completa. Gráfico Fluxo de Caixa diário (linha dupla verde/vermelha) com badge de saldo positivo/negativo. Gauge meta: semicírculo Receita vs Meta com toggle Mensal/Trimestral/Anual. Quando meta=0, oculta gauge e mostra CTA. Botão 'Personalizar Dashboard' abre modal com drag-and-drop dos cards (preferência salva por usuário).


**Conversa com**

Apenas leitura. Lê de Fluxo (F-23), A Receber (F-16), A Pagar (F-20), DRE (F-26), Metas (F-07). Não escreve.


**Dados / configurações**

Sem entidade nova. Apenas queries agregadas. Tabela UserDashboardConfig para personalização.


**Critérios de aceite**

- Cards superiores fixos no dia atual
- Cards inferiores respondem ao toggle de período
- Ticket Médio calcula corretamente quando há receita > 0 (resolve BUG-05)
- Gauge oculta quando meta=0
- Personalização do Dashboard salva por usuário
- Performance: Dashboard carrega em <2s
- Permissão: todos com acesso ao financeiro veem alguma versão


> 💡 **Nota técnica:** BUG-05 da auditoria: Ticket Médio mostra R$ 0,00 mesmo com receita. Verificar fórmula receita ÷ pacientes únicos.


### `F-28` Reclassificação em massa e correções de bugs visuais

**Prioridade:** 🟠 Alta · 
**Tamanho:** M · 
**Depende de:** `F-26, F-05`


**Descrição**

Tela auxiliar para o ADMIN/GERENTE corrigir lançamentos em massa: muda categoria, muda forma de pagamento, edita descrição. Crítica para o pós-importação Clinicorp (corrigir OTHER → PIX, classificar 'Sem categoria').


**Como funciona**

Tela /financeiro/reclassificacao com filtros poderosos: categoria atual, forma atual, valor (range), descrição (regex), data, paciente. Resultado em tabela com checkbox em cada linha + checkbox 'selecionar todos'. Ações em massa: alterar categoria, alterar forma, alterar conta, editar descrição. Confirmação dupla (mostra quantos serão alterados). Cada alteração gera AuditLog individualmente.


**Conversa com**

Atualiza FinancialEntry, Installment, Expense conforme ação. AuditLog registra cada uma.


**Dados / configurações**

Sem nova entidade. Apenas operações de UPDATE em massa com lock otimista.


**Critérios de aceite**

- Filtros combinados funcionam (categoria + valor + data, etc)
- Seleção em massa com checkbox e 'selecionar todos do filtro'
- Ações em massa funcionam: categoria, forma, conta, descrição
- Confirmação dupla mostra quantos itens serão alterados
- Cada UPDATE gera AuditLog individual
- Permissão: GERENTE/ADMIN apenas


> 💡 **Nota técnica:** Pós-importação Clinicorp: ADMIN usa para corrigir OTHER → PIX (geralmente valor > R$ 200) e classificar 'Sem categoria'.


---


## FASE 9 — Relatórios

*Análises mais profundas além do Dashboard.*


### `F-29` Relatório de Comissões

**Prioridade:** 🟠 Alta · 
**Tamanho:** M · 
**Depende de:** `F-06, F-17`


**Descrição**

Tela de apuração de comissões por profissional. Mostra o que foi recebido, calcula a comissão devida, permite marcar como paga (gera Expense automática).


**Como funciona**

Filtros: profissional, período. Tabela: data recebimento, paciente, procedimento, valor recebido, % aplicado, comissão calculada. Total ao final. Estornos aparecem como linha negativa. Botão 'Marcar como pago' por linha ou em massa: gera Expense em A Pagar com categoria Comissões e fornecedor = nome do profissional. Botão Gerar PDF para assinatura do profissional.


**Conversa com**

Lê CommissionEntry (gerado em F-17) e CommissionRule (F-06). Cria Expense em A Pagar (F-20) ao marcar como paga.


**Dados / configurações**

Lê CommissionEntry. Cria Expense ao marcar pago.


**Critérios de aceite**

- Filtros funcionam (profissional + período)
- Cálculo de comissão correto (sobre RECEBIDO, não orçado)
- Estornos aparecem como linha negativa
- Marcar como paga gera Expense automaticamente
- PDF para assinatura sai limpo
- Permissão: GERENTE/ADMIN/AUDITOR. Profissional vê apenas próprio.


> 💡 **Nota técnica:** Casos CT-COM-01 a CT-COM-05 da Auditoria.


### `F-30` Outros relatórios (Despesas por Categoria, Convênio, Ticket Médio)

**Prioridade:** 🟡 Média · 
**Tamanho:** M · 
**Depende de:** `F-26`


**Descrição**

Três sub-abas com análises complementares para o gestor.


**Como funciona**

DESPESAS POR CATEGORIA: pizza ou barras com % de cada categoria sobre total de despesa do período. Drill-down em categoria mostra lista de despesas. Sub-aba interna: comparativo de 6 meses (linha de tendência). FATURAMENTO POR CONVÊNIO: por operadora (faturado, recebido, glosa, inadimplente, ticket médio). Filtro Apenas convênio / Apenas particular / Todos. Identifica gap entre faturado e recebido. TICKET MÉDIO: geral, por profissional, por especialidade. Fórmula receita ÷ pacientes únicos atendidos. Comparativo entre profissionais (gráfico de barras).


**Conversa com**

Apenas leitura. Lê de FinancialEntry, Expense, Installment, Patient, Dentist.


**Dados / configurações**

Queries agregadas. Pode usar materialized views se performance for problema.


**Critérios de aceite**

- Despesas por Categoria: pizza correta, drill-down funciona
- Comparativo 6 meses mostra tendência
- Faturamento por Convênio identifica gap faturado vs recebido
- Ticket Médio: fórmula correta e comparativo por profissional
- Todos exportam PDF
- Permissão: GERENTE/ADMIN/AUDITOR


> 💡 **Nota técnica:** Convênio = entidade Patient.healthInsurance ou similar (depende do modelo já existente).


---


## FASE 10 — Auditoria + LGPD

*Polimentos finais: aba Auditoria, backup, exportação, anonimização LGPD.*


### `F-31` Aba Auditoria por entidade e tela global de logs

**Prioridade:** 🟡 Média · 
**Tamanho:** M · 
**Depende de:** `F-02`


**Descrição**

Visualização do AuditLog em duas formas: (1) aba 'Histórico de alterações' dentro de cada entidade financeira, (2) tela global /admin/audit-logs para ADMIN/AUDITOR.


**Como funciona**

ABA POR ENTIDADE: dentro de qualquer entidade financeira (Pagamento, Despesa, PT, etc), aba mostra timeline cronológica das alterações: quem, quando, o que mudou (diff visual antes/depois). TELA GLOBAL: filtros por entidade, ação, usuário, período, IP. Tabela paginada. Botão exportar CSV.


**Conversa com**

Apenas leitura do AuditLog (F-02).


**Dados / configurações**

Sem nova entidade. View formatada do AuditLog.


**Critérios de aceite**

- Aba 'Histórico' acessível em qualquer entidade financeira
- Diff visual mostra antes/depois de cada alteração
- Tela global filtra por todos os critérios
- Exportar CSV funciona com período > 1 mês
- Permissão: ADMIN/AUDITOR para tela global; aba por entidade conforme permissão da entidade


> 💡 **Nota técnica:** Tela global pode ter milhões de linhas — paginação obrigatória.


### `F-32` Backup automático diário

**Prioridade:** 🟠 Alta · 
**Tamanho:** M · 
**Depende de:** `F-01`


**Descrição**

Backup automático do banco financeiro, armazenado fora do servidor principal. Crítico para recuperação de desastre.


**Como funciona**

Cron diário às 03:00. Dump do banco (pg_dump ou similar), criptografa, envia para storage externo (S3, Backblaze, etc). Mantém retenção: 30 dias diários, 12 meses mensais (1º dia do mês), 5 anos anuais (1º dia do ano). Tela /admin/backups lista backups disponíveis e permite restauração (com confirmação tripla). Notifica ADMIN se backup falhar.


**Conversa com**

Backend job. Storage externo configurável.


**Dados / configurações**

Tabela BackupLog (id, kind, status, size, location, createdAt, expiresAt).


**Critérios de aceite**

- Cron roda diariamente sem intervenção
- Backup criptografado em storage externo
- Retenção respeita 30/12/5 (diário/mensal/anual)
- Notificação ao ADMIN se falhar
- Tela de listagem e restauração funcional
- Restauração testada em ambiente staging mensalmente


> 💡 **Nota técnica:** Considerar backup encriptado com chave do cliente (LGPD).


### `F-33` Exportação para contador e LGPD (anonimização)

**Prioridade:** 🟡 Média · 
**Tamanho:** M · 
**Depende de:** `F-26, F-01`


**Descrição**

Duas funcionalidades regulatórias: (1) exportação completa para o contador externo (CSV com todos os lançamentos do mês), (2) atendimento à LGPD: paciente solicita exclusão dos dados → sistema anonimiza preservando integridade contábil.


**Como funciona**

EXPORTAÇÃO CONTADOR: tela /financeiro/exportar-contador. Filtro de período. Gera ZIP com CSVs separados (Receitas, Despesas, Comissões, Movimentos do Caixa). Cada linha tem todos os campos (data, valor, categoria, conta, descrição, paciente, profissional). Pode ser configurado e enviado mensalmente por email. LGPD ANONIMIZAÇÃO: paciente solicita exclusão → ADMIN aprova → sistema substitui nome, CPF, email, telefone, endereço por hashes irreversíveis em Patient. Lançamentos financeiros e clínicos PRESERVADOS (apenas referenciam o hash). Histórico fica anonimizado mas integridade contábil mantida.


**Conversa com**

Lê todas as entidades financeiras. Atualiza Patient na anonimização.


**Dados / configurações**

Adiciona campo anonymizedAt em Patient. Tabela LGPDRequest (id, patientId, requestedAt, approvedBy, completedAt).


**Critérios de aceite**

- Exportação contador gera ZIP com CSVs corretos
- Pode ser agendada para envio mensal automático
- Anonimização LGPD substitui dados pessoais por hashes
- Lançamentos financeiros do paciente anonimizado continuam acessíveis (sem nome)
- Solicitação LGPD passa por workflow de aprovação
- Auditoria registra cada anonimização


> 💡 **Nota técnica:** LGPD permite preservar dados para fins fiscais e contábeis (5 anos). Anonimizar ao invés de deletar.
