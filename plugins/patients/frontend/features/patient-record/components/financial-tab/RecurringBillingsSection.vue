<script setup>
/**
 * RecurringBillingsSection — lista de mensalidades fixas do paciente.
 * Decisão 2026-05-28: contrato recorrente real (Financial::RecurringBilling)
 * com motor diário que gera Budget+Installment por período. Substitui o
 * "tipo Mensalidade" do modal Novo Lançamento, que era só uma label.
 *
 * Comportamento:
 *   - Carrega billings do paciente (qualquer status) ao montar e on refresh
 *   - Empty state amigável quando zero billings
 *   - Botão "+ Nova mensalidade" abre CreateRecurringBillingModal
 *   - Por item: descrição, valor, frequência, próxima geração, status badge,
 *     ações (Pausar/Retomar, Cancelar)
 *   - Confirma destrutivos com confirm nativo (parece pouco mas é o padrão
 *     do FinancialTab — refunds, cancels etc. todos usam confirm)
 */
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Toggle from '@plugins/beclinic_core/frontend/components/Toggle.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import ConfirmDangerModal from '@plugins/beclinic_core/frontend/components/ConfirmDangerModal.vue';
import PaymentMethodBadge from '@plugins/beclinic_core/frontend/components/PaymentMethodBadge.vue';
import FinancialV2, {
  isFinancialSetupRequired,
} from '@plugins/financial/frontend/features/financial/v2/api/financialV2';
import CreateRecurringBillingModal from './CreateRecurringBillingModal.vue';

const props = defineProps({
  patientId: { type: [Number, String], required: true },
});

const billings = ref([]);
const loading = ref(false);
const showCreateModal = ref(false);
const collapsed = ref(true); // default colapsado quando vazio; expande ao ter dados

const route = useRoute();
// 412 financial_setup_required: módulo ainda não configurado. Em vez de engolir
// no console (falha silenciosa), a seção mostra um aviso inline com link pro
// assistente de configuração.
const setupRequired = ref(false);
const setupRoute = computed(() => ({
  name: 'financial_v2_setup',
  params: { accountId: route.params.accountId },
}));

const FREQ_LABELS = {
  monthly: 'Mensal',
  bimonthly: 'Bimestral',
  quarterly: 'Trimestral',
  semiannual: 'Semestral',
  annual: 'Anual',
};
// Badges de status com classes light+dark — ainda usados pros estados terminais
// (completed/canceled). Pra `active`/`paused` o estado é representado pelo
// `<Toggle>` (decisão UX 2026-05-28: toggle padrão > badge "ATIVA" estático).
const TERMINAL_STATUS_META = {
  completed: {
    label: 'Concluída',
    class:
      'bg-slate-500/10 text-slate-700 border-slate-500/30 dark:bg-slate-500/15 dark:text-slate-300',
  },
  canceled: {
    label: 'Cancelada',
    class:
      'bg-red-500/10 text-red-700 border-red-500/30 dark:bg-red-500/15 dark:text-red-300',
  },
};
const isTerminal = b => ['completed', 'canceled'].includes(b.status);

// Loading map por billing.id — evita double-click no toggle enquanto o
// pause/resume tá in-flight. Vazio quando nenhum tá processando.
const togglingIds = ref(new Set());
const isToggling = id => togglingIds.value.has(id);
async function toggleActive(b) {
  if (isToggling(b.id) || isTerminal(b)) return;
  togglingIds.value.add(b.id);
  try {
    if (b.status === 'active') {
      await FinancialV2.recurringBillings.pause(b.id);
      useNotification.success('Mensalidade pausada.');
    } else {
      await FinancialV2.recurringBillings.resume(b.id);
      useNotification.success('Mensalidade retomada.');
    }
    await load();
  } catch (e) {
    useNotification.error(e?.response?.data?.message || 'Falha ao alternar status.');
  } finally {
    togglingIds.value.delete(b.id);
  }
}

const activeCount = computed(() => billings.value.filter(b => b.status === 'active').length);

async function load() {
  loading.value = true;
  setupRequired.value = false;
  try {
    const { data } = await FinancialV2.recurringBillings.index({ patient_id: props.patientId });
    billings.value = data?.data || [];
    if (billings.value.length > 0) collapsed.value = false;
  } catch (e) {
    billings.value = [];
    if (isFinancialSetupRequired(e)) {
      setupRequired.value = true;
    } else {
      // eslint-disable-next-line no-console
      console.error('[RecurringBillings] falha ao carregar', e);
    }
  } finally {
    loading.value = false;
  }
}

