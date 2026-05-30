// Custom node TipTap pra representar uma variável dinâmica dentro do
// documento. Renderiza como chip (NodeView Vue), não-editável (atom),
// serializa pro JSON ProseMirror com atributos estáveis:
//
//   {
//     "type": "variable",
//     "attrs": {
//       "key":      "patient.full_name",   // chave do catálogo (estável)
//       "label":    "Nome do paciente",     // o que aparece no chip
//       "fallback": "_______",              // texto se valor for null no render
//       "format":   null                    // override opcional do formatter
//     }
//   }
//
// Backend (DocumentTemplate model + Renderer da Fase 3) consome esse JSON
// sem precisar entender HTML — a fonte da verdade do template é o JSON.

import { Node, mergeAttributes } from '@tiptap/core';
import { VueNodeViewRenderer } from '@tiptap/vue-3';
import VariableNodeView from '../VariableNodeView.vue';

export const VariableExtension = Node.create({
  name: 'variable',

  group: 'inline',
  inline: true,
  selectable: true,
  atom: true,
  draggable: false,

  addAttributes() {
    return {
      key: {
        default: null,
        parseHTML: (el) => el.getAttribute('data-key'),
        renderHTML: (attrs) => (attrs.key ? { 'data-key': attrs.key } : {}),
      },
      label: {
        default: null,
        parseHTML: (el) => el.getAttribute('data-label'),
        renderHTML: (attrs) => (attrs.label ? { 'data-label': attrs.label } : {}),
      },
      fallback: {
        default: '_______',
        parseHTML: (el) => el.getAttribute('data-fallback') || '_______',
        renderHTML: (attrs) => ({ 'data-fallback': attrs.fallback || '_______' }),
      },
      format: {
        default: null,
        parseHTML: (el) => el.getAttribute('data-format'),
        renderHTML: (attrs) => (attrs.format ? { 'data-format': attrs.format } : {}),
      },
    };
  },

  parseHTML() {
    return [{ tag: 'span[data-variable]' }];
  },

  renderHTML({ HTMLAttributes }) {
    return [
      'span',
      mergeAttributes(HTMLAttributes, {
        'data-variable': 'true',
        class: 'tiptap-variable-chip',
      }),
      `{{ ${HTMLAttributes['data-label'] || HTMLAttributes['data-key'] || ''} }}`,
    ];
  },

  addNodeView() {
    return VueNodeViewRenderer(VariableNodeView);
  },

  addCommands() {
    return {
      insertVariable:
        (attrs) =>
        ({ commands }) =>
          commands.insertContent({ type: this.name, attrs }),
    };
  },
});

export default VariableExtension;
