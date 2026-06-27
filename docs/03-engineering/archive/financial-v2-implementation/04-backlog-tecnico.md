# Backlog de desenvolvimento — Financeiro Klivy/Salus

> Tickets técnicos detalhados: 12 épicos, ~70 tickets, 12 sprints. Versão técnica focada em desenvolvedor (complementa os 33 cards).
> 
> Convertido de: `Backlog_Dev_Financeiro_Klivy.docx`  
> Última atualização: maio de 2026

---

**Módulo Financeiro · Klivy / Salus**

*Tickets de desenvolvimento, arquitetura e ordem de implementação*

12 épicos · ~95 tickets · 12 sprints estimadas

*Documento mestre para o setor de desenvolvimento*

*Versão 1.0 · Maio de 2026*

Sumário

Parte I — Arquitetura e fundamentos

Antes dos tickets propriamente ditos, esta seção estabelece o vocabulário e as regras transversais que valem para todo o módulo financeiro. Todo ticket subsequente assume que o desenvolvedor leu e entendeu esta parte.

1\. Como ler este documento

O documento está estruturado em três partes:

1.  Parte I (esta) — fundamentos arquiteturais e padrões transversais.

2.  Parte II — backlog organizado em 12 épicos. Cada ticket vem em formato de card com ID, título, prioridade, estimativa, dependências, critérios de aceite e detalhamento técnico.

3.  Parte III — roadmap de execução em sprints, caminho crítico e dependências cruzadas.

**Convenções:**

| **Marcação**   | **Significado**                                                                              |
|----------------|----------------------------------------------------------------------------------------------|
| TICK-XXX       | ID único do ticket. Use no commit, na branch e nos comentários do PR.                        |
| CRÍTICA        | Bloqueia operação real da clínica. Não tem workaround.                                       |
| ALTA           | Importante mas tem workaround manual. Resolver em 1 sprint.                                  |
| MÉDIA          | Polimento ou melhoria. Resolver em 2-3 sprints.                                              |
| BAIXA          | Nice-to-have. Resolver quando der.                                                           |
| P / M / G / GG | Estimativa T-shirt: P ≈ 1-2 dias / M ≈ 3-5 dias / G ≈ 1-2 sprints / GG ≈ 2+ sprints          |
| CT-XX-NN       | Referência aos casos de teste do documento de Auditoria Financeira (entregue separadamente). |

2\. Mapa de comunicação entre módulos

Esta é a regra mais importante para o time. Cada operação do usuário dispara efeitos em múltiplos módulos. A tabela abaixo mostra quem dispara o quê.

2.1 Origens de movimento financeiro

Todo dinheiro que entra ou sai do sistema vem de uma destas quatro origens. Se um lançamento aparece sem origem identificada, é bug de origem fantasma.

| **Origem**                        | **O que dispara**                                                                                                                       |
|-----------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------|
| 1\. Plano de tratamento (clínica) | Profissional cria PT no prontuário → recepção aprova → gera N parcelas em A Receber. Foi a forma que a maioria das receitas vai entrar. |
| 2\. Entrada manual (recepção)     | Botão Nova Entrada em Fluxo de Caixa. Lança valor avulso (venda de produto, taxa de cancelamento, juros recebidos).                     |
| 3\. Despesa manual                | Botão Nova Despesa em A Pagar. Lança valor avulso (compra única, fornecedor pontual).                                                   |
| 4\. Despesa recorrente            | Configurada uma vez em Configurações → cron mensal gera o lançamento no dia certo (aluguel, sistema, internet).                         |

2.2 Cadeia de efeitos por operação

Quando o usuário executa uma operação, o sistema PRECISA atualizar todos os destinos abaixo de forma atômica. Se um falhar, reverter todos.

| **Operação**                 | **Cadeia de efeitos (ordem)**                                                                                                                                                                                                                                                                                                                                             |
|------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Aprovar orçamento            | 1\) Status do orçamento → Aprovado 2) Gerar N parcelas em A Receber 3) Atualizar card 'Total Aprovado' do paciente 4) Atualizar 'Novas Entradas' no Dashboard (regime competência) 5) Disparar provisão de comissão (se regra existe)                                                                                                                                     |
| Receber pagamento de parcela | 1\) Parcela → Recebido 2) Saldo da conta destino +valor 3) Lançar entrada no Fluxo de Caixa do dia efetivo 4) Atualizar comissão (de provisão para devida) 5) Atualizar status do paciente (adimplente/inadimplente) 6) Atualizar card 'Pago/Recebido' do paciente 7) Atualizar 'Receita Bruta' do DRE (regime competência) e 'Total de Entradas' do Fluxo (regime caixa) |
| Estornar parcela recebida    | 1\) Parcela → Estornado 2) Saldo da conta destino −valor 3) Lançar saída de estorno no Fluxo de Caixa do dia do estorno (NÃO retroativo) 4) Reverter comissão calculada 5) Atualizar status do paciente 6) Se era a única parcela paga, orçamento volta para Pendente                                                                                                     |
| Pagar despesa                | 1\) Despesa → Pago 2) Saldo da conta origem −valor 3) Lançar saída no Fluxo de Caixa 4) Atualizar DRE (categoria correspondente)                                                                                                                                                                                                                                          |
| Sangria do caixa             | 1\) Saldo do caixa físico −valor 2) Saldo da conta destino +valor 3) NÃO mexer no DRE (transferência interna é neutra) 4) Registrar movimento em Caixa → Histórico                                                                                                                                                                                                        |
| Fechar caixa do dia          | 1\) Calcular saldo esperado (abertura + entradas − saídas − sangrias + suprimentos) 2) Comparar com valor digitado pelo operador 3) Se diferente, criar lançamento 'Quebra de Caixa' (categoria Outras Despesas se for falta, Outras Receitas se for sobra) 4) Caixa → Fechado 5) Bloquear novos lançamentos retroativos sem reabertura                                   |

2.3 Quem lê / quem escreve em cada módulo

Esta tabela ajuda a entender o impacto de mudanças. Se o time mexer no cálculo de DRE, por exemplo, qualquer ajuste em Receita ou Despesa pode afetá-lo.

| **Módulo / Tela**      | **Lê de**                                                   | **Escreve em**                                                      |
|------------------------|-------------------------------------------------------------|---------------------------------------------------------------------|
| Dashboard              | Fluxo, A Receber, A Pagar, DRE, Metas                       | Nada (somente leitura)                                              |
| Fluxo de Caixa         | Lançamentos confirmados (entradas/saídas), Contas Bancárias | Lançamentos manuais avulsos                                         |
| A Receber              | Parcelas (PaymentItem), Pacientes, Orçamentos               | Status de parcela, Lançamento de recebimento, Lançamento de estorno |
| A Pagar                | Despesas, Categorias, Contas, Fornecedores                  | Status de despesa, Pagamento, Estorno                               |
| DRE                    | Lançamentos por competência, Categorias                     | Nada (somente leitura, agrupamento dinâmico)                        |
| Caixa                  | Operador logado, Lançamentos do dia em dinheiro             | Abertura/fechamento, Sangria, Suprimento, Quebra                    |
| Relatórios             | Comissões, Despesas, Convênios, Atendimentos, Profissionais | Marcação de comissão paga                                           |
| Configurações          | Categorias, Contas, Regras, Recorrentes, Metas              | CRUD de cada uma das 5 entidades                                    |
| Financeiro do paciente | Orçamentos, Parcelas, Pagamentos, Crédito do paciente       | Aprovação, Renegociação, Crédito, Estorno                           |

3\. Modelo de dados core

Resumo das entidades e seus principais relacionamentos. Detalhes de cada campo ficam nos tickets correspondentes.

| **Entidade**     | **Função**                                              | **Relacionamentos chave**                                                        |
|------------------|---------------------------------------------------------|----------------------------------------------------------------------------------|
| Patient          | Cadastro de paciente                                    | → Anamnesis, Appointments, TreatmentOperations, Budgets, Payments, PatientCredit |
| Dentist (User)   | Profissional / operador                                 | → Appointments, Budgets (criador), CommissionRules                               |
| Category         | Categoria financeira (Receita / Despesa)                | → usada em FinancialEntries                                                      |
| BankAccount      | Conta bancária ou caixa físico                          | → Lançamentos, Saldo cumulativo                                                  |
| CommissionRule   | Regra de comissão de profissional                       | → Dentist, gera CommissionEntry                                                  |
| RecurringExpense | Modelo de despesa recorrente                            | → gera Expense periodicamente                                                    |
| RevenueGoal      | Meta de receita (mensal/trimestral/anual)               | → usada por Dashboard                                                            |
| Budget           | Orçamento / plano de tratamento aprovado                | → Patient, Dentist, BudgetItems, Installments                                    |
| Installment      | Parcela a receber (gerada por Budget)                   | → Budget, PaymentReceipt (quando paga)                                           |
| PaymentReceipt   | Recibo de pagamento de N parcelas                       | → Installments (1..N), BankAccount, FinancialEntry                               |
| Expense          | Despesa (a pagar / paga)                                | → Category, BankAccount, RecurringExpense (se origem)                            |
| FinancialEntry   | Lançamento de fluxo de caixa (entrada/saída efetiva)    | → BankAccount, Category, origem (Installment ou Expense)                         |
| CommissionEntry  | Comissão devida ao profissional                         | → Dentist, Installment (origem do recebido)                                      |
| CashRegister     | Sessão de caixa (abertura → fechamento)                 | → User (operador), CashMovements                                                 |
| CashMovement     | Movimento dentro do caixa (sangria, suprimento, quebra) | → CashRegister, BankAccount (destino da sangria)                                 |
| AuditLog         | Log de auditoria de toda ação                           | → User, entidade afetada (genérico)                                              |
| PatientCredit    | Saldo a favor do paciente (estornos, pré-pagamento)     | → Patient                                                                        |

> **Por que separar Installment e PaymentReceipt**
>
> Um pagamento PIX único pode quitar 3 parcelas de uma vez. Modelar PaymentReceipt como entidade própria (com 1..N parcelas dentro) permite registrar isso sem duplicar a entrada de R$ 300. O FinancialEntry é gerado uma única vez, vinculado ao PaymentReceipt — e o PaymentReceipt distribui internamente para as 3 parcelas.

4\. Sistema de permissões

Cinco perfis cobrem 100% dos casos da clínica. Dev pode implementar como RBAC simples.

| **Perfil** | **Quem**                   | **O que pode fazer**                                                                                                                                                 |
|------------|----------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| RECEPCAO   | Recepcionistas             | Lançar entrada/saída avulsa, baixar parcela, abrir/fechar caixa, sangria. NÃO pode: estornar, excluir despesa paga, alterar regra de comissão, ver DRE.              |
| DENTIST    | Profissionais              | Ver próprio relatório de comissão, criar e aprovar plano de tratamento. NÃO pode: ver dados financeiros de outros profissionais, alterar configurações.              |
| GERENTE    | Coordenação                | Tudo de RECEPCAO + estornar, excluir despesa, ver DRE/Relatórios, reabrir caixa, configurar categorias e contas. NÃO pode: alterar regras de comissão, gerar backup. |
| ADMIN      | Dono da clínica / TI       | Tudo. Único que altera regras de comissão, faz importações, gera backup, acessa logs.                                                                                |
| AUDITOR    | Contador (somente leitura) | Lê tudo: DRE, Fluxo, A Receber, A Pagar, Relatórios. NÃO pode escrever nada.                                                                                         |

