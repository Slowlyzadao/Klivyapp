<script setup>
// FE-16/17 + ARCH-23 (auditoria 2026-05-19): strings PT-BR migradas pra
// `INTERNAL_CHAT.TYPING.*` via i18n. Pluralização tratada por chaves
// separadas (SINGULAR/DUAL/PLURAL) com interpolação — segue o pattern de
// `GROUP_SETTINGS.HERO.MEMBERS_COUNT_ONE/OTHER` já estabelecido.
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  roomId: { type: Number, required: true },
});

const store = useStore();
const { t } = useI18n();

const typers = computed(() =>
  store.getters['internalChatTyping/getTypersForRoom'](props.roomId)
);

const text = computed(() => {
  const list = typers.value;
  if (list.length === 0) return '';
  if (list.length === 1) {
    return t('INTERNAL_CHAT.TYPING.SINGULAR', { name: list[0].name });
  }
  if (list.length === 2) {
    return t('INTERNAL_CHAT.TYPING.DUAL', {
      name1: list[0].name,
      name2: list[1].name,
    });
  }
  return t('INTERNAL_CHAT.TYPING.PLURAL', {
    name: list[0].name,
    count: list.length - 1,
  });
});
</script>

<template>
  <div
    v-if="text"
    class="flex items-center gap-1.5 px-4 py-1.5 text-xs text-n-slate-11 bg-n-background"
  >
    <span class="flex items-center gap-0.5">
      <span class="w-1 h-1 rounded-full bg-n-slate-10 ic-typing-dot" style="animation-delay:0s" />
      <span class="w-1 h-1 rounded-full bg-n-slate-10 ic-typing-dot" style="animation-delay:.15s" />
      <span class="w-1 h-1 rounded-full bg-n-slate-10 ic-typing-dot" style="animation-delay:.3s" />
    </span>
    <span class="italic">{{ text }}</span>
  </div>
</template>
