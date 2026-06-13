// Extensão PageBreak — node atômico de bloco pra forçar uma página nova no
// PDF (ex: jogar a página de assinatura/anexo pra uma folha limpa). O
// PageBreak do TipTap Pages é Pro, então criamos o nosso.
//
// insertPageBreak() insere o node + um parágrafo logo após, pro cursor cair
// depois da quebra. O Renderer (Ruby) emite uma div com page-break-after.

import { Node, mergeAttributes } from '@tiptap/core';

export const PageBreak = Node.create({
  name: 'pageBreak',
  group: 'block',
  atom: true,
  selectable: true,

  parseHTML() {
    return [{ tag: 'div[data-page-break]' }];
  },

  renderHTML({ HTMLAttributes }) {
    return [
      'div',
      mergeAttributes(HTMLAttributes, {
        'data-page-break': 'true',
        class: 'page-break',
      }),
    ];
  },

  addCommands() {
    return {
      insertPageBreak:
        () =>
        ({ chain }) =>
          chain()
            .insertContent([{ type: this.name }, { type: 'paragraph' }])
            .run(),
    };
  },
});

export default PageBreak;
