<script>
/**
 * PaymentMethodBadge — Badge canônico para formas de pagamento.
 *
 * Componente único reutilizável (criado 2026-05-24) — evita duplicar mapas
 * KIND_LABELS/KIND_CLASSES/KIND_ICONS em cada tela que mostra forma de
 * pagamento (Settings, Fluxo de Caixa, Recebíveis, Despesas, Relatórios, etc.).
 *
 * Variantes:
 *   - default (size=md): ícone + label colorido (uso em tabelas/listas)
 *   - size=sm: versão compacta (chips em rows densos)
 *   - size=lg: versão maior pra cards/destaques
 *
 * Props:
 *   - kind          : string OBRIGATÓRIO — chave canon (dinheiro|pix|debito|
 *                     credito|boleto|transferencia|convenio|parcelamento_proprio)
 *   - method        : Object | null — payment_method completo do backend.
 *                     Se passado, mostra também o nome customizado (subline)
 *                     E o chip "até Nx" quando suporta parcelas.
 *   - provider      : string — provider raw pra usar no cálculo de "nome custom"
 *                     (se method não vier). Quando method vem, usa method.provider.
 *   - size          : 'sm' | 'md' | 'lg' (default md)
 *   - hideIcon      : boolean — usado em contexts onde ícone polui (default false)
 *   - hideLabel     : boolean — só ícone (usado em mobile/avatar style)
 *   - showName      : boolean — força mostrar method.name como sub-linha
 *                     mesmo se for igual ao kind label (default false: heurística)
 *
 * Exportações nomeadas:
 *   - PAYMENT_KIND_LABELS  : mapa kind → label PT-BR
 *   - PAYMENT_KIND_ICONS   : mapa kind → classe lucide
 *   - PAYMENT_KIND_OPTIONS : array pronto pra usar em FormSelect
 *   - kindLabel(kind)      : helper standalone
 *   - displayPaymentMethod(method) : helper "qual nome mostrar pro usuário"
 */

// Single source of truth — labels, classes, ícones.
// Quando aparecer novo kind canon (futuro), adicionar SÓ aqui.
export const PAYMENT_KIND_LABELS = Object.freeze({
  dinheiro: 'Dinheiro',
  pix: 'PIX',
  debito: 'Cartão de Débito',
  credito: 'Cartão de Crédito',
  boleto: 'Boleto',
  transferencia: 'Transferência',
  convenio: 'Convênio',
  parcelamento_proprio: 'Parcelamento Próprio',
});

export const PAYMENT_KIND_SHORT_LABELS = Object.freeze({
  dinheiro: 'Dinheiro',
  pix: 'PIX',
  debito: 'Débito',
  credito: 'Crédito',
  boleto: 'Boleto',
  transferencia: 'Transf.',
  convenio: 'Convênio',
  parcelamento_proprio: 'Parc. Próprio',
});

export const PAYMENT_KIND_ICONS = Object.freeze({
  dinheiro: 'i-lucide-banknote',
  pix: 'i-lucide-qr-code',
  debito: 'i-lucide-credit-card',
  credito: 'i-lucide-credit-card',
  boleto: 'i-lucide-barcode',
  transferencia: 'i-lucide-arrow-left-right',
  convenio: 'i-lucide-shield-check',
  parcelamento_proprio: 'i-lucide-calendar-days',
});

// Classes BEM-style por kind. Estilos definidos no <style> abaixo.
const PAYMENT_KIND_CLASSES = Object.freeze({
  dinheiro: 'pmb--dinheiro',
  pix: 'pmb--pix',
  debito: 'pmb--debito',
  credito: 'pmb--credito',
  boleto: 'pmb--boleto',
  transferencia: 'pmb--transferencia',
  convenio: 'pmb--convenio',
  parcelamento_proprio: 'pmb--parcelamento',
});

export const PAYMENT_KIND_OPTIONS = Object.freeze(
  Object.entries(PAYMENT_KIND_LABELS).map(([value, label]) => ({ value, label })),
);

export function kindLabel(kind) {
  return PAYMENT_KIND_LABELS[kind] || kind || '—';
}

export function kindShortLabel(kind) {
  return PAYMENT_KIND_SHORT_LABELS[kind] || kindLabel(kind);
}

export function kindIcon(kind) {
  return PAYMENT_KIND_ICONS[kind] || 'i-lucide-wallet';
}

// Aliases conhecidos por kind — nomes alternativos que NÃO devem ser
// tratados como "custom" porque já são variações canônicas do mesmo método.
// Inclui os defaults do seed canon (payment_methods_canon.rb) e variações
// comuns do mercado. Comparação case-insensitive + trim.
const PAYMENT_KIND_ALIASES = Object.freeze({
  dinheiro: ['dinheiro', 'cash', 'em dinheiro'],
  pix: ['pix', 'pix instantâneo'],
  debito: ['débito', 'debito', 'cartão de débito', 'cartão débito', 'cartao de debito'],
  credito: ['crédito', 'credito', 'cartão de crédito', 'cartão crédito', 'cartao de credito'],
  boleto: ['boleto', 'boleto bancário'],
  transferencia: ['transferência', 'transferencia', 'transferência bancária', 'transferencia bancaria', 'transf.', 'ted', 'doc'],
  convenio: ['convênio', 'convenio'],
  parcelamento_proprio: ['parcelamento próprio', 'parcelamento proprio', 'parc. próprio', 'parc. proprio', 'parcelamento da clínica', 'parcelamento da clinica', 'parcelamento'],
});

