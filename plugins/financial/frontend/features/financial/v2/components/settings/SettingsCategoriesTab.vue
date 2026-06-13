<script setup>
/**
 * Tela "Plano de Contas" — wireframe 2026-05-23.
 *
 * Refator total da Fase 2B: substitui a versão flat (4 colunas por kind) por
 * hierarquia 4 níveis em 2 colunas (Receitas / Despesas), conforme canon
 * `mapa-financeiro.json` step 2.
 *
 * Estrutura visual:
 *   ┌──────────── RECEITAS ────────────┐  ┌──────── DESPESAS ────────┐
 *   │ ▼ 1. Receita Clínica   [+ Sub]   │  │ ▼ 1. Pessoal    [+ Item]│
 *   │   ├ 1.1 Particulares  [+ Item]  │  │   ├ Salários              │
 *   │   │   └ Endodontia     [Inativar]│  │   ├ Pró-labore            │
 *   │   │   └ Implantodontia [...]    │  │   └ ...                   │
 *   │   └ 1.2 Convênios     [+ Item]  │  │ ▼ 2. Ocupação   [+ Item]│
 *   │ ▼ 2. Receita Não Clínica         │  │   ...                     │
 *   └──────────────────────────────────┘  └───────────────────────────┘
 *
 * Categorias `system_default = true` ficam ocultas (Estornos, Taxa de
 * Maquininha, Sem categoria). Drill-down expand/collapse por nó. Botões
 * "+ Sub" / "+ Item" abrem o CategoryFormModalV2 com parent_id pré-preenchido.
 */
