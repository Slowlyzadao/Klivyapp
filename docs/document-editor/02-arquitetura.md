# 02 — Arquitetura

## 2.1 Visão geral em camadas

```
┌──────────────────────────────────────────────────────────────────────┐
│  CAMADA 1 — EDITOR (Frontend Vue 3 + TipTap)                         │
│  Onde admin escreve o template e insere variáveis                    │
│  Output: JSON do ProseMirror serializável                            │
└──────────────────────────────────────────────────────────────────────┘
                              │ POST /api/v1/document_templates
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  CAMADA 2 — PERSISTÊNCIA (Rails + Postgres)                          │
│  Tabela document_templates: account_id, document_type,               │
│  content_json (JSONB), version, status, source                       │
└──────────────────────────────────────────────────────────────────────┘
                              │ (depois, do paciente)
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  CAMADA 3 — RENDERER (Service Ruby)                                  │
│  DocumentTemplates::Renderer                                         │
│  Input:  template.content_json + { patient:, clinic:, professional:} │
│  Pipeline:                                                           │
│    1. Carrega catálogo de variáveis (DocumentVariables::Catalog)     │
│    2. Walk no JSON do ProseMirror                                    │
│    3. Cada nó type='variable' → resolve valor + formata              │
│    4. Renderiza HTML com header/footer da clínica                    │
│  Output: HTML completo pronto pra impressão                          │
└──────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  CAMADA 4 — PDF (Grover/Chromium)                                    │
│  DocumentTemplates::PdfGenerator                                     │
│  HTML → Chromium headless → PDF/A                                    │
│  Calcula SHA-256 do PDF                                              │
│  Anexa ao Document (Active Storage), salva pdf_hash                  │
│  Executa em ActiveJob/Sidekiq se demorar > 2s                        │
└──────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  CAMADA 5 — INTEGRAÇÃO COM MODELOS EXISTENTES                        │
│  Document.create!(                                                   │
│    patient:, document_type:,                                         │
│    document_template_id: tpl.id,    ← NOVO                           │
│    rendered_html: html,             ← NOVO (congelado)               │
│    pdf_hash: sha256,                ← NOVO                           │
│    file: pdf_blob                                                    │
│  )                                                                   │
│  ConsentRecord segue a mesma lógica                                  │
└──────────────────────────────────────────────────────────────────────┘
```

## 2.2 Fluxo: Admin cria/edita template

```
1. Admin → Sidebar → "Documentos"
2. Tela de biblioteca abre: lista de pastas (sidebar) + grid de templates
3. Clica "Novo Template"
4. Modal: escolhe pasta, nome, tipo (atestado/contrato/etc.)
5. Abre editor full-screen (TipTap)
6. Digita texto livre + insere variáveis com "/"
7. Clica "Salvar" → POST /api/v1/document_templates
8. Backend serializa content_json (JSONB), valida, persiste, incrementa version
9. Volta pra biblioteca
```

## 2.3 Fluxo: Profissional gera documento pro paciente

```
1. Profissional → Pacientes → Maria → aba Documentos
2. Clica "Gerar Documento" (UI atual)
3. Modal pergunta o tipo (Atestado, Receita, Contrato, ...)  ← UI atual já existe
4. **NOVO**: dropdown de "Modelo" aparece, listando os DocumentTemplates
   da clínica com aquele tipo (+ os modelos Klivy)
5. Profissional escolhe um template (ou "Padrão Prawn" se quiser legado)
6. (Opcional) edita campos "observações" no modal
7. Clica "Gerar e Baixar PDF"
8. Backend:
   a) Carrega template.content_json
   b) Resolve variáveis com Maria + Clínica + Profissional logado + Data hoje
   c) Renderiza HTML
   d) Gera PDF via Grover
   e) Salva Document(patient: Maria, template_id: X, rendered_html: ..., pdf_hash: ...)
   f) Anexa o PDF
9. Frontend baixa o PDF (URL assinada, igual hoje)
```

## 2.4 Fluxo: Gerar consentimento

```
Mesmo fluxo do 2.3, mas:
- Trigger: aba Consentimentos do paciente
- Tipo: "consentimento_toxina", "consentimento_lgpd", etc.
- Saída: ConsentRecord (não Document)
- Body do consentimento: o rendered_html (em vez do template legado em texto puro)
- A assinatura por canvas (já existe) continua funcionando — só o conteúdo veio do editor novo
```

## 2.5 Por que JSON do ProseMirror (e não HTML puro)?

**TipTap trabalha com uma árvore estruturada** chamada `Doc Node`. Pode ser exportada como HTML ou JSON.

