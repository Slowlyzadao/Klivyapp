<script setup>
/**
 * Modal de configurar preço/categoria DRE para um AgendaService.
 *
 * Wireframe 2026-05-23: cada AgendaService cadastrado em /agenda/settings é
 * "o que se faz" (nome + duração). Aqui se define "quanto custa + como
 * contabilizar" — preço particular/convênio + categoria DRE específica
 * (geralmente um L3 sob "Procedimentos Particulares") + regra de comissão.
 *
 * Auto-sugestão: ao abrir pra um serviço sem pricing, tenta encontrar uma
 * DreCategory leaf (L3/L4) com nome igual/similar e pré-seleciona.
 * Ex: AgendaService "Endodontia" → sugere DreCategory "Endodontia" (L3
 * sob "Procedimentos Particulares").
 *
 * Props:
 *   - show: Boolean
 *   - agendaService: Object — { id, name, duration_minutes, color, ... }
 *   - existingPricing: Object | null — pricing atual (se houver)
 *   - dreCategories: Array — todas as categorias da conta (filtradas pelo parent)
 *
 * Eventos:
 *   - close
 *   - confirm: { pricing }  (objeto retornado pelo backend)
 *   - deactivate: { agendaServiceId } (clicou em "Remover pricing")
 */
import { ref, watch, computed } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import FinancialV2 from '../../api/financialV2';
import ConfirmDangerModalV2 from '../ConfirmDangerModalV2.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  agendaService: { type: Object, required: true },
  existingPricing: { type: Object, default: null },
  dreCategories: { type: Array, default: () => [] },
});

const emit = defineEmits(['close', 'confirm', 'deactivate', 'category-created']);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const form = ref({
  particular_price_reais: '',
  convenio_price_reais: '',
  financial_dre_category_id: null,
  tuss_code: '',
  internal_code: '',
});
const submitting = ref(false);

// Toggle "Serviço gratuito" (avaliação inicial, revisão, cortesia).
// Quando ON: zera os 2 campos de preço, desabilita inputs, mostra hint
// explicativo. Quando OFF: re-habilita inputs (mantém valores anteriores).
// Categoria DRE continua obrigatória — operador escolhe categoria de
// "cortesia/marketing" pra rastrear na DRE mesmo com R$ 0.
const isFreeService = ref(false);

function toggleFreeService() {
  isFreeService.value = !isFreeService.value;
  if (isFreeService.value) {
    form.value.particular_price_reais = '0';
    form.value.convenio_price_reais = '';
  } else if (form.value.particular_price_reais === '0') {
    form.value.particular_price_reais = '';
  }
}

// ── Criar nova categoria DRE inline ──────────────────────────────────
// Reduz fricção quando o operador descobre que a categoria DRE certa pro
// novo serviço não existe ainda. Em vez de sair do modal, ir em Plano de
// Contas, criar, voltar e recomeçar — abre um sub-form aqui, cria via POST,
// auto-seleciona no dropdown e segue o fluxo.
const showNewCatForm = ref(false);
const newCat = ref({ name: '', parent_id: null });
const creatingCategory = ref(false);

// Pais possíveis: categorias receita level < 4 (canon: MAX_LEVEL=4),
// não system_default. Operador escolhe ONDE colocar a nova (ex.: "Receita
// Clínica > Procedimentos Particulares > [Toxina Botulínica]").
const parentCategoryOptions = computed(() => {
  return props.dreCategories
    .filter(c => c.kind === 'receita')
    .filter(c => (c.level || 1) < 4)
    .filter(c => !c.system_default)
    .filter(c => c.active !== false)
    .sort((a, b) => (a.path || '').localeCompare(b.path || ''))
    .map(c => ({ value: c.id, label: c.path ? buildPathLabel(c) : c.name }));
});

// Monta path completo "Receita › Procedimentos Particulares" pra o
// dropdown deixar claro a hierarquia onde vai entrar.
function buildPathLabel(cat) {
  if (!cat.path) return cat.name;
  const ids = cat.path.split('/').filter(Boolean).map(Number);
  return ids
    .map(id => props.dreCategories.find(c => c.id === id)?.name)
    .filter(Boolean)
    .join(' › ');
}

function openNewCatForm() {
  // Pré-preenche nome com o do serviço (auto-sugestão)
  newCat.value = {
    name: props.agendaService?.name || '',
    parent_id: null,
  };
  showNewCatForm.value = true;
}

