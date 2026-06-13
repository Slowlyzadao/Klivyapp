# Guia de importação — Clinicorp → Klivy/Salus

> Roteiro operacional para a equipe de migração.
>
> 11 arquivos a importar · 7 etapas sequenciais · ~14.000 registros financeiros · 2.559 pacientes a migrar.
>
> Convertido de: `Guia_Importacao_Clinicorp_Klivy.pdf`  
> Última atualização: maio de 2026

---

## 1. Visão geral
Este é o roteiro de execução da migração de dados da Clinicorp para o Klivy. Foi escrito para ser usado
por quem vai operar a importação — passo a passo, na ordem certa, com critérios claros de validação a
cada etapa.

A regra principal é simples: nunca pular etapa. Cada arquivo depende do anterior. Importar PaymentItem
antes de Patient, por exemplo, gera 2.283 parcelas órfãs sem dono. Importar Budgets antes de Dentist
gera 34 orçamentos sem profissional vinculado. A ordem foi desenhada para evitar exatamente essas
situações.

#### Quem deve executar

Operador técnico (TI da clínica ou consultor) — responsável por rodar a importação no Klivy, conferir os
filtros e marcar o checklist de cada etapa.

Aprovador (gestor da clínica ou Dra. Claudia) — confere os totais de conciliação ao final de cada etapa e
libera a próxima. Sem aprovação, não avançar.

#### Tempo estimado

Importação técnica: 4 a 6 horas de trabalho concentrado. Conciliação e validação: 2 a 3 dias úteis com
idas e vindas. Total entre o início da importação e o go-live confiável: 1 semana.

#### Antes de começar — backup obrigatório

Exportar todos os arquivos da Clinicorp uma segunda vez e guardar em pasta com data. Manter
acesso de leitura à Clinicorp por pelo menos 60 dias após o go-live. Se algo der errado e o dado
não estiver no Klivy, o original ainda está acessível.

#### Princípio da idempotência

Toda importação tem que poder ser rodada duas vezes sem duplicar registro. Se a primeira
tentativa falhar no meio, a segunda não pode criar pacientes em duplicidade. O Klivy precisa usar
ImportedId (Clinicorp) ou CheckoutUuid como chave de deduplicação. Antes de cada importação
real, rodar uma simulação (dry-run) e gerar relatório de duplicatas.

## 2. Pré-requisitos — antes de importar nada
As cinco configurações abaixo precisam estar populadas antes da etapa 1. Se a clínica importar
pacientes e pagamentos com a base de configuração vazia, todos os lançamentos vão cair em "Sem
categoria" no DRE — exatamente o que está acontecendo no estado atual do sistema.

# Configuração Onde O que cadastrar

1 Categorias financeiras Financeiro → Configurações → Categorias
Receitas (Particulares, Convênios, Cartão, Vendas, Outras), Despes

2 Contas bancárias Financeiro → Configurações → Contas
Pelo menos
Bancárias
1 conta corrente PJ + 1 caixa físico. Se houver maquinin

3 Despesas recorrentes Financeiro → Configurações → Despesas
Aluguel, Recorrentes
sistema, internet, telefone, contador. Defina dia de vencime

4 Convênios (se houver)Configurações → Convênios Cadastrar cada operadora atendida com tabela de valores própria

5 Metas de receita Financeiro → Configurações → Metas
Meta mensal, trimestral e anual — para o gauge do dashboard funcio

Regras de comissão ficam para depois do passo 1

A comissão precisa do DentistId de cada profissional. Como esse ID só passa a existir no Klivy
depois que o arquivo Dentist for importado (etapa 1), as regras de comissão são cadastradas logo
após a etapa 1 e antes da etapa 2.

## 3. As 7 etapas de importação
Cada etapa abaixo deve ser executada e validada antes de avançar para a próxima. Se a validação de
uma etapa falhar, parar, corrigir, e só então prosseguir.

Etapa O que importa Arquivo(s) Volume

1 Profissionais Dentist 9 dentistas

