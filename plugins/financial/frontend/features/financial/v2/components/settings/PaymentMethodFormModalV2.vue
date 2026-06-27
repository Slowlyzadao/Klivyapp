<script setup>
/**
 * Modal de cadastrar/editar Forma de Pagamento.
 *
 * `kind` é frozen_attribute no backend — não permite mudar após criação.
 * UI desabilita o select em modo edit pra evitar tentativas frustradas.
 *
 * Props:
 *   - show: Boolean
 *   - existingMethod: Object | null
 *   - bankAccounts: Array
 *
 * Eventos:
 *   - close, confirm, deactivate(methodId)
 */
import { ref, computed, watch } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import Checkbox from '@plugins/beclinic_core/frontend/components/Checkbox.vue';
import Toggle from '@plugins/beclinic_core/frontend/components/Toggle.vue';
import FinancialV2 from '../../api/financialV2';

const props = defineProps({
  show: { type: Boolean, default: false },
  existingMethod: { type: Object, default: null },
  // `prefilledProvider` vem quando o operador clica "+ Adicionar método"
  // dentro de um grupo de provider na lista. Pré-popula o campo provider
  // pra ele só preencher kind/name/taxas (menos fricção pra cadastrar 5
  // métodos da Stone em sequência).
  prefilledProvider: { type: String, default: null },
  bankAccounts: { type: Array, default: () => [] },
});

const emit = defineEmits(['close', 'confirm', 'deactivate']);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const form = ref({
  kind: 'pix',
  name: '',
  provider: '',
  default_bank_account_id: null,
  supports_installments: false,
  max_installments: 1,
  status: 'active',
  // F2.5 — modelo de repasse de MDR. Quando true, ApproveBudget infla o
  // amount_cents das parcelas geradas para que a clínica receba o valor
  // base cheio depois da operadora reter o MDR. PIX/Dinheiro/Boleto sem
  // taxa naturalmente não precisam — flag fica false por padrão.
  passes_fee_to_patient: false,
  // Política de baixa (2026-05-27): manual | on_confirm | on_due_date.
  // Default coerente com o kind inicial (pix → on_confirm).
  settlement_mode: 'on_confirm',
});
const submitting = ref(false);

const isEdit = computed(() => !!props.existingMethod);

const KIND_OPTIONS = [
  { value: 'dinheiro',             label: 'Dinheiro' },
  { value: 'pix',                  label: 'PIX' },
  { value: 'debito',               label: 'Cartão de Débito' },
  { value: 'credito',              label: 'Cartão de Crédito' },
  { value: 'boleto',               label: 'Boleto' },
  { value: 'transferencia',        label: 'Transferência Bancária' },
  { value: 'convenio',             label: 'Convênio' },
  { value: 'parcelamento_proprio', label: 'Parcelamento Próprio' },
];

// Kinds que naturalmente suportam parcelas — não força mas pré-sugere
const INSTALLMENT_FRIENDLY = new Set(['credito', 'parcelamento_proprio', 'boleto']);

// F2.5 — kinds que normalmente têm MDR (taxa retida pela operadora). Em clínicas
// que repassam o custo ao cliente (padrão de mercado), esses kinds já vêm com
// `passes_fee_to_patient = true` pré-marcado. Operador pode desligar caso a caso.
// PIX/Dinheiro/Boleto/Convênio/Transferência ficam false porque normalmente
// não têm MDR — não há o que repassar.
const PASSTHROUGH_FRIENDLY = new Set(['credito', 'debito']);

// Política de baixa. `on_due_date` (baixa automática) SÓ é oferecida p/ cartão
// — a adquirente garante o repasse. Boleto/convênio/parcelamento próprio
// dependem do pagador honrar, então só manual/on_confirm (backend rejeita
// on_due_date neles). Espelha PaymentMethod::AUTO_SETTLE_ALLOWED_KINDS.
const AUTO_SETTLE_KINDS = new Set(['credito', 'debito']);
const SETTLEMENT_MODE_OPTIONS = [
  { value: 'manual', label: 'Manual — operador clica "Receber"' },
  { value: 'on_confirm', label: 'À vista — baixa ao aprovar (PIX/dinheiro/débito)' },
  { value: 'on_due_date', label: 'Automática — baixa na data de vencimento (cartão)' },
];

