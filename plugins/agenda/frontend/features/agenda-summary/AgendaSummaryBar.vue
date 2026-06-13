<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import agendaReportsAPI from '../../api/agendaReports';
import './agenda-summary.scss';

const props = defineProps({
  viewMode: { type: String, required: true },
  currentDate: { type: Date, required: true },
  currentWeekDays: { type: Array, default: () => [] },
});

const loading = ref(false);
const data = ref(null);

// ─── Helpers ────────────────────────────────────────────────────────────────
function toISO(year, month, day) {
  return `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

// ─── Range de datas conforme a view ─────────────────────────────────────────
const dateRange = computed(() => {
  const d = props.currentDate;
  if (props.viewMode === 'day') {
    const iso = toISO(d.getFullYear(), d.getMonth(), d.getDate());
    return { since: iso, until: iso };
  }
  if (props.viewMode === 'week') {
    const week = props.currentWeekDays;
    if (!week || week.length < 7) return null;
    const first = week[0];
    const last = week[6];
    return {
      since: toISO(first.year, first.month, first.day),
      until: toISO(last.year, last.month, last.day),
    };
  }
  const year = d.getFullYear();
  const month = d.getMonth();
  const lastDay = new Date(year, month + 1, 0).getDate();
  return { since: toISO(year, month, 1), until: toISO(year, month, lastDay) };
});

// ─── Label do período ────────────────────────────────────────────────────────
const MONTHS_PT = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];
const MONTHS_SHORT = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];
const DAYS_SHORT = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

const periodLabel = computed(() => {
  const d = props.currentDate;
  if (props.viewMode === 'day') {
    return `${DAYS_SHORT[d.getDay()]}, ${d.getDate()} de ${MONTHS_SHORT[d.getMonth()]}`;
  }
  if (props.viewMode === 'week') {
    const week = props.currentWeekDays;
    if (!week || !week.length) return '';
    const f = week[0];
    const l = week[6];
    return `${f.day}/${f.month + 1} – ${l.day}/${l.month + 1}/${l.year}`;
  }
  return `${MONTHS_PT[d.getMonth()]} ${d.getFullYear()}`;
});

// ─── Métricas ───────────────────────────────────────────────────────────────
// Auditoria 2026-05-15: alinhado com sidebar de status pra evitar confusão
// de labels (resumo dizia "Agendados" pra total, e "Pendentes" pra status
// scheduled — sidebar usa "Agendado" pra esse status). Mudanças:
//   - `total`         → "Total" (card cinza, neutro — não é status)
//   - `unconfirmed`   → "Agendados" (status scheduled — bate com sidebar)
//   - `attended`      → trocado por `completed` para "Atendidos" usar
//     exatamente o mesmo critério do filtro do sidebar (só status=completed
//     em vez de combo completed+in_progress+arrived).
const metrics = computed(() => {
  const cur = data.value?.current;
  if (!cur) return null;
  return {
    total: cur.total ?? 0,
    confirmados: cur.confirmed ?? 0,
    agendados: cur.unconfirmed ?? 0,        // status='scheduled'
    atendidos: cur.completed ?? 0,          // só status='completed'
    ocupacao: cur.occupancy_rate ?? 0,
    noShow: cur.no_show_rate ?? 0,
  };
});

// ─── Fetch ───────────────────────────────────────────────────────────────────
async function fetchData() {
  const range = dateRange.value;
  if (!range) return;
  loading.value = true;
  try {
    const res = await agendaReportsAPI.getSummary({
      since: range.since,
      until: range.until,
    });
    data.value = res.data;
  } catch {
    data.value = null;
  } finally {
    loading.value = false;
  }
}

// ─── Interação Mobile ────────────────────────────────────────────────────────
function centerCard(event) {
  event.currentTarget.scrollIntoView({
    behavior: 'smooth',
    inline: 'center',
    block: 'nearest'
  });
}

// Carrega na montagem (evita problema de timing com auth) e re-busca ao mudar view/data
onMounted(fetchData);

watch(dateRange, (newRange, oldRange) => {
  if (JSON.stringify(newRange) !== JSON.stringify(oldRange)) fetchData();
});

defineExpose({ refresh: fetchData });
</script>

<template>
  <div class="agsum-wrapper">
    <!-- Cards de métricas -->
    <div class="agsum-cards">
      <template v-if="loading">
        <div class="agsum-loading-state">
          <span class="agsum-spinner" />
          <span>Carregando...</span>
        </div>
      </template>

      <template v-else-if="metrics">
        <!-- Total — todos os eventos do período (não é o status `scheduled`) -->
        <div class="agsum-card" @click="centerCard($event)">
          <div class="agsum-card-icon agsum-icon--slate">
            <span class="i-ph-calendar-blank" />
          </div>
          <div class="agsum-card-body">
            <span class="agsum-card-value">{{ metrics.total }}</span>
            <span class="agsum-card-label">Total</span>
          </div>
        </div>

        <!-- Confirmados — alinhado com STATUS_CONFIGS.confirmed (amarelo) -->
        <div class="agsum-card" @click="centerCard($event)">
          <div class="agsum-card-icon agsum-icon--amber">
            <span class="i-ph-check-circle" />
          </div>
          <div class="agsum-card-body">
            <span class="agsum-card-value agsum-val--amber">{{
              metrics.confirmados
            }}</span>
            <span class="agsum-card-label">Confirmados</span>
          </div>
        </div>

        <!-- Agendados — status='scheduled' (antes "Pendentes"); cinza alinhado
             com STATUS_CONFIGS.scheduled -->
        <div class="agsum-card" @click="centerCard($event)">
          <div class="agsum-card-icon agsum-icon--slate">
            <span class="i-ph-clock" />
          </div>
          <div class="agsum-card-body">
            <span class="agsum-card-value agsum-val--slate">{{
              metrics.agendados
            }}</span>
            <span class="agsum-card-label">Agendados</span>
          </div>
        </div>

        <!-- Atendidos — só status='completed' (alinhado com sidebar) -->
        <div class="agsum-card" @click="centerCard($event)">
          <div class="agsum-card-icon agsum-icon--green">
            <span class="i-ph-user-check" />
          </div>
          <div class="agsum-card-body">
            <span class="agsum-card-value agsum-val--green">{{
              metrics.atendidos
            }}</span>
            <span class="agsum-card-label">Atendidos</span>
          </div>
        </div>

        <!-- Ocupação -->
        <div class="agsum-card" @click="centerCard($event)">
          <div class="agsum-card-icon agsum-icon--purple">
            <span class="i-ph-chart-pie-slice" />
          </div>
          <div class="agsum-card-body">
            <span class="agsum-card-value agsum-val--purple">{{ metrics.ocupacao }}%</span>
            <span class="agsum-card-label">Ocupação</span>
          </div>
        </div>

        <!-- Faltas -->
        <div class="agsum-card" @click="centerCard($event)">
          <div class="agsum-card-icon agsum-icon--red">
            <span class="i-ph-user-minus" />
          </div>
          <div class="agsum-card-body">
            <span class="agsum-card-value agsum-val--red">{{ metrics.noShow }}%</span>
            <span class="agsum-card-label">Faltas</span>
          </div>
        </div>
      </template>

      <template v-else>
        <div class="agsum-loading-state">
          <span class="i-ph-chart-bar" />
          <span>Sem dados</span>
        </div>
      </template>
    </div>
  </div>
</template>
