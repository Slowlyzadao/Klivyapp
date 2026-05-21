<script setup>
import { computed } from 'vue';

const props = defineProps({
  runs: { type: Array, required: true },
  selectedId: { type: Number, default: null },
});
const emit = defineEmits(['select']);

const KIND_LABEL = {
  patients: 'Pacientes',
  agenda: 'Agenda',
  anamnesis: 'Anamnese',
  financial: 'Financeiro',
};

const STATUS_LABEL = {
  pending: 'Pendente',
  processing: 'Processando',
  completed: 'Concluído',
  failed: 'Falhou',
};

function fmt(date) {
  if (!date) return '—';
  return new Date(date).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' });
}
</script>

<template>
  <div class="mig-card">
    <h2 style="font-size: 16px; font-weight: 700; margin: 0 0 12px;">Histórico de migrações</h2>
    <div v-if="!runs.length" style="font-size: 13px; color: #6b7280; padding: 20px 0; text-align: center;">
      Nenhuma migração executada ainda.
    </div>
    <table v-else class="mig-table">
      <thead>
        <tr>
          <th>ID</th>
          <th>Conta</th>
          <th>Tipo</th>
          <th>Arquivo</th>
          <th>Status</th>
          <th>Progresso</th>
          <th>Criado em</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="run in runs"
          :key="run.id"
          :style="{ cursor: 'pointer', background: selectedId === run.id ? '#eef2ff' : '' }"
          @click="emit('select', run)"
        >
          <td>#{{ run.id }}</td>
          <td>#{{ run.account_id }} {{ run.account_name ? `· ${run.account_name}` : '' }}</td>
          <td>{{ KIND_LABEL[run.kind] || run.kind }}</td>
          <td>{{ run.csv_filename || '—' }}</td>
          <td>
            <span :class="['mig-badge', `mig-badge--${run.status}`]">
              {{ STATUS_LABEL[run.status] || run.status }}
            </span>
          </td>
          <td>
            <div>{{ run.processed_rows }}/{{ run.total_rows || '?' }}</div>
            <div class="mig-progress">
              <div class="mig-progress__bar" :style="{ width: `${run.progress_percent || 0}%` }" />
            </div>
          </td>
          <td>{{ fmt(run.created_at) }}</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
