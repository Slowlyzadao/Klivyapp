<!--
  FinancialTimeline — timeline financeira unificada do prontuário.

  PR 2 do refactor 2026-05-06. Substitui as 4 abas (Transações / Orçamentos /
  Plano de Tratamento / Recibos) por uma lista única de "Lançamentos
  Financeiros" ordenada por data, com hierarquia pai → parcelas expansível.

  Coexiste com a visão clássica via toggle no FinancialTab (controlado pelo
  pai). Componente é puro/burro: recebe `entries` prontos do
  `useFinancialTimeline` e emite eventos para o pai orquestrar modais.

  Estrutura de cada `entry` (vem do backend `FinancialTimelineBuilder`):
    {
      id, source_type, source_id, recurrence_type,
      origin: { kind, label, link },
      date, description, total, paid, open, overdue,
      progress: { paid, open, overdue, total },
      status, installments: [...], actions_available: [...]
    }

  Eventos emitidos (delegados ao pai, que reusa modais existentes):
    pay(installment_id)        — abre PayTransactionModal (parcela específica)
    refund(installment_id)     — abre RefundTransactionModal
    receipt(installment)       — gera PDF de recibo
    upload-proof(installment)  — abre UploadProofModal
    view-proof(installment)    — abre URL signed do comprovante
    approve-estimate(entry)    — aprova orçamento (linha-pai estimate)
    cancel-estimate(entry)     — cancela orçamento
    open-link(entry)           — navega para Plano de Tratamento (origin=tp)
-->

<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import {
  hasBreakdown,
  breakdownTooltipLabel,
} from '@plugins/financial/frontend/features/financial/v2/composables/useInstallmentBreakdown';
import { formatCurrency } from '@plugins/patients/frontend/features/patient-record/utils/financialFormatters';
import {
  txStatusConfig,
  paymentMethodVisual,
  PAYMENT_METHOD_BADGE_LABELS,
} from '@plugins/patients/frontend/constants/financial';
import InstallmentProgress from './InstallmentProgress.vue';

const props = defineProps({
  entries: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  loadingReceiptId: { type: [Number, String, null], default: null },
  /* v-model:filter — chip de status ativo (Todos / Pendente / Pago / Vencido / Estornado).
     Filtragem real é feita no composable `useFinancialTimeline.filteredEntries`. */
  filter: { type: String, default: 'all' },
});

const emit = defineEmits([
  'pay',
  'refund',
  'charge-whatsapp',
  'receipt',
  'upload-proof',
  'view-proof',
  'approve-estimate',
  'cancel-estimate',
  'open-link',
  'update:filter',
]);

/* Filtros disponíveis. Labels alinhados aos badges visuais da timeline
   (TX_STATUS_CONFIG) pra evitar fricção: chip "Em aberto" filtra entries
   com badge "EM ABERTO", chip "Recebidos" filtra entries "PAGO" etc.
   `em_aberto` agrupa status `pendente` + `parcial` (ambos têm saldo a
   receber e o usuário pensa neles como "em aberto"). */
const filterOptions = computed(() => [
  { value: 'all', label: t('PATIENT_FINANCIAL.FILTERS.ALL'), icon: 'i-lucide-list' },
  { value: 'em_aberto', label: t('PATIENT_FINANCIAL.FILTERS.OPEN'), icon: 'i-lucide-calendar' },
  { value: 'vencido', label: t('PATIENT_FINANCIAL.FILTERS.OVERDUE'), icon: 'i-lucide-alert-circle' },
  { value: 'pago', label: t('PATIENT_FINANCIAL.FILTERS.PAID'), icon: 'i-lucide-check-circle-2' },
  { value: 'reembolsado', label: t('PATIENT_FINANCIAL.FILTERS.REFUNDED'), icon: 'i-lucide-rotate-ccw' },
  { value: 'cancelado', label: t('PATIENT_FINANCIAL.FILTERS.CANCELLED'), icon: 'i-lucide-ban' },
]);

const setFilter = value => {
  emit('update:filter', value);
};

const { t } = useI18n();

// Map de entry.id → boolean para controlar quais cards estão expandidos.
// Default é colapsado pra manter a tela escaneável.
const expanded = ref({});

const toggleExpanded = entryId => {
  expanded.value = { ...expanded.value, [entryId]: !expanded.value[entryId] };
};

