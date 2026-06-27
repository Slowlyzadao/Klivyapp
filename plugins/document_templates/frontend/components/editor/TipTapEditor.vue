<script setup>
// Wrapper do TipTap. Configura extensões, inicializa o editor com o
// content_json passado via prop, emite update v-model com o JSON atualizado.
//
// Mantém-se "burro" — não conhece o store. Pai (TemplateEditor.vue) cuida
// de persistência, atalhos globais (Cmd+S), navegação.

import { onBeforeUnmount, watch } from 'vue';
import { useEditor, EditorContent } from '@tiptap/vue-3';
import StarterKit from '@tiptap/starter-kit';
import Underline from '@tiptap/extension-underline';
import TextAlign from '@tiptap/extension-text-align';
import TextStyle from '@tiptap/extension-text-style';
import Color from '@tiptap/extension-color';
import FontFamily from '@tiptap/extension-font-family';
import Link from '@tiptap/extension-link';
import Table from '@tiptap/extension-table';
import TableRow from '@tiptap/extension-table-row';
import TableCell from '@tiptap/extension-table-cell';
import TableHeader from '@tiptap/extension-table-header';
import Placeholder from '@tiptap/extension-placeholder';
import CharacterCount from '@tiptap/extension-character-count';
import Highlight from '@tiptap/extension-highlight';
import Subscript from '@tiptap/extension-subscript';
import Superscript from '@tiptap/extension-superscript';
import Image from '@tiptap/extension-image';

import VariableExtension from './extensions/VariableExtension';
import VariableSuggestionExtension from './extensions/VariableSuggestionExtension';
import FontSize from './extensions/FontSize';
import LineHeight from './extensions/LineHeight';
import Indent from './extensions/Indent';
import PageBreak from './extensions/PageBreak';
import { sanitizeProseMirrorDoc } from '../../utils/proseMirrorSanitize';

const props = defineProps({
  modelValue: {
    type: Object,
    default: () => ({ type: 'doc', content: [{ type: 'paragraph' }] }),
  },
  placeholder: { type: String, default: '' },
  readonly: { type: Boolean, default: false },
  // Factory que retorna a lista de variáveis disponível pro suggestion "/".
  // Tipicamente `() => store.variables`.
  getVariables: { type: Function, default: () => () => [] },
});

const emit = defineEmits(['update:modelValue', 'editor-ready']);

// Referência do último JSON que NÓS emitimos. Serve pra distinguir, no watch
// de modelValue, o "eco" da nossa própria edição (mesma referência → ignora)
// de uma troca externa real de conteúdo (carregar outro template → sincroniza).
// Sem isso, toda tecla pagava sanitize + getJSON + 2× JSON.stringify do doc.
let lastEmitted = null;

const editor = useEditor({
  // Sanitiza ANTES do ProseMirror montar — um text node vazio no content
  // faria o TipTap descartar o doc inteiro e abrir vazio. Ver
  // utils/proseMirrorSanitize.js.
  content: sanitizeProseMirrorDoc(props.modelValue),
  editable: !props.readonly,
  extensions: [
    // heading levels 1-4 alimentam o dropdown de estilos (Título + H1-H3).
    StarterKit.configure({
      history: { depth: 100 },
      heading: { levels: [1, 2, 3, 4] },
    }),
    Underline,
    TextStyle,
    Color,
    FontFamily.configure({ types: ['textStyle'] }),
    FontSize,
    Highlight.configure({ multicolor: true }),
    Subscript,
    Superscript,
    TextAlign.configure({ types: ['heading', 'paragraph'] }),
    LineHeight,
    Indent,
    Link.configure({ openOnClick: false }),
    Image.configure({ inline: false, allowBase64: false }),
    Table.configure({ resizable: true }),
    TableRow,
    TableCell,
    TableHeader,
    PageBreak,
    Placeholder.configure({
      placeholder: props.placeholder ||
        'Digite o conteúdo do template — use "/" para inserir variáveis',
    }),
    CharacterCount,
    VariableExtension,
    VariableSuggestionExtension.configure({
      getVariables: props.getVariables,
    }),
  ],
  onUpdate({ editor: ed }) {
    const json = ed.getJSON();
    lastEmitted = json;
    emit('update:modelValue', json);
  },
  onCreate({ editor: ed }) {
    emit('editor-ready', ed);
  },
});

// Atualização externa (carregar template diferente) — sincroniza sem
// disparar onUpdate (segundo argumento `false`). O early-return por referência
// ignora o eco da nossa própria edição (ver `lastEmitted`), evitando o custo
// O(doc) de sanitize + getJSON + stringify a cada tecla.
watch(
  () => props.modelValue,
  (next) => {
    if (!editor.value) return;
    if (next === lastEmitted) return;
    const clean = sanitizeProseMirrorDoc(next);
    const current = editor.value.getJSON();
    if (JSON.stringify(current) !== JSON.stringify(clean)) {
      editor.value.commands.setContent(clean, false);
    }
  }
);

defineExpose({
  insertVariable: (attrs) => {
    editor.value
      ?.chain()
      .focus()
      .insertContent({ type: 'variable', attrs })
      .run();
  },
  getEditor: () => editor.value,
});

onBeforeUnmount(() => editor.value?.destroy());
</script>

<template>
  <EditorContent :editor="editor" class="tiptap-editor" />
</template>

<style lang="scss" scoped>
@use '../../styles/editor/editor';
</style>
