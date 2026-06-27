// Fontes e tamanhos disponíveis na toolbar do editor (estilo Google Docs).
//
// As famílias usam fontes web-safe + Inter (default do app). O valor vazio
// representa "padrão" (sem override inline — herda a fonte do documento).

export const FONT_FAMILIES = [
  { value: '', label: 'Inter (padrão)' },
  { value: 'Arial, sans-serif', label: 'Arial' },
  { value: 'Georgia, serif', label: 'Georgia' },
  { value: '"Times New Roman", serif', label: 'Times New Roman' },
  { value: '"Courier New", monospace', label: 'Courier New' },
  { value: 'Verdana, sans-serif', label: 'Verdana' },
  { value: '"Trebuchet MS", sans-serif', label: 'Trebuchet MS' },
];

// Espaçamento entre linhas (line-height). Valor vazio = padrão.
// Os valores devem casar com LineHeight.js options ['1','1.15','1.5','2'].
export const LINE_SPACINGS = [
  { value: '', label: 'Espaçamento' },
  { value: '1', label: '1,0' },
  { value: '1.15', label: '1,15' },
  { value: '1.5', label: '1,5' },
  { value: '2', label: '2,0' },
];

// Tamanhos em px. Valor vazio = padrão (herda do parágrafo/heading).
export const FONT_SIZES = [
  { value: '', label: 'Padrão' },
  { value: '8px', label: '8' },
  { value: '10px', label: '10' },
  { value: '11px', label: '11' },
  { value: '12px', label: '12' },
  { value: '14px', label: '14' },
  { value: '16px', label: '16' },
  { value: '18px', label: '18' },
  { value: '24px', label: '24' },
  { value: '30px', label: '30' },
  { value: '36px', label: '36' },
  { value: '48px', label: '48' },
];
