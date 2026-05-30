# 05 — Frontend (Vue 3 + TipTap)

## 5.1 Dependências NPM

```jsonc
// package.json (raiz)
{
  "dependencies": {
    "@tiptap/vue-3": "^2.5.0",
    "@tiptap/starter-kit": "^2.5.0",
    "@tiptap/extension-character-count": "^2.5.0",
    "@tiptap/extension-color": "^2.5.0",
    "@tiptap/extension-font-family": "^2.5.0",
    "@tiptap/extension-link": "^2.5.0",
    "@tiptap/extension-mention": "^2.5.0",
    "@tiptap/extension-placeholder": "^2.5.0",
    "@tiptap/extension-table": "^2.5.0",
    "@tiptap/extension-table-row": "^2.5.0",
    "@tiptap/extension-table-cell": "^2.5.0",
    "@tiptap/extension-table-header": "^2.5.0",
    "@tiptap/extension-text-align": "^2.5.0",
    "@tiptap/extension-text-style": "^2.5.0",
    "@tiptap/extension-underline": "^2.5.0",
    "@tiptap/suggestion": "^2.5.0",
    "tippy.js": "^6.3.7"          // popup do menu de variáveis
  }
}
```

### Aviso sobre ProseMirror duplicado

O projeto já tem `@chatwoot/prosemirror-schema` (usado no editor de mensagens). TipTap importa `prosemirror-state`, `prosemirror-view`, etc. — se houver erro "different instances of a keyed plugin", adicionar ao Vite:

```ts
// vite.config.ts (ou config Vue equivalente)
export default defineConfig({
  optimizeDeps: {
    include: [
      'prosemirror-state',
      'prosemirror-view',
      'prosemirror-model',
      'prosemirror-transform',
      'prosemirror-commands',
      'prosemirror-history',
      'prosemirror-keymap',
      'prosemirror-schema-list',
      'prosemirror-tables'
    ]
  }
})
```

## 5.2 Estrutura de arquivos

```
plugins/document_templates/frontend/
├── routes/
│   └── documents/
│       ├── DocumentsIndex.vue          # tela principal (lista)
│       ├── DocumentsRouter.vue         # wrapper de rota
│       └── TemplateEditor.vue          # editor full-screen
├── components/
│   ├── index/
│   │   ├── DocumentsHeader.vue
│   │   ├── FolderSidebar.vue
│   │   ├── FolderItem.vue
│   │   ├── TemplateGrid.vue
│   │   ├── TemplateCard.vue
│   │   ├── TemplateContextMenu.vue
│   │   ├── EmptyState.vue
│   │   └── KlivyLibraryDrawer.vue
│   ├── editor/
│   │   ├── TipTapEditor.vue            # wrapper do TipTap
│   │   ├── EditorToolbar.vue
│   │   ├── EditorSidebar.vue           # painel direito (variáveis, infos)
│   │   ├── VariablePickerMenu.vue      # menu aberto com "/"
│   │   ├── VariableNodeView.vue        # render do chip não-editável
│   │   ├── extensions/
│   │   │   ├── VariableExtension.js    # custom node
│   │   │   └── VariableSuggestion.js   # suggestion plugin pro "/"
│   │   └── PaperContainer.vue          # canvas A4 simulado
│   └── modals/
│       ├── NewTemplateModal.vue
│       ├── NewFolderModal.vue
│       ├── DuplicateTemplateModal.vue
│       └── DeleteConfirmModal.vue
├── composables/
│   ├── useDocumentTemplates.js
│   ├── useFolders.js
│   ├── useVariableCatalog.js
│   └── useTipTapEditor.js
├── stores/
│   └── documentTemplates.js
├── api/
│   ├── documentTemplates.js
│   ├── documentTemplateFolders.js
│   └── documentTemplateVariables.js
├── styles/
│   ├── document-templates.scss         # entry point
│   ├── _variables.scss                 # tokens locais (estende global)
│   ├── index/
│   │   ├── _index.scss
│   │   ├── _folder-sidebar.scss
│   │   ├── _template-grid.scss
│   │   └── _template-card.scss
│   ├── editor/
│   │   ├── _editor.scss
│   │   ├── _toolbar.scss
│   │   ├── _variable-node.scss
│   │   ├── _paper-container.scss
│   │   └── _picker-menu.scss
│   └── modals/
│       └── _modals.scss
└── i18n/
    └── pt_BR.json                       # strings traduzidas
```

