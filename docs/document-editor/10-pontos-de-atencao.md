# 10 — Pontos de Atenção, Riscos & Tradeoffs

> O que pode dar errado, onde o time costuma tropeçar, e o que NÃO foi resolvido ainda nesse plano.

## 10.1 Infraestrutura — Chromium no servidor

**Risco**: Grover depende de Node + Puppeteer + Chromium. Em deploy, o ambiente do app precisa ter Chromium instalado e acessível.

**Sintomas comuns:**
- `Error: Failed to launch the browser process`
- `Could not find Chromium`
- Timeouts em produção (Chromium consome ~200MB RAM/instância)

**Mitigações:**
1. **Dockerfile**: adicionar `chromium` no `apt-get install`. Padrão:
   ```dockerfile
   RUN apt-get update && apt-get install -y \
       chromium \
       fonts-freefont-ttf \
       fonts-liberation \
       libnss3 libatk-bridge2.0-0 libdrm2 libxkbcommon0 libxcomposite1 \
       libxdamage1 libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2 \
       --no-install-recommends && rm -rf /var/lib/apt/lists/*
   ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
   ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
   ```
2. **Coolify/Kubernetes**: garantir RAM dedicada (mínimo +256MB sobre o worker base).
3. **Pool de instâncias**: Grover lança um Chromium por chamada. Pra alto volume, configurar `Grover.configure` com `launch_args` e reuso.
4. **Fontes**: Chromium minimal não tem fontes brasileiras (Helvetica, Arial). Garantir `fonts-liberation` ou embed das fontes no CSS do template.

**Plano B se Grover não funcionar**: usar **PrinceXML** (comercial, mas robusto) ou voltar pra **Prawn** (perde features visuais ricas).

## 10.2 Validação do JSON ProseMirror

**Risco**: usuário (ou bug do TipTap) salva JSON malformado → tela em branco no editor + crash no renderer.

**Mitigações:**
- Validação backend no `before_save` (já mostrado em 04-backend.md seção 4.10)
- Limite de bytes (500KB).
- Lista de bloqueio de node types (`script`, `iframe`, etc.).
- Sanitização do HTML final antes de mandar pro Grover (gem `sanitize` ou `Loofah`).
- Frontend: try/catch ao carregar, mostrar "documento corrompido — restaurar versão anterior".

## 10.3 Segurança — XSS no template

**Risco**: admin malicioso (ou template Klivy malformado) injeta `<script>` no HTML.

**Mitigações:**
- Renderer **escapa todo texto** com `ERB::Util.html_escape`.
- Variáveis nunca interpoladas como HTML cru (exceto `:image_tag` que gera tag controlada com URL validada).
- `Sanitize.fragment(html, Sanitize::Config::RELAXED)` no HTML final antes do Grover.
- CSP no PDF: Chromium roda offline (`display_url` configurado), sem JS executado.

## 10.4 LGPD — IA processando dado sensível (Fase 6+)

**Risco**: mandar `patient.cpf` + `patient.full_name` pra um modelo externo (Anthropic, OpenAI) é tratamento de dado pessoal sensível de saúde.

**Mitigações (quando IA entrar):**
- Contrato com fornecedor que **NÃO armazene dados** (Anthropic tem cláusula opt-out de treinamento — verificar e habilitar).
- **Anonimizar antes de enviar** quando possível (substituir nome real por placeholder no prompt).
- Logar tudo em audit trail (`audit_logged` já existe).
- Política de retenção: max 30 dias.
- DPA assinado com fornecedor.
- Atualizar Política de Privacidade da Klivy mencionando IA + fornecedor + finalidade.

## 10.5 Versionamento de template — impactos invisíveis

**Risco**: admin edita template publicado, profissional gera documento sem perceber que a versão mudou (e que o conteúdo é diferente do esperado).

**Mitigações:**
- `version` exibido visivelmente no header do editor e no card de template.
- `Document.rendered_html` é **a fonte da verdade** — uma vez gerado, é imutável.
- Tooltip no card: "última edição há 2h por Carlos" → admin avisa equipe que mudou.
- (Fase 2+) Sistema de "rascunho" — mudanças não vão pra produção até clicar "Publicar".

## 10.6 Schema atual do Patient/User pode faltar campos