> **Permissão por operação sensível**
>
> Operações críticas (estorno, exclusão, reabertura de caixa, alteração de regra de comissão) DEVEM gerar log de auditoria com User, IP, timestamp, antes/depois. Exigir confirmação dupla (modal com texto a digitar) para exclusões irreversíveis.

5\. Padrões transversais

Cinco padrões valem para todos os módulos. Não repetir nos tickets — assumir como base.

5.1 Idempotência

- Toda ação de escrita aceita um Idempotency-Key (UUID v4) no header.

- Servidor armazena (key, response) por 24h. Mesma key → devolve a mesma resposta sem reprocessar.

- Frontend gera a key no momento que o usuário clica no botão. Duplo-clique → mesma key → sem efeito duplicado. Resolve BUG-08 da auditoria.

5.2 Soft delete + audit log

- Nenhuma entidade financeira é deletada fisicamente. Sempre soft delete com deletedAt + deletedBy.

- Toda mudança de estado escreve em AuditLog: { entityType, entityId, action, userId, before, after, ip, timestamp }.

- Listagens default filtram deletedAt IS NULL. Existe view 'Histórico/Lixeira' para ADMIN e AUDITOR.

5.3 Atomicidade dos efeitos múltiplos

- Operações que afetam vários módulos rodam em transação de banco. Falha em qualquer passo → rollback total.

- Exemplo: 'Receber pagamento' afeta 7 destinos (vide tabela 2.2). Se atualização de comissão falhar, parcela volta para Pendente, saldo da conta volta, lançamento do fluxo é desfeito.

- Para operações longas (importação em massa), usar saga pattern com pontos de checkpoint.

5.4 Regime de competência vs. caixa

- DRE usa competência: receita aparece no mês em que o orçamento foi aprovado, despesa no mês em que foi incorrida.

- Fluxo de Caixa usa caixa: receita aparece no mês em que o dinheiro entrou na conta, despesa no mês em que saiu.

- Os dois regimes convivem. Cada FinancialEntry tem competenceDate e cashDate. Listagens filtram por um ou pelo outro conforme a tela.

5.5 Numerais e arredondamento

- Todos os valores monetários armazenados em centavos (BIGINT) — nunca float. Resolve perda por arredondamento.

- Quando o sistema dividir um valor em N parcelas, distribuir o resto na ÚLTIMA parcela. Ex.: R\$ 920 ÷ 3 = R\$ 306,66 + R\$ 306,66 + R\$ 306,68.

- Frontend formata com Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).

Parte II — Backlog de tickets por épico

Os tickets estão agrupados em 12 épicos (A a L). A ordem dos épicos é também a ordem recomendada de execução. Dentro de cada épico, os tickets seguem ordem de dependência interna.

<table>

<tbody>
<tr class="odd">
<td>**ÉPICO A**

**Fundação técnica**

*Modelo de dados core, sistema de auditoria e permissões. Pré-requisito de todos os outros épicos. Sem isso, qualquer feature financeira nasce frágil.*
</td>
</tr>
</tbody>
</table>

|                                                    |               |
|----------------------------------------------------|---------------|
| **TICK-A01** · **Modelo de dados financeiro core** | **CRITICA** G |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Criar todas as tabelas e relações listadas na seção 3 da Parte I. Inclui migrations, índices, constraints. Valores monetários em BIGINT (centavos). Soft delete em todas (deletedAt, deletedBy). Timestamps de auditoria (createdAt, createdBy, updatedAt, updatedBy).</td>
</tr>
<tr class="even">
<td>**Conversa com**</td>
<td>Todos os módulos</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Migrations rodam sem erro em base zerada e em base já com dados de teste.

• Índices criados em: (PatientId), (DentistId), (BankAccountId, dueDate), (status, dueDate) — apoiam as queries de listagem com filtro.

• Foreign keys com ON DELETE RESTRICT (não deletar paciente que tem parcela vinculada).

• Seed inicial: 1 conta bancária 'Caixa físico', 1 categoria 'Sem categoria' (default), 1 perfil ADMIN.
</td>
</tr>
<tr class="even">
<td>**Modelo de dados**</td>
<td>• Patient, Dentist, Category, BankAccount, CommissionRule, RecurringExpense, RevenueGoal

• Budget, Installment, PaymentReceipt, Expense, FinancialEntry, CommissionEntry

• CashRegister, CashMovement, AuditLog, PatientCredit
</td>
</tr>
</tbody>
</table>

|                                                    |               |
|----------------------------------------------------|---------------|
| **TICK-A02** · **Sistema de auditoria (AuditLog)** | **CRITICA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Toda escrita em entidades financeiras grava em AuditLog. Implementar via interceptor/middleware do ORM para não exigir chamada explícita em cada serviço.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>Todos os módulos</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Cada CREATE/UPDATE/DELETE em entidade financeira gera 1 linha em AuditLog automaticamente.

• Campos: id, entityType, entityId, action (CREATE|UPDATE|DELETE|RESTORE), userId, ip, userAgent, before (JSONB), after (JSONB), createdAt.

• Tela 'Histórico de alterações' acessível a partir de qualquer entidade — abre lista cronológica.

• ADMIN e AUDITOR conseguem exportar logs em CSV por período.
</td>
</tr>
<tr class="odd">
<td>**Permissões**</td>
<td>Leitura: ADMIN, AUDITOR, GERENTE</td>
</tr>
<tr class="even">
<td>**Notas**</td>
<td>Considerar particionamento por mês depois de 12 meses (volume cresce rápido).</td>
</tr>
</tbody>
</table>

|                                                 |               |
|-------------------------------------------------|---------------|
| **TICK-A03** · **Sistema de permissões (RBAC)** | **CRITICA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Implementar os 5 perfis da seção 4 da Parte I: RECEPCAO, DENTIST, GERENTE, ADMIN, AUDITOR. Verificação no backend (decorator ou middleware) — frontend só esconde botões.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>Todos os endpoints</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Decorator @RequireRole(['ADMIN', 'GERENTE']) bloqueia 403 antes de executar.

• Cada usuário pode ter mais de 1 perfil simultaneamente (ex.: dentista que também é admin).

• Tela de gestão de usuários permite ADMIN atribuir/remover perfis.

• Tentativa de ação sem permissão → log em AuditLog com action='DENIED'.
</td>
</tr>
</tbody>
</table>

|                                                         |            |
|---------------------------------------------------------|------------|
| **TICK-A04** · **Idempotência em endpoints de escrita** | **ALTA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Middleware que aceita header Idempotency-Key (UUID v4). Armazena (key, response) em Redis por 24h. Mesma key → resposta cacheada sem reprocessar. Resolve BUG-08 da auditoria (duplo-clique e duplicidade na importação).</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>Frontend (gera a key) · Importações · Botões de ação</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Frontend gera key no momento do clique e envia em todas as ações de escrita.

• Duplo clique no botão 'Receber pagamento' → 1 só lançamento no servidor.

• TTL configurável (default 24h).
</td>
</tr>
</tbody>
</table>

<table>

<tbody>
<tr class="odd">
<td>**ÉPICO B**

**Configurações financeiras**

*Cinco abas em Configurações → Financeiro. Pré-requisito para qualquer importação ou lançamento manter o DRE saudável. Resolve BUG-04 (DRE em 'Sem categoria').*
</td>
</tr>
</tbody>
</table>

|                                                   |            |
|---------------------------------------------------|------------|
| **TICK-B01** · **CRUD de Categorias financeiras** | **ALTA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Aba Configurações → Categorias. Cadastrar receitas, despesas fixas, custos variáveis e outras despesas. Categorias têm tipo (RECEITA | DESPESA_FIXA | CUSTO_VARIAVEL | OUTRA_DESPESA) que determina onde aparecem no DRE.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01 · TICK-A03</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>DRE · A Pagar (seleção) · Fluxo de Caixa (seleção) · Relatórios → Despesas por Categoria</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• CRUD completo: criar, listar, editar nome, ativar/desativar.

• Não permitir excluir categoria com lançamentos vinculados — oferecer migrar lançamentos para outra categoria primeiro.

• Não permitir 2 categorias com nome idêntico do mesmo tipo.

• Categoria 'Sem categoria' (default seed) não pode ser excluída nem renomeada.

• Onboarding inicial força criar pelo menos 1 categoria de cada tipo (wizard).
</td>
</tr>
<tr class="odd">
<td>**Modelo de dados**</td>
<td>• Category (id, name, type, active, createdAt, ...)</td>
</tr>
<tr class="even">
<td>**Permissões**</td>
<td>Leitura: todos. Escrita: GERENTE, ADMIN</td>
</tr>
</tbody>
</table>

|                                             |            |
|---------------------------------------------|------------|
| **TICK-B02** · **CRUD de Contas Bancárias** | **ALTA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Aba Configurações → Contas Bancárias. Cadastrar conta corrente PJ, caixa físico, conta da maquininha. Cada conta tem saldo inicial e saldo atual (calculado). Suporta transferência interna entre contas (movimento neutro no DRE).</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01 · TICK-A03</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>Fluxo de Caixa (saldo) · A Receber (destino) · A Pagar (origem) · Caixa (caixa físico é uma BankAccount com type=CASH)</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• CRUD completo. Tipos: CHECKING (corrente), SAVINGS (poupança), CASH (físico), CARD_RECEIVABLE (a receber de maquininha).

• Saldo inicial editável só na criação. Saldo atual = saldo inicial + Σ entradas − Σ saídas (calculado, nunca armazenado).

• Tela de transferência interna: origem, destino, valor, data. Gera 2 FinancialEntries (saída na origem, entrada no destino) MARCADAS como transferência (não somam no DRE).

• Não permite excluir conta com saldo ≠ 0. Sugere transferir saldo antes.
</td>
</tr>
<tr class="odd">
<td>**Notas**</td>
<td>CT-CC-01 a CT-CC-05 da auditoria.</td>
</tr>
</tbody>
</table>

|                                               |            |
|-----------------------------------------------|------------|
| **TICK-B03** · **CRUD de Regras de Comissão** | **ALTA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Aba Configurações → Regras de Comissão. Cadastrar % de comissão por profissional. Suportar variantes: % fixo geral, % por procedimento, % por especialidade, base bruta vs. líquida (descontando MDR e laboratório).</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01 · TICK-A03 · Importação Dentist (TICK-C01)</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>A Receber (provisão) · Relatórios → Comissões</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Para cada Dentist ativo, cadastrar 1 ou mais regras com vigência (validFrom, validTo).

• Regra mais recente vigente na data do recebimento é a aplicada.

• Mudança de regra NÃO altera comissões já calculadas. Histórico preservado.