function cancelNewCatForm() {
  showNewCatForm.value = false;
  newCat.value = { name: '', parent_id: null };
}

const canCreateCategory = computed(() => {
  if (creatingCategory.value) return false;
  return newCat.value.name?.trim() && newCat.value.parent_id;
});

async function submitNewCategory() {
  if (!canCreateCategory.value) return;
  creatingCategory.value = true;
  try {
    const payload = {
      category: {
        name: newCat.value.name.trim(),
        kind: 'receita', // sempre receita: serviço gera receita por definição
        parent_id: newCat.value.parent_id,
        active: true,
      },
    };
    const { data: createdCategory } = await FinancialV2.categories.create(payload);
    notifySuccess(`Categoria "${createdCategory.name}" criada.`);
    // Avisa o parent pra atualizar a lista de dreCategories (prop ↑)
    emit('category-created', createdCategory);
    // Auto-seleciona a nova categoria no select principal
    form.value.financial_dre_category_id = createdCategory.id;
    cancelNewCatForm();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Erro ao criar categoria');
  } finally {
    creatingCategory.value = false;
  }
}

const isEdit = computed(() => !!props.existingPricing);

// ── Sugestões de categoria DRE ───────────────────────────────────────
//
// Só categorias "folha" (sem filhos, level 3 ou 4) podem receber lançamento.
// Filtra pra só receitas (kind=receita) — categorias de despesa não fazem
// sentido como destino de serviço prestado.
const leafCategories = computed(() => {
  return props.dreCategories
    .filter(c => c.kind === 'receita')
    .filter(c => !c.has_children && c.active !== false)
    .filter(c => !c.system_default);
});

// Auto-sugestão por match de nome (case + accent insensitive)
function normalizeText(s) {
  return String(s).toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim();
}

function suggestCategoryId() {
  if (!props.agendaService?.name) return null;
  const target = normalizeText(props.agendaService.name);
  // 1ª tentativa: match exato
  let match = leafCategories.value.find(c => normalizeText(c.name) === target);
  if (match) return match.id;
  // 2ª tentativa: match parcial (categoria contém nome do serviço ou vice-versa)
  match = leafCategories.value.find(c => {
    const cn = normalizeText(c.name);
    return cn.includes(target) || target.includes(cn);
  });
  return match?.id || null;
}

const categoryOptions = computed(() => {
  // Apenas o nome — sem sufixo "(nível X)" que era ruído visual.
  // Operador sabe pela navegação da árvore (Plano de Contas) qual nível
  // está. O breadcrumb completo abaixo do select já mostra o contexto
  // hierárquico ("Receita Clínica › Procedimentos Particulares › Endodontia").
  return leafCategories.value
    .sort((a, b) => (a.path || '').localeCompare(b.path || ''))
    .map(c => ({ value: c.id, label: c.name }));
});

const titleText = computed(() => isEdit.value ? `Editar preço — ${props.agendaService?.name}` : `Configurar preço — ${props.agendaService?.name}`);

const validForSubmit = computed(() => {
  if (submitting.value) return false;
  const price = parseFloat(form.value.particular_price_reais);
  return Number.isFinite(price) && price >= 0 && form.value.financial_dre_category_id;
});

// Quando o modal abre, popula o form
watch(
  () => props.show,
  (val) => {
    if (!val) return;
    if (props.existingPricing) {
      const particular = props.existingPricing.particular_price_cents || 0;
      const convenio = props.existingPricing.convenio_price_cents || 0;
      form.value = {
        particular_price_reais: particular ? (particular / 100).toFixed(2) : '0',
        convenio_price_reais: convenio ? (convenio / 100).toFixed(2) : '',
        financial_dre_category_id: props.existingPricing.financial_dre_category_id,
        tuss_code: props.existingPricing.tuss_code || '',
        internal_code: props.existingPricing.internal_code || '',
      };
      // Detecta pricing previamente cadastrado como grátis (ambos zeros)
      isFreeService.value = particular === 0 && convenio === 0;
    } else {
      // Auto-sugestão pra novo pricing
      form.value = {
        particular_price_reais: '',
        convenio_price_reais: '',
        financial_dre_category_id: suggestCategoryId(),
        tuss_code: '',
        internal_code: '',
      };
      isFreeService.value = false;
    }
    submitting.value = false;
  },
  { immediate: true },
);