**Risco**: o catálogo de variáveis em [07-catalogo-de-variaveis.md](07-catalogo-de-variaveis.md) lista campos como `User.council_number`, `Patient.responsible_name` que **podem não existir**.

**Ação obrigatória antes de iniciar a Fase 2:**

```bash
# Auditar:
rails runner 'puts Patient.columns.map(&:name)'
rails runner 'puts User.columns.map(&:name)'
```

Comparar com a tabela do catálogo. Pra cada campo faltante, decidir:
1. Adicionar via migration (campos institucionais do User como `council_number` provavelmente fazem sentido).
2. Mover pra `custom_attributes` JSONB existente (mais flexível, menos performático).
3. Remover a variável do catálogo MVP (Fase 2+).

## 10.7 Performance do editor com documento grande

**Risco**: contratos longos (~10 páginas, 5000+ caracteres) podem deixar o TipTap travado em máquina antiga do cliente.

**Mitigações:**
- Limite "soft" de 50.000 caracteres com warning.
- Debounce de autosave em 1.5-2s.
- Desabilitar extensões pesadas (Table) se documento não tiver tabela.
- Lazy-load do editor (`defineAsyncComponent` no Vue).

**Estado da arte**: TipTap aguenta 50+ páginas confortavelmente em laptop moderno. Problema real só em mobile/desktop antigo.

## 10.8 Hash SHA-256 — preparação Clicksign

**Decisão consciente**: já calculamos `pdf_hash` no MVP **antes** de integrar Clicksign.

**Por quê**: garantia de integridade desde dia 1. Se daqui a 3 anos um documento for contestado em juízo, a clínica consegue provar que o PDF arquivado é o mesmo que foi gerado.

**Não esquecer**:
- Salvar `pdf_hash` em coluna indexada.
- Validar `pdf_hash` ao reanexar/reler o arquivo (ex: backup → restore).

## 10.9 Imutabilidade do `rendered_html`

**Cuidado**: NUNCA atualizar `Document.rendered_html` depois de criado.

**Por quê**: se mudar, perde a integridade histórica. O documento já assinado/baixado pelo paciente deixa de bater com o registro.

**Como garantir**:
- `validate :rendered_html_immutability` no model.
- Audit log de qualquer tentativa de UPDATE nessa coluna.
- Trigger Postgres (futuro): `BEFORE UPDATE` rejeita mudança no campo.

## 10.10 Tradeoff: Pinia vs Vuex

**Verificar antes da Fase 1**: o projeto usa Vuex 4 (padrão Chatwoot). Pinia exige migração que está fora do escopo desta feature.

**Decisão**: usar **Vuex** mesmo que o resto do mundo recomende Pinia. Consistência > moderno.

## 10.11 i18n — internacionalização

**Risco esquecido**: Klivy é PT-BR hoje, mas se expandir, o catálogo de variáveis + templates Klivy precisam ser localizados.

**Mitigação MVP**: tudo em PT-BR mesmo, sem i18n nas strings do catálogo. Quando expandir, vira responsabilidade de migration separada (mover labels pra `config/locales/`).

## 10.12 Permissão "só admin" pode ser limitante

**Cuidado**: clínicas com 1 dentista + 1 recepcionista — o recepcionista (`agent`) não consegue mexer em templates.

**Mitigação**:
- Documentar isso na ajuda da feature.
- Fase 2: criar role "editor de documentos" customizada (a feature `custom_roles` já existe no plugin).

## 10.13 Onboarding — clínica vê tela vazia

**Risco**: nova clínica entra na aba "Documentos", vê **zero templates** próprios e os Klivy "lá em cima" — pode confundir.

**Mitigação**:
- Estado vazio com CTA grande: **"Comece copiando um modelo Klivy"** + botão que abre o drawer.
- Tour guiado opcional (Fase 4) — 3 popovers indicando: 1) modelos prontos, 2) editor, 3) usar no paciente.

## 10.14 Conflito de plugins ProseMirror

**Risco já mencionado** (5.1 do frontend): TipTap + `@chatwoot/prosemirror-schema` podem ter instâncias duplicadas → erros confusos tipo "RangeError: Schema mismatch".

