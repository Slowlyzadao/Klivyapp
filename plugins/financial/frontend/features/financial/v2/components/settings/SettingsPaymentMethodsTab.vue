<script setup>
/**
 * Tab "Formas de Pagamento" — wireframe 2026-05-23.
 *
 * Lista master de meios de pagamento (Dinheiro, PIX, Crédito, Débito, Boleto,
 * Convênio, Parcelamento Próprio). Cada linha expande pra mostrar fees
 * VERSIONADAS (canon mapa-financeiro: "NUNCA editar, sempre criar nova").
 *
 * Colunas:
 *   TIPO | NOME | PROVIDER | CONTA PADRÃO | TAXAS VIGENTES | STATUS | AÇÕES
 *
 * Sub-vista (expandable):
 *   PARCELAS | % TAXA | R$ FIXO | LIQUIDAÇÃO | VIGÊNCIA | STATUS | AÇÕES
 *
 * Endpoints:
 *   GET    /financial/v2/payment_methods
 *   POST/PUT/DELETE /financial/v2/payment_methods/:id
 *   GET    /financial/v2/payment_methods/:id/fees
 *   POST   /financial/v2/payment_methods/:id/fees       (criar nova)
 *   POST   /financial/v2/payment_methods/:id/fees/:fid/deactivate
 */
