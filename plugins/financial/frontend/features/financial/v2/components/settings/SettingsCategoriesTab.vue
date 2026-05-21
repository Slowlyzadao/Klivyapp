<script setup>
/**
 * Aba Categorias DRE — listagem + CRUD + ativar/desativar (canon §4.1).
 *
 * Categorias iniciais são criadas pelo wizard (16 defaults). Aqui é
 * manutenção contínua: adicionar novas, renomear, ativar/desativar e
 * re-seedar as defaults caso só algumas tenham sido criadas.
 *
 * "Sem categoria" não pode ser excluída nem renomeada.
 */
import { ref, computed, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import FinancialV2 from '../../api/financialV2';
import CategoryFormModalV2 from './CategoryFormModalV2.vue';
import ConfirmDangerModal from '@plugins/beclinic_core/frontend/components/ConfirmDangerModal.vue';
import '@plugins/financial/frontend/styles/financial.scss';

const categories = ref([]);
const loading = ref(false);
const seeding = ref(false);

// Modal de criar/editar (substituiu o form inline pra padronizar com o
// resto do v2 — UX premium consistente entre todos os formulários).
const showModal = ref(false);
const modalMode = ref('create'); // create | edit
const modalInitial = ref(null);
const modalPrefilledKind = ref('receita');

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

// Cada grupo tem cor própria (semântica DRE).
const KINDS = [
  { key: 'receita',        label: 'Receita',         tone: 'emerald', icon: 'i-lucide-trending-up' },
  { key: 'despesa_fixa',   label: 'Despesa Fixa',    tone: 'ruby',    icon: 'i-lucide-receipt' },
  { key: 'custo_variavel', label: 'Custo Variável',  tone: 'amber',   icon: 'i-lucide-zap' },
  { key: 'outra_despesa',  label: 'Outra Despesa',   tone: 'slate',   icon: 'i-lucide-more-horizontal' },
];

const KIND_OPTIONS = KINDS.map(k => ({ value: k.key, label: k.label }));

// Defaults canon §4.1 — usados pelo botão "Restaurar padrão".
const DEFAULT_CATEGORIES = [
  { name: 'Consultas particulares',  kind: 'receita' },
  { name: 'Convênios',               kind: 'receita' },
  { name: 'Vendas de produtos',      kind: 'receita' },
  { name: 'Outras receitas',         kind: 'receita' },
  { name: 'Aluguel',                 kind: 'despesa_fixa' },
  { name: 'Folha + encargos',        kind: 'despesa_fixa' },
  { name: 'Software/Sistemas',       kind: 'despesa_fixa' },
  { name: 'Contador',                kind: 'despesa_fixa' },
  { name: 'Materiais clínicos',      kind: 'custo_variavel' },
  { name: 'Laboratório',             kind: 'custo_variavel' },
  { name: 'Comissões',               kind: 'custo_variavel' },
  { name: 'Taxas de cartão (MDR)',   kind: 'custo_variavel' },
  { name: 'Impostos',                kind: 'outra_despesa' },
  { name: 'Marketing',               kind: 'outra_despesa' },
  { name: 'Manutenção',              kind: 'outra_despesa' },
  { name: 'Quebra de caixa',         kind: 'outra_despesa' },
];

const grouped = computed(() => {
  const groups = {};
  for (const k of KINDS) groups[k.key] = [];
  for (const c of categories.value) {
    if (!groups[c.kind]) groups[c.kind] = [];
    groups[c.kind].push(c);
  }
  return groups;
});

// Names que JÁ existem (pra evitar duplicar no seed).
const existingNamesByKind = computed(() => {
  const set = {};
  for (const k of KINDS) set[k.key] = new Set();
  for (const c of categories.value) {
    set[c.kind]?.add(c.name.trim().toLowerCase());
  }
  return set;
});

// Lista de defaults que ainda NÃO foram criadas.
const missingDefaults = computed(() =>
  DEFAULT_CATEGORIES.filter(d => !existingNamesByKind.value[d.kind]?.has(d.name.toLowerCase()))
);

async function load() {
  loading.value = true;
  try {
    const { data } = await FinancialV2.categories.index();
    categories.value = data?.data || [];
  } catch (err) {
    notifyError(err?.response?.data?.message || 'Erro ao carregar categorias');
  } finally {
    loading.value = false;
  }
}

async function toggleActive(cat) {
  try {
    await FinancialV2.categories.update(cat.id, { category: { active: !cat.active } });
    notifySuccess(cat.active ? 'Categoria desativada.' : 'Categoria ativada.');
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Erro ao atualizar');
  }
}

// Estado do ConfirmDangerModal de exclusão.
const showDeleteModal = ref(false);
const categoryToDelete = ref(null);
const deleting = ref(false);

function destroy(cat) {
  categoryToDelete.value = cat;
  showDeleteModal.value = true;
}

async function confirmDestroy() {
  const cat = categoryToDelete.value;
  if (!cat) return;
  deleting.value = true;
  try {
    await FinancialV2.categories.destroy(cat.id);
    notifySuccess('Categoria removida.');
    showDeleteModal.value = false;
    categoryToDelete.value = null;
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Erro ao remover (categoria pode estar em uso ou ser do sistema)');
  } finally {
    deleting.value = false;
  }
}

function startCreate(prefilledKind = 'receita') {
  modalMode.value = 'create';
  modalInitial.value = null;
  modalPrefilledKind.value = prefilledKind;
  showModal.value = true;
}

function startEdit(cat) {
  modalMode.value = 'edit';
  modalInitial.value = { id: cat.id, name: cat.name, kind: cat.kind };
  showModal.value = true;
}

// Callback do CategoryFormModalV2 — recarrega lista após criar/editar.
function onCategorySaved() {
  load();
}

async function restoreDefaults() {
  if (missingDefaults.value.length === 0) {
    notifySuccess('Todas as categorias padrão já existem.');
    return;
  }
  if (!confirm(`Criar ${missingDefaults.value.length} categoria(s) padrão faltante(s)?\n\nNão sobrescreve nem duplica as que já existem.`)) return;
  seeding.value = true;
  try {
    let created = 0;
    for (const def of missingDefaults.value) {
      try {
        await FinancialV2.categories.create({ category: { name: def.name, kind: def.kind, active: true } });
        created += 1;
      } catch (err) {
        // Continua mesmo se uma falhar (ex.: duplicado por race condition).
        // eslint-disable-next-line no-console
        console.warn('[SettingsCategoriesTab] seed skip', def.name, err?.message);
      }
    }
    notifySuccess(`${created} categoria(s) padrão criada(s).`);
    await load();
  } finally {
    seeding.value = false;
  }
}

onMounted(load);
</script>

<template>
  <div class="set-cat">
    <header class="set-cat__header">
      <div class="set-cat__header-text">
        <h2 class="set-cat__title">Categorias do plano de contas</h2>
        <p class="set-cat__subtitle">
          Define como cada lançamento aparece no DRE. As categorias iniciais são
          criadas pelo wizard. Aqui você adiciona, renomeia, ativa/desativa.
          <strong>"Sem categoria"</strong> não pode ser excluída (canon §4.1).
        </p>
      </div>
      <div class="set-cat__header-actions">
        <BeclinicButton
          v-if="missingDefaults.length > 0"
          variant="faded"
          color="amber"
          icon="i-lucide-package-plus"
          :label="`Restaurar ${missingDefaults.length} padrão`"
          :is-loading="seeding"
          :disabled="seeding"
          @click="restoreDefaults"
        />
        <BeclinicButton
          variant="solid"
          color="blue"
          icon="i-lucide-plus"
          label="Nova categoria"
          @click="startCreate"
        />
      </div>
    </header>

    <div v-if="loading" class="finv2-state">
      <div class="finv2-spinner" />
      <span>Carregando categorias…</span>
    </div>

    <div v-else class="set-cat__grid">
      <section
        v-for="kind in KINDS"
        :key="kind.key"
        class="set-cat__block"
        :class="`set-cat__block--tone-${kind.tone}`"
      >
        <header class="set-cat__block-header">
          <div class="set-cat__block-title">
            <i :class="kind.icon" class="w-4 h-4" />
            <h3>{{ kind.label }}</h3>
          </div>
          <div class="set-cat__block-meta">
            <Badge :label="String(grouped[kind.key]?.length || 0)" :color="kind.tone" size="xs" />
            <BeclinicButton
              size="xs"
              variant="ghost"
              color="slate"
              icon="i-lucide-plus"
              @click="startCreate(kind.key)"
            />
          </div>
        </header>

        <ul v-if="grouped[kind.key]?.length" class="set-cat__list">
          <li
            v-for="cat in grouped[kind.key]"
            :key="cat.id"
            class="set-cat__item"
            :class="{ 'set-cat__item--inactive': !cat.active }"
          >
            <span class="set-cat__name">{{ cat.name }}</span>
            <div class="set-cat__item-actions">
              <BeclinicButton
                size="xs"
                variant="ghost"
                color="slate"
                icon="i-lucide-pencil"
                @click="startEdit(cat)"
              />
              <BeclinicButton
                size="xs"
                variant="ghost"
                color="slate"
                :icon="cat.active ? 'i-lucide-eye-off' : 'i-lucide-eye'"
                @click="toggleActive(cat)"
              />
              <BeclinicButton
                size="xs"
                variant="ghost"
                color="ruby"
                icon="i-lucide-trash-2"
                @click="destroy(cat)"
              />
            </div>
          </li>
        </ul>
        <p v-else class="set-cat__empty">
          <i class="i-lucide-circle-dashed w-3.5 h-3.5" />
          Nenhuma categoria neste tipo. Clique no <strong>+</strong> acima para criar.
        </p>
      </section>
    </div>

    <!-- Modal de criar/editar — padrão visual dos outros modais v2. -->
    <CategoryFormModalV2
      :show="showModal"
      :mode="modalMode"
      :initial="modalInitial"
      :prefilled-kind="modalPrefilledKind"
      @close="showModal = false"
      @confirm="onCategorySaved"
    />

    <!-- Confirmação de exclusão de categoria. -->
    <ConfirmDangerModal
      v-model:show="showDeleteModal"
      title="Excluir categoria?"
      :message="categoryToDelete
        ? `A categoria '${categoryToDelete.name}' será removida. Lançamentos vinculados perdem a classificação (vão pra 'Sem categoria').`
        : ''"
      confirm-label="Excluir categoria"
      :loading="deleting"
      @confirm="confirmDestroy"
    />
  </div>
</template>

<style scoped lang="scss">
.set-cat__header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 16px;
  margin-bottom: 18px;
  flex-wrap: wrap;
}
.set-cat__header-text { flex: 1; min-width: 260px; }
.set-cat__header-actions { display: flex; gap: 8px; flex-wrap: wrap; }