// Opções visíveis dependem do kind: on_due_date só p/ crédito/débito.
const settlementModeOptions = computed(() =>
  SETTLEMENT_MODE_OPTIONS.filter(
    o => o.value !== 'on_due_date' || AUTO_SETTLE_KINDS.has(form.value.kind),
  ),
);

// Default de baixa por kind: crédito → automática na data; à vista
// (dinheiro/PIX/débito) → ao confirmar; resto → manual.
function suggestSettlementMode(kind) {
  if (kind === 'credito') return 'on_due_date';
  if (['dinheiro', 'pix', 'debito'].includes(kind)) return 'on_confirm';
  return 'manual';
}

const bankAccountOptions = computed(() => {
  return [
    { value: null, label: 'Nenhuma (decidir no recebimento)' },
    ...props.bankAccounts.map(b => ({ value: b.id, label: b.name })),
  ];
});

// Auto-fill do `name` baseado em (kind + provider) em CREATE.
// Resolve a fricção "Name já está em uso" quando operador queria PIX em
// 3 providers (Cielo/Stone/Asaas) e tudo virava só "PIX" → colisão de
// nome no canon (unique scope: name).
//
// Lógica:
//   - kind=pix          + provider=Cielo → "PIX Cielo"
//   - kind=pix          + provider=''    → "PIX"
//   - kind=credito      + provider=Stone → "Cartão de Crédito Stone"
//
// `userEditedName` rastreia se o operador digitou algo — se sim, não
// sobrescreve (respeita a escolha manual).
// `showCustomName` controla se o campo editável aparece (default escondido —
// reduz fricção do "Tipo: Boleto, Nome: Boleto" redundante).
// IMPORTANTE: declarados ANTES do watch `immediate: true` abaixo pra evitar
// TDZ error ("Cannot access 'X' before initialization").
const userEditedName = ref(false);
const showCustomName = ref(false);

function resetNameToAuto() {
  userEditedName.value = false;
  showCustomName.value = false;
  form.value.name = buildSuggestedName();
}

function buildSuggestedName() {
  const kindLabel = KIND_OPTIONS.find(k => k.value === form.value.kind)?.label || '';
  const provider = (form.value.provider || '').trim();
  return provider ? `${kindLabel} ${provider}`.trim() : kindLabel;
}

function maybeAutoFillName() {
  if (isEdit.value) return;
  if (userEditedName.value) return; // operador já escolheu nome custom
  form.value.name = buildSuggestedName();
}

watch(
  () => props.show,
  (val) => {
    if (!val) return;
    submitting.value = false;
    if (props.existingMethod) {
      form.value = {
        kind: props.existingMethod.kind,
        name: props.existingMethod.name || '',
        provider: props.existingMethod.provider || '',
        default_bank_account_id: props.existingMethod.default_bank_account_id,
        supports_installments: !!props.existingMethod.supports_installments,
        max_installments: props.existingMethod.max_installments || 1,
        status: props.existingMethod.status,
        passes_fee_to_patient: !!props.existingMethod.passes_fee_to_patient,
        settlement_mode: props.existingMethod.settlement_mode || suggestSettlementMode(props.existingMethod.kind),
      };
      // Em modo edit: se o nome existente é diferente do que seria
      // auto-gerado, é nome custom → abre o campo e marca como editado
      // pra preservar.
      const auto = buildSuggestedName();
      const isCustom = form.value.name && form.value.name !== auto;
      userEditedName.value = isCustom;
      showCustomName.value = isCustom;
    } else {
      form.value = {
        kind: 'pix',
        name: '',
        // Pré-preenche provider quando vem do "+ Adicionar método" de um
        // grupo (Stone, Cielo, etc). Null/undefined cai pra '' (Sem provider).
        provider: props.prefilledProvider || '',
        default_bank_account_id: null,
        supports_installments: false,
        max_installments: 1,
        status: 'active',
        passes_fee_to_patient: false,
        settlement_mode: 'on_confirm', // kind default 'pix' → à vista
      };
      // Reset dos flags — modo create começa limpo com nome auto
      userEditedName.value = false;
      showCustomName.value = false;
      // Dispara sugestão inicial (PIX + provider se houver)
      form.value.name = buildSuggestedName();
    }
  },
  { immediate: true },
);