import { ref, computed, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Toggle from '@plugins/beclinic_core/frontend/components/Toggle.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import ConfirmDangerModal from '@plugins/beclinic_core/frontend/components/ConfirmDangerModal.vue';
import PaymentMethodBadge, {
  displayPaymentMethod,
} from '@plugins/beclinic_core/frontend/components/PaymentMethodBadge.vue';
import FinancialV2 from '../../api/financialV2';
import PaymentMethodFormModalV2 from './PaymentMethodFormModalV2.vue';
import PaymentMethodFeeFormModalV2 from './PaymentMethodFeeFormModalV2.vue';

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const methods = ref([]);
const bankAccounts = ref([]);
const loading = ref(false);
const errorState = ref(null);

const showMethodModal = ref(false);
const editingMethod = ref(null);

const showFeeModal = ref(false);
const feeModalMethod = ref(null);

// Expandable: feesByMethodId[methodId] = { loaded, fees, loading }
const feesByMethodId = ref({});
const expandedMethodIds = ref(new Set());

// Collapse de grupos por provider — operador pode recolher providers cheios
// pra focar nos relevantes. Default: tudo aberto.
const collapsedProviders = ref(new Set());

function toggleProviderCollapse(providerKey) {
  if (collapsedProviders.value.has(providerKey)) {
    collapsedProviders.value.delete(providerKey);
  } else {
    collapsedProviders.value.add(providerKey);
  }
  collapsedProviders.value = new Set(collapsedProviders.value);
}

function isProviderCollapsed(providerKey) {
  return collapsedProviders.value.has(providerKey);
}

async function load() {
  loading.value = true;
  errorState.value = null;
  try {
    const [methodsRes, bankAccountsRes] = await Promise.all([
      FinancialV2.paymentMethods.index(),
      FinancialV2.bankAccounts.index(),
    ]);
    methods.value = methodsRes?.data?.data || [];
    bankAccounts.value = bankAccountsRes?.data?.data || [];
  } catch (err) {
    errorState.value = err?.response?.data?.message || 'Erro ao carregar formas de pagamento';
    notifyError(errorState.value);
  } finally {
    loading.value = false;
  }
}

onMounted(load);

// Labels e classes vivem em PaymentMethodBadge (single source of truth).
// PAYMENT_KIND_LABELS exportado pra título da sub-tabela e mensagens.

function bankAccountName(id) {
  if (!id) return '—';
  const ba = bankAccounts.value.find(b => b.id === id);
  return ba?.name || `#${id}`;
}

// ── Expansão de fees ─────────────────────────────────────────────────
async function toggleExpand(method) {
  if (expandedMethodIds.value.has(method.id)) {
    expandedMethodIds.value.delete(method.id);
    expandedMethodIds.value = new Set(expandedMethodIds.value);
    return;
  }
  expandedMethodIds.value.add(method.id);
  expandedMethodIds.value = new Set(expandedMethodIds.value);
  await loadFeesFor(method);
}

async function loadFeesFor(method) {
  const current = feesByMethodId.value[method.id];
  if (current?.loaded && !current?.stale) return;

  feesByMethodId.value = {
    ...feesByMethodId.value,
    [method.id]: { loaded: false, fees: [], loading: true },
  };

  try {
    const res = await FinancialV2.paymentMethodFees.index(method.id);
    feesByMethodId.value = {
      ...feesByMethodId.value,
      [method.id]: { loaded: true, fees: res?.data?.data || [], loading: false },
    };
  } catch (err) {
    notifyError(err?.response?.data?.message || 'Erro ao carregar taxas');
    feesByMethodId.value = {
      ...feesByMethodId.value,
      [method.id]: { loaded: true, fees: [], loading: false, error: true },
    };
  }
}

// ── Formatadores fees ─────────────────────────────────────────────────
function formatPercent(basisPoints) {
  if (basisPoints == null) return '—';
  return (basisPoints / 100).toFixed(2) + '%';
}

function formatBRL(cents) {
  if (cents == null || cents === 0) return 'R$ 0,00';
  const v = cents / 100;
  return 'R$ ' + v.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function formatDays(days) {
  if (days == null) return '—';
  if (days === 0) return 'D+0 (imediato)';
  return `D+${days}`;
}

function formatDateRange(from, to) {
  const fmt = d => d ? new Date(d).toLocaleDateString('pt-BR') : null;
  const f = fmt(from);
  const t = fmt(to);
  if (!f) return '—';
  if (!t) return `desde ${f}`;
  return `${f} → ${t}`;
}

// ── Ações de método ──────────────────────────────────────────────────
// `prefilledProvider` pra abrir modal já com provider sugerido (clique no
// botão "+ Adicionar nesta" dentro de um grupo). Modal lê e pré-preenche
// o campo provider — operador só escolhe o kind/name e taxas.
const prefilledProvider = ref(null);

// Bug fix 2026-05-23: `@click="fn"` (sem parens) passa o PointerEvent como
// primeiro arg. Sanitiza pra aceitar SÓ string — eventos viram null.
function openMethodModalForNew(providerName = null) {
  editingMethod.value = null;
  prefilledProvider.value = typeof providerName === 'string' ? providerName : null;
  showMethodModal.value = true;
}

function openMethodModalForEdit(method) {
  editingMethod.value = method;
  showMethodModal.value = true;
}

function onMethodSaved() {
  showMethodModal.value = false;
  load();
}

// Toggle inline ativo/inativo na lista — 1 clique, sem abrir modal.
// Operador 90% das vezes só quer ligar/desligar; pra editar nome, provider,
// conta, etc. usa "Editar". Backend faz UPDATE simples; taxas (active fees)
// permanecem intactas em ambos os sentidos.
async function onToggleStatus(method, newActive) {
  const targetStatus = newActive ? 'active' : 'inactive';
  // Otimisticamente atualiza UI antes do round-trip (toggle responsivo)
  const prevStatus = method.status;
  method.status = targetStatus;
  try {
    await FinancialV2.paymentMethods.update(method.id, {
      payment_method: { status: targetStatus },
    });
    notifySuccess(newActive
      ? 'Reativada — taxas existentes preservadas.'
      : 'Inativada — fica na lista, dá pra reativar.');
    // Reload pra refletir contagens/posição
    await load();
  } catch (err) {
    // Rollback otimista em caso de erro
    method.status = prevStatus;
    const msg = err?.response?.data?.message
      || err?.response?.data?.errors?.join('; ')
      || 'Erro ao alterar status.';
    notifyError(msg);
  }
}

// F2.5 — Toggle inline pra ligar/desligar repasse de MDR ao cliente.
// Mesma mecânica otimista do `onToggleStatus`. Sem reload completo
// (mudança não afeta count de fees nem posição na lista — só o flag).
async function onTogglePassthrough(method, newValue) {
  const prev = !!method.passes_fee_to_patient;
  method.passes_fee_to_patient = newValue;
  try {
    await FinancialV2.paymentMethods.update(method.id, {
      payment_method: { passes_fee_to_patient: newValue },
    });
    notifySuccess(newValue
      ? 'Repasse de taxa ativado — parcelas serão infladas na próxima aprovação.'
      : 'Repasse desativado — clínica volta a absorver a MDR.');
  } catch (err) {
    // Rollback otimista
    method.passes_fee_to_patient = prev;
    const msg = err?.response?.data?.message
      || err?.response?.data?.errors?.join('; ')
      || 'Erro ao alterar repasse de taxa.';
    notifyError(msg);
  }
}

async function onMethodDeactivate(methodId) {
  try {
    // Update status pra `inactive` — mantém o registro na lista (preserva
    // histórico visual + permite reativar via "Editar"). Antes chamava
    // `destroy` que faz soft-delete e o index filtra `.alive`, sumindo
    // da tela — UX confusa pro operador que esperava "inativar" ≠ "excluir".
    await FinancialV2.paymentMethods.update(methodId, {
      payment_method: { status: 'inactive' },
    });
    notifySuccess('Forma de pagamento inativada — fica na lista, dá pra reativar.');
    showMethodModal.value = false;
    await load();
  } catch (err) {
    const msg = err?.response?.data?.message
      || err?.response?.data?.errors?.join('; ')
      || 'Erro ao inativar.';
    notifyError(msg);
  }
}

// ── Ações de fee ─────────────────────────────────────────────────────
function openFeeModal(method) {
  feeModalMethod.value = method;
  showFeeModal.value = true;
}

function onFeeSaved() {
  showFeeModal.value = false;
  if (feeModalMethod.value) {
    // marca como stale pra forçar reload
    feesByMethodId.value = {
      ...feesByMethodId.value,
      [feeModalMethod.value.id]: {
        ...(feesByMethodId.value[feeModalMethod.value.id] || {}),
        stale: true,
      },
    };
    loadFeesFor(feeModalMethod.value);
  }
  load(); // pra atualizar contagem de taxas vigentes no master
}

async function onFeeDeactivate(method, feeId) {
  try {
    await FinancialV2.paymentMethodFees.deactivate(method.id, feeId);
    notifySuccess('Taxa inativada. Crie uma nova com vigência atualizada se necessário.');
    feesByMethodId.value = {
      ...feesByMethodId.value,
      [method.id]: { ...feesByMethodId.value[method.id], stale: true },
    };
    await loadFeesFor(method);
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.message || 'Erro ao inativar taxa');
  }
}

// ── Categorização visual ─────────────────────────────────────────────
// Agrupado por provider — mental model "contratei a Stone pra esses N kinds".
// Provider null/'' vai pro bucket "Sem provider" (formas operadas direto
// pela clínica: dinheiro, transferência bancária pessoal, parcelamento próprio).
//
// Retorna [{ provider, providerAlias, displayName, methods: [...] }] estável.
// `provider` é o raw (chave técnica do agrupamento, imutável); `providerAlias`
// é o apelido escolhido pelo operador (display). UI mostra alias se existir.
const methodsByProvider = computed(() => {
  const groups = new Map();
  for (const m of methods.value) {
    const key = (m.provider || '').trim() || '__none__';
    if (!groups.has(key)) groups.set(key, { provider: m.provider || null, alias: m.provider_alias || null, methods: [] });
    const bucket = groups.get(key);
    bucket.methods.push(m);
    // alias é o mesmo entre métodos do mesmo provider (propagado pelo backend),
    // mas em race conditions defensivo: usa o primeiro não-vazio encontrado.
    if (!bucket.alias && m.provider_alias) bucket.alias = m.provider_alias;
  }

  for (const bucket of groups.values()) {
    bucket.methods.sort((a, b) => {
      if (a.status !== b.status) return a.status === 'active' ? -1 : 1;
      return a.name.localeCompare(b.name, 'pt-BR');
    });
  }

  const result = [];
  if (groups.has('__none__')) {
    result.push(groups.get('__none__'));
    groups.delete('__none__');
  }
  [...groups.keys()].sort((a, b) => a.localeCompare(b, 'pt-BR')).forEach(key => {
    result.push(groups.get(key));
  });
  return result;
});

// ── Rename inline de provedor ────────────────────────────────────────
// Operador clica no nome do header → input substitui o texto → enter/blur
// salva. Backend propaga alias em todos os métodos do mesmo (account, provider).
const editingProviderKey = ref(null); // raw provider sendo editado (ou '__none__')
const providerAliasDraft = ref('');
const providerRenameLoading = ref(false);

function startProviderRename(group) {
  if (!group.provider) return; // "sem provedor" não tem o que renomear
  editingProviderKey.value = group.provider;
  providerAliasDraft.value = group.alias || '';
  // Foca no próximo tick — input ainda não existe no DOM nesse instante
  setTimeout(() => {
    const el = document.querySelector('.pmtab-group-alias-input');
    if (el) { el.focus(); el.select(); }
  }, 0);
}

function cancelProviderRename() {
  editingProviderKey.value = null;
  providerAliasDraft.value = '';
}

async function saveProviderRename(group) {
  if (!group.provider) return;
  const newAlias = providerAliasDraft.value.trim();
  // Se não mudou, só fecha
  if ((group.alias || '') === newAlias) {
    cancelProviderRename();
    return;
  }
  providerRenameLoading.value = true;
  try {
    await FinancialV2.paymentMethods.renameProvider({
      provider: group.provider,
      provider_alias: newAlias,
    });
    notifySuccess(newAlias
      ? `Provedor renomeado para "${newAlias}".`
      : 'Apelido removido — voltou a exibir o nome original.');
    cancelProviderRename();
    await load();
  } catch (err) {
    const msg = err?.response?.data?.message
      || err?.response?.data?.error
      || 'Erro ao renomear provedor.';
    notifyError(msg);
  } finally {
    providerRenameLoading.value = false;
  }
}

// ── Confirmação de exclusão (modal padrão beclinic_core) ─────────────
// Unifica os 2 fluxos de delete (individual e por provedor) atrás do
// mesmo ConfirmDangerModal. `confirmTarget` decide qual API chamar.
const showConfirmDelete = ref(false);
const confirmDeleteLoading = ref(false);
const confirmTarget = ref(null); // { type: 'method'|'provider', payload, title, message, confirmLabel }

function openConfirmDelete(target) {
  confirmTarget.value = target;
  showConfirmDelete.value = true;
}

function closeConfirmDelete() {
  if (confirmDeleteLoading.value) return;
  showConfirmDelete.value = false;
  confirmTarget.value = null;
}

async function executeConfirmDelete() {
  if (!confirmTarget.value) return;
  confirmDeleteLoading.value = true;
  try {
    if (confirmTarget.value.type === 'method') {
      await FinancialV2.paymentMethods.destroy(confirmTarget.value.payload.id);
      notifySuccess(`Método "${confirmTarget.value.payload.name}" excluído.`);
    } else if (confirmTarget.value.type === 'provider') {
      const { provider, label, count } = confirmTarget.value.payload;
      const res = await FinancialV2.paymentMethods.destroyProvider({ provider });
      notifySuccess(`Provedor "${label}" excluído (${res?.data?.deleted_count || count} método(s)).`);
    }
    showConfirmDelete.value = false;
    confirmTarget.value = null;
    await load();
  } catch (err) {
    const msg = err?.response?.data?.message
      || err?.response?.data?.error
      || 'Erro ao excluir.';
    notifyError(msg);
  } finally {
    confirmDeleteLoading.value = false;
  }
}

// Atalhos pra abrir o modal com payload certo
function onDeleteProvider(group) {
  if (!group.provider) return;
  const label = group.alias || group.provider;
  const count = group.methods.length;
  openConfirmDelete({
    type: 'provider',
    payload: { provider: group.provider, label, count },
    title: `Excluir provedor "${label}"?`,
    message: `Vai remover ${count} método(s) cadastrado(s) sob este provedor. Só funciona se nenhum método tiver recebido pagamento ainda — caso contrário, o histórico é preservado e a operação é bloqueada.`,
    confirmLabel: 'Excluir provedor',
  });
}

function onDeleteMethod(method) {
  openConfirmDelete({
    type: 'method',
    payload: { id: method.id, name: method.name },
    title: `Excluir "${method.name}"?`,
    message: 'Só funciona se este método nunca foi usado em lançamentos (recebimentos). Se já houve uso, prefira inativar — assim o histórico fica preservado.',
    confirmLabel: 'Excluir método',
  });
}
</script>

<template>
  <div class="pmtab">
    <header class="pmtab-header">
      <div>
        <h2 class="pmtab-title">Formas de Pagamento</h2>
        <p class="pmtab-subtitle">
          Setup #3 · Meios aceitos pela clínica. Taxas são <strong>versionadas</strong> —
          nunca editáveis. Para mudar uma taxa, inative a vigente e crie outra
          com nova data de início.
        </p>
      </div>
      <BeclinicButton
        variant="solid"
        color="blue"
        icon="i-lucide-plus"
        label="Adicionar"
        class="finv2-btn-icon-only-mobile"
        @click="openMethodModalForNew"
      />
    </header>

    <!-- Loading -->
    <div v-if="loading && methods.length === 0" class="pmtab-loading">
      <div class="pmtab-spinner" />
      <span>Carregando formas de pagamento...</span>
    </div>

    <!-- Error -->
    <div v-else-if="errorState" class="pmtab-error">
      <i class="i-lucide-alert-circle" />
      <div>
        <strong>Não foi possível carregar.</strong>
        <p>{{ errorState }}</p>
      </div>
      <BeclinicButton variant="ghost" color="slate" label="Tentar de novo" @click="load" />
    </div>

    <!-- Empty -->
    <div v-else-if="methods.length === 0" class="pmtab-empty">
      <i class="i-lucide-credit-card" />
      <h3>Nenhuma forma de pagamento configurada</h3>
      <p>Comece cadastrando dinheiro, PIX, cartão, etc. Sem isso, recebimentos não podem ser registrados.</p>
      <BeclinicButton variant="solid" color="blue" icon="i-lucide-plus" label="Adicionar primeiro" @click="openMethodModalForNew" />
    </div>

    <!-- Conteúdo -->
    <div v-else class="pmtab-content">
      <div class="pmtab-table-wrap">
        <table class="pmtab-table">
          <thead>
            <tr>
              <th class="pmtab-th-kind">TIPO</th>
              <th class="pmtab-th-bank">CONTA PADRÃO</th>
              <th class="pmtab-th-fees">TAXAS VIGENTES</th>
              <th class="pmtab-th-passthrough">REPASSA TAXA</th>
              <th class="pmtab-th-status">STATUS</th>
              <th class="pmtab-th-actions"></th>
            </tr>
          </thead>
          <tbody>
            <!-- Agrupamento por provider (canon §3 — operador contrata 1+
                 adquirentes, cada um oferece N kinds). Grupo "Sem provider"
                 cobre formas operadas direto pela clínica (dinheiro, transf
                 pessoal, parcelamento próprio). -->
            <template v-for="group in methodsByProvider" :key="group.provider || 'none'">
              <tr class="pmtab-group-header" @click="toggleProviderCollapse(group.provider || '__none__')">
                <td colspan="6">
                  <div class="pmtab-group-header-row">
                    <button
                      type="button"
                      class="pmtab-group-chevron"
                      :class="{ 'pmtab-group-chevron--collapsed': isProviderCollapsed(group.provider || '__none__') }"
                      :aria-label="isProviderCollapsed(group.provider || '__none__') ? 'Expandir grupo' : 'Recolher grupo'"
                      @click.stop="toggleProviderCollapse(group.provider || '__none__')"
                    >
                      <i class="i-lucide-chevron-down" />
                    </button>
                    <span class="pmtab-group-name">
                      <i :class="group.provider ? 'i-lucide-building-2' : 'i-lucide-circle-dot'" class="size-[14px]" />
                      <!-- Display: alias se setado, senão provider raw. "Sem provedor"
                           não é renomeável (não é um provedor real). -->
                      <template v-if="editingProviderKey === group.provider && group.provider">
                        <input
                          v-model="providerAliasDraft"
                          type="text"
                          class="pmtab-group-alias-input"
                          maxlength="120"
                          :disabled="providerRenameLoading"
                          :placeholder="group.provider"
                          @click.stop
                          @keydown.enter.prevent="saveProviderRename(group)"
                          @keydown.esc.prevent="cancelProviderRename()"
                          @blur="saveProviderRename(group)"
                        />
                      </template>
                      <template v-else>
                        <span class="pmtab-group-label">
                          {{ group.alias || group.provider || 'Sem provedor (operação direta da clínica)' }}
                        </span>
                        <span v-if="group.alias && group.provider" class="pmtab-group-raw" :title="`Nome original: ${group.provider}`">
                          ({{ group.provider }})
                        </span>
                        <button
                          v-if="group.provider"
                          type="button"
                          class="pmtab-group-rename"
                          :title="group.alias ? 'Editar apelido do provedor' : 'Adicionar apelido'"
                          aria-label="Renomear provedor"
                          @click.stop="startProviderRename(group)"
                        >
                          <i class="i-lucide-pencil size-[12px]" />
                        </button>
                      </template>
                    </span>
                    <span class="pmtab-group-count">
                      {{ group.methods.length }}
                      {{ group.methods.length === 1 ? 'método' : 'métodos' }}
                    </span>
                    <button
                      type="button"
                      class="pmtab-group-add"
                      @click.stop="openMethodModalForNew(group.provider)"
                    >
                      <i class="i-lucide-plus size-[12px]" /> Adicionar método
                    </button>
                    <!-- Excluir provedor inteiro (cadastro errado).
                         Aparece só pra grupos com provider real. Backend
                         valida se algum método foi usado em lançamentos. -->
                    <Tooltip
                      v-if="group.provider"
                      label="Excluir provedor (se nenhum método foi usado)"
                      position="top"
                    >
                      <button
                        type="button"
                        class="pmtab-group-delete"
                        aria-label="Excluir provedor"
                        @click.stop="onDeleteProvider(group)"
                      >
                        <i class="i-lucide-trash-2 size-[12px]" />
                      </button>
                    </Tooltip>
                  </div>
                </td>
              </tr>

              <template v-if="!isProviderCollapsed(group.provider || '__none__')" v-for="method in group.methods" :key="method.id">
              <tr class="pmtab-row"
                  :class="{ 'pmtab-row--inactive': method.status !== 'active', 'pmtab-row--expanded': expandedMethodIds.has(method.id) }"
                  @click="toggleExpand(method)">
                <!-- TIPO unificado — usa componente reutilizável PaymentMethodBadge
                     que centraliza ícone + label + chip parcelas + nome custom.
                     Single source of truth pra labels/ícones/classes (canon). -->
                <td class="pmtab-td-kind">
                  <PaymentMethodBadge :kind="method.kind" :method="method" size="md" />
                </td>
                <td class="pmtab-td-bank">{{ bankAccountName(method.default_bank_account_id) }}</td>
                <td class="pmtab-td-fees">
                  <span v-if="method.active_fees_count > 0" class="pmtab-fees-count">
                    {{ method.active_fees_count }} ativa(s)
                  </span>
                  <span v-else class="pmtab-fees-missing">sem taxas</span>
                </td>
                <td class="pmtab-td-passthrough" @click.stop>
                  <!-- F2.5: toggle inline pra ligar/desligar o repasse de MDR ao cliente.
                       Quando ON: ApproveBudget infla as parcelas pra clínica receber o
                       base cheio. Quando OFF: clínica absorve a taxa (V2 original).
                       Tooltip explica o efeito sem precisar reabrir o modal. -->
                  <Tooltip
                    :label="method.passes_fee_to_patient
                      ? 'Cliente paga a MDR — parcelas são infladas; clínica recebe o valor base.'
                      : 'Clínica absorve a MDR — paciente paga o valor cheio; clínica recebe líquido.'"
                    position="left"
                    multiline
                  >
                    <Toggle
                      :model-value="!!method.passes_fee_to_patient"
                      size="sm"
                      @update:model-value="(v) => onTogglePassthrough(method, v)"
                    />
                  </Tooltip>
                </td>
                <td class="pmtab-td-status" @click.stop>
                  <!-- Toggle inline: 1 clique ativa/inativa sem abrir modal.
                       Sem label — o próprio toggle (azul=ON, cinza=OFF) já
                       comunica o estado. Reduz ruído visual em listas densas. -->
                  <Toggle
                    :model-value="method.status === 'active'"
                    size="sm"
                    @update:model-value="(v) => onToggleStatus(method, v)"
                  />
                </td>
                <td class="pmtab-td-actions" @click.stop>
                  <div class="pmtab-actions-group">
                    <!-- position="left" pra evitar overflow horizontal —
                         botões estão na borda direita da tabela, tooltip "top"
                         vazaria. `multiline` reforça wrap quando texto é longo. -->
                    <Tooltip label="Editar" position="left">
                      <button
                        type="button"
                        class="pmtab-icon-btn"
                        aria-label="Editar"
                        @click.stop="openMethodModalForEdit(method)"
                      >
                        <i class="i-lucide-pencil" />
                      </button>
                    </Tooltip>
                    <!-- Excluir individual — soft-delete só se nunca foi usado.
                         Backend retorna 422 se houver Installment vinculada
                         (mensagem clara orientando a inativar em vez). -->
                    <Tooltip
                      label="Excluir (apenas se nunca usado)"
                      position="left"
                      multiline
                    >
                      <button
                        type="button"
                        class="pmtab-icon-btn pmtab-icon-btn--danger"
                        aria-label="Excluir"
                        @click.stop="onDeleteMethod(method)"
                      >
                        <i class="i-lucide-trash-2" />
                      </button>
                    </Tooltip>
                    <!-- Chevron de expand das fees migrou pra direita
                         (antes ocupava coluna inteira à esquerda — era espaço
                         desperdiçado). Linha inteira clicável continua válida. -->
                    <Tooltip :label="expandedMethodIds.has(method.id) ? 'Recolher taxas' : 'Ver taxas'" position="left">
                      <button
                        type="button"
                        class="pmtab-icon-btn pmtab-icon-btn--chevron"
                        :class="{ 'pmtab-icon-btn--chevron-open': expandedMethodIds.has(method.id) }"
                        :aria-label="expandedMethodIds.has(method.id) ? 'Recolher taxas' : 'Expandir taxas'"
                        @click.stop="toggleExpand(method)"
                      >
                        <i class="i-lucide-chevron-down" />
                      </button>
                    </Tooltip>
                  </div>
                </td>
              </tr>

              <!-- Sub-tabela de fees -->
              <tr v-if="expandedMethodIds.has(method.id)" class="pmtab-sub-row">
                <td colspan="6" class="pmtab-sub-cell">
                  <div class="pmtab-sub-wrap">
                    <div class="pmtab-sub-header">
                      <h4>Taxas versionadas — {{ displayPaymentMethod(method) }}</h4>
                      <!-- "Nova taxa" no mesmo estilo de "Adicionar método" (pill
                           pequeno azul) — consistência visual entre os 2 níveis
                           de ação (provedor vs taxa). -->
                      <button
                        type="button"
                        class="pmtab-group-add"
                        @click="openFeeModal(method)"
                      >
                        <i class="i-lucide-plus size-[12px]" /> Nova taxa
                      </button>
                    </div>

                    <div v-if="feesByMethodId[method.id]?.loading" class="pmtab-sub-loading">
                      <div class="pmtab-spinner pmtab-spinner--sm" />
                      <span>Carregando taxas...</span>
                    </div>

                    <div v-else-if="(feesByMethodId[method.id]?.fees || []).length === 0" class="pmtab-sub-empty">
                      <i class="i-lucide-percent" />
                      <p>Nenhuma taxa cadastrada. Configure pelo menos uma para cada quantidade de parcelas suportada.</p>
                    </div>

                    <table v-else class="pmtab-sub-table">
                      <thead>
                        <tr>
                          <th>PARCELAS</th>
                          <th>% TAXA</th>
                          <th>R$ FIXO</th>
                          <th>LIQUIDAÇÃO</th>
                          <th>VIGÊNCIA</th>
                          <th></th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr v-for="fee in feesByMethodId[method.id].fees" :key="fee.id"
                            :class="{ 'pmtab-sub-fee--inactive': fee.status !== 'active' }">
                          <td class="pmtab-sub-installments">{{ fee.installments_count }}x</td>
                          <td class="pmtab-sub-percent">{{ formatPercent(fee.fee_percent_basis_points) }}</td>
                          <td class="pmtab-sub-fixed">{{ formatBRL(fee.fee_fixed_cents) }}</td>
                          <td class="pmtab-sub-liquidation">{{ formatDays(fee.liquidation_days) }}</td>
                          <td class="pmtab-sub-vigency">{{ formatDateRange(fee.valid_from, fee.valid_to) }}</td>
                          <td class="pmtab-sub-actions">
                            <!-- Toggle pra inativar taxa — mesma metáfora visual do método pai.
                                 Fee é versionada: uma vez OFF, fica OFF pra sempre (canon
                                 "taxas nunca editadas, sempre nova"). Por isso o toggle só
                                 alterna no sentido ON→OFF — fees inativas mostram switch
                                 disabled (já cumpriram seu ciclo). Tooltip explica regra. -->
                            <Tooltip
                              v-if="fee.status === 'active'"
                              label="Inativar — depois crie nova taxa com vigência atualizada"
                              position="left"
                            >
                              <Toggle
                                :model-value="true"
                                size="sm"
                                @update:model-value="onFeeDeactivate(method, fee.id)"
                              />
                            </Tooltip>
                            <Tooltip
                              v-else
                              label="Taxa inativada — crie uma nova com vigência futura se precisar"
                              position="left"
                            >
                              <Toggle :model-value="false" size="sm" disabled />
                            </Tooltip>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                </td>
              </tr>
              </template> <!-- fim do v-for method in group.methods -->
            </template> <!-- fim do v-for group in methodsByProvider -->
          </tbody>
        </table>
      </div>
    </div>

    <PaymentMethodFormModalV2
      v-if="showMethodModal"
      :show="showMethodModal"
      :existing-method="editingMethod"
      :prefilled-provider="prefilledProvider"
      :bank-accounts="bankAccounts"
      @close="showMethodModal = false"
      @confirm="onMethodSaved"
      @deactivate="onMethodDeactivate"
    />

    <PaymentMethodFeeFormModalV2
      v-if="showFeeModal"
      :show="showFeeModal"
      :payment-method="feeModalMethod"
      @close="showFeeModal = false"
      @confirm="onFeeSaved"
    />

    <!-- Modal padrão de confirmação destrutiva (beclinic_core) — substitui
         window.confirm nativo. Compartilhado entre delete individual e
         delete por provedor (payload em `confirmTarget` decide qual API). -->
    <ConfirmDangerModal
      v-if="confirmTarget"
      v-model:show="showConfirmDelete"
      :title="confirmTarget.title"
      :message="confirmTarget.message"
      :confirm-label="confirmTarget.confirmLabel"
      :loading="confirmDeleteLoading"
      @confirm="executeConfirmDelete"
      @cancel="closeConfirmDelete"
    />
  </div>
</template>

<style scoped lang="scss">
.pmtab { color: rgb(var(--slate-12)); }

.pmtab-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 16px;
  margin-bottom: 20px;
  padding-bottom: 16px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.pmtab-title { margin: 0 0 6px; font-size: 22px; font-weight: 700; }
.pmtab-subtitle {
  margin: 0;
  font-size: 13px;
  color: rgb(var(--slate-10));
  line-height: 1.5;
  max-width: 760px;
}

.pmtab-loading, .pmtab-empty, .pmtab-error {
  display: flex; align-items: center; justify-content: center;
  padding: 80px 24px; text-align: center;
  color: rgb(var(--slate-9)); font-size: 14px; gap: 12px;
}
.pmtab-loading { flex-direction: row; }
.pmtab-empty, .pmtab-error {
  flex-direction: column;
  i { width: 32px; height: 32px; color: rgb(var(--slate-7)); }
  h3 { margin: 0; font-size: 16px; color: rgb(var(--slate-11)); }
  p { margin: 4px 0 0; max-width: 480px; font-size: 13px; }
}
.pmtab-error { color: rgb(var(--ruby-11)); }

.pmtab-spinner {
  width: 18px; height: 18px;
  border: 2px solid rgb(var(--slate-5));
  border-top-color: rgb(var(--blue-9));
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
  &--sm { width: 14px; height: 14px; }
}
@keyframes spin { to { transform: rotate(360deg); } }

.pmtab-content { display: flex; flex-direction: column; gap: 16px; }

.pmtab-table-wrap {
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  overflow: hidden;
  background: rgb(var(--slate-1));
  overflow-x: auto;
}

.pmtab-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
  min-width: 640px;
  /* Padding lateral consistente — reduz o espaço "vazio" à esquerda
     que ficava antes da primeira coluna real (coluna expand removida). */

  thead {
    background: rgb(var(--slate-2));
    th {
      padding: 10px 12px;
      text-align: left;
      font-size: 10px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: rgb(var(--slate-10));
      border-bottom: 1px solid rgb(var(--slate-4));
      white-space: nowrap;
    }
  }

  tbody {
    tr.pmtab-row {
      cursor: pointer;
      border-bottom: 1px solid rgb(var(--slate-3));
      transition: background-color .12s ease;
      &:hover { background: rgba(255, 255, 255, 0.02); }

      &.pmtab-row--inactive {
        opacity: 0.6;
        background: rgba(100, 116, 139, 0.04);
      }

      &.pmtab-row--expanded {
        background: rgba(16, 185, 129, 0.04);
      }
    }

    td { padding: 10px 12px; vertical-align: middle; }
  }
}

