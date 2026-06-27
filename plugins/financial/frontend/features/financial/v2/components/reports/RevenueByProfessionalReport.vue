<script setup>
/**
 * Receitas por Profissional — wireframe Hub Relatórios (2026-05-23).
 *
 * Fonte: Entries de receita (`direction='in'`, `affects_dre=true`,
 * kind∈['receita','manual_entry']) agregadas por `professional_id` na
 * competência do período.
 *
 * Colunas: Profissional · Recebimentos · Pacientes únicos · Receita ·
 *          Ticket médio · % Total
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
const data = ref({ summary: {}, items: [] });

async function load() {
  loading.value = true;
  try {
    const res = await FinancialV2.reports.revenueByProfessionalTable({
      from: props.from, to: props.to,
    });
    data.value = res.data || { summary: {}, items: [] };
  } catch (err) {
    notifyError(err?.response?.data?.error || 'Falha ao carregar receitas por profissional.');
  } finally {
    loading.value = false;
  }
}

watch(() => [props.from, props.to], load);
onMounted(load);

defineExpose({
  exportCsv: () => {
    const rows = [['Profissional', 'Recebimentos', 'Pacientes únicos', 'Receita', 'Ticket médio', '% Total']];
    data.value.items.forEach(i => {
      rows.push([
        i.professional.name, i.qty, i.patients_count,
        (i.total_cents / 100).toFixed(2).replace('.', ','),
        i.ticket_avg_cents ? (i.ticket_avg_cents / 100).toFixed(2).replace('.', ',') : '',
        i.percent_of_total
      ]);
    });
    return rows;
  },
});
</script>

<template>
  <div class="rep-detail">
    <div class="rep-detail__summary">
      Total: <strong>{{ centsToBRL(data.summary.total_cents || 0) }}</strong>
      · {{ data.summary.professionals_count || 0 }} profissionais
    </div>

    <div v-if="loading" class="finv2-state">
      <div class="finv2-spinner" /><span>Carregando…</span>
    </div>
    <div v-else-if="data.items.length === 0" class="finv2-state">
      <div class="finv2-state__icon-wrap"><i class="i-lucide-users w-7 h-7" /></div>
      <p class="finv2-state__title">Nenhuma receita atribuída a profissional</p>
      <p class="finv2-state__hint">Verifique se os Entries têm `professional_id` preenchido.</p>
    </div>
    <div v-else class="finv2-table-wrap">
      <table class="finv2-table">
        <thead>
          <tr>
            <th>Profissional</th>
            <th class="finv2-table__th-num">Recebimentos</th>
            <th class="finv2-table__th-num">Pacientes únicos</th>
            <th class="finv2-table__th-num">Receita</th>
            <th class="finv2-table__th-num">Ticket médio</th>
            <th class="finv2-table__th-num">% Total</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="i in data.items" :key="i.professional.id || 'none'">
            <td>
              <ProfessionalChip
                v-if="i.professional.id"
                :name="i.professional.name"
                :avatar-url="i.professional.avatar_url || ''"
                size="sm"
              />
              <span v-else class="finv2-table__td-muted">{{ i.professional.name }}</span>
            </td>
            <td class="finv2-table__td-num">{{ i.qty }}</td>
            <td class="finv2-table__td-num">{{ i.patients_count }}</td>
            <td class="finv2-table__td-num finv2-table__td-num--strong">{{ centsToBRL(i.total_cents) }}</td>
            <td class="finv2-table__td-num">
              {{ i.ticket_avg_cents != null ? centsToBRL(i.ticket_avg_cents) : '—' }}
            </td>
            <td class="finv2-table__td-num">{{ i.percent_of_total.toFixed(1) }}%</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<style scoped lang="scss">
.rep-detail__summary {
  padding: 10px 14px; margin-bottom: 12px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  font-size: 13px; color: rgb(var(--slate-11));
  strong { color: #047857; font-variant-numeric: tabular-nums; }
}
:root.dark .rep-detail__summary strong { color: #6ee7b7; }
</style>