function fmtBRL(cents) {
  return ((cents || 0) / 100).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  });
}
function fmtDate(iso) {
  if (!iso) return '—';
  const parts = String(iso).slice(0, 10).split('-');
  if (parts.length !== 3) return iso;
  return `${parts[2]}/${parts[1]}/${parts[0]}`;
}

// Cancelamento usa ConfirmDangerModal (componente padrão) em vez de
// window.prompt nativo — UX consistente com resto do app + light/dark.
const cancelTarget = ref(null);
const cancelReason = ref('');
const cancelLoading = ref(false);

function openCancel(b) {
  cancelTarget.value = b;
  cancelReason.value = '';
}
function closeCancel() {
  if (cancelLoading.value) return;
  cancelTarget.value = null;
  cancelReason.value = '';
}
async function confirmCancel() {
  if (!cancelTarget.value) return;
  cancelLoading.value = true;
  try {
    await FinancialV2.recurringBillings.cancel(cancelTarget.value.id, {
      reason: cancelReason.value?.trim() || null,
    });
    useNotification.success('Mensalidade cancelada.');
    cancelTarget.value = null;
    cancelReason.value = '';
    await load();
  } catch (e) {
    useNotification.error(e?.response?.data?.message || 'Falha ao cancelar.');
  } finally {
    cancelLoading.value = false;
  }
}

function onCreated() {
  showCreateModal.value = false;
  load();
}

onMounted(load);

defineExpose({ refresh: load });
</script>

