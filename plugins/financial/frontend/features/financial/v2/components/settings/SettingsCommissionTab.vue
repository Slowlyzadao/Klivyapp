<script setup>
/**
 * Aba "Regras de Comissão" — wireframe Setup #5 (2026-05-23).
 *
 * Tabela 9 colunas: REGRA / PROFISSIONAL / PAPEL (DR/SDR/Comercial) /
 * GATILHO (trigger_event) / TIPO (Percentual/Fixo) / VALOR /
 * ESCOPO (todos/por_procedimento/por_especialidade) / PGTO (pay_when) /
 * STATUS / AÇÕES.
 *
 * Canon: comissão sempre sobre RECEBIDO (não orçado), descontando MDR/lab
 * quando aplicável. Mudança de regra NÃO recalcula histórico — CommissionEntry
 * guarda snapshot da regra usada.
 *
 * Apenas ADMIN cria/edita (backend retorna 403).
 */
import { ref, computed, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ConfirmDangerModalV2 from '../ConfirmDangerModalV2.vue';
import CommissionRuleFormModalV2 from './CommissionRuleFormModalV2.vue';
import FinancialV2 from '../../api/financialV2';
import { centsToBRL } from '../../composables/useMoney';

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const rules = ref([]);
const loading = ref(false);
const errorState = ref(null);

const showFormModal = ref(false);
const formMode = ref('create');
const formInitial = ref(null);

const showDeleteModal = ref(false);
const ruleToDelete = ref(null);
const deleting = ref(false);

async function load() {
  loading.value = true;
  errorState.value = null;
  try {
    const { data } = await FinancialV2.commissionRules.index();
    rules.value = data?.data || [];
  } catch (err) {
    errorState.value = err?.response?.data?.message || 'Erro ao carregar regras';
    notifyError(errorState.value);
  } finally {
    loading.value = false;
  }
}

onMounted(load);

// ── Formatadores e labels ────────────────────────────────────────────
function fmtPercent(bp) {
  if (bp == null) return '—';
  return `${(bp / 100).toFixed(bp % 100 === 0 ? 0 : 2)}%`;
}

const ROLE_LABELS = { DR: 'DR', SDR: 'SDR', Comercial: 'Comercial' };
const ROLE_CLASSES = {
  DR: 'role--dr',
  SDR: 'role--sdr',
  Comercial: 'role--comercial',
};
function roleLabel(role) { return ROLE_LABELS[role] || role || '—'; }
function roleClass(role) { return ROLE_CLASSES[role] || ''; }

const TRIGGER_LABELS = {
  paciente_comparece: 'Paciente comparece',
  orcamento_aceito: 'Orçamento aceito',
  profissional_realizou: 'Profissional realizou',
  pagamento_confirmado: 'Pagamento confirmado',
};
function triggerLabel(trigger) { return TRIGGER_LABELS[trigger] || trigger || '—'; }

const SCOPE_LABELS = {
  todos: 'Todos os eventos',
  por_procedimento: 'Por procedimento',
  por_especialidade: 'Por especialidade',
};
function scopeLabel(rule) {
  const base = SCOPE_LABELS[rule.scope] || rule.scope || '—';
  if (rule.scope === 'por_procedimento' && rule.procedure_name) return `${base}: ${rule.procedure_name}`;
  if (rule.scope === 'por_especialidade' && rule.specialty) return `${base}: ${rule.specialty}`;
  return base;
}

const PAY_WHEN_LABELS = {
  fechamento_mes: 'No Fechamento do Mês',
  imediato: 'Imediato',
  no_recebimento: 'No Recebimento',
};
function payWhenLabel(p) { return PAY_WHEN_LABELS[p] || p || '—'; }

function ruleTypeLabel(r) {
  if (r.kind === 'valor_fixo') return 'Fixo (R$)';
  return 'Percentual';
}

function ruleValueLabel(r) {
  if (r.kind === 'valor_fixo') return centsToBRL(r.fixed_amount_cents || 0);
  return fmtPercent(r.percent_basis_points);
}

// ── Ações ─────────────────────────────────────────────────────────────
function openModalForNew() {
  formMode.value = 'create';
  formInitial.value = null;
  showFormModal.value = true;
}

function openModalForEdit(rule) {
  formMode.value = 'edit';
  formInitial.value = rule;
  showFormModal.value = true;
}

function onRuleSaved() {
  showFormModal.value = false;
  load();
}

function startInactivate(rule) {
  ruleToDelete.value = rule;
  showDeleteModal.value = true;
}

async function confirmInactivate() {
  const rule = ruleToDelete.value;
  if (!rule) return;
  deleting.value = true;
  try {
    await FinancialV2.commissionRules.destroy(rule.id);
    notifySuccess('Regra inativada.');
    showDeleteModal.value = false;
    ruleToDelete.value = null;
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ')
      || err?.response?.data?.message
      || 'Erro ao inativar');
  } finally {
    deleting.value = false;
  }
}