2 Templates de anamnese AnamnesisQuestions 44 perguntas em 3 templates

3 Pacientes Patient 2.559 cadastros

4 Anamneses preenchidas Anamnesis + PatientAnamnesis 30 anamneses · 600 respostas

5 Histórico clínico Appointment + TreatmentOperation 8.745 agendamentos · 9.638 procedimentos

6 Financeiro Budgets + PaymentHeader + PaymentItem
34 orçamentos · 1.805 cobranças · 2.283 parcela

7 Auditoria contábil (opcional) BookEntry 9.398 lançamentos

Profissionais
1 1 arquivo · 9 dentistas (8 ativos)

Por que primeiro? Appointment, Budgets e regras de comissão referenciam DentistId. Sem essa base,
todos os outros arquivos importam órfãos.

Arquivo Dentist.xlsx
Volume 9 profissionais (8 ativos, 1 deletado)

Depende de Nada — é o primeiro

Filtros / regras Filtrar Deleted=null se quiser importar só ativos. Conferir CRO, e-mail e CPF
(OtherDocumentId).

Como validar Lista de profissionais no Klivy mostra 8 nomes ativos: Daniele, Aline, Gustavo,
Guilherme, Maria Luisa, Giovana, Ironete e Cláudia.

✓ Ao terminar a etapa 1: cadastrar regras de comissão

Voltar em Financeiro → Configurações → Regras de Comissão e cadastrar uma regra para
cada profissional ativo. Sem isso, recebimentos importados não vão gerar comissão calculada
para o profissional. Definir: % sobre recebido (não sobre orçado), regra geral ou por especialidade.

Templates de anamnese
2 1 arquivo · 44 perguntas · 3 templates

Por que agora? As respostas de anamnese (etapa 4) referenciam o TemplateId. Importar respostas
antes do template gera órfãos.

Arquivo AnamnesisQuestions.xlsx
Volume 44 perguntas em 3 templates (YES_NO, DESC, OPTIONS)

Depende de Nada além da estrutura interna do Klivy

Filtros / regras Importar todos. Cada template vira um modelo de anamnese da clínica.

Como validar No Klivy: Configurações → Anamnese deve mostrar 3 modelos ("GENERAL",
"EXPERTISE" ou nomes equivalentes) com as perguntas certas em cada um.

Pacientes
3 1 arquivo · 2.559 cadastros (2.407 ativos)

Por que agora? É a base de tudo a partir daqui. Anamnese, agendamento, procedimento, orçamento e
pagamento — tudo aponta para PatientId.

Arquivo Patient.xlsx
Volume 2.559 cadastros (2.407 ativos · 151 deletados)

Depende de Nada (é a base)

Filtros / regras Importar todos, inclusive os Deleted=X (mas marcar como inativos no Klivy — preserva
histórico). Conferir nome, CPF (OtherDocumentId) e telefone (MobilePhone).

Como validar Em Pacientes do Klivy, total de ativos = 2.407. Buscar 5 pacientes específicos pelo
nome e conferir se vieram completos.

Atenção Atenção a duplicatas: se o mesmo paciente aparecer com dois CPFs ou um CPF
aparecer com dois nomes, marcar para revisão manual antes do go-live.

Anamneses preenchidas
4 2 arquivos · 30 anamneses · 600 respostas

Importação em duas sub-etapas: primeiro o cabeçalho da anamnese (4.1), depois as respostas
individuais (4.2). Inverter a ordem gera respostas órfãs.

4.1 — Anamnesis (cabeçalhos)
Arquivo Anamnesis.xlsx
Volume 30 anamneses (todas marcadas como CurrentAnamnesis=X)

Depende de Patient (etapa 3)

Filtros / regras Liga via Patient_PersonId. Importar todos.

Como validar Para cada um dos 30 pacientes com anamnese, abrir o prontuário no Klivy e confirmar
que aparece a aba Anamnese preenchida.

4.2 — PatientAnamnesis (respostas)
Arquivo PatientAnamnesis.xlsx
Volume 600 respostas individuais

