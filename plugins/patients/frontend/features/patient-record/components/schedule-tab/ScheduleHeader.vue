<script setup>
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const emit = defineEmits(['view-agenda', 'new-appointment']);

const { t } = useI18n();
</script>

<template>
  <div class="reg-header mb-6">
    <div>
      <h3 class="text-xl font-semibold text-slate-100">
        {{ t('PATIENT_SCHEDULE.HEADER.TITLE') }}
      </h3>
      <p class="text-sm text-slate-400 mt-0.5">
        {{ t('PATIENT_SCHEDULE.HEADER.SUBTITLE') }}
      </p>
    </div>
    <div class="flex items-center gap-3">
      <BeclinicButton
        variant="faded"
        color="slate"
        icon="i-lucide-calendar"
        :label="t('PATIENT_SCHEDULE.HEADER.VIEW_AGENDA')"
        @click="emit('view-agenda')"
      />
      <BeclinicButton
        variant="solid"
        color="blue"
        icon="i-lucide-calendar-plus"
        :label="t('PATIENT_SCHEDULE.HEADER.NEW_APPOINTMENT')"
        @click="emit('new-appointment')"
      />
    </div>
  </div>
</template>
