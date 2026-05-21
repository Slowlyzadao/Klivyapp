<script setup>
import { useI18n } from 'vue-i18n';
import { MEDIA_TYPE_FILTERS } from '@plugins/patients/frontend/constants/exams';

defineProps({
  active: { type: String, default: 'all' },
});

const emit = defineEmits(['update:active']);

const { t } = useI18n();
</script>

<template>
  <div class="exams-filters">
    <button
      v-for="filter in MEDIA_TYPE_FILTERS"
      :key="filter.value"
      class="exams-filter-btn"
      :class="
        active === filter.value
          ? 'exams-filter-btn--on'
          : 'exams-filter-btn--off'
      "
      @click="emit('update:active', filter.value)"
    >
      <i v-if="filter.icon" :class="`${filter.icon} w-3.5 h-3.5`" />
      {{ t(filter.labelKey) }}
    </button>
  </div>
</template>
