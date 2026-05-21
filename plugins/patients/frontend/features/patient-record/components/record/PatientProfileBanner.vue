<script setup>
import { computed } from 'vue';
import {
  formatCpf,
  formatPhone,
  formatDate,
  formatSex,
  hasValidSex,
  formatInsurance,
} from '@plugins/patients/frontend/features/patient-record/utils/patientFormatters';
import { PATIENT_STATUS_LABELS } from '@plugins/patients/frontend/features/patient-record/utils/patientStatus';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import PatientCriticalAlertPopup from './PatientCriticalAlertPopup.vue';

const props = defineProps({
  patient: { type: Object, required: true },
});

const STATUS_BADGE_PROPS = {
  novo: { intent: 'info' },
  ativo: { intent: 'success' },
  inativo: { intent: 'neutral' },
  faltoso: { intent: 'warning' },
  alta: { color: 'violet' },
  arquivado: { color: 'slate', variant: 'solid' },
};

const statusBadge = computed(() => {
  const status = props.patient.patient_status || 'novo';
  return {
    label: PATIENT_STATUS_LABELS[status] || status,
    ...(STATUS_BADGE_PROPS[status] || { intent: 'neutral' }),
  };
});
</script>

<template>
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
  <div class="profile-banner">
    <!-- Esquerda: avatar + identidade -->
    <div class="profile-banner-left">
      <!-- Avatar com badge de status sobreposto. Usa o componente canônico
           para herdar o mesmo hash de cor e iniciais usados na lista. -->
      <div class="pb-avatar-wrap">
        <Avatar
          :src="patient.avatar_url"
          :name="patient.name || ''"
          :size="52"
        />
        <span
          class="pb-status-dot"
          :class="'pb-dot-' + (patient.patient_status || 'novo')"
          :title="
            PATIENT_STATUS_LABELS[patient.patient_status] ||
            patient.patient_status
          "
        />
      </div>

      <!-- Identidade: nome + dados -->
      <div class="pb-identity">
        <div class="pb-name-row">
          <h2 class="pb-name">{{ patient.name }}</h2>
          <Badge v-bind="statusBadge" size="xs" />
          <PatientCriticalAlertPopup :alerts="patient.critical_alerts" />
        </div>

        <!-- Linha de dados demográficos -->
        <div class="pb-meta-row">
          <span v-if="patient.age" class="pb-meta-text"
            >{{ patient.age }} anos</span
          >
          <span
            v-if="patient.age && hasValidSex(patient.sex)"
            class="pb-meta-sep"
            >•</span
          >
          <span v-if="hasValidSex(patient.sex)" class="pb-meta-text">{{
            formatSex(patient.sex)
          }}</span>
        </div>

        <!-- Chips de informações -->
        <div class="pb-chips">
          <div v-if="patient.birthdate" class="pb-chip">
            <i class="i-lucide-cake w-3.5 h-3.5 pb-chip-icon" />
            <span>{{ formatDate(patient.birthdate) }}</span>
          </div>
          <div v-if="patient.phone" class="pb-chip">
            <i class="i-lucide-smartphone w-3.5 h-3.5 pb-chip-icon" />
            <span>{{ formatPhone(patient.phone) || patient.phone }}</span>
          </div>
          <div v-if="patient.email" class="pb-chip hide-mobile">
            <i class="i-lucide-mail w-3.5 h-3.5 pb-chip-icon" />
            <span>{{ patient.email }}</span>
          </div>
          <div v-if="patient.cpf" class="pb-chip hide-mobile">
            <i class="i-lucide-credit-card w-3.5 h-3.5 pb-chip-icon" />
            <span>{{ formatCpf(patient.cpf) }}</span>
          </div>
          <div v-if="formatInsurance(patient.insurance)" class="pb-chip">
            <i class="i-lucide-shield-plus w-3.5 h-3.5 pb-chip-icon" />
            <span>{{ formatInsurance(patient.insurance) }}</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Direita: badge financeiro -->
    <div class="pb-right">
      <div
        class="pb-finance-badge"
        :class="'pb-finance-' + patient.financialStatus?.toLowerCase()"
      >
        <i class="i-lucide-wallet w-4 h-4" />
        <span>{{ patient.financialStatus }}</span>
      </div>
    </div>
  </div>
</template>
