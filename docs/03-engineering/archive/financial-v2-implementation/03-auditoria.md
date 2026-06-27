# Auditoria do Financeiro — Klivy/Salus

> Diagnóstico do estado atual: 12 bugs identificados (2 críticos), 16 seções com casos de teste CT-XX-NN.
> 
> Convertido de: `Auditoria_Financeiro_Klivy.docx`  
> Última atualização: maio de 2026

---

**Sistema Klivy / Salus**

*Roteiro funcional, casos de teste e checklist de validação*

Migração: Clinicorp → Klivy

*Escopo: Clínicas odontológicas, médicas e estéticas*

*Documento elaborado em maio de 2026*

Sumário

1\. Resumo executivo

Este documento é o roteiro de auditoria do módulo financeiro do sistema Klivy (apresentado como “Salus” na interface), elaborado a partir da análise dos arquivos exportados da Clinicorp, das telas atuais do Klivy e dos relatos da equipe da clínica. O objetivo é validar, ponto a ponto, se o módulo financeiro está 100% funcional, sem excessos e sem falhas, antes de declarar a migração concluída.

A auditoria foi estruturada em três frentes: (a) verificação dos dados a serem importados da Clinicorp, (b) checklist funcional de cada área do financeiro do Klivy, e (c) catálogo dos bugs e fricções já relatados que precisam ser corrigidos antes do uso pleno.


### 1.1 Volume de dados envolvido na migração


Os números abaixo foram extraídos diretamente dos arquivos enviados (Clinicorp). Servem de referência para a conciliação após a importação no Klivy:

| **Arquivo / Entidade**     | **Quantidade**                   | **Observação**                                         |
|----------------------------|----------------------------------|--------------------------------------------------------|
| Patient (Pacientes)        | 2.559 cadastros                  | 2.407 ativos · 151 marcados como deletados             |
| Appointment (Agendamentos) | 8.745 registros                  | Período: jul/2023 a jan/2027 · 346 cancelados          |
| Budgets (Orçamentos)       | 34 orçamentos · 58 procedimentos | R\$ 24.650,83 em valor total · 16 pacientes envolvidos |
| PaymentHeader (Cabeçalhos) | 1.805 pagamentos                 | 1.764 confirmados · 39 deletados · 34 parciais         |
| PaymentItem (Parcelas)     | 2.283 parcelas                   | 1.920 recebidas · 67 canceladas · 2 editadas           |
| BookEntry (Lançamentos)    | 9.398 lançamentos                | 4.937 débitos · 4.461 créditos · 582 reconciliados     |
| Valor total movimentado    | R\$ 537.794,90 lançados          | R\$ 445.025,75 efetivamente recebidos                  |


### 1.2 Mapa de cores deste documento


- Azul (cabeçalho) — informação estrutural / referência.

- Verde claro — comportamento esperado, ponto que deve passar no teste.

- Laranja — alerta, comportamento que costuma falhar ou que já foi reportado como problema.

- Cinza claro — linha alternada, apenas leitura.

2\. Migração Clinicorp → Klivy: o que importar e como mapear

A pergunta central é: dos seis arquivos exportados da Clinicorp, quais são realmente necessários para reconstruir a contabilidade da clínica no Klivy? A resposta curta: quatro são essenciais (Patient, Budgets, PaymentHeader, PaymentItem), um é fortemente recomendado (Appointment) e um é técnico/auditorial (BookEntry). Detalho abaixo.


### 2.1 Tabela de decisão de importação


| **Arquivo**        | **Importar?** | **Para quê serve no Klivy**                                                                   | **Recomendação prática**                                                                                                                                        |
|--------------------|---------------|-----------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Patient.xlsx       | SIM           | Cadastro de pacientes (vínculo de todas as cobranças). Sem ele, nenhum recebível tem dono.    | Importar primeiro. Conferir CPF (OtherDocumentId), nome, telefone e ImportedId para conciliar IDs.                                                              |
| Budgets.xlsx       | SIM           | Orçamentos e planos de tratamento abertos. Alimenta a aba “A Receber” futura.                 | Importar somente os com BudgetApproved=X e Executed=null (em andamento). Os já executados/finalizados viram histórico.                                          |
| PaymentHeader.xlsx | SIM           | Cabeçalho de cada cobrança (data, paciente, descrição, parcial sim/não).                      | Filtrar Deleted=null. Marcar IsPartialPayment=X para revisão manual no Klivy.                                                                                   |
| PaymentItem.xlsx   | SIM           | Parcelas individuais — é onde mora a forma de pagamento, vencimento, status e valor recebido. | Filtrar Canceled=null. Mapear Type → forma de pagamento Klivy (tabela 2.3).                                                                                     |
| Appointment.xlsx   | RECOMENDADO   | Histórico de agendamentos — dá contexto para o relatório de ticket médio e produtividade.     | Sem isso, indicadores tipo “quantos atendimentos por mês” ficam zerados nos meses pré-migração.                                                                 |
| BookEntry.xlsx     | OPCIONAL      | Razão contábil interno da Clinicorp. Granularidade muito alta (9.398 linhas).                 | Não importar como transação. Guardar como referência de auditoria caso precise rastrear de onde veio um saldo. Os totais de PaymentItem já reconstroem o caixa. |


### 2.2 Ordem de importação obrigatória


Há dependência de chaves estrangeiras (PatientId aparece em todos os outros arquivos). A ordem correta é:


## 1.  Patient — cria a base de pacientes no Klivy. Se um PatientId não existir aqui, todos os pagamentos dele ficam órfãos.



## 2.  Categorias / Contas bancárias / Regras de comissão — configurar no Klivy ANTES de importar pagamentos. Sem categoria cadastrada, todo lançamento cai em “Sem categoria” (foi exatamente o que aconteceu na DRE: R\$ 3.626,00 em “Receita Bruta — Sem categoria”).



## 3.  Budgets — cria os orçamentos/planos de tratamento. Liga a Patient via PatientId.



## 4.  PaymentHeader — cria os cabeçalhos de cobrança. Liga a Patient, Budget e contém o ReceiverBusinessId (caso a clínica tenha mais de uma unidade).



## 5.  PaymentItem — cria as parcelas. Liga a PaymentHeaderId. Esse é o passo que efetivamente popula “A Receber” e “Recebidos”.



## 6.  Appointment — pode ser o último, é independente do fluxo financeiro.



### 2.3 Mapeamento de formas de pagamento (Clinicorp → Klivy)


Esse mapeamento é crítico. A Clinicorp grava o tipo na coluna PaymentItem.Type, e o Klivy precisa receber o valor traduzido para o vocabulário dele (Dinheiro, PIX, Débito, Crédito, Boleto). Os 2.283 itens de pagamento se distribuem assim:

| **Type (Clinicorp)** | **Qtd** | **% total** | **Forma no Klivy**           | **Cuidado na importação**                                                                                        |
|----------------------|---------|-------------|------------------------------|------------------------------------------------------------------------------------------------------------------|
| OTHER                | 1.167   | 51%         | Dinheiro ou PIX              | A Clinicorp não distingue Dinheiro de PIX. Pedir conferência manual nos casos de maior valor (acima de R\$ 500). |
| CREDIT_CARD_EXTERNAL | 717     | 31%         | Crédito (maquininha externa) | Conferir CreditCardInstallmentsCount e CardTypeFlag (Visa/Master/Elo) se o Klivy guardar bandeira.               |
| DEBIT_CARD_EXTERNAL  | 331     | 15%         | Débito (maquininha externa)  | Quase sempre 1× e D+1. Verificar se há taxa MDR a deduzir.                                                       |
| BOLETO_INTERNAL      | 38      | 2%          | Boleto                       | Trazer BoletoDigitalLine e BoletoUrl (linha digitável e URL) — útil pra reemissão.                               |
| CREDIT_CARD_INTERNAL | 30      | 1%          | Crédito (link/internal)      | Trazer ExternalTxId para rastrear no gateway, se for o caso.                                                     |

Status da parcela (PaymentItem) também precisa de mapeamento. As três colunas que importam são: PaymentConfirmed (X = confirmado), PaymentReceived (X = entrou no caixa) e Canceled (X = cancelado/estornado). A combinação dá:

| **PaymentConfirmed** | **PaymentReceived** | **Canceled** | **Status no Klivy**        | **Onde aparece**              |
|----------------------|---------------------|--------------|----------------------------|-------------------------------|
| X                    | X                   | —            | Recebido                   | Fluxo de Caixa + DRE Receita  |
| X                    | —                   | —            | Pendente / A receber       | Aba A Receber                 |
| —                    | —                   | —            | Em aberto (não confirmado) | Aba A Receber (sinalizado)    |
| X                    | qualquer            | X            | Estornado / Cancelado      | Histórico (não soma no caixa) |


### 2.4 Conciliação obrigatória pós-importação


Após rodar a importação, antes de liberar o sistema para uso real, conferir os seguintes totais. Os valores de referência saem dos arquivos da Clinicorp:

| **Indicador**                             | **Valor esperado (Clinicorp)** | **Como verificar no Klivy**                                                           |
|-------------------------------------------|--------------------------------|---------------------------------------------------------------------------------------|
| Pacientes ativos                          | 2.407                          | Pacientes → Filtro: ativos                                                            |
| Soma de PaymentItem com Canceled=null     | R\$ 537.794,90                 | A Receber: Total a Receber + Recebido                                                 |
| Soma de PaymentItem com PaymentReceived=X | R\$ 445.025,75                 | Fluxo de Caixa: Total de Entradas (sem filtro de período)                             |
| Pagamentos parciais (IsPartialPayment=X)  | 34 cabeçalhos                  | Marcar para revisão manual — prováveis pacientes do tipo “Manuele” descrito no relato |
| Itens cancelados                          | 67 parcelas                    | Devem aparecer em Histórico/Estornados, NUNCA em A Receber                            |
| Range de datas                            | jul/2023 a abr/2026            | Fluxo de Caixa: selecionar “Personalizado” e fechar com extrato bancário              |

3\. Fluxo geral do financeiro — como tudo deveria conversar

Antes de entrar nas telas, é essencial entender como os módulos se conectam. O Klivy parte do princípio de que todo dinheiro que entra ou sai da clínica passa por um lançamento financeiro com origem rastreável. As origens possíveis são quatro:


## 7.  Origem clínica: o profissional cria um Plano de Tratamento ou Orçamento dentro do prontuário do paciente. Ao aprovar, ele vira parcelas em “A Receber”.



## 8.  Origem manual (entrada): a recepção lança uma “Nova Entrada” diretamente em Fluxo de Caixa (ex.: venda de produto, taxa de cancelamento).



## 9.  Origem manual (saída): lançamento de “Nova Despesa” em A Pagar (ex.: aluguel, fornecedor, salário).



## 10. Origem recorrente: configuradas em Configurações → Despesas Recorrentes (ex.: assinatura de software, plano de internet) e replicadas automaticamente todo mês.


A regra de ouro é: nenhum valor pode aparecer no Dashboard, no DRE ou no Fluxo de Caixa sem ter uma dessas quatro origens identificadas. Se aparecer, é bug de origem fantasma — comum quando o sistema duplica lançamento na importação ou ao aprovar orçamento.


### 3.1 Diagrama lógico — o caminho do dinheiro


| **Etapa**                    | **O que acontece**                                                                                                | **Tela onde aparece**                  |
|------------------------------|-------------------------------------------------------------------------------------------------------------------|----------------------------------------|
| 1\. Plano de tratamento      | Dentista cria plano de tratamento no prontuário com procedimentos, valores e desconto. Ainda não vira financeiro. | Paciente → Plano de Tratamento         |
| 2\. Orçamento gerado         | Plano vira orçamento aprovável (com forma de pagamento, parcelas, vencimentos previstos).                         | Paciente → Financeiro → Orçamentos     |
| 3\. Aprovação do orçamento   | Recepção/dentista aprova. Orçamento gera N parcelas em “A Receber”, com PaymentForm e datas de vencimento.        | A Receber (status: Pendente)           |
| 4\. Recebimento da parcela   | Paciente paga. Recepção dá baixa: status muda para Recebido, valor entra no Fluxo de Caixa do dia.                | Fluxo de Caixa → Entradas              |
| 5\. Reconciliação bancária   | Confere o que entrou na conta da clínica vs. o que está marcado como recebido no sistema.                         | Fluxo de Caixa + Caixa (sangrias/sup.) |
| 6\. Comissão do profissional | Sistema calcula comissão sobre o valor recebido (não sobre o orçado), conforme regra cadastrada.                  | Relatórios → Comissões                 |
| 7\. Apuração mensal          | Receita líquida – despesas = lucro. Vai para o DRE.                                                               | DRE / Dashboard                        |


### 3.2 Princípios de integridade que a auditoria precisa validar


- **Princípio 1 — Origem única: cada parcela tem um único Orçamento de origem. Nunca dois.**

- Cobrança duplicada é o problema clássico. Aprovar o mesmo orçamento duas vezes ou importar dois headers para o mesmo budget gera o paciente devendo o dobro.

- **Princípio 2 — Imutabilidade do recebido: parcela já recebida não pode ser editada, só estornada.**

- Editar valor depois de receber distorce histórico. O caminho correto é estornar e re-lançar.

- **Princípio 3 — Conservação do valor: soma das parcelas = valor do orçamento (com desconto aplicado).**

- Se o orçamento for R\$ 920,00 com 3 parcelas, as 3 parcelas têm que somar exatamente R\$ 920,00. O sistema NÃO pode perder R\$ 0,01 por arredondamento — distribuir a diferença na última parcela.

- **Princípio 4 — Rastreabilidade total: clicando em um valor do Dashboard, é possível chegar até a parcela e o paciente que originaram aquele valor.**

- Se o Dashboard mostra R\$ 3.626 de receita bruta, deve ser possível abrir e ver a lista das transações que somam isso.

- **Princípio 5 — Caixa fechado é fechado: depois de fechar o caixa do dia, lançamentos retroativos exigem reabertura explícita com log de auditoria.**

4\. Configurações financeiras — o que precisa estar pronto antes

A tela Configurações do Financeiro tem cinco abas: Regras de Comissão, Despesas Recorrentes, Contas Bancárias, Categorias e Metas de Receita. Nenhum lançamento sério deve ser feito antes de essas cinco estarem populadas. É aqui que mora o motivo da DRE estar mostrando “Sem categoria — R\$ 3.626,00”: as categorias ainda não foram cadastradas.


### 4.1 Categorias — auditoria mínima


Categoria é como o sistema separa receita de despesa, e dentro de despesa, separa fixa de variável. Sem isso, a DRE é uma linha só. O catálogo mínimo recomendado para clínicas (com base nas categorias que apareceram nos arquivos da Clinicorp) é:

| **Categoria**          | **Tipo**       | **Exemplos do que entra**                                                       |
|------------------------|----------------|---------------------------------------------------------------------------------|
| RECEITAS               |                |                                                                                 |
| Consultas particulares | Receita        | Pagamentos diretos do paciente (Dinheiro, PIX, Débito)                          |
| Convênios              | Receita        | Faturamento de planos de saúde                                                  |
| Cartão de crédito      | Receita        | Recebimento de maquininha (separar para conciliar com extrato Cielo/Stone/etc.) |
| Vendas de produtos     | Receita        | Escovas, fios, produtos estéticos, gift cards                                   |
| Outras receitas        | Receita        | Taxa de cancelamento, multas por falta, juros recebidos                         |
| DESPESAS FIXAS         |                |                                                                                 |
| Aluguel                | Despesa Fixa   | Aluguel da sala/clínica + IPTU + condomínio                                     |
| Folha + encargos       | Despesa Fixa   | Salário de secretária, dentistas CLT, INSS, FGTS, vale-transporte               |
| Software/Sistemas      | Despesa Fixa   | Klivy, conta de internet, telefone, hospedagem                                  |
| Contador               | Despesa Fixa   | Honorários do escritório de contabilidade                                       |
| CUSTOS VARIÁVEIS       |                |                                                                                 |
| Materiais clínicos     | Custo Variável | Resina, anestésico, brocas, luvas, máscaras (entram como custo do procedimento) |
| Laboratório            | Custo Variável | Próteses, alinhadores, exames terceirizados                                     |
| Comissões              | Custo Variável | % pago aos profissionais sobre o recebido                                       |
| Taxas de cartão (MDR)  | Custo Variável | % retido pela maquininha — descontar do valor bruto                             |
| OUTRAS DESPESAS        |                |                                                                                 |
| Impostos               | Outra Despesa  | Simples Nacional, ISS, IRPF retido                                              |
| Marketing              | Outra Despesa  | Anúncios, agência, brindes                                                      |
| Manutenção             | Outra Despesa  | Conserto de equipamento, dedetização, limpeza                                   |

Casos de teste — Categorias

| **\#**    | **Cenário**                                             | **Resultado esperado**                                                              |
|-----------|---------------------------------------------------------|-------------------------------------------------------------------------------------|
| CT-CAT-01 | Criar uma categoria “Aluguel” do tipo Despesa Fixa.     | Aparece na lista. Disponível no campo “Categoria” ao criar Nova Despesa.            |
| CT-CAT-02 | Tentar criar duas categorias com nome idêntico.         | Sistema bloqueia ou pergunta se quer duplicar.                                      |
| CT-CAT-03 | Editar nome de uma categoria que já tem 50 lançamentos. | Os 50 lançamentos passam a mostrar o novo nome (não fica órfão).                    |
| CT-CAT-04 | Tentar excluir categoria com lançamentos vinculados.    | Sistema bloqueia ou exige migrar lançamentos para outra categoria.                  |
| CT-CAT-05 | Criar lançamento sem categoria.                         | Sistema permite, mas marca como “Sem categoria” na DRE (situação atual a corrigir). |


### 4.2 Contas bancárias


Cada conta bancária é uma “bolsa” separada de dinheiro. PIX cai no banco A, maquininha no banco B, dinheiro fica no caixa físico. O Klivy precisa permitir cadastrar pelo menos: Conta Corrente principal, Caixa físico (dinheiro vivo), Conta da maquininha de cartão (a receber, agenda da maquininha).

