// Extensão LineHeight — adiciona o atributo `lineHeight` aos nós de BLOCO
// (paragraph + heading). O LineHeight oficial do TipTap só existe no v3; no
// v2 precisamos de uma extensão custom.
//
// Diferente do FontSize (que é um MARK via setMark no textStyle), aqui o
// espaçamento é um atributo do nó de bloco — aplicado via updateAttributes.
// Serializa como `style="line-height: 1.5"`. O Renderer (Ruby) lê
// attrs.lineHeight em paragraph_style com sanitização numérica estrita.
//
// Exporta named + default (igual FontSize.js) pro import default funcionar.

import { Extension } from '@tiptap/core';

export const LineHeight = Extension.create({
  name: 'lineHeight',

  addOptions() {
    return {
      types: ['paragraph', 'heading'],
      heights: ['1', '1.15', '1.5', '2'],
      defaultHeight: null,
    };
  },

  addGlobalAttributes() {
    return [
      {
        types: this.options.types,
        attributes: {
          lineHeight: {
            default: this.options.defaultHeight,
            parseHTML: (el) => el.style.lineHeight || null,
            renderHTML: (attrs) =>
              attrs.lineHeight ? { style: `line-height: ${attrs.lineHeight}` } : {},
          },
        },
      },
    ];
  },

  addCommands() {
    return {
      setLineHeight:
        (height) =>
        ({ commands }) => {
          if (!this.options.heights.includes(String(height))) return false;
          return this.options.types.every((type) =>
            commands.updateAttributes(type, { lineHeight: String(height) })
          );
        },
      unsetLineHeight:
        () =>
        ({ commands }) =>
          this.options.types.every((type) =>
            commands.resetAttributes(type, 'lineHeight')
          ),
    };
  },
});

export default LineHeight;
