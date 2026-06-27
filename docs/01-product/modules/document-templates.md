# Módulo Modelos de Documento (`plugins/document_templates`)

> [!IMPORTANT]
> **Nota de Auditoria Arquitetural:**
> Este módulo é um **Rails Engine isolado** em `plugins/document_templates/`. Modelos, controllers, services e UI vivem dentro do plugin. Toques no core do Chatwoot foram **mínimos e aditivos** (registro de rotas/i18n e o chunk `vendor-prosemirror` no `vite.config.ts`).
>
> A **fonte da verdade de um template é o `content_json`** (documento ProseMirror), não HTML. O backend (`Renderer`) converte esse JSON em HTML/PDF — quem entende o conteúdo é o JSON, então trocar o editor exigiria reescrever esse contrato.
>
> **Restrição crítica de dependência:** o editor TipTap e o editor de conversas do Chatwoot puxam versões diferentes de `prosemirror-model`. É **obrigatório** mantê-lo deduplicado em uma única versão via `pnpm.overrides` no `package.json` — duas cópias quebram Enter/citação/preview com `RangeError: multiple versions of prosemirror-model`. Ver seção [Restrições técnicas](#-restrições-técnicas).

---

## 📌 Visão Geral

O **Módulo Modelos de Documento** permite à clínica criar, organizar e versionar modelos de documentos clínicos (atestados, receitas, contratos, orçamentos) e **termos de consentimento**, com um editor rico estilo Google Docs/Notion. Os modelos contêm **variáveis dinâmicas** (`{{ Nome completo }}`, `{{ CPF }}`, `{{ Cidade }}`) que são resolvidas com dados reais do paciente/clínica/profissional na hora de gerar o PDF.

Três frentes:

1. **Biblioteca & organização** (`/app/accounts/:id/documents`) — grade/lista de modelos, pastas, busca, filtro por tipo. Três origens de modelo: **Klivy** (biblioteca global, read-only, clonável), **Meus modelos** (criados pela clínica) e **clonados**.
2. **Editor de modelo** (`/app/accounts/:id/documents/:id/edit`) — canvas A4 WYSIWYG (TipTap), toolbar completa, sidebar de Configurações/Variáveis, **preview ao vivo** com paciente real, autosave.
3. **Geração de documento** — a partir do prontuário do paciente, escolhe um modelo, resolve as variáveis e gera o **PDF** (Grover/Chromium), que vira um `Document` ou `ConsentRecord` (e segue pro fluxo de assinatura quando aplicável).

---

## 🎯 Funcionalidades

### Biblioteca & organização
- 🗂 **Três abas:** Meus modelos · Todos · Biblioteca Klivy
- 📁 **Pastas** (`DocumentTemplateFolder`) por account, com sidebar de organização
- 🔎 **Busca** + filtro por tipo de documento; alternância **Grade/Lista**
- 🏷 **Badge "Personalizado"** distingue modelos da clínica dos da Klivy
- 📑 **Duplicar**, **Arquivar/Desarquivar**, **Excluir** (hard delete, bloqueado por FK quando o modelo já gerou documentos — aí o caminho é Arquivar)
- 🧬 **Clone-on-edit:** ao editar um modelo Klivy (read-only), a 1ª alteração clona pra account automaticamente e passa a editar a cópia

### Editor (TipTap)
- ✍️ **Formatação completa:** negrito, itálico, sublinhado, tachado, sobrescrito/subscrito, cor de texto, realce, limpar formatação
- 🔠 **Estilos de parágrafo** (Texto normal / Título / Cabeçalho 1-3), **família e tamanho de fonte** (stepper), **espaçamento de linha**
- 📐 **Alinhamento** (esquerda/centro/direita/justificado), **listas** (marcadores/numeradas), **recuo** (níveis 0-8)
- 🔗 **Link/unlink, imagem, tabela** (com menu de tabela), **citação**, **régua horizontal**, **caractere especial**, **quebra de página**
- ⌨️ **Atalho `/`** abre o seletor de variáveis (estilo Notion); **Cmd/Ctrl+S** salva
- 🧩 **Variáveis** inseridas pela aba lateral ou pelo `/`, renderizadas como **chip** não-editável
- 📄 **Papel** A4 / Letter / A5, retrato/paisagem, com proporção real da folha
- 💾 **Autosave** com debounce (2,5s) + retry exponencial; bloqueio de saída com alterações não salvas

### Preview ao vivo
- 👤 Escolhe um **paciente real** (busca remota) e alterna **"Preview ao vivo"**
- 🔄 Os chips `{{ Nome }}` viram o **valor resolvido** ("Danilo Mamedes", CPF formatado, data por extenso) — exatamente como sairá no PDF
- 🛡 **Não altera o `content_json`** salvo — é só camada de exibição (zero regressão no salvamento)

### Variáveis (catálogo)
- ~**55 variáveis** em **4 categorias**: 👤 Paciente · 🏥 Clínica · 👨‍⚕️ Profissional · 📅 Data
- 📚 Catálogo vive em **código** (não banco) — sem CRUD pelo usuário; resolução exige código de qualquer forma; versionado via git
- 🧮 Cada variável tem **formatter** próprio (CPF, telefone, data por extenso, moeda, etc.) e **fallback** (`_______`) quando o dado está vazio

### Geração de PDF
- 📃 `Renderer` converte `content_json` → HTML completo (com layout do papel)
- 🖨 **Grover** (Chromium headless) converte HTML → PDF
- 🔐 Calcula **SHA-256** do PDF (integridade + preparação pra assinatura)
- 📎 Anexa o PDF e persiste em `Document` ou `ConsentRecord`

---

## 🏗 Arquitetura

### Stack
- **Backend:** Rails Engine (`plugins/document_templates/lib/document_templates/engine.rb`) + ActiveRecord + Pundit (policies) + Grover (PDF)
- **Frontend:** Vue 3 (`<script setup>`) + **TipTap v2** (ProseMirror) + Pinia (store) + vue-i18n
- **API:** REST sob `/api/v1/accounts/:account_id/document_templates` (herda de `Api::V1::Accounts::BaseController`)
- **Editor:** componentes em `frontend/components/editor/` + extensões TipTap custom em `extensions/`

### Modelagem de domínio

```
DocumentTemplate
  ├─ account_id:        bigint NULL  (NULL = modelo Klivy global)
  ├─ folder_id:         bigint NULL  → DocumentTemplateFolder
  ├─ created_by_user_id:bigint NULL  → User
  ├─ source_template_id:bigint NULL  → DocumentTemplate (origem do clone)
  ├─ name:              string (obrigatório, único por [account_id, folder_id])
  ├─ description:       text
  ├─ document_type:     string (CLINICAL_TYPES + CONSENT_TYPES)
  ├─ source:            string (klivy | clinic | cloned)
  ├─ status:            string (draft | active | archived)
  ├─ paper_size:        string (A4 | Letter | A5)
  ├─ orientation:       string (portrait | landscape)
  ├─ version:           integer (auto-bump em cada update de content_json)
  ├─ content_json:      jsonb  (documento ProseMirror — FONTE DA VERDADE)
  ├─ content_html_cached: text (cache invalidado quando content_json muda)
  ├─ metadata:          jsonb
  └─ archived_at:       datetime (sincronizado com status='archived')

DocumentTemplateFolder
  ├─ account_id  → Account
  ├─ name, parent_id (árvore de pastas)
  └─ has_many :document_templates
```

**Origens (source):**
| source | account_id | significado |
|---|---|---|
| `klivy` | NULL | biblioteca global Klivy (read-only pra clínica) |
| `clinic` | X | criado do zero pela clínica X |
| `cloned` | X | clínica X clonou um Klivy (`source_template_id` aponta pro original) |

**Tipos de documento:** `CLINICAL_TYPES` (receita, atestado, pedido_exame, declaracao, relatorio_clinico, encaminhamento, contrato, orcamento, instrucao_procedimento, questionario, outro) + `CONSENT_TYPES` (consentimento_geral, _lgpd, _imagem, _toxina, _preenchimento, _laser, _fototerapia_led, _peeling, _dermoabrasao, _menor, _cirurgico, _anestesia). O tipo de troca é **escopado à família** (consentimento só vira consentimento; clínico só vira clínico).

### Fluxo de dados (content_json como fonte da verdade)

```
Editor (TipTap)
   │  onUpdate → getJSON()
   ▼
content_json (ProseMirror JSON)  ──PATCH──►  DocumentTemplate.content_json (jsonb)
   │                                              │
   │  preview (camada visual, não persiste)       │  geração
   ▼                                              ▼
chips {{var}} ↔ valores resolvidos          Renderer (JSON → HTML) → Grover → PDF
```

- O TipTap emite `content_json`; o pai grava em `draft.content_json` e faz o PATCH (debounce 2,5s).
- O `proseMirrorSanitize` remove text-nodes vazios antes de montar (um text vazio faria o TipTap descartar o doc inteiro).
- Validações do modelo: `content_json` deve ser `{type:'doc'}`, ≤ 500 KB, sem nodes proibidos (`script/iframe/object/embed`).

### Sistema de variáveis

```
Catalog (código)  →  Variable {key, label, category, formatter, example}
   │                          │
   │ for_frontend             │ insere node `variable` no content_json
   ▼                          ▼
menu "/" + aba lateral    chip {{ label }}  (VariableExtension + VariableNodeView)
   │
   │ preview / geração
   ▼
Resolver(patient, clinic, professional, now)
   ├─ read_raw(key) → Reader certo (patient/clinic/professional/date)
   ├─ Formatters.apply(raw, formatter)   (CPF, data por extenso, moeda…)
   └─ fallback (_______) quando vazio
```

- **Readers** (`app/services/document_templates/readers/`): `PatientReader`, `ClinicReader`, `ProfessionalReader`, `DateReader`.
- **Definições** (`variables/*_definitions.rb`): uma lista por categoria → evita "arquivo deus".
- `Resolver#resolve_all` resolve TODAS as chaves de uma vez (usado no **preview** e exposto via `GET .../preview_values?patient_id=X`).

### Pipeline de PDF (`PdfGenerator`)

```
1. Resolver { patient, clinic, professional, now }
2. Renderer: content_json → HTML completo (layout do papel)
3. Grover (Chromium headless): HTML → PDF     [GROVER_TIMEOUT_MS, default 30s]
4. SHA-256 do PDF (integridade / assinatura)
5. (opcional) anexa PDF + persiste rendered_html + pdf_hash em Document/ConsentRecord
```

---

## 🧑‍💻 Frontend — peças do editor

| Camada | Arquivo | Papel |
|---|---|---|
| Página | `routes/documents/TemplateEditor.vue` | Orquestra header + toolbar + canvas + sidebar; autosave; preview; atalhos |
| Editor | `components/editor/TipTapEditor.vue` | Wrapper TipTap; v-model em `content_json`; preview via shallowRef no storage |
| Toolbar | `components/editor/EditorToolbar.vue` (+ `EditorStyleSelect`, `EditorFontSizeStepper`, `EditorColorPicker`, `EditorTableMenu`, `SpecialCharPicker`, `EditorToolbarButton/Select`) | Comandos do TipTap |
| Sidebar | `components/editor/EditorSidebar.vue` | Abas Configurações/Variáveis; vira **drawer** off-canvas em telas ≤900px |
| Variáveis | `components/editor/VariablePickerMenu.vue`, `VariableNodeView.vue` | Lista/chip de variável |
| Papel | `components/editor/PaperContainer.vue` | Canvas A4/Letter/A5 retrato/paisagem |
| Store | `stores/documentTemplates.js` | Pinia: templates, biblioteca, pastas, variáveis (cacheadas) |

### Extensões TipTap custom (`components/editor/extensions/`)
- **`VariableExtension`** — node atom inline `variable` (chip); estado de preview num `shallowRef` no storage.
- **`VariableSuggestion(Extension)`** — trigger `/` (popover de inserção via tippy).
- **`FontSize`** — atributo `fontSize` no mark textStyle (não há extensão grátis no v2).
- **`LineHeight`** — atributo de espaçamento em paragraph/heading.
- **`Indent`** — nível de recuo (0-8) em paragraph/heading; o renderer Ruby é dono da unidade (`INDENT_STEP_EM = 2`).
- **`PageBreak`** — node de bloco que vira `page-break-after` no PDF (o PageBreak do TipTap é Pro).

---

## 🔌 API

| Método | Rota | Ação |
|---|---|---|
| GET | `/document_templates` | lista (filtros: `document_type`, `folder_id`, `family`, `only`, `include_archived`) |
| GET | `/document_templates/variables` | catálogo de variáveis (frontend) |
| GET | `/document_templates/klivy_library` | biblioteca Klivy global (clonável) |
| GET | `/document_templates/preview_values?patient_id=X` | resolve todas as variáveis pra um paciente (preview ao vivo) |
| GET | `/document_templates/:id` | mostra (inclui `content_json`) |
| POST | `/document_templates` | cria |
| PATCH | `/document_templates/:id` | atualiza |
| DELETE | `/document_templates/:id` | hard delete (bloqueado por FK se houver dependentes → `has_dependents`) |
| POST | `/document_templates/:id/duplicate` | duplica (mesma account) |
| POST | `/document_templates/:id/clone_to_account` | clona um Klivy pra account |
| POST | `/document_templates/:id/{archive,unarchive}` | arquiva/desarquiva |

---

## 🔒 Multi-tenancy & RBAC

- Toda query é scoped por account via `policy_scope` + `for_account(account)` (próprios + Klivy globais). Coerente com a regra dura de multi-tenancy do projeto.
- Modelos **Klivy** (`account_id NULL`) são read-only pra clínica → editar dispara **clone-on-edit** (requer `clone_to_account?` na policy; tipicamente admin).
- Policies: `DocumentTemplatePolicy`, `DocumentTemplateFolderPolicy`.

---

## ⚠️ Restrições técnicas

### `prosemirror-model` precisa ser uma instância única
O editor TipTap (`@tiptap/pm`, prosemirror-model `^1.23`) coexiste com o editor de conversas do Chatwoot (`@chatwoot/prosemirror-schema`, prosemirror-model `^1.22.3`). Se as duas versões coexistirem, os `instanceof Fragment/Node` do ProseMirror falham e o editor quebra com:

```
RangeError: Can not convert <...> to a Fragment
(looks like multiple versions of prosemirror-model were loaded)
```

…em `splitBlock` (Enter), `wrapIn` (citação), `insertContent` (quebra-de-página/variável) e ao alternar o preview.

**Solução (em vigor):** `package.json` → `pnpm.overrides."prosemirror-model": "1.25.7"` (satisfaz os dois consumidores). **Conferir** com `pnpm why prosemirror-model` (deve listar só uma versão). `manualChunks` **não** resolve isso — chunk só agrupa arquivos de saída, não funde duas cópias físicas. Após bumpar `@tiptap/*` ou `@chatwoot/prosemirror-schema`, revalidar o override.

### Outras
- **`content_json` é a fonte da verdade** — o HTML é derivado pelo `Renderer`; não persistir HTML como canon.
- **Limite de 500 KB** no `content_json`; nodes `script/iframe/object/embed` são rejeitados (defesa XSS, além da validação do frontend).
- **Deploy:** mudança de dependência (override) exige `pnpm install` + rebuild no ambiente — não basta subir só o código.

---

## 📂 Arquivos-chave

```
plugins/document_templates/
├── app/
│   ├── models/document_template.rb              # modelo central + validações
│   ├── models/document_template_folder.rb
│   ├── controllers/api/v1/accounts/document_templates_controller.rb
│   ├── serializers/document_template_serializer.rb
│   ├── policies/document_template_policy.rb
│   └── services/document_templates/
│       ├── catalog.rb                           # catálogo de variáveis
│       ├── resolver.rb                           # key → valor resolvido
│       ├── renderer.rb                           # content_json → HTML
│       ├── pdf_generator.rb                      # HTML → PDF (Grover) + SHA-256
│       ├── formatters.rb                         # CPF, data por extenso, moeda…
│       ├── readers/{patient,clinic,professional,date}_reader.rb
│       ├── variables/{patient,clinic,professional,date}_definitions.rb
│       └── seeds/                                # biblioteca Klivy (consent + clinical)
├── config/routes.rb
└── frontend/
    ├── routes/documents/{TemplateEditor,DocumentsIndex}.vue
    ├── stores/documentTemplates.js
    ├── components/editor/                        # editor + toolbar + sidebar + extensões
    ├── utils/proseMirrorSanitize.js
    └── styles/                                   # SCSS (tokens --kl-*, editor, índice)
```

---

> Histórico de correções relevantes do módulo: ver `CHANGELOG.md` (entradas `1.12.0.x`).
