<script setup>
/**
 * Pagination — controle de paginação reutilizável.
 *
 * Segue o padrão visual já em uso em `plugins/patients/frontend/routes/patients/Index.vue`
 * (lista de pacientes), que tinha código inline. Extraído pra cá pra reaproveitar
 * em qualquer listagem do sistema (financeiro v2, agenda, relatórios etc.).
 *
 * Componente "burro": estado vive no parent. Emite `update:currentPage` e
 * `update:perPage` (v-model nas duas) e mostra "Exibindo X–Y de Z {itemLabel}"
 * + dropdown de itens por página + botões de navegação com elipses.
 *
 * Uso:
 *   <Pagination
 *     v-model:current-page="currentPage"
 *     v-model:per-page="perPage"
 *     :total-count="totalCount"
 *     item-label="parcelas"
 *   />
 *
 * Props:
 *   currentPage  : number  (v-model:current-page)
 *   perPage      : number  (v-model:per-page) — default 10
 *   totalCount   : number  — total de itens em todas as páginas
 *   itemLabel    : string  — label do tipo de item (ex.: "parcelas", "pacientes")
 *   perPageOptions : number[]  — opções no dropdown (default [10, 25, 50, 100])
 *   showPerPage  : boolean — esconde dropdown se false (mobile com pouco espaço)
 */
import { computed } from 'vue';
import FormSelect from './FormSelect.vue';

const props = defineProps({
  currentPage: { type: Number, default: 1 },
  perPage: { type: Number, default: 10 },
  totalCount: { type: Number, default: 0 },
  itemLabel: { type: String, default: 'itens' },
  perPageOptions: { type: Array, default: () => [10, 25, 50, 100] },
  showPerPage: { type: Boolean, default: true },
});

const emit = defineEmits(['update:currentPage', 'update:perPage']);

const totalPages = computed(() =>
  props.totalCount > 0 ? Math.ceil(props.totalCount / props.perPage) : 1
);

const rangeStart = computed(() =>
  props.totalCount === 0 ? 0 : (props.currentPage - 1) * props.perPage + 1
);

const rangeEnd = computed(() =>
  Math.min(props.currentPage * props.perPage, props.totalCount)
);

// Lista de páginas a exibir: [1, ..., N-1, N, N+1, ..., total].
// Sempre inclui 1, current ± 1, e total. Vazios (gaps > 1) viram "...".
const pageNumbers = computed(() => {
  const total = totalPages.value;
  const cur = props.currentPage;
  const pages = new Set([1, total, cur]);
  if (cur > 1) pages.add(cur - 1);
  if (cur < total) pages.add(cur + 1);
  return [...pages].filter(p => p >= 1 && p <= total).sort((a, b) => a - b);
});

const perPageSelectOptions = computed(() =>
  props.perPageOptions.map(n => ({ value: n, label: `${n} por página` }))
);

const goToPage = target => {
  if (target < 1 || target > totalPages.value) return;
  if (target === props.currentPage) return;
  emit('update:currentPage', target);
};

const setPerPage = value => {
  const n = Number(value);
  if (!n || n === props.perPage) return;
  emit('update:perPage', n);
  // Reseta pra página 1 ao mudar tamanho — evita ficar fora de range.
  emit('update:currentPage', 1);
};
</script>

<template>
  <div v-if="totalCount > 0" class="bcl-pagination">
    <div class="bcl-pagination__info">
      Exibindo {{ rangeStart }}–{{ rangeEnd }} de {{ totalCount }} {{ itemLabel }}
    </div>
    <div class="bcl-pagination__controls">
      <FormSelect
        v-if="showPerPage"
        :model-value="perPage"
        :options="perPageSelectOptions"
        class="bcl-pagination__per-page"
        @update:model-value="setPerPage"
      />

      <button
        type="button"
        class="bcl-pagination__btn"
        :disabled="currentPage === 1"
        aria-label="Página anterior"
        @click="goToPage(currentPage - 1)"
      >
        <i class="i-lucide-chevron-left w-4 h-4" />
      </button>

      <template v-for="(pg, idx) in pageNumbers" :key="pg">
        <span
          v-if="idx > 0 && pageNumbers[idx - 1] !== pg - 1"
          class="bcl-pagination__ellipsis"
          aria-hidden="true"
        >…</span>
        <button
          type="button"
          class="bcl-pagination__btn"
          :class="{ 'bcl-pagination__btn--active': currentPage === pg }"
          :aria-current="currentPage === pg ? 'page' : undefined"
          @click="goToPage(pg)"
        >
          {{ pg }}
        </button>
      </template>

      <button
        type="button"
        class="bcl-pagination__btn"
        :disabled="currentPage === totalPages"
        aria-label="Próxima página"
        @click="goToPage(currentPage + 1)"
      >
        <i class="i-lucide-chevron-right w-4 h-4" />
      </button>
    </div>
  </div>
</template>

<style scoped lang="scss">
.bcl-pagination {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 12px 16px;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  flex-wrap: wrap;
  font-size: 13px;
}

.bcl-pagination__info {
  color: rgb(var(--slate-11));
  font-variant-numeric: tabular-nums;
}

.bcl-pagination__controls {
  display: flex;
  align-items: center;
  gap: 4px;
  flex-wrap: wrap;
}

/* Force the FormSelect trigger to match button height (32px). FormSelect default
   é 40px (min-height: 2.5rem) — pagination usa botões de 32px e o select
   ficava desalinhado. */
.bcl-pagination__per-page {
  width: 140px;
  margin-right: 6px;

  :deep(.fs-trigger) {
    min-height: 32px;
    height: 32px;
    padding-top: 0;
    padding-bottom: 0;
    font-size: 13px;
  }
}

.bcl-pagination__btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 32px;
  height: 32px;
  padding: 0 8px;
  border-radius: 8px;
  background: transparent;
  border: 1px solid rgb(var(--slate-5));
  color: rgb(var(--slate-12));
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  transition: background 0.12s ease, border-color 0.12s ease;
  font-variant-numeric: tabular-nums;

  &:hover:not(:disabled) {
    background: rgb(var(--slate-3));
    border-color: rgb(var(--slate-7));
  }

  &:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }
}

/* Cor primária da marca Klivy é azul — usar --blue-9 (não slate). */
.bcl-pagination__btn--active {
  background: rgb(var(--blue-9));
  border-color: rgb(var(--blue-9));
  color: #ffffff;

  &:hover:not(:disabled) {
    background: rgb(var(--blue-10));
    border-color: rgb(var(--blue-10));
    color: #ffffff;
  }
}

.bcl-pagination__ellipsis {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 24px;
  color: rgb(var(--slate-9));
  user-select: none;
}

@media (max-width: 640px) {
  .bcl-pagination {
    flex-direction: column;
    align-items: stretch;
    gap: 10px;
  }
  .bcl-pagination__info { text-align: center; }
  .bcl-pagination__controls { justify-content: center; }
  .bcl-pagination__per-page { width: 100%; max-width: 200px; margin-right: 0; }
}
</style>
