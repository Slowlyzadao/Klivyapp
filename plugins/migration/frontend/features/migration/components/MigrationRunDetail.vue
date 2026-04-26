<script setup>
const props = defineProps({
  run: { type: Object, default: null },
});
</script>

<template>
  <div v-if="run" class="mig-card">
    <h2 style="font-size: 16px; font-weight: 700; margin: 0 0 12px;">
      Migração #{{ run.id }} — {{ run.csv_filename || '—' }}
    </h2>

    <div class="mig-detail">
      <div class="mig-detail__row">
        <div><strong>Conta:</strong> #{{ run.account_id }} {{ run.account_name ? `· ${run.account_name}` : '' }}</div>
        <div><strong>Tipo:</strong> {{ run.kind }}</div>
        <div><strong>Origem:</strong> {{ run.source }}</div>
        <div><strong>Status:</strong> {{ run.status }}</div>
      </div>
      <div class="mig-detail__row">
        <div><strong>Total de linhas:</strong> {{ run.total_rows }}</div>
        <div><strong>Processadas:</strong> {{ run.processed_rows }}</div>
        <div><strong>Criadas:</strong> {{ run.created_count }}</div>
        <div><strong>Atualizadas:</strong> {{ run.updated_count }}</div>
        <div><strong>Ignoradas:</strong> {{ run.skipped_count }}</div>
        <div><strong>Erros:</strong> {{ run.error_count }}</div>
      </div>
    </div>

    <div v-if="run.error_message" class="mig-error">
      <strong>Falha geral:</strong> {{ run.error_message }}
    </div>

    <div v-if="run.errors_log && run.errors_log.length">
      <h3 style="font-size: 13px; font-weight: 600; margin: 16px 0 6px; color: #374151;">
        Log de linhas ({{ run.errors_log.length }})
      </h3>
      <div class="mig-error-list">
        <div
          v-for="(item, idx) in run.errors_log"
          :key="idx"
          :class="['mig-error-list__item', item.level === 'info' && 'mig-error-list__item--info']"
        >
          <strong>Linha {{ item.line }}:</strong> {{ item.message }}
        </div>
      </div>
    </div>
  </div>
</template>
