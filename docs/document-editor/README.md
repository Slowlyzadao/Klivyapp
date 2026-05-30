# Document Editor — Plano de Ação

> Feature: nova aba lateral **Documentos** com editor visual estilo Google Docs, sistema de variáveis dinâmicas, pastas, biblioteca de templates Klivy e geração de PDF. Os templates criados aqui alimentam a área de **Documentos** e **Consentimentos** que já existe dentro de Pacientes.

## TL;DR — onde mexer primeiro

1. Plugin novo `plugins/document_templates/` (segue padrão `patients`/`telemed`).
2. **TipTap** no frontend (Vue 3) com extensão `Mention` pras variáveis.
3. **Grover** no backend pra HTML→PDF (substitui Prawn no caminho novo).
4. Nova entrada `Documentos` no [Sidebar.vue](../../app/javascript/dashboard/components-next/sidebar/Sidebar.vue).
5. Modelos `Document`/`ConsentRecord` ganham FK opcional `document_template_id` — quando preenchida, o conteúdo é renderizado pelo editor novo (HTML), senão cai no Prawn legado.

## Decisões consolidadas (do brief com o usuário)

| Tema | Decisão |
|---|---|
| Posição no menu | Nova aba **Documentos** entre Teleconsulta e Pacientes (sidebar principal) |
| Relação com área atual | **Templates** vivem na nova aba; **uso** continua em Pacientes (Documentos + Consentimentos) |
| Migração dos PDFs atuais (Prawn) | Migrar tudo pro editor novo (Prawn vira fallback legado) |
| Editor | **TipTap** (`@tiptap/vue-3`) |
| Geração de PDF | **Grover** (Chromium headless) |
| Assinatura eletrônica | **Base preparada pra Clicksign** (implementação só Fase 2/futuro) |
| Onde paciente assina | Portal do Paciente **+** link do fornecedor (paciente escolhe) — Fase 2 |
| Escopo MVP | Enxuto: editor + variáveis + PDF, sem IA |
| Organização | **Pastas livres** + filtro automático por tipo |
| Catálogo Klivy | Biblioteca de templates prontos, clínica **clona** |
| Permissões | **Só administradores** podem criar/editar/deletar templates |
| Variáveis MVP | Paciente + Clínica + Profissional + Data/Hora |
| IA | Fora do MVP (mas arquitetura preparada — já temos Anthropic em telemed) |

## Índice dos documentos do plano

1. [01-decisoes-e-escopo.md](01-decisoes-e-escopo.md) — Decisões consolidadas, premissas, o que está **dentro** e o que está **fora** do MVP.
2. [02-arquitetura.md](02-arquitetura.md) — Camadas (editor → JSON → renderer → PDF), diagrama de fluxo, integração com Documentos/Consentimentos.
3. [03-modelo-de-dados.md](03-modelo-de-dados.md) — Schema das tabelas novas (`document_templates`, `document_template_folders`, `document_variables`), migrations e FKs.
4. [04-backend.md](04-backend.md) — Plugin `document_templates`, controllers, services (renderer de variáveis, gerador Grover), policies, jobs Sidekiq.
5. [05-frontend.md](05-frontend.md) — Estrutura Vue, componentes TipTap, extensão `Variable` (custom node), composables, store Pinia/Vuex.
6. [06-design-system-e-ui.md](06-design-system-e-ui.md) — Wireframes textuais das 4 telas principais, padrão SCSS modular (igual `plugins/patients/frontend/styles/`), componentes reutilizáveis.
7. [07-catalogo-de-variaveis.md](07-catalogo-de-variaveis.md) — Lista completa de variáveis (chaves, labels, formatadores) com namespacing por categoria.
8. [08-migracao-prawn.md](08-migracao-prawn.md) — Estratégia pra converter os 10 tipos de documento e ~11 consentimentos atuais em templates editáveis, sem quebrar produção.
9. [09-fases-cronograma.md](09-fases-cronograma.md) — Roadmap em 4 fases + estimativas de tempo programando com IA (Claude Code).
10. [10-pontos-de-atencao.md](10-pontos-de-atencao.md) — Riscos, tradeoffs, dívida técnica, infra (Chromium no servidor), LGPD.

## Como ler esses docs

- Se você só quer **entender a feature**: leia `01` e `02`.
- Se vai **codar o backend**: leia `02`, `03`, `04`, `07`.
- Se vai **codar o frontend**: leia `02`, `05`, `06`, `07`.
- Se quer **estimar e priorizar**: leia `01`, `09`, `10`.
- Se vai **migrar dados em produção**: leia `08`, `10`.

## Próximo passo recomendado

Ler `01-decisoes-e-escopo.md` e `09-fases-cronograma.md`, validar as fases, e abrir a Fase 1 (Fundação) — começa criando o plugin `document_templates`, migrations e a entrada no Sidebar.
