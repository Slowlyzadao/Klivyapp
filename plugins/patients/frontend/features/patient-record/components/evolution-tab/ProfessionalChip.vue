<script setup>
/**
 * ProfessionalChip — avatar redondo + nome do profissional.
 *
 * Reutilizável em qualquer lugar da aba Evolução que precise mostrar
 * "Dr. João" ao lado de algum dado clínico (cards, tabela, listas).
 *
 * Cai num avatar com inicial (estilo "JM" pra "João Mamedes") quando o
 * `avatar_url` é nulo ou falha ao carregar — preserva consistência visual.
 */
import { computed, ref } from 'vue';

const props = defineProps({
  name: { type: String, default: '' },
  avatarUrl: { type: String, default: '' },
  size: { type: String, default: 'sm', validator: v => ['xs', 'sm', 'md'].includes(v) },
});

const imgFailed = ref(false);

const initials = computed(() => {
  const parts = (props.name || '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '—';
  if (parts.length === 1) return parts[0][0].toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
});

const showImage = computed(() => !!props.avatarUrl && !imgFailed.value);
</script>

<template>
  <span class="evo-prof-chip" :class="`evo-prof-chip--${size}`">
    <span class="evo-prof-chip__avatar">
      <img
        v-if="showImage"
        :src="avatarUrl"
        :alt="name"
        class="evo-prof-chip__img"
        @error="imgFailed = true"
      />
      <span v-else class="evo-prof-chip__initials">{{ initials }}</span>
    </span>
    <span v-if="name" class="evo-prof-chip__name">{{ name }}</span>
  </span>
</template>
