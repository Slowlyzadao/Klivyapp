<script setup>
/**
 * Metas vs Realizado — wireframe Hub Relatórios (2026-05-23).
 *
 * Lista Metas ativas (RevenueGoal) cobrindo o período com 3 tiers (Mínima/
 * Principal/Desafio) e valor realizado on-the-fly. Status visual:
 *   - cinza   : sem meta (target zerado)
 *   - vermelho: abaixo da mínima
 *   - amber   : entre mínima e principal
 *   - verde   : atingiu principal
 *   - emerald+badge "Desafio!": atingiu desafio
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
const data = ref({ summary: {}, items: [] });

const STATUS_VISUAL = {
  sem_meta:               { color: 'slate',   label: 'Sem meta' },
  abaixo_min:             { color: 'ruby',    label: 'Abaixo da mínima' },
  entre_min_e_principal:  { color: 'amber',   label: 'Entre mín e principal' },
  atingiu_principal:      { color: 'emerald', label: 'Atingiu principal' },
  atingiu_desafio:        { color: 'emerald', label: 'Atingiu desafio 🚀' },
};

async function load() {
  loading.value = true;
  try {
    const res = await FinancialV2.reports.goalsVsActual({
      from: props.from, to: props.to,
    });
    data.value = res.data || { summary: {}, items: [] };
  } catch (err) {
    notifyError(err?.response?.data?.error || 'Falha ao carregar metas vs realizado.');
  } finally {
    loading.value = false;
  }
}

watch(() => [props.from, props.to], load);
onMounted(load);

function formatDateBR(iso) {
  if (!iso) return '—';
  const [y, m, d] = String(iso).slice(0, 10).split('-');
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}

function formatValue(item, key) {
  if (item.metric === 'currency') {
    return centsToBRL(item.targets[`${key}_cents`] || 0);
  }
  return (item.targets[`${key}_qty`] || 0).toLocaleString('pt-BR');
}
function formatActual(item) {
  if (item.metric === 'currency') {
    return centsToBRL(item.actual.value_cents || 0);
  }
  return (item.actual.value_qty || 0).toLocaleString('pt-BR');
}

defineExpose({
  exportCsv: () => {
    const rows = [['Meta', 'Tipo', 'Período', 'Mínima', 'Principal', 'Desafio', 'Realizado', '% Principal', 'Status']];
    data.value.items.forEach(i => {
      rows.push([
        i.name, i.kind_label,
        `${formatDateBR(i.period.start_date)} → ${formatDateBR(i.period.end_date)}`,
        formatValue(i, 'min'), formatValue(i, 'principal'), formatValue(i, 'stretch'),
        formatActual(i),
        i.progress.percent_principal ?? '',
        STATUS_VISUAL[i.progress.status]?.label || i.progress.status,
      ]);
    });
    return rows;
  },
});
</script>

<template>
  <div class="rep-detail">
    <div class="finv2-kpis">
      <div class="finv2-kpi">
        <div class="finv2-kpi__icon finv2-kpi__icon--neutral"><i class="i-lucide-target w-4 h-4" /></div>
        <div class="finv2-kpi__content">
          <span class="finv2-kpi__label">Metas ativas</span>
          <strong class="finv2-kpi__value">{{ data.summary.goals_count || 0 }}</strong>
        </div>
      </div>
      <div class="finv2-kpi">
        <div class="finv2-kpi__icon finv2-kpi__icon--positive"><i class="i-lucide-check-circle-2 w-4 h-4" /></div>
        <div class="finv2-kpi__content">
          <span class="finv2-kpi__label">Atingiram principal</span>
          <strong class="finv2-kpi__value finv2-kpi__value--positive">{{ data.summary.achieved_principal_count || 0 }}</strong>
        </div>
      </div>
      <div class="finv2-kpi">
        <div class="finv2-kpi__icon finv2-kpi__icon--neutral"><i class="i-lucide-banknote w-4 h-4" /></div>
        <div class="finv2-kpi__content">
          <span class="finv2-kpi__label">Realizado total</span>
          <strong class="finv2-kpi__value">{{ centsToBRL(data.summary.total_actual_cents || 0) }}</strong>
        </div>
      </div>
      <div class="finv2-kpi">
        <div class="finv2-kpi__icon finv2-kpi__icon--neutral"><i class="i-lucide-flag w-4 h-4" /></div>
        <div class="finv2-kpi__content">
          <span class="finv2-kpi__label">Soma metas principal</span>
          <strong class="finv2-kpi__value">{{ centsToBRL(data.summary.total_target_principal_cents || 0) }}</strong>
        </div>
      </div>
    </div>

    <div v-if="!loading && data.items.length === 0" class="finv2-state">
      <div class="finv2-state__icon-wrap"><i class="i-lucide-target w-7 h-7" /></div>
      <p class="finv2-state__title">Nenhuma meta ativa cobrindo o período</p>
      <p class="finv2-state__hint">Cadastre uma meta em Configurações → Metas.</p>
    </div>
    <div v-else class="finv2-table-wrap">
      <table class="finv2-table">
        <thead>
          <tr>
            <th>Meta</th>
            <th>Período</th>
            <th class="finv2-table__th-num">Mínima</th>
            <th class="finv2-table__th-num">Principal</th>
            <th class="finv2-table__th-num">Desafio</th>
            <th class="finv2-table__th-num">Realizado</th>
            <th>% Principal</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="i in data.items" :key="i.id">
            <td>
              <div class="rep-goal__name-cell">
                <strong>{{ i.name }}</strong>
                <span class="rep-goal__sub">
                  {{ i.kind_label }}
                  <template v-if="i.category">· {{ i.category.name }}</template>
                  <template v-if="i.professional">· {{ i.professional.name }}</template>
                </span>
              </div>
            </td>
            <td class="finv2-table__td-date">
              {{ formatDateBR(i.period.start_date) }}<br>{{ formatDateBR(i.period.end_date) }}
            </td>
            <td class="finv2-table__td-num">{{ formatValue(i, 'min') }}</td>
            <td class="finv2-table__td-num finv2-table__td-num--strong">{{ formatValue(i, 'principal') }}</td>
            <td class="finv2-table__td-num">{{ formatValue(i, 'stretch') }}</td>
            <td class="finv2-table__td-num finv2-table__td-num--strong">{{ formatActual(i) }}</td>
            <td>
              <div class="rep-goal__progress">
                <div class="rep-goal__progress-track">
                  <div
                    class="rep-goal__progress-fill"
                    :style="{
                      width: `${Math.min(100, i.progress.percent_principal || 0)}%`,
                      background: STATUS_VISUAL[i.progress.status]?.color === 'emerald' ? '#10b981'
                        : STATUS_VISUAL[i.progress.status]?.color === 'amber' ? '#f59e0b'
                        : STATUS_VISUAL[i.progress.status]?.color === 'ruby' ? '#dc2626'
                        : '#94a3b8',
                    }"
                  />
                </div>
                <span class="rep-goal__percent">{{ i.progress.percent_principal != null ? `${i.progress.percent_principal.toFixed(1)}%` : '—' }}</span>
              </div>
            </td>
            <td>
              <Badge
                :label="STATUS_VISUAL[i.progress.status]?.label || i.progress.status"
                :color="STATUS_VISUAL[i.progress.status]?.color || 'slate'"
                size="xs"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<style scoped lang="scss">
.rep-goal__name-cell { display: flex; flex-direction: column; gap: 2px; }
.rep-goal__sub { font-size: 11px; color: rgb(var(--slate-9)); }

.rep-goal__progress {
  display: flex; align-items: center; gap: 8px;
  min-width: 160px;
}
.rep-goal__progress-track {
  flex: 1; height: 8px;
  background: rgb(var(--slate-3));
  border-radius: 4px;
  overflow: hidden;
}
.rep-goal__progress-fill {
  height: 100%; border-radius: 4px;
  transition: width 0.3s ease;
}
.rep-goal__percent {
  font-size: 11px; font-weight: 600;
  color: rgb(var(--slate-12));
  font-variant-numeric: tabular-nums;
  min-width: 50px; text-align: right;
}
</style>
