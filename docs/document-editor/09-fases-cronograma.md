# 09 — Fases & Cronograma

> Estimativas baseadas em programar **em par com IA** (Claude Code) — autor escreve direção, IA escreve código, autor revisa. **1 "dia útil de IA" = ~6h focadas** (não 8h, descontando reuniões/intervalos). As estimativas pressupõem: codebase já mapeado (✅ feito neste plano), sem reuniões longas, sem refactoring grande em paralelo, ambiente local funcionando.

## 9.1 Visão das fases

| Fase | Nome | Foco | Duração estimada | Bloqueia produção? |
|---|---|---|---|---|
| **0** | Preparação | Infra, gem Grover, sidebar | 1-2 dias | Não — só prepara terreno |
| **1** | Fundação (MVP base) | Plugin + Editor + CRUD templates | 5-7 dias | É o que vai pra produção |
| **2** | Migração & Catálogo Klivy | 22 templates Klivy, conversão Prawn→JSON | 3-4 dias | Sim — sem isso a feature não tem valor pra clínica nova |
| **3** | Integração com paciente | Modal "Gerar Documento" usando templates novos | 2-3 dias | Sim — sem isso a feature está isolada |
| **4** | Polimento + QA | Testes E2E, edge cases, performance, UX details | 2-3 dias | Sim — qualidade pra produção |
| | **TOTAL MVP** | | **13-19 dias úteis** (~3-4 semanas) | |
| **5** | Assinatura Clicksign | Integração ativa com Clicksign + portal paciente | 4-6 dias | Pós-MVP |
| **6** | IA — Geração de minuta | Claude API "descreva contrato → JSON ProseMirror" | 5-7 dias | Pós-MVP |
| **7** | IA — Revisão LGPD | Detecção automática de risco | 4-5 dias | Pós-MVP |
| **8** | IA — Autopreenchimento | Cruzamento com prontuário | 3-4 dias | Pós-MVP |

## 9.2 Fase 0 — Preparação

**Objetivo**: deixar o terreno preparado, sem feature ainda visível.

| Tarefa | Quem | Estimativa |
|---|---|---|
| Adicionar gem `grover` ao Gemfile + bundle | Backend | 30min |
| Subir Chromium no Dockerfile (dev) | DevOps | 1h |
| Testar Grover.new("hello").to_pdf no console | Backend | 30min |
| Adicionar dependências TipTap ao `package.json` | Frontend | 30min |
| `vite.config` — `optimizeDeps` pra ProseMirror | Frontend | 30min |
| Criar pasta `plugins/document_templates/` com Engine boilerplate | Backend | 1h |
| Adicionar entrada "Documentos" no Sidebar (rota stub) | Frontend | 1h |
| Criar arquivos vazios das migrations (esqueleto) | Backend | 30min |
| **Subtotal** | | **5h ≈ 1 dia** |

**Deliverable**: PR pequeno que sobe sem nada visível pro usuário final, mas com a base instalada.

## 9.3 Fase 1 — Fundação (MVP base)

**Objetivo**: admin consegue criar/editar/listar templates com variáveis. Sem integração com paciente ainda.

### Backend (parallel)

| Tarefa | Estimativa |
|---|---|
| Migrations: `document_template_folders` + `document_templates` | 1h |
| Migrations: extender `documents` e `consent_records` com FK | 30min |
| Model `DocumentTemplate` + validações + enums | 2h |
| Model `DocumentTemplateFolder` | 1h |
| Concern `DocumentTemplateExtension` (extende Document/ConsentRecord) | 1h |
| `DocumentTemplates::Catalog` (catálogo de variáveis, ~51 entries) | 2h |
| Controllers + routes + serializers | 4h |
| `DocumentTemplatePolicy` | 1h |
| Testes RSpec (model + controller básicos) | 3h |
| **Subtotal backend** | **15.5h ≈ 2.5 dias** |

### Frontend (parallel)

| Tarefa | Estimativa |
|---|---|
| Estrutura de pastas + entry SCSS | 1h |
| Rotas Vue + carregamento via Sidebar | 1h |
| Store Vuex (`documentTemplates`) + cliente API | 2h |
| `DocumentsIndex.vue` (lista + filtros + Klivy section) | 4h |
| `FolderSidebar.vue` + `FolderItem.vue` + modal nova pasta | 3h |
| `TemplateGrid.vue` + `TemplateCard.vue` + estado vazio | 3h |
| `TemplateContextMenu.vue` (⋮ editar/duplicar/arquivar) | 2h |
| **TipTapEditor.vue** (wrapper completo) | 3h |
| **EditorToolbar.vue** (B/I/U + headings + listas + alinhamento + cor + fonte) | 4h |
| `VariableExtension.js` (custom node) | 2h |
| `VariableNodeView.vue` (chip do editor) | 1.5h |
| `VariableSuggestion.js` (menu disparado por `/`) | 3h |
| `VariablePickerMenu.vue` (UI do menu) | 2h |
| `PaperContainer.vue` (canvas A4 estilizado) | 1.5h |
| `EditorSidebar.vue` (painel lateral configurações + variáveis) | 3h |
| `TemplateEditor.vue` (página completa juntando tudo) | 2h |
| SCSS modular: 12 partials | 4h |
| Composables (`useDocumentTemplates`, `useVariableCatalog`, `useTipTapEditor`) | 2h |
| Integração + ajustes finos | 3h |
| **Subtotal frontend** | **47h ≈ 8 dias** |