import { ref, computed, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import FinancialV2 from '../../api/financialV2';
import CategoryFormModalV2 from './CategoryFormModalV2.vue';
import CategoryTreeNodeV2 from './CategoryTreeNodeV2.vue';
import ConfirmDangerModal from '@plugins/beclinic_core/frontend/components/ConfirmDangerModal.vue';
import '@plugins/financial/frontend/styles/financial.scss';

const categories = ref([]);
const loading = ref(false);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

// ── Modal de criar/editar ─────────────────────────────────────────────
const showModal = ref(false);
const modalMode = ref('create');
const modalInitial = ref(null);
const modalPrefilledKind = ref('receita');
const modalParentCategory = ref(null);

// ── Modal de confirmação de delete ───────────────────────────────────
const showDeleteModal = ref(false);
const categoryToDelete = ref(null);
const deleting = ref(false);

// ── Modal de confirmação de "restaurar padrão" ───────────────────────
const showRestoreModal = ref(false);
const restoring = ref(false);

// ── Carga inicial ─────────────────────────────────────────────────────
async function load() {
  loading.value = true;
  try {
    // include_system=false → filtra Estornos/Taxa de Maquininha/Sem categoria
    const { data } = await FinancialV2.categories.index({ include_system: 'false' });
    categories.value = data?.data || [];
  } catch (err) {
    notifyError(err?.response?.data?.message || 'Erro ao carregar categorias');
  } finally {
    loading.value = false;
  }
}

onMounted(load);

// ── Monta árvore a partir do array flat ──────────────────────────────
// Usa `parent_id` pra agrupar. Ordena por position dentro de cada nível.
// Retorna apenas roots (parent_id = null) com children aninhados.
function buildTree(flatList) {
  const byParent = new Map();
  for (const cat of flatList) {
    const pid = cat.parent_id || 'root';
    if (!byParent.has(pid)) byParent.set(pid, []);
    byParent.get(pid).push({ ...cat, children: [] });
  }
  for (const arr of byParent.values()) {
    arr.sort((a, b) => (a.position ?? 0) - (b.position ?? 0) || a.name.localeCompare(b.name, 'pt-BR'));
  }
  function attach(node) {
    const kids = byParent.get(node.id) || [];
    node.children = kids;
    kids.forEach(attach);
    return node;
  }
  return (byParent.get('root') || []).map(attach);
}

// ── Trees separadas: Receitas vs Despesas ────────────────────────────
// Receitas = kind='receita'
// Despesas = qualquer kind != 'receita' E != 'transfer_internal'
//            (despesa_fixa, custo_variavel, outra_despesa, breakage)
const incomeTree = computed(() => {
  return buildTree(categories.value.filter(c => c.kind === 'receita'));
});

const expenseTree = computed(() => {
  return buildTree(categories.value.filter(c => c.kind !== 'receita' && c.kind !== 'transfer_internal'));
});

// Contadores
const incomeCount = computed(() => categories.value.filter(c => c.kind === 'receita').length);
const expenseCount = computed(() => categories.value.filter(c => c.kind !== 'receita' && c.kind !== 'transfer_internal').length);

// Receita padrão atual — a que recebe lançamentos sem categoria explícita.
// Surfaceia no header da coluna Receitas (é invisível no fluxo, então mostramos).
const defaultRevenueCategory = computed(() =>
  categories.value.find(c => c.kind === 'receita' && c.is_default),
);

// Quantos níveis profundos em cada lado (info no header)
function treeDepth(nodes, currentDepth = 1) {
  if (!nodes || nodes.length === 0) return currentDepth - 1;
  return Math.max(...nodes.map(n => treeDepth(n.children, currentDepth + 1)));
}
const incomeDepth = computed(() => treeDepth(incomeTree.value));
const expenseDepth = computed(() => treeDepth(expenseTree.value));

// ── Ações do tree ────────────────────────────────────────────────────
function onAddRoot(kind) {
  modalMode.value = 'create';
  modalInitial.value = null;
  modalPrefilledKind.value = kind;
  modalParentCategory.value = null;
  showModal.value = true;
}

function onAddChild({ parent }) {
  modalMode.value = 'create';
  modalInitial.value = null;
  modalPrefilledKind.value = parent.kind;
  modalParentCategory.value = parent;
  showModal.value = true;
}

function onEdit({ category }) {
  modalMode.value = 'edit';
  modalInitial.value = { id: category.id, name: category.name, kind: category.kind, parent_id: category.parent_id };
  modalPrefilledKind.value = category.kind;
  modalParentCategory.value = null;
  showModal.value = true;
}

async function onToggle({ category }) {
  try {
    await FinancialV2.categories.update(category.id, { category: { active: !category.active } });
    notifySuccess(category.active ? 'Categoria inativada.' : 'Categoria reativada.');
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Erro ao alterar status');
  }
}

// Define a categoria de receita padrão (recebe lançamentos sem categoria
// explícita: avulso à vista, plano, mensalidade). Backend limpa a anterior —
// só uma por conta. Recarrega pra o badge "Padrão" migrar pro nó certo.
async function onSetDefault({ category }) {
  try {
    await FinancialV2.categories.setDefault(category.id);
    notifySuccess(`"${category.name}" agora é a receita padrão.`);
    await load();
  } catch (err) {
    notifyError(
      err?.response?.data?.error ||
        err?.response?.data?.errors?.join('; ') ||
        'Não foi possível definir a receita padrão.',
    );
  }
}

function onDelete({ category }) {
  categoryToDelete.value = category;
  showDeleteModal.value = true;
}

async function confirmDelete() {
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
    // Backend manda o motivo específico em `error` (singular) — ex: "Categoria
    // possui lançamentos vinculados...". Lemos `error` antes de cair no genérico.
    const data = err?.response?.data;
    notifyError(data?.error || data?.errors?.join('; ') || 'Não foi possível remover (pode ter filhos ou lançamentos)');
  } finally {
    deleting.value = false;
  }
}

function onCategorySaved() {
  load();
}

// ── Restaurar padrão ─────────────────────────────────────────────────
// Reabilitado 2026-05-27: o endpoint POST /categories/restore_defaults agora
// existe (DreCategoriesController#restore_defaults → SeedDefaultCategories).
// Ação ADITIVA/idempotente — recria só o canon faltante, nunca apaga nada.
function onRestoreDefaults() {
  showRestoreModal.value = true;
}

async function confirmRestore() {
  restoring.value = true;
  try {
    const { data } = await FinancialV2.categories.restoreDefaults();
    const created = data?.data?.created ?? 0;
    // Toast reflete o efeito REAL — não mente sucesso quando nada mudou.
    if (created > 0) {
      notifySuccess(`${created} categoria${created === 1 ? '' : 's'} padrão restaurada${created === 1 ? '' : 's'}.`);
    } else {
      notifySuccess('Tudo certo — todas as categorias padrão já existiam. Nada foi alterado.');
    }
    showRestoreModal.value = false;
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Não foi possível restaurar o padrão.');
  } finally {
    restoring.value = false;
  }
}
</script>