<template>
  <section class="recurring-billings">
    <header class="rb-header">
      <button
        type="button"
        class="rb-toggle"
        :aria-expanded="!collapsed"
        @click="collapsed = !collapsed"
      >
        <i class="i-lucide-repeat w-4 h-4 text-violet-400" />
        <span class="rb-title">Mensalidades fixas</span>
        <span v-if="activeCount > 0" class="rb-count">{{ activeCount }}</span>
        <i
          :class="collapsed ? 'i-lucide-chevron-down' : 'i-lucide-chevron-up'"
          class="w-4 h-4 ml-auto text-slate-400"
        />
      </button>
      <BeclinicButton
        size="sm"
        variant="solid"
        color="blue"
        icon="i-lucide-plus"
        label="Nova mensalidade"
        @click="showCreateModal = true"
      />
    </header>

    <div v-if="!collapsed" class="rb-body">
      <div v-if="loading" class="rb-empty">
        <i class="i-lucide-loader-2 w-4 h-4 animate-spin" />
        Carregando…
      </div>

      <div v-else-if="setupRequired" class="rb-empty">
        <i class="i-lucide-settings w-6 h-6 text-slate-500 mb-2" />
        <p class="text-sm text-slate-400">Módulo financeiro não configurado.</p>
        <p class="text-xs text-slate-500 mt-1">
          Conclua o
          <router-link :to="setupRoute" class="rb-setup-link">assistente de configuração</router-link>
          (Contas Bancárias e Formas de Pagamento) para usar mensalidades fixas.
        </p>
      </div>

      <div v-else-if="billings.length === 0" class="rb-empty">
        <i class="i-lucide-calendar-clock w-6 h-6 text-slate-500 mb-2" />
        <p class="text-sm text-slate-400">Nenhuma mensalidade configurada.</p>
        <p class="text-xs text-slate-500 mt-1">
          Use para cobrar valor recorrente (ortodontia, assinatura). Gera 1 cobrança a cada período automaticamente.
        </p>
      </div>

      <div v-else class="rb-list">
        <div v-for="b in billings" :key="b.id" class="rb-item">
          <!-- Coluna principal: descrição + meta empilhadas. O valor saiu daqui
               (estava espalhado em rb-item-row com space-between, parecia solto). -->
          <div class="rb-item-main">
            <strong class="rb-item-desc">{{ b.description }}</strong>
            <div class="rb-item-meta">
              <span class="rb-item-freq">
                <i class="i-lucide-repeat w-3 h-3" />
                {{ FREQ_LABELS[b.frequency] || b.frequency }}
              </span>
              <span class="rb-item-method">
                <PaymentMethodBadge
                  v-if="b.payment_method?.kind"
                  :kind="b.payment_method.kind"
                  :method="b.payment_method"
                  size="sm"
                  hide-installments
                />
              </span>
              <span class="rb-item-next">
                <i class="i-lucide-calendar w-3 h-3" />
                Próx.: <strong>{{ fmtDate(b.next_generation_at) }}</strong>
              </span>
              <span v-if="b.end_date" class="rb-item-end">
                Até <strong>{{ fmtDate(b.end_date) }}</strong>
              </span>
            </div>
          </div>

          <!-- Valor agora é coluna própria do grid — agrupa visualmente com
               Toggle + ✕ (todos os controles "right-side" alinhados). -->
          <span class="rb-item-amount">{{ fmtBRL(b.amount_cents) }}</span>

          <!-- Status: pra active/paused o Toggle É o estado (clicar pausa/retoma).
               Pra completed/canceled (terminais) mostra badge de texto. -->
          <span
            v-if="isTerminal(b)"
            class="rb-status-badge"
            :class="TERMINAL_STATUS_META[b.status]?.class"
          >
            {{ TERMINAL_STATUS_META[b.status]?.label || b.status }}
          </span>
          <Tooltip
            v-else
            :label="b.status === 'active' ? 'Ativa — clique para pausar' : 'Pausada — clique para retomar'"
            position="top"
          >
            <Toggle
              :model-value="b.status === 'active'"
              size="sm"
              color="brand"
              :disabled="isToggling(b.id)"
              @update:model-value="toggleActive(b)"
            />
          </Tooltip>

          <div class="rb-item-actions">
            <Tooltip
              v-if="!isTerminal(b)"
              label="Cancelar (irreversível; preserva histórico)"
              position="top"
            >
              <button
                type="button"
                class="rb-action rb-action--danger"
                aria-label="Cancelar mensalidade"
                @click="openCancel(b)"
              >
                <i class="i-lucide-x-circle w-4 h-4" />
              </button>
            </Tooltip>
          </div>
        </div>
      </div>
    </div>

    <CreateRecurringBillingModal
      :open="showCreateModal"
      :patient-id="patientId"
      @close="showCreateModal = false"
      @created="onCreated"
    />

    <!-- Modal de confirmação de cancelamento — usa ConfirmDangerModal padrão
         em vez de window.prompt nativo. Slot default abriga o textarea pro
         motivo opcional. `v-model:show` controla via boolean derivado de
         cancelTarget (null = fechado). -->
    <ConfirmDangerModal
      :show="cancelTarget !== null"
      title="Cancelar mensalidade?"
      :message="cancelTarget ? `${cancelTarget.description} — esta ação é irreversível, mas as cobranças já geradas são preservadas.` : ''"
      confirm-label="Cancelar mensalidade"
      cancel-label="Voltar"
      :loading="cancelLoading"
      @update:show="v => { if (!v) closeCancel(); }"
      @confirm="confirmCancel"
      @cancel="closeCancel"
    >
      <label class="rb-cancel-reason-label">
        Motivo do cancelamento <span class="rb-cancel-reason-hint">(opcional)</span>
      </label>
      <textarea
        v-model="cancelReason"
        rows="2"
        maxlength="500"
        placeholder="Ex.: cliente cancelou contrato, mudou de plano…"
        class="rb-cancel-reason-input"
        :disabled="cancelLoading"
      />
    </ConfirmDangerModal>
  </section>
</template>

<style scoped lang="scss">
/* Tokens Radix (`--slate-N`, `--violet-N`, `--green-N`, `--ruby-N`) auto-adaptam
   light/dark via `_next-colors.scss`. Convertido de slate-900/slate-100 hardcoded
   p/ tokens semânticos (decisão 2026-05-28): a seção é inline na aba — tem que
   bater com o resto do app em ambos os modos. */
.recurring-billings {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-6));
  border-radius: 12px;
  margin-bottom: 16px;
  overflow: hidden;
}

.rb-header {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  border-bottom: 1px solid rgb(var(--slate-5));
  background: rgb(var(--slate-3) / 0.5);
}
.rb-toggle {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  background: transparent;
  border: 0;
  color: rgb(var(--slate-12));
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  padding: 4px 6px;
  border-radius: 6px;
  flex: 1;

  &:hover { background: rgb(var(--slate-4)); }
}
.rb-title { letter-spacing: -0.01em; }
.rb-count {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 22px;
  height: 20px;
  padding: 0 7px;
  border-radius: 10px;
  background: rgb(var(--violet-4));
  color: rgb(var(--violet-11));
  border: 1px solid rgb(var(--violet-6));
  font-size: 11px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
}

