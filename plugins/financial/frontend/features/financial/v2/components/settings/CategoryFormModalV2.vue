<script setup>
/**
 * Modal de criar/editar categoria DRE — canon §4.1.
 *
 * Refatorado 2026-05-23 (Fase 2B - Plano de Contas hierárquico):
 * - Aceita `parent_category` prop pra contextualizar criação de Sub/Item
 * - Mostra info do parent + level calculado quando criando filho
 * - Bloqueia troca de `kind` em edit (frozen no contexto da hierarquia)
 * - Esconde campo `kind` em create de filho (herda do parent automaticamente)
 *
 * Props:
 *   - show: Boolean
 *   - mode: 'create' | 'edit'
 *   - initial: { id?, name?, kind?, parent_id? } (preencher ao editar)
 *   - prefilledKind: string (pré-seleciona tipo no create root)
 *   - parentCategory: Object | null — quando criando filho. Determina:
 *       · level (parent.level + 1)
 *       · kind (herdado de parent.kind)
 *       · parent_id (parent.id)
 *
 * Eventos:
 *   - close
 *   - confirm: { category }
 */
import { ref, watch, computed } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import FinancialV2 from '../../api/financialV2';

const props = defineProps({
  show: { type: Boolean, default: false },
  mode: { type: String, default: 'create' },
  initial: { type: Object, default: null },
  prefilledKind: { type: String, default: 'receita' },
  parentCategory: { type: Object, default: null },
});

const emit = defineEmits(['close', 'confirm']);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

// Kinds canon — Receita vs grupos de Despesa.
// Quando criando filho, herda do parent (campo escondido).
// Quando criando root, usuário escolhe entre Receita ou Despesa.
const KIND_OPTIONS_ROOT = [
  { value: 'receita',        label: 'Receita' },
  { value: 'outra_despesa',  label: 'Despesa (genérica)' },
  { value: 'despesa_fixa',   label: 'Despesa Fixa' },
  { value: 'custo_variavel', label: 'Custo Variável' },
];

const KIND_HINT = {
  receita:        'Aparece em "Receita Bruta" no DRE.',
  despesa_fixa:   'Aparece em "(–) Despesas Fixas" no DRE.',
  custo_variavel: 'Aparece em "(–) Custos Variáveis" no DRE.',
  outra_despesa:  'Aparece em "(–) Outras Despesas" no DRE.',
};

const form = ref({ id: null, name: '', kind: 'receita', parent_id: null });
const submitting = ref(false);

const isEdit = computed(() => props.mode === 'edit');
const isCreatingChild = computed(() => !isEdit.value && props.parentCategory);
const calculatedLevel = computed(() => {
  if (isCreatingChild.value) return (props.parentCategory.level || 1) + 1;
  if (isEdit.value && props.initial?.parent_id) return (props.initial.level || 1);
  return 1;
});

const levelLabel = computed(() => {
  switch (calculatedLevel.value) {
    case 1: return 'Grupo';
    case 2: return 'Subgrupo';
    case 3: return 'Item';
    case 4: return 'Subcategoria';
    default: return 'Categoria';
  }
});

const titleText = computed(() => {
  if (isEdit.value) return 'Editar categoria';
  if (isCreatingChild.value) {
    return `Nova ${levelLabel.value.toLowerCase()} de "${props.parentCategory.name}"`;
  }
  return 'Novo grupo';
});

const titleIcon = computed(() => (isEdit.value ? 'i-lucide-pencil' : 'i-lucide-plus'));
const ctaLabel = computed(() => (isEdit.value ? 'Salvar alterações' : 'Criar categoria'));

const validForSubmit = computed(() => !submitting.value && form.value.name?.trim().length > 0);

const kindHint = computed(() => KIND_HINT[form.value.kind] || '');

// Quando o modal abre, popula o form de acordo com o contexto.
watch(
  () => props.show,
  (val) => {
    if (!val) return;
    if (isEdit.value && props.initial) {
      form.value = {
        id: props.initial.id,
        name: props.initial.name || '',
        kind: props.initial.kind || 'receita',
        parent_id: props.initial.parent_id || null,
      };
    } else if (isCreatingChild.value) {
      // Criando filho — herda kind do parent + parent_id
      form.value = {
        id: null,
        name: '',
        kind: props.parentCategory.kind,
        parent_id: props.parentCategory.id,
      };
    } else {
      // Criando root
      form.value = {
        id: null,
        name: '',
        kind: props.prefilledKind || 'receita',
        parent_id: null,
      };
    }
    submitting.value = false;
  },
  { immediate: true },
);

