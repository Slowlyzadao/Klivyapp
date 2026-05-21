<script setup>
import PatientsAPI from '@plugins/patients/frontend/api/patients/index';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  deletedAt: { type: String, default: null },
  patientId: { type: [String, Number], required: true },
});

const emit = defineEmits(['restored']);

const restore = async () => {
  await PatientsAPI.restore(props.patientId);
  useAlert('Paciente restaurado com sucesso!');
  emit('restored');
};
</script>

<template>
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
  <div v-if="deletedAt" class="archived-banner">
    <div class="archived-banner-left">
      <i class="i-lucide-archive w-4 h-4" />
      <div>
        <p class="archived-banner-title">Paciente arquivado</p>
        <p class="archived-banner-sub">
          Arquivado em
          {{
            new Date(deletedAt).toLocaleDateString('pt-BR', {
              timeZone: 'America/Sao_Paulo',
            })
          }}
          — apenas leitura
        </p>
      </div>
    </div>
    <button
      class="archived-banner-btn"
      title="Restaurar paciente"
      @click="restore"
    >
      <i class="i-lucide-archive-restore w-4 h-4" />
      Restaurar paciente
    </button>
  </div>
</template>
