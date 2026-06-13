<script setup>
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineProps({
  canScheduleAppointment: { type: Boolean, default: false },
  canManageExams: { type: Boolean, default: false },
  canManageDocuments: { type: Boolean, default: false },
  canCharge: { type: Boolean, default: false },
  canCreateClinicalNotes: { type: Boolean, default: false },
});

const emit = defineEmits([
  'back',
  'schedule',
  'attach',
  'document',
  'charge',
  'start-service',
]);
</script>

<template>
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
  <div
    class="header-nav flex flex-row justify-between w-full gap-2 md:gap-4 items-center"
  >
    <BeclinicButton
      variant="ghost"
      color="slate"
      icon="i-lucide-arrow-left"
      class="shrink-0"
      title="Voltar para pacientes"
      @click="emit('back')"
    >
      <span class="hidden md:inline">Voltar para pacientes</span>
    </BeclinicButton>

    <div
      class="header-actions flex flex-row gap-1 sm:gap-2 w-auto overflow-x-auto pb-1 sm:pb-0 items-center"
    >
      <BeclinicButton
        v-if="canScheduleAppointment"
        variant="faded"
        color="slate"
        icon="i-lucide-calendar-plus"
        class="shrink-0"
        title="Agendar"
        @click="emit('schedule')"
      >
        <span class="hidden lg:inline">Agendar</span>
      </BeclinicButton>

      <BeclinicButton
        v-if="canManageExams"
        variant="faded"
        color="slate"
        icon="i-lucide-paperclip"
        class="shrink-0"
        title="Anexar arquivo"
        @click="emit('attach')"
      >
        <span class="hidden lg:inline">Anexar arquivo</span>
      </BeclinicButton>

      <BeclinicButton
        v-if="canManageDocuments"
        variant="faded"
        color="slate"
        icon="i-lucide-file-text"
        class="shrink-0"
        title="Gerar documento"
        @click="emit('document')"
      >
        <span class="hidden lg:inline">Gerar documento</span>
      </BeclinicButton>

      <div v-if="canCharge" class="hdr-divider hidden sm:block shrink-0" />

      <BeclinicButton
        v-if="canCharge"
        variant="faded"
        color="teal"
        icon="i-lucide-dollar-sign"
        class="shrink-0"
        title="Cobrar"
        @click="emit('charge')"
      >
        <span class="hidden lg:inline">Cobrar</span>
      </BeclinicButton>

      <BeclinicButton
        v-if="canCreateClinicalNotes"
        variant="solid"
        color="blue"
        icon="i-lucide-play"
        class="shrink-0"
        title="Iniciar atendimento"
        @click="emit('start-service')"
      >
        <span class="hidden md:inline">Iniciar atendimento</span>
      </BeclinicButton>
    </div>
  </div>
</template>
