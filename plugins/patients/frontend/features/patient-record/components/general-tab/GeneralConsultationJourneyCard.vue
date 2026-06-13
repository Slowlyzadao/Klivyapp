<script setup>
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineProps({
  last: { type: Object, default: null },
  next: { type: Object, default: null },
});

defineEmits(['schedule']);
</script>

<template>
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
  <div class="reg-section">
    <div class="reg-section-toggle" style="cursor: default">
      <div class="reg-section-toggle-left">
        <div class="reg-section-icon reg-icon-green">
          <i class="i-lucide-calendar-days w-4 h-4" />
        </div>
        <div>
          <span class="reg-section-title">Jornada de Consultas</span>
          <span class="reg-section-subtitle"
            >Última e próxima consulta agendada</span
          >
        </div>
      </div>
      <BeclinicButton
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-calendar-plus"
        label="Agendar Consulta"
        @click="$emit('schedule')"
      />
    </div>
    <div class="reg-section-body">
      <div class="reg-field-grid-2">
        <!-- Última Consulta -->
        <div class="geral-visit-card geral-visit-card--past">
          <div class="geral-visit-icon geral-visit-icon--past">
            <i class="i-lucide-history w-4 h-4" />
          </div>
          <div class="geral-visit-info">
            <span class="geral-visit-label">Última Consulta</span>
            <template v-if="last">
              <span class="geral-visit-date">{{ last.date }}</span>
              <span class="geral-visit-time">{{ last.time }}</span>
            </template>
            <span v-else class="geral-visit-empty"
              >Nenhuma consulta registrada</span
            >
          </div>
        </div>

        <!-- Próxima Consulta -->
        <div class="geral-visit-card geral-visit-card--next">
          <div class="geral-visit-icon geral-visit-icon--next">
            <i class="i-lucide-calendar-clock w-4 h-4" />
          </div>
          <div class="geral-visit-info">
            <span class="geral-visit-label">Próxima Consulta</span>
            <template v-if="next">
              <span class="geral-visit-date geral-visit-date--highlight">{{
                next.date
              }}</span>
              <span class="geral-visit-time">{{ next.time }}</span>
            </template>
            <span v-else class="geral-visit-empty"
              >Nenhum agendamento futuro</span
            >
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