/* Larguras (refactor 2026-05-24: removidas colunas EXPAND e NOME, que viviam
   duplicando TIPO. Agora TIPO comporta badge + chip parcelas + sub-linha
   custom name. Chevron de expand migrou pra coluna de ações à direita.)
   Padding-left removido — coluna usa o default do `td` (12px) e alinha
   visualmente com o header "TIPO" e com o título "Formas de Pagamento". */
.pmtab-th-kind, .pmtab-td-kind { min-width: 200px; }

/* Group header: linha que separa visualmente cada provider. Conta com
   ícone (building pra real provider, circle-dot pra "sem provider"),
   nome, contagem de métodos e CTA "+ Adicionar método nesta". */
.pmtab-group-header {
  background: rgb(var(--slate-2));
  border-top: 1px solid rgb(var(--slate-4));
  border-bottom: 1px solid rgb(var(--slate-4));
  cursor: pointer;
  user-select: none;
  transition: background-color 0.12s ease;

  &:hover { background: rgb(var(--slate-3)); }

  td { padding: 0 !important; }
}
.pmtab-group-header-row {
  display: flex; align-items: center; gap: 10px;
  padding: 8px 14px;
}
.pmtab-group-chevron {
  width: 22px; height: 22px;
  padding: 0;
  margin: 0;
  display: inline-flex; align-items: center; justify-content: center;
  background: transparent;
  border: 0;
  color: rgb(var(--slate-10));
  cursor: pointer;
  border-radius: 4px;
  transition: transform 0.18s ease, background-color 0.12s ease, color 0.12s ease;
  i { width: 14px; height: 14px; }

  &:hover { background: rgb(var(--slate-4)); color: rgb(var(--slate-12)); }
  &--collapsed { transform: rotate(-90deg); }
}
.pmtab-group-name {
  display: inline-flex; align-items: center; gap: 6px;
  font-size: 12px; font-weight: 700;
  text-transform: uppercase; letter-spacing: 0.04em;
  color: rgb(var(--slate-12));
  i { color: rgb(var(--blue-10)); }
}
.pmtab-group-label { display: inline-block; }
.pmtab-group-raw {
  font-size: 10px;
  font-weight: 500;
  color: rgb(var(--slate-9));
  text-transform: none;
  letter-spacing: 0;
}
.pmtab-group-rename {
  display: inline-flex; align-items: center; justify-content: center;
  width: 20px; height: 20px;
  background: transparent;
  border: 1px dashed transparent;
  border-radius: 4px;
  color: rgb(var(--slate-9));
  cursor: pointer;
  transition: background-color 0.12s ease, color 0.12s ease, border-color 0.12s ease;

  &:hover {
    background: rgb(var(--blue-3));
    color: rgb(var(--blue-11));
    border-color: rgb(var(--blue-7));
  }
}
.pmtab-group-alias-input {
  font-size: 12px;
  font-weight: 700;
  text-transform: none;
  letter-spacing: 0;
  color: rgb(var(--slate-12));
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--blue-8));
  border-radius: 6px;
  padding: 3px 8px;
  outline: none;
  min-width: 200px;

  &:focus { border-color: rgb(var(--blue-9)); box-shadow: 0 0 0 2px rgb(var(--blue-5) / 0.4); }
  &:disabled { opacity: 0.6; cursor: not-allowed; }
}
.pmtab-group-count {
  font-size: 11px; color: rgb(var(--slate-9));
  font-variant-numeric: tabular-nums;
}
.pmtab-group-add {
  margin-left: auto;
  display: inline-flex; align-items: center; gap: 4px;
  padding: 3px 10px;
  background: transparent;
  border: 1px dashed rgb(var(--blue-7));
  border-radius: 999px;
  color: rgb(var(--blue-11));
  font-size: 11px; font-weight: 500;
  cursor: pointer;
  transition: background 0.12s ease, border-style 0.12s ease;

  &:hover { background: rgba(59, 130, 246, 0.08); border-style: solid; }
}
.pmtab-group-delete {
  display: inline-flex; align-items: center; justify-content: center;
  width: 24px; height: 24px;
  padding: 0;
  background: transparent;
  border: 1px solid transparent;
  border-radius: 6px;
  /* Vermelho por padrão (consistente com .pmtab-icon-btn--danger).
     Tokens --ruby-N (Radix), NÃO --red-N (não existe no projeto). */
  color: rgb(var(--ruby-11));
  cursor: pointer;
  transition: background-color 0.12s ease, color 0.12s ease, border-color 0.12s ease;

  &:hover {
    background: rgb(var(--ruby-3));
    color: rgb(var(--ruby-11));
    border-color: rgb(var(--ruby-7));
  }
}
:root.dark .pmtab-group-header { background: rgba(255, 255, 255, 0.03); }
.pmtab-th-bank, .pmtab-td-bank { width: 160px; color: rgb(var(--slate-10)); }
.pmtab-th-fees, .pmtab-td-fees { width: 140px; }
.pmtab-th-status, .pmtab-td-status { width: 90px; }
.pmtab-th-actions, .pmtab-td-actions { width: 1%; white-space: nowrap; text-align: right; }

