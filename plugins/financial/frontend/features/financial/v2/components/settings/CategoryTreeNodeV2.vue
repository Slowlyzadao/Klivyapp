<script setup>
/**
 * Nó recursivo da árvore de categorias DRE — versão "premium" 2026-05-23.
 *
 * Refinamentos visuais (sem mudança funcional):
 *   - Setas Unicode (▼/▶) → ícones lucide chevron
 *   - └─ character → linhas guia CSS (border-left)
 *   - 🔒 emoji → ícone lucide lock
 *   - title= nativo → componente <Tooltip> do beclinic_core
 *   - Botões "+ Sub", "Inativar", "×" → icon buttons com tooltip
 *   - Ícone de folder/file ao lado do nome pra reforçar hierarquia
 *
 * Props inalteradas:
 *   - node       : { id, name, level, kind, parent_id, active, system_default, children: [] }
 *   - depth      : Number — profundidade visual (0 = root)
 *   - groupNumber: String — numeração herdada ("1", "1.1", "1.1.3")
 *
 * Eventos inalterados:
 *   - add-child, edit, toggle, delete
 */
import { ref, computed } from 'vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';

const props = defineProps({
  node: { type: Object, required: true },
  depth: { type: Number, default: 0 },
  groupNumber: { type: String, default: '' },
});

const emit = defineEmits(['add-child', 'edit', 'toggle', 'delete', 'set-default']);

const expanded = ref(true);
const hasChildren = computed(() => Array.isArray(props.node.children) && props.node.children.length > 0);
const isLeaf = computed(() => !hasChildren.value);
const inactive = computed(() => props.node.active === false);

// Receita padrão da conta — a que recebe lançamentos sem categoria explícita
// (avulso à vista, plano de tratamento, mensalidade). Só vale pra kind 'receita'.
const isDefaultRevenue = computed(() => props.node.kind === 'receita' && props.node.is_default === true);
// "Definir como padrão" só faz sentido numa FOLHA de receita ativa e não-reservada
// (canon: lançamentos caem sempre no nível mais profundo).
const canSetDefault = computed(() =>
  props.node.kind === 'receita'
  && isLeaf.value
  && !props.node.system_default
  && !inactive.value
  && !isDefaultRevenue.value,
);

// Texto do botão "+ Sub" ou "+ Item" depende do level (canon MAX_LEVEL=4):
//   L1 (Grupo)    → "+ Subgrupo" (cria L2)
//   L2 (Subgrupo) → "+ Item" (cria L3)
//   L3 (Item)     → "+ Subcategoria" (cria L4)
//   L4           → nenhum (limite canônico)
const addChildLabel = computed(() => {
  if (props.node.level === 1) return '+ Subgrupo';
  if (props.node.level === 2) return '+ Item';
  if (props.node.level === 3) return '+ Subcategoria';
  return null;
});
const canAddChild = computed(() => props.node.level < 4 && !inactive.value);

// Vínculos — alimenta o badge "em uso" e a desativação do botão excluir.
// `entries_count` = receitas + despesas + parcelas; `pricings_count` = procedimentos.
const lancamentosCount = computed(() => Number(props.node.entries_count) || 0);
const pricingsCount = computed(() => Number(props.node.pricings_count) || 0);
const hasVinculos = computed(() => lancamentosCount.value > 0 || pricingsCount.value > 0);
const vinculosLabel = computed(() => {
  if (!hasVinculos.value) return '';
  const parts = [];
  if (lancamentosCount.value > 0) parts.push(`${lancamentosCount.value} lançamento${lancamentosCount.value === 1 ? '' : 's'}`);
  if (pricingsCount.value > 0) parts.push(`${pricingsCount.value} procedimento${pricingsCount.value === 1 ? '' : 's'}`);
  return `Em uso: ${parts.join(' · ')}. Não pode ser excluída — migre os vínculos para outra categoria antes.`;
});

// Ícone do "folder" do nó — dá pista visual da função:
//   - root expandido    → folder-open
//   - root colapsado    → folder
//   - intermediário     → folder-tree
//   - leaf              → tag (categoria-fim, recebe lançamento)
const nodeIcon = computed(() => {
  if (isLeaf.value) return 'i-lucide-tag';
  if (props.depth === 0) {
    return expanded.value ? 'i-lucide-folder-open' : 'i-lucide-folder';
  }
  return 'i-lucide-folder-tree';
});

// Numeração estilo wireframe ("1", "1.1", "1.1.3", "1.2.1.4")
function childNumber(index) {
  if (!props.groupNumber) return String(index + 1);
  return `${props.groupNumber}.${index + 1}`;
}