const isExpanded = entryId => Boolean(expanded.value[entryId]);

// ───────── helpers de display ─────────

const formatDate = d => formatDateBR(d) || '—';

const statusBadgeProps = status => {
  const cfg = txStatusConfig(status);
  return cfg.color
    ? { color: cfg.color, icon: cfg.icon }
    : { intent: cfg.intent || 'neutral', icon: cfg.icon };
};

const statusLabel = status => {
  const cfg = txStatusConfig(status);
  return cfg.labelKey ? t(cfg.labelKey) : cfg.label;
};

const recurrenceTypeLabel = entry => {
  if (!entry.recurrence_type) return null;
  return t(`PATIENT_FINANCIAL.TIMELINE.RECURRENCE.${entry.recurrence_type.toUpperCase()}`);
};

const recurrenceTypeTooltip = entry => {
  // Regra de produto: rótulo "Mensalidade" não pode mentir sucesso —
  // tooltip explicita que cobrança automática é roadmap futuro.
  if (entry.recurrence_type === 'mensalidade') {
    return t('PATIENT_FINANCIAL.TIMELINE.RECURRENCE.MENSALIDADE_TOOLTIP');
  }
  return null;
};

const recurrenceIcon = entry => {
  if (entry.recurrence_type === 'mensalidade') return 'i-lucide-repeat';
  if (entry.recurrence_type === 'parcelamento') return 'i-lucide-layers-2';
  if (entry.recurrence_type === 'avulso') return 'i-lucide-circle-dot';
  return 'i-lucide-receipt';
};

// Cor do badge de tipo de recorrência. Cores semanticamente coerentes:
//   • mensalidade  → violeta (recorrente, "premium")
//   • parcelamento → azul    (parcelas com fim definido, "ciclo")
//   • avulso       → cinza   (genérico, lançamento único)
const recurrenceTypeColor = entry => {
  if (entry.recurrence_type === 'mensalidade') return 'violet';
  if (entry.recurrence_type === 'parcelamento') return 'blue';
  return 'slate';
};

const originIcon = entry => {
  if (entry.origin?.kind === 'treatment_plan') return 'i-lucide-stethoscope';
  if (entry.origin?.kind === 'estimate') return 'i-lucide-file-text';
  return 'i-lucide-zap';
};

// Recebe a STRING do status (não o objeto inst). Bug encontrado em
// 2026-05-06 testing: o caller passava `inst.status` mas a função
// fazia `inst.status.status` (undefined) → todos os badges caíam no
// fallback `pendente` (amber) → PAGO/ESTORNADO apareciam amarelo.
const installmentStatusBadge = status => {
  const cfg = txStatusConfig(status);
  return cfg.color
    ? { color: cfg.color, icon: cfg.icon }
    : { intent: cfg.intent || 'neutral', icon: cfg.icon };
};

const methodBadgeLabel = method =>
  PAYMENT_METHOD_BADGE_LABELS[method] || method || '';

const canPerform = (entry, action) =>
  Array.isArray(entry.actions_available) && entry.actions_available.includes(action);

// Para parcelas individuais, derivamos as ações disponíveis pela combinação
// status + tipo da entry. Mantém consistência com `actions_available` do
// builder mas no nível da parcela.
//
// Estorno parcial deixa a parcela com effective_status='pendente' mas com
// `partially_refunded=true`. Nesse caso:
//   - NÃO pode "receber" (não é cobrança normal — paciente já pagou e já levou
//     parte do estorno; receber de novo seria duplicar o lançamento).
//   - PODE "estornar" o saldo restante (received_amount > 0 ainda).
// `parcial` = baixa parcial sem cobrir o saldo total. Continua sendo
// recebível (recepção pode bater o saldo restante a qualquer hora).
const installmentCanPay = inst =>
  ['pendente', 'vencido', 'parcial'].includes(inst.status) &&
  !inst.partially_refunded;

