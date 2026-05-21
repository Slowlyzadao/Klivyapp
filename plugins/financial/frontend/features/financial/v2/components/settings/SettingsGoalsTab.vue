<script setup>
/**
 * Aba Metas (canon §4.5) — 3 metas independentes:
 *   mensal (com mês), trimestral (com quarter), anual.
 *
 * Endpoint backend: financial/v2/revenue_goals (upsert via POST /upsert).
 * Cada meta é única por (period, year, [month|quarter]).
 *
 * BUG-11 fix vem de cima: Dashboard oculta gauge se a meta=0 e mostra CTA
 * apontando pra essa tela.
 *
 * UI premium: FormSelect, BeclinicButton, Badge, live formatter, mobile-friendly.
 */
import { ref, computed, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import ConfirmDangerModal from '@plugins/beclinic_core/frontend/components/ConfirmDangerModal.vue';
import FinancialV2 from '../../api/financialV2';
import {
  brlInputToCents,
  centsToBRL,
  formatCurrencyInput,
} from '../../composables/useMoney';
import '@plugins/financial/frontend/styles/financial.scss';

const goals = ref([]);
const loading = ref(false);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const today = new Date();
const form = ref({
  monthly:    { amount_str: '', month: today.getMonth() + 1, year: today.getFullYear() },
  quarterly:  { amount_str: '', quarter: Math.ceil((today.getMonth() + 1) / 3), year: today.getFullYear() },
  annual:     { amount_str: '', year: today.getFullYear() },
});

const MONTHS = ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
                'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'];
const MONTHS_SHORT = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];

const monthOptions = MONTHS.map((label, i) => ({ value: i + 1, label }));
const quarterOptions = [
  { value: 1, label: '1º trimestre (Jan – Mar)' },
  { value: 2, label: '2º trimestre (Abr – Jun)' },
  { value: 3, label: '3º trimestre (Jul – Set)' },
  { value: 4, label: '4º trimestre (Out – Dez)' },
];

const monthlyGoals   = computed(() => goals.value.filter(g => g.period === 'monthly').sort(sortByPeriod));
const quarterlyGoals = computed(() => goals.value.filter(g => g.period === 'quarterly').sort(sortByPeriod));
const annualGoals    = computed(() => goals.value.filter(g => g.period === 'annual').sort(sortByPeriod));

function sortByPeriod(a, b) {
  if (a.year !== b.year) return b.year - a.year;
  if (a.month && b.month) return b.month - a.month;
  if (a.quarter && b.quarter) return b.quarter - a.quarter;
  return 0;
}

async function load() {
  loading.value = true;
  try {
    const { data } = await FinancialV2.revenueGoals.index();
    goals.value = data?.data || [];
  } catch (err) {
    notifyError(err?.response?.data?.message || 'Erro ao carregar metas');
  } finally {
    loading.value = false;
  }
}

async function upsert(period) {
  const payload = { period };
  const f = form.value[period];

  if (!f.amount_str || brlInputToCents(f.amount_str) <= 0) {
    notifyError('Informe um valor maior que zero.');
    return;
  }

  payload.year = f.year;
  payload.amount_cents = brlInputToCents(f.amount_str);
  if (period === 'monthly')   payload.month = f.month;
  if (period === 'quarterly') payload.quarter = f.quarter;

  loading.value = true;
  try {
    await FinancialV2.revenueGoals.upsert(payload);
    notifySuccess('Meta salva com sucesso.');
    f.amount_str = '';
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Erro ao salvar meta');
  } finally {
    loading.value = false;
  }
}

// Estado do ConfirmDangerModal (regra do projeto: usar modal pra exclusões).
const showDeleteModal = ref(false);
const goalToDelete = ref(null);
const deleting = ref(false);

function destroy(goal) {
  goalToDelete.value = goal;
  showDeleteModal.value = true;
}

async function confirmDestroy() {
  const goal = goalToDelete.value;
  if (!goal) return;
  deleting.value = true;
  try {
    await FinancialV2.revenueGoals.destroy(goal.id);
    notifySuccess('Meta removida.');
    showDeleteModal.value = false;
    goalToDelete.value = null;
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.message || 'Erro ao remover');
  } finally {
    deleting.value = false;
  }
}

function describePeriod(g) {
  if (g.period === 'monthly') return `${MONTHS_SHORT[g.month - 1]}/${g.year}`;
  if (g.period === 'quarterly') return `${g.quarter}º trim/${g.year}`;
  return `Ano ${g.year}`;
}

function onMoneyInput(period, e) {
  const formatted = formatCurrencyInput(e.target.value);
  form.value[period].amount_str = formatted;
  e.target.value = formatted;
}

onMounted(load);
</script>

