<script setup>
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineProps({
  tags: { type: Array, default: () => [] },
});

defineEmits(['view-anamnesis']);
</script>

<template>
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
  <div class="reg-section">
    <div class="reg-section-toggle" style="cursor: default">
      <div class="reg-section-toggle-left">
        <div class="reg-section-icon reg-icon-purple">
          <i class="i-lucide-tag w-4 h-4" />
        </div>
        <div>
          <span class="reg-section-title">Tags Clínicas</span>
          <span class="reg-section-subtitle"
            >Geradas automaticamente pela anamnese</span
          >
        </div>
      </div>
      <BeclinicButton
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-clipboard-plus"
        label="Ver Anamnese"
        @click="$emit('view-anamnesis')"
      />
    </div>
    <div class="reg-section-body">
      <div v-if="tags.length > 0" class="geral-tags-row">
        <div
          v-for="(tag, index) in tags"
          :key="index"
          class="clinical-tag"
          :class="'tag-' + tag.type"
        >
          <i :class="tag.icon" />
          <span>{{ tag.label }}</span>
        </div>
      </div>
      <p v-else class="text-sm text-slate-500">
        Nenhuma tag clínica. Preencha a anamnese para gerar automaticamente.
      </p>
    </div>
  </div>
</template>
