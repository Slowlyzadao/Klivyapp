<!--
  InstallmentProgress — indicador moderno de progresso de parcelas.

  Substitui as "bolinhas" antigas (que escalam mal com >12 parcelas) e o
  texto "1/3" do FinancialTransactionsTable. PR 2 do refactor 2026-05-06.

  Variantes:
    • compact    (default) — barra segmentada + contador "X/Y pagas"
    • expanded             — compact + chips por parcela (tooltip detalhado)
    • summary              — pílula "Pago: 8 · Aberto: 1 · Vencido: 1"

  Cores semânticas vêm de `constants/financial.js` (emerald/amber/red) — são
  os mesmos tokens dos badges de status; escala consistente com o resto da UI.

  Acessibilidade:
    • `aria-label` é gerado pela função `progressAriaLabel` para leitores
      de tela ("3 de 5 parcelas pagas, 1 vencida").
    • Tooltip moderno (Tooltip do beclinic_core) em cada chip/sumário —
      regra do projeto (AGENTS.md: nunca usar `title=` nativo).
-->

<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import { formatCurrency } from '@plugins/patients/frontend/features/patient-record/utils/financialFormatters';

const props = defineProps({
  // Métricas agregadas — vindas de `entry.progress` do backend v2
  // (patient_timelines_controller).
  paid: { type: Number, default: 0 },
  open: { type: Number, default: 0 },
  overdue: { type: Number, default: 0 },
  // Parcelas canceladas — separadas de `open` em 2026-05-12 pra deixar
  // claro que não impactam o valor a receber (ex: importação Clinicorp
  // trouxe muitas com Canceled='X' por desistência/renegociação).
  canceled: { type: Number, default: 0 },
  total: { type: Number, default: 0 },
  // Valores em centavos — quando disponíveis, a barra usa proporção de
  // VALOR (paid_amount / total_amount) em vez de contagem (paid/total).
  // Reflete baixa parcial: R$ 200 de R$ 285 numa parcela só → 70% em vez
  // de 0%. Fallback pra contagem quando esses campos não vêm do backend.
  paidAmountCents: { type: Number, default: 0 },
  totalAmountCents: { type: Number, default: 0 },

  // Lista de parcelas (`entry.installments` do builder) — opcional.
  // Necessária só na variante `expanded` para renderizar chips por parcela.
  installments: { type: Array, default: () => [] },

  variant: {
    type: String,
    default: 'compact',
    validator: v => ['compact', 'expanded', 'summary'].includes(v),
  },
});

const { t } = useI18n();

const safeTotal = computed(() => Math.max(props.total || 0, 1));

// Percentual da barra preferencialmente por VALOR (centavos) — assim baixa
// parcial é refletida (R$ 200 de R$ 285 → 70%). Fallback pra contagem
// quando os valores não vêm do backend (compatibilidade).
const hasAmountValues = computed(() => (props.totalAmountCents || 0) > 0);
const paidPct = computed(() => {
  if (hasAmountValues.value) {
    return Math.round(((props.paidAmountCents || 0) / props.totalAmountCents) * 100);
  }
  return Math.round(((props.paid || 0) / safeTotal.value) * 100);
});
const overduePct = computed(() => Math.round(((props.overdue || 0) / safeTotal.value) * 100));
const openPct = computed(() => Math.max(0, 100 - paidPct.value - overduePct.value));

const ariaLabel = computed(() => {
  const parts = [
    t('PATIENT_FINANCIAL.PROGRESS.ARIA_PAID', { paid: props.paid, total: props.total }),
  ];
  if (props.overdue > 0) {
    parts.push(t('PATIENT_FINANCIAL.PROGRESS.ARIA_OVERDUE', { overdue: props.overdue }));
  }
  if (props.open > 0) {
    parts.push(t('PATIENT_FINANCIAL.PROGRESS.ARIA_OPEN', { open: props.open }));
  }
  if (props.canceled > 0) {
    parts.push(
      props.canceled === 1 ? '1 cancelada' : `${props.canceled} canceladas`
    );
  }
  return parts.join(', ');
});

