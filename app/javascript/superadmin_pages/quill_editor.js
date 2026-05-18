import Quill from 'quill';
import 'quill/dist/quill.snow.css';

const TOOLBAR = [
  [{ header: [1, 2, 3, 4, false] }],
  [{ font: [] }],
  [{ size: ['small', false, 'large', 'huge'] }],
  ['bold', 'italic', 'underline', 'strike'],
  [{ color: [] }, { background: [] }],
  [{ script: 'sub' }, { script: 'super' }],
  [{ list: 'ordered' }, { list: 'bullet' }],
  [{ indent: '-1' }, { indent: '+1' }],
  [{ align: [] }],
  ['blockquote', 'code-block'],
  ['link', 'image', 'video'],
  ['clean'],
];

function initQuill(wrap) {
  if (wrap.dataset.quillReady === '1') return;
  wrap.dataset.quillReady = '1';

  const editorEl = wrap.querySelector('.ha-quill-editor');
  const htmlArea = wrap.querySelector('.ha-quill-html');
  const hidden = wrap.querySelector('.ha-quill-input');
  if (!editorEl || !hidden) return;

  const initialHtml = hidden.value || '';
  const quill = new Quill(editorEl, {
    theme: 'snow',
    modules: { toolbar: TOOLBAR },
  });
  if (initialHtml) {
    quill.clipboard.dangerouslyPasteHTML(initialHtml);
  }

  const sync = () => {
    if (wrap.classList.contains('ha-quill--html')) {
      hidden.value = htmlArea.value;
    } else {
      hidden.value = quill.getSemanticHTML
        ? quill.getSemanticHTML()
        : quill.root.innerHTML;
    }
  };

  quill.on('text-change', sync);
  htmlArea.addEventListener('input', sync);

  // HTML mode toggle injected into the toolbar.
  const toolbar = wrap.querySelector('.ql-toolbar');
  if (toolbar) {
    const wrapBtn = document.createElement('span');
    wrapBtn.className = 'ql-formats ha-quill-html-toggle-wrap';
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'ha-quill-html-toggle';
    btn.textContent = '</>';
    btn.title = 'Alternar entre editor visual e HTML bruto';
    wrapBtn.appendChild(btn);
    toolbar.appendChild(wrapBtn);

    btn.addEventListener('click', () => {
      const goingHtml = !wrap.classList.contains('ha-quill--html');
      if (goingHtml) {
        htmlArea.value = quill.getSemanticHTML
          ? quill.getSemanticHTML()
          : quill.root.innerHTML;
        wrap.classList.add('ha-quill--html');
      } else {
        quill.clipboard.dangerouslyPasteHTML(htmlArea.value || '');
        wrap.classList.remove('ha-quill--html');
      }
      sync();
    });
  }

  // Final sync on form submit so nothing is lost.
  const form = wrap.closest('form');
  if (form) form.addEventListener('submit', sync);
}

document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('[data-quill-field]').forEach(initQuill);
});