// Ordenação: ativas primeiro, depois por nome
const sortedRules = computed(() => {
  return [...rules.value].sort((a, b) => {
    if (a.active !== b.active) return a.active ? -1 : 1;
    return (a.name || '').localeCompare(b.name || '');
  });
});
</script>

<template>
  <div class="comm-tab">
    <header class="comm-tab__header">
      <div>
        <h2 class="comm-tab__title">Regras de Comissão</h2>
        <p class="comm-tab__subtitle">Setup #5 · DR / SDR / Comercial</p>
      </div>
      <BeclinicButton
        variant="solid"
        color="blue"
        icon="i-lucide-plus"
        label="Nova Regra"
        class="finv2-btn-icon-only-mobile"
        @click="openModalForNew"
      />
    </header>

    <!-- Loading -->
    <div v-if="loading && rules.length === 0" class="comm-tab__state">
      <div class="comm-tab__spinner" />
      <span>Carregando regras...</span>
    </div>

    <!-- Error -->
    <div v-else-if="errorState" class="comm-tab__state comm-tab__state--error">
      <i class="i-lucide-alert-circle" />
      <div>
        <strong>Não foi possível carregar.</strong>
        <p>{{ errorState }}</p>
      </div>
      <BeclinicButton variant="ghost" color="slate" label="Tentar de novo" @click="load" />
    </div>

    <!-- Empty -->
    <div v-else-if="rules.length === 0" class="comm-tab__state comm-tab__state--empty">
      <i class="i-lucide-percent" />
      <h3>Nenhuma regra cadastrada</h3>
      <p>
        Comece criando uma regra com o botão acima. Sem regras, a tela
        <strong>v2 · Comissões</strong> fica vazia mesmo após receber pagamentos.
      </p>
      <BeclinicButton variant="solid" color="blue" icon="i-lucide-plus" label="Adicionar primeira" @click="openModalForNew" />
    </div>

    <!-- Tabela -->
    <div v-else class="comm-tab__table-wrap">
      <table class="comm-tab__table">
        <thead>
          <tr>
            <th class="comm-tab__th-name">REGRA</th>
            <th class="comm-tab__th-prof">PROFISSIONAL</th>
            <th class="comm-tab__th-role">PAPEL</th>
            <th class="comm-tab__th-trigger">GATILHO</th>
            <th class="comm-tab__th-type">TIPO</th>
            <th class="comm-tab__th-value">VALOR</th>
            <th class="comm-tab__th-scope">ESCOPO</th>
            <th class="comm-tab__th-pay">PGTO</th>
            <th class="comm-tab__th-status">STATUS</th>
            <th class="comm-tab__th-actions"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in sortedRules" :key="r.id" :class="{ 'comm-tab__row--inactive': !r.active }">
            <td class="comm-tab__td-name">{{ r.name || '—' }}</td>
            <td class="comm-tab__td-prof">
              <Avatar
                :src="r.professional?.avatar_url || ''"
                :name="r.professional?.name || ''"
                :size="22"
                rounded-full
              />
              <span>{{ r.professional?.name || `Usuário #${r.professional_id}` }}</span>
            </td>
            <td class="comm-tab__td-role">
              <span class="comm-tab__role-badge" :class="roleClass(r.role)">{{ roleLabel(r.role) }}</span>
            </td>
            <td class="comm-tab__td-trigger">{{ triggerLabel(r.trigger_event) }}</td>
            <td class="comm-tab__td-type">{{ ruleTypeLabel(r) }}</td>
            <td class="comm-tab__td-value">{{ ruleValueLabel(r) }}</td>
            <td class="comm-tab__td-scope">{{ scopeLabel(r) }}</td>
            <td class="comm-tab__td-pay">{{ payWhenLabel(r.pay_when) }}</td>
            <td class="comm-tab__td-status">
              <span class="comm-tab__status" :class="r.active ? 'comm-tab__status--ok' : 'comm-tab__status--inactive'">
                {{ r.active ? 'ATIVO' : 'INATIVO' }}
              </span>
            </td>
            <td class="comm-tab__td-actions">
              <BeclinicButton size="sm" variant="ghost" color="slate" label="Editar" @click="openModalForEdit(r)" />
              <BeclinicButton v-if="r.active" size="sm" variant="ghost" color="slate" label="Inativar" @click="startInactivate(r)" />
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <CommissionRuleFormModalV2
      v-if="showFormModal"
      :show="showFormModal"
      :mode="formMode"
      :initial="formInitial"
      @close="showFormModal = false"
      @confirm="onRuleSaved"
    />

    <ConfirmDangerModalV2
      v-if="showDeleteModal"
      :show="showDeleteModal"
      title="Inativar regra?"
      confirm-label="Sim, inativar"
      tone="warn"
      :loading="deleting"
      @close="showDeleteModal = false; ruleToDelete = null"
      @confirm="confirmInactivate"
    >
      A regra <strong>{{ ruleToDelete?.name }}</strong> será inativada.
      <br>
      Comissões já geradas (histórico) <strong>permanecem intactas</strong>. Apenas
      novos eventos disparados pela regra param de gerar comissão.
    </ConfirmDangerModalV2>
  </div>
