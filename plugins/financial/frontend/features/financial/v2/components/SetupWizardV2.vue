<script setup>
/**
 * Wizard de configuração inicial obrigatório (canon F-04 + BUG-04 raiz).
 * Bloqueia uso do módulo financeiro até passos obrigatórios concluídos.
 *
 * Passos:
 *   1. Categorias (obrigatório — pelo menos 1 de cada tipo)
 *   2. Contas bancárias (obrigatório — pelo menos 1 + caixa físico)
 *   3. Regras de comissão (opcional)
 *   4. Despesas recorrentes (opcional)
 *   5. Meta de receita (opcional)
 *
 * Forms inline para 1 e 2 — o usuário cria os registros direto aqui.
 * 3, 4, 5 ficam como "marcar concluído" / pular por enquanto.
 */
import { ref, computed, onMounted } from 'vue';
import FinancialV2 from '../api/financialV2';
import { brlInputToCents, centsToBRL } from '../composables/useMoney';

const emit = defineEmits(['completed']);

const state = ref(null);
const loading = ref(false);
const currentStep = ref(0);
const errorMessage = ref('');

const STEPS = [
  { key: 'categories', label: 'Categorias', required: true },
  { key: 'bank_accounts', label: 'Contas e Caixa', required: true },
  { key: 'commission_rules', label: 'Comissões', required: false },
  { key: 'recurring_expenses', label: 'Despesas recorrentes', required: false },
  { key: 'revenue_goal', label: 'Metas de receita', required: false },
];

// ---- STEP 1 — Categorias (defaults canon §4.1) ----
// Permite editar antes de criar; pelo menos 1 de cada tipo é obrigatório no canon.
const defaultCategories = [
  { name: 'Consultas particulares', kind: 'receita' },
  { name: 'Convênios', kind: 'receita' },
  { name: 'Vendas de produtos', kind: 'receita' },
  { name: 'Outras receitas', kind: 'receita' },

  { name: 'Aluguel', kind: 'despesa_fixa' },
  { name: 'Folha + encargos', kind: 'despesa_fixa' },
  { name: 'Software/Sistemas', kind: 'despesa_fixa' },
  { name: 'Contador', kind: 'despesa_fixa' },

  { name: 'Materiais clínicos', kind: 'custo_variavel' },
  { name: 'Laboratório', kind: 'custo_variavel' },
  { name: 'Comissões', kind: 'custo_variavel' },
  { name: 'Taxas de cartão (MDR)', kind: 'custo_variavel' },

  { name: 'Impostos', kind: 'outra_despesa' },
  { name: 'Marketing', kind: 'outra_despesa' },
  { name: 'Manutenção', kind: 'outra_despesa' },
  { name: 'Quebra de caixa', kind: 'outra_despesa' },
];
const categoriesDraft = ref(defaultCategories.map((c) => ({ ...c, selected: true })));
const existingCategoriesCount = ref(null); // null = não verificado ainda

// ---- STEP 2 — Contas bancárias ----
const bankAccountsDraft = ref([
  { name: 'Conta Corrente PJ', kind: 'checking', initial_balance_str: '0,00', selected: true },
  { name: 'Caixa físico', kind: 'cash', initial_balance_str: '0,00', selected: true },
]);
const existingBanksCount = ref(null);

// ---------- helpers ----------
const KIND_LABEL = {
  receita: 'Receita',
  despesa_fixa: 'Despesa Fixa',
  custo_variavel: 'Custo Variável',
  outra_despesa: 'Outra Despesa',
};
const BANK_KIND_LABEL = {
  checking: 'Conta corrente',
  savings: 'Poupança',
  cash: 'Caixa físico',
  card_receivable: 'A receber de maquininha',
};

const isComplete = computed(() => state.value?.required_steps_done);
const progress = computed(() => state.value?.progress_percent || 0);

const categoriesByKind = computed(() => {
  const groups = { receita: [], despesa_fixa: [], custo_variavel: [], outra_despesa: [] };
  for (const c of categoriesDraft.value) groups[c.kind]?.push(c);
  return groups;
});

const canFinishCategoriesStep = computed(() => {
  const selected = categoriesDraft.value.filter((c) => c.selected);
  const kinds = new Set(selected.map((c) => c.kind));
  return kinds.size === 4; // pelo menos 1 de cada tipo
});

const canFinishBanksStep = computed(() => {
  const selected = bankAccountsDraft.value.filter((b) => b.selected && b.name);
  const kinds = new Set(selected.map((b) => b.kind));
  return selected.length >= 1 && kinds.has('cash'); // canon §4.2: precisa caixa físico
});

