import { ref, computed } from 'vue';

export function useFinancialFilters() {
  const period = ref('month'); // 'today' | 'week' | 'month' | 'custom'
  const customStart = ref(null);
  const customEnd = ref(null);

  const today = new Date();

  const periods = [
    { key: 'today', labelKey: 'FINANCIAL.PERIOD.TODAY' },
    { key: 'week', labelKey: 'FINANCIAL.PERIOD.WEEK' },
    { key: 'month', labelKey: 'FINANCIAL.PERIOD.MONTH' },
  ];

  const dateRange = computed(() => {
    const fmt = d => d.toISOString().split('T')[0];

    if (period.value === 'today') {
      return { start_date: fmt(today), end_date: fmt(today) };
    }

    if (period.value === 'week') {
      const sun = new Date(today);
      sun.setDate(today.getDate() - today.getDay());
      const sat = new Date(sun);
      sat.setDate(sun.getDate() + 6);
      return { start_date: fmt(sun), end_date: fmt(sat) };
    }

    if (period.value === 'month') {
      const first = new Date(today.getFullYear(), today.getMonth(), 1);
      const last = new Date(today.getFullYear(), today.getMonth() + 1, 0);
      return { start_date: fmt(first), end_date: fmt(last) };
    }

    // custom
    return {
      start_date: customStart.value,
      end_date: customEnd.value,
    };
  });

  // alias for API params (period === 'custom' needs dates)
  const dateParams = computed(() =>
    period.value === 'custom' ? dateRange.value : {}
  );

  const periodLabel = computed(() => {
    const labels = {
      today: 'Hoje',
      week: 'Semana',
      month: 'Mês',
      custom: 'Período',
    };
    return labels[period.value] || 'Mês';
  });

  const setPeriod = p => {
    period.value = p;
  };

  return {
    period,
    periods,
    dateRange,
    dateParams,
    periodLabel,
    customStart,
    customEnd,
    setPeriod,
  };
}
