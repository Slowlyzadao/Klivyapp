// HTML editor com preview live para super_admin (Administrate).
// Substitui o antigo Quill — mesma marcação de hook (`data-quill-field`)
// para não quebrar partials já em produção.
//
// - Painel esquerdo: textarea com HTML cru
// - Painel direito: iframe sandbox renderizando o HTML sanitizado
// - DOMPurify (allow permissivo) sanitiza antes do preview e antes do submit
// - Debounce 300ms no preview para não re-renderizar a cada tecla
// - Toolbar com snippets (h1/h2/h3/p/b/i/u/span/link/img/ul/li),
//   "Formatar" (pretty-print) e "Preview" (toggle)

import DOMPurify from 'dompurify';

const PREVIEW_DEBOUNCE_MS = 300;

// Whitelist permissiva: mantém estrutura/estilos que os autores usam em
// artigos da Central de Ajuda (full-doc HTML, <style>, tabelas, SVG,
// iframes para vídeos). O render final acontece dentro de um iframe
// sandbox sem `allow-scripts`, então mesmo se algo escapar daqui, scripts
// e event handlers não executam.
const PURIFY_CONFIG = {
  ADD_TAGS: ['style'],
  ADD_ATTR: ['target'],
  FORBID_TAGS: ['script', 'object', 'embed', 'base', 'form', 'input', 'button', 'textarea', 'select'],
  FORBID_ATTR: [
    // Event handlers (DOMPurify já remove on*, mas listamos por explicitude)
    'onerror', 'onload', 'onclick', 'onmouseover', 'onfocus', 'onblur',
    'onchange', 'onsubmit', 'onkeydown', 'onkeyup', 'onkeypress',
    'onmouseenter', 'onmouseleave', 'onmousedown', 'onmouseup',
    'onanimationend', 'onanimationstart', 'ontransitionend',
    // <meta http-equiv="refresh" content="0;url=javascript:..."> — vetor de
    // navegação maliciosa que sobrevive ao sandbox-sem-allow-scripts em alguns
    // browsers. Removendo o atributo, o meta fica inofensivo.
    'http-equiv',
    // formaction/formmethod sobrescrevem submit de form irmão, mas como
    // bloqueamos <form>/<input>/<button> via FORBID_TAGS, são redundantes.
    'formaction', 'formmethod',
  ],
  ALLOW_DATA_ATTR: true,
  ALLOW_UNKNOWN_PROTOCOLS: false,
};

// Hook em links externos: força noopener/noreferrer e bloqueia javascript:.
DOMPurify.addHook('afterSanitizeAttributes', node => {
  if (node.nodeName === 'A') {
    const href = node.getAttribute('href') || '';
    if (/^\s*javascript:/i.test(href)) node.removeAttribute('href');
    if (node.getAttribute('target') === '_blank') {
      node.setAttribute('rel', 'noopener noreferrer');
    }
  }
  if (node.nodeName === 'IMG') {
    const src = node.getAttribute('src') || '';
    if (/^\s*javascript:/i.test(src)) node.removeAttribute('src');
  }
});

function isFullDocument(html) {
  return /^\s*<(!doctype|html\b)/i.test(html || '');
}

function sanitize(html) {
  // WHOLE_DOCUMENT só quando há `<!DOCTYPE>`/`<html>`; senão DOMPurify
  // pode embrulhar fragmento num documento completo no retorno.
  return DOMPurify.sanitize(html || '', {
    ...PURIFY_CONFIG,
    WHOLE_DOCUMENT: isFullDocument(html),
  });
}

function debounce(fn, ms) {
  let t = null;
  return function debounced(...args) {
    clearTimeout(t);
    t = setTimeout(() => fn.apply(this, args), ms);
  };
}