// Quando muda o kind em modo CREATE, sugere defaults + atualiza nome
watch(
  () => form.value.kind,
  (kind) => {
    if (isEdit.value) return;
    const installmentFriendly = INSTALLMENT_FRIENDLY.has(kind);
    form.value.supports_installments = installmentFriendly;
    if (!installmentFriendly) form.value.max_installments = 1;
    else if (form.value.max_installments < 2) form.value.max_installments = 12;
    // F2.5 — pré-marca repasse de taxa para Crédito/Débito (padrão de mercado).
    // Operador pode desligar antes de salvar se a clínica absorve a MDR.
    form.value.passes_fee_to_patient = PASSTHROUGH_FRIENDLY.has(kind);
    // Sugere a política de baixa coerente com o kind (e garante que um
    // on_due_date herdado não sobreviva a uma troca p/ kind não-cartão).
    form.value.settlement_mode = suggestSettlementMode(kind);
    maybeAutoFillName();
  },
);

// Quando muda provider em CREATE, atualiza sugestão de nome
watch(
  () => form.value.provider,
  () => maybeAutoFillName(),
);

// Detecta digitação manual no nome — se o operador editou pra algo
// diferente da sugestão, marca como custom e para de auto-overwrite.
function onNameInput(e) {
  form.value.name = e.target.value;
  userEditedName.value = e.target.value !== buildSuggestedName();
}

watch(
  () => form.value.supports_installments,
  (val) => {
    if (!val) form.value.max_installments = 1;
    else if (form.value.max_installments < 2) form.value.max_installments = 12;
  },
);

const validForSubmit = computed(() => {
  if (submitting.value) return false;
  if (!form.value.kind) return false;
  if (!form.value.name?.trim()) return false;
  if (form.value.supports_installments && (form.value.max_installments < 1 || form.value.max_installments > 24)) return false;
  return true;
});

async function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  try {
    const payload = {
      payment_method: {
        kind: form.value.kind,
        name: form.value.name.trim(),
        provider: form.value.provider?.trim() || null,
        default_bank_account_id: form.value.default_bank_account_id,
        supports_installments: form.value.supports_installments,
        max_installments: form.value.supports_installments ? form.value.max_installments : 1,
        status: form.value.status,
        passes_fee_to_patient: form.value.passes_fee_to_patient,
        settlement_mode: form.value.settlement_mode,
      },
    };
    if (isEdit.value) {
      // Backend rejeita mudança de kind via frozen_attribute, mas excluímos
      // do permit pra não acidentar 422. Aqui também removemos do payload.
      delete payload.payment_method.kind;
      await FinancialV2.paymentMethods.update(props.existingMethod.id, payload);
      notifySuccess('Forma de pagamento atualizada.');
    } else {
      await FinancialV2.paymentMethods.create(payload);
      notifySuccess('Forma de pagamento cadastrada.');
    }
    emit('confirm');
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || err?.response?.data?.message || 'Erro ao salvar');
  } finally {
    submitting.value = false;
  }
}

function close() {
  if (submitting.value) return;
  emit('close');
}

// `onClickDeactivate` removido em 2026-05-23 — o caminho de inativar
// agora é único (dropdown Status no body + Salvar). Parent ainda escuta
// `deactivate` por compat se aparecer chamada externa, mas o modal não
// dispara mais.

const titleText = computed(() => isEdit.value ? `Editar — ${props.existingMethod?.name}` : 'Nova forma de pagamento');

// Toggle boolean ↔ status string ('active' | 'inactive'). Toggle vive no
// header do modal pra ser a primeira ação visível (alta importância).
const isActive = computed({
  get: () => form.value.status === 'active',
  set: (val) => { form.value.status = val ? 'active' : 'inactive'; },
});
</script>

