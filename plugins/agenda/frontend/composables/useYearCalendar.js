/**
 * useYearCalendar — agregação derivada de `byDay` para a Year View.
 *
 * Recebe:
 *   - byDay: Ref<{ 'YYYY-MM-DD': { count, scheduled, confirmed, ... } }>
 *   - year:  Ref<number>
 *   - hiddenStatuses: Ref<string[]>  // filtros laterais do agenda store
 *
 * Expõe (todos `computed` memoizados):
 *   - effectiveByDay   → byDay com `count` recomputado excluindo status ocultos
 *   - monthTotals      → array[12] com totais por mês
 *   - yearTotal        → soma de todos os meses
 *   - peakMonth        → { index, count } do mês com maior total
 *   - bucketByDay      → Map<dateKey, bucket 0..4> pré-calculado
 *   - colorBucket(dk)  → função O(1) que consulta `bucketByDay`
 *   - getDay(dk)       → stats do dia (passthrough p/ tooltip)
 *
 * Estratégia de escala (quantil real):
 *   Em vez de `count / max` (que distorce quando há outliers — um dia
 *   anômalo com 50 eventos coloca todos os outros no bucket-1), agrupamos
 *   por PERCENTIL do conjunto de dias com eventos:
 *     - 0 eventos             → bucket 0
 *     - 1 até P40             → bucket 1 (baixa densidade)
 *     - P40 até P70           → bucket 2 (média)
 *     - P70 até P90           → bucket 3 (alta)
 *     - P90+ (top 10%)        → bucket 4 (pico)
 *
 *   Distribuição equilibrada independente do volume da clínica e robusta
 *   a outliers — o pico representa sempre os ~10% dias mais cheios do ano.
 *
 * Toda matemática roda em pass único O(N) + sort O(N log N) onde N = dias
 * com eventos no ano (≤366). Recomputa só quando byDay/year/hiddenStatuses
 * mudam. `bucketByDay` é frozen Map<string, number>.
 */
import { computed } from 'vue';

const ALL_STATUSES = [
  'scheduled',
  'confirmed',
  'arrived',
  'in_progress',
  'completed',
  'cancelled',
  'no_show',
];

// Percentil empírico (método nearest-rank). Aceita array já ordenado e
// retorna o valor no percentil `p` (0..1). Para 100 itens, p=0.4 retorna
// o 40º maior. Eficiente e estável; sem interpolação porque os "counts"
// são inteiros e queremos thresholds inteiros.
function percentile(sortedAsc, p) {
  if (!sortedAsc.length) return 0;
  if (p <= 0) return sortedAsc[0];
  if (p >= 1) return sortedAsc[sortedAsc.length - 1];
  const idx = Math.ceil(p * sortedAsc.length) - 1;
  return sortedAsc[Math.max(0, Math.min(idx, sortedAsc.length - 1))];
}

export function useYearCalendar({ byDay, year, hiddenStatuses }) {
  const effectiveByDay = computed(() => {
    const source = byDay.value || {};
    const hidden = hiddenStatuses?.value || [];
    if (!hidden.length) return source;

    const visible = ALL_STATUSES.filter(s => !hidden.includes(s));
    const out = {};
    for (const key of Object.keys(source)) {
      const day = source[key];
      let visibleCount = 0;
      for (const s of visible) {
        visibleCount += day[s] || 0;
      }
      out[key] = { ...day, count: visibleCount };
    }
    return out;
  });

  const monthTotals = computed(() => {
    const totals = new Array(12).fill(0);
    const source = effectiveByDay.value;
    const yr = year.value;
    for (const key of Object.keys(source)) {
      if (!key.startsWith(`${yr}-`)) continue;
      const month = parseInt(key.slice(5, 7), 10) - 1;
      if (month < 0 || month > 11) continue;
      totals[month] += source[key].count || 0;
    }
    return totals;
  });

  const yearTotal = computed(() => {
    let sum = 0;
    for (const t of monthTotals.value) sum += t;
    return sum;
  });

  const peakMonth = computed(() => {
    const totals = monthTotals.value;
    let idx = 0;
    let max = totals[0];
    for (let i = 1; i < 12; i += 1) {
      if (totals[i] > max) {
        max = totals[i];
        idx = i;
      }
    }
    return { index: idx, count: max };
  });

  // ─── Quantile-based bucketing ─────────────────────────────────────
  //
  // Pré-calcula UMA vez a tabela `bucketByDay` (Map<dateKey, 0..4>).
  // Recomputa só quando effectiveByDay muda. Cada célula renderizada
  // então faz apenas `.get(dateKey)` (O(1)) — zero loop por célula no
  // render do template.
  const bucketByDay = computed(() => {
    const source = effectiveByDay.value;
    const result = new Map();

    // Coleta counts > 0 pra calcular percentis da DISTRIBUIÇÃO real.
    // Dias zero ficam fora do cálculo dos thresholds (senão eles
    // "puxam" P40 pra zero e tudo vira bucket-1).
    const nonZero = [];
    const keys = Object.keys(source);
    for (const k of keys) {
      const c = source[k]?.count || 0;
      if (c > 0) nonZero.push(c);
    }

    if (nonZero.length === 0) {
      for (const k of keys) result.set(k, 0);
      return result;
    }

    nonZero.sort((a, b) => a - b);
    const p40 = percentile(nonZero, 0.4);
    const p70 = percentile(nonZero, 0.7);
    const p90 = percentile(nonZero, 0.9);

    for (const k of keys) {
      const c = source[k]?.count || 0;
      let bucket;
      if (c === 0) bucket = 0;
      else if (c <= p40) bucket = 1;
      else if (c <= p70) bucket = 2;
      else if (c <= p90) bucket = 3;
      else bucket = 4;
      result.set(k, bucket);
    }

    return result;
  });

  const dayMax = computed(() => {
    let max = 0;
    const source = effectiveByDay.value;
    for (const key of Object.keys(source)) {
      const c = source[key].count || 0;
      if (c > max) max = c;
    }
    return max;
  });

  function colorBucket(dateKey) {
    return bucketByDay.value.get(dateKey) || 0;
  }

  function getDay(dateKey) {
    return effectiveByDay.value[dateKey] || null;
  }

  return {
    effectiveByDay,
    monthTotals,
    yearTotal,
    peakMonth,
    dayMax,
    bucketByDay,
    colorBucket,
    getDay,
  };
}
