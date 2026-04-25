// Regressão linear simples pelo método dos mínimos quadrados
// Usado pelo Gráfico #10 (Ticket Médio com Tendência)

export function linearRegression(data) {
  const n = data.length;
  if (n < 2) return { slope: 0, points: data.slice() };

  const sumX = data.reduce((s, _, i) => s + i, 0);
  const sumY = data.reduce((s, v) => s + v, 0);
  const sumXY = data.reduce((s, v, i) => s + i * v, 0);
  const sumX2 = data.reduce((s, _, i) => s + i * i, 0);

  const slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
  const intercept = (sumY - slope * sumX) / n;

  return {
    slope,
    points: data.map((_, i) => +(slope * i + intercept).toFixed(2)),
  };
}

// Detecta se a tendência dos últimos N pontos é de queda
export function isTrendingDown(data, lastN = 3) {
  const slice = data.slice(-lastN);
  const { slope } = linearRegression(slice);
  return slope < 0;
}