<template>
  <div class="cat-plan">
    <!-- Header — explicação curta + tooltip pra detalhes (canon reservados). -->
    <header class="cat-plan-header">
      <div>
        <h2 class="cat-plan-title">Plano de Contas</h2>
        <p class="cat-plan-subtitle">
          Estrutura em até <strong>4 níveis</strong> — Grupo › Subgrupo › Item › Subcategoria.
          Lançamentos sempre caem no <strong>nível mais profundo</strong> (folha).
          <Tooltip
            label="Categorias 'Sem categoria', 'Estornos' e 'Taxa de Maquininha' são reservadas do sistema e usadas automaticamente — não aparecem nesta lista, não são editáveis nem excluíveis."
            position="bottom"
            multiline
          >
            <span class="cat-plan-subtitle-info">
              <i class="i-lucide-info size-[12px]" />
              Categorias reservadas
            </span>
          </Tooltip>
        </p>
      </div>
      <!-- Restaurar padrão — recria o canon faltante (aditivo, não destrutivo). -->
      <Tooltip
        label="Recria as categorias padrão que estiverem faltando. Suas categorias personalizadas e os lançamentos existentes não são alterados."
        position="bottom"
        multiline
      >
        <button
          type="button"
          class="cat-plan-restore-btn"
          :disabled="restoring"
          @click="onRestoreDefaults"
        >
          <i class="i-lucide-rotate-ccw size-[14px]" />
          {{ restoring ? 'Restaurando…' : 'Restaurar padrão' }}
        </button>
      </Tooltip>
    </header>

    <!-- Loading state -->
    <div v-if="loading" class="cat-plan-loading">
      <div class="cat-plan-spinner" />
      <span>Carregando categorias...</span>
    </div>

    <!-- 2 colunas: Receitas | Despesas -->
    <div v-else class="cat-plan-grid">
      <!-- Coluna RECEITAS -->
      <section class="cat-plan-col cat-plan-col--income">
        <header class="cat-plan-col-header">
          <div>
            <h3 class="cat-plan-col-title">RECEITAS</h3>
            <p class="cat-plan-col-meta">
              {{ incomeDepth }} {{ incomeDepth === 1 ? 'nível' : 'níveis' }} ·
              {{ incomeCount }} categoria{{ incomeCount === 1 ? '' : 's' }}
            </p>
            <!-- Receita padrão — invisível no fluxo, então mostramos aqui qual é
                 (ou avisamos que não tem). Define-se clicando na ★ de uma folha. -->
            <p
              class="cat-plan-default-line"
              :class="{ 'cat-plan-default-line--none': !defaultRevenueCategory }"
            >
              <i
                :class="defaultRevenueCategory ? 'i-lucide-star' : 'i-lucide-star-off'"
                class="size-[12px]"
              />
              <template v-if="defaultRevenueCategory">
                Receita padrão: <strong>{{ defaultRevenueCategory.name }}</strong>
              </template>
              <template v-else>
                Sem receita padrão — lançamentos sem categoria caem numa receita qualquer. Clique na ★ de uma categoria-folha.
              </template>
            </p>
          </div>
          <button
            type="button"
            class="cat-plan-col-add"
            @click="onAddRoot('receita')"
          >
            + Grupo
          </button>
        </header>

        <div v-if="incomeTree.length === 0" class="cat-plan-empty">
          Nenhum grupo de receita ainda. Clique em <strong>+ Grupo</strong> pra começar.
        </div>

        <div v-else class="cat-plan-tree">
          <CategoryTreeNodeV2
            v-for="(node, idx) in incomeTree"
            :key="node.id"
            :node="node"
            :depth="0"
            :group-number="String(idx + 1)"
            @add-child="onAddChild"
            @edit="onEdit"
            @toggle="onToggle"
            @delete="onDelete"
            @set-default="onSetDefault"
          />
        </div>
      </section>

      <!-- Coluna DESPESAS -->
      <section class="cat-plan-col cat-plan-col--expense">
        <header class="cat-plan-col-header">
          <div>
            <h3 class="cat-plan-col-title">DESPESAS</h3>
            <p class="cat-plan-col-meta">
              {{ expenseDepth }} {{ expenseDepth === 1 ? 'nível' : 'níveis' }} ·
              {{ expenseCount }} categoria{{ expenseCount === 1 ? '' : 's' }}
            </p>
          </div>
          <button
            type="button"
            class="cat-plan-col-add"
            @click="onAddRoot('outra_despesa')"
          >
            + Grupo
          </button>
        </header>

        <div v-if="expenseTree.length === 0" class="cat-plan-empty">
          Nenhum grupo de despesa ainda. Clique em <strong>+ Grupo</strong> pra começar.
        </div>

        <div v-else class="cat-plan-tree">
          <CategoryTreeNodeV2
            v-for="(node, idx) in expenseTree"
            :key="node.id"
            :node="node"
            :depth="0"
            :group-number="String(idx + 1)"
            @add-child="onAddChild"
            @edit="onEdit"
            @toggle="onToggle"
            @delete="onDelete"
            @set-default="onSetDefault"
          />
        </div>
      </section>
    </div>

    <!-- Regras canônicas (rodapé informativo) -->
    <footer class="cat-plan-rules">
      <h4>REGRAS</h4>
      <ul>
        <li>Lançamentos sempre caem no <strong>nível mais baixo</strong> (subcategoria/item).</li>
        <li>Taxa de maquininha é <strong class="cat-plan-highlight">gerada automaticamente</strong> ao registrar recebimento — nunca lançar manualmente.</li>
        <li>Comissão é <strong>DESPESA</strong> (Pessoal &gt; Comissões de Profissionais) — não redução de receita.</li>
        <li>Laboratório cai automaticamente via prontuário do paciente.</li>
      </ul>
    </footer>

    <!-- Modal de criar/editar categoria -->
    <CategoryFormModalV2
      :show="showModal"
      :mode="modalMode"
      :initial="modalInitial"
      :prefilled-kind="modalPrefilledKind"
      :parent-category="modalParentCategory"
      @close="showModal = false"
      @confirm="onCategorySaved"
    />

    <!-- Confirm delete — usa v-model:show pra reativar fechamento via X/overlay/Cancelar.
         Bug 2026-05-23: estava com `:show` + `@close`, mas o componente emite
         `update:show` + `cancel` (não `close`). Modal não fechava no Cancelar. -->
    <ConfirmDangerModal
      v-if="showDeleteModal && categoryToDelete"
      v-model:show="showDeleteModal"
      title="Excluir categoria"
      :message="`Tem certeza que deseja excluir '${categoryToDelete.name}'? Esta ação não pode ser desfeita.`"
      confirm-label="Excluir"
      :loading="deleting"
      @confirm="confirmDelete"
    />

    <!-- Confirma "restaurar padrão". Ação aditiva/segura, mas pede confirmação
         por mexer na estrutura do Plano de Contas. Copy deixa claro que NADA
         é apagado pra não assustar. -->
    <ConfirmDangerModal
      v-if="showRestoreModal"
      v-model:show="showRestoreModal"
      title="Restaurar Plano de Contas padrão"
      message="Isso recria as categorias padrão (canon) que estiverem faltando. Suas categorias personalizadas e os lançamentos existentes NÃO são alterados nem removidos."
      confirm-label="Restaurar padrão"
      :loading="restoring"
      @confirm="confirmRestore"
    />
  </div>