const SNIPPETS = {
  h1:   { tpl: '<h1>${sel|Título}</h1>',                                          cursor: 4 },
  h2:   { tpl: '<h2>${sel|Subtítulo}</h2>',                                        cursor: 4 },
  h3:   { tpl: '<h3>${sel|Seção}</h3>',                                            cursor: 4 },
  p:    { tpl: '<p>${sel|Parágrafo}</p>',                                          cursor: 3 },
  b:    { tpl: '<strong>${sel|texto}</strong>',                                    cursor: 8 },
  i:    { tpl: '<em>${sel|texto}</em>',                                            cursor: 4 },
  u:    { tpl: '<u>${sel|texto}</u>',                                              cursor: 3 },
  span: { tpl: '<span class="">${sel|texto}</span>',                               cursor: 13 },
  link: { tpl: '<a href="https://" target="_blank" rel="noopener noreferrer">${sel|texto do link}</a>', cursor: 9 },
  img:  { tpl: '<img src="https://" alt="${sel|descrição}" />',                    cursor: 11 },
  ul:   { tpl: '<ul>\n  <li>${sel|item}</li>\n</ul>',                              cursor: 9 },
  li:   { tpl: '<li>${sel|item}</li>',                                             cursor: 4 },
};

function applySnippet(textarea, snippet) {
  const conf = SNIPPETS[snippet];
  if (!conf) return;
  const start = textarea.selectionStart;
  const end = textarea.selectionEnd;
  const selected = textarea.value.slice(start, end);
  const m = conf.tpl.match(/\$\{sel\|([^}]*)\}/);
  const placeholder = m ? m[1] : '';
  const filled = conf.tpl.replace(/\$\{sel\|[^}]*\}/, selected || placeholder);
  const before = textarea.value.slice(0, start);
  const after = textarea.value.slice(end);
  textarea.value = before + filled + after;
  // Posiciona cursor no conteúdo (selecionando placeholder, se vazio)
  if (selected) {
    const caret = before.length + filled.length;
    textarea.setSelectionRange(caret, caret);
  } else {
    const fillStart = before.length + conf.cursor;
    textarea.setSelectionRange(fillStart, fillStart + placeholder.length);
  }
  textarea.dispatchEvent(new Event('input', { bubbles: true }));
  textarea.focus();
}

// Pretty-print rudimentar (sem dependência externa).
// Quebra linhas em tags de bloco e indenta.
const BLOCK_TAGS = new Set([
  'html','head','body','article','section','header','footer','nav','main',
  'div','p','ul','ol','li','table','thead','tbody','tr','td','th','blockquote',
  'h1','h2','h3','h4','h5','h6','figure','figcaption','pre','style','script',
  'form','fieldset',
]);
const INLINE_VOID = new Set(['br','hr','img','input','meta','link','source','area','base','col','embed','param','track','wbr']);

function formatHtml(input) {
  const tokens = [];
  const re = /(<!--[\s\S]*?-->)|(<!doctype[^>]*>)|(<\/?[a-zA-Z][^>]*>)|([^<]+)/gi;
  let m;
  while ((m = re.exec(input)) !== null) {
    if (m[1] || m[2]) tokens.push({ kind: 'raw', text: m[1] || m[2] });
    else if (m[3]) {
      const tag = m[3];
      const isClose = /^<\//.test(tag);
      const nameMatch = tag.match(/^<\/?\s*([a-zA-Z0-9]+)/);
      const name = nameMatch ? nameMatch[1].toLowerCase() : '';
      const selfClose = /\/>$/.test(tag) || INLINE_VOID.has(name);
      tokens.push({ kind: 'tag', text: tag, name, isClose, selfClose });
    } else if (m[4]) {
      tokens.push({ kind: 'text', text: m[4] });
    }
  }

  const out = [];
  let depth = 0;
  const indent = (n) => '  '.repeat(Math.max(n, 0));
  // Tags cujo conteúdo deve ser preservado literalmente entre abertura e fechamento
  const PRE_LIKE = new Set(['pre','script','style','textarea']);
  let preserveDepth = 0;

  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    if (preserveDepth > 0) {
      out.push(t.text);
      if (t.kind === 'tag' && t.isClose && PRE_LIKE.has(t.name)) {
        preserveDepth--;
        if (preserveDepth === 0) out.push('\n');
      }
      continue;
    }
    if (t.kind === 'raw') {
      out.push((out.length ? '\n' : '') + indent(depth) + t.text);
    } else if (t.kind === 'tag') {
      if (t.isClose && BLOCK_TAGS.has(t.name)) depth = Math.max(depth - 1, 0);
      const isBlock = BLOCK_TAGS.has(t.name);
      if (isBlock) out.push((out.length ? '\n' : '') + indent(depth) + t.text);
      else out.push(t.text);
      if (!t.isClose && !t.selfClose && BLOCK_TAGS.has(t.name)) depth++;
      if (!t.isClose && !t.selfClose && PRE_LIKE.has(t.name)) preserveDepth++;
    } else {
      // texto entre tags: preserva mas tira whitespace puro
      const txt = t.text.replace(/\s+/g, ' ');
      if (txt.trim().length === 0) continue;
      const prev = tokens[i - 1];
      if (prev && prev.kind === 'tag' && BLOCK_TAGS.has(prev.name) && !prev.isClose) {
        out.push('\n' + indent(depth) + txt.trim());
      } else {
        out.push(txt);
      }
    }
  }
  return out.join('').replace(/\n{3,}/g, '\n\n').trim() + '\n';
}