// Categoria atualmente selecionada — usado pra mostrar breadcrumb (caminho hierárquico).
const selectedCategory = computed(() => {
  if (!form.value.financial_dre_category_id) return null;
  return props.dreCategories.find(c => c.id === form.value.financial_dre_category_id);
});

// Caminho hierárquico legível ("Receita Clínica > Procedimentos Particulares > Endodontia")
const selectedCategoryPath = computed(() => {
  const cat = selectedCategory.value;
  if (!cat || !cat.path) return '';
  const ids = cat.path.split('/').filter(Boolean).map(Number);
  return ids
    .map(id => props.dreCategories.find(c => c.id === id)?.name)
    .filter(Boolean)
    .join(' › ');
});

async function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  try {
    const payload = {
      service_pricing: {
        particular_price_cents: Math.round(parseFloat(form.value.particular_price_reais) * 100),
        financial_dre_category_id: form.value.financial_dre_category_id,
      },
    };
    if (form.value.convenio_price_reais && parseFloat(form.value.convenio_price_reais) > 0) {
      payload.service_pricing.convenio_price_cents = Math.round(parseFloat(form.value.convenio_price_reais) * 100);
    }
    if (form.value.tuss_code) payload.service_pricing.tuss_code = form.value.tuss_code;
    if (form.value.internal_code) payload.service_pricing.internal_code = form.value.internal_code;

    const response = await FinancialV2.servicePricings.upsert(props.agendaService.id, payload);
    notifySuccess(isEdit.value ? 'Preço atualizado.' : 'Preço configurado.');
    emit('confirm', response?.data);
    emit('close');
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Erro ao salvar preço');
  } finally {
    submitting.value = false;
  }
}

function close() {
  if (submitting.value) return;
  emit('close');
}

// Substitui o `confirm()` nativo por modal padronizado.
const deactivateConfirmOpen = ref(false);

function onClickDeactivate() {
  if (submitting.value) return;
  deactivateConfirmOpen.value = true;
}

function confirmDeactivate() {
  deactivateConfirmOpen.value = false;
  emit('deactivate', { agendaServiceId: props.agendaService.id });
  emit('close');
}
</script>