| Critério | HTML | JSON ProseMirror |
|---|---|---|
| Voltar pro editor | Funciona, mas atributos customizados sofrem | Round-trip perfeito |
| Variável como dado estruturado | Vira `<span data-variable="...">` — frágil, regex pra parsear | Vira nó `{type:'variable', attrs:{...}}` — semântica forte |
| Versionamento | Diff de strings ruim | Diff de árvore (mais limpo, futuro) |
| Tamanho no banco | Menor | Maior (~30% mais bytes) |
| Performance | Ler HTML é trivial | Walk de árvore JSON também (não é gargalo) |

**Decisão**: salvar JSON. O HTML é gerado SÓ no momento da renderização final pra PDF. O cache `content_html_cached` é opcional pra acelerar preview.

## 2.6 O nó "variável" — semântica

```json
{
  "type": "variable",
  "attrs": {
    "key": "patient.full_name",       // chave do catálogo (estável)
    "label": "Nome do paciente",       // o que aparece no chip
    "fallback": "_________________",   // o que mostrar se valor for null
    "format": null                     // opcional: "uppercase", "date_long", etc.
  }
}
```

No editor renderiza como:

```
[ Nome do paciente ]   ← chip não-editável, cor de destaque, atomic node
```

No PDF gerado (depois do renderer):

```
Maria Silva Santos     ← texto puro substituindo o chip
```

## 2.7 Versionamento e imutabilidade

**Regra de ouro**: documento gerado **NUNCA muda** se o template for editado depois.

**Como garantimos**:

1. `Document.rendered_html` armazena o HTML **final, com variáveis já resolvidas**, congelado na hora da geração.
2. `Document.pdf_hash` (SHA-256) prova integridade.
3. `Document.document_template_id` é referência **histórica** (não pra renderizar de novo) — fica `RESTRICT ON DELETE` pra não deletar template usado.
4. `DocumentTemplate.version` incrementa a cada save — auditoria.

**Editar template** = nova versão. Documentos antigos seguem apontando pra... bem, pro `document_template_id` original mesmo, mas o `rendered_html` deles é o que vale.

## 2.8 Como o catálogo de variáveis é exposto

Catálogo vive em **código Ruby** (`DocumentVariables::Catalog`) — não em tabela.

**Por que código e não banco**:
- Versionado via git (mudanças têm review).
- Não tem CRUD de variável (clínica não cria variável customizada no MVP).
- Resolução do valor exige código de qualquer jeito (`patient.full_name` → método).
- Atualização não exige migration.

**Endpoint REST**:

```
GET /api/v1/document_templates/variables
→ [
    { key: 'patient.full_name', label: 'Nome do paciente',
      category: 'Paciente', example: 'Maria Silva' },
    { key: 'patient.cpf', label: 'CPF do paciente',
      category: 'Paciente', example: '123.456.789-00' },
    ...
  ]
```

Frontend cacheia a resposta e usa no dropdown do editor.

## 2.9 Como o tipo de template casa com Document.document_type

`Document.document_type` é um **enum** já existente:
```ruby
enum document_type: { receita: 0, atestado: 1, pedido_exame: 2, declaracao: 3,
                      relatorio_clinico: 4, encaminhamento: 5, contrato: 6,
                      orcamento: 7, instrucao_procedimento: 8, questionario: 9,
                      outro: 10 }
```

`DocumentTemplate.document_type` usa o **mesmo enum** + estende com os tipos de consentimento:
```ruby
enum document_type: {
  # Documentos clínicos (espelha Document)
  receita: 0, atestado: 1, pedido_exame: 2, declaracao: 3,
  relatorio_clinico: 4, encaminhamento: 5, contrato: 6,
  orcamento: 7, instrucao_procedimento: 8, questionario: 9, outro: 10,
  # Consentimentos (espelha ConsentRecord)
  consentimento_geral: 100, consentimento_lgpd: 101, consentimento_imagem: 102,
  consentimento_toxina: 103, consentimento_preenchimento: 104,
  consentimento_laser: 105, consentimento_fototerapia_led: 106,
  consentimento_peeling: 107, consentimento_dermoabrasao: 108,
  consentimento_menor: 109, consentimento_cirurgico: 110,
  consentimento_anestesia: 111
}
```

A "família" (clínico vs. consentimento) é deduzida pelo range numérico (< 100 = Document, ≥ 100 = ConsentRecord).

## 2.10 Plugin layout