| **\#**   | **Cenário**                                                         | **Resultado esperado**                                                                                  |
|----------|---------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------|
| CT-CC-01 | Cadastrar conta “Itaú PJ” com saldo inicial R\$ 5.000,00.           | Conta aparece. Saldo de Caixa total reflete +R\$ 5.000.                                                 |
| CT-CC-02 | Lançar entrada de R\$ 200 e marcar “Itaú PJ” como destino.          | Saldo Itaú = R\$ 5.200. Saldo Caixa físico inalterado.                                                  |
| CT-CC-03 | Fazer transferência interna de R\$ 500 do Itaú para o Caixa físico. | Itaú = R\$ 4.700, Caixa = R\$ 500. NÃO pode aparecer no DRE como receita ou despesa (movimento neutro). |
| CT-CC-04 | Excluir conta com saldo positivo.                                   | Sistema bloqueia: “Conta com saldo R\$ X. Transfira o saldo antes de excluir.”                          |
| CT-CC-05 | Marcar conta como inativa.                                          | Some dos seletores de destino, mas histórico de lançamentos antigos preservado.                         |


### 4.3 Regras de comissão


Esta é uma das áreas mais sensíveis para clínicas com mais de um profissional. A regra geral é: comissão é calculada sobre o valor RECEBIDO (não sobre o orçado), descontando taxas de cartão e laboratório quando aplicável. O Klivy precisa permitir variações por profissional, por procedimento e por forma de pagamento.

| **Tipo de regra**                | **Descrição**                                                    | **Exemplo**                                              |
|----------------------------------|------------------------------------------------------------------|----------------------------------------------------------|
| Percentual fixo por profissional | Profissional X recebe Y% sobre tudo que receber dele.            | Dra. Maria → 40% de tudo                                 |
| Percentual por procedimento      | Cada procedimento tem seu próprio %.                             | Limpeza 50%, Implante 30%, Clareamento 40%               |
| Por especialidade                | Especialidade dita o %.                                          | Ortodontia 35%, Endodontia 50%                           |
| Líquida vs. bruta                | % sobre valor bruto (orçado) ou líquido (recebido menos custos). | % sobre líquido é o padrão justo                         |
| Sobre recebimento ou agendamento | Provisão na confirmação ou só quando entra no caixa.             | Recomendado: só ao receber (evita comissão sobre calote) |

Casos de teste — Comissões

| **\#**    | **Cenário**                                                                        | **Resultado esperado**                                                                                                                                        |
|-----------|------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|
| CT-COM-01 | Criar regra Dra. X = 40% sobre recebido.                                           | Regra aparece e é aplicável a partir da data de criação.                                                                                                      |
| CT-COM-02 | Receber parcela de R\$ 500 da Dra. X.                                              | Em Relatórios → Comissões: Dra. X tem R\$ 200 a receber de comissão.                                                                                          |
| CT-COM-03 | Estornar a parcela de R\$ 500 do CT-02.                                            | Comissão da Dra. X volta a R\$ 0. NÃO pode ficar a R\$ 200 órfão.                                                                                             |
| CT-COM-04 | Mudar regra da Dra. X de 40% para 50% no meio do mês.                              | Recebimentos antes da mudança continuam a 40%. Recebimentos depois, a 50%. Auditoria preservada.                                                              |
| CT-COM-05 | Pagamento parcial: orçamento R\$ 1.000 com 50% de comissão. Paciente paga R\$ 300. | Comissão calculada sobre R\$ 300 = R\$ 150. Não sobre R\$ 1.000.                                                                                              |
| CT-COM-06 | Receber em cartão de crédito 3x sem deduzir taxa de máquina.                       | ⚠ ATENÇÃO: a regra deve permitir descontar MDR antes de calcular comissão. Caso contrário a clínica paga comissão sobre dinheiro que ela não recebeu líquido. |


### 4.4 Despesas recorrentes


Despesas que se repetem em data e valor previsíveis (aluguel, sistema, internet). O sistema gera o lançamento automaticamente todo mês na data configurada.

| **\#**   | **Cenário**                                                           | **Resultado esperado**                                                                                                   |
|----------|-----------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------|
| CT-RC-01 | Cadastrar “Aluguel R\$ 3.500” com vencimento todo dia 5.              | Em A Pagar aparece automaticamente uma despesa para 05 do mês corrente e do próximo.                                     |
| CT-RC-02 | No mês seguinte, pagar a despesa do dia 5.                            | Vira saída. Próximo mês a despesa é gerada normalmente.                                                                  |
| CT-RC-03 | Editar valor de R\$ 3.500 para R\$ 3.700.                             | Próximas ocorrências = R\$ 3.700. Anteriores não mudam.                                                                  |
| CT-RC-04 | Inativar despesa recorrente.                                          | Próximas não são geradas. As já geradas e não pagas continuam em A Pagar (decisão do usuário se quer manter ou excluir). |
| CT-RC-05 | Despesa com data variável (luz, água) — usar campo de valor estimado. | Sistema deixa cadastrar com valor mas exigir confirmação na data de pagamento.                                           |


### 4.5 Metas de receita


Visíveis no Dashboard como “Receita vs. Meta Mensal”. No print do sistema atual a meta está em R\$ 0,00 (não cadastrada), por isso o gauge está em 0,0% mesmo com R\$ 2.388 já realizados.

| **\#**     | **Cenário**                        | **Resultado esperado**                                                  |
|------------|------------------------------------|-------------------------------------------------------------------------|
| CT-META-01 | Cadastrar meta mensal R\$ 50.000.  | Dashboard passa a mostrar % de atingimento real.                        |
| CT-META-02 | Cadastrar meta trimestral e anual. | Toggles do gauge (Mensal/Trimestral/Anual) carregam valores diferentes. |
| CT-META-03 | Ajustar meta no meio do mês.       | Recálculo imediato sem precisar refazer lançamentos.                    |

5\. Dashboard financeiro

É a tela de entrada — concentra os indicadores de visão rápida. No print enviado vê-se: Entradas Hoje, Saídas Hoje, Saldo do Dia, Inadimplência Total, Receita Líquida, Saídas, Novas Entradas, Lucro Líquido, Ticket Médio, blocos de A Receber/A Pagar, gráfico de Fluxo de Caixa Diário e Receita vs. Meta. A auditoria do Dashboard é principalmente de coerência: os números aqui têm que bater com os números das telas-fonte.


### 5.1 Tabela de coerência cruzada


Valores observados no print de teste — confira se ainda batem na sua base atual:

| **Card no Dashboard**  | **Valor no print** | **Tem que ser igual a**                                                     |
|------------------------|--------------------|-----------------------------------------------------------------------------|
| Receita Líquida (mês)  | R\$ 2.388,00       | DRE → Receita Líquida do mesmo período                                      |
| Saídas (mês)           | R\$ 0,00           | Soma de A Pagar pago no mês + DRE → Despesas Fixas + Custos Variáveis       |
| Novas Entradas         | R\$ 3.458,00       | Soma de orçamentos NOVOS aprovados no mês (parcelas geradas)                |
| Lucro Líquido          | R\$ 2.388,00       | DRE → Lucro Líquido do mês                                                  |
| Ticket Médio           | R\$ 0,00           | (Receita Bruta) ÷ (nº atendimentos COM cobrança no mês). Zerado é suspeito. |
| A Receber → Vencidos   | R\$ 0,00           | A Receber → filtro Vencido                                                  |
| A Receber → A vencer   | R\$ 3.170,00       | A Receber → filtro A vencer                                                 |
| Saldo em Caixa (Fluxo) | R\$ 4.464,00       | Soma dos saldos das contas bancárias + Caixa físico                         |

Casos de teste — Dashboard

| **\#**     | **Cenário**                               | **Resultado esperado**                                                                         |
|------------|-------------------------------------------|------------------------------------------------------------------------------------------------|
| CT-DASH-01 | Lançar nova entrada de R\$ 100 hoje.      | Card “Entradas Hoje” passa de R\$ 0 para R\$ 100. Saldo do Dia idem.                           |
| CT-DASH-02 | Mudar filtro Hoje/Semana/Mês.             | Todos os cards recalculam. Não pode misturar período (ex.: cards mensais com gráfico semanal). |
| CT-DASH-03 | Clicar em “Inadimplência Total”.          | Leva direto para a aba A Receber → filtro Vencido. Soma confere.                               |
| CT-DASH-04 | Clicar em “Ver todos” no bloco A Receber. | Leva para A Receber. Filtro de período herdado do Dashboard.                                   |
| CT-DASH-05 | Ticket Médio com 0 atendimentos.          | Mostra R\$ 0 ou “—”. NUNCA dividir por zero (não pode aparecer NaN/Infinity).                  |
| CT-DASH-06 | Personalizar Dashboard: ocultar card.     | Preferência salva por usuário. Outros usuários não são afetados.                               |

6\. Fluxo de Caixa

É a fotografia do que efetivamente entrou e saiu (regime de caixa, não de competência). Tela com: cards de Total de Entradas, Total de Saídas, Saldo Líquido, Saldo em Caixa, gráfico diário, e detalhamento por dia. Os botões “Nova Entrada”, “Nova Saída” e “Gerar PDF” estão visíveis no print.


### 6.1 Diferença crítica: Saldo Líquido vs. Saldo em Caixa


Esses dois cards confundem na maioria das clínicas. Documente claramente:

| **Indicador**  | **Significado**                                                                                                                                      |
|----------------|------------------------------------------------------------------------------------------------------------------------------------------------------|
| Saldo Líquido  | Entradas do período — Saídas do período. Resultado do PERÍODO selecionado. No print: R\$ 2.388,00 (mai/2026).                                        |
| Saldo em Caixa | Patrimônio acumulado em todas as contas (banco + dinheiro físico). É um saldo INSTANTÂNEO, não muda com o filtro de período. No print: R\$ 4.464,00. |

*Se os usuários estão confundindo, considere renomear no produto para “Resultado do Período” e “Saldo Disponível Hoje”.*


### 6.2 Casos de teste — Fluxo de Caixa


| **\#**   | **Cenário**                                                                      | **Resultado esperado**                                                                                                                        |
|----------|----------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| CT-FC-01 | Botão “Nova Entrada”: lançar R\$ 250 em dinheiro, conta Caixa físico, hoje.      | Aparece na tabela de detalhamento de hoje. Total de Entradas +250. Saldo em Caixa do físico +250.                                             |
| CT-FC-02 | Botão “Nova Saída”: lançar R\$ 150 com categoria Materiais, conta Itaú PJ, hoje. | Total de Saídas +150. Saldo Itaú −150. Aparece em A Pagar como pago. Aparece no DRE como Custo Variável.                                      |
| CT-FC-03 | Selecionar período personalizado de 01/04 a 30/04.                               | Cards e gráfico carregam só abril. Maio some.                                                                                                 |
| CT-FC-04 | Gerar PDF.                                                                       | PDF tem cabeçalho da clínica, período, totais, tabela de movimentações com todas as colunas (data, descrição, paciente, forma, valor, conta). |
| CT-FC-05 | Lançamento retroativo (data de 3 meses atrás).                                   | Sistema permite com aviso. Atualiza saldo histórico. NÃO pode bagunçar o saldo de caixa atual (refazer cumulativo).                           |
| CT-FC-06 | Lançamento futuro (entrada agendada para próximo mês).                           | Não entra no Total de Entradas do mês atual. Vai pra A Receber com data futura.                                                               |
| CT-FC-07 | Excluir uma entrada já lançada.                                                  | Sistema pede confirmação. Lança movimento de estorno (não apaga histórico).                                                                   |
| CT-FC-08 | Clicar duas vezes seguidas em Nova Entrada (duplo clique).                       | NÃO pode criar dois lançamentos. Botão precisa ser bloqueado durante o submit.                                                                |


### 6.3 Detalhamento por dia (tabela inferior)


A tabela mostra Data, Entradas, Saídas, Saldo. Auditoria:

- Soma da coluna Entradas = card Total de Entradas (sempre).

- Saldo de cada dia = Saldo do dia anterior + Entradas do dia − Saídas do dia (efeito cumulativo).

- Dias sem movimento aparecem com R\$ 0,00 / R\$ 0,00 / saldo do dia anterior — não somem da listagem.

- Ordenação ascendente ou descendente por clique no cabeçalho.

- Clicando em um dia, abrir extrato detalhado com todas as transações daquele dia.

7\. A Receber

Coração do dia a dia da recepção. No print vê-se: Total a Receber R\$ 3.170, Recebido R\$ 4.464, Vencido R\$ 0, Transações 32. Lista com Descrição (paciente + parcela), Valor, Vencimento, Recebido em, Forma, Status, Ações. Botões Nova Entrada, Gerar PDF, filtros.


### 7.1 Status possíveis e regras de transição


| **Status**  | **Significado**                                                     | **Transições válidas**                                            |
|-------------|---------------------------------------------------------------------|-------------------------------------------------------------------|
| Pendente    | Parcela criada, ainda não recebida, dentro do prazo.                | → Recebido (ao dar baixa) \| → Vencido (após data) \| → Cancelado |
| Vencido     | Pendente que passou da data de vencimento sem baixa.                | → Recebido (com ou sem juros) \| → Cancelado \| → Renegociado     |
| Recebido    | Parcela paga e o dinheiro entrou em uma conta.                      | → Estornado (caminho único; não volta direto pra Pendente)        |
| Estornado   | Foi recebido mas o pagamento foi devolvido (chargeback, devolução). | Histórico apenas. Não soma em nenhum total ativo.                 |
| Cancelado   | Parcela inválida desde a origem (orçamento desistido).              | Histórico apenas.                                                 |
| Renegociado | Parcela substituída por novas parcelas com outras condições.        | Histórico aponta para as novas parcelas que substituíram.         |


### 7.2 Casos de teste — A Receber