• Comissão calculada sobre RECEBIDO (não sobre orçado). CT-COM-05.

• Opção 'Descontar MDR antes do cálculo' — reduz base de cálculo pela taxa de cartão antes de aplicar %.
</td>
</tr>
<tr class="odd">
<td>**Modelo de dados**</td>
<td>• CommissionRule (id, dentistId, kind, percent, validFrom, validTo, deductMDR, ...)</td>
</tr>
</tbody>
</table>

|                                                 |             |
|-------------------------------------------------|-------------|
| **TICK-B04** · **CRUD de Despesas Recorrentes** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Aba Configurações → Despesas Recorrentes. Cadastrar despesas que se repetem (aluguel, sistema, internet) com dia de vencimento e valor. Cron diário gera a Expense correspondente em A Pagar conforme calendário.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01 · TICK-B01 · TICK-B02</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>A Pagar</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Cadastro: nome, categoria, conta padrão, valor (ou 'variável'), dia do mês, recorrência (mensal/bimestral/trimestral/anual), vigência (start, end).

• Cron roda diariamente às 00:01 e gera as Expenses para próximos 35 dias (sempre 1 mês adiantado para o usuário ver no A Pagar).

• Cron é idempotente: se já existe Expense para aquele recorrente naquela competência, não cria de novo.

• Editar valor da recorrente afeta APENAS competências futuras. Anteriores preservadas. CT-RC-03.

• Inativar recorrente não exclui Expenses já geradas — só não gera novas. CT-RC-04.
</td>
</tr>
</tbody>
</table>

|                                             |             |
|---------------------------------------------|-------------|
| **TICK-B05** · **CRUD de Metas de Receita** | **BAIXA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Aba Configurações → Metas. Cadastrar meta mensal, trimestral e anual. Dashboard usa para o gauge 'Receita vs Meta'. Resolve parte do BUG-11.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>Dashboard</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Cadastro de 3 metas independentes (mensal, trimestral, anual).

• Permitir editar a meta retroativamente (caso o usuário ajuste meio do mês). Recalcula gauge imediatamente.

• Quando meta = 0, frontend (TICK-J05) oculta o gauge e mostra CTA 'Cadastre uma meta'.
</td>
</tr>
</tbody>
</table>

|                                                 |             |
|-------------------------------------------------|-------------|
| **TICK-B06** · **Wizard de onboarding inicial** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Quando o ADMIN entra pela primeira vez no Financeiro, abre wizard que força configurar o mínimo viável antes de liberar o módulo. Resolve BUG-04 da auditoria (categoria default 'Sem categoria').</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-B01 · TICK-B02 · TICK-B03</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>Configurações</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Passo 1: criar pelo menos 1 categoria de cada tipo (Receita, Despesa Fixa, Custo Variável, Outra Despesa).

• Passo 2: criar pelo menos 1 conta bancária + caixa físico.

• Passo 3: cadastrar regra de comissão para cada profissional ativo (skip se a clínica não usa comissão).

• Passo 4: cadastrar pelo menos 1 despesa recorrente (skip permitido).

• Passo 5: cadastrar meta de receita (skip permitido).

• Pode ser pausado e retomado. Estado salvo em UserPreferences.
</td>
</tr>
</tbody>
</table>

<table>

<tbody>
<tr class="odd">
<td>**ÉPICO C**

**Importação Clinicorp → Klivy**

*Onze importadores em ordem específica de dependência. Cada um valida, processa e registra. Roda em background com painel de monitoramento.*
</td>
</tr>
</tbody>
</table>

> **Padrão para todos os importadores**
>
> (1) Aceitar arquivo XLSX. (2) Pre-validar colunas obrigatórias. (3) Rodar em background com job assíncrono. (4) Retornar relatório: total de linhas, importadas, ignoradas (com motivo), com erro (com linha e mensagem). (5) Ser idempotente via ImportedId/CheckoutUuid (TICK-A04). (6) Permitir desfazer (TICK-C12).

|                                       |               |
|---------------------------------------|---------------|
| **TICK-C01** · **Importador Dentist** | **CRITICA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Importa o arquivo Dentist.xlsx (9 profissionais, 8 ativos). Primeiro passo da migração — sem isso, todos os outros importam órfãos. Ver Guia de Importação seção 'Etapa 1'.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>Configurações → Comissão (próximo passo)</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Mapear: Name, CRO, Email, OtherDocumentId (CPF), MobilePhone, BirthDate, Sex, Active, Deleted, id (Clinicorp) → guardar como externalId.

• Marcar Type=DENTIST como perfil DENTIST do RBAC.

• Deleted=X → soft delete no Klivy.

• Validação: 8 ativos importados (Daniele, Aline, Gustavo, Guilherme, Maria Luisa, Giovana, Ironete, Cláudia).
</td>
</tr>
</tbody>
</table>

|                                                  |            |
|--------------------------------------------------|------------|
| **TICK-C02** · **Importador AnamnesisQuestions** | **ALTA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Importa templates de anamnese (44 perguntas em 3 templates). Tem que vir antes de Patient porque PatientAnamnesis referencia TemplateId.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Cada TemplateId vira um AnamnesisTemplate no Klivy.

• Cada linha vira AnamnesisQuestion vinculada ao template.

• Preservar Seq (ordem das perguntas).

• Mapear QuestionType (YES_NO, DESC, OPTIONS) e Options (JSON).
</td>
</tr>
</tbody>
</table>

|                                       |               |
|---------------------------------------|---------------|
| **TICK-C03** · **Importador Patient** | **CRITICA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Importa 2.559 pacientes. Liga a tudo via PatientId. Deletados=X importam mas marcados como inativos (preserva histórico).</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>Anamnese, Appointments, Budgets, Payments</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Mapear todos os 42 campos relevantes (nome, CPF, telefone, endereço, responsável, etc.).

• Detectar duplicatas por CPF antes de importar — gerar relatório de revisão para o ADMIN.

• Active=X importa como ativo. Deleted=X soft-deleted no Klivy.

• Validação: 2.407 ativos visíveis em Pacientes após importação.
</td>
</tr>
</tbody>
</table>

|                                                            |             |
|------------------------------------------------------------|-------------|
| **TICK-C04** · **Importador Anamnesis + PatientAnamnesis** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Importa em duas sub-etapas. (4.1) Anamnesis: 30 cabeçalhos, um por paciente. (4.2) PatientAnamnesis: 600 respostas. Inverter ordem gera respostas órfãs.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-C02 · TICK-C03</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Sub-etapa 4.1: cria 30 PatientAnamnesisHeader vinculados a Patient via Patient_PersonId.

• Sub-etapa 4.2: cria 600 PatientAnamnesisAnswer vinculadas ao header (via AnamnesisId).

• Validação: 3 pacientes ao acaso têm anamnese completa com perguntas em ordem e respostas certas.
</td>
</tr>
</tbody>
</table>

|                                           |            |
|-------------------------------------------|------------|
| **TICK-C05** · **Importador Appointment** | **ALTA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Importa 8.745 agendamentos (jul/2023 a jan/2027). Inclui 346 cancelados — devem aparecer com status 'Cancelado', não sumir.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-C01 · TICK-C03</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Mapear date, fromTime, toTime, PatientId, DentistId, Status, Notes, Procedures.

• Status preservado: CONFIRMED, MISSED, CHECKOUT, ARRIVED, IN_SESSION, LATE, CANCELED.

• Categoria (CategoryDescription='Odonto') vira tag ou campo livre.

• Validação: agenda mostra eventos no mês de jul/2023 ao filtrar.
</td>
</tr>
</tbody>
</table>

|                                                  |             |
|--------------------------------------------------|-------------|
| **TICK-C06** · **Importador TreatmentOperation** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Importa 9.638 procedimentos clínicos (9.635 executados). Histórico de evolução do paciente. ATENÇÃO: 9.637 estão com DentistId vazio e Type nulo no arquivo — confirmar com Clinicorp se há outra exportação antes de prosseguir.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-C03</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Mapear Amount, ProcedureCondition, Type, Tooth, Surface, ExecutedDate, PatientId, DentistId.

• Deleted=X (21 registros) não importa.

• Procedimentos sem DentistId importam vinculados apenas ao Patient — gerar relatório dos sem profissional para revisão.

• Validação: prontuário do paciente mostra histórico em Evolução.
</td>
</tr>
<tr class="even">
<td>**Notas**</td>
<td>Bloqueador: validar com Clinicorp se há campos preenchidos em outra exportação.</td>
</tr>
</tbody>
</table>

|                                       |               |
|---------------------------------------|---------------|
| **TICK-C07** · **Importador Budgets** | **CRITICA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Importa orçamentos. 34 orçamentos / 58 procedimentos / R$ 24.650,83 / 16 pacientes. Filtrar BudgetApproved=X e Executed=null (em andamento). Já executados viram histórico.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01 · TICK-C01 · TICK-C03</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>A Receber</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Cada BudgetId único vira 1 Budget. Linhas múltiplas (procedimentos) viram BudgetItems.

• Mapear BudgetAmount, BudgetDiscount, BudgetPaymentForm, BudgetPaymentInstallments, BudgetPaymentType.

• Status: BudgetApproved=X → APPROVED. NotApproved=X → REJECTED. Executed=X → COMPLETED.

• Aprovar não gera parcelas aqui (parcelas vêm da importação de PaymentItem). Apenas registra orçamento.

• Validação: A Receber mostra ≤ 34 orçamentos abertos. Pacientes com orçamento conhecido (Rafael Strelow, etc.) batem.
</td>
</tr>
</tbody>
</table>

|                                             |               |
|---------------------------------------------|---------------|
| **TICK-C08** · **Importador PaymentHeader** | **CRITICA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Importa 1.805 cabeçalhos de cobrança. Filtrar Deleted=null (sobram 1.766). Marcar IsPartialPayment=X (34 cabeçalhos) para revisão manual no Klivy — são prováveis casos do tipo 'Manuele' (pagamento parcial em dinheiro/PIX).</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-C03 · TICK-C07</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>A Receber</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• 1.766 PaymentReceipts criados (1 por linha não deletada).

• Os 34 marcados como parciais aparecem em fila de revisão exclusiva — gerente confere um a um antes do go-live.

• Mapear PatientId, BookEntryIdList (referência), PaymentDate, PaymentForm_CharacteristicId, ReceiptType.
</td>
</tr>
</tbody>
</table>

|                                           |               |
|-------------------------------------------|---------------|
| **TICK-C09** · **Importador PaymentItem** | **CRITICA** G |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>É O importador. 2.283 parcelas, R$ 537.794,90 lançado, R$ 445.025,75 recebido. Mapear coluna Type para forma de pagamento Klivy. A Clinicorp não distingue Dinheiro de PIX — todos viram 'Dinheiro' por padrão e gerente reclassifica.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01 · TICK-C08</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>A Receber · Fluxo de Caixa</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Filtrar Canceled=null (sobram 2.216).

• Mapeamento Type → forma: OTHER → DINHEIRO (revisar PIX). CREDIT_CARD_EXTERNAL → CREDITO. DEBIT_CARD_EXTERNAL → DEBITO. BOLETO_INTERNAL → BOLETO. CREDIT_CARD_INTERNAL → CREDITO.

