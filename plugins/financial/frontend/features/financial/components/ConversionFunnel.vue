<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChartSkeleton from './ChartSkeleton.vue';
import ChartEmptyState from './ChartEmptyState.vue';

const props = defineProps({
  data: {
    type: Object,
    default: () => ({ etapas: [], pior_queda: null }),
  },
  loading: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();

const isEmpty = computed(() => {
  return (
    !props.data ||
    !props.data.etapas ||
    props.data.etapas.length === 0 ||
    props.data.etapas.every(e => e.valor === 0)
  );
});

const maxVal = computed(() => {
  if (isEmpty.value) return 1;
  return Math.max(...props.data.etapas.map(e => e.valor));
});
</script>

<template>
  <div class="conversion-funnel-wrapper">
    <template v-if="loading">
      <ChartSkeleton height="260px" />
    </template>
    <template v-else-if="isEmpty">
      <ChartEmptyState :message="t('FINANCIAL.CHARTS.EMPTY')" />
    </template>
    <template v-else>
      <div v-if="data.pior_queda" class="funnel-alert">
        <i class="i-lucide-alert-triangle" />
        {{ t('FINANCIAL.CHARTS.FUNNEL.BIGGEST_DROP') }}
        <strong>{{ data.pior_queda }}</strong>
      </div>
      <div class="funnel-container">
        <div
          v-for="(item, index) in data.etapas"
          :key="item.etapa"
          class="funnel-step-wrapper"
        >
          <div v-if="index > 0" class="funnel-step-connector">
            <span
              class="funnel-step-rate"
              :class="{
                'funnel-step-rate--danger': data.pior_queda === item.etapa,
              }"
            >
              <i class="i-lucide-arrow-down" />
              {{
                item.taxa_conversao !== null ? item.taxa_conversao + '%' : '--'
              }}
            </span>
          </div>

          <div class="funnel-step">
            <div class="funnel-step__label">{{ item.etapa }}</div>
            <div class="funnel-step__bar-container">
              <div
                class="funnel-step__bar"
                :style="{
                  width: `${(item.valor / maxVal) * 100}%`,
                  backgroundColor:
                    data.pior_queda === item.etapa ? '#EF4444' : '#3B82F6',
                }"
              >
                <span class="funnel-step__value">{{ item.valor }}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
