// Extensão Indent — adiciona um NÍVEL inteiro de recuo (0..8) a paragraph +
// heading, com comandos indent()/outdent() que fazem clamp.
//
// Guardamos um LEVEL (não CSS bruto) pra manter CSS não-confiável fora do
// PDF — o Renderer (Ruby) é dono da unidade (em). Coexiste com textAlign +
// lineHeight no mesmo nó. Em listas, a toolbar roteia pra
// sinkListItem/liftListItem em vez destes comandos.
//
// CRÍTICO: o passo de 2em no renderHTML DEVE bater com renderer.rb
// INDENT_STEP_EM = 2, senão editor e PDF divergem visualmente.

import { Extension } from '@tiptap/core';

export const Indent = Extension.create({
  name: 'indent',

  addOptions() {
    return { types: ['paragraph', 'heading'], minLevel: 0, maxLevel: 8 };
  },

  addGlobalAttributes() {
    return [
      {
        types: this.options.types,
        attributes: {
          indent: {
            default: 0,
            parseHTML: (el) => parseInt(el.getAttribute('data-indent'), 10) || 0,
            renderHTML: (attrs) => {
              const level = attrs.indent || 0;
              return level
                ? { 'data-indent': level, style: `margin-left: ${level * 2}em` }
                : {};
            },
          },
        },
      },
    ];
  },

  addCommands() {
    const clamp = (value) =>
      Math.min(this.options.maxLevel, Math.max(this.options.minLevel, value));

    const shift = (delta) =>
      ({ editor, commands }) =>
        this.options.types.every((type) => {
          const current = editor.getAttributes(type).indent || 0;
          return commands.updateAttributes(type, { indent: clamp(current + delta) });
        });

    return {
      indent: () => shift(1),
      outdent: () => shift(-1),
    };
  },
});

export default Indent;
