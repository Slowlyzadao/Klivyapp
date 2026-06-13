<script setup>
// Toolbar do editor — layout equivalente ao Google Docs, escopado pra
// contratos/consentimentos. Ordem dos grupos (esquerda → direita):
//   histórico | estilos | fonte | tamanho(stepper) | formato inline +
//   sub/sobrescrito | cor texto | realce | limpar formatação |
//   inserir (link/unlink/imagem/tabela/menu-tabela/régua/citação/
//   caractere-especial/quebra-página) | alinhamento | espaçamento |
//   listas | recuo
//
// Variáveis: inseridas pela aba "Variáveis" da sidebar ou pelo atalho "/".
//
// Recebe `editor` (instância TipTap). Não fala com o store — tudo via API
// do TipTap. Estado lido inline (mesmo padrão reativo do isActive).

import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import EditorToolbarButton from './EditorToolbarButton.vue';
import EditorToolbarSelect from './EditorToolbarSelect.vue';
import EditorStyleSelect from './EditorStyleSelect.vue';
import EditorFontSizeStepper from './EditorFontSizeStepper.vue';
import EditorColorPicker from './EditorColorPicker.vue';
import EditorTableMenu from './EditorTableMenu.vue';
import SpecialCharPicker from './SpecialCharPicker.vue';
import PromptDialog from '../modals/PromptDialog.vue';
import { usePrompt } from '../../composables/useDialogs';
import { FONT_FAMILIES, LINE_SPACINGS } from '../../constants/editorFonts';

const props = defineProps({
  editor: { type: Object, required: true },
});

const { t } = useI18n();

// Um único PromptDialog serve link e imagem (abertos um de cada vez).
const { promptState, prompt, onSubmit, onCancel } = usePrompt();

const fontFamilies = FONT_FAMILIES;
const lineSpacings = LINE_SPACINGS;

const isActive = (name, attrs) => props.editor.isActive(name, attrs);
const cmd = (chainFn) => chainFn(props.editor.chain().focus()).run();
const setAlign = (alignment) => cmd((c) => c.setTextAlign(alignment));

// ── Fonte ─────────────────────────────────────────────────────────────
const currentFontFamily = () =>
  props.editor.getAttributes('textStyle').fontFamily || '';
const setFontFamily = (value) => {
  const chain = props.editor.chain().focus();
  if (value) chain.setFontFamily(value).run();
  else chain.unsetFontFamily().run();
};

// ── Espaçamento de linha ────────────────────────────────────────────────
const currentLineHeight = () => {
  const types = ['paragraph', 'heading'];
  for (const type of types) {
    const lh = props.editor.getAttributes(type).lineHeight;
    if (lh) return String(lh);
  }
  return '';
};
const setLineSpacing = (value) => {
  const chain = props.editor.chain().focus();
  if (value) chain.setLineHeight(value).run();
  else chain.unsetLineHeight().run();
};

// ── Link / imagem (via PromptDialog) ────────────────────────────────────
const insertLink = async () => {
  const url = await prompt({
    title: t('DOCUMENT_TEMPLATES.EDITOR.INSERT_LINK'),
    label: t('DOCUMENT_TEMPLATES.EDITOR.LINK_LABEL'),
    placeholder: 'https://...',
    defaultValue: props.editor.getAttributes('link').href || '',
    confirmLabel: t('DOCUMENT_TEMPLATES.EDITOR.INSERT_LINK'),
    cancelLabel: t('DOCUMENT_TEMPLATES.MODAL.CANCEL'),
    inputType: 'url',
  });
  if (url) {
    props.editor.chain().focus().extendMarkRange('link').setLink({ href: url }).run();
  }
};

const removeLink = () => props.editor.chain().focus().unsetLink().run();

const insertImage = async () => {
  const url = await prompt({
    title: t('DOCUMENT_TEMPLATES.EDITOR.INSERT_IMAGE'),
    label: t('DOCUMENT_TEMPLATES.EDITOR.IMAGE_URL_LABEL'),
    placeholder: 'https://...',
    confirmLabel: t('DOCUMENT_TEMPLATES.EDITOR.INSERT_IMAGE'),
    cancelLabel: t('DOCUMENT_TEMPLATES.MODAL.CANCEL'),
    inputType: 'url',
  });
  if (url) props.editor.chain().focus().setImage({ src: url }).run();
};

// ── Recuo (em listas usa sink/lift; senão a extensão Indent) ────────────
const increaseIndent = () => {
  if (isActive('listItem')) cmd((c) => c.sinkListItem('listItem'));
  else cmd((c) => c.indent());
};
const decreaseIndent = () => {
  if (isActive('listItem')) cmd((c) => c.liftListItem('listItem'));
  else cmd((c) => c.outdent());
};

const clearFormatting = () =>
  props.editor.chain().focus().clearNodes().unsetAllMarks().run();

const canUndo = computed(() => props.editor.can().chain().focus().undo().run());
const canRedo = computed(() => props.editor.can().chain().focus().redo().run());
</script>

