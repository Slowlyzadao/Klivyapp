# 01 — Decisões e Escopo

## 1.1 Visão da feature em uma frase

> **Uma biblioteca de templates de documentos da clínica**, com editor visual rico (estilo Google Docs) e variáveis dinâmicas — os templates aqui criados são reaproveitados pelas áreas de Documentos e Consentimentos que já existem dentro de Pacientes.

## 1.2 Quem usa, quando, pra quê

| Persona | Quando entra | Pra fazer o quê |
|---|---|---|
| **Admin da clínica** | Onboarding inicial e raramente depois | Cria/edita os modelos de contrato, atestado, consentimentos LGPD/imagem, etc. |
| **Profissional (médico, dentista, esteta)** | Todo dia, dentro da ficha do paciente | Seleciona um template existente e gera o documento final pro paciente |
| **Paciente** | Quando vai assinar (Fase 2) | Recebe o documento por WhatsApp/e-mail ou abre no portal e assina |
| **Klivy (a gente)** | Uma vez, ao subir a feature | Popula a **biblioteca de modelos Klivy** (padrões que toda clínica vê) |

## 1.3 O que está DENTRO do MVP (Fase 1)

✅ Nova entrada **Documentos** no sidebar principal do dashboard.
✅ Tela inicial da feature com **lista de pastas + grid/lista de templates**.
✅ CRUD completo de **pastas** (criar, renomear, deletar, mover).
✅ CRUD completo de **templates** (criar, editar, duplicar, arquivar, deletar).
✅ **Editor TipTap** com toolbar: negrito/itálico/sublinhado, títulos (H1-H3), listas, alinhamento, link, tabela simples, cor de texto, font-family, undo/redo, placeholder, contador.
✅ **Inserção de variáveis** via gatilho `/` ou `{{` — abre menu com catálogo (filtrável por busca).
✅ Cada variável renderiza no editor como um **chip não-editável** (`[Nome do paciente]`).
✅ Cada template declara um **tipo** (atestado, receita, contrato, consentimento_toxina, etc.) — mesmo enum dos modelos atuais.
✅ **Catálogo Klivy** de templates (15-20 modelos prontos), clonáveis pela clínica.
✅ **Geração de documento real** a partir de um template, dentro do paciente (substitui as variáveis, gera HTML, vira PDF via **Grover**).
✅ **Migração dos 10 tipos atuais** (`Document`) e **11 consentimentos atuais** (`ConsentRecord`) pra ficarem disponíveis como modelos Klivy.
✅ **Permissões**: só `administrator` mexe nos templates; `agent` só usa.
✅ Catálogo de variáveis: **paciente, clínica, profissional, data/hora**.
✅ **Versionamento congelado**: ao gerar um documento, o conteúdo final é salvo desacoplado do template — editar template depois NÃO altera documentos gerados.
✅ **Hash SHA-256** do PDF final salvo no `Document.metadata` (preparação pra Clicksign).
✅ Trilha de auditoria mínima (já existe `audit_logged`/`Trackable` no modelo `Document`).

## 1.4 O que está FORA do MVP (vai pra fases seguintes)

❌ Geração de minuta por IA a partir de linguagem natural (Fase 3).
❌ Revisão automática de risco LGPD/jurídico (Fase 3).
❌ Sugestão contextual de cláusulas (Fase 3).
❌ Explicação de cláusula em linguagem simples pro paciente (Fase 3).
❌ Variáveis de tratamento/agendamento/financeiro (Fase 2).
❌ Variáveis customizáveis pela clínica (Fase 2).
❌ Integração ativa com Clicksign (só a base/arquitetura — efetivar na Fase 2).
❌ Assinatura via portal do paciente nativa (Fase 2 — usa o que já tem em `plugins/patient_portal`).
❌ Colaboração em tempo real (multi-user editing) — não está no roadmap.
❌ Comentários no documento — não está no roadmap.
❌ Histórico de versões com diff visual — versionamento existe (campo `version`), mas sem UI de diff no MVP.

## 1.5 Decisões técnicas consolidadas

### Frontend
- **Editor**: TipTap 2 (`@tiptap/vue-3`, `@tiptap/starter-kit`, `@tiptap/extension-mention`, `@tiptap/extension-table`, `@tiptap/extension-text-align`, `@tiptap/extension-color`, `@tiptap/extension-font-family`, `@tiptap/extension-link`, `@tiptap/extension-placeholder`, `@tiptap/extension-character-count`).
- **Variáveis**: implementadas como **custom node** próprio (não Mention puro), porque queremos atributos estáveis (`variable_key`, `label`, `fallback`) e renderização customizada como chip.
- **Stack Vue**: Vue 3 + Composition API + Pinia (ou Vuex se preferir consistência com o projeto — verificar no Sidebar.vue qual é o padrão atual).
- **Estilo**: SCSS modular igual ao padrão de `plugins/patients/frontend/styles/` — entry point + partials por domínio + `_variables.scss` herdando os tokens já existentes.