// Distinção entre 2 conceitos (split em 2 helpers pra UX defensiva):
//   • `installmentHasPayment` = parcela tem pagamento registrado. Determina
//     se o botão de estorno DEVE APARECER.
//   • `installmentHasReceipt` = parcela tem PaymentReceipt vinculado (canon
//     v2 §5.3). Determina se o botão fica ATIVO ou DESABILITADO.
//
// Dados legados/migrados podem ter `status='pago'` sem `PaymentReceiptItem`
// — backend rejeita o refund. Em vez de esconder o botão, mostramos disabled
// com tooltip explicando "recebimento legado, sem recibo v2". Parcelas pagas
// pelo fluxo v2 sempre têm recibo, então botão fica habilitado normalmente.
const installmentHasPayment = inst =>
  inst.status === 'pago' ||
  (inst.partially_refunded && Number(inst.received_amount_cents || 0) > 0);

const installmentHasReceipt = inst => Number(inst.receipts_count || 0) > 0;

// Mantido pra compat — usado em outros lugares se houver, e expressa
// semântica "pode estornar AGORA". Hoje só usado pelo `v-if` do botão
// no template (será substituído pela split acima).
const installmentCanRefund = installmentHasPayment;

const installmentCanReceipt = inst => inst.status === 'pago' || inst.partially_refunded;

const installmentCanViewProof = inst =>
  (inst.status === 'pago' || inst.partially_refunded) && Boolean(inst.payment_proof_url);

const installmentCanAttachProof = inst =>
  (inst.status === 'pago' || inst.partially_refunded) && !inst.payment_proof_url;

// Filtra as parcelas exibidas DENTRO de cada entry conforme o chip ativo.
// Sem isso, ao clicar "Em aberto", o orçamento agregado (status `parcial`)
// passa pelo filtro de entries mas mostra TODAS as parcelas (pagas + em
// aberto) — visualmente confuso. Aqui mantemos só as parcelas que casam
// com o status do chip.
const installmentsForFilter = (installments, filterValue) => {
  const list = installments || [];
  if (!filterValue || filterValue === 'all') return list;
  if (filterValue === 'em_aberto' || filterValue === 'pendente') {
    return list.filter(i => ['pendente', 'vencido', 'parcial'].includes(i.status));
  }
  if (filterValue === 'vencido') return list.filter(i => i.status === 'vencido');
  if (filterValue === 'pago') return list.filter(i => i.status === 'pago');
  if (filterValue === 'reembolsado') {
    return list.filter(i => i.status === 'reembolsado' || i.partially_refunded);
  }
  return list;
};

const isReceiptLoading = inst => props.loadingReceiptId === inst.id;

// Empty / loading
const isEmpty = computed(() => !props.loading && props.entries.length === 0);
</script>