.rb-body { padding: 12px 16px 16px; }
.rb-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 24px 12px;
  text-align: center;
  color: rgb(var(--slate-11));
  font-size: 13px;
  gap: 4px;
}
.rb-setup-link {
  color: rgb(var(--blue-11));
  font-weight: 600;
  text-decoration: underline;
  &:hover { color: rgb(var(--blue-12)); }
}

.rb-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.rb-item {
  /* 4 colunas: [main] [valor] [toggle/badge] [✕]. Valor saiu da coluna main
     (decisão 2026-05-28) pra ficar agrupado com os outros controles "right-side"
     em vez de espalhado dentro da 1fr — antes parecia solto. */
  display: grid;
  grid-template-columns: 1fr auto auto auto;
  align-items: center;
  gap: 14px;
  padding: 12px 14px;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-6));
  border-radius: 8px;
}
.rb-item-main {
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.rb-item-desc {
  color: rgb(var(--slate-12));
  font-size: 14px;
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  line-height: 1.2;
}
.rb-item-amount {
  /* `--teal-11` é o token "money" do design system — `--green-*` não existe
     (vide [[project-emerald-token-inexistente]]). Renderiza teal saturado em
     ambos os modos com bom contraste. */
  color: rgb(var(--teal-11));
  font-size: 15px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
  text-align: right;
  /* Mínimo pra ancorar valores curtos (R$ 50,00) e largos (R$ 12.345,67)
     na mesma posição visual — evita "saltinho" entre linhas de billings. */
  min-width: 84px;
}
.rb-item-meta {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 12px;
  font-size: 12px;
  color: rgb(var(--slate-11));

  > span {
    display: inline-flex;
    align-items: center;
    gap: 4px;
  }
  strong { color: rgb(var(--slate-12)); font-weight: 600; font-variant-numeric: tabular-nums; }
  i { opacity: 0.8; }
}

.rb-status-badge {
  display: inline-flex;
  align-items: center;
  padding: 3px 9px;
  border-radius: 999px;
  border: 1px solid;
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  flex-shrink: 0;
}

.rb-item-actions {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}
.rb-action {
  width: 28px;
  height: 28px;
  padding: 0;
  border-radius: 6px;
  border: 1px solid transparent;
  background: transparent;
  color: rgb(var(--slate-11));
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  transition: all 160ms;

  &:hover {
    background: rgb(var(--slate-4));
    color: rgb(var(--slate-12));
    border-color: rgb(var(--slate-7));
  }
  &--danger:hover {
    background: rgb(var(--ruby-4));
    color: rgb(var(--ruby-11));
    border-color: rgb(var(--ruby-7));
  }
}

@media (max-width: 640px) {
  /* Mobile: mantém as 4 colunas (1fr auto auto auto) mas comprime gap e
     padding. `rb-item-meta` é flex-wrap, então o texto quebra naturalmente
     se a coluna `main` ficar muito estreita. Mais elegante que stacked. */
  .rb-item {
    gap: 8px;
    padding: 10px 12px;
  }
  .rb-item-amount {
    font-size: 14px;
    min-width: 0;
  }
}

/* Textarea do motivo no ConfirmDangerModal — slot content carrega o
   `data-v-*` desse componente, então scoped funciona mesmo com o modal
   teleportado pro <body>. */
.rb-cancel-reason-label {
  display: block;
  margin-top: 10px;
  font-size: 12px;
  font-weight: 500;
  color: rgb(var(--slate-11));
}
.rb-cancel-reason-hint {
  color: rgb(var(--slate-9));
  font-weight: 400;
}
.rb-cancel-reason-input {
  display: block;
  width: 100%;
  margin-top: 6px;
  padding: 8px 10px;
  background: rgb(var(--slate-1));
  color: rgb(var(--slate-12));
  border: 1px solid rgb(var(--slate-6));
  border-radius: 6px;
  font-size: 13px;
  font-family: inherit;
  line-height: 1.4;
  resize: vertical;
  min-height: 56px;
  transition: border-color 0.12s;

  &::placeholder { color: rgb(var(--slate-9)); }
  &:focus {
    outline: none;
    border-color: rgb(var(--ruby-9));
    box-shadow: 0 0 0 3px rgb(var(--ruby-9) / 0.12);
  }
  &:disabled { opacity: 0.6; cursor: not-allowed; }
}
</style>
