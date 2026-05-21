<script setup>
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineEmits(['create-plan']);

const { t } = useI18n();
</script>

<template>
  <div class="rp-tab-header hide-on-print">
    <div>
      <h3 class="rp-tab-title">{{ t('PATIENT_TREATMENT_PLAN.HEADER.TITLE') }}</h3>
      <p class="rp-tab-subtitle">
        {{ t('PATIENT_TREATMENT_PLAN.HEADER.SUBTITLE') }}
      </p>
    </div>
    <BeclinicButton
      v-can="['patients', 'manage_treatment_plans']"
      variant="solid"
      color="blue"
      icon="i-lucide-plus"
      :label="t('PATIENT_TREATMENT_PLAN.HEADER.NEW_PLAN')"
      @click="$emit('create-plan')"
    />
  </div>
</template>