### Backend
- **PDF**: gem **Grover** (HTML → PDF via Chromium headless). Adicionar ao `Gemfile`. Em paralelo, manter Prawn vivo no codebase enquanto a migração dos 10+11 tipos atuais não estiver 100% concluída.
- **Plugin novo**: `plugins/document_templates/` — segue mesma estrutura de `patients`/`telemed` (Engine, namespaces, rotas isoladas).
- **Modelos novos**:
  - `DocumentTemplate` (campos: account_id, folder_id, name, document_type, content_json, content_html_cached, version, source ['klivy'|'clinic'|'cloned'], source_template_id, status ['active'|'archived'], created_by_user_id).
  - `DocumentTemplateFolder` (account_id, name, parent_id [nullable, pra subpasta], position).
  - (Opcional) `DocumentVariableDefinition` se quisermos catálogo no banco. No MVP, sugiro **catálogo em código** (`PORO`) — mais simples e versionado via git.
- **Renderer**: `DocumentTemplates::Renderer` (input: `template_json + entities { patient:, clinic:, professional: }`; output: HTML pronto pra Grover).
- **Geração**: `DocumentTemplates::PdfGenerator` (usa Grover; rodando em **ActiveJob/Sidekiq** se demorar mais de 2s).
- **Catálogo Klivy**: seed `db/seeds/document_template_catalog.rb` cria templates marcados com `source: 'klivy'` e `account_id: null`. Quando a clínica clica "Usar este modelo" → clona pro `account_id` dela.

### Integração com os modelos existentes
- `Document` (plugins/patients) ganha:
  - `document_template_id` (FK opcional pra `document_templates`)
  - `rendered_html` (TEXT — HTML congelado no momento da geração)
  - `pdf_hash` (string SHA-256 — preparação Clicksign)
  - Comportamento: se `document_template_id IS NOT NULL`, gera via Grover; senão, usa Prawn (legado).
- `ConsentRecord` (plugins/patients) ganha:
  - `document_template_id` (FK opcional)
  - Mesma lógica: se template novo → renderiza pelo editor; senão, mantém o `body` atual.

## 1.6 Premissas explícitas (assumidas — alinhar se discordar)

1. **Account-scoped**: cada `DocumentTemplate` pertence a uma `account` (clínica). Não há compartilhamento entre clínicas no MVP, exceto os templates Klivy (que têm `account_id: null` e `source: 'klivy'`).
2. **Sem assinatura no MVP**: o fluxo termina em "Gerar PDF + download/envio por WhatsApp" — exatamente o que já existe hoje pros 10 tipos atuais. A diferença é o conteúdo agora vir de um template editável.
3. **Onboarding**: nova conta de clínica **não** ganha cópia automática dos templates Klivy. Ela vê na aba uma seção "Modelos Klivy" e clica "Usar este modelo" pra clonar — isso evita encher a conta de lixo.
4. **Subpastas**: o schema suporta (`parent_id`), mas no MVP a UI permite **só 1 nível** (pastas no topo, templates dentro). Subpastas vêm depois se houver demanda.
5. **Mobile**: editor é desktop-first. A geração de documento pelo profissional dentro do paciente (telado mobile) continua funcionando — só a tela de edição de template não é otimizada pra mobile no MVP.

## 1.7 Critérios de aceite do MVP

A feature está pronta pra produção quando:

- [ ] Admin consegue criar uma pasta, criar um template do tipo "contrato", inserir variáveis, salvar.
- [ ] Profissional dentro de um paciente abre "Gerar Documento" e vê os templates de "contrato" da clínica (filtrado por tipo).
- [ ] Ao selecionar, sistema gera o PDF com as variáveis preenchidas via Grover, salva no `Document` e disponibiliza o download (mesma UI atual).
- [ ] Editar o template depois NÃO modifica o documento já gerado.
- [ ] Profissional sem permissão admin NÃO consegue acessar a aba Documentos (ou vê em modo read-only).
- [ ] Catálogo Klivy aparece com 15+ modelos prontos, cloná­veis.
- [ ] Migração: todos os 10 tipos antigos e 11 consentimentos antigos têm equivalente como template Klivy.
- [ ] Performance: geração de PDF roda em background (Sidekiq) e leva < 5s p99.
- [ ] Sem regressão na área de Documentos/Consentimentos do paciente (caminho legado Prawn continua funcionando).