## 5.3 Rotas no dashboard

Editar `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` (ou onde estão as rotas top-level) adicionando:

```js
import DocumentsRouter from '@/plugins/document_templates/frontend/routes/documents/DocumentsRouter.vue';

const documentRoutes = [
  {
    path: 'documents',
    component: DocumentsRouter,
    children: [
      {
        path: '',
        name: 'documents_index',
        component: () => import('@/plugins/document_templates/frontend/routes/documents/DocumentsIndex.vue'),
        meta: { permissions: ['administrator', 'agent'] }
      },
      {
        path: 'new',
        name: 'documents_new',
        component: () => import('@/plugins/document_templates/frontend/routes/documents/TemplateEditor.vue'),
        meta: { permissions: ['administrator'] }
      },
      {
        path: ':id/edit',
        name: 'documents_edit',
        component: () => import('@/plugins/document_templates/frontend/routes/documents/TemplateEditor.vue'),
        meta: { permissions: ['administrator'] }
      }
    ]
  }
];
```

## 5.4 Entrada no sidebar

Editar [`app/javascript/dashboard/components-next/sidebar/Sidebar.vue`](../../app/javascript/dashboard/components-next/sidebar/Sidebar.vue):

```vue
<!-- Após o item "Pacientes" -->
<SidebarItem
  :to="`/app/accounts/${accountId}/documents`"
  :label="$t('SIDEBAR.DOCUMENTS')"
  icon="file-text"
  data-testid="sidebar-documents"
/>
```

E adicionar tradução em `app/javascript/dashboard/i18n/locale/pt_BR/sidebar.json`:
```json
{ "SIDEBAR": { "DOCUMENTS": "Documentos" } }
```

## 5.5 Componente central: `TipTapEditor.vue`

```vue
<template>
  <div class="tiptap-wrapper">
    <EditorToolbar
      v-if="editor"
      :editor="editor"
      @insert-variable="onInsertVariable"
    />
    <PaperContainer :paper-size="paperSize" :orientation="orientation">
      <EditorContent :editor="editor" class="tiptap-content" />
    </PaperContainer>
    <CharacterCount :editor="editor" />
  </div>
</template>

<script setup>
import { ref, onMounted, onBeforeUnmount, watch } from 'vue';
import { useEditor, EditorContent } from '@tiptap/vue-3';
import StarterKit from '@tiptap/starter-kit';
import Underline from '@tiptap/extension-underline';
import TextAlign from '@tiptap/extension-text-align';
import TextStyle from '@tiptap/extension-text-style';
import Color from '@tiptap/extension-color';
import FontFamily from '@tiptap/extension-font-family';
import Link from '@tiptap/extension-link';
import Table from '@tiptap/extension-table';
import TableRow from '@tiptap/extension-table-row';
import TableCell from '@tiptap/extension-table-cell';
import TableHeader from '@tiptap/extension-table-header';
import Placeholder from '@tiptap/extension-placeholder';
import CharacterCount from '@tiptap/extension-character-count';

import VariableExtension from './extensions/VariableExtension';
import VariableSuggestion from './extensions/VariableSuggestion';

import EditorToolbar from './EditorToolbar.vue';
import PaperContainer from './PaperContainer.vue';

const props = defineProps({
  modelValue: { type: Object, default: () => ({ type: 'doc', content: [] }) },
  paperSize: { type: String, default: 'A4' },
  orientation: { type: String, default: 'portrait' },
  readonly: { type: Boolean, default: false }
});

const emit = defineEmits(['update:modelValue', 'editor-ready']);

const editor = useEditor({
  content: props.modelValue,
  editable: !props.readonly,
  extensions: [
    StarterKit.configure({ history: { depth: 100 } }),
    Underline,
    TextStyle,
    Color,
    FontFamily.configure({ types: ['textStyle'] }),
    TextAlign.configure({ types: ['heading', 'paragraph'] }),
    Link.configure({ openOnClick: false }),
    Table.configure({ resizable: true }),
    TableRow,
    TableCell,
    TableHeader,
    Placeholder.configure({
      placeholder: 'Digite o conteúdo do template — use "/" para inserir variáveis'
    }),
    CharacterCount,
    VariableExtension.configure({ suggestion: VariableSuggestion })
  ],
  onUpdate({ editor }) {
    emit('update:modelValue', editor.getJSON());
  },
  onCreate({ editor }) {
    emit('editor-ready', editor);
  }
});

const onInsertVariable = (variable) => {
  editor.value
    ?.chain()
    .focus()
    .insertContent({ type: 'variable', attrs: variable })
    .run();
};

watch(() => props.modelValue, (next) => {
  // Atualização externa (ex: carregar template)
  if (!editor.value) return;
  const current = editor.value.getJSON();
  if (JSON.stringify(current) !== JSON.stringify(next)) {
    editor.value.commands.setContent(next, false);
  }
});

onBeforeUnmount(() => editor.value?.destroy());
</script>
```