Depende de Anamnesis (4.1) + AnamnesisQuestions (etapa 2)

Filtros / regras Liga via AnamnesisId (cabeçalho) e TemplateId (modelo). Importar todos.

Como validar Pegar 3 pacientes ao acaso e abrir a anamnese — todas as perguntas devem ter
resposta (Sim/Não/Texto), iguais às da Clinicorp.

Histórico clínico
5 2 arquivos · 8.745 agendamentos · 9.638 procedimentos

Por que agora? Esses dois arquivos enriquecem o prontuário do paciente com histórico de atendimentos
e procedimentos clínicos. Não dependem do financeiro, mas alimentam relatórios de produtividade.

5.1 — Appointment
Arquivo Appointment.xlsx
Volume 8.745 agendamentos (jul/2023 a jan/2027) · 346 cancelados

Depende de Patient + Dentist

Filtros / regras Importar todos. Manter status original (CONFIRMED, MISSED, CHECKOUT, etc.).
Cancelados devem ficar como "Cancelado" no Klivy, não sumir.

Como validar Filtrar agenda do Klivy por mês de jul/2023 — deve mostrar agendamentos. Total geral
= 8.745. Soma de cancelados = 346.

5.2 — TreatmentOperation
Arquivo TreatmentOperation.xlsx
Volume 9.638 procedimentos clínicos · 9.635 executados · 21 deletados

Depende de Patient

Filtros / regras Importar com Deleted=null. ProcedureCondition=EXECUTED é o normal.

Como validar Em prontuário do paciente, aba Evolução → Histórico de procedimentos deve mostrar
tudo que foi feito.

Atenção 9.637 dos 9.638 estão com DentistId vazio e Type nulo no arquivo exportado. Vão
importar como histórico genérico do paciente, sem profissional vinculado nem
categorização. Antes de prosseguir, conferir com a Clinicorp se há outra exportação
com esses campos preenchidos.

Financeiro
6 3 arquivos · 34 orçamentos · 1.805 cobranças · 2.283 parcelas

Etapa mais sensível. A integridade financeira da clínica depende dela. Importação em três sub-etapas —
qualquer inversão quebra o vínculo entre orçamento e pagamento.

6.1 — Budgets
Arquivo Budgets.xlsx
Volume 34 orçamentos · 58 procedimentos · R$ 24.650,83 · 16 pacientes

Depende de Patient + Dentist

Filtros / regras Importar só BudgetApproved=X e Executed=null (em andamento). Os já
executados/finalizados viram histórico só para referência.

Como validar Em A Receber do Klivy: filtrar por orçamentos abertos — deve aparecer pouco menos
de 34 (só os ainda em andamento). Conferir 3 pacientes que sabidamente têm
orçamento aberto.

6.2 — PaymentHeader
Arquivo PaymentHeader.xlsx
Volume 1.805 cabeçalhos · 1.764 confirmados · 39 deletados · 34 parciais

Depende de Patient + Budgets

Filtros / regras Filtrar Deleted=null (sobram 1.766). Marcar IsPartialPayment=X (34 cabeçalhos) para
revisão manual no Klivy.

Como validar Importou exatamente 1.766 cabeçalhos? Os 34 marcados como parciais aparecem em
uma lista de revisão?

Atenção Os 34 pagamentos parciais provavelmente são os casos do tipo "Manuele" — paciente
paga valor diferente da parcela combinada. Revisar manualmente um por um antes de
dar como concluído.

6.3 — PaymentItem
Arquivo PaymentItem.xlsx
Volume 2.283 parcelas · 1.920 recebidas · 67 canceladas · R$ 537.794,90 lançado · R$
445.025,75 recebido

Depende de PaymentHeader (6.2)

Filtros / regras Filtrar Canceled=null (sobram 2.216). Mapear coluna Type para forma de pagamento
Klivy (ver tabela abaixo).