</template>

<style scoped lang="scss">
.cat-plan {
  /* Padding agora vem do `.finset__main` do parent (SettingsV2).
     Sem padding aqui pra evitar duplicação. */
  color: rgb(var(--slate-12));
}

.cat-plan-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 24px;
  margin-bottom: 24px;
  padding-bottom: 16px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.cat-plan-title {
  margin: 0 0 6px;
  font-size: 22px;
  font-weight: 700;
  color: rgb(var(--slate-12));
}
.cat-plan-subtitle {
  margin: 0;
  font-size: 13px;
  color: rgb(var(--slate-10));
  line-height: 1.5;
  max-width: 760px;
}
/* "Categorias reservadas" — pill discreto com tooltip pra abrir detalhe.
   Move informação avançada (canon de sistema) pra demanda em vez de
   ocupar 2 linhas do subtítulo. */
.cat-plan-subtitle-info {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  margin-left: 6px;
  padding: 1px 8px 1px 6px;
  border-radius: 999px;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-11));
  font-size: 11.5px;
  cursor: help;
  border: 1px dashed rgb(var(--slate-5));
  &:hover { background: rgb(var(--slate-4)); border-style: solid; }
}

/* Restaurar padrão — botão secundário discreto no header. Ação pouco
   frequente (governança), então outline azul em vez de fill. */
