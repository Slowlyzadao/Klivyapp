<script setup>
// TemplateListRow — versão linha de TemplateCard (modo "list").
//
// Mostra: ícone | nome + tipo | badge origem | meta (v + data) | menu ⋮
//
// Stateless — emite mesmos eventos do TemplateCard pra parent tratar igual.

import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { labelFor } from '../../constants/documentTypes';

const props = defineProps({
  template: { type: Object, required: true },
  variant: {
    type: String,
    default: 'owned',
    validator: (v) => ['owned', 'klivy'].includes(v),
  },
});

const emit = defineEmits(['open', 'menu']);

const { t } = useI18n();

const typeLabel = computed(() => labelFor(props.template.document_type));

const badge = computed(() => {
  if (props.variant === 'klivy') {
    return { label: t('DOCUMENT_TEMPLATES.CARD.BADGE_KLIVY'), kind: 'klivy' };
  }
  if (props.template.is_cloned) {
    return { label: t('DOCUMENT_TEMPLATES.CARD.BADGE_CLONED'), kind: 'cloned' };
  }
  if (props.template.is_klivy) {
    return { label: t('DOCUMENT_TEMPLATES.CARD.BADGE_KLIVY'), kind: 'klivy' };
  }
  return null;
});

const updatedAt = computed(() => {
  if (!props.template.updated_at) return '';
  return new Date(props.template.updated_at).toLocaleDateString('pt-BR');
});

const onClick = () => emit('open', props.template);
const onMenuClick = (e) => {
  e.stopPropagation();
  emit('menu', { template: props.template, anchor: e.currentTarget });
};

const isDraggable = computed(() => props.variant === 'owned');

const onDragStart = (e) => {
  if (!isDraggable.value) return;
  e.dataTransfer.effectAllowed = 'move';
  e.dataTransfer.setData('application/x-doc-template-id', String(props.template.id));
  e.dataTransfer.setData('text/plain', props.template.name);
};
</script>

<template>
  <article
    class="tpl-row"
    role="button"
    tabindex="0"
    :draggable="isDraggable"
    @click="onClick"
    @keydown.enter="onClick"
    @dragstart="onDragStart"
  >
    <div class="tpl-row__icon">
      <span class="i-lucide-file-text" />
    </div>

    <div class="tpl-row__heading">
      <h3 class="tpl-row__title">{{ template.name }}</h3>
      <p class="tpl-row__type">{{ typeLabel }}</p>
    </div>

    <div class="tpl-row__badge-col">
      <span
        v-if="badge"
        class="tpl-row__badge"
        :class="`tpl-row__badge--${badge.kind}`"
      >
        {{ badge.label }}
      </span>
    </div>

    <div class="tpl-row__meta">
      <span v-if="template.version" class="tpl-row__version">
        v{{ template.version }}
      </span>
      <span v-if="updatedAt && template.version" class="tpl-row__dot">•</span>
      <span v-if="updatedAt" class="tpl-row__date">{{ updatedAt }}</span>
    </div>

    <button
      type="button"
      class="tpl-row__menu-btn"
      :aria-label="t('DOCUMENT_TEMPLATES.CARD.MENU')"
      @click="onMenuClick"
    >
      <span class="i-lucide-ellipsis-vertical" />
    </button>
  </article>
</template>

<style lang="scss" scoped>
@use '../../styles/index/template-list';
</style>
