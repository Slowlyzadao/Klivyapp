<script setup>
/**
 * Modal de criar/editar categoria DRE — canon §4.1.
 *
 * Substitui o form inline na SettingsCategoriesTab. Padrão visual
 * idêntico aos outros modais v2 (ManualEntry, PayExpense, ReceivePayment):
 * mobile fullscreen, desktop dialog centralizado, FormSelect, BeclinicButton.
 *
 * Props:
 *   - show: Boolean
 *   - mode: 'create' | 'edit'
 *   - initial: { id?, name?, kind? } (preencher ao editar)
 *   - prefilledKind: string (pré-seleciona tipo no create, ex.: 'receita')
 *
 * Eventos:
 *   - close
 *   - confirm: { category } (objeto retornado pelo backend)
 */
import { ref, watch, computed } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import FinancialV2 from '../../api/financialV2';

const props = defineProps({
  show: { type: Boolean, default: false },
  mode: { type: String, default: 'create' }, // 'create' | 'edit'
  initial: { type: Object, default: null },
  prefilledKind: { type: String, default: 'receita' },
});

const emit = defineEmits(['close', 'confirm']);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const KIND_OPTIONS = [
  { value: 'receita',        label: 'Receita' },
  { value: 'despesa_fixa',   label: 'Despesa Fixa' },
  { value: 'custo_variavel', label: 'Custo Variável' },
  { value: 'outra_despesa',  label: 'Outra Despesa' },
];

const KIND_HINT = {
  receita:        'Aparece em "Receita Bruta" no DRE. Ex.: Consultas particulares, Convênios, Vendas.',
  despesa_fixa:   'Aparece em "(–) Despesas Fixas" no DRE. Ex.: Aluguel, Folha + encargos, Sistema.',
  custo_variavel: 'Aparece em "(–) Custos Variáveis" no DRE. Ex.: Materiais, Laboratório, Comissões.',
  outra_despesa:  'Aparece em "(–) Outras Despesas" no DRE. Ex.: Impostos, Marketing, Estornos.',
};

const form = ref({ id: null, name: '', kind: 'receita' });
const submitting = ref(false);

const isEdit = computed(() => props.mode === 'edit');
const titleText = computed(() => (isEdit.value ? 'Editar categoria' : 'Nova categoria'));
const titleIcon = computed(() => (isEdit.value ? 'i-lucide-pencil' : 'i-lucide-plus'));
const ctaLabel = computed(() => (isEdit.value ? 'Salvar alterações' : 'Criar categoria'));

const validForSubmit = computed(() => !submitting.value && form.value.name?.trim().length > 0);

const kindHint = computed(() => KIND_HINT[form.value.kind] || '');

watch(
  () => props.show,
  (val) => {
    if (!val) return;
    if (isEdit.value && props.initial) {
      form.value = {
        id: props.initial.id,
        name: props.initial.name || '',
        kind: props.initial.kind || 'receita',
      };
    } else {
      form.value = { id: null, name: '', kind: props.prefilledKind || 'receita' };
    }
    submitting.value = false;
  },
  { immediate: true },
);

async function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  try {
    const payload = { category: { name: form.value.name.trim(), kind: form.value.kind } };
    let response;
    if (isEdit.value) {
      response = await FinancialV2.categories.update(form.value.id, payload);
      notifySuccess('Categoria atualizada.');
    } else {
      payload.category.active = true;
      response = await FinancialV2.categories.create(payload);
      notifySuccess('Categoria criada.');
    }
    emit('confirm', response?.data);
    emit('close');
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Erro ao salvar categoria');
  } finally {
    submitting.value = false;
  }
}

function close() {
  if (submitting.value) return;
  emit('close');
}
</script>

