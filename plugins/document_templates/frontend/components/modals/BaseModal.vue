<script setup>
// Shell de modal centralizado — match design system M3 Klivy.
// Backdrop click fecha, ESC fecha, `<slot>` recebe body.
// Slots: header (opcional, default mostra title prop) e footer (opcional).
//
// Aplica classe .document-templates-scope no wrapper teleportado pra
// herdar tokens --kl-* mesmo sendo render fora do .documents-index root.

import { onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  title: { type: String, default: '' },
  closeOnBackdrop: { type: Boolean, default: true },
});

const emit = defineEmits(['close']);

const { t } = useI18n();

const onKeydown = (e) => {
  if (e.key === 'Escape') emit('close');
};

const onBackdrop = () => {
  if (props.closeOnBackdrop) emit('close');
};

onMounted(() => document.addEventListener('keydown', onKeydown));
onBeforeUnmount(() => document.removeEventListener('keydown', onKeydown));
</script>

<template>
  <Teleport to="body">
    <div class="document-templates-scope">
      <div class="base-modal__backdrop" @click.self="onBackdrop">
        <div
          class="base-modal__container"
          role="dialog"
          aria-modal="true"
          :aria-label="title"
        >
          <header v-if="title || $slots.header" class="base-modal__header">
            <slot name="header">
              <h3 class="base-modal__title">{{ title }}</h3>
            </slot>
            <button
              type="button"
              class="base-modal__close"
              :aria-label="t('DOCUMENT_TEMPLATES.MODAL.CLOSE')"
              @click="emit('close')"
            >
              <span class="i-lucide-x" />
            </button>
          </header>

          <div class="base-modal__body">
            <slot />
          </div>

          <footer v-if="$slots.footer" class="base-modal__footer">
            <slot name="footer" />
          </footer>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style lang="scss" scoped>
@use '../../styles/modals/base-modal';
</style>