<template>
  <div class="set-goals">
    <header class="set-goals__header">
      <h2 class="set-goals__title">Metas de receita</h2>
      <p class="set-goals__subtitle">
        Três metas independentes (mensal, trimestral, anual). O Dashboard usa a
        meta vigente para o gauge "Receita vs Meta". Editar uma meta no meio do
        período recalcula o gauge imediatamente.
      </p>
    </header>

    <div class="set-goals__grid">
      <!-- Mensal -->
      <section class="set-goals__card">
        <header class="set-goals__card-header">
          <i class="i-lucide-calendar-days w-4 h-4 set-goals__card-icon set-goals__card-icon--blue" />
          <h3>Meta mensal</h3>
        </header>

        <div class="set-goals__form">
          <div class="set-goals__form-row">
            <label class="set-goals__field">
              <span class="set-goals__field-label">Mês</span>
              <FormSelect v-model="form.monthly.month" :options="monthOptions" />
            </label>
            <label class="set-goals__field">
              <span class="set-goals__field-label">Ano</span>
              <input v-model.number="form.monthly.year" type="number" min="2020" max="2099" class="finv2-input" />
            </label>
          </div>
          <label class="set-goals__field">
            <span class="set-goals__field-label">Valor da meta</span>
            <div class="set-goals__currency-wrap">
              <span class="set-goals__currency-prefix">R$</span>
              <input
                :value="form.monthly.amount_str"
                type="text"
                inputmode="numeric"
                placeholder="50.000,00"
                class="finv2-input set-goals__currency-input"
                @input="(e) => onMoneyInput('monthly', e)"
              />
            </div>
          </label>
          <BeclinicButton
            variant="solid"
            color="teal"
            icon="i-lucide-target"
            label="Salvar meta mensal"
            :is-loading="loading"
            :disabled="loading"
            @click="upsert('monthly')"
          />
        </div>

        <div v-if="monthlyGoals.length" class="set-goals__history">
          <h4 class="set-goals__history-title">
            Metas cadastradas
            <Badge :label="String(monthlyGoals.length)" color="blue" size="xs" />
          </h4>
          <ul class="set-goals__list">
            <li v-for="g in monthlyGoals" :key="g.id" class="set-goals__list-item">
              <span class="set-goals__period">{{ describePeriod(g) }}</span>
              <strong class="set-goals__amount">{{ centsToBRL(g.amount_cents) }}</strong>
              <BeclinicButton size="xs" variant="ghost" color="ruby" icon="i-lucide-trash-2" @click="destroy(g)" />
            </li>
          </ul>
        </div>
      </section>

      <!-- Trimestral -->
      <section class="set-goals__card">
        <header class="set-goals__card-header">
          <i class="i-lucide-calendar w-4 h-4 set-goals__card-icon set-goals__card-icon--violet" />
          <h3>Meta trimestral</h3>
        </header>

        <div class="set-goals__form">
          <div class="set-goals__form-row">
            <label class="set-goals__field">
              <span class="set-goals__field-label">Trimestre</span>
              <FormSelect v-model="form.quarterly.quarter" :options="quarterOptions" />
            </label>
            <label class="set-goals__field">
              <span class="set-goals__field-label">Ano</span>
              <input v-model.number="form.quarterly.year" type="number" min="2020" max="2099" class="finv2-input" />
            </label>
          </div>
          <label class="set-goals__field">
            <span class="set-goals__field-label">Valor da meta</span>
            <div class="set-goals__currency-wrap">
              <span class="set-goals__currency-prefix">R$</span>
              <input
                :value="form.quarterly.amount_str"
                type="text"
                inputmode="numeric"
                placeholder="150.000,00"
                class="finv2-input set-goals__currency-input"
                @input="(e) => onMoneyInput('quarterly', e)"
              />
            </div>
          </label>
          <BeclinicButton
            variant="solid"
            color="teal"
            icon="i-lucide-target"
            label="Salvar meta trimestral"
            :is-loading="loading"
            :disabled="loading"
            @click="upsert('quarterly')"
          />
        </div>

        <div v-if="quarterlyGoals.length" class="set-goals__history">
          <h4 class="set-goals__history-title">
            Metas cadastradas
            <Badge :label="String(quarterlyGoals.length)" color="violet" size="xs" />
          </h4>
          <ul class="set-goals__list">
            <li v-for="g in quarterlyGoals" :key="g.id" class="set-goals__list-item">
              <span class="set-goals__period">{{ describePeriod(g) }}</span>
              <strong class="set-goals__amount">{{ centsToBRL(g.amount_cents) }}</strong>
              <BeclinicButton size="xs" variant="ghost" color="ruby" icon="i-lucide-trash-2" @click="destroy(g)" />
            </li>
          </ul>
        </div>
      </section>

      <!-- Anual -->
      <section class="set-goals__card">
        <header class="set-goals__card-header">
          <i class="i-lucide-trophy w-4 h-4 set-goals__card-icon set-goals__card-icon--emerald" />
          <h3>Meta anual</h3>
        </header>

        <div class="set-goals__form">
          <label class="set-goals__field">
            <span class="set-goals__field-label">Ano</span>
            <input v-model.number="form.annual.year" type="number" min="2020" max="2099" class="finv2-input" />
          </label>
          <label class="set-goals__field">
            <span class="set-goals__field-label">Valor da meta</span>
            <div class="set-goals__currency-wrap">
              <span class="set-goals__currency-prefix">R$</span>
              <input
                :value="form.annual.amount_str"
                type="text"
                inputmode="numeric"
                placeholder="600.000,00"
                class="finv2-input set-goals__currency-input"
                @input="(e) => onMoneyInput('annual', e)"
              />
            </div>
          </label>
          <BeclinicButton
            variant="solid"
            color="teal"
            icon="i-lucide-target"
            label="Salvar meta anual"
            :is-loading="loading"
            :disabled="loading"
            @click="upsert('annual')"
          />
        </div>

        <div v-if="annualGoals.length" class="set-goals__history">
          <h4 class="set-goals__history-title">
            Metas cadastradas
            <Badge :label="String(annualGoals.length)" color="emerald" size="xs" />
          </h4>
          <ul class="set-goals__list">
            <li v-for="g in annualGoals" :key="g.id" class="set-goals__list-item">
              <span class="set-goals__period">{{ describePeriod(g) }}</span>
              <strong class="set-goals__amount">{{ centsToBRL(g.amount_cents) }}</strong>
              <BeclinicButton size="xs" variant="ghost" color="ruby" icon="i-lucide-trash-2" @click="destroy(g)" />
            </li>
          </ul>
        </div>
      </section>
    </div>

    <!-- Confirmação de exclusão de meta. -->
    <ConfirmDangerModal
      v-model:show="showDeleteModal"
      title="Remover meta?"
      :message="goalToDelete
        ? `A meta de ${describePeriod(goalToDelete)} (${centsToBRL(goalToDelete.amount_cents)}) será removida. Esta ação não pode ser desfeita.`
        : ''"
      confirm-label="Remover meta"
      :loading="deleting"
      @confirm="confirmDestroy"
    />
  </div>
