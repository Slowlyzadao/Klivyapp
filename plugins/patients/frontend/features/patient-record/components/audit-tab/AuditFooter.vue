<script setup>
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineProps({
  meta: {
    type: Object,
    default: () => ({ total_count: 0, current_page: 1, total_pages: 1 }),
  },
  currentPage: { type: Number, default: 1 },
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['prev', 'next']);

const { t } = useI18n();
</script>

<template>
  <div class="aud-footer mt-5">
    <p class="aud-footer-note">
      <i class="i-lucide-lock w-3 h-3" />
      {{ t('PATIENT_AUDIT.FOOTER.IMMUTABLE_NOTE') }}
      <span class="aud-footer-total">
        {{ t('PATIENT_AUDIT.FOOTER.TOTAL', { count: meta.total_count }) }}
      </span>
    </p>
    <div class="aud-pagination">
      <span class="aud-page-info">
        {{
          t('PATIENT_AUDIT.FOOTER.PAGE_INFO', {
            current: meta.current_page,
            total: meta.total_pages,
          })
        }}
      </span>
      <div class="flex gap-2">
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-chevron-left"
          :label="t('PATIENT_AUDIT.FOOTER.PREV')"
          :disabled="currentPage <= 1 || isLoading"
          @click="emit('prev')"
        />
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-chevron-right"
          trailing-icon
          :label="t('PATIENT_AUDIT.FOOTER.NEXT')"
          :disabled="currentPage >= meta.total_pages || isLoading"
          @click="emit('next')"
        />
      </div>
    </div>
  </div>
</template>