</template>

<style scoped lang="scss">
.comm-tab { color: rgb(var(--slate-12)); }

.comm-tab__header {
  display: flex; justify-content: space-between; align-items: flex-start;
  gap: 16px; margin-bottom: 20px;
  padding-bottom: 16px; border-bottom: 1px solid rgb(var(--slate-4));
}
.comm-tab__title { margin: 0 0 4px; font-size: 22px; font-weight: 700; }
.comm-tab__subtitle { margin: 0; font-size: 13px; color: rgb(var(--slate-10)); }

/* ── States ──────────────────────────────────────────────── */
.comm-tab__state {
  display: flex; align-items: center; justify-content: center;
  padding: 60px 24px; text-align: center;
  color: rgb(var(--slate-9));
  font-size: 14px; gap: 12px;
}
.comm-tab__state--empty, .comm-tab__state--error {
  flex-direction: column;
  i { width: 32px; height: 32px; color: rgb(var(--slate-7)); }
  h3 { margin: 0; font-size: 16px; color: rgb(var(--slate-11)); }
  p { margin: 4px 0 0; max-width: 480px; font-size: 13px; }
}
.comm-tab__state--error { color: rgb(var(--ruby-10)); }

.comm-tab__spinner {
  width: 18px; height: 18px;
  border: 2px solid rgb(var(--slate-5));
  border-top-color: rgb(var(--blue-9));
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

/* ── Table ───────────────────────────────────────────────── */
.comm-tab__table-wrap {
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  overflow: hidden;
  background: rgb(var(--slate-1));
  overflow-x: auto;
}

.comm-tab__table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
  min-width: 1100px;

  thead {
    background: rgb(var(--slate-2));
    th {
      padding: 10px 12px;
      text-align: left;
      font-size: 10px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: rgb(var(--slate-10));
      border-bottom: 1px solid rgb(var(--slate-4));
      white-space: nowrap;
    }
  }

  tbody {
    tr {
      border-bottom: 1px solid rgb(var(--slate-3));
      transition: background-color .12s ease;
      &:last-child { border-bottom: 0; }
      &:hover { background: rgba(255, 255, 255, 0.02); }
      &.comm-tab__row--inactive { opacity: 0.55; }
    }
    td { padding: 12px; vertical-align: middle; }
  }
}

.comm-tab__th-name, .comm-tab__td-name { min-width: 200px; font-weight: 600; color: rgb(var(--slate-12)); }
.comm-tab__th-prof, .comm-tab__td-prof { min-width: 180px; }
.comm-tab__th-role, .comm-tab__td-role { width: 90px; }
.comm-tab__th-trigger, .comm-tab__td-trigger { min-width: 160px; color: rgb(var(--slate-10)); font-size: 12px; }
.comm-tab__th-type, .comm-tab__td-type { width: 100px; color: rgb(var(--slate-10)); }
.comm-tab__th-value, .comm-tab__td-value {
  width: 90px; text-align: right;
  font-weight: 700; font-variant-numeric: tabular-nums;
  color: rgb(var(--slate-12));
}
.comm-tab__th-scope, .comm-tab__td-scope { min-width: 140px; color: rgb(var(--slate-10)); font-size: 12px; }
.comm-tab__th-pay, .comm-tab__td-pay { min-width: 160px; color: rgb(var(--slate-10)); font-size: 12px; }
.comm-tab__th-status, .comm-tab__td-status { width: 90px; white-space: nowrap; }
.comm-tab__th-actions, .comm-tab__td-actions { width: 1%; white-space: nowrap; text-align: right; }

.comm-tab__td-prof {
  display: flex; align-items: center; gap: 10px;
  span { color: rgb(var(--slate-12)); font-weight: 500; }
}

.comm-tab__role-badge {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 5px;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.05em;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-11));

  &.role--dr        { background: rgba(59, 130, 246, 0.12);  color: rgb(var(--blue-11)); }
  &.role--sdr       { background: rgba(139, 92, 246, 0.12);  color: rgb(var(--violet-11)); }
  &.role--comercial { background: rgba(236, 72, 153, 0.12);  color: rgb(var(--pink-11)); }
}

.comm-tab__status {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 4px;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.05em;

  &--ok       { background: rgba(16, 185, 129, 0.15); color: rgb(var(--emerald-11)); }
  &--inactive { background: rgba(100, 116, 139, 0.15); color: rgb(var(--slate-10)); }
}
</style>