| **\#**   | **Cenário**                                                                      | **Resultado esperado**                                                                                                                                          |
|----------|----------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| CT-AR-01 | Filtro por descrição: digitar nome do paciente.                                  | Lista filtra. Considerar acentos e maiúsculas. Aceita busca parcial.                                                                                            |
| CT-AR-02 | Filtro por período: selecionar 27/04 a 30/04.                                    | Lista carrega só vencimentos nesse intervalo.                                                                                                                   |
| CT-AR-03 | Filtro por status (Pendente, Recebido, Vencido).                                 | Recalcula totais dos cards superiores conforme filtro.                                                                                                          |
| CT-AR-04 | Dar baixa em parcela: clicar em Receber.                                         | Abre modal pedindo: data efetiva do recebimento, forma de pagamento (pode editar), conta de destino, observação.                                                |
| CT-AR-05 | Dar baixa em valor PARCIAL — ex.: parcela R\$ 306, paciente pagou R\$ 200.       | ⚠ FUNCIONALIDADE FALHA NO SISTEMA ATUAL (vide cap. 13). Esperado: campo “Valor recebido” editável. Diferença vai pra nova parcela ou registro de saldo devedor. |
| CT-AR-06 | Dar baixa com data retroativa (paciente pagou ontem mas só lancei hoje).         | Permitir alterar a data de recebimento no modal. O caixa do dia X é afetado, não o caixa de hoje.                                                               |
| CT-AR-07 | Editar parcela ainda Pendente: alterar valor.                                    | Permitido. Alteração registrada no log do paciente.                                                                                                             |
| CT-AR-08 | Editar parcela já Recebida.                                                      | BLOQUEADO. Mensagem: “Para editar, é necessário estornar primeiro.”                                                                                             |
| CT-AR-09 | Estornar parcela Recebida.                                                       | Status passa pra Estornado. Saldo da conta destino reduzido. Comissão reaberta. Lançamento de estorno aparece no Fluxo de Caixa.                                |
| CT-AR-10 | Aplicar juros/multa em parcela vencida.                                          | Permitir adicionar valor extra ao receber. Juros vai pra categoria “Outras receitas” (não vira receita do procedimento).                                        |
| CT-AR-11 | Receber duas parcelas no mesmo PIX (R\$ 100 + R\$ 200 = R\$ 300).                | Permitir seleção múltipla → baixa conjunta. Forma de pagamento e data únicas para o lote.                                                                       |
| CT-AR-12 | Renegociar dívida: paciente devia R\$ 1.000 em 1×, transformar em 4× de R\$ 250. | Funcionalidade “Renegociar”. Parcela original vai pra Renegociada. Quatro novas parcelas criadas referenciando a original.                                      |
| CT-AR-13 | Geração de boleto/PIX com QRCode na hora da baixa.                               | Se o sistema integra com banco, gerar e exibir QRCode/linha digitável. Se não, ao menos permitir colar o código manualmente.                                    |
| CT-AR-14 | Exportar lista filtrada para PDF.                                                | PDF respeita os filtros aplicados. Cabeçalho mostra qual filtro foi usado.                                                                                      |
| CT-AR-15 | Pesquisar parcela por número de orçamento (ex.: \#16).                           | Busca encontra. Útil para tirar dúvida do paciente que cita o número.                                                                                           |


### 7.3 Estorno: o caminho que precisa funcionar


Estorno é a operação mais delicada — afeta cinco lugares ao mesmo tempo. Quando você estorna uma parcela de R\$ 300 paga em PIX, o sistema PRECISA fazer:


## 11. Mudar status da parcela para Estornado.



## 12. Subtrair R\$ 300 da conta bancária que recebeu o PIX.



## 13. Lançar movimento de saída no Fluxo de Caixa do dia do estorno (não retroativo).



## 14. Reverter a comissão calculada para o profissional.



## 15. Voltar o orçamento para o status correto (se era a única parcela paga, orçamento volta a Pendente).


*Falha em qualquer um dos cinco passos é bug crítico. Sugestão de teste: lançar uma parcela R\$ 300 → receber → conferir os 5 efeitos → estornar → conferir se os 5 efeitos voltaram exatamente como estavam.*

8\. A Pagar

Tela espelho de A Receber, mas para saídas. No print vê-se Total a Pagar R\$ 0, Total Recorrente R\$ 0, Próximos a Vencer R\$ 0, Transações 0 — todos zerados (clínica ainda não cadastrou despesas no Klivy). Botões Nova Despesa, Gerar PDF, filtro Apenas vencidos.


### 8.1 Casos de teste — A Pagar


| **\#**   | **Cenário**                                                                                       | **Resultado esperado**                                                                                                     |
|----------|---------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------|
| CT-AP-01 | Nova Despesa: aluguel R\$ 3.500, vencimento dia 5, categoria Aluguel, fornecedor “Imobiliária X”. | Aparece em A Pagar com status Pendente. Card Total a Pagar +3.500.                                                         |
| CT-AP-02 | Pagar a despesa: clicar Pagar, escolher conta Itaú PJ, data hoje.                                 | Status → Pago. Saldo Itaú −3.500. Aparece em Fluxo de Caixa → Saídas. Aparece no DRE → Despesas Fixas (categoria Aluguel). |
| CT-AP-03 | Marcar despesa como recorrente mensal.                                                            | Próximo mês a despesa é gerada automaticamente. Vide CT-RC.                                                                |
| CT-AP-04 | Despesa parcelada: equipamento R\$ 12.000 em 6×.                                                  | Sistema cria 6 parcelas de R\$ 2.000 com vencimentos mensais. Cada uma é um item independente em A Pagar.                  |
| CT-AP-05 | Anexar comprovante (NF, boleto, recibo) na despesa.                                               | Upload aceita PDF/JPG/PNG. Anexo persiste e é baixável depois.                                                             |
| CT-AP-06 | Pagamento parcial de despesa.                                                                     | Mesma lógica de A Receber: campo de valor editável no momento da baixa, gera saldo a pagar.                                |
| CT-AP-07 | Cancelar despesa não paga.                                                                        | Status → Cancelado. Sai da lista de Próximos a Vencer.                                                                     |
| CT-AP-08 | Estornar despesa já paga (pagamento errado, restituição do fornecedor).                           | Saldo da conta volta. Movimento de estorno em Fluxo de Caixa.                                                              |
| CT-AP-09 | Filtro “Apenas vencidos”.                                                                         | Lista carrega só pendências com vencimento \< hoje.                                                                        |
| CT-AP-10 | Categorizar várias despesas em lote.                                                              | Seleção múltipla + ação em lote disponível.                                                                                |


### 8.2 Tipos de saída que toda clínica tem


Liste e teste essas categorias com pelo menos um lançamento real durante a auditoria — pra garantir que cada uma se comporta certo no DRE:

- Aluguel — Despesa fixa mensal.

- Folha de pagamento (separar salário, INSS, FGTS, vale-transporte) — Despesa fixa.

- Comissão paga ao profissional — Custo variável, abate da margem do procedimento.

- Materiais clínicos (anestésico, agulha, brocas) — Custo variável.

- Laboratório (prótese, alinhador, exame terceirizado) — Custo variável, idealmente vinculado ao procedimento/paciente.

- Sistema/software (Klivy, internet) — Despesa fixa, idealmente recorrente automática.

- Marketing — Outra despesa.

- Manutenção/equipamentos — Outra despesa.

- Impostos (Simples, ISS, IRPF) — Outra despesa, idealmente com calendário fiscal sugerido.

- Pró-labore do(s) sócio(s) — Despesa fixa, separada da folha CLT.

9\. DRE — Demonstração do Resultado do Exercício

DRE é regime de competência (não de caixa). Mostra o resultado considerando quando a receita foi gerada e quando a despesa foi incorrida, independente de quando o dinheiro entrou ou saiu. No print de teste o DRE mostra: Receita Bruta R\$ 3.626, Sem categoria R\$ 3.626 (alerta!), Receita Líquida R\$ 3.626, Margem Bruta R\$ 3.626, EBITDA R\$ 3.626, Lucro Líquido R\$ 3.626 — todos iguais porque ainda não há deduções nem despesas categorizadas. Var % de 1713% mostra grande variação vs. período anterior.


### 9.1 Estrutura padrão do DRE


| **Linha**            | **Cálculo / fonte**                                                                                           |
|----------------------|---------------------------------------------------------------------------------------------------------------|
| Receita Bruta        | Σ de todas as parcelas confirmadas no período (regime de competência: data do orçamento, não do recebimento). |
| (–) Deduções         | Devoluções, descontos concedidos depois da venda, glosas de convênio.                                         |
| = Receita Líquida    | Receita Bruta – Deduções                                                                                      |
| (–) Custos Variáveis | Materiais clínicos, laboratório, comissões, taxas de cartão (MDR)                                             |
| = Margem Bruta       | Receita Líquida – Custos Variáveis                                                                            |
| (–) Despesas Fixas   | Aluguel, folha, sistema, contador                                                                             |
| = EBITDA             | Margem Bruta – Despesas Fixas. Resultado operacional antes de impostos/financeiras.                           |
| (–) Outras Despesas  | Marketing, manutenção, impostos sobre o lucro                                                                 |
| = Lucro Líquido      | EBITDA – Outras Despesas. Resultado final.                                                                    |


### 9.2 Casos de teste — DRE


| **\#**    | **Cenário**                                   | **Resultado esperado**                                                                                                                                                                      |
|-----------|-----------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| CT-DRE-01 | Toggle Mês / Trimestre / Ano / Personalizado. | Recalcula todas as linhas. Var % compara com período anterior equivalente (mês com mês, trimestre com trimestre).                                                                           |
| CT-DRE-02 | Expandir “Receita Bruta”: lista categorias.   | Vê-se cada categoria (Particulares, Convênios, Cartão, etc.) com seu sub-total. Soma = Receita Bruta.                                                                                       |
| CT-DRE-03 | Expandir “Custos Variáveis”.                  | Idem: Materiais, Laboratório, Comissões, MDR. Cada um abrir lista de lançamentos clicando.                                                                                                  |
| CT-DRE-04 | Lançamento sem categoria.                     | Cai em “Sem categoria” como hoje. AVISO no topo: “3 lançamentos sem categoria — clique para classificar.”                                                                                   |
| CT-DRE-05 | Comparar Mai/2026 com Abr/2026.               | Coluna Período Anterior carrega abril. Var % corretamente calculada (não pode dar 1713% se valor anterior era zero — usar “—” ou “Novo”).                                                   |
| CT-DRE-06 | Gerar PDF do DRE.                             | PDF tem todas as linhas, períodos comparados, observação se há lançamentos sem categoria.                                                                                                   |
| CT-DRE-07 | Variação % com período anterior = 0.          | Não pode mostrar 1713,0%. Sugestão: mostrar “Novo” ou “—”.                                                                                                                                  |
| CT-DRE-08 | Conferir DRE × Fluxo de Caixa do mesmo mês.   | Vai dar diferente. DRE = competência (orçamentos do mês), Fluxo = caixa (recebimentos do mês). Diferença é a inadimplência ou recebimentos antecipados — explicar isso na tela com tooltip. |

10\. Relatórios

No print há 4 abas: Comissões, Despesas por Categoria, Faturamento por Convênio, Ticket Médio. Cada uma precisa ser testada.


### 10.1 Comissões


| **\#**        | **Cenário**                                                | **Resultado esperado**                                                                                       |
|---------------|------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------|
| CT-REL-COM-01 | Selecionar profissional + período Mês/Mai 2026 + Calcular. | Lista todos os recebimentos do profissional no mês, valor base, % aplicado, comissão devida. Total ao final. |
| CT-REL-COM-02 | Profissional sem regra cadastrada.                         | Mostrar “Sem regra de comissão configurada” em vez de listar com 0%.                                         |
| CT-REL-COM-03 | Recebimento parcial: paciente pagou metade.                | Comissão calculada apenas sobre a metade recebida (não sobre orçado).                                        |
| CT-REL-COM-04 | Estorno no período.                                        | Linha de estorno aparece subtraindo da comissão do mês.                                                      |
| CT-REL-COM-05 | Marcar comissão como Paga.                                 | Status passa pra Paga. Próxima apuração não recalcula essa.                                                  |
| CT-REL-COM-06 | Exportar PDF de comissão para o profissional assinar.      | PDF com identificação, período, lista detalhada, total, espaço para assinatura.                              |


### 10.2 Despesas por Categoria


| **\#**       | **Cenário**                  | **Resultado esperado**                                                                                             |
|--------------|------------------------------|--------------------------------------------------------------------------------------------------------------------|
| CT-REL-DC-01 | Período mensal.              | Pizza ou barras: % de cada categoria sobre total. Total bate com DRE → Despesas Fixas + Custos Variáveis + Outras. |
| CT-REL-DC-02 | Drill-down em uma categoria. | Lista de lançamentos daquela categoria no período.                                                                 |
| CT-REL-DC-03 | Comparativo de 6 meses.      | Tendência de cada categoria — útil pra ver aumento de aluguel, materiais inflacionando, etc.                       |


### 10.3 Faturamento por Convênio


| **\#**       | **Cenário**                                                                          | **Resultado esperado**                                                              |
|--------------|--------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------|
| CT-REL-FC-01 | Listar todos os convênios + total faturado e total recebido por convênio no período. | Permite identificar inadimplência por operadora.                                    |
| CT-REL-FC-02 | Glosa: convênio pagou menos que o cobrado.                                           | Diferença lançada como Dedução no DRE. Histórico do paciente registra a glosa.      |
| CT-REL-FC-03 | Particular vs. Convênio.                                                             | Toggle ou filtro pra separar. Receita de particular costuma ter margem muito maior. |


### 10.4 Ticket Médio


| **\#**       | **Cenário**                      | **Resultado esperado**                                                                                              |
|--------------|----------------------------------|---------------------------------------------------------------------------------------------------------------------|
| CT-REL-TM-01 | Ticket médio por profissional.   | Total recebido do profissional ÷ nº pacientes atendidos. Não é nº atendimentos (paciente que veio 5× conta como 1). |
| CT-REL-TM-02 | Ticket médio geral da clínica.   | Receita ÷ pacientes únicos atendidos.                                                                               |
| CT-REL-TM-03 | Comparativo entre profissionais. | Permite identificar quem fecha planos mais caros.                                                                   |
| CT-REL-TM-04 | Filtrar por especialidade.       | Ticket médio de Ortodontia vs. Endodontia vs. Estética.                                                             |

11\. Caixa (abertura, fechamento, sangria, suprimento)

É o dinheiro físico que circula na recepção. No print: tela vazia com saldo de abertura R\$ 0,00 e botão Abrir Caixa. Tem aba “Caixa do Dia” e “Histórico”. Auditoria precisa cobrir o ciclo completo.


### 11.1 Ciclo do caixa



## 16. Abertura: recepcionista digita o valor que está na gaveta (saldo de abertura). Caixa fica Aberto.



## 17. Movimentação: durante o dia, recebimentos em dinheiro entram. Pagamentos pequenos (sangria) saem. Reforços (suprimento) podem ser adicionados.



## 18. Fechamento: recepcionista conta o dinheiro físico, sistema mostra saldo esperado, registra diferença (se houver). Caixa fica Fechado.



## 19. Histórico: caixas fechados ficam disponíveis para auditoria. Conferência por dia, por operador.



### 11.2 Casos de teste — Caixa


| **\#**   | **Cenário**                                                                | **Resultado esperado**                                                                                        |
|----------|----------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------|
| CT-CX-01 | Abrir caixa com R\$ 100 de troco.                                          | Status: Aberto. Saldo inicial registrado. Operador identificado.                                              |
| CT-CX-02 | Receber 3 parcelas em dinheiro durante o dia (R\$ 50 + R\$ 100 + R\$ 200). | Saldo do caixa: R\$ 100 + 350 = R\$ 450.                                                                      |
| CT-CX-03 | Sangria: tirar R\$ 200 do caixa (depositar no banco).                      | Saldo do caixa físico: R\$ 250. Saldo da conta destino +200. Movimento neutro no DRE (transferência interna). |
| CT-CX-04 | Suprimento: pegar R\$ 50 do banco e colocar no caixa para troco.           | Inverso da sangria.                                                                                           |
| CT-CX-05 | Fechamento: contar R\$ 245 no físico (deveria ser R\$ 250).                | Sistema registra diferença de −R\$ 5,00 (sobra/falta). Lançado como Despesa em “Quebra de Caixa”.             |
| CT-CX-06 | Tentar fechar caixa com parcelas pendentes do dia.                         | Aviso: “Há 2 parcelas em dinheiro do dia ainda em Pendente. Deseja confirmar?”                                |
| CT-CX-07 | Tentar lançar movimento em caixa fechado.                                  | Bloqueado. Mensagem: “Caixa do dia X está fechado. Reabra para lançar.”                                       |
| CT-CX-08 | Reabrir caixa fechado.                                                     | Permitido para perfis Admin/Gerente. Registra log: quem reabriu, quando, por quê.                             |
| CT-CX-09 | Histórico: filtrar caixas por operador.                                    | Filtra. Mostra valor de abertura, fechamento, diferença, status.                                              |
| CT-CX-10 | Imprimir resumo de fechamento.                                             | PDF com totais por forma de pagamento, sangrias, suprimentos, diferença.                                      |

*Observação importante: o Caixa só rastreia DINHEIRO FÍSICO. PIX, cartão e boleto não passam por aqui — vão direto para suas contas bancárias respectivas. Auditar isso para evitar dupla contagem.*

12\. Financeiro do paciente (dentro do prontuário)

Acessível pela aba Financeiro do prontuário (print 9 — paciente ACIR LISBOA). Cards: Total Aprovado, Pago/Recebido, Em Aberto, Devedor (Vencido), Crédito. Abaixo: 4 abas — Transações, Orçamentos, Plano de Tratamento, Recibos. Botões: Novo Orçamento, Receber Pagamento, Cobrar.


### 12.1 Cards de resumo do paciente


| **Card**          | **O que tem que somar**                                                                                                   |
|-------------------|---------------------------------------------------------------------------------------------------------------------------|
| Total Aprovado    | Σ de todos os orçamentos APROVADOS do paciente, com desconto aplicado.                                                    |
| Pago/Recebido     | Σ de parcelas Recebidas. Atualiza em tempo real ao dar baixa.                                                             |
| Em Aberto         | Σ de parcelas Pendentes ainda no prazo.                                                                                   |
| Devedor (Vencido) | Σ de parcelas Pendentes vencidas. Indicador de inadimplência do paciente.                                                 |
| Crédito           | Saldo positivo a favor do paciente (estornos não devolvidos, pré-pagamento). Pode ser usado para abater futuras parcelas. |

**Coerência: Total Aprovado = Pago + Em Aberto + Vencido + Estornado − Crédito.**


### 12.2 Casos de teste — Financeiro do paciente


| **\#**    | **Cenário**                                                            | **Resultado esperado**                                                                                                                                 |
|-----------|------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------|
| CT-PAC-01 | Paciente novo: criar Plano de Tratamento de R\$ 1.000 com 5% desconto. | Card Total Aprovado = R\$ 950 após aprovação. 1 ou N parcelas geradas conforme escolha.                                                                |
| CT-PAC-02 | Receber Pagamento direto pelo prontuário.                              | Mesmo modal de A Receber, com mesmas regras (data editável, valor parcial, etc.).                                                                      |
| CT-PAC-03 | Aba Transações: ver todas as parcelas do paciente.                     | Lista cronológica. Filtros: Todos, Pendentes, Pagos, Vencidos, Estornados.                                                                             |
| CT-PAC-04 | Aba Orçamentos: ver orçamentos aprovados, rejeitados, em análise.      | Permite reaproveitar orçamento rejeitado, gerar 2ª via.                                                                                                |
| CT-PAC-05 | Botão Cobrar: enviar lembrança de pagamento.                           | Abre modal com texto pronto, opção PIX/boleto, envio por WhatsApp/e-mail.                                                                              |
| CT-PAC-06 | Aba Recibos: gerar recibo de um pagamento.                             | PDF com dados do paciente, valor, data, descrição, CPF da clínica, assinatura digital opcional.                                                        |
| CT-PAC-07 | Status Adimplente / Inadimplente.                                      | Calculado automaticamente: tem alguma parcela vencida → Inadimplente. Status visível no header do prontuário.                                          |
| CT-PAC-08 | Crédito por estorno: paciente pagou, depois estornou metade.           | Crédito do paciente fica positivo no valor estornado. Próxima parcela pode ser abatida automaticamente (com confirmação).                              |
| CT-PAC-09 | Mudar forma de pagamento de um orçamento já aprovado.                  | ⚠ FUNCIONALIDADE FALHA NO SISTEMA ATUAL (vide cap. 13). Esperado: permitir editar parcelas que ainda não foram pagas, mantendo as já pagas como estão. |
| CT-PAC-10 | Excluir orçamento aprovado por engano.                                 | ⚠ FUNCIONALIDADE FALHA NO SISTEMA ATUAL. Esperado: bloquear se já houver parcela paga, permitir cancelar se tudo está pendente.                        |

13\. Bugs, limitações e fricções já reportadas

Esta seção consolida os problemas relatados pela equipe da clínica nas conversas. Cada item vira um cartão de bug com prioridade. Resolver TODOS antes de declarar a auditoria fechada.

| **ID** | **Prioridade** | **Problema relatado**                                                                                                                                                                           | **Correção esperada**                                                                                                                                                                                                                                                                   |
|--------|----------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| BUG-01 | CRÍTICA        | Não existe baixa parcial em parcela de Dinheiro/PIX. Orçamento de R\$ 920 com 3 parcelas de R\$ 306 — paciente paga R\$ 276 (valor diferente da parcela). O sistema não permite registrar isso. | No modal de Receber Pagamento, adicionar campo “Valor recebido” editável. Se \< parcela, gerar saldo a receber em nova parcela com data sugerida (próximo mês). Se \> parcela, lançar excedente como Crédito do paciente. Aplicar para Dinheiro, PIX e Boleto. Cartão segue automático. |
| BUG-02 | CRÍTICA        | Orçamento aprovado não pode ser editado nem excluído. Recepção lançou no PIX 1× e descobriu que paciente já tinha pago metade.                                                                  | Permitir editar parcelas Pendentes (forma, valor, vencimento). Bloquear edição apenas das já Recebidas. Permitir excluir orçamento se nenhuma parcela foi paga; senão, oferecer Cancelar (mantém histórico).                                                                            |
| BUG-03 | ALTA           | DRE mostra Var. % de 1713,0% quando período anterior era quase zero — número não tem significado prático.                                                                                       | Quando valor anterior \< 5% do atual, exibir “Novo” em vez de %. Quando = 0, exibir “—”.                                                                                                                                                                                                |
| BUG-04 | ALTA           | DRE consolida tudo em “Sem categoria” porque categorias não foram cadastradas.                                                                                                                  | Forçar criação de categorias mínimas no onboarding. Adicionar aviso no topo do DRE quando há lançamentos sem categoria, com botão direto para classificar.                                                                                                                              |
| BUG-05 | ALTA           | Ticket Médio aparece R\$ 0,00 mesmo com receita de R\$ 2.388.                                                                                                                                   | Verificar fórmula. Provavelmente está dividindo Receita por 0 (nº de pacientes únicos não está sendo contado). Mostrar “—” em vez de R\$ 0,00 quando indefinido.                                                                                                                        |
| BUG-06 | ALTA           | Saldo do Dia não está claro: a clínica não sabe se é dia atual, mês ou caixa total.                                                                                                             | Renomear cards: “Saldo do Dia” → “Resultado de Hoje”. “Saldo em Caixa” → “Saldo Disponível Hoje”. Adicionar tooltip explicativo em cada card.                                                                                                                                           |
| BUG-07 | MÉDIA          | Não há indicação visual clara de qual orçamento ainda permite edição.                                                                                                                           | Ícone de cadeado em orçamentos com pelo menos uma parcela paga. Hover: “Há R\$ X já recebidos. Estorne para editar.”                                                                                                                                                                    |
| BUG-08 | MÉDIA          | Importação da Clinicorp pode duplicar lançamentos.                                                                                                                                              | Implementar idempotência: usar ImportedId/CheckoutUuid para detectar registros já importados. Antes da importação real, gerar relatório de duplicidades possíveis.                                                                                                                      |
| BUG-09 | MÉDIA          | Sem distinção visual entre Dinheiro e PIX — Clinicorp gravava ambos como OTHER.                                                                                                                 | Na importação, marcar todos os OTHER como “Dinheiro” por padrão e oferecer reclassificação em massa por filtro de valor (ex.: valores acima de R\$ 200 → provável PIX).                                                                                                                 |
| BUG-10 | BAIXA          | Campo Inadimplência Total no Dashboard com indicador “100.0%” em vermelho mesmo sem inadimplência real.                                                                                         | Trocar % de variação por valor absoluto quando a base é zero ou pequena.                                                                                                                                                                                                                |
| BUG-11 | BAIXA          | Gráfico de Receita vs Meta Mensal mostra 0,0% sempre que meta não está cadastrada.                                                                                                              | Quando meta = 0, ocultar o gauge e mostrar CTA “Cadastre uma meta para acompanhar seu progresso” com link direto para Configurações.                                                                                                                                                    |
| BUG-12 | MÉDIA          | Não há logs de auditoria visíveis (quem editou, quando, o quê).                                                                                                                                 | Aba Auditoria já existe no prontuário do paciente — replicar para todas as ações financeiras (lançamento, edição, estorno, exclusão de despesa).                                                                                                                                        |

14\. Formas de pagamento — comportamento esperado

Cada forma de pagamento se comporta diferente. Esta seção é o manual interno para a recepção e ao mesmo tempo o roteiro para validar o sistema.


### 14.1 Dinheiro


| **Aspecto**   | **Comportamento**                                                                    |
|---------------|--------------------------------------------------------------------------------------|
| Confirmação   | Imediata, no momento da entrega física.                                              |
| Conta destino | Caixa físico (gaveta da recepção).                                                   |
| Parcelamento  | Sim — tipicamente várias parcelas semanais ou mensais (ex.: tratamento ortodôntico). |
| Baixa parcial | Obrigatória. Paciente pode pagar valor diferente da parcela combinada (ver BUG-01).  |
| Troco         | Permitir registrar valor pago \> valor devido, lançando troco como saída.            |
| Auditoria     | Conferência diária no fechamento de caixa físico.                                    |
| Recibo        | Sempre oferecer impressão/envio do recibo.                                           |


### 14.2 PIX


| **Aspecto**   | **Comportamento**                                                                                                                         |
|---------------|-------------------------------------------------------------------------------------------------------------------------------------------|
| Confirmação   | Quase imediata. Idealmente integrar com banco para confirmação automática (Sicredi, Itaú, BB têm API).                                    |
| Conta destino | Conta corrente PJ que tem o PIX cadastrado.                                                                                               |
| Parcelamento  | Não nativo — mas a clínica pode combinar pagamentos parcelados em PIX (ex.: 3× de R\$ 300 mensal).                                        |
| Baixa parcial | Sim, igual a Dinheiro.                                                                                                                    |
| QRCode        | Sistema deve gerar QRCode estático (chave PIX da clínica) ou dinâmico (com valor preenchido) para colar no totem ou enviar pelo WhatsApp. |
| Auditoria     | Conferir extrato bancário diário com lançamentos do sistema.                                                                              |


### 14.3 Cartão de Débito


| **Aspecto**   | **Comportamento**                                                                              |
|---------------|------------------------------------------------------------------------------------------------|
| Confirmação   | Imediata na maquininha. Geralmente D+1 na conta da clínica.                                    |
| Conta destino | Conta da credenciadora (Cielo, Stone, Rede, etc.) — pode ser modelada como “a receber em D+1”. |
| Parcelamento  | Sempre 1×. Se houver maquininha que parcele débito, é exceção.                                 |
| Taxa MDR      | Tipicamente 1,5% a 2,5%. Descontar do valor bruto antes de virar receita líquida.              |
| Baixa parcial | Não — débito é tudo ou nada. Se passou na máquina, foi tudo aprovado.                          |
| Auditoria     | Conferir relatório da credenciadora vs. lançamentos do sistema.                                |


### 14.4 Cartão de Crédito


| **Aspecto**   | **Comportamento**                                                                                                                                                          |
|---------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Confirmação   | Imediata na maquininha (autorização). Liquidação D+30 a D+90 dependendo do contrato.                                                                                       |
| Conta destino | Conta da credenciadora — modelada como “a receber em N parcelas”.                                                                                                          |
| Parcelamento  | 1× até 12× (ou mais). Cada parcela cai em mês diferente. SE for parcelado SEM JUROS para o paciente, a clínica é quem absorve o custo do parcelamento (taxa maior do MDR). |
| Taxa MDR      | 1× = 2,5% a 4% / 6× = 5% a 8% / 12× = 8% a 14% (depende do contrato e da bandeira). Sistema deve permitir cadastrar tabela de taxas por nº de parcelas.                    |
| Baixa parcial | Não. Sistema gera N parcelas a receber automaticamente, e cada uma é baixada quando a credenciadora paga.                                                                  |
| Antecipação   | Algumas clínicas antecipam recebíveis (vendem o direito de receber em N dias). Lançar como custo financeiro, não como desconto na receita.                                 |
| Estorno       | Crédito permite estorno integral em até 90 dias (chargeback). Sistema precisa lidar com isso.                                                                              |


### 14.5 Boleto Bancário


| **Aspecto**   | **Comportamento**                                                                                                                 |
|---------------|-----------------------------------------------------------------------------------------------------------------------------------|
| Confirmação   | D+1 ou D+2 após pagamento, via retorno bancário. Pode ser manual (recepção marca como pago) ou automático (integração com banco). |
| Conta destino | Conta corrente PJ que emite o boleto.                                                                                             |
| Parcelamento  | Sim, gerar carnê com N boletos (um para cada vencimento).                                                                         |
| Vencimento    | Configurável por boleto. Sistema deve lembrar quando vai vencer e quando venceu.                                                  |
| Juros e multa | Configurar regra padrão (ex.: 2% multa + 1% juros mensal). Aplicar automaticamente após data de vencimento.                       |
| 2ª via        | Permitir reemissão com novo vencimento se o paciente perdeu.                                                                      |
| Baixa parcial | Em geral o banco aceita. Sistema deve permitir registrar valor diferente do face do boleto.                                       |
| Auditoria     | Arquivo de retorno bancário (CNAB) deve ser processável pelo sistema, ou no mínimo importável manualmente.                        |


### 14.6 Convênio / Plano de saúde


| **Aspecto**               | **Comportamento**                                                                                                                                    |
|---------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------|
| Confirmação               | Demorada. Procedimento é executado, depois enviado em lote para o convênio, que paga em 30/45/60 dias após faturamento.                              |
| Conta destino             | Conta corrente PJ — convênio paga via TED ou crédito direto.                                                                                         |
| Faturamento por guia/lote | Sistema deve agrupar atendimentos por convênio + período, gerar lote para envio (XML TISS na odontologia/saúde).                                     |
| Glosa                     | Convênio pode pagar menos que o cobrado. Diferença vira Dedução. Possível recurso de glosa.                                                          |
| Coparticipação            | Algumas operadoras: paciente paga uma parte, convênio paga outra. Sistema deve separar as duas receitas.                                             |
| Tabela de procedimentos   | Cada convênio tem sua tabela de valores. Sistema deve permitir cadastrar tabela por convênio (Bradesco, Amil, Unimed, SulAmérica, Odontoprev, etc.). |

15\. Checklist final de auditoria

Use esta lista como controle. Marcar cada item ao validar. Se algum não passar, abrir bug com referência ao ID desta seção (ex.: CHK-08).

| **ID** | **Área**       | **Item**                                                                                                     |
|--------|----------------|--------------------------------------------------------------------------------------------------------------|
| CHK-01 | Configurações  | Categorias mínimas cadastradas (Receitas, Despesas Fixas, Custos Variáveis, Outras Despesas)                 |
| CHK-02 | Configurações  | Pelo menos 1 conta bancária + 1 caixa físico cadastrados                                                     |
| CHK-03 | Configurações  | Regra de comissão criada para cada profissional ativo                                                        |
| CHK-04 | Configurações  | Despesas recorrentes principais cadastradas (aluguel, sistema, internet)                                     |
| CHK-05 | Configurações  | Meta de receita mensal cadastrada                                                                            |
| CHK-06 | Migração       | Total de pacientes ativos = 2.407 (conferido em Pacientes)                                                   |
| CHK-07 | Migração       | Total recebido histórico = R\$ 445.025,75 (conferido em Fluxo de Caixa, sem filtro)                          |
| CHK-08 | Migração       | Total a receber histórico ≈ R\$ 92.769,15 (R\$ 537.794,90 lançado − R\$ 445.025,75 recebido)                 |
| CHK-09 | Migração       | Pagamentos parciais marcados (34 cabeçalhos com IsPartialPayment=X) revisados manualmente                    |
| CHK-10 | Migração       | Itens cancelados (67) NÃO aparecem em A Receber                                                              |
| CHK-11 | Migração       | PaymentItem com Type=OTHER reclassificados para Dinheiro/PIX                                                 |
| CHK-12 | Migração       | Importação idempotente — re-execução não duplica registros                                                   |
| CHK-13 | Dashboard      | Receita Líquida do mês = DRE Receita Líquida do mesmo período                                                |
| CHK-14 | Dashboard      | Lucro Líquido = DRE Lucro Líquido do mesmo período                                                           |
| CHK-15 | Dashboard      | A Receber A Vencer = soma dos pendentes futuros em A Receber                                                 |
| CHK-16 | Dashboard      | Ticket Médio mostra valor real (não R\$ 0,00 com receita \> 0)                                               |
| CHK-17 | Dashboard      | Inadimplência % calculada corretamente (sem 100% sem inadimplência real)                                     |
| CHK-18 | Fluxo de Caixa | Nova Entrada lança em Fluxo + atualiza saldo da conta + aparece em DRE                                       |
| CHK-19 | Fluxo de Caixa | Nova Saída lança em Fluxo + reduz saldo da conta + aparece em DRE                                            |
| CHK-20 | Fluxo de Caixa | Filtro de período afeta apenas Fluxo, não muda Saldo em Caixa                                                |
| CHK-21 | Fluxo de Caixa | Detalhamento por dia: soma das entradas = total de entradas                                                  |
| CHK-22 | Fluxo de Caixa | PDF gerado com cabeçalho da clínica e período correto                                                        |
| CHK-23 | Fluxo de Caixa | Botão Nova Entrada não duplica em duplo clique                                                               |
| CHK-24 | A Receber      | Total a Receber + Recebido bate com soma das parcelas não canceladas                                         |
| CHK-25 | A Receber      | Vencido = soma de Pendentes com data de vencimento \< hoje                                                   |
| CHK-26 | A Receber      | Filtros (descrição, período, forma, status) funcionam isoladamente e combinados                              |
| CHK-27 | A Receber      | Baixa de parcela atualiza Pago/Recebido em tempo real (5 efeitos: status, conta, fluxo, comissão, orçamento) |
| CHK-28 | A Receber      | Baixa parcial em Dinheiro/PIX/Boleto funciona (BUG-01)                                                       |
| CHK-29 | A Receber      | Edição de orçamento aprovado funciona para parcelas pendentes (BUG-02)                                       |
| CHK-30 | A Receber      | Estorno reverte os 5 efeitos da baixa                                                                        |
| CHK-31 | A Receber      | Renegociação cria novas parcelas referenciando a antiga                                                      |
| CHK-32 | A Pagar        | Despesa cadastrada aparece com status correto                                                                |
| CHK-33 | A Pagar        | Pagamento de despesa baixa saldo da conta + aparece no DRE na categoria certa                                |
| CHK-34 | A Pagar        | Despesa recorrente regenera no próximo mês automaticamente                                                   |
| CHK-35 | A Pagar        | Estorno de despesa paga devolve saldo                                                                        |
| CHK-36 | DRE            | Lançamento sem categoria gera AVISO destacado                                                                |
| CHK-37 | DRE            | Variação % não mostra valores absurdos (1713%) — usa “Novo” quando base = 0 (BUG-03)                         |
| CHK-38 | DRE            | Drill-down em cada categoria leva à lista de lançamentos                                                     |
| CHK-39 | DRE            | Comparação com período anterior é coerente (mês com mês)                                                     |
| CHK-40 | Caixa          | Abertura registra operador, data e saldo inicial                                                             |
| CHK-41 | Caixa          | Fechamento detecta diferença e a registra como quebra                                                        |
| CHK-42 | Caixa          | Caixa fechado bloqueia novos lançamentos retroativos sem reabertura                                          |
| CHK-43 | Caixa          | Sangria/suprimento são neutros no DRE                                                                        |
| CHK-44 | Relatórios     | Comissões: cálculo sobre RECEBIDO, não sobre orçado                                                          |
| CHK-45 | Relatórios     | Comissões: estorno de pagamento reverte comissão                                                             |
| CHK-46 | Relatórios     | Despesas por categoria: total = DRE Despesas + Custos                                                        |
| CHK-47 | Relatórios     | Ticket Médio por profissional usa pacientes únicos, não atendimentos                                         |
| CHK-48 | Paciente       | Total Aprovado = Pago + Em Aberto + Vencido + Estornado − Crédito                                            |
| CHK-49 | Paciente       | Status Adimplente/Inadimplente atualiza automaticamente                                                      |
| CHK-50 | Paciente       | Recibo gerado tem CPF/CNPJ da clínica e do paciente, valor por extenso                                       |
| CHK-51 | Auditoria      | Todas as ações financeiras geram log (quem, quando, o quê)                                                   |
| CHK-52 | Auditoria      | Permissões por perfil: recepção não exclui despesa, gerente sim                                              |
| CHK-53 | Geral          | Backup diário automático dos dados financeiros                                                               |
| CHK-54 | Geral          | Exportação completa em XLSX/CSV disponível para o contador                                                   |

16\. Conclusão e próximos passos sugeridos

Com base na análise dos dados exportados, das telas atuais e dos relatos da equipe, o módulo financeiro do Klivy tem uma estrutura visualmente bem-resolvida — Dashboard, Fluxo de Caixa, A Receber, A Pagar, DRE, Relatórios, Caixa e Configurações estão todos presentes. Os problemas concentram-se em três frentes:


## 20. Funcionalidades essenciais ausentes (BUGs 1 e 2 — críticos): ausência de baixa parcial e impossibilidade de editar orçamento aprovado. Esses dois bloqueiam o uso real para qualquer clínica que aceita pagamentos parcelados em dinheiro/PIX, que é o caso aqui.



## 21. Apresentação de dados confusa (BUGs 3, 5, 6, 10, 11): variações de % sem sentido, ticket médio zerado, nomenclatura ambígua. São polimentos importantes mas não bloqueiam operação.



## 22. Configuração incompleta (BUG-04 e dependentes): as categorias precisam ser cadastradas antes de qualquer importação, senão a DRE fica inutilizável. Isso é processo, não bug — incluir no onboarding.



### 16.1 Sequência recomendada de execução



## 23. SEMANA 1 — Configuração: cadastrar todas as categorias, contas bancárias, regras de comissão, despesas recorrentes e meta. Antes de qualquer importação.



## 24. SEMANA 2 — Bugs 1 e 2: solicitar correção urgente ao time Klivy. Sem isso, a clínica não consegue operar.



## 25. SEMANA 3 — Importação piloto: importar 1 mês da Clinicorp (abril/2026). Conferir total recebido vs. extrato bancário do mês. Validar 10 pacientes manualmente.



## 26. SEMANA 4 — Importação completa: rodar histórico inteiro. Conciliar com os totais da seção 1.1 deste documento.



## 27. SEMANA 5 — Auditoria funcional: rodar os 54 itens do checklist (cap. 15). Abrir bugs para cada item que falhar.



## 28. SEMANA 6 — Polimentos: BUGs 3, 5, 6, 10, 11. Treinamento da equipe.



## 29. SEMANA 7 — Operação plena com a Clinicorp ainda como backup somente leitura por 60 dias.



### 16.2 Riscos a monitorar


- Risco de duplicidade na importação — mitigar com idempotência (BUG-08).

- Risco de descontinuação de acesso à Clinicorp — exportar tudo enquanto há acesso, manter backups frios.

- Risco de equipe resistir ao novo sistema — treinamento prático com casos reais antes do go-live.

- Risco de perda de comissão histórica — antes da migração, gerar relatório de comissões pagas/devidas na Clinicorp e arquivar.

- Risco fiscal — envolver o contador da clínica desde a semana 1 para validar a estrutura de DRE.

*Documento elaborado para ser usado como roteiro vivo. Atualize as marcações da seção 15 conforme for validando. A coerência cruzada (Dashboard × Fluxo × DRE × A Receber) é o que dá confiança no sistema — se os números bateram em três telas diferentes, o módulo está saudável.*

*Boa auditoria.*