## 5.6 Extensão `VariableExtension.js` (custom node)

```js
import { Node, mergeAttributes } from '@tiptap/core';
import { VueNodeViewRenderer } from '@tiptap/vue-3';
import VariableNodeView from '../VariableNodeView.vue';

const VariableExtension = Node.create({
  name: 'variable',

  group: 'inline',
  inline: true,
  selectable: true,
  atom: true,  // tratado como bloco único, não editável caractere a caractere

  addAttributes() {
    return {
      key:      { default: null, parseHTML: el => el.getAttribute('data-key'),    renderHTML: a => ({ 'data-key': a.key }) },
      label:    { default: null, parseHTML: el => el.getAttribute('data-label'),  renderHTML: a => ({ 'data-label': a.label }) },
      fallback: { default: '_______', parseHTML: el => el.getAttribute('data-fallback'), renderHTML: a => ({ 'data-fallback': a.fallback }) },
      format:   { default: null, parseHTML: el => el.getAttribute('data-format'), renderHTML: a => a.format ? { 'data-format': a.format } : {} }
    };
  },

  parseHTML() {
    return [{ tag: 'span[data-variable]' }];
  },

  renderHTML({ HTMLAttributes }) {
    return [
      'span',
      mergeAttributes(HTMLAttributes, { 'data-variable': '', class: 'tiptap-variable' }),
      `{{ ${HTMLAttributes['data-label'] || HTMLAttributes['data-key']} }}`
    ];
  },

  addNodeView() {
    return VueNodeViewRenderer(VariableNodeView);
  },

  addCommands() {
    return {
      insertVariable: (attrs) => ({ commands }) =>
        commands.insertContent({ type: this.name, attrs })
    };
  }
});

export default VariableExtension;
```

## 5.7 `VariableSuggestion.js` (menu disparado pelo "/")

```js
import { VueRenderer } from '@tiptap/vue-3';
import tippy from 'tippy.js';
import VariablePickerMenu from '../VariablePickerMenu.vue';
import { useVariableCatalog } from '../../../composables/useVariableCatalog';

const VariableSuggestion = {
  char: '/',
  startOfLine: false,

  items: ({ query }) => {
    const { catalog } = useVariableCatalog();
    return catalog.value
      .filter(v =>
        v.label.toLowerCase().includes(query.toLowerCase()) ||
        v.key.toLowerCase().includes(query.toLowerCase())
      )
      .slice(0, 12);
  },

  render: () => {
    let component, popup;

    return {
      onStart: (props) => {
        component = new VueRenderer(VariablePickerMenu, { props, editor: props.editor });
        popup = tippy('body', {
          getReferenceClientRect: props.clientRect,
          appendTo: () => document.body,
          content: component.element,
          showOnCreate: true, interactive: true,
          trigger: 'manual', placement: 'bottom-start'
        });
      },
      onUpdate: (props) => {
        component.updateProps(props);
        popup[0].setProps({ getReferenceClientRect: props.clientRect });
      },
      onKeyDown: (props) => {
        if (props.event.key === 'Escape') { popup[0].hide(); return true; }
        return component.ref?.onKeyDown?.(props);
      },
      onExit: () => { popup[0].destroy(); component.destroy(); }
    };
  }
};

export default VariableSuggestion;
```

