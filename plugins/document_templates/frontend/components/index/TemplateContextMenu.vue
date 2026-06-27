<script setup>
// Popover ⋮ do TemplateCard — Duplicar / Arquivar / Reativar / Deletar.
//
// Posicionamento: recebe `anchor` (DOMElement do botão ⋮) e calcula posição
// absoluta. Fecha ao clicar fora ou apertar ESC. Não usa popper/floating-ui
// pra evitar dependência — geometria simples baseada em getBoundingClientRect.

import { ref, computed, onMounted, onBeforeUnmount, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  template: { type: Object, required: true },
  anchor:   { type: Object, default: null }, // HTMLElement do trigger
});

const emit = defineEmits([
  'close',
  'duplicate',
  'archive',
  'unarchive',
  'delete',
]);

const { t } = useI18n();
const menuRef = ref(null);
const position = ref({ top: 0, left: 0 });

// Templates Klivy (account_id NULL) são read-only — não podem ser editados/
// arquivados/deletados. O user só vê "Duplicar".
const isKlivy = computed(() => props.template.is_klivy);
const isArchived = computed(() => props.template.status === 'archived');

const computePosition = () => {
  if (!props.anchor) return;
  const rect = props.anchor.getBoundingClientRect();
  // Alinha pela direita do trigger, abre pra baixo.
  position.value = {
    top: rect.bottom + 4,
    left: rect.right - 200, // largura do menu (~200px)
  };
};

const onDocumentClick = (event) => {
  if (!menuRef.value) return;
  if (menuRef.value.contains(event.target)) return;
  if (props.anchor?.contains(event.target)) return;
  emit('close');
};

const onKeyDown = (event) => {
  if (event.key === 'Escape') emit('close');
};

onMounted(async () => {
  await nextTick();
  computePosition();
  document.addEventListener('mousedown', onDocumentClick);
  document.addEventListener('keydown', onKeyDown);
});

onBeforeUnmount(() => {
  document.removeEventListener('mousedown', onDocumentClick);
  document.removeEventListener('keydown', onKeyDown);
});

// Confirmação de exclusão é feita pelo pai (DocumentsIndex) via ConfirmDialog
// do design system — aqui só emitimos o evento e fechamos o menu.
const handleDuplicate = () => { emit('duplicate', props.template); emit('close'); };
const handleArchive   = () => { emit('archive',   props.template); emit('close'); };
const handleUnarchive = () => { emit('unarchive', props.template); emit('close'); };
const handleDelete    = () => { emit('delete',    props.template); emit('close'); };
</script>

<template>
  <Teleport to="body">
    <div
      ref="menuRef"
      class="template-context-menu"
      :style="{ top: `${position.top}px`, left: `${position.left}px` }"
      role="menu"
    >
      <button
        type="button"
        class="template-context-menu__item"
        role="menuitem"
        @click="handleDuplicate"
      >
        <span class="i-lucide-copy" />
        {{ t('DOCUMENT_TEMPLATES.CONTEXT_MENU.DUPLICATE') }}
      </button>

      <template v-if="!isKlivy">
        <button
          v-if="!isArchived"
          type="button"
          class="template-context-menu__item"
          role="menuitem"
          @click="handleArchive"
        >
          <span class="i-lucide-archive" />
          {{ t('DOCUMENT_TEMPLATES.CONTEXT_MENU.ARCHIVE') }}
        </button>
        <button
          v-else
          type="button"
          class="template-context-menu__item"
          role="menuitem"
          @click="handleUnarchive"
        >
          <span class="i-lucide-archive-restore" />
          {{ t('DOCUMENT_TEMPLATES.CONTEXT_MENU.UNARCHIVE') }}
        </button>

        <div class="template-context-menu__divider" />

        <button
          type="button"
          class="template-context-menu__item template-context-menu__item--danger"
          role="menuitem"
          @click="handleDelete"
        >
          <span class="i-lucide-trash-2" />
          {{ t('DOCUMENT_TEMPLATES.CONTEXT_MENU.DELETE') }}
        </button>
      </template>
    </div>
  </Teleport>
</template>

<style lang="scss" scoped>
@use '../../styles/index/template-context-menu';
</style>
