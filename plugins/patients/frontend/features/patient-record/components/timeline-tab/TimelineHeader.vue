<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineProps({
  eventCount: { type: Number, default: 0 },
  sortOrder: { type: String, default: 'newest' },
});

const emit = defineEmits(['update:sortOrder']);

const { t } = useI18n();
const sortMenuOpen = ref(false);

const SORT_OPTIONS = [
  {
    value: 'newest',
    labelKey: 'PATIENT_TIMELINE.HEADER.SORT_NEWEST_FIRST',
    icon: 'i-lucide-arrow-down-narrow-wide',
  },
  {
    value: 'oldest',
    labelKey: 'PATIENT_TIMELINE.HEADER.SORT_OLDEST_FIRST',
    icon: 'i-lucide-arrow-up-narrow-wide',
  },
];

const selectSort = value => {
  emit('update:sortOrder', value);
  sortMenuOpen.value = false;
};
</script>

<template>
  <div class="reg-header mb-6">
    <div>
      <h3 class="text-xl font-semibold text-slate-100">
        {{ t('PATIENT_TIMELINE.HEADER.TITLE') }}
      </h3>
      <p class="text-sm text-slate-400 mt-0.5">
        {{ t('PATIENT_TIMELINE.HEADER.SUBTITLE') }}
      </p>
    </div>
    <div class="flex items-center gap-3">
      <span class="text-xs text-slate-500">
        {{
          eventCount === 1
            ? t('PATIENT_TIMELINE.HEADER.EVENT_COUNT_SINGULAR', { count: eventCount })
            : t('PATIENT_TIMELINE.HEADER.EVENT_COUNT_PLURAL', { count: eventCount })
        }}
      </span>
      <div class="relative">
        <BeclinicButton
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-arrow-up-down"
          :label="
            sortOrder === 'oldest'
              ? t('PATIENT_TIMELINE.HEADER.SORT_OLDEST')
              : t('PATIENT_TIMELINE.HEADER.SORT_NEWEST')
          "
          @click="sortMenuOpen = !sortMenuOpen"
        />
        <div v-if="sortMenuOpen" class="tl-sort-dropdown" @click.stop>
          <button
            v-for="opt in SORT_OPTIONS"
            :key="opt.value"
            class="tl-sort-option"
            :class="{ 'tl-sort-option--active': sortOrder === opt.value }"
            @click="selectSort(opt.value)"
          >
            <i :class="opt.icon" class="w-3.5 h-3.5" />
            {{ t(opt.labelKey) }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