<template>
  <Teleport to="body">
    <div v-if="show" class="spm-v2__backdrop">
      <div class="spm-v2__modal" role="dialog" aria-modal="true">
        <header class="spm-v2__header">
          <div class="spm-v2__header-text">
            <h2 class="spm-v2__title">
              <i class="i-lucide-receipt spm-v2__title-icon" />
              {{ titleText }}
            </h2>
            <p class="spm-v2__subtitle">
              <span class="spm-v2__service-meta">
                <i class="i-lucide-clock" />
                {{ agendaService?.duration_minutes }} min
                <span v-if="agendaService?.requires_room" class="spm-v2__chip">Exige sala</span>
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

        <div class="spm-v2__body">
          <!-- Categoria DRE -->
          <label class="spm-v2__field">
            <span class="spm-v2__field-label">
              Categoria DRE <span class="spm-v2__required">*</span>
              <button
                v-if="!showNewCatForm"
                type="button"
                class="spm-v2__new-cat-link"
                @click="openNewCatForm"
              >
                <i class="i-lucide-plus size-[12px]" />
                Criar nova
              </button>
            </span>
            <FormSelect
              v-model="form.financial_dre_category_id"
              :options="categoryOptions"
              placeholder="Selecione onde aparece no DRE"
              :disabled="showNewCatForm"
            />
            <p v-if="selectedCategoryPath && !showNewCatForm" class="spm-v2__field-hint">
              <i class="i-lucide-folder-tree" />
              <strong>{{ selectedCategoryPath }}</strong>
            </p>
            <p v-else-if="!selectedCategoryPath && !showNewCatForm" class="spm-v2__field-hint spm-v2__field-hint--warn">
              <i class="i-lucide-alert-triangle" />
              Sem categoria, o serviço não pode ser lançado financeiramente.
            </p>
          </label>

          <!-- Sub-form: criar nova categoria DRE sem sair do modal -->
          <div v-if="showNewCatForm" class="spm-v2__new-cat">
            <div class="spm-v2__new-cat-header">
              <strong>
                <i class="i-lucide-folder-plus size-[14px]" />
                Nova categoria DRE
              </strong>
              <span class="spm-v2__field-hint-mini">
                Cria como subcategoria de um grupo existente. Sempre tipo "Receita" porque vai vincular a serviço.
              </span>
            </div>
            <div class="spm-v2__new-cat-fields">
              <label class="spm-v2__field">
                <span class="spm-v2__field-label">Nome <span class="spm-v2__required">*</span></span>
                <input
                  v-model="newCat.name"
                  type="text"
                  class="finv2-input"
                  placeholder="Ex.: Toxina Botulínica, Harmonização Facial"
                />
              </label>
              <label class="spm-v2__field">
                <span class="spm-v2__field-label">Dentro de <span class="spm-v2__required">*</span></span>
                <FormSelect
                  v-model="newCat.parent_id"
                  :options="parentCategoryOptions"
                  placeholder="Selecione o grupo onde a nova categoria vai entrar"
                />
              </label>
            </div>
            <div class="spm-v2__new-cat-actions">
              <BeclinicButton
                variant="ghost"
                color="slate"
                size="sm"
                label="Cancelar"
                :disabled="creatingCategory"
                @click="cancelNewCatForm"
              />
              <BeclinicButton
                variant="solid"
                color="blue"
                size="sm"
                icon="i-lucide-check"
                label="Criar categoria"
                :is-loading="creatingCategory"
                :disabled="!canCreateCategory"
                @click="submitNewCategory"
              />
            </div>
          </div>

          <!-- Toggle "Serviço gratuito" — pra avaliação inicial, revisão
               pós-cirúrgica, consulta de cortesia. Zera preços e desabilita
               os inputs quando ligado. Categoria DRE continua obrigatória. -->
          <div class="spm-v2__free-toggle">
            <label class="spm-v2__free-toggle-row">
              <div class="spm-v2__free-toggle-info">
                <strong>
                  <i class="i-lucide-gift size-[14px]" />
                  Serviço gratuito
                </strong>
                <span class="spm-v2__field-hint-mini">
                  Avaliação inicial, revisão pós-cirúrgica, cortesia. Zera os preços e mantém categoria pra rastreio no DRE.
                </span>
              </div>
              <button
                type="button"
                class="spm-v2__toggle-switch"
                :class="{ 'spm-v2__toggle-switch--on': isFreeService }"
                @click="toggleFreeService"
              >
                <span class="spm-v2__toggle-thumb" />
              </button>
            </label>
          </div>

          <!-- Preços -->
          <div class="spm-v2__row">
            <label class="spm-v2__field">
              <span class="spm-v2__field-label">
                Preço Particular (R$) <span class="spm-v2__required">*</span>
              </span>
              <input
                v-model="form.particular_price_reais"
                type="number"
                step="0.01"
                min="0"
                class="finv2-input"
                placeholder="0,00"
                :disabled="isFreeService"
                @keyup.enter="submit"
              />
            </label>

            <label class="spm-v2__field">
              <span class="spm-v2__field-label">
                Preço Convênio (R$) <span class="spm-v2__optional">opcional</span>
              </span>
              <input
                v-model="form.convenio_price_reais"
                type="number"
                step="0.01"
                min="0"
                class="finv2-input"
                placeholder="0,00"
                :disabled="isFreeService"
              />
              <span class="spm-v2__field-hint-mini">
                {{ isFreeService ? 'Desabilitado pra serviço gratuito' : 'Vazio = não aceita convênio' }}
              </span>
            </label>
          </div>

          <!-- Códigos opcionais -->
          <details class="spm-v2__details">
            <summary>Códigos contábeis (opcional)</summary>
            <div class="spm-v2__row spm-v2__details-content">
              <label class="spm-v2__field">
                <span class="spm-v2__field-label">Código TUSS</span>
                <input
                  v-model="form.tuss_code"
                  type="text"
                  class="finv2-input"
                  placeholder="Ex.: 81000027"
                  maxlength="32"
                />
                <span class="spm-v2__field-hint-mini">Tabela TUSS (convênios médicos)</span>
              </label>
              <label class="spm-v2__field">
                <span class="spm-v2__field-label">Código Interno</span>
                <input
                  v-model="form.internal_code"
                  type="text"
                  class="finv2-input"
                  placeholder="Ex.: PROC-001"
                  maxlength="32"
                />
              </label>
            </div>
          </details>
        </div>

        <footer class="spm-v2__footer">
          <BeclinicButton
            v-if="isEdit"
            variant="ghost"
            color="ruby"
            label="Remover pricing"
            icon="i-lucide-trash-2"
            :disabled="submitting"
            @click="onClickDeactivate"
          />
          <div class="spm-v2__footer-actions">
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
              :label="isEdit ? 'Salvar alterações' : 'Configurar preço'"
              :is-loading="submitting"
              :disabled="!validForSubmit"
              @click="submit"
            />
          </div>
        </footer>
      </div>
    </div>
  </Teleport>

  <ConfirmDangerModalV2
    v-if="deactivateConfirmOpen"
    :show="deactivateConfirmOpen"
    title="Remover pricing financeiro?"
    confirm-label="Sim, remover"
    tone="warn"
    @close="deactivateConfirmOpen = false"
    @confirm="confirmDeactivate"
  >
    Remover pricing de <strong>{{ agendaService?.name }}</strong>.
    <br>
    O serviço permanece na agenda, mas <strong>não poderá ser lançado financeiramente</strong>
    até ser reconfigurado.
  </ConfirmDangerModalV2>
