<script setup>
// Header da aba "Treinamento": título, contador de conversas e botão de
// envio de um novo .zip.
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineProps({
  totalCount: { type: Number, required: true },
});

defineEmits(['create']);
</script>

<template>
  <header class="flex-shrink-0 px-8 py-6 border-b border-n-weak bg-n-solid-1">
    <div class="flex items-start justify-between gap-6">
      <div class="min-w-0 flex-1">
        <div class="flex items-center gap-3 flex-wrap">
          <h1 class="text-2xl font-semibold text-n-slate-12 tracking-tight">
            {{ $t('AI_AGENT.TRAINING.TITLE') }}
          </h1>
          <span
            v-if="totalCount > 0"
            class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium rounded-full bg-n-alpha-2 text-n-slate-11"
          >
            {{ $t('AI_AGENT.TRAINING.COUNT', { count: totalCount }) }}
          </span>
        </div>
        <p class="text-sm text-n-slate-11 mt-1.5 max-w-3xl leading-relaxed">
          {{ $t('AI_AGENT.TRAINING.DESCRIPTION') }}
        </p>
      </div>
      <BeclinicButton
        class="shrink-0"
        :label="$t('AI_AGENT.TRAINING.NEW_BUTTON')"
        icon="i-lucide-upload"
        @click="$emit('create')"
      />
    </div>
  </header>
</template>