/* Grupo de ações inline (edit + delete) — alinhado à direita */
.pmtab-actions-group {
  display: inline-flex; align-items: center; gap: 4px;
}

/* Botão ícone-only na coluna ações da tabela — compacto, sem rótulo.
 * Reduz ruído visual na linha; tooltip nativo + aria-label garantem semântica.
 * Padding 0 — área clicável vem só do width/height. */
.pmtab-icon-btn {
  width: 28px; height: 28px;
  padding: 0;
  margin: 0;
  display: inline-flex; align-items: center; justify-content: center;
  background: transparent;
  border: 1px solid transparent;
  border-radius: 6px;
  color: rgb(var(--slate-10));
  cursor: pointer;
  transition: background-color 0.12s ease, color 0.12s ease, border-color 0.12s ease;
  i { width: 14px; height: 14px; }

  &:hover {
    background: rgb(var(--slate-3));
    color: rgb(var(--blue-11));
    border-color: rgb(var(--slate-4));
  }

  /* Variante danger — vermelho POR PADRÃO (não só hover) pra
   * sinalizar ação destrutiva. Hover intensifica com background.
   * IMPORTANTE: projeto usa --ruby-N (Radix), NÃO --red-N.
   * Tokens --red-* não existem em _next-colors.scss → fallback
   * preto silencioso (bug 1.8.0.13). Validado em
   * app/javascript/dashboard/assets/scss/_next-colors.scss. */
  &--danger {
    color: rgb(var(--ruby-11));
  }
  &--danger:hover {
    background: rgb(var(--ruby-3));
    color: rgb(var(--ruby-11));
    border-color: rgb(var(--ruby-7));
  }
}

