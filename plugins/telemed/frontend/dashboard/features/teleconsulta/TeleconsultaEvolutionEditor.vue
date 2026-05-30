<script setup>
// Audit 2026-05-26 — Componente simplificado.
// Antes: SOAP cards + Pontos de Atenção + actions (aprovar/editar/recusar).
// Agora: SÓ Pontos de Atenção. Todo o resto (campos editáveis + ações de
// aprovar/recusar) foi migrado pro TeleconsultaProcedureRegister.vue, que
// vive em bloco full-width abaixo da transcrição. Esse componente fica na
// lateral direita só pra destacar contraindicações e alergias.
import { computed } from 'vue';

const props = defineProps({
  evolution: { type: Object, required: true },
});

const TAG_VARIANT = {
  high: 'tcd-attention-tag--danger',
  medium: 'tcd-attention-tag--warn',
  low: 'tcd-attention-tag--default',
};
const ICON_VARIANT = {
  high: { cls: 'i-lucide-alert-triangle', color: 'tcd-attention-card__icon-danger' },
  medium: { cls: 'i-lucide-alert-circle', color: 'tcd-attention-card__icon-warn' },
  low: { cls: 'i-lucide-info', color: 'tcd-attention-card__icon-info' },
};
const TYPE_LABEL = {
  alergy:     'Alergia',
  allergy:    'Alergia',
  medication: 'Medicação',
  systemic:   'Sistêmico',
  behavior:   'Comportamento',
  other:      'Outro',
};
const tagClass = pt => TAG_VARIANT[pt.severity] || 'tcd-attention-tag--default';
const iconFor = pt => ICON_VARIANT[pt.severity] || ICON_VARIANT.low;
const tagLabel = pt => {
  const key = String(pt.type || '').toLowerCase().trim();
  return TYPE_LABEL[key] || (pt.type ? pt.type : 'Atenção');
};

const attentionPoints = computed(() =>
  Array.isArray(props.evolution.attention_points) ? props.evolution.attention_points : []
);

// Sem unsaved-changes detection aqui (o componente é read-only). O guard
// `onBeforeRouteLeave` no TeleconsultaDetailPage continua delegando pra
// hasUnsavedChanges do ProcedureRegister, que é o componente editável.
const hasUnsavedChanges = computed(() => false);
defineExpose({ hasUnsavedChanges });
</script>

<template>
  <section class="tcd-attention-panel" aria-label="Pontos de atenção clínica">
    <header class="tcd-attention-panel__head">
      <h3 class="tcd-attention-panel__title">
        <i class="i-lucide-alert-triangle w-5 h-5 tcd-attention-panel__title-icon" />
        <span>Pontos de Atenção</span>
      </h3>
      <p v-if="attentionPoints.length" class="tcd-attention-panel__subtitle">
        {{ attentionPoints.length }} {{ attentionPoints.length === 1 ? 'ponto identificado' : 'pontos identificados' }} pela IA
      </p>
    </header>

    <div v-if="attentionPoints.length" class="tcd-attention__list">
      <article
        v-for="pt in attentionPoints"
        :key="`${pt.type || ''}-${(pt.text || '').slice(0, 40)}`"
        class="tcd-attention-card"
      >
        <header class="tcd-attention-card__head">
          <span :class="['tcd-attention-tag', tagClass(pt)]">
            {{ tagLabel(pt) }}
          </span>
          <i :class="[iconFor(pt).cls, 'w-4 h-4', iconFor(pt).color]" />
        </header>
        <p class="tcd-attention-card__text">{{ pt.text }}</p>
      </article>
    </div>
    <p v-else class="tcd-attention-panel__empty">
      Nenhum ponto de atenção identificado nesta consulta.
    </p>
  </section>
</template>
