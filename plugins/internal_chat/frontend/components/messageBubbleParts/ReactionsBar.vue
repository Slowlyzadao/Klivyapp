<script setup>
// FE-1 (auditoria 2026-05-19): extraído de MessageBubble.vue — listagem
// das reactions abaixo da bolha aparecia 2x (sticker + bolha normal).
// Display-only com 1 emit. Classes `ic-reaction-badge` e variantes vivem
// no `<style>` (não-scoped) do MessageBubble pai pra evitar duplicação.
//
// FE-16/17 + ARCH-23 (auditoria 2026-05-19): tooltips migrados pra
// `INTERNAL_CHAT.MESSAGE_BUBBLE_PARTS.REACTIONS.*` via i18n. Emoji entra
// como interpolação no `REACT_WITH_TOOLTIP`.
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';

defineProps({
  reactions: { type: Array, default: () => [] },
  // Controla alinhamento da lista. Sticker sempre `end`; bolha normal usa
  // `end` quando é própria, `start` quando é de outro.
  align: {
    type: String,
    default: 'start',
    validator: v => ['start', 'end'].includes(v),
  },
  // Margem top: sticker usa `mt-1`, bolha normal usa `mt-1.5`. Mantido
  // por prop pra preservar o spacing original exatamente.
  topSpacing: {
    type: String,
    default: 'mt-1',
    validator: v => ['mt-1', 'mt-1.5'].includes(v),
  },
});

defineEmits(['react']);
</script>

<template>
  <div
    v-if="reactions.length"
    class="flex flex-wrap gap-1"
    :class="[topSpacing, align === 'end' ? 'justify-end' : 'justify-start']"
  >
    <Tooltip
      v-for="r in reactions"
      :key="r.emoji"
      :label="
        r.by_me
          ? $t('INTERNAL_CHAT.MESSAGE_BUBBLE_PARTS.REACTIONS.REMOVE_MINE_TOOLTIP')
          : $t('INTERNAL_CHAT.MESSAGE_BUBBLE_PARTS.REACTIONS.REACT_WITH_TOOLTIP', {
              emoji: r.emoji,
            })
      "
    >
      <button
        type="button"
        class="ic-reaction-badge"
        :class="r.by_me ? 'ic-reaction-badge-mine' : ''"
        @click="$emit('react', r.emoji)"
      >
        <span>{{ r.emoji }}</span>
        <span class="ic-reaction-count">{{ r.count }}</span>
      </button>
    </Tooltip>
  </div>
</template>
