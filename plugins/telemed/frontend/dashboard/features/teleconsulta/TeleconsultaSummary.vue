<script setup>
// Resumo executivo da teleconsulta (Markdown gerado pelo Claude — bloco
// `## Resumo Executivo`). 2026-05-22:
//   - Antes: caía no `raw_markdown` SOAP inteiro com truncate de 600 chars
//     e exibia como texto puro (Markdown cru visível e cortado com "…").
//   - Agora: campo dedicado `evolution.summary`, Markdown renderizado via
//     markdown-it (mesma lib que o Chatwoot usa em MessageFormatter), sem
//     limite de caracteres. Negrito/bullets aparecem formatados.
import { computed } from 'vue';
import MarkdownIt from 'markdown-it';

const props = defineProps({
  summary: { type: String, default: '' },
});

// Instância local — sem plugins de mention/link específicos do Chatwoot.
// `html: false` impede injeção de HTML pelo modelo. `breaks: true` mantém
// quebras de linha simples como <br> (UX de texto clínico).
const md = new MarkdownIt({
  html: false,
  breaks: true,
  linkify: false,
  typographer: false,
});

const hasContent = computed(() => props.summary.trim().length > 0);
const rendered = computed(() => md.render(props.summary || ''));
</script>

<template>
  <section class="tcd-card">
    <h3 class="tcd-card__title">
      <i class="i-lucide-clipboard-list w-5 h-5 tcd-card__title-icon" />
      <span>Resumo da Teleconsulta</span>
    </h3>

    <p v-if="!hasContent" class="tcd-summary__empty">
      Resumo executivo ainda não disponível para esta teleconsulta.
    </p>
    <!-- v-html é seguro: `html: false` no MarkdownIt impede HTML cru
         vindo do Claude; só passam tags geradas pelo próprio renderer
         (<p>, <strong>, <ul>, <li>, etc.). -->
    <div v-else class="tcd-summary__markdown" v-html="rendered" />
  </section>
</template>

<style scoped>
.tcd-summary__markdown {
  font-size: 0.95rem;
  line-height: 1.55;
  color: rgb(17, 24, 39);
}
.tcd-summary__markdown :deep(p) {
  margin: 0 0 0.75rem;
}
.tcd-summary__markdown :deep(p:last-child) {
  margin-bottom: 0;
}
.tcd-summary__markdown :deep(ul),
.tcd-summary__markdown :deep(ol) {
  margin: 0.25rem 0 0.75rem 1.25rem;
  padding: 0;
}
.tcd-summary__markdown :deep(li) {
  margin: 0.15rem 0;
}
.tcd-summary__markdown :deep(strong) {
  color: rgb(17, 24, 39);
  font-weight: 600;
}
.tcd-summary__markdown :deep(code) {
  background: rgba(15, 23, 42, 0.06);
  padding: 0.05rem 0.3rem;
  border-radius: 4px;
  font-size: 0.85em;
}
</style>
