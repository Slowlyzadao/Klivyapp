# Teste Visual do Financeiro — Roteiro para a Equipe da Clínica

> Roteiro **passo a passo** para a recepção, dono da clínica ou time de produto validar visualmente o módulo financeiro antes de usar com pacientes reais.
>
> **Tempo estimado:** 30 a 45 minutos
> **Não precisa conhecimento técnico** — só seguir os passos e marcar o que viu.
> **Não vai apagar nada importante** — testes feitos em uma conta de testes ou com pacientes de exemplo.

---

## Antes de começar

### O que você precisa
- [ ] Computador com navegador moderno (Chrome, Firefox, Edge ou Safari atualizado)
- [ ] Login de **Administrador** na sua conta Klivy
- [ ] **1 paciente cadastrado** (pode ser um real ou criar um "Paciente Teste")
- [ ] **15 minutos sem interrupção** para fazer o fluxo principal

### Como marcar o resultado
Cada passo tem uma caixa **[ ]** ao lado. Quando o passo der certo, marque **[x]**. Se algo estranho acontecer, anote do lado.

> 💡 **Dica:** abre este documento numa aba e o Klivy noutra, vai alternando.

---

## 🏁 Etapa 1 — Primeira impressão do Dashboard

### O que fazer

1. Faça login no Klivy
2. No menu lateral à esquerda, clique em **Financeiro**
3. Você cairá na tela **Dashboard**

### O que conferir

- [ ] 1.1 — A tela abre **sem erro** (não fica branca, não trava)
- [ ] 1.2 — Lá em cima à direita tem 5 botões: **Semana · Mês · Trimestre · Ano · Todos**
- [ ] 1.3 — O botão **Mês** está azul (selecionado por padrão)
- [ ] 1.4 — Aparece o mês atual (ex: "05/2026") com setinhas pra navegar
- [ ] 1.5 — No topo direito tem os botões verdes/vermelhos: **Nova entrada** e **Nova saída**

### Blocos que devem aparecer (em ordem, descendo a tela)

- [ ] 1.6 — **HOJE** com 2 cards: "Resultado de Hoje" + "Saldo Disponível Hoje"
- [ ] 1.7 — **MÊS · 05/2026** com 4 cards: Receita Bruta, Despesa, Lucro Líquido, Ticket Médio
- [ ] 1.8 — **VENCIMENTOS · 05/2026** com 4 cards: A Receber, Vencido, A Pagar, A vencer em 3 dias
- [ ] 1.9 — **META** com gauge verde mostrando o % atingido
- [ ] 1.10 — **ANÁLISES** com 2 gráficos lado a lado (Fluxo + Composição)
- [ ] 1.11 — Mais 2 gráficos (Aging + Receita por Profissional)
- [ ] 1.12 — **PREVISÕES E TENDÊNCIAS** com 2 gráficos (Projeção + Tendência Inadimplência)

### 🎨 Visual

- [ ] 1.13 — Cores agradáveis (azul, verde, vermelho usados com sentido — não vibrante demais)
- [ ] 1.14 — Letras legíveis (sem nada cortado)
- [ ] 1.15 — Em todos os valores R$, o separador de milhar aparece com **ponto**: ex: `R$ 1.234,56` (e NÃO `R$ 1234,56`)

---

## 🔘 Etapa 2 — Brincar com os filtros de período

### O que fazer

1. Ainda no Dashboard, clique em **Semana** no topo
2. Veja a tela toda recarregar com dados diferentes

### O que conferir

- [ ] 2.1 — O botão **Semana** ficou azul
- [ ] 2.2 — O label do meio mostra algo tipo "11/05 – 17/05/2026"
- [ ] 2.3 — Os números dos cards mudaram (valores menores, é só uma semana)
- [ ] 2.4 — O título da seção de meta mudou para "**Meta de receita mensal**" ou similar

3. Clique em **Trimestre**
- [ ] 2.5 — Label vira "T2/2026" (ou T1/T3/T4 conforme o mês)
- [ ] 2.6 — Título da meta vira "**Meta de receita trimestral**"

4. Clique em **Ano**
- [ ] 2.7 — Label vira "2026"
- [ ] 2.8 — Título da meta vira "**Meta de receita anual**"