**Conclusão Fase 1**: 2-3 dias backend + 7-8 dias frontend (paralelizáveis) = **5-7 dias corridos** se você focar 100%.

## 9.4 Fase 2 — Migração & Catálogo Klivy

**Objetivo**: 22 templates Klivy prontos no banco, clínica pode clonar.

| Tarefa | Estimativa |
|---|---|
| Setup do seed (`SeedKlivyLibrary` + estrutura de pastas) | 1h |
| Auditar variáveis necessárias vs schema atual (`User.council_number`, `Patient.responsible_name`, etc.) | 2h |
| Migrations adicionais pra campos faltantes | 1.5h |
| Conversão Prawn → JSON dos 10 documentos clínicos | 5h (~30min/cada) |
| Conversão dos 12 consentimentos (mais texto, menos lógica) | 4h |
| `CloneKlivyTemplate` service + endpoint + UI do botão "Usar" | 2h |
| `KlivyLibraryDrawer.vue` (UI da biblioteca completa) | 3h |
| Teste manual de cada template gerando PDF | 3h |
| **Subtotal** | **21.5h ≈ 3.5 dias** |

## 9.5 Fase 3 — Integração com a tela do paciente

**Objetivo**: profissional dentro do paciente escolhe template e gera documento real.

| Tarefa | Estimativa |
|---|---|
| Modificar `Patients::PdfGenerator` (decisão Grover/Prawn) | 1.5h |
| Modificar `Patients::ConsentSigner` (idem) | 1h |
| `DocumentTemplates::PdfGenerator` (service Grover) | 3h |
| `DocumentTemplates::Renderer` (JSON → HTML) | 4h |
| `DocumentTemplates::Resolver` (variáveis → valores) | 3h |
| Template ERB `pdf_layout.html.erb` (header/footer/CSS) | 2h |
| `GeneratePdfJob` (Sidekiq, ActionCable broadcast) | 2h |
| Modificar `GenerateDocumentModal.vue` (dropdown de modelo) | 2.5h |
| Modificar UI do novo consentimento (dropdown de modelo) | 2h |
| Testes E2E do fluxo completo | 3h |
| **Subtotal** | **24h ≈ 4 dias** |

## 9.6 Fase 4 — Polimento + QA

| Tarefa | Estimativa |
|---|---|
| Drag-and-drop templates entre pastas | 2h |
| Atalhos de teclado (Cmd+S, Cmd+/) | 1h |
| Estados de erro do editor (rede offline, save falhou) | 2h |
| Hash SHA-256 + preparação Clicksign (campos prontos, sem integração ativa) | 2h |
| Pré-visualização "com paciente teste" | 3h |
| Dark mode (validar tokens, ajustar chips) | 1.5h |
| Acessibilidade (aria-labels, foco visível) | 2h |
| Performance: lazy-load do editor, debounce do autosave | 2h |
| Bug bashing + correções | 4h |
| **Subtotal** | **19.5h ≈ 3 dias** |

## 9.7 Visão consolidada do MVP

| Fase | Dias úteis | Acumulado |
|---|---|---|
| Fase 0 — Preparação | 1 | 1 |
| Fase 1 — Fundação | 5-7 | 6-8 |
| Fase 2 — Catálogo Klivy | 3-4 | 9-12 |
| Fase 3 — Integração paciente | 4 | 13-16 |
| Fase 4 — Polimento | 3 | 16-19 |
| **TOTAL MVP** | **13-19 dias úteis (~3-4 semanas)** | |

**Em calendário corrido** (5 dias/semana, 100% dedicado):
- **Cenário rápido (13 dias)**: ~2.5 semanas → 3 semanas úteis
- **Cenário realista (19 dias)**: ~4 semanas → ~1 mês

**Margem recomendada**: 1 semana adicional pra imprevistos (infra do Chromium em prod, design system refresh, bugs do Patient/Account schema). **Total prático: 5 semanas (~1 mês e meio)**.

## 9.8 Fases pós-MVP (Fase 5+)

### Fase 5 — Assinatura Clicksign (4-6 dias)