</template>

<style scoped lang="scss">
.spm-v2__backdrop {
  position: fixed; inset: 0;
  background: rgba(15, 23, 42, 0.6);
  backdrop-filter: blur(4px);
  display: flex; align-items: stretch; justify-content: center;
  z-index: 9999;
}
@media (min-width: 640px) {
  .spm-v2__backdrop { align-items: center; padding: 16px; }
}

.spm-v2__modal {
  width: 100%; height: 100%;
  background: rgb(var(--slate-1));
  display: flex; flex-direction: column;
  overflow: hidden;
}
@media (min-width: 640px) {
  .spm-v2__modal {
    width: min(560px, 100%);
    max-height: calc(100vh - 32px);
    height: auto;
    border: 1px solid rgb(var(--slate-4));
    border-radius: 16px;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
  }
}

.spm-v2__header {
  display: flex; justify-content: space-between; align-items: flex-start;
  gap: 12px; padding: 18px 20px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.spm-v2__title {
  margin: 0; font-size: 16px; font-weight: 600;
  color: rgb(var(--slate-12));
  display: flex; align-items: center; gap: 8px;
}
.spm-v2__title-icon { width: 18px; height: 18px; color: rgb(var(--emerald-9)); }
.spm-v2__subtitle { margin: 6px 0 0; font-size: 13px; color: rgb(var(--slate-9)); }
.spm-v2__service-meta {
  display: inline-flex; align-items: center; gap: 6px;
  i { width: 14px; height: 14px; }
}
.spm-v2__chip {
  display: inline-block;
  margin-left: 6px;
  padding: 2px 8px;
  border-radius: 8px;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-11));
  font-size: 11px;
}

.spm-v2__body {
  flex: 1; overflow-y: auto;
  padding: 18px 20px;
  display: flex; flex-direction: column; gap: 16px;
}

.spm-v2__row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;

  @media (max-width: 480px) { grid-template-columns: 1fr; }
}

