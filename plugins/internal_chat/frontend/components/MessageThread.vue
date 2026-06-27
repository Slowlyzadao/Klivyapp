<script setup>
// FE-16/17 + ARCH-23 (auditoria 2026-05-19): empty state migrado pra
// `INTERNAL_CHAT.THREAD.EMPTY`. Date dividers continuam usando
// `toLocaleDateString('pt-BR', ...)` (API nativa do navegador) — locale
// data já é localizado pelo runtime, não é string hardcoded da UI.
//
// PERF-25 (auditoria 2026-05-19): MessageThread INTENCIONALMENTE NÃO
// virtualizado neste audit. Riscos sem E2E coverage:
//   1. Date dividers entre grupos de mensagens → exigiria achatar
//      `grouped` em lista plana de tipos heterogêneos (divider | message)
//   2. `jumpTo(id)` usa `document.querySelector('[data-msg-id]')` pra
//      navegação de reply — items fora do viewport NÃO estão no DOM
//      em scroller virtualizado. Precisaria scrollToItem(idx) + retry.
//   3. `scrollToBottom()` em new message depende de scrollEl.scrollHeight
//      direto — DynamicScroller tem API própria com lifecycle diferente
//   4. Heights MUITO variáveis: texto (40px) vs sticker (200px) vs
//      anexos (até 400px+) vs reply preview embed. size-dependencies
//      precisariam cobrir todos os tipos
//   5. Reverse infinite scroll (planejado, ainda não impl) colidiria
// Impacto real só em salas com >500 msgs visíveis (raro hoje). Quando
// E2E framework (Cypress/Playwright) existir, revisitar com test coverage
// pra detectar regressão de scroll/jumpTo. RoomList + MentionsView já
// virtualizados no mesmo lote — ganho onde o risco era baixo.
import { computed, nextTick, onMounted, ref, watch } from 'vue';
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

// Auto-scroll pro final da thread. 3 fases pra cobrir conteúdo que cresce
// async (imagens, attachments, stickers que terminam de carregar depois
// do 1º render — scrollHeight aumenta e a thread "trava" no meio):
//   1. nextTick   — Vue flush, DOM básico pronto
//   2. ~80ms      — primeira leva de imagens em cache
//   3. ~300ms    — attachments/stickers que demoram pra decodificar
// Sempre usa `instant` no scrollTo (smooth deixa user perdido em conversas
// longas — pula da meio do scroll pra ponta em 600ms é desorientador).
const scrollToBottom = () => {
  const scrollNow = () => {
    if (scrollEl.value) {
      scrollEl.value.scrollTop = scrollEl.value.scrollHeight;
    }
  };
  nextTick(scrollNow);
  setTimeout(scrollNow, 80);
  setTimeout(scrollNow, 300);
};

// PERF-22 (auditoria 2026-05-18): consolida 2 watchers que observavam
// `messages.value.length` em apenas 1. Antes scrollToBottom() e o
// markRead/clearUnread rodavam em ticks separados — agora ambos no
// mesmo callback, evitando 2 re-runs do reactive tracking por msg nova.
//
// `immediate: true` garante scroll inicial quando o usuário entra direto
// numa sala via URL (sem mudança de roomId, watcher antes não disparava).
watch(() => props.roomId, () => scrollToBottom(), { immediate: true });

// Backup: força scroll on mount caso a thread já tenha mensagens em cache
// no store (1º render). Sem isso, em refresh com store warm o user caía
// no meio do scroll.
onMounted(() => scrollToBottom());

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
    scrollToBottom();
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
      {{ $t('INTERNAL_CHAT.THREAD.EMPTY') }}
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