5. Clique em **Todos**
- [ ] 2.9 — Label vira "Todo o período"
- [ ] 2.10 — As setinhas (◀ ▶) ficam **acinzentadas** (desabilitadas — não tem como navegar fora de "todo")

6. Clique em **Mês** de novo (voltar ao padrão)
- [ ] 2.11 — Volta ao mês atual
- [ ] 2.12 — As setinhas voltam ao normal

---

## 📈 Etapa 3 — Olhar os gráficos com mais carinho

### O que fazer

1. Role a página até a seção **ANÁLISES**

### O que conferir em cada gráfico

#### **Fluxo de Caixa Diário** (gráfico de linha com 3 cores)

- [ ] 3.1 — Tem 3 linhas: verde (Entradas), vermelha (Saídas), azul tracejada (Saldo acumulado)
- [ ] 3.2 — Eixo de baixo mostra datas (ex: "10/05", "12/05", "14/05"...)
- [ ] 3.3 — Eixo da esquerda mostra valores em R$ (ex: "R$ 5.0k", "R$ 10.0k")
- [ ] 3.4 — Passa o mouse em cima de um ponto → aparece **tooltip preto** com valores formatados (ex: `R$ 1.234,56` com ponto separador)
- [ ] 3.5 — Embaixo do gráfico tem a legenda: ▢ Entradas · ▢ Saídas · ▢ Saldo acumulado

#### **Composição de Receita** (rosquinha)

- [ ] 3.6 — Tipo "donut" (rosquinha) com vazado no meio
- [ ] 3.7 — No meio aparece "Total · R$ X.XXX,XX"
- [ ] 3.8 — Do lado direito tem uma legenda com as categorias e valores
- [ ] 3.9 — Passa o mouse → mostra "Categoria: R$ X · X.X%"

#### **Aging Inadimplência** (barras horizontais)

- [ ] 3.10 — Tem 4 barras: 1-30 dias, 31-60, 61-90, 90+
- [ ] 3.11 — Cores vão de amarelo→laranja→vermelho conforme atraso
- [ ] 3.12 — Se a clínica não tem inadimplência, mostra "Tudo em dia ✅"

#### **Receita por Profissional** (barras horizontais azuis)

- [ ] 3.13 — Mostra até 5 profissionais (os que mais geraram receita)
- [ ] 3.14 — Barras azuis cor da marca
- [ ] 3.15 — Tooltip mostra "R$ valor · ticket médio R$ X"

#### **Projeção de Fluxo de Caixa** (linha azul tracejada)

- [ ] 3.16 — Subtítulo diz "Próximos 60 dias · saldo final estimado R$ X"
- [ ] 3.17 — Se em algum dia o saldo previsto ficar negativo, aparece um **alerta amarelo** no topo do gráfico

#### **Tendência de Inadimplência** (linha vermelha)

- [ ] 3.18 — Mostra 12 meses
- [ ] 3.19 — No canto direito tem um badge: "**Piorando**" (vermelho), "**Estável**" (cinza) ou "**Melhorando**" (verde)

---

## 🧑‍⚕️ Etapa 4 — Aba Financeiro do paciente

> Esta é a tela que a recepção mais vai usar no dia a dia. Vamos cobrar e receber pagamento.

### O que fazer

1. No menu lateral, clique em **Pacientes**
2. Abra um paciente qualquer (ou crie "Paciente Teste")
3. No prontuário, clique na aba **Financeiro** (ícone $ no menu lateral do prontuário)

### O que conferir na entrada

- [ ] 4.1 — A aba abre sem erro
- [ ] 4.2 — Aparecem **5 cards** no topo: Total Aprovado · Pago/Recebido · Em Aberto · Devedor (Vencido) · Crédito
- [ ] 4.3 — Se o paciente é novo, todos os cards mostram **R$ 0,00**
- [ ] 4.4 — No canto direito tem 3 botões: **Imprimir Extrato · Novo Lançamento · Receber Pagamento**

### Cobrar — criar orçamento simples

5. Clique em **Cobrar** ou **Novo Lançamento** (verde grande no topo)
6. Modal abre — preenche:
   - Item: "Consulta de teste"
   - Valor: 250
   - Profissional: escolhe qualquer um
   - Forma de pagamento: **PIX**
   - Parcelas: 1
