<script setup>
// FE-1 (auditoria 2026-05-19): extraído de MessageBubble.vue.
// FE-16/17 + ARCH-23 (auditoria 2026-05-19): strings PT-BR migradas pra
// `INTERNAL_CHAT.MESSAGE_BUBBLE_PARTS.ACTIONS_MENU.*` via i18n.
//
// UX-fix 2026-05-20 (v4): TELEPORT pra `body` + position fixed calculada
// do `anchorEl`. Antes o menu era `<div absolute>` ancorado ao container
// `relative` do bubble — em mensagens curtas o menu transbordava por
// cima/baixo das mensagens vizinhas, e clicks nos emojis podiam parecer
// reagir à conversa "anterior" porque o user via reactions pills da
// vizinha através do menu (com a sombra) e perdia referência.
// Com Teleport + fixed, o menu vive fora do thread, não interfere com
// nenhum scroll/layout, e o click event NUNCA pode propagar pra outras
// mensagens (não é mais filho do DOM da bolha).
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';

const props = defineProps({
  reactionEmojis: { type: Array, required: true },
  reactions: { type: Array, default: () => [] },
  canReact: { type: Boolean, default: false },
  canEdit: { type: Boolean, default: false },
  canDelete: { type: Boolean, default: false },
  canConverseWithSender: { type: Boolean, default: false },
  isFavorited: { type: Boolean, default: false },
  favoritePending: { type: Boolean, default: false },
  senderName: { type: String, default: '' },
  isOwn: { type: Boolean, default: false },
  // Element DOM do botão de chevron (passed by ref do MessageBubble).
  // Usado pra calcular position fixed do menu.
  anchorEl: { type: [Object, Function], default: null },
});

defineEmits([
  'react',
  'reply',
  'reply-privately',
  'converse-with-sender',
  'toggle-favorite',
  'edit',
  'delete',
]);

const MENU_WIDTH = 208; // w-52
const MENU_MARGIN = 4;
const VIEWPORT_PAD = 8;

// Ref no div do portal — usamos pra medir a altura REAL do menu após
// renderizar (alturas mudam por: 6 emojis presentes ou não, botões
// canEdit/canDelete visíveis ou não, nome do remetente longo wrapando).
const menuRef = ref(null);

// Altura medida na última iteração. Quando ainda não renderizou (1ª frame),
// cai num default conservador. Re-medido a cada mount + a cada resize.
const measuredHeight = ref(0);

// Inicial: opacity:0 + pointer-events:none pra evitar flicker visual ANTES
// de medir o tamanho real e reposicionar. Re-render fica invisível por
// ~1 frame; depois aparece já no lugar certo.
const style = ref({
  top: '0px',
  left: '0px',
  opacity: 0,
  pointerEvents: 'none',
});

const resolveAnchor = () => {
  const raw = props.anchorEl;
  if (!raw) return null;
  // Vue passa o template ref como HTMLElement direto, ou via .value se
  // recebemos um Ref. Cobre os 2 casos.
  return raw instanceof HTMLElement ? raw : raw?.$el || raw?.value || null;
};

// Computa posição usando a altura REAL do menu (se já medido) ou uma
// estimativa conservadora pequena (em vez do 320px antigo que criava
// um gap visual gigante quando o menu flipava pra cima).
const computePosition = () => {
  const el = resolveAnchor();
  if (!el || typeof el.getBoundingClientRect !== 'function') return;
  const rect = el.getBoundingClientRect();
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  const menuH = measuredHeight.value || 200; // estimate até medir

  // ── Vertical: abaixo do chevron por padrão; flipa pra cima só se não couber
  let top = rect.bottom + MENU_MARGIN;
  if (top + menuH > vh - VIEWPORT_PAD) {
    // Tenta acima
    if (rect.top - menuH - MENU_MARGIN >= VIEWPORT_PAD) {
      top = rect.top - menuH - MENU_MARGIN;
    } else {
      // Não cabe nem em cima nem embaixo (viewport minúsculo) — escolhe
      // o lado com mais espaço e clampa.
      const spaceBelow = vh - rect.bottom;
      const spaceAbove = rect.top;
      if (spaceAbove > spaceBelow) {
        top = Math.max(VIEWPORT_PAD, rect.top - menuH - MENU_MARGIN);
      } else {
        top = Math.min(rect.bottom + MENU_MARGIN, vh - menuH - VIEWPORT_PAD);
      }
    }
  }

  // ── Horizontal: alinha right edge do menu ao right edge do chevron
  // (chevron sempre fica no canto top-right da bolha, OWN ou other).
  // Clamp lateral pra não vazar viewport.
  let left = rect.right - MENU_WIDTH;
  if (left < VIEWPORT_PAD) left = VIEWPORT_PAD;
  if (left + MENU_WIDTH > vw - VIEWPORT_PAD) {
    left = vw - MENU_WIDTH - VIEWPORT_PAD;
  }

  style.value = {
    top: `${top}px`,
    left: `${left}px`,
    opacity: 1,
    pointerEvents: 'auto',
  };
};

// Mede a altura real do menu portal e recomputa posição. Roda pós-mount
// (1ª passada) e em watcher de mudanças do conteúdo.
const measureAndPosition = async () => {
  computePosition(); // posiciona com estimativa primeiro (pode ficar invisível)
  await nextTick();
  if (menuRef.value) {
    const h = menuRef.value.getBoundingClientRect().height;
    if (h > 0 && h !== measuredHeight.value) {
      measuredHeight.value = h;
      computePosition(); // re-posiciona com altura real
    } else {
      // Mesma altura — só garante opacidade 1 (caso 1ª passada tenha
      // ficado em opacity:0 por anchor ausente momentaneamente).
      style.value = { ...style.value, opacity: 1, pointerEvents: 'auto' };
    }
  }
};

