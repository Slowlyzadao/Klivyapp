// Extensão TipTap que registra o suggestion plugin do "/" dentro do editor.
// Aceita uma factory de items (variables) e usa o handler genérico em
// VariableSuggestion.js pra construir a config completa.
//
// Uso (em TipTapEditor.vue):
//   VariableSuggestionExtension.configure({
//     getVariables: () => store.variables,
//   })

import { Extension } from '@tiptap/core';
import Suggestion from '@tiptap/suggestion';
import { buildVariableSuggestion } from './VariableSuggestion';

export const VariableSuggestionExtension = Extension.create({
  name: 'variableSuggestion',

  addOptions() {
    return {
      // Factory que retorna a lista atual de variáveis (pode ser computed
      // do store, vai ser reavaliada em cada `items` callback).
      getVariables: () => [],
    };
  },

  addProseMirrorPlugins() {
    const suggestionConfig = buildVariableSuggestion(this.options.getVariables);
    return [
      Suggestion({
        editor: this.editor,
        ...suggestionConfig,
      }),
    ];
  },
});

export default VariableSuggestionExtension;