<template>
  <Teleport to="body">
    <div v-if="show" class="pmm-v2__backdrop">
      <div class="pmm-v2__modal" role="dialog" aria-modal="true">
        <header class="pmm-v2__header">
          <div class="pmm-v2__header-text">
            <h2 class="pmm-v2__title">
              <i class="i-lucide-credit-card pmm-v2__title-icon" />
              {{ titleText }}
            </h2>
            <p class="pmm-v2__subtitle">
              Taxas (% e R$ fixo por nº de parcelas) ficam na sub-vista expansível, não aqui.
            </p>
          </div>
          <div class="pmm-v2__header-actions">
            <!-- Toggle de status no topo (alta visibilidade) — opera ativo/inativo
                 sem precisar dropdown. v-model bool → string 'active'/'inactive'.
                 Cor: brand (azul Klivy canon) — padrão Toggle, não passa. -->
            <Toggle
              v-model="isActive"
              :label="isActive ? 'Ativo' : 'Inativo'"
              size="md"
            />
            <BeclinicButton size="sm" variant="ghost" color="slate" icon="i-lucide-x" :disabled="submitting" @click="close" />
          </div>
        </header>

        <div class="pmm-v2__body">
          <!-- Reordenado 2026-05-23: Provedor é o "container" mental
               (contratei a Cielo → cadastro quais kinds eles oferecem).
               Vem primeiro pra refletir o fluxo natural do operador. -->
          <label class="pmm-v2__field">
            <span class="pmm-v2__field-label">
              Provedor
              <span class="pmm-v2__field-hint-mini">(opcional — quem processa a transação)</span>
            </span>
            <input
              v-model="form.provider"
              type="text"
              class="finv2-input"
              placeholder="Ex.: Cielo, Stone, PagSeguro, Mercado Pago"
              maxlength="80"
            />
          </label>

          <label class="pmm-v2__field">
            <span class="pmm-v2__field-label">
              Tipo <span class="pmm-v2__required">*</span>
              <span v-if="isEdit" class="pmm-v2__field-hint-mini">(imutável após criação)</span>
            </span>
            <FormSelect v-model="form.kind" :options="KIND_OPTIONS" :disabled="isEdit" />
          </label>

          <label class="pmm-v2__field">
            <span class="pmm-v2__field-label">Conta bancária padrão</span>
            <FormSelect v-model="form.default_bank_account_id" :options="bankAccountOptions" />
          </label>

          <!-- Nome auto-derivado: kind label (+ provider se houver).
               Mostra preview do que será salvo + link "Personalizar"
               pra quem quiser nome custom ("Caixinha", "PIX do sócio"). -->
          <div class="pmm-v2__name-preview">
            <div class="pmm-v2__name-preview-info">
              <span class="pmm-v2__name-preview-label">Nome no sistema</span>
              <strong class="pmm-v2__name-preview-value">{{ form.name || '—' }}</strong>
            </div>
            <button
              v-if="!showCustomName"
              type="button"
              class="pmm-v2__customize-link"
              @click="showCustomName = true"
            >
              <i class="i-lucide-pencil size-[12px]" /> Personalizar
            </button>
          </div>
          <label v-if="showCustomName" class="pmm-v2__field">
            <span class="pmm-v2__field-label">
              Nome personalizado <span class="pmm-v2__required">*</span>
              <button type="button" class="pmm-v2__customize-link pmm-v2__customize-link--reset" @click="resetNameToAuto">
                Voltar ao automático
              </button>
            </span>
            <input
              :value="form.name"
              type="text"
              class="finv2-input"
              placeholder="Ex.: Caixinha, PIX Sócio, Cielo (loja Centro)"
              maxlength="120"
              @input="onNameInput"
            />
            <span class="pmm-v2__field-hint-mini">Nome visível na hora de receber/escolher forma.</span>
          </label>

          <div class="pmm-v2__checkbox-wrap">
            <Checkbox v-model="form.supports_installments" label="Aceita parcelamento" />
          </div>

          <label v-if="form.supports_installments" class="pmm-v2__field">
            <span class="pmm-v2__field-label">Parcela máxima (1–24)</span>
            <input v-model.number="form.max_installments" type="number" min="1" max="24" class="finv2-input" />
            <span class="pmm-v2__field-hint-mini">
              Cada quantidade pode ter sua própria taxa (configurada na sub-vista).
            </span>
          </label>

          <div class="pmm-v2__passthrough-block">
            <Checkbox v-model="form.passes_fee_to_patient" label="Repassar taxa ao cliente" />
            <p class="pmm-v2__passthrough-hint">
              Quando ativo, o valor das parcelas é inflado para que a clínica receba o valor base cheio.
              <span class="pmm-v2__passthrough-example">
                Ex.: parcela base R$ 200 com taxa 3,5% → cliente paga R$ 207,25 / clínica recebe R$ 200,00.
              </span>
            </p>
          </div>

          <!-- Política de baixa (2026-05-27). on_due_date só aparece p/ cartão. -->
          <label class="pmm-v2__field">
            <span class="pmm-v2__field-label">Baixa do recebimento</span>
            <FormSelect v-model="form.settlement_mode" :options="settlementModeOptions" />
            <span class="pmm-v2__field-hint-mini">
              <template v-if="form.settlement_mode === 'on_due_date'">
                Cartão: a parcela vira "Recebido" sozinha na data — a adquirente garante o repasse, sem clicar "Receber".
              </template>
              <template v-else-if="form.settlement_mode === 'on_confirm'">
                À vista: a parcela já entra "Recebido" ao aprovar o orçamento (precisa de conta bancária padrão definida acima).
              </template>
              <template v-else>
                Manual: o operador dá baixa clicando "Receber". Use para boleto, convênio e parcelamento próprio — neles a clínica assume o risco de cobrança.
              </template>
            </span>
          </label>

          <!-- Dropdown Status removido (2026-05-23) — substituído pelo
               Toggle no header do modal (alta visibilidade, 1 clique). -->
        </div>

        <footer class="pmm-v2__footer">
          <!-- Botão "Inativar" do footer removido (2026-05-23) — redundante
               com o dropdown "Status" do body. Operador agora muda Status
               pra "Inativo" e salva. Caminho único = menos confusão.
               Reativar continua via chip inline na lista (1 clique). -->
          <div class="pmm-v2__footer-actions">
            <BeclinicButton variant="ghost" color="slate" label="Cancelar" :disabled="submitting" @click="close" />
            <BeclinicButton
              variant="solid"
              color="blue"
              icon="i-lucide-check"
              :label="isEdit ? 'Salvar alterações' : 'Cadastrar'"
              :is-loading="submitting"
              :disabled="!validForSubmit"
              @click="submit"
            />
          </div>
        </footer>
      </div>
    </div>
  </Teleport>