function buildPreviewDoc(html) {
  // Se o autor escreveu um documento completo, usa como está. Senão, embrulha
  // num documento mínimo com as mesmas regras CSS base do drawer público
  // (HelpArticleDrawer.vue) para que o preview reflita o render final.
  const isFullDoc = /^\s*<(!doctype|html\b)/i.test(html);
  if (isFullDoc) return html;
  return `<!DOCTYPE html><html lang="pt-BR"><head>` +
    `<meta charset="UTF-8">` +
    `<meta name="viewport" content="width=device-width, initial-scale=1.0">` +
    `<base target="_parent">` +
    `<style>
      html, body { margin: 0; padding: 0; }
      body {
        font-family: -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', Roboto, sans-serif;
        color: #1f2937; line-height: 1.7; font-size: 15px; padding: 16px;
      }
      p { margin: 0 0 14px; }
      h1, h2, h3 { color: #0f172a; }
      h2 { font-size: 1.15em; font-weight: 700; margin: 22px 0 10px; }
      h3 { font-size: 1em; font-weight: 600; margin: 18px 0 8px; }
      ul, ol { padding-left: 20px; margin: 8px 0 14px; }
      li { margin-bottom: 4px; }
      blockquote { border-left: 3px solid #2c5cc5; padding-left: 14px; color: #475569; margin: 14px 0; }
      a { color: #2c5cc5; text-decoration: underline; }
      img, video, iframe { max-width: 100%; height: auto; border-radius: 8px; }
      pre, code { background: #f3f4f6; border-radius: 4px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
      code { padding: 2px 6px; font-size: 0.9em; }
      pre { padding: 12px 14px; overflow-x: auto; }
      pre code { background: none; padding: 0; }
    </style>` +
    `</head><body>${html}</body></html>`;
}

// --- Syntax highlighting (overlay sobre textarea) ---
//
// Tokenizamos o HTML em pedaços (doctype, comentário, tag, texto) e dentro
// de cada tag separamos `<`, nome, atributos (nome/igual/valor) e `>`.
// O resultado é colocado num `<pre><code>` posicionado atrás do textarea
// (cuja cor é transparente). Isso evita dependências (Prism/Highlight.js)
// e funciona com qualquer tamanho de conteúdo sem custo de runtime alto.

