// Extensão FontSize — adiciona o atributo `fontSize` ao mark textStyle do
// TipTap (não há extensão oficial gratuita no v2). Serializa como
// `style="font-size: 14px"` no HTML e no JSON ProseMirror via textStyle.
//
// Comandos: setFontSize(size) / unsetFontSize(). O backend Renderer lê
// textStyle.fontSize e aplica no PDF (mesmo caminho do fontFamily/color).

import { Extension } from '@tiptap/core';

export const FontSize = Extension.create({
  name: 'fontSize',

  addOptions() {
    return { types: ['textStyle'] };
  },

  addGlobalAttributes() {
    return [
      {
        types: this.options.types,
        attributes: {
          fontSize: {
            default: null,
            parseHTML: (element) => element.style.fontSize || null,
            renderHTML: (attributes) => {
              if (!attributes.fontSize) return {};
              return { style: `font-size: ${attributes.fontSize}` };
            },
          },
        },
      },
    ];
  },

  addCommands() {
    return {
      setFontSize:
        (size) =>
        ({ chain }) =>
          chain().setMark('textStyle', { fontSize: size }).run(),
      unsetFontSize:
        () =>
        ({ chain }) =>
          chain().setMark('textStyle', { fontSize: null }).removeEmptyTextStyle().run(),
    };
  },
});

export default FontSize;