/* Variante chevron do icon-btn — usada pra expandir/recolher fees.
 * Rotação 180° quando aberto (vira chevron-up visualmente). */
.pmtab-icon-btn--chevron {
  i { transition: transform 0.18s ease; }
}
.pmtab-icon-btn--chevron-open {
  background: rgb(var(--blue-3));
  color: rgb(var(--blue-11));
  border-color: rgb(var(--blue-7));
  i { transform: rotate(180deg); }
}

/* Badge de TIPO + chip parcelas + custom name agora vivem em
 * @plugins/beclinic_core/frontend/components/PaymentMethodBadge.vue
 * — single source of truth. Não duplicar aqui. */

.pmtab-fees-count {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 4px;
  font-size: 11px;
  font-weight: 600;
  background: rgba(16, 185, 129, 0.12);
  color: rgb(var(--emerald-11));
}
.pmtab-fees-missing {
  font-size: 11px;
  font-style: italic;
  color: rgb(var(--amber-10));
}

/* .pmtab-status (badge ATIVA/INATIVA) removido 2026-05-24 — Toggle inline
 * já comunica o estado. Sem texto redundante. */

/* ── Sub-row (fees) ───────────────────────────────────────── */
.pmtab-sub-row td.pmtab-sub-cell {
  padding: 0;
  background: rgb(var(--slate-2) / 0.5);
  border-bottom: 1px solid rgb(var(--slate-4));
}
/* Fix 2026-05-24: padding-left era 50px (sobra da era em que existia
 * coluna `expand` à esquerda). Coluna removida — agora o conteúdo da
 * sub-tabela alinha com a 1ª coluna real (TIPO). */