<template>
  <Teleport to="body">
    <div v-if="show" class="cfm-v2__backdrop" @click.self="close">
      <div class="cfm-v2__modal" role="dialog" aria-modal="true">
        <header class="cfm-v2__header">
          <div class="cfm-v2__header-text">
            <h2 class="cfm-v2__title">
              <i :class="titleIcon" class="cfm-v2__title-icon" />
              {{ titleText }}
            </h2>
            <p class="cfm-v2__subtitle">
              Categorias controlam como o lançamento aparece no DRE (canon §4.1).
            </p>
          </div>
          <BeclinicButton
            size="sm"
            variant="ghost"
            color="slate"
            icon="i-lucide-x"
            :disabled="submitting"
            @click="close"
          />
        </header>

        <div class="cfm-v2__body">
          <label class="cfm-v2__field">
            <span class="cfm-v2__field-label">Nome *</span>
            <input
              v-model="form.name"
              type="text"
              class="finv2-input"
              placeholder="Ex.: Consultas particulares, Aluguel, Marketing, Estornos"
              autofocus
              @keyup.enter="submit"
            />
          </label>

          <label class="cfm-v2__field">
            <span class="cfm-v2__field-label">Tipo (DRE) *</span>
            <FormSelect v-model="form.kind" :options="KIND_OPTIONS" />
            <p v-if="kindHint" class="cfm-v2__field-hint">
              <i class="i-lucide-info w-3.5 h-3.5" />
              {{ kindHint }}
            </p>
          </label>
        </div>

        <footer class="cfm-v2__footer">
          <BeclinicButton
            variant="ghost"
            color="slate"
            label="Cancelar"
            :disabled="submitting"
            @click="close"
          />
          <BeclinicButton
            variant="solid"
            color="teal"
            icon="i-lucide-check"
            :label="ctaLabel"
            :is-loading="submitting"
            :disabled="!validForSubmit"
            @click="submit"
          />
        </footer>
      </div>
    </div>
  </Teleport>
</template>

<style scoped lang="scss">
/* Padrão dos modais v2 — backdrop + modal shell. */
.cfm-v2__backdrop {
  position: fixed; inset: 0;
  background: rgba(15, 23, 42, 0.6);
  backdrop-filter: blur(4px);
  display: flex; align-items: stretch; justify-content: center;
  z-index: 9999; padding: 0;
}
@media (min-width: 640px) {
  .cfm-v2__backdrop { align-items: center; padding: 16px; }
}

.cfm-v2__modal {
  width: 100%; height: 100%;
  background: rgb(var(--slate-1));
  border: 0; border-radius: 0;
  display: flex; flex-direction: column;
  overflow: hidden;
}
@media (min-width: 640px) {
  .cfm-v2__modal {
    width: min(520px, 100%);
    max-height: calc(100vh - 32px);
    height: auto;
    border: 1px solid rgb(var(--slate-4));
    border-radius: 16px;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
  }
}

.cfm-v2__header {
  display: flex; justify-content: space-between; align-items: flex-start;
  gap: 12px; padding: 18px 20px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.cfm-v2__title {
  margin: 0; font-size: 17px; font-weight: 600;
  color: rgb(var(--slate-12));
  display: flex; align-items: center; gap: 8px;
}
.cfm-v2__title-icon { width: 18px; height: 18px; color: rgb(var(--blue-9)); }
.cfm-v2__subtitle { margin: 4px 0 0; font-size: 13px; color: rgb(var(--slate-9)); }

.cfm-v2__body {
  flex: 1; overflow-y: auto;
  padding: 18px 20px;
  display: flex; flex-direction: column; gap: 14px;
}

.cfm-v2__field { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.cfm-v2__field-label {
  font-size: 12px; font-weight: 500; color: rgb(var(--slate-11));
}
.cfm-v2__field-hint {
  display: flex; align-items: flex-start; gap: 6px;
  margin: 4px 0 0;
  padding: 8px 10px;
  border-radius: 8px;
  background: rgb(var(--slate-2));
  border-left: 3px solid rgb(var(--blue-8));
  color: rgb(var(--slate-11));
  font-size: 12px;
  line-height: 1.4;
  i { color: rgb(var(--blue-9)); flex-shrink: 0; margin-top: 2px; }
}

.cfm-v2__footer {
  display: flex; justify-content: flex-end; gap: 8px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-4));
}
@media (max-width: 640px) {
  .cfm-v2__footer { flex-direction: column-reverse; }
  .cfm-v2__footer > * { width: 100%; }
}
</style>