```
plugins/document_templates/
├── lib/
│   ├── document_templates.rb           # Engine entry
│   └── document_templates/
│       └── engine.rb                    # Rails::Engine + class_eval pra estender Document/ConsentRecord
├── app/
│   ├── models/
│   │   ├── document_template.rb
│   │   └── document_template_folder.rb
│   ├── controllers/api/v1/accounts/
│   │   ├── document_templates_controller.rb
│   │   ├── document_template_folders_controller.rb
│   │   └── document_template_variables_controller.rb
│   ├── services/
│   │   └── document_templates/
│   │       ├── renderer.rb              # JSON → HTML
│   │       ├── pdf_generator.rb         # HTML → PDF (Grover)
│   │       ├── catalog.rb               # PORO com catálogo de variáveis
│   │       ├── resolver.rb              # patient → valores reais
│   │       └── seed_klivy_library.rb    # popula catálogo Klivy
│   ├── jobs/
│   │   └── document_templates/
│   │       └── generate_pdf_job.rb
│   ├── policies/
│   │   ├── document_template_policy.rb
│   │   └── document_template_folder_policy.rb
│   └── views/                           # vazio — só JSON API
├── config/
│   └── routes.rb
├── db/
│   └── migrate/                         # (ou centralizado em /db/migrate)
└── frontend/
    ├── routes/
    │   └── documents/
    │       ├── DocumentsIndex.vue       # tela principal
    │       ├── TemplateEditor.vue       # editor full-screen
    │       └── KlivyLibrary.vue         # modelos Klivy
    ├── components/
    │   ├── FolderSidebar.vue
    │   ├── TemplateGrid.vue
    │   ├── TemplateCard.vue
    │   ├── editor/
    │   │   ├── TipTapEditor.vue
    │   │   ├── EditorToolbar.vue
    │   │   ├── VariableNode.vue         # custom node renderer
    │   │   ├── VariablePickerMenu.vue   # menu aberto pelo "/"
    │   │   └── extensions/
    │   │       └── VariableExtension.js
    │   └── modals/
    │       ├── NewTemplateModal.vue
    │       ├── NewFolderModal.vue
    │       └── DuplicateTemplateModal.vue
    ├── composables/
    │   ├── useDocumentTemplates.js
    │   ├── useFolders.js
    │   └── useVariableCatalog.js
    ├── stores/
    │   └── documentTemplates.js          # Pinia (ou Vuex se for padrão)
    ├── styles/
    │   ├── document-templates.scss      # entry
    │   ├── _variables.scss              # tokens locais (estende global)
    │   ├── index/                       # partials da tela principal
    │   │   ├── _folder-sidebar.scss
    │   │   └── _template-grid.scss
    │   └── editor/                      # partials do editor
    │       ├── _editor.scss
    │       ├── _toolbar.scss
    │       └── _variable-node.scss
    └── api/
        └── documentTemplates.js          # cliente Axios
```

## 2.11 Pontos de integração explícitos

| Onde | O quê muda | Como |
|---|---|---|
| [Sidebar.vue](../../app/javascript/dashboard/components-next/sidebar/Sidebar.vue) | Adicionar entrada "Documentos" | Novo `<SidebarItem>` com ícone, rota `/app/accounts/:id/documents` |
| `app/javascript/dashboard/routes/` | Nova rota top-level | Carrega `plugins/document_templates/frontend/routes/documents/DocumentsIndex.vue` |
| `Patients::PdfGenerator` (existente) | Saber decidir Grover vs Prawn | If `document_template_id.present?` → chama novo gerador, senão Prawn |
| `Patients::ConsentSigner` (existente) | Idem | Mesma lógica |
| Modal `GenerateDocumentModal.vue` | Adicionar dropdown "Modelo" | Carrega templates da clínica filtrados por tipo via novo endpoint |
| Modal de novo consentimento | Adicionar dropdown "Modelo" | Idem |

## 2.12 Diagrama de dados (FK)

```
accounts ─┬─< document_template_folders ─< document_templates
          │                                     │
          └─< documents (existente) ────────────┤
                                                │
                                                ▼
                                       (versão histórica, RESTRICT)
                  ┌─< consent_records (existente) ─→

document_templates
  ├── account_id (nullable: TRUE quando source='klivy')
  ├── folder_id (nullable)
  ├── document_type (enum)
  ├── content_json (JSONB)
  ├── content_html_cached (TEXT, nullable — cache opcional)
  ├── version (integer, default 1)
  ├── source (enum: 'klivy', 'clinic', 'cloned')
  ├── source_template_id (FK→self, nullable — quando 'cloned')
  ├── status (enum: 'draft', 'active', 'archived')
  ├── created_by_user_id
  └── timestamps + soft delete
```

Detalhamento dos campos e migrations em [`03-modelo-de-dados.md`](03-modelo-de-dados.md).
