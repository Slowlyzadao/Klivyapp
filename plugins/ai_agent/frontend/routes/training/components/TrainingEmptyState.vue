<script setup>
// Empty state quando nenhuma conversa de treinamento foi enviada ainda.
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineEmits(['create']);
</script>

<template>
  <div class="flex flex-col items-center justify-center py-24 text-center">
    <div
      class="flex items-center justify-center w-20 h-20 rounded-2xl bg-n-alpha-2 text-n-slate-10 mb-5"
    >
      <svg
        class="w-9 h-9"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.7"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <path
          d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"
        />
      </svg>
    </div>
    <h3 class="text-lg font-semibold text-n-slate-12">
      {{ $t('AI_AGENT.TRAINING.EMPTY_TITLE') }}
    </h3>
    <p class="text-sm text-n-slate-10 mt-1.5 mb-6 max-w-md leading-relaxed">
      {{ $t('AI_AGENT.TRAINING.EMPTY_DESCRIPTION') }}
    </p>
    <BeclinicButton
      :label="$t('AI_AGENT.TRAINING.EMPTY_CTA')"
      icon="i-lucide-upload"
      @click="$emit('create')"
    />
  </div>
</template>
