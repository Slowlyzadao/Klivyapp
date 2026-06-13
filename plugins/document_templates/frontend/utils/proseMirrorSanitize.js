// Sanitiza um documento ProseMirror antes de entregá-lo ao TipTap.
//
// Motivo: o ProseMirror proíbe text nodes vazios ({ type:'text', text:'' }).
// Ao montar o editor, `schema.nodeFromJSON` lança
//   RangeError: Empty text nodes are not allowed
// e o TipTap (com `enableContentCheck:false`, que é o default) NÃO propaga o
// erro — ele DESCARTA o documento inteiro e abre o editor em branco
// (só o placeholder aparece). Ou seja: um único text vazio, vindo de seed
// legado, clone ou import, "apaga" o template inteiro na tela.
//
// Esta função remove recursivamente os text nodes inválidos preservando o
// resto da estrutura. Parágrafos que ficam sem filhos viram parágrafos
// vazios (content: []) — válidos no ProseMirror e renderizados como linha
// em branco, que era a intenção original do `paragraph('')` no seed.
export function sanitizeProseMirrorDoc(doc) {
  if (!doc || typeof doc !== 'object') return doc;

  const prune = nodes => {
    if (!Array.isArray(nodes)) return nodes;
    return nodes.reduce((acc, node) => {
      if (!node || typeof node !== 'object') return acc;
      // Descarta text node vazio/sem texto.
      if (node.type === 'text' && String(node.text ?? '').length === 0) {
        return acc;
      }
      const next = { ...node };
      if (Array.isArray(node.content)) next.content = prune(node.content);
      acc.push(next);
      return acc;
    }, []);
  };

  return { ...doc, content: prune(doc.content) };
}

export default sanitizeProseMirrorDoc;