.pmtab-sub-wrap {
  padding: 14px 20px 18px 18px;
  border-left: 2px solid rgb(var(--blue-7));
  margin-left: 0;
}
.pmtab-sub-header {
  display: flex; justify-content: space-between; align-items: center;
  margin-bottom: 10px;
  h4 {
    margin: 0;
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: rgb(var(--slate-10));
    font-weight: 600;
  }
}
.pmtab-sub-loading {
  display: flex; gap: 8px; align-items: center;
  padding: 16px;
  font-size: 12px;
  color: rgb(var(--slate-9));
}
.pmtab-sub-empty {
  display: flex; gap: 10px; align-items: flex-start;
  padding: 12px;
  background: rgba(245, 158, 11, 0.06);
  border-radius: 8px;
  i { width: 16px; height: 16px; color: rgb(var(--amber-10)); flex-shrink: 0; margin-top: 2px; }
  p { margin: 0; font-size: 12px; color: rgb(var(--slate-11)); }
}

.pmtab-sub-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
  background: rgb(var(--slate-1));
  border-radius: 8px;
  overflow: hidden;
  border: 1px solid rgb(var(--slate-4));

  thead {
    background: rgb(var(--slate-2));
    th {
      padding: 6px 10px;
      text-align: left;
      font-size: 9px;
      font-weight: 600;
      letter-spacing: 0.05em;
      color: rgb(var(--slate-9));
      border-bottom: 1px solid rgb(var(--slate-4));
    }
  }
  tbody tr {
    border-bottom: 1px solid rgb(var(--slate-3));
    &:last-child { border-bottom: 0; }
    &.pmtab-sub-fee--inactive { opacity: 0.5; }
  }
  td { padding: 6px 10px; vertical-align: middle; }
}

.pmtab-sub-installments { font-weight: 600; color: rgb(var(--slate-12)); width: 70px; }
.pmtab-sub-percent { font-variant-numeric: tabular-nums; width: 80px; color: rgb(var(--slate-11)); }
.pmtab-sub-fixed { font-variant-numeric: tabular-nums; width: 100px; color: rgb(var(--slate-11)); }
.pmtab-sub-liquidation { width: 110px; color: rgb(var(--slate-10)); }
.pmtab-sub-vigency { color: rgb(var(--slate-10)); font-size: 11px; }
.pmtab-sub-actions { width: 1%; white-space: nowrap; text-align: right; }
</style>