async function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  try {
    const payload = {
      category: {
        name: form.value.name.trim(),
        kind: form.value.kind,
        parent_id: form.value.parent_id,
      },
    };
    let response;
    if (isEdit.value) {
      // Em edit, NÃO mexer em kind/parent_id (canon imutabilidade hierárquica
      // — mover categoria é trabalho separado, fora de "renomear")
      const editPayload = { category: { name: payload.category.name } };
      response = await FinancialV2.categories.update(form.value.id, editPayload);
      notifySuccess('Categoria atualizada.');
    } else {
      payload.category.active = true;
      response = await FinancialV2.categories.create(payload);
      notifySuccess(isCreatingChild.value ? `${levelLabel.value} criado(a).` : 'Grupo criado.');
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
    <div v-if="show" class="cfm-v2__backdrop">
      <div class="cfm-v2__modal" role="dialog" aria-modal="true">
        <header class="cfm-v2__header">
          <div class="cfm-v2__header-text">
            <h2 class="cfm-v2__title">
              <i :class="titleIcon" class="cfm-v2__title-icon" />
              {{ titleText }}
            </h2>
            <p class="cfm-v2__subtitle">
              <span v-if="isCreatingChild" class="cfm-v2__breadcrumb">
                <strong>Nível {{ calculatedLevel }}</strong> ({{ levelLabel }}) — filho de
                "{{ parentCategory.name }}"
              </span>
              <span v-else>
                Categorias do plano de contas (canon §4.1). Hierarquia até 4 níveis.
              </span>
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
              :placeholder="isCreatingChild
                ? 'Ex.: Procedimentos Particulares, Endodontia, Aluguel...'
                : 'Ex.: Receita Clínica, Pessoal, Marketing...'"
              autofocus
              @keyup.enter="submit"
            />
          </label>

          <!-- Tipo (DRE) — só pra root NEW. Em edit ou child, herdado/imutável. -->
          <label v-if="!isCreatingChild && !isEdit" class="cfm-v2__field">
            <span class="cfm-v2__field-label">Tipo (DRE) *</span>
            <FormSelect v-model="form.kind" :options="KIND_OPTIONS_ROOT" />
            <p v-if="kindHint" class="cfm-v2__field-hint">
              <i class="i-lucide-info w-3.5 h-3.5" />
              {{ kindHint }}
            </p>
          </label>

          <!-- Info-only: parent + level (quando criando child) -->
          <div v-if="isCreatingChild" class="cfm-v2__info-block">
            <div class="cfm-v2__info-line">
              <span class="cfm-v2__info-label">Pai:</span>
              <span class="cfm-v2__info-value">{{ parentCategory.name }}</span>
            </div>
            <div class="cfm-v2__info-line">
              <span class="cfm-v2__info-label">Tipo herdado:</span>
              <span class="cfm-v2__info-value">{{ form.kind }}</span>
            </div>
            <div class="cfm-v2__info-line">
              <span class="cfm-v2__info-label">Nível:</span>
              <span class="cfm-v2__info-value">{{ calculatedLevel }} ({{ levelLabel }})</span>
            </div>
          </div>

          <!-- Info-only: imutabilidade em edit -->
          <div v-if="isEdit" class="cfm-v2__info-block cfm-v2__info-block--warn">
            <i class="i-lucide-lock w-3.5 h-3.5" />
            <span>
              Editar apenas o <strong>nome</strong>. Tipo e posição na hierarquia são imutáveis
              (canon: snapshot histórico de lançamentos vinculados).
            </span>
          </div>
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
            color="blue"
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
.cfm-v2__breadcrumb {
  display: inline-block;
  font-size: 12px;
  color: rgb(var(--slate-11));
  strong { color: rgb(var(--blue-10)); }
}

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

.cfm-v2__info-block {
  padding: 12px 14px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  display: flex;
  flex-direction: column;
  gap: 6px;
  font-size: 12px;

  &--warn {
    flex-direction: row;
    align-items: flex-start;
    gap: 8px;
    border-left: 3px solid rgb(var(--amber-8));
    color: rgb(var(--slate-11));
    line-height: 1.5;
    i { color: rgb(var(--amber-10)); flex-shrink: 0; margin-top: 2px; }
  }
}
.cfm-v2__info-line {
  display: flex;
  gap: 8px;
  color: rgb(var(--slate-11));
}
.cfm-v2__info-label {
  min-width: 90px;
  color: rgb(var(--slate-9));
}
.cfm-v2__info-value {
  font-weight: 500;
  color: rgb(var(--slate-12));
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