• Status pela combinação: PaymentConfirmed=X + PaymentReceived=X → RECEIVED. PaymentConfirmed=X sem Received → PENDING. Canceled=X → CANCELED.

• Para cada parcela RECEIVED, gerar FinancialEntry no Fluxo de Caixa com cashDate=ReceivedDate.

• Validação: Fluxo de Caixa sem filtro = R$ 445.025,75 (± R$ 50). A Receber Total = R$ 92.769,15.
</td>
</tr>
<tr class="odd">
<td>**Notas**</td>
<td>Tela 'Reclassificação em massa de OTHER' deve permitir filtrar por valor (acima de R$ 200 → PIX) e marcar em lote.</td>
</tr>
</tbody>
</table>

|                                                          |            |
|----------------------------------------------------------|------------|
| **TICK-C10** · **Painel de monitoramento de importação** | **ALTA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Tela onde ADMIN acompanha importações em andamento e histórico. Cada job mostra progresso, erros e relatório final.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-C01</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Lista de jobs: nome do importador, arquivo, iniciado em, status (RUNNING, DONE, FAILED), progresso %.

• Drill-down em job concluído mostra: total processado, importado, ignorado (com motivo), erro (com linha).

• Botão 'Baixar relatório CSV' para exportar resultado completo.

• Notificação por e-mail ao ADMIN quando job conclui (sucesso ou falha).
</td>
</tr>
</tbody>
</table>

|                                                          |            |
|----------------------------------------------------------|------------|
| **TICK-C11** · **Detector de duplicatas pré-importação** | **ALTA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Antes de cada importador rodar de verdade, oferecer dry-run: lê o arquivo, simula a importação, devolve relatório de quais linhas já existem (matched) e quais são novas. Não escreve nada no banco. Resolve BUG-08.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A04 · TICK-C01</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Endpoint POST /api/import/{type}/dry-run aceita arquivo, devolve JSON com: { total, novos, existentes, conflitos }.

• Conflito: linha do arquivo tem mesmo externalId que registro existente, mas com campo divergente (nome diferente, etc.).

• Frontend mostra preview antes do botão 'Confirmar importação'.
</td>
</tr>
</tbody>
</table>

|                                               |             |
|-----------------------------------------------|-------------|
| **TICK-C12** · **Desfazer última importação** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Permitir reverter um job de importação com soft delete em massa de tudo que ele criou. Salva-vidas para casos onde a importação importou dados errados (mapeamento equivocado, arquivo errado, etc.).</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A02 · TICK-C10</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Cada FinancialEntry / Patient / Budget criado por importação carrega importJobId.

• Botão 'Desfazer' no painel de monitoramento marca todas as entidades daquele jobId como deletedAt = now.

• Operação irreversível confirmada com modal exigindo digitar 'DESFAZER'.

• Restauração possível via endpoint /api/admin/import/{jobId}/restore (apenas ADMIN).
</td>
</tr>
<tr class="even">
<td>**Permissões**</td>
<td>Apenas ADMIN</td>
</tr>
</tbody>
</table>

<table>

<tbody>
<tr class="odd">
<td>**ÉPICO D**

**Núcleo financeiro do paciente**

*Plano de tratamento → Orçamento → Aprovação → Geração de parcelas. É a forma como 95% das receitas entram no sistema. Resolve BUG-02 (impossibilidade de editar orçamento aprovado).*
</td>
</tr>
</tbody>
</table>

|                                                    |               |
|----------------------------------------------------|---------------|
| **TICK-D01** · **Plano de tratamento → Orçamento** | **CRITICA** G |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Dentista cria plano no prontuário com procedimentos, valores e desconto. Vira Budget no estado DRAFT. Não vira financeiro até ser aprovado.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01 · TICK-C03</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>Prontuário · A Receber (após aprovação)</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Tela 'Novo Orçamento' dentro do prontuário do paciente.

• Adicionar 1..N BudgetItems (procedimento, dente, valor unitário, valor final).

• Campo desconto global (valor R$ ou %).

• Forma de pagamento padrão (DINHEIRO / PIX / DEBITO / CREDITO / BOLETO).

• Número de parcelas (1..12).

• Status inicial: DRAFT. Pode ser editado livremente.
</td>
</tr>
<tr class="odd">
<td>**Modelo de dados**</td>
<td>• Budget, BudgetItem</td>
</tr>
</tbody>
</table>

|                                                           |               |
|-----------------------------------------------------------|---------------|
| **TICK-D02** · **Aprovação de orçamento (gera parcelas)** | **CRITICA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Ao aprovar Budget DRAFT → APPROVED, sistema gera N Installments com vencimentos automáticos (parcela 1 hoje, 2 +30 dias, 3 +60 dias). Distribui valor exato entre parcelas (resto na última, vide padrão 5.5).</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-D01 · TICK-A04</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>A Receber (parcelas aparecem) · Comissão (provisão) · Dashboard (Novas Entradas competência)</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Soma das parcelas = valor do Budget com desconto aplicado. SEMPRE.

• Tolerância 0 — usar centavos e distribuir resto na última parcela.

• Status do Budget muda para APPROVED. approvedBy, approvedAt registrados.

• Cada Installment criada já com status PENDING e dueDate calculado.

• Disparar criação de CommissionEntry com status PROVISIONED para cada parcela.

• Operação atômica em transação. Falha → tudo desfeito.
</td>
</tr>
</tbody>
</table>

|                                                          |               |
|----------------------------------------------------------|---------------|
| **TICK-D03** · **Edição de orçamento aprovado (BUG-02)** | **CRITICA** G |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>RESOLVE BUG-02 da auditoria. Recepção precisa editar orçamento aprovado. Regras: parcelas ainda PENDING podem ser alteradas (forma, valor, vencimento). Parcelas RECEIVED são imutáveis — para alterar exige estorno antes.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-D02 · TICK-E07</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>A Receber · Prontuário</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Botão Editar disponível em Budget APPROVED.

• Modal mostra cada Installment com indicador visual: cadeado se RECEIVED, editável se PENDING.

• Ao salvar: parcelas PENDING são atualizadas; saldo deve continuar batendo com Budget.amount − Σ recebido.

• Permitir adicionar parcela nova (caso paciente queira esticar pagamento).

• Permitir remover parcela PENDING (recalcular distribuição entre as restantes).

• Log em AuditLog mostra antes/depois de cada parcela editada.
</td>
</tr>
<tr class="odd">
<td>**Notas**</td>
<td>CT-AR-08 e CT-PAC-09 da auditoria.</td>
</tr>
</tbody>
</table>

|                                              |            |
|----------------------------------------------|------------|
| **TICK-D04** · **Cancelamento de orçamento** | **ALTA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Permitir cancelar orçamento aprovado quando paciente desistiu. Cancela todas as parcelas PENDING. Parcelas já RECEIVED viram crédito do paciente (TICK-D06).</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-D02 · TICK-D06</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Botão Cancelar disponível em Budget APPROVED.

• Modal pede motivo (texto livre obrigatório).

• Status do Budget → CANCELED. Parcelas PENDING → CANCELED.

• Parcelas RECEIVED: oferecer 2 opções: (a) virar crédito do paciente, (b) estornar (gera devolução).

• Comissão provisionada das parcelas canceladas é removida.

• Status do paciente recalculado.
</td>
</tr>
</tbody>
</table>

|                                           |             |
|-------------------------------------------|-------------|
| **TICK-D05** · **Renegociação de dívida** | **MEDIA** G |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Paciente está com 4 parcelas vencidas de R$ 250 = R$ 1.000. Quer renegociar para 6 de R$ 200 (com juros). Sistema cria novo Budget filho referenciando as parcelas originais como 'substituídas'.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-D02</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Tela Renegociar abre seleção das parcelas a renegociar (PENDING e VENCIDAS).

• Calcula valor original + juros (campo editável).

• Define nova condição: nº parcelas, forma, vencimentos.

• Cria novo Budget tipo RENEGOTIATION com link para Budget original.

• Parcelas originais → status RENEGOTIATED (saem de A Receber, vão para histórico).

• Histórico do paciente mostra link entre original e renegociação.

• CT-AR-12 da auditoria.
</td>
</tr>
</tbody>
</table>

|                                                        |             |
|--------------------------------------------------------|-------------|
| **TICK-D06** · **Crédito do paciente (PatientCredit)** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Paciente tem saldo positivo a favor (estornos não devolvidos, pré-pagamento, valor pago acima da parcela). Pode ser abatido em parcela futura.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>A Receber (abatimento) · Financeiro do paciente (card Crédito)</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Saldo de crédito por paciente, calculado: Σ entradas em PatientCredit − Σ saídas.

• Crédito é gerado por: (a) estorno sem devolução (TICK-E08), (b) pagamento de valor maior que a parcela (TICK-E04), (c) lançamento manual (gerente).

• Ao receber parcela, sistema oferece abater do crédito disponível antes de pedir forma de pagamento.

• Card 'Crédito' no prontuário mostra saldo atual e histórico de movimentos.

• Crédito não tem prazo de validade (configurável).

• Sacar crédito (devolver dinheiro pro paciente) gera saída no Fluxo de Caixa.
</td>
</tr>
</tbody>
</table>

|                                                                 |             |
|-----------------------------------------------------------------|-------------|
| **TICK-D07** · **Status Adimplente / Inadimplente do paciente** | **MEDIA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Calcular automaticamente. Visível no header do prontuário. Inadimplente = pelo menos 1 parcela vencida e não paga.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-D02</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Cálculo on-the-fly via query (não persistir): EXISTS Installment WHERE patientId=X AND status=PENDING AND dueDate &lt; today.

• Badge no header do prontuário: verde 'Adimplente' / amarelo 'Em atraso (1 parcela)' / vermelho 'Inadimplente (3+ parcelas)'.

• Tooltip mostra quanto está vencido e há quantos dias.

• Listagem de pacientes permite filtrar por status.
</td>
</tr>
</tbody>
</table>

|                                                 |            |
|-------------------------------------------------|------------|
| **TICK-D08** · **Aba Financeiro no prontuário** | **ALTA** G |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Aba que centraliza tudo do paciente: cards (Total Aprovado, Pago, Em Aberto, Vencido, Crédito) + 4 sub-abas (Transações, Orçamentos, Plano de Tratamento, Recibos). Print 9 da auditoria.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-D01 · TICK-D02 · TICK-D06 · TICK-D07</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>Prontuário</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• 5 cards no topo. Coerência: Total Aprovado = Pago + Em Aberto + Vencido + Estornado − Crédito. SEMPRE.

• Aba Transações: lista cronológica de Installments + Expenses do paciente. Filtros: Todos, Pendentes, Pagos, Vencidos, Estornados.

• Aba Orçamentos: lista de Budgets com status. Permite criar novo, editar, cancelar.

• Aba Plano de Tratamento: visão clínica (procedimentos do orçamento, executados/pendentes).

• Aba Recibos: lista PaymentReceipts. Botão 'Imprimir/Reenviar' por recibo.

