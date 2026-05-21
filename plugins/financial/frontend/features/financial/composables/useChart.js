// composable compartilhado para todos os gráficos Chart.js
// fornece: tema (dark/light), cores de grid, tooltip padrão, formatadores

import { ref, onMounted, onBeforeUnmount } from 'vue';

export function useChart() {
  const isDark = ref(document.body.classList.contains('dark'));

  let observer = null;
  onMounted(() => {
    observer = new MutationObserver(() => {
      isDark.value = document.body.classList.contains('dark');
    });
    observer.observe(document.body, {
      attributes: true,
      attributeFilter: ['class'],
    });
  });
  onBeforeUnmount(() => observer?.disconnect());

  const gridColor = () => (isDark.value ? '#334155' : '#E2E8F0');
  const tickColor = () => (isDark.value ? '#94A3B8' : '#64748B');

  const defaultScales = () => ({
    x: {
      grid: { color: gridColor(), drawBorder: false },
      ticks: { color: tickColor(), font: { size: 11 } },
    },
    y: {
      grid: { color: gridColor(), drawBorder: false },
      ticks: { color: tickColor(), font: { size: 11 } },
    },
  });

  const defaultTooltip = {
    backgroundColor: '#1E293B',
    titleColor: '#F8FAFC',
    bodyColor: '#CBD5E1',
    borderColor: '#334155',
    borderWidth: 1,
    borderRadius: 8,
    padding: 10,
    callbacks: {},
  };

  const formatBRL = value =>
    new Intl.NumberFormat('pt-BR', {
      style: 'currency',
      currency: 'BRL',
    }).format(parseFloat(value) || 0);

  const formatPct = (value, decimals = 1) =>
    `${(parseFloat(value) || 0).toFixed(decimals)}%`;

  const formatShort = value => {
    const num = parseFloat(value) || 0;
    if (Math.abs(num) >= 1_000_000)
      return `R$ ${(num / 1_000_000).toFixed(1)}M`;
    if (Math.abs(num) >= 1_000) return `R$ ${(num / 1_000).toFixed(1)}k`;
    return formatBRL(num);
  };

  return {
    isDark,
    gridColor,
    tickColor,
    defaultScales,
    defaultTooltip,
    formatBRL,
    formatPct,
    formatShort,
  };
}