</template>

<style scoped lang="scss">
.pmm-v2__backdrop {
  position: fixed; inset: 0;
  background: rgba(15, 23, 42, 0.6);
  backdrop-filter: blur(4px);
  display: flex; align-items: stretch; justify-content: center;
  z-index: 9999;
}
@media (min-width: 640px) {
  .pmm-v2__backdrop { align-items: center; padding: 16px; }
}

.pmm-v2__modal {
  width: 100%; height: 100%;
  background: rgb(var(--slate-1));
  display: flex; flex-direction: column;
  overflow: hidden;
}
@media (min-width: 640px) {
  .pmm-v2__modal {
    width: min(560px, 100%);
    max-height: calc(100vh - 32px);
    height: auto;
    border: 1px solid rgb(var(--slate-4));
    border-radius: 16px;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
  }
}

.pmm-v2__header {
  display: flex; justify-content: space-between; align-items: flex-start;
  gap: 12px; padding: 18px 20px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.pmm-v2__header-text { min-width: 0; flex: 1; }
.pmm-v2__header-actions {
  display: flex; align-items: center; gap: 12px;
  flex-shrink: 0;
}
.pmm-v2__title {
  margin: 0; font-size: 16px; font-weight: 600;
  color: rgb(var(--slate-12));
  display: flex; align-items: center; gap: 8px;
}
.pmm-v2__title-icon { width: 18px; height: 18px; color: rgb(var(--emerald-9)); }
.pmm-v2__subtitle { margin: 6px 0 0; font-size: 12px; color: rgb(var(--slate-9)); }

.pmm-v2__body {
  flex: 1; overflow-y: auto;
  padding: 18px 20px;
  display: flex; flex-direction: column; gap: 14px;
}

.pmm-v2__row {
  display: grid; grid-template-columns: 1fr 1fr; gap: 12px;
  @media (max-width: 480px) { grid-template-columns: 1fr; }
}

.pmm-v2__field { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.pmm-v2__field-label {
  font-size: 12px; font-weight: 500; color: rgb(var(--slate-11));
  display: flex; align-items: center; gap: 4px;
}
.pmm-v2__required { color: rgb(var(--ruby-9)); }
.pmm-v2__field-hint-mini {
  font-size: 11px;
  color: rgb(var(--slate-9));
  font-weight: 400;
  font-style: italic;
}

/* Preview do nome auto-gerado — bloco discreto que mostra qual `name`
   será salvo no banco. Operador raramente precisa personalizar, mas o
   link "Personalizar" abre o campo quando faz sentido (Caixinha, etc). */
.pmm-v2__name-preview {
  display: flex; align-items: center; justify-content: space-between; gap: 12px;
  padding: 10px 14px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
}
.pmm-v2__name-preview-info {
  display: flex; flex-direction: column; gap: 2px; min-width: 0;
}
.pmm-v2__name-preview-label {
  font-size: 10.5px; font-weight: 600;
  text-transform: uppercase; letter-spacing: 0.04em;
  color: rgb(var(--slate-9));
}
.pmm-v2__name-preview-value {
  font-size: 13.5px; font-weight: 600;
  color: rgb(var(--slate-12));
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.pmm-v2__customize-link {
  display: inline-flex; align-items: center; gap: 4px;
  padding: 4px 10px;
  background: transparent;
  border: 1px dashed rgb(var(--blue-7));
  border-radius: 999px;
  color: rgb(var(--blue-11));
  font-size: 11px; font-weight: 500;
  cursor: pointer;
  transition: background 0.12s ease, border-style 0.12s ease;
  flex-shrink: 0;
  &:hover { background: rgba(59, 130, 246, 0.08); border-style: solid; }
  &--reset {
    margin-left: auto;
    border: 0;
    padding: 0 6px;
    background: transparent;
    color: rgb(var(--slate-9));
    font-style: italic;
    &:hover { color: rgb(var(--slate-12)); background: transparent; }
  }
}

.pmm-v2__checkbox-wrap {
  display: flex;
  align-items: center;
  padding: 4px 0;
}

// F2.5 — Bloco vertical do toggle "Repassar taxa ao cliente": checkbox em cima,
// descrição em parágrafo de largura total embaixo. Visual mais limpo que a
// versão horizontal (texto vazava à direita do label quebrado em 2 linhas).
.pmm-v2__passthrough-block {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 10px 12px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
}

.pmm-v2__passthrough-hint {
  margin: 0;
  padding-left: 28px;  // alinha o texto com o label do checkbox (não com a caixa)
  color: rgb(var(--slate-10));
  font-size: 12px;
  line-height: 1.45;
}

.pmm-v2__passthrough-example {
  display: block;
  margin-top: 2px;
  color: rgb(var(--slate-11));
}

.pmm-v2__footer {
  display: flex; justify-content: space-between; gap: 8px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-4));
  @media (max-width: 480px) {
    flex-direction: column-reverse;
    .pmm-v2__footer-actions {
      flex-direction: column-reverse;
      width: 100%;
      > * { width: 100%; }
    }
  }
}
.pmm-v2__footer-actions { display: flex; gap: 8px; margin-left: auto; }
</style>
