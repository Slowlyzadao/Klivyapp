<script setup>
import { ref, onMounted } from 'vue';
import { usePlans } from './composables/usePlans.js';
import { usePlanForm } from './composables/usePlanForm.js';
import PlanCard from './components/PlanCard.vue';
import PlanFormModal from './components/PlanFormModal.vue';
import AsIcon from '../../shared/AsIcon.vue';
import '../../shared/assinatura.css';
import './plans.css';

const showModal = ref(false);
const confirmDelete = ref(null);
const toast = ref(null);

const { plans, loading, error, fetchPlans, deletePlan, upsertPlan } = usePlans();

const { form, editingId, saving, formError, openNew, openEdit, toggleFeature, save } =
  usePlanForm(plan => {
    upsertPlan(plan);
    showModal.value = false;
    showToast('Plano salvo com sucesso!');
  });

function handleNew() {
  openNew();
  showModal.value = true;
}

function handleEdit(plan) {
  openEdit(plan);
  showModal.value = true;
}

async function handleDelete(plan) {
  if (!window.confirm(`Excluir o plano "${plan.name}"? Esta ação não pode ser desfeita.`)) return;
  try {
    await deletePlan(plan.id);
    showToast('Plano excluído.');
  } catch (e) {
    showToast('Erro ao excluir plano.', true);
  }
}

function showToast(msg, isError = false) {
  toast.value = { msg, isError };
  setTimeout(() => (toast.value = null), 3500);
}

onMounted(fetchPlans);
</script>

<template>
  <div class="as-page">
    <header class="as-page__header">
      <div>
        <h1 class="as-page__title">Planos de Assinatura</h1>
        <p class="as-page__subtitle">Gerencie os planos disponíveis para contratação</p>
      </div>
      <button type="button" class="reset-base as-btn as-btn--primary" @click="handleNew">
        <AsIcon name="add" :size="16" />
        Novo Plano
      </button>
    </header>

    <div v-if="loading" class="as-loading">
      <AsIcon name="loader" :size="20" class="as-spin" />
      <span>Carregando planos...</span>
    </div>

    <div v-else-if="error" class="as-alert as-alert--error">{{ error }}</div>

    <div v-else-if="plans.length === 0" class="as-empty">
      <AsIcon name="tag" :size="48" class="as-empty__icon" />
      <p class="as-empty__text">Nenhum plano cadastrado ainda.</p>
      <button type="button" class="reset-base as-btn as-btn--primary" @click="handleNew">Criar primeiro plano</button>
    </div>

    <div v-else class="plans-grid">
      <PlanCard
        v-for="plan in plans"
        :key="plan.id"
        :plan="plan"
        @edit="handleEdit"
        @delete="handleDelete"
      />
    </div>

    <PlanFormModal
      v-if="showModal"
      :form="form"
      :editing-id="editingId"
      :saving="saving"
      :error="formError"
      @save="save"
      @close="showModal = false"
      @toggle-feature="toggleFeature"
    />

    <div v-if="toast" class="as-toast" :class="{ 'as-toast--error': toast.isError }">
      <AsIcon :name="toast.isError ? 'alert' : 'check'" :size="16" />
      {{ toast.msg }}
    </div>
  </div>
</template>