onMounted(() => {
  measureAndPosition();
  window.addEventListener('scroll', computePosition, true);
  window.addEventListener('resize', measureAndPosition);
});

onBeforeUnmount(() => {
  window.removeEventListener('scroll', computePosition, true);
  window.removeEventListener('resize', measureAndPosition);
});

watch(() => props.anchorEl, measureAndPosition);
</script>

<template>
  <Teleport to="body">
    <!-- `ic-app` re-aplicado: Teleport tira o portal do DOM do ChatShell.
         Não tem <p> aqui hoje, mas se algum dia tiver não vaza margem. -->
    <div
      ref="menuRef"
      class="ic-app ic-actions-menu-portal fixed z-[100] w-52 rounded-lg shadow-2xl bg-n-solid-1 border border-n-weak overflow-hidden"
      :style="style"
      @click.stop
      @mousedown.stop
    >
      <!-- Quick reactions row (estilo WhatsApp) — 6 emojis padrão -->
      <div
        v-if="canReact"
        class="flex items-center justify-between gap-1 px-2 py-2 border-b border-n-weak"
      >
        <Tooltip
          v-for="e in reactionEmojis"
          :key="e"
          :label="$t('INTERNAL_CHAT.MESSAGE_BUBBLE_PARTS.ACTIONS_MENU.REACT_WITH_TOOLTIP', { emoji: e })"
        >
          <button
            type="button"
            class="ic-reaction-pick"
            :class="reactions.find(r => r.emoji === e && r.by_me) ? 'ic-reaction-pick-active' : ''"
            @click.stop="$emit('react', e)"
          >
            {{ e }}
          </button>
        </Tooltip>
      </div>
      <button
        type="button"
        class="flex items-center w-full gap-2 px-3 py-2 text-xs text-start text-n-slate-12 hover:bg-n-alpha-1"
        @click.stop="$emit('reply')"
      >
        <span class="i-lucide-corner-up-left text-sm" />
        <span>{{ $t('INTERNAL_CHAT.MESSAGE_BUBBLE_PARTS.ACTIONS_MENU.REPLY') }}</span>
      </button>
      <button
        v-if="canConverseWithSender"
        type="button"
        class="flex items-center w-full gap-2 px-3 py-2 text-xs text-start text-n-slate-12 hover:bg-n-alpha-1"
        @click.stop="$emit('reply-privately')"
      >
        <span class="i-lucide-reply text-sm" />
        <span class="truncate flex-1">
          {{ $t('INTERNAL_CHAT.MESSAGE_BUBBLE_PARTS.ACTIONS_MENU.REPLY_PRIVATELY') }}
        </span>
      </button>
      <button
        v-if="canConverseWithSender"
        type="button"
        class="flex items-center w-full gap-2 px-3 py-2 text-xs text-start text-n-slate-12 hover:bg-n-alpha-1"
        @click.stop="$emit('converse-with-sender')"
      >
        <span class="i-lucide-message-circle text-sm" />
        <span class="truncate">
          {{
            $t('INTERNAL_CHAT.MESSAGE_BUBBLE_PARTS.ACTIONS_MENU.CONVERSE_WITH_SENDER', {
              name: senderName,
            })
          }}
        </span>
      </button>
      <button
        type="button"
        class="flex items-center w-full gap-2 px-3 py-2 text-xs text-start hover:bg-n-alpha-1"
        :class="isFavorited ? 'text-n-amber-11' : 'text-n-slate-12'"
        :disabled="favoritePending"
        @click.stop="$emit('toggle-favorite')"
      >
        <span :class="isFavorited ? 'i-lucide-star-off' : 'i-lucide-star'" class="text-sm" />
        <span class="flex-1">
          {{
            isFavorited
              ? $t('INTERNAL_CHAT.MESSAGE_BUBBLE_PARTS.ACTIONS_MENU.UNFAVORITE')
              : $t('INTERNAL_CHAT.MESSAGE_BUBBLE_PARTS.ACTIONS_MENU.FAVORITE')
          }}
        </span>
      </button>
      <button
        v-if="canEdit"
        type="button"
        class="flex items-center w-full gap-2 px-3 py-2 text-xs text-start text-n-slate-12 hover:bg-n-alpha-1 border-t border-n-weak"
        @click.stop="$emit('edit')"
      >
        <span class="i-lucide-pencil text-sm" />
        <span>{{ $t('INTERNAL_CHAT.MESSAGE_BUBBLE_PARTS.ACTIONS_MENU.EDIT') }}</span>
      </button>
      <button
        v-if="canDelete"
        type="button"
        class="flex items-center w-full gap-2 px-3 py-2 text-xs text-start text-n-ruby-11 hover:bg-n-ruby-3"
        :class="canEdit ? '' : 'border-t border-n-weak'"
        @click.stop="$emit('delete')"
      >
        <span class="i-lucide-trash-2 text-sm" />
        <span>{{ $t('INTERNAL_CHAT.MESSAGE_BUBBLE_PARTS.ACTIONS_MENU.DELETE') }}</span>
      </button>
    </div>
  </Teleport>
</template>