<template>
  <section class="fin-tl">
    <!-- Filtro de status (chips segmentados) -->
    <div
      class="fin-tl-filters"
      role="tablist"
      :aria-label="t('PATIENT_FINANCIAL.FILTERS.ARIA_LABEL')"
    >
      <button
        v-for="opt in filterOptions"
        :key="opt.value"
        type="button"
        role="tab"
        class="fin-tl-filter-chip"
        :class="{ 'fin-tl-filter-chip--active': filter === opt.value }"
        :aria-selected="filter === opt.value"
        @click="setFilter(opt.value)"
      >
        <i :class="opt.icon" class="w-3.5 h-3.5" />
        <span>{{ opt.label }}</span>
      </button>
    </div>

    <!-- Loading -->
    <div v-if="loading" class="fin-tl-loading">
      <div
        class="w-8 h-8 rounded-full border-2 border-emerald-400 border-t-transparent animate-spin"
        aria-hidden="true"
      />
      <p class="fin-tl-loading-text">{{ t('PATIENT_FINANCIAL.TIMELINE.LOADING') }}</p>
    </div>

    <!-- Empty -->
    <div v-else-if="isEmpty" class="fin-tl-empty">
      <div class="fin-tl-empty-icon">
        <i class="i-lucide-list-todo w-6 h-6" />
      </div>
      <p class="fin-tl-empty-title">{{ t('PATIENT_FINANCIAL.TIMELINE.EMPTY_TITLE') }}</p>
      <p class="fin-tl-empty-hint">{{ t('PATIENT_FINANCIAL.TIMELINE.EMPTY_HINT') }}</p>
    </div>

    <!-- Lista de cards (linha-pai) -->
    <div v-else class="fin-tl-list">
      <article
        v-for="entry in entries"
        :key="entry.id"
        class="fin-tl-card"
        :class="{
          'fin-tl-card--expanded': isExpanded(entry.id),
          'fin-tl-card--needs-approval':
            entry.status === 'rascunho' || entry.status === 'enviado',
          'fin-tl-card--cancelled': entry.status === 'cancelado',
        }"
      >
        <!-- Header da linha-pai (sempre visível) -->
        <header class="fin-tl-card-head">
          <button
            type="button"
            class="fin-tl-card-toggle"
            :aria-expanded="isExpanded(entry.id)"
            :aria-label="t('PATIENT_FINANCIAL.TIMELINE.TOGGLE_ARIA', { description: entry.description })"
            @click="toggleExpanded(entry.id)"
          >
            <span class="fin-tl-card-origin-icon">
              <i :class="recurrenceIcon(entry)" class="w-4 h-4" />
            </span>

            <div class="fin-tl-card-meta">
              <div class="fin-tl-card-title-row">
                <h4 class="fin-tl-card-title">
                  {{ entry.description || t('PATIENT_FINANCIAL.TX_TABLE.DEFAULT_DESCRIPTION') }}
                </h4>
                <Tooltip
                  v-if="recurrenceTypeLabel(entry) && recurrenceTypeTooltip(entry)"
                  :label="recurrenceTypeTooltip(entry)"
                >
                  <Badge
                    :label="recurrenceTypeLabel(entry)"
                    :color="recurrenceTypeColor(entry)"
                    :icon="recurrenceIcon(entry)"
                    size="xs"
                  />
                </Tooltip>
                <Badge
                  v-else-if="recurrenceTypeLabel(entry)"
                  :label="recurrenceTypeLabel(entry)"
                  :color="recurrenceTypeColor(entry)"
                  :icon="recurrenceIcon(entry)"
                  size="xs"
                />
                <!-- CTA visual para orçamentos aguardando aprovação:
                     evita o usuário precisar expandir o card pra descobrir
                     que tem ação pendente. Aparece só em rascunho/enviado. -->
                <Badge
                  v-if="entry.status === 'rascunho' || entry.status === 'enviado'"
                  :label="t('PATIENT_FINANCIAL.TIMELINE.NEEDS_APPROVAL')"
                  color="amber"
                  variant="solid"
                  icon="i-lucide-alert-circle"
                  size="xs"
                />
              </div>
              <p class="fin-tl-card-subtitle">
                <span class="fin-tl-card-origin-label">
                  <i :class="originIcon(entry)" class="w-3 h-3 mr-1" />
                  <a
                    v-if="entry.origin?.kind === 'treatment_plan' && entry.origin.link"
                    href="#"
                    class="fin-tl-card-link"
                    @click.stop.prevent="emit('open-link', entry)"
                  >
                    {{ entry.origin.label }}
                  </a>
                  <span v-else>{{ entry.origin?.label || '—' }}</span>
                </span>
                <span class="fin-tl-card-sep">·</span>
                <span>{{ formatDate(entry.date) }}</span>
              </p>
            </div>

            <div class="fin-tl-card-totals">
              <div class="fin-tl-card-amount">{{ formatCurrency(entry.total) }}</div>
              <Badge
                :label="statusLabel(entry.status)"
                v-bind="statusBadgeProps(entry.status)"
                size="xs"
              />
            </div>

            <i
              class="fin-tl-card-chevron"
              :class="
                isExpanded(entry.id) ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
              "
              aria-hidden="true"
            />
          </button>

          <!-- Indicador de progresso (sempre visível) -->
          <div class="fin-tl-card-progress">
            <InstallmentProgress
              :paid="entry.progress?.paid || 0"
              :open="entry.progress?.open || 0"
              :overdue="entry.progress?.overdue || 0"
              :canceled="entry.progress?.canceled || 0"
              :total="entry.progress?.total || 1"
              :paid-amount-cents="entry.progress?.paid_amount_cents || 0"
              :total-amount-cents="entry.progress?.total_amount_cents || 0"
              :installments="entry.installments || []"
              variant="compact"
            />
          </div>
        </header>

        <!-- Corpo expandido: parcelas (Nível 2) e ações de orçamento -->
        <div v-if="isExpanded(entry.id)" class="fin-tl-card-body">
          <!-- Ações de linha-pai (estimate em rascunho/enviado) -->
          <div
            v-if="canPerform(entry, 'approve_estimate') || canPerform(entry, 'cancel_estimate')"
            class="fin-tl-card-parent-actions"
          >
            <BeclinicButton
              v-if="canPerform(entry, 'approve_estimate')"
              v-can="['patients', 'manage_financial']"
              size="sm"
              variant="solid"
              color="teal"
              icon="i-lucide-check"
              :label="t('PATIENT_FINANCIAL.TIMELINE.ACTIONS.APPROVE_ESTIMATE')"
              @click="emit('approve-estimate', entry)"
            />
            <BeclinicButton
              v-if="canPerform(entry, 'cancel_estimate')"
              v-can="['patients', 'manage_financial']"
              size="sm"
              variant="ghost"
              color="ruby"
              icon="i-lucide-x"
              :label="t('PATIENT_FINANCIAL.TIMELINE.ACTIONS.CANCEL_ESTIMATE')"
              @click="emit('cancel-estimate', entry)"
            />
          </div>

          <!-- Lista de parcelas — respeita o chip de filtro ativo, escondendo
               parcelas que não correspondem (ex: chip "Em aberto" oculta
               parcelas pagas dentro de um orçamento parcial). Header do card
               continua mostrando contagem agregada real (X/Y pagas). -->
          <ul class="fin-tl-installments">
            <li
              v-for="inst in installmentsForFilter(entry.installments, filter)"
              :key="inst.id"
              class="fin-tl-installment"
              :class="{
                'fin-tl-installment--paid': inst.status === 'pago',
                'fin-tl-installment--open': inst.status === 'pendente',
                'fin-tl-installment--overdue': inst.status === 'vencido',
                'fin-tl-installment--partial': inst.status === 'parcial',
                'fin-tl-installment--refunded': inst.status === 'reembolsado',
                'fin-tl-installment--partial-refund': inst.partially_refunded,
              }"
            >
              <span class="fin-tl-installment-number">
                {{ inst.number }}/{{ inst.total }}
              </span>

              <div class="fin-tl-installment-info">
                <p class="fin-tl-installment-title">
                  <!-- Baixa parcial: mostra saldo restante + valor original
                       riscado (mesma UX da tela A Receber global). Pra outros
                       status, mostra o valor da parcela direto. -->
                  <template v-if="inst.status === 'parcial' && inst.remaining">
                    <span>{{ formatCurrency(inst.remaining) }}</span>
                    <span class="fin-tl-installment-amount-strike">
                      de {{ formatCurrency(inst.amount) }}
                    </span>
                  </template>
                  <template v-else>
                    {{ formatCurrency(inst.amount) }}
                  </template>
                  <Badge
                    v-if="inst.payment_method"
                    :label="methodBadgeLabel(inst.payment_method)"
                    :color="paymentMethodVisual(inst.payment_method).color"
                    :icon="paymentMethodVisual(inst.payment_method).icon"
                    size="xs"
                  />
                  <!-- Ícone info: breakdown de juros/multa/desconto/crédito
                       quando houver. Mesmo padrão de Recebíveis e Fluxo de Caixa. -->
                  <Tooltip
                    v-if="hasBreakdown(inst)"
                    :label="breakdownTooltipLabel(inst)"
                    position="top"
                    multiline
                  >
                    <i class="i-lucide-info fin-tl-breakdown-icon" />
                  </Tooltip>
                </p>
                <!-- Estorno parcial: mostra divisão recebido/estornado em vez
                     do "Vence em ..." padrão. Sinal visual claro para evitar
                     o operador confundir com parcela só pendente. -->
                <p
                  v-if="inst.partially_refunded"
                  class="fin-tl-installment-meta fin-tl-installment-partial"
                >
                  <span class="fin-tl-installment-partial-received">
                    <i class="i-lucide-check w-3 h-3" />
                    {{ formatCurrency(inst.received_amount) }} recebido
                  </span>
                  <span class="fin-tl-installment-partial-sep">·</span>
                  <span class="fin-tl-installment-partial-refunded">
                    <i class="i-lucide-undo w-3 h-3" />
                    {{ formatCurrency(inst.refunded) }} estornado
                  </span>
                </p>
                <p v-else class="fin-tl-installment-meta">
                  <span v-if="inst.status === 'pago' && inst.paid_at">
                    {{
                      t('PATIENT_FINANCIAL.TX_TABLE.PAID_AT', {
                        date: formatDate(inst.paid_at),
                      })
                    }}
                  </span>
                  <span v-else-if="inst.due_date">
                    {{
                      t('PATIENT_FINANCIAL.TIMELINE.DUE_AT', {
                        date: formatDate(inst.due_date),
                      })
                    }}
                  </span>
                  <span v-else>—</span>
                </p>
              </div>

              <!-- Em estorno parcial, troca o badge de "Pendente" por
                   "Estornado parcial" pra deixar o estado claro de cara. -->
              <Badge
                v-if="inst.partially_refunded"
                label="Estornado parcial"
                color="amber"
                icon="i-lucide-undo"
                size="xs"
              />
              <Badge
                v-else
                :label="statusLabel(inst.status)"
                v-bind="installmentStatusBadge(inst.status)"
                size="xs"
              />

              <div class="fin-tl-installment-actions">
                <BeclinicButton
                  v-if="installmentCanPay(inst)"
                  v-can="['patients', 'manage_financial']"
                  size="xs"
                  variant="faded"
                  color="teal"
                  icon="i-lucide-check"
                  :label="t('PATIENT_FINANCIAL.TX_ACTIONS.RECEIVE')"
                  @click="emit('pay', inst.id)"
                />
                <Tooltip
                  v-if="installmentCanPay(inst)"
                  label="Editar parcela (canon BUG-02)"
                >
                  <BeclinicButton
                    v-can="['patients', 'manage_financial']"
                    size="xs"
                    variant="ghost"
                    color="slate"
                    icon="i-lucide-pencil"
                    @click="emit('edit-installment', { installment: inst, entry })"
                  />
                </Tooltip>
                <Tooltip
                  v-if="installmentCanPay(inst)"
                  :label="t('PATIENT_FINANCIAL.TX_ACTIONS.WHATSAPP_TITLE')"
                >
                  <BeclinicButton
                    v-can="['patients', 'manage_financial']"
                    size="xs"
                    variant="ghost"
                    color="teal"
                    icon="i-ri-whatsapp-fill"
                    @click="emit('charge-whatsapp', inst.id)"
                  />
                </Tooltip>
                <Tooltip
                  v-if="installmentCanViewProof(inst)"
                  :label="t('PATIENT_FINANCIAL.TX_ACTIONS.VIEW_PROOF_TITLE')"
                >
                  <BeclinicButton
                    size="xs"
                    variant="ghost"
                    color="slate"
                    icon="i-ph-file-text"
                    @click="emit('view-proof', inst)"
                  />
                </Tooltip>
                <Tooltip
                  v-if="installmentCanAttachProof(inst)"
                  :label="t('PATIENT_FINANCIAL.TX_ACTIONS.ATTACH_PROOF_TITLE')"
                >
                  <BeclinicButton
                    v-can="['patients', 'manage_financial']"
                    size="xs"
                    variant="ghost"
                    color="slate"
                    icon="i-ph-upload-simple"
                    @click="emit('upload-proof', inst)"
                  />
                </Tooltip>
                <Tooltip
                  v-if="installmentCanReceipt(inst)"
                  :label="t('PATIENT_FINANCIAL.TIMELINE.ACTIONS.RECEIPT_TITLE')"
                >
                  <BeclinicButton
                    size="xs"
                    variant="ghost"
                    color="teal"
                    :icon="
                      isReceiptLoading(inst) ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-printer'
                    "
                    :disabled="isReceiptLoading(inst)"
                    @click="emit('receipt', inst)"
                  />
                </Tooltip>
                <Tooltip
                  v-if="installmentHasPayment(inst)"
                  :label="installmentHasReceipt(inst)
                    ? t('PATIENT_FINANCIAL.TX_ACTIONS.REFUND_TITLE')
                    : 'Pagamento importado de outro sistema — não tem como estornar'"
                  multiline
                >
                  <BeclinicButton
                    v-can="['patients', 'manage_financial']"
                    size="xs"
                    variant="ghost"
                    color="ruby"
                    icon="i-lucide-undo"
                    :disabled="!installmentHasReceipt(inst)"
                    @click="installmentHasReceipt(inst) && emit('refund', inst.id)"
                  />
                </Tooltip>
              </div>
            </li>
          </ul>
        </div>
      </article>
    </div>
  </section>
</template>
