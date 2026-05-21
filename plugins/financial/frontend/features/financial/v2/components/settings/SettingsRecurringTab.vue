<script setup>
/**
 * Aba Despesas Recorrentes — listagem (canon §4.4).
 * Cron diário gera as despesas dos próximos 35 dias (idempotente).
 * Editar valor afeta APENAS competências futuras.
 */
import { ref, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import FinancialV2 from '../../api/financialV2';
import { centsToBRL } from '../../composables/useMoney';
import '@plugins/financial/frontend/styles/financial.scss';

const list = ref([]);
const loading = ref(false);

const notifyError = msg => useNotification.error(msg);

const FREQ_LABEL = {
  monthly:    'Mensal',
  bimonthly:  'Bimestral',
  quarterly:  'Trimestral',
  semiannual: 'Semestral',
  annual:     'Anual',
};

const FREQ_BADGE = {
  monthly:    { color: 'blue',    label: 'Mensal' },
  bimonthly:  { color: 'cyan',    label: 'Bimestral' },
  quarterly:  { color: 'violet',  label: 'Trimestral' },
  semiannual: { color: 'amber',   label: 'Semestral' },
  annual:     { color: 'emerald', label: 'Anual' },
};

function freqBadge(freq) {
  return FREQ_BADGE[freq] || { color: 'slate', label: FREQ_LABEL[freq] || freq };
}

function formatDateBR(iso) {
  if (!iso) return null;
  const [y, m, d] = String(iso).slice(0, 10).split('-');
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}

async function load() {
  loading.value = true;
  try {
    const { data } = await FinancialV2.recurringExpenses.index();
    list.value = data?.data || [];
  } catch (err) {
    notifyError(err?.response?.data?.message || 'Erro ao carregar recorrentes');
  } finally {
    loading.value = false;
  }
}

onMounted(load);
</script>

<template>
  <div class="set-rec">
    <header class="set-rec__header">
      <h2 class="set-rec__title">Despesas recorrentes</h2>
      <p class="set-rec__subtitle">
        Modelo de despesas que se repetem (aluguel, sistema, internet…).
        Um cron diário gera as próximas em <strong>A Pagar</strong> automaticamente.
        Editar valor afeta apenas competências futuras (canon §4.4).
      </p>
    </header>

    <div v-if="loading" class="finv2-state">
      <div class="finv2-spinner" />
      <span>Carregando recorrentes…</span>
    </div>

    <div v-else-if="list.length" class="finv2-table-wrap">
      <table class="finv2-table">
        <thead>
          <tr>
            <th>Nome</th>
            <th>Frequência</th>
            <th class="finv2-table__th-num">Dia</th>
            <th class="finv2-table__th-num">Valor</th>
            <th>Vigência</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in list" :key="r.id" :class="{ 'set-rec__row--inactive': !r.active }">
            <td><strong>{{ r.name }}</strong></td>
            <td>
              <Badge
                :label="freqBadge(r.frequency).label"
                :color="freqBadge(r.frequency).color"
                size="xs"
              />
            </td>
            <td class="finv2-table__td-num">{{ r.due_day }}</td>
            <td class="finv2-table__td-num finv2-table__td-num--strong">
              {{ centsToBRL(r.amount_cents) }}
              <small v-if="r.variable_amount" class="set-rec__variable">(variável)</small>
            </td>
            <td class="finv2-table__td-muted">
              {{ formatDateBR(r.start_date) || '—' }}
              {{ r.end_date ? `→ ${formatDateBR(r.end_date)}` : '→ indeterminada' }}
            </td>
            <td>
              <Badge
                :label="r.active ? 'Ativa' : 'Inativa'"
                :color="r.active ? 'emerald' : 'slate'"
                :icon="r.active ? 'i-lucide-check-circle-2' : 'i-lucide-circle-off'"
                size="xs"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div v-else class="finv2-state">
      <div class="finv2-state__icon-wrap"><i class="i-lucide-repeat w-7 h-7" /></div>
      <p class="finv2-state__title">Nenhuma despesa recorrente</p>
      <p class="finv2-state__hint">
        Cadastro completo via API por enquanto. UI dedicada em construção.
      </p>
    </div>
  </div>
</template>

<style scoped lang="scss">
.set-rec__header { margin-bottom: 18px; }
.set-rec__title { margin: 0 0 4px; font-size: 17px; font-weight: 600; color: rgb(var(--slate-12)); }
.set-rec__subtitle {
  margin: 0; color: rgb(var(--slate-9)); font-size: 13px; line-height: 1.5;
  strong { color: rgb(var(--slate-12)); font-weight: 600; }
}
.set-rec__row--inactive { opacity: 0.55; }
.set-rec__variable {
  margin-left: 4px;
  color: rgb(var(--slate-9));
  font-size: 11px;
  font-weight: 400;
}
</style>