</template>

<style scoped lang="scss">
.set-goals__header { margin-bottom: 18px; }
.set-goals__title { margin: 0 0 4px; font-size: 17px; font-weight: 600; color: rgb(var(--slate-12)); }
.set-goals__subtitle { margin: 0; color: rgb(var(--slate-9)); font-size: 13px; line-height: 1.5; max-width: 640px; }

.set-goals__grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
  gap: 14px;
}

.set-goals__card {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 16px;
  display: flex; flex-direction: column; gap: 14px;
}
.set-goals__card-header {
  display: flex; align-items: center; gap: 8px;
  h3 { margin: 0; font-size: 14px; font-weight: 600; color: rgb(var(--slate-12)); }
}
.set-goals__card-icon--blue    { color: rgb(var(--blue-9)); }
.set-goals__card-icon--violet  { color: #7c3aed; }
.set-goals__card-icon--emerald { color: #047857; }
:root.dark .set-goals__card-icon--violet  { color: #c4b5fd; }
:root.dark .set-goals__card-icon--emerald { color: #6ee7b7; }

.set-goals__form { display: flex; flex-direction: column; gap: 10px; }
.set-goals__form-row { display: grid; grid-template-columns: 2fr 1fr; gap: 8px; }
@media (max-width: 480px) { .set-goals__form-row { grid-template-columns: 1fr; } }

.set-goals__field { display: flex; flex-direction: column; gap: 5px; min-width: 0; }
.set-goals__field-label { font-size: 12px; font-weight: 500; color: rgb(var(--slate-11)); }

/* Currency input */
.set-goals__currency-wrap { position: relative; display: flex; align-items: center; }
.set-goals__currency-prefix {
  position: absolute; left: 12px; top: 50%; transform: translateY(-50%);
  font-size: 13px; font-weight: 500; color: rgb(var(--slate-9));
  pointer-events: none; z-index: 1;
}
.set-goals__currency-input {
  padding-left: 32px;
  text-align: right;
  font-variant-numeric: tabular-nums;
}

/* Histórico */
.set-goals__history { padding-top: 12px; border-top: 1px dashed rgb(var(--slate-5)); display: flex; flex-direction: column; gap: 8px; }
.set-goals__history-title {
  margin: 0;
  display: inline-flex; align-items: center; gap: 6px;
  font-size: 11px; text-transform: uppercase; letter-spacing: 0.04em;
  color: rgb(var(--slate-9)); font-weight: 600;
}

.set-goals__list { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 6px; }
.set-goals__list-item {
  display: grid; grid-template-columns: 1fr auto auto; gap: 8px; align-items: center;
  padding: 8px 10px;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-3));
  border-radius: 8px;
  font-size: 13px;
}
.set-goals__period { color: rgb(var(--slate-11)); }
.set-goals__amount { color: rgb(var(--slate-12)); font-weight: 600; font-variant-numeric: tabular-nums; }
</style>