function onClickEdit() {
  if (props.node.system_default) return;
  emit('edit', { category: props.node });
}
</script>

<template>
  <div class="cat-tree-node" :class="`cat-tree-node--depth-${depth}`">
    <!-- Linha do nó atual -->
    <div
      class="cat-tree-row"
      :class="{
        'cat-tree-row--inactive': inactive,
        'cat-tree-row--root': depth === 0,
      }"
    >
      <!-- Lado esquerdo: chevron expand/collapse (ou placeholder se leaf) -->
      <button
        v-if="hasChildren"
        type="button"
        class="cat-tree-chevron"
        @click="expanded = !expanded"
        :aria-label="expanded ? 'Recolher' : 'Expandir'"
      >
        <i
          :class="expanded ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'"
          class="size-[14px]"
        />
      </button>
      <span v-else class="cat-tree-chevron cat-tree-chevron--leaf" />

      <!-- Ícone de folder/tag -->
      <i :class="nodeIcon" class="cat-tree-icon size-[14px]" />

      <!-- Nome + número -->
      <Tooltip
        :label="node.system_default
          ? 'Categoria reservada do sistema — não editável'
          : 'Clique para editar o nome'"
        position="top"
      >
        <button
          type="button"
          class="cat-tree-name"
          :class="{
            'cat-tree-name--root': depth === 0,
            'cat-tree-name--subgroup': depth === 1,
            'cat-tree-name--item': depth >= 2,
            'cat-tree-name--system': node.system_default,
          }"
          :disabled="node.system_default"
          @click="onClickEdit"
        >
          <span v-if="groupNumber" class="cat-tree-num">{{ groupNumber }}</span>
          <span class="cat-tree-name-text">{{ node.name }}</span>
          <i
            v-if="node.system_default"
            class="i-lucide-lock cat-tree-lock size-[10px]"
          />
        </button>
      </Tooltip>

      <!-- Bloco direito: badge "em uso" (sempre visível) + ações (hover),
           agrupados pra ocupar UMA célula do grid da linha (senão o filho extra
           quebraria pra uma segunda linha). -->
      <div class="cat-tree-right">
      <!-- Badge "Padrão" — esta receita recebe lançamentos sem categoria
           explícita. Sempre visível (descobrível sem hover). -->
      <Tooltip
        v-if="isDefaultRevenue"
        label="Receita padrão: recebe lançamentos sem categoria explícita (avulso à vista, plano de tratamento, mensalidade)."
        position="top"
        multiline
      >
        <span class="cat-tree-default-badge">
          <i class="i-lucide-star size-[11px]" />
          Padrão
        </span>
      </Tooltip>

      <!-- Badge "em uso" — sinaliza vínculos (não excluível); explica de antemão
           por que o botão excluir fica desabilitado. -->
      <Tooltip v-if="hasVinculos" :label="vinculosLabel" position="top">
        <span class="cat-tree-vinculo">
          <i class="i-lucide-link-2 size-[11px]" />
          {{ lancamentosCount > 0 ? lancamentosCount : pricingsCount }}
        </span>
      </Tooltip>

      <!-- Ações à direita (revelam no hover, exceto + Sub que fica sempre visível
           em root pra ser descobrível) -->
      <div class="cat-tree-actions">
        <Tooltip
          v-if="canAddChild && addChildLabel"
          :label="`Adicionar ${addChildLabel.replace('+ ', '').toLowerCase()} dentro de ${node.name}`"
          position="top"
        >
          <button
            type="button"
            class="cat-tree-btn cat-tree-btn--add"
            @click="emit('add-child', { parent: node })"
          >
            {{ addChildLabel }}
          </button>
        </Tooltip>
        <Tooltip
          v-if="canSetDefault"
          label="Definir como receita padrão — passa a receber lançamentos sem categoria explícita."
          position="top"
          multiline
        >
          <button
            type="button"
            class="cat-tree-btn-icon cat-tree-btn-icon--default"
            aria-label="Definir como receita padrão"
            @click="emit('set-default', { category: node })"
          >
            <i class="i-lucide-star size-[13px]" />
          </button>
        </Tooltip>
        <Tooltip
          v-if="!node.system_default"
          :label="inactive ? 'Reativar — volta a aparecer em selects' : 'Inativar — esconde sem perder histórico'"
          position="top"
        >
          <button
            type="button"
            class="cat-tree-btn-icon"
            :class="inactive ? 'cat-tree-btn-icon--reactivate' : 'cat-tree-btn-icon--toggle'"
            @click="emit('toggle', { category: node })"
          >
            <i :class="inactive ? 'i-lucide-rotate-ccw' : 'i-lucide-eye-off'" class="size-[13px]" />
          </button>
        </Tooltip>
        <Tooltip
          v-if="!node.system_default && isLeaf"
          :label="hasVinculos ? vinculosLabel : 'Excluir (só folhas sem lançamentos vinculados)'"
          position="top"
        >
          <button
            type="button"
            class="cat-tree-btn-icon cat-tree-btn-icon--delete"
            :disabled="hasVinculos"
            @click="emit('delete', { category: node })"
          >
            <i class="i-lucide-trash-2 size-[13px]" />
          </button>
        </Tooltip>
      </div>
      </div>
    </div>

    <!-- Filhos recursivos com guide-line vertical -->
    <div
      v-if="hasChildren && expanded"
      class="cat-tree-children"
      :class="{ 'cat-tree-children--root': depth === 0 }"
    >
      <CategoryTreeNodeV2
        v-for="(child, idx) in node.children"
        :key="child.id"
        :node="child"
        :depth="depth + 1"
        :group-number="childNumber(idx)"
        @add-child="(p) => emit('add-child', p)"
        @edit="(p) => emit('edit', p)"
        @toggle="(p) => emit('toggle', p)"
        @delete="(p) => emit('delete', p)"
        @set-default="(p) => emit('set-default', p)"
      />
    </div>
  </div>