7. Clica **Salvar**

### O que conferir

- [ ] 4.5 — Modal abriu lisinho, sem trambolho visual
- [ ] 4.6 — Quando você seleciona **PIX**, o ícone que aparece é o **logo oficial do PIX** (verde/turquesa, "ondinha"), NÃO um QR code genérico
- [ ] 4.7 — Após salvar, toast verde "Orçamento criado" aparece
- [ ] 4.8 — O card "Total Aprovado" agora mostra **R$ 250,00**
- [ ] 4.9 — O card "Em Aberto" também mostra **R$ 250,00**
- [ ] 4.10 — Lá embaixo aparece o orçamento criado com status "EM ABERTO" (badge laranja/amber)

### Receber o pagamento

8. Agora clica em **Receber Pagamento**
9. Modal abre listando a parcela
10. Selecionar a parcela
11. Forma: **PIX** (de novo, confere se o ícone PIX SVG aparece selecionado com borda verde)
12. Valor recebido: 250
13. Data: hoje
14. Conta destino: a conta padrão da clínica
15. **Confirmar**

### O que conferir

- [ ] 4.11 — Modal de receber pagamento abre certinho
- [ ] 4.12 — A opção PIX selecionada tem fundo verde-claro com **anel/borda verde** (não fica "invisível")
- [ ] 4.13 — Após confirmar, toast verde "Pagamento registrado"
- [ ] 4.14 — Card "Pago/Recebido" agora mostra **R$ 250,00**
- [ ] 4.15 — Card "Em Aberto" volta para **R$ 0,00**
- [ ] 4.16 — A parcela na lista vira **PAGO** (badge verde)

### Imprimir extrato

16. Clica em **Imprimir Extrato** (canto superior direito)
17. Aguarda 1-2 segundos

### O que conferir

- [ ] 4.17 — Um PDF abre (ou baixa) com o extrato do paciente
- [ ] 4.18 — PDF tem: nome do paciente, lista das parcelas, datas, valores, formas de pagamento
- [ ] 4.19 — Cabeçalho com nome da clínica
- [ ] 4.20 — Layout limpo, sem letra cortada

---

## 💰 Etapa 5 — Conferir no Fluxo de Caixa

### O que fazer

1. No menu lateral, clique em **Financeiro** → **Fluxo de Caixa**

### O que conferir

- [ ] 5.1 — Tela abre listando as movimentações
- [ ] 5.2 — Aparece a movimentação do pagamento que você acabou de receber (R$ 250 entrada)
- [ ] 5.3 — A linha mostra: data, descrição, **badge verde "Receita"**, categoria, conta, paciente, valor com `+`
- [ ] 5.4 — No topo: cards de **Saldo Total · Entradas no Período · Saídas no Período · Resultado Líquido**
- [ ] 5.5 — Os 3 botões de filtro: **Todos · Entradas · Saídas** funcionam (clica em "Entradas" → só aparecem as entradas)
- [ ] 5.6 — Tem um botão **Filtros** no canto direito que abre um painel lateral com filtros avançados

### O que NÃO deve aparecer

- [ ] 5.7 — Nenhum valor com formatação errada (ex: `R$ 250` sem casas decimais, ou `R$ 250,00,00` duplicado)
- [ ] 5.8 — Nenhuma linha "fantasma" ou texto em inglês escapado

---

## 📊 Etapa 6 — Conferir no DRE

### O que fazer

1. No menu lateral: **Financeiro → DRE**

### O que conferir

- [ ] 6.1 — Aparece o seletor de período (igual ao Dashboard: Semana/Mês/Trimestre/Ano/Todos)
- [ ] 6.2 — A página mostra 4 sections grandes que dá pra **expandir/recolher** clicando:
  - Receita Bruta
  - Custos Variáveis
  - Despesas Fixas
  - Outras Despesas
- [ ] 6.3 — Cada section mostra um total à direita
- [ ] 6.4 — Tem uma section "RESUMO" embaixo com a fórmula contábil:
  - Receita Bruta
  - (–) Deduções
  - = Receita Líquida
  - (–) Custos Variáveis
  - = Margem Bruta
  - (–) Despesas Fixas
  - = EBITDA
  - (–) Outras Despesas
  - = **Lucro Líquido**