.set-cat__title { margin: 0 0 4px; font-size: 17px; font-weight: 600; color: rgb(var(--slate-12)); }
.set-cat__subtitle {
  margin: 0; color: rgb(var(--slate-9)); font-size: 13px; line-height: 1.5;
  strong { color: rgb(var(--slate-12)); font-weight: 600; }
}

/* Grid de blocos */
.set-cat__grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 14px;
}

.set-cat__block {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 14px;
  display: flex; flex-direction: column; gap: 10px;
}
.set-cat__block-header {
  display: flex; justify-content: space-between; align-items: center;
}
.set-cat__block-title {
  display: inline-flex; align-items: center; gap: 6px;
  h3 {
    margin: 0; font-size: 12px; font-weight: 600;
    color: rgb(var(--slate-12));
    text-transform: uppercase; letter-spacing: 0.04em;
  }
}
.set-cat__block-meta { display: inline-flex; align-items: center; gap: 4px; }

.set-cat__block--tone-emerald i { color: #047857; }
.set-cat__block--tone-ruby    i { color: #b91c1c; }
.set-cat__block--tone-amber   i { color: #b45309; }
.set-cat__block--tone-slate   i { color: rgb(var(--slate-9)); }
:root.dark .set-cat__block--tone-emerald i { color: #6ee7b7; }
:root.dark .set-cat__block--tone-ruby    i { color: #fca5a5; }
:root.dark .set-cat__block--tone-amber   i { color: #fcd34d; }

.set-cat__list { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 4px; }
.set-cat__item {
  display: flex; justify-content: space-between; align-items: center; gap: 8px;
  padding: 5px 8px 5px 10px;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-3));
  border-radius: 8px;
  font-size: 13px;
  color: rgb(var(--slate-12));
}
.set-cat__item--inactive {
  opacity: 0.55;
  .set-cat__name { text-decoration: line-through; }
}
.set-cat__name { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; flex: 1; }
.set-cat__item-actions { display: inline-flex; gap: 2px; flex-shrink: 0; }

.set-cat__empty {
  margin: 0;
  display: flex; align-items: center; justify-content: center; gap: 6px;
  padding: 14px 12px;
  text-align: center;
  color: rgb(var(--slate-9));
  font-size: 12px;
  font-style: italic;
  border: 1px dashed rgb(var(--slate-4));
  border-radius: 8px;
  strong { color: rgb(var(--slate-11)); font-weight: 700; font-style: normal; }
}
</style>
