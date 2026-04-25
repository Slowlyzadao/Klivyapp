export function useFormatCurrency() {
  const formatCurrency = (value, currency = 'BRL') => {
    const num = parseFloat(value) || 0;
    return new Intl.NumberFormat('pt-BR', {
      style: 'currency',
      currency,
      minimumFractionDigits: 2,
    }).format(num);
  };

  const formatShort = value => {
    const num = parseFloat(value) || 0;
    if (Math.abs(num) >= 1_000_000)
      return `R$ ${(num / 1_000_000).toFixed(1)}M`;
    if (Math.abs(num) >= 1_000) return `R$ ${(num / 1_000).toFixed(1)}K`;
    return formatCurrency(num);
  };

  return { formatCurrency, formatShort };
}