<template>
  <div class="editor-toolbar">
    <!-- Histórico -->
    <div class="editor-toolbar__group">
      <EditorToolbarButton
        icon="undo-2"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.UNDO')"
        :disabled="!canUndo"
        @click="cmd((c) => c.undo())"
      />
      <EditorToolbarButton
        icon="redo-2"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.REDO')"
        :disabled="!canRedo"
        @click="cmd((c) => c.redo())"
      />
    </div>

    <!-- Estilos de parágrafo -->
    <div class="editor-toolbar__group">
      <EditorStyleSelect :editor="editor" />
    </div>

    <!-- Fonte + tamanho -->
    <div class="editor-toolbar__group">
      <EditorToolbarSelect
        :model-value="currentFontFamily()"
        :options="fontFamilies"
        :aria-label="t('DOCUMENT_TEMPLATES.EDITOR.FONT_FAMILY')"
        width="146px"
        @update:model-value="setFontFamily"
      />
      <EditorFontSizeStepper :editor="editor" />
    </div>

    <!-- Formatação inline -->
    <div class="editor-toolbar__group">
      <EditorToolbarButton
        icon="bold"
        :active="isActive('bold')"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.BOLD')"
        @click="cmd((c) => c.toggleBold())"
      />
      <EditorToolbarButton
        icon="italic"
        :active="isActive('italic')"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.ITALIC')"
        @click="cmd((c) => c.toggleItalic())"
      />
      <EditorToolbarButton
        icon="underline"
        :active="isActive('underline')"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.UNDERLINE')"
        @click="cmd((c) => c.toggleUnderline())"
      />
      <EditorToolbarButton
        icon="strikethrough"
        :active="isActive('strike')"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.STRIKE')"
        @click="cmd((c) => c.toggleStrike())"
      />
      <EditorToolbarButton
        icon="superscript"
        :active="isActive('superscript')"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.SUPERSCRIPT')"
        @click="cmd((c) => c.toggleSuperscript())"
      />
      <EditorToolbarButton
        icon="subscript"
        :active="isActive('subscript')"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.SUBSCRIPT')"
        @click="cmd((c) => c.toggleSubscript())"
      />
    </div>

    <!-- Cor do texto + realce -->
    <div class="editor-toolbar__group">
      <EditorColorPicker :editor="editor" mode="text" />
      <EditorColorPicker :editor="editor" mode="highlight" />
      <EditorToolbarButton
        icon="remove-formatting"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.CLEAR_FORMATTING')"
        @click="clearFormatting"
      />
    </div>

    <!-- Inserções -->
    <div class="editor-toolbar__group">
      <EditorToolbarButton
        icon="link"
        :active="isActive('link')"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.INSERT_LINK')"
        @click="insertLink"
      />
      <EditorToolbarButton
        v-if="isActive('link')"
        icon="unlink"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.REMOVE_LINK')"
        @click="removeLink"
      />
      <EditorToolbarButton
        icon="image"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.INSERT_IMAGE')"
        @click="insertImage"
      />
      <EditorToolbarButton
        icon="table"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.INSERT_TABLE')"
        @click="cmd((c) => c.insertTable({ rows: 3, cols: 3, withHeaderRow: true }))"
      />
      <EditorTableMenu v-if="isActive('table')" :editor="editor" />
      <EditorToolbarButton
        icon="quote"
        :active="isActive('blockquote')"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.BLOCKQUOTE')"
        @click="cmd((c) => c.toggleBlockquote())"
      />
      <EditorToolbarButton
        icon="minus"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.INSERT_HORIZONTAL_RULE')"
        @click="cmd((c) => c.setHorizontalRule())"
      />
      <SpecialCharPicker :editor="editor" />
      <EditorToolbarButton
        icon="scissors-line-dashed"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.INSERT_PAGE_BREAK')"
        @click="cmd((c) => c.insertPageBreak())"
      />
    </div>

    <!-- Alinhamento -->
    <div class="editor-toolbar__group">
      <EditorToolbarButton
        icon="align-left"
        :active="isActive({ textAlign: 'left' })"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.ALIGN_LEFT')"
        @click="setAlign('left')"
      />
      <EditorToolbarButton
        icon="align-center"
        :active="isActive({ textAlign: 'center' })"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.ALIGN_CENTER')"
        @click="setAlign('center')"
      />
      <EditorToolbarButton
        icon="align-right"
        :active="isActive({ textAlign: 'right' })"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.ALIGN_RIGHT')"
        @click="setAlign('right')"
      />
      <EditorToolbarButton
        icon="align-justify"
        :active="isActive({ textAlign: 'justify' })"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.ALIGN_JUSTIFY')"
        @click="setAlign('justify')"
      />
    </div>

    <!-- Espaçamento entre linhas -->
    <div class="editor-toolbar__group">
      <EditorToolbarSelect
        :model-value="currentLineHeight()"
        :options="lineSpacings"
        :aria-label="t('DOCUMENT_TEMPLATES.EDITOR.LINE_SPACING')"
        width="118px"
        @update:model-value="setLineSpacing"
      />
    </div>

    <!-- Listas + recuo -->
    <div class="editor-toolbar__group">
      <EditorToolbarButton
        icon="list"
        :active="isActive('bulletList')"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.BULLET_LIST')"
        @click="cmd((c) => c.toggleBulletList())"
      />
      <EditorToolbarButton
        icon="list-ordered"
        :active="isActive('orderedList')"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.ORDERED_LIST')"
        @click="cmd((c) => c.toggleOrderedList())"
      />
      <EditorToolbarButton
        icon="indent-decrease"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.INDENT_DECREASE')"
        @click="decreaseIndent"
      />
      <EditorToolbarButton
        icon="indent-increase"
        :title="t('DOCUMENT_TEMPLATES.EDITOR.INDENT_INCREASE')"
        @click="increaseIndent"
      />
    </div>

    <PromptDialog
      v-bind="promptState"
      @submit="onSubmit"
      @cancel="onCancel"
    />
  </div>
</template>

<style lang="scss" scoped>
@use '../../styles/editor/toolbar';
</style>
