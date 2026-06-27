<script setup>
/**
 * PeriodSelectorV2 — seletor de período tipo "pill chips + navegador".
 *
 * Migrado/extraído do DashboardV2 pra virar reuso entre Hub Relatórios,
 * Dashboard, DRE e outras telas que filtram por período.
 *
 * API (`v-model:from` + `v-model:to`):
 *   <PeriodSelectorV2 v-model:from="filters.from" v-model:to="filters.to" />
 *
 * `from`/`to` são strings ISO `YYYY-MM-DD`. O componente gerencia
 * internamente o `type` (week|month|quarter|year|all) + `anchor` (Date) e
 * recalcula `from`/`to` sempre que o operador interage. Não persiste a
 * escolha — quem instancia decide se quer guardar `type` em localStorage.
 *
 * Visual:
 *   - 5 chips ("Semana / Mês / Trimestre / Ano / Todos") em pill group
 *   - Navegador "‹ 05/2026 ›" pra deslocar anchor (esconde no type=all)
 *
 * Decisões:
 *   - Default = 'month' com anchor=hoje (recupera o month corrente)
 *   - 'all' usa range 2010-01-01 → hoje (mesmo do dashboard canon)
 *   - 'week' começa no domingo (start.getDay()=0)
 */
import { ref, computed, watch, onMounted } from 'vue';

const props = defineProps({
  from: { type: String, default: '' },
  to:   { type: String, default: '' },
  // Se quiser começar diferente de 'month', passa via prop. Não-reactive
  // depois do mount — é só seed inicial.
  defaultType: { type: String, default: 'month' },
});

const emit = defineEmits(['update:from', 'update:to']);

const PERIOD_TYPES = [
  { value: 'week',    label: 'Semana' },
  { value: 'month',   label: 'Mês' },
  { value: 'quarter', label: 'Trimestre' },
  { value: 'year',    label: 'Ano' },
  { value: 'all',     label: 'Todos' },
];

const periodType = ref(props.defaultType);
const anchor = ref(new Date());

function buildPeriod(type, date) {
  const y = date.getFullYear();
  const m = date.getMonth();
  if (type === 'all') {
    return {
      from: '2010-01-01',
      to: new Date().toISOString().slice(0, 10),
      label: 'Todo o período',
    };
  }
  if (type === 'year') {
    return { from: `${y}-01-01`, to: `${y}-12-31`, label: String(y) };
  }
  if (type === 'quarter') {
    const q = Math.floor(m / 3);
    const first = `${y}-${String(q * 3 + 1).padStart(2, '0')}-01`;
    const last = new Date(y, (q + 1) * 3, 0).toISOString().slice(0, 10);
    return { from: first, to: last, label: `T${q + 1}/${y}` };
  }
  if (type === 'week') {
    // Domingo a sábado (locale BR padrão de calendar). Anchor pode estar
    // no meio da semana; ajustamos pra início pra evitar drift.
    const start = new Date(date);
    start.setDate(start.getDate() - start.getDay());
    const end = new Date(start);
    end.setDate(end.getDate() + 6);
    const fmt = d => `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}`;
    return {
      from: start.toISOString().slice(0, 10),
      to: end.toISOString().slice(0, 10),
      label: `${fmt(start)} – ${fmt(end)}/${end.getFullYear()}`,
    };
  }
  // month (default)
  const first = `${y}-${String(m + 1).padStart(2, '0')}-01`;
  const last = new Date(y, m + 1, 0).toISOString().slice(0, 10);
  return { from: first, to: last, label: `${String(m + 1).padStart(2, '0')}/${y}` };
}

const period = computed(() => buildPeriod(periodType.value, anchor.value));

function emitPeriod() {
  if (period.value.from !== props.from) emit('update:from', period.value.from);
  if (period.value.to   !== props.to)   emit('update:to',   period.value.to);
}

watch(period, emitPeriod);

function setType(type) {
  periodType.value = type;
}

function shift(direction) {
  const d = new Date(anchor.value);
  if (periodType.value === 'week')    d.setDate(d.getDate() + direction * 7);
  if (periodType.value === 'month')   d.setMonth(d.getMonth() + direction);
  if (periodType.value === 'quarter') d.setMonth(d.getMonth() + direction * 3);
  if (periodType.value === 'year')    d.setFullYear(d.getFullYear() + direction);
  anchor.value = d;
}

onMounted(emitPeriod);
</script>

<template>
  <div class="periodv2">
    <div class="periodv2__chips">
      <button
        v-for="t in PERIOD_TYPES"
        :key="t.value"
        type="button"
        class="periodv2__chip"
        :class="{ 'periodv2__chip--active': periodType === t.value }"
        @click="setType(t.value)"
      >
        {{ t.label }}
      </button>
    </div>
    <div v-if="periodType !== 'all'" class="periodv2__shift">
      <button
        type="button"
        class="periodv2__shift-btn"
        aria-label="Anterior"
        @click="shift(-1)"
      >
        <i class="i-lucide-chevron-left" />
      </button>
      <strong class="periodv2__shift-label">{{ period.label }}</strong>
      <button
        type="button"
        class="periodv2__shift-btn"
        aria-label="Próximo"
        @click="shift(1)"
      >
        <i class="i-lucide-chevron-right" />
      </button>
    </div>
  </div>
</template>

<style scoped lang="scss">
.periodv2 {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}

/* Chips (Semana/Mês/Trim/Ano/Todos) */
.periodv2__chips {
  display: inline-flex;
  background: rgb(var(--slate-3));
  border-radius: 8px;
  padding: 2px;
}
.periodv2__chip {
  padding: 6px 12px;
  background: transparent;
  border: 0;
  border-radius: 6px;
  font-size: 12px;
  font-weight: 500;
  color: rgb(var(--slate-10));
  cursor: pointer;
  transition: background 0.12s ease, color 0.12s ease;

  &:hover:not(&--active) {
    color: rgb(var(--slate-12));
  }
  &--active {
    background: rgb(var(--slate-1));
    color: rgb(var(--slate-12));
    box-shadow: 0 1px 2px rgba(0, 0, 0, 0.1);
  }
}

/* Navegador "‹ 05/2026 ›" */
.periodv2__shift {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 4px 8px;
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  font-size: 12px;
  color: rgb(var(--slate-11));
}
.periodv2__shift-btn {
  background: transparent;
  border: 0;
  padding: 0;
  width: 22px;
  height: 22px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 4px;
  color: rgb(var(--slate-10));
  cursor: pointer;
  i { width: 14px; height: 14px; display: block; }
  &:hover { background: rgb(var(--slate-3)); color: rgb(var(--slate-12)); }
}
.periodv2__shift-label {
  font-weight: 600;
  color: rgb(var(--slate-12));
  font-variant-numeric: tabular-nums;
}
</style>
