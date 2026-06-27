<script setup>
/**
 * Página DEV/preview pra abrir o PaymentPlanWizardV2 contra um budget real
 * SEM precisar integrar nos entry points reais (aba do paciente, A Receber).
 *
 * Acesso: /app/accounts/:accountId/financial/v2/_dev/payment-plan-wizard?budget_id=X
 *
 * NÃO exposta em nenhum menu — só URL direta. Permite QA + dev validarem o
 * fluxo ponta-a-ponta antes da F3 plugar o wizard nos entry points reais
 * atrás de feature flag `payment_plan_wizard_v2`.
 *
 * Banner amarelo deixa explícito "modo dev" pra não confundir operador real.
 */
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import FinancialV2 from '../api/financialV2';
import PaymentPlanWizardV2 from '../components/wizard/PaymentPlanWizardV2.vue';
import { centsToBRL } from '../composables/useMoney';

const route = useRoute();

const budgetIdInput = ref(route.query.budget_id ? String(route.query.budget_id) : '');
const budget = ref(null);
const loading = ref(false);
const loadError = ref('');
const wizardOpen = ref(false);
const lastApprovalResult = ref(null);

async function loadBudget() {
  if (!budgetIdInput.value) return;
  loading.value = true;
  loadError.value = '';
  try {
    const { data } = await FinancialV2.budgets.show(budgetIdInput.value);
    budget.value = data?.data || data || null;
  } catch (e) {
    budget.value = null;
    loadError.value = e?.response?.data?.message || e?.response?.data?.error || e.message || 'Falha ao carregar';
  } finally {
    loading.value = false;
  }
}

function openWizard() {
  if (!budget.value) return;
  wizardOpen.value = true;
}

function onApproved(result) {
  lastApprovalResult.value = result;
  wizardOpen.value = false;
  // Recarrega o budget pra mostrar parcelas geradas
  loadBudget();
}

const isApproved = computed(() => budget.value?.status === 'aprovado' || budget.value?.status === 'concluido');

onMounted(() => {
  if (budgetIdInput.value) loadBudget();
});
watch(() => route.query.budget_id, (v) => {
  if (v && String(v) !== budgetIdInput.value) {
    budgetIdInput.value = String(v);
    loadBudget();
  }
});
</script>

<template>
  <div class="dev-page">
    <div class="dev-banner">
      <i class="i-lucide-flask-conical w-5 h-5" />
      <div>
        <strong>Modo DEV — PaymentPlanWizardV2 isolado</strong>
        <p>Esta página é preview do wizard antes da integração nos entry points reais (F3 do plano).
        Mudanças aprovadas aqui afetam dados de produção da conta.</p>
      </div>
    </div>

    <header class="page-header">
      <h1>Preview do Wizard de Aprovação</h1>
      <p class="subtitle">
        Cole um <code>budget_id</code> em status <strong>rascunho</strong>, abra o wizard,
        configure entrada/parcelamento e veja o efeito da aprovação.
      </p>
    </header>

    <div class="loader-card">
      <label class="budget-input">
        <span>Budget ID</span>
        <input
          v-model="budgetIdInput"
          type="text"
          placeholder="ex: 13885"
          @keydown.enter="loadBudget"
        />
      </label>
      <button type="button" class="btn-load" :disabled="!budgetIdInput || loading" @click="loadBudget">
        {{ loading ? 'Carregando…' : 'Carregar' }}
      </button>
    </div>

    <div v-if="loadError" class="error-card">
      {{ loadError }}
    </div>

    <div v-if="budget" class="budget-card">
      <header>
        <div>
          <h2>Budget #{{ budget.id }}</h2>
          <p class="meta">
            patient_id={{ budget.patient_id }} ·
            origin={{ budget.origin }} ·
            status=<strong :class="`status-${budget.status}`">{{ budget.status }}</strong>
          </p>
        </div>
        <div class="totals">
          <span class="lbl">Total</span>
          <strong>{{ centsToBRL(budget.total_cents) }}</strong>
        </div>
      </header>

      <table v-if="budget.items?.length" class="items">
        <thead>
          <tr><th>Item</th><th>Qtd</th><th>Unit.</th><th>Subtotal</th></tr>
        </thead>
        <tbody>
          <tr v-for="item in budget.items" :key="item.id">
            <td>{{ item.description }}</td>
            <td>{{ item.quantity }}</td>
            <td>{{ centsToBRL(item.unit_price_cents) }}</td>
            <td>{{ centsToBRL(item.total_cents) }}</td>
          </tr>
        </tbody>
      </table>

      <table v-if="budget.installments?.length" class="installments">
        <caption>Parcelas atuais ({{ budget.installments.length }})</caption>
        <thead>
          <tr><th>#</th><th>Valor</th><th>Vencimento</th><th>Forma</th><th>Status</th><th>Recebido</th></tr>
        </thead>
        <tbody>
          <tr v-for="ins in budget.installments" :key="ins.id">
            <td>{{ ins.number }}/{{ ins.total_in_series }}</td>
            <td>{{ centsToBRL(ins.amount_cents) }}</td>
            <td>{{ ins.due_date }}</td>
            <td>{{ ins.payment_method }}</td>
            <td>{{ ins.status }}</td>
            <td>{{ centsToBRL(ins.received_amount_cents) }}</td>
          </tr>
        </tbody>
      </table>

      <footer class="actions">
        <button
          type="button"
          class="btn-open-wizard"
          :disabled="isApproved"
          :title="isApproved ? 'Budget já aprovado — wizard não aplica' : ''"
          @click="openWizard"
        >
          <i class="i-lucide-wand-2 w-4 h-4" />
          {{ isApproved ? 'Budget já aprovado' : 'Abrir Wizard de Configuração' }}
        </button>
      </footer>
    </div>

    <div v-if="lastApprovalResult" class="approval-result">
      <h3>
        <i class="i-lucide-check-circle-2 w-5 h-5" />
        Última aprovação retornada pelo backend
      </h3>
      <details>
        <summary>Ver payload completo</summary>
        <pre>{{ JSON.stringify(lastApprovalResult, null, 2) }}</pre>
      </details>
    </div>

    <PaymentPlanWizardV2
      :show="wizardOpen"
      :budget="budget"
      @close="wizardOpen = false"
      @approved="onApproved"
    />
  </div>