// ---------- API actions ----------
async function load() {
  loading.value = true;
  errorMessage.value = '';
  try {
    const { data } = await FinancialV2.setup.show();
    state.value = data;
    const firstPending = STEPS.findIndex((s) => !state.value.steps[s.key]);
    currentStep.value = firstPending === -1 ? STEPS.length - 1 : firstPending;
    // refresh contadores
    fetchCounts();
  } catch (err) {
    errorMessage.value = err?.response?.data?.message || err?.message || 'Erro ao carregar setup';
  } finally {
    loading.value = false;
  }
}

async function fetchCounts() {
  try {
    const cats = await FinancialV2.categories.index();
    existingCategoriesCount.value = cats.data?.data?.length || 0;
  } catch { existingCategoriesCount.value = 0; }
  try {
    const banks = await FinancialV2.bankAccounts.index();
    existingBanksCount.value = banks.data?.data?.length || 0;
  } catch { existingBanksCount.value = 0; }
}

async function completeStep(stepKey) {
  loading.value = true;
  errorMessage.value = '';
  try {
    const { data } = await FinancialV2.setup.completeStep(`step_${stepKey}_done`);
    state.value = data;
    if (currentStep.value < STEPS.length - 1) currentStep.value++;
    if (state.value.required_steps_done) emit('completed');
  } catch (err) {
    errorMessage.value = err?.response?.data?.message || err?.message || 'Erro ao concluir passo';
  } finally {
    loading.value = false;
  }
}

async function createCategoriesAndAdvance() {
  loading.value = true;
  errorMessage.value = '';
  try {
    const toCreate = categoriesDraft.value.filter((c) => c.selected && c.name?.trim());
    for (const c of toCreate) {
      await FinancialV2.categories.create({ category: { name: c.name, kind: c.kind, active: true } });
    }
    await completeStep('categories');
  } catch (err) {
    errorMessage.value = err?.response?.data?.errors?.join('; ') || err?.message || 'Erro ao criar categorias';
  } finally {
    loading.value = false;
    fetchCounts();
  }
}

async function createBanksAndAdvance() {
  loading.value = true;
  errorMessage.value = '';
  try {
    const toCreate = bankAccountsDraft.value.filter((b) => b.selected && b.name?.trim());
    for (const b of toCreate) {
      await FinancialV2.bankAccounts.create({
        bank_account: {
          name: b.name,
          kind: b.kind,
          initial_balance_cents: brlInputToCents(b.initial_balance_str || '0,00'),
          active: true,
        },
      });
    }
    await completeStep('bank_accounts');
  } catch (err) {
    errorMessage.value = err?.response?.data?.errors?.join('; ') || err?.message || 'Erro ao criar contas';
  } finally {
    loading.value = false;
    fetchCounts();
  }
}

function addCategoryRow(kind) {
  categoriesDraft.value.push({ name: '', kind, selected: true });
}
function addBankRow() {
  bankAccountsDraft.value.push({ name: '', kind: 'checking', initial_balance_str: '0,00', selected: true });
}

onMounted(load);
</script>