**Solução documentada** (em 5.1) — testar localmente o quanto antes (Fase 0).

## 10.15 Custo de fila/storage

**Risco**: cada documento gerado adiciona:
- ~80KB de PDF (Active Storage / S3)
- ~10KB de `rendered_html` (Postgres)
- 1 row em `documents`

**Estimativa pra 1.000 clínicas × 200 docs/mês = 200.000 docs/mês**:
- Storage: 16 GB/mês × 12 = 192 GB/ano.
- Postgres: 2 GB/ano de `rendered_html`.

**Plano**: usar Active Storage com S3/R2 (provavelmente já configurado). Política de arquivamento depois de 5 anos (LGPD pede 5 anos pra dados de saúde).

## 10.16 Testes E2E são lentos com Chromium

**Risco**: testes que geram PDF real demoram 2-5s cada. Suite cresce, CI fica lento.

**Mitigação**:
- Marcar testes E2E de PDF como `slow: true` e rodar só em CI nightly.
- Em unit tests, **mockar** o Grover (`Grover.any_instance.stub(:to_pdf).and_return("fake")`).
- Testar a string HTML gerada (mais barato), assumir que Grover funciona.

## 10.17 Não foi resolvido neste plano

Esses pontos foram identificados mas **propositadamente fora do escopo** — precisam decisão futura:

1. **Comentários e revisão colaborativa** (ex: dentista comenta no contrato antes de finalizar). Não tem no MVP.
2. **Diff visual entre versões** do template — schema suporta (`version`), UI não.
3. **Templates compartilhados entre clínicas** do mesmo grupo (ex: rede de franquias). Hoje só conta sozinha.
4. **Multi-idioma** no documento (paciente estrangeiro).
5. **Assinatura digital ICP-Brasil** dentro do app (precisaria certificado A1/A3 do profissional — Clicksign cobre isso).
6. **Email/SMS de notificação** quando documento é gerado. Hoje WhatsApp manual.
7. **PDF/A para arquivamento permanente** (LGPD pede em alguns casos — Grover suporta mas precisa configurar).
8. **Watermark "RASCUNHO"** pra previews.

## 10.18 Decisões a confirmar ANTES de começar a Fase 1

- [ ] Schema do `Patient` tem todos os campos da seção 7.2? Se não, lista de migrations adicionais.
- [ ] Schema do `User` tem `council_number`, `specialty`? Senão, migrations.
- [ ] Logo da clínica é Active Storage attachment no `Account`? Onde está hoje?
- [ ] Custom_attributes do `Account` armazena CNPJ/endereço, ou tem colunas dedicadas?
- [ ] Padrão de store é Vuex 4 confirmado? (verificar `app/javascript/dashboard/store/index.js`)
- [ ] O sistema usa Pinia em alguma área nova ou tudo é Vuex?
- [ ] Versão do Vue (2 ou 3)? Estamos assumindo Vue 3 — confirmar no `package.json`.
- [ ] Deploy é Coolify (citado em `docs/guia_instalacao_coolify.md`) ou Heroku? Influencia Dockerfile.

> Esses pontos devem ser resolvidos numa primeira sessão de pair programming (~1h), antes de codar.

## 10.19 Saúde da feature pós-launch — métricas

Pra acompanhar se a feature está sendo adotada:

- % de clínicas que criaram ≥ 1 template em 30 dias do release
- % de documentos gerados via template novo (vs Prawn legado)
- Templates Klivy mais clonados (sinal do que vale priorizar nos próximos modelos)
- Erros de geração de PDF (rate de falha do Grover)
- Tempo médio de geração de PDF p50/p95/p99
- Tamanho médio dos PDFs gerados

Definir em Sentry/Grafana antes do go-live.

## 10.20 Lição aprendida importante

> **Não tente competir com Google Docs.** TipTap dá uma experiência ~80% boa. Tentar chegar a 100% (colaboração real-time, comentários, sugestões) vai consumir 10x mais esforço que toda a feature até aqui. **O valor está nas variáveis e na biblioteca de templates clínicos**, não no editor em si.

Quando aparecer o pedido "queremos colaborar tipo Google Docs", o roadmap diz: **não é o nosso jogo**. O jogo é **clínica gera documento certo, rápido, com integridade**.