## 5.8 `VariableNodeView.vue` (renderização do chip no editor)

```vue
<template>
  <NodeViewWrapper as="span" class="tiptap-variable-chip"
                   :class="{ 'tiptap-variable-chip--selected': selected }">
    <Icon name="variable" class="tiptap-variable-chip__icon" />
    <span class="tiptap-variable-chip__label">{{ node.attrs.label }}</span>
  </NodeViewWrapper>
</template>

<script setup>
import { NodeViewWrapper, nodeViewProps } from '@tiptap/vue-3';
import Icon from '@/components-next/icon/Icon.vue';
defineProps(nodeViewProps);
</script>
```

CSS (em `_variable-node.scss`):

```scss
@use '../variables' as *;

.tiptap-variable-chip {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px 8px;
  border-radius: 6px;
  background: rgba($brand-info-bright, 0.12);
  color: $brand-info;
  font-size: 0.875em;
  font-weight: 500;
  line-height: 1.4;
  cursor: pointer;
  user-select: none;
  vertical-align: baseline;
  transition: background 120ms ease, transform 120ms ease;

  &:hover { background: rgba($brand-info-bright, 0.2); }
  &--selected {
    background: rgba($brand-info-bright, 0.3);
    outline: 2px solid $brand-info;
  }
  &__icon  { width: 12px; height: 12px; }
  &__label { white-space: nowrap; }
}
```

## 5.9 Composable: `useVariableCatalog.js`

```js
import { ref, computed } from 'vue';
import { fetchVariables } from '../api/documentTemplateVariables';

const catalog = ref([]);
const loaded = ref(false);

export function useVariableCatalog() {
  const load = async () => {
    if (loaded.value) return;
    const { data } = await fetchVariables();
    catalog.value = data;
    loaded.value = true;
  };

  const byCategory = computed(() => {
    const groups = {};
    catalog.value.forEach(v => {
      groups[v.category] ??= [];
      groups[v.category].push(v);
    });
    return groups;
  });

  return { catalog, byCategory, loaded, load };
}
```

## 5.10 Cliente API

```js
// api/documentTemplates.js
import axios from 'axios';

const base = (accountId) => `/api/v1/accounts/${accountId}/document_templates`;

export const fetchTemplates = (accountId, params = {}) =>
  axios.get(base(accountId), { params });

export const fetchKlivyLibrary = (accountId, params = {}) =>
  axios.get(`${base(accountId)}/klivy_library`, { params });

export const fetchTemplate = (accountId, id) =>
  axios.get(`${base(accountId)}/${id}`);

export const createTemplate = (accountId, payload) =>
  axios.post(base(accountId), { document_template: payload });

export const updateTemplate = (accountId, id, payload) =>
  axios.patch(`${base(accountId)}/${id}`, { document_template: payload });

export const duplicateTemplate = (accountId, id) =>
  axios.post(`${base(accountId)}/${id}/duplicate`);

export const cloneKlivyToAccount = (accountId, klivyTemplateId) =>
  axios.post(`${base(accountId)}/${klivyTemplateId}/clone_to_account`);

export const archiveTemplate = (accountId, id) =>
  axios.post(`${base(accountId)}/${id}/archive`);
```

## 5.11 Integração com a tela atual de "Gerar Documento" do paciente