<template>
  <div v-if="state && state.status !== 'completed'" class="setup-wizard-v2">
    <div class="card">
      <header>
        <h1>Configurar módulo financeiro</h1>
        <p>
          Conclua os passos abaixo para liberar o uso. Sem eles, lançamentos caem em
          <strong>"Sem categoria"</strong> e o DRE fica incompleto.
        </p>
        <div class="progress">
          <div class="bar" :style="{ width: `${progress}%` }"></div>
          <span>{{ progress }}%</span>
        </div>
      </header>

      <p v-if="errorMessage" class="error" role="alert">{{ errorMessage }}</p>

      <ol class="steps">
        <li
          v-for="(step, idx) in STEPS"
          :key="step.key"
          :class="{
            done: state.steps[step.key],
            current: idx === currentStep,
            disabled: idx > currentStep && !state.steps[step.key],
          }"
        >
          <span class="step-bullet">
            <span v-if="state.steps[step.key]" class="i-lucide-check" />
            <span v-else>{{ idx + 1 }}</span>
          </span>
          <div class="step-body">
            <header class="step-header">
              <strong>{{ step.label }}</strong>
              <small v-if="step.required" class="required">obrigatório</small>
              <small v-else>opcional</small>
            </header>

            <!-- ===== STEP 1 — Categorias ===== -->
            <div v-if="idx === currentStep && step.key === 'categories' && !state.steps.categories" class="step-content">
              <p class="hint">
                O canon do módulo recomenda pelo menos 1 categoria de cada tipo (Receita, Despesa Fixa, Custo Variável, Outra Despesa).
                Edite ou desmarque o que não usa.
                <span v-if="existingCategoriesCount > 0">— Você já tem <strong>{{ existingCategoriesCount }}</strong> cadastrada(s).</span>
              </p>
              <div class="cat-groups">
                <fieldset v-for="(group, kind) in categoriesByKind" :key="kind">
                  <legend>{{ KIND_LABEL[kind] }}</legend>
                  <label v-for="cat in group" :key="`${cat.kind}-${cat.name}-${categoriesDraft.indexOf(cat)}`" class="cat-row">
                    <input v-model="cat.selected" type="checkbox" />
                    <input v-model="cat.name" type="text" :placeholder="`Nome da ${KIND_LABEL[kind].toLowerCase()}`" />
                  </label>
                  <button type="button" class="btn-add" @click="addCategoryRow(kind)">+ adicionar</button>
                </fieldset>
              </div>
              <div class="step-actions">
                <button type="button" class="btn-confirm" :disabled="!canFinishCategoriesStep || loading" @click="createCategoriesAndAdvance">
                  Criar categorias e continuar
                </button>
                <button type="button" class="btn-skip" :disabled="loading" @click="completeStep('categories')">
                  Pular (já tenho)
                </button>
              </div>
            </div>

            <!-- ===== STEP 2 — Contas bancárias ===== -->
            <div v-else-if="idx === currentStep && step.key === 'bank_accounts' && !state.steps.bank_accounts" class="step-content">
              <p class="hint">
                Cadastre pelo menos uma conta bancária e o caixa físico (obrigatório por convenção do módulo).
                <span v-if="existingBanksCount > 0">— Você já tem <strong>{{ existingBanksCount }}</strong> cadastrada(s).</span>
              </p>
              <div class="banks">
                <div v-for="(b, i) in bankAccountsDraft" :key="`bank-${i}`" class="bank-row">
                  <label class="check">
                    <input v-model="b.selected" type="checkbox" />
                  </label>
                  <input v-model="b.name" type="text" placeholder="Nome (ex: Itaú PJ)" />
                  <select v-model="b.kind">
                    <option value="checking">Conta corrente</option>
                    <option value="savings">Poupança</option>
                    <option value="cash">Caixa físico</option>
                    <option value="card_receivable">A receber de maquininha</option>
                  </select>
                  <input v-model="b.initial_balance_str" type="text" inputmode="decimal" placeholder="Saldo inicial" />
                </div>
                <button type="button" class="btn-add" @click="addBankRow">+ adicionar</button>
              </div>
              <div class="step-actions">
                <button type="button" class="btn-confirm" :disabled="!canFinishBanksStep || loading" @click="createBanksAndAdvance">
                  Criar contas e continuar
                </button>
                <button type="button" class="btn-skip" :disabled="loading" @click="completeStep('bank_accounts')">
                  Pular (já tenho)
                </button>
                <p v-if="!canFinishBanksStep" class="hint warn">
                  É preciso ter ao menos uma conta + um caixa físico (kind=cash).
                </p>
              </div>
            </div>

            <!-- ===== STEPS 3-5 — opcionais ===== -->
            <div v-else-if="idx === currentStep && !state.steps[step.key]" class="step-content">
              <p class="hint">
                Você pode configurar isso mais tarde em <strong>Financeiro → Configurações</strong>.
                Marque como concluído para passar adiante.
              </p>
              <div class="step-actions">
                <button type="button" class="btn-confirm" :disabled="loading" @click="completeStep(step.key)">
                  Marcar passo concluído
                </button>
              </div>
            </div>
          </div>
        </li>
      </ol>

      <footer v-if="isComplete">
        <p class="ok">
          <span class="i-lucide-check-circle" aria-hidden="true"></span>
          Passos obrigatórios concluídos. Você já pode usar o módulo financeiro.
        </p>
      </footer>
    </div>
  </div>
</template>

