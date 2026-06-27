<template>
  <Badge :variant="variant" :size="size">{{ label }}</Badge>
</template>

<script setup>
import { computed } from 'vue';
import Badge from './Badge.vue';

const props = defineProps({
  status:    { type: String, required: true },
  cancelled: { type: Boolean, default: false },
  size:      { type: String, default: 'md' }
});

const MAP = {
  scheduled:   { label: 'Agendada',     variant: 'primary' },
  confirmed:   { label: 'Confirmada',   variant: 'success' },
  arrived:     { label: 'Você chegou',  variant: 'success' },
  in_progress: { label: 'Em andamento', variant: 'warning' },
  completed:   { label: 'Realizada',    variant: 'neutral' },
  no_show:     { label: 'Faltou',       variant: 'danger'  },
  cancelled:   { label: 'Cancelada',    variant: 'danger'  }
};

const variant = computed(() => (props.cancelled ? MAP.cancelled.variant : (MAP[props.status]?.variant || 'neutral')));
const label   = computed(() => (props.cancelled ? MAP.cancelled.label   : (MAP[props.status]?.label   || props.status)));
</script>
