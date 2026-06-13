<script setup>
// Dropdown de estilos de parágrafo (Texto normal / Título / Cabeçalho 1-3),
// estilo Google Docs. Reaproveita o EditorToolbarSelect (native select).
// Mapeia Título→h1, Cabeçalho 1→h2, etc (TipTap não tem nó "Título" nativo).

import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import EditorToolbarSelect from './EditorToolbarSelect.vue';

const props = defineProps({
  editor: { type: Object, required: true },
});

const { t } = useI18n();

const styles = computed(() => [
  { value: 'p', label: t('DOCUMENT_TEMPLATES.EDITOR.STYLE_NORMAL') },
  { value: 'h1', label: t('DOCUMENT_TEMPLATES.EDITOR.STYLE_TITLE') },
  { value: 'h2', label: t('DOCUMENT_TEMPLATES.EDITOR.STYLE_HEADING1') },
  { value: 'h3', label: t('DOCUMENT_TEMPLATES.EDITOR.STYLE_HEADING2') },
  { value: 'h4', label: t('DOCUMENT_TEMPLATES.EDITOR.STYLE_HEADING3') },
]);

const current = () => {
  if (props.editor.isActive('paragraph')) return 'p';
  const level = [1, 2, 3, 4].find((l) =>
    props.editor.isActive('heading', { level: l }),
  );
  return level ? `h${level}` : 'p';
};

const apply = (value) => {
  const chain = props.editor.chain().focus();
  // setHeading (não toggleHeading): um select sempre DEFINE um estilo
  // explícito. Com toggle, re-selecionar o estilo já ativo o desligava de
  // volta pra parágrafo (o FormSelect emite update mesmo na opção atual).
  if (value === 'p') chain.setParagraph().run();
  else chain.setHeading({ level: Number(value[1]) }).run();
};
</script>

<template>
  <EditorToolbarSelect
    :model-value="current()"
    :options="styles"
    :aria-label="t('DOCUMENT_TEMPLATES.EDITOR.STYLE_NORMAL')"
    width="150px"
    @update:model-value="apply"
  />
</template>