.cat-plan-restore-btn {
  flex-shrink: 0;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  background: transparent;
  color: rgb(var(--blue-11));
  border: 1px solid rgb(var(--blue-7));
  padding: 7px 14px;
  border-radius: 8px;
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  transition: background-color .12s ease, border-color .12s ease;

  &:hover:not(:disabled) {
    background: rgb(var(--blue-9) / 0.08);
    border-color: rgb(var(--blue-8));
  }
  &:disabled { opacity: 0.6; cursor: not-allowed; }
}

.cat-plan-loading {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 12px;
  padding: 80px 0;
  color: rgb(var(--slate-9));
  font-size: 14px;
}
.cat-plan-spinner {
  width: 18px;
  height: 18px;
  border: 2px solid rgb(var(--slate-5));
  border-top-color: rgb(var(--blue-9));
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

.cat-plan-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 24px;

  @media (max-width: 1100px) {
    grid-template-columns: 1fr;
  }
}

.cat-plan-col {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 18px 20px;
  min-height: 280px;

  // Canon financeiro V2 = AZUL Klivy (decisão 2026-05-23). O `--emerald-*`
  // usado antes NÃO existe no design system (só slate/blue/ruby/teal), então
  // `rgb(var(--emerald-9))` era inválido → background resetava pra transparent
  // e o botão "+ Grupo" aparecia branco. Trocado por --blue-*.
  &--income .cat-plan-col-title {
    color: rgb(var(--blue-10));
  }
  &--income .cat-plan-col-add {
    background: rgb(var(--blue-9));
    &:hover { background: rgb(var(--blue-10)); }
  }

  &--expense .cat-plan-col-title {
    color: rgb(var(--ruby-10));
  }
  &--expense .cat-plan-col-add {
    background: rgb(var(--ruby-9));
    &:hover { background: rgb(var(--ruby-10)); }
  }
}

.cat-plan-col-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 12px;
  margin-bottom: 16px;
  padding-bottom: 12px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.cat-plan-col-title {
  margin: 0;
  font-size: 14px;
  font-weight: 700;
  letter-spacing: 0.05em;
}
.cat-plan-col-meta {
  margin: 4px 0 0;
  font-size: 11px;
  color: rgb(var(--slate-9));
}
/* Linha "Receita padrão: X" — azul canon quando definida, âmbar de alerta
   quando não há nenhuma (lançamento sem categoria cai numa receita qualquer). */
.cat-plan-default-line {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  margin: 6px 0 0;
  font-size: 11.5px;
  line-height: 1.4;
  color: rgb(var(--blue-11));

  i { flex-shrink: 0; color: rgb(var(--blue-10)); }
  strong { color: rgb(var(--blue-11)); font-weight: 600; }

  &--none {
    color: rgb(var(--amber-11));
    i { color: rgb(var(--amber-10)); }
  }
}
.cat-plan-col-add {
  background: rgb(var(--slate-9));
  color: white;
  border: 0;
  padding: 6px 12px;
  border-radius: 6px;
  font-size: 12px;
  font-weight: 500;
  cursor: pointer;
  transition: background-color .12s ease;
}

.cat-plan-empty {
  padding: 32px 16px;
  text-align: center;
  color: rgb(var(--slate-9));
  font-size: 13px;
}

.cat-plan-tree {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.cat-plan-rules {
  margin-top: 28px;
  padding: 18px 20px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;

  h4 {
    margin: 0 0 10px;
    font-size: 12px;
    font-weight: 700;
    letter-spacing: 0.05em;
    color: rgb(var(--slate-11));
  }

  ul {
    margin: 0;
    padding-left: 18px;
    color: rgb(var(--slate-11));
    font-size: 13px;
    line-height: 1.7;
  }

  strong { color: rgb(var(--slate-12)); }
}
.cat-plan-highlight {
  color: rgb(var(--amber-10)) !important;
}
</style>
