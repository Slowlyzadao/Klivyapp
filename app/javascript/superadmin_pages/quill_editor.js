import Quill from 'quill';
import 'quill/dist/quill.snow.css';

const TOOLBAR = [
  [{ header: [1, 2, 3, 4, 5, 6, false] }],
  [{ font: [] }, { size: ['small', false, 'large', 'huge'] }],
  ['bold', 'italic', 'underline', 'strike'],
  [{ color: [] }, { background: [] }],
  [{ script: 'sub' }, { script: 'super' }],
  [{ list: 'ordered' }, { list: 'bullet' }, { list: 'check' }],
  [{ indent: '-1' }, { indent: '+1' }],
  [{ align: [] }],
  ['blockquote', 'code-block'],
  ['link', 'image', 'video'],
  ['clean'],
];

function imageHandler(quill) {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = 'image/*';
  input.style.display = 'none';
  document.body.appendChild(input);

  input.addEventListener('change', () => {
    const file = input.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = e => {
      const range = quill.getSelection(true);
      quill.insertEmbed(range.index, 'image', e.target.result, Quill.sources.USER);
      quill.setSelection(range.index + 1, Quill.sources.SILENT);
    };
    reader.readAsDataURL(file);
    document.body.removeChild(input);
  });

  input.click();
}

function videoHandler(quill) {
  const url = prompt('Cole a URL do vídeo (YouTube, Vimeo, ou link direto):');
  if (!url) return;

  // Convert YouTube watch URL to embed URL
  let embedUrl = url;
  const ytMatch = url.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/)([A-Za-z0-9_-]{11})/);
  if (ytMatch) {
    embedUrl = `https://www.youtube.com/embed/${ytMatch[1]}`;
  }
  // Convert Vimeo URL to embed URL
  const vimeoMatch = url.match(/vimeo\.com\/(\d+)/);
  if (vimeoMatch) {
    embedUrl = `https://player.vimeo.com/video/${vimeoMatch[1]}`;
  }

  const range = quill.getSelection(true);
  quill.insertEmbed(range.index, 'video', embedUrl, Quill.sources.USER);
  quill.setSelection(range.index + 1, Quill.sources.SILENT);
}

function initQuillEditor(wrap) {
  const hiddenInput  = wrap.querySelector('.ha-quill-hidden');
  const htmlTextarea = wrap.querySelector('.ha-quill-html-textarea');
  const editorEl     = wrap.querySelector('.ha-quill-editor');
  if (!editorEl || !hiddenInput) return;

  const quill = new Quill(editorEl, {
    theme: 'snow',
    placeholder: 'Escreva o conteúdo do artigo aqui...',
    modules: {
      toolbar: {
        container: TOOLBAR,
        handlers: {
          image: () => imageHandler(quill),
          video: () => videoHandler(quill),
        },
      },
    },
  });

  // Load existing content
  const initialHTML = hiddenInput.value.trim();
  if (initialHTML) {
    quill.clipboard.dangerouslyPasteHTML(initialHTML);
    quill.setSelection(0, 0);
  }

  // Sync to hidden input on every change
  quill.on('text-change', () => {
    hiddenInput.value = quill.getSemanticHTML();
  });

  // ── Custom HTML toggle button ──────────────────────────────
  let htmlMode = false;
  const toolbarEl = wrap.querySelector('.ql-toolbar');
  const quillContainer = wrap.querySelector('.ql-container');

  const htmlGroup = document.createElement('span');
  htmlGroup.className = 'ql-formats';
  const htmlBtn = document.createElement('button');
  htmlBtn.type = 'button';
  htmlBtn.className = 'ql-html-toggle';
  htmlBtn.title = 'Editar HTML bruto';
  htmlBtn.textContent = '</>';
  htmlGroup.appendChild(htmlBtn);
  toolbarEl.appendChild(htmlGroup);

  htmlBtn.addEventListener('mousedown', e => {
    e.preventDefault();
    htmlMode = !htmlMode;
    if (htmlMode) {
      htmlTextarea.value = quill.getSemanticHTML();
      quillContainer.style.display = 'none';
      htmlTextarea.style.display = 'block';
      htmlBtn.classList.add('ql-active');
    } else {
      quill.clipboard.dangerouslyPasteHTML(htmlTextarea.value);
      hiddenInput.value = htmlTextarea.value;
      htmlTextarea.style.display = 'none';
      quillContainer.style.display = '';
      htmlBtn.classList.remove('ql-active');
    }
  });

  // Final sync on form submit
  const form = wrap.closest('form');
  if (form) {
    form.addEventListener('submit', () => {
      hiddenInput.value = htmlMode
        ? htmlTextarea.value
        : quill.getSemanticHTML();
    });
  }
}

document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('.ha-quill-wrap').forEach(initQuillEditor);
});
