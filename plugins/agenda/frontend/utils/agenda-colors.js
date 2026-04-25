/**
 * Utilitários de cores para a Agenda.
 * Funções puras sem side-effects.
 */

/**
 * Gera cor única e viva por agente usando o ângulo do número áureo (137.508°).
 * Distribui as cores pelo espectro sem repetição para qualquer quantidade de agentes.
 */
export function agentIdToColor(id) {
  const n =
    typeof id === 'number'
      ? id
      : String(id)
          .split('')
          .reduce((acc, c) => acc * 31 + c.charCodeAt(0), 0);
  const hue = (n * 137.508) % 360;
  return `hsl(${Math.round(hue)}, 70%, 60%)`;
}

/**
 * Converte hsl(h, s%, l%) para { r, g, b } (0-255).
 */
export function hslToRgb(hslStr) {
  const m = hslStr.match(/hsl\((\d+),\s*(\d+)%,\s*(\d+)%\)/);
  if (!m) return { r: 59, g: 130, b: 246 };
  const h = parseInt(m[1], 10) / 360;
  const s = parseInt(m[2], 10) / 100;
  const l = parseInt(m[3], 10) / 100;
  let r;
  let g;
  let b;
  if (s === 0) {
    r = g = b = l;
  } else {
    const hue2rgb = (p, q, t) => {
      if (t < 0) t += 1;
      if (t > 1) t -= 1;
      if (t < 1 / 6) return p + (q - p) * 6 * t;
      if (t < 1 / 2) return q;
      if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
      return p;
    };
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    const p = 2 * l - q;
    r = hue2rgb(p, q, h + 1 / 3);
    g = hue2rgb(p, q, h);
    b = hue2rgb(p, q, h - 1 / 3);
  }
  return {
    r: Math.round(r * 255),
    g: Math.round(g * 255),
    b: Math.round(b * 255),
  };
}

export function solidEventBg(colorStr, isDark) {
  return colorStr || '#3b82f6';
}

/**
 * Retorna a cor de prioridade.
 */
export function getPriorityColor(val) {
  if (val === 'urgent') return '#ef4444';
  if (val === 'high') return '#f97316';
  if (val === 'low') return '#a8a29e';
  return '#3b82f6';
}

/**
 * Retorna o estilo de prioridade { color, borderColor }.
 */
export function getPriorityStyle(val) {
  if (val === 'urgent') return { color: '#ef4444', borderColor: '#ef4444' };
  if (val === 'high') return { color: '#f97316', borderColor: '#f97316' };
  if (val === 'low') return { color: '#a8a29e', borderColor: '#a8a29e' };
  return { color: '#3b82f6', borderColor: '#3b82f6' };
}
