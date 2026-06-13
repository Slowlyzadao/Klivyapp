<template>
  <button type="button" class="pp-doc-card" @click="$emit('open', document)">
    <div class="pp-doc-card__icon">
      <IconDocument :size="22" />
    </div>
    <div class="pp-doc-card__body">
      <div class="pp-doc-card__title">{{ document.title }}</div>
      <div class="pp-doc-card__meta">
        <Badge size="sm" :variant="typeVariant">{{ typeLabel }}</Badge>
        <span class="pp-doc-card__date">{{ formattedDate }}</span>
      </div>
    </div>
    <IconChevronRight :size="18" class="pp-doc-card__chevron" />
  </button>
</template>

<script setup>
import { computed } from 'vue';
import Badge from './Badge.vue';
import IconDocument from './icons/IconDocument.vue';
import IconChevronRight from './icons/IconChevronRight.vue';
import { formatDate } from '../utils/format';

const props = defineProps({
  document: { type: Object, required: true }
});

defineEmits(['open']);

const TYPE_LABELS = {
  receita:               'Receita',
  atestado:              'Atestado',
  pedido_exame:          'Pedido de exame',
  declaracao:            'Declaração',
  relatorio_clinico:     'Relatório',
  encaminhamento:        'Encaminhamento',
  contrato:              'Contrato',
  orcamento:             'Orçamento',
  instrucao_procedimento: 'Instruções',
  questionario:          'Questionário',
  outro:                 'Documento'
};

const TYPE_VARIANTS = {
  receita: 'success',
  atestado: 'primary',
  pedido_exame: 'warning',
  contrato: 'neutral',
  orcamento: 'warning'
};

const typeLabel  = computed(() => TYPE_LABELS[props.document.document_type] || 'Documento');
const typeVariant = computed(() => TYPE_VARIANTS[props.document.document_type] || 'neutral');
const formattedDate = computed(() => formatDate(props.document.created_at));
</script>

<style scoped>
.pp-doc-card {
  width: 100%; display: flex; align-items: center; gap: 12px;
  background: #fff; border: 1px solid var(--pp-color-border); border-radius: 14px;
  padding: 12px; text-align: left; cursor: pointer; font: inherit; color: inherit;
  transition: transform 80ms ease, box-shadow 120ms ease, border-color 120ms ease;
}
.pp-doc-card:hover  { box-shadow: 0 4px 12px rgba(15, 23, 42, .06); border-color: var(--pp-color-primary); }
.pp-doc-card:active { transform: scale(0.99); }

.pp-doc-card__icon {
  width: 40px; height: 40px; border-radius: 12px; flex-shrink: 0;
  display: flex; align-items: center; justify-content: center;
  background: color-mix(in srgb, var(--pp-color-primary) 10%, transparent);
  color: var(--pp-color-primary);
}
.pp-doc-card__body { flex: 1; min-width: 0; }
.pp-doc-card__title {
  font-weight: 600; font-size: 14px; color: var(--pp-color-text);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.pp-doc-card__meta { display: flex; align-items: center; gap: 8px; margin-top: 4px; }
.pp-doc-card__date { font-size: 12px; color: var(--pp-color-text-muted); }
.pp-doc-card__chevron { color: var(--pp-color-text-muted); flex-shrink: 0; }
</style>
