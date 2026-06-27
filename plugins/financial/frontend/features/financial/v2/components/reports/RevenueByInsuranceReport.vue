<script setup>
/**
 * Receitas por Convênio — renomeio do antigo "Convênio".
 *
 * Mostra faturamento/recebido/em-aberto/gap por operadora de plano de saúde
 * ou particular. Modes (Todos/Convênio/Particular) filtram a base.
 */
import { ref, watch, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import FinancialV2 from '../../api/financialV2';
import { centsToBRL } from '../../composables/useMoney';

const props = defineProps({
  from: { type: String, required: true },
  to:   { type: String, required: true },
});

const notifyError = msg => useNotification.error(msg);
const loading = ref(false);
const data = ref({ summary: {}, operadoras: [] });
const mode = ref('all');

const MODES = [
  { key: 'all',        label: 'Todos',      tone: 'blue' },
  { key: 'convenio',   label: 'Convênio',   tone: 'cyan' },
  { key: 'particular', label: 'Particular', tone: 'slate' },
];

async function load() {
  loading.value = true;
  try {
    const res = await FinancialV2.reports.convenio({
      from: props.from, to: props.to, mode: mode.value,
    });
    data.value = res.data || { summary: {}, operadoras: [] };
  } catch (err) {
    notifyError(err?.response?.data?.error || 'Falha ao carregar receitas por convênio.');
  } finally {
    loading.value = false;
  }
}

watch(() => [props.from, props.to, mode.value], load);
onMounted(load);

defineExpose({
  exportCsv: () => {
    const rows = [['Operadora', 'Faturado', 'Recebido', 'Gap', 'Em aberto', 'Pacientes', 'Ticket médio']];
    data.value.operadoras.forEach(op => {
      rows.push([
        op.name,
        (op.faturado_cents / 100).toFixed(2).replace('.', ','),
        (op.recebido_cents / 100).toFixed(2).replace('.', ','),
        (op.gap_cents / 100).toFixed(2).replace('.', ','),
        (op.em_aberto_cents / 100).toFixed(2).replace('.', ','),
        op.patients_count,
        (op.ticket_medio_cents / 100).toFixed(2).replace('.', ','),
      ]);
    });
    return rows;
  },
});
</script>

<template>
  <div class="rep-detail">
    <div class="finv2-chips" role="tablist">
      <button
        v-for="m in MODES"
        :key="m.key"
        type="button"
        class="finv2-chip"
        :class="[`finv2-chip--tone-${m.tone}`, { 'finv2-chip--active': mode === m.key }]"
        @click="mode = m.key"
      >
        <span>{{ m.label }}</span>
      </button>
    </div>

    <div class="finv2-kpis">
      <div class="finv2-kpi">
        <div class="finv2-kpi__icon finv2-kpi__icon--neutral"><i class="i-lucide-receipt w-4 h-4" /></div>
        <div class="finv2-kpi__content">
          <span class="finv2-kpi__label">Faturado</span>
          <strong class="finv2-kpi__value">{{ centsToBRL(data.summary.faturado_cents || 0) }}</strong>
        </div>
      </div>
      <div class="finv2-kpi">
        <div class="finv2-kpi__icon finv2-kpi__icon--positive"><i class="i-lucide-banknote w-4 h-4" /></div>
        <div class="finv2-kpi__content">
          <span class="finv2-kpi__label">Recebido</span>
          <strong class="finv2-kpi__value finv2-kpi__value--positive">{{ centsToBRL(data.summary.recebido_cents || 0) }}</strong>
        </div>
      </div>
      <div class="finv2-kpi">
        <div class="finv2-kpi__icon finv2-kpi__icon--danger"><i class="i-lucide-alert-circle w-4 h-4" /></div>
        <div class="finv2-kpi__content">
          <span class="finv2-kpi__label">Em aberto</span>
          <strong class="finv2-kpi__value finv2-kpi__value--danger">{{ centsToBRL(data.summary.em_aberto_cents || 0) }}</strong>
        </div>
      </div>
      <div class="finv2-kpi">
        <div class="finv2-kpi__icon finv2-kpi__icon--neutral"><i class="i-lucide-trending-up w-4 h-4" /></div>
        <div class="finv2-kpi__content">
          <span class="finv2-kpi__label">Ticket médio</span>
          <strong class="finv2-kpi__value">{{ centsToBRL(data.summary.ticket_medio_cents || 0) }}</strong>
        </div>
      </div>
    </div>

    <div v-if="loading" class="finv2-state">
      <div class="finv2-spinner" /><span>Carregando…</span>
    </div>
    <div v-else-if="data.operadoras.length === 0" class="finv2-state">
      <div class="finv2-state__icon-wrap"><i class="i-lucide-shield w-7 h-7" /></div>
      <p class="finv2-state__title">Nenhuma operadora no período</p>
    </div>
    <div v-else class="finv2-table-wrap">
      <table class="finv2-table">
        <thead>
          <tr>
            <th>Operadora</th>
            <th class="finv2-table__th-num">Faturado</th>
            <th class="finv2-table__th-num">Recebido</th>
            <th class="finv2-table__th-num">Gap</th>
            <th class="finv2-table__th-num">Em aberto</th>
            <th class="finv2-table__th-num">Pacientes</th>
            <th class="finv2-table__th-num">Ticket médio</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="op in data.operadoras" :key="op.name">
            <td>
              <Badge
                :label="op.name"
                :color="op.name === 'Particular' ? 'slate' : 'cyan'"
                size="xs"
              />
            </td>
            <td class="finv2-table__td-num">{{ centsToBRL(op.faturado_cents) }}</td>
            <td class="finv2-table__td-num finv2-table__td-num--strong">{{ centsToBRL(op.recebido_cents) }}</td>
            <td class="finv2-table__td-num rep-detail__gap">
              {{ op.gap_cents > 0 ? centsToBRL(op.gap_cents) : '—' }}
            </td>
            <td class="finv2-table__td-num rep-detail__open">{{ centsToBRL(op.em_aberto_cents) }}</td>
            <td class="finv2-table__td-num">{{ op.patients_count }}</td>
            <td class="finv2-table__td-num">{{ centsToBRL(op.ticket_medio_cents) }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<style scoped lang="scss">
.rep-detail__gap { color: rgb(var(--amber-11)); font-weight: 600; }
.rep-detail__open { color: rgb(var(--ruby-11)); }
:root.dark .rep-detail__gap { color: #fcd34d; }
:root.dark .rep-detail__open { color: #fca5a5; }
</style>
