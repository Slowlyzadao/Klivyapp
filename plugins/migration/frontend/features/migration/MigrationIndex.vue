<script setup>
import './migration.css';
import { ref, onMounted, onUnmounted } from 'vue';
import MigrationUploadForm from './components/MigrationUploadForm.vue';
import MigrationRunsTable from './components/MigrationRunsTable.vue';
import MigrationRunDetail from './components/MigrationRunDetail.vue';
import { fetchIndex, fetchRun } from './api/migrationApi.js';

const accounts = ref([]);
const runs = ref([]);
const selectedRun = ref(null);
const loading = ref(true);
let pollTimer = null;

async function refresh() {
  try {
    const data = await fetchIndex();
    accounts.value = data.accounts || [];
    runs.value = data.runs || [];
    if (selectedRun.value) {
      const fresh = runs.value.find(r => r.id === selectedRun.value.id);
      if (fresh) selectedRun.value = fresh;
    }
  } catch (e) {
    console.error('[Migration] refresh failed', e);
  } finally {
    loading.value = false;
  }
}

async function refreshSelected() {
  if (!selectedRun.value) return;
  try {
    selectedRun.value = await fetchRun(selectedRun.value.id);
  } catch (e) {
    console.error('[Migration] refresh selected failed', e);
  }
}

function selectRun(run) {
  selectedRun.value = run;
  refreshSelected();
}

function onRunCreated(run) {
  selectedRun.value = run;
  refresh();
}

onMounted(() => {
  refresh();
  pollTimer = setInterval(() => {
    refresh();
    refreshSelected();
  }, 4000);
});
onUnmounted(() => {
  if (pollTimer) clearInterval(pollTimer);
});
</script>

<template>
  <div class="mig-page">
    <div class="mig-header">
      <div>
        <h1>Migração</h1>
        <p>Importe planilhas (Clinicorp, etc.) para uma conta específica do Klivy.</p>
      </div>
    </div>

    <MigrationUploadForm :accounts="accounts" @run-created="onRunCreated" />
    <MigrationRunsTable :runs="runs" :selected-id="selectedRun?.id" @select="selectRun" />
    <MigrationRunDetail v-if="selectedRun" :run="selectedRun" />
  </div>
</template>