- [ ] 6.5 — Os números batem (Lucro Líquido = Receitas - Despesas)
- [ ] 6.6 — Se houver lançamentos sem categoria, aparece um **alerta amarelo** no topo: "X lançamentos sem categoria · Reclassificar"

---

## 🧹 Etapa 7 — Reclassificar (organizar a casa)

### O que fazer

1. Menu lateral: **Financeiro → Reclassificar**

### O que conferir

- [ ] 7.1 — Tela abre com 3 cards no topo: **Sem categoria · Total Entradas · Total Saídas**
- [ ] 7.2 — Lista de lançamentos sem categoria aparece (se tiver algum)
- [ ] 7.3 — Cada linha tem checkbox + descrição + valor + paciente + ação
- [ ] 7.4 — Filtros de **Todos · Entradas · Saídas** + busca + datas funcionam
- [ ] 7.5 — Marcando vários checkboxes, aparece uma **barra azul** embaixo com "Aplicar categoria"

---

## ⚙️ Etapa 8 — Configurações

### O que fazer

1. Menu lateral: **Financeiro → Configurações**

### O que conferir

- [ ] 8.1 — Tela abre com **5 abas em cima**: Categorias · Contas e Caixa · Comissões · Despesas Recorrentes · Metas
- [ ] 8.2 — Cada aba abre sua tela própria
- [ ] 8.3 — Botão **+ Nova [item]** funcionando em cada aba
- [ ] 8.4 — Clicar para **excluir** um item abre um **modal de confirmação bonitinho** com ícone vermelho de alerta (NÃO um popup feio do navegador tipo "Tem certeza?")

### Aba Metas — confirmar que aceita 3 tipos

- [ ] 8.5 — Tem 3 cards: **Meta mensal · Meta trimestral · Meta anual**
- [ ] 8.6 — Cada card permite cadastrar separadamente
- [ ] 8.7 — Após salvar, a meta vira "1 meta cadastrada" no rodapé do card

---

## 🔍 Etapa 9 — A Receber + A Pagar (rápido)

### A Receber

1. Menu: **Financeiro → A Receber**
- [ ] 9.1 — Lista de parcelas pendentes aparece
- [ ] 9.2 — KPIs no topo: Total a Receber, Vencido, A vencer 7 dias
- [ ] 9.3 — Cada linha mostra: paciente, valor, vencimento, status (PENDENTE/VENCIDO/PAGO)
- [ ] 9.4 — Botão "Cobrar" em cada linha pendente

### A Pagar

2. Menu: **Financeiro → A Pagar**
- [ ] 9.5 — Lista de despesas
- [ ] 9.6 — Se você não cadastrou nenhuma, aparece estado vazio amigável
- [ ] 9.7 — Botão **+ Nova saída avulsa** funciona

---

## 📜 Etapa 10 — Auditoria + Backups + Contador

### Auditoria

1. Menu: **Financeiro → Auditoria**
- [ ] 10.1 — Lista de ações feitas no sistema (criou orçamento, recebeu pagamento, etc)
- [ ] 10.2 — Filtros por entidade, ação, usuário, período
- [ ] 10.3 — Clicar numa linha abre um painel ao lado mostrando "antes vs depois" da mudança

### Backups

2. Menu: **Financeiro → Backups**
- [ ] 10.4 — Lista de backups criados (data, tamanho, status)
- [ ] 10.5 — Botão "**Rodar backup agora**" funciona (mostra spinner, depois aparece o novo backup na lista)
- [ ] 10.6 — Cada backup tem opção de **excluir** com modal de confirmação

### Contador

3. Menu: **Financeiro → Contador**
- [ ] 10.7 — Tela de exportação com seletor de período
- [ ] 10.8 — Botão **Pré-visualizar** mostra contadores
- [ ] 10.9 — Botão **Baixar CSVs** baixa 4 arquivos `.csv` (recibos, despesas, etc)

### LGPD

