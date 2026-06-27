// Suggestion plugin do TipTap pra abrir o VariablePickerMenu quando o user
// digita "/" no editor. Usa tippy.js como popup container.
//
// Por que NÃO usar @tiptap/extension-mention diretamente: o Mention insere
// um node `mention` próprio. Já temos nosso node `variable` com schema
// estável — então usamos só o trigger `Suggestion` (que vem incluído no
// starter-kit / @tiptap/suggestion) e inserimos nosso node ao confirmar.

import { VueRenderer } from '@tiptap/vue-3';
import tippy from 'tippy.js';
import VariablePickerMenu from '../VariablePickerMenu.vue';

// Recebe o store/composable pra ler a lista. Em vez de instanciá-lo aqui
// (composable só pode rodar no setup do componente), o pai injeta a
// função que retorna `variables.value` no momento da chamada.
export function buildVariableSuggestion(getVariables) {
  return {
    char: '/',
    startOfLine: false,
    allowSpaces: false,

    items: ({ query }) => {
      const q = String(query || '').toLowerCase();
      const all = getVariables() || [];
      if (!q) return all.slice(0, 12);
      return all
        .filter(v =>
          v.label.toLowerCase().includes(q) ||
          v.key.toLowerCase().includes(q)
        )
        .slice(0, 12);
    },

    command: ({ editor, range, props }) => {
      // Remove o "/" digitado e insere o node variable no lugar.
      editor
        .chain()
        .focus()
        .deleteRange(range)
        .insertContent({
          type: 'variable',
          attrs: {
            key: props.key,
            label: props.label,
            fallback: '_______',
          },
        })
        .insertContent(' ')
        .run();
    },

    render: () => {
      let component;
      let popup;
      let highlightedIndex = 0;

      return {
        onStart: (props) => {
          highlightedIndex = 0;
          component = new VueRenderer(VariablePickerMenu, {
            props: {
              items: props.items,
              highlightedIndex,
              'onUpdate:highlightedIndex': (i) => {
                highlightedIndex = i;
                component.updateProps({ highlightedIndex });
              },
              onSelect: (variable) =>
                props.command({ key: variable.key, label: variable.label }),
            },
            editor: props.editor,
          });

          if (!props.clientRect) return;

          popup = tippy('body', {
            getReferenceClientRect: props.clientRect,
            appendTo: () => document.body,
            content: component.element,
            showOnCreate: true,
            interactive: true,
            trigger: 'manual',
            placement: 'bottom-start',
            maxWidth: 'none',
          });
        },

        onUpdate: (props) => {
          // A query mudou → a lista filtrada é outra. Reseta o destaque pro
          // topo (UX Notion/Linear) pra não ficar apontando um índice que não
          // existe mais na nova lista (senão o Enter inseriria a variável
          // errada — ver clamp defensivo no onKeyDown do VariablePickerMenu).
          highlightedIndex = 0;
          component.updateProps({
            items: props.items,
            highlightedIndex,
            onSelect: (variable) =>
              props.command({ key: variable.key, label: variable.label }),
          });
          popup?.[0]?.setProps({ getReferenceClientRect: props.clientRect });
        },

        onKeyDown: (props) => {
          if (props.event.key === 'Escape') {
            popup?.[0]?.hide();
            return true;
          }
          return component.ref?.onKeyDown?.(props) || false;
        },

        onExit: () => {
          popup?.[0]?.destroy();
          component?.destroy();
        },
      };
    },
  };
}

export default buildVariableSuggestion;