</template>

<style scoped lang="scss">
.cat-tree-node {
  font-size: 13px;
  color: rgb(var(--slate-12));
}

/* Linha do nó: chevron · ícone · nome · ações */
.cat-tree-row {
  display: grid;
  grid-template-columns: 22px 18px 1fr auto;
  align-items: center;
  gap: 6px;
  padding: 5px 8px;
  border-radius: 6px;
  transition: background-color 0.12s ease;

  &:hover {
    background: rgb(var(--slate-3));
  }

  &--inactive {
    opacity: 0.5;
    .cat-tree-name-text { text-decoration: line-through; }
  }
  &--root {
    background: rgb(var(--slate-2));
    margin-bottom: 2px;
  }
}

/* Chevron expand/collapse */
.cat-tree-chevron {
  background: transparent;
  border: 0;
  padding: 0;
  width: 22px; height: 22px;
  display: inline-flex; align-items: center; justify-content: center;
  border-radius: 4px;
  color: rgb(var(--slate-10));
  cursor: pointer;
  transition: background 0.12s ease;

  &:hover { background: rgb(var(--slate-4)); color: rgb(var(--slate-12)); }
  &--leaf { cursor: default; visibility: hidden; }
}

/* Ícone do nó (folder/tag) */
.cat-tree-icon {
  color: rgb(var(--blue-9));
  flex-shrink: 0;
}
.cat-tree-node--depth-0 .cat-tree-icon { color: rgb(var(--blue-10)); }

/* Nome do nó (botão clicável) */
.cat-tree-name {
  background: transparent;
  border: 0;
  padding: 0;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  text-align: left;
  cursor: pointer;
  color: rgb(var(--slate-12));
  font-size: 13px;
  line-height: 1.4;
  min-width: 0;
  font-family: inherit;

  &:hover:not(:disabled) .cat-tree-name-text {
    color: rgb(var(--blue-11));
    text-decoration: underline;
    text-decoration-style: dotted;
    text-underline-offset: 3px;
  }

  &:disabled {
    cursor: not-allowed;
    color: rgb(var(--slate-9));
  }

  &--root .cat-tree-name-text { font-weight: 600; font-size: 14px; }
  &--subgroup .cat-tree-name-text { font-weight: 500; }
  &--system .cat-tree-name-text { font-style: italic; }
}

.cat-tree-name-text {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  transition: color 0.12s ease;
}

.cat-tree-lock {
  color: rgb(var(--slate-8));
  flex-shrink: 0;
}

.cat-tree-num {
  display: inline-block;
  min-width: 28px;
  padding: 1px 5px;
  border-radius: 3px;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-10));
  font-size: 10.5px;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
  text-align: center;
  flex-shrink: 0;
}

/* Bloco direito da linha: badge + ações numa única célula do grid. */
.cat-tree-right {
  display: inline-flex;
  align-items: center;
  justify-content: flex-end;
  gap: 6px;
  min-width: 0;
}

