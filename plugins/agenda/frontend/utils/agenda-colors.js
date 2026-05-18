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
 * Parses any color string (hsl, hex, rgb) into { r, g, b } 0-255.
 * Returns blue fallback if unparseable.
 */
export function parseColorToRgb(colorStr) {
  if (!colorStr) return { r: 59, g: 130, b: 246 };
  if (colorStr.startsWith('hsl')) return hslToRgb(colorStr);
  if (colorStr.startsWith('#')) {
    let hex = colorStr.slice(1);
    if (hex.length === 3) hex = hex.split('').map(c => c + c).join('');
    return {
      r: parseInt(hex.slice(0, 2), 16),
      g: parseInt(hex.slice(2, 4), 16),
      b: parseInt(hex.slice(4, 6), 16),
    };
  }
  const m = colorStr.match(/rgba?\((\d+)\D+(\d+)\D+(\d+)/);
  if (m) return { r: +m[1], g: +m[2], b: +m[3] };
  return { r: 59, g: 130, b: 246 };
}

/**
 * Returns the WCAG-compliant text color (#fff or dark slate) given a
 * background. Uses relative luminance — threshold 0.5 for visual balance,
 * giving us at least 4.5:1 contrast against typical event backgrounds.
 */
export function getContrastColor(bgColor) {
  const { r, g, b } = parseColorToRgb(bgColor);
  const toLin = c => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
  };
  const L = 0.2126 * toLin(r) + 0.7152 * toLin(g) + 0.0722 * toLin(b);
  return L > 0.5 ? '#1f2937' : '#ffffff';
}

/**
 * Returns a translucent rgba version of the input color at the given alpha.
 * Always rgba (independente do formato de entrada) — útil para layers que
 * precisam ser sobrepostas sem ocultar o que está atrás (ex.: lane atrás
 * dos eventos não pode cobrir o hatch de slots bloqueados).
 */
export function translucentBgFromColor(colorStr, alpha = 0.10) {
  const { r, g, b } = parseColorToRgb(colorStr);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

/**
 * Versão opaca (sem alpha) do pastel — necessária para o body do card de
 * evento, que fica em cima das linhas do grid: alpha deixa as linhas
 * vazarem e prejudica leitura.
 *
 * Light mode: mistura com branco (12% cor / 88% branco) → quase branco
 *   com hue da cor.
 * Dark mode: mistura com slate-900 (rgb(15,23,42)) na mesma proporção
 *   → quase preto com hue da cor. Mantém saturação visível sem clarear
 *   demais o card num fundo escuro.
 */
export function opaquePastelFromColor(colorStr, isDark = false) {
  if (!colorStr) return isDark ? 'rgb(30, 41, 59)' : '#eef2ff';
  const { r, g, b } = parseColorToRgb(colorStr);
  if (isDark) {
    const baseR = 15;
    const baseG = 23;
    const baseB = 42;
    const mix = (c, base) => Math.round(c * 0.18 + base * 0.82);
    return `rgb(${mix(r, baseR)}, ${mix(g, baseG)}, ${mix(b, baseB)})`;
  }
  const mix = c => Math.round(c * 0.12 + 255 * 0.88);
  return `rgb(${mix(r)}, ${mix(g)}, ${mix(b)})`;
}

/**
 * Returns a soft pastel tint of the color for use as background.
 *
 * Light mode (HSL): L=95% (quase branco com hue).
 * Dark mode (HSL): L=20% (quase preto com hue).
 * Não-HSL: alpha 0.12 (light) ou 0.22 (dark) — em fundo escuro precisa de
 *   mais alpha pra cor não desaparecer.
 */
export function pastelBgFromColor(colorStr, isDark = false) {
  if (!colorStr) {
    return isDark ? 'rgba(59, 130, 246, 0.22)' : 'rgba(59, 130, 246, 0.10)';
  }
  if (colorStr.startsWith('hsl')) {
    const m = colorStr.match(/hsl\((\d+),\s*(\d+)%,\s*\d+%\)/);
    if (m) return `hsl(${m[1]}, ${m[2]}%, ${isDark ? '20' : '95'}%)`;
  }
  const { r, g, b } = parseColorToRgb(colorStr);
  return `rgba(${r}, ${g}, ${b}, ${isDark ? 0.22 : 0.12})`;
}

/**
 * Cor de texto legível sobre o pastel da mesma matiz.
 *
 * Light mode: versão escurecida saturada (HSL L=28% / RGB ×0.42) — texto
 *   dark sobre fundo light com contraste WCAG.
 * Dark mode: versão clareada (HSL L=85% / RGB ×0.4 + branco ×0.6) — texto
 *   light sobre fundo dark, mantendo a hue pra harmonizar com o card.
 *
 * Nome `darkened*` é histórico (era only-light); hoje produz "tinted text"
 * adaptativo. Mantido pra não quebrar imports existentes.
 */
export function darkenedTextColor(colorStr, isDark = false) {
  if (!colorStr) return isDark ? '#cbd5e1' : '#1e40af';
  if (colorStr.startsWith('hsl')) {
    const m = colorStr.match(/hsl\((\d+),\s*(\d+)%,\s*\d+%\)/);
    if (m) {
      const sat = Math.max(55, parseInt(m[2], 10));
      return `hsl(${m[1]}, ${sat}%, ${isDark ? '85' : '28'}%)`;
    }
  }
  const { r, g, b } = parseColorToRgb(colorStr);
  if (isDark) {
    const lighten = c => Math.round(c * 0.4 + 255 * 0.6);
    return `rgb(${lighten(r)}, ${lighten(g)}, ${lighten(b)})`;
  }
  return `rgb(${Math.round(r * 0.42)}, ${Math.round(g * 0.42)}, ${Math.round(b * 0.42)})`;
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