| Tarefa | Estimativa |
|---|---|
| Cadastro de credenciais Clicksign (env vars) | 1h |
| Service `Signatures::ClicksignProvider` (criar envelope, listener webhook) | 6h |
| Modelagem `SignatureRequest` (status, evento, hash, IP, timestamp) | 3h |
| UI: botão "Enviar pra Assinatura" no `Document` | 2h |
| UI: modal de status da assinatura | 2h |
| Webhook handler (Clicksign → Klivy) | 3h |
| Integração com Portal do Paciente (mostra docs pendentes) | 5h |
| Botão "Reenviar" + cancelar envelope | 2h |
| Trilha de auditoria completa (timestamp, IP, geolocation) | 2h |
| **Subtotal** | **26h ≈ 4-5 dias** |

### Fase 6 — IA: Geração de minuta (5-7 dias)

| Tarefa | Estimativa |
|---|---|
| Endpoint `POST /document_templates/ai/draft` (recebe prompt) | 1h |
| Prompt engineering pra gerar JSON ProseMirror válido | 8h |
| Reuso do client Anthropic existente (telemed já tem) | 2h |
| Validador defensivo (JSON malformado vira erro tratável) | 3h |
| UI: modal "Criar com IA — descreva o documento" | 3h |
| UI: progress indicator + diff antes de aceitar | 4h |
| Testes com 20+ prompts variados | 4h |
| Refinamento de prompt + few-shot examples | 6h |
| Rate limiting + custos por conta | 2h |
| **Subtotal** | **33h ≈ 5-6 dias** |

### Fase 7 — IA: Revisão LGPD (4-5 dias)

| Tarefa | Estimativa |
|---|---|
| Prompt pra detectar omissão de cláusulas LGPD | 6h |
| UI: painel lateral "Sugestões da IA" no editor | 4h |
| UI: highlight da parte do documento referida | 3h |
| Endpoint `POST /document_templates/:id/ai/review` | 2h |
| Cache de revisão (mesmo template não revisa duas vezes) | 2h |
| Testes com templates problemáticos | 3h |
| Disclaimer jurídico + opt-out na conta | 2h |
| **Subtotal** | **22h ≈ 3.5-4 dias** |

### Fase 8 — IA: Autopreenchimento (3-4 dias)

| Tarefa | Estimativa |
|---|---|
| Service `DocumentTemplates::SmartFiller` (recebe variável + paciente → preenche extra-campos) | 5h |
| Casos: plano de tratamento (concatena sessões), histórico de procedimentos, alergias | 4h |
| UI: indicador "Preenchido por IA" + permite editar | 2h |
| Testes | 3h |
| **Subtotal** | **14h ≈ 2-3 dias** |

## 9.9 Cronograma sugerido (com folga)

Pressupondo **um único dev** em par com IA, 5 dias/semana:

```
SEM 1  ─ Fase 0 + início Fase 1 (backend + setup editor)
SEM 2  ─ Fase 1 (frontend editor + variáveis + lista)
SEM 3  ─ Fim Fase 1 + começo Fase 2 (conversão templates)
SEM 4  ─ Fase 2 + Fase 3 (integração paciente)
SEM 5  ─ Fase 4 (polimento) + buffer/QA
                ▼
            🚀 GO LIVE MVP
SEM 6-7 ─ Fase 5 (Clicksign) [opcional pós-launch]
SEM 8-9 ─ Fase 6 (IA geração)
SEM 10  ─ Fase 7 (IA LGPD)
SEM 11  ─ Fase 8 (IA autofill)
```

## 9.10 Riscos que podem aumentar a estimativa

1. **Chromium em produção** dá problema → +2-3 dias debug infra.
2. **Schema dos modelos `Patient`/`User`** não tem todos os campos do catálogo → +1-2 dias de migrations + UI de Settings.
3. **Design não existir** pronto pras telas → +3-5 dias se precisar contratar designer ou desenhar tudo.
4. **Conversão dos 22 templates Klivy** for mais densa que estimado → +1-2 dias.
5. **Testes E2E** falhando intermitentes (Chromium é lento em CI) → +1-2 dias estabilização.

**Buffer prático sugerido**: 30% sobre a estimativa otimista = **~25 dias úteis (~5 semanas)** pra MVP completo.

## 9.11 O que entregar primeiro pra ver valor

Se quiser **demo em 2 semanas** com algo navegável (não produção):

- Fase 0 ✅
- Fase 1 ✅
- Pular Fase 2 — usar 2-3 templates manuais como demo
- Pular Fase 3 — editor existe mas não conversa com paciente
- = **demo em ~10 dias úteis**, mostrando admin criando template, inserindo variáveis, baixando PDF de teste

Pra **produção real**: tem que fazer pelo menos até Fase 3 (caso contrário a feature está isolada do paciente, sem valor).