function escapeForOverlay(s) {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function highlightTagInner(tag) {
  // tag começa com `<` ou `</` e termina com `>` ou `/>`.
  const m = tag.match(/^(<\/?)([a-zA-Z][\w:-]*)([\s\S]*?)(\/?>)$/);
  if (!m) return escapeForOverlay(tag);
  const [, openBracket, name, attrsRaw, closeBracket] = m;

  // Atributos: nome opcional[ = "valor" | 'valor' | sem aspas ]
  const attrRe = /(\s+)([a-zA-Z_:][\w:.-]*)(\s*=\s*("[^"]*"|'[^']*'|[^\s>]+))?/g;
  let attrsHtml = '';
  let lastIdx = 0;
  let am;
  while ((am = attrRe.exec(attrsRaw)) !== null) {
    attrsHtml += escapeForOverlay(attrsRaw.slice(lastIdx, am.index));
    attrsHtml += escapeForOverlay(am[1]); // espaço
    attrsHtml += `<span class="hl-attr">${escapeForOverlay(am[2])}</span>`;
    if (am[3]) {
      const eqMatch = am[3].match(/^(\s*=\s*)([\s\S]*)$/);
      if (eqMatch) {
        attrsHtml += `<span class="hl-eq">${escapeForOverlay(eqMatch[1])}</span>`;
        attrsHtml += `<span class="hl-string">${escapeForOverlay(eqMatch[2])}</span>`;
      } else {
        attrsHtml += escapeForOverlay(am[3]);
      }
    }
    lastIdx = am.index + am[0].length;
  }
  attrsHtml += escapeForOverlay(attrsRaw.slice(lastIdx));

  return (
    `<span class="hl-bracket">${escapeForOverlay(openBracket)}</span>` +
    `<span class="hl-tag">${escapeForOverlay(name)}</span>` +
    attrsHtml +
    `<span class="hl-bracket">${escapeForOverlay(closeBracket)}</span>`
  );
}

function highlightHtml(input) {
  if (!input) return '';
  const re = /(<!--[\s\S]*?-->)|(<!doctype[^>]*>)|(<\/?[a-zA-Z][^>]*>)|([^<]+)/gi;
  let out = '';
  let m;
  while ((m = re.exec(input)) !== null) {
    if (m[1]) out += `<span class="hl-comment">${escapeForOverlay(m[1])}</span>`;
    else if (m[2]) out += `<span class="hl-doctype">${escapeForOverlay(m[2])}</span>`;
    else if (m[3]) out += highlightTagInner(m[3]);
    else if (m[4]) out += escapeForOverlay(m[4]);
  }
  // Adiciona uma linha em branco final pra evitar reposicionar o caret
  // quando o texto termina sem newline (workaround comum).
  if (input.endsWith('\n')) out += ' ';
  return out;
}

function setStatus(el, msg, kind) {
  if (!el) return;
  el.textContent = msg || '';
  el.classList.remove('is-warn', 'is-ok');
  if (kind === 'warn') el.classList.add('is-warn');
  else if (kind === 'ok') el.classList.add('is-ok');
}

function syncGutter(textarea, gutterEl) {
  if (!gutterEl) return;
  const lines = (textarea.value.match(/\n/g) || []).length + 1;
  // Limita a renderização a um teto razoável; navegador tolera bem isso.
  const max = Math.max(lines, 1);
  let s = '';
  for (let i = 1; i <= max; i++) s += i + '\n';
  gutterEl.textContent = s;
}

function syncGutterScroll(textarea, gutterEl) {
  if (!gutterEl) return;
  gutterEl.scrollTop = textarea.scrollTop;
}

function init(wrap) {
  if (wrap.dataset.htmlEditorReady === '1') return;
  wrap.dataset.htmlEditorReady = '1';

  const textarea = wrap.querySelector('[data-source]');
  const hidden = wrap.querySelector('[data-input]');
  const previewIframe = wrap.querySelector('[data-preview]');
  const gutter = wrap.querySelector('[data-gutter]');
  const lengthEl = wrap.querySelector('[data-length]');
  const statusEl = wrap.querySelector('[data-status-msg]');
  const highlightEl = wrap.querySelector('[data-highlight] code');
  if (!textarea || !hidden) return;

  function updateHighlight() {
    if (!highlightEl) return;
    highlightEl.innerHTML = highlightHtml(textarea.value);
  }

  function syncHighlightScroll() {
    const pre = highlightEl?.parentElement;
    if (!pre) return;
    pre.scrollTop = textarea.scrollTop;
    pre.scrollLeft = textarea.scrollLeft;
  }

  const renderPreview = () => {
    const raw = textarea.value || '';
    let clean;
    try {
      clean = sanitize(raw);
      const removed = DOMPurify.removed || [];
      if (removed.length) {
        setStatus(statusEl, `Sanitização removeu ${removed.length} elemento(s) inseguro(s).`, 'warn');
      } else {
        setStatus(statusEl, '', null);
      }
    } catch (err) {
      clean = '';
      setStatus(statusEl, 'Erro ao sanitizar HTML.', 'warn');
    }
    if (previewIframe) {
      previewIframe.srcdoc = buildPreviewDoc(clean);
    }
  };

  const debouncedPreview = debounce(renderPreview, PREVIEW_DEBOUNCE_MS);

  const sync = () => {
    // O hidden carrega o HTML cru durante a edição (preview já sanitizado).
    // Sanitização final aplicada no submit (vide listener abaixo).
    hidden.value = textarea.value;
    if (lengthEl) lengthEl.textContent = textarea.value.length;
    syncGutter(textarea, gutter);
    updateHighlight();
    syncHighlightScroll();
    debouncedPreview();
  };

  textarea.addEventListener('input', sync);
  textarea.addEventListener('scroll', () => {
    syncGutterScroll(textarea, gutter);
    syncHighlightScroll();
  });
  textarea.addEventListener('keydown', (e) => {
    // Tab insere 2 espaços em vez de mudar foco
    if (e.key === 'Tab') {
      e.preventDefault();
      const s = textarea.selectionStart;
      const en = textarea.selectionEnd;
      textarea.value = textarea.value.slice(0, s) + '  ' + textarea.value.slice(en);
      textarea.setSelectionRange(s + 2, s + 2);
      sync();
    }
  });

  // Snippets
  wrap.querySelectorAll('[data-snippet]').forEach((btn) => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      applySnippet(textarea, btn.dataset.snippet);
    });
  });

  function setViewMode(mode) {
    // mode: 'split' | 'html' | 'preview'
    wrap.classList.toggle('ha-html--only-html', mode === 'html');
    wrap.classList.toggle('ha-html--only-preview', mode === 'preview');
    const htmlBtn = wrap.querySelector('[data-action="view-html"]');
    const splitBtn = wrap.querySelector('[data-action="view-split"]');
    const prevBtn = wrap.querySelector('[data-action="view-preview"]');
    htmlBtn?.classList.toggle('is-active', mode === 'html');
    splitBtn?.classList.toggle('is-active', mode === 'split');
    prevBtn?.classList.toggle('is-active', mode === 'preview');
  }

  // Botões de ação
  wrap.querySelectorAll('[data-action]').forEach((btn) => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      const action = btn.dataset.action;
      if (action === 'format') {
        try {
          textarea.value = formatHtml(textarea.value);
          sync();
          setStatus(statusEl, 'HTML reindentado.', 'ok');
          setTimeout(() => setStatus(statusEl, '', null), 1500);
        } catch (err) {
          setStatus(statusEl, 'Não foi possível formatar.', 'warn');
        }
      } else if (action === 'view-html') {
        setViewMode('html');
      } else if (action === 'view-split') {
        setViewMode('split');
      } else if (action === 'view-preview') {
        setViewMode('preview');
      }
    });
  });

  // Boot: split é o modo default
  setViewMode('split');

  // Sanitização final no submit (defesa em profundidade — o iframe do drawer
  // já bloqueia scripts via sandbox, isto é uma camada extra contra autor
  // comprometido). Se nada perigoso for removido, o output é idêntico ao input.
  const form = wrap.closest('form');
  if (form) {
    form.addEventListener('submit', () => {
      hidden.value = sanitize(textarea.value);
    });
  }

  // Boot inicial
  sync();
  renderPreview();
}

document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('[data-quill-field]').forEach(init);
});
