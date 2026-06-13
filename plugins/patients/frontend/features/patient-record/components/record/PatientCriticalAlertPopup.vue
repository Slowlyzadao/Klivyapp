<script setup>
import { ref } from 'vue';

defineProps({
  alerts: { type: Array, default: () => [] },
});

const isOpen = ref(false);

const toggle = () => {
  isOpen.value = !isOpen.value;
};

const close = () => {
  isOpen.value = false;
};
</script>

<template>
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
  <div v-if="alerts && alerts.length > 0" class="critical-alert-container">
    <button
      class="btn-critical-alert enhanced"
      title="Atenção Clínica"
      @click.stop="toggle"
    >
      <i class="i-lucide-alert-circle" />
    </button>
    <div v-if="isOpen" class="critical-popup">
      <div class="popup-header">
        <i class="i-lucide-alert-triangle" />
        <span>Atenção Clínica</span>
        <button class="btn-close-popup" @click="close">
          <i class="i-lucide-x" />
        </button>
      </div>
      <div class="popup-body critical-popup-body">
        <div
          v-for="alert in alerts"
          :key="alert.id"
          class="alert-item"
        >
          <strong>{{ alert.severity }}:</strong> {{ alert.message }}
        </div>
      </div>
    </div>
  </div>
</template>
