<script setup>
// FE-4 (auditoria 2026-05-18): extraído do Index.vue (516 LOC).
// Header da tela de templates de notificação interna (sem botão de criação —
// templates são seedados pelo sistema, usuário só edita).
defineProps({
  activeCount: { type: Number, required: true },
  cardCount: { type: Number, required: true },
});
</script>

<template>
  <header class="flex-shrink-0 px-8 py-6 border-b border-n-weak bg-n-solid-1">
    <div class="flex items-start justify-between gap-6">
      <div class="min-w-0 flex-1">
        <div class="flex items-center gap-3 flex-wrap">
          <h1 class="text-2xl font-semibold text-n-slate-12 tracking-tight">Templates de notificação interna</h1>
          <span
            v-if="cardCount > 0"
            class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium rounded-full bg-n-alpha-2 text-n-slate-11"
          >
            <span class="w-1.5 h-1.5 rounded-full bg-emerald-500" />
            {{ activeCount }} {{ activeCount === 1 ? 'ativo' : 'ativos' }}
            <span class="text-n-slate-9">·</span>
            {{ cardCount }} no total
          </span>
        </div>
        <p class="text-sm text-n-slate-11 mt-1.5 max-w-3xl leading-relaxed">
          Configure quais avisos a Beatriz manda no Chat Interno e pra qual sala ou pessoa cada um vai. As mensagens são pré-definidas (zero token) — você edita o texto, escolhe o destino e ativa.
        </p>
      </div>
    </div>
  </header>
</template>