A tela atual ([`plugins/patients/frontend/routes/patients/tabs/DocumentsTab.vue`](../../plugins/patients/frontend/routes/patients/tabs/DocumentsTab.vue) e seu modal `GenerateDocumentModal.vue`) hoje:
- Pergunta `document_type`
- Tem campo de "Observações"
- Botão "Gerar e Baixar PDF"

**Modificação necessária**: depois de escolher o tipo, mostrar dropdown "Modelo":

```
┌──────────────────────────────────────────┐
│ Tipo de Documento *                      │
│ [ Atestado Médico         ▼ ]            │
├──────────────────────────────────────────┤
│ Modelo *  (nova label)                   │
│ [ Atestado Padrão Klivy   ▼ ]            │
│   ↳ Atestado Padrão Klivy                │
│   ↳ Atestado Personalizado da Clínica    │
│   ↳ + Criar novo modelo →                │ → link pra aba Documentos
├──────────────────────────────────────────┤
│ Observações (opcional)                   │
│ [____________________________]           │
├──────────────────────────────────────────┤
│ [ Cancelar ]  [ 📄 Gerar e Baixar PDF ] │
└──────────────────────────────────────────┘
```

Lógica: quando `documentType` muda, chamar `fetchTemplates(accountId, { document_type })` e popular o dropdown.

Quando submeter, mandar `template_id` junto do payload — o backend já sabe escolher Grover vs Prawn (caminho 4.9 do backend).

## 5.12 Store Pinia (ou Vuex se for o padrão)

> **Verificar primeiro** se o projeto usa Pinia ou Vuex. Pelo histórico do Chatwoot, é Vuex 4. Se for Vuex:

```js
// store/modules/documentTemplates.js
import { fetchTemplates, fetchTemplate, createTemplate /*...*/ } from '@/plugins/document_templates/frontend/api/documentTemplates';

const state = {
  templates: [],
  klivyLibrary: [],
  folders: [],
  isLoading: false,
  selectedFolder: null,
  selectedType: null
};

const getters = {
  templatesByFolder: (state) => (folderId) =>
    state.templates.filter(t => t.folder_id === folderId),
  templatesByType: (state) => (type) =>
    state.templates.filter(t => t.document_type === type)
};

const actions = {
  async loadTemplates({ commit, rootState }) {
    commit('setLoading', true);
    const { data } = await fetchTemplates(rootState.accountId);
    commit('setTemplates', data);
    commit('setLoading', false);
  },
  // ... CRUD actions
};
```

## 5.13 Reaproveitar componentes existentes

Componentes do design system que já são usados em `plugins/patients/`:

| Pra que serve | Provável caminho/nome |
|---|---|
| Botão primário/secundário | `components-next/button/Button.vue` |
| Input/select | `components-next/input/...` |
| Modal | `components-next/modal/Modal.vue` |
| Ícone (Lucide) | `components-next/icon/Icon.vue` |
| Avatar | `components-next/avatar/...` |
| Toast/notificação | já existe via `useToast()` |
| Confirm dialog | já existe (usar mesmo padrão de `DocumentsTable.vue`) |

> **Inventariar antes de codar** essa lista olhando o `DocumentsTab.vue` atual — todos esses já estão sendo usados lá. Reuso máximo é meta.

## 5.14 Acessibilidade e atalhos

Atalhos do TipTap (já vêm prontos): `Cmd/Ctrl+B`, `Cmd/Ctrl+I`, `Cmd/Ctrl+U`, `Cmd/Ctrl+Z`, etc.
Atalhos customizados (sugestão):
- `Cmd/Ctrl + /` → abre painel de variáveis
- `Cmd/Ctrl + S` → salva template
- `Cmd/Ctrl + Shift + V` → cola sem formatação

## 5.15 Performance

- **Editor**: TipTap aguenta tranquilamente documento de 50 páginas com tabelas. Não precisa virtualização no MVP.
- **Save**: debounce de 1.5s, otimista (mostra "salvo" antes de confirmar HTTP).
- **Catálogo de variáveis**: cachear em memória após primeiro fetch.
- **Lista de templates**: paginação só vira preocupação acima de 200 templates (improvável na clínica média).