</template>

<style scoped lang="scss">
.dev-page {
  max-width: 1100px;
  margin: 0 auto;
  padding: 24px;
  display: flex; flex-direction: column; gap: 16px;
}

.dev-banner {
  display: flex; align-items: flex-start; gap: 12px;
  background: rgb(var(--amber-3));
  border: 1px solid rgb(var(--amber-7));
  color: rgb(var(--amber-11));
  border-radius: 8px;
  padding: 12px 16px;

  > i { margin-top: 2px; }
  strong { font-size: 14px; }
  p { margin: 4px 0 0; font-size: 12px; }
}

.page-header {
  h1 { margin: 0 0 4px; font-size: 22px; color: rgb(var(--slate-12)); }
  .subtitle { margin: 0; font-size: 13px; color: rgb(var(--slate-10)); }
  code { background: rgb(var(--slate-3)); padding: 1px 5px; border-radius: 4px; }
}

.loader-card {
  display: flex; gap: 12px; align-items: flex-end;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  padding: 14px;

  .budget-input {
    flex: 1;
    display: flex; flex-direction: column; gap: 4px;
    > span { font-size: 12px; color: rgb(var(--slate-10)); text-transform: uppercase; letter-spacing: 0.05em; }
    > input {
      padding: 8px 10px; border: 1px solid rgb(var(--slate-6)); border-radius: 6px;
      background: rgb(var(--slate-1)); color: rgb(var(--slate-12)); font-size: 14px;
    }
  }
  .btn-load {
    padding: 8px 16px;
    background: rgb(var(--blue-9)); color: white;
    border: 0; border-radius: 6px; cursor: pointer; font-weight: 500;
    &:hover:not(:disabled) { background: rgb(var(--blue-10)); }
    &:disabled { background: rgb(var(--slate-6)); cursor: not-allowed; }
  }
}

.error-card {
  padding: 12px 14px;
  background: rgb(var(--ruby-3));
  color: rgb(var(--ruby-11));
  border: 1px solid rgb(var(--ruby-7));
  border-radius: 8px;
  font-size: 13px;
}

.budget-card {
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 10px;
  padding: 16px 20px;

  header {
    display: flex; justify-content: space-between; align-items: flex-start;
    border-bottom: 1px solid rgb(var(--slate-3));
    padding-bottom: 12px; margin-bottom: 12px;

    h2 { margin: 0; font-size: 18px; color: rgb(var(--slate-12)); }
    .meta {
      margin: 4px 0 0; font-size: 12px; color: rgb(var(--slate-10));
      .status-rascunho { color: rgb(var(--amber-11)); }
      .status-aprovado { color: rgb(var(--green-11)); }
      .status-cancelado { color: rgb(var(--ruby-11)); }
      .status-concluido { color: rgb(var(--blue-11)); }
    }
    .totals {
      text-align: right;
      .lbl { font-size: 11px; color: rgb(var(--slate-10)); text-transform: uppercase; }
      strong { display: block; font-size: 20px; color: rgb(var(--blue-11)); }
    }
  }

  table {
    width: 100%; border-collapse: collapse; font-size: 13px; margin-top: 12px;
    caption {
      text-align: left;
      padding: 6px 0;
      font-size: 12px; color: rgb(var(--slate-10));
      text-transform: uppercase; letter-spacing: 0.05em;
    }
    th { text-align: left; padding: 8px; border-bottom: 1px solid rgb(var(--slate-4));
      font-weight: 600; color: rgb(var(--slate-11)); }
    td { padding: 6px 8px; border-bottom: 1px solid rgb(var(--slate-2)); }
  }
}

.actions {
  margin-top: 16px;
  display: flex; justify-content: flex-end;
}

.btn-open-wizard {
  display: inline-flex; align-items: center; gap: 8px;
  padding: 10px 16px;
  background: rgb(var(--blue-9)); color: white;
  border: 0; border-radius: 8px; cursor: pointer;
  font-weight: 600; font-size: 14px;

  &:hover:not(:disabled) { background: rgb(var(--blue-10)); }
  &:disabled { background: rgb(var(--slate-6)); cursor: not-allowed; }
}

.approval-result {
  background: rgb(var(--green-2));
  border: 1px solid rgb(var(--green-7));
  border-radius: 8px;
  padding: 14px 16px;

  h3 {
    display: inline-flex; align-items: center; gap: 8px;
    margin: 0 0 8px; font-size: 15px; color: rgb(var(--green-11));
  }
  summary { cursor: pointer; color: rgb(var(--blue-11)); font-size: 13px; }
  pre {
    margin: 8px 0 0;
    background: rgb(var(--slate-1));
    border: 1px solid rgb(var(--slate-4));
    border-radius: 6px;
    padding: 10px;
    font-size: 11px;
    line-height: 1.5;
    overflow-x: auto;
    max-height: 400px;
    color: rgb(var(--slate-12));
  }
}
</style>