/* Badge "em uso" — vínculos (lançamentos/procedimentos). Sempre visível,
   âmbar discreto pra sinalizar "bloqueado pra exclusão". */
.cat-tree-vinculo {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  flex-shrink: 0;
  padding: 1px 7px 1px 5px;
  border-radius: 999px;
  background: rgb(var(--amber-3));
  color: rgb(var(--amber-11));
  font-size: 10.5px;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
  cursor: help;
  border: 1px solid rgb(var(--amber-6));
}

/* Badge "Padrão" — receita que recebe lançamentos sem categoria. Azul (canon
   financeiro V2) pra contrastar com o âmbar do badge "em uso" ao lado. */
.cat-tree-default-badge {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  flex-shrink: 0;
  padding: 1px 8px 1px 6px;
  border-radius: 999px;
  background: rgb(var(--blue-3));
  color: rgb(var(--blue-11));
  font-size: 10.5px;
  font-weight: 600;
  cursor: help;
  border: 1px solid rgb(var(--blue-6));

  i { color: rgb(var(--blue-10)); }
}

/* Ações */
.cat-tree-actions {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  opacity: 0;
  transition: opacity 0.12s ease;
}
.cat-tree-row:hover .cat-tree-actions,
.cat-tree-row:focus-within .cat-tree-actions {
  opacity: 1;
}
/* Root sempre visível pra +Subgrupo ser descobrível */
.cat-tree-row--root .cat-tree-actions {
  opacity: 1;
}

/* Botão "+ Subgrupo / + Item / + Subcategoria" — pílula */
.cat-tree-btn {
  background: transparent;
  border: 1px solid rgba(16, 185, 129, 0.4);
  border-radius: 999px;
  padding: 2px 10px;
  font-size: 11px;
  font-weight: 500;
  color: rgb(var(--emerald-11));
  cursor: pointer;
  line-height: 1.4;
  transition: background 0.12s ease, border-color 0.12s ease;
  white-space: nowrap;

  &:hover {
    background: rgba(16, 185, 129, 0.12);
    border-color: rgba(16, 185, 129, 0.6);
  }
}

/* Botões icon-only (toggle visibility, delete) */
.cat-tree-btn-icon {
  background: transparent;
  border: 1px solid rgb(var(--slate-5));
  border-radius: 6px;
  padding: 0;
  width: 24px; height: 24px;
  display: inline-flex; align-items: center; justify-content: center;
  color: rgb(var(--slate-10));
  cursor: pointer;
  transition: background 0.12s ease, border-color 0.12s ease, color 0.12s ease;

  &:hover { background: rgb(var(--slate-3)); color: rgb(var(--slate-12)); border-color: rgb(var(--slate-7)); }

  &--toggle:hover { color: rgb(var(--amber-11)); border-color: rgba(245, 158, 11, 0.5); background: rgba(245, 158, 11, 0.08); }
  &--reactivate { color: rgb(var(--blue-10)); border-color: rgba(59, 130, 246, 0.4); }
  &--reactivate:hover { background: rgba(59, 130, 246, 0.10); color: rgb(var(--blue-11)); }
  &--delete:hover { color: rgb(var(--ruby-11)); border-color: rgba(239, 68, 68, 0.5); background: rgba(239, 68, 68, 0.08); }
  &--default:hover { color: rgb(var(--blue-11)); border-color: rgba(59, 130, 246, 0.5); background: rgba(59, 130, 246, 0.08); }

  /* Bloqueado: categoria com vínculos (lançamentos/procedimentos). Tooltip
     explica o motivo; o badge âmbar reforça. */
  &:disabled {
    opacity: 0.35;
    cursor: not-allowed;
    &:hover { background: transparent; color: rgb(var(--slate-10)); border-color: rgb(var(--slate-5)); }
  }
}

/* Linhas guia verticais entre filhos — substitui o └─ character */
.cat-tree-children {
  position: relative;
  margin-left: 22px; /* alinha com o chevron */
  padding-left: 16px;
  border-left: 1px dashed rgb(var(--slate-5));
  margin-top: 2px;
}
.cat-tree-children--root {
  border-left-color: rgb(var(--slate-6));
}

/* Dark mode polish — guidelines mais sutis */
:root.dark .cat-tree-children { border-left-color: rgba(255, 255, 255, 0.08); }
:root.dark .cat-tree-children--root { border-left-color: rgba(255, 255, 255, 0.14); }
:root.dark .cat-tree-row--root { background: rgba(255, 255, 255, 0.03); }
:root.dark .cat-tree-num { background: rgba(255, 255, 255, 0.06); }
</style>