const installmentTooltip = inst => {
  const status = (() => {
    if (inst.status === 'pago') return t('PATIENT_FINANCIAL.STATUS.TX.PAID');
    if (inst.status === 'vencido') return t('PATIENT_FINANCIAL.STATUS.TX.OVERDUE');
    if (inst.status === 'cancelado') return t('PATIENT_FINANCIAL.STATUS.TX.CANCELLED');
    if (inst.status === 'reembolsado') return t('PATIENT_FINANCIAL.STATUS.TX.REFUNDED');
    return t('PATIENT_FINANCIAL.STATUS.TX.PENDING');
  })();
  const date = formatDateBR(inst.paid_at || inst.due_date) || '—';
  return `${status} · ${formatCurrency(inst.amount)} · ${date}`;
};

const chipClass = inst => {
  if (inst.status === 'pago') return 'fin-progress-chip--paid';
  if (inst.status === 'vencido') return 'fin-progress-chip--overdue';
  if (inst.status === 'reembolsado') return 'fin-progress-chip--refunded';
  if (inst.status === 'cancelado') return 'fin-progress-chip--cancelled';
  return 'fin-progress-chip--open';
};
</script>

<template>
  <div
    class="fin-progress"
    :class="`fin-progress--${variant}`"
    role="img"
    :aria-label="ariaLabel"
  >
    <!-- Variante summary: só pílulas com totais -->
    <div v-if="variant === 'summary'" class="fin-progress-summary">
      <Tooltip :label="t('PATIENT_FINANCIAL.PROGRESS.PAID_TOOLTIP', { count: paid })">
        <span class="fin-progress-pill fin-progress-pill--paid">
          <i class="i-lucide-check-circle-2 w-3 h-3" />
          {{ paid }}
        </span>
      </Tooltip>
      <Tooltip
        v-if="open > 0"
        :label="t('PATIENT_FINANCIAL.PROGRESS.OPEN_TOOLTIP', { count: open })"
      >
        <span class="fin-progress-pill fin-progress-pill--open">
          <i class="i-lucide-calendar w-3 h-3" />
          {{ open }}
        </span>
      </Tooltip>
      <Tooltip
        v-if="overdue > 0"
        :label="t('PATIENT_FINANCIAL.PROGRESS.OVERDUE_TOOLTIP', { count: overdue })"
      >
        <span class="fin-progress-pill fin-progress-pill--overdue">
          <i class="i-lucide-clock-3 w-3 h-3" />
          {{ overdue }}
        </span>
      </Tooltip>
      <Tooltip
        v-if="canceled > 0"
        :label="canceled === 1 ? '1 parcela cancelada' : `${canceled} parcelas canceladas`"
      >
        <span class="fin-progress-pill fin-progress-pill--cancelled">
          <i class="i-lucide-ban w-3 h-3" />
          {{ canceled }}
        </span>
      </Tooltip>
    </div>

    <!-- Variantes compact e expanded: barra simples — cinza de fundo
         (slate-4) + verde preenchendo proporcional ao % pago.
         Decisão de produto 2026-05-06: barra **não** diferencia
         open/overdue (info redundante com badges de status nas linhas).
         Modelo "vai enchendo conforme paga" é mais escaneável que 3
         segmentos coloridos. -->
    <div v-else>
      <div class="fin-progress-bar" aria-hidden="true">
        <div
          v-if="paidPct > 0"
          class="fin-progress-seg fin-progress-seg--paid"
          :style="{ width: `${paidPct}%` }"
        />
      </div>

      <div class="fin-progress-counter">
        <span class="fin-progress-counter-paid">{{ paid }}</span
        >/{{ total }}
        {{ t('PATIENT_FINANCIAL.PROGRESS.PAID_LABEL') }}
        <template v-if="overdue > 0">
          <span class="fin-progress-counter-sep">·</span>
          <span class="fin-progress-counter-overdue">
            {{ overdue }} {{ t('PATIENT_FINANCIAL.PROGRESS.OVERDUE_LABEL') }}
          </span>
        </template>
        <template v-if="canceled > 0">
          <span class="fin-progress-counter-sep">·</span>
          <span class="fin-progress-counter-cancelled">
            {{ canceled === 1 ? '1 cancelada' : `${canceled} canceladas` }}
          </span>
        </template>
      </div>

      <!-- Chips detalhados (só na variante expanded) -->
      <div v-if="variant === 'expanded' && installments.length > 0" class="fin-progress-chips">
        <Tooltip
          v-for="inst in installments"
          :key="inst.id"
          :label="installmentTooltip(inst)"
        >
          <span class="fin-progress-chip" :class="chipClass(inst)">
            {{ inst.number }}
          </span>
        </Tooltip>
      </div>
    </div>
  </div>
</template>