// Heurística "qual nome mostrar pro usuário".
// Prioridade: nome custom (se ≠ kind label, short label, ou alias canon) > kind label.
// Não duplica provider (provider já vem em outro local da UI).
// Refactor 2026-05-24: cobre aliases do seed canon + variações de mercado.
// Sem isso, name="Parcelamento da Clínica" (seed) aparecia como sub-linha
// redundante abaixo do badge "Parc. Próprio".
export function displayPaymentMethod(method) {
  if (!method) return '—';
  const name = (method.name || '').trim();
  if (!name) return kindLabel(method.kind);
  const nameLower = name.toLowerCase();
  const aliases = PAYMENT_KIND_ALIASES[method.kind] || [];

  // Bate com um alias canon PURO ("PIX", "Parcelamento da Clínica") → não é
  // custom, exibe só o kind label oficial (evita "PIX" duplicado sob badge PIX).
  //
  // Fix 2026-05-27: removida a supressão de "{alias} {provedor}" (ex: "PIX Stone").
  // O nome auto-sugerido é sempre "{tipo} {provedor}", então essa regra fazia o
  // nome sugerido SEMPRE sumir (só nomes 100% custom apareciam) — confundia o
  // operador. Pior: o provedor não aparece em telas que não agrupam por provedor
  // (Fluxo de Caixa, Recebíveis), então esconder "PIX Stone" perdia info. Agora
  // "PIX Stone" aparece, consistente com o preview do form.
  for (const alias of aliases) {
    if (nameLower === alias) return kindLabel(method.kind);
  }
  // Fallback: bate com kindLabel/shortLabel explícito
  if (nameLower === kindLabel(method.kind).toLowerCase()) return kindLabel(method.kind);
  if (nameLower === kindShortLabel(method.kind).toLowerCase()) return kindLabel(method.kind);

  return name;
}
</script>

<script setup>
import { computed } from 'vue';

const props = defineProps({
  kind: { type: String, required: true },
  method: { type: Object, default: null },
  provider: { type: String, default: '' },
  size: { type: String, default: 'md', validator: v => ['sm', 'md', 'lg'].includes(v) },
  hideIcon: { type: Boolean, default: false },
  hideLabel: { type: Boolean, default: false },
  showName: { type: Boolean, default: false },
  // Esconde o chip "até Nx" — útil quando a info de parcela já está
  // visível em outro lugar (ex: lista de Recebíveis mostra "parcela 4/12"
  // próximo do badge, então "até 12x" vira ruído redundante).
  hideInstallments: { type: Boolean, default: false },
});

const label = computed(() => (props.size === 'sm' ? kindShortLabel(props.kind) : kindLabel(props.kind)));
const icon = computed(() => kindIcon(props.kind));
const kindClass = computed(() => PAYMENT_KIND_CLASSES[props.kind] || '');

// Nome custom só aparece quando faz sentido (não duplica TIPO/provider)
const customName = computed(() => {
  if (!props.method) return null;
  const display = displayPaymentMethod(props.method);
  // Só mostra como sub-linha se for diferente do label do kind
  return display !== kindLabel(props.method.kind) ? display : null;
});

const showCustomName = computed(() => props.showName || (props.method && customName.value));

// "até Nx" chip — só quando o method suporta parcelas e tem max_installments,
// E o caller não pediu pra esconder (ex: contexto onde já há "parcela N/M" visível).
const installmentsLabel = computed(() => {
  if (props.hideInstallments) return null;
  if (!props.method?.supports_installments) return null;
  const max = props.method.max_installments;
  if (!max || max < 2) return null;
  return `até ${max}x`;
});
</script>

