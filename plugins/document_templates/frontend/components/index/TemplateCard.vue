<script setup>
// Card de template (variant grid). Match mockup M3 Klivy:
//   • h-320px fixo, rounded-xl, hover → border primary
//   • Preview h-48 com bg surface-low, header bar + linhas simuladas
//   • Badge canto sup. direito (Personalizado | Klivy)
//   • Body com título headline-sm + tipo label-md
//   • Footer com v1 • data + menu (more_vert)
//
// Stateless — emite `open` (click no card) e `menu` (click no ⋮).
// Pai decide o que fazer baseado no variant/tab.

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

// Badge de origem — Personalizado | Klivy. Em "Meus modelos" mistura clones
// (Personalizado, derivado de Klivy) e originais da clínica (sem badge ou
// Klivy se for original importado).
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

const onCardClick = () => emit('open', props.template);

const onMenuClick = (e) => {
  e.stopPropagation();
  emit('menu', { template: props.template, anchor: e.currentTarget });
};

// Drag-and-drop: só owned. Klivy é read-only.
const isDraggable = computed(() => props.variant === 'owned');

const onDragStart = (e) => {
  if (!isDraggable.value) return;
  e.dataTransfer.effectAllowed = 'move';
  e.dataTransfer.setData('application/x-doc-template-id', String(props.template.id));
  e.dataTransfer.setData('text/plain', props.template.name);
};

// Tem preview real (template já tem content) ou cai pro wireframe.
const hasRealPreview = computed(() => {
  const html = props.template.preview_html;
  return typeof html === 'string' && html.trim().length > 0;
});

// Variações de larguras pras linhas simuladas no preview — dá variedade
// visual entre cards sem precisar de dados reais.
const lineWidths = computed(() => {
  const id = props.template.id || 0;
  const patterns = [
    ['100%', '83%', '100%', '66%'],
    ['100%', '90%', '75%', '85%'],
    ['100%', '100%', '60%', '80%'],
    ['90%', '100%', '75%', '50%'],
    ['100%', '70%', '95%', '80%'],
  ];
  return patterns[id % patterns.length];
});

const titleBarWidth = computed(() => {
  const id = props.template.id || 0;
  const widths = ['33%', '50%', '40%', '45%'];
  return widths[id % widths.length];
});
</script>

<template>
  <article
    class="tpl-card"
    role="button"
    tabindex="0"
    :draggable="isDraggable"
    @click="onCardClick"
    @keydown.enter="onCardClick"
    @dragstart="onDragStart"
  >
    <!--
      Preview area: mostra o texto REAL do documento (preview_html vindo
      do backend, já sanitizado pelo Renderer). Fallback pro wireframe
      quando o template ainda está vazio (sem content real).
    -->
    <div class="tpl-card__preview" aria-hidden="true">
      <!--
        Mini-papel branco que envolve o HTML real do template. Tipografia
        em tamanho NORMAL (14-22px) — visualização miniaturizada via
        transform: scale() no SCSS. Isso evita o minimum-font-size do
        Chrome que clampa qualquer coisa abaixo de ~10px.
      -->
      <div v-if="hasRealPreview" class="tpl-card__preview-doc">
        <div class="tpl-card__preview-doc-inner" v-html="template.preview_html" />
      </div>
      <div v-else class="tpl-card__preview-content">
        <span
          class="tpl-card__preview-title-bar"
          :style="{ width: titleBarWidth }"
        />
        <div class="tpl-card__preview-lines">
          <span
            v-for="(w, i) in lineWidths"
            :key="i"
            class="tpl-card__preview-line"
            :style="{ width: w }"
          />
        </div>
      </div>

      <span
        v-if="badge"
        class="tpl-card__badge"
        :class="`tpl-card__badge--${badge.kind}`"
      >
        {{ badge.label }}
      </span>
    </div>

    <!-- Body: título + tipo -->
    <div class="tpl-card__body">
      <div class="tpl-card__heading">
        <h3 class="tpl-card__title">{{ template.name }}</h3>
        <p class="tpl-card__type">{{ typeLabel }}</p>
      </div>

      <div class="tpl-card__footer">
        <div class="tpl-card__meta">
          <span v-if="template.version" class="tpl-card__version">
            v{{ template.version }}
          </span>
          <span v-if="updatedAt && template.version" class="tpl-card__dot">•</span>
          <span v-if="updatedAt" class="tpl-card__date">{{ updatedAt }}</span>
        </div>
        <button
          type="button"
          class="tpl-card__menu-btn"
          :aria-label="t('DOCUMENT_TEMPLATES.CARD.MENU')"
          @click="onMenuClick"
        >
          <span class="i-lucide-ellipsis-vertical" />
        </button>
      </div>
    </div>
  </article>
</template>

<style lang="scss" scoped>
@use '../../styles/index/template-card';
</style>
