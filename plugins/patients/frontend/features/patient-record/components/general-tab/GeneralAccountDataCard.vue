<script setup>
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import { PATIENT_STATUS_OPTIONS } from '@plugins/patients/frontend/features/patient-record/utils/patientStatus';

defineProps({
  patient: { type: Object, required: true },
});

defineEmits(['change-status']);
</script>

<template>
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
  <div class="reg-section">
    <div class="reg-section-toggle" style="cursor: default">
      <div class="reg-section-toggle-left">
        <div class="reg-section-icon reg-icon-amber">
          <i class="i-lucide-settings-2 w-4 h-4" />
        </div>
        <div>
          <span class="reg-section-title">Dados da Conta</span>
          <span class="reg-section-subtitle">Status, unidade e origem</span>
        </div>
      </div>
    </div>
    <div class="reg-section-body">
      <div class="form-group">
        <label>Status do Paciente</label>
        <FormSelect
          v-model="patient.patient_status"
          :options="PATIENT_STATUS_OPTIONS"
          placeholder="Selecione"
          @change="$emit('change-status', $event)"
        />
      </div>
      <div class="geral-meta-row">
        <div class="geral-meta-item">
          <span class="geral-meta-label">Unidade / Clínica</span>
          <span class="geral-meta-value">{{ patient.unit || '—' }}</span>
        </div>
        <div class="geral-meta-item mt-4">
          <span class="geral-meta-label">Origem (Lead)</span>
          <span class="geral-meta-value">{{ patient.origin || '—' }}</span>
        </div>
      </div>
    </div>
  </div>
</template>