<style scoped lang="scss">
.setup-wizard-v2 {
  display: grid; place-items: center; padding: 24px;
  .card {
    width: min(900px, 100%); background: white; border-radius: 12px;
    padding: 24px; display: flex; flex-direction: column; gap: 16px;
    box-shadow: 0 8px 32px rgba(15, 23, 42, 0.08);
  }
  h1 { margin: 0 0 4px; font-size: 22px; }
  p { margin: 0; color: var(--s-600, #475569); font-size: 14px; }
  .progress {
    height: 8px; background: var(--s-100, #f1f5f9); border-radius: 999px; overflow: hidden;
    position: relative; margin-top: 12px;
    .bar { height: 100%; background: var(--g-500, #22c55e); transition: width 200ms; }
    span { position: absolute; right: 8px; top: -20px; font-size: 11px; color: var(--s-600, #475569); }
  }
  .error { color: var(--r-700, #b91c1c); padding: 8px 12px; border-radius: 6px; background: var(--r-50, #fef2f2); border: 1px solid var(--r-200, #fecaca); font-size: 13px; }
  .steps {
    list-style: none; padding: 0; margin: 0;
    display: flex; flex-direction: column; gap: 12px;
    li {
      display: flex; gap: 12px;
      padding: 12px; border-radius: 8px; border: 1px solid var(--s-200, #e2e8f0);
      transition: background 200ms;
      &.done { background: var(--g-50, #f0fdf4); border-color: var(--g-200, #bbf7d0); }
      &.current { border-color: var(--w-400, #60a5fa); background: var(--w-50, #eff6ff); }
      &.disabled { opacity: 0.6; }
    }
    .step-bullet {
      width: 28px; height: 28px; border-radius: 50%; background: var(--s-100, #f1f5f9);
      display: grid; place-items: center; font-weight: 600; font-size: 12px;
      flex-shrink: 0;
    }
    li.done .step-bullet { background: var(--g-500, #22c55e); color: white; }
    li.current .step-bullet { background: var(--w-500, #3b82f6); color: white; }
    .step-body { flex: 1; display: flex; flex-direction: column; gap: 4px; }
    .step-header { display: flex; align-items: baseline; gap: 8px; }
    .step-header small { color: var(--s-500, #64748b); }
    .step-header small.required { color: var(--r-600, #dc2626); font-weight: 600; text-transform: uppercase; }
    .step-content { margin-top: 8px; padding-top: 8px; border-top: 1px dashed var(--s-200, #e2e8f0); }
    .hint { font-size: 12px; color: var(--s-700, #334155); margin: 0 0 8px; line-height: 1.5; }
    .hint.warn { color: var(--r-700, #b91c1c); }
  }
  .cat-groups {
    display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px;
    fieldset {
      border: 1px solid var(--s-200, #e2e8f0); border-radius: 8px; padding: 8px 10px;
      legend { font-size: 11px; font-weight: 700; padding: 0 6px; color: var(--s-700, #334155); text-transform: uppercase; letter-spacing: 0.04em; }
    }
    .cat-row {
      display: grid; grid-template-columns: auto 1fr; gap: 6px; align-items: center; margin-bottom: 4px;
      input[type='text'] { padding: 4px 8px; font-size: 13px; border: 1px solid var(--s-200, #e2e8f0); border-radius: 4px; }
    }
  }
  .banks {
    display: flex; flex-direction: column; gap: 8px;
    .bank-row {
      display: grid; grid-template-columns: auto 2fr 1.5fr 1fr; gap: 8px; align-items: center;
      input, select { padding: 6px 10px; border: 1px solid var(--s-300, #cbd5e1); border-radius: 6px; font-size: 13px; }
      .check input { transform: scale(1.1); }
    }
  }
  .btn-add {
    margin-top: 4px; padding: 4px 10px; background: transparent; border: 1px dashed var(--s-300, #cbd5e1);
    border-radius: 4px; cursor: pointer; font-size: 12px; color: var(--s-700, #334155);
    &:hover { background: var(--s-50, #f8fafc); }
  }
  .step-actions {
    display: flex; gap: 8px; align-items: center; margin-top: 12px; flex-wrap: wrap;
    .btn-confirm {
      padding: 8px 14px; background: var(--w-600, #1e88e5); color: white;
      border: 0; border-radius: 6px; cursor: pointer; font-weight: 600;
      &:disabled { opacity: 0.5; cursor: not-allowed; }
    }
    .btn-skip {
      padding: 8px 14px; background: transparent; color: var(--s-700, #334155);
      border: 1px solid var(--s-300, #cbd5e1); border-radius: 6px; cursor: pointer; font-weight: 500;
      &:hover { background: var(--s-50, #f8fafc); }
      &:disabled { opacity: 0.5; }
    }
  }
  .ok {
    color: var(--g-700, #15803d); font-weight: 600; display: flex; align-items: center; gap: 6px;
  }
}
</style>
