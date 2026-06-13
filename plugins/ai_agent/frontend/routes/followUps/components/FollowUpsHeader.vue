<script setup>
// FE-3 (auditoria 2026-05-18): extraído do Index.vue (702 LOC).
// Header da tela de follow-ups com contador de ativos/total e botão de criação.
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineProps({
  activeCount: { type: Number, required: true },
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
            {{ $t('AI_AGENT.FOLLOW_UPS.TITLE') }}
          </h1>
          <span
            v-if="totalCount > 0"
            class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium rounded-full bg-n-alpha-2 text-n-slate-11"
          >
            <span class="w-1.5 h-1.5 rounded-full bg-emerald-500" />
            {{ activeCount === 1
                ? $t('AI_AGENT.FOLLOW_UPS.ACTIVE_COUNT_ONE', { count: activeCount })
                : $t('AI_AGENT.FOLLOW_UPS.ACTIVE_COUNT_MANY', { count: activeCount }) }}
            <span class="text-n-slate-9">·</span>
            {{ $t('AI_AGENT.FOLLOW_UPS.TOTAL_SUFFIX', { count: totalCount }) }}
          </span>
        </div>
        <p class="text-sm text-n-slate-11 mt-1.5 max-w-3xl leading-relaxed">
          {{ $t('AI_AGENT.FOLLOW_UPS.DESCRIPTION') }}
        </p>
      </div>
      <BeclinicButton
        class="shrink-0"
        :label="$t('AI_AGENT.FOLLOW_UPS.NEW_BUTTON')"
        icon="i-lucide-plus"
        @click="$emit('create')"
      />
    </div>
  </header>
</template>