Como validar Em Fluxo de Caixa, sem filtro de período: Total de Entradas = R$ 445.025,75 (± R$ 50
de arredondamento). Em A Receber: Total = R$ 537.794,90 − R$ 445.025,75 = R$
92.769,15.

Atenção A Clinicorp não distingue Dinheiro de PIX (ambos viram "OTHER" — 1.167 itens, 51%
do total). Marcar todos como "Dinheiro" por padrão e oferecer reclassificação em
massa por valor (acima de R$ 200 → provável PIX).

Mapeamento PaymentItem.Type → Klivy

Type (Clinicorp) Qtd Forma no Klivy

OTHER 1.167 (51%) Dinheiro (revisar para PIX nos valores altos)

CREDIT_CARD_EXTERNAL 717 (31%) Crédito (maquininha externa)

DEBIT_CARD_EXTERNAL 331 (15%) Débito (maquininha externa)

BOLETO_INTERNAL 38 (2%) Boleto

CREDIT_CARD_INTERNAL 30 (1%) Crédito (link/internal)

Auditoria contábil (opcional)
7 1 arquivo · 9.398 lançamentos

Por que opcional? O BookEntry é o razão contábil interno da Clinicorp — granularidade muito alta. Os
totais que ele representa já foram reconstruídos pelo PaymentItem da etapa 6. Importar como transação
geraria duplicidade.

Arquivo BookEntry.xlsx
Volume 9.398 lançamentos · 4.937 débitos · 4.461 créditos

Depende de —

Filtros / regras NÃO importar como transação. Guardar como arquivo de referência caso precise
rastrear de onde veio um saldo no futuro.

Como validar Manter o arquivo em pasta arquivada com nome
"BookEntry_Clinicorp_referencia_apenas.xlsx".

## 4. Conciliação final — números que precisam
bater
Depois das 7 etapas, antes de declarar a importação concluída e liberar o Klivy para a equipe, rodar essa
conciliação. Se um único número não bater, parar e investigar.

Indicador Valor esperado Onde conferir no Klivy

Profissionais ativos 8 Configurações → Profissionais

Templates de anamnese 3 Configurações → Anamnese

Pacientes ativos 2.407 Pacientes (filtro: ativos)

Pacientes com anamnese preenchida 30 Pacientes (filtro: anamnese ≥ 1)

Total de agendamentos 8.745 Agenda (sem filtro de período)

Procedimentos clínicos no histórico 9.617 Soma de evoluções dos pacientes

Orçamentos abertos ≤ 34 A Receber → filtro por orçamento

Cabeçalhos de cobrança 1.766 Total interno

Parcelas ativas 2.216 A Receber: pendentes + recebidas

Valor total lançado R$ 537.794,90 A Receber: Total a Receber + Recebido

Valor total recebido R$ 445.025,75 Fluxo de Caixa: Total de Entradas (sem filtro)

Saldo a receber líquido R$ 92.769,15 A Receber: Total a Receber

Itens cancelados 67 Histórico — NÃO podem aparecer em A Receber

Tolerância de arredondamento

Diferença de até R$ 50,00 em totais financeiros pode ser arredondamento. Diferença maior que
isso é bug de importação — investigar antes de seguir.

## 5. Plano de contingência — quando algo der
errado
Importações falham. A pergunta não é "se", é "quando". O plano abaixo descreve o que fazer em cada
cenário comum.

Cenário A — Falha no meio de uma etapa
Exemplo: importação de PaymentItem trava com 1.500 de 2.283 importados.

• Não tente continuar. Reverter a etapa inteira.
• Conferir log do Klivy para identificar a linha que travou.
• Corrigir o dado-problema no arquivo Excel original.
• Limpar a importação parcial (Klivy precisa ter função "desfazer última importação").
• Rodar a etapa do zero. A idempotência garante que isso não duplica os 1.500 já importados, mas,
por garantia, conferir total final.

Cenário B — Conciliação não bate
Exemplo: total recebido no Klivy é R$ 442.000, esperado R$ 445.025,75. Diferença de R$ 3.025,75 —
fora da tolerância.

