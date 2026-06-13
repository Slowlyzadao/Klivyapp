<script setup>
/**
 * Ticket Médio — migrado da tab antiga.
 *
 * KPIs: Receita líquida · Pacientes únicos · Ticket médio geral
 * Tabela: ranking de profissionais por ticket médio + barra comparativa
 */
import { ref, watch, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import ProfessionalChip from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/ProfessionalChip.vue';
import FinancialV2 from '../../api/financialV2';
import { centsToBRL } from '../../composables/useMoney';

const props = defineProps({
  from: { type: String, required: true },
  to:   { type: String, required: true },
});

const notifyError = msg => useNotification.error(msg);
const loading = ref(false);
const data = ref({ overall: {}, by_professional: [] });

async function load() {
  loading.value = true;
  try {
    const res = await FinancialV2.reports.ticketMedio({
      from: props.from, to: props.to,
    });
    data.value = res.data || { overall: {}, by_professional: [] };
  } catch (err) {
    notifyError(err?.response?.data?.error || 'Falha ao carregar ticket médio.');
  } finally {
    loading.value = false;
  }
}

watch(() => [props.from, props.to], load);
onMounted(load);

defineExpose({
  exportCsv: () => {
    const rows = [['Profissional', 'Receita', 'Pacientes únicos', 'Recibos', 'Ticket médio']];
    data.value.by_professional.forEach(p => {
      rows.push([
        p.name,
        (p.receita_cents / 100).toFixed(2).replace('.', ','),
        p.patients_count, p.receipts_count,
        (p.ticket_medio_cents / 100).toFixed(2).replace('.', ','),
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
        <div class="finv2-kpi__icon finv2-kpi__icon--positive"><i class="i-lucide-banknote w-4 h-4" /></div>
        <div class="finv2-kpi__content">
          <span class="finv2-kpi__label">Receita líquida</span>
          <strong class="finv2-kpi__value finv2-kpi__value--positive">{{ centsToBRL(data.overall.receita_cents || 0) }}</strong>
        </div>
      </div>
      <div class="finv2-kpi">
        <div class="finv2-kpi__icon finv2-kpi__icon--neutral"><i class="i-lucide-users w-4 h-4" /></div>
        <div class="finv2-kpi__content">
          <span class="finv2-kpi__label">Pacientes únicos</span>
          <strong class="finv2-kpi__value">{{ data.overall.patients_count || 0 }}</strong>
        </div>
      </div>
      <div class="finv2-kpi">
        <div class="finv2-kpi__icon finv2-kpi__icon--neutral"><i class="i-lucide-trending-up w-4 h-4" /></div>
        <div class="finv2-kpi__content">
          <span class="finv2-kpi__label">Ticket médio geral</span>
          <strong class="finv2-kpi__value">{{ centsToBRL(data.overall.ticket_medio_cents || 0) }}</strong>
        </div>
      </div>
    </div>

    <div v-if="!loading && data.by_professional.length === 0" class="finv2-state">
      <div class="finv2-state__icon-wrap"><i class="i-lucide-trending-up w-7 h-7" /></div>
      <p class="finv2-state__title">Sem pagamentos no período</p>
    </div>
    <div v-else class="finv2-table-wrap">
      <table class="finv2-table">
        <thead>
          <tr>
            <th>Profissional</th>
            <th class="finv2-table__th-num">Receita</th>
            <th class="finv2-table__th-num">Pacientes únicos</th>
            <th class="finv2-table__th-num">Recibos</th>
            <th class="finv2-table__th-num">Ticket médio</th>
            <th>Comparativo</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="p in data.by_professional" :key="p.id || 'none'">
            <td>
              <ProfessionalChip v-if="p.id" :name="p.name" :avatar-url="p.avatar_url || ''" size="sm" />
              <span v-else class="finv2-table__td-muted">{{ p.name }}</span>
            </td>
            <td class="finv2-table__td-num">{{ centsToBRL(p.receita_cents) }}</td>
            <td class="finv2-table__td-num">{{ p.patients_count }}</td>
            <td class="finv2-table__td-num">{{ p.receipts_count }}</td>
            <td class="finv2-table__td-num finv2-table__td-num--strong">{{ centsToBRL(p.ticket_medio_cents) }}</td>
            <td class="rep-detail__bar-cell">
              <div class="rep-detail__bar-track">
                <div
                  class="rep-detail__bar-fill"
                  :style="{
                    width: `${Math.min(100, (p.ticket_medio_cents /
                      Math.max(1, data.overall.ticket_medio_cents || 1)) * 50)}%`,
                    background: '#3b82f6',
                  }"
                />
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<style scoped lang="scss">
.rep-detail__bar-cell { width: 25%; min-width: 120px; }
.rep-detail__bar-track { width: 100%; height: 8px; border-radius: 4px; background: rgb(var(--slate-3)); overflow: hidden; }
.rep-detail__bar-fill { height: 100%; border-radius: 4px; transition: width 0.3s ease; }
</style>