4. Menu: **Financeiro → LGPD**
- [ ] 10.10 — Tela de solicitações de anonimização
- [ ] 10.11 — Botão **Nova solicitação** abre modal com busca de paciente
- [ ] 10.12 — Solicitações aparecem com status (Pendente / Aprovada / Executada)

---

## 🎯 Etapa 11 — Caixa físico (só se a clínica usar dinheiro em espécie)

### O que fazer

1. Menu: **Financeiro → Caixa**

### Se a clínica NÃO usar dinheiro físico

- [ ] 11.1 — Aparece estado vazio: "Selecione um caixa" → "Nenhum cadastrado"
- [ ] 11.2 — Mensagem clara explicando que precisa cadastrar conta tipo "Caixa físico" antes
- ✅ Pode pular o resto desta etapa

### Se a clínica USA dinheiro físico

3. Cadastrar a conta tipo "Caixa físico" em Configurações → Contas e Caixa primeiro
4. Voltar nesta tela e selecionar o caixa
5. Clicar **Abrir sessão**, valor inicial R$ 50 (troco)

- [ ] 11.3 — Sessão abre, aparece relógio "Aberto às HH:MM"
- [ ] 11.4 — Botões aparecem: Sangria · Suprimento · Fechar sessão
- [ ] 11.5 — Ao fechar, sistema pede "Quanto dinheiro tem no caixa físico agora?" e compara com o esperado

---

## ✅ Etapa 12 — Sanity check final

### Volte ao Dashboard e confira o resumo

- [ ] 12.1 — Os R$ 250 que você recebeu aparecem em "Hoje · Entradas"
- [ ] 12.2 — A Receita Bruta do mês incrementou
- [ ] 12.3 — Lucro Líquido positivo
- [ ] 12.4 — O gráfico Fluxo de Caixa Diário tem um pontinho verde hoje
- [ ] 12.5 — A meta percentual subiu um pouquinho

### Volte ao prontuário do mesmo paciente

- [ ] 12.6 — Os 5 cards do paciente refletem o estado correto:
  - Total Aprovado: R$ 250
  - Pago: R$ 250
  - Em Aberto: R$ 0
  - Devedor: R$ 0
  - Crédito: R$ 0

---

## 🚨 O que reportar se algo der errado

Anote no formato:

| Etapa | O que aconteceu | Captura de tela? |
|---|---|---|
| 4.6 | O ícone PIX apareceu como QR code, não a logo oficial | sim, anexo |
| 6.5 | DRE mostrou Lucro Líquido R$ -50.000 (impossível) | sim |

E manda pro time de desenvolvimento (Danilo / suporte).

---

## 📋 Resumo executivo (pra finalizar)

Conte quantos **[x]** marcou e quantos ficaram **[ ]**.

```
Total de checkpoints: ~110
Marcados PASS:        ___ / 110
Bugs encontrados:     ___
Bloqueios pra usar:   ___ (críticos)
```

**Critério de aprovação para uso real:**
- ✅ **OK pra produção** — se ≥ 95% PASS e zero bug crítico
- ⚠️ **Esperar correção** — se algum bug crítico (botão que não funciona, valor errado em R$, tela que não abre)
- 🔧 **OK com ressalva** — se bugs cosméticos (cor errada, texto cortado) — anota e usa, conserta depois

---

## ❓ Perguntas comuns

**"Quanto tempo isso vai me tomar?"**
Sério: 30-45 minutos se tudo der certo. Se tropeçar em alguma tela, anota e continua.

**"Preciso saber programação?"**
Não. Só seguir os passos e olhar a tela.

**"Posso fazer isso com paciente real?"**
Pode, **mas é melhor com um Paciente Teste** porque você vai mexer em valores que aparecem em relatório. Crie "Maria Teste · CPF 000.000.000-00" antes.

**"E se eu fizer errado e estragar algo?"**
Não tem como estragar. Tudo o que você criar pode ser excluído ou estornado. E todas as ações ficam registradas em **Auditoria**.

**"Preciso fazer tudo de uma vez?"**
Não. Pode parar na Etapa 4 (paciente core) e continuar amanhã. O importante é fazer pelo menos 1-4 antes de operar de verdade.

---

Boa testagem! 🚀 Qualquer dúvida, chama o Danilo.
