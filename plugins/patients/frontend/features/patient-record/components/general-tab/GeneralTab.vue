<script setup>
import GeneralClinicalTagsCard from './GeneralClinicalTagsCard.vue';
import GeneralActiveTreatmentCard from './GeneralActiveTreatmentCard.vue';
import GeneralAccountDataCard from './GeneralAccountDataCard.vue';
import GeneralConsultationJourneyCard from './GeneralConsultationJourneyCard.vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineProps({
  patient: { type: Object, required: true },
  clinicalTags: { type: Array, default: () => [] },
  activePlan: { type: Object, default: null },
  professional: {
    type: Object,
    default: () => ({ name: '—', avatar: '', roleLabel: '', roleSlug: '' }),
  },
  lastAppointment: { type: Object, default: null },
  nextAppointment: { type: Object, default: null },
});

defineEmits([
  'edit-record',
  'view-anamnesis',
  'view-plans',
  'change-status',
  'change-responsible',
  'schedule',
]);
</script>

<template>
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
  <div class="tab-pane fade-in">
    <!-- Header -->
    <div class="reg-header mb-5">
      <div>
        <h3 class="text-xl font-semibold text-slate-100">Visão Geral</h3>
        <p class="text-sm text-slate-400 mt-0.5">
          Painel clínico rápido — informações essenciais antes do atendimento.
        </p>
      </div>
      <BeclinicButton
        variant="faded"
        color="slate"
        icon="i-lucide-edit-3"
        label="Editar Ficha"
        @click="$emit('edit-record')"
      />
    </div>

    <!-- Banner: Alertas Críticos -->
    <div
      v-if="patient.critical_alerts && patient.critical_alerts.length > 0"
      class="geral-alert-banner mb-4"
    >
      <div class="geral-alert-icon">
        <i class="i-lucide-siren w-4 h-4" />
      </div>
      <div class="geral-alert-body">
        <span class="geral-alert-title">Alertas Críticos</span>
        <span class="geral-alert-text">
          <span v-for="(a, i) in patient.critical_alerts" :key="i">
            {{ a.title || a.message
            }}<span v-if="i < patient.critical_alerts.length - 1"> · </span>
          </span>
        </span>
      </div>
    </div>

    <!-- Nota Fixada -->
    <div v-if="patient.pinned_note" class="geral-pinned-note mb-4">
      <i class="i-lucide-pin w-4 h-4 text-amber-400 flex-shrink-0" />
      <span class="text-sm text-slate-300">{{ patient.pinned_note }}</span>
    </div>

    <!-- Grid principal -->
    <div class="reg-form-grid flex flex-col gap-4">
      <GeneralClinicalTagsCard
        :tags="clinicalTags"
        @view-anamnesis="$emit('view-anamnesis')"
      />

      <div class="reg-field-grid-2">
        <GeneralActiveTreatmentCard
          :plan="activePlan"
          :prof-name="professional.name"
          :prof-avatar="professional.avatar"
          :prof-role-label="professional.roleLabel"
          :prof-role-slug="professional.roleSlug"
          @view-plans="$emit('view-plans')"
          @change-responsible="$emit('change-responsible')"
        />
        <GeneralAccountDataCard
          :patient="patient"
          @change-status="$emit('change-status', $event)"
        />
      </div>

      <GeneralConsultationJourneyCard
        :last="lastAppointment"
        :next="nextAppointment"
        @schedule="$emit('schedule')"
      />
    </div>
  </div>
</template>
