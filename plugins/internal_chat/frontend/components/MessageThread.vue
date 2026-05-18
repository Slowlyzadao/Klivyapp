<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useStore } from 'vuex';
import MessageBubble from './MessageBubble.vue';
import patternLight from '@plugins/internal_chat/frontend/assets/chat-bg-pattern.svg';
import patternDark from '@plugins/internal_chat/frontend/assets/chat-bg-pattern-dark.svg';

const props = defineProps({
  roomId: { type: Number, required: true },
});
const emit = defineEmits(['reply']);

const store = useStore();
const scrollEl = ref(null);

const messages = computed(() =>
  store.getters['internalChatMessages/getMessagesForRoom'](props.roomId)
);
const currentUserId = computed(() => store.getters.getCurrentUserID);

const scrollToBottom = () => {
  nextTick(() => {
    if (scrollEl.value) {
      scrollEl.value.scrollTop = scrollEl.value.scrollHeight;
    }
  });
};

watch(() => messages.value.length, () => scrollToBottom());
watch(() => props.roomId, () => scrollToBottom());

const grouped = computed(() => {
  const groups = [];
  let currentLabel = null;
  for (const m of messages.value) {
    const d = new Date(m.created_at);
    const label = d.toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: 'long',
      year: 'numeric',
    });
    if (label !== currentLabel) {
      groups.push({ label, items: [] });
      currentLabel = label;
    }
    groups[groups.length - 1].items.push(m);
  }
  return groups;
});

watch(
  () => messages.value.length,
  () => {
    const last = messages.value[messages.value.length - 1];
    if (last && last.sender?.id !== currentUserId.value) {
      store.dispatch('internalChatMessages/markRead', {
        roomId: props.roomId,
        messageId: last.id,
      });
      store.dispatch('internalChatRooms/clearUnread', props.roomId);
    }
  }
);

const jumpTo = id => {
  const el = document.querySelector(`[data-msg-id="${id}"]`);
  if (!el) return;
  el.scrollIntoView({ behavior: 'smooth', block: 'center' });
  el.classList.add('ic-msg-flash');
  setTimeout(() => el.classList.remove('ic-msg-flash'), 1500);
};
</script>

<template>
  <div
    ref="scrollEl"
    class="flex-1 px-4 py-4 overflow-y-auto ic-thread-scroll bg-n-background ic-thread-pattern"
    :style="{
      '--ic-pattern-light': `url('${patternLight}')`,
      '--ic-pattern-dark': `url('${patternDark}')`,
    }"
  >
    <div
      v-if="!messages.length"
      class="flex flex-col items-center justify-center h-full text-sm text-n-slate-11"
    >
      <span class="i-lucide-message-square text-3xl mb-2 text-n-slate-9" />
      Nenhuma mensagem ainda. Envie a primeira!
    </div>

    <template v-else>
      <div
        v-for="group in grouped"
        :key="group.label"
        class="space-y-1"
      >
        <div class="flex justify-center my-3">
          <span
            class="px-2 py-0.5 text-[11px] rounded-full bg-n-alpha-1 text-n-slate-11"
          >
            {{ group.label }}
          </span>
        </div>
        <div
          v-for="m in group.items"
          :key="m.id"
          :data-msg-id="m.id"
        >
          <MessageBubble
            :message="m"
            :is-own="m.sender?.id === currentUserId"
            @reply="emit('reply', $event)"
            @jump-to-reply="jumpTo"
          />
        </div>
      </div>
    </template>
  </div>
</template>

<style>
/* Pattern denso de fundo (ícones de odonto/estética/bem-estar).
   SVG via asset import (Vite) — variáveis setadas inline pelo template. */
.ic-thread-pattern {
  background-image: var(--ic-pattern-light);
  background-repeat: repeat;
  background-size: 600px 600px;
}
.dark .ic-thread-pattern {
  background-image: var(--ic-pattern-dark);
}
</style>