• Não declarar importação concluída.
• Filtrar PaymentItem original por mês e conferir mês a mês onde está a diferença.
• Casos típicos: itens cancelados que vieram como ativos, parcelas duplicadas, OTHER mapeado
errado.
• Corrigir a origem e re-rodar somente os meses com problema.

Cenário C — Pacientes duplicados aparecem após importação
Exemplo: "Maria Silva" aparece duas vezes na busca, com mesmo CPF.
• Não excluir manualmente — você perde o histórico de um dos dois.
• Usar função "Mesclar pacientes" do Klivy (verificar se existe; se não, abrir bug).
• Conferir se o problema vem do arquivo original (mesmo CPF com 2 IDs).

Cenário D — Reverter tudo (worst case)
Quando voltar atrás é mais barato que corrigir.

• Solicitar ao Klivy reset completo da base.
• Confirmar que os arquivos Excel originais estão íntegros na pasta de backup.
• Reiniciar do passo 0 (pré-requisitos).
• Avisar a clínica que o go-live atrasa pelo menos 1 semana.

Acesso à Clinicorp ainda como rede de segurança

Manter login da Clinicorp ativo (modo somente leitura) por pelo menos 60 dias após o go-live. Se
um dado sumir no Klivy, a fonte original ainda está acessível para conferência.

## 6. Checklist de execução
Marcar conforme avança. Sem todas as caixas marcadas, não declarar a migração concluída.

Etapa 0 — Pré-requisitos
Backup duplo dos 11 arquivos Excel da Clinicorp em pasta com data

Categorias financeiras cadastradas (Receitas, Despesas Fixas, Custos Variáveis, Outras)

Pelo menos 1 conta corrente PJ + 1 caixa físico cadastrados

Despesas recorrentes principais cadastradas (aluguel, sistema, internet)

Convênios cadastrados (se houver)

Metas de receita mensal/trimestral/anual cadastradas

Acesso à Clinicorp em modo leitura confirmado para os próximos 60 dias

Etapas 1 a 7 — Importação
Etapa 1 concluída: Dentist importado, 8 ativos visíveis no Klivy

Regras de comissão cadastradas para cada profissional ativo

Etapa 2 concluída: 3 templates de anamnese visíveis em Configurações

Etapa 3 concluída: 2.407 pacientes ativos visíveis em Pacientes

Etapa 4.1 concluída: 30 anamneses cabeçalho importadas

Etapa 4.2 concluída: 600 respostas importadas, conferidas em 3 pacientes-amostra

Etapa 5.1 concluída: 8.745 agendamentos visíveis na agenda

Etapa 5.2 concluída: histórico de procedimentos visível nos prontuários

Etapa 6.1 concluída: ≤ 34 orçamentos abertos visíveis em A Receber

Etapa 6.2 concluída: 1.766 cabeçalhos importados, 34 marcados para revisão

Etapa 6.3 concluída: 2.216 parcelas importadas, OTHER mapeado para Dinheiro/PIX

Etapa 7: BookEntry arquivado como referência (não importado como transação)

Conciliação final
Total de Entradas no Fluxo de Caixa = R$ 445.025,75 (± R$ 50)

Saldo a Receber = R$ 92.769,15 (± R$ 50)

Itens cancelados (67) NÃO aparecem em A Receber

Pagamentos parciais (34) revisados manualmente um a um

DRE não tem mais lançamentos em "Sem categoria"

5 pacientes-amostra conferidos manualmente: dados, anamnese, histórico e financeiro corretos

Aprovador (gestor da clínica) assinou conciliação final

Pós go-live
Treinamento da recepção sobre baixa de pagamento e A Receber realizado

Treinamento dos profissionais sobre prontuário e plano de tratamento realizado

Período de paralelo (Klivy + Clinicorp) definido (sugestão: 30 dias)

Auditoria pós go-live agendada para 30, 60 e 90 dias

Boa importação. Se um item do checklist falhar, parar e investigar — não avançar pulando etapa.