<template>
  <div class="pmb-wrap" :class="[`pmb-wrap--${size}`]">
    <div class="pmb-line">
      <span class="pmb-badge" :class="[kindClass, `pmb-badge--${size}`]">
        <!-- PIX usa SVG oficial do Banco Central (cor brand reconhecível
             no Brasil). Demais kinds usam ícones Lucide. fill=currentColor
             pra herdar a cor do badge (kind class define o token). -->
        <svg
          v-if="kind === 'pix' && !hideIcon"
          class="pmb-icon pmb-icon--pix"
          viewBox="0 0 297 297"
          fill="currentColor"
          aria-hidden="true"
          role="presentation"
        >
          <path d="M231.433 227.02C219.791 227.02 208.84 222.487 200.607 214.257L156.096 169.745C152.971 166.612 147.524 166.621 144.4 169.745L99.7266 214.42C91.4932 222.649 80.5425 227.183 68.8998 227.183H60.1281L116.503 283.556C134.108 301.161 162.653 301.161 180.26 283.556L236.795 227.02H231.433Z" />
          <path d="M68.8992 69.5768C80.5419 69.5768 91.4927 74.1101 99.726 82.3395L144.399 127.021C147.617 130.239 152.87 130.251 156.095 127.017L200.606 82.5023C208.839 74.273 219.79 69.7397 231.433 69.7397H236.794L180.261 13.205C162.653 -4.40167 134.107 -4.40167 116.502 13.205L60.13 69.577L68.8992 69.5768Z" />
          <path d="M283.557 116.501L249.393 82.3373C248.641 82.6386 247.826 82.8266 246.966 82.8266H231.433C223.402 82.8266 215.541 86.084 209.866 91.7626L165.357 136.273C161.192 140.439 155.718 142.523 150.25 142.523C144.777 142.523 139.308 140.439 135.144 136.277L90.4662 91.6C84.7915 85.92 76.9302 82.664 68.8995 82.664H49.7996C48.9849 82.664 48.2236 82.472 47.5049 82.2013L13.205 116.501C-4.40167 134.108 -4.40167 162.652 13.205 180.259L47.5036 214.557C48.2236 214.287 48.9849 214.095 49.7996 214.095H68.8995C76.9302 214.095 84.7915 210.839 90.4662 205.16L135.14 160.487C143.214 152.419 157.29 152.416 165.357 160.49L209.866 204.997C215.541 210.676 223.402 213.933 231.433 213.933H246.966C247.826 213.933 248.641 214.121 249.393 214.422L283.557 180.258C301.162 162.652 301.162 134.108 283.557 116.501Z" />
        </svg>
        <i v-else-if="!hideIcon" :class="icon" class="pmb-icon" />
        <span v-if="!hideLabel" class="pmb-label">{{ label }}</span>
      </span>
      <!-- Nome custom INLINE (lado a lado com o badge) — antes ia pra 2ª linha
           porque era filho do .pmb-wrap (column). 2026-05-27. -->
      <span v-if="showCustomName" class="pmb-custom-name" :title="customName">
        {{ customName }}
      </span>
      <span v-if="installmentsLabel" class="pmb-installments-chip">
        {{ installmentsLabel }}
      </span>
    </div>
  </div>
</template>

<style scoped lang="scss">
.pmb-wrap {
  display: inline-flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.pmb-line {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}

.pmb-badge {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 3px 8px;
  border-radius: 6px;
  font-weight: 600;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-11));
  border: 1px solid transparent;
  line-height: 1.2;

  &--sm  { font-size: 10.5px; padding: 2px 6px; gap: 4px; }
  &--md  { font-size: 11px;   padding: 3px 8px; gap: 5px; }
  &--lg  { font-size: 13px;   padding: 5px 12px; gap: 6px; }
}

.pmb-icon {
  width: 12px; height: 12px;
  flex-shrink: 0;
}
.pmb-badge--sm .pmb-icon { width: 11px; height: 11px; }
.pmb-badge--lg .pmb-icon { width: 15px; height: 15px; }

/* Cores por kind — paleta canon Klivy.
 * Background com alpha baixo + cor sólida no texto/ícone (alta legibilidade). */
.pmb--dinheiro     { background: rgba(34, 197, 94, 0.10);  color: rgb(var(--green-11));   border-color: rgba(34, 197, 94, 0.22); }
.pmb--pix          { background: rgba(16, 185, 129, 0.10); color: rgb(var(--emerald-11)); border-color: rgba(16, 185, 129, 0.22); }
.pmb--debito       { background: rgba(59, 130, 246, 0.10); color: rgb(var(--blue-11));    border-color: rgba(59, 130, 246, 0.22); }
.pmb--credito      { background: rgba(139, 92, 246, 0.10); color: rgb(var(--violet-11));  border-color: rgba(139, 92, 246, 0.22); }
.pmb--boleto       { background: rgba(245, 158, 11, 0.10); color: rgb(var(--amber-11));   border-color: rgba(245, 158, 11, 0.22); }
.pmb--transferencia{ background: rgba(14, 165, 233, 0.10); color: rgb(var(--sky-11));     border-color: rgba(14, 165, 233, 0.22); }
.pmb--convenio     { background: rgba(168, 85, 247, 0.10); color: rgb(var(--purple-11));  border-color: rgba(168, 85, 247, 0.22); }
.pmb--parcelamento { background: rgba(236, 72, 153, 0.10); color: rgb(var(--pink-11));    border-color: rgba(236, 72, 153, 0.22); }

.pmb-installments-chip {
  display: inline-flex;
  align-items: center;
  padding: 1px 8px;
  border-radius: 999px;
  font-size: 10.5px;
  font-weight: 500;
  font-variant-numeric: tabular-nums;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-10));
  border: 1px solid rgb(var(--slate-4));
}

.pmb-custom-name {
  font-size: 11.5px;
  font-weight: 500;
  color: rgb(var(--slate-10));
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 240px;
}
</style>
