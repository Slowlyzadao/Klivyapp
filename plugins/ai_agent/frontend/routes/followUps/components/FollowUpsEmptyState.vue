<script setup>
// FE-3 (auditoria 2026-05-18): extraído do Index.vue (702 LOC).
// Empty state quando nenhuma regra de follow-up foi cadastrada.
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineEmits(['create']);
</script>

<template>
  <div class="flex flex-col items-center justify-center py-24 text-center">
    <div class="flex items-center justify-center w-20 h-20 rounded-2xl bg-n-alpha-2 text-n-slate-10 mb-5">
      <svg class="w-9 h-9" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="m3 11 18-5v12L3 14v-3z"/><path d="M11.6 16.8a3 3 0 1 1-5.8-1.6"/></svg>
    </div>
    <h3 class="text-lg font-semibold text-n-slate-12">{{ $t('AI_AGENT.FOLLOW_UPS.EMPTY_TITLE') }}</h3>
    <p class="text-sm text-n-slate-10 mt-1.5 mb-6 max-w-md">
      {{ $t('AI_AGENT.FOLLOW_UPS.EMPTY_DESCRIPTION') }}
    </p>
    <BeclinicButton
      :label="$t('AI_AGENT.FOLLOW_UPS.EMPTY_CTA')"
      icon="i-lucide-plus"
      @click="$emit('create')"
    />
  </div>
</template>