.spm-v2__field { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.spm-v2__field-label {
  font-size: 12px; font-weight: 500; color: rgb(var(--slate-11));
  display: flex; align-items: center; gap: 4px;
}
.spm-v2__required { color: rgb(var(--ruby-9)); }
.spm-v2__optional {
  color: rgb(var(--slate-8));
  font-size: 10px;
  font-weight: 400;
  font-style: italic;
}

.spm-v2__field-hint {
  display: flex; align-items: center; gap: 6px;
  margin: 4px 0 0;
  padding: 8px 10px;
  border-radius: 8px;
  background: rgb(var(--slate-2));
  border-left: 3px solid rgb(var(--blue-8));
  color: rgb(var(--slate-11));
  font-size: 12px;
  line-height: 1.4;
  i { width: 14px; height: 14px; color: rgb(var(--blue-9)); flex-shrink: 0; }
  strong { color: rgb(var(--slate-12)); }

  &--warn {
    border-left-color: rgb(var(--amber-8));
    i { color: rgb(var(--amber-10)); }
  }
}
.spm-v2__field-hint-mini {
  font-size: 11px;
  color: rgb(var(--slate-9));
}

/* Link "+ Criar nova" ao lado do label da categoria — descobrível mas sutil */
.spm-v2__new-cat-link {
  display: inline-flex; align-items: center; gap: 3px;
  margin-left: auto;
  padding: 2px 8px;
  background: transparent;
  border: 1px dashed rgb(var(--blue-7));
  border-radius: 999px;
  color: rgb(var(--blue-11));
  font-size: 11px; font-weight: 500;
  cursor: pointer;
  transition: background 0.12s ease, border-color 0.12s ease;
  &:hover { background: rgba(59, 130, 246, 0.08); border-style: solid; }
}

/* Sub-form de criar categoria — bloco destacado em azul (mesma família
   visual do toggle "Serviço gratuito" pra coerência). */
.spm-v2__new-cat {
  margin-top: -4px;
  background: rgba(59, 130, 246, 0.06);
  border: 1px solid rgba(59, 130, 246, 0.22);
  border-radius: 10px;
  padding: 14px;
  display: flex; flex-direction: column; gap: 12px;
}
.spm-v2__new-cat-header {
  display: flex; flex-direction: column; gap: 2px;
  strong {
    display: inline-flex; align-items: center; gap: 6px;
    font-size: 13px; color: rgb(var(--slate-12));
    i { color: rgb(var(--blue-10)); }
  }
}
.spm-v2__new-cat-fields {
  display: flex; flex-direction: column; gap: 10px;
}
.spm-v2__new-cat-actions {
  display: flex; justify-content: flex-end; gap: 8px;
}
:root.dark .spm-v2__new-cat {
  background: rgba(59, 130, 246, 0.15);
  border-color: rgba(59, 130, 246, 0.32);
}

/* Toggle "Serviço gratuito" — bloco destacado em azul (intencional, não erro) */
.spm-v2__free-toggle {
  background: rgba(59, 130, 246, 0.06);
  border: 1px solid rgba(59, 130, 246, 0.18);
  border-radius: 10px;
  padding: 12px 14px;
}
.spm-v2__free-toggle-row {
  display: flex; align-items: center; justify-content: space-between; gap: 12px;
  cursor: pointer;
}
.spm-v2__free-toggle-info {
  display: flex; flex-direction: column; gap: 2px; flex: 1;
  line-height: 1.35; /* default era ~1.5 — tava espaçado demais pro contexto */
  strong {
    display: inline-flex; align-items: center; gap: 6px;
    font-size: 13px; line-height: 1.2;
    color: rgb(var(--slate-12));
    i { color: rgb(var(--blue-10)); }
  }
  .spm-v2__field-hint-mini { line-height: 1.35; }
}
:root.dark .spm-v2__free-toggle {
  background: rgba(59, 130, 246, 0.15);
  border-color: rgba(59, 130, 246, 0.32);
}

/* Switch on/off — mesmo padrão de SettingsTabServices.vue */
.spm-v2__toggle-switch {
  position: relative;
  width: 44px; height: 24px;
  background: rgb(var(--slate-6));
  border-radius: 12px;
  border: 0;
  padding: 0;
  cursor: pointer;
  transition: background 0.2s ease;
  flex-shrink: 0;
}
.spm-v2__toggle-switch--on {
  background: rgb(var(--blue-9));
}
.spm-v2__toggle-thumb {
  position: absolute;
  top: 3px; left: 3px;
  width: 18px; height: 18px;
  background: #fff;
  border-radius: 50%;
  box-shadow: 0 2px 4px rgba(0,0,0,0.2);
  transition: transform 0.2s cubic-bezier(0.4, 0, 0.2, 1);
}
.spm-v2__toggle-switch--on .spm-v2__toggle-thumb {
  transform: translateX(20px);
}

.spm-v2__details {
  margin-top: 4px;
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;

  summary {
    padding: 10px 14px;
    cursor: pointer;
    font-size: 12px;
    color: rgb(var(--slate-11));
    user-select: none;

    &:hover { color: rgb(var(--slate-12)); }
  }
}
.spm-v2__details-content {
  padding: 0 14px 14px;
}

.spm-v2__footer {
  display: flex; justify-content: space-between; gap: 8px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-4));

  @media (max-width: 480px) {
    flex-direction: column-reverse;
    .spm-v2__footer-actions {
      flex-direction: column-reverse;
      width: 100%;
      > * { width: 100%; }
    }
  }
}
.spm-v2__footer-actions {
  display: flex; gap: 8px; margin-left: auto;
}
</style>