• Botões topo: Agendar, Anexar arquivo, Gerar documento, Cobrar, Iniciar atendimento, Receber Pagamento, Novo Orçamento.
</td>
</tr>
</tbody>
</table>

<table>

<tbody>
<tr class="odd">
<td>**ÉPICO E**

**A Receber**

*Coração do dia a dia da recepção. Inclui o BUG-01 da auditoria (baixa parcial em Dinheiro/PIX) que é CRÍTICO. Tela vista no print 3 da auditoria.*
</td>
</tr>
</tbody>
</table>

|                                                            |               |
|------------------------------------------------------------|---------------|
| **TICK-E01** · **Tela A Receber (lista, filtros, totais)** | **CRITICA** G |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Tela principal: 4 cards (Total a Receber, Recebido, Vencido, Transações) + lista de parcelas com filtros e ações.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-D02</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>Dashboard · Prontuário</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Cards calculados em tempo real conforme filtro de período.

• Lista mostra: Descrição (paciente + parcela #/#), Valor, Vencimento, Recebido em, Forma, Status, Ações.

• Filtros: descrição (busca), período (date range), status (Pendente/Recebido/Vencido/Estornado/Cancelado), forma de pagamento.

• Filtros combinados: cards e lista recalculam juntos.

• Ordenação por clique nos headers.

• Paginação ou scroll infinito (decidir conforme volume — 2.283+ no caso da clínica).
</td>
</tr>
<tr class="odd">
<td>**Notas**</td>
<td>CT-AR-01 a CT-AR-15 da auditoria.</td>
</tr>
</tbody>
</table>

|                                                           |               |
|-----------------------------------------------------------|---------------|
| **TICK-E02** · **Modal Receber Pagamento (caso simples)** | **CRITICA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Modal disparado pelo botão Receber em uma parcela. Caso simples: paciente paga valor exato. Confirma forma e conta.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-E01</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>Fluxo de Caixa · Caixa · Comissão</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Modal pré-preenche: valor da parcela, forma de pagamento do orçamento, conta padrão da forma, data hoje.

• Campos editáveis: valor (vide TICK-E03), forma, conta destino, data efetiva, observação.

• Botão Confirmar dispara cadeia de efeitos (vide tabela 2.2 — 7 destinos).

• Após sucesso, modal fecha e a lista atualiza imediatamente.
</td>
</tr>
</tbody>
</table>

|                                                                  |               |
|------------------------------------------------------------------|---------------|
| **TICK-E03** · **Baixa parcial em Dinheiro/PIX/Boleto (BUG-01)** | **CRITICA** G |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>RESOLVE BUG-01 — A reclamação número 1 da clínica. Paciente combinou parcela R$ 306, paga R$ 276. Sistema PRECISA permitir registrar exatamente isso.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-E02 · TICK-D06</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>A Receber · Crédito do paciente</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Campo 'Valor recebido' editável no modal (default = valor da parcela).

• Se valor &lt; parcela: dropdown de ação: (a) Gerar nova parcela com diferença e vencimento sugerido (próximo mês), (b) Lançar como 'Saldo devedor sem prazo' (vai vencer hoje + 30), (c) Cancelar diferença (paciente não vai pagar).

• Se valor &gt; parcela: lançar excedente como Crédito do paciente (TICK-D06).

• Disponível APENAS para forma DINHEIRO, PIX e BOLETO. Cartão (débito/crédito) segue automático e não permite parcial.

• Comissão recalcula sobre o valor recebido, não sobre o orçado.

• Histórico no prontuário mostra a parcela original e a nova com link entre elas.
</td>
</tr>
<tr class="odd">
<td>**Notas**</td>
<td>Caso real Manuele: orçamento R$ 920 / 3x R$ 306 / paga R$ 276 → gera parcela #2 ajustada para R$ 336.</td>
</tr>
</tbody>
</table>

|                                                       |             |
|-------------------------------------------------------|-------------|
| **TICK-E04** · **Baixa em lote (múltiplas parcelas)** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Paciente fez PIX único de R$ 300 que cobre 2 parcelas (R$ 100 + R$ 200). Sistema deve permitir selecionar as 2 e dar baixa juntas.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-E02</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Checkbox por linha na lista de A Receber.

• Botão 'Receber selecionadas' aparece quando ≥ 2 selecionadas.

• Modal mostra soma das selecionadas, forma e data únicas para o lote.

• Gera 1 PaymentReceipt vinculando as N Installments + 1 FinancialEntry.
</td>
</tr>
</tbody>
</table>

|                                                           |             |
|-----------------------------------------------------------|-------------|
| **TICK-E05** · **Aplicação de juros e multa em vencidos** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Parcela vencida pode ser quitada com juros + multa. Configurar regra padrão na clínica (ex.: 2% multa + 1% ao mês juros).</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-E02</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>DRE (juros vai para 'Outras Receitas')</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Configuração global: % multa, % juros mensais.

• Modal Receber Pagamento mostra parcela vencida com sugestão de juros + multa calculados.

• Campo editável (recepcionista pode dar desconto na hora).

• Juros e multa lançados em FinancialEntry com categoria 'Juros e Multa Recebidos' (Outras Receitas).

• Não somam à receita do procedimento (não distorcem ticket médio nem comissão).
</td>
</tr>
</tbody>
</table>

|                                                   |             |
|---------------------------------------------------|-------------|
| **TICK-E06** · **Cobrança via WhatsApp / e-mail** | **MEDIA** G |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Botão 'Cobrar' em parcela ou no header do paciente. Abre modal com texto pronto + opção de enviar PIX (TICK-E07) ou link de boleto.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-E07</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Templates de mensagem (configuráveis por clínica): lembrete amigável, vencimento próximo, vencido, segunda cobrança.

• Variáveis: {nome}, {valor}, {vencimento}, {linkPix}, {linkBoleto}.

• Envio por WhatsApp (link wa.me) ou e-mail (SMTP da clínica).

• Histórico de cobranças enviadas no prontuário.
</td>
</tr>
</tbody>
</table>

|                                          |             |
|------------------------------------------|-------------|
| **TICK-E07** · **Geração de QRCode PIX** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Para parcelas em PIX, gerar QRCode (estático com chave PIX da clínica, ou dinâmico com valor preenchido).</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-B02</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>A Receber (modal de baixa)</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Configuração: chave PIX da clínica em Configurações → Contas Bancárias.

• QRCode estático: gerado client-side com chave + valor.

• QRCode dinâmico (BR Code): integração com banco se disponível (Sicredi, Itaú, BB têm API).

• Frontend exibe QRCode + linha pix copia-e-cola.

• Confirmação: webhook do banco marca parcela como recebida automaticamente (se integrado).
</td>
</tr>
<tr class="odd">
<td>**Notas**</td>
<td>Integração com banco fica em ticket separado (TICK-K-INT-01).</td>
</tr>
</tbody>
</table>

|                                                |               |
|------------------------------------------------|---------------|
| **TICK-E08** · **Estorno de parcela recebida** | **CRITICA** G |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Operação delicada. Reverte os 7 efeitos do recebimento. Frontend pede confirmação dupla. Backend atômico.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-E02 · TICK-D06</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>Fluxo de Caixa · Comissão · Crédito do paciente · Prontuário</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Botão Estornar disponível APENAS em parcelas RECEIVED. Permissão: GERENTE ou ADMIN.

• Modal pede motivo (obrigatório). Confirmação dupla (digitar 'ESTORNAR').

• Cadeia de efeitos atômica (transação): (1) Installment → REFUNDED. (2) Saldo da conta destino −valor. (3) Lançar SAÍDA no Fluxo de Caixa do dia ATUAL (não retroativo). (4) Reverter CommissionEntry. (5) Recalcular status do paciente. (6) Se era a única parcela paga, Budget volta a APPROVED.

• Modal final pergunta: (a) devolver dinheiro ao paciente (gera saída adicional), (b) virar crédito do paciente (TICK-D06).

• AuditLog completo: antes/depois, usuário, IP, motivo.
</td>
</tr>
<tr class="odd">
<td>**Notas**</td>
<td>CT-AR-09 e seção 7.3 da auditoria. Teste obrigatório: lançar → receber → estornar → verificar 7 efeitos voltaram ao estado original.</td>
</tr>
</tbody>
</table>

<table>

<tbody>
<tr class="odd">
<td>**ÉPICO F**

**A Pagar**

*Tela espelho de A Receber, mas para saídas. Inclui geração automática de despesas recorrentes e estorno de despesa paga.*
</td>
</tr>
</tbody>
</table>

|                                                          |            |
|----------------------------------------------------------|------------|
| **TICK-F01** · **Tela A Pagar (lista, filtros, totais)** | **ALTA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Tela principal: 4 cards (Total a Pagar, Total Recorrente, Próximos a Vencer, Transações) + lista. Print 4 da auditoria.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>Fluxo de Caixa · DRE</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Cards calculados em tempo real.

• Lista mostra: Descrição, Categoria, Vencimento, Valor, Conta, Status (Pendente/Pago/Vencido/Cancelado), Ações.

• Filtros: descrição, período, categoria, conta, status, 'Apenas vencidos'.

• Ordenação clicável.

• Vazio: mostra ícone + mensagem 'Nenhum título a pagar' (como no print).
</td>
</tr>
</tbody>
</table>

|                                       |            |
|---------------------------------------|------------|
| **TICK-F02** · **Modal Nova Despesa** | **ALTA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Cadastro avulso de despesa. Permite parcelamento (gera N Expenses).</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-F01 · TICK-B01 · TICK-B02</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Campos: descrição, categoria (obrigatório), fornecedor (texto livre), valor, vencimento, conta padrão, parcelas (1..N), recorrência (sim/não — se sim leva pra TICK-B04).

• Anexar comprovante (PDF/JPG/PNG até 10MB).

• Salvar gera 1..N Expenses com vencimentos sequenciais (mensais).

• Soma das parcelas = valor original (resto na última).
</td>
</tr>
</tbody>
</table>

|                                         |            |
|-----------------------------------------|------------|
| **TICK-F03** · **Pagamento de despesa** | **ALTA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Marca Expense como paga. Reduz saldo da conta. Aparece no Fluxo de Caixa e no DRE.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-F02</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>Fluxo de Caixa · DRE</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Botão Pagar abre modal com data efetiva e conta de origem.

• Permitir valor pago diferente do face (ex.: desconto, juros) — gera diferença lançada em 'Juros pagos' ou 'Descontos obtidos'.

• Cadeia de efeitos atômica: Expense → PAID, Saldo da conta −valor, FinancialEntry de saída no Fluxo (cashDate=data informada).

• DRE acolhe pela competenceDate (data de vencimento, não pagamento).
</td>
</tr>
</tbody>
</table>

|                                                 |             |
|-------------------------------------------------|-------------|
| **TICK-F04** · **Pagamento parcial de despesa** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Espelho de TICK-E03. Despesa de R$ 1.000, paguei R$ 600 hoje, vou pagar R$ 400 mês que vem.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-F03</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Modal Pagar tem campo 'Valor pago' editável.

• Se &lt; face: oferecer (a) gerar nova Expense com diferença, vencimento +30 dias, (b) cancelar diferença.

• Se &gt; face: registrar 'Juros pagos' como categoria automática.
</td>
</tr>
</tbody>
</table>

|                                            |             |
|--------------------------------------------|-------------|
| **TICK-F05** · **Estorno de despesa paga** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Pagou despesa errado. Restituição do fornecedor. Reverte saldo + lança entrada no Fluxo.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-F03</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Permissão: GERENTE ou ADMIN.

• Confirmação dupla.

• Cadeia: Expense → REFUNDED, Saldo da conta +valor, FinancialEntry de entrada no Fluxo (data atual).

• AuditLog completo.
</td>
</tr>
</tbody>
</table>

|                                                                    |             |
|--------------------------------------------------------------------|-------------|
| **TICK-F06** · **Geração automática de despesa recorrente (cron)** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Cron diário lê RecurringExpenses e gera Expenses no horizonte de 35 dias. Idempotente.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-B04 · TICK-F02</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Job agendado às 00:01 todos os dias.

• Para cada RecurringExpense ativa: calcular próximas competências dentro do horizonte.

• Se já existe Expense (recurringId, competence) → pular.

• Senão criar Expense em PENDING.

• Log do cron disponível em /admin/jobs.
</td>
</tr>
</tbody>
</table>

<table>

<tbody>
<tr class="odd">
<td>**ÉPICO G**

**Fluxo de Caixa**

*A fotografia do regime de caixa. Print 2 da auditoria. Inclui correção de nomenclatura (BUG-06) e bloqueio de duplo clique (BUG-08).*
</td>
</tr>
</tbody>
</table>

|                                                          |            |
|----------------------------------------------------------|------------|
| **TICK-G01** · **Tela Fluxo de Caixa (cards + gráfico)** | **ALTA** G |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Tela com 4 cards (Total Entradas, Total Saídas, Saldo Líquido, Saldo em Caixa), gráfico diário e tabela detalhada por dia.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01 · TICK-B02</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>A Receber (entradas) · A Pagar (saídas) · Caixa</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Saldo Líquido = entradas − saídas DO PERÍODO selecionado.

• Saldo em Caixa = saldo atual de TODAS as contas (instantâneo, não muda com filtro).

• Renomear na UI: 'Saldo Líquido' → 'Resultado do Período'. 'Saldo em Caixa' → 'Saldo Disponível Hoje'. Tooltip explica diferença. (BUG-06)

• Gráfico de linha: 1 verde (Entradas) + 1 vermelha (Saídas) por dia.

• Filtro de período: Hoje / Semana / Mês / Personalizado.

• Botão 'Saldo positivo no período' (verde) ou 'Saldo negativo' (vermelho) como badge automático.
</td>
</tr>
</tbody>
</table>

|                                                |             |
|------------------------------------------------|-------------|
| **TICK-G02** · **Tabela Detalhamento por Dia** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Tabela embaixo do gráfico. Mostra cada dia do período com Entradas, Saídas, Saldo cumulativo.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-G01</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Linhas: Data, Entradas, Saídas, Saldo (= saldo do dia anterior + entradas − saídas).

• Dias sem movimento aparecem com R$ 0,00 / R$ 0,00 / saldo herdado.

• Clicar em um dia abre drawer com lista de transações daquele dia.

• Ordenação asc/desc por clique no header.

• Soma total de Entradas = card Total de Entradas. Sempre.
</td>
</tr>
</tbody>
</table>

|                                                |            |
|------------------------------------------------|------------|
| **TICK-G03** · **Botão Nova Entrada (manual)** | **ALTA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Lançamento avulso de entrada (não vinculado a paciente). Ex.: venda de produto, taxa de cancelamento.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-G01 · TICK-A04</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Modal: descrição, valor, conta destino, categoria (de Receita), data efetiva, observação.

• Salva como FinancialEntry tipo INCOME, manual=true.

• Atualiza imediatamente: Total de Entradas, Saldo da conta, gráfico, tabela.

• Botão usa Idempotency-Key (TICK-A04) — duplo clique não duplica.
</td>
</tr>
</tbody>
</table>

|                                              |            |
|----------------------------------------------|------------|
| **TICK-G04** · **Botão Nova Saída (manual)** | **ALTA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Lançamento avulso de saída. Cria Expense PAID em uma operação só (atalho de TICK-F02 + TICK-F03).</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-G01 · TICK-F03</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Modal: descrição, valor, conta origem, categoria (de Despesa), data efetiva, fornecedor, observação, anexo.

• Cria Expense status=PAID + FinancialEntry de saída.

• Atalho útil para despesas pequenas que não precisam de cadastro prévio em A Pagar.
</td>
</tr>
</tbody>
</table>

|                                            |             |
|--------------------------------------------|-------------|
| **TICK-G05** · **Geração de PDF do Fluxo** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Botão Gerar PDF exporta período selecionado. Cabeçalho com clínica, totais, gráfico, tabela detalhada.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-G01</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• PDF tem cabeçalho com nome da clínica, CNPJ, período.

• Resumo: 4 cards.

• Gráfico (renderizado server-side).

• Tabela com TODAS as transações (não só dias).

• Footer: gerado em DATETIME, por USER, hash de integridade.
</td>
</tr>
</tbody>
</table>

|                                                      |             |
|------------------------------------------------------|-------------|
| **TICK-G06** · **Lançamento retroativo (com aviso)** | **BAIXA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Recepção esqueceu de lançar um pagamento de ontem. Permitir lançar com data anterior — mas com aviso.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-G03 · TICK-G04</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Modal mostra alerta amarelo se data efetiva &lt; hoje.

• Mensagem: 'Atenção: lançamento retroativo afeta o saldo do dia X. Ele não recalcula o caixa fechado.'

• Bloqueado se a data cai em caixa já fechado — exigir reabrir o caixa antes (TICK-H05).

• AuditLog marca como retroativo.
</td>
</tr>
</tbody>
</table>

<table>

<tbody>
<tr class="odd">
<td>**ÉPICO H**

**Caixa (sessão diária)**

*Caixa físico — abertura, fechamento, sangria, suprimento. Print 7 da auditoria. Rastreia DINHEIRO somente; PIX/cartão/boleto vão direto para suas contas.*
</td>
</tr>
</tbody>
</table>

|                                      |            |
|--------------------------------------|------------|
| **TICK-H01** · **Abertura de caixa** | **ALTA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Recepcionista digita valor inicial em dinheiro. Cria CashRegister status=OPEN vinculada ao operador e à data.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01 · TICK-B02</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>Fluxo de Caixa (lançamentos em dinheiro)</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Tela 'Caixa do Dia' mostra Aberto/Fechado conforme dia atual.

• Botão Abrir Caixa quando ainda não aberto. Modal pede saldo de abertura.

• Cria CashRegister(date, openedBy, openedAt, openingBalance, status=OPEN).

• Não permitir 2 caixas abertos no mesmo dia.

• Operador pode abrir caixa pra dias passados (ADMIN apenas).

• Aba Histórico lista caixas anteriores.
</td>
</tr>
</tbody>
</table>

|                            |             |
|----------------------------|-------------|
| **TICK-H02** · **Sangria** | **MEDIA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Tirar dinheiro do caixa físico para depositar em conta. Movimento NEUTRO no DRE (transferência interna).</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-H01 · TICK-B02</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Botão Sangria no caixa aberto. Modal: valor, conta destino, observação.

• Cria CashMovement type=WITHDRAWAL + 2 FinancialEntries marcados como TRANSFER (saída na CASH, entrada na conta destino).

• TRANSFER não soma no DRE.

• Caixa físico saldo −valor. Conta destino +valor.
</td>
</tr>
</tbody>
</table>

|                               |             |
|-------------------------------|-------------|
| **TICK-H03** · **Suprimento** | **MEDIA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Inverso da sangria. Pegar dinheiro do banco e colocar no caixa para troco.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-H01</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Botão Suprimento. Modal: valor, conta origem, observação.

• Cria CashMovement type=DEPOSIT + 2 FinancialEntries TRANSFER.

• Caixa físico +valor. Conta origem −valor.
</td>
</tr>
</tbody>
</table>

|                                                        |            |
|--------------------------------------------------------|------------|
| **TICK-H04** · **Fechamento de caixa (com diferença)** | **ALTA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Recepcionista conta dinheiro físico no fim do expediente. Sistema mostra valor esperado. Diferença é registrada.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-H01 · TICK-H02 · TICK-H03</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>DRE (quebra de caixa entra como Outras Despesas/Receitas)</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Tela Fechar Caixa mostra: saldo esperado calculado (abertura + entradas − saídas − sangrias + suprimentos), campo 'Saldo conferido' (digitar valor).

• Diferença = conferido − esperado.

• Se diferença ≠ 0: criar lançamento 'Quebra de Caixa' categoria 'Outras Despesas' (se falta) ou 'Outras Receitas' (se sobra).

• Status: CashRegister → CLOSED. closedBy, closedAt, closingBalance, difference registrados.

• Aviso se há parcelas em dinheiro do dia ainda PENDING — dá opção de confirmar mesmo assim ou voltar.

• PDF de resumo gerado automaticamente (TICK-H07).
</td>
</tr>
</tbody>
</table>

|                                        |             |
|----------------------------------------|-------------|
| **TICK-H05** · **Reabertura de caixa** | **MEDIA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Caixa já fechado mas precisa de ajuste retroativo. ADMIN ou GERENTE pode reabrir com log obrigatório.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-H04</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Botão Reabrir disponível em caixa CLOSED.

• Modal pede motivo (obrigatório).

• Status volta para OPEN. reopenedBy, reopenedAt, reopenReason registrados.

• AuditLog completo.

• Após nova alteração, fechar de novo (TICK-H04). Histórico mantém todos os fechamentos.
</td>
</tr>
<tr class="even">
<td>**Permissões**</td>
<td>ADMIN, GERENTE</td>
</tr>
</tbody>
</table>

|                                                            |            |
|------------------------------------------------------------|------------|
| **TICK-H06** · **Bloqueio de lançamento em caixa fechado** | **ALTA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Tentar lançar movimento em dinheiro com data em caixa fechado retorna erro pedindo reabrir antes.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-H04 · TICK-H05</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Validação no backend: se forma de pagamento = DINHEIRO E cashDate cai em CashRegister CLOSED → 409 Conflict.

• Frontend captura erro e mostra modal: 'Caixa do dia X está fechado. Reabra para lançar.' Botão direto para TICK-H05.

• Usuário sem permissão para reabrir vê mensagem orientando a chamar gerente.
</td>
</tr>
</tbody>
</table>

|                                                |             |
|------------------------------------------------|-------------|
| **TICK-H07** · **PDF de resumo de fechamento** | **BAIXA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Recibo de fechamento. Operador imprime/assina. Útil pra auditoria física.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-H04</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Cabeçalho: clínica, data, operador.

• Tabela: saldo abertura, entradas (por forma), saídas, sangrias, suprimentos.

• Saldo esperado, conferido, diferença.

• Espaço pra assinatura do operador e do gerente.
</td>
</tr>
</tbody>
</table>

|                                        |             |
|----------------------------------------|-------------|
| **TICK-H08** · **Histórico de caixas** | **BAIXA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Aba Histórico lista todas as sessões de caixa. Filtros por operador, data, status.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-H01</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Lista: data, operador, abertura, fechamento, diferença, status.

• Filtros por operador, range de data, status (Aberto/Fechado/Reaberto).

• Drill-down em uma sessão mostra todos os movimentos.
</td>
</tr>
</tbody>
</table>

<table>

<tbody>
<tr class="odd">
<td>**ÉPICO I**

**DRE — Demonstração do Resultado**

*Regime de competência. Print 5 da auditoria. Inclui correção do BUG-03 (var % absurda) e BUG-04 (sem categoria).*
</td>
</tr>
</tbody>
</table>

|                                         |            |
|-----------------------------------------|------------|
| **TICK-I01** · **Tela DRE (estrutura)** | **ALTA** G |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Tela com toggle de período (Mês/Trimestre/Ano/Personalizado), comparativo com período anterior, linhas hierárquicas.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-B01</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Toggle de período no topo.

• Linhas: Receita Bruta → Deduções → Receita Líquida → Custos Variáveis → Margem Bruta → Despesas Fixas → EBITDA → Outras Despesas → Lucro Líquido.

• Cada linha tem: Descrição, Período Atual, Período Anterior, Var %.

• Linhas-resultado (Receita Líquida, Margem Bruta, EBITDA, Lucro Líquido) destacadas em negrito.

• Texto 'vs. período anterior: DD/MM/AAAA - DD/MM/AAAA' abaixo do título.
</td>
</tr>
</tbody>
</table>

|                                              |            |
|----------------------------------------------|------------|
| **TICK-I02** · **Cálculo das linhas do DRE** | **ALTA** G |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Engine que agrupa FinancialEntries por categoria e tipo, no regime de competência.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-I01</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Receita Bruta = Σ entries com category.type=RECEITA no período (por competenceDate).

• Custos Variáveis = Σ category.type=CUSTO_VARIAVEL.

• Despesas Fixas = Σ category.type=DESPESA_FIXA.

• Outras Despesas = Σ category.type=OUTRA_DESPESA.

• TRANSFER (sangria/suprimento) NÃO entra em nada.

• Cada categoria tem subtotal expansível embaixo da linha agregadora.
</td>
</tr>
</tbody>
</table>

|                                            |             |
|--------------------------------------------|-------------|
| **TICK-I03** · **Drill-down em categoria** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Clicar em 'Receita Bruta' expande mostrando cada categoria. Clicar em uma categoria leva à lista de lançamentos.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-I02</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Caret expansível ao lado de cada linha agregadora.

• Expande mostrando subcategorias com valor.

• Clicar em subcategoria → drawer ou nova tela com lista de FinancialEntries.

• Da lista, clicar em entry → vai para origem (parcela, despesa, etc.).
</td>
</tr>
</tbody>
</table>

|                                                  |            |
|--------------------------------------------------|------------|
| **TICK-I04** · **Variação % corrigida (BUG-03)** | **ALTA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>RESOLVE BUG-03. Var % de 1713% não tem significado prático. Quando base anterior ≈ 0, mostrar 'Novo' ou '—'.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-I02</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Se valor anterior = 0 e atual &gt; 0: mostrar 'Novo' em verde.

• Se valor anterior &gt; 0 e atual = 0: mostrar 'Zerou' em vermelho.

• Se valor anterior &lt; 5% do atual: mostrar 'Novo' (variação não significativa de base muito pequena).

• Caso contrário: mostrar % normal.

• Mostrar seta ↑ ou ↓ junto.
</td>
</tr>
</tbody>
</table>

|                                                                |            |
|----------------------------------------------------------------|------------|
| **TICK-I05** · **Aviso de lançamentos sem categoria (BUG-04)** | **ALTA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>RESOLVE BUG-04. Banner amarelo no topo do DRE quando há lançamentos com category='Sem categoria'. Linka direto para tela de classificação.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-I02</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Banner aparece se count(entries com category='Sem categoria') &gt; 0.

• Mensagem: 'Há N lançamentos sem categoria — clique para classificar.'

• Clique abre tela com lista filtrada e dropdown de categoria por linha.

• Botão 'Atribuir em lote': selecionar várias linhas e aplicar mesma categoria.
</td>
</tr>
</tbody>
</table>

|                               |             |
|-------------------------------|-------------|
| **TICK-I06** · **PDF do DRE** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Exportar DRE em PDF para enviar ao contador.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-I01</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• PDF com mesma estrutura da tela.

• Cabeçalho: clínica, CNPJ, período.

• Linhas hierárquicas. Subtotais e totais destacados.

• Comparativo com período anterior.

• Footer com gerado em / por / hash.
</td>
</tr>
</tbody>
</table>

<table>

<tbody>
<tr class="odd">
<td>**ÉPICO J**

**Dashboard financeiro**

*Tela inicial. Print 1 da auditoria. Inclui correção de BUG-05 (ticket médio R$ 0), BUG-06 (nomenclatura confusa), BUG-10 (inadimplência 100%) e BUG-11 (gauge de meta zerado).*
</td>
</tr>
</tbody>
</table>

|                                                      |            |
|------------------------------------------------------|------------|
| **TICK-J01** · **Tela Dashboard (cards principais)** | **ALTA** G |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Cards: Entradas Hoje, Saídas Hoje, Saldo do Dia, Inadimplência Total, Receita Líquida, Saídas, Novas Entradas, Lucro Líquido, Ticket Médio. Toggle Hoje/Semana/Mês.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-I02 · TICK-G01</td>
</tr>
<tr class="odd">
<td>**Conversa com**</td>
<td>Fluxo, A Receber, A Pagar, DRE, Metas</td>
</tr>
<tr class="even">
<td>**Critérios de aceite**</td>
<td>• Toggle no topo direito: Hoje / Semana / Mês.

• Cards superiores (4): Entradas Hoje, Saídas Hoje, Saldo do Dia, Inadimplência. Sempre do dia atual independente do toggle.

• Cards inferiores (5): Receita Líquida, Saídas, Novas Entradas, Lucro Líquido, Ticket Médio. Respondem ao toggle.

• Cada card com mini-sparkline mostrando últimos 7 dias.

• Variação % vs. período anterior — usar regra TICK-I04.
</td>
</tr>
</tbody>
</table>

|                                                        |             |
|--------------------------------------------------------|-------------|
| **TICK-J02** · **Blocos A Receber e A Pagar (resumo)** | **MEDIA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Dois blocos lado a lado mostrando: Vencidos, A vencer, Vencem hoje. Link 'Ver todos' leva para a aba completa.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-E01 · TICK-F01</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Bloco A Receber: 3 linhas (Vencidos, A vencer, Vencem hoje) com valores.

• Bloco A Pagar idêntico.

• Link 'Ver todos' herda período do Dashboard.
</td>
</tr>
</tbody>
</table>

|                                                  |             |
|--------------------------------------------------|-------------|
| **TICK-J03** · **Gráfico Fluxo de Caixa Diário** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Gráfico de linha duplo (Entradas verde, Saídas vermelha) por dia do período.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-G01</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Linha verde Entradas + linha vermelha Saídas.

• Eixo X: dias do período.

• Eixo Y: valor R$.

• Hover mostra valor exato do dia.

• Badge 'Saldo positivo no período' acima do gráfico (verde se &gt;0, vermelho se &lt;0).
</td>
</tr>
</tbody>
</table>

|                                                  |            |
|--------------------------------------------------|------------|
| **TICK-J04** · **Ticket Médio correto (BUG-05)** | **ALTA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>RESOLVE BUG-05. Card mostra R$ 0,00 mesmo com receita &gt; 0. Fórmula está dividindo por 0.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-J01</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Fórmula: Σ (FinancialEntries de receita do período por competência) / count(distinct PatientId nessas entries).

• Se denominador = 0: mostrar '—' (NUNCA R$ 0,00 nem NaN).

• Tooltip explica: 'Receita ÷ pacientes únicos atendidos no período'.
</td>
</tr>
</tbody>
</table>

|                                                   |             |
|---------------------------------------------------|-------------|
| **TICK-J05** · **Gauge Receita vs Meta (BUG-11)** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Semicírculo mostrando % de atingimento da meta do mês. Quando meta=0, ocultar gauge e mostrar CTA.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-B05 · TICK-J01</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Toggle Mensal/Trimestral/Anual.

• Gauge mostra % com seta para % atingido.

• Indicadores: Meta, Esperado até hoje (% proporcional do período passado), Dias restantes.

• Se meta = 0: ocultar gauge. Mostrar caixa com 'Cadastre uma meta para acompanhar progresso' + botão direto para Configurações.

• Cor da % atingida: verde (≥100%), amarelo (70-99%), vermelho (&lt;70%).
</td>
</tr>
</tbody>
</table>

|                                                                |             |
|----------------------------------------------------------------|-------------|
| **TICK-J06** · **Card Inadimplência sem 100% errado (BUG-10)** | **MEDIA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>RESOLVE BUG-10. Card mostra '100.0%' em vermelho mesmo quando não há inadimplência real.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-J01</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Card mostra valor absoluto da inadimplência (Σ parcelas vencidas e não pagas).

• % só aparece quando houver base estável de comparação (período anterior &gt; 0).

• Se valor = 0: card aparece com '—' ou 'Sem inadimplência' em verde.
</td>
</tr>
</tbody>
</table>

|                                                |             |
|------------------------------------------------|-------------|
| **TICK-J07** · **Personalização do Dashboard** | **BAIXA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Botão 'Personalizar Dashboard'. Usuário escolhe quais cards mostrar e em qual ordem.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-J01</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Modal de configuração lista todos os cards/blocos.

• Drag-and-drop reordena.

• Toggle ativa/desativa cada card.

• Preferência salva por usuário (UserPreferences).

• 'Restaurar padrão' disponível.
</td>
</tr>
</tbody>
</table>

<table>

<tbody>
<tr class="odd">
<td>**ÉPICO K**

**Relatórios**

*Quatro abas: Comissões, Despesas por Categoria, Faturamento por Convênio, Ticket Médio. Print 6 da auditoria.*
</td>
</tr>
</tbody>
</table>

|                                        |            |
|----------------------------------------|------------|
| **TICK-K01** · **Relatório Comissões** | **ALTA** G |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Aba Comissões. Selecionar profissional + período. Lista todos os recebimentos do período com valor base, % aplicado, comissão devida.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-B03 · TICK-E02</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Filtros: profissional (autocomplete), período (Mês/Trimestre/Ano/Personalizado).

• Tabela: data recebimento, paciente, procedimento, valor recebido, % aplicado, comissão.

• Total ao final.

• Estornos do período aparecem como linha negativa.

• Linhas com regra ausente alertam: 'Sem regra de comissão configurada'.

• Cálculo: comissão sobre RECEBIDO (não orçado) — TICK-B03.
</td>
</tr>
</tbody>
</table>

|                                              |             |
|----------------------------------------------|-------------|
| **TICK-K02** · **Marcar comissão como paga** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>No relatório, selecionar linhas e marcar 'Paga'. Cria Expense automática e baixa.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-K01 · TICK-F03</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Checkbox por linha + ação 'Marcar como paga'.

• Cria Expense category=Comissões, fornecedor=nome do profissional, valor=Σ marcadas.

• Marcar Expense PAID na hora (atalho Nova Saída).

• CommissionEntry → status PAID. paidAt registrado.

• Próxima apuração não recalcula essas (já pagas).
</td>
</tr>
</tbody>
</table>

|                                                    |             |
|----------------------------------------------------|-------------|
| **TICK-K03** · **PDF de comissão para assinatura** | **BAIXA** P |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Profissional assina recibo de comissão recebida.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-K01</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Cabeçalho: nome do profissional, CRO, CPF, período.

• Tabela detalhada com todos os recebimentos.

• Total.

• Espaço para assinatura.
</td>
</tr>
</tbody>
</table>

|                                                     |             |
|-----------------------------------------------------|-------------|
| **TICK-K04** · **Relatório Despesas por Categoria** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Aba Despesas. Pizza ou barras com % por categoria. Drill-down.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-I02</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Gráfico de pizza com % de cada categoria sobre total de despesa do período.

• Tabela embaixo com valores absolutos e %.

• Drill-down em categoria mostra lista de Expenses.

• Comparativo de 6 meses (linha de tendência por categoria) em sub-aba.
</td>
</tr>
</tbody>
</table>

|                                                       |             |
|-------------------------------------------------------|-------------|
| **TICK-K05** · **Relatório Faturamento por Convênio** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Aba Convênios. Total faturado e recebido por operadora. Identifica inadimplência.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-E02 · TICK-B-CONV (convênios — escopo futuro)</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Tabela: convênio, faturado, recebido, glosa, inadimplente, ticket médio.

• Filtro: período.

• Toggle 'Apenas convênio' / 'Apenas particular' / 'Todos'.

• Identifica gap entre faturado e recebido (=glosa + inadimplência).
</td>
</tr>
</tbody>
</table>

|                                           |             |
|-------------------------------------------|-------------|
| **TICK-K06** · **Relatório Ticket Médio** | **BAIXA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Aba Ticket Médio. Por profissional, por especialidade, geral.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-J04</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• 3 visões: Geral, Por profissional, Por especialidade.

• Fórmula: Receita ÷ pacientes únicos atendidos.

• Comparativo entre profissionais (gráfico de barras).

• Filtro de período.
</td>
</tr>
</tbody>
</table>

<table>

<tbody>
<tr class="odd">
<td>**ÉPICO L**

**Auditoria, logs e backup**

*Funcionalidades transversais para garantir rastreabilidade e segurança. Resolve BUG-12 (logs ausentes).*
</td>
</tr>
</tbody>
</table>

|                                                |             |
|------------------------------------------------|-------------|
| **TICK-L01** · **Aba Auditoria nas entidades** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Em cada entidade financeira (Budget, Installment, Expense, Patient), aba 'Auditoria' mostra histórico de alterações. Vista no print 9 da auditoria (já existe no Patient).</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A02</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Aba Auditoria disponível em: Patient, Budget, Installment, Expense, CashRegister.

• Lista cronológica reversa: data/hora, usuário, ação, antes → depois.

• Diff visual destacando o que mudou (verde = adicionou, vermelho = removeu).

• Filtro por tipo de ação (CREATE/UPDATE/DELETE/RESTORE).
</td>
</tr>
</tbody>
</table>

|                                                |             |
|------------------------------------------------|-------------|
| **TICK-L02** · **Tela global de logs (admin)** | **BAIXA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>ADMIN tem tela /admin/audit-logs com busca por usuário, entidade, período, ação.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A02</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Filtros: usuário, entidade (tipo), ID, período, ação, IP.

• Lista paginada.

• Exportar CSV do resultado filtrado.

• Drill-down em log mostra JSON completo de before/after.
</td>
</tr>
<tr class="even">
<td>**Permissões**</td>
<td>ADMIN</td>
</tr>
</tbody>
</table>

|                                             |            |
|---------------------------------------------|------------|
| **TICK-L03** · **Backup diário automático** | **ALTA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Cron diário gera dump da base e envia para storage seguro (S3 ou similar). Retenção: 30 dias diários, 12 meses mensais.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Cron 04:00 (horário Brasil, fora do pico).

• pg_dump comprimido enviado para bucket criptografado.

• Retenção: últimos 30 dumps diários + 1 dump por mês dos últimos 12 meses.

• Notificação ao ADMIN se backup falhar.

• Tela /admin/backups mostra histórico e permite download manual (para ADMIN).
</td>
</tr>
</tbody>
</table>

|                                                        |             |
|--------------------------------------------------------|-------------|
| **TICK-L04** · **Exportação completa para o contador** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Exportar período em XLSX/CSV com layout amigável ao contador (não o pg_dump cru).</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Botão 'Exportar para contador' em Configurações.

• Modal: período, formato (XLSX ou CSV).

• Gera arquivo com 5 abas: Receitas, Despesas, Movimentações de caixa, DRE, Comissões.

• Layout: data, descrição, categoria, valor, conta, paciente, profissional.
</td>
</tr>
</tbody>
</table>

|                                                |             |
|------------------------------------------------|-------------|
| **TICK-L05** · **Política de retenção e LGPD** | **MEDIA** M |

<table>

<tbody>
<tr class="odd">
<td>**Descrição**</td>
<td>Implementar conformidade LGPD: anonimização de dados de paciente após N anos de inatividade, exportação de dados a pedido do titular, exclusão sob solicitação.</td>
</tr>
<tr class="even">
<td>**Depende de**</td>
<td>TICK-A01 · TICK-A02</td>
</tr>
<tr class="odd">
<td>**Critérios de aceite**</td>
<td>• Cron mensal verifica pacientes inativos há &gt; 5 anos sem solicitação ativa de retenção.

• Marca como ANONYMIZED: nome → 'Paciente removido', CPF → null, telefone → null. Histórico financeiro preservado (despersonalizado).

• Endpoint /api/lgpd/export retorna JSON com tudo do paciente.

• Endpoint /api/lgpd/delete remove dados pessoais (mantém financeiro despersonalizado por exigência fiscal).
</td>
</tr>
</tbody>
</table>

Parte III — Roadmap de execução

1\. Sequência por sprint (12 sprints)

Estimativa baseada em time de 2 a 3 desenvolvedores full-stack. Cada sprint = 2 semanas. Total ~6 meses.

| **Sprint** | **Objetivo**                        | **Tickets**                                                     |
|------------|-------------------------------------|-----------------------------------------------------------------|
| S1         | Fundação técnica                    | TICK-A01, A02, A03, A04                                         |
| S2         | Configurações                       | TICK-B01, B02, B03, B05, B06                                    |
| S3         | Importação base                     | TICK-C01, C02, C03, C10, C11, C12                               |
| S4         | Importação financeira               | TICK-C07, C08, C09 + reclassificação OTHER                      |
| S5         | Importação clínica                  | TICK-C04, C05, C06                                              |
| S6         | Núcleo paciente                     | TICK-D01, D02, D08                                              |
| S7         | A Receber + correção crítica BUG-01 | TICK-E01, E02, E03 (BUG-01), E08                                |
| S8         | Edição de orçamento (BUG-02)        | TICK-D03, D04, D06, D07, E04, E05                               |
| S9         | A Pagar + Despesas Recorrentes      | TICK-F01, F02, F03, F04, F05, F06, B04                          |
| S10        | Fluxo de Caixa + Caixa              | TICK-G01, G02, G03, G04, G06, H01, H02, H03, H04, H05, H06      |
| S11        | DRE + Dashboard + correções         | TICK-I01, I02, I03, I04, I05, J01, J02, J03, J04, J05, J06      |
| S12        | Relatórios + Polimentos             | TICK-K01, K02, K04, L01, L03, L04 + tickets de baixa prioridade |

> **Sprints 7 e 8 são caminho crítico**
>
> Os BUGs 1 e 2 da auditoria estão nessas sprints. São o bloqueio número 1 da clínica. Se o time tiver problemas anteriores, NÃO postergar S7 — antecipar movimentando outros tickets para depois.

2\. Caminho crítico (dependências bloqueantes)

As dependências abaixo formam o caminho crítico. Atrasar qualquer um destes atrasa a entrega final.

4.  TICK-A01 (modelo de dados) — bloqueia tudo.

5.  TICK-A03 (RBAC) — bloqueia configurações sensíveis.

6.  TICK-B01, B02, B03 — bloqueiam importação financeira (sem categoria, conta e regra de comissão, importações geram lixo).

7.  TICK-C03 (Patient) — bloqueia C04, C05, C06, C07, C08, C09.

8.  TICK-D01, D02 (Plano → Orçamento → parcelas) — bloqueiam todo o épico E (A Receber).

9.  TICK-E02 (modal receber) — bloqueia E03 (baixa parcial), E04 (em lote), E05 (juros), E08 (estorno).

10. TICK-I02 (cálculo do DRE) — bloqueia I03, I04, I05 e todos os Dashboards baseados em receita/despesa.

3\. Antes de cada sprint começar

- Refinar tickets da sprint com o time (estimativa, critérios mais detalhados, mockups).

- Garantir que os tickets das sprints anteriores foram concluídos e mergeados.

- Validar que as dependências cruzadas estão atendidas (vide caminho crítico).

- Pareamento técnico entre dev e PO/auditoria para validar entendimento.

4\. Definição de Pronto (DoD) — vale para todos os tickets

11. Código revisado por pelo menos 1 outro dev.

12. Testes automatizados (unitários + integração) cobrindo critérios de aceite.

13. Migration aplicada e revertível em ambiente de teste.

14. Documentação interna atualizada (README do módulo).

15. Auditoria via TICK-A02 funcionando (ações registradas).

16. PR mergeado em main e deploy em homologação.

17. Validação manual em homologação por QA ou PO.

18. Sem regressão nos tickets já concluídos (suite de regressão verde).

5\. Antes do go-live

Checklist final de release. Vinculado ao Checklist da auditoria (54 itens) e ao Guia de Importação (54 etapas).

19. 100% dos tickets CRÍTICA e ALTA mergeados.

20. Todos os 54 itens do checklist da auditoria marcados.

21. Importação completa rodada em ambiente de homologação com base real.

22. Conciliação financeira batendo (R\$ 445.025,75 recebidos, R\$ 92.769,15 a receber).

23. Treinamento de recepção e profissionais realizado.

24. Backup automático rodando há pelo menos 7 dias.

25. Acesso à Clinicorp (modo leitura) confirmado para 60 dias pós go-live.

*Documento mestre. Atualizar conforme tickets forem concluídos. ID dos tickets é estável — usar nas branches (ex.: feat/TICK-E03-baixa-parcial).*
